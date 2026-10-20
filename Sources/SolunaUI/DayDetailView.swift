import SwiftUI
import LunarCore

/// 选中日期的详情卡：把「这一天是什么日子」说全，而不是只列日程。
///
/// 之前这块只显示「当日无日程」，选了日期几乎得不到信息；现在依次给：
/// 公历 + 星期 → 农历 → 节气/节日 → 宜忌（可选）→ 当日日程。
public struct DayDetailView: View {
    let date: Date
    let calendar: Calendar
    let showYiji: Bool
    let onAddEvent: () -> Void

    public init(date: Date,
                calendar: Calendar = Calendar(identifier: .gregorian),
                showYiji: Bool,
                onAddEvent: @escaping () -> Void) {
        self.date = date
        self.calendar = calendar
        self.showYiji = showYiji
        self.onAddEvent = onAddEvent
    }

    private static let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

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

    private var events: [String] { EventProvider.shared.events(on: date) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                let m = calendar.component(.month, from: date)
                let d = calendar.component(.day, from: date)
                Text("\(m)月\(d)日 \(weekday)")
                    .font(.system(size: 11, weight: .medium))
                if let f = festivalText {
                    Text(f)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adaptive(light: 0xD43030, dark: 0xFF6961))
                }
                if let term = termText {
                    Text(term)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adaptive(light: 0xB8860B, dark: 0xE3B341))
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
                Text("宜 \(yj.yi)　忌 \(yj.ji)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider().padding(.vertical, 1)

            if events.isEmpty {
                HStack(spacing: 4) {
                    Text(EventProvider.shared.authorized ? "当日无日程" : "授权系统日历后显示日程")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    if EventProvider.shared.authorized {
                        Text("· 双击日期可添加")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
            } else {
                ForEach(events, id: \.self) { title in
                    Text("· " + title).font(.system(size: 11)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}
