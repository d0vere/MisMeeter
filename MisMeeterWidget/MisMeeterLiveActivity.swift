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
                        Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(context.state.isMuted ? .red : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.isMuted ? "Muted" : "Microphone live")
                                .font(.headline)
                            Text(context.state.presetLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 8) {
                        Button(intent: ToggleMuteIntent()) {
                            Image(systemName: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                        }
                        .buttonStyle(.bordered)

                        Button(intent: EndLiveActivityIntent()) {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.state.isMuted ? .red : .green)
                    .accessibilityLabel(context.state.isMuted ? "Microphone muted" : "Microphone active")
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(context.state.isMuted ? .red : .green)
            }
            .keylineTint(context.state.isMuted ? .red : .green)
        }
    }
}

private struct LockActivityView: View {
    let context: ActivityViewContext<MicActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((context.state.isMuted ? Color.red : Color.green).opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(context.state.isMuted ? .red : .green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.isMuted ? "Microphone muted" : "Microphone live")
                    .font(.headline)
                Text(context.state.destinationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 8) {
                Button(intent: ToggleMuteIntent()) {
                    Image(systemName: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                }
                .buttonStyle(.bordered)

                Button(intent: EndLiveActivityIntent()) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
