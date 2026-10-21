import AVFoundation

/// Activating the session stops other audio in the car (the radio, a podcast), so
/// it is turned on only while a conversation runs and turned off right after.
@MainActor
final class AudioSessionController {
    private let session = AVAudioSession.sharedInstance()

    func activate() throws {
        // Recording is allowed in CarPlay only for navigation and voice-based conversational
        // apps, and only while the voice control screen is showing.
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    func deactivate() {
        // Lets whatever was playing before pick up again.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
