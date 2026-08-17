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
        .description("Monitor the active VBAN stream and control the microphone.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct MisMeeterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MisMeeterEntry

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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: entry.state.isMuted ? "mic.slash.fill" : "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(entry.state.isMuted ? .red : (entry.state.isStreaming ? .green : .secondary))
                    .widgetAccentable()
                Spacer()
                Text(entry.state.isStreaming ? "LIVE" : "READY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Text(entry.state.presetName)
                .font(.headline)
                .lineLimit(1)
            Text(entry.state.destination)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if entry.state.isStreaming {
                HStack(spacing: 8) {
                    Button(intent: ToggleMuteIntent()) {
                        Image(systemName: entry.state.isMuted ? "mic.fill" : "mic.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(intent: EndLiveActivityIntent()) {
                        Image(systemName: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
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
                Label("MisMeeter", systemImage: "waveform.circle.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.state.isStreaming ? (entry.state.isMuted ? "Microphone muted" : "Streaming") : "Ready to stream")
                    .font(.title3.weight(.semibold))
                Text(entry.state.destination)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let start = entry.state.startedAt, entry.state.isStreaming {
                    Text(start, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                if entry.state.isStreaming {
                    Button(intent: ToggleMuteIntent()) {
                        Image(systemName: entry.state.isMuted ? "mic.fill" : "mic.slash.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(intent: EndLiveActivityIntent()) {
                        Image(systemName: "stop.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Link(destination: URL(string: "mismeeter://home")!) {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: entry.state.isMuted ? "mic.slash.fill" : (entry.state.isStreaming ? "waveform" : "waveform.badge.plus"))
                .font(.title3)
        }
        .widgetAccentable()
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.state.isStreaming ? "MisMeeter Live" : "MisMeeter Ready",
                  systemImage: entry.state.isMuted ? "mic.slash.fill" : "waveform")
                .font(.headline)
            Text(entry.state.isStreaming ? entry.state.presetName : "Tap to open")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .widgetURL(URL(string: "mismeeter://home"))
    }
}
