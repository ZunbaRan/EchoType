import Foundation

struct TranslationConfiguration: Equatable {
    var baseURL: String
    var model: String
    var apiKey: String
}

/// 一次 AI 翻译的结果。讲解相关字段已停用（prompt 只返回 translation），
/// 保留字段以兼容缓存中的旧数据。
struct TranslationResult: Codable, Equatable {
    var translation: String
    var alternatives: [String]
    var kind: String
    var phonetic: String
    var meaning: String
    var examples: [String]

    private enum CodingKeys: String, CodingKey {
        case translation, alternatives, kind, phonetic, meaning, examples
    }

    init(translation: String, alternatives: [String] = [], kind: String = "", phonetic: String = "", meaning: String = "", examples: [String] = []) {
        self.translation = translation
        self.alternatives = alternatives
        self.kind = kind
        self.phonetic = phonetic
        self.meaning = meaning
        self.examples = examples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        alternatives = try container.decodeIfPresent([String].self, forKey: .alternatives) ?? []
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        examples = try container.decodeIfPresent([String].self, forKey: .examples) ?? []
    }
}

extension TranslationResult {
    init(translation: String) {
        self.init(translation: translation, alternatives: [], kind: "", phonetic: "", meaning: "", examples: [])
    }
}
