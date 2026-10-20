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
    @State private var showYear = false
    @State private var selectedDay: Date?
    @State private var editingDay: Date?
    @State private var locationTick = 0   // 定位成功后 bump，强制重算干支行
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
            if let sel = selectedDay {
                DayDetailView(date: sel, calendar: cal, showYiji: yijiEnabled) {
                    editingDay = sel
                }
            }
            if selectedDay == nil, yijiEnabled, let yj = Yiji.on(date: Date()) {
                Text("宜 \(yj.yi)　忌 \(yj.ji)")
                    .font(.system(size: t.lunarFont))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.top, 8)
            }
            Divider().padding(.top, 4)
            footer
        }
        .frame(width: t.popoverWidth)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .sheet(isPresented: Binding(
            get: { editingDay != nil },
            set: { if !$0 { editingDay = nil } }
        )) {
            if let day = editingDay {
                EventEditorView(date: day, calendar: cal) {
                    EventProvider.shared.refresh(
                        year: cal.component(.year, from: day),
                        month: cal.component(.month, from: day))
                }
            }
        }
        .sheet(isPresented: $showYear) {
            let year = cal.component(.year, from: displayed)
            YearOverviewView(
                year: year,
                digest: YearDigest.build(year: year, calendar: cal) { d, lunar in
                    guard let b = store.match(date: d, lunar: lunar) else { return nil }
                    return b.name.count <= 2 ? b.name : "生日"
                },
                skin: skin,
                onPick: { month in
                    if let d = cal.date(from: DateComponents(year: year, month: month, day: 1)) {
                        displayed = d
                    }
                }
            )
        }
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
            Button(action: { showYear = true }) {
                HStack(spacing: 2) {
                    Text(monthTitle).font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: { shiftMonth(1) }) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 6)
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

    /// 网格语义来自 LunarCore.MonthGrid —— 弹窗与小组件共用同一份单元格计算
    private typealias DayCell = MonthGrid.Day

    private var monthCells: [DayCell] {
        MonthGrid.build(month: displayed, calendar: cal) { d, lunar in
            guard let b = store.match(date: d, lunar: lunar) else { return nil }
            return b.name.count <= 2 ? b.name : "生日"
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: t.rowSpacing) {
            ForEach(monthCells) { cell in cellView(cell) }
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
            // 公历数字（角标贴在这个圆的右上角，不再单独占一条 13pt 空间）
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
                .font(.system(size: t.lunarFont,
                              weight: cell.tone == .birthday ? .semibold : .regular))
                .foregroundStyle(lunarColor(cell))
                .lineLimit(1)
        }
        // 角标位：只留半个条带高（原先是整条 13pt，行间因此显出大片空白）
        .padding(.top, t.badgeStripHeight * 0.5)
        .frame(maxWidth: .infinity)
        .background(bandBg(cell))
        // 角标叠在预留位右上角：落在色带内，也不压到上一行
        .overlay(alignment: .topTrailing) { badgeTag(cell) }
        // 事件点浮在行间空隙里，不占一行高（没有日程时那里本来就是空白）
        .overlay(alignment: .bottom) {
            Circle()
                .fill(EventProvider.shared.hasEvent(on: cell.date) && cell.inMonth
                      ? Color.accentColor : .clear)
                .frame(width: t.eventDot, height: t.eventDot)
                .offset(y: t.eventDot)
        }
        .background(bandBg(cell))
        .contentShape(Rectangle())
        // 双击：打开新建日程面板（单击是选中，两个手势必须按 2 → 1 的顺序挂）
        .onTapGesture(count: 2) {
            editingDay = cell.date
        }
        .onTapGesture(count: 1) {
            selectedDay = isSelected(cell) ? nil : cell.date
        }
    }

    /// 休 / 班 角标：叠在单元格预留位（半个条带高）的右上角，落在色带内
    @ViewBuilder
    private func badgeTag(_ cell: DayCell) -> some View {
        if let b = cell.badge {
            Text(b)
                .font(.system(size: t.badgeFont, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 2)
                .background(badgeBg(cell))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .padding(.trailing, 3)
        }
    }

    private func isSelected(_ cell: DayCell) -> Bool {
        guard let sel = selectedDay else { return false }
        return cal.startOfDay(for: sel) == cal.startOfDay(for: cell.date)
    }

    private func badgeBg(_ cell: DayCell) -> Color {
        guard let b = cell.badge else { return .clear }
        return b == "休" ? skin.badgeOff : skin.badgeWork
    }

    private func numberColor(_ cell: DayCell) -> Color {
        if !cell.inMonth { return .adaptive(light: 0xC7C7CC, dark: 0x545456) }
        if case .off = cell.status { return skin.holidayNumber }
        if cell.tone == .festival { return .primary }
        return .primary
    }

    private func lunarColor(_ cell: DayCell) -> Color {
        switch cell.tone {
        case .festival: return skin.festivalText
        case .birthday: return skin.birthdayText
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
