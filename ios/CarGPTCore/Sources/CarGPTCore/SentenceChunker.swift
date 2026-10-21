import Foundation

/// Splits streamed reply text into sentences so speech can start as soon as the
/// first sentence arrives instead of waiting for the whole reply.
public struct SentenceChunker: Sendable {
    private var buffer = ""

    public init() {}

    /// Adds newly streamed text and returns any sentences it completed.
    public mutating func append(_ text: String) -> [String] {
        buffer += text
        var sentences: [String] = []
        while let end = Self.sentenceEnd(in: buffer) {
            let sentence = buffer[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[end...])
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
        }
        return sentences
    }

    /// Returns whatever is left once the stream has ended.
    public mutating func flush() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    /// The index just past the first sentence boundary: a newline, or `.`, `!` or `?`
    /// (plus any closing quotes or brackets) followed by whitespace. A terminator at the
    /// very end of the buffer doesn't count yet, since "3." may turn out to be "3.5".
    static func sentenceEnd(in text: String) -> String.Index? {
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "\n" {
                return text.index(after: i)
            }
            if c == "." || c == "!" || c == "?" {
                var j = text.index(after: i)
                while j < text.endIndex, closers.contains(text[j]) {
                    j = text.index(after: j)
                }
                if j < text.endIndex, text[j].isWhitespace {
                    return j
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    private static let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]"]
}
