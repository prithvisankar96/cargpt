import Foundation
import Testing
@testable import CarGPTCore

@Suite struct ChatEventTests {
    @Test func parsesTheBackendsEventTypes() {
        #expect(ChatEvent.parse(sseLine: #"data: {"type":"text","text":"Hello"}"#) == .text("Hello"))
        #expect(ChatEvent.parse(sseLine: #"data: {"type":"done","stopReason":"end_turn"}"#) == .done(stopReason: "end_turn"))
        #expect(ChatEvent.parse(sseLine: #"data: {"type":"done","stopReason":null}"#) == .done(stopReason: nil))
        #expect(ChatEvent.parse(sseLine: #"data: {"type":"error"}"#) == .error)
    }

    @Test func ignoresLinesWithoutEvents() {
        #expect(ChatEvent.parse(sseLine: "event: text") == nil)
        #expect(ChatEvent.parse(sseLine: ": keep-alive") == nil)
        #expect(ChatEvent.parse(sseLine: "") == nil)
        #expect(ChatEvent.parse(sseLine: "data: not json") == nil)
        #expect(ChatEvent.parse(sseLine: #"data: {"type":"something_new"}"#) == nil)
    }

    @Test func encodesMessagesTheWayTheBackendExpects() throws {
        let data = try JSONEncoder().encode(ChatMessage(role: .user, content: "Hi"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(object == ["role": "user", "content": "Hi"])
    }
}
