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

    override var canBecomeKey: Bool { true }

    // MARK: 用户手动拖拽后的位置记忆

    private var userDragged = false
    private var isProgrammaticMove = false

    /// 用户拖拽过之后，翻译时保持用户放置的位置，不再自动贴边；关闭悬浮窗后重置。
    private func observeUserDrags() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidMoveUser),
            name: NSWindow.didMoveNotification, object: nil
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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }

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
