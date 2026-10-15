import Foundation
import EventKit

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
    private var authorized = false
    private var cachedDays: Set<String> = []   // "yyyy-M-d"

    private init() {}

    public func requestAccessIfNeeded() {
        store.requestAccess(to: .event) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    /// 拉取某月有事件的日期集合（只读）
    public func refresh(year: Int, month: Int) {
        guard authorized else { return }
        var cal = Calendar(identifier: .gregorian)
        var c = DateComponents(); c.year = year; c.month = month
        guard let start = cal.date(from: c),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return }
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: pred)
        var days = Set<String>()
        for e in events {
            let dc = cal.dateComponents([.year, .month, .day], from: e.startDate)
            if let y = dc.year, let m = dc.month, let d = dc.day {
                days.insert("\(y)-\(m)-\(d)")
            }
        }
        cachedDays = days
    }

    public func hasEvent(on date: Date) -> Bool {
        guard authorized else { return false }
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return cachedDays.contains("\(c.year!)-\(c.month!)-\(c.day!)")
    }
}

/// 登录自启（SMAppService，macOS 13+；SPM 直跑二进制下注册会失败，属预期——打包成 .app 后生效）
public enum LaunchAtLogin {
    public static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "launchAtLogin") }
        set {
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
            apply()
        }
    }

    public static func apply() {
        // SMAppService 需要 .app bundle；调试二进制下静默跳过
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        // 打包后启用：
        // try? SMAppService.mainApp.register() / .unregister()
    }
}
