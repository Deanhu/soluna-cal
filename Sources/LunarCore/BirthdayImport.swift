import Foundation

/// 生日批量导入的文本解析（纯逻辑，无 UI 依赖，可单测）。
///
/// 为什么不用文件导入：生日存在 App 自己的偏好里，用户手上多数没有 CSV，
/// 让人先整理成文件再导入是多余的一步。粘贴几行更快。
///
/// 每行格式（空格 / 逗号 / 制表符分隔都接受）：
///     妈妈 9-19 农历
///     小王 10-20 公历
///     奶奶 闰6-05 农历
///
/// 历法标记可省略（默认农历，与设置页默认一致）；日期分隔符接受 - / . 月 日。
public enum BirthdayImport {

    public struct Row: Equatable {
        public let name: String
        public let month: Int
        public let day: Int
        public let isLeapMonth: Bool
        public let isLunar: Bool
    }

    public struct Failure: Equatable {
        public let line: Int      // 1-based，方便用户对照原文
        public let text: String
        public let reason: String
    }

    public struct Result: Equatable {
        public let rows: [Row]
        public let failures: [Failure]
        public var isEmpty: Bool { rows.isEmpty && failures.isEmpty }
    }

    private static let lunarWords: Set<String> = ["农历", "阴历", "旧历", "lunar", "L"]
    private static let solarWords: Set<String> = ["公历", "阳历", "新历", "solar", "S"]

    /// 公历每月天数；2 月按 29 计（闰年生日合法），2/30 这种直接判错
    private static let solarMonthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    public static func parse(_ text: String, defaultLunar: Bool = true) -> Result {
        var rows: [Row] = []
        var failures: [Failure] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (idx, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // 分隔符统一成空格，便于按 token 取
            let normalized = line
                .replacingOccurrences(of: "，", with: " ")
                .replacingOccurrences(of: ",", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "：", with: " ")
                .replacingOccurrences(of: ":", with: " ")
                .replacingOccurrences(of: "、", with: " ")
            let tokens = normalized.split(separator: " ").map(String.init)
            guard tokens.count >= 2 else {
                failures.append(.init(line: idx + 1, text: line, reason: "缺少年月日（写法：妈妈 9-19 农历）"))
                continue
            }

            // 历法标记：看最后一个 token
            var isLunar = defaultLunar
            var dateTokens = tokens
            if let last = tokens.last {
                let lower = last.lowercased()
                if lunarWords.contains(lower) { isLunar = true; dateTokens.removeLast() }
                else if solarWords.contains(lower) { isLunar = false; dateTokens.removeLast() }
            }
            guard dateTokens.count >= 2 else {
                failures.append(.init(line: idx + 1, text: line, reason: "只有名字，没有日期"))
                continue
            }

            let dateToken = dateTokens[dateTokens.count - 1]
            let name = dateTokens.dropLast().joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                failures.append(.init(line: idx + 1, text: line, reason: "没有名字"))
                continue
            }

            guard let parsed = parseDate(dateToken) else {
                failures.append(.init(line: idx + 1, text: line, reason: "日期「\(dateToken)」看不懂（写法：9-19）"))
                continue
            }
            var (month, day, leap) = parsed
            if leap && !isLunar {
                failures.append(.init(line: idx + 1, text: line, reason: "公历没有闰月"))
                continue
            }
            guard (1...12).contains(month) else {
                failures.append(.init(line: idx + 1, text: line, reason: "月份 \(month) 超出 1–12"))
                continue
            }
            let maxDay = isLunar ? 30 : Self.solarMonthDays[month - 1]
            guard (1...maxDay).contains(day) else {
                failures.append(.init(line: idx + 1, text: line, reason: isLunar
                                      ? "农历日 \(day) 超出 1–30"
                                      : "\(month) 月没有 \(day) 日"))
                continue
            }
            rows.append(.init(name: name, month: month, day: day, isLeapMonth: leap, isLunar: isLunar))
        }

        return Result(rows: rows, failures: failures)
    }

    /// 解析 `9-19` / `9/19` / `9.19` / `9月19` / `闰6-05`
    private static func parseDate(_ token: String) -> (month: Int, day: Int, leap: Bool)? {
        var s = token
        var leap = false
        if s.hasPrefix("闰") { leap = true; s.removeFirst() }

        for sep in ["-", "/", ".", "月"] {
            if let r = s.range(of: sep) {
                var left = String(s[s.startIndex..<r.lowerBound])
                var right = String(s[r.upperBound...])
                if right.hasSuffix("日") { right.removeLast() }
                guard let m = Int(left), let d = Int(right) else { return nil }
                return (m, d, leap)
            }
        }
        guard let m = Int(s) else { return nil }
        _ = m
        return nil
    }
}
