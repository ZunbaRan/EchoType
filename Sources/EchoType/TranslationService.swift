import Foundation

enum TranslationError: LocalizedError {
    case notConfigured
    case invalidEndpoint
    case requestFailed(statusCode: Int, message: String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先在设置中配置翻译 API Key。"
        case .invalidEndpoint: return "翻译服务地址无效。"
        case .requestFailed(_, let message): return message
        case .malformedResponse: return "翻译服务返回了无法识别的结果。"
        }
    }
}

/// AI 翻译服务：OpenAI 兼容 /chat/completions 接口（移植自 EchoSub，按输入场景重写 prompt）。
final class TranslationService {

    func translate(
        text: String,
        appName: String,
        configuration: TranslationConfiguration,
        completion: @escaping (Result<TranslationResult, Error>) -> Void
    ) {
        guard !configuration.apiKey.isEmpty else {
            completion(.failure(TranslationError.notConfigured))
            return
        }
        let base = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            completion(.failure(TranslationError.invalidEndpoint))
            return
        }

        let source: [String: Any] = [
            "source_text": text,
            "app_context": appName,
            "target_language": "English",
        ]
        guard let sourceData = try? JSONSerialization.data(withJSONObject: source),
              let sourceJSON = String(data: sourceData, encoding: .utf8) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        let system = """
        You are a professional translator helping a Chinese user write English inside the app "\(appName)".
        Translate the user's Chinese input into natural, idiomatic English that fits this context.
        Decide whether the input is a single word, a short phrase, or a full sentence, and answer accordingly.
        Return only valid JSON with exactly these keys:
        {"translation":"...","alternatives":["..."],"kind":"word|phrase|sentence","phonetic":"","meaning":"","examples":[]}
        Rules:
        - translation: the single best English translation. Keep proper nouns. Never add explanations inside it.
        - alternatives: up to 2 alternative English renderings with different tone or phrasing; may be [].
        - kind: "word", "phrase", or "sentence" based on the source.
        - phonetic: IPA of the English word when kind == "word", otherwise "".
        - meaning: a brief Simplified Chinese explanation of the source word/phrase when kind != "sentence", otherwise "".
        - examples: 1-2 short English example sentences using the word/phrase when kind != "sentence", otherwise [].
        """
        let payload: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.3,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": sourceJSON],
            ],
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(.failure(TranslationError.malformedResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                    .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                completion(.failure(TranslationError.requestFailed(
                    statusCode: http.statusCode,
                    message: message ?? "翻译请求失败（\(http.statusCode)）。"
                )))
                return
            }
            guard let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data),
                  let content = envelope.choices.first?.message.content,
                  let jsonData = Self.extractJSON(from: content).data(using: .utf8),
                  let result = try? JSONDecoder().decode(TranslationResult.self, from: jsonData),
                  !result.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            completion(.success(result))
        }.resume()
    }

    func testConnection(configuration: TranslationConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
        translate(text: "你好，很高兴见到你。", appName: "EchoType", configuration: configuration) {
            completion($0.map { _ in () })
        }
    }

    private static func extractJSON(from text: String) -> String {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}") else { return text }
        return String(text[first...last])
    }
}

private struct ChatEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message
    }
    var choices: [Choice]
}
