import AppKit

/// 计算悬浮窗贴在输入框旁边的位置：默认下方，空间不足自动翻转到上方，并夹紧在可视区域内。
enum SnapPositionSolver {
    /// 纯逻辑版本：可视区域由调用方给出，便于测试。
    static func frame(preferredSize: NSSize, near fieldFrame: CGRect, edge: SnapEdge, visibleFrame visible: NSRect) -> CGRect {
        let gap: CGFloat = 8

        var origin = NSPoint(x: fieldFrame.minX, y: 0)
        switch edge {
        case .below:
            origin.y = fieldFrame.minY - gap - preferredSize.height
            if origin.y < visible.minY + gap {
                origin.y = fieldFrame.maxY + gap
            }
        case .above:
            origin.y = fieldFrame.maxY + gap
            if origin.y + preferredSize.height > visible.maxY - gap {
                origin.y = fieldFrame.minY - gap - preferredSize.height
            }
        }
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - preferredSize.height - gap)
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - preferredSize.width - gap)
        return NSRect(origin: origin, size: preferredSize)
    }

    static func frame(preferredSize: NSSize, near fieldFrame: CGRect, edge: SnapEdge) -> CGRect {
        let screen = NSScreen.screens.first { $0.frame.contains(fieldFrame.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return frame(preferredSize: preferredSize, near: fieldFrame, edge: edge, visibleFrame: visible)
    }
}
