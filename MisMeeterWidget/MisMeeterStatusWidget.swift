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
        .configurationDisplayName("MisMeeter Control")
        .description("Monitor and control MisMeeter transmit and receive audio.")
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

    private var small: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                statusIcon(systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: entry.state.isReceiving, muted: entry.state.isReceiveMuted)
                statusIcon(systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill", active: entry.state.isStreaming, muted: entry.state.isMuted)
                Spacer()
                Text(isActive ? "LIVE" : "READY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Text(entry.state.status)
                .font(.headline)
                .lineLimit(1)
            Text(entry.state.presetName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if isActive {
                HStack(spacing: 6) {
                    Button(intent: ToggleReceiveMuteIntent()) {
                        Image(systemName: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.state.isReceiving)

                    Button(intent: ToggleMuteIntent()) {
                        Image(systemName: entry.state.isMuted ? "mic.fill" : "mic.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.state.isStreaming)

                    Button(intent: EndLiveActivityIntent()) {
                        Image(systemName: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Link(destination: URL(string: "mismeeter://home")!) {
                    Label("Open", systemImage: "arrow.up.forward.app.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    statusIcon(systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: entry.state.isReceiving, muted: entry.state.isReceiveMuted)
                    statusIcon(systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill", active: entry.state.isStreaming, muted: entry.state.isMuted)
                    Text("MisMeeter")
                        .font(.headline)
                }
                Text(isActive ? entry.state.status : "Ready")
                    .font(.title3.weight(.semibold))
                Text(entry.state.destination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                HStack(spacing: 8) {
                    Button(intent: ToggleReceiveMuteIntent()) {
                        Image(systemName: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.state.isReceiving)

                    Button(intent: ToggleMuteIntent()) {
                        Image(systemName: entry.state.isMuted ? "mic.fill" : "mic.slash.fill")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!entry.state.isStreaming)

                    Button(intent: EndLiveActivityIntent()) {
                        Image(systemName: "stop.fill")
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Link(destination: URL(string: "mismeeter://home")!) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            HStack(spacing: 2) {
                if entry.state.isReceiving { Image(systemName: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.1.fill") }
                if entry.state.isStreaming { Image(systemName: entry.state.isMuted ? "mic.slash.fill" : "mic.fill") }
                if !isActive { Image(systemName: "waveform.badge.plus") }
            }
            .font(.caption.weight(.bold))
        }
        .widgetAccentable()
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(isActive ? "MisMeeter Live" : "MisMeeter Ready", systemImage: isActive ? "waveform" : "waveform.badge.plus")
                .font(.headline)
            Text(isActive ? entry.state.status : "Tap to open")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .widgetURL(URL(string: "mismeeter://home"))
    }

    private func statusIcon(systemImage: String, active: Bool, muted: Bool) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
            .widgetAccentable()
    }
}
