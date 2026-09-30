import AppKit
import Testing
@testable import EchoType

struct GlassTintTests {
    @Test func defaultFactorProducesExpectedAlpha() {
        let tint = ResultView.glassTint(forOpacity: 0.94, factor: 0.35)
        #expect(tint != nil)
        #expect(abs(tint!.alphaComponent - 0.329) < 1e-6)
    }

    @Test func zeroOpacityReturnsNil() {
        #expect(ResultView.glassTint(forOpacity: 0.0, factor: 0.35) == nil)
    }

    @Test func belowThresholdReturnsNil() {
        // 0.05 * 0.35 = 0.0175 ≤ 0.02
        #expect(ResultView.glassTint(forOpacity: 0.05, factor: 0.35) == nil)
    }

    @Test func aboveThresholdReturnsTint() {
        let tint = ResultView.glassTint(forOpacity: 0.1, factor: 0.35)
        #expect(tint != nil)
        #expect(abs(tint!.alphaComponent - 0.035) < 1e-6)
    }

    @Test func zeroFactorAlwaysNil() {
        #expect(ResultView.glassTint(forOpacity: 1.0, factor: 0.0) == nil)
    }

    @Test func fullFactorFullOpacity() {
        let tint = ResultView.glassTint(forOpacity: 1.0, factor: 1.0)
        #expect(tint != nil)
        #expect(abs(tint!.alphaComponent - 1.0) < 1e-6)
    }

    @Test func alphaIncreasesMonotonicallyWithOpacity() {
        let a = ResultView.glassTint(forOpacity: 0.3, factor: 0.35)!.alphaComponent
        let b = ResultView.glassTint(forOpacity: 0.6, factor: 0.35)!.alphaComponent
        let c = ResultView.glassTint(forOpacity: 0.9, factor: 0.35)!.alphaComponent
        #expect(a < b && b < c)
    }
}
