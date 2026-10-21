import AppKit
import EventKit
import Foundation

/// `--selfcheck`：一条命令完成环境自检，输出可直接截图发回。
///
/// 只读：不改偏好、不装服务、不常驻。唯一副作用是临时建一个菜单栏项（随即移除），
/// 用来判断「菜单栏还建不建得出来」——这正是「装完没反应」最常见的断点。
enum SelfCheck {
    static func run() -> Int32 {
        var problems: [String] = []
        let bundlePath = Bundle.main.bundlePath

        section("版本")
        print("SolunaCal \(LaunchLog.versionText)")
        print(LaunchLog.systemText)
        print("应用位置 \(bundlePath)")

        // 1. 是不是还挂在磁盘映像里跑
        section("安装位置")
        if bundlePath.hasPrefix("/Volumes/") {
            print("✗ 正在从磁盘映像（DMG）里运行")
            print("  → 必须先把 SolunaCal 拖进「应用程序」文件夹再打开")
            problems.append("应用还在 DMG 里，没有复制到「应用程序」")
        } else if bundlePath.hasPrefix("/Applications/") {
            print("✓ 已安装到「应用程序」")
        } else {
            print("△ 不在「应用程序」里（能用，但建议移过去）")
        }

        // 2. 隔离标记
        section("隔离标记（决定会不会被系统拦）")
        if hasQuarantine(bundlePath) {
            print("✗ 仍有 com.apple.quarantine —— 下次双击仍会被拦")
            print("  → 终端执行：xattr -cr \"\(bundlePath)\"")
            problems.append("隔离标记未清除")
        } else {
            print("✓ 已清除")
        }

        // 3. 日历权限：决定「新建日程」写系统日历还是只存本机。
        //    用户报「点授权没反应」基本都是这里已经是 denied ——
        //    被拒之后系统不会再弹窗，点按钮当然什么都不发生。
        section("日历权限")
        let auth = EKEventStore.authorizationStatus(for: .event)
        switch auth {
        case .notDetermined:
            print("· 尚未询问（下次点「授权」时系统会弹窗）")
        case .denied:
            print("✗ 已被拒绝 —— 系统不会再弹窗，所以点「授权」不会有任何反应")
            print("  → 去「系统设置 → 隐私与安全性 → 日历」把 SolunaCal 勾上")
            problems.append("日历权限被拒，系统不会再弹窗")
        case .restricted:
            print("✗ 受系统限制（家长控制 / 设备管理），无法授权")
            problems.append("日历权限受系统限制")
        case .fullAccess:
            print("✓ 已授权（完全访问）")
        case .writeOnly:
            print("△ 只有写入权限：能建日程，但读不到已有日程（月历不显示小圆点）")
        @unknown default:
            print("? 未知状态 raw=\(auth.rawValue)")
        }

        // 4. 内嵌组件是否齐（缺了会在启动瞬间退出，什么都不显示）
        section("内嵌组件")
        let frameworks = ["LunarCore", "SolunaUI"]
        for name in frameworks {
            let path = "\(bundlePath)/Contents/Frameworks/\(name).framework"
            if FileManager.default.fileExists(atPath: path) {
                print("✓ \(name).framework")
            } else {
                print("✗ 缺少 \(name).framework —— 安装不完整，请重新复制")
                problems.append("缺少 \(name).framework")
            }
        }

        // 4. 菜单栏项能否创建
        section("菜单栏")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if item.button != nil {
            print("✓ 能创建菜单栏项")
            NSStatusBar.system.removeStatusItem(item)
        } else {
            print("✗ 菜单栏项创建失败")
            problems.append("菜单栏项创建失败")
        }
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.soluna.cal")
            .filter { $0.processIdentifier != getpid() }
        if others.isEmpty {
            print("· 当前没有其他 SolunaCal 实例在跑")
        } else {
            print("· 另有 \(others.count) 个 SolunaCal 实例在跑（pid \(others.map { String($0.processIdentifier) }.joined(separator: ", "))）")
        }

        // 5. 首次引导状态：它决定「打开后有没有窗口」
        section("首次引导")
        if UserDefaults.standard.bool(forKey: "onboarding.completed") {
            print("· 已完成（所以打开后不会再有窗口，只会出现在菜单栏右上角）")
        } else {
            print("· 未完成（下次打开会弹「欢迎使用 Soluna」窗口）")
        }

        // 6. 最近日志
        section("最近启动日志")
        let tail = LaunchLog.tail(8)
        if tail.isEmpty {
            print("（还没有日志——说明这个版本还没成功启动过）")
        } else {
            tail.forEach { print($0) }
        }
        print("日志文件：\(LaunchLog.fileURL.path)")

        // 7. 结论
        section("结论")
        if problems.isEmpty {
            print("✓ 环境正常。如果看不到界面，请看屏幕右上角菜单栏（它不占 Dock，也不开窗口）。")
            print("  菜单栏图标被挤掉时：先退出几个别的菜单栏 App，或点一下桌面再看右上角。")
            return 0
        } else {
            for p in problems { print("✗ \(p)") }
            return 1
        }
    }

    private static func section(_ title: String) {
        print("")
        print("── \(title) ──")
    }

    private static func hasQuarantine(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) > 0
    }
}
