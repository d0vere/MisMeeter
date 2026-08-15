import ActivityKit
import WidgetKit
import SwiftUI

struct MisMeeterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MicActivityAttributes.self) { context in
            lockScreenView(context)
                .activityBackgroundTint(.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(
                        context.state.isMuted ? "Muted" : "Live",
                        systemImage: context.state.isMuted ? "mic.slash.fill" : "mic.fill"
                    )
                    .font(.headline)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.connectionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Button(intent: ToggleMuteIntent()) {
                        Label(
                            context.state.isMuted ? "Unmute" : "Mute",
                            systemImage: context.state.isMuted ? "mic.fill" : "mic.slash.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } compactLeading: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
            } compactTrailing: {
                Text(context.state.isMuted ? "OFF" : "ON")
                    .font(.caption2.bold())
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .widgetURL(URL(string: "mismeeter://activity"))
            .keylineTint(context.state.isMuted ? .orange : .green)
        }
    }

    @ViewBuilder
    private func lockScreenView(_ context: ActivityViewContext<MicActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: context.state.isMuted ? "mic.slash.circle.fill" : "mic.circle.fill")
                .font(.system(size: 36))

            VStack(alignment: .leading, spacing: 4) {
                Text("MisMeeter")
                    .font(.headline)

                Text(context.state.isMuted ? "MICROPHONE MUTED" : "MICROPHONE ACTIVE")
                    .font(.subheadline.bold())

                Text(context.attributes.sessionName + " • " + context.state.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(intent: ToggleMuteIntent()) {
                Image(systemName: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                    .font(.title3)
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(context.state.isMuted ? "Unmute" : "Mute")
        }
        .padding()
    }
}
