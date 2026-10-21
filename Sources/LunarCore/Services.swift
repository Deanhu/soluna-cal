import Foundation
import EventKit
import ServiceManagement
import Combine
import AppKit

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
///
/// 可观察：弹窗与「新建日程」窗口是两棵独立的视图树，保存后弹窗不会自动
/// 重绘——sheet 时代共处一棵树所以看不出来，窗口化之后这是必修的。
public final class EventProvider: ObservableObject {
    public static let shared = EventProvider()
    private let store = EKEventStore()
    /// 当日事件缓存。标记 @Published：刷新时驱动所有观察它的界面重绘
    @Published public private(set) var cached: [String: [EventItem]] = [:]   // "yyyy-M-d" -> 当日事件

    /// 一条日程：标题之外还留时间与日历名。
    /// 光有标题时，「同名事件出现在两个日历」会被显示成完全一样的两行，无处分辨。
    public struct EventItem: Identifiable, Equatable {
        public let id: String
        public let title: String
        public let start: Date
        public let calendarTitle: String
        public let isAllDay: Bool
        /// 只存在本机（没授权系统日历时写的那条）。列表里要标出来，
        /// 而且只有这种能删——系统日历的条目归「日历」App 管。
        public let localID: UUID?

        public init(id: String, title: String, start: Date, calendarTitle: String,
                    isAllDay: Bool, localID: UUID? = nil) {
            self.id = id
            self.title = title
            self.start = start
            self.calendarTitle = calendarTitle
            self.isAllDay = isAllDay
            self.localID = localID
        }
    }

    private init() {
        // 启动就同步读一次授权状态：等 requestFullAccessToEvents 的回调太晚，
        // 用户一开 App 就双击建日程时，编辑器会先按「未授权」显示错误文案。
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        if let data = UserDefaults.standard.data(forKey: Self.localKey),
           let list = try? JSONDecoder().decode([LocalEvent].self, from: data) {
            localEvents = list
        }
    }

    // MARK: 本机日程（未授权系统日历时的落地存储）

    /// 本机日程。写系统日历要授权，但「不授权」不等于「不能用」——
    /// 用户在这里记下的东西必须有地方去，否则整个新建日程功能等于废掉
    /// （0.4.8 之前就是这样：点保存只弹「写入失败：未授权系统日历」）。
    public struct LocalEvent: Codable, Identifiable, Equatable {
        public var id: UUID
        public var title: String
        /// 与事件缓存同格式 "yyyy-M-d"，跨时区不跑偏
        public var dayKey: String
        public var start: Date

        public init(id: UUID = UUID(), title: String, dayKey: String, start: Date) {
            self.id = id
            self.title = title
            self.dayKey = dayKey
            self.start = start
        }
    }

    private static let localKey = "localEvents.v1"
    /// 标记 @Published：保存/删除后月历圆点与详情卡立刻跟着变
    @Published public private(set) var localEvents: [LocalEvent] = []

    /// 能否写进系统日历：既要有权限，也要有可写的默认日历。
    /// 两者缺一都只能存本机，界面按这个值决定提示文案。
    public var canWriteToSystem: Bool {
        authorized && store.defaultCalendarForNewEvents != nil
    }

    /// 保存一条本机日程（9:00 开始，与系统日历那条的时间口径一致）
    @discardableResult
    public func addLocalEvent(title: String, on date: Date) -> LocalEvent {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        let ev = LocalEvent(title: title, dayKey: Self.key(of: date), start: start)
        localEvents.append(ev)
        persistLocal()
        return ev
    }

    public func removeLocalEvent(id: UUID) {
        localEvents.removeAll { $0.id == id }
        persistLocal()
    }

    private func persistLocal() {
        if let data = try? JSONEncoder().encode(localEvents) {
            UserDefaults.standard.set(data, forKey: Self.localKey)
        }
    }

    /// 系统事件 + 本机事件合成一条时间轴。纯函数，方便钉测试。
    static func merge(_ system: [EventItem], _ local: [EventItem]) -> [EventItem] {
        (system + local).sorted { $0.start < $1.start }
    }

    /// 是否已获系统日历授权（驱动「授权后显示」提示文案）；也标记 @Published
    @Published public private(set) var authorized = false

    /// 请求授权；授权通过后立即执行 completion（用于首刷当月事件点）
    ///
    /// `onDenied` 只在**用户主动点「授权」**时传：系统没弹框（状态仍是
    /// notDetermined）或用户以前拒过时，光把 `authorized` 置 false，界面上
    /// 什么都不会变 —— 用户看到的就是「点了没反应」。所以这里必须给一个
    /// 看得见的落点（打开系统设置面板 + 卡片里出提示）。
    /// 不要放进 popover 自动刷新里，否则每次开弹窗都会弹设置面板。
    public func requestAccessIfNeeded(then completion: (() -> Void)? = nil,
                                      onDenied: (() -> Void)? = nil) {
        // macOS 14+ 新 API（我们的部署目标即 14，无需回退分支）
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                if granted {
                    completion?()
                } else {
                    onDenied?()
                }
            }
        }
    }

    /// 打开「系统设置 › 隐私与安全性 › 日历」。
    /// 系统一旦记成「已拒绝」就再也不会弹框，只能由用户去这里打开；
    /// 这是我们唯一能替他缩短的一步。
    public func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(url)
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
        let k = Self.key(of: date)
        if authorized, cached[k] != nil { return true }
        return localEvents.contains { $0.dayKey == k }
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

    /// 当日事件：系统日历（已授权时）+ 本机日程，按时间排一条轴。
    /// 本机的条目 calendarTitle 写「本机」，用户在列表里能一眼看出它没进系统日历。
    public func events(on date: Date) -> [EventItem] {
        let k = Self.key(of: date)
        let system = authorized ? (cached[k] ?? []) : []
        let local = localEvents
            .filter { $0.dayKey == k }
            .map { EventItem(id: $0.id.uuidString, title: $0.title, start: $0.start,
                             calendarTitle: "本机", isAllDay: false, localID: $0.id) }
        return Self.merge(system, local)
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

    /// 保存结果：进了系统日历，还是只落在本机
    public enum SaveTarget { case system, local }

    /// 写入：优先系统日历；没权限 / 没有可写的默认日历 → 存本机。
    ///
    /// 以前这里 `guard authorized else { throw }`，未授权时点保存只弹
    /// 「写入失败：未授权系统日历」，用户输入直接丢弃。拒绝授权是很常见的
    /// 选择（系统问的是「完全访问日历」这种强权限），不该让功能整个不可用。
    /// 系统日历本身写入失败（磁盘/账户异常）仍然抛出，那种错误要让人看见。
    @discardableResult
    public func addEvent(title: String, on date: Date) throws -> SaveTarget {
        guard canWriteToSystem, let target = store.defaultCalendarForNewEvents else {
            addLocalEvent(title: title, on: date)
            return .local
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
        return .system
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
