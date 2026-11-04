# -*- coding: utf-8 -*-
"""equip_budget_audit.py — 装备属性预算：按「费用 × 星级」分档，属性总量偏离本档太多的要进台账写理由。

★由来（2026-11-04，方案书 docs/plans/20261102b-参考黑箱学AI开发方式.md A3，Issue #3）：
  学《黑箱：无限构筑》的数值做法 —— 它让 Agent 批量给参数，平衡问题自己没解决；
  我们反过来把「每件装备的属性该在什么量级」写成会红的门禁，新装备 / 改数值时自动比同档。

★怎么算（全部从数据里量，不手拍权重）：
  1. 属性来自事实源 `EquipStats.STATS`（复用 tools/basestats_audit.py 的 code_stats()，那边有分母断言）。
  2. 每种属性的「一份」= 全部装备里该属性 1 星值的中位数（例：生命一份 ≈ 100、攻击一份 ≈ 15）。
  3. 一件装备某星级的属性分 = Σ 属性值 / 该属性的一份。
  4. 本档预算 = 同费用同星级全部装备属性分的中位数。比值 = 属性分 / 本档预算。
  5. 比值 > HIGH 或 < LOW ⇒ 必须在 LEDGER 里有一条写明理由；没有 ⇒ 红。台账里某条已经不越界了 ⇒ 也红（台账只减不增）。
  另守：每件装备每项属性 1 星 ≤ 2 星 ≤ 3 星（倒挂 = 笔误）。
★只管属性：装备效果的强弱不在这里（效果型装备属性故意低，见台账）。

  python tools/equip_budget_audit.py          # ALL OK / FAILED
  python tools/equip_budget_audit.py --table  # 另打每件装备每星的比值（调数值时看）
"""
import io, json, os, statistics, sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))
from basestats_audit import code_stats  # noqa: E402

HIGH = 2.5
LOW = 0.3
## 越界台账：(装备, 星级) → 理由。「用户 11-04 确认有意」= 11-04 报给用户、用户原话「三件装备的数值像是有意设计的」。
LEDGER = {
    ("p2eq_043", 3): "用户 11-04 确认有意：海浪护符（4 费）3 星生命 5000，是 4 费里唯一跳到 5 费 3 星量级的",
    ("p2eq_017", 3): "用户 11-04 确认有意：不沉之锚（5 费）3 星生命 4000 + 双抗 150，在本来就跳档的 5 费 3 星里还高 2.6 倍（坦克定位）",
    ("p2eq_011", 1): "用户 11-04 确认有意（属性型）：饮血护符坠四条属性全给（攻 / 吸血 / 治疗增幅 / 盾增），效果只有法力满连斩",
    ("p2eq_011", 2): "同上（饮血护符坠 2 星）",
    ("p2eq_011", 3): "同上（饮血护符坠 3 星）",
    ("p2eq_038", 3): "效果型（推断）：信号放大器强度在效果里，属性故意低",
    ("p2eq_032", 2): "效果型（推断）：唤灵骨符强度在召唤效果里，属性故意低",
    ("p2eq_032", 3): "同上（唤灵骨符 3 星）",
    ("p2eq_033", 1): "效果型（推断）：复活海螺强度在复活效果里，属性故意低",
}


def main():
    table = "--table" in sys.argv[1:]
    stats = code_stats()
    eq = json.load(io.open("data/phase2-equipment.json", encoding="utf-8"))
    eq = eq.get("equipment") if isinstance(eq, dict) else eq
    cost = {str(e["id"]): int(e.get("cost", 0)) for e in eq}
    fails = []
    print("[分母] 属性表解析到 %d 件（每件 3 星）· 数据表 %d 件" % (len(stats), len(cost)))
    if len(stats) != len(cost) or set(stats) != set(cost):
        fails.append("属性表与数据表的装备集合不一致：只在属性表 %s / 只在数据表 %s"
                     % (sorted(set(stats) - set(cost))[:5], sorted(set(cost) - set(stats))[:5]))
    ## 单调：1 星 ≤ 2 星 ≤ 3 星
    n_mono = 0
    for iid, sts in stats.items():
        for k in set().union(*sts):
            a, b, c = (s.get(k, 0.0) for s in sts)
            n_mono += 1
            if not (a <= b <= c):
                fails.append("%s %s 星级倒挂 %s / %s / %s" % (iid, k, a, b, c))
    print("[分母] 单调检查 %d 条（装备 × 属性）" % n_mono)
    ## 每种属性的「一份」
    keys = sorted(set(k for sts in stats.values() for s in sts for k in s))
    unit = {}
    for k in keys:
        vals = [sts[0][k] for sts in stats.values() if sts[0].get(k, 0.0) > 0]
        if not vals:
            vals = [s[k] for sts in stats.values() for s in sts if s.get(k, 0.0) > 0]
        unit[k] = statistics.median(vals)
    print("[量] 每种属性的一份（1 星中位数）：" + "、".join("%s %g" % (k, unit[k]) for k in keys))
    score = {iid: [sum(v / unit[k] for k, v in s.items() if v > 0) for s in sts] for iid, sts in stats.items()}
    groups = {}
    for iid, sc in score.items():
        if iid not in cost:
            continue
        for st in range(3):
            groups.setdefault((cost[iid], st), []).append(sc[st])
    budget = {g: statistics.median(v) for g, v in groups.items()}
    print("[量] 各档预算（属性分中位数）：" + "  ".join("%d费%d星 %.2f(%d件)" % (c, s + 1, budget[(c, s)], len(groups[(c, s)]))
                                                for c, s in sorted(budget)))
    hit = {}
    n_cmp = 0
    for iid, sc in sorted(score.items()):
        if iid not in cost:
            continue
        for st in range(3):
            g = (cost[iid], st)
            if len(groups[g]) < 3:
                continue   # 同档不到 3 件（0 费只有 1 件）不比
            n_cmp += 1
            r = sc[st] / budget[g] if budget[g] > 0 else 0.0
            if table:
                print("  %s %d费 %d星 属性分 %.2f 比值 %.2f" % (iid, cost[iid], st + 1, sc[st], r))
            if r > HIGH or (sc[st] > 0 and r < LOW):
                hit[(iid, st + 1)] = r
    print("[分母] 比过 %d 个「装备 × 星级」，越界 %d 个（> %.1f 倍或 < %.1f 倍本档中位数）" % (n_cmp, len(hit), HIGH, LOW))
    for key, r in sorted(hit.items()):
        if key in LEDGER:
            print("  台账 %s %d星 比值 %.2f —— %s" % (key[0], key[1], r, LEDGER[key]))
        else:
            fails.append("%s %d 星属性分是本档中位数的 %.2f 倍 —— 是笔误就改 STATS；有意就进 LEDGER 写理由" % (key[0], key[1], r))
    for key in sorted(LEDGER):
        if key not in hit:
            fails.append("台账 %s %d 星已经不越界了 —— 删掉这条（台账只减不增）" % key)
    if n_cmp < 200:
        fails.append("比过的只有 %d 个（< 200）—— 解析或分档出问题了" % n_cmp)
    if fails:
        for f in fails:
            print("[FAIL] " + f)
        print("\nFAILED: %d 处" % len(fails))
        return 1
    print("\nALL OK —— 装备属性预算：%d 个越界全在台账里，单调 %d 条无倒挂" % (len(hit), n_mono))
    return 0


if __name__ == "__main__":
    sys.exit(main())
