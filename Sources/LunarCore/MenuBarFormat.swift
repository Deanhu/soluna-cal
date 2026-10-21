import Foundation

/// 菜单栏格式 token 拼装引擎（二期 V2-1）
/// token：{Y}年 {M}月 {D}日 {W}周几 {LM}农历月 {LD}农历日 {GY}年干支 {SX}生肖
/// {GD}日干支 {SH}时辰 {SG}时干支（{SH}/{SG} 随系统时间每小时变化）
/// 非法 token 原样保留（不崩不空白）；空模板回退默认。
public enum MenuBarFormat {
    public static let defaultTemplate = "{M}月{D}日 周{W}"

    /// 预设 3 档（PRD 验收）
    public static let presets: [(label: String, template: String)] = [
        ("简洁", "{M}月{D}日 周{W}"),
        ("带农历", "{M}月{D}日 周{W} · {LM}{LD}"),
        ("农历优先", "{LM}{LD} · {GY}年"),
    ]

    /// 渲染模板。农历超出数据范围时农历类 token 渲染为空串，并清掉「 · 」分隔符残骸
    public static func render(template: String, date: Date) -> String {
        let tpl = template.isEmpty ? defaultTemplate : template
        let cal = Calendar(identifier: .gregorian)
        let weekday = ["?", "日", "一", "二", "三", "四", "五", "六"][cal.component(.weekday, from: date)]
        let lunar = LunarCalendar.lunarDateOrNil(from: date)

        var result = ""
        var i = tpl.startIndex
        while i < tpl.endIndex {
            if tpl[i] == "{", let close = tpl[i...].firstIndex(of: "}") {
                let token = String(tpl[tpl.index(after: i)..<close])
                if let value = tokenValue(token, date: date, cal: cal, weekday: weekday, lunar: lunar) {
                    result += value
                } else {
                    result += "{\(token)}"   // 未知 token：原样保留
                }
                i = tpl.index(after: close)
            } else {
                result.append(tpl[i])
                i = tpl.index(after: i)
            }
        }
        // 农历超范围：清掉「只为包裹农历而存在」的分隔符
        if lunar == nil {
            result = result.replacingOccurrences(of: " · ", with: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func tokenValue(_ token: String, date: Date, cal: Calendar,
                                   weekday: String, lunar: LunarDate?) -> String? {
        switch token {
        case "Y": return "\(cal.component(.year, from: date))"
        case "M": return "\(cal.component(.month, from: date))"
        case "D": return "\(cal.component(.day, from: date))"
        case "W": return weekday
        case "LM":
            guard let l = lunar else { return "" }
            return (l.isLeapMonth ? "闰" : "") + LunarDate.monthName(l.month) + "月"
        case "LD":
            guard let l = lunar else { return "" }
            return LunarDate.dayName(l.day)
        case "GY":
            guard let l = lunar else { return "" }
            return Ganzhi.year(l.year)
        case "SX":
            guard let l = lunar else { return "" }
            return Ganzhi.animal(l.year)
        case "GD": return Ganzhi.day(date)   // 日干支（锚点法，不依赖农历表范围）
        case "SH": return Shichen.of(date: date).name     // 时辰（如「午时」）
        case "SG": return Shichen.of(date: date).ganzhi   // 时干支（如「丙午」）
        default: return nil
        }
    }

    /// 菜单栏宽度估算（pt）：经菜单栏真实字体校准（CJK≈12，ASCII≈7，
    /// 实测「10月15日 周四 · 九月初六」= 154.5pt）。
    /// 刘海屏实测教训：超长状态项会被系统静默隐藏，编辑器用它做长度预警。
    public static func estimatedWidth(_ text: String) -> Double {
        text.reduce(0) { $0 + ($1.isASCII ? 7 : 12) }
    }

    /// 预警线：三档官方预设实测均 ≤155pt，预警线留到 180；
    /// 超过则提示刘海机型菜单栏可能显示不全
    public static let widthWarningThreshold: Double = 180
}

public extension Notification.Name {
    /// 菜单栏标题相关偏好变更（设置页切换格式/农历开关时发出，App 主入口监听并即时刷新）
    static let menuBarTitleNeedsUpdate = Notification.Name("menuBarTitleNeedsUpdate")

    /// 菜单栏形态变更（纯文字 / 图标+文字 / 纯图标）。
    /// 形态决定状态项宽度与有没有图标，必须重建，不能只改标题。
    static let menuBarStyleNeedsUpdate = Notification.Name("menuBarStyleNeedsUpdate")
    /// 弹窗密度变了：弹窗尺寸是按密度固定的，需要重算一次
    static let popoverDensityNeedsUpdate = Notification.Name("popoverDensityNeedsUpdate")
}
