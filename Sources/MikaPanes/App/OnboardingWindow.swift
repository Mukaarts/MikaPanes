import AppKit
import SwiftUI
import Combine

/// Polls permission state so the onboarding UI stays live while the user grants
/// access in System Settings.
@MainActor
final class PermissionsViewModel: ObservableObject {
    @Published var accessibility = PermissionsService.isAccessibilityTrusted
    @Published var fullDiskAccess = PermissionsService.hasFullDiskAccess

    private var timer: Timer?
    var onAccessibilityGranted: (() -> Void)?

    func startPolling() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let wasAccessibility = accessibility
        accessibility = PermissionsService.isAccessibilityTrusted
        fullDiskAccess = PermissionsService.hasFullDiskAccess
        if !wasAccessibility && accessibility {
            onAccessibilityGranted?()
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: PermissionsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mika+ Panes")
                    .font(.title2).bold()
                Text("Window tiling + a keyboard-driven Finder overlay, from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            permissionCard(
                title: "Accessibility",
                required: true,
                granted: model.accessibility,
                description: "Required to move and resize windows with hotkeys.",
                buttonTitle: model.accessibility ? "Open Settings" : "Grant Access…",
                action: {
                    PermissionsService.requestAccessibility()
                    PermissionsService.openAccessibilitySettings()
                }
            )

            permissionCard(
                title: "Full Disk Access",
                required: false,
                granted: model.fullDiskAccess,
                description: "Optional. Lets the overlay act on files in protected locations.",
                buttonTitle: "Open Settings",
                action: { PermissionsService.openFullDiskAccessSettings() }
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Default hotkeys").font(.headline)
                hotkeyHint("Tiling halves", "⌃⌥ + Arrows")
                hotkeyHint("Quarters", "⌃⌥ + U / I / J / K")
                hotkeyHint("Maximize · Center", "⌃⌥↩ · ⌃⌥C")
                hotkeyHint("Move to next display", "⌃⌥⌘→")
                hotkeyHint("Open Finder overlay", "⌃⌥Space")
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func permissionCard(
        title: String,
        required: Bool,
        granted: Bool,
        description: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : (required ? .orange : .secondary))
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if required {
                        Text("required").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
                .disabled(granted && !required)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func hotkeyHint(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(keys).font(.system(.caption, design: .monospaced))
        }
    }
}

/// Wraps the SwiftUI onboarding in a regular (non-accessory) window so it can be
/// shown on demand from the menu and on first run when Accessibility is missing.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let model = PermissionsViewModel()

    init() {
        model.onAccessibilityGranted = { [weak self] in
            // Bring focus back to whatever the user was doing; keep window open
            // so they can also grant Full Disk Access if they want.
            self?.model.objectWillChange.send()
        }
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Mika+ Panes"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        model.startPolling()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
