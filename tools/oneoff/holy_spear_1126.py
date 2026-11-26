"""holy_spear_1126.py —— 146 圣枪重做(方案书 docs/plans/20261126c-圣枪重做.md; 用户 11-26 晚设计)
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


SP = "scripts/systems/equip/eq_spear_batch.gd"

OLD_CONST = """const HOLY_STACKS := 3
const HOLY_DMG := [150.0, 250.0, 500.0]
const HOLY_HEAL := [0.05, 0.08, 0.12]
"""
NEW_CONST = """## 146 圣枪(11-26 晚用户重做成坦克装 · 方案书 20261126c)
const HOLY_GUARD_AT := 0.5                     # 每一路首次生命值低于这个比例 ⇒ 圣枪护盾 + 双抗
const HOLY_GUARD_PCT := [0.40, 0.60, 1.00]     # 圣枪护盾 = 最大生命值 ×(不衰减, 换路随单位重建清掉)
const HOLY_RESIST := [30.0, 50.0, 100.0]       # 护甲 / 魔抗各 +, 持续到这一路结束
const HOLY_STORE_CAP := 1.0                    # 储能上限 = 最大生命值 ×
const HOLY_IV := 12.0                          # 每 12 秒开始引导
const HOLY_ORB_IV := 0.25                      # 引导中每 0.25 秒出一个光球
const HOLY_ORB_COST := [500.0, 400.0, 300.0]   # 每个光球消耗的储能; 不够一个就结束引导
const HOLY_ORB_SPD := 900.0
const HOLY_ORB_HEAL := [150.0, 250.0, 400.0]   # 砸到友方: 临时等级 +1 并回复
const HOLY_ORB_DMG := [150.0, 250.0, 500.0]    # 砸到敌方: 魔法伤害
const HOLY_ORB_SHIELD := [60.0, 100.0, 200.0]  # 砸到敌方: 携带者护盾(照样存回储能条, 用户「不需要去限制」)
"""

OLD_BASIC = """		"p2eq_146":   # 圣枪: 圣痕 3 层引爆(待重新设计)
			var key := "holy:" + ck
			var marks: Dictionary = t.get("_holy_marks", {})
			var uid := str(u.get("_spear_uid", ""))
			if uid == "":
				_uid_n += 1
				uid = "s%d" % _uid_n
				u["_spear_uid"] = uid
			var mk: String = uid + key
			var nm := int(marks.get(mk, 0)) + 1
			if nm >= HOLY_STACKS:
				marks.erase(mk)
				stat["holy"] += 1
				var dmg: int = battle._resolve_dmg(u, float(HOLY_DMG[si]), t, true, false)
				battle._damage._apply_damage_from(u, t, dmg, COL_MAGIC, 0.0, false, true)
				battle._damage._heal(u, float(u.get("maxHp", 0.0)) * float(HOLY_HEAL[si]))
				_fx("holy_burst", [u, t])
			else:
				marks[mk] = nm
				_fx("holy_stigma", [t, nm])   # 不叫 holy_mark: 魔法书演出层(父类)有同名的 122 治愈圣典标记, 会画成别人的招牌
			t["_holy_marks"] = marks


static var _uid_n := 0
"""
NEW_BASIC = ""

OLD_STORE_ANCHOR = """# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════
"""
NEW_STORE = """## 146 圣枪储能: 携带者获得任何护盾(普通 / 魔法 / 物理 / 溢出治疗转盾)都按到手的量存进每一件圣枪各自的储能条。
##   ★挂在全部「获盾记账」点上(_st_shield 的五个写点), 不是只挂 _grant_shield: 魔法 / 物理护盾是独立字段, 不走它。
##   静态: 登场护盾在圣枪自己的 on_spawn 之前就可能发, 不能等批系统登记; 份号直接从装备栏算(EquipCk.copies)。
static func holy_store(u: Dictionary, amt: float) -> void:
	if amt <= 0.0:
		return
	var cs: Array = EquipCk.copies(u, "p2eq_146")
	if cs.is_empty():
		return
	var hs: Dictionary = u.get("_holy_store", {})
	var cap: float = float(u.get("maxHp", 0.0)) * HOLY_STORE_CAP
	for c in cs:
		var k := str(c[0])
		hs[k] = minf(cap, float(hs.get(k, 0.0)) + amt)
	u["_holy_store"] = hs


static func holy_stored(u: Dictionary, ck: String) -> float:
	return float((u.get("_holy_store", {}) as Dictionary).get(ck, 0.0))


""" + OLD_STORE_ANCHOR

OLD_TICK_LIST = """		if not ["p2eq_138", "p2eq_139", "p2eq_140", "p2eq_141", "p2eq_142", "p2eq_144", "p2eq_145"].has(eid):"""
NEW_TICK_LIST = """		if not ["p2eq_138", "p2eq_139", "p2eq_140", "p2eq_141", "p2eq_142", "p2eq_144", "p2eq_145", "p2eq_146"].has(eid):"""

OLD_TICK_145 = """			"p2eq_145":
				var a4 := _acc(u, "eter:" + ck) + delta
				if a4 >= ETERNAL_IV:
					a4 -= ETERNAL_IV
					_eternal(u, si, ck)
				_set_acc(u, "eter:" + ck, a4)
"""
NEW_TICK_145 = OLD_TICK_145 + """			"p2eq_146":
				_tick_holy(u, si, ck, delta)
"""

OLD_CLEAR = """func clear_all() -> void:
"""
NEW_CLEAR = """## 146 圣枪每帧: ① 每一路首次低于 50% 生命 ⇒ 圣枪护盾 + 双抗; ② 每 12 秒开始引导, 引导中每 0.25 秒耗储能出一个光球, 不够就结束。
##   引导期间照常移动攻击(用户没说要定身); 引导中拿到的护盾照样存进来(存的口在 holy_store, 不分是否引导)。
func _tick_holy(u: Dictionary, si: int, ck: String, delta: float) -> void:
	if _acc(u, "holy_g:" + ck) <= 0.0 and float(u.get("hp", 0.0)) < float(u.get("maxHp", 0.0)) * HOLY_GUARD_AT:
		_set_acc(u, "holy_g:" + ck, 1.0)
		stat["holy_guard"] += 1
		u["_own_grant_vfx"] = true   # 圣枪护盾自己画(不叠通用六棱罩)
		battle._damage._grant_shield(u, float(u.get("maxHp", 0.0)) * float(HOLY_GUARD_PCT[si]))
		battle._damage._buff(u, "def", float(HOLY_RESIST[si]), false, 99999.0)   # 到这一路结束(换路单位重建, buff 随之清)
		battle._damage._buff(u, "mr", float(HOLY_RESIST[si]), false, 99999.0)
		_fx("holy_guard", [u])
	var a := _acc(u, "holy_t:" + ck) + delta
	if a >= HOLY_IV:
		a -= HOLY_IV
		if _acc(u, "holy_ch:" + ck) <= 0.0:
			_set_acc(u, "holy_ch:" + ck, 1.0)
			_set_acc(u, "holy_oi:" + ck, 0.0)   # 开始引导的这一步就出第一个
			stat["holy_channel"] += 1
			_fx("holy_channel", [u, true])
	_set_acc(u, "holy_t:" + ck, a)
	if _acc(u, "holy_ch:" + ck) <= 0.0:
		return
	var oi := _acc(u, "holy_oi:" + ck) - delta
	var cost: float = float(HOLY_ORB_COST[si])
	while oi <= 0.0:
		var hs: Dictionary = u.get("_holy_store", {})
		var have: float = float(hs.get(ck, 0.0))
		if have < cost:
			_set_acc(u, "holy_ch:" + ck, 0.0)
			_fx("holy_channel", [u, false])
			oi = 0.0
			break
		hs[ck] = have - cost
		u["_holy_store"] = hs
		_holy_orb(u, si, ck)
		oi += HOLY_ORB_IV
	_set_acc(u, "holy_oi:" + ck, oi)


## 光球候选: 友方只有统领与小将(含携带者自己; 不含召唤物 / 龟蛋 / 训龟大师), 敌方是全部可选中的单位(含召唤物)。
func holy_pool(u: Dictionary) -> Array:
	var out: Array = []
	for o in battle._targeting._allies_of(u, true):
		if o.get("alive", false) and not bool(o.get("is_summon", false)) and not bool(o.get("_isEgg", false)):
			out.append(o)
	for o in battle._targeting._targetable_enemies(u):
		out.append(o)
	return out


func _holy_orb(u: Dictionary, si: int, ck: String) -> void:
	var pool: Array = holy_pool(u)
	if pool.is_empty():
		return
	var tg: Dictionary = pool[battle._battle_rng.randi() % pool.size()]
	var ally: bool = battle._is_ally(u, tg)
	stat["holy_orb"] += 1
	var me: Dictionary = u
	var node = null
	var vx = _vfx()
	if vx != null and vx.has_method("holy_orb_fly"):
		node = vx.holy_orb_fly(u, tg, ally)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, HOLY_ORB_SPD,
		func(hit: bool) -> void:
			_fx("holy_orb_end", [node, hit, tg, ally])
			if not hit or not tg.get("alive", false):
				return
			if ally:
				stat["holy_ally"] += 1
				battle._equip_tick_sys.holy_level_up(tg)
				battle._damage._heal(tg, float(HOLY_ORB_HEAL[si]))
			else:
				stat["holy_enemy"] += 1
				_magic(me, tg, float(HOLY_ORB_DMG[si]))
				if me.get("alive", false):
					battle._damage._grant_shield(me, float(HOLY_ORB_SHIELD[si])),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("holy_orb_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)


""" + OLD_CLEAR

OLD_STAT = '"eternal": 0, "eternal_hit": 0, "holy": 0}'
NEW_STAT = '"eternal": 0, "eternal_hit": 0, "holy_guard": 0, "holy_channel": 0, "holy_orb": 0, "holy_ally": 0, "holy_enemy": 0}'

OLD_MIRROR_LIST = """		if not ["p2eq_140", "p2eq_142", "p2eq_143"].has(eid):"""
NEW_MIRROR_LIST = """		if not ["p2eq_140", "p2eq_142", "p2eq_143", "p2eq_146"].has(eid):"""
OLD_MIRROR_143 = """					_live_put(u, ck, {"buff": 0, "pct": int(floor(_acc(u, "ftj:" + ck) / need * 100.0))})
"""
NEW_MIRROR_143 = OLD_MIRROR_143 + """			"p2eq_146":
				_live_put(u, ck, {"store": int(holy_stored(u, ck)), "cap": int(float(u.get("maxHp", 0.0)) * HOLY_STORE_CAP),
					"channel": _acc(u, "holy_ch:" + ck) > 0.0, "next": int(ceil(HOLY_IV - _acc(u, "holy_t:" + ck)))})
"""

patch(SP, [(OLD_CONST, NEW_CONST, 1), (OLD_BASIC, NEW_BASIC, 1), (OLD_STORE_ANCHOR, NEW_STORE, 1),
           (OLD_TICK_LIST, NEW_TICK_LIST, 1), (OLD_TICK_145, NEW_TICK_145, 1), (OLD_CLEAR, NEW_CLEAR, 1),
           (OLD_STAT, NEW_STAT, 1), (OLD_MIRROR_LIST, NEW_MIRROR_LIST, 1), (OLD_MIRROR_143, NEW_MIRROR_143, 1)])

## ── 五个获盾记账点挂储能 ──
patch("scripts/scenes/battle/battle_damage.gd", [
    ("""	u["_st_shield"] = float(u.get("_st_shield", 0)) + got   # §STATS: 实际获盾(同 _st_heal: 累计用 float, 否则每次调用丢掉小数)
""", """	u["_st_shield"] = float(u.get("_st_shield", 0)) + got   # §STATS: 实际获盾(同 _st_heal: 累计用 float, 否则每次调用丢掉小数)
	EqSpearBatch.holy_store(u, float(got))   # 146 圣枪: 获得的任何护盾存进储能条
""", 1),
    ("""			u["_st_shield"] = float(u.get("_st_shield", 0)) + (float(u["shield"]) - _osb)
""", """			u["_st_shield"] = float(u.get("_st_shield", 0)) + (float(u["shield"]) - _osb)
			EqSpearBatch.holy_store(u, float(u["shield"]) - _osb)   # 146 圣枪储能(溢出治疗转的盾也算获得护盾)
""", 1),
])
patch("scripts/systems/equip/eq_chip_batch.gd", [
    ("""				a["_st_shield"] = float(a.get("_st_shield", 0)) + got
""", """				a["_st_shield"] = float(a.get("_st_shield", 0)) + got
				EqSpearBatch.holy_store(a, float(got))   # 146 圣枪储能
""", 1),
])
patch("scripts/systems/equip/eq_mask_batch.gd", [
    ("""			u["_st_shield"] = float(u.get("_st_shield", 0)) + amt   # 记账同 012 海藻: 获盾 + 这件装备统计的「护盾」栏
""", """			u["_st_shield"] = float(u.get("_st_shield", 0)) + amt   # 记账同 012 海藻: 获盾 + 这件装备统计的「护盾」栏
			EqSpearBatch.holy_store(u, amt)   # 146 圣枪储能(物理护盾也算)
""", 1),
])
patch("scripts/systems/equip/magic_shield.gd", [
    ("""	u["_st_shield"] = float(u.get("_st_shield", 0)) + amt   # §STATS 获盾(与 _grant_shield 同口径; 装备账 == Σ获盾 由 verify_equip_tally 对账)
""", """	u["_st_shield"] = float(u.get("_st_shield", 0)) + amt   # §STATS 获盾(与 _grant_shield 同口径; 装备账 == Σ获盾 由 verify_equip_tally 对账)
	EqSpearBatch.holy_store(u, amt)   # 146 圣枪储能(魔法护盾也算)
""", 1),
])

## ── 临时等级: 温泉蛋与圣枪共用基准与攻速总数 ──
ET = "scripts/systems/equip/equip_tick_system.gd"
patch(ET, [
    # 逐级升(温泉蛋)
    ("""		if not stt.has("ref_atk"):   # 首次升级锁基准 → 线性+5%/级(同统领 1+0.05×级, 非复利)
			stt["ref_atk"] = u["base_atk"]; stt["ref_def"] = u["base_def"]; stt["ref_mr"] = u["base_mr"]
			stt["ref_hp"] = u["maxHp"]; stt["ref_iv"] = float(u.get("atk_interval", 1.0))
""", """		if not stt.has("ref_atk"):   # 首次升级锁基准 → 线性+5%/级(同统领 1+0.05×级, 非复利)
			_tlv_ref_into(u, stt)
""", 1),
    ("""		u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + EGG_LV_ASPD * float(el)))   # 攻速/级(同统领)
""", """		u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + EGG_LV_ASPD * float(el + int(u.get("_holy_lv", 0)))))   # 攻速/级(同统领); 圣枪临时等级一起算
""", 1),
    # 跨路重放(温泉蛋)
    ("""	if not stt.has("ref_atk"):
		stt["ref_atk"] = u["base_atk"]; stt["ref_def"] = u["base_def"]; stt["ref_mr"] = u["base_mr"]
		stt["ref_hp"] = u["maxHp"]; stt["ref_iv"] = float(u.get("atk_interval", 1.0))
""", """	if not stt.has("ref_atk"):
		_tlv_ref_into(u, stt)
""", 1),
    ("""	u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + EGG_LV_ASPD * float(n)))
""", """	u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + EGG_LV_ASPD * float(n + int(u.get("_holy_lv", 0)))))
""", 1),
    ("""func _egg_replay_levels(u: Dictionary, n: int) -> void:
""", """## 临时等级的基准(温泉蛋 036 与圣枪 146 共用一份): 本单位第一次拿临时等级那一刻的基础属性。
##   ★共用的理由: 两边各锁各的基准、各写各的攻击间隔 ⇒ 同一只龟两件都有时, 后写的一方把另一方加的攻速抹掉。
func _tlv_ref(u: Dictionary) -> Dictionary:
	if not u.has("_tlv_ref"):
		u["_tlv_ref"] = {"atk": float(u["base_atk"]), "def": float(u["base_def"]), "mr": float(u["base_mr"]),
			"hp": float(u["maxHp"]), "iv": float(u.get("atk_interval", 1.0))}
	return u["_tlv_ref"]


func _tlv_ref_into(u: Dictionary, stt: Dictionary) -> void:
	var r: Dictionary = _tlv_ref(u)
	stt["ref_atk"] = r["atk"]; stt["ref_def"] = r["def"]; stt["ref_mr"] = r["mr"]
	stt["ref_hp"] = r["hp"]; stt["ref_iv"] = r["iv"]


## 146 圣枪光球砸到友方: 临时等级 +1(规则同温泉蛋: 线性 +5% 基础攻击 / 双抗 / 最大生命, 攻速 +2%; 本路有效, 换路单位重建即清)。
func holy_level_up(u: Dictionary) -> void:
	if not u.get("alive", false) or battle._untouch_block(u, "holy_level"):
		return
	var r: Dictionary = _tlv_ref(u)
	u["_holy_lv"] = int(u.get("_holy_lv", 0)) + 1
	u["base_atk"] += float(r["atk"]) * EGG_LV_GROWTH
	u["base_def"] += float(r["def"]) * EGG_LV_GROWTH
	u["base_mr"] += float(r["mr"]) * EGG_LV_GROWTH
	var hpg: float = float(r["hp"]) * EGG_LV_GROWTH
	u["maxHp"] += hpg; u["hp"] += hpg
	var egg: int = 0
	var es: Dictionary = u.get("eq_state", {})
	if es.has(battle._equip_sys.key_of(u, "p2eq_036")):
		egg = int((es[battle._equip_sys.key_of(u, "p2eq_036")] as Dictionary).get("egg_levels", 0))
	u["atk_interval"] = maxf(0.1, float(r["iv"]) / (1.0 + EGG_LV_ASPD * float(egg + int(u["_holy_lv"]))))
	battle._recalc_stats(u)


func _egg_replay_levels(u: Dictionary, n: int) -> void:
""", 1),
])

## 显示等级: 加上圣枪临时等级
patch("scripts/scenes/RealtimeBattle3DScene.gd", [
    ("""	return lv + int(st.get("egg_levels", 0))
""", """	return lv + int(st.get("egg_levels", 0)) + int(u.get("_holy_lv", 0))   # 146 圣枪光球给的临时等级
""", 1),
])

## 属性 / 档位标签
patch("scripts/gamedata/equip_stats.gd", [
    ("""	"p2eq_146": [{"hp": 300, "atk": 30}, {"hp": 700, "atk": 70}, {"hp": 2000, "atk": 300}],   # 长矛 · 5费 · 圣枪(2026-11-26 方案书 20261126)""",
     """	"p2eq_146": [{"hp": 200, "def": 15, "mr": 15}, {"hp": 450, "def": 30, "mr": 30}, {"hp": 2500, "def": 120, "mr": 120}],   # 长矛 · 5费 · 圣枪(11-26 晚重做成坦克装 · 方案书 20261126c; 档位对齐 106)""", 1),
])
patch("scripts/gamedata/equip_tier_labels.gd", [
    ("""	"p2eq_146": ["引爆伤害 #", "回复 #% 最大生命值"],""",
     """	"p2eq_146": ["圣枪护盾 #% 最大生命值", "护甲和魔抗 +#", "每个光球消耗 # 储能", "友方回复 #", "敌方魔法伤害 #", "护盾 #"],""", 1),
])
print("ok")

## ── 文案(体例同 012 / 127 / 036; 随星级变的数顺序 = 档位标签顺序) ──
OLD_DESC = "攻击为目标叠加圣痕，达到 {C:EqSpearBatch.HOLY_STACKS} 层时引爆，造成 {C:EqSpearBatch.HOLY_DMG} 魔法伤害，并回复自身 {C:EqSpearBatch.HOLY_HEAL%}% 最大生命值。"
NEW_DESC = ("每个战场中生命值首次低于 {C:EqSpearBatch.HOLY_GUARD_AT%}% 时，获得自身 {C:EqSpearBatch.HOLY_GUARD_PCT%}% 最大生命值的圣枪护盾，该护盾不会衰减；"
            "同时获得 {C:EqSpearBatch.HOLY_RESIST} 护甲和魔抗，持续到这个战场结束。\n"
            "获得任何护盾时，将护盾值存入储能，储能上限为自身最大生命值。每 {C:EqSpearBatch.HOLY_IV} 秒开始引导：每 {C:EqSpearBatch.HOLY_ORB_IV} 秒消耗 {C:EqSpearBatch.HOLY_ORB_COST} 点储能，"
            "向场上随机一个单位射出光球，储能不足时引导结束。光球命中友方统领或小将时，使其获得 1 点临时等级（持续到这个战场结束）并回复 {C:EqSpearBatch.HOLY_ORB_HEAL} 生命值；"
            "命中敌方单位时，造成 {C:EqSpearBatch.HOLY_ORB_DMG} 魔法伤害，并为自身提供 {C:EqSpearBatch.HOLY_ORB_SHIELD} 护盾。")
OLD_BRIEF = "攻击叠加圣痕，达到上限时引爆并回复生命值。"
NEW_BRIEF = "首次半血时获得圣枪护盾与双抗。护盾存入储能，定期引导光球：强化友军或攻击敌人。"
patch("data/phase2-equipment.json", [
    (OLD_DESC, NEW_DESC, 1), (OLD_BRIEF, NEW_BRIEF, 1),
    ('"baseStats1": "+生命300/700/2000·攻30/70/300",\n    "shopAvailable": 1,\n    "emoji": "🔱"',
     '"baseStats1": "+生命200/450/2500·护甲15/30/120·魔抗15/30/120",\n    "shopAvailable": 1,\n    "emoji": "🔱"', 1),
])
print("json ok")
