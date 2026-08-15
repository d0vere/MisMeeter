import ActivityKit
import WidgetKit
import SwiftUI


struct MisMeeterLiveActivity: Widget {

    var body: some WidgetConfiguration {

        ActivityConfiguration(
            for: MicActivityAttributes.self
        ) { context in

            lockScreenView(context)

                .activityBackgroundTint(
                    context.state.isMuted
                        ? Color.red.opacity(0.75)
                        : Color.green.opacity(0.75)
                )

                .activitySystemActionForegroundColor(
                    .white
                )

        } dynamicIsland: { context in

            DynamicIsland {

                /*
                 EXPANDED - LEADING
                 */

                DynamicIslandExpandedRegion(
                    .leading
                ) {

                    HStack {

                        Image(
                            systemName:
                                context.state.isMuted
                                ? "mic.slash.fill"
                                : "mic.fill"
                        )

                        Text(
                            context.state.isMuted
                                ? "MUTED"
                                : "LIVE"
                        )
                        .font(.headline)
                    }
                }


                /*
                 EXPANDED - TRAILING
                 */

                DynamicIslandExpandedRegion(
                    .trailing
                ) {

                    Text(
                        context.state.connectionLabel
                    )

                    .font(.caption)

                    .foregroundStyle(
                        .secondary
                    )
                }


                /*
                 EXPANDED - BOTTOM
                 */

                DynamicIslandExpandedRegion(
                    .bottom
                ) {

                    VStack(spacing: 8) {

                        Text(
                            context.state.isMuted
                                ? "Microphone is muted"
                                : "Microphone is active"
                        )

                        .font(.caption)


                        Button(
                            intent: ToggleMuteIntent()
                        ) {

                            Label(

                                context.state.isMuted
                                    ? "UNMUTE"
                                    : "MUTE",

                                systemImage:
                                    context.state.isMuted
                                    ? "mic.fill"
                                    : "mic.slash.fill"
                            )

                            .font(.headline)

                            .frame(
                                maxWidth: .infinity
                            )

                            .padding(.vertical, 4)
                        }

                        .buttonStyle(
                            .borderedProminent
                        )
                    }
                }

            }


            /*
             DYNAMIC ISLAND COMPACT LEADING

             Esperimento:
             proviamo un vero Button/AppIntent
             direttamente nella compact region.
             */

            compactLeading: {

                Button(
                    intent: ToggleMuteIntent()
                ) {

                    Image(
                        systemName:
                            context.state.isMuted
                            ? "mic.slash.fill"
                            : "mic.fill"
                    )

                    .font(.headline)
                }

                .buttonStyle(.plain)
            }


            /*
             COMPACT TRAILING
             */

            compactTrailing: {

                Text(
                    context.state.isMuted
                        ? "OFF"
                        : "ON"
                )

                .font(.caption2.bold())
            }


            /*
             MINIMAL
             */

            minimal: {

                Image(
                    systemName:
                        context.state.isMuted
                        ? "mic.slash.fill"
                        : "mic.fill"
                )
            }


            .keylineTint(
                context.state.isMuted
                    ? .red
                    : .green
            )
        }
    }


    /*
     LOCK SCREEN
     */

    @ViewBuilder
    private func lockScreenView(
        _ context:
            ActivityViewContext<
                MicActivityAttributes
            >
    ) -> some View {

        VStack(spacing: 14) {

            HStack(spacing: 14) {

                Image(
                    systemName:
                        context.state.isMuted
                        ? "mic.slash.circle.fill"
                        : "mic.circle.fill"
                )

                .font(
                    .system(size: 38)
                )


                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {

                    Text("MisMeeter")

                        .font(
                            .headline
                        )


                    Text(
                        context.state.isMuted
                            ? "MICROPHONE MUTED"
                            : "MICROPHONE ACTIVE"
                    )

                    .font(
                        .subheadline.bold()
                    )


                    Text(
                        context.attributes.sessionName
                        +
                        " • "
                        +
                        context.state.connectionLabel
                    )

                    .font(.caption)

                    .foregroundStyle(
                        .secondary
                    )
                }


                Spacer()
            }


            Button(
                intent: ToggleMuteIntent()
            ) {

                HStack {

                    Image(
                        systemName:
                            context.state.isMuted
                            ? "mic.fill"
                            : "mic.slash.fill"
                    )


                    Text(
                        context.state.isMuted
                            ? "UNMUTE MICROPHONE"
                            : "MUTE MICROPHONE"
                    )
                }

                .font(.headline)

                .frame(
                    maxWidth: .infinity
                )

                .padding(
                    .vertical,
                    5
                )
            }

            .buttonStyle(
                .borderedProminent
            )
        }

        .padding()
    }
}
