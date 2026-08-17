import AVFoundation
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("selectedPreset") private var selectedTXPreset = 0
    @AppStorage("p1Name") private var p1Name = "Studio"
    @AppStorage("p1Host") private var p1Host = ""
    @AppStorage("p1Port") private var p1Port = "6980"
    @AppStorage("p1Stream") private var p1Stream = "MisMeeter"
    @AppStorage("p2Name") private var p2Name = "Office"
    @AppStorage("p2Host") private var p2Host = ""
    @AppStorage("p2Port") private var p2Port = "6980"
    @AppStorage("p2Stream") private var p2Stream = "MisMeeter2"
    @AppStorage("p3Name") private var p3Name = "Mobile"
    @AppStorage("p3Host") private var p3Host = ""
    @AppStorage("p3Port") private var p3Port = "6980"
    @AppStorage("p3Stream") private var p3Stream = "MisMeeter3"

    @AppStorage("microphoneGainDB") private var gainDB = 12.0
    @AppStorage("captureModeV21") private var captureModeRaw = CaptureMode.voiceProcessingIO.rawValue
    @AppStorage("transmissionModeV08") private var transmissionModeRaw = VBANTransmissionMode.automatic.rawValue

    @AppStorage("selectedRXPreset") private var selectedRXPreset = 0
    @AppStorage("rx1Name") private var rx1Name = "Main"
    @AppStorage("rx1Port") private var rx1Port = "6980"
    @AppStorage("rx1Stream") private var rx1Stream = "PC-Main"
    @AppStorage("rx1Buffer") private var rx1Buffer = 100.0
    @AppStorage("rx2Name") private var rx2Name = "Aux"
    @AppStorage("rx2Port") private var rx2Port = "6980"
    @AppStorage("rx2Stream") private var rx2Stream = "PC-Aux"
    @AppStorage("rx2Buffer") private var rx2Buffer = 100.0
    @AppStorage("rx3Name") private var rx3Name = "Other"
    @AppStorage("rx3Port") private var rx3Port = "6980"
    @AppStorage("rx3Stream") private var rx3Stream = "PC-Other"
    @AppStorage("rx3Buffer") private var rx3Buffer = 100.0

    @State private var isStreaming = MisMeeterRuntime.shared.isStreaming
    @State private var isMuted = MisMeeterRuntime.shared.isMuted
    @State private var isReceiving = MisMeeterRuntime.shared.isReceiving
    @State private var txStatus = "Ready"
    @State private var rxStatus = "Ready"
    @State private var meter: Float = 0
    @State private var packetsSent: UInt64 = 0
    @State private var sendErrors: UInt64 = 0
    @State private var maxSendGapMS = 0.0
    @State private var maxCaptureGapMS = 0.0
    @State private var actualIOBufferMS = 0.0
    @State private var callbackFrames = 0
    @State private var measuredCaptureHz = 48_000.0
    @State private var effectiveTXHz = 48_000.0
    @State private var voiceProcessingActive = false
    @State private var rxPackets: UInt64 = 0
    @State private var rxLost: UInt64 = 0
    @State private var rxUnderflows: UInt64 = 0
    @State private var rxBufferedFrames = 0
    @State private var rxPlaybackRate: Float = 1
    @State private var rxAdaptiveTargetMS = 100.0
    @State private var alertMessage: String?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { homeView }
                .tabItem { Label("Home", systemImage: "waveform.circle.fill") }
                .tag(0)

            NavigationStack { routesView }
                .tabItem { Label("Routes", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(1)

            NavigationStack { monitorView }
                .tabItem { Label("Monitor", systemImage: "chart.xyaxis.line") }
                .tag(2)

            NavigationStack { settingsView }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(3)
        }
        .tint(.accentColor)
        .onAppear {
            wireRuntimeCallbacks()
            MisMeeterRuntime.shared.gainDB = Float(gainDB)
            Task { await MisMeeterRuntime.shared.cleanupOrphanedLiveActivitiesIfIdle() }
            updateScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { _, phase in updateScenePhase(phase) }
        .onOpenURL { _ in selectedTab = 0 }
        .alert("MisMeeter", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var homeView: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                audioLevelCard
                HStack(spacing: 12) {
                    compactStatusCard(title: "TX", value: txStatus, icon: "arrow.up.circle.fill", active: isStreaming)
                    compactStatusCard(title: "RX", value: rxStatus, icon: "arrow.down.circle.fill", active: isReceiving)
                }
                liveSurfaceCard
            }
            .padding(16)
        }
        .background(appBackground)
        .navigationTitle("MisMeeter")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { selectedTab = 3 } label: { Image(systemName: "gearshape") }
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isStreaming ? (isMuted ? "Microphone muted" : "On air") : "Ready to connect")
                        .font(.title2.weight(.bold))
                    Text(currentTXPreset.destinationLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                statusPill
            }

            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 14)
                    .frame(width: 148, height: 148)
                Circle()
                    .trim(from: 0, to: isStreaming ? CGFloat(max(0.08, min(1, meter))) : 0.06)
                    .stroke(
                        isMuted ? Color.orange : (isStreaming ? Color.green : Color.secondary),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 148, height: 148)
                    .animation(.smooth(duration: 0.22), value: meter)
                Image(systemName: isMuted ? "mic.slash.fill" : (isStreaming ? "waveform" : "mic.fill"))
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(isMuted ? .orange : (isStreaming ? .green : .primary))
                    .contentTransition(.symbolEffect(.replace))
            }

            if isStreaming {
                HStack(spacing: 12) {
                    Button {
                        isMuted = MisMeeterRuntime.shared.toggleMuted()
                    } label: {
                        Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "mic.fill" : "mic.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        Task { await stopTX() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                Button {
                    Task { await startTX() }
                } label: {
                    Label("Start microphone stream", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(20)
        .glassCard()
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isStreaming ? (isMuted ? Color.orange : Color.green) : Color.secondary)
                .frame(width: 8, height: 8)
            Text(isStreaming ? (isMuted ? "MUTED" : "LIVE") : "IDLE")
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }

    private var audioLevelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Microphone level", systemImage: "waveform")
                    .font(.headline)
                Spacer()
                Text("+\(Int(gainDB)) dB")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(meter > 0.85 ? Color.orange : Color.green)
                        .frame(width: proxy.size.width * CGFloat(max(0.01, min(1, meter))))
                        .animation(.linear(duration: 0.08), value: meter)
                }
            }
            .frame(height: 9)
        }
        .padding(18)
        .glassCard()
    }

    private func compactStatusCard(title: String, value: String, icon: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(active ? .green : .secondary)
                Spacer()
                Circle().fill(active ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
            }
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard()
    }

    private var liveSurfaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live surfaces", systemImage: "platter.filled.top.and.arrow.up.iphone")
                .font(.headline)
            Text("Live Activity, Dynamic Island and the Home/Lock Screen widget mirror the current stream and expose Mute and Stop while TX is active.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                surfaceBadge("Live Activity", "bolt.horizontal.circle")
                surfaceBadge("Widget", "square.grid.2x2")
                surfaceBadge("Island", "capsule")
            }
        }
        .padding(18)
        .glassCard()
    }

    private func surfaceBadge(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var routesView: some View {
        Form {
            Section {
                Picker("TX preset", selection: $selectedTXPreset) {
                    Text(p1Name).tag(0); Text(p2Name).tag(1); Text(p3Name).tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(isStreaming)

                TextField("Preset name", text: txNameBinding)
                TextField("Destination IPv4", text: txHostBinding)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("UDP port", text: txPortBinding)
                    .keyboardType(.numberPad)
                TextField("VBAN stream", text: txStreamBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Label("Microphone → VBAN", systemImage: "mic.and.signal.meter")
            } footer: {
                Text("Use the destination iPv4 of the VoiceMeeter host. UDP transmission is clocked directly by Core Audio for stable lock-screen behavior.")
            }

            Section {
                Button {
                    Task { isStreaming ? await stopTX() : await startTX() }
                } label: {
                    Label(isStreaming ? "Stop TX" : "Start TX", systemImage: isStreaming ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Section {
                Picker("RX preset", selection: $selectedRXPreset) {
                    Text(rx1Name).tag(0); Text(rx2Name).tag(1); Text(rx3Name).tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(isReceiving)

                TextField("Preset name", text: rxNameBinding)
                TextField("Listen port", text: rxPortBinding).keyboardType(.numberPad)
                TextField("VBAN stream", text: rxStreamBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                VStack(alignment: .leading) {
                    HStack {
                        Text("Jitter buffer")
                        Spacer()
                        Text("\(Int(rxBufferBinding.wrappedValue)) ms").foregroundStyle(.secondary)
                    }
                    Slider(value: rxBufferBinding, in: 40...600, step: 10)
                }
            } header: {
                Label("VBAN → iPhone", systemImage: "speaker.wave.3.fill")
            }

            Section {
                Button {
                    isReceiving ? stopRX() : startRX()
                } label: {
                    Label(isReceiving ? "Stop listening" : "Start listening", systemImage: isReceiving ? "stop.fill" : "ear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Routes")
    }

    private var monitorView: some View {
        ScrollView {
            VStack(spacing: 14) {
                diagnosticGroup(title: "Transport", icon: "network") {
                    metric("Packets sent", packetsSent.formatted())
                    metric("Send errors", sendErrors.formatted())
                    metric("Max TX gap", String(format: "%.2f ms", maxSendGapMS))
                    metric("Capture rate", String(format: "%.1f Hz", measuredCaptureHz))
                    metric("TX rate", String(format: "%.1f Hz", effectiveTXHz))
                }

                diagnosticGroup(title: "Core Audio", icon: "waveform.badge.mic") {
                    metric("Callback", "\(callbackFrames) frames")
                    metric("I/O buffer", String(format: "%.2f ms", actualIOBufferMS))
                    metric("Max callback gap", String(format: "%.2f ms", maxCaptureGapMS))
                    metric("Voice processing", voiceProcessingActive ? "Active" : "Raw RemoteIO")
                    metric("TX clock", "Audio callback")
                }

                diagnosticGroup(title: "Receiver", icon: "speaker.wave.2") {
                    metric("Packets", rxPackets.formatted())
                    metric("Lost", rxLost.formatted())
                    metric("Underflows", rxUnderflows.formatted())
                    metric("Buffered", "\(rxBufferedFrames) frames")
                    metric("Clock correction", String(format: "%.4fx", rxPlaybackRate))
                    metric("Adaptive target", String(format: "%.0f ms", rxAdaptiveTargetMS))
                }
            }
            .padding(16)
        }
        .background(appBackground)
        .navigationTitle("Monitor")
    }

    private func diagnosticGroup<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(18)
        .glassCard()
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.medium))
        }
    }

    private var settingsView: some View {
        Form {
            Section("Microphone") {
                Picker("Capture engine", selection: $captureModeRaw) {
                    ForEach(CaptureMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                }
                .disabled(isStreaming)

                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Input gain"); Spacer(); Text("+\(Int(gainDB)) dB").foregroundStyle(.secondary) }
                    Slider(value: $gainDB, in: 0...24, step: 1)
                        .onChange(of: gainDB) { _, value in MisMeeterRuntime.shared.gainDB = Float(value) }
                }
            }

            Section("Background reliability") {
                Label("Audio-clocked nonblocking UDP", systemImage: "checkmark.seal.fill")
                Label("Audio background mode", systemImage: "lock.shield.fill")
                Text("The TX path has no GCD timer, semaphore worker or catch-up burst between Core Audio and VBAN.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("System surfaces") {
                Label("Live Activity + Dynamic Island", systemImage: "capsule.fill")
                Label("Home & Lock Screen Widget", systemImage: "square.grid.2x2.fill")
                Text("Mute and Stop actions remain synchronized with the running audio process through the shared App Group control channel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "3.0.0")
                LabeledContent("Audio", value: "48 kHz / PCM16 / VBAN")
                LabeledContent("Minimum iOS", value: "17.0")
                LabeledContent("Optimized SDK", value: "iOS 26 / Xcode 26.6")
            }
        }
        .navigationTitle("Settings")
    }

    private var appBackground: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.10), Color.clear, Color.primary.opacity(0.025)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func startTX() async {
        let preset = currentTXPreset
        guard !preset.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertMessage = "Enter the VoiceMeeter destination IPv4 address first."
            selectedTab = 1
            return
        }
        do {
            try await MisMeeterRuntime.shared.start(
                preset: preset,
                gainDB: Float(gainDB),
                transmissionMode: VBANTransmissionMode(rawValue: transmissionModeRaw) ?? .automatic,
                captureMode: CaptureMode(rawValue: captureModeRaw) ?? .voiceProcessingIO
            )
            await MainActor.run {
                isStreaming = true
                isMuted = false
                txStatus = "Live"
            }
        } catch {
            await MainActor.run {
                isStreaming = false
                alertMessage = error.localizedDescription
            }
        }
    }

    private func stopTX() async {
        await MisMeeterRuntime.shared.stop()
        await MainActor.run {
            isStreaming = false
            isMuted = false
            meter = 0
            txStatus = "Ready"
        }
    }

    private func startRX() {
        do {
            try MisMeeterRuntime.shared.startReceiving(preset: currentRXPreset)
            isReceiving = true
            rxStatus = "Listening"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func stopRX() {
        MisMeeterRuntime.shared.stopReceiving()
        isReceiving = false
        rxStatus = "Ready"
    }

    private func wireRuntimeCallbacks() {
        let runtime = MisMeeterRuntime.shared
        runtime.onStatusChange = { value in DispatchQueue.main.async { txStatus = value } }
        runtime.onMeter = { value in DispatchQueue.main.async { meter = value } }
        runtime.onPacketsSent = { value in DispatchQueue.main.async { packetsSent = value } }
        runtime.onUnderruns = { value in DispatchQueue.main.async { sendErrors = value } }
        runtime.onAudioDiagnostics = { frames, duration in
            DispatchQueue.main.async { callbackFrames = frames; actualIOBufferMS = duration * 1000 }
        }
        runtime.onCaptureGap = { value in DispatchQueue.main.async { maxCaptureGapMS = value } }
        runtime.onPLLStats = { _, capture, tx, _, _ in
            DispatchQueue.main.async { measuredCaptureHz = capture; effectiveTXHz = tx }
        }
        runtime.onVoiceProcessingState = { value in DispatchQueue.main.async { voiceProcessingActive = value } }
        runtime.onTransportMode = { _, _, _, gap in DispatchQueue.main.async { maxSendGapMS = gap } }
        runtime.onReceiverStatus = { value in DispatchQueue.main.async { rxStatus = value } }
        runtime.onReceiverDiagnostics = { received, _, lost, buffered, underflows, _, rate, target in
            DispatchQueue.main.async {
                rxPackets = received; rxLost = lost; rxBufferedFrames = buffered
                rxUnderflows = underflows; rxPlaybackRate = rate; rxAdaptiveTargetMS = target
            }
        }
    }

    private func updateScenePhase(_ phase: ScenePhase) {
        guard MisMeeterRuntime.shared.isStreaming else { return }
        switch phase {
        case .active: MisMeeterRuntime.shared.enterForegroundTransport()
        case .inactive: MisMeeterRuntime.shared.beginLockTransition()
        case .background: MisMeeterRuntime.shared.enterBackgroundTransport()
        @unknown default: break
        }
    }

    private var currentTXPreset: VBANPreset {
        switch selectedTXPreset {
        case 1: return VBANPreset(name: p2Name, host: p2Host, port: UInt16(Int(p2Port) ?? 6980), streamName: p2Stream)
        case 2: return VBANPreset(name: p3Name, host: p3Host, port: UInt16(Int(p3Port) ?? 6980), streamName: p3Stream)
        default: return VBANPreset(name: p1Name, host: p1Host, port: UInt16(Int(p1Port) ?? 6980), streamName: p1Stream)
        }
    }

    private var currentRXPreset: VBANReceivePreset {
        switch selectedRXPreset {
        case 1: return VBANReceivePreset(name: rx2Name, port: UInt16(Int(rx2Port) ?? 6980), streamName: rx2Stream, bufferMS: rx2Buffer)
        case 2: return VBANReceivePreset(name: rx3Name, port: UInt16(Int(rx3Port) ?? 6980), streamName: rx3Stream, bufferMS: rx3Buffer)
        default: return VBANReceivePreset(name: rx1Name, port: UInt16(Int(rx1Port) ?? 6980), streamName: rx1Stream, bufferMS: rx1Buffer)
        }
    }

    private var txNameBinding: Binding<String> { selectedTXPreset == 1 ? $p2Name : (selectedTXPreset == 2 ? $p3Name : $p1Name) }
    private var txHostBinding: Binding<String> { selectedTXPreset == 1 ? $p2Host : (selectedTXPreset == 2 ? $p3Host : $p1Host) }
    private var txPortBinding: Binding<String> { selectedTXPreset == 1 ? $p2Port : (selectedTXPreset == 2 ? $p3Port : $p1Port) }
    private var txStreamBinding: Binding<String> { selectedTXPreset == 1 ? $p2Stream : (selectedTXPreset == 2 ? $p3Stream : $p1Stream) }
    private var rxNameBinding: Binding<String> { selectedRXPreset == 1 ? $rx2Name : (selectedRXPreset == 2 ? $rx3Name : $rx1Name) }
    private var rxPortBinding: Binding<String> { selectedRXPreset == 1 ? $rx2Port : (selectedRXPreset == 2 ? $rx3Port : $rx1Port) }
    private var rxStreamBinding: Binding<String> { selectedRXPreset == 1 ? $rx2Stream : (selectedRXPreset == 2 ? $rx3Stream : $rx1Stream) }
    private var rxBufferBinding: Binding<Double> { selectedRXPreset == 1 ? $rx2Buffer : (selectedRXPreset == 2 ? $rx3Buffer : $rx1Buffer) }
}

private extension View {
    func glassCard() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 0.7)
            }
    }
}
