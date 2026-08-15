import AVFoundation
import SwiftUI

struct ContentView: View {
    @AppStorage("vbanHost") private var host = ""
    @AppStorage("vbanPort") private var portText = "6980"
    @AppStorage("vbanStreamName") private var streamName = "MisMeeter"

    @State private var isStreaming = MisMeeterRuntime.shared.isStreaming
    @State private var isMuted = MisMeeterRuntime.shared.isMuted
    @State private var status = "Ready"
    @State private var meter: Float = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("VBAN destination") {
                    TextField("PC IPv4, e.g. 192.168.1.50", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                        .disabled(isStreaming)

                    TextField("UDP port", text: $portText)
                        .keyboardType(.numberPad)
                        .disabled(isStreaming)

                    TextField("Stream name", text: $streamName)
                        .textInputAutocapitalization(.never)
                        .disabled(isStreaming)

                    Text("VoiceMeeter VBAN IN must use the same stream name. Default port: 6980.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Microphone") {
                    HStack {
                        Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text(isMuted ? "Muted" : "Live")
                                .font(.headline)
                            ProgressView(value: Double(meter))
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
                            systemImage: isStreaming ? "stop.fill" : "dot.radiowaves.left.and.right"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }

                Section("Status") {
                    Text(status)
                    if isStreaming {
                        LabeledContent("Format", value: "48 kHz • PCM16 • Mono")
                        LabeledContent("Destination", value: "\(host):\(portText)")
                        LabeledContent("VBAN stream", value: streamName)
                    }
                }

                Section {
                    Text("Mute changes the actual VBAN audio immediately. ActivityKit may redraw the Lock Screen / Dynamic Island slightly later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("MisMeeter")
            .onAppear { wireRuntimeCallbacks() }
        }
    }

    private func wireRuntimeCallbacks() {
        MisMeeterRuntime.shared.onStatusChange = { value in
            DispatchQueue.main.async { status = value }
        }

        MisMeeterRuntime.shared.onMeter = { value in
            DispatchQueue.main.async { meter = isMuted ? 0 : value }
        }
    }

    private func startStreaming() async {
        let cleanedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedHost.isEmpty else {
            status = "Enter the Windows PC IPv4 address."
            return
        }
        guard let port = UInt16(portText), port > 0 else {
            status = "Invalid UDP port."
            return
        }
        guard !streamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = "Enter a VBAN stream name."
            return
        }

        let granted = await requestMicrophonePermission()
        guard granted else {
            status = "Microphone permission denied."
            return
        }

        do {
            try await MisMeeterRuntime.shared.start(
                host: cleanedHost,
                port: port,
                streamName: streamName
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
        isStreaming = false
        isMuted = MisMeeterRuntime.shared.isMuted
        meter = 0
        status = "Stopped"
    }

    private func toggleMuteFromApp() {
        isMuted = MisMeeterRuntime.shared.toggleMuted()
        Task {
            await MisMeeterRuntime.shared.syncLiveActivity(
                destinationLabel: "\(host):\(portText)"
            )
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
