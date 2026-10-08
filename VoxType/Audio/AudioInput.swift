import CoreAudio
import Foundation

struct AudioLevels: Equatable {
    let peakDBFS: Double
    let rmsDBFS: Double

    static let floorDBFS = -200.0

    static func measure(_ samples: [Float]) -> AudioLevels {
        guard !samples.isEmpty else { return AudioLevels(peakDBFS: floorDBFS, rmsDBFS: floorDBFS) }
        var peak: Float = 0
        var sumSquares: Double = 0
        for s in samples {
            peak = max(peak, abs(s))
            sumSquares += Double(s) * Double(s)
        }
        let rms = (sumSquares / Double(samples.count)).squareRoot()
        return AudioLevels(peakDBFS: dbfs(Double(peak)), rmsDBFS: dbfs(rms))
    }

    static func normalizedForDetection(_ samples: [Float], peakDBFS: Double = -3) -> [Float] {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0 else { return samples }
        let gain = Float(pow(10, peakDBFS / 20)) / peak
        return samples.map { $0 * gain }
    }

    private static func dbfs(_ amplitude: Double) -> Double {
        amplitude > 0 ? max(floorDBFS, 20 * log10(amplitude)) : floorDBFS
    }
}

enum AudioInput {

    static func defaultKind() -> String {
        guard let id = defaultDeviceID() else { return "none" }
        switch uint32(id, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal) {
        case kAudioDeviceTransportTypeBuiltIn:
            let source = uint32(id, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeInput)
            return source == fourCC("emic") ? "jack" : "builtin"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "bluetooth"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return "continuity"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "virtual"
        default: return "other"
        }
    }

    static func defaultName() -> String? {
        guard let id = defaultDeviceID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func defaultDeviceID() -> AudioObjectID? {
        let id = uint32(AudioObjectID(kAudioObjectSystemObject),
                        kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)
        return (id == nil || id == kAudioObjectUnknown) ? nil : id
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func fourCC(_ code: String) -> UInt32 {
        code.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

enum SpeechGate: Equatable {
    case transcribe
    case skip(notice: String)

    static func decide(hasSpeech: Bool?, inputKind: String) -> SpeechGate {
        guard hasSpeech == false else { return .transcribe }
        if inputKind == "jack" {
            return .skip(notice: "No speech detected — check the input in System Settings → Sound")
        }
        return .skip(notice: "No speech detected")
    }
}
