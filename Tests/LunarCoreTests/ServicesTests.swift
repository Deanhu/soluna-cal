import XCTest
@testable import LunarCore

final class ServicesTests: XCTestCase {
    private var cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    func testYiji() {
        // 内置表覆盖 2025–2027，今天（2026-10-15）必须能查到
        let yj = Yiji.on(date: date(2026, 10, 15), calendar: cal)
        XCTAssertNotNil(yj)
        XCTAssertFalse(yj!.yi.isEmpty)
        // 表外日期返回 nil 而不是瞎编
        XCTAssertNil(Yiji.on(date: date(2030, 1, 1), calendar: cal))
    }

    func testLaunchAtLoginDefault() {
        // 默认不自启（不打扰底线）
        XCTAssertFalse(LaunchAtLogin.enabled)
    }
}
