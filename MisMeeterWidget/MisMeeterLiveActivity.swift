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
                // Keep both transport indicators on the leading side of the physical
                // camera/sensor area. The trailing side is intentionally text-only so
                // compact mode never places the TX microphone on the right edge.
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        expandedTransportBadge(
                            prefix: "RX",
                            systemImage: context.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                            active: context.state.isReceiving,
                            muted: context.state.isReceiveMuted
                        )

                        expandedTransportBadge(
                            prefix: "TX",
                            systemImage: context.state.isMuted ? "mic.slash.fill" : "mic.fill",
                            active: context.state.isStreaming,
                            muted: context.state.isMuted
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityElement(children: .combine)
                }

                DynamicIslandExpandedRegion(.center) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.statusLabel)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(context.state.sendPresetLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
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
                compactTransportPair(context.state)
                    .padding(.leading, 1)
                    .accessibilityLabel(compactAccessibilityLabel(context.state))
            } compactTrailing: {
                EmptyView()
            } minimal: {
                if context.state.isStreaming {
                    compactIndicator(
                        systemImage: context.state.isMuted ? "mic.slash.fill" : "mic.fill",
                        active: true,
                        muted: context.state.isMuted
                    )
                } else {
                    compactIndicator(
                        systemImage: context.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        active: context.state.isReceiving,
                        muted: context.state.isReceiveMuted
                    )
                }
            }
            .keylineTint(isAnyMuted(context.state) ? .red : .green)
        }
    }

    @ViewBuilder
    private func expandedTransportBadge(prefix: String, systemImage: String, active: Bool, muted: Bool) -> some View {
        HStack(spacing: 3) {
            Text(prefix)
                .font(.caption2.weight(.bold))
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .symbolRenderingMode(.monochrome)
        }
        .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
        .opacity(active ? 1.0 : 0.48)
        .fixedSize()
    }

    @ViewBuilder
    private func compactTransportPair(_ state: MicActivityAttributes.ContentState) -> some View {
        HStack(spacing: 2) {
            compactIndicator(
                systemImage: state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                active: state.isReceiving,
                muted: state.isReceiveMuted
            )
            compactIndicator(
                systemImage: state.isMuted ? "mic.slash.fill" : "mic.fill",
                active: state.isStreaming,
                muted: state.isMuted
            )
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    @ViewBuilder
    private func compactIndicator(systemImage: String, active: Bool, muted: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10.5, weight: .bold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(active ? (muted ? Color.red : Color.green) : Color.secondary)
            .opacity(active ? 1.0 : 0.45)
            .frame(width: 13, height: 18, alignment: .center)
    }

    private func compactAccessibilityLabel(_ state: MicActivityAttributes.ContentState) -> String {
        let rx = state.isReceiving ? (state.isReceiveMuted ? "RX muted" : "RX active") : "RX idle"
        let tx = state.isStreaming ? (state.isMuted ? "TX muted" : "TX active") : "TX idle"
        return "\(rx), \(tx)"
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
