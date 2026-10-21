import Foundation

/// One event from the backend's `/v1/chat` server-sent event stream.
public enum ChatEvent: Equatable, Sendable {
    case text(String)
    case done(stopReason: String?)
    case error

    /// Parses one line of the stream. Returns nil for lines that carry no event
    /// (`event:` names, comments, blank lines) and for event types this version doesn't know.
    ///
    /// Every `data:` line holds a complete JSON object with a `type` field, so the
    /// parser never needs the blank lines between events, which
    /// `URLSession.AsyncBytes.lines` drops.
    public static func parse(sseLine line: String) -> ChatEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else { return nil }

        switch payload.type {
        case "text": return payload.text.map(ChatEvent.text)
        case "done": return .done(stopReason: payload.stopReason)
        case "error": return .error
        default: return nil
        }
    }

    private struct Payload: Decodable {
        var type: String
        var text: String?
        var stopReason: String?
    }
}
