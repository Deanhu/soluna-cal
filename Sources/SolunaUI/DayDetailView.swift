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

    @State private var yijiSheetOpen = false

    public init(date: Date,
                calendar: Calendar = Calendar(identifier: .gregorian),
                showYiji: Bool,
                skin: Skin = .default,
                onAddEvent: @escaping () -> Void,
                onRequestAccess: @escaping () -> Void = {}) {
        self.date = date
        self.calendar = calendar
        self.showYiji = showYiji
        self.skin = skin
        self.onAddEvent = onAddEvent
        self.onRequestAccess = onRequestAccess
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
                    .onTapGesture { yijiSheetOpen = true }
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
            }

            Divider().padding(.vertical, 1)

            if events.isEmpty {
                HStack(spacing: 6) {
                    if EventProvider.shared.authorized {
                        Text("当日无日程").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text("· 双击日期可添加").font(.system(size: 10)).foregroundStyle(.tertiary)
                    } else {
                        // 更新一次系统就会重问一次（ad-hoc 签名的 DR 就是二进制哈希），
                        // 所以这里给按钮，而不是让人自己去系统设置里找
                        Text("需要授权系统日历（更新后会重新询问）")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                            .lineLimit(1)
                        Button("授权") { onRequestAccess() }
                            .buttonStyle(.link).font(.system(size: 10))
                    }
                }
            } else {
                // 带上开始时间：同名事件从不同日历来时，时间与日历名是唯一的区分线索
                ForEach(events) { item in
                    HStack(spacing: 4) {
                        Text(item.isAllDay ? "全天" : Self.timeFormatter.string(from: item.start))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(item.title).font(.system(size: 11)).lineLimit(1)
                        if events.count > 1, item.calendarTitle != "?" {
                            Text(item.calendarTitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .sheet(isPresented: $yijiSheetOpen) {
            if let yj = Yiji.on(date: date, calendar: calendar) {
                YijiSheet(date: date, yi: yj.yi, ji: yj.ji, calendar: calendar, skin: skin)
            }
        }
    }
}
