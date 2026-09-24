import Cocoa
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager!
    private let audioRecorder = AudioRecorder()
    private let whisperManager = WhisperManager()
    private let textInserter = TextInsertionManager()
    private let hotKeyManager = GlobalHotKeyManager()
    private let overlay = TranscriptionOverlay()
    private let history = TranscriptionHistory.shared
    private let settings = AppSettings.shared
    private var warmObserver: AnyCancellable?

    private var transcriptionTask: Task<Void, Never>?
    private var isCancelling = false

    enum AppState {
        case loadingModel
        case modelUnavailable
        case idle
        case recording
        case processing
    }

    private var state: AppState = .idle {
        didSet {
            menuBarManager?.updateState(state)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        menuBarManager = MenuBarManager(onQuit: { [weak self] in
            self?.quit()
        }, onResetPosition: { [weak self] in
            self?.overlay.resetPosition()
        })
        overlay.setOnCancel { [weak self] in self?.cancelCurrent() }
        state = .loadingModel
        overlay.setIdle()

        setupHotKey()
        checkAccessibilityPermission()

        audioRecorder.setWarm(settings.keepMicWarm)
        warmObserver = settings.$keepMicWarm.sink { [weak self] warm in
            self?.audioRecorder.setWarm(warm)
        }

        Task {
            await whisperManager.loadModel()
            await MainActor.run {
                if whisperManager.isModelLoaded {
                    state = .idle
                    if whisperManager.lastModelLoadMs > 2000 {
                        menuBarManager.showNotification("Ready")
                    }
                } else {
                    state = .modelUnavailable
                    showModelMissingAlert()
                }
            }
        }
    }

    private var keyDownTime: Date = Date.distantPast
    private var isToggleMode: Bool = false

    private func setupHotKey() {
        hotKeyManager.onKeyDown = { [weak self] id in
            DispatchQueue.main.async {
                guard let self = self else { return }

                let now = Date()
                guard now.timeIntervalSince(self.keyDownTime) > 0.2 else { return }

                if self.state == .idle {
                    self.keyDownTime = now
                    self.isToggleMode = false
                    self.startRecording()
                } else if self.state == .recording {
                    self.stopRecordingAndTranscribe()
                } else if self.state == .processing {
                    self.cancelCurrent()
                }
            }
        }

        hotKeyManager.onKeyUp = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.state == .recording else { return }

                let pressDuration = Date().timeIntervalSince(self.keyDownTime)
                if pressDuration < 0.4 {
                    self.isToggleMode = true
                } else {
                    if !self.isToggleMode {
                        self.stopRecordingAndTranscribe()
                    }
                }
            }
        }
        hotKeyManager.start()
    }

    private func startRecording() {
        if state == .loadingModel {
            overlay.showNotice("Loading model…")
            return
        }
        if state == .modelUnavailable {
            showModelMissingAlert()
            return
        }

        guard state == .idle else { return }
        guard whisperManager.isModelLoaded else {
            Log.app.error("Cannot record: model not loaded")
            return
        }
        state = .recording
        textInserter.captureTargetApp()

        let armedAt = CFAbsoluteTimeGetCurrent()
        var indicatorShown = false
        let showIndicator = { [weak self] in
            guard let self = self, !indicatorShown, self.state == .recording else { return }
            indicatorShown = true
            self.overlay.startRecording()
        }

        audioRecorder.onFirstBuffer = {
            PerfLog.shared.set("mic_start_ms", (CFAbsoluteTimeGetCurrent() - armedAt) * 1000)
            showIndicator()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showIndicator() }

        audioRecorder.startRecording()
    }

    func cancelCurrent() {
        switch state {
        case .recording:
            audioRecorder.cancelRecording()
            overlay.setIdle()
            state = .idle

        case .processing:
            isCancelling = true
            whisperManager.cancel()
            transcriptionTask?.cancel()
            overlay.setIdle()
            state = .idle

        case .idle, .loadingModel, .modelUnavailable:
            break
        }
    }

    private func stopRecordingAndTranscribe() {
        guard state == .recording else { return }
        state = .processing

        let audioData = audioRecorder.stopRecording()

        PerfLog.shared.begin(
            audioSeconds: Double(audioData.count) / 16000.0,
            language: settings.language.rawValue,
            llmEnabled: settings.ollamaEnabled,
            isColdStart: whisperManager.isColdStart
        )
        PerfLog.shared.set("model", settings.selectedModel.rawValue)
        PerfLog.shared.set("model_load_ms", whisperManager.lastModelLoadMs)

        guard !audioData.isEmpty else {
            Log.app.notice("No audio captured")
            overlay.setIdle()
            state = .idle
            return
        }

        overlay.showTranscribing()

        transcriptionTask = Task {
            let rawText = await whisperManager.transcribe(audioData: audioData)

            if Task.isCancelled || self.isCancelling {
                await MainActor.run { self.isCancelling = false }
                return
            }

            if let raw = rawText, !raw.isEmpty {
                var text = TextPostProcessor.process(raw, removeFillers: self.settings.fillerRemovalEnabled)

                let parsedActions = VoiceCommandManager.parse(text: text)

                if parsedActions.count == 1, case .insertText(_) = parsedActions[0] {
                    if self.settings.ollamaEnabled && !text.isEmpty {
                        await MainActor.run { self.overlay.showLLMProcessing() }

                        let appName = self.textInserter.getTargetAppName()
                        let clipboardContext = NSPasteboard.general.string(forType: .string)

                        PerfLog.shared.mark("t4")
                        text = await TextPostProcessor.processWithLLM(
                            text,
                            appName: appName,
                            clipboardContext: clipboardContext
                        )
                        PerfLog.shared.mark("t5")
                        PerfLog.shared.set("llm_provider", self.settings.llmProvider.rawValue)
                    }

                    let finalText = text

                    if Task.isCancelled || self.isCancelling {
                        await MainActor.run { self.isCancelling = false }
                        return
                    }

                    await MainActor.run {
                        guard !finalText.isEmpty else {
                            self.overlay.setIdle()
                            self.state = .idle
                            return
                        }
                        Log.app.debug("Final text: \(finalText, privacy: .private)")
                        self.history.add(finalText)

                        let uncertain = self.settings.ollamaEnabled
                            ? []
                            : self.whisperManager.lastWordConfidences
                                .filter { $0.confidence < 0.5 }
                                .map { $0.word }
                        if !uncertain.isEmpty {
                            Log.app.debug("Low-confidence words: \(uncertain, privacy: .private)")
                        }
                        self.overlay.showText(finalText, uncertain: uncertain)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.textInserter.insertText(finalText)
                            self.overlay.showPasted(finalText)
                            PerfLog.shared.mark("t6")
                            PerfLog.shared.set("out_chars", finalText.count)
                            PerfLog.shared.end()
                            self.state = .idle
                        }
                    }
                } else {
                    let command = text
                    await MainActor.run {
                        Log.app.info("Executing voice command: \(command, privacy: .private)")
                        self.overlay.showPasted("Command: \(command)")
                        VoiceCommandManager.execute(actions: parsedActions, targetPID: self.textInserter.targetPID)
                        self.state = .idle
                    }
                }
            } else {
                await MainActor.run {
                    Log.app.notice("No text transcribed")
                    self.overlay.setIdle()
                    self.state = .idle
                }
            }
        }
    }

    private func showModelMissingAlert() {
        let fileName = settings.selectedModel.fileName
        let alert = NSAlert()
        alert.messageText = "VoxType needs a speech model"
        alert.informativeText = """
            The model "\(fileName)" is not installed yet. In Terminal, go to the \
            folder where you downloaded VoxType and run:

                ./setup.sh --model

            Or put the file in the Models folder yourself, then quit and reopen VoxType.
            """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Models Folder")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            let dir = whisperManager.modelsDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            Log.app.error("Accessibility permission not granted; paste will not work (System Settings → Privacy & Security → Accessibility)")
            menuBarManager.showNotification("Grant Accessibility to paste text")
        } else {
            Log.app.info("Accessibility permission granted")
        }
    }

    private func quit() {
        hotKeyManager.stop()
        overlay.dismiss()
        whisperManager.shutdown()
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.resetPosition()
        return true
    }
}
