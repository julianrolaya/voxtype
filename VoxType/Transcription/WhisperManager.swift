import Foundation

class WhisperManager {
    private var context: OpaquePointer?
    private var loadedModelName: String?
    private let settings = AppSettings.shared

    var isModelLoaded: Bool { context != nil }

    private let abortFlag = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    private(set) var wasCancelled = false

    init() {
        abortFlag.initialize(to: false)
    }

    private(set) var lastModelLoadMs: Double = 0
    private(set) var isColdStart = true

    private(set) var lastWordConfidences: [(word: String, confidence: Float)] = []

    private(set) var lastLanguage: String?

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoxType/Models")
    }

    static let vadModelFile = "ggml-silero-v5.1.2.bin"
    static let vadThreshold: Float = 0.5

    private var vadContext: OpaquePointer?

    private func loadVADIfNeeded() {
        guard vadContext == nil else { return }
        let path = modelsDirectory.appendingPathComponent(Self.vadModelFile).path
        guard FileManager.default.fileExists(atPath: path) else {
            Log.transcription.notice("Voice detector model not installed (\(Self.vadModelFile, privacy: .public)); every capture goes to Whisper. Run ./setup.sh --model")
            return
        }
        var params = whisper_vad_default_context_params()
        params.n_threads = 4
        params.use_gpu = false
        vadContext = whisper_vad_init_from_file_with_params(path, params)
        if vadContext == nil { Log.transcription.error("Failed to load the voice detector") }
    }

    func hasSpeech(_ samples: [Float]) -> Bool? {
        guard let vctx = vadContext, !samples.isEmpty else { return nil }
        var params = whisper_vad_default_params()
        params.threshold = Self.vadThreshold
        let probe = AudioLevels.normalizedForDetection(samples)
        let segments = probe.withUnsafeBufferPointer {
            whisper_vad_segments_from_samples(vctx, params, $0.baseAddress, Int32($0.count))
        }
        guard let segments else { return nil }
        defer { whisper_vad_free_segments(segments) }
        return whisper_vad_segments_n_segments(segments) > 0
    }

    func loadModel() async {
        loadVADIfNeeded()
        let modelFile = settings.selectedModel.fileName

        if loadedModelName == modelFile && context != nil { return }

        if let ctx = context {
            whisper_free(ctx)
            context = nil
            loadedModelName = nil
        }

        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let modelPath = modelsDirectory.appendingPathComponent(modelFile).path

        guard FileManager.default.fileExists(atPath: modelPath) else {
            Log.transcription.error("Model not found: \(modelFile, privacy: .public). Run ./setup.sh --model")
            return
        }

        Log.transcription.info("Loading model \(modelFile, privacy: .public)")

        let params = whisper_context_default_params()
        let loadStart = CFAbsoluteTimeGetCurrent()
        context = whisper_init_from_file_with_params(modelPath, params)
        lastModelLoadMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000

        if context != nil {
            loadedModelName = modelFile
            isColdStart = true
            Log.transcription.info("Model loaded in \(self.lastModelLoadMs, format: .fixed(precision: 0)) ms")
        } else {
            Log.transcription.error("Failed to initialize whisper context")
        }
    }

    func transcribe(audioData: [Float]) async -> String? {
        guard let ctx = context else {
            Log.transcription.error("Model not loaded")
            return nil
        }

        guard audioData.count > 0 else {
            Log.transcription.notice("Empty audio data")
            return nil
        }

        if audioData.count < 8000 {
            Log.transcription.notice("Audio too short (\(audioData.count) samples, < 0.5 s); skipping")
            return nil
        }

        Log.transcription.debug("Transcribing \(audioData.count) samples")

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.single_segment = false
        params.no_timestamps = true
        params.n_threads = 4

        let langPtr = strdup(settings.language.rawValue)
        params.language = UnsafePointer(langPtr)

        var vocabPtr: UnsafeMutablePointer<CChar>? = nil
        let vocab = settings.customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vocab.isEmpty {
            vocabPtr = strdup(vocab)
            params.initial_prompt = UnsafePointer(vocabPtr)
        }

        abortFlag.pointee = false
        wasCancelled = false
        params.abort_callback = { userData in
            guard let userData = userData else { return false }
            return userData.assumingMemoryBound(to: Bool.self).pointee
        }
        params.abort_callback_user_data = UnsafeMutableRawPointer(abortFlag)

        PerfLog.shared.mark("t1")
        let result = audioData.withUnsafeBufferPointer { bufferPointer in
            whisper_full(ctx, params, bufferPointer.baseAddress, Int32(audioData.count))
        }
        PerfLog.shared.mark("t3")
        isColdStart = false

        free(langPtr)
        if let ptr = vocabPtr { free(ptr) }

        if abortFlag.pointee {
            wasCancelled = true
            Log.transcription.info("Transcription cancelled by user")
            return nil
        }

        guard result == 0 else {
            Log.transcription.error("Transcription failed with code \(result)")
            return nil
        }

        let nSegments = whisper_full_n_segments(ctx)
        var fullText = ""

        for i in 0..<nSegments {
            if let cString = whisper_full_get_segment_text(ctx, i) {
                fullText += String(cString: cString)
            }
        }

        lastWordConfidences = collectWordConfidences(ctx: ctx, segments: nSegments)
        lastLanguage = whisper_lang_str(whisper_full_lang_id(ctx)).map { String(cString: $0) }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let cleaned = HallucinationFilter.clean(trimmed) else {
            Log.transcription.info("Filtered hallucination: \(trimmed, privacy: .private)")
            return nil
        }
        if cleaned != trimmed {
            Log.transcription.info("Stripped hallucinated sentences, kept \(cleaned.count) chars")
        }
        return cleaned
    }

    private func collectWordConfidences(
        ctx: OpaquePointer, segments: Int32
    ) -> [(word: String, confidence: Float)] {
        var words: [(word: String, confidence: Float)] = []
        var current = ""
        var minP: Float = 1.0

        func flush() {
            let w = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !w.isEmpty { words.append((word: w, confidence: minP)) }
            current = ""
            minP = 1.0
        }

        for s in 0..<segments {
            for t in 0..<whisper_full_n_tokens(ctx, s) {
                guard let c = whisper_full_get_token_text(ctx, s, t) else { continue }
                let piece = String(cString: c)
                if piece.hasPrefix("[") { continue }

                if piece.hasPrefix(" ") { flush() }
                current += piece
                minP = min(minP, whisper_full_get_token_p(ctx, s, t))
            }
        }
        flush()
        return words
    }

    func shutdown() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
            loadedModelName = nil
        }
        if let vctx = vadContext {
            whisper_vad_free(vctx)
            vadContext = nil
        }
    }

    func cancel() {
        abortFlag.pointee = true
    }

    deinit {
        abortFlag.deallocate()
        if let ctx = context {
            whisper_free(ctx)
        }
        if let vctx = vadContext {
            whisper_vad_free(vctx)
        }
    }
}
