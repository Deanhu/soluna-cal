import SwiftUI
import AppKit
import LunarCore

/// 弹窗内的设置与录入面板（一期：宜忌开关 / 农历生日录入 / 登录自启）
public struct SettingsView: View {
    @ObservedObject public var store: BirthdayStore
    @AppStorage("yijiEnabled") private var yijiEnabled = false
    @AppStorage("countdownEnabled") private var countdownEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("popoverDensity") private var popoverDensity = PopoverDensity.standard.rawValue
    @AppStorage("menuBarLunar") private var menuBarLunar = false
    @AppStorage("menuBarTemplate") private var menuBarTemplate: String?
    @State private var customTemplate = ""
    @AppStorage("skin") private var skinRaw = Skin.default.rawValue
    @AppStorage("ganzhiEnabled") private var ganzhiEnabled = false
    @AppStorage("hoverEnabled") private var hoverEnabled = false
    @AppStorage("hoverDelay") private var hoverDelay = 0.4
    @AppStorage("notify.holidayEve") private var notifyHolidayEve = false
    @AppStorage("notify.festival") private var notifyFestival = false
    @AppStorage("notify.birthday") private var notifyBirthday = false
    @AppStorage("notify.dndEnabled") private var dndEnabled = false
    @AppStorage("notify.dndStart") private var dndStartMin = 22 * 60
    @AppStorage("notify.dndEnd") private var dndEndMin = 7 * 60
    @State private var recordingHotKey = false
    @State private var keyMonitor: Any?
    @State private var newName = ""
    @State private var newMonth = 1
    @State private var newDay = 1
    @State private var newKind: BirthdayStore.Entry.CalendarKind = .lunar
    @State private var newCycle: BirthdayStore.Entry.Cycle = .yearly
    @Environment(\.dismiss) private var dismiss

    public init(store: BirthdayStore) { self.store = store }

    public var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("设置").font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            Toggle("显示宜忌（黄历）", isOn: $yijiEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("显示放假倒计时", isOn: $countdownEnabled)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("登录后自动启动", isOn: $launchAtLogin)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: launchAtLogin) { LaunchAtLogin.enabled = launchAtLogin }

            Toggle("菜单栏显示农历", isOn: $menuBarLunar)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: menuBarLunar) {
                    // 开关是快捷路径：动了开关就清掉自定义模板（最后一次操作生效）
                    UserDefaults.standard.removeObject(forKey: "menuBarTemplate")
                    NotificationCenter.default.post(name: .menuBarTitleNeedsUpdate, object: nil)
                }

            // 菜单栏格式（二期 token 拼装）：预设 3 档 + 自定义
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("菜单栏格式").font(.callout)
                    Spacer()
                    Picker("菜单栏格式", selection: formatChoice) {
                        Text("简洁").tag(0)
                        Text("带农历").tag(1)
                        Text("农历优先").tag(2)
                        Text("自定义").tag(3)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                }
                if formatChoice.wrappedValue == 3 {
                    TextField("如 {M}月{D}日 周{W} · {LM}{LD}", text: $customTemplate)
                        .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                        .onChange(of: customTemplate) {
                            menuBarTemplate = customTemplate
                            NotificationCenter.default.post(name: .menuBarTitleNeedsUpdate, object: nil)
                        }
                    Text("预览：" + MenuBarFormat.render(template: customTemplate, date: Date()))
                        .font(.caption)
                    Text("可用：{Y}年 {M}月 {D}日 {W}周 {LM}农历月 {LD}农历日 {GY}年干支 {SX}生肖 {GD}日干支")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if MenuBarFormat.estimatedWidth(
                        MenuBarFormat.render(template: customTemplate, date: Date()))
                        > MenuBarFormat.widthWarningThreshold {
                        Text("偏长：刘海屏 Mac 的菜单栏可能显示不全")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }

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

            HStack {
                Text("皮肤").font(.callout)
                Spacer()
                Picker("皮肤", selection: $skinRaw) {
                    ForEach(Skin.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 180)
            }

            Toggle("显示干支时辰（真太阳时）", isOn: $ganzhiEnabled)
                .toggleStyle(.switch).controlSize(.small)
                .onChange(of: ganzhiEnabled) {
                    if ganzhiEnabled { LocationProvider.shared.locate() }
                }

            // 快捷键 + 悬停（二期 V2-4）
            HStack {
                Text("呼出快捷键").font(.callout)
                Spacer()
                Button(recordingHotKey ? "按下新快捷键…" : HotKeyManager.saved.display) {
                    recordingHotKey.toggle()
                }
                .font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Toggle("悬停弹出", isOn: $hoverEnabled)
                    .toggleStyle(.switch).controlSize(.small)
                if hoverEnabled {
                    Slider(value: $hoverDelay, in: 0.2...1.5, step: 0.1)
                        .frame(width: 110)
                    Text(String(format: "%.1fs", hoverDelay))
                        .font(.caption).foregroundStyle(.secondary).frame(width: 34)
                }
            }

            // 通知（二期 V2-2）
            Divider()
            Text("通知").font(.subheadline).fontWeight(.medium)
            Toggle("放假前一日提醒（18:00）", isOn: $notifyHolidayEve)
                .toggleStyle(.switch).controlSize(.small).onChange(of: notifyHolidayEve) { reschedule() }
            Toggle("节日当天提醒（09:00）", isOn: $notifyFestival)
                .toggleStyle(.switch).controlSize(.small).onChange(of: notifyFestival) { reschedule() }
            Toggle("生日/纪念日提醒（09:00）", isOn: $notifyBirthday)
                .toggleStyle(.switch).controlSize(.small).onChange(of: notifyBirthday) { reschedule() }
            HStack {
                Toggle("免打扰时段", isOn: $dndEnabled)
                    .toggleStyle(.switch).controlSize(.small).onChange(of: dndEnabled) { reschedule() }
                if dndEnabled {
                    DatePicker("", selection: dndStart, displayedComponents: .hourAndMinute)
                        .labelsHidden().frame(width: 64)
                    Text("至").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: dndEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden().frame(width: 64)
                }
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
                        reschedule()   // 生日提醒纳入新条目
                    }.disabled(newName.isEmpty)
                }
            }

            if !store.entries.isEmpty {
                ForEach(sortedEntries, id: \.entry.id) { item in
                    HStack {
                        Text(item.entry.name)
                        Spacer()
                        Text(describe(item.entry))
                            .foregroundStyle(.secondary).font(.caption)
                        Text(countdownText(item.days))
                            .font(.caption)
                            .foregroundStyle(item.days <= 7
                                ? Color.adaptive(light: 0xD43030, dark: 0xFF6961)
                                : Color.secondary)
                        Button("删") { store.remove(item.entry); reschedule() }
                            .buttonStyle(.plain).foregroundStyle(.red).font(.caption)
                    }
                }
            }
        }
            .padding(12)
            .frame(width: 360)
        }
        .frame(width: 360)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            if customTemplate.isEmpty {
                customTemplate = menuBarTemplate ?? MenuBarFormat.presets[1].template
            }
        }
        .onChange(of: recordingHotKey) {
            if recordingHotKey {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
                    guard let combo = HotKeyManager.combo(from: ev) else { return ev }
                    HotKeyManager.saved = combo
                    if !HotKeyManager.shared.register(combo) {
                        NSLog("[SolunaCal] 快捷键注册失败（可能被占用）: %@", combo.display)
                    }
                    recordingHotKey = false
                    return nil   // 吞掉这次按键
                }
            } else if let m = keyMonitor {
                NSEvent.removeMonitor(m)
                keyMonitor = nil
            }
        }
    }

    private func describe(_ e: BirthdayStore.Entry) -> String {
        let md = e.calendar == .lunar
            ? "农历\(LunarDate.monthName(e.lunarMonth))月\(LunarDate.dayName(e.lunarDay))"
            : "公历\(e.lunarMonth)月\(e.lunarDay)日"
        return e.cycle == .yearly ? md : "每月" + (e.calendar == .lunar ? LunarDate.dayName(e.lunarDay) : "\(e.lunarDay)日")
    }

    /// 生日看板：按下次出现从近到远排序（nextOccurrence 为空的排最后）
    private var sortedEntries: [(entry: BirthdayStore.Entry, days: Int)] {
        store.entries
            .map { ($0, store.nextOccurrence(of: $0)?.days ?? .max) }
            .sorted { $0.1 < $1.1 }
    }

    private func countdownText(_ days: Int) -> String {
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case .max: return ""
        default: return "\(days) 天后"
        }
    }

    /// 菜单栏格式选择：0-2 = 预设（清掉自定义模板并同步农历开关），3 = 自定义
    private var formatChoice: Binding<Int> {
        Binding(
            get: {
                if let t = menuBarTemplate {
                    return MenuBarFormat.presets.firstIndex { $0.template == t } ?? 3
                }
                return menuBarLunar ? 1 : 0
            },
            set: { choice in
                if choice == 3 {
                    if customTemplate.isEmpty {
                        customTemplate = menuBarTemplate ?? MenuBarFormat.presets[1].template
                    }
                    menuBarTemplate = customTemplate
                } else {
                    // 预设直接落模板（不走 menuBarLunar 遗留开关），
                    // 否则「农历优先」(choice 2) 会写成 template=nil+lunar=false → 实际渲染成简洁
                    menuBarTemplate = MenuBarFormat.presets[choice].template
                    menuBarLunar = (choice >= 1)
                }
                NotificationCenter.default.post(name: .menuBarTitleNeedsUpdate, object: nil)
            }
        )
    }

    // MARK: 二期联动

    private func reschedule() { NotificationManager.reschedule(store: store) }

    /// 免打扰「分钟制 ↔ Date」转换绑定
    private func minuteBinding(_ keyPath: ReferenceWritableKeyPath<SettingsView, Int>) -> Binding<Date> {
        Binding(
            get: {
                let mins = self[keyPath: keyPath]
                return Calendar(identifier: .gregorian).date(
                    bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar(identifier: .gregorian)
                self[keyPath: keyPath] = c.component(.hour, from: d) * 60 + c.component(.minute, from: d)
                reschedule()
            }
        )
    }
    private var dndStart: Binding<Date> { minuteBinding(\.dndStartMin) }
    private var dndEnd: Binding<Date> { minuteBinding(\.dndEndMin) }
}
