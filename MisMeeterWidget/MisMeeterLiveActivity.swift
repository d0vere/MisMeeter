import ActivityKit
import SwiftUI
import WidgetKit

struct MisMeeterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MicActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(
                    context.state.isMuted
                        ? Color.red.opacity(0.72)
                        : Color.green.opacity(0.72)
                )
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.state.isMuted ? "MUTED" : "LIVE",
                        systemImage: context.state.isMuted
                            ? "mic.slash.fill"
                            : "mic.fill"
                    )
                    .font(.headline)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing) {
                        Text(context.state.presetLabel)
                            .font(.caption.bold())

                        Text(context.state.destinationLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: ToggleMuteIntent()) {
                        Label(
                            context.state.isMuted ? "UNMUTE" : "MUTE",
                            systemImage: context.state.isMuted
                                ? "mic.fill"
                                : "mic.slash.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                }

            } compactLeading: {
                Button(intent: ToggleMuteIntent()) {
                    Image(
                        systemName: context.state.isMuted
                            ? "mic.slash.fill"
                            : "mic.fill"
                    )
                }
                .buttonStyle(.plain)

            } compactTrailing: {
                Text(context.state.isMuted ? "OFF" : "ON")
                    .font(.caption2.bold())

            } minimal: {
                Image(
                    systemName: context.state.isMuted
                        ? "mic.slash.fill"
                        : "mic.fill"
                )
            }
            .keylineTint(context.state.isMuted ? .red : .green)
        }
    }

    @ViewBuilder
    private func lockScreenView(
        _ context: ActivityViewContext<MicActivityAttributes>
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Image(
                    systemName: context.state.isMuted
                        ? "mic.slash.circle.fill"
                        : "mic.circle.fill"
                )
                .font(.system(size: 38))

                VStack(alignment: .leading, spacing: 3) {
                    Text("MisMeeter")
                        .font(.headline)

                    Text(
                        context.state.isMuted
                            ? "MICROPHONE MUTED"
                            : "MICROPHONE ACTIVE"
                    )
                    .font(.subheadline.bold())

                    Text(
                        "\(context.state.presetLabel) • \(context.state.destinationLabel)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Button(intent: ToggleMuteIntent()) {
                Label(
                    context.state.isMuted
                        ? "UNMUTE MICROPHONE"
                        : "MUTE MICROPHONE",
                    systemImage: context.state.isMuted
                        ? "mic.fill"
                        : "mic.slash.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
