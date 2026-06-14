import AppKit
import ApplicationServices

/// Reads and mutates the focused window of the frontmost app via the AX API.
/// All frames are in AX (top-left origin) global coordinates.
final class AXWindowService {

    /// The focused window element of the frontmost application, if any.
    func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var windowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )
        guard status == .success, let windowRef else { return nil }
        // CFTypeRef carrying an AXUIElement — safe to treat as such.
        return (windowRef as! AXUIElement)
    }

    /// Current frame of a window in AX coordinates.
    func frame(of window: AXUIElement) -> CGRect? {
        guard let position = copyValue(window, kAXPositionAttribute, .cgPoint, CGPoint.self),
              let size = copyValue(window, kAXSizeAttribute, .cgSize, CGSize.self)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Move and resize a window. Position is set before and after the size, since
    /// some apps clamp position to their pre-resize size. Returns whether the
    /// window ended up close to the requested frame.
    @discardableResult
    func setFrame(_ frame: CGRect, for window: AXUIElement) -> Bool {
        setPosition(frame.origin, for: window)
        setSize(frame.size, for: window)
        setPosition(frame.origin, for: window)

        guard let result = self.frame(of: window) else { return false }
        let tolerance: CGFloat = 2
        let ok = abs(result.origin.x - frame.origin.x) <= tolerance
            && abs(result.origin.y - frame.origin.y) <= tolerance
            && abs(result.size.width - frame.size.width) <= tolerance
            && abs(result.size.height - frame.size.height) <= tolerance
        if !ok {
            NSLog("MikaPanes: window did not accept exact frame (likely a resize-resistant app)")
        }
        return ok
    }

    // MARK: - Private

    private func setPosition(_ point: CGPoint, for window: AXUIElement) {
        var value = point
        if let axValue = AXValueCreate(.cgPoint, &value) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axValue)
        }
    }

    private func setSize(_ size: CGSize, for window: AXUIElement) {
        var value = size
        if let axValue = AXValueCreate(.cgSize, &value) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, axValue)
        }
    }

    /// Copy an `AXValue` attribute and unwrap it into a concrete CG type.
    private func copyValue<T>(
        _ element: AXUIElement,
        _ attribute: String,
        _ type: AXValueType,
        _ out: T.Type
    ) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref
        else { return nil }
        let axValue = ref as! AXValue
        let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { result.deallocate() }
        guard AXValueGetValue(axValue, type, result) else { return nil }
        return result.pointee
    }
}
