import CarGPTCore
import Foundation

enum ChatClientError: Error {
    case invalidResponse
    case http(Int)
}

/// Talks to the CarGPT backend, which holds the Anthropic API key. The app only
/// ever has its own session token.
struct ChatClient: Sendable {
    let backendURL: URL

    /// Streams the assistant's reply to the conversation so far. Ending the
    /// iteration early (or cancelling the task iterating it) cancels the request.
    func streamReply(messages: [ChatMessage], sessionToken: String) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: backendURL.appending(path: "v1/chat"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(["messages": messages])

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatClientError.invalidResponse }
                    guard http.statusCode == 200 else { throw ChatClientError.http(http.statusCode) }

                    for try await line in bytes.lines {
                        if let event = ChatEvent.parse(sseLine: line) {
                            continuation.yield(event)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
