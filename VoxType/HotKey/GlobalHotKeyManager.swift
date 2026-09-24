import Cocoa
import Carbon

class GlobalHotKeyManager {
    var onKeyDown: ((UInt32) -> Void)?
    var onKeyUp: ((UInt32) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    static var shared: GlobalHotKeyManager?

    func start() {
        GlobalHotKeyManager.shared = self

        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status1 = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandlerRef
        )

        guard status1 == noErr else {
            Log.hotkey.error("Failed to install event handler: \(status1)")
            return
        }

        let hotKeyID1 = EventHotKeyID(signature: 0x564F5854, id: 1)

        var ref1: EventHotKeyRef?
        let status2 = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID1,
            GetApplicationEventTarget(),
            OptionBits(0),
            &ref1
        )

        if status2 == noErr {
            hotKeyRefs.append(ref1)
            Log.hotkey.info("Global hotkey registered (⌥+Space)")
        }
    }

    func stop() {
        for ref in hotKeyRefs {
            if let r = ref { UnregisterEventHotKey(r) }
        }
        hotKeyRefs.removeAll()
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        GlobalHotKeyManager.shared = nil
    }

    deinit {
        stop()
    }
}

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event,
          let manager = GlobalHotKeyManager.shared else {
        return OSStatus(eventNotHandledErr)
    }

    let eventKind = GetEventKind(event)
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event,
                      EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID),
                      nil,
                      MemoryLayout<EventHotKeyID>.size,
                      nil,
                      &hotKeyID)

    switch Int(eventKind) {
    case kEventHotKeyPressed:
        DispatchQueue.main.async {
            manager.onKeyDown?(hotKeyID.id)
        }
    case kEventHotKeyReleased:
        DispatchQueue.main.async {
            manager.onKeyUp?(hotKeyID.id)
        }
    default:
        break
    }

    return noErr
}
