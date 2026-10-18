#!/usr/bin/env python3
"""用独立历法库（lunar-python）反向核对测试里的节气断言。

为什么需要这个脚本：
    测试断言如果由实现自己"生成"，那它只能证明实现没变，不能证明实现是对的。
    这个脚本把 Tests/ 里写死的节气断言逐条抽出来，用另一套历法实现重算一遍，
    不一致就报错。这样"断言正确"才有独立来源，而不是我的记忆或猜测。

依赖：
    lunar-python（纯 Python，无需编译）。本机装在
    .workbuddy-ai/scratch/lunar_pkg/lunar_python-<ver>/ 下，用 PYTHONPATH 引入。
    找不到时脚本会明确提示，不会静默跳过。

用法：
    python3 tools/verify_solarterm_assertions.py
退出码 0 = 全部一致；1 = 有不一致或无法核对。
"""

from __future__ import annotations

import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent
TESTS = REPO / "Tests"

# 节气枚举名 → lunar-python 的节气名
TERM_NAMES = {
    "minorCold": "小寒", "majorCold": "大寒", "springBegins": "立春", "rainWater": "雨水",
    "insectsAwaken": "惊蛰", "springEquinox": "春分", "qingming": "清明", "grainRain": "谷雨",
    "summerBegins": "立夏", "grainBuds": "小满", "grainInEar": "芒种", "summerSolstice": "夏至",
    "minorHeat": "小暑", "majorHeat": "大暑", "autumnBegins": "立秋", "endOfHeat": "处暑",
    "whiteDew": "白露", "autumnEquinox": "秋分", "coldDew": "寒露", "frostDescent": "霜降",
    "winterBegins": "立冬", "minorSnow": "小雪", "majorSnow": "大雪", "winterSolstice": "冬至",
}

PATTERN = re.compile(
    r"XCTAssertEqual\(\s*SolarTerm\.on\(date:\s*date\((\d+),\s*(\d+),\s*(\d+)\),\s*calendar:\s*cal\)\s*,"
    r"\s*\.([A-Za-z]+)\s*\)"
)


def load_lunar():
    try:
        from lunar_python import Solar  # type: ignore
        return Solar
    except ModuleNotFoundError:
        pass
    # 退回到工作区里的解包副本（不写系统临时目录）
    for cand in sorted((REPO / ".workbuddy-ai" / "scratch" / "lunar_pkg").glob("lunar_python-*")):
        if cand.is_dir():
            sys.path.insert(0, str(cand))
            try:
                from lunar_python import Solar  # type: ignore
                return Solar
            except ModuleNotFoundError:
                sys.path.pop(0)
    print("FAIL: 找不到 lunar-python，无法做独立核对（拒绝静默跳过）")
    print("  安装：TMPDIR=<工作区内目录> pip install lunar_python")
    print("  或解包到 .workbuddy-ai/scratch/lunar_pkg/lunar_python-<ver>/")
    raise SystemExit(1)


def main() -> int:
    Solar = load_lunar()

    cases: list[tuple[str, int, tuple[int, int, int], str]] = []
    for path in sorted(TESTS.rglob("*.swift")):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            m = PATTERN.search(line)
            if not m:
                continue
            y, mo, d, enum = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
            if enum not in TERM_NAMES:
                continue
            cases.append((f"{path.relative_to(REPO)}:{lineno}", (y, mo, d), enum))

    if not cases:
        print("FAIL: 一条节气断言都没抽到，正则或测试结构变了")
        return 1

    bad: list[str] = []
    for where, (y, mo, d), enum in cases:
        lunar = Solar.fromYmd(y, mo, d).getLunar()
        actual = lunar.getJieQi() or ""          # 当天恰为节气则返回节气名
        expect = TERM_NAMES[enum]
        if actual != expect:
            bad.append(f"{where}  {y}-{mo:02d}-{d:02d} 断言={expect} 独立库={actual or '（当天无节气）'}")

    print(f"抽出节气断言 {len(cases)} 条，逐条用 lunar-python 重算。")
    if bad:
        print(f"FAIL: {len(bad)} 条不一致：")
        for b in bad[:40]:
            print("  " + b)
        if len(bad) > 40:
            print(f"  …另有 {len(bad) - 40} 条")
        return 1
    print(f"PASS: {len(cases)}/{len(cases)} 条与独立历法库一致。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
