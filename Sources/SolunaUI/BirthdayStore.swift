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
    /// false 时纯内存（测试用，不污染 UserDefaults / iCloud）
    private let persists: Bool

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

    /// 命中检查：该公历日是否命中某条目（按条目自身的历法与周期）
    public func match(date: Date, lunar: LunarDate) -> Entry? {
        let gcal = Calendar(identifier: .gregorian)
        let sm = gcal.component(.month, from: date)
        let sd = gcal.component(.day, from: date)
        return entries.first { e in
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
    }

    private func load() {
        // 云端优先（云端存在且能解码则以云端为准）
        if let cf = cloudFile,
           let d = try? Data(contentsOf: cf),
           let cloud = try? JSONDecoder().decode([Entry].self, from: d), !cloud.isEmpty {
            entries = cloud
            UserDefaults.standard.set(d, forKey: key)   // 回写本地缓存
            return
        }
        if let d = UserDefaults.standard.data(forKey: key) {
            entries = (try? JSONDecoder().decode([Entry].self, from: d)) ?? []
        }
    }

    private func save() {
        guard persists, let d = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(d, forKey: key)
        if let cf = cloudFile {
            try? FileManager.default.createDirectory(
                at: cf.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: cf, options: .atomic)
        }
    }
}
