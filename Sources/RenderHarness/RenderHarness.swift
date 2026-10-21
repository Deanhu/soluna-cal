import AppKit
import SwiftUI
import SolunaUI
import LunarCore

/// 离屏渲染 harness：把弹窗视图绘成 PNG，用于无头自查。
/// 用法: RenderHarness <输出.png>
@main
enum RenderHarnessMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let args = CommandLine.arguments
        // 防跨次污染：命令行可执行文件的 UserDefaults 以进程名为域且持久化到磁盘。
        // 先清残留，再用 volatile 域（不落盘、优先级高于持久域）覆盖本 harness 管理的全部 key。
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "RenderHarness")
        UserDefaults.standard.removePersistentDomain(forName: "RenderHarness")
        var flags: [String: Any] = [
            "popoverDensity": "standard",
            "skin": "default",
            "ganzhiEnabled": false,
        ]
        // --density=compact|standard|comfortable：渲染指定密度
        if let flag = args.first(where: { $0.hasPrefix("--density=") }) {
            flags["popoverDensity"] = String(flag.dropFirst("--density=".count))
        }
        // --month=YYYY-MM：渲染指定月份（边界翻页自查用）
        var initialMonth: Date?
        if let flag = args.first(where: { $0.hasPrefix("--month=") }) {
            let parts = flag.dropFirst("--month=".count).split(separator: "-").compactMap { Int($0) }
            if parts.count == 2 {
                initialMonth = Calendar(identifier: .gregorian)
                    .date(from: DateComponents(year: parts[0], month: parts[1], day: 15))
            }
        }
        // --skin=default|springFestival：渲染指定皮肤
        if let flag = args.first(where: { $0.hasPrefix("--skin=") }) {
            flags["skin"] = String(flag.dropFirst("--skin=".count))
        }
        // --ganzhi：开启干支时辰行（真太阳时校正需定位，离屏下退回 120°E）
        if args.contains("--ganzhi") {
            flags["ganzhiEnabled"] = true
        }
        // --yiji：开启宜忌行（底部区域自查，用户反馈里常带这一行）
        flags["yijiEnabled"] = args.contains("--yiji")
        // 清完残留后把本 harness 管理的 key 全量显式写入（含默认值），保证单次运行自洽
        for (key, value) in flags { UserDefaults.standard.set(value, forKey: key) }
        // --select=YYYY-MM-DD：预选某日（渲染选中日区域：日程列表/干支行）
        var initialSelected: Date?
        func parseDay(_ flag: String) -> Date? {
            let parts = flag.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return Calendar(identifier: .gregorian)
                .date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
        }
        if let flag = args.first(where: { $0.hasPrefix("--select=") }) {
            initialSelected = parseDay(String(flag.dropFirst("--select=".count)))
        }
        // --format-custom：让设置页落在「自定义」格式档，渲染模板编辑器与实时预览
        if args.contains("--format-custom") {
            UserDefaults.standard.set("{GY}{SX} {M}月{D}日 {W} {LM}{LD}", forKey: "menuBarTemplate")
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
        if args.contains("--year") {
            let y = 2026
            let c = Calendar(identifier: .gregorian)
            let digest = YearDigest.build(year: y, calendar: c) { d, _ in
                (c.component(.month, from: d) == 10 && c.component(.day, from: d) == 28) ? "妈妈" : nil
            }
            hosting = NSHostingView(rootView: AnyView(
                YearOverviewView(year: y, digest: digest, skin: .default, onPick: { _ in })))
        } else if args.contains("--fallback") {
            hosting = NSHostingView(rootView: AnyView(
                FallbackWindowView(store: store, hotKeyText: "⌥⌘C", onClose: {})))
        } else if args.contains("--yiji-sheet") {
            let d = initialMonth ?? Date()
            let yj = Yiji.on(date: d) ?? (yi: "嫁娶 纳采 订盟 开市 交易 立券 挂匾 祭祀 祈福 开光 造车器 出行 拆卸 修造 动土 上梁 安床 开仓 出货财", ji: "探病 纳畜 伐木 起基 作梁 盖屋")
            hosting = NSHostingView(rootView: AnyView(
                YijiSheet(date: d, yi: yj.yi, ji: yj.ji)))
        } else if args.contains("--event-editor") {
            hosting = NSHostingView(rootView: AnyView(
                EventEditorView(date: initialMonth ?? Date()) { }))
        } else if args.contains("--import") {
            hosting = NSHostingView(rootView: AnyView(
                BirthdayImportView(initialText: "妈妈 9-19 农历\n小王 10-20 公历\n奶奶 闰6-05 农历\n张三 13-1 农历") { _ in }))
        } else if args.contains("--settings") {
            hosting = NSHostingView(rootView: AnyView(SettingsView(store: store)))
        } else if args.contains("--onboarding") {
            var startPage = 0
            if let flag = args.first(where: { $0.hasPrefix("--page=") }),
               let n = Int(flag.dropFirst("--page=".count)) { startPage = n }
            hosting = NSHostingView(rootView: AnyView(
                OnboardingView(initialPage: startPage, onFinish: {})))
        } else {
            hosting = NSHostingView(rootView: AnyView(CalendarPopoverView(
                store: store, initialMonth: initialMonth, initialSelected: initialSelected,
                // --access-denied：渲染「点过授权但没拿到权限」那一版详情卡
                initialAccessDenied: args.contains("--access-denied"))))
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
