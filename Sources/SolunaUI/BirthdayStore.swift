import Foundation
import LunarCore

/// 农历生日/纪念日存储：UserDefaults 本地 + iCloud Drive 可见文件夹同步（零 entitlement）
/// 同步文件: ~/Library/Mobile Documents/com~apple~CloudDocs/SolunaCal/birthdays.json
/// 冲突策略: 后写覆盖（生日数据量小，可接受；上架迁 KVS 时只换存储后端）
public final class BirthdayStore: ObservableObject {
    public struct Entry: Codable, Identifiable, Equatable {
        public var id = UUID()
        public var name: String
        public var lunarMonth: Int
        public var lunarDay: Int
        public var isLeapMonth: Bool = false
    }

    @Published public private(set) var entries: [Entry] = []
    private let key = "birthdays.v1"

    /// iCloud Drive 同步文件路径（不可用 = nil，静默降级为纯本地）
    private var cloudFile: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let drive = home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("SolunaCal/birthdays.json")
    }

    public init() { load() }

    public func add(_ e: Entry) { entries.append(e); save() }
    public func remove(_ e: Entry) { entries.removeAll { $0.id == e.id }; save() }

    /// 命中检查：该公历日是否是某条目的农历纪念日
    public func match(date: Date, lunar: LunarDate) -> Entry? {
        entries.first {
            $0.lunarMonth == lunar.month && $0.lunarDay == lunar.day &&
            ($0.isLeapMonth == lunar.isLeapMonth || !$0.isLeapMonth)
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
        guard let d = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(d, forKey: key)
        if let cf = cloudFile {
            try? FileManager.default.createDirectory(
                at: cf.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: cf, options: .atomic)
        }
    }
}
