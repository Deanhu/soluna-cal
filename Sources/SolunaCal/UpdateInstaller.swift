import AppKit
import Foundation
import LunarCore

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
        sleep 2
        SRC="$1"
        DST="$2"
        NEW="$DST.new.$$"
        OLD="$DST.old.$$"

        if [ ! -d "$SRC" ]; then exit 1; fi

        /usr/bin/ditto "$SRC" "$NEW" || { /bin/rm -rf "$NEW"; exit 1; }
        /usr/bin/xattr -cr "$NEW"

        if [ -d "$DST" ]; then
            /bin/mv "$DST" "$OLD" || { /bin/rm -rf "$NEW"; exit 1; }
        fi
        if ! /bin/mv "$NEW" "$DST"; then
            [ -d "$OLD" ] && /bin/mv "$OLD" "$DST"
            exit 1
        fi
        /bin/rm -rf "$OLD"
        /usr/bin/open "$DST"
        exit 0
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path, source.path, destination.path]
        try process.run()

        // 等旧进程真的起来再退出，避免父进程先死导致 exec 失败
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}
