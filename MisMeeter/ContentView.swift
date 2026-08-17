import AVFoundation
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    // ---------------- TX presets ----------------

    @AppStorage("selectedPreset")
    private var selectedTXPreset = 0

    @AppStorage("p1Name")
    private var p1Name = "Preset 1"
    @AppStorage("p1Host")
    private var p1Host = ""
    @AppStorage("p1Port")
    private var p1Port = "6980"
    @AppStorage("p1Stream")
    private var p1Stream = "MisMeeter"

    @AppStorage("p2Name")
    private var p2Name = "Preset 2"
    @AppStorage("p2Host")
    private var p2Host = ""
    @AppStorage("p2Port")
    private var p2Port = "6980"
    @AppStorage("p2Stream")
    private var p2Stream = "MisMeeter2"

    @AppStorage("p3Name")
    private var p3Name = "Preset 3"
    @AppStorage("p3Host")
    private var p3Host = ""
    @AppStorage("p3Port")
    private var p3Port = "6980"
    @AppStorage("p3Stream")
    private var p3Stream = "MisMeeter3"

    @AppStorage("microphoneGainDB")
    private var gainDB = 12.0

    @AppStorage("captureModeV21")
    private var captureModeRaw =
        CaptureMode.voiceProcessingIO.rawValue

    @AppStorage("transmissionModeV08")
    private var transmissionModeRaw =
        VBANTransmissionMode.automatic.rawValue

    // ---------------- RX presets ----------------

    @AppStorage("selectedRXPreset")
    private var selectedRXPreset = 0

    @AppStorage("rx1Name")
    private var rx1Name = "RX 1"
    @AppStorage("rx1Port")
    private var rx1Port = "6980"
    @AppStorage("rx1Stream")
    private var rx1Stream = "PC-Main"
    @AppStorage("rx1Buffer")
    private var rx1Buffer = 100.0

    @AppStorage("rx2Name")
    private var rx2Name = "RX 2"
    @AppStorage("rx2Port")
    private var rx2Port = "6980"
    @AppStorage("rx2Stream")
    private var rx2Stream = "PC-Aux"
    @AppStorage("rx2Buffer")
    private var rx2Buffer = 100.0

    @AppStorage("rx3Name")
    private var rx3Name = "RX 3"
    @AppStorage("rx3Port")
    private var rx3Port = "6980"
    @AppStorage("rx3Stream")
    private var rx3Stream = "PC-Other"
    @AppStorage("rx3Buffer")
    private var rx3Buffer = 100.0

    // ---------------- TX state ----------------

    @State private var isStreaming =
        MisMeeterRuntime.shared.isStreaming
    @State private var isMuted =
        MisMeeterRuntime.shared.isMuted
    @State private var txStatus = "TX ready"
    @State private var meter: Float = 0
    @State private var packetsSent: UInt64 = 0
    @State private var callbackFrames = 0
    @State private var actualIOBufferMS = 0.0
    @State private var sendErrors: UInt64 = 0
    @State private var voiceProcessingActive = false
    @State private var measuredCaptureHz = 48_000.0
    @State private var effectiveTXHz = 48_000.0
    @State private var maxSendGapMS = 0.0
    @State private var maxCaptureGapMS = 0.0
    @State private var gapsOver10: UInt64 = 0
    @State private var gapsOver15: UInt64 = 0
    @State private var gapsOver25: UInt64 = 0
    @State private var gapsOver50: UInt64 = 0
    @State private var captureRingFrames = 0
    @State private var captureRingOverruns: UInt64 = 0
    @State private var txWakeMaxGapMS = 0.0
    @State private var txLateWakeCount: UInt64 = 0
    @State private var txCatchUpPackets: UInt64 = 0
    @State private var txTargetFrames = 1536
    @State private var audioWorkgroupJoined = false

    // ---------------- RX state ----------------

    @State private var isReceiving =
        MisMeeterRuntime.shared.isReceiving
    @State private var rxStatus = "RX ready"
    @State private var rxPackets: UInt64 = 0
    @State private var rxRejected: UInt64 = 0
    @State private var rxLost: UInt64 = 0
    @State private var rxBufferedFrames = 0
    @State private var rxUnderflows: UInt64 = 0
    @State private var rxPrimed = false
    @State private var rxPlaybackRate: Float = 1.0
    @State private var rxAdaptiveTargetMS = 100.0

    var body: some View {
        NavigationStack {
            Form {
                txSection
                rxSection
                diagnosticsSection
            }
            .navigationTitle("MisMeeter")
            .onAppear {
                wireRuntimeCallbacks()
                MisMeeterRuntime.shared.gainDB =
                    Float(gainDB)

                Task {
                    await MisMeeterRuntime.shared
                        .cleanupOrphanedLiveActivitiesIfIdle()
                }

                updateScenePhase(scenePhase)
            }
            .onChange(
                of: scenePhase
            ) { _, phase in
                updateScenePhase(phase)
            }
        }
    }

    // MARK: - TX UI

    private var txSection: some View {
        Section("MIC → VBAN") {
            Picker(
                "TX preset",
                selection: $selectedTXPreset
            ) {
                Text(
                    p1Name.isEmpty
                    ? "Preset 1"
                    : p1Name
                ).tag(0)

                Text(
                    p2Name.isEmpty
                    ? "Preset 2"
                    : p2Name
                ).tag(1)

                Text(
                    p3Name.isEmpty
                    ? "Preset 3"
                    : p3Name
                ).tag(2)
            }
            .pickerStyle(.segmented)
            .disabled(isStreaming)

            txPresetEditor

            Picker(
                "Capture engine",
                selection:
                    $captureModeRaw
            ) {
                ForEach(
                    CaptureMode.allCases
                ) { mode in
                    Text(
                        mode.title
                    )
                    .tag(
                        mode.rawValue
                    )
                }
            }
            .pickerStyle(.segmented)
            .disabled(isStreaming)

            Text(
                "v2.1 rolls back deterministic catch-up pacing. The TX worker joins the RemoteIO/VoiceProcessingIO Audio Workgroup, uses a small fixed 32 ms foreground / 48 ms background queue, and never sends a catch-up burst. Very stale whole packets are discarded instead."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Image(
                    systemName:
                        isMuted
                        ? "mic.slash.fill"
                        : "mic.fill"
                )

                VStack(
                    alignment: .leading
                ) {
                    Text(
                        isMuted
                        ? "Microphone muted"
                        : "Microphone live"
                    )

                    ProgressView(
                        value: Double(meter)
                    )
                }
            }

            VStack {
                HStack {
                    Text("Mic gain")
                    Spacer()
                    Text("+\(Int(gainDB)) dB")
                }

                Slider(
                    value: $gainDB,
                    in: 0...24,
                    step: 1
                )
                .onChange(
                    of: gainDB
                ) { _, value in
                    MisMeeterRuntime.shared
                        .gainDB = Float(value)
                }
            }

            Button {
                isMuted =
                    MisMeeterRuntime.shared
                        .toggleMuted()

                Task {
                    await MisMeeterRuntime.shared
                        .syncLiveActivity()
                }
            } label: {
                Label(
                    isMuted
                    ? "Unmute mic"
                    : "Mute mic",
                    systemImage:
                        isMuted
                        ? "mic.fill"
                        : "mic.slash.fill"
                )
            }
            .disabled(!isStreaming)

            Button {
                Task {
                    if isStreaming {
                        await stopTX()
                    } else {
                        await startTX()
                    }
                }
            } label: {
                Label(
                    isStreaming
                    ? "Stop Mic TX"
                    : "Start Mic TX",
                    systemImage:
                        isStreaming
                        ? "stop.fill"
                        : "dot.radiowaves.left.and.right"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text(txStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var txPresetEditor: some View {
        switch selectedTXPreset {
        case 1:
            txPresetFields(
                name: $p2Name,
                host: $p2Host,
                port: $p2Port,
                stream: $p2Stream
            )
        case 2:
            txPresetFields(
                name: $p3Name,
                host: $p3Host,
                port: $p3Port,
                stream: $p3Stream
            )
        default:
            txPresetFields(
                name: $p1Name,
                host: $p1Host,
                port: $p1Port,
                stream: $p1Stream
            )
        }
    }

    @ViewBuilder
    private func txPresetFields(
        name: Binding<String>,
        host: Binding<String>,
        port: Binding<String>,
        stream: Binding<String>
    ) -> some View {
        TextField(
            "Preset name",
            text: name
        )
        .disabled(isStreaming)

        TextField(
            "PC IPv4",
            text: host
        )
        .textInputAutocapitalization(.never)
        .keyboardType(.numbersAndPunctuation)
        .disabled(isStreaming)

        TextField(
            "UDP port",
            text: port
        )
        .keyboardType(.numberPad)
        .disabled(isStreaming)

        TextField(
            "VBAN stream",
            text: stream
        )
        .textInputAutocapitalization(.never)
        .disabled(isStreaming)
    }

    // MARK: - RX UI

    private var rxSection: some View {
        Section("VBAN → iPhone") {
            Picker(
                "RX preset",
                selection: $selectedRXPreset
            ) {
                Text(
                    rx1Name.isEmpty
                    ? "RX 1"
                    : rx1Name
                ).tag(0)

                Text(
                    rx2Name.isEmpty
                    ? "RX 2"
                    : rx2Name
                ).tag(1)

                Text(
                    rx3Name.isEmpty
                    ? "RX 3"
                    : rx3Name
                ).tag(2)
            }
            .pickerStyle(.segmented)
            .disabled(isReceiving)

            rxPresetEditor

            Button {
                if isReceiving {
                    stopRX()
                } else {
                    startRX()
                }
            } label: {
                Label(
                    isReceiving
                    ? "Stop Listening"
                    : "Start Listening",
                    systemImage:
                        isReceiving
                        ? "speaker.slash.fill"
                        : "speaker.wave.3.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Text(rxStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            if isReceiving {
                LabeledContent(
                    "Buffered",
                    value:
                        String(
                            format:
                                "%.0f ms",
                            Double(
                                rxBufferedFrames
                            ) /
                            VBANPacket.sampleRate *
                            1000
                        )
                )

                LabeledContent(
                    "Primed",
                    value:
                        rxPrimed
                        ? "Yes"
                        : "Buffering…"
                )

                LabeledContent(
                    "Packets",
                    value: "\(rxPackets)"
                )

                LabeledContent(
                    "Lost frames",
                    value: "\(rxLost)"
                )

                LabeledContent(
                    "Playback underflows",
                    value: "\(rxUnderflows)"
                )

                LabeledContent(
                    "Clock correction",
                    value:
                        String(
                            format:
                                "%.4fx",
                            rxPlaybackRate
                        )
                )

                LabeledContent(
                    "Adaptive target",
                    value:
                        String(
                            format:
                                "%.0f ms",
                            rxAdaptiveTargetMS
                        )
                )
            }

            Text(
                "Configure VoiceMeeter VBAN OUT to the iPhone's LAN IPv4, " +
                "the selected UDP port and the exact same stream name. " +
                "Receiver supports 48 kHz PCM16 mono/stereo."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rxPresetEditor: some View {
        switch selectedRXPreset {
        case 1:
            rxPresetFields(
                name: $rx2Name,
                port: $rx2Port,
                stream: $rx2Stream,
                buffer: $rx2Buffer
            )
        case 2:
            rxPresetFields(
                name: $rx3Name,
                port: $rx3Port,
                stream: $rx3Stream,
                buffer: $rx3Buffer
            )
        default:
            rxPresetFields(
                name: $rx1Name,
                port: $rx1Port,
                stream: $rx1Stream,
                buffer: $rx1Buffer
            )
        }
    }

    @ViewBuilder
    private func rxPresetFields(
        name: Binding<String>,
        port: Binding<String>,
        stream: Binding<String>,
        buffer: Binding<Double>
    ) -> some View {
        TextField(
            "Preset name",
            text: name
        )
        .disabled(isReceiving)

        TextField(
            "Listen UDP port",
            text: port
        )
        .keyboardType(.numberPad)
        .disabled(isReceiving)

        TextField(
            "VBAN stream",
            text: stream
        )
        .textInputAutocapitalization(.never)
        .disabled(isReceiving)

        VStack(
            alignment: .leading
        ) {
            HStack {
                Text("Jitter buffer")
                Spacer()
                Text(
                    "\(Int(buffer.wrappedValue)) ms"
                )
            }

            Slider(
                value: buffer,
                in: 40...600,
                step: 10
            )
            .disabled(isReceiving)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section("Diagnostics") {
            if isStreaming {
                LabeledContent(
                    "TX callback",
                    value:
                        "\(callbackFrames) frames"
                )

                LabeledContent(
                    "TX I/O",
                    value:
                        String(
                            format:
                                "%.2f ms",
                            actualIOBufferMS
                        )
                )

                LabeledContent(
                    "Capture",
                    value:
                        String(
                            format:
                                "%.1f Hz",
                            measuredCaptureHz
                        )
                )

                LabeledContent(
                    "TX rate",
                    value:
                        String(
                            format:
                                "%.1f Hz",
                            effectiveTXHz
                        )
                )

                LabeledContent(
                    "TX network max gap",
                    value:
                        String(
                            format:
                                "%.2f ms",
                            maxSendGapMS
                        )
                )

                LabeledContent(
                    "Mic callback max gap",
                    value:
                        String(
                            format:
                                "%.2f ms",
                            maxCaptureGapMS
                        )
                )

                LabeledContent(
                    "Mic gaps >10 ms",
                    value: "\(gapsOver10)"
                )

                LabeledContent(
                    "Mic gaps >15 ms",
                    value: "\(gapsOver15)"
                )

                LabeledContent(
                    "Mic gaps >25 ms",
                    value: "\(gapsOver25)"
                )

                LabeledContent(
                    "Mic gaps >50 ms",
                    value: "\(gapsOver50)"
                )

                LabeledContent(
                    "TX queue",
                    value:
                        "\(captureRingFrames) frames"
                )

                LabeledContent(
                    "TX queue overruns",
                    value:
                        "\(captureRingOverruns)"
                )

                LabeledContent(
                    "TX wake lifetime max",
                    value:
                        String(
                            format:
                                "%.2f ms",
                            txWakeMaxGapMS
                        )
                )

                LabeledContent(
                    "TX late wakes",
                    value:
                        "\(txLateWakeCount)"
                )

                LabeledContent(
                    "TX stale packets dropped",
                    value:
                        "\(txCatchUpPackets)"
                )

                LabeledContent(
                    "TX target",
                    value:
                        String(
                            format:
                                "%.1f ms",
                            Double(txTargetFrames) /
                            VBANPacket.sampleRate *
                            1000
                        )
                )

                LabeledContent(
                    "Audio Workgroup",
                    value:
                        audioWorkgroupJoined
                        ? "Joined"
                        : "Unavailable"
                )

                LabeledContent(
                    "TX send errors",
                    value: "\(sendErrors)"
                )

                LabeledContent(
                    "TX packets",
                    value: "\(packetsSent)"
                )
            }

            if isReceiving {
                LabeledContent(
                    "RX rejected",
                    value: "\(rxRejected)"
                )
            }

            if !isStreaming &&
                !isReceiving {
                Text(
                    "TX and RX are both stopped."
                )
                .foregroundStyle(.secondary)
            }

            Text(
                "Mic TX and speaker RX are independent: either can run alone, " +
                "or both can run at the same time."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Preset models

    private var currentTXPreset: VBANPreset {
        switch selectedTXPreset {
        case 1:
            return makeTXPreset(
                name: p2Name,
                host: p2Host,
                portText: p2Port,
                stream: p2Stream,
                fallback:
                    "Preset 2"
            )
        case 2:
            return makeTXPreset(
                name: p3Name,
                host: p3Host,
                portText: p3Port,
                stream: p3Stream,
                fallback:
                    "Preset 3"
            )
        default:
            return makeTXPreset(
                name: p1Name,
                host: p1Host,
                portText: p1Port,
                stream: p1Stream,
                fallback:
                    "Preset 1"
            )
        }
    }

    private var currentRXPreset:
        VBANReceivePreset {
        switch selectedRXPreset {
        case 1:
            return makeRXPreset(
                name: rx2Name,
                portText: rx2Port,
                stream: rx2Stream,
                buffer: rx2Buffer,
                fallback: "RX 2"
            )
        case 2:
            return makeRXPreset(
                name: rx3Name,
                portText: rx3Port,
                stream: rx3Stream,
                buffer: rx3Buffer,
                fallback: "RX 3"
            )
        default:
            return makeRXPreset(
                name: rx1Name,
                portText: rx1Port,
                stream: rx1Stream,
                buffer: rx1Buffer,
                fallback: "RX 1"
            )
        }
    }

    private func makeTXPreset(
        name: String,
        host: String,
        portText: String,
        stream: String,
        fallback: String
    ) -> VBANPreset {
        VBANPreset(
            name:
                name.isEmpty
                ? fallback
                : name,
            host:
                host.trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
            port:
                UInt16(portText)
                ?? 6980,
            streamName:
                stream
        )
    }

    private func makeRXPreset(
        name: String,
        portText: String,
        stream: String,
        buffer: Double,
        fallback: String
    ) -> VBANReceivePreset {
        VBANReceivePreset(
            name:
                name.isEmpty
                ? fallback
                : name,
            port:
                UInt16(portText)
                ?? 6980,
            streamName: stream,
            bufferMS: buffer
        )
    }

    // MARK: - Actions

    private func startTX() async {
        let preset =
            currentTXPreset

        guard !preset.host.isEmpty else {
            txStatus =
                "Enter PC IPv4."
            return
        }

        let granted =
            await requestMicrophonePermission()

        guard granted else {
            txStatus =
                "Microphone permission denied."
            return
        }

        do {
            let mode =
                VBANTransmissionMode(
                    rawValue:
                        transmissionModeRaw
                ) ?? .automatic

            try await MisMeeterRuntime.shared
                .start(
                    preset: preset,
                    gainDB: Float(gainDB),
                    transmissionMode: mode,
                    captureMode:
                        CaptureMode(
                            rawValue:
                                captureModeRaw
                        ) ??
                        .remoteIORaw
                )

            isStreaming = true
            isMuted = false
            txStatus = "Streaming VBAN"
        } catch {
            txStatus =
                error.localizedDescription
        }
    }

    private func stopTX() async {
        await MisMeeterRuntime.shared
            .stop()

        await MainActor.run {
            isStreaming = false
            meter = 0
            txStatus = "TX stopped"
        }
    }

    private func startRX() {
        do {
            try MisMeeterRuntime.shared
                .startReceiving(
                    preset:
                        currentRXPreset
                )

            isReceiving = true
            rxStatus =
                "Listening for \(currentRXPreset.sanitizedStreamName)"
        } catch {
            rxStatus =
                error.localizedDescription
        }
    }

    private func stopRX() {
        MisMeeterRuntime.shared
            .stopReceiving()

        isReceiving = false
        rxStatus = "RX stopped"
        rxBufferedFrames = 0
        rxPrimed = false
        rxPlaybackRate = 1.0
        rxAdaptiveTargetMS =
            currentRXPreset.bufferMS
    }

    private func requestMicrophonePermission()
        async -> Bool {
        await withCheckedContinuation {
            continuation in

            AVAudioSession.sharedInstance()
                .requestRecordPermission {
                    granted in

                    continuation.resume(
                        returning: granted
                    )
                }
        }
    }

    // MARK: - Runtime callbacks

    private func wireRuntimeCallbacks() {
        MisMeeterRuntime.shared
            .onStatusChange = { value in
                DispatchQueue.main.async {
                    txStatus = value
                }
            }

        MisMeeterRuntime.shared
            .onMeter = { value in
                DispatchQueue.main.async {
                    meter =
                        isMuted
                        ? 0
                        : value
                }
            }

        MisMeeterRuntime.shared
            .onPacketsSent = { value in
                DispatchQueue.main.async {
                    packetsSent = value
                }
            }

        MisMeeterRuntime.shared
            .onUnderruns = { value in
                DispatchQueue.main.async {
                    sendErrors = value
                }
            }

        MisMeeterRuntime.shared
            .onAudioDiagnostics = {
                frames,
                duration in

                DispatchQueue.main.async {
                    callbackFrames =
                        frames
                    actualIOBufferMS =
                        duration * 1000
                }
            }

        MisMeeterRuntime.shared
            .onCaptureGap = {
                gapMS in

                DispatchQueue.main.async {
                    maxCaptureGapMS =
                        gapMS
                }
            }

        MisMeeterRuntime.shared
            .onCaptureLabDiagnostics = {
                maxGap,
                over10,
                over15,
                over25,
                over50,
                buffered,
                overruns,
                wakeGap,
                lateWakes,
                catchUps,
                targetFrames in

                DispatchQueue.main.async {
                    maxCaptureGapMS =
                        maxGap

                    gapsOver10 =
                        over10
                    gapsOver15 =
                        over15
                    gapsOver25 =
                        over25
                    gapsOver50 =
                        over50

                    captureRingFrames =
                        buffered

                    captureRingOverruns =
                        overruns

                    txWakeMaxGapMS =
                        wakeGap

                    txLateWakeCount =
                        lateWakes

                    txCatchUpPackets =
                        catchUps

                    txTargetFrames =
                        targetFrames
                }
            }

        MisMeeterRuntime.shared
            .onPLLStats = {
                _,
                captureHz,
                txHz,
                _,
                _ in

                DispatchQueue.main.async {
                    measuredCaptureHz =
                        captureHz
                    effectiveTXHz =
                        txHz
                }
            }

        MisMeeterRuntime.shared
            .onTransportMode = {
                _,
                _,
                _,
                gapMS in

                DispatchQueue.main.async {
                    maxSendGapMS =
                        gapMS
                }
            }

        MisMeeterRuntime.shared
            .onVoiceProcessingState = {
                enabled in

                DispatchQueue.main.async {
                    voiceProcessingActive =
                        enabled
                }
            }

        MisMeeterRuntime.shared
            .onAudioWorkgroupState = {
                joined in

                DispatchQueue.main.async {
                    audioWorkgroupJoined =
                        joined
                }
            }

        MisMeeterRuntime.shared
            .onReceiverStatus = {
                value in

                DispatchQueue.main.async {
                    rxStatus = value
                }
            }

        MisMeeterRuntime.shared
            .onReceiverDiagnostics = {
                received,
                rejected,
                lost,
                buffered,
                underflows,
                primed,
                rate,
                targetMS in

                DispatchQueue.main.async {
                    rxPackets = received
                    rxRejected = rejected
                    rxLost = lost
                    rxBufferedFrames =
                        buffered
                    rxUnderflows =
                        underflows
                    rxPrimed = primed
                    rxPlaybackRate = rate
                    rxAdaptiveTargetMS =
                        targetMS
                }
            }
    }

    private func updateScenePhase(
        _ phase: ScenePhase
    ) {
        switch phase {
        case .active:
            MisMeeterRuntime.shared
                .enterForegroundTransport()

        case .inactive:
            MisMeeterRuntime.shared
                .beginLockTransition()

        case .background:
            MisMeeterRuntime.shared
                .enterBackgroundTransport()

        @unknown default:
            break
        }
    }
}
