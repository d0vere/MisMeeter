import SwiftUI
import AppIntents
import WidgetKit

private struct MisMeeterEntry: TimelineEntry {
    let date: Date
    let state: SharedTransportSnapshot
}

private struct MisMeeterProvider: TimelineProvider {
    func placeholder(in context: Context) -> MisMeeterEntry {
        MisMeeterEntry(
            date: .now,
            state: SharedTransportSnapshot(
                isStreaming: true,
                isMuted: false,
                isReceiving: true,
                isReceiveMuted: false,
                presetName: "Studio TX",
                sendPresetName: "Studio TX",
                receivePresetName: "Control Room",
                destination: "192.168.1.40:6980",
                streamName: "MisMeeter",
                startedAt: .now.addingTimeInterval(-420),
                status: "Active"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MisMeeterEntry) -> Void) {
        completion(MisMeeterEntry(date: .now, state: SharedAppState.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MisMeeterEntry>) -> Void) {
        let entry = MisMeeterEntry(date: .now, state: SharedAppState.readSnapshot())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct MisMeeterStatusWidget: Widget {
    let kind = "MisMeeterStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MisMeeterProvider()) { entry in
            MisMeeterWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("MisMeeter Dashboard")
        .description("Send and Receive presets, status and controls at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct MisMeeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MisMeeterEntry

    private var isActive: Bool { entry.state.isStreaming || entry.state.isReceiving }

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Home Screen small

    private var small: some View {
        VStack(alignment: .leading, spacing: 9) {
            transportPresetLine(
                prefix: "TX",
                preset: entry.state.sendPresetName,
                systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                active: entry.state.isStreaming,
                muted: entry.state.isMuted
            )

            transportPresetLine(
                prefix: "RX",
                preset: entry.state.receivePresetName,
                systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                active: entry.state.isReceiving,
                muted: entry.state.isReceiveMuted
            )

            Spacer(minLength: 0)

            if isActive {
                HStack(spacing: 6) {
                    compactIntentButton(
                        systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        disabled: !entry.state.isReceiving,
                        tint: transportTint(active: entry.state.isReceiving, muted: entry.state.isReceiveMuted),
                        intent: ToggleReceiveMuteIntent()
                    )
                    compactIntentButton(
                        systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill",
                        disabled: !entry.state.isStreaming,
                        tint: transportTint(active: entry.state.isStreaming, muted: entry.state.isMuted),
                        intent: ToggleMuteIntent()
                    )
                    Button(intent: EndLiveActivityIntent()) {
                        Image(systemName: "stop.fill")
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Link(destination: URL(string: "mismeeter://home")!) {
                    HStack {
                        Text("Open MisMeeter")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Home Screen medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    presetText(prefix: "TX", name: entry.state.sendPresetName)
                    presetText(prefix: "RX", name: entry.state.receivePresetName)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 10) {
                    statusIcon(
                        systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                        active: entry.state.isStreaming,
                        muted: entry.state.isMuted
                    )
                    statusIcon(
                        systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        active: entry.state.isReceiving,
                        muted: entry.state.isReceiveMuted
                    )
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if isActive {
                    Button(intent: ToggleReceiveMuteIntent()) {
                        Label(entry.state.isReceiveMuted ? "RX on" : "Mute RX", systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(transportTint(active: entry.state.isReceiving, muted: entry.state.isReceiveMuted))
                    .disabled(!entry.state.isReceiving)

                    Button(intent: ToggleMuteIntent()) {
                        Label(entry.state.isMuted ? "Mic on" : "Mute mic", systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(transportTint(active: entry.state.isStreaming, muted: entry.state.isMuted))
                    .disabled(!entry.state.isStreaming)

                    Button(intent: EndLiveActivityIntent()) {
                        Label("Stop all", systemImage: "stop.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Link(destination: URL(string: "mismeeter://home")!) {
                        Label("Open MisMeeter", systemImage: "arrow.up.forward.app.fill")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: Lock Screen widgets

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: isActive ? "waveform" : "waveform.badge.plus")
                    .font(.caption.weight(.bold))
                Text(activeCountText)
                    .font(.caption2.weight(.bold))
            }
        }
        .widgetAccentable()
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text("TX · \(entry.state.sendPresetName)")
                    .lineLimit(1)
                Spacer(minLength: 3)
                Image(systemName: entry.state.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            HStack(spacing: 5) {
                Text("RX · \(entry.state.receivePresetName)")
                    .lineLimit(1)
                Spacer(minLength: 3)
                Image(systemName: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
            }
        }
        .font(.caption2.weight(.semibold))
        .widgetURL(URL(string: "mismeeter://home"))
    }

    private var activeCountText: String {
        let count = (entry.state.isStreaming ? 1 : 0) + (entry.state.isReceiving ? 1 : 0)
        return count == 0 ? "Idle" : "\(count)/2"
    }

    // MARK: Building blocks

    private func transportPresetLine(prefix: String, preset: String, systemImage: String, active: Bool, muted: Bool) -> some View {
        HStack(spacing: 7) {
            Text("\(prefix) · \(preset)")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 5)
            statusIcon(systemImage: systemImage, active: active, muted: muted)
        }
    }

    private func presetText(prefix: String, name: String) -> some View {
        HStack(spacing: 5) {
            Text(prefix)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(name)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func statusIcon(systemImage: String, active: Bool, muted: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
            .frame(width: 24, height: 24)
    }

    private func transportTint(active: Bool, muted: Bool) -> Color {
        guard active else { return .gray }
        return muted ? .red : .green
    }

    private func compactIntentButton<I: AppIntent>(systemImage: String, disabled: Bool, tint: Color, intent: I) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(disabled)
    }
}
