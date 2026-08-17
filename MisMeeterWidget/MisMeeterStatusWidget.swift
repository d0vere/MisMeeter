import AppIntents
import SwiftUI
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
                .containerBackground(for: .widget) {
                    WidgetSurface()
                }
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
            dashboard(compact: false)
        default:
            dashboard(compact: true)
        }
    }

    private func dashboard(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)

                Text("MISMEETER")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Circle()
                        .fill(isActive ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(isActive ? entry.state.status.uppercased() : "READY")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(isActive ? .primary : .secondary)
            }

            transportStrip

            Spacer(minLength: 0)

            controls(minHeight: compact ? 31 : 34)
        }
        .widgetURL(isActive ? nil : URL(string: "mismeeter://home"))
    }

    private var transportStrip: some View {
        HStack(spacing: 6) {
            TransportPill(
                label: "RX",
                preset: entry.state.receivePresetName,
                systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                active: entry.state.isReceiving,
                muted: entry.state.isReceiveMuted
            )

            TransportPill(
                label: "TX",
                preset: entry.state.sendPresetName,
                systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                active: entry.state.isStreaming,
                muted: entry.state.isMuted
            )
        }
    }

    @ViewBuilder
    private func controls(minHeight: CGFloat) -> some View {
        if isActive {
            HStack(spacing: 6) {
                ControlButton(
                    systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    accessibilityText: entry.state.isReceiveMuted ? "Unmute receive audio" : "Mute receive audio",
                    enabled: entry.state.isReceiving,
                    active: entry.state.isReceiving,
                    muted: entry.state.isReceiveMuted,
                    minHeight: minHeight,
                    intent: ToggleReceiveMuteIntent()
                )

                ControlButton(
                    systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill",
                    accessibilityText: entry.state.isMuted ? "Unmute microphone" : "Mute microphone",
                    enabled: entry.state.isStreaming,
                    active: entry.state.isStreaming,
                    muted: entry.state.isMuted,
                    minHeight: minHeight,
                    intent: ToggleMuteIntent()
                )

                Button(intent: EndLiveActivityIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: minHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Stop all")
            }
        } else {
            Link(destination: URL(string: "mismeeter://home")!) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Open MisMeeter")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.bold))
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: minHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary.opacity(0.82))
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: primaryAccessoryImage)
                    .font(.body.weight(.bold))
                Text(accessoryStateText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
        }
        .widgetAccentable()
        .widgetURL(URL(string: "mismeeter://home"))
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.caption2.weight(.bold))
                Text(isActive ? entry.state.status : "Ready")
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                Image(systemName: entry.state.isMuted ? "mic.slash.fill" : "mic.fill")
            }

            HStack(spacing: 7) {
                accessoryPreset("RX", entry.state.receivePresetName)
                accessoryPreset("TX", entry.state.sendPresetName)
            }
        }
        .widgetURL(URL(string: "mismeeter://home"))
    }

    private func accessoryPreset(_ label: String, _ preset: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
            Text(preset)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var primaryAccessoryImage: String {
        if entry.state.isStreaming {
            return entry.state.isMuted ? "mic.slash.fill" : "mic.fill"
        }
        if entry.state.isReceiving {
            return entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        }
        return "waveform"
    }

    private var accessoryStateText: String {
        if entry.state.isStreaming && entry.state.isReceiving { return "RX·TX" }
        if entry.state.isStreaming { return "TX" }
        if entry.state.isReceiving { return "RX" }
        return "IDLE"
    }
}

private struct WidgetSurface: View {
    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            LinearGradient(
                colors: [Color.primary.opacity(0.055), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct TransportPill: View {
    let label: String
    let preset: String
    let systemImage: String
    let active: Bool
    let muted: Bool

    private var stateColor: Color {
        guard active else { return .secondary }
        return muted ? .red : .green
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(stateColor)

            Text(preset)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .allowsTightening(true)

            Spacer(minLength: 0)

            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(stateColor)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        .opacity(active ? 1 : 0.68)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(preset), \(active ? (muted ? "muted" : "active") : "inactive")")
    }
}

private struct ControlButton<I: AppIntent>: View {
    let systemImage: String
    let accessibilityText: String
    let enabled: Bool
    let active: Bool
    let muted: Bool
    let minHeight: CGFloat
    let intent: I

    private var tint: Color {
        guard active else { return .gray }
        return muted ? .red : .green
    }

    var body: some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!enabled)
        .accessibilityLabel(accessibilityText)
    }
}
