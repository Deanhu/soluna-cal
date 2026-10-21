import SwiftUI
import LunarCore

/// 年视图（列表形态）。
///
/// 为什么是列表不是 12 宫格：弹窗宽度只有 300–336pt，12 个月塞进去
/// 每天格子约 14pt、字号得压到 5–6pt，读不了。列表在同样宽度下可读，
/// 而且直接回答「今年还有哪些假、谁的生日快到了」。
public struct YearOverviewView: View {
    let year: Int
    let digest: [Int: [YearDigest.Item]]
    let skin: Skin
    let onPick: (Int) -> Void
    let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    public init(year: Int,
                digest: [Int: [YearDigest.Item]],
                skin: Skin = .default,
                onPick: @escaping (Int) -> Void,
                onClose: (() -> Void)? = nil) {
        self.year = year
        self.digest = digest
        self.skin = skin
        self.onPick = onPick
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(String(year)) 年").font(.headline)
                Spacer()
                Text("点某个月跳过去").font(.caption).foregroundStyle(.secondary)
                Button("关闭") { dismiss() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1...12, id: \.self) { month in
                        monthBlock(month)
                        if month < 12 { Divider().padding(.leading, 44) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 372, height: 470)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func monthBlock(_ month: Int) -> some View {
        let items = digest[month] ?? []
        HStack(alignment: .top, spacing: 8) {
            Text("\(month) 月")
                .font(.system(size: 12, weight: items.isEmpty ? .regular : .semibold))
                .foregroundStyle(items.isEmpty ? Color.secondary : Color.primary)
                .frame(width: 36, alignment: .trailing)
                .padding(.top, 1)

            if items.isEmpty {
                Text("—").font(.system(size: 12)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        HStack(spacing: 6) {
                            Text(item.dayRangeText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 62, alignment: .trailing)
                            Text(item.text)
                                .font(.system(size: 12))
                                .foregroundStyle(color(item.kind))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onPick(month)
            dismiss()
        }
    }

    private func color(_ kind: YearDigest.Kind) -> Color {
        switch kind {
        case .off:      return skin.holidayNumber
        case .work:     return .secondary
        case .festival: return skin.festivalText
        case .term:     return skin.termText
        case .birthday: return skin.birthdayText
        }
    }
}
