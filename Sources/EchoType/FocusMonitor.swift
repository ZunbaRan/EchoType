import AppKit
import ApplicationServices

/// 全局焦点监听：以短周期轮询读取"最前端应用 -> 聚焦元素"，
/// 相比 AXObserver 通知在各应用间的支持差异，轮询行为更稳定、覆盖面更广。
final class FocusMonitor {
    static let shared = FocusMonitor()

    /// 焦点进入/离开可输入区域（field 为 nil 表示当前没有可输入焦点）。
    var onFieldChanged: ((FieldContext?) -> Void)?
    /// 可输入焦点内文本发生变化。
    var onTextChanged: ((FieldContext) -> Void)?

    private var timer: Timer?
    private var currentField: FieldContext?
    private var lastValue: String = ""
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true
        poll()
        let pollTimer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(pollTimer, forMode: .common)
        timer = pollTimer
        NotificationCenter.default.addObserver(
            self, selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    @objc private func frontmostAppChanged() {
        poll()
    }

    private func poll() {
        guard isRunning, AXIsProcessTrusted() else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            loseField()
            return
        }
        // 忽略自身（设置窗口、状态窗口中获得焦点时不干扰悬浮窗）。
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement, kAXFocusedUIElementAttribute as CFString, &raw
        )
        guard result == .success, let focused = raw, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            loseField()
            return
        }
        let axElement = focused as! AXUIElement
        guard let field = FieldContext(element: axElement, appName: app.localizedName ?? "") ,
              field.isTextInput else {
            loseField()
            return
        }

        if let existing = currentField, existing.role == field.role,
           existing.frameTopLeft == field.frameTopLeft {
            // 同一元素：只在文本变化时回调。
            if field.value != lastValue {
                lastValue = field.value
                onTextChanged?(field)
            }
            currentField = field
            return
        }

        currentField = field
        lastValue = field.value
        onFieldChanged?(field)
        if field.containsCJK {
            onTextChanged?(field)
        }
    }

    private func loseField() {
        guard currentField != nil else { return }
        currentField = nil
        lastValue = ""
        onFieldChanged?(nil)
    }
}
