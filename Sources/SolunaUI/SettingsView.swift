import SwiftUI
import LunarCore

/// 弹窗内的设置与录入面板（一期：宜忌开关 / 农历生日录入 / 登录自启）
public struct SettingsView: View {
    @ObservedObject public var store: BirthdayStore
    @AppStorage("yijiEnabled") private var yijiEnabled = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var newName = ""
    @State private var newMonth = 1
    @State private var newDay = 1

    public init(store: BirthdayStore) { self.store = store }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置").font(.headline)

            Toggle("显示宜忌（黄历）", isOn: $yijiEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("登录后自动启动", isOn: $launchAtLogin)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: launchAtLogin) { LaunchAtLogin.enabled = $1 }

            Divider()

            Text("农历生日 / 纪念日").font(.subheadline).fontWeight(.medium)
            HStack(spacing: 6) {
                TextField("名字", text: $newName)
                    .textFieldStyle(.roundedBorder).frame(width: 90)
                Picker("月", selection: $newMonth) {
                    ForEach(1...12, id: \.self) { Text(LunarDate.monthName($0) + "月").tag($0) }
                }.labelsHidden().frame(width: 76)
                Picker("日", selection: $newDay) {
                    ForEach(1...30, id: \.self) { Text(LunarDate.dayName($0)).tag($0) }
                }.labelsHidden().frame(width: 76)
                Button("添加") {
                    guard !newName.isEmpty else { return }
                    store.add(.init(name: newName, lunarMonth: newMonth, lunarDay: newDay))
                    newName = ""
                }.disabled(newName.isEmpty)
            }

            if !store.entries.isEmpty {
                ForEach(store.entries) { e in
                    HStack {
                        Text(e.name)
                        Spacer()
                        Text("农历\(LunarDate.monthName(e.lunarMonth))月\(LunarDate.dayName(e.lunarDay))")
                            .foregroundStyle(.secondary).font(.caption)
                        Button("删") { store.remove(e) }
                            .buttonStyle(.plain).foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
