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
    let onClose: (() -> Void)?

    @State private var title = ""
    @State private var error: String?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    public init(date: Date,
                calendar: Calendar = Calendar(identifier: .gregorian),
                onSaved: @escaping () -> Void,
                onClose: (() -> Void)? = nil) {
        self.date = date
        self.calendar = calendar
        self.onSaved = onSaved
        self.onClose = onClose
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

            Text(hintText)
                .font(.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消") { if let onClose { onClose() } else { dismiss() } }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { focused = true }
    }

    /// 写去哪，取决于能不能写系统日历。文案必须说实话：
    /// 本机那条既不进系统「日历」，也不会有提醒，不能让用户以为一样。
    private var hintText: String {
        EventProvider.shared.canWriteToSystem
            ? "写入系统「日历」的默认日历：当天 9:00–10:00，开始前 10 分钟提醒。"
            : "没拿到系统日历权限，只保存在本机：当天 9:00，不会出现在系统「日历」里，也不会提醒。"
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try EventProvider.shared.addEvent(title: trimmed, on: date)
            onSaved()
            if let onClose { onClose() } else { dismiss() }
        } catch {
            self.error = "写入失败：\(error.localizedDescription)"
        }
    }
}
