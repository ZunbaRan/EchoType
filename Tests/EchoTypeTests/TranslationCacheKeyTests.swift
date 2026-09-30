import Testing
@testable import EchoType

struct TranslationCacheKeyTests {
    @Test func sameSourceAndModelGivesSameKey() {
        #expect(
            TranslationCache.cacheKey(source: "你好", model: "qwen-plus")
            == TranslationCache.cacheKey(source: "你好", model: "qwen-plus")
        )
    }

    @Test func differentModelGivesDifferentKey() {
        #expect(
            TranslationCache.cacheKey(source: "你好", model: "qwen-plus")
            != TranslationCache.cacheKey(source: "你好", model: "gpt-4o")
        )
    }

    @Test func differentSourceGivesDifferentKey() {
        #expect(
            TranslationCache.cacheKey(source: "你好", model: "qwen-plus")
            != TranslationCache.cacheKey(source: "再见", model: "qwen-plus")
        )
    }

    @Test func keyIsLowercaseHexSHA256() {
        let key = TranslationCache.cacheKey(source: "你好", model: "qwen-plus")
        #expect(key.count == 64)
        #expect(key.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
