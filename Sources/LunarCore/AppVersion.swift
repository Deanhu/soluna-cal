import Foundation

/// 版本号比较（纯逻辑，可单测）。
///
/// 只处理我们自己的版本号形态：`0.3.0` 这类点分数字，段数可不等。
/// 不用 `String.compare` 逐字符比——那会把 "0.10.0" 判成小于 "0.9.0"。
public enum AppVersion {

    /// a 比 b 新返回 true；相等或更旧返回 false
    public static func isNewer(_ a: String, than b: String) -> Bool {
        compare(a, b) > 0
    }

    /// 1 = a 更新，0 = 相同，-1 = a 更旧
    public static func compare(_ a: String, _ b: String) -> Int {
        let left = segments(a)
        let right = segments(b)
        let n = max(left.count, right.count)
        for i in 0..<n {
            let x = i < left.count ? left[i] : 0
            let y = i < right.count ? right[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }

    /// 把 "0.3.1-beta" 这类后缀丢掉再切段；非法段按 0 处理
    private static func segments(_ s: String) -> [Int] {
        let core = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
