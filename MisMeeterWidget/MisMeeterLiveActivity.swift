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
                // Expanded mode deliberately leaves the physical camera/sensor area clear.
                // RX is kept on the left and TX on the right, with the preset labels growing
                // outward from their indicators instead of putting content over the camera.
                DynamicIslandExpandedRegion(.leading) {
                    // RX: preset label first, speaker immediately to its right.
                    // The whole cluster is anchored to the inner edge of the leading region,
                    // so the speaker stays next to the physical island instead of drifting outward.
                    HStack(spacing: 4) {
                        Text(context.state.receivePresetLabel)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                            .allowsTightening(true)

                        if context.state.isReceiving {
                            receiveIndicator(context.state)
                                .fixedSize()
                                .accessibilityLabel(context.state.isReceiveMuted ? "Receive audio muted" : "Receive audio active")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.center) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if context.state.isStreaming {
                            microphoneIndicator(context.state)
                                .fixedSize()
                                .accessibilityLabel(context.state.isMuted ? "Microphone muted" : "Microphone active")
                        }
                        Text(context.state.sendPresetLabel)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                            .allowsTightening(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        activityControl(
                            title: context.state.isReceiveMuted ? "Audio on" : "Mute RX",
                            systemImage: context.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            enabled: context.state.isReceiving,
                            tint: transportTint(active: context.state.isReceiving, muted: context.state.isReceiveMuted),
                            intent: ToggleReceiveMuteIntent()
                        )

                        activityControl(
                            title: context.state.isMuted ? "Mic on" : "Mute Mic",
                            systemImage: context.state.isMuted ? "mic.fill" : "mic.slash.fill",
                            enabled: context.state.isStreaming,
                            tint: transportTint(active: context.state.isStreaming, muted: context.state.isMuted),
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

    private func transportTint(active: Bool, muted: Bool) -> Color {
        guard active else { return .gray }
        return muted ? .red : .green
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("RX · \(context.state.receivePresetLabel)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    stateBadge(
                        systemImage: context.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        active: context.state.isReceiving,
                        muted: context.state.isReceiveMuted
                    )
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("TX · \(context.state.sendPresetLabel)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    stateBadge(
                        systemImage: context.state.isMuted ? "mic.slash.fill" : "mic.fill",
                        active: context.state.isStreaming,
                        muted: context.state.isMuted
                    )
                }
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
                .tint(transportTint(active: context.state.isReceiving, muted: context.state.isReceiveMuted))
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
                .tint(transportTint(active: context.state.isStreaming, muted: context.state.isMuted))
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

    private func transportTint(active: Bool, muted: Bool) -> Color {
        guard active else { return .gray }
        return muted ? .red : .green
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
