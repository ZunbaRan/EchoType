import Foundation
import CryptoKit

/// 本地翻译缓存：相同原文 + 相同模型不重复请求，避免计费与延迟。
final class TranslationCache {
    static let shared = TranslationCache()

    struct Entry: Codable {
        var source: String
        var model: String
        var result: TranslationResult
        var createdAt: Date
    }

    private let fileURL: URL
    private var entries: [String: Entry] = [:]
    private let maximumEntries = 800

    private init() {
        fileURL = EchoStorage.directoryURL.appendingPathComponent("translation-cache.json")
        load()
    }

    private func key(for source: String, model: String) -> String {
        let digest = SHA256.hash(data: Data("\(model)\n\(source)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func get(source: String, model: String) -> TranslationResult? {
        entries[key(for: source, model: model)]?.result
    }

    func put(source: String, model: String, result: TranslationResult) {
        entries[key(for: source, model: model)] = Entry(source: source, model: model, result: result, createdAt: Date())
        prune()
        save()
    }

    var count: Int { entries.count }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func prune() {
        guard entries.count > maximumEntries else { return }
        let sorted = entries.sorted { $0.value.createdAt < $1.value.createdAt }
        let overflow = sorted.prefix(entries.count - maximumEntries)
        overflow.forEach { entries.removeValue(forKey: $0.key) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder.echo.decode([String: Entry].self, from: data) else { return }
        entries = stored
    }

    private func save() {
        guard let data = try? JSONEncoder.echo.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
