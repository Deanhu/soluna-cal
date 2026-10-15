import XCTest
@testable import LunarCore

final class LunarCoreTests: XCTestCase {
    private var cal = Calendar(identifier: .gregorian)

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return cal.date(from: c)!
    }

    // MARK: 农历换算（基准点为已知公农历对照）

    func testEpoch() {
        let l = LunarCalendar.lunarDate(from: date(1900, 1, 31))
        XCTAssertEqual(l, LunarDate(year: 1900, month: 1, day: 1, isLeapMonth: false))
    }

    /// 边界安全版：范围外返回 nil 而不是崩溃（翻页边界格/远未来扫描走这条路）
    func testLunarDateOrNilBounds() {
        // 范围内
        XCTAssertNotNil(LunarCalendar.lunarDateOrNil(from: date(2026, 10, 15)))
        // 范围上界内：2099 年末
        XCTAssertNotNil(LunarCalendar.lunarDateOrNil(from: date(2099, 12, 31)))
        // 范围外：1900-01-31（epoch）之前、农历 2099 年末之后的公历日
        XCTAssertNil(LunarCalendar.lunarDateOrNil(from: date(1900, 1, 30)))
        XCTAssertNil(LunarCalendar.lunarDateOrNil(from: date(2100, 6, 15)))
        // 支持区间声明与数据表一致
        XCTAssertEqual(LunarCalendar.supportedRange, 1900...2099)
    }

    func testKnownDates() {
        // 2026-10-14 = 九月初五
        let l1 = LunarCalendar.lunarDate(from: date(2026, 10, 14))
        XCTAssertEqual(l1, LunarDate(year: 2026, month: 9, day: 5, isLeapMonth: false))
        // 2026 春节 = 2-17
        let l2 = LunarCalendar.lunarDate(from: date(2026, 2, 17))
        XCTAssertEqual(l2, LunarDate(year: 2026, month: 1, day: 1, isLeapMonth: false))
        // 2025 春节 = 1-29
        let l3 = LunarCalendar.lunarDate(from: date(2025, 1, 29))
        XCTAssertEqual(l3, LunarDate(year: 2025, month: 1, day: 1, isLeapMonth: false))
    }

    func testLeapMonth() {
        // 2025 闰六月
        XCTAssertEqual(LunarCalendar.leapMonth(of: 2025), 6)
        XCTAssertEqual(LunarCalendar.leapMonth(of: 2026), 0)
        // 2025-07-25 = 闰六月初一
        let l = LunarCalendar.lunarDate(from: date(2025, 7, 25))
        XCTAssertEqual(l, LunarDate(year: 2025, month: 6, day: 1, isLeapMonth: true))
    }

    func testRoundTrip() {
        for (y, m, d) in [(2026,10,14), (2025,7,25), (2000,1,1), (2049,12,31), (1900,2,1)] {
            let solar = date(y, m, d)
            let lunar = LunarCalendar.lunarDate(from: solar)
            XCTAssertEqual(LunarCalendar.solarDate(from: lunar), solar, "\(y)-\(m)-\(d)")
        }
    }

    // MARK: 节气

    func testSolarTerms() {
        // 2026 寒露 = 10-08，霜降 = 10-23，冬至 = 12-22
        XCTAssertEqual(cal.component(.day, from: SolarTerm.coldDew.day(in: 2026)), 8)
        XCTAssertEqual(cal.component(.day, from: SolarTerm.frostDescent.day(in: 2026)), 23)
        XCTAssertEqual(cal.component(.day, from: SolarTerm.winterSolstice.day(in: 2026)), 22)
        XCTAssertEqual(SolarTerm.on(date: date(2026, 10, 8), calendar: cal), .coldDew)
        XCTAssertNil(SolarTerm.on(date: date(2026, 10, 9), calendar: cal))
    }

    // MARK: 干支

    func testGanzhi() {
        XCTAssertEqual(Ganzhi.year(2026), "丙午")
        XCTAssertEqual(Ganzhi.animal(2026), "马")
        XCTAssertEqual(Ganzhi.year(1984), "甲子")
    }

    // MARK: 节日

    func testFestivals() {
        XCTAssertEqual(Festival.solarFestival(month: 10, day: 1), "国庆")
        XCTAssertEqual(Festival.lunarFestival(of: LunarDate(year: 2026, month: 9, day: 9, isLeapMonth: false)), "重阳")
        // 除夕：2026 腊月大，除夕=腊月三十=2027-02-05
        let chuxi = LunarCalendar.lunarDate(from: date(2027, 2, 5))
        XCTAssertEqual(Festival.lunarFestival(of: chuxi), "除夕")
    }

    // MARK: 调休状态

    func testHolidayStatus() {
        HolidayStore.calendar = cal
        XCTAssertEqual(HolidayStore.status(on: date(2026, 10, 1)), .off("国庆节"))
        XCTAssertEqual(HolidayStore.status(on: date(2026, 10, 10)), .work("国庆节"))
        XCTAssertEqual(HolidayStore.status(on: date(2026, 10, 14)), .normal)
        XCTAssertEqual(HolidayStore.status(on: date(2026, 10, 18)), .weekend)
    }

    func testNextHoliday() {
        HolidayStore.calendar = cal
        // 2026-09-25 → 国庆节 还有 6 天（中秋 9/25 当天已开始，取段首比较自然跳过）
        let n = HolidayStore.nextHoliday(after: date(2026, 9, 25))
        XCTAssertEqual(n?.name, "国庆节")
        XCTAssertEqual(n?.days, 6)
        // 跨年：年内假期过完后落到次年元旦兜底
        let n2 = HolidayStore.nextHoliday(after: date(2026, 10, 14))
        XCTAssertEqual(n2?.name, "元旦")
        XCTAssertEqual(n2?.days, 79)
    }
}
