import AVFoundation
import SwiftUI

struct DashboardView: View {
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

    @AppStorage("selectedRXPreset") private var selectedRXPreset = 0
    @AppStorage("rx1Name") private var rx1Name = "Main"
    @AppStorage("rx1Port") private var rx1Port = "6980"
    @AppStorage("rx1Stream") private var rx1Stream = "PC-Main"
    @AppStorage("rx2Name") private var rx2Name = "Aux"
    @AppStorage("rx2Port") private var rx2Port = "6980"
    @AppStorage("rx2Stream") private var rx2Stream = "PC-Aux"
    @AppStorage("rx3Name") private var rx3Name = "Other"
    @AppStorage("rx3Port") private var rx3Port = "6980"
    @AppStorage("rx3Stream") private var rx3Stream = "PC-Other"

    @State private var editTXPreset = 0
    @State private var editRXPreset = 0
    @State private var isStreaming = MisMeeterRuntime.shared.isStreaming
    @State private var isMuted = MisMeeterRuntime.shared.isMuted
    @State private var isReceiving = MisMeeterRuntime.shared.isReceiving
    @State private var isReceiveMuted = MisMeeterRuntime.shared.isReceiveMuted
    @State private var meter: Float = 0
    @State private var packetsSent: UInt64 = 0
    @State private var sendErrors: UInt64 = 0
    @State private var maxSendGapMS = 0.0
    @State private var measuredCaptureHz = 48_000.0
    @State private var effectiveTXHz = 48_000.0
    @State private var rxPackets: UInt64 = 0
    @State private var rxLost: UInt64 = 0
    @State private var rxUnderflows: UInt64 = 0
    @State private var rxBufferedFrames = 0
    @State private var rxPlaybackRate: Float = 1
    @State private var rxAdaptiveTargetMS = 35.0
    @State private var alertMessage: String?
    @State private var selectedTab: DashboardSection = .transmit
    @State private var switchingTX = false
    @State private var switchingRX = false
    @FocusState private var isEditingPreset: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                TabView(selection: $selectedTab) {
                    txHome.tag(DashboardSection.transmit)
                    rxHome.tag(DashboardSection.receive)
                    presets.tag(DashboardSection.presets)
                    settings.tag(DashboardSection.settings)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            if !isEditingPreset { navigationBar.padding(.bottom, 8) }
        }
        .tint(.accentColor)
        .onAppear {
            selectedTXPreset = min(max(selectedTXPreset, 0), 2)
            selectedRXPreset = min(max(selectedRXPreset, 0), 2)
            editTXPreset = selectedTXPreset
            editRXPreset = selectedRXPreset
            if CaptureMode(rawValue: captureModeRaw) == nil { captureModeRaw = CaptureMode.voiceProcessingIO.rawValue }
            wireCallbacks()
            MisMeeterRuntime.shared.gainDB = Float(gainDB)
            reconcile()
            MisMeeterRuntime.shared.refreshSystemControls()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reconcile(); MisMeeterRuntime.shared.refreshSystemControls() }
        }
        .alert("MisMeeter", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: { Text(alertMessage ?? "") }
    }

    private var txHome: some View {
        ScrollView {
            VStack(spacing: 18) {
                txHero
                txPresetCard
                levelCard
                HStack(spacing: 12) {
                    statusCard("TX", txStatus, "arrow.up.circle.fill", isStreaming)
                    statusCard("RX", rxStatus, "arrow.down.circle.fill", isReceiving)
                }
                txControls
                txQuality
            }
            .padding(16).padding(.bottom, 92)
        }
        .background(background)
        .navigationTitle("Send")
    }

    private var txHero: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isStreaming ? (isMuted ? "Microphone muted" : "On air") : "Ready to connect").font(.title2.bold())
                    Text(displayedTX.destinationLabel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                statePill(isStreaming, muted: isMuted, live: "LIVE")
            }
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 14).frame(width: 148, height: 148)
                Circle().trim(from: 0, to: isStreaming ? CGFloat(max(0.08, min(1, meter))) : 0.06)
                    .stroke(isMuted ? .red : (isStreaming ? .green : .secondary), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 148, height: 148)
                Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill").font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(isMuted ? .red : (isStreaming ? .green : .primary))
            }
            if isStreaming {
                HStack(spacing: 12) {
                    Button { isMuted = MisMeeterRuntime.shared.toggleMuted() } label: {
                        Label(isMuted ? "Unmute" : "Mute", systemImage: isMuted ? "mic.fill" : "mic.slash.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button(role: .destructive) { Task { await stopTX() } } label: {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                }
            } else {
                Button { Task { await startTX() } } label: {
                    Label("Start microphone stream", systemImage: "dot.radiowaves.left.and.right").font(.headline).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(20).glassCard()
    }

    private var txPresetCard: some View {
        presetCard(title: "Send preset", icon: "point.3.connected.trianglepath.dotted", selection: $selectedTXPreset,
                   names: [p1Name, p2Name, p3Name], busy: switchingTX) { index in
            Task { await changeTXPreset(to: index) }
        }
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Microphone level", systemImage: "waveform").font(.headline); Spacer(); Text("+\(Int(gainDB)) dB").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(meter > 0.85 ? .orange : .green).frame(width: geo.size.width * CGFloat(max(0.01, min(1, meter))))
                }
            }.frame(height: 9)
        }.padding(18).glassCard()
    }

    private var txControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Send controls", systemImage: "slider.horizontal.3").font(.headline)
            HStack { Label("Input gain", systemImage: "dial.medium.fill"); Spacer(); Text("+\(Int(gainDB)) dB").monospacedDigit() }
            Slider(value: $gainDB, in: 0...24, step: 1).onChange(of: gainDB) { _, v in MisMeeterRuntime.shared.gainDB = Float(v) }
            Divider()
            HStack {
                Label("Capture engine", systemImage: "waveform.badge.mic")
                Spacer()
                Picker("Capture", selection: $captureModeRaw) { ForEach(CaptureMode.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden().pickerStyle(.menu).disabled(isStreaming)
            }
        }.padding(18).glassCard()
    }

    private var txQuality: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Send quality", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
            metric("Packets sent", packetsSent.formatted()); metric("Send errors", sendErrors.formatted())
            metric("Max TX gap", String(format: "%.2f ms", maxSendGapMS)); metric("Capture rate", String(format: "%.1f Hz", measuredCaptureHz)); metric("TX rate", String(format: "%.1f Hz", effectiveTXHz))
        }.padding(18).glassCard()
    }

    private var rxHome: some View {
        ScrollView {
            VStack(spacing: 18) {
                rxHero
                rxPresetCard
                rxBuffer
                HStack(spacing: 12) {
                    statusCard("Packets", rxPackets.formatted(), "shippingbox.fill", isReceiving)
                    statusCard("Underflows", rxUnderflows.formatted(), "exclamationmark.triangle.fill", isReceiving && rxUnderflows == 0)
                }
                rxQuality
            }.padding(16).padding(.bottom, 92)
        }.background(background).navigationTitle("Receive")
    }

    private var rxHero: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isReceiving ? (isReceiveMuted ? "Receive muted" : "Listening") : "Ready to listen").font(.title2.bold())
                    Text("\(displayedRX.name) · \(displayedRX.streamName)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(); statePill(isReceiving, muted: isReceiveMuted, live: "LIVE")
            }
            ZStack {
                Circle().stroke(.primary.opacity(0.08), lineWidth: 14).frame(width: 148, height: 148)
                Circle().trim(from: 0, to: isReceiving ? 0.82 : 0.06).stroke(isReceiveMuted ? .red : (isReceiving ? .green : .secondary), style: StrokeStyle(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 148, height: 148)
                Image(systemName: isReceiveMuted ? "speaker.slash.fill" : (isReceiving ? "speaker.wave.3.fill" : "ear")).font(.system(size: 42, weight: .semibold)).foregroundStyle(isReceiveMuted ? .red : (isReceiving ? .green : .primary))
            }
            if isReceiving {
                HStack(spacing: 12) {
                    Button { isReceiveMuted = MisMeeterRuntime.shared.toggleReceiveMuted() } label: { Label(isReceiveMuted ? "Audio on" : "Mute RX", systemImage: isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button(role: .destructive) { stopRX() } label: { Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large)
                }
            } else {
                Button { startRX() } label: { Label("Start receiving audio", systemImage: "ear").font(.headline).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(20).glassCard()
    }

    private var rxPresetCard: some View {
        presetCard(title: "Receive preset", icon: "dot.radiowaves.left.and.right", selection: $selectedRXPreset,
                   names: [rx1Name, rx2Name, rx3Name], busy: switchingRX) { index in
            changeRXPreset(to: index)
        }
    }

    private var rxBuffer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label("Automatic jitter", systemImage: "waveform.path.ecg").font(.headline); Spacer(); Text("\(Int(rxAdaptiveTargetMS)) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            ProgressView(value: min(max(Double(rxBufferedFrames) / max(rxAdaptiveTargetMS * 48.0, 1.0), 0), 1))
            metric("Clock correction", String(format: "%.4fx", rxPlaybackRate))
        }.padding(18).glassCard()
    }

    private var rxQuality: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reception quality", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
            metric("Packets received", rxPackets.formatted()); metric("Lost", rxLost.formatted()); metric("Underflows", rxUnderflows.formatted()); metric("Buffered", String(format: "%.1f ms", Double(rxBufferedFrames) / 48.0))
        }.padding(18).glassCard()
    }

    private func presetCard(title: String, icon: String, selection: Binding<Int>, names: [String], busy: Bool, changed: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                else { Text((isStreaming || isReceiving) ? "Switch live" : "Active preset").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Button {
                        guard selection.wrappedValue != index, !busy else { return }
                        selection.wrappedValue = index
                        changed(index)
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.secondary)
                            Text(names[index].isEmpty ? "Preset \(index + 1)" : names[index]).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(selection.wrappedValue == index ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selection.wrappedValue == index ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1) }
                    }.buttonStyle(.plain).disabled(busy)
                }
            }
        }.padding(18).glassCard()
    }

    private var presets: some View {
        Form {
            Section {
                Picker("Edit TX preset", selection: $editTXPreset) { Text(p1Name).tag(0); Text(p2Name).tag(1); Text(p3Name).tag(2) }.pickerStyle(.segmented)
                TextField("Preset name", text: editTXName).focused($isEditingPreset)
                TextField("Destination IPv4", text: editTXHost).focused($isEditingPreset).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("UDP port", text: editTXPort).focused($isEditingPreset).keyboardType(.numberPad)
                TextField("VBAN stream", text: editTXStream).focused($isEditingPreset).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Label("Transmit presets", systemImage: "mic.and.signal.meter") }
              footer: { Text("Configure the three Send presets here. Choose the active one from the Send screen, even while streaming.") }

            Section {
                Picker("Edit RX preset", selection: $editRXPreset) { Text(rx1Name).tag(0); Text(rx2Name).tag(1); Text(rx3Name).tag(2) }.pickerStyle(.segmented)
                TextField("Preset name", text: editRXName).focused($isEditingPreset)
                TextField("Listen port", text: editRXPort).focused($isEditingPreset).keyboardType(.numberPad)
                TextField("VBAN stream", text: editRXStream).focused($isEditingPreset).textInputAutocapitalization(.never).autocorrectionDisabled()
                HStack { Label("Jitter buffer", systemImage: "bolt.horizontal.circle"); Spacer(); Text("Automatic").foregroundStyle(.secondary) }
            } header: { Label("Receive presets", systemImage: "speaker.wave.3.fill") }
              footer: { Text("Configure the three Receive presets here. Choose the active one from the Receive screen, even while listening.") }
        }.safeAreaPadding(.bottom, 86).navigationTitle("Presets")
    }

    private var settings: some View {
        Form {
            Section("Audio & network baseline") {
                Label("Core Audio realtime capture", systemImage: "checkmark.seal.fill")
                Label("Audio-clocked nonblocking UDP", systemImage: "checkmark.seal.fill")
                Label("Adaptive RX jitter buffer", systemImage: "checkmark.seal.fill")
                Text("The known-good audio and VBAN networking pipeline is preserved. Live preset changes restart only the affected stream using the same runtime stack.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Transport") { metric("Packets sent", packetsSent.formatted()); metric("Send errors", sendErrors.formatted()); metric("Max TX gap", String(format: "%.2f ms", maxSendGapMS)); metric("RX packets", rxPackets.formatted()); metric("RX lost", rxLost.formatted()) }
            Section("About") { LabeledContent("Version", value: appVersion); LabeledContent("Audio", value: "48 kHz / PCM16 / VBAN"); LabeledContent("Minimum iOS", value: "18.5") }
        }.safeAreaPadding(.bottom, 86).navigationTitle("Settings")
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            ForEach(DashboardSection.allCases) { item in
                Button { withAnimation(.smooth(duration: 0.24)) { selectedTab = item } } label: {
                    VStack(spacing: 3) { Image(systemName: item.icon).font(.system(size: 16, weight: .semibold)); Text(item.title).font(.system(size: 9.5, weight: .semibold)) }
                        .frame(width: 54, height: 48).foregroundStyle(selectedTab == item ? Color.primary : Color.secondary)
                        .background { if selectedTab == item { Capsule().fill(Color.primary.opacity(0.075)) } }
                }.buttonStyle(.plain)
            }
        }.padding(5).background { Capsule().fill(.ultraThinMaterial).overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7) }.shadow(color: .black.opacity(0.10), radius: 18, y: 8) }
    }

    private func statePill(_ active: Bool, muted: Bool, live: String) -> some View {
        HStack(spacing: 6) { Circle().fill(active ? (muted ? Color.red : Color.green) : Color.secondary).frame(width: 8, height: 8); Text(active ? (muted ? "MUTED" : live) : "IDLE").font(.caption2.bold()) }
            .padding(.horizontal, 10).padding(.vertical, 7).background(.thinMaterial, in: Capsule())
    }

    private func statusCard(_ title: String, _ value: String, _ icon: String, _ active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) { HStack { Image(systemName: icon).foregroundStyle(active ? .green : .secondary); Spacer(); Circle().fill(active ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7) }; Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.semibold)).lineLimit(2) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard()
    }

    private func metric(_ label: String, _ value: String) -> some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).font(.body.monospacedDigit().weight(.medium)) } }
    private var background: some View { LinearGradient(colors: [Color.accentColor.opacity(0.10), .clear, Color.primary.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea() }

    private func changeTXPreset(to index: Int) async {
        guard isStreaming else { return }
        switchingTX = true
        let wasMuted = isMuted
        await MisMeeterRuntime.shared.stop()
        await MainActor.run { reconcile() }
        await startTX()
        if wasMuted && MisMeeterRuntime.shared.isStreaming { _ = MisMeeterRuntime.shared.toggleMuted() }
        await MainActor.run { reconcile(); switchingTX = false }
    }

    private func changeRXPreset(to index: Int) {
        guard isReceiving else { return }
        switchingRX = true
        let wasMuted = isReceiveMuted
        MisMeeterRuntime.shared.stopReceiving()
        do {
            try MisMeeterRuntime.shared.startReceiving(preset: currentRX)
            if wasMuted { _ = MisMeeterRuntime.shared.toggleReceiveMuted() }
        } catch { alertMessage = error.localizedDescription }
        reconcile(); switchingRX = false
    }

    private func startTX() async {
        var preset = currentTX
        guard let port = validPort(portString(forTX: selectedTXPreset)) else { await MainActor.run { alertMessage = "Enter a valid TX UDP port between 1 and 65535." }; return }
        preset.port = port
        guard !preset.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { await MainActor.run { alertMessage = "Enter the destination IPv4 address in Presets first." }; return }
        guard await AVAudioApplication.requestRecordPermission() else { await MainActor.run { alertMessage = "Microphone access is required to transmit audio." }; return }
        do {
            try await MisMeeterRuntime.shared.start(preset: preset, gainDB: Float(gainDB), captureMode: CaptureMode(rawValue: captureModeRaw) ?? .voiceProcessingIO)
            await MainActor.run { reconcile() }
        } catch { await MainActor.run { reconcile(); alertMessage = error.localizedDescription } }
    }

    private func stopTX() async { await MisMeeterRuntime.shared.stop(); await MainActor.run { reconcile() } }
    private func startRX() { do { try MisMeeterRuntime.shared.startReceiving(preset: currentRX); reconcile() } catch { alertMessage = error.localizedDescription } }
    private func stopRX() { MisMeeterRuntime.shared.stopReceiving(); reconcile() }

    private func reconcile() {
        let r = MisMeeterRuntime.shared
        isStreaming = r.isStreaming; isMuted = r.isStreaming ? r.isMuted : false
        isReceiving = r.isReceiving; isReceiveMuted = r.isReceiving ? r.isReceiveMuted : false
        if !r.isStreaming { meter = 0 }
    }

    private func wireCallbacks() {
        let r = MisMeeterRuntime.shared
        r.onMicrophoneDiagnostics = { value, _, _, _ in DispatchQueue.main.async { meter = value } }
        r.onTransmitterDiagnostics = { sent, errors, capture, tx, gap in DispatchQueue.main.async { packetsSent = sent; sendErrors = errors; measuredCaptureHz = capture; effectiveTXHz = tx; maxSendGapMS = gap } }
        r.onReceiverDiagnostics = { received, _, lost, buffered, underflows, _, rate, target in DispatchQueue.main.async { rxPackets = received; rxLost = lost; rxBufferedFrames = buffered; rxUnderflows = underflows; rxPlaybackRate = rate; rxAdaptiveTargetMS = target } }
        r.onTransportSnapshotChange = { _ in DispatchQueue.main.async { reconcile() } }
    }

    private func validPort(_ s: String) -> UInt16? { guard let p = UInt16(s.trimmingCharacters(in: .whitespacesAndNewlines)), p > 0 else { return nil }; return p }
    private func portString(forTX i: Int) -> String { i == 1 ? p2Port : (i == 2 ? p3Port : p1Port) }

    private var currentTX: VBANPreset {
        switch selectedTXPreset {
        case 1: return VBANPreset(name: p2Name, host: p2Host, port: validPort(p2Port) ?? 6980, streamName: p2Stream)
        case 2: return VBANPreset(name: p3Name, host: p3Host, port: validPort(p3Port) ?? 6980, streamName: p3Stream)
        default: return VBANPreset(name: p1Name, host: p1Host, port: validPort(p1Port) ?? 6980, streamName: p1Stream)
        }
    }
    private var currentRX: VBANReceivePreset {
        switch selectedRXPreset {
        case 1: return VBANReceivePreset(name: rx2Name, port: validPort(rx2Port) ?? 6980, streamName: rx2Stream)
        case 2: return VBANReceivePreset(name: rx3Name, port: validPort(rx3Port) ?? 6980, streamName: rx3Stream)
        default: return VBANReceivePreset(name: rx1Name, port: validPort(rx1Port) ?? 6980, streamName: rx1Stream)
        }
    }
    private var displayedTX: VBANPreset { isStreaming ? MisMeeterRuntime.shared.activePreset : currentTX }
    private var displayedRX: VBANReceivePreset { isReceiving ? MisMeeterRuntime.shared.activeReceivePreset : currentRX }
    private var txStatus: String { isStreaming ? (isMuted ? "Muted" : "Live") : "Ready" }
    private var rxStatus: String { isReceiving ? (isReceiveMuted ? "Receive muted" : "Listening") : "Ready" }
    private var appVersion: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "5.1.0" }

    private var editTXName: Binding<String> { editTXPreset == 1 ? $p2Name : (editTXPreset == 2 ? $p3Name : $p1Name) }
    private var editTXHost: Binding<String> { editTXPreset == 1 ? $p2Host : (editTXPreset == 2 ? $p3Host : $p1Host) }
    private var editTXPort: Binding<String> { editTXPreset == 1 ? $p2Port : (editTXPreset == 2 ? $p3Port : $p1Port) }
    private var editTXStream: Binding<String> { editTXPreset == 1 ? $p2Stream : (editTXPreset == 2 ? $p3Stream : $p1Stream) }
    private var editRXName: Binding<String> { editRXPreset == 1 ? $rx2Name : (editRXPreset == 2 ? $rx3Name : $rx1Name) }
    private var editRXPort: Binding<String> { editRXPreset == 1 ? $rx2Port : (editRXPreset == 2 ? $rx3Port : $rx1Port) }
    private var editRXStream: Binding<String> { editRXPreset == 1 ? $rx2Stream : (editRXPreset == 2 ? $rx3Stream : $rx1Stream) }
}

private enum DashboardSection: String, CaseIterable, Identifiable {
    case transmit, receive, presets, settings
    var id: String { rawValue }
    var title: String { switch self { case .transmit: "Send"; case .receive: "Receive"; case .presets: "Presets"; case .settings: "Settings" } }
    var icon: String { switch self { case .transmit: "mic.fill"; case .receive: "speaker.wave.2.fill"; case .presets: "slider.horizontal.3"; case .settings: "gearshape.fill" } }
}
