import AppKit
import ScreenCaptureKit

/// 面板背后内容的明暗：决定悬浮窗用浅色（aqua，深字）还是深色（darkAqua，白字）外观。
enum BackdropTone {
    case light
    case dark
}

/// 采样屏幕上某矩形区域的平均亮度，判定 Liquid Glass 悬浮窗该用哪种外观。
/// 截取小尺寸背景图，排除本应用，不保存或发送图像。
enum BackdropSampler {

    /// 平均亮度阈值（0~1，越高越亮）：低于此值判为深色背景。
    static let darkThreshold: CGFloat = 0.5

    static func tone(forLuminance luminance: CGFloat, previous: BackdropTone? = nil) -> BackdropTone {
        // Match easydict-lite's hysteresis so mixed backgrounds do not repeatedly flip text color.
        let threshold: CGFloat = previous == .dark ? 0.6 : (previous == .light ? 0.4 : darkThreshold)
        return luminance < threshold ? .dark : .light
    }

    @available(macOS 14.0, *)
    static func luminance(behindPanelFrame frame: NSRect) async throws -> CGFloat? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        guard !ownApplications.isEmpty else { return nil }
        let sampleRect = ScreenCoordinates.topLeftFrame(
            fromCocoa: frame.insetBy(dx: 18, dy: 18),
            primaryScreenMaxY: CGDisplayBounds(CGMainDisplayID()).height
        )
        func area(_ display: SCDisplay) -> CGFloat {
            let intersection = display.frame.intersection(sampleRect)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        guard let display = content.displays.max(by: { area($0) < area($1) }) else { return nil }
        let crop = sampleRect.intersection(display.frame)
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return nil }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = crop.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let scale = 64 / max(crop.width, crop.height)
        configuration.width = max(1, Int((crop.width * scale).rounded()))
        configuration.height = max(1, Int((crop.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return luminance(of: image)
    }

    /// 平均亮度（0~1）：把整图缩到 1×1 取像素，最稳的全局近似。
    static func luminance(of image: CGImage) -> CGFloat? {
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: 4)
        // Rec.601 感知亮度
        return (0.299 * CGFloat(p[0]) + 0.587 * CGFloat(p[1]) + 0.114 * CGFloat(p[2])) / 255
    }
}
