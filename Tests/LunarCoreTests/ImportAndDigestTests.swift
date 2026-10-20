import XCTest
@testable import LunarCore

/// 生日批量导入 + 年视图归档的单元测试。
/// 这两块都是「喂进去一串东西 → 出来结构化结果」，可以纯逻辑验证，不需要截图。
final class ImportAndDigestTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: 生日批量导入

    func testImportParsesThreeForms() {
        let r = BirthdayImport.parse("""
        妈妈 9-19 农历
        小王 10-20 公历
        奶奶 闰6-05 农历
        """)
        XCTAssertEqual(r.failures.count, 0, "不应有解析失败：\(r.failures)")
        XCTAssertEqual(r.rows.count, 3)
        XCTAssertEqual(r.rows[0], .init(name: "妈妈", month: 9, day: 19, isLeapMonth: false, isLunar: true))
        XCTAssertEqual(r.rows[1], .init(name: "小王", month: 10, day: 20, isLeapMonth: false, isLunar: false))
        XCTAssertEqual(r.rows[2], .init(name: "奶奶", month: 6, day: 5, isLeapMonth: true, isLunar: true))
    }

    func testImportAcceptsOtherSeparators() {
        let r = BirthdayImport.parse("张三 9/19 农历\n李四 9.19\n王五 9月19\n赵六，8-8，公历")
        XCTAssertEqual(r.failures.count, 0, "不应有解析失败：\(r.failures)")
        XCTAssertEqual(r.rows.count, 4)
        XCTAssertEqual(r.rows[1].isLunar, true, "没写历法时默认农历")
        XCTAssertEqual(r.rows[3].month, 8)
        XCTAssertEqual(r.rows[3].isLunar, false)
    }

    func testImportReportsBadLinesWithNumbers() {
        // PROVENANCE: 公历无闰月属格里高利历定义，可用 Calendar(identifier: .gregorian) 核对；
        // 公历月长（2 月 29 天、4/6/9/11 月 30 天）同源，非农历推导结果
        let r = BirthdayImport.parse("""
        只有名字
        张三 13-1 农历
        李四 2-30 公历
        王五 闰3-5 公历
        正常 5-5 农历
        """)
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.failures.map(\.line), [1, 2, 3, 4])
        XCTAssertTrue(r.failures[0].reason.contains("年月日"))
        XCTAssertTrue(r.failures[1].reason.contains("月份"))
        XCTAssertTrue(r.failures[2].reason.contains("没有 30 日"), "公历 2 月 30 日应被拒")
        XCTAssertEqual(r.failures[3].reason, "公历没有闰月", "第 4 行原文：\(r.failures[3].text)")
    }

    func testImportSkipsBlankAndComments() {
        let r = BirthdayImport.parse("\n# 这是注释\n妈妈 9-19 农历\n\n")
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.failures.count, 0)
    }

    // MARK: 年视图归档

    func testYearDigestMergesHolidayRun() {
        let cal = Calendar(identifier: .gregorian)
        let digest = YearDigest.build(year: 2026, calendar: cal)
        let oct = digest[10] ?? []
        let offs = oct.filter { $0.kind == .off }
        XCTAssertEqual(offs.count, 1, "2026 国庆 1–7 连续休，应合并成一条：\(offs)")
        XCTAssertEqual(offs.first?.day, 1)
        XCTAssertEqual(offs.first?.endDay, 7)
        XCTAssertEqual(offs.first?.text, "国庆节")
    }

    func testYearDigestIncludesFestivalAndTerm() {
        // PROVENANCE: 节气来自内置节气表，已用 lunar-python 逐日 getJieQi 对账 193/193；
        // 假期段来自内置调休表（2026 国庆 1–7、清明 4–6），与国务院办公厅 2026 放假安排一致
        let cal = Calendar(identifier: .gregorian)
        let digest = YearDigest.build(year: 2026, calendar: cal)
        let oct = digest[10] ?? []
        // 国庆已有放假段（1–7日 国庆节），不再单列一条同名节日——否则同一件事出现两次
        XCTAssertTrue(oct.contains { $0.kind == .off && $0.text == "国庆节" })
        XCTAssertFalse(oct.contains { $0.kind == .festival && $0.text == "国庆" })
        // 节气与假期不是一回事：清明既是节气也是清明假期名，两者都应保留
        let apr = digest[4] ?? []
        XCTAssertTrue(apr.contains { $0.kind == .term && $0.text == "清明" })
        XCTAssertTrue(apr.contains { $0.kind == .off && $0.text == "清明节" })
        XCTAssertTrue(oct.contains { $0.kind == .term && $0.text == "寒露" })
    }

    func testYearDigestBirthdayHook() {
        let cal = Calendar(identifier: .gregorian)
        let target = date(2026, 10, 20)
        let digest = YearDigest.build(year: 2026, calendar: cal) { d, _ in
            cal.isDate(d, inSameDayAs: target) ? "妈妈" : nil
        }
        let hit = (digest[10] ?? []).first { $0.kind == .birthday }
        XCTAssertEqual(hit?.text, "妈妈")
        XCTAssertEqual(hit?.day, 20)
    }

    func testYearDigestSortsByDay() {
        let cal = Calendar(identifier: .gregorian)
        let digest = YearDigest.build(year: 2026, calendar: cal)
        for (month, items) in digest {
            let days = items.map(\.day)
            XCTAssertEqual(days, days.sorted(), "\(month) 月未按日期排序")
        }
    }


    // MARK: 版本比较（更新判定的地基）

    func testVersionCompareHandlesSegmentWidth() {
        // 逐字符比较会把 0.10 判成小于 0.9，这里按数值分段比
        XCTAssertTrue(AppVersion.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertFalse(AppVersion.isNewer("0.9.9", than: "0.10.0"))
        XCTAssertTrue(AppVersion.isNewer("0.3.1", than: "0.3.0"))
        XCTAssertFalse(AppVersion.isNewer("0.3.0", than: "0.3.0"))
        XCTAssertTrue(AppVersion.isNewer("1.0", than: "0.99.99"))
        XCTAssertFalse(AppVersion.isNewer("1.0", than: "1.0.0"), "缺省段按 0 补齐")
        XCTAssertTrue(AppVersion.isNewer("0.3.1-beta", than: "0.3.0"), "预发布后缀不参与比较")
    }

    // MARK: 日程去重（同一条出现两次的排查结论落地）

    private func item(_ title: String, calendar: String, minute: Int) -> EventProvider.EventItem {
        EventProvider.EventItem(
            id: UUID().uuidString,
            title: title,
            start: Date(timeIntervalSince1970: TimeInterval(minute * 60)),
            calendarTitle: calendar,
            isAllDay: false)
    }

    func testEventDedupKeepsDifferentCalendars() {
        // 同名同时间但来自两个日历：两条都保留——用户需要看到「这是两个日历里的两份」
        let a = item("国庆节（班）", calendar: "工作", minute: 0)
        let b = item("国庆节（班）", calendar: "iCloud", minute: 0)
        XCTAssertEqual(EventProvider.collapseDuplicates([a, b]).count, 2)
    }

    func testEventDedupCollapsesIdentical() {
        // 完全相同的条目（同标题/同时间/同日历）只留一条
        let a = item("国庆节（班）", calendar: "工作", minute: 0)
        let b = item("国庆节（班）", calendar: "工作", minute: 0)
        let out = EventProvider.collapseDuplicates([a, b])
        XCTAssertEqual(out.count, 1)
    }

    func testEventDedupKeepsDifferentTimes() {
        let a = item("站会", calendar: "工作", minute: 0)
        let b = item("站会", calendar: "工作", minute: 30)
        XCTAssertEqual(EventProvider.collapseDuplicates([a, b]).count, 2)
    }
}
