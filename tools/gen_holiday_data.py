#!/usr/bin/env python3
"""从 timor.tech 年度 JSON 机械生成调休数据（唯一真源 = 下载的 timor JSON）：
1. 更新 data/holidays.json（curated 校验源）
2. 重写 Sources/LunarCore/Festivals.swift 里 BUNDLED-BEGIN/END 之间的内置兜底

用法: python3 tools/gen_holiday_data.py <timor_2026.json> [timor_2027.json ...]
注意：只处理真实抓取的文件；某年 timor 无数据就不要传，由现有兜底保留。
"""
import json, re, sys, pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

# timor 对春节逐日给名（除夕/初一…初七），聚合成「春节」
SPRING_FESTIVAL_DAYS = {"除夕"} | {f"初{c}" for c in "一二三四五六七八九十"}

def norm_name(raw):
    name = re.sub(r"调休|（.*?）", "", raw).strip()
    name = name.replace("后补班", "")
    if name in SPRING_FESTIVAL_DAYS:
        return "春节"
    return name

def parse_timor(fp):
    d = json.load(open(fp))
    assert d.get("code") == 0, f"{fp}: code != 0"
    year = int(d["holiday"][next(iter(d["holiday"]))]["date"][:4]) if d.get("holiday") else None
    by_name = {}
    for md, v in (d.get("holiday") or {}).items():
        if v.get("holiday"):
            name = norm_name(v.get("name", "假期"))
            by_name.setdefault(name, {"off": [], "work": []})["off"].append(md)
        elif v.get("after"):
            name = norm_name(v.get("target") or v.get("name", ""))
            by_name.setdefault(name, {"off": [], "work": []})["work"].append(md)
    ranges = [{"name": k, "off": sorted(v["off"]), "work": sorted(v["work"])}
              for k, v in by_name.items()]
    return {"year": year, "ranges": ranges}

def main():
    entries = [parse_timor(f) for f in sys.argv[1:]]
    assert entries, "至少传一个 timor JSON"
    years = [e["year"] for e in entries]
    assert len(set(years)) == len(years), "年份重复"

    # 1) curated data/holidays.json：与现有条目按年合并（新数据覆盖同年）
    dp = ROOT / "data" / "holidays.json"
    existing = json.load(open(dp)) if dp.exists() else []
    merged = {e["year"]: e for e in existing}
    for e in entries:
        merged[e["year"]] = e
    out = [merged[y] for y in sorted(merged)]
    dp.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
    print(f"curated 更新: {dp} 年份={[e['year'] for e in out]}")

    # 2) Festivals.swift 内置兜底：只重写标记区
    sp = ROOT / "Sources" / "LunarCore" / "Festivals.swift"
    src = sp.read_text()
    blocks = []
    for e in entries:
        lines = [f"        HolidayData(year: {e['year']}, ranges: ["]
        for r in e["ranges"]:
            off = ",".join(f'"{d}"' for d in r["off"])
            work = ",".join(f'"{d}"' for d in r["work"])
            lines.append(f'            .init(name: "{r["name"]}", off: [{off}], work: [{work}]),')
        lines.append("        ]),")
        blocks.append("\n".join(lines))
    body = "\n".join(blocks)
    pat = re.compile(r"(// BUNDLED-BEGIN.*?)\n.*?\n(\s*// BUNDLED-END)", re.S)
    assert pat.search(src), "Festivals.swift 缺 BUNDLED 标记"
    src2 = pat.sub(lambda m: m.group(1) + "\n" + body + "\n" + m.group(2), src)
    assert src2 != src
    sp.write_text(src2)
    print(f"bundled 更新: {sp} 年份={years}")

if __name__ == "__main__":
    main()
