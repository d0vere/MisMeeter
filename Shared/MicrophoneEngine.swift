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
        case .noInput:
            return "No microphone input is available."
        case .audioUnitCreation(let status):
            return "Could not create microphone Audio Unit (\(status))."
        case .audioUnitConfiguration(let status):
            return "Could not configure microphone Audio Unit (\(status))."
        case .unsupportedSampleRate(let rate):
            return "The microphone session is running at \(Int(rate)) Hz; MisMeeter requires 48000 Hz."
        }
    }
}

final class MicrophoneEngine {
    private let transmitter: VBANTransmitter

    private var audioUnit: AudioUnit?
    private var renderBuffer =
        [Float](repeating: 0, count: 4096)

    private let gainLock =
        OSAllocatedUnfairLock(initialState: Float(12))

    private var lastCallbackHostTime: UInt64?
    private var maxCallbackGapMS: Double = 0
    private var callbackCount: UInt64 = 0

    var onMeter: ((Float) -> Void)?
    var onAudioDiagnostics: ((Int, Double) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?
    var onCaptureGap: ((Double) -> Void)?

    init(transmitter: VBANTransmitter) {
        self.transmitter = transmitter
    }

    var gainDB: Float {
        get {
            gainLock.withLock { $0 }
        }
        set {
            gainLock.withLock {
                $0 = max(0, min(24, newValue))
            }
        }
    }

    func start(
        voiceProcessingEnabled: Bool,
        backgroundOutputKeepAlive: Bool = true
    ) throws {
        stop(
            deactivateSession: false
        )

        let session =
            AVAudioSession.sharedInstance()

        try AudioSessionCoordinator.shared
            .configureForDuplex(
                voiceProcessing:
                    voiceProcessingEnabled
            )

        guard session.isInputAvailable else {
            throw MicrophoneEngineError.noInput
        }

        guard abs(
            session.sampleRate -
            VBANPacket.sampleRate
        ) < 1 else {
            throw MicrophoneEngineError
                .unsupportedSampleRate(
                    session.sampleRate
                )
        }

        let subtype: OSType =
            voiceProcessingEnabled
            ? kAudioUnitSubType_VoiceProcessingIO
            : kAudioUnitSubType_RemoteIO

        var description =
            AudioComponentDescription(
                componentType:
                    kAudioUnitType_Output,
                componentSubType:
                    subtype,
                componentManufacturer:
                    kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )

        guard let component =
            AudioComponentFindNext(
                nil,
                &description
            )
        else {
            throw MicrophoneEngineError
                .audioUnitCreation(-1)
        }

        var unit: AudioUnit?

        var status =
            AudioComponentInstanceNew(
                component,
                &unit
            )

        guard status == noErr,
              let unit
        else {
            throw MicrophoneEngineError
                .audioUnitCreation(status)
        }

        audioUnit = unit

        // Enable input on RemoteIO input bus 1.
        var enableInput: UInt32 = 1

        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableInput,
            UInt32(
                MemoryLayout<UInt32>.size
            )
        )

        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError
                .audioUnitConfiguration(status)
        }

        // No audible output is required from this Audio Unit.
        // RX playback remains handled by its own AVAudioEngine.
        var disableOutput: UInt32 = 0

        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &disableOutput,
            UInt32(
                MemoryLayout<UInt32>.size
            )
        )

        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError
                .audioUnitConfiguration(status)
        }

        // We ask RemoteIO to render microphone audio as mono Float32 at 48k.
        // Format is set on the output scope of input element 1.
        var format =
            AudioStreamBasicDescription(
                mSampleRate:
                    VBANPacket.sampleRate,
                mFormatID:
                    kAudioFormatLinearPCM,
                mFormatFlags:
                    kAudioFormatFlagsNativeFloatPacked |
                    kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket:
                    UInt32(
                        MemoryLayout<Float>.size
                    ),
                mFramesPerPacket: 1,
                mBytesPerFrame:
                    UInt32(
                        MemoryLayout<Float>.size
                    ),
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
            UInt32(
                MemoryLayout<
                    AudioStreamBasicDescription
                >.size
            )
        )

        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError
                .audioUnitConfiguration(status)
        }

        var callback =
            AURenderCallbackStruct(
                inputProc:
                    microphoneRenderCallback,
                inputProcRefCon:
                    Unmanaged.passUnretained(
                        self
                    ).toOpaque()
            )

        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            1,
            &callback,
            UInt32(
                MemoryLayout<
                    AURenderCallbackStruct
                >.size
            )
        )

        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError
                .audioUnitConfiguration(status)
        }

        status =
            AudioUnitInitialize(unit)

        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError
                .audioUnitConfiguration(status)
        }

        lastCallbackHostTime = nil
        maxCallbackGapMS = 0
        callbackCount = 0

        status =
            AudioOutputUnitStart(unit)

        guard status == noErr else {
            cleanupAudioUnit()
            throw MicrophoneEngineError
                .audioUnitConfiguration(status)
        }

        onVoiceProcessingState?(
            voiceProcessingEnabled
        )

        // Explicit loudspeaker preference when RX is also active.
        AudioSessionCoordinator.shared
            .forceSpeaker()

        print(
            "MISMEETER: RemoteIO capture started • " +
            "\(session.sampleRate) Hz • " +
            "\(session.ioBufferDuration * 1000) ms • " +
            "voiceProcessing=\(voiceProcessingEnabled)"
        )
    }

    func stop(
        deactivateSession: Bool = true
    ) {
        cleanupAudioUnit()

        if deactivateSession {
            AudioSessionCoordinator.shared
                .deactivateIfPossible()
        }
    }

    fileprivate func handleRender(
        actionFlags: UnsafeMutablePointer<
            AudioUnitRenderActionFlags
        >,
        timeStamp: UnsafePointer<
            AudioTimeStamp
        >,
        busNumber: UInt32,
        frameCount: UInt32
    ) -> OSStatus {
        guard let unit = audioUnit else {
            return noErr
        }

        let frames = Int(frameCount)

        if frames <= 0 {
            return noErr
        }

        if frames > renderBuffer.count {
            // This should not occur with the requested hardware quantum.
            // Avoid allocating from the realtime callback.
            return kAudio_ParamError
        }

        var buffer =
            AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize:
                    UInt32(
                        frames *
                        MemoryLayout<Float>.size
                    ),
                mData:
                    &renderBuffer
            )

        var list =
            AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: buffer
            )

        let status =
            AudioUnitRender(
                unit,
                actionFlags,
                timeStamp,
                1,
                frameCount,
                &list
            )

        guard status == noErr else {
            return status
        }

        measureCallbackGap(
            hostTime:
                timeStamp.pointee.mHostTime
        )

        let gain =
            gainLock.withLock { $0 }

        let linearGain =
            powf(
                10,
                gain / 20
            )

        var output = [Int16]()
        output.reserveCapacity(frames)

        var peak: Float = 0

        renderBuffer
            .withUnsafeBufferPointer {
                pointer in

                for index in 0..<frames {
                    let raw =
                        pointer[index]

                    peak =
                        max(
                            peak,
                            abs(raw)
                        )

                    let limited =
                        tanhf(
                            raw *
                            linearGain
                        )

                    output.append(
                        Int16(
                            max(
                                -1,
                                min(
                                    1,
                                    limited
                                )
                            ) *
                            Float(
                                Int16.max
                            )
                        )
                    )
                }
            }

        onMeter?(
            min(
                1,
                peak * linearGain
            )
        )

        onAudioDiagnostics?(
            frames,
            AVAudioSession
                .sharedInstance()
                .ioBufferDuration
        )

        transmitter.enqueue(
            output
        )

        callbackCount &+= 1

        return noErr
    }

    private func measureCallbackGap(
        hostTime: UInt64
    ) {
        guard hostTime != 0 else {
            return
        }

        if let previous =
            lastCallbackHostTime {
            let delta =
                hostTime - previous

            let seconds =
                AVAudioTime.seconds(
                    forHostTime: delta
                )

            let gapMS =
                seconds * 1000

            maxCallbackGapMS =
                max(
                    maxCallbackGapMS,
                    gapMS
                )

            if callbackCount % 64 == 0 {
                onCaptureGap?(
                    maxCallbackGapMS
                )
            }
        }

        lastCallbackHostTime =
            hostTime
    }

    private func cleanupAudioUnit() {
        guard let unit =
            audioUnit
        else {
            return
        }

        _ = AudioOutputUnitStop(unit)
        _ = AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)

        audioUnit = nil
    }
}

private let microphoneRenderCallback:
    AURenderCallback = {
        refCon,
        actionFlags,
        timeStamp,
        busNumber,
        frameCount,
        _ in

        let engine =
            Unmanaged<
                MicrophoneEngine
            >
            .fromOpaque(refCon)
            .takeUnretainedValue()

        return engine.handleRender(
            actionFlags: actionFlags,
            timeStamp: timeStamp,
            busNumber: busNumber,
            frameCount: frameCount
        )
    }
