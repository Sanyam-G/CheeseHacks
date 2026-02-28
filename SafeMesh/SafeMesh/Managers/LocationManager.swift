import Foundation
import CoreLocation
import Combine

/// Manages device location - GPS works offline
class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastError: String?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
    }

    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        locationManager.startUpdatingLocation()
    }

    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    /// Calculate distance from current location to a coordinate
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }

        let from = CLLocation(latitude: current.latitude, longitude: current.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return from.distance(from: to)
    }

    /// Format distance for display
    func formattedDistance(to coordinate: CLLocationCoordinate2D) -> String {
        guard let meters = distance(to: coordinate) else { return "Unknown" }

        if meters < 1000 {
            return String(format: "%.0f m", meters)
        } else {
            let km = meters / 1000
            return String(format: "%.1f km", km)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        DispatchQueue.main.async {
            self.currentLocation = location.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.lastError = error.localizedDescription
        }
        print("❌ Location error: \(error)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdating()
        case .denied, .restricted:
            lastError = "Location access denied"
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
