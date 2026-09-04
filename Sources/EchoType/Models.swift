import Foundation

struct TranslationConfiguration: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

/// 一次 AI 翻译的完整结果：译文、备选、以及词/短语级的释义信息。
struct TranslationResult: Codable, Equatable {
    var translation: String
    var alternatives: [String]
    var kind: String
    var phonetic: String
    var meaning: String
    var examples: [String]

    var kindDescription: String {
        switch kind {
        case "word": return "单词"
        case "phrase": return "短语"
        case "sentence": return "句子"
        default: return kind.isEmpty ? "句子" : kind
        }
    }
}

extension TranslationResult {
    init(translation: String) {
        self.init(translation: translation, alternatives: [], kind: "sentence", phonetic: "", meaning: "", examples: [])
    }
}
