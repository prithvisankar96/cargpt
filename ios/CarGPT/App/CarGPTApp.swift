import SwiftUI

@main
struct CarGPTApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(auth: AppServices.shared.auth, voice: AppServices.shared.voice)
        }
    }
}

/// Objects shared by the iPhone window and the CarPlay scene. The CarPlay scene
/// delegate is created by UIKit, outside SwiftUI, so it reaches these through `shared`.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let auth: AuthManager
    let voice: VoiceSession

    private init() {
        let backendURL = AppConfig.backendURL
        auth = AuthManager(backendURL: backendURL)
        voice = VoiceSession(auth: auth, client: ChatClient(backendURL: backendURL))
    }
}

enum AppConfig {
    /// Set with the BACKEND_URL build setting in project.yml.
    static let backendURL: URL = {
        guard
            let string = Bundle.main.object(forInfoDictionaryKey: "BackendURL") as? String,
            let url = URL(string: string)
        else {
            fatalError("BackendURL is missing from Info.plist; set BACKEND_URL in project.yml")
        }
        return url
    }()
}
