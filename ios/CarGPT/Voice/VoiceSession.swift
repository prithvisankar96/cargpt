import AVFoundation
import CarGPTCore
import Combine

/// Runs a hands-free conversation: listen, send the transcript to the backend,
/// speak the reply sentence by sentence, then listen again. It ends when the
/// driver says nothing, taps Stop, or audio is interrupted (a call, Siri).
///
/// The audio session is only active while a conversation runs, so the car's
/// radio resumes as soon as it ends.
@MainActor
final class VoiceSession: ObservableObject {
    enum Phase: Equatable {
        case idle, listening, thinking, speaking
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var messages: [ChatMessage] = []

    var isActive: Bool { loop != nil }

    private let auth: AuthManager
    private let client: ChatClient
    private let audio = AudioSessionController()
    private let recognizer = SpeechRecognizer()
    private let speaker = Speaker()
    private var loop: Task<Void, Never>?
    private var interrupted = false
    private var interruptionObserver: NSObjectProtocol?

    /// Odd, so the history sent (which ends with the driver's turn) also starts with one.
    private let maxHistory = 41

    init(auth: AuthManager, client: ChatClient) {
        self.auth = auth
        self.client = client
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                AVAudioSession.InterruptionType(rawValue: raw) == .began
            else { return }
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// Starts a conversation, or does nothing if one is running. Pass
    /// `promptForPermissions: false` from CarPlay, where the driver can't answer a prompt.
    func start(promptForPermissions: Bool) {
        guard loop == nil else { return }
        loop = Task { await run(promptForPermissions: promptForPermissions) }
    }

    /// Ends the conversation immediately and releases the audio session.
    func stop() {
        guard let loop else { return }
        loop.cancel()
        self.loop = nil
        recognizer.cancel()
        speaker.stop()
        audio.deactivate()
        // Drop a question that never got its answer, so the history keeps alternating.
        if messages.last?.role == .user {
            messages.removeLast()
        }
        phase = .idle
    }

    /// Cuts off the reply being spoken and goes straight back to listening.
    func interrupt() {
        guard phase == .speaking else { return }
        interrupted = true
        speaker.stop()
    }

    func newConversation() {
        stop()
        messages = []
    }

    // MARK: - Conversation loop

    private func run(promptForPermissions: Bool) async {
        do {
            try audio.activate()
            let permitted = promptForPermissions
                ? await SpeechRecognizer.requestPermissions()
                : SpeechRecognizer.hasPermissions
            guard permitted else { throw VoiceError.permissionsMissing }
            guard auth.sessionToken != nil else { throw VoiceError.signedOut }

            while !Task.isCancelled {
                phase = .listening
                let heard = try await recognizer.listen()
                // Silence means the driver is done; end the conversation and free the audio.
                if heard.isEmpty || Task.isCancelled { break }

                messages.append(ChatMessage(role: .user, content: heard))
                phase = .thinking
                try await respond()
            }
        } catch {
            // stop() has already cleaned up after a cancellation.
            if Task.isCancelled { return }
            if messages.last?.role == .user {
                messages.removeLast()
            }
            if case ChatClientError.http(401) = error {
                auth.signOut()
            }
            await say(VoiceError.spokenMessage(for: error))
        }
        guard !Task.isCancelled else { return }
        audio.deactivate()
        phase = .idle
        loop = nil
    }

    private func respond() async throws {
        guard let token = auth.sessionToken else { throw VoiceError.signedOut }

        var chunker = SentenceChunker()
        var reply = ""
        var refused = false
        interrupted = false

        let history = Array(messages.suffix(maxHistory))
        for try await event in client.streamReply(messages: history, sessionToken: token) {
            if interrupted { break }
            switch event {
            case .text(let text):
                reply += text
                chunker.append(text).forEach(speak)
            case .done(let stopReason):
                refused = stopReason == "refusal"
            case .error:
                throw VoiceError.server
            }
        }
        // A cancelled stream just ends, so check before speaking anything that's left.
        try Task.checkCancellation()

        if refused {
            // A declined reply may have been cut off partway. Don't keep it, or the question, in the history.
            speaker.stop()
            messages.removeLast()
            await say("Sorry, I can't help with that one.")
            return
        }

        if !interrupted, let rest = chunker.flush() {
            speak(rest)
        }
        await speaker.waitUntilDone()
        try Task.checkCancellation()

        if reply.isEmpty {
            messages.removeLast()
        } else {
            // Keep a reply that was interrupted too: the model said it, and the driver heard part of it.
            messages.append(ChatMessage(role: .assistant, content: reply))
        }
    }

    private func speak(_ sentence: String) {
        phase = .speaking
        speaker.enqueue(sentence)
    }

    private func say(_ text: String) async {
        speak(text)
        await speaker.waitUntilDone()
    }
}

enum VoiceError: Error {
    case permissionsMissing
    case signedOut
    case server

    static func spokenMessage(for error: Error) -> String {
        switch error {
        case VoiceError.permissionsMissing:
            "I need microphone and speech recognition access. When you're parked, open CarGPT on your iPhone to allow it."
        case VoiceError.signedOut, ChatClientError.http(401):
            "Please sign in. When you're parked, open CarGPT on your iPhone."
        case ChatClientError.http(429):
            "You've reached the request limit. Try again in a minute."
        default:
            "Sorry, I couldn't reach the server. Try again in a moment."
        }
    }
}
