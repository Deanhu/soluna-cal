import Foundation
import EventKit
import ServiceManagement

/// 宜忌查询（数据见 Generated/YijiData.swift，2025–2027 内置）
public enum Yiji {
    public static func on(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> (yi: String, ji: String)? {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return YIJI_TABLE["\(y)-\(m)-\(d)"]
    }
}

/// 系统日历事件只读（EventKit；授权被拒时静默降级为无点）
public final class EventProvider {
    public static let shared = EventProvider()
    private let store = EKEventStore()
    private var cached: [String: [String]] = [:]   // "yyyy-M-d" -> 当日事件标题

    private init() {}

    /// 是否已获系统日历授权（驱动「授权后显示」提示文案）
    public private(set) var authorized = false

    /// 请求授权；授权通过后立即执行 completion（用于首刷当月事件点）
    public func requestAccessIfNeeded(then completion: (() -> Void)? = nil) {
        // macOS 14+ 新 API（我们的部署目标即 14，无需回退分支）
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                if granted { completion?() }
            }
        }
    }

    /// 拉取某月有事件的日期集合（只读）
    public func refresh(year: Int, month: Int) {
        guard authorized else { return }
        let cal = Calendar(identifier: .gregorian)
        let c0 = DateComponents(year: year, month: month)
        guard let start = cal.date(from: c0),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: pred)
        var map: [String: [String]] = [:]
        for e in events {
            let dc = cal.dateComponents([.year, .month, .day], from: e.startDate)
            if let y = dc.year, let m = dc.month, let d = dc.day {
                map["\(y)-\(m)-\(d)", default: []].append(e.title)
            }
        }
        cached = map
    }

    private static func key(of date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }

    public func hasEvent(on date: Date) -> Bool {
        guard authorized else { return false }
        return cached[Self.key(of: date)] != nil
    }

    /// 当日事件标题列表（只读；无授权/无事件 = 空）
    public func events(on date: Date) -> [String] {
        guard authorized else { return [] }
        return cached[Self.key(of: date)] ?? []
    }
}

/// 登录自启（SMAppService，macOS 13+）
/// 注意：仅在 .app bundle 内注册有效；SPM 直跑二进制下静默跳过。
/// 未签名/临时签名包注册失败时只记日志，不崩溃。
public enum LaunchAtLogin {
    /// 真实状态：.app 内以系统注册状态为准，调试二进制退回 UserDefaults
    public static var enabled: Bool {
        get {
            if Bundle.main.bundleURL.pathExtension == "app" {
                return SMAppService.mainApp.status == .enabled
            }
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            apply(newValue)
        }
    }

    public static func apply(_ target: Bool? = nil) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let enable = target ?? UserDefaults.standard.bool(forKey: "launchAtLogin")
        do {
            if enable {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("[SolunaCal] LaunchAtLogin 注册失败（可能未签名）: \(error.localizedDescription)")
        }
    }
}
