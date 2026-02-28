import SwiftUI
import MapKit

struct MapView: View {
    @EnvironmentObject var meshManager: MeshManager
    @EnvironmentObject var locationManager: LocationManager

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedAlert: SOSAlert?

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    // User location
                    UserAnnotation()

                    // Connected peers
                    ForEach(Array(meshManager.peerLocations.values)) { peer in
                        if let coord = peer.coordinate {
                            Annotation(peer.displayName, coordinate: coord) {
                                PeerAnnotationView(name: peer.displayName)
                            }
                        }
                    }

                    // SOS Alerts
                    ForEach(meshManager.sosAlerts) { alert in
                        Annotation(alert.senderName, coordinate: alert.coordinate) {
                            SOSAnnotationView(alert: alert) {
                                selectedAlert = alert
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }

                // Legend
                VStack {
                    Spacer()
                    legendView
                }
            }
            .navigationTitle("Mesh Map")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedAlert) { alert in
                SOSDetailSheet(alert: alert)
                    .environmentObject(locationManager)
            }
        }
    }

    private var legendView: some View {
        HStack(spacing: 16) {
            LegendItem(color: .blue, label: "You")
            LegendItem(color: .green, label: "Peer")
            LegendItem(color: .red, label: "SOS")
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}

struct PeerAnnotationView: View {
    let name: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.green)
                    .frame(width: 32, height: 32)
                Image(systemName: "iphone")
                    .foregroundStyle(.white)
                    .font(.system(size: 16))
            }
            Text(name)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .cornerRadius(4)
        }
    }
}

struct SOSAnnotationView: View {
    let alert: SOSAlert
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Pulse effect
                Circle()
                    .fill(.red.opacity(0.3))
                    .frame(width: isPulsing ? 60 : 40, height: isPulsing ? 60 : 40)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isPulsing)

                Circle()
                    .fill(.red)
                    .frame(width: 36, height: 36)

                Image(systemName: alert.emergencyType.icon)
                    .foregroundStyle(.white)
                    .font(.system(size: 18))
            }
            .onAppear { isPulsing = true }
            .onTapGesture(perform: onTap)

            Text(alert.senderName)
                .font(.caption2.bold())
                .foregroundStyle(.red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.white)
                .cornerRadius(4)
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption)
        }
    }
}

struct SOSDetailSheet: View {
    let alert: SOSAlert
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Emergency type header
                HStack {
                    Image(systemName: alert.emergencyType.icon)
                        .font(.title)
                    Text(alert.emergencyType.rawValue)
                        .font(.title.bold())
                }
                .foregroundStyle(.red)

                Divider()

                // Details
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "From", value: alert.senderName)
                    DetailRow(label: "Time", value: alert.timestamp.formatted())
                    DetailRow(label: "Distance", value: locationManager.formattedDistance(to: alert.coordinate))
                    DetailRow(label: "Coordinates", value: String(format: "%.6f, %.6f", alert.latitude, alert.longitude))

                    if let medical = alert.medicalInfo {
                        DetailRow(label: "Medical Info", value: medical)
                    }

                    if alert.hopPath.count > 1 {
                        DetailRow(label: "Relay Path", value: alert.hopPath.joined(separator: " → "))
                    }
                }
                .padding()

                Spacer()

                // Open in Maps button
                Button(action: openInMaps) {
                    Label("Open in Maps", systemImage: "map.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding(.top)
            .navigationTitle("SOS Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: alert.coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = "\(alert.senderName) - SOS"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking
        ])
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }
}

#Preview {
    MapView()
        .environmentObject(MeshManager())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
}
