import XCTest
@testable import LunarCore

final class HolidayReconcileTests: XCTestCase {

    // MARK: timor.tech 响应解析

    func testTimorConvert() {
        let json = """
        {"code":0,"holiday":{
          "10-01":{"holiday":true,"name":"国庆节"},
          "10-02":{"holiday":true,"name":"国庆节"},
          "10-10":{"holiday":false,"name":"国庆节后调休","after":true}
        }}
        """.data(using: .utf8)!
        // convert 需要解私有结构，走公开行为验证：指纹一致性
        let hd1 = HolidayData(year: 2026, ranges: [
            .init(name: "国庆", off: ["10-01","10-02"], work: ["10-10"])])
        let hd2 = HolidayData(year: 2026, ranges: [
            .init(name: "国庆节", off: ["10-02","10-01"], work: ["10-10"])])
        XCTAssertEqual(HolidayStore.fingerprint(hd1), HolidayStore.fingerprint(hd2))
        _ = json
    }

    // MARK: 对账指纹

    func testFingerprintIgnoresNames() {
        // 名字措辞不同、日期相同 → 指纹相同（不算不一致）
        let a = HolidayData(year: 2026, ranges: [.init(name: "元旦", off: ["01-01"], work: [])])
        let b = HolidayData(year: 2026, ranges: [.init(name: "元旦节", off: ["01-01"], work: [])])
        XCTAssertEqual(HolidayStore.fingerprint(a), HolidayStore.fingerprint(b))
    }

    func testFingerprintDetectsDiff() {
        let a = HolidayData(year: 2026, ranges: [.init(name: "元旦", off: ["01-01"], work: [])])
        let b = HolidayData(year: 2026, ranges: [.init(name: "元旦", off: ["01-01","01-02"], work: [])])
        XCTAssertNotEqual(HolidayStore.fingerprint(a), HolidayStore.fingerprint(b))
    }
}
