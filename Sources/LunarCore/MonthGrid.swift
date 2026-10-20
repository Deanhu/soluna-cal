import Foundation

/// 月历网格模型（唯一真源）：弹窗与小组件共用同一套单元格计算。
///
/// 抽出的原因：此前弹窗与 widget 各写一份 monthCells，农历/节日/节气/调休规则
/// 重复实现，改一处忘另一处就会视觉漂移。现在网格语义只在这里定义，
/// 两个界面只负责「怎么画」。
public enum MonthGrid {

    public enum TextTone: Equatable {
        case normal      // 普通农历日
        case festival    // 节日
        case birthday    // 生日（单独色调，不和节日共用）
        case term        // 节气
        case faint       // 非本月
    }

    public enum BandRole: Equatable {
        case none, single, start, middle, end
    }

    public struct Day: Identifiable, Equatable {
        public let id: Int              // 0..<42，固定 6 行 × 7 列
        public let date: Date
        public let inMonth: Bool
        public let isToday: Bool
        public let status: DayStatus
        public let lunarText: String    // 节日 > 节气 > 初一 > 农历日
        public let tone: TextTone
        public let bandRole: BandRole   // 假期色带角色
        public let badge: String?       // "休" / "班" / nil
    }

    /// 构建某月的 42 格（周一起始，固定 6 行）。
    /// - Parameter birthdayText: 生日覆盖文案；返回 nil 表示当天无生日。
    ///   弹窗传入 BirthdayStore 的实现，widget 传 nil（无 App Group 数据）。
    public static func build(month: Date,
                             today: Date = Date(),
                             calendar cal: Calendar = Calendar(identifier: .gregorian),
                             birthdayText: ((Date, LunarDate) -> String?)? = nil) -> [Day] {
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps) else { return [] }
        let firstWeekday = (cal.component(.weekday, from: first) + 5) % 7   // 周一 = 0
        guard let start = cal.date(byAdding: .day, value: -firstWeekday, to: first) else { return [] }
        let todayStart = cal.startOfDay(for: today)

        var cells: [Day] = (0..<42).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            let inMonth = cal.component(.month, from: d) == comps.month
            // 边界月份可能超出历法数据范围：安全版返回 nil → 农历位空白，不崩溃
            guard let lunar = LunarCalendar.lunarDateOrNil(from: d) else {
                return Day(id: i, date: d, inMonth: inMonth,
                           isToday: cal.startOfDay(for: d) == todayStart,
                           status: .normal, lunarText: " ", tone: .faint,
                           bandRole: .none, badge: nil)
            }

            var text = LunarDate.dayName(lunar.day)
            var tone = TextTone.normal
            if let f = Festival.solarFestival(month: cal.component(.month, from: d),
                                              day: cal.component(.day, from: d)) {
                text = f; tone = .festival
            } else if let f = Festival.lunarFestival(of: lunar) {
                text = f; tone = .festival
            } else if let t = SolarTerm.on(date: d, calendar: cal) {
                text = t.description; tone = .term
            } else if lunar.day == 1 {
                text = (lunar.isLeapMonth ? "闰" : "") + LunarDate.monthName(lunar.month) + "月"
            }
            // 生日优先于初一月份名（「妈妈」比「冬月初一」对用户更重要）
            if let b = birthdayText?(d, lunar) {
                text = b; tone = .birthday
            }
            if !inMonth { tone = .faint }

            return Day(id: i, date: d, inMonth: inMonth,
                       isToday: cal.startOfDay(for: d) == todayStart,
                       status: HolidayStore.status(on: d),
                       lunarText: text, tone: tone, bandRole: .none, badge: nil)
        }

        // 假期色带：连续休息为一个假期段（跨行不断段），整段只在第一天标「休」
        // （对齐小米/华为行为：7 天长假跨周只出现一个角标）；色带圆角仍按行首尾处理
        var i = 0
        while i < cells.count {
            guard case .off = cells[i].status else { i += 1; continue }
            var runEnd = i
            while runEnd + 1 < cells.count, case .off = cells[runEnd + 1].status { runEnd += 1 }
            for k in i...runEnd {
                let role: BandRole
                if i == runEnd { role = .single }
                else if k == i { role = .start }
                else if k == runEnd { role = .end }
                else if k % 7 == 0 { role = .start }
                else if (k + 1) % 7 == 0 { role = .end }
                else { role = .middle }
                cells[k] = copy(cells[k], bandRole: role, badge: k == i ? "休" : nil)
            }
            i = runEnd + 1
        }
        // 补班：单格「班」角标
        for k in cells.indices {
            if case .work = cells[k].status {
                cells[k] = copy(cells[k], bandRole: .single, badge: "班")
            }
        }
        return cells
    }

    private static func copy(_ d: Day, bandRole: BandRole, badge: String?) -> Day {
        Day(id: d.id, date: d.date, inMonth: d.inMonth, isToday: d.isToday,
            status: d.status, lunarText: d.lunarText, tone: d.tone,
            bandRole: bandRole, badge: badge)
    }
}
