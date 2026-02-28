import SwiftUI
import AudioToolbox

struct SOSAlertOverlay: View {
    let alert: SOSAlert
    @Binding var isPresented: Bool
    @EnvironmentObject var locationManager: LocationManager

    @State private var isPulsing = false
    @State private var hasPlayedSound = false

    var body: some View {
        ZStack {
            // Pulsing red background
            Color.red
                .opacity(isPulsing ? 0.9 : 0.7)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)

            VStack(spacing: 24) {
                Spacer()

                // Emergency icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.yellow)
                    .shadow(radius: 10)

                // Title
                Text("EMERGENCY ALERT")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.white)

                // Sender info
                VStack(spacing: 8) {
                    Text(alert.senderName)
                        .font(.title.bold())
                    Text("needs help")
                        .font(.title3)
                }
                .foregroundStyle(.white)

                // Emergency type
                HStack {
                    Image(systemName: alert.emergencyType.icon)
                        .font(.title)
                    Text(alert.emergencyType.rawValue.uppercased())
                        .font(.title2.bold())
                }
                .foregroundStyle(.yellow)
                .padding()
                .background(.white.opacity(0.2))
                .cornerRadius(12)

                // Distance
                VStack(spacing: 4) {
                    Text("DISTANCE")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(locationManager.formattedDistance(to: alert.coordinate))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                // Coordinates
                VStack(spacing: 4) {
                    Text("LOCATION")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(String(format: "%.6f, %.6f", alert.latitude, alert.longitude))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }

                // Medical info if available
                if let medicalInfo = alert.medicalInfo, !medicalInfo.isEmpty {
                    VStack(spacing: 4) {
                        Text("MEDICAL INFO")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                        Text(medicalInfo)
                            .font(.body)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(.white.opacity(0.2))
                    .cornerRadius(12)
                }

                // Relay path
                if alert.hopPath.count > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                        Text("Via: \(alert.hopPath.joined(separator: " → "))")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                }

                Spacer()

                // Dismiss button
                Button(action: { isPresented = false }) {
                    Text("ACKNOWLEDGE")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            isPulsing = true
            playAlertSound()
            triggerHaptics()
        }
    }

    private func playAlertSound() {
        guard !hasPlayedSound else { return }
        hasPlayedSound = true
        AudioServicesPlayAlertSound(SystemSoundID(1005)) // System alert sound
    }

    private func triggerHaptics() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Continuous haptics
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            generator.notificationOccurred(.error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            generator.notificationOccurred(.error)
        }
    }
}

#Preview {
    SOSAlertOverlay(
        alert: SOSAlert(
            senderID: "test",
            senderName: "John's iPhone",
            coordinate: .init(latitude: 43.0731, longitude: -89.4012),
            emergencyType: .medical,
            medicalInfo: "Type O+, Allergic to penicillin"
        ),
        isPresented: .constant(true)
    )
    .environmentObject(LocationManager())
}
