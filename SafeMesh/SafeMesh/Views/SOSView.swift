import SwiftUI

struct SOSView: View {
    @EnvironmentObject var meshManager: MeshManager
    @EnvironmentObject var locationManager: LocationManager

    @State private var selectedEmergencyType: EmergencyType = .medical
    @State private var medicalInfo = ""
    @State private var showingConfirmation = false
    @State private var isPressed = false
    @State private var sosActive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()

                // Status
                if sosActive {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        Text("SOS SENT")
                            .font(.title.bold())
                        Text("Help is being notified")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Emergency type selector
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Emergency Type")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(EmergencyType.allCases, id: \.self) { type in
                                EmergencyTypeButton(
                                    type: type,
                                    isSelected: selectedEmergencyType == type
                                ) {
                                    selectedEmergencyType = type
                                }
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Medical info (optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Medical Info (Optional)")
                            .font(.headline)
                        TextField("Blood type, allergies, conditions...", text: $medicalInfo)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Giant SOS Button
                Button(action: {
                    showingConfirmation = true
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.red, .red.opacity(0.7)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .shadow(color: .red.opacity(0.5), radius: isPressed ? 30 : 20)
                            .scaleEffect(isPressed ? 0.95 : 1.0)

                        VStack(spacing: 8) {
                            Image(systemName: "sos")
                                .font(.system(size: 50, weight: .bold))
                            Text("EMERGENCY")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(sosActive)
                .opacity(sosActive ? 0.5 : 1.0)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressed = true }
                        .onEnded { _ in isPressed = false }
                )

                // Location status
                HStack {
                    Image(systemName: locationManager.currentLocation != nil ? "location.fill" : "location.slash")
                    Text(locationManager.currentLocation != nil ? "GPS Ready" : "Acquiring GPS...")
                }
                .font(.caption)
                .foregroundStyle(locationManager.currentLocation != nil ? .green : .orange)

                Spacer()
            }
            .navigationTitle("Emergency SOS")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Send Emergency SOS?",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Send SOS", role: .destructive) {
                    sendSOS()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will broadcast your location and emergency to all nearby devices.")
            }
        }
    }

    private func sendSOS() {
        guard let location = locationManager.currentLocation else {
            // Use a default/last known location or show error
            return
        }

        meshManager.sendSOS(
            coordinate: location,
            type: selectedEmergencyType,
            medicalInfo: medicalInfo.isEmpty ? nil : medicalInfo
        )

        sosActive = true

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

struct EmergencyTypeButton: View {
    let type: EmergencyType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.title2)
                Text(type.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.red.opacity(0.3) : Color(.systemGray5))
            .foregroundStyle(isSelected ? .red : .primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SOSView()
        .environmentObject(MeshManager())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
}
