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
                presetName: "Studio",
                destination: "192.168.1.40:6980",
                streamName: "MisMeeter",
                startedAt: .now.addingTimeInterval(-420),
                status: "Duplex live"
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
        .description("A dedicated Send and Receive dashboard, separate from the Live Activity.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct MisMeeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MisMeeterEntry

    private var isActive: Bool { entry.state.isStreaming || entry.state.isReceiving }

    private var overallStatus: String {
        guard isActive else { return "Ready" }
        if entry.state.isStreaming && entry.state.isReceiving { return "Send + Receive" }
        if entry.state.isStreaming { return "Sending" }
        return "Receiving"
    }

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
            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(entry.state.presetName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 7, height: 7)
            }

            VStack(spacing: 6) {
                transportRow(
                    title: "Receive",
                    systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: entry.state.isReceiving,
                    muted: entry.state.isReceiveMuted
                )
                transportRow(
                    title: "Send",
                    systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: entry.state.isStreaming,
                    muted: entry.state.isMuted
                )
            }

            Spacer(minLength: 0)

            if isActive {
                HStack(spacing: 6) {
                    compactIntentButton(
                        systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        disabled: !entry.state.isReceiving,
                        intent: ToggleReceiveMuteIntent()
                    )
                    compactIntentButton(
                        systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill",
                        disabled: !entry.state.isStreaming,
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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.state.presetName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text(overallStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Text(entry.state.streamName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 9) {
                dashboardTile(
                    title: "Receive",
                    detail: entry.state.isReceiving ? (entry.state.isReceiveMuted ? "Muted" : "Listening") : "Idle",
                    systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: entry.state.isReceiving,
                    muted: entry.state.isReceiveMuted
                )
                dashboardTile(
                    title: "Send",
                    detail: entry.state.isStreaming ? (entry.state.isMuted ? "Muted" : "On air") : "Idle",
                    systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: entry.state.isStreaming,
                    muted: entry.state.isMuted
                )
            }

            HStack(spacing: 8) {
                if isActive {
                    Button(intent: ToggleReceiveMuteIntent()) {
                        Label(entry.state.isReceiveMuted ? "RX on" : "Mute RX", systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.state.isReceiving)

                    Button(intent: ToggleMuteIntent()) {
                        Label(entry.state.isMuted ? "Mic on" : "Mute mic", systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill")
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
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
            Text(entry.state.presetName)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 8) {
                Label(receiveShortStatus, systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.1.fill")
                Label(sendShortStatus, systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .widgetURL(URL(string: "mismeeter://home"))
    }

    private var activeCountText: String {
        let count = (entry.state.isStreaming ? 1 : 0) + (entry.state.isReceiving ? 1 : 0)
        return count == 0 ? "Idle" : "\(count)/2"
    }

    private var receiveShortStatus: String {
        guard entry.state.isReceiving else { return "RX idle" }
        return entry.state.isReceiveMuted ? "RX muted" : "RX on"
    }

    private var sendShortStatus: String {
        guard entry.state.isStreaming else { return "TX idle" }
        return entry.state.isMuted ? "TX muted" : "TX on"
    }

    // MARK: Building blocks

    private func transportRow(title: String, systemImage: String, active: Bool, muted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)
                .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(active ? (muted ? "Muted" : "Active") : "Idle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func dashboardTile(title: String, detail: String, systemImage: String, active: Bool, muted: Bool) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill((active ? (muted ? Color.red : Color.green) : Color.secondary).opacity(0.13))
                    .frame(width: 32, height: 32)
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func compactIntentButton<I: AppIntent>(systemImage: String, disabled: Bool, intent: I) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }
}
