import SwiftUI

struct NetworkStatusView: View {
    @EnvironmentObject var meshManager: MeshManager
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        NavigationStack {
            List {
                // Mesh Status
                Section {
                    HStack {
                        Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(meshManager.isRunning ? .green : .red)
                                .frame(width: 10, height: 10)
                            Text(meshManager.isRunning ? "Active" : "Inactive")
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Label("Your Device", systemImage: "iphone")
                        Spacer()
                        Text(meshManager.deviceName)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Mesh Network")
                }

                // Statistics
                Section {
                    StatRow(icon: "person.2.fill", label: "Connected Peers", value: "\(meshManager.connectedPeers.count)")
                    StatRow(icon: "message.fill", label: "Messages", value: "\(meshManager.messages.count)")
                    StatRow(icon: "arrow.triangle.branch", label: "Relayed", value: "\(meshManager.relayedCount)")
                    StatRow(icon: "sos", label: "SOS Alerts", value: "\(meshManager.sosAlerts.count)")
                } header: {
                    Text("Statistics")
                }

                // Connected Peers
                Section {
                    if meshManager.connectedPeers.isEmpty {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Searching for nearby devices...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(meshManager.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundStyle(.green)
                                Text(peer.displayName)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                } header: {
                    Text("Connected Devices")
                } footer: {
                    Text("Devices automatically connect via Bluetooth. Keep devices within ~100 feet of each other.")
                }

                // Location Status
                Section {
                    HStack {
                        Label("GPS", systemImage: "location.fill")
                        Spacer()
                        if let location = locationManager.currentLocation {
                            Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Acquiring...")
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack {
                        Label("Permission", systemImage: "lock.shield")
                        Spacer()
                        Text(permissionText)
                            .foregroundStyle(permissionColor)
                    }
                } header: {
                    Text("Location")
                }

                // How it works
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(icon: "1.circle.fill", text: "Devices discover each other via Bluetooth")
                        InfoRow(icon: "2.circle.fill", text: "Messages hop from phone to phone")
                        InfoRow(icon: "3.circle.fill", text: "Each phone relays to extend range")
                        InfoRow(icon: "4.circle.fill", text: "No internet or cell towers needed")
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("How SafeMesh Works")
                }

                // Controls
                Section {
                    Button(action: toggleMesh) {
                        HStack {
                            Image(systemName: meshManager.isRunning ? "stop.fill" : "play.fill")
                            Text(meshManager.isRunning ? "Stop Mesh" : "Start Mesh")
                        }
                        .foregroundStyle(meshManager.isRunning ? .red : .green)
                    }
                }
            }
            .navigationTitle("Network")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var permissionText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "When In Use"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Set"
        @unknown default: return "Unknown"
        }
    }

    private var permissionColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .green
        case .denied, .restricted: return .red
        default: return .orange
        }
    }

    private func toggleMesh() {
        if meshManager.isRunning {
            meshManager.stop()
        } else {
            meshManager.start()
        }
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
        }
    }
}

#Preview {
    NetworkStatusView()
        .environmentObject(MeshManager())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
}
