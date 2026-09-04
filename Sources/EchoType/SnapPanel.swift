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
    }

    private func worksWithSpaces(_ allSpaces: Bool) {
        collectionBehavior = allSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

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

    /// 贴到指定输入框旁边显示。
    func show(near field: FieldContext) {
        let size = NSSize(width: Self.preferredWidth, height: max(120, frame.height))
        let frame = SnapPositionSolver.frame(preferredSize: size, near: field.cocoaFrame, edge: AppSettings.shared.snapEdge)
        setFrame(frame, display: true, animate: false)
        orderFrontRegardless()
    }

    /// 内容高度变化后自适应（保持左上角不动）。
    func resizeToFitContent() {
        guard let content = contentView else { return }
        let height = max(120, content.fittingSize.height)
        var newFrame = frame
        newFrame.origin.y = frame.maxY - height
        newFrame.size.height = height
        setFrame(newFrame, display: true, animate: false)
    }
}
