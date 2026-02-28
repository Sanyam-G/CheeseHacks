import SwiftUI

struct ContentView: View {
    @EnvironmentObject var meshManager: MeshManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingSOSOverlay = false
    @State private var currentSOSAlert: SOSAlert?

    var body: some View {
        ZStack {
            TabView {
                ChatView()
                    .tabItem {
                        Label("Messages", systemImage: "message.fill")
                    }

                SOSView()
                    .tabItem {
                        Label("SOS", systemImage: "sos")
                    }

                MapView()
                    .tabItem {
                        Label("Map", systemImage: "map.fill")
                    }

                NetworkStatusView()
                    .tabItem {
                        Label("Network", systemImage: "antenna.radiowaves.left.and.right")
                    }
            }
            .tint(.red)

            // SOS Alert Overlay
            if showingSOSOverlay, let alert = currentSOSAlert {
                SOSAlertOverlay(alert: alert, isPresented: $showingSOSOverlay)
                    .transition(.opacity)
            }
        }
        .onChange(of: meshManager.sosAlerts) { oldAlerts, newAlerts in
            // Check for new SOS alerts that aren't from us
            if let newAlert = newAlerts.last,
               newAlert.senderID != meshManager.deviceID,
               !oldAlerts.contains(where: { $0.id == newAlert.id }) {
                currentSOSAlert = newAlert
                showingSOSOverlay = true
                triggerSOSFeedback()
            }
        }
    }

    private func triggerSOSFeedback() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Play alert sound
        // AudioServicesPlayAlertSound(SystemSoundID(1005))
    }
}

#Preview {
    ContentView()
        .environmentObject(MeshManager())
        .environmentObject(LocationManager())
}
