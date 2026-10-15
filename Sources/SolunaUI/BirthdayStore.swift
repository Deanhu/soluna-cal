import Foundation
import LunarCore

/// 农历生日/纪念日存储：UserDefaults 本地 + iCloud Drive 可见文件夹同步（零 entitlement）
/// 同步文件: ~/Library/Mobile Documents/com~apple~CloudDocs/SolunaCal/birthdays.json
/// 冲突策略: 后写覆盖（生日数据量小，可接受；上架迁 KVS 时只换存储后端）
public final class BirthdayStore: ObservableObject {
    public struct Entry: Codable, Identifiable, Equatable {
        public enum CalendarKind: String, Codable { case lunar, solar }
        public enum Cycle: String, Codable { case yearly, monthly }
        public var id = UUID()
        public var name: String
        /// 月/日：lunar 时是农历月日，solar 时是公历月日
        public var lunarMonth: Int
        public var lunarDay: Int
        public var isLeapMonth: Bool = false
        public var calendar: CalendarKind = .lunar
        public var cycle: Cycle = .yearly

        public init(name: String, lunarMonth: Int, lunarDay: Int,
                    isLeapMonth: Bool = false,
                    calendar: CalendarKind = .lunar, cycle: Cycle = .yearly) {
            self.name = name; self.lunarMonth = lunarMonth; self.lunarDay = lunarDay
            self.isLeapMonth = isLeapMonth; self.calendar = calendar; self.cycle = cycle
        }

        // 旧数据（v1 无 calendar/cycle 字段）兼容解码
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decode(String.self, forKey: .name)
            lunarMonth = try c.decode(Int.self, forKey: .lunarMonth)
            lunarDay = try c.decode(Int.self, forKey: .lunarDay)
            isLeapMonth = try c.decodeIfPresent(Bool.self, forKey: .isLeapMonth) ?? false
            calendar = try c.decodeIfPresent(CalendarKind.self, forKey: .calendar) ?? .lunar
            cycle = try c.decodeIfPresent(Cycle.self, forKey: .cycle) ?? .yearly
        }
    }

    @Published public private(set) var entries: [Entry] = []
    private let key = "birthdays.v1"
    private let mtimeKey = "birthdays.v1.mtime"   // 本地最后修改时间（冲突判定用）
    /// false 时纯内存（测试用，不污染 UserDefaults / iCloud）
    private let persists: Bool

    /// 冲突裁决（PRD：同步冲突以最新修改为准）。
    /// 本地无时间戳 = 旧版本数据，保持云优先的旧行为；云文件时间读不到 = 信本地。
    static func preferCloud(cloudMTime: TimeInterval?, localMTime: TimeInterval?) -> Bool {
        guard let l = localMTime else { return true }
        guard let c = cloudMTime else { return false }
        return c >= l
    }

    /// iCloud Drive 同步文件路径（不可用 = nil，静默降级为纯本地）
    private var cloudFile: URL? {
        guard persists else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let drive = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("SolunaCal/birthdays.json")
    }

    public init(persists: Bool = true) {
        self.persists = persists
        if persists { load() }
    }

    public func add(_ e: Entry) { entries.append(e); save() }
    public func remove(_ e: Entry) { entries.removeAll { $0.id == e.id }; save() }

    /// 某条目下次出现的公历日期与距今天数（0 = 今天）。
    /// 非闰月条目：农历年周期最长约 384 天（闰月年），扫 400 天必命中。
    /// 闰月条目：同一闰月间隔 2~19 年不等（如 2025 闰六月→2036 闰六月），扫描必漏，
    /// 改为按年直查 `leapMonth(of:)` 再正算公历日。
    public func nextOccurrence(of entry: Entry,
                               from: Date = Date()) -> (date: Date, days: Int)? {
        let gcal = Calendar(identifier: .gregorian)
        let start = gcal.startOfDay(for: from)
        if entry.calendar == .lunar, entry.cycle == .yearly, entry.isLeapMonth {
            let fromYear = gcal.component(.year, from: start)
            for y in fromYear...LunarCalendar.supportedRange.upperBound {
                guard LunarCalendar.leapMonth(of: y) == entry.lunarMonth,
                      entry.lunarDay <= LunarCalendar.monthDays(year: y, month: entry.lunarMonth, leap: true)
                else { continue }
                let d = LunarCalendar.solarDate(from: LunarDate(
                    year: y, month: entry.lunarMonth, day: entry.lunarDay, isLeapMonth: true))
                if d >= start {
                    return (d, gcal.dateComponents([.day], from: start, to: d).day ?? 0)
                }
            }
            return nil
        }
        for offset in 0..<400 {
            guard let d = gcal.date(byAdding: .day, value: offset, to: start),
                  let lunar = LunarCalendar.lunarDateOrNil(from: d) else { continue }
            if matchEntry(entry, date: d, lunar: lunar) { return (d, offset) }
        }
        return nil
    }

    /// 单条目命中判定（match 的逐条目版，供 nextOccurrence 复用同一规则）
    private func matchEntry(_ e: Entry, date: Date, lunar: LunarDate) -> Bool {
        let gcal = Calendar(identifier: .gregorian)
        let sm = gcal.component(.month, from: date)
        let sd = gcal.component(.day, from: date)
        switch (e.calendar, e.cycle) {
        case (.lunar, .yearly):
            return e.lunarMonth == lunar.month && e.lunarDay == lunar.day &&
                   (e.isLeapMonth == lunar.isLeapMonth || !e.isLeapMonth)
        case (.lunar, .monthly):
            return e.lunarDay == lunar.day
        case (.solar, .yearly):
            return e.lunarMonth == sm && e.lunarDay == sd
        case (.solar, .monthly):
            return e.lunarDay == sd
        }
    }

    /// 命中检查：该公历日是否命中某条目（按条目自身的历法与周期）
    public func match(date: Date, lunar: LunarDate) -> Entry? {
        entries.first { matchEntry($0, date: date, lunar: lunar) }
    }

    /// 单条目公开版（通知计划器等外部调用；超出历法数据范围返回 false）
    public func matches(_ entry: Entry, date: Date) -> Bool {
        guard let lunar = LunarCalendar.lunarDateOrNil(from: date) else { return false }
        return matchEntry(entry, date: date, lunar: lunar)
    }

    private func load() {
        // 双源取「最新修改」：本地时间戳 vs 云文件修改时间（PRD：冲突以最新修改为准）
        let localTS = UserDefaults.standard.object(forKey: mtimeKey) as? Double
        if let cf = cloudFile,
           let d = try? Data(contentsOf: cf),
           let cloud = try? JSONDecoder().decode([Entry].self, from: d), !cloud.isEmpty {
            let cloudTS = (try? FileManager.default.attributesOfItem(
                atPath: cf.path))?[.modificationDate] as? Date
            if Self.preferCloud(cloudMTime: cloudTS?.timeIntervalSince1970, localMTime: localTS) {
                entries = cloud
                UserDefaults.standard.set(d, forKey: key)   // 回写本地缓存
                return
            }
        }
        if let d = UserDefaults.standard.data(forKey: key) {
            entries = (try? JSONDecoder().decode([Entry].self, from: d)) ?? []
        }
    }

    private func save() {
        guard persists, let d = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(d, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: mtimeKey)
        if let cf = cloudFile {
            try? FileManager.default.createDirectory(
                at: cf.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: cf, options: .atomic)
        }
    }
}
