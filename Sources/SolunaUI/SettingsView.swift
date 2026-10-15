import SwiftUI
import LunarCore

/// 弹窗内的设置与录入面板（一期：宜忌开关 / 农历生日录入 / 登录自启）
public struct SettingsView: View {
    @ObservedObject public var store: BirthdayStore
    @AppStorage("yijiEnabled") private var yijiEnabled = false
    @AppStorage("countdownEnabled") private var countdownEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("popoverDensity") private var popoverDensity = PopoverDensity.standard.rawValue
    @State private var newName = ""
    @State private var newMonth = 1
    @State private var newDay = 1
    @State private var newKind: BirthdayStore.Entry.CalendarKind = .lunar
    @State private var newCycle: BirthdayStore.Entry.Cycle = .yearly

    public init(store: BirthdayStore) { self.store = store }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置").font(.headline)

            Toggle("显示宜忌（黄历）", isOn: $yijiEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("显示放假倒计时", isOn: $countdownEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("登录后自动启动", isOn: $launchAtLogin)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: launchAtLogin) { LaunchAtLogin.enabled = launchAtLogin }

            HStack {
                Text("弹窗密度").font(.callout)
                Spacer()
                Picker("弹窗密度", selection: $popoverDensity) {
                    ForEach(PopoverDensity.allCases) { d in
                        Text(d.label).tag(d.rawValue)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 180)
            }

            Divider()

            Text("生日 / 纪念日").font(.subheadline).fontWeight(.medium)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("名字", text: $newName)
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                    Picker("历法", selection: $newKind) {
                        Text("农历").tag(BirthdayStore.Entry.CalendarKind.lunar)
                        Text("公历").tag(BirthdayStore.Entry.CalendarKind.solar)
                    }.labelsHidden().frame(width: 64)
                    Picker("重复", selection: $newCycle) {
                        Text("每年").tag(BirthdayStore.Entry.Cycle.yearly)
                        Text("每月").tag(BirthdayStore.Entry.Cycle.monthly)
                    }.labelsHidden().frame(width: 64)
                }
                HStack(spacing: 6) {
                    Picker("月", selection: $newMonth) {
                        ForEach(1...12, id: \.self) {
                            Text(newKind == .lunar ? LunarDate.monthName($0) + "月" : "\($0)月").tag($0)
                        }
                    }.labelsHidden().frame(width: 76)
                    Picker("日", selection: $newDay) {
                        ForEach(1...(newKind == .lunar ? 30 : 31), id: \.self) {
                            Text(newKind == .lunar ? LunarDate.dayName($0) : "\($0)日").tag($0)
                        }
                    }.labelsHidden().frame(width: 76)
                    Button("添加") {
                        guard !newName.isEmpty else { return }
                        store.add(.init(name: newName, lunarMonth: newMonth, lunarDay: newDay,
                                        calendar: newKind, cycle: newCycle))
                        newName = ""
                    }.disabled(newName.isEmpty)
                }
            }

            if !store.entries.isEmpty {
                ForEach(store.entries) { e in
                    HStack {
                        Text(e.name)
                        Spacer()
                        Text(describe(e))
                            .foregroundStyle(.secondary).font(.caption)
                        Button("删") { store.remove(e) }
                            .buttonStyle(.plain).foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private func describe(_ e: BirthdayStore.Entry) -> String {
        let md = e.calendar == .lunar
            ? "农历\(LunarDate.monthName(e.lunarMonth))月\(LunarDate.dayName(e.lunarDay))"
            : "公历\(e.lunarMonth)月\(e.lunarDay)日"
        return e.cycle == .yearly ? md : "每月" + (e.calendar == .lunar ? LunarDate.dayName(e.lunarDay) : "\(e.lunarDay)日")
    }
}
