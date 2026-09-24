import Cocoa
import SwiftUI

class MenuBarManager {
    private var statusItem: NSStatusItem!
    private let onQuit: () -> Void
    private let onResetPosition: () -> Void
    private var onSettings: (() -> Void)?
    private var onHistory: (() -> Void)?
    private var pulseTimer: Timer?
    private weak var hotkeyItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    init(onQuit: @escaping () -> Void, onResetPosition: @escaping () -> Void) {
        self.onQuit = onQuit
        self.onResetPosition = onResetPosition
        setupStatusItem()
    }

    func setCallbacks(onSettings: @escaping () -> Void, onHistory: @escaping () -> Void) {
        self.onSettings = onSettings
        self.onHistory = onHistory
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "VoxType — Voice Dictation", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: "Loading model…", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)
        self.hotkeyItem = hotkeyItem

        menu.addItem(NSMenuItem.separator())

        let resetItem = NSMenuItem(title: "Reset Widget Position", action: #selector(resetPositionAction), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        let historyItem = NSMenuItem(title: "History...", action: #selector(historyAction), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(settingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VoxType", action: #selector(quitAction), keyEquivalent: "q"))
        menu.items.last?.target = self

        statusItem.menu = menu
        setIcon(name: "circle.dotted", color: .systemGray)
    }

    func updateState(_ state: AppDelegate.AppState) {
        pulseTimer?.invalidate()
        pulseTimer = nil

        switch state {
        case .loadingModel:
            setIcon(name: "circle.dotted", color: .systemGray)
            hotkeyItem?.title = "Loading model…"
            var tick = 0
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                tick = (tick + 1) % 2
                self?.setIcon(name: tick == 0 ? "circle.dotted" : "circle.dashed", color: .systemGray)
            }

        case .modelUnavailable:
            setIcon(name: "exclamationmark.triangle", color: .systemOrange)
            hotkeyItem?.title = "Model not found — see console"

        case .idle:
            setIcon(name: "mic", color: nil)
            hotkeyItem?.title = "Hold ⌥+Space to dictate"

        case .recording:
            setIcon(name: "mic.fill", color: .systemRed)
            var toggled = false
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                toggled.toggle()
                self?.setIcon(name: toggled ? "mic" : "mic.fill", color: .systemRed)
            }

        case .processing:
            setIcon(name: "waveform", color: .systemBlue)
            let icons = ["waveform", "waveform.circle", "waveform"]
            var idx = 0
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                idx = (idx + 1) % icons.count
                self?.setIcon(name: idx == 1 ? "ellipsis.circle" : "waveform", color: .systemBlue)
            }
        }
    }

    private func setIcon(name: String, color: NSColor?) {
        guard let button = statusItem?.button else { return }

        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let color = color {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        }

        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "VoxType")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = (color == nil)
    }

    func showNotification(_ message: String) {
        guard let button = statusItem?.button else { return }
        let original = button.image
        button.title = " \(message)"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            button.title = ""
            button.image = original
        }
    }

    @objc private func settingsAction() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView()
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "VoxType Settings"
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.contentMinSize = NSSize(width: 420, height: 320)
        w.setContentSize(NSSize(width: 460, height: 620))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
    }

    @objc private func historyAction() {
        if let w = historyWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = HistoryView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 420)

        let w = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Transcription History"
        w.isReleasedWhenClosed = false
        w.contentView = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        historyWindow = w
    }

    @objc private func resetPositionAction() {
        onResetPosition()
    }

    @objc private func quitAction() {
        pulseTimer?.invalidate()
        onQuit()
    }
}
