import Foundation

/// 菜单栏标题拼装（纯函数，便于测试）
public enum MenuBarTitle {
    /// 默认「10月15日 周四」；showLunar 时追加「 · 九月初六」
    public static func format(_ date: Date, showLunar: Bool) -> String {
        let cal = Calendar(identifier: .gregorian)
        let weekday = ["?", "日", "一", "二", "三", "四", "五", "六"][cal.component(.weekday, from: date)]
        var title = String(format: "%d月%d日 周%@",
                           cal.component(.month, from: date),
                           cal.component(.day, from: date), weekday)
        if showLunar, let lunar = LunarCalendar.lunarDateOrNil(from: date) {
            title += " · " + (lunar.isLeapMonth ? "闰" : "")
                + LunarDate.monthName(lunar.month) + "月" + LunarDate.dayName(lunar.day)
        }
        return title
    }
}

public extension Notification.Name {
    /// 菜单栏标题相关偏好变更（设置页切换「显示农历」时发出，App 主入口监听并即时刷新）
    static let menuBarTitleNeedsUpdate = Notification.Name("menuBarTitleNeedsUpdate")
}
