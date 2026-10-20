import Foundation

/// 启动日志：写到 `~/Library/Logs/SolunaCal.log`。
///
/// 为什么要有它：用户反馈「装完没反应」时，只看描述无法区分
/// 「没启动」「启动了但菜单栏项没建出来」「菜单栏项建出来了但被挤没了」。
/// 每一层在这里留一行，用户把日志发回来就能定位，不用远程猜。
///
/// 约束：只追加、不覆盖；超过 512 KB 轮转成 `.1`（最多两份），不会无限增长。
enum LaunchLog {
    static var fileURL: URL {
        FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("SolunaCal.log")
    }

    /// 形如 `0.2.1 (2)`
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static var systemText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) \(Arch.current)"
    }

    /// 固定格式：跨语言环境一致，且可直接按字面排序
    private static let stampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()

    static func write(_ message: String) {
        let line = "[\(stampFormatter.string(from: Date()))] \(message)\n"
        let url = fileURL
        let fm = FileManager.default

        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        rotateIfNeeded(url: url)

        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func rotateIfNeeded(url: URL) {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int,
              size > 512 * 1024 else { return }
        let old = url.deletingLastPathComponent().appendingPathComponent("SolunaCal.log.1")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
    }

    /// 自检里展示最近几行
    static func tail(_ lines: Int) -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(lines)
            .map(String.init)
    }
}

/// 当前可执行文件的 CPU 架构（区分是否跑在 Rosetta 下）
enum Arch {
    static var current: String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        let translated = isTranslated
        return translated ? "\(machine)（Rosetta）" : machine
    }

    private static var isTranslated: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &value, &size, nil, 0)
        return result == 0 && value == 1
    }
}
