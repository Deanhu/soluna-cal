import AppKit
import SwiftUI
import SolunaUI

/// 离屏渲染 harness：把弹窗视图绘成 PNG，用于无头自查。
/// 用法: RenderHarness <输出.png>
@main
enum RenderHarnessMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let args = CommandLine.arguments
        // --density=compact|standard|comfortable：渲染指定密度
        if let flag = args.first(where: { $0.hasPrefix("--density=") }) {
            UserDefaults.standard.set(String(flag.dropFirst("--density=".count)), forKey: "popoverDensity")
        }
        // --settings / --onboarding：渲染对应视图；默认渲染月历弹窗
        // --demo-birthdays：用纯内存示例数据（不碰真实 UserDefaults / iCloud）
        let store: BirthdayStore
        if args.contains("--demo-birthdays") {
            store = BirthdayStore(persists: false)
            store.add(.init(name: "妈妈", lunarMonth: 9, lunarDay: 19))   // 近：约 4 天后（红）
            store.add(.init(name: "爸爸", lunarMonth: 3, lunarDay: 6))    // 远：明春
            store.add(.init(name: "纪念日", lunarMonth: 10, lunarDay: 20, calendar: .solar)) // 5 天后
        } else {
            store = BirthdayStore()
        }
        let hosting: NSHostingView<AnyView>
        if args.contains("--settings") {
            hosting = NSHostingView(rootView: AnyView(SettingsView(store: store)))
        } else if args.contains("--onboarding") {
            hosting = NSHostingView(rootView: AnyView(OnboardingView(onFinish: {})))
        } else {
            hosting = NSHostingView(rootView: AnyView(CalendarPopoverView(store: store)))
        }
        // --dark：强制深色外观，用于深色模式自查
        if args.contains("--dark") {
            hosting.appearance = NSAppearance(named: .darkAqua)
        }
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 430)
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fatalError("bitmapImageRepForCachingDisplay failed")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("png encoding failed")
        }
        let out = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "soluna_preview.png"
        try! png.write(to: URL(fileURLWithPath: out))
        print("written:", out, Int(size.width), "x", Int(size.height))
        exit(0)
    }
}
