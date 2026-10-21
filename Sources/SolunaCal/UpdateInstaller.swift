import AppKit
import Foundation
import LunarCore

/// 安装位置管理：从安装包（磁盘映像）里直接运行是「临时状态」——
/// 卷一弹出 App 就没了，自动更新也用不了（目标只读）。首次运行就该把用户
/// 引到「应用程序」，而不是等他在更新时撞墙（0.4.3 真实事故）。
enum AppInstaller {
    /// 是否正从挂载卷（DMG）里直接运行
    static var isRunningFromVolume: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Volumes/")
    }

    static var installedURL: URL { URL(fileURLWithPath: "/Applications/SolunaCal.app") }

    /// 把当前运行的 App 装进「应用程序」。先拷到同卷临时名再整体替换，
    /// 任何一步失败都不会破坏已经装好的那份。
    static func installToApplications() throws -> URL {
        let fm = FileManager.default
        let dst = installedURL
        let tmp = URL(fileURLWithPath: "/Applications/.SolunaCal.app.new-\(getpid())")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: Bundle.main.bundleURL, to: tmp)
        clearQuarantine(tmp)
        if fm.fileExists(atPath: dst.path) {
            _ = try fm.replaceItemAt(dst, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: dst)
        }
        clearQuarantine(dst)
        return dst
    }

    /// 清掉「从网上下载」的隔离标记，否则 Gatekeeper 会拦首次打开
    private static func clearQuarantine(_ url: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-cr", url.path]
        try? p.run()
        p.waitUntilExit()
    }
}

/// 插包即更新：用户双击新 DMG 后，由**已安装、已被用户放行过的 App** 自己完成替换。
///
/// 为什么不让 DMG 里带安装器：没有 Apple 公证时，任何随包分发的可执行体
/// （安装器 App、.command 脚本）都会被 Gatekeeper 拦下——两种都实测过。
/// 唯一不受拦的是已经装进「应用程序」并被运行过的 App，所以更新只能由它来做。
enum UpdateInstaller {

    struct Candidate {
        let appURL: URL          // /Volumes/xxx/SolunaCal.app
        let version: String
        let volumeName: String
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private static var installURL: URL { Bundle.main.bundleURL }

    /// 当前运行位置能否被更新替换：装在「应用程序」里才可以。
    /// 从 DMG 卷里直接跑时 installURL 指向只读卷（EROFS），替换必败——
    /// 而且流程会先把旧 App 退掉，脚本再失败就没人把它拉回来，
    /// 用户侧看到的就是「点完更新，菜单栏图标没了」。所以先问可写性。
    static var isUpdatableInPlace: Bool {
        let path = installURL.path
        if path.hasPrefix("/Volumes/") { return false }
        return FileManager.default.isWritableFile(atPath: path)
    }

    /// 打开安装卷，让用户自己把 App 拖进「应用程序」
    static func revealInstallSource(_ candidate: Candidate) {
        // 注意：当前 SDK 里 deletingLastPathComponent 是方法不是属性，必须带 ()
        NSWorkspace.shared.open(candidate.appURL.deletingLastPathComponent())
    }

    /// 扫描 /Volumes 下的挂载卷，找出版本更高的 SolunaCal.app。
    /// 不用 FileManager.mountedVolumeURLs：实测在非全屏会话里它只返回 "/"，
    /// 挂载的磁盘映像根本列不出来；直接读 /Volumes 目录稳定得多。
    static func findCandidate() -> Candidate? {
        let fm = FileManager.default
        let volumesRoot = URL(fileURLWithPath: "/Volumes")
        let names = (try? fm.contentsOfDirectory(atPath: volumesRoot.path)) ?? []

        var best: Candidate?
        for name in names where !name.hasPrefix(".") {
            let vol = volumesRoot.appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: vol.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // 启动卷会以符号链接出现在 /Volumes 里，跳过
            if (try? vol.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }

            let app = vol.appendingPathComponent("SolunaCal.app")
            let plist = app.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let ver = dict["CFBundleShortVersionString"] as? String else { continue }
            guard AppVersion.isNewer(ver, than: currentVersion) else { continue }
            if best == nil || AppVersion.isNewer(ver, than: best!.version) {
                best = Candidate(appURL: app, version: ver, volumeName: name)
            }
        }
        return best
    }

    /// 弹窗询问；用户确认后返回 true
    static func askAndInstall(_ candidate: Candidate) -> Bool {
        // 从安装包卷里直接运行：替换目标只读，必败。此时只引导安装，
        // 绝不让 App 退出——退出后脚本失败就没人把它拉回来了
        // （实测症状：点完「立即更新」，菜单栏图标消失）。
        guard isUpdatableInPlace else {
            LaunchLog.write("更新中止：当前 App 位于只读位置（\(installURL.path)），先引导安装")
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "不能自动更新：App 所在位置不可写入"
            alert.informativeText = """
            当前 App 所在的位置盖不上新文件——从安装包（磁盘映像）里直接运行时
            就是这样，安装包是只读的。当前版本 \(currentVersion) 会继续正常用。

            装一次以后就能自动更新了：
            在打开的安装包窗口里，把 SolunaCal 拖到「应用程序」文件夹，
            以后从「应用程序」打开它。
            """
            alert.addButton(withTitle: "打开安装包")
            alert.addButton(withTitle: "以后再说")
            if alert.runModal() == .alertFirstButtonReturn {
                revealInstallSource(candidate)
            }
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "发现新版本 \(candidate.version)"
        alert.informativeText = """
        当前版本 \(currentVersion)，安装包来自「\(candidate.volumeName)」。

        点「立即更新」会自动完成：退出当前版本 → 替换 → 重新打开。
        你的生日、设置都会保留。
        """
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "以后再说")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try startReplace(from: candidate.appURL, to: installURL)
            LaunchLog.write("开始更新：\(currentVersion) → \(candidate.version)")
            return true
        } catch {
            let fail = NSAlert()
            fail.messageText = "更新失败"
            fail.informativeText = error.localizedDescription
            fail.addButton(withTitle: "好")
            fail.runModal()
            LaunchLog.write("更新失败：\(error.localizedDescription)")
            return false
        }
    }

    /// 写一个延迟执行的替换脚本，然后由调用方退出 App。
    /// 之所以要先退出再替换：运行中的 .app 被覆盖后进程仍在用内存里的旧代码，
    /// 表现就是「装了新版却还是旧界面」（已实测）。
    ///
    /// 铁律：**任何失败路径都必须把 App 重新打开**。旧进程已经退了，
    /// 脚本再不拉回来，用户侧就是「点完更新什么都没有了」——这是 0.4.3
    /// 真实事故的成因（只读卷上替换失败，静默 exit 1，无人重开）。
    /// 失败原因写进 update-error.log，下次启动时弹给用户看。
    private static func startReplace(from source: URL, to destination: URL) throws {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SolunaCal", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let scriptURL = support.appendingPathComponent("update.sh")

        let script = """
        #!/bin/sh
        # 由 SolunaCal 生成：等旧进程退出 → 整包替换 → 清隔离标记 → 重新打开
        # 顺序刻意做成「先拷到 .new，成功后再换」，任何一步失败都不会把用户装好的 App 弄没
        # fail()：留错误记录 + 把 App 拉回来。缺任何一条，用户都会「点完更新图标没了」
        ERR="$3"
        LOG="$ERR/update-error.log"

        fail() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
            [ -d "$DST" ] && /usr/bin/open "$DST"
            exit 1
        }

        sleep 2
        SRC="$1"
        DST="$2"
        NEW="$DST.new.$$"
        OLD="$DST.old.$$"

        if [ ! -d "$SRC" ]; then fail "安装源不存在：$SRC"; fi

        /usr/bin/ditto "$SRC" "$NEW" || { /bin/rm -rf "$NEW"; fail "拷贝失败（安装包所在的卷可能只读，或空间不足）：$DST"; }
        /usr/bin/xattr -cr "$NEW"

        if [ -d "$DST" ]; then
            /bin/mv "$DST" "$OLD" || { /bin/rm -rf "$NEW"; fail "旧版本移走失败：$DST"; }
        fi
        if ! /bin/mv "$NEW" "$DST"; then
            [ -d "$OLD" ] && /bin/mv "$OLD" "$DST"
            fail "替换失败，已回滚到原版本：$DST"
        fi
        /bin/rm -rf "$OLD"
        # 安装已成功：open 失败只是没自动拉起（用户手动双击即可），
        # 不能算「更新失败」——新版已经装好了。只留一条记录。
        if ! /usr/bin/open "$DST"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 新版本已装好，但没能自动打开，请手动双击打开：$DST" >> "$LOG"
        fi
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, source.path, destination.path, support.path]
        try process.run()

        // 等旧进程真的起来再退出，避免父进程先死导致 exec 失败
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
