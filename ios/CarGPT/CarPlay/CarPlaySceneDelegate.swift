import CarPlay
import Combine

/// The CarPlay screen. Apple's voice-based conversational category allows voice
/// only in the car: no reply text or images, just the voice control screen while
/// a conversation is running, plus a small root screen to start one.
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPInterfaceControllerDelegate {
    private var interfaceController: CPInterfaceController?
    private var voiceTemplate: CPVoiceControlTemplate?
    private var phaseSubscription: AnyCancellable?

    private var voice: VoiceSession { AppServices.shared.voice }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        interfaceController.delegate = self
        interfaceController.setRootTemplate(makeRootTemplate(), animated: false, completion: nil)

        phaseSubscription = voice.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.show(phase) }

        // The category requires voice to be the primary mode on launch, so start listening right away.
        voice.start(promptForPermissions: false)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        // Don't carry on talking through the phone's speaker once the car is gone.
        voice.stop()
        phaseSubscription = nil
        voiceTemplate = nil
        self.interfaceController = nil
    }

    // MARK: - CPInterfaceControllerDelegate

    func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
        // If the system closes the voice screen, end the conversation too: recording is
        // only allowed while the voice control screen is showing.
        if aTemplate === voiceTemplate {
            voiceTemplate = nil
            voice.stop()
        }
    }

    // MARK: - Templates

    private func show(_ phase: VoiceSession.Phase) {
        guard let interfaceController else { return }

        guard phase != .idle else {
            if voiceTemplate != nil {
                voiceTemplate = nil
                interfaceController.dismissTemplate(animated: true, completion: nil)
            }
            return
        }

        if voiceTemplate == nil {
            let template = makeVoiceTemplate()
            voiceTemplate = template
            interfaceController.presentTemplate(template, animated: true, completion: nil)
        }
        voiceTemplate?.activateVoiceControlState(withIdentifier: phase.stateIdentifier)
    }

    private func makeRootTemplate() -> CPTemplate {
        let talk = CPGridButton(titleVariants: ["Talk"], image: symbol("mic.fill")) { [weak self] _ in
            self?.voice.start(promptForPermissions: false)
        }
        let newChat = CPGridButton(titleVariants: ["New chat"], image: symbol("plus.bubble")) { [weak self] _ in
            self?.voice.newConversation()
            self?.voice.start(promptForPermissions: false)
        }
        return CPGridTemplate(title: "CarGPT", gridButtons: [talk, newChat])
    }

    private func makeVoiceTemplate() -> CPVoiceControlTemplate {
        let states = VoiceSession.Phase.active.map { phase in
            let state = CPVoiceControlState(
                identifier: phase.stateIdentifier,
                titleVariants: [phase.carPlayTitle],
                image: symbol(phase.carPlaySymbol, pointSize: 120),
                repeats: true
            )
            state.actionButtons = actionButtons(for: phase)
            return state
        }
        return CPVoiceControlTemplate(voiceControlStates: states)
    }

    private func actionButtons(for phase: VoiceSession.Phase) -> [CPButton] {
        let stop = CPButton(image: symbol("xmark")) { [weak self] _ in
            self?.voice.stop()
        }
        stop.title = "Stop"
        guard phase == .speaking else { return [stop] }

        let interrupt = CPButton(image: symbol("mic.fill")) { [weak self] _ in
            self?.voice.interrupt()
        }
        interrupt.title = "Interrupt"
        return [interrupt, stop]
    }

    private func symbol(_ name: String, pointSize: CGFloat = 40) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize)
        return UIImage(systemName: name, withConfiguration: configuration) ?? UIImage()
    }
}

private extension VoiceSession.Phase {
    static let active: [VoiceSession.Phase] = [.listening, .thinking, .speaking]

    var stateIdentifier: String { "\(self)" }

    var carPlayTitle: String {
        switch self {
        case .idle: ""
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking…"
        }
    }

    var carPlaySymbol: String {
        switch self {
        case .idle: "mic"
        case .listening: "waveform"
        case .thinking: "ellipsis"
        case .speaking: "speaker.wave.2.fill"
        }
    }
}
