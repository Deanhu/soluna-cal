import SwiftUI
import LunarCore

/// 月历弹窗：实现 v3.4 颜色语义系统
/// - 今日 = 全图唯一实心圆（视觉重量最高）
/// - 假期 = 连续浅红色带（行内圆角端点），每段仅段首一枚「休」角标
/// - 补班 = 灰底「班」角标 + 浅灰底，数字墨色
/// - 节日红字 / 节气赭金 = 纯文字，不用图形重量
public struct CalendarPopoverView: View {
    public init(store: BirthdayStore) { self.store = store }
    @ObservedObject var store: BirthdayStore
    @State private var displayed: Date = Date()
    private let cal = Calendar(identifier: .gregorian)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    public var body: some View {
        VStack(spacing: 0) {
            header
            weekdayRow
            monthGrid
            Divider().padding(.top, 2)
            footer
        }
        .frame(width: 300)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            Button(action: { shiftMonth(-1) }) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()
            Button(action: { shiftMonth(1) }) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 4)
    }

    private var monthTitle: String {
        let y = cal.component(.year, from: displayed)
        let m = cal.component(.month, from: displayed)
        let lunar = LunarCalendar.lunarDate(from: displayed)
        return String(format: "%d年%d月 · %@%@年", y, m, Ganzhi.year(lunar.year), Ganzhi.animal(lunar.year))
    }

    private func shiftMonth(_ delta: Int) {
        displayed = cal.date(byAdding: .month, value: delta, to: displayed) ?? displayed
    }

    // MARK: 星期行

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(["一","二","三","四","五","六","日"], id: \.self) { w in
                Text(w).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 月历网格

    /// 一天在网格里的呈现模型
    private struct DayCell: Identifiable {
        let id = UUID()
        let date: Date
        let inMonth: Bool
        let isToday: Bool
        let status: DayStatus
        let lunarText: String
        let lunarColor: CellTextColor
        let bandRole: BandRole     // 假期色带的角色
        let showBadge: String?     // "休" / "班" / nil

        enum CellTextColor { case normal, festival, term, faint }
        enum BandRole { case none, single, start, middle, end }
    }

    private var monthCells: [DayCell] {
        // 周一起始，6 行 42 格
        let comps = cal.dateComponents([.year, .month], from: displayed)
        let first = cal.date(from: comps)!
        let firstWeekday = (cal.component(.weekday, from: first) + 5) % 7  // 周一=0
        let start = cal.date(byAdding: .day, value: -firstWeekday, to: first)!
        let today = cal.startOfDay(for: Date())

        var cells: [DayCell] = (0..<42).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let inMonth = cal.component(.month, from: d) == comps.month
            let lunar = LunarCalendar.lunarDate(from: d)
            let status = HolidayStore.status(on: d)

            // 农历小字：节日 > 节气 > 初一 > 日
            var text = LunarDate.dayName(lunar.day)
            var color = DayCell.CellTextColor.normal
            if let f = Festival.solarFestival(month: cal.component(.month, from: d),
                                              day: cal.component(.day, from: d)) {
                text = f; color = .festival
            } else if let f = Festival.lunarFestival(of: lunar) {
                text = f; color = .festival
            } else if let t = SolarTerm.on(date: d, calendar: cal) {
                text = t.description; color = .term
            } else if lunar.day == 1 {
                text = (lunar.isLeapMonth ? "闰" : "") + LunarDate.monthName(lunar.month) + "月"
            } else if store.match(date: d, lunar: lunar) != nil {
                text = "生日"; color = .festival
            }
            if !inMonth { color = .faint }

            return DayCell(date: d, inMonth: inMonth,
                           isToday: cal.startOfDay(for: d) == today,
                           status: status, lunarText: text, lunarColor: color,
                           bandRole: .none, showBadge: nil)
        }

        // 假期色带：连续 off 分段，行内断行处分段；段首格给「休」角标
        var i = 0
        while i < cells.count {
            guard case .off = cells[i].status else { i += 1; continue }
            var j = i
            while j + 1 < cells.count, case .off = cells[j + 1].status, (j + 1) % 7 != 0 { j += 1 }
            for k in i...j {
                let role: DayCell.BandRole =
                    (i == j) ? .single : (k == i ? .start : (k == j ? .end : .middle))
                cells[k] = DayCell(date: cells[k].date, inMonth: cells[k].inMonth,
                                   isToday: cells[k].isToday, status: cells[k].status,
                                   lunarText: cells[k].lunarText, lunarColor: cells[k].lunarColor,
                                   bandRole: role, showBadge: k == i ? "休" : nil)
            }
            i = j + 1
        }
        // 补班角标
        for k in cells.indices {
            if case .work = cells[k].status {
                cells[k] = DayCell(date: cells[k].date, inMonth: cells[k].inMonth,
                                   isToday: cells[k].isToday, status: cells[k].status,
                                   lunarText: cells[k].lunarText, lunarColor: cells[k].lunarColor,
                                   bandRole: .single, showBadge: "班")
            }
        }
        return cells
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(monthCells) { cell in cellView(cell) }
        }
    }

    @ViewBuilder
    private func cellView(_ cell: DayCell) -> some View {
        VStack(spacing: 1) {
            // 角标带：恒留 13px（无角标也占位，行高一致、零重叠）
            HStack {
                Spacer(minLength: 0)
                Text(cell.showBadge ?? " ")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 2)
                    .background(badgeBg(cell))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.trailing, 3)
            .frame(height: 13, alignment: .top)
            // 公历数字
            Text("\(cal.component(.day, from: cell.date))")
                .font(.system(size: 13))
                .foregroundStyle(cell.isToday ? .white : numberColor(cell))
                .frame(width: 22, height: 22)
                .background(cell.isToday ? Color.accentColor : .clear)
                .clipShape(Circle())
            // 农历小字（非当月格不显示，避免噪音）
            Text(cell.inMonth ? cell.lunarText : " ")
                .font(.system(size: 9))
                .foregroundStyle(lunarColor(cell))
                .lineLimit(1)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity)
        .background(bandBg(cell))
    }

    private func badgeBg(_ cell: DayCell) -> Color {
        guard let b = cell.showBadge else { return .clear }
        return b == "休" ? Color(hex: 0xE64545) : Color(hex: 0x6E6E73)
    }

    private func numberColor(_ cell: DayCell) -> Color {
        if !cell.inMonth { return Color(hex: 0xC7C7CC) }
        if case .off = cell.status { return Color(hex: 0xE64545) }
        if cell.lunarColor == .festival { return .primary }
        return .primary
    }

    private func lunarColor(_ cell: DayCell) -> Color {
        switch cell.lunarColor {
        case .festival: return Color(hex: 0xD43030)
        case .term:     return Color(hex: 0xB8860B)
        case .faint:    return Color(hex: 0xC7C7CC)
        case .normal:   return .secondary
        }
    }

    private func bandBg(_ cell: DayCell) -> some View {
        let tint: Color
        switch cell.status {
        case .off:  tint = Color(hex: 0xFFF0EF)
        case .work: tint = Color(hex: 0xF0F0F2)
        default:    tint = .clear
        }
        var radii = RectangleCornerRadii()
        switch cell.bandRole {
        case .single: radii = .init(topLeading: 8, bottomLeading: 8, bottomTrailing: 8, topTrailing: 8)
        case .start:  radii = .init(topLeading: 8, bottomLeading: 8)
        case .end:    radii = .init(bottomTrailing: 8, topTrailing: 8)
        default: break
        }
        return UnevenRoundedRectangle(cornerRadii: radii).fill(tint)
    }

    // MARK: 底部：倒计时条

    private var footer: some View {
        HStack {
            if let next = HolidayStore.nextHoliday(after: Date()) {
                Text("距 \(next.name) 还有 ")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                + Text("\(next.days)").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xD43030))
                + Text(" 天").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { displayed = Date() }) { Text("回到今天") }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
