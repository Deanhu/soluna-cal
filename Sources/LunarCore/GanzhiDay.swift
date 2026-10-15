import Foundation

public extension Ganzhi {
    /// 日干支：锚点法。2000-01-01 = 戊午（六十甲子序号 54），按日累加取模。
    /// 锚点与结果均经独立历法库逐日交叉核对（见 LunarCoreTests）。
    static func day(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let anchor = cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        let days = cal.dateComponents([.day], from: anchor,
                                      to: cal.startOfDay(for: date)).day ?? 0
        let idx = ((54 + days) % 60 + 60) % 60
        return stems[idx % 10] + branches[idx % 12]
    }
}

/// 十二时辰（含五鼠遁时干；23:00 起的晚子时按次日日干推，与主流历法库一致）
public enum Shichen {
    public struct Info: Equatable {
        public let name: String     // 如「午时」
        public let ganzhi: String   // 如「丙午」
    }

    public static func of(date: Date) -> Info {
        let cal = Calendar(identifier: .gregorian)
        let h = cal.component(.hour, from: date)
        let branchIdx = ((h + 1) / 2) % 12          // 23-1 子, 1-3 丑, …
        // 晚子时（23:00+）用次日日干
        let dayForStem = h >= 23
            ? cal.date(byAdding: .day, value: 1, to: date)! : date
        let dayGanzhi = Ganzhi.day(dayForStem)
        let dayStemIdx = Ganzhi.stems.firstIndex(of: String(dayGanzhi.prefix(1)))!
        let startStem = (dayStemIdx % 5) * 2         // 五鼠遁：甲己起甲子
        let stem = Ganzhi.stems[(startStem + branchIdx) % 10]
        return Info(name: Ganzhi.branches[branchIdx] + "时", ganzhi: stem + Ganzhi.branches[branchIdx])
    }
}

/// 真太阳时校正：标准时 + 经度修正（相对东经 120°）+ 均时差
public enum TrueSolarTime {
    /// 均时差（分钟），天文近似式；11 月初约 +16，2 月中约 −14
    public static func equationOfTimeMinutes(dayOfYear n: Int) -> Double {
        let b = 2 * Double.pi * Double(n - 81) / 364.0
        return 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
    }

    /// 校正量（分钟）。未定位时调用方传 longitude = 120（即只加均时差）
    public static func correctionMinutes(for date: Date, longitude: Double) -> Double {
        let cal = Calendar(identifier: .gregorian)
        let n = cal.ordinality(of: .day, in: .year, for: date) ?? 1
        return 4 * (longitude - 120) + equationOfTimeMinutes(dayOfYear: n)
    }

    public static func correct(_ date: Date, longitude: Double) -> Date {
        date.addingTimeInterval(correctionMinutes(for: date, longitude: longitude) * 60)
    }
}
