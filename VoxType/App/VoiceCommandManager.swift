import Cocoa

struct VoiceCommandManager {
    enum Action {
        case insertText(String)
        case pressKey(keyCode: CGKeyCode, flags: CGEventFlags)
    }

    static func parse(text: String) -> [Action] {
        let cleanText = text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch cleanText {
        case "deshacer", "deshazlo", "deshaz", "undo", "undo that":
            return [.pressKey(keyCode: 0x06 , flags: .maskCommand)]

        case "borrar", "borra", "borralo", "delete", "borrar última palabra", "borra última palabra", "delete last word":
            return [.pressKey(keyCode: 0x33 , flags: .maskAlternate)]

        case "borrar todo", "borra todo", "eliminar todo", "elimina todo", "delete all", "clear all":
            return [
                .pressKey(keyCode: 0x00 , flags: .maskCommand),
                .pressKey(keyCode: 0x33 , flags: [])
            ]

        case "seleccionar todo", "selecciona todo", "select all":
            return [.pressKey(keyCode: 0x00 , flags: .maskCommand)]

        case "copiar", "copia", "copialo", "copy", "copy that":
            return [.pressKey(keyCode: 0x08 , flags: .maskCommand)]

        case "pegar", "pega", "pegalo", "paste", "paste that":
            return [.pressKey(keyCode: 0x09 , flags: .maskCommand)]

        case "cortar", "corta", "cortalo", "cut", "cut that":
            return [.pressKey(keyCode: 0x07 , flags: .maskCommand)]

        case "enter", "intro", "return", "nueva línea", "new line":
            return [.pressKey(keyCode: 0x24 , flags: [])]

        default:
            return [.insertText(text)]
        }
    }

    static func execute(actions: [Action], targetPID: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        for action in actions {
            switch action {
            case .insertText(_):
                break

            case .pressKey(let keyCode, let flags):
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { continue }

                keyDown.flags = flags
                keyUp.flags = flags

                if targetPID != 0 {
                    keyDown.postToPid(targetPID)
                    usleep(10_000)
                    keyUp.postToPid(targetPID)
                } else {
                    Task { @MainActor in
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        let applescriptModifier = applescriptString(for: flags)
                        let applescriptKey = applescriptKey(for: keyCode)
                        proc.arguments = ["-e", "tell application \"System Events\" to \(applescriptKey) \(applescriptModifier)"]
                        try? proc.run()
                    }
                }
                usleep(50_000)
            }
        }
    }

    private static func applescriptString(for flags: CGEventFlags) -> String {
        if flags.contains(.maskCommand) { return "using command down" }
        if flags.contains(.maskAlternate) { return "using option down" }
        if flags.contains(.maskControl) { return "using control down" }
        if flags.contains(.maskShift) { return "using shift down" }
        return ""
    }

    private static func applescriptKey(for keyCode: CGKeyCode) -> String {
        switch keyCode {
        case 0x06: return "keystroke \"z\""
        case 0x08: return "keystroke \"c\""
        case 0x09: return "keystroke \"v\""
        case 0x07: return "keystroke \"x\""
        case 0x00: return "keystroke \"a\""
        case 0x24: return "key code 36"
        case 0x33: return "key code 51"
        default: return ""
        }
    }
}
