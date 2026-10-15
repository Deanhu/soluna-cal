import Foundation

/// 节日（公历固定日 + 农历固定日）
public enum Festival {
    /// 公历节日：月/日 -> 名称
    public static let solar: [String: String] = [
        "1-1": "元旦", "2-14": "情人节", "3-8": "妇女节", "3-12": "植树节",
        "4-1": "愚人节", "5-1": "劳动节", "5-4": "青年节", "6-1": "儿童节",
        "7-1": "建党节", "8-1": "建军节", "9-10": "教师节", "10-1": "国庆",
        "12-24": "平安夜", "12-25": "圣诞节",
    ]
    /// 农历节日：月/日 -> 名称
    public static let lunar: [String: String] = [
        "1-1": "春节", "1-15": "元宵", "2-2": "龙抬头", "5-5": "端午",
        "7-7": "七夕", "8-15": "中秋", "9-9": "重阳", "12-8": "腊八",
    ]
    /// 农历腊月廿九/三十 -> 除夕（看腊月大小）
    public static func lunarFestival(of d: LunarDate) -> String? {
        if d.month == 12 {
            let last = LunarCalendar.monthDays(year: d.year, month: 12)
            if d.day == last { return "除夕" }
        }
        return lunar["\(d.month)-\(d.day)"]
    }
    public static func solarFestival(month: Int, day: Int) -> String? {
        solar["\(month)-\(day)"]
    }
}

/// 某天的休/班状态
public enum DayStatus: Equatable {
    case normal          // 普通日
    case weekend         // 普通周末
    case off(String)     // 节假日休息（携带假期名）
    case work(String)    // 调休补班（携带假期名）
}

/// 调休数据层：内置 JSON 兜底 + Application Support 缓存的在线版本
/// JSON 格式：{"year": 2026, "ranges": [{"name":"国庆中秋","off":["10-01",...],"work":["09-28","10-11",...]}]}
public struct HolidayData: Codable {
    public struct Range: Codable {
        public var name: String
        public var off: [String]    // "MM-dd"
        public var work: [String]   // "MM-dd"
    }
    public var year: Int
    public var ranges: [Range]
}

public enum HolidayStore {
    public static var calendar = Calendar(identifier: .gregorian)

    /// 内置兜底数据（2026 年，国务院通知为准；发版时更新）
    static let bundled: [HolidayData] = [
        HolidayData(year: 2026, ranges: [
            .init(name: "元旦",   off: ["01-01","01-02","01-03"], work: []),
            .init(name: "春节",   off: ["02-16","02-17","02-18","02-19","02-20","02-21","02-22"], work: ["02-14","02-28"]),
            .init(name: "清明",   off: ["04-04","04-05","04-06"], work: []),
            .init(name: "劳动节", off: ["05-01","05-02","05-03","05-04","05-05"], work: ["05-09"]),
            .init(name: "端午",   off: ["06-19","06-20","06-21"], work: []),
            .init(name: "国庆中秋", off: ["10-01","10-02","10-03","10-04","10-05","10-06","10-07"], work: ["10-10"]),
        ]),
        // 跨年倒计时需要次年元旦兜底；次年完整安排在国务院通知发布后更新
        HolidayData(year: 2027, ranges: [
            .init(name: "元旦",   off: ["01-01","01-02","01-03"], work: []),
        ]),
    ]

    /// 在线数据 URL（待 Dean 拍板数据源后启用；nil = 只用内置）
    public static var remoteURL: URL? = nil

    static var cacheDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SolunaCal", isDirectory: true)
    }

    public static func status(on date: Date) -> DayStatus {
        let y = calendar.component(.year, from: date)
        let md = String(format: "%02d-%02d", calendar.component(.month, from: date),
                        calendar.component(.day, from: date))
        let data = load(year: y)
        for r in data.ranges {
            if r.off.contains(md) { return .off(r.name) }
            if r.work.contains(md) { return .work(r.name) }
        }
        let wd = calendar.component(.weekday, from: date)
        return (wd == 1 || wd == 7) ? .weekend : .normal
    }

    static func load(year: Int) -> HolidayData {
        if let cached = try? Data(contentsOf: cacheDir.appendingPathComponent("holidays-\(year).json")),
           let hd = try? JSONDecoder().decode(HolidayData.self, from: cached) {
            return hd
        }
        return bundled.first { $0.year == year } ?? HolidayData(year: year, ranges: [])
    }

    /// 启动后后台拉取在线数据（成功则覆盖缓存）
    public static func refreshInBackground() {
        guard let url = remoteURL else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let list = try? JSONDecoder().decode([HolidayData].self, from: data) else { return }
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            for hd in list {
                try? JSONEncoder().encode(hd)
                    .write(to: cacheDir.appendingPathComponent("holidays-\(hd.year).json"))
            }
        }.resume()
    }

    /// 距下一个法定假（名称, 日期, 天数）
    public static func nextHoliday(after date: Date) -> (name: String, date: Date, days: Int)? {
        let y = calendar.component(.year, from: date)
        for yy in [y, y + 1] {
            for r in load(year: yy).ranges {
                guard let first = r.off.map({ "\(yy)-\($0)" }).sorted().first,
                      let d = dateFromISO(first), d > date else { continue }
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                                   to: d).day!
                return (r.name, d, days)
            }
        }
        return nil
    }

    private static func dateFromISO(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = calendar
        return f.date(from: s)
    }
}
