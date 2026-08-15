import SwiftUI
import ActivityKit

struct ContentView: View {

    @State private var status =
        "Live Activity non avviata"

    @State private var isRunning = false


    var body: some View {

        NavigationStack {

            VStack(spacing: 24) {

                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))

                Text("MisMeeter")
                    .font(.largeTitle.bold())

                Text("Live Activity Debug Build")
                    .foregroundStyle(.secondary)


                Text(status)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)


                Button {

                    Task {

                        if isRunning {

                            await stopActivities()

                        } else {

                            startActivity()

                        }
                    }

                } label: {

                    Label(
                        isRunning
                            ? "Stop Live Activity"
                            : "Start Live Activity",

                        systemImage:
                            isRunning
                            ? "stop.fill"
                            : "play.fill"
                    )

                    .frame(maxWidth: .infinity)

                    .padding(.vertical, 8)
                }

                .buttonStyle(.borderedProminent)


                if isRunning {

                    Button {

                        Task {

                            await toggleFromApp()

                        }

                    } label: {

                        Label(
                            "Toggle Mic dall'app",
                            systemImage: "mic.fill"
                        )

                        .frame(maxWidth: .infinity)

                        .padding(.vertical, 8)
                    }

                    .buttonStyle(.bordered)
                }


                Text(
                    """
                    DEBUG: verde = microfono ON
                    rosso = microfono MUTED

                    Il microfono reale non viene ancora acquisito.
                    """
                )

                .font(.footnote)

                .foregroundStyle(.secondary)

                .multilineTextAlignment(.center)


                Spacer()
            }

            .padding()

            .navigationTitle("MisMeeter")

            .task {

                refreshStatus()

            }
        }
    }


    private func startActivity() {

        guard ActivityAuthorizationInfo()
            .areActivitiesEnabled
        else {

            status =
                "Live Activities disabilitate nelle impostazioni iOS."

            return
        }


        if !Activity<MicActivityAttributes>
            .activities
            .isEmpty
        {

            status =
                "Una Live Activity MisMeeter è già attiva."

            isRunning = true

            return
        }


        let attributes =
            MicActivityAttributes(
                sessionName: "PC Microphone"
            )


        let initialState =
            MicActivityAttributes.ContentState(
                isMuted: false,
                connectionLabel: "Prototype"
            )


        do {

            let content =
                ActivityContent(
                    state: initialState,
                    staleDate: nil
                )


            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )


            status =
                """
                Live Activity avviata.
                Verde = ON.
                Rosso = MUTED.
                """


            isRunning = true

        } catch {

            status =
                """
                Errore ActivityKit:
                \(error.localizedDescription)
                """


            isRunning = false
        }
    }


    private func toggleFromApp() async {

        let activities =
            Activity<MicActivityAttributes>
            .activities


        for activity in activities {

            let oldState =
                activity.content.state


            let newState =
                MicActivityAttributes.ContentState(
                    isMuted: !oldState.isMuted,
                    connectionLabel:
                        oldState.connectionLabel
                )


            await activity.update(

                ActivityContent(
                    state: newState,
                    staleDate: nil
                )
            )
        }


        status =
            "Toggle eseguito direttamente dall'app."
    }


    private func stopActivities() async {

        let finalState =
            MicActivityAttributes.ContentState(
                isMuted: true,
                connectionLabel: "Stopped"
            )


        for activity
        in Activity<MicActivityAttributes>
            .activities
        {

            await activity.end(

                ActivityContent(
                    state: finalState,
                    staleDate: nil
                ),

                dismissalPolicy: .immediate
            )
        }


        status =
            "Live Activity terminata."


        isRunning = false
    }


    private func refreshStatus() {

        isRunning =
            !Activity<MicActivityAttributes>
                .activities
                .isEmpty


        if isRunning {

            status =
                "Live Activity già attiva."
        }
    }
}


#Preview {

    ContentView()
}
