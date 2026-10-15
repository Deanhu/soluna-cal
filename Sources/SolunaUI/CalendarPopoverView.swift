import SwiftUI
import AppKit
import LunarCore

/// 月历弹窗：实现 v3.4 颜色语义系统
/// - 今日 = 全图唯一实心圆（视觉重量最高）
/// - 假期 = 连续浅红色带（行内圆角端点），每段仅段首一枚「休」角标
/// - 补班 = 灰底「班」角标 + 浅灰底，数字墨色
/// - 节日红字 / 节气赭金 = 纯文字，不用图形重量
public struct CalendarPopoverView: View {
    /// initialMonth：预览/测试用，可指定起始月份（如边界 1900-01 / 2099-12）
    /// initialSelected：预览/测试用，预选某日以渲染选中日区域（干支行、日程列表）
    /// initialEditing：预览/测试用，让某日直接进入就地编辑条状态
    public init(store: BirthdayStore, initialMonth: Date? = nil, initialSelected: Date? = nil, initialEditing: Date? = nil) {
        self.store = store
        _displayed = State(initialValue: initialMonth ?? Date())
        _selectedDay = State(initialValue: initialSelected)
        _editingDay = State(initialValue: initialEditing)
    }
    @ObservedObject var store: BirthdayStore
    @State private var displayed: Date
    @State private var showSettings = false
    @State private var selectedDay: Date?
    @State private var editingDay: Date?
    @State private var locationTick = 0   // 定位成功后 bump，强制重算干支行
    @State private var newEventTitle = ""
    @State private var eventError: String?
    @AppStorage("yijiEnabled") private var yijiEnabled = false
    @AppStorage("countdownEnabled") private var countdownEnabled = true
    @AppStorage("popoverDensity") private var densityRaw = PopoverDensity.standard.rawValue
    @AppStorage("skin") private var skinRaw = Skin.default.rawValue
    @AppStorage("ganzhiEnabled") private var ganzhiEnabled = false
    private let cal = Calendar(identifier: .gregorian)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    /// 当前密度的整套尺寸 token
    private var t: PopoverDensity.Tokens {
        (PopoverDensity(rawValue: densityRaw) ?? .standard).tokens
    }
    private var skin: Skin { Skin(rawValue: skinRaw) ?? .default }

    public var body: some View {
        VStack(spacing: 0) {
            header
            weekdayRow
            monthGrid
            inlineEventEditor
            selectedDayEvents
            if yijiEnabled, let yj = Yiji.on(date: Date()) {
                Text("宜 \(yj.yi)　忌 \(yj.ji)")
                    .font(.system(size: t.lunarFont))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.top, 3)
            }
            Divider().padding(.top, 2)
            footer
        }
        .frame(width: t.popoverWidth)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .onAppear { refreshEvents() }
        .onChange(of: displayed) { refreshEvents() }
        .onReceive(NotificationCenter.default.publisher(for: .locationDidUpdate)) { _ in
            locationTick += 1
        }
    }

    private func refreshEvents() {
        EventProvider.shared.requestAccessIfNeeded { [self] in
            EventProvider.shared.refresh(year: cal.component(.year, from: displayed),
                                         month: cal.component(.month, from: displayed))
        }
        EventProvider.shared.refresh(year: cal.component(.year, from: displayed),
                                     month: cal.component(.month, from: displayed))
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
        guard let lunar = LunarCalendar.lunarDateOrNil(from: displayed) else {
            return String(format: "%d年%d月", y, m)
        }
        return String(format: "%d年%d月 · %@%@年", y, m, Ganzhi.year(lunar.year), Ganzhi.animal(lunar.year))
    }

    /// 翻页范围钳制在历法数据覆盖区间内（数据外无农历可显示）
    private func shiftMonth(_ delta: Int) {
        guard let next = cal.date(byAdding: .month, value: delta, to: displayed) else { return }
        let y = cal.component(.year, from: next)
        guard LunarCalendar.supportedRange.contains(y) else { return }
        displayed = next
    }

    // MARK: 星期行

    private var weekdayRow: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(["一","二","三","四","五","六","日"], id: \.self) { w in
                Text(w).font(.system(size: t.lunarFont)).foregroundStyle(.secondary)
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
            // 翻页边界格可能超出历法数据范围：安全版返回 nil → 农历位空白，不崩溃
            guard let lunar = LunarCalendar.lunarDateOrNil(from: d) else {
                return DayCell(date: d, inMonth: inMonth,
                               isToday: cal.startOfDay(for: d) == today,
                               status: .normal, lunarText: " ", lunarColor: .faint,
                               bandRole: .none, showBadge: nil)
            }
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
            }
            // 生日优先于初一月份名（「妈妈的生日」比「冬月初一」对用户更重要）
            if let b = store.match(date: d, lunar: lunar) {
                text = b.name.count <= 2 ? b.name : "生日"; color = inMonth ? .festival : .faint
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
        LazyVGrid(columns: columns, spacing: t.rowSpacing) {
            ForEach(monthCells) { cell in cellView(cell) }
        }
    }

    /// 双击日期的就地编辑条（二期：写入系统日历）
    @ViewBuilder
    private var inlineEventEditor: some View {
        if let ed = editingDay {
            let m = cal.component(.month, from: ed)
            let d = cal.component(.day, from: ed)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(m)月\(d)日")
                        .font(.system(size: t.footerFont, weight: .medium))
                    TextField("事件名称（写进系统日历）", text: $newEventTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: t.footerFont))
                        .onSubmit { commitEvent() }
                    Button("保存") { commitEvent() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                        .disabled(newEventTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("取消") { editingDay = nil; eventError = nil }
                        .buttonStyle(.plain).controlSize(.small)
                }
                if let err = eventError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 8).padding(.top, 4)
        }
    }

    private func commitEvent() {
        guard let ed = editingDay else { return }
        let title = newEventTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        do {
            try EventProvider.shared.addEvent(title: title, on: ed)
            editingDay = nil; newEventTitle = ""; eventError = nil
            selectedDay = ed   // 保存后直接展示该日（能看到新事件点）
        } catch {
            eventError = "写入失败：\(error.localizedDescription)"
        }
    }

    /// 选中日的事件列表（点日期展开；只读）
    @ViewBuilder
    private var selectedDayEvents: some View {
        if let sel = selectedDay {
            let d = cal.component(.day, from: sel)
            let m = cal.component(.month, from: sel)
            let events = EventProvider.shared.events(on: sel)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(m)月\(d)日 日程")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if ganzhiEnabled { ganzhiLine(for: sel) }
                if events.isEmpty {
                    Text(EventProvider.shared.authorized ? "当日无日程" : "授权系统日历后显示当日日程")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                } else {
                    ForEach(events, id: \.self) { t in
                        Text("· " + t).font(.system(size: 11)).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.top, 4)
        }
    }

    /// 干支时辰行（默认关）：日柱 + 当前时辰（真太阳时校正）
    private func ganzhiLine(for day: Date) -> some View {
        let lon = LocationProvider.shared.longitude
        let corrected = TrueSolarTime.correct(Date(), longitude: lon)
        let sc = Shichen.of(date: corrected)
        let delta = TrueSolarTime.correctionMinutes(for: Date(), longitude: lon)
        let located = LocationProvider.shared.isLocated
        return Text("日柱 \(Ganzhi.day(day)) · 现在\(sc.ganzhi)时"
            + "（真太阳时\(delta >= 0 ? "+" : "")\(String(format: "%.0f", delta))分"
            + (located ? "" : "·未定位") + "）")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func cellView(_ cell: DayCell) -> some View {
        VStack(spacing: 1) {
            // 角标带：恒留占位高（无角标也占位，行高一致、零重叠）
            HStack {
                Spacer(minLength: 0)
                Text(cell.showBadge ?? " ")
                    .font(.system(size: t.badgeFont, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 2)
                    .background(badgeBg(cell))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.trailing, 3)
            .frame(height: t.badgeStripHeight, alignment: .top)
            // 公历数字
            Text("\(cal.component(.day, from: cell.date))")
                .font(.system(size: t.numberFont))
                .foregroundStyle(cell.isToday ? .white : numberColor(cell))
                .frame(width: t.todayCircle, height: t.todayCircle)
                .background(cell.isToday ? skin.todayFill : .clear)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                        .opacity(isSelected(cell) && !cell.isToday ? 1 : 0)
                )
            // 农历小字（非当月格不显示，避免噪音）
            Text(cell.inMonth ? cell.lunarText : " ")
                .font(.system(size: t.lunarFont))
                .foregroundStyle(lunarColor(cell))
                .lineLimit(1)
            // 事件点（系统日历只读整合）
            Circle()
                .fill(EventProvider.shared.hasEvent(on: cell.date) && cell.inMonth
                      ? Color.accentColor : .clear)
                .frame(width: t.eventDot, height: t.eventDot)
                .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity)
        .background(bandBg(cell))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingDay = cell.date
            newEventTitle = ""
            eventError = nil
        }
        .onTapGesture(count: 1) {
            selectedDay = isSelected(cell) ? nil : cell.date
        }
    }

    private func isSelected(_ cell: DayCell) -> Bool {
        guard let sel = selectedDay else { return false }
        return cal.startOfDay(for: sel) == cal.startOfDay(for: cell.date)
    }

    private func badgeBg(_ cell: DayCell) -> Color {
        guard let b = cell.showBadge else { return .clear }
        return b == "休" ? skin.badgeOff : skin.badgeWork
    }

    private func numberColor(_ cell: DayCell) -> Color {
        if !cell.inMonth { return .adaptive(light: 0xC7C7CC, dark: 0x545456) }
        if case .off = cell.status { return skin.holidayNumber }
        if cell.lunarColor == .festival { return .primary }
        return .primary
    }

    private func lunarColor(_ cell: DayCell) -> Color {
        switch cell.lunarColor {
        case .festival: return skin.festivalText
        case .term:     return skin.termText
        case .faint:    return .adaptive(light: 0xC7C7CC, dark: 0x545456)
        case .normal:   return .adaptive(light: 0x86868B, dark: 0x98989D)
        }
    }

    private func bandBg(_ cell: DayCell) -> some View {
        let tint: Color
        switch cell.status {
        case .off:  tint = skin.bandOff
        case .work: tint = skin.bandWork
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
            if countdownEnabled, let next = HolidayStore.nextHoliday(after: Date()) {
                Text("距 \(next.name) 还有 ")
                    .font(.system(size: t.footerFont)).foregroundStyle(.secondary)
                + Text("\(next.days)").font(.system(size: t.footerFont, weight: .semibold))
                    .foregroundStyle(skin.countdownAccent)
                + Text(" 天").font(.system(size: t.footerFont)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: { showSettings = true }) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Button(action: { displayed = Date() }) { Text("回到今天") }
                .buttonStyle(.plain).font(.system(size: t.footerFont)).foregroundStyle(Color.accentColor)
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

    /// 深浅色自适应：浅色模式用 light，深色模式用 dark
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}
