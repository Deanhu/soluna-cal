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

    /// 作为独立窗口呈现时，关闭要关窗（dismiss 对普通窗口无效）
    let onClose: (() -> Void)?

    public init(store: BirthdayStore, onClose: (() -> Void)? = nil) {
        self.store = store
        self.onClose = onClose
    }

    /// 页脚展示的版本号
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var headerBar: some View {
        HStack {
            Text("设置").font(.headline)
            Spacer()
            Button(action: closeAction) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 作为窗口时关窗；作为 sheet 时 dismiss。抽出来是为了让 body 的表达式简单到能编译
    private func closeAction() {
        if let onClose { onClose() } else { dismiss() }
    }

    // MARK: 版式基准

    /// 所有「n 选 1」的控件占同一列右对齐；标签左对齐。两条竖直基准线，页面才不散。
    private let controlColumn: CGFloat = 200
    private var labelFont: Font { .system(size: 12) }
    private var sectionFont: Font { .system(size: 11, weight: .semibold) }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    displaySection
                    menuBarSection
                    interactionSection
                    notifySection
                    birthdaySection
                    Divider().padding(.top, 14)

                    // 退出入口：菜单栏配件 App 没有 Dock 图标、也没有应用菜单，
                    // 不在这里给一个按钮，用户就只能去「活动监视器」杀进程，
                    // 也就没法把 App 拖进废纸篓（系统拒删运行中的 App）。
                    HStack(spacing: 8) {
                        Text("SolunaCal \(Self.versionText)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("退出 SolunaCal") {
                            // 统一走 AppDelegate：带看门狗，万一被模态/窗口卡住也能退干净
                            NotificationCenter.default.post(name: .solunaQuitRequested, object: nil)
                        }
                            .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.visible)
        }
        .frame(width: 440)
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

    private var displaySection: some View {
section("显示") {
            toggleRow("显示宜忌（黄历）", $yijiEnabled)
            toggleRow("显示放假倒计时", $countdownEnabled)
            toggleRow("显示干支时辰（真太阳时）", $ganzhiEnabled)
                .onChange(of: ganzhiEnabled) { if ganzhiEnabled { LocationProvider.shared.locate() } }
        }
    }

    private var menuBarSection: some View {
section("菜单栏") {
            row("菜单栏形态") {
                Picker("菜单栏形态", selection: $statusItemStyle) {
                    Text("图标+文字").tag(1)
                    Text("仅图标").tag(2)
                    Text("仅文字").tag(0)
                }
                .labelsHidden().pickerStyle(.segmented)
                .onChange(of: statusItemStyle) {
                    NotificationCenter.default.post(name: .menuBarStyleNeedsUpdate, object: nil)
                }
            }
            if statusItemStyle != 2 {
                hint("右上角看不到它时，切「仅图标」更容易露出来")
            }

            row("菜单栏格式") {
                Picker("菜单栏格式", selection: formatChoice) {
                    Text("简洁").tag(0)
                    Text("带农历").tag(1)
                    Text("农历优先").tag(2)
                    Text("自定义").tag(3)
                }
                .labelsHidden().pickerStyle(.segmented)
            }
            if formatChoice.wrappedValue == 3 {
                templateEditor
            }

        }
    }

    private var interactionSection: some View {
section("交互") {
            toggleRow("登录后自动启动", $launchAtLogin)
                .onChange(of: launchAtLogin) { LaunchAtLogin.enabled = launchAtLogin }

            toggleRow("悬停弹出", $hoverEnabled)
            if hoverEnabled {
                HStack(spacing: 8) {
                    Slider(value: $hoverDelay, in: 0.2...1.5, step: 0.1)
                    Text(String(format: "%.1fs", hoverDelay))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.leading, 2)
                .padding(.vertical, 2)
            }

            row("呼出快捷键") {
                Button(recordingHotKey ? "按下新快捷键…" : HotKeyManager.saved.display) {
                    recordingHotKey.toggle()
                }
                .font(.system(size: 11, design: .monospaced))
                .controlSize(.small)
            }

            row("弹窗密度") {
                Picker("弹窗密度", selection: $popoverDensity) {
                    ForEach(PopoverDensity.allCases) { d in Text(d.label).tag(d.rawValue) }
                }
                .labelsHidden().pickerStyle(.segmented)
                .onChange(of: popoverDensity) {
                    NotificationCenter.default.post(name: .popoverDensityNeedsUpdate, object: nil)
                }
            }

            row("皮肤") {
                Picker("皮肤", selection: $skinRaw) {
                    ForEach(Skin.allCases) { s in Text(s.label).tag(s.rawValue) }
                }
                .labelsHidden().pickerStyle(.segmented)
            }
        }
    }

    private var notifySection: some View {
section("通知") {
            HStack(spacing: 6) {
                Text("系统权限").font(labelFont).foregroundStyle(.secondary)
                Spacer()
                Text(authText).font(.caption).foregroundStyle(authColor)
                if notifyAuth == .denied {
                    Button("去系统设置") { openNotificationSettings() }
                        .buttonStyle(.link).font(.caption)
                }
            }
            .frame(minHeight: 20)

            toggleRow("放假前一日提醒（18:00）", $notifyHolidayEve).onChange(of: notifyHolidayEve) { reschedule() }
            toggleRow("节日当天提醒（09:00）", $notifyFestival).onChange(of: notifyFestival) { reschedule() }
            toggleRow("生日/纪念日提醒（09:00）", $notifyBirthday).onChange(of: notifyBirthday) { reschedule() }
            toggleRow("免打扰时段", $dndEnabled).onChange(of: dndEnabled) { reschedule() }
            if dndEnabled {
                HStack(spacing: 6) {
                    DatePicker("", selection: dndStart, displayedComponents: .hourAndMinute)
                        .labelsHidden().frame(width: 70)
                    Text("至").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: dndEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden().frame(width: 70)
                }
                .padding(.leading, 2)
                .padding(.vertical, 2)
            }

            hint(nextReminderText)
        }
    }

    private var birthdaySection: some View {
section("生日 / 纪念日") {
            HStack {
                Text("已添加 \(store.entries.count) 条").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("批量添加") { showImport = true }
                    .buttonStyle(.link).font(.caption)
            }
            .frame(minHeight: 20)

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
            .padding(.vertical, 4)

            if !store.entries.isEmpty {
                ForEach(sortedEntries, id: \.entry.id) { item in
                    HStack {
                        Text(item.entry.name).font(labelFont)
                        Spacer()
                        Text(describe(item.entry))
                            .foregroundStyle(.secondary).font(.caption)
                        Text(countdownText(item.days))
                            .font(.caption)
                            .frame(width: 52, alignment: .trailing)
                            .foregroundStyle(item.days <= 7
                                ? Color.adaptive(light: 0xD43030, dark: 0xFF6961)
                                : Color.secondary)
                        Button("删") { store.remove(item.entry); reschedule() }
                            .buttonStyle(.plain).foregroundStyle(.red).font(.caption)
                    }
                    .frame(minHeight: 22)
                    .padding(.trailing, 2)
                }
            }
        }
    }

    // MARK: 版式零件

    /// 一行设置：标签左对齐，控件固定落在同一条右基准线上
    @ViewBuilder
    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(label).font(labelFont).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control().frame(width: controlColumn, alignment: .trailing)
        }
        .frame(minHeight: 26)
        .padding(.vertical, 2)
    }

    private func toggleRow(_ label: String, _ binding: Binding<Bool>) -> some View {
        row(label) {
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        Text(title).font(sectionFont).foregroundStyle(.secondary)
            .padding(.top, 14).padding(.bottom, 2)
        content()
    }

    /// 自定义模板编辑区：单独占满一行，不进控件列
    private var templateEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .padding(.bottom, 6)
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
