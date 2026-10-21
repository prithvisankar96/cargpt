import AuthenticationServices
import CarGPTCore
import SwiftUI

/// The iPhone app. Unlike the CarPlay screen, it can show text, so it holds
/// sign-in, the transcript, and permission prompts.
struct ContentView: View {
    @ObservedObject var auth: AuthManager
    @ObservedObject var voice: VoiceSession

    var body: some View {
        if auth.sessionToken == nil {
            SignInView(auth: auth)
        } else {
            ConversationView(auth: auth, voice: voice)
        }
    }
}

private struct SignInView: View {
    let auth: AuthManager
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "car.fill")
                .font(.system(size: 64))
            Text("CarGPT")
                .font(.largeTitle.bold())
            Text("A voice assistant for the road. Sign in once here, then talk to it from CarPlay.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                // The backend only needs Apple's stable user ID, not a name or email.
                request.requestedScopes = []
            } onCompletion: { result in
                handle(result)
            }
            .frame(height: 50)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityToken = credential.identityToken
            else {
                errorMessage = "Sign in with Apple didn't return an identity token."
                return
            }
            Task {
                do {
                    try await auth.signIn(identityToken: identityToken)
                } catch {
                    errorMessage = "Couldn't sign in: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ConversationView: View {
    let auth: AuthManager
    @ObservedObject var voice: VoiceSession

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(voice.messages.enumerated()), id: \.offset) { _, message in
                        MessageBubble(message: message)
                    }
                }
                .padding()
            }
            .overlay {
                if voice.messages.isEmpty {
                    ContentUnavailableView(
                        "Tap to talk",
                        systemImage: "waveform",
                        description: Text("In the car, open CarGPT on the CarPlay screen and it starts listening.")
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                TalkButton(phase: voice.phase) {
                    if voice.isActive {
                        voice.stop()
                    } else {
                        voice.start(promptForPermissions: true)
                    }
                }
                .padding()
            }
            .navigationTitle("CarGPT")
            .toolbar {
                Menu {
                    Button("New conversation", systemImage: "plus.bubble") {
                        voice.newConversation()
                    }
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        voice.stop()
                        auth.signOut()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .task {
                // Ask here, on the phone. Permission prompts can't be answered from the car.
                _ = await SpeechRecognizer.requestPermissions()
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .padding(12)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

private struct TalkButton: View {
    let phase: VoiceSession.Phase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
        .clipShape(Capsule())
    }

    private var title: String {
        switch phase {
        case .idle: "Talk"
        case .listening: "Listening… tap to stop"
        case .thinking: "Thinking… tap to stop"
        case .speaking: "Speaking… tap to stop"
        }
    }

    private var symbol: String {
        phase == .idle ? "mic.fill" : "stop.fill"
    }
}
