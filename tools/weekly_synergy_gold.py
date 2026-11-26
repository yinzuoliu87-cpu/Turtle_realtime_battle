"""weekly_synergy_gold.py —— 本周羁绊(16 抽 10)的独立 Python 实现, 算金标给 verify_weekly_synergy 比(方案书 20261124d §6)。

  python tools/weekly_synergy_gold.py          # 重写 tests/golden/weekly_synergy.json(2026-11-30 起 104 周)

与 scripts/gamedata/weekly_synergy.gd 各写各的: 排序键 = FNV-1a 32 位("周锚点|羁绊名" 的 UTF-8 字节), 同键按名字码点比, 取前 10。
"""
import calendar, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALL = ["剑", "盾", "枪", "弓箭", "法器", "灵物", "奇械", "食物", "遗物", "药水", "匕首", "魔法书", "面具", "筹码", "炸弹", "长矛"]


def fnv(s):
    h = 2166136261
    for b in s.encode("utf-8"):
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


LAUNCH = calendar.timegm((2026, 11, 30, 0, 0, 0))   # 上线那一周保底 6 个新羁绊(11-27), 另 4 个从老羁绊里按同一排序取
NEW = ["匕首", "魔法书", "面具", "筹码", "炸弹", "长矛"]


def week(anchor):
    if anchor == LAUNCH:
        return NEW + [t for _, t in sorted((fnv("%d|%s" % (anchor, t)), t) for t in ALL if t not in NEW)][:4]
    return [t for _, t in sorted((fnv("%d|%s" % (anchor, t)), t) for t in ALL)][:10]


def main():
    start = calendar.timegm((2026, 11, 30, 0, 0, 0))
    out = {str(start + 7 * 86400 * i): week(start + 7 * 86400 * i) for i in range(104)}
    p = os.path.join(ROOT, "tests", "golden", "weekly_synergy.json")
    open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(out, ensure_ascii=False, indent=1) + "\n")
    sys.stdout.reconfigure(encoding="utf-8")
    print("写入 %d 周 · 第一周 %d: %s" % (len(out), start, "、".join(week(start))))


if __name__ == "__main__":
    main()
