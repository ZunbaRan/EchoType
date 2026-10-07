import AppKit

/// 非激活式悬浮面板：点击与拖动都不会夺走当前输入应用的焦点。
final class SnapPanel: NSPanel {
    static let preferredWidth: CGFloat = 400

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.preferredWidth, height: 180),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        // Native edge/corner resizing with window-local hover hints.
        minSize = NSSize(width: 260, height: 140)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 全局强制 darkAqua 是为设置/状态窗口的深色设计；
        // 玻璃悬浮窗改用浅色外观，Liquid Glass 才呈亮色，语义文字色随 vibrancy 适配背景。
        if ResultView.usesLiquidGlass {
            appearance = NSAppearance(named: .aqua)
        }
        worksWithSpaces(AppSettings.shared.showsOnAllSpaces)
        observeUserDrags()
        observeResizeAndKey()
    }

    private func worksWithSpaces(_ allSpaces: Bool) {
        collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
    }

    // MARK: key 身份与系统边缘缩放
    //
    // 参考 Easydict ResultPanel 的已验证方案：系统的 .resizable 边缘缩放需要
    // 窗口能持 key（canBecomeKey=false 时缩放拖拽不生效）。但常驻 key 会抢走
    // 前台应用的键盘输入——所以点击/拖拽后让 key 自动归还，仅在缩放会话期间持有。

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private var backdropAdaptItem: DispatchWorkItem?

    private func observeResizeAndKey() {
        let center = NotificationCenter.default
        // 非缩放期间拿到 key（如点击面板）：归还键盘到前台应用；
        // 但鼠标还按着（缩放拖拽刚开始、inLiveResize 尚未置位）时不能归还——
        // 缩放跟踪需要 key 身份，所以等交互结束后再 resign。
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: self, queue: .main) { [weak self] _ in
            self?.scheduleResignKey()
        }
        center.addObserver(
            self, selector: #selector(liveResizeBegan),
            name: NSWindow.willStartLiveResizeNotification, object: self
        )
        center.addObserver(
            self, selector: #selector(liveResizeEnded),
            name: NSWindow.didEndLiveResizeNotification, object: self
        )
        // 缩放中背景区域不断变化：防抖重采样明暗
        center.addObserver(forName: NSWindow.didResizeNotification, object: self, queue: .main) { [weak self] _ in
            self?.scheduleBackdropAdapt()
        }
        center.addObserver(forName: NSWindow.didChangeScreenNotification, object: self, queue: .main) { [weak self] _ in
            self?.updateSizeLimits()
        }
    }

    @objc private func liveResizeBegan() {
        updateSizeLimits()
        // Every resize edge counts as intentional placement, including edges that leave the origin unchanged.
        userDragged = true
    }

    /// 缩放结束：持久化尺寸（之后每次显示沿用）、归还 key。
    /// inLiveResize 用 NSWindow 自带属性，缩放跟踪期间由 AppKit 维护。
    @objc private func liveResizeEnded() {
        let size = frame.size
        if size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
            AppSettings.shared.panelSize = size
        }
        resignKey()
    }

    private func scheduleBackdropAdapt() {
        backdropAdaptItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.adaptAppearanceToBackdrop() }
        backdropAdaptItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    /// 归还 key 身份：交互进行中（按住鼠标/缩放会话）稍候重试，交互结束后归还。
    private func scheduleResignKey() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.isKeyWindow else { return }
            if self.inLiveResize || NSEvent.pressedMouseButtons != 0 {
                self.scheduleResignKey()
            } else {
                self.resignKey()
            }
        }
    }

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
        guard isVisible, !isProgrammaticMove else { return }
        userDragged = true
        // 拖到新背景上后重新判定明暗
        scheduleBackdropAdapt()
    }

    /// 按面板背后内容的平均亮度切换外观：亮背景 → aqua（浅玻璃深字），
    /// 暗背景 → darkAqua（深玻璃白字）。NSGlassEffectView 不会自动适配，
    /// 语义文字色随外观自动反转；采样失败（如无屏幕录制权限）保持现状。
    private func adaptAppearanceToBackdrop() {
        guard ResultView.usesLiquidGlass else { return }
        let primaryMaxY = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.maxY
            ?? frame.maxY
        let screenRect = ScreenCoordinates.topLeftFrame(fromCocoa: frame, primaryScreenMaxY: primaryMaxY)
        let windowID = isVisible ? CGWindowID(windowNumber) : nil
        guard let luminance = BackdropSampler.luminance(under: screenRect, belowWindowID: windowID) else { return }
        let darkBackdrop = BackdropSampler.tone(forLuminance: luminance) == .dark
        appearance = NSAppearance(named: darkBackdrop ? .darkAqua : .aqua)
    }

    override func orderOut(_ sender: Any?) {
        (contentView as? ResultView)?.clearResizeHint()
        super.orderOut(sender)
        userDragged = false // 关闭后重新唤出时恢复自动贴边
    }

    // 面板可归还是 key（缩放需要），Esc 由全局键盘监听兜底关闭。

    func applySettings() {
        worksWithSpaces(AppSettings.shared.showsOnAllSpaces)
    }

    /// 按当前屏幕可视区钳制缩放范围（参考 Easydict：窗口换屏后也要可用）。
    private func updateSizeLimits() {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        updateSizeLimits(in: visible)
    }

    private func updateSizeLimits(in visible: NSRect) {
        minSize = NSSize(width: min(260, visible.width), height: min(140, visible.height))
        maxSize = visible.size
    }

    /// 显示尺寸：用户存的尺寸优先，并钳制在可视区内（换到小屏不丢保存值，只是显示时收缩）。
    private func restoredSize(in visible: NSRect) -> NSSize {
        let saved = AppSettings.shared.panelSize
        let minW = min(260, visible.width), minH = min(140, visible.height)
        return NSSize(
            width: min(visible.width, max(minW, saved?.width ?? Self.preferredWidth)),
            height: min(visible.height, max(minH, saved?.height ?? 180))
        )
    }

    /// 贴到指定输入框旁边显示；用户拖拽过的位置与缩放过的尺寸都保持沿用。
    func show(near field: FieldContext) {
        // A completed request can arrive during AppKit's live-resize event tracking.
        // Updating its text is safe; resetting its frame here would fight the user's drag.
        guard !inLiveResize else { return }
        let targetScreen = userDragged ? screen : NSScreen.screens.first { $0.frame.contains(field.cocoaFrame.origin) }
        guard let visible = (targetScreen ?? NSScreen.main)?.visibleFrame else { return }
        updateSizeLimits(in: visible)
        if !userDragged {
            var frame = SnapPositionSolver.frame(
                preferredSize: restoredSize(in: visible),
                near: field.cocoaFrame, edge: AppSettings.shared.snapEdge, visibleFrame: visible
            )
            // The solver normally leaves an eight-point gap; a screen-sized panel needs the full area.
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            isProgrammaticMove = true
            setFrame(frame, display: true, animate: false)
            isProgrammaticMove = false
        }
        adaptAppearanceToBackdrop()
        orderFrontRegardless()
    }
}
