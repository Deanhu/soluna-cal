# Soluna Cal（知时日历）

macOS 菜单栏日历：公历、农历、节气、节日、调休色带、放假倒计时、农历生日——点开菜单栏，三秒看清今天。

## 一期功能（V1）

- 菜单栏日期时钟（`10月15日 周四`）
- 月历弹窗：农历小字 / 节日红字 / 节气赭金 / 今日唯一实心高亮
- 调休色带：假期连续浅红色带 + 段首「休」角标；补班灰色「班」角标（红休灰班）
- 放假倒计时条
- 农历生日/纪念日（UserDefaults 持久化，iCloud 同步二期开 entitlement）
- 首次引导 3 屏 / 深浅色自适应 / 无 Dock 图标

## 构建与测试

```bash
# 编译
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --disable-sandbox

# 单元测试（历法引擎 9 项：农历换算/闰月/节气/干支/节日/调休/倒计时）
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox

# 运行（菜单栏出现日期，点开即月历）
.build/debug/SolunaCal
```

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
- 调休数据：`Festivals.swift` 内置 2026 年为兜底；在线数据源 URL 待定（`HolidayStore.remoteURL`），通知发布后 48h 内更新是产品承诺
- UI 语义：v3.4 定稿（今日唯一实心 / 假期色带段首单角标 / 红休灰班 / 无格线）

