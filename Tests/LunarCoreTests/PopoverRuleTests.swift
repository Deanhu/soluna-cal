import XCTest
@testable import LunarCore

/// 弹窗翻月规则：朋友 B 反馈里「翻月后详情不刷新」「距元旦还有 72 天指代不清」两条。
/// 这两条以前只能靠手点验证，现在规则抽到 PopoverMonthRule，用边界把行为钉住。
final class PopoverRuleTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    // MARK: 翻月清选中

    /// B 的实际场景：10 月 18 日选中着，翻到 11 月 —— 必须清掉，
    /// 否则底部详情卡会一直写着「10月18日」，而 11 月网格里根本没有那天。
    func testSelectionClearedWhenMonthChanges() {
        XCTAssertTrue(PopoverMonthRule.shouldClearSelection(
            selected: date(2026, 10, 18), displayed: date(2026, 11, 1), calendar: cal))
    }

    /// 同一个月内换选中日、或原地不动，都不该清
    func testSelectionKeptWithinSameMonth() {
        XCTAssertFalse(PopoverMonthRule.shouldClearSelection(
            selected: date(2026, 10, 18), displayed: date(2026, 10, 1), calendar: cal))
        XCTAssertFalse(PopoverMonthRule.shouldClearSelection(
            selected: date(2026, 10, 18), displayed: date(2026, 10, 31), calendar: cal))
    }

    /// 没有选中时无所谓清不清，必须返回 false（否则会误触发 editingDay 重置）
    func testNoSelectionNeverClears() {
        XCTAssertFalse(PopoverMonthRule.shouldClearSelection(
            selected: nil, displayed: date(2026, 11, 1), calendar: cal))
    }

    /// 跨年：2026-12-31 → 2027-01-01 是不同月，必须清（只比月份不能只比年或只比月）
    func testSelectionClearedAcrossYearBoundary() {
        XCTAssertTrue(PopoverMonthRule.shouldClearSelection(
            selected: date(2026, 12, 31), displayed: date(2027, 1, 1), calendar: cal))
    }

    /// 反向：只比月份数字会把「2026-01」和「2027-01」当成同一个月，必须不相等
    func testSameMonthNumberDifferentYearIsDifferentMonth() {
        XCTAssertTrue(PopoverMonthRule.shouldClearSelection(
            selected: date(2026, 1, 15), displayed: date(2027, 1, 1), calendar: cal))
    }

    // MARK: 倒计时文案

    /// B 的截图场景：2026-10-21 看 2027 年元旦，只写「元旦」分不清是哪个
    func testCountdownAddsYearWhenTargetIsNextYear() {
        XCTAssertEqual(
            PopoverMonthRule.countdownLabel(name: "元旦", targetYear: 2027, todayYear: 2026),
            "2027 年元旦")
    }

    /// 同年内的节日不加年份，别把「距 国庆 还有 3 天」写成「距 2026 年国庆 还有 3 天」
    func testCountdownKeepsPlainNameWithinSameYear() {
        XCTAssertEqual(
            PopoverMonthRule.countdownLabel(name: "国庆", targetYear: 2026, todayYear: 2026),
            "国庆")
    }
}
