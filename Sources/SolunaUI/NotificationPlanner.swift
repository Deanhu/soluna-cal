import Foundation
import LunarCore

/// 通知偏好（UserDefaults 持久化键见 NotificationManager）
public struct NotifyPrefs: Equatable {
    public var holidayEve = false    // 放假前一日 18:00
    public var festival = false      // 节日当天 09:00
    public var birthday = false      // 生日/纪念日当天 09:00
    public var dndEnabled = false    // 免打扰
    public var dndStartMin = 22 * 60 // 分钟制，默认可跨零点
    public var dndEndMin = 7 * 60
}

public struct NotifyPlan: Equatable {
    public enum Kind: String { case holidayEve, festival, birthday }
    public let kind: Kind
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
}

/// 通知计划器（纯函数：给定 now 产出未来 N 天的通知列表，全部逻辑可测）
public enum NotificationPlanner {
    private static let cal = Calendar(identifier: .gregorian)

    public static func plan(now: Date, prefs: NotifyPrefs, store: BirthdayStore,
                            horizonDays: Int = 60) -> [NotifyPlan] {
        var out: [NotifyPlan] = []
        let today = cal.startOfDay(for: now)

        // 放假前一日 18:00：「明天开始休 N 天」
        if prefs.holidayEve {
            for yy in [cal.component(.year, from: now), cal.component(.year, from: now) + 1] {
                for r in HolidayStore.load(year: yy).ranges {
                    guard let first = r.off.map({ "\(yy)-\($0)" }).sorted().first,
                          let start = iso(first) else { continue }
                    guard let fire = at(start, dayOffset: -1, hour: 18) else { continue }
                    guard fire > now, fire <= today + Double(horizonDays) * 86400 else { continue }
                    out.append(NotifyPlan(
                        kind: .holidayEve, id: "holidayEve-\(first)",
                        fireDate: fire, title: "明天开始放假",
                        body: "\(r.name)：连休 \(r.off.count) 天" +
                              (r.work.isEmpty ? "" : "；补班 \(r.work.count) 天，记得设闹钟")))
                }
            }
        }

        // 逐日扫描：节日 + 生日（当天 09:00）
        for offset in 0..<horizonDays {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let fire = at(day, dayOffset: 0, hour: 9), fire > now else { continue }
            let y = cal.component(.year, from: day)
            let m = cal.component(.month, from: day)
            let d = cal.component(.day, from: day)

            if prefs.festival {
                let lunar = LunarCalendar.lunarDateOrNil(from: day)
                let names = [
                    Festival.solarFestival(month: m, day: d),
                    lunar.flatMap { Festival.lunarFestival(of: $0) },
                ].compactMap { $0 }
                for name in names {
                    out.append(NotifyPlan(kind: .festival,
                                          id: "festival-\(y)-\(m)-\(d)-\(name)",
                                          fireDate: fire, title: name,
                                          body: "今天是\(name)"))
                }
            }

            if prefs.birthday {
                for e in store.entries where store.matches(e, date: day) {
                    out.append(NotifyPlan(kind: .birthday,
                                          id: "birthday-\(e.id.uuidString)-\(y)\(m)\(d)",
                                          fireDate: fire, title: "今天是\(e.name)的日子",
                                          body: "\(e.name) · \(describe(e))"))
                }
            }
        }

        // 免打扰：命中时段的通知顺延到时段结束
        if prefs.dndEnabled {
            out = out.map { p in
                NotifyPlan(kind: p.kind, id: p.id,
                           fireDate: shiftOutOfDND(p.fireDate,
                                                   startMin: prefs.dndStartMin,
                                                   endMin: prefs.dndEndMin),
                           title: p.title, body: p.body)
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    /// 免打扰顺延：fire 落在 [startMin, endMin)（可跨零点）则推到窗口结束时刻
    public static func shiftOutOfDND(_ fire: Date, startMin: Int, endMin: Int) -> Date {
        let minOfDay = cal.component(.hour, from: fire) * 60 + cal.component(.minute, from: fire)
        let overnight = startMin > endMin
        let inWindow = overnight ? (minOfDay >= startMin || minOfDay < endMin)
                                 : (minOfDay >= startMin && minOfDay < endMin)
        guard inWindow else { return fire }
        let dayStart = cal.startOfDay(for: fire)
        // 跨零点且当前在凌晨段 → 窗口结束在今天；否则在明天
        let endIsToday = overnight ? (minOfDay < endMin) : true
        let targetDay = endIsToday ? dayStart : cal.date(byAdding: .day, value: 1, to: dayStart)!
        return targetDay + TimeInterval(endMin * 60)
    }

    private static func at(_ day: Date, dayOffset: Int, hour: Int) -> Date? {
        guard let d = cal.date(byAdding: .day, value: dayOffset, to: day) else { return nil }
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)
    }

    private static func iso(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.calendar = cal
        return f.date(from: s)
    }

    private static func describe(_ e: BirthdayStore.Entry) -> String {
        e.calendar == .lunar
            ? "农历\(e.isLeapMonth ? "闰" : "")\(LunarDate.monthName(e.lunarMonth))月\(LunarDate.dayName(e.lunarDay))"
            : "公历\(e.lunarMonth)月\(e.lunarDay)日"
    }
}
