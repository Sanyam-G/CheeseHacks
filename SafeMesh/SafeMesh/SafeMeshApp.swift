import SwiftUI

@main
struct SafeMeshApp: App {
    @StateObject private var meshManager = MeshManager()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(meshManager)
                .environmentObject(locationManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    locationManager.requestPermission()
                    meshManager.start()
                }
        }
    }
}
