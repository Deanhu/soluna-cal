import XCTest
@testable import LunarCore

final class HolidayReconcileTests: XCTestCase {

    // MARK: timor.tech 响应解析

    func testTimorConvert() {
        // convert 直接驱动真实解码路径：补班名必须取 target（而非「国庆节后补班」）
        let json = """
        {"code":0,"holiday":{
          "10-01":{"holiday":true,"name":"国庆节"},
          "10-02":{"holiday":true,"name":"国庆节"},
          "10-10":{"holiday":false,"name":"国庆节后补班","after":true,"target":"国庆节"}
        }}
        """.data(using: .utf8)!
        let resp = try! JSONDecoder().decode(HolidayStore.TimorResponse.self, from: json)
        let hd = HolidayStore.convert(timor: resp, year: 2026)
        XCTAssertEqual(hd.ranges.count, 1)
        XCTAssertEqual(hd.ranges[0].name, "国庆节")
        XCTAssertEqual(hd.ranges[0].off, ["10-01", "10-02"])
        XCTAssertEqual(hd.ranges[0].work, ["10-10"])

        // 指纹一致性：名字措辞不同不构成不一致
        let hd1 = HolidayData(year: 2026, ranges: [
            .init(name: "国庆", off: ["10-01","10-02"], work: ["10-10"])])
        XCTAssertEqual(HolidayStore.fingerprint(hd), HolidayStore.fingerprint(hd1))
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
