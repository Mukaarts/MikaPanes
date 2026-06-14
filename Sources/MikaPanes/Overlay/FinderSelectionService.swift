import Foundation

/// Reads the current selection of the frontmost Finder window via Apple Events
/// (AppleScript). The first call triggers the system Automation permission prompt.
enum FinderSelectionService {

    static func currentSelection() -> [URL] {
        let source = """
        tell application "Finder"
            set sel to selection as alias list
            set output to ""
            repeat with i from 1 to count of sel
                set output to output & POSIX path of (item i of sel as text)
                if i < (count of sel) then set output to output & linefeed
            end repeat
            return output
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return [] }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            NSLog("MikaPanes: Finder selection query failed: \(errorInfo)")
            return []
        }
        guard let text = descriptor.stringValue, !text.isEmpty else { return [] }
        return text
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
    }
}
