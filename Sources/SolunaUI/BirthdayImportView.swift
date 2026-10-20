import SwiftUI
import LunarCore

/// 生日批量导入面板：粘贴多行 → 实时预览 → 确认写入。
///
/// 为什么用粘贴而不是文件选择：生日存在 App 自己的偏好里，用户手上多数没有
/// 现成 CSV；让人先整理成文件是多余一步。粘贴几行最快，也最容易核对。
public struct BirthdayImportView: View {
    let onCommit: ([BirthdayImport.Row]) -> Void

    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    public init(initialText: String = "",
                onCommit: @escaping ([BirthdayImport.Row]) -> Void) {
        _text = State(initialValue: initialText)
        self.onCommit = onCommit
    }

    private var parsed: BirthdayImport.Result { BirthdayImport.parse(text) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批量添加生日").font(.headline)
            Text("每行一个：名字 月-日 [农历/公历]。历法不写按农历算；闰月写「闰6-05」。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 132)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                )

            // 实时结果：能导入几条、哪几行有问题，都在这里说清楚
            let result = parsed
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("示例：妈妈 9-19 农历 ／ 小王 10-20 公历")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                if !result.rows.isEmpty {
                    Text("可导入 \(result.rows.count) 条：" +
                         result.rows.prefix(3).map { "\($0.name) \($0.month)-\($0.day)" }
                            .joined(separator: "、") +
                         (result.rows.count > 3 ? " …" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                ForEach(result.failures.prefix(4), id: \.line) { f in
                    Text("第 \(f.line) 行：\(f.reason)")
                        .font(.caption).foregroundStyle(.red)
                }
                if result.failures.count > 4 {
                    Text("…另有 \(result.failures.count - 4) 行有问题")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("导入 \(parsed.rows.count) 条") {
                    onCommit(parsed.rows)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsed.rows.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 400)
    }
}
