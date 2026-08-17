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
                presetName: "Studio TX",
                sendPresetName: "Studio TX",
                receivePresetName: "Control Room",
                destination: "192.168.1.40:6980",
                streamName: "MisMeeter",
                startedAt: .now.addingTimeInterval(-420),
                status: "Active"
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
                .containerBackground(for: .widget) {
                    Color(uiColor: .secondarySystemBackground)
                }
        }
        .configurationDisplayName("MisMeeter Dashboard")
        .description("Send and Receive presets, status and controls at a glance.")
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

    // MARK: - Home Screen small

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            widgetHeader(compact: true)

            VStack(spacing: 7) {
                compactTransportRow(
                    title: "RX",
                    preset: entry.state.receivePresetName,
                    systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: entry.state.isReceiving,
                    muted: entry.state.isReceiveMuted
                )

                compactTransportRow(
                    title: "TX",
                    preset: entry.state.sendPresetName,
                    systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: entry.state.isStreaming,
                    muted: entry.state.isMuted
                )
            }

            if isActive {
                controlBar(compact: true)
            } else {
                openAppButton
            }
        }
    }

    // MARK: - Home Screen medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(compact: false)

            HStack(spacing: 10) {
                transportCard(
                    title: "RECEIVE",
                    preset: entry.state.receivePresetName,
                    systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    active: entry.state.isReceiving,
                    muted: entry.state.isReceiveMuted
                )

                transportCard(
                    title: "TRANSMIT",
                    preset: entry.state.sendPresetName,
                    systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill",
                    active: entry.state.isStreaming,
                    muted: entry.state.isMuted
                )
            }

            Spacer(minLength: 0)

            if isActive {
                controlBar(compact: false)
            } else {
                openAppButton
            }
        }
    }

    // MARK: - Lock Screen widgets

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: isActive ? "waveform" : "waveform.slash")
                    .font(.caption.weight(.bold))

                Text(activeCountText)
                    .font(.caption2.weight(.bold))
            }
        }
        .widgetAccentable()
        .widgetURL(URL(string: "mismeeter://home"))
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.caption.weight(.bold))

                Text("MisMeeter")
                    .font(.caption.weight(.bold))

                Spacer(minLength: 2)

                Text(overallStatusLabel)
                    .font(.caption2.weight(.semibold))
            }

            HStack(spacing: 8) {
                accessoryTransportLabel(
                    prefix: "RX",
                    preset: entry.state.receivePresetName,
                    systemImage: entry.state.isReceiveMuted ? "speaker.slash.fill" : "speaker.wave.1.fill"
                )

                accessoryTransportLabel(
                    prefix: "TX",
                    preset: entry.state.sendPresetName,
                    systemImage: entry.state.isMuted ? "mic.slash.fill" : "mic.fill"
                )
            }
        }
        .widgetURL(URL(string: "mismeeter://home"))
    }

    // MARK: - Header

    private func widgetHeader(compact: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
                    .fill(.primary.opacity(0.08))

                Image(systemName: "waveform")
                    .font((compact ? Font.caption : Font.subheadline).weight(.bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: compact ? 22 : 30, height: compact ? 22 : 30)

            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text("MisMeeter")
                        .font(.subheadline.weight(.bold))
                    Text(statusSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("MisMeeter")
                    .font(.caption.weight(.bold))
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle()
                    .fill(overallStatusColor)
                    .frame(width: 7, height: 7)

                Text(overallStatusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.primary.opacity(0.055), in: Capsule())
        }
    }

    // MARK: - Transport presentation

    private func compactTransportRow(
        title: String,
        preset: String,
        systemImage: String,
        active: Bool,
        muted: Bool
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(transportColor(active: active, muted: muted).opacity(active ? 0.15 : 0.08))

                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(transportColor(active: active, muted: muted))
            }
            .frame(width: 23, height: 23)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(transportStateLabel(active: active, muted: muted))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(transportColor(active: active, muted: muted))
                }

                Text(preset)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func transportCard(
        title: String,
        preset: String,
        systemImage: String,
        active: Bool,
        muted: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(transportColor(active: active, muted: muted).opacity(active ? 0.15 : 0.08))

                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(transportColor(active: active, muted: muted))
                }
                .frame(width: 31, height: 31)

                Spacer(minLength: 4)

                Text(transportStateLabel(active: active, muted: muted))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(transportColor(active: active, muted: muted))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                Text(preset)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - Controls

    private func controlBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            intentControl(
                systemImage: entry.state.isReceiveMuted ? "speaker.wave.2.fill" : "speaker.slash.fill",
                accessibilityLabel: entry.state.isReceiveMuted ? "Unmute receive audio" : "Mute receive audio",
                disabled: !entry.state.isReceiving,
                foreground: transportColor(active: entry.state.isReceiving, muted: entry.state.isReceiveMuted),
                compact: compact,
                intent: ToggleReceiveMuteIntent()
            )

            intentControl(
                systemImage: entry.state.isMuted ? "mic.fill" : "mic.slash.fill",
                accessibilityLabel: entry.state.isMuted ? "Unmute microphone" : "Mute microphone",
                disabled: !entry.state.isStreaming,
                foreground: transportColor(active: entry.state.isStreaming, muted: entry.state.isMuted),
                compact: compact,
                intent: ToggleMuteIntent()
            )

            Button(intent: EndLiveActivityIntent()) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.fill")
                    if !compact {
                        Text("Stop")
                            .font(.caption.weight(.bold))
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 34)
                .background(.red.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop all audio")
        }
    }

    private func intentControl<I: AppIntent>(
        systemImage: String,
        accessibilityLabel: String,
        disabled: Bool,
        foreground: Color,
        compact: Bool,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(disabled ? Color.secondary : foreground)
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 34)
                .background(
                    (disabled ? Color.secondary : foreground).opacity(disabled ? 0.07 : 0.11),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var openAppButton: some View {
        Link(destination: URL(string: "mismeeter://home")!) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up.forward.app.fill")
                Text("Open MisMeeter")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 34)
            .padding(.horizontal, 10)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Accessory building blocks

    private func accessoryTransportLabel(prefix: String, preset: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text("\(prefix) · \(preset)")
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .font(.caption2.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - State helpers

    private var activeCountText: String {
        let count = (entry.state.isStreaming ? 1 : 0) + (entry.state.isReceiving ? 1 : 0)
        return count == 0 ? "Idle" : "\(count)/2"
    }

    private var overallStatusLabel: String {
        switch (entry.state.isReceiving, entry.state.isStreaming) {
        case (true, true): return "Duplex"
        case (true, false): return "RX Live"
        case (false, true): return "TX Live"
        case (false, false): return "Idle"
        }
    }

    private var statusSubtitle: String {
        guard isActive else { return "No active audio transport" }
        if entry.state.isReceiveMuted && entry.state.isMuted { return "RX and TX muted" }
        if entry.state.isReceiveMuted { return "Receive audio muted" }
        if entry.state.isMuted { return "Microphone muted" }
        return entry.state.isReceiving && entry.state.isStreaming ? "Receive and transmit active" : "Audio transport active"
    }

    private var overallStatusColor: Color {
        guard isActive else { return .secondary }
        return (entry.state.isReceiveMuted || entry.state.isMuted) ? .orange : .green
    }

    private func transportStateLabel(active: Bool, muted: Bool) -> String {
        guard active else { return "Off" }
        return muted ? "Muted" : "Live"
    }

    private func transportColor(active: Bool, muted: Bool) -> Color {
        guard active else { return .secondary }
        return muted ? .orange : .green
    }
}
