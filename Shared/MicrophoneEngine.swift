import AVFoundation
import AudioToolbox
import Foundation
import os

enum MicrophoneEngineError: LocalizedError {
    case noInput
    case audioUnitCreation(OSStatus)
    case audioUnitConfiguration(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInput:
            return "No microphone input is available."
        case .audioUnitCreation(let status):
            return "Could not create microphone Audio Unit (\(status))."
        case .audioUnitConfiguration(let stage, let status):
            return "Could not configure microphone Audio Unit [\(stage)] (\(status))."
        }
    }
}

final class MicrophoneEngine {
    private struct DiagnosticsState {
        var previousWallClockNS: UInt64?
        var maxWallClockGapMS: Double = 0
        var latestMeter: Float = 0
        var latestFrames: Int = 0
    }

    private let transmitter: VBANTransmitter
    private let diagnosticsQueue = DispatchQueue(
        label: "dev.mismeeter.microphone.diagnostics",
        qos: .utility
    )
    private let gainLock = OSAllocatedUnfairLock(initialState: Float(12))
    private let diagnosticsLock = OSAllocatedUnfairLock(initialState: DiagnosticsState())

    private var diagnosticsTimer: DispatchSourceTimer?
    private var audioUnit: AudioUnit?
    private var floatRenderBuffer = [Float](repeating: 0, count: 8192)
    private var int16Scratch = [Int16](repeating: 0, count: 8192)

    /// meter, callbackFrames, currentIOBufferDuration, maxCallbackGapMS
    var onDiagnostics: ((Float, Int, Double, Double) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?

    init(transmitter: VBANTransmitter) {
        self.transmitter = transmitter
    }

    deinit {
        stopDiagnosticsTimer()
        cleanupAudioUnit()
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

        let subtype: OSType = voiceProcessing
            ? kAudioUnitSubType_VoiceProcessingIO
            : kAudioUnitSubType_RemoteIO
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
        guard status == noErr, let unit else {
            throw MicrophoneEngineError.audioUnitCreation(status)
        }
        audioUnit = unit

        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("enable-input", status)
        }

        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("disable-output", status)
        }

        // Keep the application side at the VBAN rate. RemoteIO can perform sample-rate
        // conversion when the current route uses a different hardware rate.
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

        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("stream-format", status)
        }

        // Bound callback size to the preallocated realtime buffers.
        var maximumFramesPerSlice = UInt32(floatRenderBuffer.count)
        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_MaximumFramesPerSlice,
            kAudioUnitScope_Global,
            0,
            &maximumFramesPerSlice,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("maximum-frames", status)
        }

        var callback = AURenderCallbackStruct(
            inputProc: microphoneRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            1,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("input-callback", status)
        }

        status = AudioUnitInitialize(unit)
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("initialize", status)
        }

        diagnosticsLock.withLock { $0 = DiagnosticsState() }
        status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError.audioUnitConfiguration("start", status)
        }

        startDiagnosticsTimer()
        onVoiceProcessingState?(voiceProcessing)
        AudioSessionCoordinator.shared.preferBuiltInSpeakerIfNeeded()
    }

    func stop(deactivateSession: Bool = true) {
        stopDiagnosticsTimer()
        cleanupAudioUnit()
        onVoiceProcessingState?(false)
        if deactivateSession {
            AudioSessionCoordinator.shared.deactivateIfPossible()
        }
    }

    fileprivate func handleRender(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard let unit = audioUnit else { return noErr }
        let frames = Int(frameCount)
        guard frames > 0, frames <= floatRenderBuffer.count else {
            return kAudio_ParamError
        }

        let nowNS = DispatchTime.now().uptimeNanoseconds

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
                for index in 0..<frames {
                    let raw = floatPointer[index]
                    peak = max(peak, abs(raw))
                    let limited = tanhf(raw * linearGain)
                    intPointer[index] = Int16(max(-1, min(1, limited)) * Float(Int16.max))
                }
            }
            if let baseAddress = intPointer.baseAddress {
                transmitter.sendPCM16(baseAddress, frameCount: frames)
            }
        }

        diagnosticsLock.withLock { state in
            if let previous = state.previousWallClockNS {
                state.maxWallClockGapMS = max(
                    state.maxWallClockGapMS,
                    Double(nowNS - previous) / 1_000_000.0
                )
            }
            state.previousWallClockNS = nowNS
            state.latestFrames = frames
            state.latestMeter = min(1, peak * linearGain)
        }
        return noErr
    }

    private func startDiagnosticsTimer() {
        stopDiagnosticsTimer()
        let timer = DispatchSource.makeTimerSource(queue: diagnosticsQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(150),
            repeating: .milliseconds(250),
            leeway: .milliseconds(30)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let snapshot = self.diagnosticsLock.withLock { state in
                (state.latestMeter, state.latestFrames, state.maxWallClockGapMS)
            }
            let ioBufferDuration = AVAudioSession.sharedInstance().ioBufferDuration
            self.onDiagnostics?(snapshot.0, snapshot.1, ioBufferDuration, snapshot.2)
        }
        diagnosticsTimer = timer
        timer.resume()
    }

    private func stopDiagnosticsTimer() {
        diagnosticsTimer?.setEventHandler {}
        diagnosticsTimer?.cancel()
        diagnosticsTimer = nil
    }

    private func cleanupAudioUnit() {
        guard let unit = audioUnit else { return }
        _ = AudioOutputUnitStop(unit)
        _ = AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        audioUnit = nil
    }
}

private let microphoneRenderCallback: AURenderCallback = {
    refCon,
    actionFlags,
    timeStamp,
    _,
    frameCount,
    _ in
    let engine = Unmanaged<MicrophoneEngine>.fromOpaque(refCon).takeUnretainedValue()
    return engine.handleRender(
        actionFlags: actionFlags,
        timeStamp: timeStamp,
        frameCount: frameCount
    )
}
