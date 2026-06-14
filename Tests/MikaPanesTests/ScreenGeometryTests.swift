import Testing
import CoreGraphics
@testable import MikaPanes

@Suite struct ScreenGeometryTests {

    @Test func flipIsInvolution() {
        let height: CGFloat = 1080
        let rect = CGRect(x: 100, y: 200, width: 400, height: 300)
        let once = ScreenGeometry.flip(rect, primaryHeight: height)
        let twice = ScreenGeometry.flip(once, primaryHeight: height)
        #expect(twice == rect)
    }

    @Test func topLeftAXMapsToTopOfCocoaSpace() {
        let height: CGFloat = 1000
        // AX rect at the very top (y == 0), 200 tall.
        let ax = CGRect(x: 0, y: 0, width: 100, height: 200)
        let cocoa = ScreenGeometry.axToCocoa(ax, primaryHeight: height)
        // In Cocoa, the top of a 1000-tall screen is y == 800 for a 200-tall window.
        #expect(cocoa.origin.y == 800)
        #expect(cocoa.origin.x == 0)
    }

    @Test func xAndSizePreserved() {
        let height: CGFloat = 1440
        let rect = CGRect(x: 333, y: 444, width: 555, height: 666)
        let flipped = ScreenGeometry.flip(rect, primaryHeight: height)
        #expect(flipped.origin.x == 333)
        #expect(flipped.width == 555)
        #expect(flipped.height == 666)
    }
}
