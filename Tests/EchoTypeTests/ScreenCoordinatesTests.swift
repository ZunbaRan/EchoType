import AppKit
import Testing
@testable import EchoType

struct ScreenCoordinatesTests {
    @Test func cocoaFrameConversion() {
        let result = ScreenCoordinates.cocoaFrame(
            fromTopLeft: CGRect(x: 100, y: 50, width: 200, height: 30),
            primaryScreenMaxY: 900
        )
        #expect(result == NSRect(x: 100, y: 820, width: 200, height: 30))
    }

    @Test func rectAtScreenTop() {
        let result = ScreenCoordinates.cocoaFrame(
            fromTopLeft: CGRect(x: 0, y: 0, width: 100, height: 30),
            primaryScreenMaxY: 900
        )
        #expect(result.origin.y == 870)
    }

    @Test func rectAtScreenBottom() {
        let result = ScreenCoordinates.cocoaFrame(
            fromTopLeft: CGRect(x: 0, y: 870, width: 100, height: 30),
            primaryScreenMaxY: 900
        )
        #expect(result.origin.y == 0)
    }
}
