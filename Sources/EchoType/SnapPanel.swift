import AppKit

/// 非激活式悬浮面板：点击与拖动都不会夺走当前输入应用的焦点。
final class SnapPanel: NSPanel {
    static let preferredWidth: CGFloat = 400

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 180),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 全局强制 darkAqua 是为设置/状态窗口的深色设计；
        // 玻璃悬浮窗改用浅色外观，Liquid Glass 才呈亮色，语义文字色随 vibrancy 适配背景。
        if ResultView.usesLiquidGlass {
            appearance = NSAppearance(named: .aqua)
        }
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        worksWithSpaces(AppSettings.shared.showsOnAllSpaces)
        observeUserDrags()
    }

    private func worksWithSpaces(_ allSpaces: Bool) {
        collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
    }

    // 永不成为 key window：液态渲染由 _hasActiveAppearance 覆盖提供（见下），
    // 不需要真实窗口身份；面板不抢前台应用的键盘输入。
    override var canBecomeKey: Bool { false }

    /// 液态玻璃把「活跃渲染」挂在窗口的私有查询 _hasActiveAppearance 上，
    /// 而不是公开的 isKeyWindow/isMainWindow（实验证明改后者无效）。
    /// 这里覆盖为 true：玻璃在非 key 悬浮窗里也呈现液态——
    /// 这只是渲染提示，不改变窗口真实状态，所以不会接管键盘。
    /// 若未来 macOS 移除/改名该方法，此覆盖自然失效、回退磨砂态，不崩溃。
    @objc(_hasActiveAppearance)
    private func echotype_hasActiveAppearance() -> Bool {
        if ResultView.usesLiquidGlass { return true }
        return Self.realActiveAppearance(self, NSSelectorFromString("_hasActiveAppearance"))
    }

    /// 同一机制的忽略键盘焦点变体（菜单/检查器等路径会查它），一并覆盖。
    @objc(_hasActiveAppearanceIgnoringKeyFocus)
    private func echotype_hasActiveAppearanceIgnoringKeyFocus() -> Bool {
        if ResultView.usesLiquidGlass { return true }
        return Self.realActiveAppearance(self, NSSelectorFromString("_hasActiveAppearanceIgnoringKeyFocus"))
    }

    /// 调用 NSWindow 上同名私有方法的真实实现（非玻璃路径保持原行为）。
    private static func realActiveAppearance(_ obj: AnyObject, _ sel: Selector) -> Bool {
        typealias Fn = @convention(c) (AnyObject, Selector) -> Bool
        guard let imp = class_getMethodImplementation(NSWindow.self, sel) else { return false }
        return unsafeBitCast(imp, to: Fn.self)(obj, sel)
    }

    // MARK: 用户手动拖拽后的位置记忆

    private var userDragged = false
    private var isProgrammaticMove = false

    /// 用户拖拽过之后，翻译时保持用户放置的位置，不再自动贴边；关闭悬浮窗后重置。
    private func observeUserDrags() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidMoveUser),
            name: NSWindow.didMoveNotification, object: self
        )
    }

    @objc private func windowDidMoveUser() {
        guard !isProgrammaticMove else { return }
        userDragged = true
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        userDragged = false // 关闭后重新唤出时恢复自动贴边
    }

    // 面板 canBecomeKey=false，永远不进响应链：Esc 由
    /// EchoTypeApp 的全局键盘监听关闭（TranslationCoordinator.installGlobalEscapeMonitor）。

    func applySettings() {
        worksWithSpaces(AppSettings.shared.showsOnAllSpaces)
    }

    /// 贴到指定输入框旁边显示；用户手动拖拽过则保持其放置的位置。
    func show(near field: FieldContext) {
        if !userDragged {
            let size = NSSize(width: Self.preferredWidth, height: max(120, frame.height))
            let frame = SnapPositionSolver.frame(preferredSize: size, near: field.cocoaFrame, edge: AppSettings.shared.snapEdge)
            isProgrammaticMove = true
            setFrame(frame, display: true, animate: false)
            isProgrammaticMove = false
        }
        orderFrontRegardless()
    }

    /// 内容高度变化后自适应（保持左上角不动）。
    func resizeToFitContent() {
        guard let content = contentView else { return }
        let height = max(120, content.fittingSize.height)
        var newFrame = frame
        newFrame.origin.y = frame.maxY - height
        newFrame.size.height = height
        isProgrammaticMove = true
        setFrame(newFrame, display: true, animate: false)
        isProgrammaticMove = false
    }
}
