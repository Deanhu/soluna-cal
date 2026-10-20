import Foundation

/// 年视图的数据（纯逻辑，可单测）：把某一年里「有内容的日子」按月归档。
///
/// 为什么不做年宫格：弹窗宽度只有 300–336pt，12 个月塞进去每天格子约 14pt，
/// 字号得压到 5–6pt，等于不可读。列表才是这个尺寸下能读的形态。
///
/// 收录内容：放假段（连续休合并成一条）、补班日、节日、节气、生日。
public enum YearDigest {

    public enum Kind: Int, Equatable {
        case off = 0        // 放假
        case work = 1       // 补班
        case festival = 2   // 节日
        case term = 3       // 节气
        case birthday = 4   // 生日
    }

    public struct Item: Identifiable, Equatable {
        public let id: String
        public let day: Int
        public let endDay: Int?      // 放假日段用；单日为 nil
        public let text: String
        public let kind: Kind

        public var dayRangeText: String {
            guard let e = endDay, e != day else { return "\(day)日" }
            return "\(day)–\(e)日"
        }
    }

    private struct Run {
        var name: String
        var month: Int
        var start: Int
        var end: Int
    }

    /// 生成某年 12 个月的条目；key 为月份 1–12。
    /// - Parameter birthdayText: 与 MonthGrid 相同语义的生日覆盖闭包（nil 表示不收录生日）
    public static func build(year: Int,
                             calendar: Calendar = Calendar(identifier: .gregorian),
                             birthdayText: ((Date, LunarDate) -> String?)? = nil) -> [Int: [Item]] {
        var out: [Int: [Item]] = [:]
        guard var cursor = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) else {
            return out
        }

        var openOff: Run?
        var previous: Date?
        var offRuns: [Run] = []          // 用于去掉「假期名 = 节日名」的重复行

        func flushOff() {
            guard let run = openOff else { return }
            out[run.month, default: []].append(
                .init(id: "off-\(run.month)-\(run.start)-\(run.name)",
                      day: run.start, endDay: run.end, text: run.name, kind: .off))
            offRuns.append(run)
            openOff = nil
        }

        while calendar.component(.year, from: cursor) == year {
            let month = calendar.component(.month, from: cursor)
            let day = calendar.component(.day, from: cursor)
            let status = HolidayStore.status(on: cursor)

            if case .off(let name) = status {
                let consecutive = openOff?.name == name && previous != nil
                    && calendar.isDate(previous!, inSameDayAs:
                        calendar.date(byAdding: .day, value: -1, to: cursor)!)
                if consecutive {
                    openOff?.end = day
                } else {
                    flushOff()
                    openOff = Run(name: name, month: month, start: day, end: day)
                }
            } else {
                flushOff()
                if case .work(let name) = status {
                    out[month, default: []].append(
                        .init(id: "work-\(month)-\(day)", day: day, endDay: nil,
                              text: "补班 · \(name)", kind: .work))
                }
            }

            if let f = Festival.solarFestival(month: month, day: day) {
                out[month, default: []].append(
                    .init(id: "festival-\(month)-\(day)-\(f)", day: day, endDay: nil,
                          text: f, kind: .festival))
            } else {
                let lunar = LunarCalendar.lunarDate(from: cursor)
                if let f = Festival.lunarFestival(of: lunar) {
                    out[month, default: []].append(
                        .init(id: "festival-\(month)-\(day)-\(f)", day: day, endDay: nil,
                              text: f, kind: .festival))
                }
            }

            if let term = SolarTerm.on(date: cursor, calendar: calendar) {
                out[month, default: []].append(
                    .init(id: "term-\(month)-\(day)-\(term)", day: day, endDay: nil,
                          text: term.description, kind: .term))
            }

            if let b = birthdayText?(cursor, LunarCalendar.lunarDate(from: cursor)) {
                out[month, default: []].append(
                    .init(id: "birthday-\(month)-\(day)-\(b)", day: day, endDay: nil,
                          text: b, kind: .birthday))
            }

            previous = cursor
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        flushOff()

        // 同一段假期已经用假期名占了一行（如「15–23日 春节」），
        // 再列一条「17日 春节」纯属重复，去掉。
        for run in offRuns {
            guard var items = out[run.month] else { continue }
            let runKey = normalize(run.name)
            items.removeAll { $0.kind == .festival && normalize($0.text) == runKey
                && $0.day >= run.start && $0.day <= run.end }
            out[run.month] = items
        }

        for key in out.keys {
            out[key]?.sort { a, b in
                if a.day != b.day { return a.day < b.day }
                return a.kind.rawValue < b.kind.rawValue
            }
        }
        return out
    }

    /// 「清明节」与「清明」视为同名；「国庆节」与「国庆」同理
    private static func normalize(_ s: String) -> String {
        s.hasSuffix("节") ? String(s.dropLast()) : s
    }
}
