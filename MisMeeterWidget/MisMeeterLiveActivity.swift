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
                // Keep the RX/TX indicators in the same visual anchors used by the
                // compact island. Expanded content grows around them instead of
                // pushing the indicators toward the outer clipped edges.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if context.state.isReceiving {
                            receiveIndicator(context.state)
                                .accessibilityLabel(context.state.isReceiveMuted ? "Receive audio muted" : "Receive audio active")
                        }
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("Live")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 0) {
                        if context.state.isStreaming {
                            microphoneIndicator(context.state)
                                .accessibilityLabel(context.state.isMuted ? "Microphone muted" : "Microphone active")
                        }
                        Spacer(minLength: 0)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        activityControl(
                            title: context.state.isReceiveMuted ? "Audio on" : "Mute RX",
                            systemImage: context.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            enabled: context.state.isReceiving,
                            tint: context.state.isReceiveMuted ? .green : .blue,
                            intent: ToggleReceiveMuteIntent()
                        )

                        activityControl(
                            title: context.state.isMuted ? "Mic on" : "Mute Mic",
                            systemImage: context.state.isMuted ? "mic.fill" : "mic.slash.fill",
                            enabled: context.state.isStreaming,
                            tint: context.state.isMuted ? .green : .orange,
                            intent: ToggleMuteIntent()
                        )

                        Button(intent: EndLiveActivityIntent()) {
                            VStack(spacing: 5) {
                                Image(systemName: "stop.fill")
                                    .font(.title3.weight(.bold))
                                Text("Stop all")
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                if context.state.isReceiving {
                    receiveIndicator(context.state)
                        .accessibilityLabel(context.state.isReceiveMuted ? "Receive audio muted" : "Receive audio active")
                }
            } compactTrailing: {
                if context.state.isStreaming {
                    microphoneIndicator(context.state)
                        .accessibilityLabel(context.state.isMuted ? "Microphone muted" : "Microphone active")
                }
            } minimal: {
                if context.state.isStreaming {
                    microphoneIndicator(context.state)
                } else {
                    receiveIndicator(context.state)
                }
            }
            .keylineTint(isAnyMuted(context.state) ? .red : .green)
        }
    }

    @ViewBuilder
    private func receiveIndicator(_ state: MicActivityAttributes.ContentState) -> some View {
        Image(systemName: state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(state.isReceiveMuted ? .red : .green)
    }

    @ViewBuilder
    private func microphoneIndicator(_ state: MicActivityAttributes.ContentState) -> some View {
        Image(systemName: state.isMuted ? "mic.slash.fill" : "mic.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(state.isMuted ? .red : .green)
    }

    private func isAnyMuted(_ state: MicActivityAttributes.ContentState) -> Bool {
        (state.isStreaming && state.isMuted) || (state.isReceiving && state.isReceiveMuted)
    }

    private func activityControl<I: AppIntent>(
        title: String,
        systemImage: String,
        enabled: Bool,
        tint: Color,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(!enabled)
    }
}

private struct LockActivityView: View {
    let context: ActivityViewContext<MicActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                stateBadge(
                    systemImage: context.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: context.state.isReceiving,
                    muted: context.state.isReceiveMuted
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live")
                        .font(.headline)
                    Text(context.state.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                stateBadge(
                    systemImage: context.state.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: context.state.isStreaming,
                    muted: context.state.isMuted
                )
            }

            HStack(spacing: 10) {
                Button(intent: ToggleReceiveMuteIntent()) {
                    Label(
                        context.state.isReceiveMuted ? "Audio on" : "Mute RX",
                        systemImage: context.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(context.state.isReceiveMuted ? .green : .blue)
                .disabled(!context.state.isReceiving)

                Button(intent: ToggleMuteIntent()) {
                    Label(
                        context.state.isMuted ? "Mic on" : "Mute Mic",
                        systemImage: context.state.isMuted ? "mic.fill" : "mic.slash.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(context.state.isMuted ? .green : .orange)
                .disabled(!context.state.isStreaming)

                Button(intent: EndLiveActivityIntent()) {
                    Label("Stop all", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func stateBadge(systemImage: String, active: Bool, muted: Bool) -> some View {
        ZStack {
            Circle()
                .fill((muted ? Color.red : Color.green).opacity(active ? 0.16 : 0.06))
                .frame(width: 38, height: 38)
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
        }
    }
}
