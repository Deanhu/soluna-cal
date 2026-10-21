import SwiftUI

/// 皮肤系统（二期 V2-3）：皮肤 = 纯 token 包，不改布局、不动密度。
/// 一期颜色已全部 token 化，这里只是给每档 token 提供第二组取值。
public enum Skin: String, CaseIterable, Identifiable {
    case `default`, springFestival

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .default: return "默认"
        case .springFestival: return "春节限定"
        }
    }

    // MARK: token 覆盖（浅色 / 深色）

    var badgeOff: Color {          // 「休」角标底色
        switch self {
        case .default: return Color(hex: 0xFF3B30)
        case .springFestival: return Color(hex: 0x9E2B22)   // 朱砂
        }
    }
    var badgeWork: Color { Color(hex: 0x6E6E73) }          // 「班」两皮肤同灰

    var bandOff: Color {
        switch self {
        case .default: return .adaptive(light: 0xFDECEA, dark: 0x4E2A28)
        case .springFestival: return .adaptive(light: 0xF6E3DC, dark: 0x3D2620)
        }
    }
    var bandWork: Color { Color.adaptive(light: 0xF0F0F2, dark: 0x2E2E30) }

    var festivalText: Color {      // 节日红字
        switch self {
        case .default: return .adaptive(light: 0xD43030, dark: 0xFF6961)
        case .springFestival: return .adaptive(light: 0x9E2B22, dark: 0xE88A7D)
        }
    }
    var holidayNumber: Color {     // 假日公历数字
        switch self {
        case .default: return .adaptive(light: 0xFF3B30, dark: 0xFF6961)
        case .springFestival: return .adaptive(light: 0x9E2B22, dark: 0xE88A7D)
        }
    }
    var termText: Color { .adaptive(light: 0xB8860B, dark: 0xE3B341) }

    /// 生日文案（玫红）：与节日红、节气金都拉开，避免「看不出这是生日」
    var birthdayText: Color { .adaptive(light: 0xE0235C, dark: 0xFF7AAF) }

    /// 宜（可做）：绿；忌（避开）：赭红。
    /// 与节日红刻意拉开——节日红是「这一天是节日」的事实标记，
    /// 忌的红是「不建议做」的判断，同色会混淆。
    var yijiGood: Color {
        switch self {
        case .default: return .adaptive(light: 0x2F7D4A, dark: 0x6ECF93)
        case .springFestival: return .adaptive(light: 0x2E5D4B, dark: 0x7FCBA5)
        }
    }
    var yijiBad: Color {
        switch self {
        case .default: return .adaptive(light: 0xB5442E, dark: 0xE58E78)
        case .springFestival: return .adaptive(light: 0x9E2B22, dark: 0xE88A7D)
        }
    }

    var todayFill: Color {         // 今日实心（春节皮肤换朱砂，蓝色让给系统）
        switch self {
        case .default: return Color.accentColor
        case .springFestival: return Color(hex: 0x9E2B22)
        }
    }

    var countdownAccent: Color {   // 倒计时数字
        switch self {
        case .default: return .adaptive(light: 0xD43030, dark: 0xFF6961)
        case .springFestival: return .adaptive(light: 0x9E2B22, dark: 0xE88A7D)
        }
    }
}

public extension UserDefaults {
    var currentSkin: Skin {
        Skin(rawValue: string(forKey: "skin") ?? "") ?? .default
    }
}
