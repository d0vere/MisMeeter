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
                        .background(selection.wrappedValue == index ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selection.wrappedValue == index ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.06), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(busy)
                }
            }
            Text("Tap a preset to make it active. If audio is running, MisMeeter switches using the existing audio/network runtime.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).glassCard()
    }

    private var presets: some View {
        Form {
            Section {
                Picker("Edit TX preset", selection: $editTXPreset) { ForEach(0..<3, id: \.self) { Text("\($0 + 1)").tag($0) } }.pickerStyle(.segmented)
                TextField("Preset name", text: editTXName).focused($isEditingPreset)
                TextField("Destination IPv4", text: editTXHost).focused($isEditingPreset).keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("UDP port", text: editTXPort).focused($isEditingPreset).keyboardType(.numberPad)
                TextField("VBAN stream", text: editTXStream).focused($isEditingPreset).textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: { Label("Transmit presets", systemImage: "mic.and.signal.meter") }
              footer: { Text("Configure the three Send presets here. Choose the active one from the Send screen, even while streaming.") }

            Section {
                Picker("Edit RX preset", selection: $editRXPreset) { ForEach(0..<3, id: \.self) { Text("\($0 + 1)").tag($0) } }.pickerStyle(.segmented)
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
            Section("Audio") {
                LabeledContent("Sample rate", value: "48 kHz")
                LabeledContent("Format", value: "PCM 16-bit")
                LabeledContent("Packet audio", value: "256 frames")
                LabeledContent("RX jitter", value: "Automatic")
            }
            Section("System") {
                LabeledContent("Background audio", value: "Enabled")
                LabeledContent("Control Center", value: "TX / RX mute")
                LabeledContent("Live Activity", value: "Enabled")
            }
        }.safeAreaPadding(.bottom, 86).navigationTitle("Settings")
    }

    private var navigationBar: some View {
        HStack(spacing: 4) {
            ForEach(DashboardSection.allCases) { section in
                Button {
                    withAnimation(.snappy(duration: 0.24)) { selectedTab = section }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: section.icon).font(.system(size: 17, weight: selectedTab == section ? .semibold : .regular))
                        Text(section.title).font(.caption2.weight(selectedTab == section ? .semibold : .regular))
                    }.foregroundStyle(selectedTab == section ? Color.accentColor : Color.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
        }.padding(5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.primary.opacity(0.08))).padding(.horizontal, 12).shadow(radius: 14, y: 7)
    }

    private var background: some View { LinearGradient(colors: [Color.accentColor.opacity(0.06), Color.clear], startPoint: .topLeading, endPoint: .center).ignoresSafeArea() }
    private func metric(_ name: String, _ value: String) -> some View { HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() } }
    private func statusCard(_ title: String, _ value: String, _ icon: String, _ positive: Bool) -> some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(positive ? .green : .secondary); Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(16).glassCard() }
    private func statePill(_ active: Bool, muted: Bool, live: String) -> some View { HStack(spacing: 6) { Circle().fill(muted ? .red : (active ? .green : .secondary)).frame(width: 7, height: 7); Text(muted ? "MUTED" : (active ? live : "IDLE")).font(.caption2.bold()) }.padding(.horizontal, 10).padding(.vertical, 6).background(.thinMaterial, in: Capsule()) }

    private var txStatus: String { !isStreaming ? "Idle" : (isMuted ? "Muted" : "Streaming") }
    private var rxStatus: String { !isReceiving ? "Idle" : (isReceiveMuted ? "Muted" : "Listening") }

    private var displayedTX: VBANPreset { txPreset(selectedTXPreset) }
    private var displayedRX: VBANReceivePreset { rxPreset(selectedRXPreset) }

    private func txPreset(_ index: Int) -> VBANPreset {
        let names = [p1Name, p2Name, p3Name], hosts = [p1Host, p2Host, p3Host], ports = [p1Port, p2Port, p3Port], streams = [p1Stream, p2Stream, p3Stream]
        return VBANPreset(name: names[index], host: hosts[index], port: UInt16(ports[index]) ?? 6980, streamName: streams[index])
    }
    private func rxPreset(_ index: Int) -> VBANReceivePreset {
        let names = [rx1Name, rx2Name, rx3Name], ports = [rx1Port, rx2Port, rx3Port], streams = [rx1Stream, rx2Stream, rx3Stream]
        return VBANReceivePreset(name: names[index], port: UInt16(ports[index]) ?? 6980, streamName: streams[index])
    }

    @MainActor private func startTX() async {
        do { try await MisMeeterRuntime.shared.start(preset: displayedTX, gainDB: Float(gainDB), captureMode: CaptureMode(rawValue: captureModeRaw) ?? .voiceProcessingIO); reconcile() }
        catch { alertMessage = error.localizedDescription; reconcile() }
    }
    @MainActor private func stopTX() async { await MisMeeterRuntime.shared.stop(); reconcile() }
    private func startRX() { do { try MisMeeterRuntime.shared.startReceiving(preset: displayedRX); reconcile() } catch { alertMessage = error.localizedDescription; reconcile() } }
    private func stopRX() { MisMeeterRuntime.shared.stopReceiving(); reconcile() }

    @MainActor private func changeTXPreset(to index: Int) async {
        guard isStreaming else { return }
        switchingTX = true; defer { switchingTX = false }
        await MisMeeterRuntime.shared.stop()
        do { try await MisMeeterRuntime.shared.start(preset: txPreset(index), gainDB: Float(gainDB), captureMode: CaptureMode(rawValue: captureModeRaw) ?? .voiceProcessingIO) }
        catch { alertMessage = "Preset \(index + 1): \(error.localizedDescription)" }
        reconcile()
    }
    private func changeRXPreset(to index: Int) {
        guard isReceiving else { return }
        switchingRX = true
        MisMeeterRuntime.shared.stopReceiving()
        do { try MisMeeterRuntime.shared.startReceiving(preset: rxPreset(index)) }
        catch { alertMessage = "Preset \(index + 1): \(error.localizedDescription)" }
        switchingRX = false; reconcile()
    }

    private func wireCallbacks() {
        MisMeeterRuntime.shared.onMeter = { value in Task { @MainActor in meter = value } }
        MisMeeterRuntime.shared.onDiagnostics = { p, e, g, c, t in Task { @MainActor in packetsSent = p; sendErrors = e; maxSendGapMS = g; measuredCaptureHz = c; effectiveTXHz = t } }
        MisMeeterRuntime.shared.onReceiveDiagnostics = { p, l, u, b, r, target in Task { @MainActor in rxPackets = p; rxLost = l; rxUnderflows = u; rxBufferedFrames = b; rxPlaybackRate = r; rxAdaptiveTargetMS = target } }
    }
    private func reconcile() { isStreaming = MisMeeterRuntime.shared.isStreaming; isMuted = MisMeeterRuntime.shared.isMuted; isReceiving = MisMeeterRuntime.shared.isReceiving; isReceiveMuted = MisMeeterRuntime.shared.isReceiveMuted }

    private var editTXName: Binding<String> { binding(index: editTXPreset, values: ($p1Name, $p2Name, $p3Name)) }
    private var editTXHost: Binding<String> { binding(index: editTXPreset, values: ($p1Host, $p2Host, $p3Host)) }
    private var editTXPort: Binding<String> { binding(index: editTXPreset, values: ($p1Port, $p2Port, $p3Port)) }
    private var editTXStream: Binding<String> { binding(index: editTXPreset, values: ($p1Stream, $p2Stream, $p3Stream)) }
    private var editRXName: Binding<String> { binding(index: editRXPreset, values: ($rx1Name, $rx2Name, $rx3Name)) }
    private var editRXPort: Binding<String> { binding(index: editRXPreset, values: ($rx1Port, $rx2Port, $rx3Port)) }
    private var editRXStream: Binding<String> { binding(index: editRXPreset, values: ($rx1Stream, $rx2Stream, $rx3Stream)) }
    private func binding(index: Int, values: (Binding<String>, Binding<String>, Binding<String>)) -> Binding<String> { switch index { case 1: values.1; case 2: values.2; default: values.0 } }
}

private enum DashboardSection: Int, CaseIterable, Identifiable {
    case transmit, receive, presets, settings
    var id: Int { rawValue }
    var title: String { switch self { case .transmit: "Send"; case .receive: "Receive"; case .presets: "Presets"; case .settings: "Settings" } }
    var icon: String { switch self { case .transmit: "mic.fill"; case .receive: "speaker.wave.3.fill"; case .presets: "square.grid.2x2.fill"; case .settings: "gearshape.fill" } }
}
