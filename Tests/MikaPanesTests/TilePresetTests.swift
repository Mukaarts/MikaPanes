import Testing
import CoreGraphics
@testable import MikaPanes

@Suite struct TilePresetTests {

    // A visible frame not anchored at the origin, to catch min-offset bugs.
    let vf = CGRect(x: 100, y: 50, width: 1600, height: 1000)
    let current = CGRect(x: 300, y: 300, width: 640, height: 480)

    @Test func leftHalf() {
        #expect(TilePreset.leftHalf.frame(in: vf, current: current)
            == CGRect(x: 100, y: 50, width: 800, height: 1000))
    }

    @Test func rightHalf() {
        #expect(TilePreset.rightHalf.frame(in: vf, current: current)
            == CGRect(x: 900, y: 50, width: 800, height: 1000))
    }

    @Test func topHalfIsUpperInCocoaSpace() {
        // Top half occupies the higher y range (Cocoa origin is bottom-left).
        #expect(TilePreset.topHalf.frame(in: vf, current: current)
            == CGRect(x: 100, y: 550, width: 1600, height: 500))
    }

    @Test func bottomHalf() {
        #expect(TilePreset.bottomHalf.frame(in: vf, current: current)
            == CGRect(x: 100, y: 50, width: 1600, height: 500))
    }

    @Test func topRightQuarter() {
        #expect(TilePreset.topRight.frame(in: vf, current: current)
            == CGRect(x: 900, y: 550, width: 800, height: 500))
    }

    @Test func maximizeFillsVisibleFrame() {
        #expect(TilePreset.maximize.frame(in: vf, current: current) == vf)
    }

    @Test func centerKeepsSizeAndCenters() throws {
        let r = try #require(TilePreset.center.frame(in: vf, current: current))
        #expect(r.size == current.size)
        #expect(r.midX == vf.midX)
        #expect(r.midY == vf.midY)
    }

    @Test func displayPresetsReturnNil() {
        #expect(TilePreset.nextDisplay.frame(in: vf, current: current) == nil)
        #expect(TilePreset.previousDisplay.frame(in: vf, current: current) == nil)
    }
}
