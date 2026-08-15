import SwiftUI
import ActivityKit

struct ContentView: View {
    @State private var status = "Live Activity non avviata"
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 78))

                Text("MisMeeter")
                    .font(.largeTitle.bold())

                Text("Test Live Activity + Dynamic Island")
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
                        isRunning ? "Stop Live Activity" : "Start Live Activity",
                        systemImage: isRunning ? "stop.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Text("Questa build non usa ancora il microfono: serve solo a verificare ActivityKit, Widget Extension e sideload.")
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
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities disabilitate nelle impostazioni di iOS."
            return
        }

        if !Activity<MicActivityAttributes>.activities.isEmpty {
            status = "Una Live Activity MisMeeter è già attiva."
            isRunning = true
            return
        }

        let attributes = MicActivityAttributes(sessionName: "PC Microphone")
        let state = MicActivityAttributes.ContentState(
            isMuted: false,
            connectionLabel: "Prototype"
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            status = "Live Activity avviata. Controlla Lock Screen e Dynamic Island."
            isRunning = true
        } catch {
            status = "Errore ActivityKit: \(error.localizedDescription)"
            isRunning = false
        }
    }

    private func stopActivities() async {
        let finalState = MicActivityAttributes.ContentState(
            isMuted: true,
            connectionLabel: "Stopped"
        )

        for activity in Activity<MicActivityAttributes>.activities {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }

        status = "Live Activity terminata."
        isRunning = false
    }

    private func refreshStatus() {
        isRunning = !Activity<MicActivityAttributes>.activities.isEmpty
        if isRunning {
            status = "Live Activity già attiva."
        }
    }
}

#Preview {
    ContentView()
}
