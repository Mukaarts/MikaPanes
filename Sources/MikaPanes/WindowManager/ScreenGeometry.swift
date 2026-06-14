import AppKit

/// Bridges between the two coordinate systems involved in window tiling:
///
/// - **AX / Quartz**: global, origin at the *top-left* of the primary display, y grows down.
/// - **Cocoa / NSScreen**: global, origin at the *bottom-left* of the primary display, y grows up.
///
/// The flip math is an involution, so `axToCocoa` and `cocoaToAX` are the same
/// transform. Both are pure functions of `primaryHeight` for easy unit testing.
enum ScreenGeometry {

    /// Flip a rect between AX and Cocoa coordinate spaces.
    static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    static func axToCocoa(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    static func cocoaToAX(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    // MARK: - NSScreen helpers

    /// Height of the primary display (the one whose origin is (0,0)); the
    /// reference for the coordinate flip.
    static var primaryHeight: CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero }
        return (primary ?? NSScreen.main)?.frame.height ?? 0
    }

    /// The screen that best contains a Cocoa-space rect (largest overlap),
    /// falling back to the screen under the rect's center, then `.main`.
    static func screen(containing cocoaRect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in screens {
            let overlap = screen.frame.intersection(cocoaRect)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        if let best { return best }

        let center = CGPoint(x: cocoaRect.midX, y: cocoaRect.midY)
        return screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    /// Screens ordered left-to-right, then top-to-bottom — a stable order for
    /// "next/previous display".
    static func orderedScreens() -> [NSScreen] {
        NSScreen.screens.sorted {
            $0.frame.minX != $1.frame.minX
                ? $0.frame.minX < $1.frame.minX
                : $0.frame.minY < $1.frame.minY
        }
    }
}
