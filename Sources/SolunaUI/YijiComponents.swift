import SwiftUI
import LunarCore

/// 宜 / 忌 的统一渲染件。
///
/// 这个元素有三处要显示：详情卡、未选中日期时的底部、以及展开面板。
/// 三处各写一遍的结果是——改了一处，另外两处还是旧样子。
/// 所以把「色标」和「两行摘要」抽成公共件，三处共用一份。
public struct YijiLabelChip: View {
    let text: String
    let tint: Color
    var fontSize: CGFloat

    public init(_ text: String, tint: Color, fontSize: CGFloat = 9) {
        self.text = text
        self.tint = tint
        self.fontSize = fontSize
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(tint)
            .fixedSize()                       // 不能被压缩，否则「宜/忌」会被切掉
            .frame(width: fontSize + 5, height: fontSize + 4)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }
}

/// 「宜 …… / 忌 ……」两行摘要（详情卡与未选中日期时的底部共用同一个排版）
public struct YijiSummary: View {
    let yi: String
    let ji: String
    let skin: Skin
    var fontSize: CGFloat

    public init(yi: String, ji: String, skin: Skin, fontSize: CGFloat = 10) {
        self.yi = yi
        self.ji = ji
        self.skin = skin
        self.fontSize = fontSize
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line("宜", yi, skin.yijiGood)
            line("忌", ji, skin.yijiBad)
        }
    }

    private func line(_ label: String, _ items: String, _ tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            YijiLabelChip(label, tint: tint, fontSize: fontSize - 1)
            Text(items)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }
}
