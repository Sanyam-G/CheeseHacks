import SwiftUI
import CoreLocation

/// Authorities or volunteers can broadcast shelter, water, evacuation info
/// This turns SafeMesh into an information lifeline not just a chat
struct ResourceView: View {
    @EnvironmentObject var meshManager: MeshManager
    @EnvironmentObject var locationManager: LocationManager

    @State private var showingBroadcastSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if meshManager.resourceBroadcasts.isEmpty {
                    emptyState
                } else {
                    resourceList
                }
            }
            .navigationTitle("Resources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showingBroadcastSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .sheet(isPresented: $showingBroadcastSheet) {
                BroadcastResourceSheet()
                    .environmentObject(meshManager)
                    .environmentObject(locationManager)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No resources broadcast yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Authorities and volunteers can broadcast shelter locations, water stations, and evacuation routes here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { showingBroadcastSheet = true }) {
                Label("Broadcast a Resource", systemImage: "plus")
                    .padding()
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .cornerRadius(12)
            }
        }
    }

    private var resourceList: some View {
        List {
            ForEach(ResourceType.allCases, id: \.self) { type in
                let items = meshManager.resourceBroadcasts.filter { $0.type == type }
                if !items.isEmpty {
                    Section(header: Label(type.rawValue, systemImage: type.icon)) {
                        ForEach(items) { resource in
                            ResourceRow(resource: resource)
                                .environmentObject(locationManager)
                        }
                    }
                }
            }
        }
    }
}

struct ResourceRow: View {
    let resource: ResourceBroadcast
    @EnvironmentObject var locationManager: LocationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(resource.title)
                    .font(.headline)
                Spacer()
                Text(locationManager.formattedDistance(to: resource.coordinate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(resource.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                Text("Via \(resource.hopPath.count) hops • \(resource.senderName)")
                    .font(.caption)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct BroadcastResourceSheet: View {
    @EnvironmentObject var meshManager: MeshManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedType: ResourceType = .shelter
    @State private var title = ""
    @State private var description = ""
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Resource Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(ResourceType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon).tag(type)
                        }
                    }
                    .pickerStyle(.wheel)
                }

                Section("Details") {
                    TextField("Title (e.g. 'Madison East High School')", text: $title)
                    TextField("Description (e.g. 'Open 24hrs, 200 capacity')", text: $description, axis: .vertical)
                        .lineLimit(3)
                }

                Section("Location") {
                    if let loc = locationManager.currentLocation {
                        HStack {
                            Image(systemName: "location.fill").foregroundStyle(.green)
                            Text(String(format: "%.5f, %.5f", loc.latitude, loc.longitude))
                                .font(.system(.caption, design: .monospaced))
                        }
                    } else {
                        Label("Acquiring GPS...", systemImage: "location.slash")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Broadcast Resource")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Broadcast") { broadcast() }
                        .disabled(title.isEmpty || locationManager.currentLocation == nil)
                        .fontWeight(.bold)
                }
            }
            .overlay {
                if sent {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)
                        Text("Broadcast Sent!")
                            .font(.title2.bold())
                        Text("Relaying across the mesh...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.8))
                }
            }
        }
    }

    private func broadcast() {
        guard let loc = locationManager.currentLocation else { return }
        let resource = ResourceBroadcast(
            senderID: meshManager.deviceID,
            senderName: meshManager.deviceName,
            type: selectedType,
            title: title,
            description: description.isEmpty ? selectedType.rawValue : description,
            coordinate: loc
        )
        meshManager.sendResourceBroadcast(resource)
        sent = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
    }
}

#Preview {
    ResourceView()
        .environmentObject(MeshManager())
        .environmentObject(LocationManager())
        .preferredColorScheme(.dark)
}
