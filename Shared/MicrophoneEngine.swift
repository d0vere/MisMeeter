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

    private var floatRenderBuffer =
        [Float](repeating: 0, count: 4096)

    private var int16Scratch =
        [Int16](repeating: 0, count: 4096)

    private let txQueue =
        TXPacketQueue(
            capacityFrames: 96_000
        )

    private let pacer =
        MonotonicPacer()

    private let workerQueue =
        DispatchQueue(
            label: "dev.mismeeter.tx.worker",
            qos: .userInteractive
        )

    private let workerSignal =
        DispatchSemaphore(value: 0)

    private var workerRunning = false

    private var workerScratch =
        [Int16](
            repeating: 0,
            count: VBANPacket.samplesPerPacket
        )

    private let packetIntervalNS: UInt64 =
        UInt64(
            Double(VBANPacket.samplesPerPacket) /
            VBANPacket.sampleRate *
            1_000_000_000.0
        )

    private let txControlLock =
        OSAllocatedUnfairLock(
            initialState:
                TXControlState()
        )

    private struct TXControlState {
        var targetFrames = 2048          // default ≈42.67 ms
        var isBackground = false

        var lifetimeMaxDeadlineLateMS: Double = 0
        var recentMaxDeadlineLateMS: Double = 0
        var lateDeadlineCount: UInt64 = 0
        var catchUpPackets: UInt64 = 0

        var nextDeadlineTicks: UInt64 = 0
        var pacerPrimed = false

        var adaptationWindowStartTicks: UInt64 = 0
        var stableSinceTicks: UInt64 = 0
    }
    var onMeter: ((Float) -> Void)?
    var onAudioDiagnostics: ((Int, Double) -> Void)?
    var onVoiceProcessingState: ((Bool) -> Void)?

    /// micMaxGap, >10, >15, >25, >50,
    /// txBufferedFrames, txOverruns,
    /// txWakeMaxGapMS, txLateWakeCount, txCatchUpPackets, txTargetFrames
    var onCaptureLabDiagnostics: ((
        Double,
        UInt64,
        UInt64,
        UInt64,
        UInt64,
        Int,
        UInt64,
        Double,
        UInt64,
        UInt64,
        Int
    ) -> Void)?

    init(
        transmitter: VBANTransmitter
    ) {
        self.transmitter =
            transmitter
    }

    var gainDB: Float {
        get {
            gainLock.withLock {
                $0
            }
        }
        set {
            gainLock.withLock {
                $0 =
                    max(
                        0,
                        min(
                            24,
                            newValue
                        )
                    )
            }
        }
    }

    func start(
        captureMode: CaptureMode
    ) throws {
        stop(
            deactivateSession: false
        )

        let voiceProcessing =
            captureMode
                .usesVoiceProcessing

        try AudioSessionCoordinator
            .shared
            .configureForDuplex(
                voiceProcessing:
                    voiceProcessing
            )

        let session =
            AVAudioSession
                .sharedInstance()

        guard session.isInputAvailable
        else {
            throw MicrophoneEngineError
                .noInput
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
            voiceProcessing
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
                .audioUnitCreation(
                    status
                )
        }

        audioUnit = unit

        var enableInput: UInt32 = 1

        status =
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Input,
                1,
                &enableInput,
                UInt32(
                    MemoryLayout<
                        UInt32
                    >.size
                )
            )

        guard status == noErr else {
            cleanupAudioUnit()

            throw MicrophoneEngineError
                .audioUnitConfiguration(
                    status
                )
        }

        var disableOutput:
            UInt32 = 0

        status =
            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_EnableIO,
                kAudioUnitScope_Output,
                0,
                &disableOutput,
                UInt32(
                    MemoryLayout<
                        UInt32
                    >.size
                )
            )

        guard status == noErr else {
            cleanupAudioUnit()

            throw MicrophoneEngineError
                .audioUnitConfiguration(
                    status
                )
        }

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
                        MemoryLayout<
                            Float
                        >.size
                    ),
                mFramesPerPacket: 1,
                mBytesPerFrame:
                    UInt32(
                        MemoryLayout<
                            Float
                        >.size
                    ),
                mChannelsPerFrame: 1,
                mBitsPerChannel: 32,
                mReserved: 0
            )

        status =
            AudioUnitSetProperty(
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
                .audioUnitConfiguration(
                    status
                )
        }

        var callback =
            AURenderCallbackStruct(
                inputProc:
                    microphoneRenderCallback,
                inputProcRefCon:
                    Unmanaged
                        .passUnretained(
                            self
                        )
                        .toOpaque()
            )

        status =
            AudioUnitSetProperty(
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
                .audioUnitConfiguration(
                    status
                )
        }

        status =
            AudioUnitInitialize(
                unit
            )

        guard status == noErr else {
            cleanupAudioUnit()

            throw MicrophoneEngineError
                .audioUnitConfiguration(
                    status
                )
        }

        txQueue.reset(
            targetFrames: 2048
        )

        diagnosticsLock.withLock {
            $0 =
                DiagnosticsState()
        }

        txControlLock.withLock {
            $0 = TXControlState()
        }

        startWorker()

        status =
            AudioOutputUnitStart(
                unit
            )

        guard status == noErr else {
            stopWorker()
            cleanupAudioUnit()

            throw MicrophoneEngineError
                .audioUnitConfiguration(
                    status
                )
        }

        onVoiceProcessingState?(
            voiceProcessing
        )

        AudioSessionCoordinator
            .shared
            .forceSpeaker()

        print(
            "MISMEETER: CaptureLab \(captureMode.title) • " +
            "\(session.sampleRate) Hz • " +
            "\(session.ioBufferDuration * 1000) ms"
        )
    }

    func stop(
        deactivateSession: Bool = true
    ) {
        stopWorker()
        cleanupAudioUnit()

        if deactivateSession {
            AudioSessionCoordinator
                .shared
                .deactivateIfPossible()
        }
    }

    fileprivate func handleRender(
        actionFlags:
            UnsafeMutablePointer<
                AudioUnitRenderActionFlags
            >,
        timeStamp:
            UnsafePointer<
                AudioTimeStamp
            >,
        frameCount:
            UInt32
    ) -> OSStatus {
        guard let unit =
            audioUnit
        else {
            return noErr
        }

        let frames =
            Int(frameCount)

        guard frames > 0,
              frames <=
                floatRenderBuffer.count
        else {
            return kAudio_ParamError
        }

        let nowNS =
            DispatchTime
                .now()
                .uptimeNanoseconds

        updateWallClockDiagnostics(
            nowNS: nowNS,
            frameCount: frames
        )

        let renderStatus:
            OSStatus =
            floatRenderBuffer
                .withUnsafeMutableBufferPointer {
                    floatPointer in

                    var audioBuffer =
                        AudioBuffer(
                            mNumberChannels: 1,
                            mDataByteSize:
                                UInt32(
                                    frames *
                                    MemoryLayout<
                                        Float
                                    >.size
                                ),
                            mData:
                                floatPointer
                                    .baseAddress
                        )

                    var list =
                        AudioBufferList(
                            mNumberBuffers: 1,
                            mBuffers:
                                audioBuffer
                        )

                    return AudioUnitRender(
                        unit,
                        actionFlags,
                        timeStamp,
                        1,
                        frameCount,
                        &list
                    )
                }

        guard renderStatus ==
                noErr
        else {
            return renderStatus
        }

        let gain =
            gainLock.withLock {
                $0
            }

        let linearGain =
            powf(
                10,
                gain / 20
            )

        var peak: Float = 0

        int16Scratch
            .withUnsafeMutableBufferPointer {
                intPointer in

                floatRenderBuffer
                    .withUnsafeBufferPointer {
                        floatPointer in

                        for i in 0..<frames {
                            let raw =
                                floatPointer[i]

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

                            intPointer[i] =
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
                        }

                        if let base =
                            intPointer.baseAddress {
                            txQueue.write(
                                from: base,
                                count: frames
                            )
                            workerSignal.signal()
                        }
                    }
            }

        // These callbacks are intentionally lightweight and sampled.
        let callbackNumber =
            diagnosticsLock
                .withLock { state in
                    state.callbackCount
                }

        if callbackNumber % 32 == 0 {
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
        }

        return noErr
    }

    private func updateWallClockDiagnostics(
        nowNS: UInt64,
        frameCount: Int
    ) {
        diagnosticsLock.withLock {
            state in

            if let previous =
                state.previousWallClockNS {
                let gapMS =
                    Double(
                        nowNS - previous
                    ) /
                    1_000_000.0

                state.maxWallClockGapMS =
                    max(
                        state.maxWallClockGapMS,
                        gapMS
                    )

                if gapMS > 10 {
                    state.gapsOver10 &+= 1
                }

                if gapMS > 15 {
                    state.gapsOver15 &+= 1
                }

                if gapMS > 25 {
                    state.gapsOver25 &+= 1
                }

                if gapMS > 50 {
                    state.gapsOver50 &+= 1
                }
            }

            state.previousWallClockNS =
                nowNS

            state.callbackCount &+= 1
            state.lastFrameCount =
                frameCount
        }
    }


    func setBackgroundMode(
        _ background: Bool
    ) {
        let newTarget =
            background
            ? 3072       // 64.0 ms
            : 2048       // 42.67 ms

        txControlLock.withLock {
            state in

            state.isBackground =
                background

            if state.targetFrames <
                newTarget {
                state.targetFrames =
                    newTarget
            }

            state.recentMaxDeadlineLateMS = 0
            state.stableSinceTicks = 0
        }

        txQueue.setTargetFrames(
            max(
                txQueue.targetFrames(),
                newTarget
            )
        )

        workerSignal.signal()
    }


    private func startWorker() {
        stopWorker()

        workerRunning = true

        workerQueue.async {
            [weak self] in

            guard let self else {
                return
            }

            // A persistent task avoids repeatedly depending on Dispatch timer
            // wakeups. Once primed, pacing is controlled by mach_wait_until()
            // against an absolute monotonic timeline.
            while self.workerRunning {
                if !self.waitUntilPrimed() {
                    continue
                }

                self.runPacerCycle()
            }
        }
    }

    private func stopWorker() {
        workerRunning = false
        workerSignal.signal()

        txControlLock.withLock {
            state in
            state.pacerPrimed = false
            state.nextDeadlineTicks = 0
        }
    }

    private func waitUntilPrimed() -> Bool {
        while workerRunning {
            let snapshot =
                txQueue.snapshot()

            if snapshot.bufferedFrames >=
                snapshot.targetFrames {

                let now =
                    pacer.nowTicks()

                txControlLock.withLock {
                    state in

                    state.pacerPrimed = true
                    state.nextDeadlineTicks =
                        now

                    state.adaptationWindowStartTicks =
                        now

                    state.stableSinceTicks = 0
                }

                return true
            }

            _ = workerSignal.wait(
                timeout:
                    .now() +
                    .milliseconds(100)
            )
        }

        return false
    }

    private func runPacerCycle() {
        let deadline =
            txControlLock.withLock {
                $0.nextDeadlineTicks
            }

        pacer.wait(
            until: deadline
        )

        guard workerRunning else {
            return
        }

        let now =
            pacer.nowTicks()

        let lateTicks =
            now > deadline
            ? now - deadline
            : 0

        let lateMS =
            Double(
                pacer.nanoseconds(
                    forTicks:
                        lateTicks
                )
            ) /
            1_000_000.0

        txControlLock.withLock {
            state in

            state.lifetimeMaxDeadlineLateMS =
                max(
                    state.lifetimeMaxDeadlineLateMS,
                    lateMS
                )

            state.recentMaxDeadlineLateMS =
                max(
                    state.recentMaxDeadlineLateMS,
                    lateMS
                )

            if lateMS > 2.0 {
                state.lateDeadlineCount &+= 1
            }
        }

        sendDuePackets(
            nowTicks: now
        )

        adaptDeterministicTarget(
            nowTicks: now
        )

        publishCaptureLabDiagnostics()
    }

    private func sendDuePackets(
        nowTicks: UInt64
    ) {
        workerScratch
            .withUnsafeMutableBufferPointer {
                pointer in

                guard let base =
                    pointer.baseAddress
                else {
                    return
                }

                let intervalTicks =
                    pacer.ticks(
                        forNanoseconds:
                            packetIntervalNS
                    )

                var sent = 0

                while workerRunning &&
                        sent < 8 {
                    let deadline =
                        txControlLock
                            .withLock {
                                $0.nextDeadlineTicks
                            }

                    // The first packet for this cycle is always due.
                    // Subsequent packets are catch-up packets only if their
                    // absolute deadline has already passed.
                    if sent > 0 &&
                        nowTicks < deadline {
                        break
                    }

                    guard txQueue.readPacket(
                        into: base
                    ) else {
                        // Capture has not supplied enough PCM. Re-prime instead
                        // of transmitting artificial silence.
                        txControlLock.withLock {
                            state in
                            state.pacerPrimed = false
                        }

                        return
                    }

                    let packet =
                        Array(
                            UnsafeBufferPointer(
                                start: base,
                                count:
                                    VBANPacket.samplesPerPacket
                            )
                        )

                    transmitter.enqueue(
                        packet
                    )

                    txControlLock.withLock {
                        state in

                        if sent > 0 {
                            state.catchUpPackets &+= 1
                        }

                        state.nextDeadlineTicks &+=
                            intervalTicks
                    }

                    sent += 1
                }

                // If scheduling was catastrophically late, do not reset the
                // clock to "now". The next pacer cycle continues catching up
                // from the original absolute timeline.
            }
    }

    private func adaptDeterministicTarget(
        nowTicks: UInt64
    ) {
        let fiveSecondsTicks =
            pacer.ticks(
                forNanoseconds:
                    5_000_000_000
            )

        let thirtySecondsTicks =
            pacer.ticks(
                forNanoseconds:
                    30_000_000_000
            )

        let snapshot =
            txQueue.snapshot()

        var requestedTarget:
            Int?

        txControlLock.withLock {
            state in

            if state.adaptationWindowStartTicks == 0 {
                state.adaptationWindowStartTicks =
                    nowTicks
                return
            }

            guard nowTicks -
                    state.adaptationWindowStartTicks >=
                    fiveSecondsTicks
            else {
                return
            }

            let floor =
                state.isBackground
                ? 3072   // 64 ms
                : 2048   // 42.67 ms

            // If the pacer deadline was missed by more than one packet period,
            // add two packets (~10.67 ms) of safety.
            if state.recentMaxDeadlineLateMS >
                5.5 {

                let newTarget =
                    min(
                        8192,  // ~170.7 ms
                        max(
                            floor,
                            snapshot.targetFrames +
                            512
                        )
                    )

                requestedTarget =
                    newTarget

                state.targetFrames =
                    newTarget

                state.stableSinceTicks =
                    0
            } else {
                if state.stableSinceTicks == 0 {
                    state.stableSinceTicks =
                        nowTicks
                }

                if nowTicks -
                    state.stableSinceTicks >=
                    thirtySecondsTicks,
                   snapshot.targetFrames >
                    floor {

                    let newTarget =
                        max(
                            floor,
                            snapshot.targetFrames -
                            256
                        )

                    requestedTarget =
                        newTarget

                    state.targetFrames =
                        newTarget

                    state.stableSinceTicks =
                        nowTicks
                }
            }

            state.recentMaxDeadlineLateMS =
                0

            state.adaptationWindowStartTicks =
                nowTicks
        }

        if let requestedTarget {
            txQueue.setTargetFrames(
                requestedTarget
            )
        }
    }

    private func publishCaptureLabDiagnostics() {
        let diag =
            diagnosticsLock.withLock {
                state in

                (
                    state.maxWallClockGapMS,
                    state.gapsOver10,
                    state.gapsOver15,
                    state.gapsOver25,
                    state.gapsOver50
                )
            }

        let queueSnapshot =
            txQueue.snapshot()

        let control =
            txControlLock.withLock {
                state in

                (
                    state.lifetimeMaxDeadlineLateMS,
                    state.lateDeadlineCount,
                    state.catchUpPackets,
                    state.targetFrames
                )
            }

        onCaptureLabDiagnostics?(
            diag.0,
            diag.1,
            diag.2,
            diag.3,
            diag.4,
            queueSnapshot.bufferedFrames,
            queueSnapshot.overruns,
            control.0,
            control.1,
            control.2,
            control.3
        )
    }

    private func cleanupAudioUnit() {
        guard let unit =
            audioUnit
        else {
            return
        }

        _ =
            AudioOutputUnitStop(
                unit
            )

        _ =
            AudioUnitUninitialize(
                unit
            )

        AudioComponentInstanceDispose(
            unit
        )

        audioUnit = nil
    }
}

private let microphoneRenderCallback:
    AURenderCallback = {
        refCon,
        actionFlags,
        timeStamp,
        _,
        frameCount,
        _ in

        let engine =
            Unmanaged<
                MicrophoneEngine
            >
            .fromOpaque(
                refCon
            )
            .takeUnretainedValue()

        return engine.handleRender(
            actionFlags:
                actionFlags,
            timeStamp:
                timeStamp,
            frameCount:
                frameCount
        )
    }
