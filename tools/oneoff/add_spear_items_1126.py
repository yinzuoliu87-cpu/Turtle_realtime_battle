"""add_spear_items_1126.py —— 长矛羁绊 10 件新装备进数据表 + 接线(方案书 docs/plans/20261126-长矛羁绊.md §4)

  python tools/oneoff/add_spear_items_1126.py      # 幂等: 已有同 id 就覆盖那一条; 接线已接过就跳过

写: data/phase2-equipment.json · data/p2eq-types.json · scripts/gamedata/equip_stats.gd(STATS) · b4_owner.gd · equip_system.gd · battle_damage.gd(142 正面减伤)。
文案体例同面具批(写「攻击」不写普攻、不写码数、不用分号、百分比生命写明是谁的、不写「携带者」)。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
E = "EqSpearBatch"


def c(n):
    return "{C:%s.%s}" % (E, n)


def cp(n):
    return "{C:%s.%s%%}%%" % (E, n)


ITEMS = [
    ("p2eq_137", "竹矛", 1, "+攻6/12/20·龟能回复4/6/10%",
     [{"atk": 6, "_echargePct": 4}, {"atk": 12, "_echargePct": 6}, {"atk": 20, "_echargePct": 10}],
     "每第 %s 次攻击刺穿目标，目标身后的一名敌人受到 %s 攻击力的物理伤害。" % (c("BAMBOO_EVERY"), cp("BAMBOO_PCT")),
     "每第三次攻击刺穿目标，伤到身后的敌人。"),
    ("p2eq_138", "鱼叉", 1, "+生命80/160/300·龟能回复4/6/10%",
     [{"hp": 80, "_echargePct": 4}, {"hp": 160, "_echargePct": 6}, {"hp": 300, "_echargePct": 10}],
     "攻击给目标挂上倒钩，持续 %s 秒。挂着倒钩的敌人每移动一段距离，受到 %s 物理伤害。" % (c("BARB_SEC"), c("BARB_PER_100")),
     "攻击挂上倒钩，敌人越跑越疼。"),
    ("p2eq_139", "标枪", 2, "+攻14/30/50·龟能回复5/8/12%",
     [{"atk": 14, "_echargePct": 5}, {"atk": 30, "_echargePct": 8}, {"atk": 50, "_echargePct": 12}],
     "每 %s 秒向最远的敌人掷出一根标枪，造成 %s 攻击力的物理伤害，并使其移动速度降低 %s，持续 %s 秒。"
     % (c("JAV_IV"), cp("JAV_PCT"), cp("JAV_SLOW"), c("JAV_SLOW_SEC")),
     "定时向最远的敌人掷出标枪并减速。"),
    ("p2eq_140", "骑枪", 2, "+生命100/200/380·龟能回复5/8/12%",
     [{"hp": 100, "_echargePct": 5}, {"hp": 200, "_echargePct": 8}, {"hp": 380, "_echargePct": 12}],
     "【冲阵】每移动一段距离获得 1 层冲势，至多 %s 层。下一次攻击消耗全部冲势，每层额外造成 %s 攻击力的物理伤害。" % (c("LANCE_MAX"), cp("LANCE_PCT")),
     "移动积攒冲势，下一次攻击把冲势全部打出去。"),
    ("p2eq_141", "长戟", 3, "+攻15/28/48·龟能回复6/10/15%",
     [{"atk": 15, "_echargePct": 6}, {"atk": 28, "_echargePct": 10}, {"atk": 48, "_echargePct": 15}],
     "攻击变为扇形横扫，前方扇形内的其他敌人受到 %s 攻击力的物理伤害。" % cp("HALB_PCT"),
     "攻击横扫前方一片敌人。"),
    ("p2eq_142", "盾矛", 3, "+生命120/240/450·护甲10/18/30",
     [{"hp": 120, "def": 10}, {"hp": 240, "def": 18}, {"hp": 450, "def": 30}],
     "受到来自正面的攻击和技能伤害降低 %s。每受到 %s 次攻击，用矛反刺攻击者，造成自身 %s 护甲的物理伤害。持续伤害不会触发此效果。"
     % (cp("SHSP_DR"), c("SHSP_EVERY"), cp("SHSP_ARMOR")),
     "正面减伤，挨打多了用矛反刺。"),
    ("p2eq_143", "方天画戟", 4, "+生命200/420/1000·攻20/38/90",
     [{"hp": 200, "atk": 20}, {"hp": 420, "atk": 38}, {"hp": 1000, "atk": 90}],
     "【无双】身边有至少 %s 名敌人时，每秒横扫一圈，对身边的敌人造成 %s 攻击力的物理伤害。" % (c("FTJ_MIN"), cp("FTJ_PCT")),
     "被围住时每秒横扫一圈。"),
    ("p2eq_144", "投矛器", 4, "+攻25/45/110·龟能回复8/12/18%",
     [{"atk": 25, "_echargePct": 8}, {"atk": 45, "_echargePct": 12}, {"atk": 110, "_echargePct": 18}],
     "每 %s 秒朝敌人最密集的方向扇形掷出 %s 根矛，每根命中第一个敌人，造成 %s 攻击力的物理伤害。" % (c("ATL_IV"), c("ATL_N"), cp("ATL_PCT")),
     "定时朝敌群扇形掷出一排矛。"),
    ("p2eq_145", "永恒之枪", 5, "+攻40/90/400·龟能回复10/15/25%",
     [{"atk": 40, "_echargePct": 10}, {"atk": 90, "_echargePct": 15}, {"atk": 400, "_echargePct": 25}],
     "每 %s 秒向生命值最高的敌人掷出永恒之枪，造成目标 %s 最大生命值的物理伤害，并将其钉在原地 %s 秒。"
     % (c("ETERNAL_IV"), cp("ETERNAL_PCT"), c("ETERNAL_PIN")),
     "定时把生命值最高的敌人钉在原地。"),
    ("p2eq_146", "圣枪", 5, "+生命300/700/2000·攻30/70/300",
     [{"hp": 300, "atk": 30}, {"hp": 700, "atk": 70}, {"hp": 2000, "atk": 300}],
     "攻击为目标叠加圣痕，叠满 %s 层时引爆，造成 %s 魔法伤害，并回复自身 %s 最大生命值。" % (c("HOLY_STACKS"), c("HOLY_DMG"), cp("HOLY_HEAL")),
     "攻击叠圣痕，叠满引爆并回复生命值。"),
]


def ed(rel, old, new, cnt=1):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    crlf = b"\r\n" in raw
    s = raw.decode("utf-8").replace("\r\n", "\n")
    if new in s and old not in s:
        return
    assert s.count(old) == cnt, (rel, old[:60], s.count(old))
    s = s.replace(old, new)
    if crlf:
        s = s.replace("\n", "\r\n")
    open(p, "wb").write(s.encode("utf-8"))


def main():
    p = os.path.join(ROOT, "data/phase2-equipment.json")
    d = json.loads(open(p, "rb").read().decode("utf-8"))
    idx = {e["id"]: i for i, e in enumerate(d)}
    for (iid, name, cost, shown, stats, desc, brief) in ITEMS:
        ent = {"id": iid, "name": name, "cost": cost, "baseStats1": shown, "shopAvailable": 1, "emoji": "🔱",
               "effectDesc1": desc, "effectDesc3": "", "img": "equip/%s.png" % iid, "effectBrief": brief}
        if iid in idx:
            d[idx[iid]] = ent
        else:
            d.append(ent)
    open(p, "wb").write((json.dumps(d, ensure_ascii=False, indent=2) + "\n").replace("\n", "\r\n").encode("utf-8"))
    tp = os.path.join(ROOT, "data/p2eq-types.json")
    t = json.loads(open(tp, "rb").read().decode("utf-8"))
    for it in ITEMS:
        t[it[0]] = "长矛"
    open(tp, "wb").write((json.dumps(t, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    sp = os.path.join(ROOT, "scripts/gamedata/equip_stats.gd")
    b = open(sp, "rb").read()
    nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
    s = b.decode("utf-8").replace("\r\n", "\n")
    for (iid, name, cost, shown, stats, desc, brief) in reversed(ITEMS):
        line = '\t"%s": %s,   # 长矛 · %d费 · %s(2026-11-26 方案书 20261126)' % (iid, json.dumps(stats, ensure_ascii=False), cost, name)
        s = re.sub(r'^\t"%s": .*$\n' % iid, "", s, flags=re.M)
        anchor = re.search(r'^\t"p2eq_136": .*$', s, re.M)
        assert anchor
        s = s[:anchor.end()] + "\n" + line + s[anchor.end():]
    open(sp, "wb").write(s.replace("\n", nl).encode("utf-8"))
    ## 接线
    ed("scripts/gamedata/b4_owner.gd", '''	"p2eq_132": "mask", "p2eq_133": "mask", "p2eq_134": "mask", "p2eq_135": "mask", "p2eq_136": "mask",
}''', '''	"p2eq_132": "mask", "p2eq_133": "mask", "p2eq_134": "mask", "p2eq_135": "mask", "p2eq_136": "mask",
	## 长矛批(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md)
	"p2eq_137": "spear", "p2eq_138": "spear", "p2eq_139": "spear", "p2eq_140": "spear", "p2eq_141": "spear",
	"p2eq_142": "spear", "p2eq_143": "spear", "p2eq_144": "spear", "p2eq_145": "spear", "p2eq_146": "spear",
}''')
    Q = "scripts/systems/equip/equip_system.gd"
    ed(Q, '''var _mask_sys: EqMaskBatch       # 面具 10 件(127~136)·eq_mask_batch.gd(11-26 方案书 20261125c)''',
       '''var _mask_sys: EqMaskBatch       # 面具 10 件(127~136)·eq_mask_batch.gd(11-26 方案书 20261125c)
var _spear_sys: EqSpearBatch     # 长矛 10 件(137~146)·eq_spear_batch.gd(11-26 方案书 20261126)''')
    ed(Q, '''_mask_sys = EqMaskBatch.new(b)''', '''_mask_sys = EqMaskBatch.new(b); _spear_sys = EqSpearBatch.new(b)''')
    ed(Q, '''"mask": _mask_sys}''', '''"mask": _mask_sys, "spear": _spear_sys}''')
    ed(Q, '''_dagger_sys, _magic_sys, _mask_sys]''', '''_dagger_sys, _magic_sys, _mask_sys, _spear_sys]''')
    ed("scripts/scenes/battle/battle_damage.gd", '''	var d = battle._mitigate_incoming(u, float(dmg), raw)
''', '''	var d = battle._mitigate_incoming(u, float(dmg), raw)
	if u.get("_shsp_dr", 0.0) > 0.0 and not raw: d = EqSpearBatch.front_block(u, src, d)   # 142 盾矛: 正面来的攻击 / 技能伤害降低(只有这条路有来源方向)
''')
    print("写入 %d 件 + 接线" % len(ITEMS))


if __name__ == "__main__":
    main()
