import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct MisMeeterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MicActivityAttributes.self) { context in
            LockActivityView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        Image(systemName: context.state.isMuted ? "mic.slash.fill" : "waveform.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.isMuted ? "Muted" : "On Air")
                                .font(.headline)
                            Text(context.state.presetLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let start = context.state.startedAt, context.state.isStreaming {
                            Text(start, style: .timer)
                                .font(.caption.monospacedDigit())
                        }
                        Text(context.state.isReceiving ? "Duplex" : "TX")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        HStack {
                            Image(systemName: "network")
                            Text(context.state.destinationLabel)
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button(intent: ToggleMuteIntent()) {
                                Label(context.state.isMuted ? "Unmute" : "Mute",
                                      systemImage: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button(intent: EndLiveActivityIntent()) {
                                Label("Stop", systemImage: "stop.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "waveform")
                    .foregroundStyle(context.state.isMuted ? .orange : .green)
            } compactTrailing: {
                if let start = context.state.startedAt, context.state.isStreaming {
                    Text(start, style: .timer)
                        .font(.caption2.monospacedDigit())
                } else {
                    Text(context.state.statusLabel)
                        .font(.caption2.weight(.semibold))
                }
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "waveform")
                    .foregroundStyle(context.state.isMuted ? .orange : .green)
            }
            .keylineTint(context.state.isMuted ? .orange : .green)
        }
    }
}

private struct LockActivityView: View {
    let context: ActivityViewContext<MicActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 48, height: 48)
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "waveform")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(context.state.isMuted ? .orange : .green)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("MisMeeter")
                        .font(.headline)
                    Text(context.state.statusLabel.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(context.state.isMuted ? .orange : .green)
                }
                Text(context.state.presetLabel)
                    .font(.subheadline.weight(.semibold))
                Text(context.state.destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                if let start = context.state.startedAt, context.state.isStreaming {
                    Text(start, style: .timer)
                        .font(.caption.monospacedDigit())
                }
                HStack(spacing: 8) {
                    Button(intent: ToggleMuteIntent()) {
                        Image(systemName: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(intent: EndLiveActivityIntent()) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
    }
}
