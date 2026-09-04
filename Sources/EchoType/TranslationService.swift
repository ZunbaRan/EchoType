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

/// 思考模式策略：短句翻译完全不需要思考过程（既慢又贵），支持显式开关的模型一律关闭。
enum ThinkingModePolicy {
    static func supportsExplicitThinking(model: String) -> Bool {
        let normalized = model.lowercased()
        return normalized.contains("qwen3")
            || normalized.contains("qwen-3")
            || normalized.contains("deepseek-v3")
            || normalized.contains("deepseek-v4")
            || normalized.contains("deepseek-r")
    }

    static func applyThinkingMode(to payload: inout [String: Any], model: String) {
        guard supportsExplicitThinking(model: model) else { return }
        payload["enable_thinking"] = false
        // DashScope 在思考关闭时才接受 JSON 模式，这里保持 response_format 不变。
    }
}

/// 流式输出时从部分 JSON 内容中增量提取 translation 字段，
/// 让悬浮窗在模型生成过程中就实时显示译文。
enum StreamingJSONExtractor {
    static func partialTranslation(_ content: String) -> String? {
        guard let keyRange = content.range(of: "\"translation\"") else { return nil }
        var rest = content[keyRange.upperBound...]
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        rest = rest[rest.index(after: colon)...]
        rest = rest.drop(while: { $0 == " " })
        guard rest.first == "\"" else { return nil }
        rest = rest[rest.index(after: rest.startIndex)...]

        var output = ""
        var characters = Array(rest).makeIterator()
        while let ch = characters.next() {
            if ch == "\\" {
                guard let escaped = characters.next() else { break }
                switch escaped {
                case "n": output.append("\n")
                case "t": output.append("\t")
                case "\"": output.append("\"")
                case "\\": output.append("\\")
                case "/": output.append("/")
                case "u": break // 英文译文中极少出现 \uXXXX 转义，流式阶段忽略
                default: output.append(escaped)
                }
            } else if ch == "\"" {
                return output // 闭合：完整译文
            } else {
                output.append(ch)
            }
        }
        return output // 未闭合：返回已有部分
    }
}

/// AI 翻译服务：OpenAI 兼容 /chat/completions 接口（移植自 EchoSub，按输入场景重写 prompt）。
final class TranslationService {

    private func makeRequest(
        text: String,
        appName: String,
        configuration: TranslationConfiguration,
        stream: Bool
    ) throws -> URLRequest {
        guard !configuration.apiKey.isEmpty else { throw TranslationError.notConfigured }
        let base = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw TranslationError.invalidEndpoint
        }

        let source: [String: Any] = [
            "source_text": text,
            "app_context": appName,
            "target_language": "English",
        ]
        guard let sourceData = try? JSONSerialization.data(withJSONObject: source),
              let sourceJSON = String(data: sourceData, encoding: .utf8) else {
            throw TranslationError.malformedResponse
        }

        let system = """
        You are a professional translator helping a Chinese user write English inside the app "\(appName)".
        Translate the user's Chinese input into natural, idiomatic English that fits this context.
        Return only valid JSON with a single key:
        {"translation":"..."}
        - translation: the natural, idiomatic English translation. Keep proper nouns. Never add explanations, notes, or extra keys.
        """
        var payload: [String: Any] = [
            "model": configuration.model,
            "temperature": 0.3,
            "stream": stream,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": sourceJSON],
            ],
        ]
        ThinkingModePolicy.applyThinkingMode(to: &payload, model: configuration.model)
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw TranslationError.malformedResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 60
        return request
    }

    /// 流式翻译：译文随生成实时回调 onDelta（主线程），结束后返回完整结果。
    func streamTranslate(
        text: String,
        appName: String,
        configuration: TranslationConfiguration,
        onDelta: @escaping (String) -> Void,
        completion: @escaping (Result<TranslationResult, Error>) -> Void
    ) {
        let request: URLRequest
        do {
            request = try makeRequest(text: text, appName: appName, configuration: configuration, stream: true)
        } catch {
            completion(.failure(error))
            return
        }

        Task {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw TranslationError.malformedResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    var bodyData = Data()
                    for try await byte in bytes { bodyData.append(byte) }
                    let message = (try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
                        .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
                    throw TranslationError.requestFailed(
                        statusCode: http.statusCode,
                        message: message ?? "翻译请求失败（\(http.statusCode)）。"
                    )
                }

                var content = ""
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                          let delta = chunk.choices.first?.delta.content else { continue }
                    content += delta
                    if let partial = StreamingJSONExtractor.partialTranslation(content) {
                        DispatchQueue.main.async { onDelta(partial) }
                    }
                }

                let jsonData = Self.extractJSON(from: content).data(using: .utf8) ?? Data()
                guard let result = try? JSONDecoder().decode(TranslationResult.self, from: jsonData),
                      !result.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TranslationError.malformedResponse
                }
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// 非流式（用于设置页测试连接）。
    func testConnection(configuration: TranslationConfiguration, completion: @escaping (Result<Void, Error>) -> Void) {
        let request: URLRequest
        do {
            request = try makeRequest(text: "你好，很高兴见到你。", appName: "EchoType", configuration: configuration, stream: false)
        } catch {
            completion(.failure(error))
            return
        }

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
                  envelope.choices.first?.message.content.isEmpty == false else {
                completion(.failure(TranslationError.malformedResponse))
                return
            }
            completion(.success(()))
        }.resume()
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

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { var content: String? }
        var delta: Delta
    }
    var choices: [Choice]
}
