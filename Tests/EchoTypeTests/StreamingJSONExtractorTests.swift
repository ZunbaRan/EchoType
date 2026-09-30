import Testing
@testable import EchoType

struct StreamingJSONExtractorTests {
    @Test func noTranslationKeyReturnsNil() {
        #expect(StreamingJSONExtractor.partialTranslation("{\"foo\":\"bar\"}") == nil)
    }

    @Test func keyPresentButNoColonValueReturnsNil() {
        #expect(StreamingJSONExtractor.partialTranslation("{\"translation\":") == nil)
    }

    @Test func colonPresentButNoOpeningQuoteReturnsNil() {
        #expect(StreamingJSONExtractor.partialTranslation("{\"translation\": ") == nil)
    }

    @Test func unclosedStringReturnsPartial() {
        #expect(
            StreamingJSONExtractor.partialTranslation("{\"translation\":\"Hello wor")
            == "Hello wor"
        )
    }

    @Test func closedStringReturnsCompleteValue() {
        #expect(
            StreamingJSONExtractor.partialTranslation("{\"translation\":\"Hello world\"}")
            == "Hello world"
        )
    }

    @Test func multipleSpacesAfterColon() {
        #expect(
            StreamingJSONExtractor.partialTranslation("{\"translation\":   \"Hi\"}")
            == "Hi"
        )
    }

    @Test func escapedDoubleQuote() {
        #expect(
            StreamingJSONExtractor.partialTranslation("{\"translation\":\"He said \\\"hi\\\"\"}")
            == "He said \"hi\""
        )
    }

    @Test func escapedNewline() {
        #expect(
            StreamingJSONExtractor.partialTranslation("{\"translation\":\"a\\nb\"}")
            == "a\nb"
        )
    }

    @Test func escapedBackslash() {
        #expect(
            StreamingJSONExtractor.partialTranslation("{\"translation\":\"a\\\\b\"}")
            == "a\\b"
        )
    }
}
