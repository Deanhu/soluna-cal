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

    /// 内置兜底数据（断网/双源皆挂时用）
    static let bundled: [HolidayData] = [
        // BUNDLED-BEGIN 由 tools/gen_holiday_data.py 从 timor.tech 真实数据机械生成，勿手改
        HolidayData(year: 2026, ranges: [
            .init(name: "元旦", off: ["01-01","01-02","01-03"], work: ["01-04"]),
            .init(name: "春节", off: ["02-15","02-16","02-17","02-18","02-19","02-20","02-21","02-22","02-23"], work: ["02-28"]),
            .init(name: "清明节", off: ["04-04","04-05","04-06"], work: []),
            .init(name: "劳动节", off: ["05-01","05-02","05-03","05-04","05-05"], work: ["05-09"]),
            .init(name: "端午节", off: ["06-19","06-20","06-21"], work: []),
            .init(name: "中秋节", off: ["09-25","09-26","09-27"], work: []),
            .init(name: "国庆节", off: ["10-01","10-02","10-03","10-04","10-05","10-06","10-07"], work: ["10-10"]),
        ]),
        // BUNDLED-END
        // 跨年倒计时的次年元旦兜底（手工维护；次年完整安排待国务院通知后跑生成器）
        HolidayData(year: 2027, ranges: [
            .init(name: "元旦", off: ["01-01","01-02","01-03"], work: []),
        ]),
    ]

    // MARK: 三级数据源：主源 API → curated 校验 → 内置兜底
    //
    // 主源: timor.tech 节假日 API（社区维护，国务院通知后更新快，零运维）
    // 校验: repo data/holidays.json（人工维护，不直接给用户用，用来对账）
    // 兜底: bundled（上面）
    // 对账不一致 → onMismatch 告警（默认 NSLog），不静默信任任何一方

    /// 主源 API 模板，{year} 占位
    public static var primaryURLTemplate = "https://timor.tech/api/holiday/year/{year}"
    /// curated 校验源（repo raw URL，人工维护）
    public static var curatedURL: URL? = URL(string:
        "https://raw.githubusercontent.com/Deanhu/soluna-cal/main/data/holidays.json")
    /// 对账不一致回调（测试可注入）
    public static var onMismatch: (String) -> Void = { NSLog("[SolunaCal] 调休数据对账不一致: %@", $0) }

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

    // MARK: 主源拉取 + 对账

    /// timor.tech 响应格式（internal 以便测试直接驱动 convert）
    struct TimorResponse: Codable {
        struct Day: Codable {
            var holiday: Bool
            var name: String?
            var after: Bool?     // true = 调休补班日
            var target: String?  // 补班归属的假期名（如「国庆节后补班」的 target=「国庆节」）
        }
        var code: Int
        var holiday: [String: Day]?
    }

    /// 与 tools/gen_holiday_data.py 的 norm_name 保持一致（单一分组规则，两侧同步改）
    static func normalizeHolidayName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "调休", with: "")
            .replacingOccurrences(of: "后补班", with: "")
            .trimmingCharacters(in: .whitespaces)
        let springDays: Set<String> = ["除夕", "初一", "初二", "初三", "初四", "初五",
                                       "初六", "初七", "初八", "初九", "初十"]
        if springDays.contains(name) { name = "春节" }
        return name
    }

    /// 把 timor.tech 按日条目聚合为我们的 Range 结构
    static func convert(timor t: TimorResponse, year: Int) -> HolidayData {
        var byName: [String: (off: [String], work: [String])] = [:]
        for (md, day) in t.holiday ?? [:] {
            let raw: String
            if day.holiday { raw = day.name ?? "假期" }
            else if day.after == true { raw = day.target ?? day.name ?? "假期" }
            else { continue }
            let name = normalizeHolidayName(raw)
            var e = byName[name, default: ([], [])]
            if day.holiday { e.off.append(md) } else { e.work.append(md) }
            byName[name] = e
        }
        return HolidayData(year: year, ranges: byName.map {
            HolidayData.Range(name: $0.key, off: $0.value.off.sorted(), work: $0.value.work.sorted())
        })
    }

    /// 启动后后台拉取：主源 → 缓存；再拉 curated 对账
    public static func refreshInBackground() {
        let years = [calendar.component(.year, from: Date()),
                     calendar.component(.year, from: Date()) + 1]
        for y in years { refreshYear(y) }
        reconcileInBackground()
    }

    /// timor.tech 有 Cloudflare 挑战，默认 UA 会被 403；必须带浏览器 UA
    private static func timorRequest(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url)
        r.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
                   forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private static func refreshYear(_ year: Int) {
        guard let url = URL(string: primaryURLTemplate.replacingOccurrences(of: "{year}", with: "\(year)")) else { return }
        URLSession.shared.dataTask(with: timorRequest(url)) { data, _, _ in
            guard let data,
                  let resp = try? JSONDecoder().decode(TimorResponse.self, from: data),
                  resp.code == 0 else { return }
            let hd = convert(timor: resp, year: year)
            guard !hd.ranges.isEmpty else { return }
            try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try? JSONEncoder().encode(hd)
                .write(to: cacheDir.appendingPathComponent("holidays-\(year).json"))
        }.resume()
    }

    /// 对账：主源缓存 vs curated 校验源；不一致触发告警，不改变用户数据
    static func reconcileInBackground() {
        guard let url = curatedURL else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let curated = try? JSONDecoder().decode([HolidayData].self, from: data) else { return }
            for c in curated {
                let primary = load(year: c.year)
                guard !primary.ranges.isEmpty else { continue }
                if fingerprint(primary) != fingerprint(c) {
                    onMismatch("year=\(c.year) 主源与 curated 不一致（主源 \(primary.ranges.count) 段 / curated \(c.ranges.count) 段）")
                }
            }
        }.resume()
    }

    /// 对账指纹：只看 off/work 日期集合（名字措辞差异不算不一致）
    static func fingerprint(_ hd: HolidayData) -> String {
        let off = hd.ranges.flatMap { $0.off }.sorted().joined()
        let work = hd.ranges.flatMap { $0.work }.sorted().joined()
        return off + "|" + work
    }

    /// 距下一个法定假（名称, 日期, 天数）；已开始的假期段跳过（不显示「距进行中的假期还有 1 天」）
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
