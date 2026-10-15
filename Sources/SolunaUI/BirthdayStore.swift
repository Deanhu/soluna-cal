import Foundation
import LunarCore

/// 农历生日/纪念日存储：UserDefaults 持久化（iCloud KVS 同步留待二期开 entitlement）
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
        guard let d = UserDefaults.standard.data(forKey: key) else { return }
        entries = (try? JSONDecoder().decode([Entry].self, from: d)) ?? []
    }
    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
