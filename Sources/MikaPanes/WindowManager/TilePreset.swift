import CoreGraphics

/// A window tiling target. Geometry is computed in Cocoa coordinates
/// (bottom-left origin), matching `NSScreen.visibleFrame`.
enum TilePreset {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center
    case nextDisplay, previousDisplay

    /// Target frame for presets confined to a single screen.
    ///
    /// Returns `nil` for the display-moving presets, which need the screen list
    /// and are handled by `WindowTiler`.
    ///
    /// - Parameters:
    ///   - visibleFrame: the screen area excluding menu bar/dock (Cocoa coords).
    ///   - current: the window's current frame (Cocoa coords), used by `.center`.
    func frame(in vf: CGRect, current: CGRect) -> CGRect? {
        let halfW = vf.width / 2
        let halfH = vf.height / 2
        switch self {
        case .leftHalf:
            return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: vf.height)
        case .rightHalf:
            return CGRect(x: vf.midX, y: vf.minY, width: halfW, height: vf.height)
        case .topHalf:
            return CGRect(x: vf.minX, y: vf.midY, width: vf.width, height: halfH)
        case .bottomHalf:
            return CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: halfH)
        case .topLeft:
            return CGRect(x: vf.minX, y: vf.midY, width: halfW, height: halfH)
        case .topRight:
            return CGRect(x: vf.midX, y: vf.midY, width: halfW, height: halfH)
        case .bottomLeft:
            return CGRect(x: vf.minX, y: vf.minY, width: halfW, height: halfH)
        case .bottomRight:
            return CGRect(x: vf.midX, y: vf.minY, width: halfW, height: halfH)
        case .maximize:
            return vf
        case .center:
            let w = min(current.width, vf.width)
            let h = min(current.height, vf.height)
            return CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
        case .nextDisplay, .previousDisplay:
            return nil
        }
    }
}
