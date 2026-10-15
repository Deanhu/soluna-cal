import Foundation
import CoreLocation

/// 定位（仅用于真太阳时经度校正）：一次定位 + UserDefaults 缓存；
/// 拒绝授权/失败 → 回退东经 120°（东八区中央经线），UI 明示「未定位」
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    public static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private override init() { super.init(); manager.delegate = self }

    /// 当前经度 + 是否真实定位
    public var longitude: Double {
        let ud = UserDefaults.standard
        return ud.object(forKey: "location.longitude") != nil
            ? ud.double(forKey: "location.longitude") : 120.0
    }
    public var isLocated: Bool {
        UserDefaults.standard.object(forKey: "location.longitude") != nil
    }

    /// 请求一次定位（开关打开时调用；多次调用幂等）
    public func locate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorized: manager.requestLocation()
        default: break
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let lon = locations.last?.coordinate.longitude else { return }
        UserDefaults.standard.set(lon, forKey: "location.longitude")
        NotificationCenter.default.post(name: .locationDidUpdate, object: nil)
    }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[SolunaCal] 定位失败（真太阳时按东经 120°）: \(error.localizedDescription)")
    }
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized { manager.requestLocation() }
    }
}

public extension Notification.Name {
    static let locationDidUpdate = Notification.Name("locationDidUpdate")
}
