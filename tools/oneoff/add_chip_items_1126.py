"""add_chip_items_1126.py —— 筹码 10 枚(消耗品)进数据表 + 接线(方案书 docs/plans/20261126b-筹码.md)

  python tools/oneoff/add_chip_items_1126.py      # 幂等

写: phase2-equipment.json / p2eq-types.json / equip_stats.gd(STATS) / equip_pool.gd(NO_STAR) / b4_owner.gd / equip_system.gd /
    主场景 _mitigate_incoming(金色护罩) / battle_damage(金色护罩免持续伤害 + 棕色复活) / eq_mask_batch.revive(棕色复用威尼斯复活流程) /
    GameState.burn_chips + EconLedger._income(正式对局打完损坏) / phase2_types(类型名 / 图标 / 介绍; 不进 TYPES —— 没有羁绊档位)。
"""
import json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.stdout.reconfigure(encoding="utf-8")
E = "EqChipBatch"
TAIL = "消耗品：只有一星，不会升星，带进一场积分赛、闯关赛或决赛日对局后损坏。"


def c(n):
    return "{C:%s.%s}" % (E, n)


def cp(n):
    return "{C:%s.%s%%}%%" % (E, n)


def three(d):
    return [d, d, d]


ITEMS = [
    ("p2eq_147", "白色筹码", 1, "+攻45·攻速50%", three({"atk": 45, "_aspdPct": 50}), TAIL, "一次性的攻击力与攻击速度。"),
    ("p2eq_148", "粉色筹码", 1, "+生命700·护甲40", three({"hp": 700, "def": 40}), TAIL, "一次性的生命值与护甲。"),
    ("p2eq_149", "红色筹码", 2, "+攻70·暴击率30%", three({"atk": 70, "crit": 0.30}), TAIL, "一次性的攻击力与暴击率。"),
    ("p2eq_150", "绿色筹码", 2, "+生命900·魔抗40", three({"hp": 900, "mr": 40}),
     "每秒回复 %s 最大生命值。" % cp("GREEN_REGEN") + TAIL, "一次性的生命值、魔抗与持续回复。"),
    ("p2eq_151", "黑色筹码", 3, "+生命600", three({"hp": 600}),
     "登场时为所有友军提供相当于自身 %s 最大生命值的物理护盾，该护盾只吸收物理伤害，不会消散。" % cp("SHIELD_PCT") + TAIL, "登场时为全队提供物理护盾。"),
    ("p2eq_152", "紫色筹码", 3, "+生命600", three({"hp": 600}),
     "登场时为所有友军提供相当于自身 %s 最大生命值的魔法护盾，该护盾只吸收魔法伤害，不会消散。" % cp("SHIELD_PCT") + TAIL, "登场时为全队提供魔法护盾。"),
    ("p2eq_153", "黄色筹码", 4, "+攻70·攻速50%·暴击伤害30%", three({"atk": 70, "_aspdPct": 50, "critDmg": 0.30}),
     "整个战场免疫控制。" + TAIL, "一次性的攻击属性，整个战场免疫控制。"),
    ("p2eq_154", "棕色筹码", 4, "+生命1500·护甲60·魔抗60", three({"hp": 1500, "def": 60, "mr": 60}),
     "首次受到致命伤害时倒地不死，%s 秒内回复至 %s 最大生命值后继续战斗。每个战场一次。" % (c("BROWN_SEC"), cp("BROWN_HEAL")) + TAIL, "一次性的双抗与复活。"),
    ("p2eq_155", "金色筹码", 5, "+生命1000", three({"hp": 1000}),
     "开打第 %s 秒，为所有友军套上金色护罩，持续 %s 秒，期间免疫伤害与负面效果，并使所有友军在这个战场获得 %s 攻击力、%s 护甲和魔抗。"
     % (c("GOLD_AT"), c("GOLD_SEC"), c("GOLD_TEAM_ATK"), c("GOLD_TEAM_RES")) + TAIL, "第 8 秒全队金色护罩并提升全队属性。"),
    ("p2eq_156", "灰色筹码", 5, "+生命500", three({"hp": 500}),
     "每次攻击或受到攻击获得 1 层，至多 %s 层。每层提供 %s 攻击力、%s 护甲和魔抗、%s 最大生命值。叠满后额外获得 %s 增伤与 %s 减伤。"
     % (c("GREY_CAP"), c("GREY_ATK"), c("GREY_RES"), c("GREY_HP"), cp("GREY_FULL_AMP"), cp("GREY_FULL_DR")) + TAIL, "攻击或挨打叠层，越打越强。"),
]


def ed(rel, old, new, cnt=1):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    crlf = b"\r\n" in raw
    s = raw.decode("utf-8").replace("\r\n", "\n")
    if new in s:
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
        ent = {"id": iid, "name": name, "cost": cost, "baseStats1": shown, "shopAvailable": 1, "emoji": "🪙",
               "effectDesc1": desc, "effectDesc3": "", "img": "equip/%s.png" % iid, "effectBrief": brief}
        if iid in idx:
            d[idx[iid]] = ent
        else:
            d.append(ent)
    open(p, "wb").write((json.dumps(d, ensure_ascii=False, indent=2) + "\n").replace("\n", "\r\n").encode("utf-8"))
    tp = os.path.join(ROOT, "data/p2eq-types.json")
    t = json.loads(open(tp, "rb").read().decode("utf-8"))
    for it in ITEMS:
        t[it[0]] = "筹码"
    open(tp, "wb").write((json.dumps(t, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    sp = os.path.join(ROOT, "scripts/gamedata/equip_stats.gd")
    b = open(sp, "rb").read()
    nl = "\r\n" if b.count(b"\r\n") > b.count(b"\n") / 2 else "\n"
    s = b.decode("utf-8").replace("\r\n", "\n")
    for (iid, name, cost, shown, stats, desc, brief) in reversed(ITEMS):
        line = '\t"%s": %s,   # 筹码 · %d费 · %s(2026-11-26 方案书 20261126b; 只有一星, 三档同值)' % (iid, json.dumps(stats, ensure_ascii=False), cost, name)
        s = re.sub(r'^\t"%s": .*$\n' % iid, "", s, flags=re.M)
        anchor = re.search(r'^\t"p2eq_146": .*$', s, re.M)
        assert anchor
        s = s[:anchor.end()] + "\n" + line + s[anchor.end():]
    open(sp, "wb").write(s.replace("\n", nl).encode("utf-8"))
    ids = ", ".join('"p2eq_%d": true' % i for i in range(147, 157))
    ed("scripts/gamedata/equip_pool.gd", '''const NO_STAR := {"p2eq_096": true}''',
       '''const NO_STAR := {"p2eq_096": true,
	## 筹码 10 枚(2026-11-26 用户 11-24「只有一星不合成」, 方案书 20261126b): 不进三合一(张数照常, 不是无限件)
	%s}''' % ids)
    ed("scripts/gamedata/b4_owner.gd", '''	"p2eq_142": "spear", "p2eq_143": "spear", "p2eq_144": "spear", "p2eq_145": "spear", "p2eq_146": "spear",
}''', '''	"p2eq_142": "spear", "p2eq_143": "spear", "p2eq_144": "spear", "p2eq_145": "spear", "p2eq_146": "spear",
	## 筹码(2026-11-26 · 方案书 docs/plans/20261126b-筹码.md)
	"p2eq_147": "chip", "p2eq_148": "chip", "p2eq_149": "chip", "p2eq_150": "chip", "p2eq_151": "chip",
	"p2eq_152": "chip", "p2eq_153": "chip", "p2eq_154": "chip", "p2eq_155": "chip", "p2eq_156": "chip",
}''')
    Q = "scripts/systems/equip/equip_system.gd"
    ed(Q, '''var _spear_sys: EqSpearBatch     # 长矛 10 件(137~146)·eq_spear_batch.gd(11-26 方案书 20261126)''',
       '''var _spear_sys: EqSpearBatch     # 长矛 10 件(137~146)·eq_spear_batch.gd(11-26 方案书 20261126)
var _chip_sys: EqChipBatch       # 筹码 10 枚(147~156)·eq_chip_batch.gd(11-26 方案书 20261126b)''')
    ed(Q, '''_spear_sys = EqSpearBatch.new(b)''', '''_spear_sys = EqSpearBatch.new(b); _chip_sys = EqChipBatch.new(b)''')
    ed(Q, '''"spear": _spear_sys}''', '''"spear": _spear_sys, "chip": _chip_sys}''')
    ed(Q, '''_mask_sys, _spear_sys]''', '''_mask_sys, _spear_sys, _chip_sys]''')
    ed("scripts/scenes/RealtimeBattle3DScene.gd", '''	if _t < float(u.get("_tame_invuln_until", 0.0)):
		return 0.0                                   # ★驯服重生演出期(2.5秒)无敌(用户 2026-07-28 B7)''',
       '''	if _t < float(u.get("_tame_invuln_until", 0.0)):
		return 0.0                                   # ★驯服重生演出期(2.5秒)无敌(用户 2026-07-28 B7)
	if _t < float(u.get("_gold_guard_until", 0.0)):
		return 0.0                                   # 155 金色筹码: 金色护罩 3 秒免疫伤害(两条伤害路的共用收口)''')
    D = "scripts/scenes/battle/battle_damage.gd"
    ed(D, '''	if u is Dictionary and u.get("_gas_mask", false) and battle._equip_sys._mask_sys.dot_immune(u, type):
		return   # 133 防毒面具: 免疫灼烧 / 中毒 / 流血''', '''	if u is Dictionary and u.get("_gas_mask", false) and battle._equip_sys._mask_sys.dot_immune(u, type):
		return   # 133 防毒面具: 免疫灼烧 / 中毒 / 流血
	if u is Dictionary and battle._t < float(u.get("_gold_guard_until", 0.0)):
		return   # 155 金色筹码: 护罩期间免疫负面效果(持续伤害不上层)''')
    ed(D, '''	if u.get("_ven_ready", false) and d > 0.0 and float(u["hp"]) - d <= 0.0:''',
       '''	if (u.get("_ven_ready", false) or u.get("_chip_revive_ready", false)) and d > 0.0 and float(u["hp"]) - d <= 0.0:''', 2)
    M = "scripts/systems/equip/eq_mask_batch.gd"
    ed(M, '''	if not bool(u.get("_ven_ready", false)) or float(u["hp"]) - d > 0.0:
		return d
	u["_ven_ready"] = false
	var si: int = int(u.get("_ven_si", 0))''', '''	var ven: bool = bool(u.get("_ven_ready", false))
	if (not ven and not bool(u.get("_chip_revive_ready", false))) or float(u["hp"]) - d > 0.0:
		return d
	## 威尼斯面具先用; 用完了才轮到 154 棕色筹码(同一套倒地复活流程, 回血比例 60%)
	var heal_pct: float
	if ven:
		u["_ven_ready"] = false
		heal_pct = float(VEN_HEAL[int(u.get("_ven_si", 0))])
	else:
		u["_chip_revive_ready"] = false
		heal_pct = EqChipBatch.BROWN_HEAL
		battle._equip_sys._chip_sys.stat["brown"] += 1''')
    ed(M, '''	_revives.append({"u": u, "t0": t, "to": float(u.get("maxHp", 1.0)) * float(VEN_HEAL[si])})''',
       '''	_revives.append({"u": u, "t0": t, "to": float(u.get("maxHp", 1.0)) * heal_pct})''')
    ## 打完损坏
    G = "autoload/GameState.gd"
    ed(G, '''func pool_give_back(eid: String, star: int) -> void:''', '''## 筹码(消耗品, 方案书 20261126b): 把穿在统领 / 小将身上的筹码全部拿掉(这一场用掉了), 张数退回卡池(守恒律照旧)。
## 只由 EconLedger._income 在正式对局那一笔进账时调 —— 服务器重放走同一份代码, 两边一定一致。返回烧掉几枚。
func burn_chips() -> int:
	var n := 0
	for pid in persistent_equipped.keys():
		var keep: Array = []
		for it in persistent_equipped[pid]:
			if it is Dictionary and _P2Types_ref().types_of(str((it as Dictionary).get("id", ""))).has("筹码"):
				pool_give_back(str((it as Dictionary)["id"]), int((it as Dictionary).get("star", 1)))
				n += 1
			else:
				keep.append(it)
		persistent_equipped[pid] = keep
	var a: Dictionary = get_dual_lineup().duplicate(true)
	var changed := false
	for lane in a.keys():
		if not (a[lane] is Array):
			continue
		for u in a[lane]:
			if not (u is Dictionary) or not ((u as Dictionary).get("equips") is Array):
				continue
			var keep2: Array = []
			for it2 in (u as Dictionary)["equips"]:
				if it2 is Dictionary and _P2Types_ref().types_of(str((it2 as Dictionary).get("id", ""))).has("筹码"):
					pool_give_back(str((it2 as Dictionary)["id"]), int((it2 as Dictionary).get("star", 1)))
					n += 1
					changed = true
				else:
					keep2.append(it2)
			(u as Dictionary)["equips"] = keep2
	if changed:
		dual_lineup = a
	if n > 0:
		sync_synergy_grants()
	return n


static func _P2Types_ref():
	return load("res://scripts/gamedata/phase2_types.gd")


func pool_give_back(eid: String, star: int) -> void:''')
    L = "scripts/gamedata/econ_ledger.gd"
    ed(L, '''	if c == 0 and xp == 0 and not axe and cj == 0:
		return {"ok": false, "reason": "empty"}''', '''	if c == 0 and xp == 0 and not axe and cj == 0:
		return {"ok": false, "reason": "empty"}
	## 筹码(消耗品, 方案书 20261126b): 正式对局的那一笔进账 = 这一场打完 ⇒ 身上的筹码损坏。
	##   按来源判、不靠客户端传字段 ⇒ 不扣就和服务器重放对不上。每场只有一笔带经验的进账走这几个来源。
	var burned := 0
	if CHIP_BURN_SRCS.has(str(op.get("src", ""))):
		burned = int(gs.burn_chips()) if gs.has_method("burn_chips") else 0''')
    ed(L, '''	return {"ok": true, "coins": c}


## 服务器那一局结束时我方宝箱龟的进度''', '''	return {"ok": true, "coins": c, "burned": burned}


## 服务器那一局结束时我方宝箱龟的进度''')
    ed(L, '''const TEST_SHOP_SEED := 20260819''', '''const TEST_SHOP_SEED := 20260819
## 这几种进账 = 一场正式对局打完(积分赛 / 周六闯关 / 周日决赛), 筹码在这一笔里损坏(方案书 20261126b)。切磋 / 教程不记账, 自然不扣。
const CHIP_BURN_SRCS := {"ranked": true, "ranked_ref": true, "gauntlet": true, "finals": true}''')
    T = "scripts/gamedata/phase2_types.gd"
    ed(T, '''	"长矛": "res://assets/sprites/tags/tag-spear.png",''', '''	"长矛": "res://assets/sprites/tags/tag-spear.png",
	"筹码": "res://assets/sprites/tags/tag-chip.png",''')
    ed(T, '''	"长矛": "长矛·百夫长",''', '''	"长矛": "长矛·百夫长",
	"筹码": "筹码·消耗品",''')
    print("写入 %d 枚 + 接线" % len(ITEMS))


if __name__ == "__main__":
    main()
