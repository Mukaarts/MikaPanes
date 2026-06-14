import AppKit
import QuickLookUI

/// Drives a shared `QLPreviewPanel` for the overlay's current item(s).
///
/// QuickLook expects a controller in the responder chain. Because the overlay is
/// a non-activating accessory panel, we assign the data source directly and bring
/// the panel up ourselves. If the panel is unavailable for any reason, we fall
/// back to the `qlmanage -p` CLI.
final class QuickLookController: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    func preview(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { NSSound.beep(); return }
        self.urls = existing

        guard let panel = QLPreviewPanel.shared() else {
            previewViaCLI(existing)
            return
        }
        // QuickLook needs to be frontmost to render; activate the app for it.
        NSApp.activate(ignoringOtherApps: true)
        panel.dataSource = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        urls[index] as NSURL
    }

    // MARK: - Fallback

    private func previewViaCLI(_ urls: [URL]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p"] + urls.map(\.path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
