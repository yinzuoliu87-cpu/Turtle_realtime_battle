class_name EqChipBatch
extends RefCounted
## eq_chip_batch.gd —— 筹码 10 枚(消耗品)的效果本体(2026-11-26 · 方案书 docs/plans/20261126b-筹码.md §4)
##   147 白 1 元 · 148 粉 2.5 元 · 149 红 5 元 · 150 绿 25 元 · 151 黑 100 元 · 152 紫 500 元 · 153 黄 1000 元
##   · 154 棕 5000 元 · 155 金 10 万 · 156 灰 2.5 万
## 消耗品规则(用户 11-24): 没有羁绊档位、不给羁绊属性; 只有一星、不进三合一(EquipPool.NO_STAR); 带进一场正式对局打完就损坏
##   (EconLedger._income 按对局来源扣, 服务器重放同一份代码 ⇒ 两边一致)。纯属性的几枚走 STATS, 这里只管带效果的。
var battle

# ── 150 绿 ──
const GREEN_REGEN := 0.01           # 每秒回复 最大生命值 ×
# ── 151 黑 / 152 紫 ──
const SHIELD_PCT := 0.30            # 全体友军护盾 = 携带者最大生命值 ×(不衰减, 打空为止)
# ── 154 棕 ──
const BROWN_SEC := 2.5
const BROWN_HEAL := 0.60
# ── 155 金 ──
const GOLD_AT := 8.0
const GOLD_SEC := 3.0
const GOLD_TEAM_ATK := 25.0
const GOLD_TEAM_RES := 25.0
# ── 156 灰 ──
const GREY_CAP := 40
const GREY_ATK := 2.0
const GREY_RES := 2.0
const GREY_HP := 20.0
const GREY_FULL_AMP := 0.10
const GREY_FULL_DR := 0.10

var stat := {"shield_phys": 0, "shield_mag": 0, "cc_immune": 0, "brown": 0, "gold_guard": 0, "grey_full": 0}
var _golds: Array = []      # {u, done}


func _init(b) -> void:
	battle = b


## 筹码的演出画在长矛羁绊那一层(SpearEqVfx)。那一层是懒加载的: 场上没有长矛时一直是空的 ⇒ 先让它建起来
##   (11-26 夜录像抓到: 原来直接读、是空就跳过 ⇒ 没带长矛的阵容里黑紫开场护盾 / 金色护罩 / 灰色满层一个都不画)
func _fx(method: String, args: Array = []) -> void:
	if battle.get("_spear_syn") == null:
		return
	if battle._spear_syn.vfx == null:
		battle._spear_syn._fx("noop", [])
	var v = battle._spear_syn.vfx
	if v != null and v.has_method(method):
		v.callv(method, args)


func _allies(u: Dictionary) -> Array:
	var out: Array = []
	var side := str(battle._eff_side(u))
	for o in battle._units:
		if o is Dictionary and o.get("alive", false) and str(battle._eff_side(o)) == side and not bool(o.get("_isEgg", false)) \
				and not battle._is_untouchable(o):
			out.append(o)
	return out


func on_spawn(u: Dictionary, eid: String, _si: int) -> void:
	match eid:
		"p2eq_151", "p2eq_152":   # 黑 = 物理护盾 / 紫 = 魔法护盾, 给全体友军(每枚各自生效, 可叠)
			var amt: float = float(u.get("maxHp", 0.0)) * SHIELD_PCT
			var key: String = "phys_shield" if eid == "p2eq_151" else "magic_shield"
			## 记账照 012 海藻(MagicShield.seaweed_on_spawn): 乘受盾方护盾强度 · 进受盾方「获盾」· 记进这一枚的装备统计「护盾」栏
			##   (原来直接加字段不记账 ⇒ 装备统计里这枚给的盾是 0, 直播覆盖扫描 verify_stream_coverage 抓到「151 没产出」)
			var tl: Array = battle._equip_sys.tally.push(u, battle._equip_sys.key_of(u, eid))
			for a in _allies(u):
				var got: float = amt * BattleDamage.shield_strength(a, battle._t)
				a[key] = float(a.get(key, 0.0)) + got
				a["_st_shield"] = float(a.get("_st_shield", 0)) + got
				EqSpearBatch.holy_store(a, float(got))   # 146 圣枪储能
				battle._equip_sys.tally.on_shield(a, got)
			battle._equip_sys.tally.pop(tl)
			stat["shield_phys" if eid == "p2eq_151" else "shield_mag"] += 1
			_fx("chip_team_shield", [u, eid == "p2eq_151"])
		"p2eq_153":   # 黄: 整个战场控制免疫
			u["cc_immune_until"] = maxf(float(u.get("cc_immune_until", 0.0)), 1.0e12)
			stat["cc_immune"] += 1
			_fx("chip_cc_block", [u])   # 登场时头顶转一下黄色筹码: 告诉玩家这只免控
		"p2eq_154":
			u["_chip_revive_ready"] = true
		"p2eq_155":
			_golds.append({"u": u, "done": false})
		"p2eq_156":
			u["_grey_stk"] = 0


## 153 黄: 一次控制被挡掉(equip_tally.on_cc_block 调) ⇒ 头顶黄色筹码转一圈 + 金色盾光
func on_cc_block(u: Dictionary) -> void:
	stat["cc_block"] = int(stat.get("cc_block", 0)) + 1
	_fx("chip_cc_block", [u])


func on_basic(u: Dictionary, _tgt, eid: String, _si: int) -> void:
	if eid == "p2eq_156":
		_grey_add(u)


func on_damaged(u: Dictionary, _src, _dmg: float, eid: String, _si: int) -> void:
	if eid == "p2eq_156" and not bool(u.get("_b4_dot", false)):
		_grey_add(u)


## 156 灰: 每次攻击或受击 +1 层(至多 40): 每层 +2 攻 +2 护甲 +2 魔抗 +20 最大生命; 满层再 +10% 增伤与减伤
func _grey_add(u: Dictionary) -> void:
	var n := int(u.get("_grey_stk", 0))
	if n >= GREY_CAP:
		return
	n += 1
	u["_grey_stk"] = n
	u["base_atk"] = float(u.get("base_atk", 0.0)) + GREY_ATK
	u["base_def"] = float(u.get("base_def", 0.0)) + GREY_RES
	u["base_mr"] = float(u.get("base_mr", 0.0)) + GREY_RES
	u["maxHp"] = float(u.get("maxHp", 0.0)) + GREY_HP
	u["hp"] = float(u.get("hp", 0.0)) + GREY_HP
	if n == GREY_CAP:
		u["damage_amp"] = float(u.get("damage_amp", 0.0)) + GREY_FULL_AMP
		u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + GREY_FULL_DR
		stat["grey_full"] += 1
		_fx("chip_grey_full", [u])
	battle._recalc_stats(u)


func on_hit(_s: Dictionary, _t: Dictionary, _d: float, _e: String, _si: int) -> void:
	pass


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_kill(_k: Dictionary, _v: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_any_basic(_u: Dictionary, _tgt) -> void:
	pass


func tick(_delta: float) -> void:
	var el: float = float(battle._t) - float(battle._sd_t0)
	for g in _golds:
		var u: Dictionary = g["u"]
		if bool(g["done"]) or not u.get("alive", false) or el < GOLD_AT:
			continue
		g["done"] = true
		var tl: Array = battle._equip_sys.tally.push(u, battle._equip_sys.key_of(u, "p2eq_155"))   # 演出与加成记在这一枚名下(装备统计 / 直播覆盖扫描按上下文认)
		_gold_guard(u)
		battle._equip_sys.tally.pop(tl)


## 155 金: 第 8 秒全体友军金色护罩 3 秒(免疫伤害与负面效果) + 这一路全体友军 +25 攻击 +25 双抗
func _gold_guard(u: Dictionary) -> void:
	var t := float(battle._t)
	stat["gold_guard"] += 1
	for a in _allies(u):
		a["_gold_guard_until"] = maxf(float(a.get("_gold_guard_until", 0.0)), t + GOLD_SEC)
		a["cc_immune_until"] = maxf(float(a.get("cc_immune_until", 0.0)), t + GOLD_SEC)
		a["base_atk"] = float(a.get("base_atk", 0.0)) + GOLD_TEAM_ATK
		a["base_def"] = float(a.get("base_def", 0.0)) + GOLD_TEAM_RES
		a["base_mr"] = float(a.get("base_mr", 0.0)) + GOLD_TEAM_RES
		battle._recalc_stats(a)
	_fx("chip_gold_guard", [u, GOLD_SEC])


## 信息面板「本局」要显示的状态, 每帧镜像进 eq_state[装备键](面板 info_panel.eq_live_lines 只读它; eq_state 随直播下发 ⇒ 观战一致)。
##   只供显示、不参与结算(不改对局结果)。只放整数(倒计时按整秒), 免得每帧都变把直播数据撑大。
##   11-26 用户「物理护盾条呢…你这我随便一问，你这个就没做到啊？」⇒ 30 件新装备的显示逐件补齐。
func _live_put(u: Dictionary, ck: String, d: Dictionary) -> void:
	var est: Dictionary = u.get("eq_state", {})
	var cur = est.get(ck, {})
	if not (cur is Dictionary):
		cur = {}
	for k in d:
		(cur as Dictionary)[k] = d[k]
	est[ck] = cur
	u["eq_state"] = est


func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var es0 = battle._equip_sys
	var ckp0: Array = es0.ck_save()
	for e0 in u.get("equips", []):
		if not (e0 is Dictionary):
			continue
		var eid0 := str((e0 as Dictionary).get("id", ""))
		if not ["p2eq_153", "p2eq_154", "p2eq_155", "p2eq_156"].has(eid0):
			continue
		es0.ck_set(u, e0)
		var ck0: String = es0.key_of(u, eid0)
		match eid0:
			"p2eq_153":
				_live_put(u, ck0, {"cci": true})
			"p2eq_154":
				_live_put(u, ck0, {"ready": bool(u.get("_chip_revive_ready", false))})   # 面板同威尼斯面具那一种写法
			"p2eq_155":
				var done := true
				for g in _golds:
					if is_same(g["u"], u) and not bool(g["done"]):
						done = false
				_live_put(u, ck0, {"done": done})
			_:
				_live_put(u, ck0, {"stk": int(u.get("_grey_stk", 0))})
	es0.ck_restore(ckp0)
	if float(u["hp"]) >= float(u.get("maxHp", 0.0)):
		return
	## 150 绿: 每秒回复 1% 最大生命值。每枚各自回、各自记进自己的装备统计(用户 11-13「每件各自独立生效…统计也分开」;
	##   原来几枚合成一次 _heal 且不压统计上下文 ⇒ 回的血不记在任何一枚名下, 直播覆盖扫描 verify_stream_coverage 抓到「150 没产出」)
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u.get("equips", []):
		if not (e is Dictionary) or str((e as Dictionary).get("id", "")) != "p2eq_150":
			continue
		es.ck_set(u, e)
		var tl: Array = es.tally.push(u, es.key_of(u, "p2eq_150"))
		battle._damage._heal(u, float(u.get("maxHp", 0.0)) * GREEN_REGEN * delta, true)
		es.tally.pop(tl)
	es.ck_restore(ckp)


func clear_all() -> void:
	_golds.clear()


func reset_match() -> void:
	pass
