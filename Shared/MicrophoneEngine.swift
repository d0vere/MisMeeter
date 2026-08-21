import AVFoundation
import AudioToolbox
import Foundation
import os

enum MicrophoneEngineError: LocalizedError {
    case noInput
    case audioUnitCreation(OSStatus)
    case audioUnitConfiguration(OSStatus)
    case unsupportedSampleRate(Double)

    var errorDescription: String? {
        switch self {
        case .noInput: return "No microphone input is available."
        case .audioUnitCreation(let status): return "Could not create microphone Audio Unit (\(status))."
        case .audioUnitConfiguration(let status): return "Could not configure microphone Audio Unit (\(status))."
        case .unsupportedSampleRate(let rate): return "The active audio route is \(Int(rate)) Hz; MisMeeter requires 48000 Hz."
        }
    }
}

final class MicrophoneEngine {
    private let transmitter: VBANTransmitter
    private var audioUnit: AudioUnit?
    private var floatRenderBuffer = [Float](repeating: 0, count: 8192)
    private var int16Scratch = [Int16](repeating: 0, count: 8192)

    private let gainLock = OSAllocatedUnfairLock(initialState: Float(12))
    private let diagnosticsLock = OSAllocatedUnfairLock(initialState: DiagnosticsState())

    private struct DiagnosticsState {
        var previousWallClockNS: UInt64?
        var maxWallClockGapMS: Double = 0
        var gapsOver10: UInt64 = 0
        var gapsOver15: UInt64 = 0
        var gapsOver25: UInt64 = 0
        var gapsOver50: UInt64 = 0
        var callbackCount: UInt64 = 0
    }

    var onMeter: ((Float) -> Void)?
    var onAudioDiagnostics: ((Int, Double) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?
    var onCaptureLabDiagnostics: ((Double, UInt64, UInt64, UInt64, UInt64, Int, UInt64, Double, UInt64, UInt64, Int) -> Void)?

    init(transmitter: VBANTransmitter) {
        self.transmitter = transmitter
    }

    var gainDB: Float {
        get { gainLock.withLock { $0 } }
        set { gainLock.withLock { $0 = max(0, min(24, newValue)) } }
    }

    func start(captureMode: CaptureMode) throws {
        stop(deactivateSession: false)
        let voiceProcessing = captureMode.usesVoiceProcessing

        try AudioSessionCoordinator.shared.configureForDuplex(voiceProcessing: voiceProcessing)
        let session = AVAudioSession.sharedInstance()
        guard session.isInputAvailable else { throw MicrophoneEngineError.noInput }
        guard abs(session.sampleRate - VBANPacket.sampleRate) < 1 else {
            throw MicrophoneEngineError.unsupportedSampleRate(session.sampleRate)
        }

        let subtype: OSType = voiceProcessing ? kAudioUnitSubType_VoiceProcessingIO : kAudioUnitSubType_RemoteIO
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subtype,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &description) else {
            throw MicrophoneEngineError.audioUnitCreation(-1)
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let unit else { throw MicrophoneEngineError.audioUnitCreation(status) }
        audioUnit = unit

        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enableInput, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { cleanupAudioUnit(); throw MicrophoneEngineError.audioUnitConfiguration(status) }

        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disableOutput, UInt32(MemoryLayout<UInt32>.size))
        guard status == noErr else { cleanupAudioUnit(); throw MicrophoneEngineError.audioUnitConfiguration(status) }

        var format = AudioStreamBasicDescription(
            mSampleRate: VBANPacket.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { cleanupAudioUnit(); throw MicrophoneEngineError.audioUnitConfiguration(status) }

        var callback = AURenderCallbackStruct(
            inputProc: microphoneRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { cleanupAudioUnit(); throw MicrophoneEngineError.audioUnitConfiguration(status) }

        status = AudioUnitInitialize(unit)
        guard status == noErr else { cleanupAudioUnit(); throw MicrophoneEngineError.audioUnitConfiguration(status) }

        diagnosticsLock.withLock { $0 = DiagnosticsState() }
        status = AudioOutputUnitStart(unit)
        guard status == noErr else { cleanupAudioUnit(); throw MicrophoneEngineError.audioUnitConfiguration(status) }

        onVoiceProcessingState?(voiceProcessing)
        AudioSessionCoordinator.shared.forceSpeaker()
    }

    func stop(deactivateSession: Bool = true) {
        cleanupAudioUnit()
        if deactivateSession { AudioSessionCoordinator.shared.deactivateIfPossible() }
    }

    func setBackgroundMode(_ background: Bool) {
        // TX is audio-clocked now; no scheduler-dependent background queue exists.
        publishDiagnostics()
    }

    fileprivate func handleRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard let unit = audioUnit else { return noErr }
        let frames = Int(frameCount)
        guard frames > 0, frames <= floatRenderBuffer.count else { return kAudio_ParamError }

        let nowNS = DispatchTime.now().uptimeNanoseconds
        updateWallClockDiagnostics(nowNS: nowNS)

        let renderStatus: OSStatus = floatRenderBuffer.withUnsafeMutableBufferPointer { floatPointer in
            let audioBuffer = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                mData: floatPointer.baseAddress
            )
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            return AudioUnitRender(unit, actionFlags, timeStamp, 1, frameCount, &list)
        }
        guard renderStatus == noErr else { return renderStatus }

        let gain = gainLock.withLock { $0 }
        let linearGain = powf(10, gain / 20)
        var peak: Float = 0

        int16Scratch.withUnsafeMutableBufferPointer { intPointer in
            floatRenderBuffer.withUnsafeBufferPointer { floatPointer in
                for i in 0..<frames {
                    let raw = floatPointer[i]
                    peak = max(peak, abs(raw))
                    let limited = tanhf(raw * linearGain)
                    intPointer[i] = Int16(max(-1, min(1, limited)) * Float(Int16.max))
                }
            }
            if let base = intPointer.baseAddress {
                transmitter.sendPCM16(base, frameCount: frames)
            }
        }

        let count = diagnosticsLock.withLock { $0.callbackCount }
        if count % 24 == 0 {
            onMeter?(min(1, peak * linearGain))
            onAudioDiagnostics?(frames, AVAudioSession.sharedInstance().ioBufferDuration)
            publishDiagnostics()
        }
        return noErr
    }

    private func updateWallClockDiagnostics(nowNS: UInt64) {
        diagnosticsLock.withLock { state in
            if let previous = state.previousWallClockNS {
                let gapMS = Double(nowNS - previous) / 1_000_000.0
                state.maxWallClockGapMS = max(state.maxWallClockGapMS, gapMS)
                if gapMS > 10 { state.gapsOver10 &+= 1 }
                if gapMS > 15 { state.gapsOver15 &+= 1 }
                if gapMS > 25 { state.gapsOver25 &+= 1 }
                if gapMS > 50 { state.gapsOver50 &+= 1 }
            }
            state.previousWallClockNS = nowNS
            state.callbackCount &+= 1
        }
    }

    private func publishDiagnostics() {
        let d = diagnosticsLock.withLock { ($0.maxWallClockGapMS, $0.gapsOver10, $0.gapsOver15, $0.gapsOver25, $0.gapsOver50) }
        onCaptureLabDiagnostics?(d.0, d.1, d.2, d.3, d.4, 0, 0, 0, 0, 0, 0)
    }

    private func cleanupAudioUnit() {
        guard let unit = audioUnit else { return }
        _ = AudioOutputUnitStop(unit)
        _ = AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        audioUnit = nil
    }
}

private let microphoneRenderCallback: AURenderCallback = { refCon, actionFlags, timeStamp, _, frameCount, _ in
    let engine = Unmanaged<MicrophoneEngine>.fromOpaque(refCon).takeUnretainedValue()
    return engine.handleRender(actionFlags: actionFlags, timeStamp: timeStamp, frameCount: frameCount)
}
