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
            transportSummaryRow

            Spacer(minLength: 0)

            widgetControls(minHeight: 30)
        }
    }

    // MARK: Home Screen medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            transportSummaryRow

            Spacer(minLength: 0)

            widgetControls(minHeight: 32)
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

    private var transportSummaryRow: some View {
        HStack(spacing: 6) {
            Group {
                Text("RX - ")
                    .fontWeight(.bold)
                + Text(entry.state.receivePresetName)
                + Text("   TX - ")
                    .fontWeight(.bold)
                + Text(entry.state.sendPresetName)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .allowsTightening(true)

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                statusIcon(
                    systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: entry.state.isReceiving,
                    muted: entry.state.isReceiveMuted
                )
                statusIcon(
                    systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: entry.state.isStreaming,
                    muted: entry.state.isMuted
                )
            }
            .fixedSize()
        }
    }

    @ViewBuilder
    private func widgetControls(minHeight: CGFloat) -> some View {
        if isActive {
            HStack(spacing: 6) {
                compactIntentButton(
                    systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    disabled: !entry.state.isReceiving,
                    tint: transportTint(active: entry.state.isReceiving, muted: entry.state.isReceiveMuted),
                    minHeight: minHeight,
                    intent: ToggleReceiveMuteIntent()
                )
                compactIntentButton(
                    systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill",
                    disabled: !entry.state.isStreaming,
                    tint: transportTint(active: entry.state.isStreaming, muted: entry.state.isMuted),
                    minHeight: minHeight,
                    intent: ToggleMuteIntent()
                )
                Button(intent: EndLiveActivityIntent()) {
                    Image(systemName: "stop.fill")
                        .frame(maxWidth: .infinity, minHeight: minHeight)
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
                .frame(maxWidth: .infinity, minHeight: minHeight)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var activeCountText: String {
        let count = (entry.state.isStreaming ? 1 : 0) + (entry.state.isReceiving ? 1 : 0)
        return count == 0 ? "Idle" : "\(count)/2"
    }

    // MARK: Building blocks


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

    private func compactIntentButton<I: AppIntent>(systemImage: String, disabled: Bool, tint: Color, minHeight: CGFloat, intent: I) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: minHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(disabled)
    }
}
