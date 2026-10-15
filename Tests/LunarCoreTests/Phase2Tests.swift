import XCTest
import AppKit
@testable import LunarCore
@testable import SolunaUI

/// 二期：干支/时辰/真太阳时 + 通知计划器
final class Phase2Tests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: 日干支（锚点经独立历法库逐点核对）

    func testDayGanzhiAnchors() {
        let anchors: [(Int, Int, Int, String)] = [
            (1949, 10, 1, "甲子"), (2000, 1, 1, "戊午"), (2024, 2, 10, "甲辰"),
            (2025, 7, 25, "乙未"), (2026, 1, 1, "乙亥"), (2026, 2, 17, "壬戌"),
            (2026, 10, 15, "壬戌"), (2026, 12, 31, "己卯"),
        ]
        for (y, m, d, expect) in anchors {
            XCTAssertEqual(Ganzhi.day(date(y, m, d)), expect, "\(y)-\(m)-\(d)")
        }
    }

    // MARK: 时辰（五鼠遁；2026-10-15 壬戌日，经独立历法库核对）

    func testShichen() {
        // 壬日：子时起庚子
        XCTAssertEqual(Shichen.of(date: date(2026, 10, 15, 0, 30)), .init(name: "子时", ganzhi: "庚子"))
        XCTAssertEqual(Shichen.of(date: date(2026, 10, 15, 1, 30)), .init(name: "丑时", ganzhi: "辛丑"))
        XCTAssertEqual(Shichen.of(date: date(2026, 10, 15, 12, 30)), .init(name: "午时", ganzhi: "丙午"))
        XCTAssertEqual(Shichen.of(date: date(2026, 10, 15, 22, 30)), .init(name: "亥时", ganzhi: "辛亥"))
        // 晚子时（23 点后）按次日（癸）日干推 → 壬子
        XCTAssertEqual(Shichen.of(date: date(2026, 10, 15, 23, 30)), .init(name: "子时", ganzhi: "壬子"))
    }

    // MARK: 真太阳时（均时差全年两个极值月 + 经度修正符号）

    func testTrueSolarTime() {
        // 均时差：11 月初约 +16 分（年内正极值）
        let eotNov = TrueSolarTime.equationOfTimeMinutes(dayOfYear: 307)   // 2026-11-03
        XCTAssertTrue((15.0...17.5).contains(eotNov), "11 月初均时差应约 +16，实际 \(eotNov)")
        // 2 月中约 −14 分（年内负极值）
        let eotFeb = TrueSolarTime.equationOfTimeMinutes(dayOfYear: 43)    // 2026-02-12
        XCTAssertTrue((-15.5...(-13.0)).contains(eotFeb), "2 月中均时差应约 −14，实际 \(eotFeb)")
        // 经度修正：重庆 106°E → 4×(106−120) = −56 分；北京 116.4°E → −14.4 分
        let cq = TrueSolarTime.correctionMinutes(for: date(2026, 6, 1), longitude: 106)
        XCTAssertEqual(cq - TrueSolarTime.equationOfTimeMinutes(dayOfYear: 152), -56, accuracy: 0.01)
    }

    // MARK: 菜单栏 {GD} token

    func testDayGanzhiToken() {
        XCTAssertEqual(MenuBarFormat.render(template: "{GD}", date: date(2026, 10, 15)), "壬戌")
    }

    // MARK: 通知计划器

    func testPlannerTogglesOff() {
        let store = BirthdayStore(persists: false)
        store.add(.init(name: "妈妈", lunarMonth: 9, lunarDay: 19))
        XCTAssertTrue(NotificationPlanner.plan(now: date(2026, 10, 15),
                                               prefs: NotifyPrefs(), store: store).isEmpty)
    }

    func testPlannerBirthday() {
        let store = BirthdayStore(persists: false)
        store.add(.init(name: "妈妈", lunarMonth: 9, lunarDay: 19))   // = 2026-10-28（九月初二=10-11 已独立验证，+17 天）
        var prefs = NotifyPrefs(); prefs.birthday = true
        let plans = NotificationPlanner.plan(now: date(2026, 10, 15), prefs: prefs, store: store)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].kind, .birthday)
        XCTAssertEqual(plans[0].fireDate, date(2026, 10, 28, 9, 0))
        XCTAssertTrue(plans[0].body.contains("妈妈"))
    }

    func testPlannerHolidayEve() {
        var prefs = NotifyPrefs(); prefs.holidayEve = true
        let plans = NotificationPlanner.plan(now: date(2026, 9, 30, 12),
                                             prefs: prefs, store: BirthdayStore(persists: false))
        // 国庆 10-01 起休 7 天 → 前一日 18:00
        XCTAssertTrue(plans.contains {
            $0.kind == .holidayEve && $0.fireDate == date(2026, 9, 30, 18)
                && $0.body.contains("连休 7 天")
        })
    }

    func testPlannerFestival() {
        var prefs = NotifyPrefs(); prefs.festival = true
        let plans = NotificationPlanner.plan(now: date(2026, 10, 1, 8),
                                             prefs: prefs, store: BirthdayStore(persists: false))
        XCTAssertTrue(plans.contains { $0.title == "国庆" && $0.fireDate == date(2026, 10, 1, 9) })
    }

    // MARK: 免打扰顺延

    func testDNDShift() {
        // 跨零点 22:00–07:00
        XCTAssertEqual(NotificationPlanner.shiftOutOfDND(date(2026, 1, 1, 23), startMin: 1320, endMin: 420),
                       date(2026, 1, 2, 7))
        XCTAssertEqual(NotificationPlanner.shiftOutOfDND(date(2026, 1, 1, 3), startMin: 1320, endMin: 420),
                       date(2026, 1, 1, 7))
        XCTAssertEqual(NotificationPlanner.shiftOutOfDND(date(2026, 1, 1, 12), startMin: 1320, endMin: 420),
                       date(2026, 1, 1, 12))
        // 不跨零点 12:00–14:00
        XCTAssertEqual(NotificationPlanner.shiftOutOfDND(date(2026, 1, 1, 13), startMin: 720, endMin: 840),
                       date(2026, 1, 1, 14))
        // 通知计划整体走 DND：放假提醒 18:00 落在 17:00–19:00 → 19:00
        var prefs = NotifyPrefs()
        prefs.holidayEve = true; prefs.dndEnabled = true
        prefs.dndStartMin = 17 * 60; prefs.dndEndMin = 19 * 60
        let plans = NotificationPlanner.plan(now: date(2026, 9, 30, 12),
                                             prefs: prefs, store: BirthdayStore(persists: false))
        XCTAssertTrue(plans.contains { $0.fireDate == date(2026, 9, 30, 19) })
    }

    // MARK: 快捷键组合录制

    func testHotKeyComboRequiresModifier() {
        func keyEvent(_ mods: NSEvent.ModifierFlags, keyCode: UInt16 = 8) -> NSEvent {  // 8 = kVK_ANSI_C
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods,
                             timestamp: 0, windowNumber: 0, context: nil,
                             characters: "c", charactersIgnoringModifiers: "c",
                             isARepeat: false, keyCode: keyCode)!
        }
        // 裸字母键（无修饰键）必须拒绝——否则打字就触发弹窗
        XCTAssertNil(HotKeyManager.combo(from: keyEvent([])))
        // ⌥C = 出厂默认
        let c = HotKeyManager.combo(from: keyEvent(.option))
        XCTAssertEqual(c, .default)
        XCTAssertEqual(c?.display, "⌥C")
        // 组合修饰键位与展示顺序
        XCTAssertEqual(HotKeyManager.combo(from: keyEvent([.command, .shift]))?.display, "⇧⌘C")
    }

    // MARK: 菜单栏空模板回退

    func testMenuBarFormatEmptyTemplate() {
        let d = date(2026, 10, 15)
        XCTAssertEqual(MenuBarFormat.render(template: "", date: d),
                       MenuBarFormat.render(template: MenuBarFormat.defaultTemplate, date: d))
    }
}
