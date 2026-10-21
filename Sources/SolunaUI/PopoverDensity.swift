import SwiftUI

/// 弹窗密度：整套联动 token，不是单点缩放。
/// 滑杆式自由缩放会让色带圆角 / 角标带高 / 今日圆互相失调，
/// 所以只提供三档精心配平的组合。
public enum PopoverDensity: String, CaseIterable, Identifiable {
    case compact, standard, comfortable

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .compact:     return "紧凑"
        case .standard:    return "标准"
        case .comfortable: return "宽松"
        }
    }

    /// 一档密度 = 一整套互相配平的尺寸
    public struct Tokens {
        public let popoverWidth: CGFloat   // 弹窗总宽（格宽 = (宽-12)/7）
        public let popoverHeight: CGFloat  // 弹窗固定高：尺寸不随内容变，超出部分内部滚动
        public let numberFont: CGFloat     // 公历数字
        public let lunarFont: CGFloat      // 农历小字
        public let badgeFont: CGFloat      // 休/班角标
        public let badgeStripHeight: CGFloat // 角标带占位高
        public let todayCircle: CGFloat    // 今日实心圆直径
        public let eventDot: CGFloat       // 事件点直径
        public let rowSpacing: CGFloat     // 月历行距
        public let footerFont: CGFloat     // 底部倒计时
    }

    public var tokens: Tokens {
        switch self {
        case .compact:
            return Tokens(popoverWidth: 264, popoverHeight: 430, numberFont: 12, lunarFont: 9,
                          badgeFont: 8, badgeStripHeight: 16, todayCircle: 20,
                          eventDot: 4, rowSpacing: 1, footerFont: 10)
        case .standard:
            return Tokens(popoverWidth: 300, popoverHeight: 470, numberFont: 13, lunarFont: 10,
                          badgeFont: 9, badgeStripHeight: 18, todayCircle: 22,
                          eventDot: 5, rowSpacing: 2, footerFont: 11)
        case .comfortable:
            return Tokens(popoverWidth: 336, popoverHeight: 510, numberFont: 14, lunarFont: 11,
                          badgeFont: 10, badgeStripHeight: 20, todayCircle: 24,
                          eventDot: 5, rowSpacing: 3, footerFont: 12)
        }
    }
}

public extension UserDefaults {
    /// 当前弹窗密度（未设置 = 标准）
    var popoverDensity: PopoverDensity {
        PopoverDensity(rawValue: string(forKey: "popoverDensity") ?? "") ?? .standard
    }
}
