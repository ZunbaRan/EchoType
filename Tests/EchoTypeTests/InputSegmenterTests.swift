import Testing
@testable import EchoType

struct InputSegmenterTests {
    // MARK: containsCJK

    @Test func containsCJKPureASCII() {
        #expect(!InputSegmenter.containsCJK("hello"))
    }

    @Test func containsCJKMixed() {
        #expect(InputSegmenter.containsCJK("hello 世界"))
    }

    /// 平假名不在 0x4E00–0x9FFF / 0x3400–0x4DBF 内：本测试文档化"只认汉字"的既定范围。
    @Test func containsCJKHiraganaOnly() {
        #expect(!InputSegmenter.containsCJK("こんにちは"))
    }

    @Test func containsCJKEmpty() {
        #expect(!InputSegmenter.containsCJK(""))
    }

    // MARK: lastSegment

    @Test func lastSegmentEmpty() {
        #expect(InputSegmenter.lastSegment(of: "") == nil)
    }

    @Test func lastSegmentAllWhitespaceLines() {
        #expect(InputSegmenter.lastSegment(of: "   \n  \n ") == nil)
    }

    @Test func lastSegmentMultipleLines() {
        #expect(InputSegmenter.lastSegment(of: "第一行\n第二行") == "第二行")
    }

    @Test func lastSegmentTrailingWhitespaceLineFiltered() {
        #expect(InputSegmenter.lastSegment(of: "第一行\n第二行\n   ") == "第二行")
    }

    @Test func lastSegmentTrimsWhitespace() {
        #expect(InputSegmenter.lastSegment(of: "  前后有空格  ") == "前后有空格")
    }

    @Test func lastSegmentShortLineNotTruncated() {
        let line = "这是一句话。再来一句"
        #expect(InputSegmenter.lastSegment(of: line) == line)
    }

    @Test func lastSegmentLongLineTruncatedAtLastSeparator() {
        let text = String(repeating: "中", count: 170) + "。" + "最后一句"
        #expect(InputSegmenter.lastSegment(of: text) == "最后一句")
    }

    @Test func lastSegmentLongLineWithoutSeparatorReturnsWholeLine() {
        let line = String(repeating: "中", count: 170)
        #expect(InputSegmenter.lastSegment(of: line) == line)
    }

    /// 长行最后一个分隔符恰好在行尾时 tail 为空，既有行为是保持整行不变。
    @Test func lastSegmentLongLineSeparatorAtEndReturnsWholeLine() {
        let line = String(repeating: "中", count: 170) + "。"
        #expect(InputSegmenter.lastSegment(of: line) == line)
    }
}
