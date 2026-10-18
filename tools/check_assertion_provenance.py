#!/usr/bin/env python3
"""断言来源守卫：测试里出现历法事实字面量时，必须声明它从哪来。

为什么存在：我三次把「猜的」日干支 / 农历日期写进断言，然后让实现去迁就猜测。
这个脚本把那条纪律变成机器拦截——没有合格来源声明的测试函数，提交直接失败。

规则：
- 扫描 Tests/**/*.swift；
- 任一 XCTAssert 行含历法事实（干支、节气、农历月/日、时辰）时，
  该断言所在的测试函数内必须有 `// PROVENANCE: <来源>` 行；
- 来源不能是空话：正文至少 12 个字符，且必须提到一种可复算的方法
  （lunar-python / 锚点 / 对账 / 核对 / 重算 / 推导 / 天文台 / 官方）；
- 缺失或不合格即退出码 1，并列出文件:行号。

配套：`tools/verify_solarterm_assertions.py` 会把节气断言逐条用 lunar-python 重算，
所以 PROVENANCE 里写的「对账」是可复现的，不是自称。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

STEMS = "甲乙丙丁戊己庚辛壬癸"
BRANCHES = "子丑寅卯辰巳午未申酉戌亥"
TERMS = [
    "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
    "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
    "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至",
]
LUNAR_MONTHS = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月",
                "九月", "十月", "冬月", "腊月", "闰月"]
LUNAR_DAYS = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
              "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
              "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]

GANZHI_RE = re.compile(f"[{STEMS}][{BRANCHES}]")
SHICHEN_RE = re.compile(f"[{BRANCHES}]时")
FACT_RE = re.compile("|".join([GANZHI_RE.pattern, SHICHEN_RE.pattern] + TERMS + LUNAR_MONTHS + LUNAR_DAYS))

FUNC_RE = re.compile(r"^\s*(?:public\s+)?func\s+(test\w+)\s*\(")
ASSERT_RE = re.compile(r"XCTAssert")
PROV_RE = re.compile(r"//\s*PROVENANCE:\s*(.*)$")

MIN_PROV_LEN = 12
METHOD_KEYWORDS = ("lunar-python", "锚点", "对账", "核对", "重算", "推导", "天文台", "官方")


def check_file(path: Path) -> list[tuple[int, str, str]]:
    violations: list[tuple[int, str, str]] = []
    current_func = "<file scope>"
    prov_state = "missing"          # missing | weak | ok
    func_facts: list[tuple[int, str]] = []

    def flush() -> None:
        nonlocal func_facts
        if func_facts and prov_state != "ok":
            for line_no, text in func_facts:
                tag = "缺少来源声明" if prov_state == "missing" else "来源声明不合格（需写明可复算的方法）"
                violations.append((line_no, current_func, f"[{tag}] {text}"))
        func_facts = []

    for idx, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        m = FUNC_RE.match(raw)
        if m:
            flush()
            current_func = m.group(1)
            prov_state = "missing"
            continue
        pm = PROV_RE.search(raw)
        if pm:
            body = pm.group(1).strip()
            ok = len(body) >= MIN_PROV_LEN and any(k in body for k in METHOD_KEYWORDS)
            # 同一函数里后写的合格声明可以覆盖前面的空话，但反过来不行
            if ok:
                prov_state = "ok"
            elif prov_state != "ok":
                prov_state = "weak"
            continue
        if ASSERT_RE.search(raw) and FACT_RE.search(raw):
            func_facts.append((idx, raw.strip()))

    flush()
    return violations


def main() -> int:
    # 允许指定目录，便于用「故意违规的样本」验证守卫本身真的会拦（见 --self-test）
    if len(sys.argv) > 2 and sys.argv[1] == "--tests-dir":
        root = Path(sys.argv[2]).resolve()
        tests = root
    else:
        root = Path(__file__).resolve().parents[1]
        tests = root / "Tests"
    files = sorted(tests.rglob("*.swift"))
    if not files:
        print("没有找到测试文件，路径异常", file=sys.stderr)
        return 2

    total = 0
    for f in files:
        for line_no, func, text in check_file(f):
            total += 1
            print(f"{f.relative_to(root)}:{line_no}  [{func}]  {text[:110]}")

    if total:
        print(f"\nFAIL: {total} 条历法事实断言没有合格来源声明。")
        print("在对应测试函数里加一行，写清怎么独立算出来的，例如：")
        print("  // PROVENANCE: lunar-python 1.4.8 逐日 getJieQi 对账，193/193 一致")
        print("  // PROVENANCE: 2000-01-01=戊午 锚点法推导")
        return 1
    print(f"PASS: {len(files)} 个测试文件，历法事实断言均有合格来源声明。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
