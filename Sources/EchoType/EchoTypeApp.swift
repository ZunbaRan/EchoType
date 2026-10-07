import AppKit

@main
enum EchoTypeApplication {
    private static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        // 菜单栏常驻应用：不占用 Dock，通过屏幕右上角状态栏图标交互
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = TranslationCoordinator()
    private var settingsWindowController: SettingsWindowController?
    private var statusWindowController: StatusWindowController?
    private var statusItem: NSStatusItem?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        statusWindowController = StatusWindowController()
        settingsWindowController = SettingsWindowController()
        setupStatusItem()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .echoOpenSettings, object: nil, queue: .main) { [weak self] _ in
            self?.showSettings()
        })

        AccessibilityManager.ensure(prompt: true)
        coordinator.start()
        GlobalHotKey.register()

        statusWindowController?.showWindow(nil)
        statusWindowController?.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: "EchoType")
        item.button?.toolTip = "EchoType — 输入框旁的 AI 翻译"

        let menu = NSMenu()
        let status = NSMenuItem(title: "状态窗口", action: #selector(showStatusWindow), keyEquivalent: "")
        status.target = self
        menu.addItem(status)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettingsMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        let translate = NSMenuItem(title: "翻译当前输入（⌃⌥T）", action: #selector(translateNow), keyEquivalent: "")
        translate.target = self
        menu.addItem(translate)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 EchoType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            statusWindowController?.showWindow(nil)
            statusWindowController?.refreshPermissionStatus()
        }
        return true
    }

    @objc private func showSettingsMenu() {
        showSettings()
    }

    @objc private func showStatusWindow() {
        statusWindowController?.showWindow(nil)
        statusWindowController?.refreshPermissionStatus()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func translateNow() {
        GlobalHotKey.handler?()
    }

    private func showSettings() {
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 把「焦点监听 → 触发 → AI 翻译 → 悬浮窗展示/复制」串起来的协调器。
final class TranslationCoordinator {
    private let monitor = FocusMonitor.shared
    private let panel = SnapPanel()
    private let resultView = ResultView()
    private let trigger = TriggerController()
    private let service = TranslationService()

    private var currentField: FieldContext?
    private var currentSource: String?
    private var requestGeneration = 0

    func start() {
        // AppKit owns the content frame; text/layout must not resize the window.
        resultView.autoresizingMask = [.width, .height]
        panel.contentView = resultView
        resultView.onCopy = { [weak self] text in
            self?.copyToPasteboard(text)
        }
        monitor.onFieldChanged = { [weak self] field in
            self?.handleFieldChange(field)
        }
        monitor.onTextChanged = { [weak self] field in
            self?.trigger.textChanged(field)
        }
        trigger.onTranslate = { [weak self] text, field in
            self?.translate(text, field: field)
        }
        GlobalHotKey.handler = { [weak self] in
            guard let self, let field = self.currentField else { return }
            self.trigger.triggerNow(field)
        }

        monitor.start()

        let center = NotificationCenter.default
        center.addObserver(forName: .echoSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.panel.applySettings()
            self?.resultView.applySettings()
        }

        // 交互结束后面板归还 key 身份，输入仍属于来源应用；用全局监听处理此时的 Esc。
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func handleFieldChange(_ field: FieldContext?) {
        currentField = field
        if field == nil {
            trigger.cancel()
            // 常驻模式下不隐藏；非常驻时，用户正在与悬浮窗交互（面板为键窗口或鼠标悬停其上）也不隐藏
            if !AppSettings.shared.pinPanel && !isUserInteractingWithPanel {
                panel.orderOut(nil)
            }
        }
    }

    private var isUserInteractingWithPanel: Bool {
        guard panel.isVisible else { return false }
        return panel.inLiveResize || panel.isKeyWindow || NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
    }

    private func translate(_ text: String, field: FieldContext) {
        requestGeneration += 1
        let generation = requestGeneration
        currentSource = text

        if let cached = TranslationCache.shared.get(source: text, model: AppSettings.shared.translationModel) {
            present(cached, field: field)
            return
        }

        resultView.setLoading(text)
        panel.show(near: field)

        service.streamTranslate(
            text: text,
            appName: field.appName,
            configuration: AppSettings.shared.translationConfiguration,
            onDelta: { [weak self] partial in
                guard let self, generation == self.requestGeneration else { return }
                self.resultView.updatePartial(partial)
            },
            completion: { [weak self] result in
                guard let self, generation == self.requestGeneration else { return } // 已过期：用户继续输入
                switch result {
                case .success(let translated):
                    TranslationCache.shared.put(source: text, model: AppSettings.shared.translationModel, result: translated)
                    self.present(translated, field: field)
                case .failure(let error):
                    self.resultView.showError(error.localizedDescription)
                }
            }
        )
    }

    private func present(_ result: TranslationResult, field: FieldContext) {
        resultView.show(result)
        panel.show(near: field)
        if AppSettings.shared.autoCopyTranslation {
            copyToPasteboard(result.translation)
            resultView.showAutoCopied()
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
