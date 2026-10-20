import SwiftUI
import LunarCore

/// 创建日程的编辑面板（双击日期或点详情卡里的「＋ 日程」打开）。
///
/// 之前是网格下方一条很窄的行内编辑条，容易看不见；改成独立面板后，
/// 输入框、日期、保存按钮都在同一处，不会和日历挤在一起。
public struct EventEditorView: View {
    let date: Date
    let calendar: Calendar
    let onSaved: () -> Void

    @State private var title = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(date: Date,
                calendar: Calendar = Calendar(identifier: .gregorian),
                onSaved: @escaping () -> Void) {
        self.date = date
        self.calendar = calendar
        self.onSaved = onSaved
        _ = calendar
    }

    private var dateTitle: String {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        let lunar = LunarCalendar.lunarDate(from: date)
        return "\(m)月\(d)日 · \(LunarDate.monthName(lunar.month))月\(LunarDate.dayName(lunar.day))"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新建日程").font(.headline)
            Text(dateTitle).font(.caption).foregroundStyle(.secondary)

            TextField("日程名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { save() }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Text("写入系统「日历」的默认日历：当天 9:00–10:00，开始前 10 分钟提醒。")
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try EventProvider.shared.addEvent(title: trimmed, on: date)
            onSaved()
            dismiss()
        } catch {
            self.error = "写入失败：\(error.localizedDescription)"
        }
    }
}
