import CoreLocation

/// When-in-use location only. Gets one fresh fix and PUTs it to
/// `/me/location`, which the backend rounds to ~1km before storing (the
/// "coarse" location the privacy copy promises). No background location.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var oneShotContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var isDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Get one fresh fix and submit it to the backend. Returns true on success
    /// (authorized, fix acquired, upload succeeded).
    @discardableResult
    func submitLocation() async -> Bool {
        guard isAuthorized else { return false }
        guard let coord = await requestOneShotLocation() else { return false }
        do {
            try await APIClient.shared.submitLocation(lat: coord.latitude, lng: coord.longitude)
            return true
        } catch {
            return false
        }
    }

    private func requestOneShotLocation() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { continuation in
            oneShotContinuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate
        Task { @MainActor in
            self.oneShotContinuation?.resume(returning: coord)
            self.oneShotContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.oneShotContinuation?.resume(returning: nil)
            self.oneShotContinuation = nil
        }
    }
}
