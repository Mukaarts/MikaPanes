import AppKit

/// Applies tiling presets to the focused window, handling coordinate conversion
/// and multi-monitor layout.
@MainActor
final class WindowTiler {
    private let ax: AXWindowService

    init(ax: AXWindowService = AXWindowService()) {
        self.ax = ax
    }

    func apply(_ preset: TilePreset) {
        guard PermissionsService.isAccessibilityTrusted else {
            PermissionsService.requestAccessibility()
            return
        }
        guard let window = ax.focusedWindow(), let axFrame = ax.frame(of: window) else {
            NSSound.beep()
            return
        }

        let primaryHeight = ScreenGeometry.primaryHeight
        let cocoaFrame = ScreenGeometry.axToCocoa(axFrame, primaryHeight: primaryHeight)

        guard let target = targetFrame(for: preset, current: cocoaFrame) else {
            NSSound.beep()
            return
        }

        let axTarget = ScreenGeometry.cocoaToAX(target, primaryHeight: primaryHeight)
        ax.setFrame(axTarget, for: window)
    }

    /// Resolve the target frame (Cocoa coords) for a preset given the window's
    /// current frame.
    private func targetFrame(for preset: TilePreset, current: CGRect) -> CGRect? {
        guard let screen = ScreenGeometry.screen(containing: current) else { return nil }

        switch preset {
        case .nextDisplay:
            return frameOnAdjacentDisplay(from: screen, current: current, offset: 1)
        case .previousDisplay:
            return frameOnAdjacentDisplay(from: screen, current: current, offset: -1)
        default:
            return preset.frame(in: screen.visibleFrame, current: current)
        }
    }

    /// Map the window onto the next/previous screen, preserving its relative
    /// position and clamping its size to the destination's visible area.
    private func frameOnAdjacentDisplay(
        from screen: NSScreen,
        current: CGRect,
        offset: Int
    ) -> CGRect? {
        let screens = ScreenGeometry.orderedScreens()
        guard screens.count > 1,
              let index = screens.firstIndex(of: screen)
        else { return nil }

        let destination = screens[(index + offset + screens.count) % screens.count]
        let src = screen.visibleFrame
        let dst = destination.visibleFrame

        let relX = src.width > 0 ? (current.minX - src.minX) / src.width : 0
        let relY = src.height > 0 ? (current.minY - src.minY) / src.height : 0

        let width = min(current.width, dst.width)
        let height = min(current.height, dst.height)
        var x = dst.minX + relX * dst.width
        var y = dst.minY + relY * dst.height

        // Clamp so the window stays fully on the destination's visible area.
        x = min(max(x, dst.minX), dst.maxX - width)
        y = min(max(y, dst.minY), dst.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
