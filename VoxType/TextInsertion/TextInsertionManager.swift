import Cocoa

class TextInsertionManager {

    private(set) var targetPID: pid_t = 0
    private var targetAppName: String?

    func captureTargetApp() {
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            targetPID = frontApp.processIdentifier
            targetAppName = frontApp.localizedName
            Log.insertion.debug("Target app: \(frontApp.localizedName ?? "unknown", privacy: .private) (pid \(self.targetPID))")
        }
    }

    func getTargetAppName() -> String? {
        return targetAppName
    }

    func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general

        let savedContents = savePasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        activateTargetApp()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.performPaste()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.restorePasteboard(pasteboard, contents: savedContents)
            }
        }
    }

    private func activateTargetApp() {
        guard targetPID != 0,
              let app = NSRunningApplication(processIdentifier: targetPID) else { return }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    private func performPaste() {
        if !AXIsProcessTrusted() {
            Log.insertion.error("Cannot paste: Accessibility permission not granted (System Settings → Privacy & Security → Accessibility)")
            return
        }

        guard targetPID != 0 else {
            osascriptPaste()
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            osascriptPaste()
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        keyDown.postToPid(targetPID)
        usleep(20_000)
        keyUp.postToPid(targetPID)
        Log.insertion.debug("Pasted via CGEvent.postToPid(\(self.targetPID))")
    }

    private func osascriptPaste() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                Log.insertion.debug("Pasted via osascript")
            } else {
                Log.insertion.error("osascript failed with status \(process.terminationStatus)")
            }
        } catch {
            Log.insertion.error("osascript error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private struct SavedItem {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private func savePasteboard(_ pasteboard: NSPasteboard) -> [SavedItem] {
        var items: [SavedItem] = []
        guard let types = pasteboard.types else { return items }

        for type in types {
            if let data = pasteboard.data(forType: type) {
                items.append(SavedItem(type: type, data: data))
            }
        }
        return items
    }

    private func restorePasteboard(_ pasteboard: NSPasteboard, contents: [SavedItem]) {
        guard !contents.isEmpty else { return }
        pasteboard.clearContents()
        for item in contents {
            pasteboard.setData(item.data, forType: item.type)
        }
    }
}
