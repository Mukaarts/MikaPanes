import AppKit
import Carbon.HIToolbox

/// Registers global shortcuts via Carbon's `RegisterEventHotKey` and dispatches
/// presses to action handlers. One shared event handler fans out by hotkey id.
final class HotKeyManager {
    /// Called on the main thread when a registered hotkey is pressed.
    var onAction: ((HotKeyAction) -> Void)?

    private struct Registration {
        let action: HotKeyAction
        let ref: EventHotKeyRef
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    /// Four-char code identifying our hotkey signature.
    private let signature: OSType = {
        let chars = Array("MKPN".utf8)
        return (OSType(chars[0]) << 24) | (OSType(chars[1]) << 16)
             | (OSType(chars[2]) << 8) | OSType(chars[3])
    }()

    init() {
        installHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    // MARK: - Registration

    /// Registers the current binding for every action in the store, dropping any
    /// previous registrations first.
    func registerDefaults(using store: SettingsStore) {
        unregisterAll()
        for action in HotKeyAction.allCases {
            register(action, binding: store.binding(for: action))
        }
    }

    @discardableResult
    func register(_ action: HotKeyAction, binding: KeyBinding) -> Bool {
        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("MikaPanes: failed to register hotkey for \(action.rawValue) (status \(status))")
            return false
        }
        registrations[id] = Registration(action: action, ref: ref)
        return true
    }

    func unregisterAll() {
        for (_, reg) in registrations {
            UnregisterEventHotKey(reg.ref)
        }
        registrations.removeAll()
    }

    // MARK: - Carbon event handling

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(event)
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              let registration = registrations[hotKeyID.id]
        else { return OSStatus(eventNotHandledErr) }

        let action = registration.action
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
        return noErr
    }
}
