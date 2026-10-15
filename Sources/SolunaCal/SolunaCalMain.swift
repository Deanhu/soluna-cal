import AppKit
import SwiftUI
import LunarCore
import SolunaUI

@main
enum SolunaCalMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // 菜单栏 App，无 Dock 图标
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer?
    private var hoverTimer: Timer?
    private let store = BirthdayStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HolidayStore.refreshInBackground()
        // 同步登录自启注册状态与偏好（升级/重装后保持一致）
        if UserDefaults.standard.bool(forKey: "launchAtLogin") { LaunchAtLogin.apply() }

        // 全局快捷键（二期）：默认 ⌥C 呼出弹窗
        HotKeyManager.shared.onTrigger = { [weak self] in self?.togglePopover() }
        HotKeyManager.shared.register(HotKeyManager.saved)

        // 通知：启动时全量重排 + 每小时检查、落在凌晨 3 点的那次 tick 重排（幂等）
        NotificationManager.reschedule(store: store)
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            let c = Calendar(identifier: .gregorian)
            if c.component(.hour, from: Date()) == 3 { NotificationManager.reschedule(store: self.store) }
        }.tolerance = 60

        // 调试预览：--preview 直接把弹窗内容放进普通窗口（供截图自查）
        if CommandLine.arguments.contains("--preview") {
            NSApp.setActivationPolicy(.regular)
            let win = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 320, height: 420),
                styleMask: [.titled], backing: .buffered, defer: false)
            win.title = "Soluna Preview"
            win.contentViewController = NSHostingController(
                rootView: CalendarPopoverView(store: store))
            win.center()
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 状态项形态：0=纯文字 1=图标+文字（默认） 2=纯图标（菜单栏拥挤时兜底）
        let style = UserDefaults.standard.integer(forKey: "statusItemStyle")
        statusItem = NSStatusBar.system.statusItem(
            withLength: style == 2 ? NSStatusItem.squareLength : NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            if style >= 1 {
                button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "Soluna")
            }
        }
        updateTitle()

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
        popover.contentSize = NSSize(width: 300, height: 400)
        let popoverHC = NSHostingController(rootView: CalendarPopoverView(store: store))
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

        if Onboarding.needsOnboarding {
            showOnboarding()
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
        guard UserDefaults.standard.integer(forKey: "statusItemStyle") != 2 else {
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
        let wc = NSWindowController(window: NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false))
        wc.window?.title = "欢迎使用 Soluna"
        wc.window?.contentViewController = NSHostingController(
            rootView: OnboardingView { Onboarding.markCompleted() ; wc.close() })
        wc.window?.center()
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
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
