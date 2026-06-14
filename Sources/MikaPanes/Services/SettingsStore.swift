import Foundation
import Carbon.HIToolbox

/// Carbon modifier masks, named for readability.
enum CarbonModifier {
    static let cmd: UInt32 = UInt32(cmdKey)
    static let shift: UInt32 = UInt32(shiftKey)
    static let option: UInt32 = UInt32(optionKey)
    static let control: UInt32 = UInt32(controlKey)
}

/// A global shortcut: a virtual key code plus Carbon modifier flags.
struct KeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
}

/// Every action that can be bound to a global hotkey.
enum HotKeyAction: String, CaseIterable, Codable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center
    case nextDisplay, previousDisplay
    case toggleOverlay

    /// The tiling preset this action maps to, if any. `toggleOverlay` has none.
    var tilePreset: TilePreset? {
        switch self {
        case .leftHalf: return .leftHalf
        case .rightHalf: return .rightHalf
        case .topHalf: return .topHalf
        case .bottomHalf: return .bottomHalf
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .maximize: return .maximize
        case .center: return .center
        case .nextDisplay: return .nextDisplay
        case .previousDisplay: return .previousDisplay
        case .toggleOverlay: return nil
        }
    }

    /// Rectangle-style default bindings shipped with the MVP.
    var defaultBinding: KeyBinding {
        let ctrlOpt = CarbonModifier.control | CarbonModifier.option
        let ctrlOptCmd = ctrlOpt | CarbonModifier.cmd
        switch self {
        case .leftHalf:        return KeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOpt)
        case .rightHalf:       return KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOpt)
        case .topHalf:         return KeyBinding(keyCode: UInt32(kVK_UpArrow), modifiers: ctrlOpt)
        case .bottomHalf:      return KeyBinding(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOpt)
        case .topLeft:         return KeyBinding(keyCode: UInt32(kVK_ANSI_U), modifiers: ctrlOpt)
        case .topRight:        return KeyBinding(keyCode: UInt32(kVK_ANSI_I), modifiers: ctrlOpt)
        case .bottomLeft:      return KeyBinding(keyCode: UInt32(kVK_ANSI_J), modifiers: ctrlOpt)
        case .bottomRight:     return KeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOpt)
        case .maximize:        return KeyBinding(keyCode: UInt32(kVK_Return), modifiers: ctrlOpt)
        case .center:          return KeyBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOpt)
        case .nextDisplay:     return KeyBinding(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOptCmd)
        case .previousDisplay: return KeyBinding(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOptCmd)
        case .toggleOverlay:   return KeyBinding(keyCode: UInt32(kVK_Space), modifiers: ctrlOpt)
        }
    }
}

/// Typed wrapper over `UserDefaults` for persisted settings.
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults
    private enum Key {
        static let bindings = "hotkey.bindings"
        static let browserRoot = "overlay.browserRoot"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Hotkey bindings

    /// All bindings, falling back to defaults for any action without a stored value.
    func binding(for action: HotKeyAction) -> KeyBinding {
        storedBindings()[action] ?? action.defaultBinding
    }

    func setBinding(_ binding: KeyBinding, for action: HotKeyAction) {
        var map = storedBindings()
        map[action] = binding
        persistBindings(map)
    }

    func resetBindingsToDefaults() {
        defaults.removeObject(forKey: Key.bindings)
    }

    private func storedBindings() -> [HotKeyAction: KeyBinding] {
        guard let data = defaults.data(forKey: Key.bindings),
              let raw = try? JSONDecoder().decode([String: KeyBinding].self, from: data)
        else { return [:] }
        var result: [HotKeyAction: KeyBinding] = [:]
        for (key, value) in raw {
            if let action = HotKeyAction(rawValue: key) { result[action] = value }
        }
        return result
    }

    private func persistBindings(_ map: [HotKeyAction: KeyBinding]) {
        let raw = Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Key.bindings)
        }
    }

    // MARK: - Overlay browser root

    var browserRoot: URL {
        get {
            if let path = defaults.string(forKey: Key.browserRoot) {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }
        set {
            defaults.set(newValue.path, forKey: Key.browserRoot)
        }
    }
}
