import XCTest
@testable import LunarCore
@testable import SolunaUI

/// 生日/纪念日匹配：历法（农历/公历）× 周期（每年/每月）× 旧数据兼容
final class BirthdayStoreTests: XCTestCase {
    private var store: BirthdayStore!
    private let cal = Calendar(identifier: .gregorian)

    override func setUp() {
        store = BirthdayStore(persists: false)   // 纯内存，不污染 UserDefaults / iCloud
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func lunar(_ y: Int, _ m: Int, _ d: Int) -> LunarDate {
        LunarCalendar.lunarDate(from: date(y, m, d))
    }

    func testLunarYearly() {
        // 农历八月十五 = 2026-09-25（中秋）
        store.add(.init(name: "甲", lunarMonth: 8, lunarDay: 15))
        XCTAssertNotNil(store.match(date: date(2026, 9, 25), lunar: lunar(2026, 9, 25)))
        XCTAssertNil(store.match(date: date(2026, 9, 26), lunar: lunar(2026, 9, 26)))
    }

    func testSolarYearly() {
        store.add(.init(name: "乙", lunarMonth: 10, lunarDay: 1, calendar: .solar))
        XCTAssertNotNil(store.match(date: date(2026, 10, 1), lunar: lunar(2026, 10, 1)))
        XCTAssertNotNil(store.match(date: date(2027, 10, 1), lunar: lunar(2027, 10, 1)))
        XCTAssertNil(store.match(date: date(2026, 10, 2), lunar: lunar(2026, 10, 2)))
    }

    func testSolarMonthly() {
        store.add(.init(name: "丙", lunarMonth: 3, lunarDay: 15, calendar: .solar, cycle: .monthly))
        // 每月 15 日命中，与月份字段无关
        XCTAssertNotNil(store.match(date: date(2026, 1, 15), lunar: lunar(2026, 1, 15)))
        XCTAssertNotNil(store.match(date: date(2026, 7, 15), lunar: lunar(2026, 7, 15)))
        XCTAssertNil(store.match(date: date(2026, 7, 16), lunar: lunar(2026, 7, 16)))
    }

    func testLunarMonthly() {
        store.add(.init(name: "丁", lunarMonth: 6, lunarDay: 1, cycle: .monthly))
        // 2026-10-10 = 农历九月初一（与录入的六月无关，按月周期命中）
        let d = date(2026, 10, 10)
        XCTAssertEqual(LunarCalendar.lunarDate(from: d).day, 1)
        XCTAssertNotNil(store.match(date: d, lunar: LunarCalendar.lunarDate(from: d)))
    }

    /// v1 旧数据（无 calendar/cycle 字段）必须能解码且默认 = 农历每年
    func testLegacyDecode() throws {
        let json = #"[{"id":"5E8A2C5D-0000-0000-0000-000000000001","name":"妈","lunarMonth":8,"lunarDay":15,"isLeapMonth":false}]"#
        let entries = try JSONDecoder().decode([BirthdayStore.Entry].self, from: Data(json.utf8))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].calendar, .lunar)
        XCTAssertEqual(entries[0].cycle, .yearly)
    }

    // MARK: nextOccurrence（生日看板倒数）

    func testNextOccurrenceToday() {
        // 2026-10-10 = 农历九月初一；当天命中 → 0 天
        store.add(.init(name: "甲", lunarMonth: 9, lunarDay: 1))
        let r = store.nextOccurrence(of: store.entries[0], from: date(2026, 10, 10))
        XCTAssertEqual(r?.days, 0)
        XCTAssertEqual(r?.date, date(2026, 10, 10))
    }

    func testNextOccurrenceFutureLunar() {
        // 2026-10-11 = 农历九月初二；条目九月初三 → 1 天后（2026-10-12）
        store.add(.init(name: "乙", lunarMonth: 9, lunarDay: 3))
        let r = store.nextOccurrence(of: store.entries[0], from: date(2026, 10, 11))
        XCTAssertEqual(r?.days, 1)
        XCTAssertEqual(r?.date, date(2026, 10, 12))
    }

    func testNextOccurrenceSolarYearly() {
        // 公历 1 月 1 日：2026-10-15 起算 → 2027-01-01，共 78 天
        store.add(.init(name: "丙", lunarMonth: 1, lunarDay: 1, calendar: .solar))
        let r = store.nextOccurrence(of: store.entries[0], from: date(2026, 10, 15))
        XCTAssertEqual(r?.date, date(2027, 1, 1))
        XCTAssertEqual(r?.days, 78)
    }

    func testNextOccurrenceMonthly() {
        // 每月农历初一：2026-10-15（九月初六）起算 → 十月初一 = 2026-11-09，25 天
        store.add(.init(name: "丁", lunarMonth: 6, lunarDay: 1, cycle: .monthly))
        let r = store.nextOccurrence(of: store.entries[0], from: date(2026, 10, 15))
        XCTAssertEqual(r?.date, date(2026, 11, 9))
        XCTAssertEqual(r?.days, 25)
    }

    // MARK: 闰月生日（同一闰月间隔 2~19 年，400 天扫描必漏，改按年直查）

    func testNextOccurrenceLeapMonth() {
        // 闰五月初一：2026-10-15 起算 → 2028-06-23（lunar-python 独立核对）
        store.add(.init(name: "闰", lunarMonth: 5, lunarDay: 1, isLeapMonth: true))
        let r = store.nextOccurrence(of: store.entries[0], from: date(2026, 10, 15))
        XCTAssertEqual(r?.date, date(2028, 6, 23))
        // 命中判定自洽：查到的公历日必须能 matches 回来
        XCTAssertTrue(store.matches(store.entries[0], date: date(2028, 6, 23)))
        // 2028-05-24 = 非闰五月初一（lunar-python 核实）→ 不得命中闰五月条目
        XCTAssertFalse(store.matches(store.entries[0], date: date(2028, 5, 24)))
    }

    func testNextOccurrenceLeapMonthPast() {
        // 起算点在闰月之前：2025-06-01 → 2025 闰六月初一 = 2025-07-25（lunar-python 独立核对）
        store.add(.init(name: "闰六", lunarMonth: 6, lunarDay: 1, isLeapMonth: true))
        let r = store.nextOccurrence(of: store.entries[0], from: date(2025, 6, 1))
        XCTAssertEqual(r?.date, date(2025, 7, 25))
        XCTAssertEqual(r?.days, 54)
    }

    // MARK: 同步冲突裁决（PRD：以最新修改为准）

    func testPreferCloudDecision() {
        // 本地无时间戳（旧版本数据）→ 云优先（保持旧行为）
        XCTAssertTrue(BirthdayStore.preferCloud(cloudMTime: 100, localMTime: nil))
        // 云文件时间读不到 → 信本地（本地更新不该被云端旧数据覆盖）
        XCTAssertFalse(BirthdayStore.preferCloud(cloudMTime: nil, localMTime: 100))
        // 云更新 → 云赢；本地更新 → 本地赢（修复前此处恒为云赢 = 本地离线修改丢失）
        XCTAssertTrue(BirthdayStore.preferCloud(cloudMTime: 200, localMTime: 100))
        XCTAssertFalse(BirthdayStore.preferCloud(cloudMTime: 100, localMTime: 200))
        // 相等 → 云优先（内容等价，无实际差异）
        XCTAssertTrue(BirthdayStore.preferCloud(cloudMTime: 100, localMTime: 100))
    }
}
