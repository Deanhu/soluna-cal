import WidgetKit
import SwiftUI

/// SolunaCal 月历小组件（二期 V2-7）：中/大两尺寸。
/// 历法/调休数据由 LunarCore 源码直接编进扩展（同模块编译，不可 import LunarCore；
/// 内置数据表，无需跨进程数据共享）；
/// 生日/纪念日依赖 App Group，待上架签名阶段接入（见 docs/phase2-plan.md）。
struct MonthEntry: TimelineEntry {
    let date: Date
}

struct MonthProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonthEntry { MonthEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (MonthEntry) -> Void) {
        completion(MonthEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MonthEntry>) -> Void) {
        // 每天 0 点刷新一次即可（月历粒度）
        let cal = Calendar(identifier: .gregorian)
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        completion(Timeline(entries: [MonthEntry(date: Date())], policy: .after(tomorrow)))
    }
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: MonthEntry

    private let cal = Calendar(identifier: .gregorian)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: "%d年%d月", cal.component(.year, from: entry.date),
                            cal.component(.month, from: entry.date)))
                    .font(.headline)
                Spacer()
                if family == .systemLarge,
                   let next = HolidayStore.nextHoliday(after: entry.date) {
                    Text("距\(next.name) \(next.days) 天")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(["一","二","三","四","五","六","日"], id: \.self) { w in
                    Text(w).font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(monthCells(), id: \.self) { cell in
                    Text(cell.text)
                        .font(.system(size: family == .systemLarge ? 11 : 9,
                                      weight: cell.isToday ? .bold : .regular))
                        .foregroundStyle(cell.isToday ? .white :
                                            (cell.inMonth ? .primary : Color(.tertiaryLabelColor)))
                        .frame(maxWidth: .infinity, minHeight: family == .systemLarge ? 24 : 16)
                        .background(cell.isToday ? Color.accentColor : cell.bandColor)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(family == .systemLarge ? 12 : 8)
    }

    private struct Cell: Hashable {
        let id: Int
        let text: String
        let isToday: Bool
        let inMonth: Bool
        let bandColor: Color
    }

    private func monthCells() -> [Cell] {
        let comps = cal.dateComponents([.year, .month], from: entry.date)
        let first = cal.date(from: comps)!
        let firstWeekday = (cal.component(.weekday, from: first) + 5) % 7
        let start = cal.date(byAdding: .day, value: -firstWeekday, to: first)!
        let today = cal.startOfDay(for: Date())
        return (0..<42).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let inMonth = cal.component(.month, from: d) == comps.month
            var text = "\(cal.component(.day, from: d))"
            if family == .systemLarge, inMonth,
               let lunar = LunarCalendar.lunarDateOrNil(from: d) {
                if let f = Festival.lunarFestival(of: lunar)
                    ?? Festival.solarFestival(month: comps.month ?? 0,
                                              day: cal.component(.day, from: d)) {
                    text = f
                } else if lunar.day == 1 {
                    text = LunarDate.monthName(lunar.month) + "月"
                }
            }
            var band = Color.clear
            if case .off = HolidayStore.status(on: d) { band = Color.red.opacity(0.12) }
            return Cell(id: i, text: text,
                        isToday: cal.startOfDay(for: d) == today,
                        inMonth: inMonth, bandColor: band)
        }
    }
}

struct SolunaMonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SolunaMonth", provider: MonthProvider()) { entry in
            MonthWidgetView(entry: entry)
        }
        .configurationDisplayName("Soluna 月历")
        .description("农历、节日、调休一屏看齐")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct SolunaWidgetBundle: WidgetBundle {
    var body: some Widget { SolunaMonthWidget() }
}
