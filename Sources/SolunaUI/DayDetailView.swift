import SwiftUI
import LunarCore

/// 选中日期的详情卡：把「这一天是什么日子」说全，而不是只列日程。
///
/// 依次给：公历 + 星期 → 农历 → 宜忌（可选）→ 当日日程。
/// 宜忌只放两行摘要，完整内容点开 `YijiSheet`——三处渲染共用 `YijiSummary` / `YijiLabelChip`。
public struct DayDetailView: View {
    let date: Date
    let calendar: Calendar
    let showYiji: Bool
    let skin: Skin
    let onAddEvent: () -> Void
    let onRequestAccess: () -> Void
    /// 点过「授权」但没拿到权限：换成一句能照做的指引，别再给同一个按钮
    let accessDenied: Bool
    /// 打开完整宜忌（作为独立窗口）。sheet 挂在 NSPopover 上会变幽灵窗口，不能用
    let onOpenYiji: ((Date) -> Void)?

    /// 正在二次确认的那一条（存 id 不存整条：事件删掉后对象就过期了）。
    /// 弹窗里不能开 sheet / alert（会变幽灵窗口），所以确认界面直接替换那一行本身。
    @State private var pendingDeleteID: String?
    /// 鼠标停在哪条上：删除按钮默认低对比，悬停才变红，避免一行里全是红叉
    @State private var hoveredID: String?
    /// 删除失败的原因，就地显示 —— 不做静默失败
    @State private var deleteError: String?

    public init(date: Date,
                calendar: Calendar = Calendar(identifier: .gregorian),
                showYiji: Bool,
                skin: Skin = .default,
                onAddEvent: @escaping () -> Void,
                onRequestAccess: @escaping () -> Void = {},
                accessDenied: Bool = false,
                onOpenYiji: ((Date) -> Void)? = nil,
                initialPendingDeleteID: String? = nil) {
        self.date = date
        self.calendar = calendar
        self.showYiji = showYiji
        self.skin = skin
        self.onAddEvent = onAddEvent
        self.onRequestAccess = onRequestAccess
        self.accessDenied = accessDenied
        self.onOpenYiji = onOpenYiji
        // 只给离屏渲染用：正常运行时由点「×」置位
        _pendingDeleteID = State(initialValue: initialPendingDeleteID)
    }

    private static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var weekday: String {
        // Calendar 的 weekday 是 1=周日…7=周六
        let idx = calendar.component(.weekday, from: date)
        return Self.weekdayNames[(idx + 5) % 7]
    }

    private var lunar: LunarDate { LunarCalendar.lunarDate(from: date) }

    private var festivalText: String? {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return Festival.solarFestival(month: m, day: d) ?? Festival.lunarFestival(of: lunar)
    }

    private var termText: String? {
        SolarTerm.on(date: date, calendar: calendar)?.description
    }

    private var events: [EventProvider.EventItem] { EventProvider.shared.events(on: date) }

    /// 执行删除。失败原因留在卡片里，不静默吞掉。
    private func confirmDelete(_ item: EventProvider.EventItem) {
        deleteError = EventProvider.shared.delete(item)
        pendingDeleteID = nil
        hoveredID = nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                let m = calendar.component(.month, from: date)
                let d = calendar.component(.day, from: date)
                Text("\(m)月\(d)日 \(weekday)")
                    .font(.system(size: 11, weight: .medium))
                if let f = festivalText {
                    Text(f).font(.system(size: 10)).foregroundStyle(skin.festivalText)
                }
                if let term = termText {
                    Text(term).font(.system(size: 10)).foregroundStyle(skin.termText)
                }
                Spacer(minLength: 0)
                Button(action: onAddEvent) {
                    Text("＋ 日程").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            // 农历全称：年份干支 + 月 + 日（闰月会带「闰」字）
            Text("\(Ganzhi.year(lunar.year))年 \(lunar.isLeapMonth ? "闰" : "")\(LunarDate.monthName(lunar.month))月\(LunarDate.dayName(lunar.day))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if showYiji, let yj = Yiji.on(date: date, calendar: calendar) {
                // 一行塞「宜…忌…」时，忌会被整段挤掉；拆成两行各自省略，
                // 至少两边都能看到开头；完整内容点开看。
                YijiSummary(yi: yj.yi, ji: yj.ji, skin: skin)
                    .padding(.trailing, 10)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenYiji?(date) }
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
            }

            Divider().padding(.vertical, 1)

            if events.isEmpty {
                HStack(spacing: 6) {
                    if EventProvider.shared.canWriteToSystem {
                        Text("当日无日程").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text("· 双击日期可添加").font(.system(size: 10)).foregroundStyle(.tertiary)
                    } else if accessDenied {
                        // 已经点过一次、没拿到权限：再给同一个按钮不会有新结果。
                        // 分两行写 —— 挤在一行会被截成「…隐私与安全性 ›…」，
                        // 用户看不到「日历」两个字，等于没告诉他去哪儿。
                        VStack(alignment: .leading, spacing: 2) {
                            Text("未授权系统日历 · 新日程只存本机")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                            Text("到「系统设置 › 隐私与安全性 › 日历」里打开")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    } else {
                        // 没授权也能记，只是存在本机。这里把差别讲清楚，
                        // 再给一个授权入口（更新一次系统就会重问一次，ad-hoc 签名的 DR 是二进制哈希）
                        Text("未授权系统日历 · 新日程只存本机")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Button("授权") { onRequestAccess() }
                            .buttonStyle(.link).font(.system(size: 10))
                    }
                }
            } else {
                // 带上开始时间：同名事件从不同日历来时，时间与日历名是唯一的区分线索
                // 限高 + 可滚动：弹窗高度是固定的，事件多了不能把布局顶破
                ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                ForEach(events) { item in
                    if pendingDeleteID == item.id {
                        // 二次确认：删日程是不可逆的，但也不能为此弹模态
                        HStack(spacing: 6) {
                            Text("删除「\(item.title)」？")
                                .font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 0)
                            Button("删除") { confirmDelete(item) }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.red)
                            Button("取消") { pendingDeleteID = nil }
                                .buttonStyle(.plain).font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Text(item.isAllDay ? "全天" : Self.timeFormatter.string(from: item.start))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(item.title).font(.system(size: 11)).lineLimit(1)
                            // 本机的始终标出来：它没进系统日历，用户得知道
                            if item.localID != nil || (events.count > 1 && item.calendarTitle != "?") {
                                Text(item.calendarTitle)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            // 删除入口。原来只藏在右键菜单里 —— 没人会去右键一行日程，
                            // 结果就是「没有删除功能」。常驻显示，但压低对比度。
                            Button {
                                deleteError = nil
                                pendingDeleteID = item.id
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .frame(width: 12, height: 12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(hoveredID == item.id ? Color.red : Color.secondary.opacity(0.5))
                            .help(item.localID != nil
                                  ? "删除这条本机日程"
                                  : "删除这条日程（系统「日历」里也会一起删掉）")
                        }
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { hoveredID = item.id }
                            else if hoveredID == item.id { hoveredID = nil }
                        }
                        .contextMenu {
                            Button(item.localID != nil ? "删除这条本机日程" : "删除这条日程",
                                   role: .destructive) {
                                deleteError = nil
                                pendingDeleteID = item.id
                            }
                        }
                    }
                }
                }
                }
                .frame(maxHeight: 72, alignment: .top)
                if let err = deleteError {
                    Text(err)
                        .font(.system(size: 9)).foregroundStyle(.red)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}
