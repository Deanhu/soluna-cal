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

    // MARK: 节气表（抽年回归，数据先经 lunar-python 逐日法全量对账 4800/4800）

    /// 节气表抽年回归：8 个代表年 × 24 节气，全部先经 lunar-python 逐日法对账（4800/4800 一致）
    func testSolarTermSampledYears() {
        let cal = Calendar(identifier: .gregorian)
        // 1900 年
        XCTAssertEqual(SolarTerm.on(date: date(1900, 1, 6), calendar: cal), .minorCold)  // 1900 小寒
        XCTAssertEqual(SolarTerm.on(date: date(1900, 1, 20), calendar: cal), .majorCold)  // 1900 大寒
        XCTAssertEqual(SolarTerm.on(date: date(1900, 2, 4), calendar: cal), .springBegins)  // 1900 立春
        XCTAssertEqual(SolarTerm.on(date: date(1900, 2, 19), calendar: cal), .rainWater)  // 1900 雨水
        XCTAssertEqual(SolarTerm.on(date: date(1900, 3, 6), calendar: cal), .insectsAwaken)  // 1900 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(1900, 3, 21), calendar: cal), .springEquinox)  // 1900 春分
        XCTAssertEqual(SolarTerm.on(date: date(1900, 4, 5), calendar: cal), .qingming)  // 1900 清明
        XCTAssertEqual(SolarTerm.on(date: date(1900, 4, 20), calendar: cal), .grainRain)  // 1900 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(1900, 5, 6), calendar: cal), .summerBegins)  // 1900 立夏
        XCTAssertEqual(SolarTerm.on(date: date(1900, 5, 21), calendar: cal), .grainBuds)  // 1900 小满
        XCTAssertEqual(SolarTerm.on(date: date(1900, 6, 6), calendar: cal), .grainInEar)  // 1900 芒种
        XCTAssertEqual(SolarTerm.on(date: date(1900, 6, 22), calendar: cal), .summerSolstice)  // 1900 夏至
        XCTAssertEqual(SolarTerm.on(date: date(1900, 7, 7), calendar: cal), .minorHeat)  // 1900 小暑
        XCTAssertEqual(SolarTerm.on(date: date(1900, 7, 23), calendar: cal), .majorHeat)  // 1900 大暑
        XCTAssertEqual(SolarTerm.on(date: date(1900, 8, 8), calendar: cal), .autumnBegins)  // 1900 立秋
        XCTAssertEqual(SolarTerm.on(date: date(1900, 8, 23), calendar: cal), .endOfHeat)  // 1900 处暑
        XCTAssertEqual(SolarTerm.on(date: date(1900, 9, 8), calendar: cal), .whiteDew)  // 1900 白露
        XCTAssertEqual(SolarTerm.on(date: date(1900, 9, 23), calendar: cal), .autumnEquinox)  // 1900 秋分
        XCTAssertEqual(SolarTerm.on(date: date(1900, 10, 9), calendar: cal), .coldDew)  // 1900 寒露
        XCTAssertEqual(SolarTerm.on(date: date(1900, 10, 24), calendar: cal), .frostDescent)  // 1900 霜降
        XCTAssertEqual(SolarTerm.on(date: date(1900, 11, 8), calendar: cal), .winterBegins)  // 1900 立冬
        XCTAssertEqual(SolarTerm.on(date: date(1900, 11, 23), calendar: cal), .minorSnow)  // 1900 小雪
        XCTAssertEqual(SolarTerm.on(date: date(1900, 12, 7), calendar: cal), .majorSnow)  // 1900 大雪
        XCTAssertEqual(SolarTerm.on(date: date(1900, 12, 22), calendar: cal), .winterSolstice)  // 1900 冬至
        // 1902 年
        XCTAssertEqual(SolarTerm.on(date: date(1902, 1, 6), calendar: cal), .minorCold)  // 1902 小寒
        XCTAssertEqual(SolarTerm.on(date: date(1902, 1, 21), calendar: cal), .majorCold)  // 1902 大寒
        XCTAssertEqual(SolarTerm.on(date: date(1902, 2, 5), calendar: cal), .springBegins)  // 1902 立春
        XCTAssertEqual(SolarTerm.on(date: date(1902, 2, 19), calendar: cal), .rainWater)  // 1902 雨水
        XCTAssertEqual(SolarTerm.on(date: date(1902, 3, 6), calendar: cal), .insectsAwaken)  // 1902 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(1902, 3, 21), calendar: cal), .springEquinox)  // 1902 春分
        XCTAssertEqual(SolarTerm.on(date: date(1902, 4, 6), calendar: cal), .qingming)  // 1902 清明
        XCTAssertEqual(SolarTerm.on(date: date(1902, 4, 21), calendar: cal), .grainRain)  // 1902 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(1902, 5, 6), calendar: cal), .summerBegins)  // 1902 立夏
        XCTAssertEqual(SolarTerm.on(date: date(1902, 5, 22), calendar: cal), .grainBuds)  // 1902 小满
        XCTAssertEqual(SolarTerm.on(date: date(1902, 6, 7), calendar: cal), .grainInEar)  // 1902 芒种
        XCTAssertEqual(SolarTerm.on(date: date(1902, 6, 22), calendar: cal), .summerSolstice)  // 1902 夏至
        XCTAssertEqual(SolarTerm.on(date: date(1902, 7, 8), calendar: cal), .minorHeat)  // 1902 小暑
        XCTAssertEqual(SolarTerm.on(date: date(1902, 7, 24), calendar: cal), .majorHeat)  // 1902 大暑
        XCTAssertEqual(SolarTerm.on(date: date(1902, 8, 8), calendar: cal), .autumnBegins)  // 1902 立秋
        XCTAssertEqual(SolarTerm.on(date: date(1902, 8, 24), calendar: cal), .endOfHeat)  // 1902 处暑
        XCTAssertEqual(SolarTerm.on(date: date(1902, 9, 8), calendar: cal), .whiteDew)  // 1902 白露
        XCTAssertEqual(SolarTerm.on(date: date(1902, 9, 24), calendar: cal), .autumnEquinox)  // 1902 秋分
        XCTAssertEqual(SolarTerm.on(date: date(1902, 10, 9), calendar: cal), .coldDew)  // 1902 寒露
        XCTAssertEqual(SolarTerm.on(date: date(1902, 10, 24), calendar: cal), .frostDescent)  // 1902 霜降
        XCTAssertEqual(SolarTerm.on(date: date(1902, 11, 8), calendar: cal), .winterBegins)  // 1902 立冬
        XCTAssertEqual(SolarTerm.on(date: date(1902, 11, 23), calendar: cal), .minorSnow)  // 1902 小雪
        XCTAssertEqual(SolarTerm.on(date: date(1902, 12, 8), calendar: cal), .majorSnow)  // 1902 大雪
        XCTAssertEqual(SolarTerm.on(date: date(1902, 12, 23), calendar: cal), .winterSolstice)  // 1902 冬至
        // 1952 年
        XCTAssertEqual(SolarTerm.on(date: date(1952, 1, 6), calendar: cal), .minorCold)  // 1952 小寒
        XCTAssertEqual(SolarTerm.on(date: date(1952, 1, 21), calendar: cal), .majorCold)  // 1952 大寒
        XCTAssertEqual(SolarTerm.on(date: date(1952, 2, 5), calendar: cal), .springBegins)  // 1952 立春
        XCTAssertEqual(SolarTerm.on(date: date(1952, 2, 20), calendar: cal), .rainWater)  // 1952 雨水
        XCTAssertEqual(SolarTerm.on(date: date(1952, 3, 5), calendar: cal), .insectsAwaken)  // 1952 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(1952, 3, 21), calendar: cal), .springEquinox)  // 1952 春分
        XCTAssertEqual(SolarTerm.on(date: date(1952, 4, 5), calendar: cal), .qingming)  // 1952 清明
        XCTAssertEqual(SolarTerm.on(date: date(1952, 4, 20), calendar: cal), .grainRain)  // 1952 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(1952, 5, 5), calendar: cal), .summerBegins)  // 1952 立夏
        XCTAssertEqual(SolarTerm.on(date: date(1952, 5, 21), calendar: cal), .grainBuds)  // 1952 小满
        XCTAssertEqual(SolarTerm.on(date: date(1952, 6, 6), calendar: cal), .grainInEar)  // 1952 芒种
        XCTAssertEqual(SolarTerm.on(date: date(1952, 6, 21), calendar: cal), .summerSolstice)  // 1952 夏至
        XCTAssertEqual(SolarTerm.on(date: date(1952, 7, 7), calendar: cal), .minorHeat)  // 1952 小暑
        XCTAssertEqual(SolarTerm.on(date: date(1952, 7, 23), calendar: cal), .majorHeat)  // 1952 大暑
        XCTAssertEqual(SolarTerm.on(date: date(1952, 8, 7), calendar: cal), .autumnBegins)  // 1952 立秋
        XCTAssertEqual(SolarTerm.on(date: date(1952, 8, 23), calendar: cal), .endOfHeat)  // 1952 处暑
        XCTAssertEqual(SolarTerm.on(date: date(1952, 9, 8), calendar: cal), .whiteDew)  // 1952 白露
        XCTAssertEqual(SolarTerm.on(date: date(1952, 9, 23), calendar: cal), .autumnEquinox)  // 1952 秋分
        XCTAssertEqual(SolarTerm.on(date: date(1952, 10, 8), calendar: cal), .coldDew)  // 1952 寒露
        XCTAssertEqual(SolarTerm.on(date: date(1952, 10, 23), calendar: cal), .frostDescent)  // 1952 霜降
        XCTAssertEqual(SolarTerm.on(date: date(1952, 11, 7), calendar: cal), .winterBegins)  // 1952 立冬
        XCTAssertEqual(SolarTerm.on(date: date(1952, 11, 22), calendar: cal), .minorSnow)  // 1952 小雪
        XCTAssertEqual(SolarTerm.on(date: date(1952, 12, 7), calendar: cal), .majorSnow)  // 1952 大雪
        XCTAssertEqual(SolarTerm.on(date: date(1952, 12, 22), calendar: cal), .winterSolstice)  // 1952 冬至
        // 1988 年
        XCTAssertEqual(SolarTerm.on(date: date(1988, 1, 6), calendar: cal), .minorCold)  // 1988 小寒
        XCTAssertEqual(SolarTerm.on(date: date(1988, 1, 21), calendar: cal), .majorCold)  // 1988 大寒
        XCTAssertEqual(SolarTerm.on(date: date(1988, 2, 4), calendar: cal), .springBegins)  // 1988 立春
        XCTAssertEqual(SolarTerm.on(date: date(1988, 2, 19), calendar: cal), .rainWater)  // 1988 雨水
        XCTAssertEqual(SolarTerm.on(date: date(1988, 3, 5), calendar: cal), .insectsAwaken)  // 1988 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(1988, 3, 20), calendar: cal), .springEquinox)  // 1988 春分
        XCTAssertEqual(SolarTerm.on(date: date(1988, 4, 4), calendar: cal), .qingming)  // 1988 清明
        XCTAssertEqual(SolarTerm.on(date: date(1988, 4, 20), calendar: cal), .grainRain)  // 1988 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(1988, 5, 5), calendar: cal), .summerBegins)  // 1988 立夏
        XCTAssertEqual(SolarTerm.on(date: date(1988, 5, 21), calendar: cal), .grainBuds)  // 1988 小满
        XCTAssertEqual(SolarTerm.on(date: date(1988, 6, 5), calendar: cal), .grainInEar)  // 1988 芒种
        XCTAssertEqual(SolarTerm.on(date: date(1988, 6, 21), calendar: cal), .summerSolstice)  // 1988 夏至
        XCTAssertEqual(SolarTerm.on(date: date(1988, 7, 7), calendar: cal), .minorHeat)  // 1988 小暑
        XCTAssertEqual(SolarTerm.on(date: date(1988, 7, 22), calendar: cal), .majorHeat)  // 1988 大暑
        XCTAssertEqual(SolarTerm.on(date: date(1988, 8, 7), calendar: cal), .autumnBegins)  // 1988 立秋
        XCTAssertEqual(SolarTerm.on(date: date(1988, 8, 23), calendar: cal), .endOfHeat)  // 1988 处暑
        XCTAssertEqual(SolarTerm.on(date: date(1988, 9, 7), calendar: cal), .whiteDew)  // 1988 白露
        XCTAssertEqual(SolarTerm.on(date: date(1988, 9, 23), calendar: cal), .autumnEquinox)  // 1988 秋分
        XCTAssertEqual(SolarTerm.on(date: date(1988, 10, 8), calendar: cal), .coldDew)  // 1988 寒露
        XCTAssertEqual(SolarTerm.on(date: date(1988, 10, 23), calendar: cal), .frostDescent)  // 1988 霜降
        XCTAssertEqual(SolarTerm.on(date: date(1988, 11, 7), calendar: cal), .winterBegins)  // 1988 立冬
        XCTAssertEqual(SolarTerm.on(date: date(1988, 11, 22), calendar: cal), .minorSnow)  // 1988 小雪
        XCTAssertEqual(SolarTerm.on(date: date(1988, 12, 7), calendar: cal), .majorSnow)  // 1988 大雪
        XCTAssertEqual(SolarTerm.on(date: date(1988, 12, 21), calendar: cal), .winterSolstice)  // 1988 冬至
        // 2016 年
        XCTAssertEqual(SolarTerm.on(date: date(2016, 1, 6), calendar: cal), .minorCold)  // 2016 小寒
        XCTAssertEqual(SolarTerm.on(date: date(2016, 1, 20), calendar: cal), .majorCold)  // 2016 大寒
        XCTAssertEqual(SolarTerm.on(date: date(2016, 2, 4), calendar: cal), .springBegins)  // 2016 立春
        XCTAssertEqual(SolarTerm.on(date: date(2016, 2, 19), calendar: cal), .rainWater)  // 2016 雨水
        XCTAssertEqual(SolarTerm.on(date: date(2016, 3, 5), calendar: cal), .insectsAwaken)  // 2016 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(2016, 3, 20), calendar: cal), .springEquinox)  // 2016 春分
        XCTAssertEqual(SolarTerm.on(date: date(2016, 4, 4), calendar: cal), .qingming)  // 2016 清明
        XCTAssertEqual(SolarTerm.on(date: date(2016, 4, 19), calendar: cal), .grainRain)  // 2016 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(2016, 5, 5), calendar: cal), .summerBegins)  // 2016 立夏
        XCTAssertEqual(SolarTerm.on(date: date(2016, 5, 20), calendar: cal), .grainBuds)  // 2016 小满
        XCTAssertEqual(SolarTerm.on(date: date(2016, 6, 5), calendar: cal), .grainInEar)  // 2016 芒种
        XCTAssertEqual(SolarTerm.on(date: date(2016, 6, 21), calendar: cal), .summerSolstice)  // 2016 夏至
        XCTAssertEqual(SolarTerm.on(date: date(2016, 7, 7), calendar: cal), .minorHeat)  // 2016 小暑
        XCTAssertEqual(SolarTerm.on(date: date(2016, 7, 22), calendar: cal), .majorHeat)  // 2016 大暑
        XCTAssertEqual(SolarTerm.on(date: date(2016, 8, 7), calendar: cal), .autumnBegins)  // 2016 立秋
        XCTAssertEqual(SolarTerm.on(date: date(2016, 8, 23), calendar: cal), .endOfHeat)  // 2016 处暑
        XCTAssertEqual(SolarTerm.on(date: date(2016, 9, 7), calendar: cal), .whiteDew)  // 2016 白露
        XCTAssertEqual(SolarTerm.on(date: date(2016, 9, 22), calendar: cal), .autumnEquinox)  // 2016 秋分
        XCTAssertEqual(SolarTerm.on(date: date(2016, 10, 8), calendar: cal), .coldDew)  // 2016 寒露
        XCTAssertEqual(SolarTerm.on(date: date(2016, 10, 23), calendar: cal), .frostDescent)  // 2016 霜降
        XCTAssertEqual(SolarTerm.on(date: date(2016, 11, 7), calendar: cal), .winterBegins)  // 2016 立冬
        XCTAssertEqual(SolarTerm.on(date: date(2016, 11, 22), calendar: cal), .minorSnow)  // 2016 小雪
        XCTAssertEqual(SolarTerm.on(date: date(2016, 12, 7), calendar: cal), .majorSnow)  // 2016 大雪
        XCTAssertEqual(SolarTerm.on(date: date(2016, 12, 21), calendar: cal), .winterSolstice)  // 2016 冬至
        // 2026 年
        XCTAssertEqual(SolarTerm.on(date: date(2026, 1, 5), calendar: cal), .minorCold)  // 2026 小寒
        XCTAssertEqual(SolarTerm.on(date: date(2026, 1, 20), calendar: cal), .majorCold)  // 2026 大寒
        XCTAssertEqual(SolarTerm.on(date: date(2026, 2, 4), calendar: cal), .springBegins)  // 2026 立春
        XCTAssertEqual(SolarTerm.on(date: date(2026, 2, 18), calendar: cal), .rainWater)  // 2026 雨水
        XCTAssertEqual(SolarTerm.on(date: date(2026, 3, 5), calendar: cal), .insectsAwaken)  // 2026 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(2026, 3, 20), calendar: cal), .springEquinox)  // 2026 春分
        XCTAssertEqual(SolarTerm.on(date: date(2026, 4, 5), calendar: cal), .qingming)  // 2026 清明
        XCTAssertEqual(SolarTerm.on(date: date(2026, 4, 20), calendar: cal), .grainRain)  // 2026 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(2026, 5, 5), calendar: cal), .summerBegins)  // 2026 立夏
        XCTAssertEqual(SolarTerm.on(date: date(2026, 5, 21), calendar: cal), .grainBuds)  // 2026 小满
        XCTAssertEqual(SolarTerm.on(date: date(2026, 6, 5), calendar: cal), .grainInEar)  // 2026 芒种
        XCTAssertEqual(SolarTerm.on(date: date(2026, 6, 21), calendar: cal), .summerSolstice)  // 2026 夏至
        XCTAssertEqual(SolarTerm.on(date: date(2026, 7, 7), calendar: cal), .minorHeat)  // 2026 小暑
        XCTAssertEqual(SolarTerm.on(date: date(2026, 7, 23), calendar: cal), .majorHeat)  // 2026 大暑
        XCTAssertEqual(SolarTerm.on(date: date(2026, 8, 7), calendar: cal), .autumnBegins)  // 2026 立秋
        XCTAssertEqual(SolarTerm.on(date: date(2026, 8, 23), calendar: cal), .endOfHeat)  // 2026 处暑
        XCTAssertEqual(SolarTerm.on(date: date(2026, 9, 7), calendar: cal), .whiteDew)  // 2026 白露
        XCTAssertEqual(SolarTerm.on(date: date(2026, 9, 23), calendar: cal), .autumnEquinox)  // 2026 秋分
        XCTAssertEqual(SolarTerm.on(date: date(2026, 10, 8), calendar: cal), .coldDew)  // 2026 寒露
        XCTAssertEqual(SolarTerm.on(date: date(2026, 10, 23), calendar: cal), .frostDescent)  // 2026 霜降
        XCTAssertEqual(SolarTerm.on(date: date(2026, 11, 7), calendar: cal), .winterBegins)  // 2026 立冬
        XCTAssertEqual(SolarTerm.on(date: date(2026, 11, 22), calendar: cal), .minorSnow)  // 2026 小雪
        XCTAssertEqual(SolarTerm.on(date: date(2026, 12, 7), calendar: cal), .majorSnow)  // 2026 大雪
        XCTAssertEqual(SolarTerm.on(date: date(2026, 12, 22), calendar: cal), .winterSolstice)  // 2026 冬至
        // 2088 年
        XCTAssertEqual(SolarTerm.on(date: date(2088, 1, 5), calendar: cal), .minorCold)  // 2088 小寒
        XCTAssertEqual(SolarTerm.on(date: date(2088, 1, 20), calendar: cal), .majorCold)  // 2088 大寒
        XCTAssertEqual(SolarTerm.on(date: date(2088, 2, 4), calendar: cal), .springBegins)  // 2088 立春
        XCTAssertEqual(SolarTerm.on(date: date(2088, 2, 19), calendar: cal), .rainWater)  // 2088 雨水
        XCTAssertEqual(SolarTerm.on(date: date(2088, 3, 4), calendar: cal), .insectsAwaken)  // 2088 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(2088, 3, 19), calendar: cal), .springEquinox)  // 2088 春分
        XCTAssertEqual(SolarTerm.on(date: date(2088, 4, 4), calendar: cal), .qingming)  // 2088 清明
        XCTAssertEqual(SolarTerm.on(date: date(2088, 4, 19), calendar: cal), .grainRain)  // 2088 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(2088, 5, 4), calendar: cal), .summerBegins)  // 2088 立夏
        XCTAssertEqual(SolarTerm.on(date: date(2088, 5, 20), calendar: cal), .grainBuds)  // 2088 小满
        XCTAssertEqual(SolarTerm.on(date: date(2088, 6, 4), calendar: cal), .grainInEar)  // 2088 芒种
        XCTAssertEqual(SolarTerm.on(date: date(2088, 6, 20), calendar: cal), .summerSolstice)  // 2088 夏至
        XCTAssertEqual(SolarTerm.on(date: date(2088, 7, 6), calendar: cal), .minorHeat)  // 2088 小暑
        XCTAssertEqual(SolarTerm.on(date: date(2088, 7, 22), calendar: cal), .majorHeat)  // 2088 大暑
        XCTAssertEqual(SolarTerm.on(date: date(2088, 8, 6), calendar: cal), .autumnBegins)  // 2088 立秋
        XCTAssertEqual(SolarTerm.on(date: date(2088, 8, 22), calendar: cal), .endOfHeat)  // 2088 处暑
        XCTAssertEqual(SolarTerm.on(date: date(2088, 9, 6), calendar: cal), .whiteDew)  // 2088 白露
        XCTAssertEqual(SolarTerm.on(date: date(2088, 9, 22), calendar: cal), .autumnEquinox)  // 2088 秋分
        XCTAssertEqual(SolarTerm.on(date: date(2088, 10, 7), calendar: cal), .coldDew)  // 2088 寒露
        XCTAssertEqual(SolarTerm.on(date: date(2088, 10, 22), calendar: cal), .frostDescent)  // 2088 霜降
        XCTAssertEqual(SolarTerm.on(date: date(2088, 11, 6), calendar: cal), .winterBegins)  // 2088 立冬
        XCTAssertEqual(SolarTerm.on(date: date(2088, 11, 21), calendar: cal), .minorSnow)  // 2088 小雪
        XCTAssertEqual(SolarTerm.on(date: date(2088, 12, 6), calendar: cal), .majorSnow)  // 2088 大雪
        XCTAssertEqual(SolarTerm.on(date: date(2088, 12, 21), calendar: cal), .winterSolstice)  // 2088 冬至
        // 2099 年
        XCTAssertEqual(SolarTerm.on(date: date(2099, 1, 5), calendar: cal), .minorCold)  // 2099 小寒
        XCTAssertEqual(SolarTerm.on(date: date(2099, 1, 20), calendar: cal), .majorCold)  // 2099 大寒
        XCTAssertEqual(SolarTerm.on(date: date(2099, 2, 3), calendar: cal), .springBegins)  // 2099 立春
        XCTAssertEqual(SolarTerm.on(date: date(2099, 2, 18), calendar: cal), .rainWater)  // 2099 雨水
        XCTAssertEqual(SolarTerm.on(date: date(2099, 3, 5), calendar: cal), .insectsAwaken)  // 2099 惊蛰
        XCTAssertEqual(SolarTerm.on(date: date(2099, 3, 20), calendar: cal), .springEquinox)  // 2099 春分
        XCTAssertEqual(SolarTerm.on(date: date(2099, 4, 4), calendar: cal), .qingming)  // 2099 清明
        XCTAssertEqual(SolarTerm.on(date: date(2099, 4, 20), calendar: cal), .grainRain)  // 2099 谷雨
        XCTAssertEqual(SolarTerm.on(date: date(2099, 5, 5), calendar: cal), .summerBegins)  // 2099 立夏
        XCTAssertEqual(SolarTerm.on(date: date(2099, 5, 21), calendar: cal), .grainBuds)  // 2099 小满
        XCTAssertEqual(SolarTerm.on(date: date(2099, 6, 5), calendar: cal), .grainInEar)  // 2099 芒种
        XCTAssertEqual(SolarTerm.on(date: date(2099, 6, 21), calendar: cal), .summerSolstice)  // 2099 夏至
        XCTAssertEqual(SolarTerm.on(date: date(2099, 7, 7), calendar: cal), .minorHeat)  // 2099 小暑
        XCTAssertEqual(SolarTerm.on(date: date(2099, 7, 22), calendar: cal), .majorHeat)  // 2099 大暑
        XCTAssertEqual(SolarTerm.on(date: date(2099, 8, 7), calendar: cal), .autumnBegins)  // 2099 立秋
        XCTAssertEqual(SolarTerm.on(date: date(2099, 8, 23), calendar: cal), .endOfHeat)  // 2099 处暑
        XCTAssertEqual(SolarTerm.on(date: date(2099, 9, 7), calendar: cal), .whiteDew)  // 2099 白露
        XCTAssertEqual(SolarTerm.on(date: date(2099, 9, 23), calendar: cal), .autumnEquinox)  // 2099 秋分
        XCTAssertEqual(SolarTerm.on(date: date(2099, 10, 8), calendar: cal), .coldDew)  // 2099 寒露
        XCTAssertEqual(SolarTerm.on(date: date(2099, 10, 23), calendar: cal), .frostDescent)  // 2099 霜降
        XCTAssertEqual(SolarTerm.on(date: date(2099, 11, 7), calendar: cal), .winterBegins)  // 2099 立冬
        XCTAssertEqual(SolarTerm.on(date: date(2099, 11, 22), calendar: cal), .minorSnow)  // 2099 小雪
        XCTAssertEqual(SolarTerm.on(date: date(2099, 12, 7), calendar: cal), .majorSnow)  // 2099 大雪
        XCTAssertEqual(SolarTerm.on(date: date(2099, 12, 21), calendar: cal), .winterSolstice)  // 2099 冬至
    }
}
