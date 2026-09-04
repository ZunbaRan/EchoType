import AppKit

/// 主窗口：权限状态 + 使用说明，也是未授权时的引导入口。
final class StatusWindowController: NSWindowController, NSWindowDelegate {
    private let permissionLabel = EchoStyle.label("", size: 12.5, weight: .medium)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EchoType"
        window.backgroundColor = EchoStyle.windowBackground
        window.setFrameAutosaveName("EchoType.status")
        super.init(window: window)
        window.delegate = self
        buildInterface()
    }

    required init?(coder: NSCoder) { nil }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true

        let title = EchoStyle.label("EchoType", size: 22, weight: .bold)
        let subtitle = EchoStyle.label("在任意输入框旁实时给出英文翻译", size: 12, color: EchoStyle.textSecondary)

        permissionLabel.stringValue = Self.permissionText()

        let grant = EchoStyle.button("前往授权", target: self, action: #selector(grantPermission))
        let settings = EchoStyle.button("打开设置", symbol: "gearshape", target: self, action: #selector(openSettings))
        let buttons = NSStackView(views: [grant, settings])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let usage = EchoStyle.label(
            "把焦点放到任意应用的输入框，用中文输入；停顿后悬浮窗会自动贴在输入框旁显示英文翻译、备选译法与词/短语解释。\n⌃⌥T 立即翻译 · Esc 关闭悬浮窗 · 点击「复制英文」只复制英文译文。",
            size: 11, color: EchoStyle.textTertiary, lines: 5
        )

        let stack = NSStackView(views: [title, subtitle, permissionLabel, buttons, usage])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor),
        ])
    }

    private static func permissionText() -> String {
        AccessibilityManager.isTrusted ? "● 辅助功能权限已授权" : "○ 未授权：需要辅助功能权限才能读取输入框"
    }

    private static func permissionColor() -> NSColor {
        AccessibilityManager.isTrusted ? .systemGreen : .systemOrange
    }

    func refreshPermissionStatus() {
        permissionLabel.stringValue = Self.permissionText()
        permissionLabel.textColor = Self.permissionColor()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshPermissionStatus()
    }

    @objc private func grantPermission() {
        if !AccessibilityManager.isTrusted {
            AccessibilityManager.ensure(prompt: true)
        }
        AccessibilityManager.openSystemSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.refreshPermissionStatus()
        }
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .echoOpenSettings, object: nil)
    }
}

extension Notification.Name {
    static let echoOpenSettings = Notification.Name("EchoType.openSettings")
}
