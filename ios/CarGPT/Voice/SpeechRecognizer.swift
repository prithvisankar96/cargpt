import AVFoundation
import Speech

/// On-device speech-to-text for one utterance at a time. The utterance ends when
/// the driver pauses, so they never have to press anything to send.
@MainActor
final class SpeechRecognizer {
    enum RecognizerError: Error {
        case unavailable
    }

    /// How long the driver can pause before the utterance counts as finished.
    private let endOfSpeechPause: Duration = .milliseconds(1200)
    /// How long to wait for the driver to start talking before giving up.
    private let noSpeechTimeout: Duration = .seconds(8)

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String, Error>?
    private var transcript = ""
    private var timer: Task<Void, Never>?

    static var hasPermissions: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    /// Shows the system prompts if the user hasn't answered them yet.
    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    /// Listens until the driver stops talking and returns what they said, or ""
    /// if they never started. The audio session must already be active.
    func listen() async throws -> String {
        guard let recognizer, recognizer.isAvailable else { throw RecognizerError.unavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            // Faster, works without signal, and keeps the audio on the phone.
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        transcript = ""

        Self.feed(engine.inputNode, into: request)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            finish(with: .failure(error))
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            restartTimer(noSpeechTimeout)
            task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failed = error != nil
                Task { @MainActor in
                    self?.handle(text: text, isFinal: isFinal, failed: failed)
                }
            }
        }
    }

    /// Stops listening; a pending `listen()` throws `CancellationError`.
    func cancel() {
        finish(with: .failure(CancellationError()))
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty {
            transcript = text
            restartTimer(endOfSpeechPause)
        }
        // A recognition error usually means no speech was detected; return what we have.
        if isFinal || failed {
            finish(with: .success(transcript))
        }
    }

    private func restartTimer(_ delay: Duration) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.finish(with: .success(self.transcript))
        }
    }

    private func finish(with result: Result<String, Error>) {
        guard request != nil else { return }
        timer?.cancel()
        timer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    /// Kept nonisolated: the tap runs on a real-time audio thread, not the main actor.
    private nonisolated static func feed(_ input: AVAudioInputNode, into request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }
}
