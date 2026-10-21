import SwiftUI
import LunarCore

/// 完整宜忌（点详情卡里的宜/忌两行打开）。
///
/// 卡片本身只放得下一行，塞「宜…忌…」两段的结果是第二段被挤没；
/// 所以卡片里给摘要，完整内容放到这里。
public struct YijiSheet: View {
    let date: Date
    let yi: String
    let ji: String
    let calendar: Calendar
    let skin: Skin

    @Environment(\.dismiss) private var dismiss

    public init(date: Date, yi: String, ji: String,
                calendar: Calendar = Calendar(identifier: .gregorian),
                skin: Skin = .default) {
        self.date = date
        self.yi = yi
        self.ji = ji
        self.calendar = calendar
        self.skin = skin
    }

    private var title: String {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        let lunar = LunarCalendar.lunarDate(from: date)
        return "\(m)月\(d)日 · \(LunarDate.monthName(lunar.month))月\(LunarDate.dayName(lunar.day))"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("宜忌").font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)

            block("宜", yi, tint: skin.yijiGood)
            block("忌", ji, tint: skin.yijiBad)

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func block(_ label: String, _ items: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            YijiLabelChip(label, tint: tint, fontSize: 10)
            Text(items)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
