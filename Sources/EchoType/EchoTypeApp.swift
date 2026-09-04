import AppKit

@main
enum EchoTypeApplication {
    private static let delegate = AppDelegate()

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let coordinator = TranslationCoordinator()
    private var settingsWindowController: SettingsWindowController?
    private var statusWindowController: StatusWindowController?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()

        statusWindowController = StatusWindowController()
        settingsWindowController = SettingsWindowController()

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

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 EchoType", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettingsMenu), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 EchoType", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = main
    }

    @objc private func showSettingsMenu() {
        showSettings()
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
        resultView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = resultView
        resultView.onCopy = { text in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
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
    }

    private func handleFieldChange(_ field: FieldContext?) {
        currentField = field
        if field == nil {
            trigger.cancel()
            panel.orderOut(nil)
        }
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

        service.translate(
            text: text,
            appName: field.appName,
            configuration: AppSettings.shared.translationConfiguration
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, generation == self.requestGeneration else { return } // 已过期：用户继续输入
                switch result {
                case .success(let translated):
                    TranslationCache.shared.put(source: text, model: AppSettings.shared.translationModel, result: translated)
                    self.present(translated, field: field)
                case .failure(let error):
                    self.resultView.showError(error.localizedDescription)
                    self.panel.resizeToFitContent()
                }
            }
        }
    }

    private func present(_ result: TranslationResult, field: FieldContext) {
        resultView.show(result)
        panel.show(near: field)
        panel.resizeToFitContent()
    }
}
