import AVFoundation
import SwiftUI

struct ContentView: View {
    @AppStorage("selectedPreset") private var selectedPreset = 0

    @AppStorage("p1Name") private var p1Name = "Preset 1"
    @AppStorage("p1Host") private var p1Host = ""
    @AppStorage("p1Port") private var p1Port = "6980"
    @AppStorage("p1Stream") private var p1Stream = "MisMeeter"

    @AppStorage("p2Name") private var p2Name = "Preset 2"
    @AppStorage("p2Host") private var p2Host = ""
    @AppStorage("p2Port") private var p2Port = "6980"
    @AppStorage("p2Stream") private var p2Stream = "MisMeeter2"

    @AppStorage("p3Name") private var p3Name = "Preset 3"
    @AppStorage("p3Host") private var p3Host = ""
    @AppStorage("p3Port") private var p3Port = "6980"
    @AppStorage("p3Stream") private var p3Stream = "MisMeeter3"

    @AppStorage("microphoneGainDB") private var gainDB = 12.0
    @AppStorage("transmissionModeV08") private var transmissionModeRaw = VBANTransmissionMode.automatic.rawValue
    @AppStorage("appleVoiceProcessing") private var appleVoiceProcessing = false

    @State private var isStreaming = MisMeeterRuntime.shared.isStreaming
    @State private var isMuted = MisMeeterRuntime.shared.isMuted
    @State private var status = "Ready"
    @State private var meter: Float = 0
    @State private var bufferSamples = 0
    @State private var packetsSent: UInt64 = 0
    @State private var callbackFrames = 0
    @State private var actualIOBufferMS = 0.0
    @State private var underruns: UInt64 = 0
    @State private var senderPrimed = false
    @State private var adaptiveLatencyMS = 150.0
    @State private var measuredCaptureHz = 48000.0
    @State private var effectiveTXHz = 48000.0
    @State private var schedulerLateMS = 0.0
    @State private var catchUpPackets: UInt64 = 0
    @State private var voiceProcessingActive = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    Picker("Active preset", selection: $selectedPreset) {
                        Text(p1Name.isEmpty ? "Preset 1" : p1Name).tag(0)
                        Text(p2Name.isEmpty ? "Preset 2" : p2Name).tag(1)
                        Text(p3Name.isEmpty ? "Preset 3" : p3Name).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isStreaming)

                    presetEditor
                }

                Section("Transport") {
                    LabeledContent("Clock", value: "AVAudioSinkNode realtime")
                    Text(
                        "The VBAN sender now follows the realtime Core Audio input render clock. " +
                        "It does not depend on a DispatchSourceTimer, so screen lock should not fragment packet timing."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Audio processing") {
                    Toggle(
                        "Apple Voice Processing",
                        isOn: $appleVoiceProcessing
                    )
                    .disabled(isStreaming)

                    Text(
                        "Uses Apple's VoiceProcessingIO DSP for speech: noise suppression, " +
                        "automatic gain processing and echo cancellation. " +
                        "It can change the tonal character of the microphone. Stop VBAN before changing it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if isStreaming {
                        LabeledContent(
                            "Voice Processing active",
                            value: voiceProcessingActive ? "Yes" : "No"
                        )
                    }
                }

                Section("Microphone") {
                    HStack {
                        Image(
                            systemName: isMuted
                                ? "mic.slash.fill"
                                : "mic.fill"
                        )
                        .font(.title2)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(isMuted ? "Muted" : "Live")
                                .font(.headline)

                            ProgressView(value: Double(meter))
                        }
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Software gain")
                            Spacer()
                            Text("+\(Int(gainDB)) dB")
                                .monospacedDigit()
                        }

                        Slider(
                            value: $gainDB,
                            in: 0...24,
                            step: 1
                        )
                        .onChange(of: gainDB) { _, newValue in
                            MisMeeterRuntime.shared.gainDB = Float(newValue)
                        }
                    }

                    Button {
                        toggleMuteFromApp()
                    } label: {
                        Label(
                            isMuted ? "Unmute microphone" : "Mute microphone",
                            systemImage: isMuted ? "mic.fill" : "mic.slash.fill"
                        )
                    }
                    .disabled(!isStreaming)
                }

                Section {
                    Button {
                        Task {
                            if isStreaming {
                                await stopStreaming()
                            } else {
                                await startStreaming()
                            }
                        }
                    } label: {
                        Label(
                            isStreaming ? "Stop VBAN" : "Start VBAN",
                            systemImage: isStreaming
                                ? "stop.fill"
                                : "dot.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }

                Section("Status") {
                    Text(status)

                    if isStreaming {
                        let preset = currentPreset

                        LabeledContent("Preset", value: preset.name)
                        LabeledContent("Stream", value: preset.sanitizedStreamName)
                        LabeledContent("Destination", value: preset.destinationLabel)
                        LabeledContent("Format", value: "48 kHz • PCM16 • Mono")
                        LabeledContent("Packet", value: "256 samples • 5.33 ms")
                        LabeledContent("Sender buffer", value: "\(bufferSamples) samples")
                        LabeledContent("Input callback", value: "\(callbackFrames) frames")
                        LabeledContent(
                            "Actual I/O buffer",
                            value: String(format: "%.2f ms", actualIOBufferMS)
                        )
                        LabeledContent("Sender primed", value: senderPrimed ? "Yes" : "No")
                        LabeledContent("Sender target", value: "Realtime")
                        LabeledContent("Capture rate", value: String(format: "%.1f Hz", measuredCaptureHz))
                        LabeledContent("TX rate", value: String(format: "%.1f Hz", effectiveTXHz))
                        LabeledContent("Software scheduler", value: "Disabled")
                        LabeledContent("Capture clock", value: "Audio realtime")
                        LabeledContent("Underruns", value: "\(underruns)")
                        LabeledContent("Packets sent", value: "\(packetsSent)")
                    }
                }

                Section {
                    Text(
                        "v0.9 uses AVAudioSinkNode as the realtime capture/packet clock. " +
                        "This removes the background-sensitive software timer entirely."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("MisMeeter")
            .onAppear {
                wireRuntimeCallbacks()
                MisMeeterRuntime.shared.gainDB = Float(gainDB)
            }
        }
    }

    @ViewBuilder
    private var presetEditor: some View {
        switch selectedPreset {
        case 1:
            presetFields(
                name: $p2Name,
                host: $p2Host,
                port: $p2Port,
                stream: $p2Stream
            )
        case 2:
            presetFields(
                name: $p3Name,
                host: $p3Host,
                port: $p3Port,
                stream: $p3Stream
            )
        default:
            presetFields(
                name: $p1Name,
                host: $p1Host,
                port: $p1Port,
                stream: $p1Stream
            )
        }
    }

    @ViewBuilder
    private func presetFields(
        name: Binding<String>,
        host: Binding<String>,
        port: Binding<String>,
        stream: Binding<String>
    ) -> some View {
        TextField("Preset name", text: name)
            .disabled(isStreaming)

        TextField("PC IPv4 / hostname", text: host)
            .textInputAutocapitalization(.never)
            .keyboardType(.numbersAndPunctuation)
            .disabled(isStreaming)

        TextField("UDP port", text: port)
            .keyboardType(.numberPad)
            .disabled(isStreaming)

        TextField("VBAN stream name", text: stream)
            .textInputAutocapitalization(.never)
            .disabled(isStreaming)

        Text("VBAN stream names are limited to 16 ASCII characters.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var currentPreset: VBANPreset {
        switch selectedPreset {
        case 1:
            return makePreset(
                name: p2Name,
                host: p2Host,
                portText: p2Port,
                stream: p2Stream,
                fallbackName: "Preset 2"
            )
        case 2:
            return makePreset(
                name: p3Name,
                host: p3Host,
                portText: p3Port,
                stream: p3Stream,
                fallbackName: "Preset 3"
            )
        default:
            return makePreset(
                name: p1Name,
                host: p1Host,
                portText: p1Port,
                stream: p1Stream,
                fallbackName: "Preset 1"
            )
        }
    }

    private func makePreset(
        name: String,
        host: String,
        portText: String,
        stream: String,
        fallbackName: String
    ) -> VBANPreset {
        VBANPreset(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallbackName
                : name,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: UInt16(portText) ?? 6980,
            streamName: stream.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func wireRuntimeCallbacks() {
        MisMeeterRuntime.shared.onStatusChange = { value in
            DispatchQueue.main.async {
                status = value
            }
        }

        MisMeeterRuntime.shared.onMeter = { value in
            DispatchQueue.main.async {
                meter = isMuted ? 0 : value
            }
        }

        MisMeeterRuntime.shared.onBufferLevel = { value in
            DispatchQueue.main.async {
                bufferSamples = value
            }
        }

        MisMeeterRuntime.shared.onAudioDiagnostics = { frames, duration in
            DispatchQueue.main.async {
                callbackFrames = frames
                actualIOBufferMS = duration * 1000
            }
        }

        MisMeeterRuntime.shared.onUnderruns = { value in
            DispatchQueue.main.async {
                underruns = value
            }
        }

        MisMeeterRuntime.shared.onPacketsSent = { value in
            DispatchQueue.main.async {
                packetsSent = value
            }
        }

        MisMeeterRuntime.shared.onPrimedChange = { value in
            DispatchQueue.main.async { senderPrimed = value }
        }
        MisMeeterRuntime.shared.onPLLStats = { targetMS, captureHz, txHz, lateMS, catchUps in
            DispatchQueue.main.async {
                adaptiveLatencyMS = targetMS
                measuredCaptureHz = captureHz
                effectiveTXHz = txHz
                schedulerLateMS = lateMS
                catchUpPackets = catchUps
            }
        }

        MisMeeterRuntime.shared.onVoiceProcessingState = { enabled in
            DispatchQueue.main.async {
                voiceProcessingActive = enabled
            }
        }
    }

    private func startStreaming() async {
        let preset = currentPreset

        guard !preset.host.isEmpty else {
            status = "Enter the Windows PC IPv4 address."
            return
        }

        guard !preset.streamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Enter a VBAN stream name."
            return
        }

        let granted = await requestMicrophonePermission()
        guard granted else {
            status = "Microphone permission denied."
            return
        }

        do {
            let mode = VBANTransmissionMode(
                rawValue: transmissionModeRaw
            ) ?? .balanced

            try await MisMeeterRuntime.shared.start(
                preset: preset,
                gainDB: Float(gainDB),
                transmissionMode: mode,
                voiceProcessingEnabled: appleVoiceProcessing
            )

            isStreaming = true
            isMuted = false
            status = "Streaming VBAN"
        } catch {
            status = error.localizedDescription
            isStreaming = false
        }
    }

    private func stopStreaming() async {
        await MisMeeterRuntime.shared.stop()

        await MainActor.run {
            isStreaming = false
            isMuted = MisMeeterRuntime.shared.isMuted
            meter = 0
            bufferSamples = 0
            packetsSent = 0
            callbackFrames = 0
            actualIOBufferMS = 0
            underruns = 0
            senderPrimed = false
            adaptiveLatencyMS = 0
            measuredCaptureHz = 48000
            effectiveTXHz = 48000
            schedulerLateMS = 0
            catchUpPackets = 0
            voiceProcessingActive = false
            status = "Stopped"
        }
    }

    private func toggleMuteFromApp() {
        isMuted = MisMeeterRuntime.shared.toggleMuted()

        Task {
            await MisMeeterRuntime.shared.syncLiveActivity()
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
