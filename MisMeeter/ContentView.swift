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
    @State private var isReceiveMuted = MisMeeterRuntime.shared.isReceiveMuted
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
    @State private var selectedTab: AppSection = .transmit
    @FocusState private var isEditingPreset: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack { txHomeView }
                    .tag(AppSection.transmit)

                NavigationStack { rxHomeView }
                    .tag(AppSection.receive)

                NavigationStack { presetsView }
                    .tag(AppSection.presets)

                NavigationStack { settingsView }
                    .tag(AppSection.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.keyboard, edges: .bottom)

            if !isEditingPreset {
                floatingNavigation
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(.accentColor)
        .onAppear {
            wireRuntimeCallbacks()
            MisMeeterRuntime.shared.gainDB = Float(gainDB)
            reconcileRuntimeState()
            Task {
                await MisMeeterRuntime.shared.reconcileExternalControlState()
                await MisMeeterRuntime.shared.cleanupOrphanedLiveActivitiesIfIdle()
                await MainActor.run { reconcileRuntimeState() }
            }
            updateScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await MisMeeterRuntime.shared.reconcileExternalControlState()
                    await MainActor.run { reconcileRuntimeState() }
                }
            }
            updateScenePhase(phase)
        }
        .onOpenURL { _ in
            reconcileRuntimeState()
            selectedTab = .transmit
        }
        .alert("MisMeeter", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var floatingNavigation: some View {
        HStack(spacing: 4) {
            ForEach(AppSection.allCases) { item in
                Button {
                    withAnimation(.smooth(duration: 0.24)) { selectedTab = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(width: 54, height: 48)
                    .foregroundStyle(selectedTab == item ? Color.primary : Color.secondary)
                    .background {
                        if selectedTab == item {
                            Capsule()
                                .fill(Color.primary.opacity(0.075))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
                .shadow(color: Color.black.opacity(0.10), radius: 18, y: 8)
        }
    }

    private var txHomeView: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                audioLevelCard
                sendControlsCard
                HStack(spacing: 12) {
                    compactStatusCard(title: "TX", value: txStatus, icon: "arrow.up.circle.fill", active: isStreaming)
                    compactStatusCard(title: "RX", value: rxStatus, icon: "arrow.down.circle.fill", active: isReceiving)
                }
                sendQualityCard
            }
            .padding(16)
            .padding(.bottom, 92)
        }
        .background(appBackground)
        .navigationTitle("Send")
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
                txStatusPill
            }

            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.08), lineWidth: 14)
                    .frame(width: 148, height: 148)
                Circle()
                    .trim(from: 0, to: isStreaming ? CGFloat(max(0.08, min(1, meter))) : 0.06)
                    .stroke(
                        isMuted ? Color.red : (isStreaming ? Color.green : Color.secondary),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 148, height: 148)
                    .animation(.smooth(duration: 0.22), value: meter)
                Image(systemName: isMuted ? "mic.slash.fill" : (isStreaming ? "mic.fill" : "mic.fill"))
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(isMuted ? .red : (isStreaming ? .green : .primary))
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

    private var txStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isStreaming ? (isMuted ? Color.red : Color.green) : Color.secondary)
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

    private var sendControlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Send controls", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text(isStreaming ? "Locked while live" : "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Input gain", systemImage: "dial.medium.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("+\(Int(gainDB)) dB")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $gainDB, in: 0...24, step: 1)
                    .onChange(of: gainDB) { _, value in
                        MisMeeterRuntime.shared.gainDB = Float(value)
                    }
            }

            Divider().opacity(0.45)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Capture engine", systemImage: "waveform.badge.mic")
                        .font(.subheadline.weight(.semibold))
                    Text("Choose the Core Audio input path used by Send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("Capture engine", selection: $captureModeRaw) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isStreaming)
            }
        }
        .padding(18)
        .glassCard()
    }

    private var rxHomeView: some View {
        ScrollView {
            VStack(spacing: 18) {
                rxHeroCard
                rxBufferCard
                HStack(spacing: 12) {
                    compactStatusCard(title: "Packets", value: rxPackets.formatted(), icon: "shippingbox.fill", active: isReceiving)
                    compactStatusCard(title: "Underflows", value: rxUnderflows.formatted(), icon: "exclamationmark.triangle.fill", active: rxUnderflows == 0 && isReceiving)
                }
                receiverQualityCard
            }
            .padding(16)
            .padding(.bottom, 92)
        }
        .background(appBackground)
        .navigationTitle("Receive")
    }

    private var rxHeroCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isReceiving ? (isReceiveMuted ? "Receive muted" : "Listening") : "Ready to listen")
                        .font(.title2.weight(.bold))
                    Text("\(currentRXPreset.name) · \(currentRXPreset.streamName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(isReceiving ? (isReceiveMuted ? Color.red : Color.green) : Color.secondary).frame(width: 8, height: 8)
                    Text(isReceiving ? (isReceiveMuted ? "MUTED" : "LIVE") : "IDLE").font(.caption2.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
            }

            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 14).frame(width: 148, height: 148)
                Circle()
                    .trim(from: 0, to: isReceiving ? 0.82 : 0.06)
                    .stroke(isReceiving ? (isReceiveMuted ? Color.red : Color.green) : Color.secondary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 148, height: 148)
                Image(systemName: isReceiving ? (isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.3.fill") : "ear")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(isReceiving ? (isReceiveMuted ? .red : .green) : .primary)
                    .contentTransition(.symbolEffect(.replace))
            }

            if isReceiving {
                HStack(spacing: 12) {
                    Button {
                        isReceiveMuted = MisMeeterRuntime.shared.toggleReceiveMuted()
                    } label: {
                        Label(isReceiveMuted ? "Audio on" : "Mute RX", systemImage: isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .destructive) {
                        stopRX()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                Button {
                    startRX()
                } label: {
                    Label("Start receiving audio", systemImage: "ear")
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

    private var rxBufferCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Receive buffer", systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text("\(Int(rxAdaptiveTargetMS)) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(Double(rxBufferedFrames) / 9600.0, 0), 1))
            HStack {
                Text("Clock correction")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.4fx", rxPlaybackRate))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .padding(18)
        .glassCard()
    }

    private var receiverQualityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reception quality", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            metric("Packets received", rxPackets.formatted())
            metric("Lost", rxLost.formatted())
            metric("Underflows", rxUnderflows.formatted())
            metric("Buffered", "\(rxBufferedFrames) frames")
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

    private var sendQualityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Send quality", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            metric("Packets sent", packetsSent.formatted())
            metric("Send errors", sendErrors.formatted())
            metric("Max TX gap", String(format: "%.2f ms", maxSendGapMS))
            metric("Capture rate", String(format: "%.1f Hz", measuredCaptureHz))
            metric("TX rate", String(format: "%.1f Hz", effectiveTXHz))
        }
        .padding(18)
        .glassCard()
    }

    private var presetsView: some View {
        Form {
            Section {
                Picker("TX preset", selection: $selectedTXPreset) {
                    Text(p1Name).tag(0); Text(p2Name).tag(1); Text(p3Name).tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(isStreaming)

                TextField("Preset name", text: txNameBinding)
                    .focused($isEditingPreset)
                TextField("Destination IPv4", text: txHostBinding)
                    .focused($isEditingPreset)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("UDP port", text: txPortBinding)
                    .focused($isEditingPreset)
                    .keyboardType(.numberPad)
                TextField("VBAN stream", text: txStreamBinding)
                    .focused($isEditingPreset)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Label("Transmit preset", systemImage: "mic.and.signal.meter")
            } footer: {
                Text("Destination used by the Send screen.")
            }

            Section {
                Picker("RX preset", selection: $selectedRXPreset) {
                    Text(rx1Name).tag(0); Text(rx2Name).tag(1); Text(rx3Name).tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(isReceiving)

                TextField("Preset name", text: rxNameBinding)
                    .focused($isEditingPreset)
                TextField("Listen port", text: rxPortBinding)
                    .focused($isEditingPreset)
                    .keyboardType(.numberPad)
                TextField("VBAN stream", text: rxStreamBinding)
                    .focused($isEditingPreset)
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
                Label("Receive preset", systemImage: "speaker.wave.3.fill")
            } footer: {
                Text("Source configuration used by the Receive Home screen.")
            }
        }
        .safeAreaPadding(.bottom, 86)
        .navigationTitle("Presets")
    }

    private var settingsView: some View {
        Form {
            Section("Background reliability") {
                Label("Audio-clocked nonblocking UDP", systemImage: "checkmark.seal.fill")
                Label("Audio background mode", systemImage: "lock.shield.fill")
                Text("The TX path has no GCD timer, semaphore worker or catch-up burst between Core Audio and VBAN.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Monitor · Transport") {
                metric("Packets sent", packetsSent.formatted())
                metric("Send errors", sendErrors.formatted())
                metric("Max TX gap", String(format: "%.2f ms", maxSendGapMS))
                metric("Capture rate", String(format: "%.1f Hz", measuredCaptureHz))
                metric("TX rate", String(format: "%.1f Hz", effectiveTXHz))
            }

            Section("Monitor · Core Audio") {
                metric("Callback", "\(callbackFrames) frames")
                metric("I/O buffer", String(format: "%.2f ms", actualIOBufferMS))
                metric("Max callback gap", String(format: "%.2f ms", maxCaptureGapMS))
                metric("Voice processing", voiceProcessingActive ? "Active" : "Raw RemoteIO")
                metric("TX clock", "Audio callback")
            }

            Section("Monitor · Receiver") {
                metric("Packets", rxPackets.formatted())
                metric("Lost", rxLost.formatted())
                metric("Underflows", rxUnderflows.formatted())
                metric("Buffered", "\(rxBufferedFrames) frames")
                metric("Clock correction", String(format: "%.4fx", rxPlaybackRate))
                metric("Adaptive target", String(format: "%.0f ms", rxAdaptiveTargetMS))
            }

            Section("System surfaces") {
                Label("Dynamic Island TX + RX indicators", systemImage: "capsule.fill")
                Label("Home & Lock Screen Widget", systemImage: "square.grid.2x2.fill")
                Text("Receive mute, microphone mute and Stop All synchronize through the shared App Group control channel and reconcile whenever the app returns to foreground.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "3.2.3")
                LabeledContent("Audio", value: "48 kHz / PCM16 / VBAN")
                LabeledContent("Minimum iOS", value: "18.5")
                LabeledContent("Toolchain", value: "Xcode 16.4 · iOS SDK 18.5")
            }
        }
        .safeAreaPadding(.bottom, 86)
        .navigationTitle("Settings")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit().weight(.medium))
        }
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
            selectedTab = .presets
            return
        }
        do {
            try await MisMeeterRuntime.shared.start(
                preset: preset,
                gainDB: Float(gainDB),
                transmissionMode: VBANTransmissionMode(rawValue: transmissionModeRaw) ?? .automatic,
                captureMode: CaptureMode(rawValue: captureModeRaw) ?? .voiceProcessingIO
            )
            await MainActor.run { reconcileRuntimeState() }
        } catch {
            await MainActor.run {
                reconcileRuntimeState()
                alertMessage = error.localizedDescription
            }
        }
    }

    private func stopTX() async {
        await MisMeeterRuntime.shared.stop()
        await MainActor.run { reconcileRuntimeState() }
    }

    private func startRX() {
        do {
            try MisMeeterRuntime.shared.startReceiving(preset: currentRXPreset)
            reconcileRuntimeState()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func stopRX() {
        MisMeeterRuntime.shared.stopReceiving()
        reconcileRuntimeState()
    }

    private func reconcileRuntimeState() {
        let runtime = MisMeeterRuntime.shared
        let shared = SharedAppState.readSnapshot()

        isStreaming = runtime.isStreaming
        isMuted = runtime.isStreaming ? runtime.isMuted : false
        isReceiving = runtime.isReceiving
        isReceiveMuted = runtime.isReceiving ? runtime.isReceiveMuted : false
        meter = runtime.isStreaming ? meter : 0

        if runtime.isStreaming {
            txStatus = runtime.isMuted ? "Muted" : "Live"
        } else {
            txStatus = "Ready"
        }

        if runtime.isReceiving {
            rxStatus = runtime.isReceiveMuted ? "Receive muted" : "Listening"
        } else {
            rxStatus = "Ready"
        }

        // If an App Intent stopped the stream while the UI was suspended, ensure the
        // foreground view never resurrects stale controls from its previous @State.
        if !shared.isStreaming && !runtime.isStreaming {
            isStreaming = false
            isMuted = false
        }
    }

    private func wireRuntimeCallbacks() {
        let runtime = MisMeeterRuntime.shared
        runtime.onStatusChange = { value in
            DispatchQueue.main.async {
                txStatus = value
                reconcileRuntimeState()
            }
        }
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
        runtime.onReceiverStatus = { value in
            DispatchQueue.main.async {
                rxStatus = value
                reconcileRuntimeState()
            }
        }
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

private enum AppSection: String, CaseIterable, Identifiable {
    case transmit
    case receive
    case presets
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transmit: return "Send"
        case .receive: return "Receive"
        case .presets: return "Presets"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .transmit: return "mic.fill"
        case .receive: return "speaker.wave.2.fill"
        case .presets: return "slider.horizontal.3"
        case .settings: return "gearshape.fill"
        }
    }
}

private extension View {
    func glassCard() -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7)
                    }
            }
    }
}
