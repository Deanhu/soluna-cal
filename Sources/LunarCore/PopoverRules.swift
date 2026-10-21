import Foundation

/// 弹窗的月份切换规则。
///
/// 这两条规则原来写在 SwiftUI 视图的私有方法里，只能靠手点验证，改坏了也测不出来
/// （朋友 B 报的「翻了月底部还显示上个月那天」「距元旦还有 72 天指代不清」都是这类）。
/// 抽到 LunarCore 后可以被单元测试直接覆盖边界：跨年、同月不同日、无选中。
public enum PopoverMonthRule {

    /// 翻到别的月份后，选中日如果已经不在新月份里，就该清掉。
    ///
    /// 不清的后果：底部详情卡一直显示上个月那一天，而网格里根本找不到那一天，
    /// 用户看到的是一个对不上的状态（B 的截图：标题是 11 月，底部写着「10月18日」）。
    public static func shouldClearSelection(
        selected: Date?,
        displayed: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard let selected else { return false }
        return !calendar.isDate(selected, equalTo: displayed, toGranularity: .month)
    }

    /// 倒计时条上目标节日的写法：同年只写节日名，跨年补上年份。
    ///
    /// 只写「距 元旦 还有 72 天」时，如果用户正翻到 2027 年 1 月、屏幕上就摆着元旦，
    /// 分不清指的是哪个元旦（B 标了「容易有歧義」）。
    public static func countdownLabel(name: String, targetYear: Int, todayYear: Int) -> String {
        targetYear == todayYear ? name : "\(targetYear) 年\(name)"
    }

    /// 「回到今天」之后应有的状态：月份翻到今天，**选中日也必须落到今天**。
    ///
    /// 只翻月是不够的：如果当前就停在这个月，`displayed` 赋同一个月的值等于没变，
    /// 而选中日因为「同月内不清理」被保留 —— 点下去界面一动不动。
    /// （2026-10-21 Dean 在 10 月里选中 22 号后点「回到今天」，什么都没发生。）
    public static func backToTodayState(now: Date) -> (displayed: Date, selected: Date) {
        (now, now)
    }
}
