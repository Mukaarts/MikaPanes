import AppKit
import ApplicationServices

/// Checks and requests the privacy permissions the app depends on.
///
/// - Accessibility (required) for window tiling via the AX API.
/// - Full Disk Access (optional) so the overlay can act on protected locations.
enum PermissionsService {

    // MARK: - Accessibility

    /// Whether the process is trusted to use the Accessibility API.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system Accessibility prompt (shows the app in the list).
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // MARK: - Full Disk Access

    /// Heuristic: try to read a TCC-protected path. If it fails, FDA is missing.
    /// There is no public API to query Full Disk Access directly.
    static var hasFullDiskAccess: Bool {
        let probe = ("~/Library/Application Support/com.apple.TCC/TCC.db" as NSString)
            .expandingTildeInPath
        let fd = open(probe, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        return false
    }

    static func openFullDiskAccessSettings() {
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    // MARK: - Helpers

    private static func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
