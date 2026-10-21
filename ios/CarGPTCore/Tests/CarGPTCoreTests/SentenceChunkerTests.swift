import Testing
@testable import CarGPTCore

@Suite struct SentenceChunkerTests {
    @Test func emitsSentencesAsTheyComplete() {
        var chunker = SentenceChunker()
        #expect(chunker.append("It's about two hundred") == [])
        #expect(chunker.append(" thousand miles. The light takes") == ["It's about two hundred thousand miles."])
        #expect(chunker.append(" just over a second! Neat?") == ["The light takes just over a second!"])
        #expect(chunker.flush() == "Neat?")
        #expect(chunker.flush() == nil)
    }

    @Test func waitsWhenAPeriodMightBeADecimalPoint() {
        var chunker = SentenceChunker()
        #expect(chunker.append("It's 3.") == [])
        #expect(chunker.append("5 miles away. Turn") == ["It's 3.5 miles away."])
    }

    @Test func keepsClosingQuotesWithTheirSentence() {
        var chunker = SentenceChunker()
        #expect(chunker.append("She said \"go left.\" Then") == ["She said \"go left.\""])
        #expect(chunker.append(" stop (really.) Ok") == ["Then stop (really.)"])
    }

    @Test func treatsEllipsisAsOneBoundary() {
        var chunker = SentenceChunker()
        #expect(chunker.append("Well... maybe. ") == ["Well...", "maybe."])
    }

    @Test func splitsOnNewlinesAndSkipsBlankLines() {
        var chunker = SentenceChunker()
        #expect(chunker.append("First line\n\nSecond line\n") == ["First line", "Second line"])
    }
}
