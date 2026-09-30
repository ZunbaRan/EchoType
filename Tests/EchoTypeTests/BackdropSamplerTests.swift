import AppKit
import Testing
@testable import EchoType

struct BackdropSamplerTests {
    @Test func darkBelowThreshold() {
        #expect(BackdropSampler.tone(forLuminance: 0) == .dark)
        #expect(BackdropSampler.tone(forLuminance: BackdropSampler.darkThreshold - 0.01) == .dark)
    }

    @Test func lightAtOrAboveThreshold() {
        #expect(BackdropSampler.tone(forLuminance: BackdropSampler.darkThreshold) == .light)
        #expect(BackdropSampler.tone(forLuminance: 1) == .light)
    }

    @Test func luminanceOfSolidPixels() {
        #expect(BackdropSampler.luminance(of: solidImage(r: 0, g: 0, b: 0)!) == 0)
        let white = BackdropSampler.luminance(of: solidImage(r: 255, g: 255, b: 255)!)!
        #expect(abs(white - 1) < 0.01)
        // Rec.601: 纯绿 ~0.587
        let green = BackdropSampler.luminance(of: solidImage(r: 0, g: 255, b: 0)!)!
        #expect(abs(green - 0.587) < 0.02)
    }

    /// 构造 1×1 纯色 CGImage。
    private func solidImage(r: UInt8, g: UInt8, b: UInt8) -> CGImage? {
        var px: [UInt8] = [r, g, b, 255]
        guard let ctx = CGContext(
            data: &px, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}
