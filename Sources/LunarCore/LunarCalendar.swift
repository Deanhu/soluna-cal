import Foundation

/// 农历日期
public struct LunarDate: Equatable, CustomStringConvertible {
    public let year: Int
    public let month: Int        // 1-12
    public let day: Int          // 1-29/30
    public let isLeapMonth: Bool

    public var description: String {
        "\(year)\(isLeapMonth ? " 闰" : " ")\(Self.monthName(month))月\(Self.dayName(day))"
    }

    static let monthNames = ["正","二","三","四","五","六","七","八","九","十","冬","腊"]
    static let dayNames = ["初一","初二","初三","初四","初五","初六","初七","初八","初九","初十",
                           "十一","十二","十三","十四","十五","十六","十七","十八","十九","二十",
                           "廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"]

    public static func monthName(_ m: Int) -> String { monthNames[m - 1] }
    public static func dayName(_ d: Int) -> String { dayNames[d - 1] }
}

/// 农历换算引擎（查表法，数据见 Generated/LunarData.swift，覆盖 1900–2099）
public enum LunarCalendar {
    /// 农历 1900-01-01 = 公历 1900-01-31
    private static let epoch: Date = {
        var c = DateComponents(); c.year = 1900; c.month = 1; c.day = 31
        return Calendar(identifier: .gregorian).date(from: c)!
    }()
    private static let gregorian = Calendar(identifier: .gregorian)

    public static var supportedRange: ClosedRange<Int> {
        LUNAR_FIRST_YEAR...(LUNAR_FIRST_YEAR + LUNAR_YEAR_INFOS.count - 1)
    }

    static func yearInfo(_ year: Int) -> UInt32 {
        precondition(supportedRange.contains(year), "year \(year) out of \(supportedRange)")
        return LUNAR_YEAR_INFOS[year - LUNAR_FIRST_YEAR]
    }

    /// 闰月月份（0 = 无）
    public static func leapMonth(of year: Int) -> Int { Int(yearInfo(year) & 0xF) }

    /// 某农历年某月天数；leap=true 查闰月
    public static func monthDays(year: Int, month: Int, leap: Bool = false) -> Int {
        let info = yearInfo(year)
        if leap {
            precondition(leapMonth(of: year) == month, "year \(year) has no leap month \(month)")
            return (info >> 4) & 1 == 1 ? 30 : 29
        }
        return (info >> (month + 4)) & 1 == 1 ? 30 : 29
    }

    /// 公历 -> 农历
    public static func lunarDate(from date: Date) -> LunarDate {
        let days = gregorian.dateComponents([.day], from: epoch, to: date).day!
        precondition(days >= 0, "date before 1900-01-31")
        var remaining = days
        var year = LUNAR_FIRST_YEAR
        while true {
            let yd = yearDays(year)
            if remaining < yd { break }
            remaining -= yd
            year += 1
        }
        let leap = leapMonth(of: year)
        var month = 1
        var isLeap = false
        while month <= 12 {
            // 先正常月
            let md = monthDays(year: year, month: month)
            if remaining < md { return LunarDate(year: year, month: month, day: remaining + 1, isLeapMonth: isLeap) }
            remaining -= md
            // 该月之后若有闰月
            if leap == month {
                let ld = monthDays(year: year, month: month, leap: true)
                if remaining < ld {
                    return LunarDate(year: year, month: month, day: remaining + 1, isLeapMonth: true)
                }
                remaining -= ld
            }
            month += 1
        }
        fatalError("unreachable")
    }

    /// 农历 -> 公历
    public static func solarDate(from lunar: LunarDate) -> Date {
        var days = 0
        for y in LUNAR_FIRST_YEAR..<lunar.year { days += yearDays(y) }
        let leap = leapMonth(of: lunar.year)
        var m = 1
        while m < lunar.month {
            days += monthDays(year: lunar.year, month: m)
            if leap == m { days += monthDays(year: lunar.year, month: m, leap: true) }
            m += 1
        }
        if lunar.isLeapMonth {
            precondition(leap == lunar.month, "no leap month")
            days += monthDays(year: lunar.year, month: lunar.month)
        }
        days += lunar.day - 1
        return gregorian.date(byAdding: .day, value: days, to: epoch)!
    }

    private static func yearDays(_ year: Int) -> Int {
        var total = 0
        for m in 1...12 { total += monthDays(year: year, month: m) }
        let leap = leapMonth(of: year)
        if leap > 0 { total += monthDays(year: year, month: leap, leap: true) }
        return total
    }
}

/// 二十四节气
public enum SolarTerm: Int, CaseIterable, CustomStringConvertible {
    case minorCold = 0, majorCold, springBegins, rainWater, insectsAwaken, springEquinox,
         qingming, grainRain, summerBegins, grainBuds, grainInEar, summerSolstice,
         minorHeat, majorHeat, autumnBegins, endOfHeat, whiteDew, autumnEquinox,
         coldDew, frostDescent, winterBegins, minorSnow, majorSnow, winterSolstice

    static let names = ["小寒","大寒","立春","雨水","惊蛰","春分","清明","谷雨","立夏","小满","芒种","夏至",
                        "小暑","大暑","立秋","处暑","白露","秋分","寒露","霜降","立冬","小雪","大雪","冬至"]
    public var description: String { Self.names[rawValue] }

    /// 该节气所在「日」（数据表只存日；节气所在月份 = rawValue/2+1，小寒1月、大寒1月、立春2月…）
    public func day(in year: Int) -> Date {
        let yi = year - LUNAR_FIRST_YEAR
        precondition(yi >= 0 && yi < SOLAR_TERM_DAYS.count)
        var c = DateComponents()
        c.year = year; c.month = rawValue / 2 + 1; c.day = Int(SOLAR_TERM_DAYS[yi][rawValue])
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// 某公历日是否节气日
    public static func on(date: Date, calendar: Calendar) -> SolarTerm? {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        guard y >= LUNAR_FIRST_YEAR && y < LUNAR_FIRST_YEAR + SOLAR_TERM_DAYS.count else { return nil }
        let row = SOLAR_TERM_DAYS[y - LUNAR_FIRST_YEAR]
        for t in allCases where t.rawValue / 2 + 1 == m && Int(row[t.rawValue]) == d { return t }
        return nil
    }
}

/// 干支与生肖
public enum Ganzhi {
    static let stems = ["甲","乙","丙","丁","戊","己","庚","辛","壬","癸"]
    static let branches = ["子","丑","寅","卯","辰","巳","午","未","申","酉","戌","亥"]
    static let animals = ["鼠","牛","虎","兔","龙","蛇","马","羊","猴","鸡","狗","猪"]

    /// 年干支（以农历年为准；1984 = 甲子）
    public static func year(_ lunarYear: Int) -> String {
        let i = (lunarYear - 1984) % 60
        let k = i < 0 ? i + 60 : i
        return stems[k % 10] + branches[k % 12]
    }
    public static func animal(_ lunarYear: Int) -> String {
        let i = (lunarYear - 1984) % 60
        let k = i < 0 ? i + 60 : i
        return animals[k % 12]
    }
}
