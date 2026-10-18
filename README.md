# Soluna Cal（知时日历）

macOS 菜单栏日历：公历、农历、节气、节日、调休色带、放假倒计时、农历生日——点开菜单栏，三秒看清今天。

## 一期功能（V1）

- 菜单栏日期时钟（`10月15日 周四`）
- 月历弹窗：农历小字 / 节日红字 / 节气赭金 / 今日唯一实心高亮
- 调休色带：连续休息整段为一个假期（跨周不断段），**整段只在第一天标一个「休」角标**；补班灰色「班」角标（红休灰班）
- 放假倒计时条
- 农历生日/纪念日（UserDefaults 持久化，iCloud 同步二期开 entitlement）
- 首次引导 3 屏 / 深浅色自适应 / 无 Dock 图标

## 构建与测试

```bash
# 编译
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --disable-sandbox

# 单元测试（48 项：农历换算 / 闰月 / 节气 / 干支时辰 / 节日 / 调休 / 倒计时 / 共享网格）
# 注意：不能用 swift test —— 开源工具链缺 XCTest，必须走 xcodebuild
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -project SolunaCal.xcodeproj -scheme SolunaCal

# 运行（菜单栏出现日期，点开即月历）
.build/debug/SolunaCal
```

## 出包

```bash
tools/make_dmg.sh          # → dist/SolunaCal-<版本>.dmg（双架构 + ad-hoc 签名 + 安装说明）
```

打包前会先跑 `tools/preflight.sh`，任一步失败就不出包：
断言来源守卫 → 节气断言独立对账 → 单元测试。

## 断言来源纪律（已机器化）

历法事实（干支 / 节气 / 农历日 / 时辰）写进测试断言前，必须先用独立方法算出来，
再在同一个测试函数里写明来源：

```swift
func testDayGanzhiToken() {
    // PROVENANCE: lunar-python 1.4.8 核对 2026-10-15 日干支=壬戌
    XCTAssertEqual(MenuBarFormat.render(template: "{GD}", date: date(2026, 10, 15)), "壬戌")
}
```

- `tools/check_assertion_provenance.py`：缺来源、或来源写成空话（少于 12 字、没提可复算方法）→ 退出码 1。
- `tools/verify_solarterm_assertions.py`：把测试里的节气断言逐条用 lunar-python 重算，不是自查自证。
- 启用提交拦截（每个克隆做一次）：`git config core.hooksPath .githooks`

为什么要有这套：曾经三次把「猜的」日干支写进断言，再让实现去迁就猜测——
测试全绿但事实是错的。现在这条纪律不靠记性，靠拦截。


## 结构

```
Sources/LunarCore/          历法引擎（纯 Swift，零依赖）
  LunarCalendar.swift       农历换算 / 节气 / 干支生肖
  Festivals.swift           节日表 + 调休数据层（内置兜底 + 在线刷新）
  Generated/LunarData.swift 数据表（机械生成，勿手改）
Sources/SolunaCal/          菜单栏 App（SwiftUI + AppKit）
Tests/LunarCoreTests/       单元测试
```

## 数据口径

- 历法数据：内置数据表，覆盖 1900–2099
- 调休数据：在线主源 → 本地缓存 → 内置兜底三级；另有校验源对账，通知发布后 48h 内更新是产品承诺
- UI 语义：v3.4 定稿（今日唯一实心 / 假期色带整段单角标 / 红休灰班 / 无格线）
