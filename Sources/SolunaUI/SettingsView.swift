import SwiftUI
import AppKit
import UserNotifications
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
    /// 菜单栏形态：0=仅文字 1=图标+文字 2=仅图标。
    /// 与 AppDelegate.statusStyle 读取同一个键，默认 1。
    @AppStorage("statusItemStyle") private var statusItemStyle = 1
    @State private var customTemplate = ""
    @State private var showImport = false
    @State private var notifyAuth: UNAuthorizationStatus = .notDetermined
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

    /// 页脚展示的版本号
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

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

            // 菜单栏形态：决定显示「图标 + 文字 / 只有图标 / 只有文字」。
            // 刘海屏 Mac 上菜单栏放不下时，系统会把项藏到刘海后面（看不见也没提示），
            // 切成「仅图标」宽度从约 120pt 降到约 22pt，基本都能挤回来。
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("菜单栏形态").font(.callout)
                    Spacer()
                    Picker("菜单栏形态", selection: $statusItemStyle) {
                        Text("仅文字").tag(0)
                        Text("图标 + 文字").tag(1)
                        Text("仅图标").tag(2)
                    }
                    .labelsHidden().frame(width: 132)
                    .onChange(of: statusItemStyle) {
                        NotificationCenter.default.post(name: .menuBarStyleNeedsUpdate, object: nil)
                    }
                }
                if statusItemStyle != 2 {
                    Text("右上角看不到它时，切「仅图标」更容易露出来")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                    Text("可用：{Y}年 {M}月 {D}日 {W}周 {LM}农历月 {LD}农历日 {GY}年干支 {SX}生肖 {GD}日干支 {SH}时辰 {SG}时干支")
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
            HStack(spacing: 6) {
                Text("通知").font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(authText)
                    .font(.caption)
                    .foregroundStyle(authColor)
                if notifyAuth == .denied {
                    Button("去系统设置") { openNotificationSettings() }
                        .buttonStyle(.link).font(.caption)
                }
            }
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

            Text(nextReminderText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("生日 / 纪念日").font(.subheadline).fontWeight(.medium)
                Spacer()
                Button("批量添加") { showImport = true }
                    .buttonStyle(.link).font(.caption)
            }
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

            Divider().padding(.top, 6)

            // 退出入口：菜单栏配件 App 没有 Dock 图标、也没有应用菜单，
            // 不在这里给一个按钮，用户就只能去「活动监视器」杀进程，
            // 也就没法把 App 拖进废纸篓（系统拒删运行中的 App）。
            HStack(spacing: 8) {
                Text("SolunaCal \(Self.versionText)")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出 SolunaCal") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
            .padding(.top, 2)
        }
            .padding(12)
            .frame(width: 360)
        }
        .frame(width: 360)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showImport) {
            BirthdayImportView { rows in
                for r in rows {
                    store.add(.init(name: r.name,
                                     lunarMonth: r.month,
                                     lunarDay: r.day,
                                     isLeapMonth: r.isLeapMonth,
                                     calendar: r.isLunar ? .lunar : .solar))
                }
                reschedule()   // 新条目纳入提醒
            }
        }
        .task { await loadNotificationAuth() }
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

    // MARK: 通知状态

    /// 读系统通知权限。没有 bundle 时（离屏渲染）直接跳过——
    /// UNUserNotificationCenter.current() 在无 bundle 进程里会抛 ObjC 异常。
    private func loadNotificationAuth() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifyAuth = settings.authorizationStatus
    }

    private var authText: String {
        switch notifyAuth {
        case .authorized, .provisional: return "已允许"
        case .denied:                   return "已拒绝"
        case .notDetermined:            return "尚未询问"
        @unknown default:               return "未知"
        }
    }

    private var authColor: Color {
        switch notifyAuth {
        case .authorized, .provisional: return .secondary
        case .denied:                   return .red
        default:                        return .secondary
        }
    }

    private func openNotificationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let url { NSWorkspace.shared.open(url) }
    }

    /// 让「提醒到底排上没有」可见：算一遍未来 60 天的计划，取最近一条
    private var nextReminderText: String {
        let plans = NotificationPlanner.plan(now: Date(),
                                             prefs: NotificationManager.prefs,
                                             store: store)
        if let p = plans.first {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEEE HH:mm"
            return "下次提醒：\(f.string(from: p.fireDate)) · \(p.title)"
        }
        let anyOn = notifyHolidayEve || notifyFestival || notifyBirthday
        return anyOn ? "未来 60 天没有可提醒的日子" : "提醒全部关闭，不会收到通知"
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
