import AVFoundation

/// Text-to-speech using Apple's on-device voices. Sentences are queued as they
/// stream in, so the first one plays while the rest of the reply is still arriving.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = Speaker.bestVoice()
    private var pending: Set<ObjectIdentifier> = []
    private var drained: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func enqueue(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        pending.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    /// Returns once everything queued has been spoken, or `stop()` is called.
    func waitUntilDone() async {
        guard !pending.isEmpty else { return }
        await withCheckedContinuation { drained = $0 }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pending.removeAll()
        resumeIfDrained()
    }

    private func finished(_ id: ObjectIdentifier) {
        pending.remove(id)
        resumeIfDrained()
    }

    private func resumeIfDrained() {
        guard pending.isEmpty else { return }
        drained?.resume()
        drained = nil
    }

    /// The highest-quality installed voice for the user's language. Enhanced and premium
    /// voices are free downloads in Settings > Accessibility > Spoken Content > Voices.
    private nonisolated static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }
}
