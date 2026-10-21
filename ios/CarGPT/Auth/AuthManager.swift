import Foundation

/// Trades a Sign in with Apple identity token for a backend session token and
/// keeps it in the Keychain.
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var sessionToken: String?

    private let backendURL: URL
    private static let keychainAccount = "session-token"

    init(backendURL: URL) {
        self.backendURL = backendURL
        sessionToken = Keychain.read(account: Self.keychainAccount)
    }

    func signIn(identityToken: Data) async throws {
        var request = URLRequest(url: backendURL.appending(path: "v1/auth/apple"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["identityToken": String(decoding: identityToken, as: UTF8.self)])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ChatClientError.invalidResponse }
        guard http.statusCode == 200 else { throw ChatClientError.http(http.statusCode) }

        let token = try JSONDecoder().decode(SessionResponse.self, from: data).sessionToken
        Keychain.save(token, account: Self.keychainAccount)
        sessionToken = token
    }

    func signOut() {
        Keychain.delete(account: Self.keychainAccount)
        sessionToken = nil
    }

    private struct SessionResponse: Decodable {
        var sessionToken: String
    }
}
