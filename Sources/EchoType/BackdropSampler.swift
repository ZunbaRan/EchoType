import AppKit

/// 面板背后内容的明暗：决定悬浮窗用浅色（aqua，深字）还是深色（darkAqua，白字）外观。
enum BackdropTone {
    case light
    case dark
}

/// 采样屏幕上某矩形区域的平均亮度，判定 Liquid Glass 悬浮窗该用哪种外观。
/// NSGlassEffectView 自身不会随背景明暗切换外观——实测 aqua/darkAqua 各自固定色调，
/// 所以由我们在显示前采样背景、显式选择，文字随语义色（labelColor 等）自动适配。
enum BackdropSampler {

    /// 平均亮度阈值（0~1，越高越亮）：低于此值判为深色背景。
    static let darkThreshold: CGFloat = 0.5

    static func tone(forLuminance luminance: CGFloat) -> BackdropTone {
        luminance < darkThreshold ? .dark : .light
    }

    /// 采样 screenRect（Quartz 左上原点全局坐标）的平均亮度。
    /// `belowWindowID` 传入已上屏面板的窗口号时，截取"该窗口之下"的内容，避免采到面板自身。
    /// 未授权屏幕录制等失败场景返回 nil（调用方保持现状即可）。
    static func luminance(under screenRect: CGRect, belowWindowID windowID: CGWindowID?) -> CGFloat? {
        let option: CGWindowListOption = windowID != nil ? .optionOnScreenBelowWindow : .optionOnScreenOnly
        guard let image = CGWindowListCreateImage(
            screenRect,
            option,
            windowID ?? kCGNullWindowID,
            [.nominalResolution]
        ) else { return nil }
        return self.luminance(of: image)
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
