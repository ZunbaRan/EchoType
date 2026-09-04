import Foundation

enum EchoStorage {
    static let directoryURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("EchoType", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
}

extension JSONEncoder {
    static let echo: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let echo: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// 按产品设计以明文保存 API Key（credentials.json，权限 600，不入 Git）。
final class PlaintextCredentialStore {
    static let shared = PlaintextCredentialStore(
        fileURL: EchoStorage.directoryURL.appendingPathComponent("credentials.json")
    )

    private struct Credentials: Codable {
        var translationAPIKey: String = ""

        private enum CodingKeys: String, CodingKey { case translationAPIKey }

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            translationAPIKey = try container.decodeIfPresent(String.self, forKey: .translationAPIKey) ?? ""
        }
    }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadTranslationAPIKey() -> String {
        load().translationAPIKey
    }

    func saveTranslationAPIKey(_ value: String) {
        var credentials = load()
        credentials.translationAPIKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        save(credentials)
    }

    private func load() -> Credentials {
        guard let data = try? Data(contentsOf: fileURL),
              let credentials = try? JSONDecoder.echo.decode(Credentials.self, from: data) else {
            return Credentials()
        }
        return credentials
    }

    private func save(_ credentials: Credentials) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.echo.encode(credentials) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

enum SnapEdge: Int {
    case below = 0
    case above = 1
}

extension Notification.Name {
    static let echoSettingsChanged = Notification.Name("EchoType.settingsChanged")
}

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // MARK: 翻译服务

    var translationBaseURL: String {
        get { defaults.string(forKey: "translationBaseURL") ?? "https://dashscope.aliyuncs.com/compatible-mode/v1" }
        set { update(newValue, key: "translationBaseURL", current: translationBaseURL) }
    }

    var translationModel: String {
        get { defaults.string(forKey: "translationModel") ?? "qwen3.7-plus" }
        set { update(newValue, key: "translationModel", current: translationModel) }
    }

    var translationConfiguration: TranslationConfiguration {
        TranslationConfiguration(
            baseURL: translationBaseURL,
            model: translationModel,
            apiKey: PlaintextCredentialStore.shared.loadTranslationAPIKey()
        )
    }

    // MARK: 触发方式

    var autoTranslate: Bool {
        get { defaults.object(forKey: "autoTranslate") == nil ? true : defaults.bool(forKey: "autoTranslate") }
        set { update(newValue, key: "autoTranslate", current: autoTranslate) }
    }

    var debounceInterval: Double {
        get {
            let value = defaults.object(forKey: "debounceInterval") == nil ? 1.2 : defaults.double(forKey: "debounceInterval")
            return min(3, max(0.3, value))
        }
        set { update(min(3, max(0.3, newValue)), key: "debounceInterval", current: debounceInterval) }
    }

    // MARK: 悬浮窗外观

    var panelFontSize: Double {
        get {
            let value = defaults.object(forKey: "panelFontSize") == nil ? 15 : defaults.double(forKey: "panelFontSize")
            return min(28, max(11, value))
        }
        set { update(min(28, max(11, newValue)), key: "panelFontSize", current: panelFontSize) }
    }

    var backgroundOpacity: Double {
        get {
            let value = defaults.object(forKey: "backgroundOpacity") == nil ? 0.94 : defaults.double(forKey: "backgroundOpacity")
            return min(1, max(0, value))
        }
        set { update(min(1, max(0, newValue)), key: "backgroundOpacity", current: backgroundOpacity) }
    }

    var snapEdge: SnapEdge {
        get {
            guard defaults.object(forKey: "snapEdge") != nil else { return .below }
            return SnapEdge(rawValue: defaults.integer(forKey: "snapEdge")) ?? .below
        }
        set { update(newValue.rawValue, key: "snapEdge", current: snapEdge.rawValue) }
    }

    var showsOnAllSpaces: Bool {
        get { defaults.object(forKey: "showsOnAllSpaces") == nil ? true : defaults.bool(forKey: "showsOnAllSpaces") }
        set { update(newValue, key: "showsOnAllSpaces", current: showsOnAllSpaces) }
    }

    /// 常驻：显示后不随焦点离开输入框而自动隐藏（Esc 或手动关闭）。
    var pinPanel: Bool {
        get { defaults.object(forKey: "pinPanel") == nil ? true : defaults.bool(forKey: "pinPanel") }
        set { update(newValue, key: "pinPanel", current: pinPanel) }
    }

    func reset() {
        ["translationBaseURL", "translationModel", "autoTranslate", "debounceInterval",
         "panelFontSize", "backgroundOpacity", "snapEdge", "showsOnAllSpaces", "pinPanel"].forEach(defaults.removeObject(forKey:))
        changed()
    }

    private func update<T: Equatable>(_ value: T, key: String, current: T) {
        guard value != current else { return }
        defaults.set(value, forKey: key)
        changed()
    }

    private func changed() {
        NotificationCenter.default.post(name: .echoSettingsChanged, object: nil)
    }
}
