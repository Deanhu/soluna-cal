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
    private var cached: [String: [EventItem]] = [:]   // "yyyy-M-d" -> 当日事件

    /// 一条日程：标题之外还留时间与日历名。
    /// 光有标题时，「同名事件出现在两个日历」会被显示成完全一样的两行，无处分辨。
    public struct EventItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let start: Date
        public let calendarTitle: String
        public let isAllDay: Bool
    }

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
        var map: [String: [EventItem]] = [:]
        for e in events {
            let dc = cal.dateComponents([.year, .month, .day], from: e.startDate)
            guard let y = dc.year, let m = dc.month, let d = dc.day else { continue }
            let item = EventItem(id: e.eventIdentifier ?? UUID().uuidString,
                                 title: e.title ?? "(无标题)",
                                 start: e.startDate,
                                 calendarTitle: e.calendar?.title ?? "?",
                                 isAllDay: e.isAllDay)
            map["\(y)-\(m)-\(d)", default: []].append(item)
        }
        for key in map.keys {
            map[key] = Self.collapseDuplicates(map[key] ?? [])
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

    /// 去掉完全相同的条目（同标题 + 同开始时间 + 同日历）。
    /// 分属不同日历的同名事件**保留**——那正是用户需要看见的区别。
    static func collapseDuplicates(_ items: [EventItem]) -> [EventItem] {
        var out: [EventItem] = []
        var seen: Set<String> = []
        for item in items {
            let fp = "\(item.calendarTitle)|\(item.title)|\(item.start.timeIntervalSince1970)"
            if seen.contains(fp) { continue }
            seen.insert(fp)
            out.append(item)
        }
        return out
    }

    /// 当日事件（只读；无授权/无事件 = 空）
    public func events(on date: Date) -> [EventItem] {
        guard authorized else { return [] }
        return (cached[Self.key(of: date)] ?? []).sorted { $0.start < $1.start }
    }

    /// 诊断：某天系统日历里到底有几条事件，各自属于哪个日历。
    /// 用户报「同一条出现两次」时，先跑这个再判断是数据重复还是显示问题。
    public func dump(date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        guard authorized else { return "未授权系统日历，无法读取" }
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return "日期无效" }
        let pred = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        let list = store.events(matching: pred)
        var out = "\(date) 共 \(list.count) 条事件\n"
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm"
        for (i, e) in list.enumerated() {
            out += "  \(i + 1). 「\(e.title ?? "(无标题)")」 \(df.string(from: e.startDate))–\(df.string(from: e.endDate))"
            out += " 日历=\(e.calendar?.title ?? "?")"
            out += " 全天=\(e.isAllDay ? "是" : "否")"
            out += " id=\(e.eventIdentifier ?? "-")\n"
        }
        return out
    }

    /// 写入：在指定日创建 1 小时事件（二期双击创建；macOS 14 fullAccess 含写权限）
    /// 失败抛出具体错误（无权限 / 无默认日历 / 系统拒绝），调用方负责提示
    public func addEvent(title: String, on date: Date) throws {
        guard authorized else { throw NSError(domain: "SolunaCal", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "未授权系统日历"]) }
        guard let target = store.defaultCalendarForNewEvents else {
            throw NSError(domain: "SolunaCal", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "系统日历没有可写入的日历"])
        }
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        let ev = EKEvent(eventStore: store)
        ev.title = title
        ev.startDate = start
        ev.endDate = start.addingTimeInterval(3600)
        ev.calendar = target
        // 不带闹钟的事件写进系统日历后【不会提醒】——EventKit 不会套用日历的默认提醒。
        // 用户在这里建日程就是想让 App 提醒他，所以固定加一条「开始前 10 分钟」。
        ev.addAlarm(EKAlarm(relativeOffset: -10 * 60))
        try store.save(ev, span: .thisEvent)
        refresh(year: cal.component(.year, from: date), month: cal.component(.month, from: date))
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
