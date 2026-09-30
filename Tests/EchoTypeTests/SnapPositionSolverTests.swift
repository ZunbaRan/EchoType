import AppKit
import Testing
@testable import EchoType

struct SnapPositionSolverTests {
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = NSSize(width: 400, height: 180)

    private func solve(near field: CGRect, edge: SnapEdge) -> CGRect {
        SnapPositionSolver.frame(
            preferredSize: size, near: field, edge: edge, visibleFrame: visible
        )
    }

    @Test func belowWithSpace() {
        let frame = solve(near: CGRect(x: 100, y: 500, width: 300, height: 30), edge: .below)
        #expect(frame.origin == NSPoint(x: 100, y: 312))
    }

    @Test func belowWithoutSpaceFlipsAbove() {
        let frame = solve(near: CGRect(x: 100, y: 50, width: 300, height: 30), edge: .below)
        #expect(frame.origin.y == 88)
    }

    @Test func aboveWithSpace() {
        let frame = solve(near: CGRect(x: 100, y: 100, width: 300, height: 30), edge: .above)
        #expect(frame.origin.y == 138)
    }

    @Test func aboveWithoutSpaceFlipsBelow() {
        let frame = solve(near: CGRect(x: 100, y: 800, width: 300, height: 30), edge: .above)
        #expect(frame.origin.y == 612)
    }

    @Test func xClampedToRightEdge() {
        let frame = solve(near: CGRect(x: 1400, y: 500, width: 30, height: 30), edge: .below)
        #expect(frame.origin.x == 1032)
    }

    @Test func xClampedToLeftEdge() {
        let frame = solve(near: CGRect(x: -50, y: 500, width: 300, height: 30), edge: .below)
        #expect(frame.origin.x == 8)
    }

    @Test func returnedSizeEqualsPreferredSize() {
        let frame = solve(near: CGRect(x: 100, y: 500, width: 300, height: 30), edge: .below)
        #expect(frame.size == size)
    }
}
