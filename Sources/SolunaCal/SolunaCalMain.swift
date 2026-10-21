import AppKit
import SwiftUI
import LunarCore
import SolunaUI

@main
enum SolunaCalMain {
    static func main() {
        // 自检模式：打印环境检查结果后直接退出，不建菜单栏项、不常驻。
        // 用途：用户报「装完没反应」时，让他在终端跑一条命令把输出发回来。
        if CommandLine.arguments.contains("--selfcheck") {
            exit(SelfCheck.run())
        }
        // 日程诊断：某天系统日历到底有几条、各属哪个日历
        if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--dump-events=") }) {
            let raw = String(flag.dropFirst("--dump-events=".count))
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            guard let day = df.date(from: raw) else {
                print("日期格式应为 YYYY-MM-DD，例如 --dump-events=2026-10-10")
                exit(2)
            }
            var finished = false
            EventProvider.shared.requestAccessIfNeeded {
                print(EventProvider.shared.dump(date: day))
                finished = true
            }
            // 手动泵主 RunLoop：授权回调投递在主队列，直接 sleep 会死锁
            let deadline = Date().addingTimeInterval(20)
            while !finished, Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            if !finished { print("等待系统日历授权超时（20 秒）") }
            exit(finished ? 0 : 1)
        }
        // 更新检查的调试入口：打印当前版本与已挂载卷里的候选，供无头验证
        if CommandLine.arguments.contains("--check-update") {
            let cur = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            print("当前版本 \(cur)")
            let vols = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
            print("挂载卷：\(vols.map(\.path).joined(separator: " | "))")
            if let c = UpdateInstaller.findCandidate() {
                print("发现候选 \(c.version)  \(c.appURL.path)")
                exit(0)
            } else {
                print("没有更高版本")
                exit(1)
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // 菜单栏 App，无 Dock 图标
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var fallbackWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var eventWindow: NSWindow?
    private var yearWindow: NSWindow?
    private var yijiWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var timer: Timer?
    private var hoverTimer: Timer?
    private let store = BirthdayStore()

    /// 菜单栏形态（0=纯文字 1=图标+文字 2=纯图标）。
    /// 未写过该键时取 1——原先直接读 integer 会得到 0，导致「图标+文字」这条
    /// 默认路径从未生效，自定义的月印图标一直不显示。
    static var statusStyle: Int {
        let ud = UserDefaults.standard
        return ud.object(forKey: "statusItemStyle") == nil ? 1 : ud.integer(forKey: "statusItemStyle")
    }

    /// 按当前形态重建状态项的宽度与图标。
    /// 形态切换必须重建（宽度和有无图标都变了），只改标题不够。
    private func applyStatusAppearance() {
        guard statusItem != nil else { return }
        let style = Self.statusStyle
        statusItem.length = style == 2 ? NSStatusItem.squareLength : NSStatusItem.variableLength
        if let button = statusItem.button {
            if style >= 1 {
                // 自定义菜单栏模板图标（日历+弦月）；模板渲染自动适配深浅菜单栏
                let img = NSImage(named: "MenuBarIcon")
                img?.isTemplate = true
                if let img { img.accessibilityDescription = "Soluna" }
                button.image = img ?? NSImage(systemSymbolName: "calendar", accessibilityDescription: "Soluna")
            } else {
                button.image = nil
            }
        }
        updateTitle()
        LaunchLog.write("菜单栏形态已应用 style=\(style) 宽度=\(style == 2 ? "方形" : "自适应") 标题=「\(statusItem.button?.title ?? "")」")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 第一行就写日志：哪怕后面某步崩了，也能看出「启动到了这里」
        LaunchLog.write("启动 v\(LaunchLog.versionText) \(LaunchLog.systemText) path=\(Bundle.main.bundlePath)")
        logRunLocation()

        HolidayStore.refreshInBackground()
        // 同步登录自启注册状态与偏好（升级/重装后保持一致）
        if UserDefaults.standard.bool(forKey: "launchAtLogin") { LaunchAtLogin.apply() }

        // 全局快捷键（二期）：默认 ⌥C 呼出弹窗
        HotKeyManager.shared.onTrigger = { [weak self] in self?.togglePopover() }
        HotKeyManager.shared.register(HotKeyManager.saved)

        // 通知：启动时全量重排 + 每小时检查、落在凌晨 3 点的那次 tick 重排（幂等）
        if Bundle.main.bundleIdentifier != nil {
            NotificationManager.reschedule(store: store)
        } else {
            LaunchLog.write("跳过通知调度：当前进程没有 bundle id（不是标准 .app 启动）")
        }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let c = Calendar(identifier: .gregorian)
            if c.component(.hour, from: Date()) == 3 { NotificationManager.reschedule(store: self.store) }
        }.tolerance = 60

        // 调试预览：--preview 直接把弹窗内容放进普通窗口（供截图自查）
        if CommandLine.arguments.contains("--preview") {
            LaunchLog.write("预览模式（--preview）：不建菜单栏项，直接开窗口")
            NSApp.setActivationPolicy(.regular)
            let win = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 320, height: 420),
                styleMask: [.titled], backing: .buffered, defer: false)
            win.title = "Soluna Preview"
            host(CalendarPopoverView(store: store), in: win)
            win.center()
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 调试预览：--preview-panel=<settings|event|year|yiji|fallback|onboarding>
        // 按真实窗口路径（CloseableWindow + host()）打开面板，带 --out=<path> 时
        // 等布局完成后把内容渲染成 PNG 再退出——不依赖 screencapture / 激活 / 多屏坐标。
        // 用途：窗口承载出问题时无头复现（设置页曾被压成只剩标题一条）。
        if let flag = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-panel=") }) {
            let name = String(flag.dropFirst("--preview-panel=".count))
            LaunchLog.write("预览模式（--preview-panel=\(name)）")
            NSApp.setActivationPolicy(.regular)
            func show<V: View>(_ title: String, _ size: NSSize, _ view: V) {
                // 直接走生产路径：验的就是真路径，避免诊断代码与实现各写一份而分叉
                var slot: NSWindow?
                present(&slot, title: title, size: size, view: view)
                guard let w = slot,
                      let outFlag = CommandLine.arguments.first(where: { $0.hasPrefix("--out=") })
                else { return }
                let out = String(outFlag.dropFirst("--out=".count))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    guard let view = w.contentView else { print("no-content-view"); exit(1) }
                    print("panel=\(name) contentView=\(view.bounds.size) window=\(w.frame.size)")
                    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        print("capture-failed"); exit(1)
                    }
                    view.cacheDisplay(in: view.bounds, to: rep)   // 少了这步拿到的是空白位图
                    guard let png = rep.representation(using: .png, properties: [:]) else {
                        print("capture-failed"); exit(1)
                    }
                    try? png.write(to: URL(fileURLWithPath: out))
                    print("captured:", out)
                    exit(0)
                }
            }
            switch name {
            case "event":
                show("新建日程", NSSize(width: 360, height: 210),
                     EventEditorView(date: Date()) {} onClose: {})
            case "year":
                let y = Calendar(identifier: .gregorian).component(.year, from: Date())
                show("\(y) 年", NSSize(width: 420, height: 560),
                     YearOverviewView(year: y, digest: YearDigest.build(year: y) { _, _ in nil },
                                      onPick: { _ in }) {})
            case "yiji":
                let d = Date()
                let yj = Yiji.on(date: d) ?? (yi: "嫁娶 纳采 订盟", ji: "探病 伐木")
                show("宜忌", NSSize(width: 380, height: 320),
                     YijiSheet(date: d, yi: yj.yi, ji: yj.ji) {})
            case "fallback":
                show("SolunaCal", NSSize(width: 340, height: 600),
                     FallbackWindowView(store: store, hotKeyText: HotKeyManager.saved.display) {})
            case "onboarding":
                show("欢迎使用 Soluna", NSSize(width: 420, height: 320),
                     OnboardingView(hotKeyText: HotKeyManager.saved.display) {})
            default:
                show("SolunaCal 设置", NSSize(width: 440, height: 660),
                     SettingsView(store: store))
            }
            return
        }

        // 状态项形态：0=纯文字 1=图标+文字（默认） 2=纯图标（菜单栏拥挤时兜底）
        let style = Self.statusStyle
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(handleStatusClick)
            button.target = self
            // 同时接左键和右键：左键弹月历，右键出「退出」菜单
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        applyStatusAppearance()

        // 菜单栏项是唯一可见入口：建没建出来、标题是什么，必须留痕
        if let button = statusItem.button {
            LaunchLog.write("菜单栏项已创建 style=\(style) 标题=「\(button.title)」 图标=\(button.image != nil ? "有" : "无")")
        } else {
            LaunchLog.write("错误：菜单栏项创建失败（button 为 nil），界面不可见")
        }

        // 悬停弹出（二期）：trackingArea 跟随按钮可视区域；owner 必须是 NSResponder
        if let button = statusItem.button {
            hoverTracker.onEnter = { [weak self] in self?.scheduleHoverOpen() }
            hoverTracker.onExit = { [weak self] in
                self?.hoverTimer?.invalidate(); self?.hoverTimer = nil
            }
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: hoverTracker, userInfo: nil))
        }

        popover = NSPopover()
        popover.behavior = .transient
        // 初始尺寸按当前密度算，否则打开瞬间是 300 宽、0.15 秒后才跳到正确宽度，
        // 看起来像「先窄一下再弹开」。内容宽 = popoverWidth + 左右各 6pt。
        // 尺寸固定：宽度 = popoverWidth + 左右各 6pt；高度直接用 token。
        // 不再随内容变化，也就不需要任何"跟随内容"的同步逻辑。
        applyPopoverSize()   // 尺寸只在一处算：按当前密度固定宽高
        let popoverView = makePopoverView(fixedHeight: true)
        let popoverHC = NSHostingController(rootView: popoverView)
        // 让 popover 跟随内容尺寸（弹窗密度切换时自动伸缩）
        popoverHC.sizingOptions = [.preferredContentSize]
        popover.contentViewController = popoverHC

        // 每分钟刷新菜单栏标题
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateTitle()
        }
        // 设置里切换「菜单栏显示农历」立即生效（不等下一次定时刷新）
        NotificationCenter.default.addObserver(
            forName: .menuBarTitleNeedsUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.updateTitle()
        }
        // 设置里切换菜单栏形态：宽度和图标都变了，必须重建
        NotificationCenter.default.addObserver(
            forName: .solunaQuitRequested, object: nil, queue: .main) { [weak self] _ in
            self?.quitApp()
        }
        NotificationCenter.default.addObserver(
            forName: .popoverDensityNeedsUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.applyPopoverSize()
        }
        NotificationCenter.default.addObserver(
            forName: .menuBarStyleNeedsUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.applyStatusAppearance()
        }

        // 更新：双击新 DMG 后由本进程接手（DMG 里的可执行体过不了 Gatekeeper）
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] _ in
            self?.checkForUpdate(manual: false)
        }
        // 启动时也查一次：用户可能先挂载了 DMG 再启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.checkForUpdate(manual: false)
        }

        // 菜单栏塞满时图标会被藏到刘海后面：新用户将看不到任何入口。
        // 启动后确认一次，藏了就开兜底窗口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showFallbackIfStatusItemHidden()
        }

        // 上次自动更新失败的话，必须让用户知道（脚本会在 Application Support 留记录）。
        // 静默失败的代价是「点完更新图标没了，还以为 App 坏了」——0.4.3 真实事故。
        reportUpdateFailureIfAny()

        if Onboarding.needsOnboarding {
            LaunchLog.write("弹出首次引导窗口")
            showOnboarding()
        } else {
            LaunchLog.write("首次引导已完成，本次不弹窗口（只显示菜单栏项）")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        LaunchLog.write("退出")
    }

    /// 从安装卷直接运行时留个痕：自动更新此时不可用（替换目标只读），
    /// 出问题时能一眼看出用户是怎么跑的。
    private func logRunLocation() {
        guard Bundle.main.bundleURL.path.hasPrefix("/Volumes/") else { return }
        LaunchLog.write("注意：正从安装卷直接运行（\(Bundle.main.bundleURL.path)），自动更新不可用")
    }

    /// 上次更新失败：弹给用户看，然后清记录（只报一次）。
    /// 文案面向用户——不说「只读卷」「ditto」，只说现象和恢复办法。
    private func reportUpdateFailureIfAny() {
        let log = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SolunaCal", isDirectory: true)
            .appendingPathComponent("update-error.log")
        guard let text = try? String(contentsOf: log, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? FileManager.default.removeItem(at: log)
        LaunchLog.write("上次更新失败记录：\(text.replacingOccurrences(of: "\n", with: " | "))")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "上次自动更新没有正常完成"
        alert.informativeText = """
        \(text)

        当前版本还能正常用，数据都在。重新打开安装包、再试一次更新即可；
        如果还失败，把 App 拖到「应用程序」文件夹后再试。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// 菜单栏按钮点击：左键弹月历，右键出菜单（右键里必须有「退出」，
    /// 否则用户没法关掉这个没有 Dock 图标、也没有应用菜单的 App，连带删不掉）
    @objc private func handleStatusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let update = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdateMenu), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 SolunaCal", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // 弹完立刻摘掉，避免影响左键直接开弹窗
    }

    @objc private func checkForUpdateMenu() {
        checkForUpdate(manual: true)
    }

    /// 找新版本并按需弹窗；manual=true 时即使已提示过也再问一次
    private func checkForUpdate(manual: Bool) {
        guard let candidate = UpdateInstaller.findCandidate() else {
            if manual {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "没有可用的新版本"
                alert.informativeText = "当前 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")。\n先把新版本的安装包双击打开（会挂载成一个磁盘），再点这里。"
                alert.addButton(withTitle: "好")
                alert.runModal()
            }
            return
        }
        let key = "lastPromptedUpdate.version"
        if !manual, UserDefaults.standard.string(forKey: key) == candidate.version { return }
        UserDefaults.standard.set(candidate.version, forKey: key)
        _ = UpdateInstaller.askAndInstall(candidate)
    }

    /// 闪两下菜单栏图标：刚看完引导的人需要知道「东西在哪」
    private func flashStatusItem(times: Int = 2) {
        guard let button = statusItem.button else { return }
        for i in 0..<times {
            let delay = Double(i) * 0.7
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { button.highlight(true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.35) { button.highlight(false) }
        }
    }

    /// 判断菜单栏图标是否被系统藏起来了。
    /// 有刘海的屏幕会给出刘海两侧的安全区；图标落在两个区之外就是被藏了。
    private func statusItemIsHidden() -> Bool {
        guard let button = statusItem.button, let win = button.window else { return false }
        let frame = win.frame

        // 还没布局好（宽高为 0）时结果不可信：一律当可见，避免每次启动误弹
        guard frame.width > 1, frame.height > 1 else { return false }

        // 双屏时状态项在每块屏的菜单栏各有一份：任一屏可见即算可见。
        // 只查 win.screen 会在「内建刘海屏被藏、外接屏正常」时误报。
        for screen in NSScreen.screens {
            let zones = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea]
                .compactMap { $0 }
            if zones.isEmpty {
                if screen.frame.intersects(frame) { return false }
            } else if zones.contains(where: { $0.intersects(frame) }) {
                return false
            }
        }
        return true
    }

    private func showFallbackIfStatusItemHidden(retry: Bool = true) {
        if statusItemIsHidden() {
            showFallbackWindow()
            return
        }
        // 窗口还没布局好时（宽高为 0）结果不可信，1.2 秒后再看一眼
        if retry, let win = statusItem.button?.window,
           win.frame.width <= 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.showFallbackIfStatusItemHidden(retry: false)
            }
        }
    }

    /// 兜底窗口：说明为什么看不到图标 + 一个能用的日历
    /// 按当前密度重设弹窗尺寸（改密度、启动时都用这一条路径）
    private func applyPopoverSize() {
        let raw = UserDefaults.standard.string(forKey: "popoverDensity")
            ?? PopoverDensity.standard.rawValue
        let tk = (PopoverDensity(rawValue: raw) ?? .standard).tokens
        popover.contentSize = NSSize(width: tk.popoverWidth + 12, height: tk.popoverHeight)
    }

    private func showFallbackWindow() {
        if let w = fallbackWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = FallbackWindowView(store: store,
                                      hotKeyText: HotKeyManager.saved.display,
                                      onRequestSettings: { [weak self] in self?.showSettingsWindow() },
                                      onRequestYear: { [weak self] in self?.showYearWindow() },
                                      onEditEvent: { [weak self] day in self?.showEventEditor(day) },
                                      onOpenYiji: { [weak self] day in self?.showYijiWindow(day) }) { [weak self] in
            self?.fallbackWindow?.close()
        }
        let wc = NSWindowController(window: CloseableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false))
        wc.window?.title = "SolunaCal"
        wc.window?.delegate = self
        wc.window?.isReleasedWhenClosed = false
        // 先量理想高度，再按它收窗口（兜底窗口要贴合内容，不是固定 600）
        let ideal = NSHostingView(rootView: view).fittingSize
        if let win = wc.window { host(view, in: win) }
        wc.showWindow(nil)
        // 内容高度要等布局完成才知道：下一拍按理想尺寸收一下窗口
        DispatchQueue.main.async {
            if ideal.height > 0 {
                wc.window?.setContentSize(NSSize(width: 340, height: ideal.height))
            }
            wc.window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        fallbackWindow = wc.window
        LaunchLog.write("菜单栏图标不可见，已开兜底窗口")
    }

    /// 图标看不见时，双击 App 是唯一自然的入口：重新打开就给窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 图标在 → 老老实实弹菜单栏面板，不要莫名多一个窗口
        if statusItemIsHidden() {
            showFallbackWindow()
        } else if !popover.isShown {
            togglePopover()
        }
        return true
    }

    /// 弹窗/兜底窗口共用同一份视图装配：模态一律走独立窗口，视图里不再有 sheet
    private func makePopoverView(fixedHeight: Bool) -> CalendarPopoverView {
        var v = CalendarPopoverView(store: store, fixedHeight: fixedHeight)
        v.onOpenSettings = { [weak self] in self?.showSettingsWindow() }
        v.onEditEvent = { [weak self] day in self?.showEventEditor(day) }
        v.onOpenYear = { [weak self] in self?.showYearWindow() }
        v.onOpenYiji = { [weak self] day in self?.showYijiWindow(day) }
        return v
    }

    /// 把 SwiftUI 视图装进窗口，并让内容始终填满内容区。
    ///
    /// 不要用 NSHostingController 当 contentViewController：它会把窗口收缩到
    /// 内容的「理想尺寸」，而 ScrollView 的理想高度是 0 —— 设置页因此被压成
    /// 只剩标题一条（实测 440×660 的窗口被压成 440×65，内容视图 440×37，
    /// 就是「点设置只有一行字」的那个 bug）。NSHostingView 直接当 contentView
    /// 并开自适应，内容才会真正填满窗口。
    private func host<V: View>(_ view: V, in window: NSWindow) {
        let hv = NSHostingView(rootView: view)
        hv.frame = NSRect(origin: .zero, size: window.contentLayoutRect.size)
        hv.autoresizingMask = [.width, .height]
        window.contentView = hv
    }

    /// 统一的窗口呈现：已存在就前置，避免重复开
    private func present<C: View>(_ slot: inout NSWindow?, title: String,
                                  size: NSSize, view: C) {
        if let w = slot {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // 尺寸在创建时就算准，别让窗口先开成声明尺寸再被内容收缩（会看到跳一下）：
        // 内容比窗口小 → 收成内容尺寸（不留大片空白）；
        // 内容带 ScrollView → 理想高度会大于声明值，按声明值截断（窗口固定、内部滚动）
        let fitting = NSHostingView(rootView: view).fittingSize
        let target = NSSize(width: min(size.width, max(fitting.width, 1)),
                            height: min(size.height, max(fitting.height, 1)))
        // CloseableWindow：配件 App 没有「窗口」菜单，⌘W 走菜单那条路不通，
        // 直接在窗口里把 Esc / ⌘W 接成关窗，和其他 Mac 应用行为一致
        let w = CloseableWindow(contentRect: NSRect(origin: .zero, size: target),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = title
        host(view, in: w)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        slot = w
    }

    /// 关闭任意已打开的面板窗口（弹窗还开着时先收，避免它浮在新窗口背后）
    private func dismissPopover() {
        guard popover != nil, popover.isShown else { return }
        popover.performClose(nil)
    }

    /// 窗口被关掉时清槽位：只靠 onClose 回调管不住「点红钮 / ⌘W」这两条路。
    /// 槽位留着旧窗口，下次打开就是旧窗口旧状态（设置权限状态、输入框全带旧的）；
    /// 实测已关闭窗口虽能被 makeKeyAndOrderFront 重新显示，但内容不会重建。
    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if w === settingsWindow { settingsWindow = nil }
        else if w === eventWindow { eventWindow = nil }
        else if w === yearWindow { yearWindow = nil }
        else if w === yijiWindow { yijiWindow = nil }
        else if w === fallbackWindow { fallbackWindow = nil }
        else if w === onboardingWindow {
            onboardingWindow = nil
            // 引导被红钮关掉等同「跳过」：不留着每次启动重弹
            Onboarding.markCompleted()
        }
    }

    private func showSettingsWindow() {
        dismissPopover()
        present(&settingsWindow, title: "SolunaCal 设置",
                size: NSSize(width: 440, height: 660),
                view: SettingsView(store: store) { [weak self] in
                    self?.settingsWindow?.close()
                })
    }

    private func showEventEditor(_ day: Date) {
        dismissPopover()
        present(&eventWindow, title: "新建日程", size: NSSize(width: 360, height: 210),
                view: EventEditorView(date: day) {
                    EventProvider.shared.refresh(year: Calendar(identifier: .gregorian).component(.year, from: day),
                                                 month: Calendar(identifier: .gregorian).component(.month, from: day))
                } onClose: { [weak self] in
                    self?.eventWindow?.close()
                })
    }

    private func showYearWindow() {
        dismissPopover()
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        present(&yearWindow, title: "\(year) 年", size: NSSize(width: 420, height: 560),
                view: YearOverviewView(
                    year: year,
                    digest: YearDigest.build(year: year) { d, lunar in
                        guard let b = self.store.match(date: d, lunar: lunar) else { return nil }
                        return b.name.count <= 2 ? b.name : "生日"
                    },
                    skin: UserDefaults.standard.currentSkin,
                    onPick: { month in
                        let c = DateComponents(year: year, month: month, day: 1)
                        if let d = Calendar(identifier: .gregorian).date(from: c) {
                            NotificationCenter.default.post(name: .solunaJumpToMonth, object: d)
                        }
                    }) { [weak self] in
                    self?.yearWindow?.close()
                })
    }

    private func showYijiWindow(_ day: Date) {
        dismissPopover()
        guard let yj = Yiji.on(date: day) else { return }
        present(&yijiWindow, title: "宜忌", size: NSSize(width: 380, height: 320),
                view: YijiSheet(date: day, yi: yj.yi, ji: yj.ji,
                                skin: UserDefaults.standard.currentSkin) { [weak self] in
                    self?.yijiWindow?.close()
                })
    }

    @objc private func quitApp() {
        LaunchLog.write("用户从菜单栏退出")
        NSApp.terminate(nil)
        // 看门狗：某些情况下 terminate 会被模态/窗口拖住（朋友 B 点退出没反应），
        // 1.5 秒还没退就强制结束进程。
        // 必须挂全局队列：主队列 asyncAfter 自己要排在主线程后面——
        // 主线程被模态会话卡死时（正是它要兜底的场景）主队列的看门狗永远不触发。
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
            LaunchLog.write("terminate 未在 1.5 秒内完成，强制 exit(0)")
            exit(0)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: 悬停弹出

    private let hoverTracker = HoverTracker()

    private func scheduleHoverOpen() {
        guard UserDefaults.standard.bool(forKey: "hoverEnabled"), popover.isShown == false else { return }
        let delay = UserDefaults.standard.object(forKey: "hoverDelay") != nil
            ? UserDefaults.standard.double(forKey: "hoverDelay") : 0.4
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, let button = self.statusItem.button, !self.popover.isShown else { return }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateTitle() {
        guard Self.statusStyle != 2 else {
            statusItem.button?.title = ""
            return
        }
        let ud = UserDefaults.standard
        // 自定义模板优先；否则一期「显示农历」开关映射到预设（开关被 token 系统吸收）
        let template = ud.string(forKey: "menuBarTemplate")
            ?? (ud.bool(forKey: "menuBarLunar")
                ? MenuBarFormat.presets[1].template : MenuBarFormat.presets[0].template)
        statusItem.button?.title = MenuBarFormat.render(template: template, date: Date())
    }

    private func showOnboarding() {
        let wc = NSWindowController(window: CloseableWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable], backing: .buffered, defer: false))
        wc.window?.title = "欢迎使用 Soluna"
        wc.window?.delegate = self
        if let win = wc.window {
            host(OnboardingView(hotKeyText: HotKeyManager.saved.display) {
                Onboarding.markCompleted()
                // 引导里可能刚打开提醒：立刻排期，别等下一次启动
                NotificationManager.reschedule(store: self.store)
                wc.close()
                // 引导刚讲完「图标在右上角」，这里立刻指一下位置：
                // 图标在就闪两下，图标被藏就直接开兜底窗口
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self else { return }
                    if self.statusItemIsHidden() {
                        self.showFallbackWindow()
                    } else {
                        self.flashStatusItem()
                    }
                }
            }, in: win)
        }
        wc.window?.center()
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = wc.window
    }
}

/// 面板窗口：把 Esc / ⌘W 接成关窗。
/// 配件应用没有「窗口」菜单，⌘W 沿菜单链根本到不了这里，只能窗口自己接。
final class CloseableWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
    override func performClose(_ sender: Any?) { close() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:                        // Esc
            close()
        default:
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "w" {
                close()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

/// 悬停事件接收器（NSTrackingArea 的 owner 必须是 NSResponder）
private final class HoverTracker: NSResponder {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// 首次引导标记
enum Onboarding {
    static let key = "onboarding.completed"
    static var needsOnboarding: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func markCompleted() { UserDefaults.standard.set(true, forKey: key) }
}
