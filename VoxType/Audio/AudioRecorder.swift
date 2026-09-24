import AVFoundation

class AudioRecorder {
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: [Float] = []
    private let bufferQueue = DispatchQueue(label: "com.voxtype.audiobuffer")

    private let targetSampleRate: Double = 16000.0

    var onFirstBuffer: (() -> Void)?
    private var sawFirstBuffer = false

    private var isCapturing = false

    private var preRoll: [Float] = []
    private var preRollCapacity: Int { Int(targetSampleRate * 0.5) }

    private(set) var isWarm = false

    init() {
        _ = audioEngine.inputNode

        audioEngine.prepare()
    }

    func setWarm(_ on: Bool) {
        guard on != isWarm else { return }
        isWarm = on
        if on {
            startEngineIfNeeded()
        } else if !isCapturing {
            stopEngine()
        }
    }

    func startRecording() {
        if isWarm && audioEngine.isRunning {
            bufferQueue.sync {
                audioBuffer = preRoll
                preRoll.removeAll(keepingCapacity: true)
                isCapturing = true
            }
            sawFirstBuffer = true
            DispatchQueue.main.async { self.onFirstBuffer?() }
            Log.audio.debug("Recording started (warm, \(self.audioBuffer.count) pre-roll samples)")
            return
        }

        sawFirstBuffer = false
        bufferQueue.sync {
            audioBuffer = []
            isCapturing = true
        }
        startEngineIfNeeded()
    }

    private func startEngineIfNeeded() {
        guard !audioEngine.isRunning else { return }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            Log.audio.error("Failed to create target audio format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Log.audio.error("Failed to create audio converter from \(inputFormat, privacy: .public) to \(targetFormat, privacy: .public)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            if !self.sawFirstBuffer {
                self.sawFirstBuffer = true
                DispatchQueue.main.async { self.onFirstBuffer?() }
            }
            self.convertAndAccumulate(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }

        do {
            try audioEngine.start()
            Log.audio.debug("Recording started")
        } catch {
            Log.audio.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopEngine() {
        guard audioEngine.isRunning else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        audioEngine.prepare()
        bufferQueue.sync { preRoll.removeAll(keepingCapacity: false) }
    }

    func cancelRecording() {
        bufferQueue.sync {
            isCapturing = false
            audioBuffer.removeAll(keepingCapacity: false)
            preRoll.removeAll(keepingCapacity: true)
        }
        if !isWarm { stopEngine() }
        Log.audio.info("Recording cancelled; audio discarded")
    }

    func stopRecording() -> [Float] {
        bufferQueue.sync { isCapturing = false }
        if !isWarm { stopEngine() }
        Log.audio.debug("Recording stopped")

        var result: [Float] = []
        bufferQueue.sync {
            result = self.audioBuffer
        }

        let duration = Double(result.count) / targetSampleRate
        Log.audio.debug("Captured \(duration, format: .fixed(precision: 1)) s of audio (\(result.count) samples)")
        return result
    }

    private func convertAndAccumulate(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var hasData = true

        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let error = error {
            Log.audio.error("Audio conversion error: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let frameLength = Int(convertedBuffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

        bufferQueue.sync {
            if self.isCapturing {
                self.audioBuffer.append(contentsOf: samples)
            } else if self.isWarm {
                self.preRoll.append(contentsOf: samples)
                let excess = self.preRoll.count - self.preRollCapacity
                if excess > 0 { self.preRoll.removeFirst(excess) }
            }
        }
    }
}
