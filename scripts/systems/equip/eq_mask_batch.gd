class_name EqMaskBatch
extends RefCounted
## eq_mask_batch.gd —— 面具羁绊 10 件新装备的效果本体(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md §3)
##   127 纸面具 · 128 狐狸面具 · 129 京剧脸谱 · 130 舞狮头(召唤舞狮) · 131 小丑面具 · 132 鬼面 · 133 防毒面具
##   · 134 威尼斯面具(复活) · 135 黄金面具(金光) · 136 千面(里世界, 见 otherworld_system.gd)
##
## 每件单独生效, 跟有没有激活【偷脸】无关(用户 11-25 夜「装备的效果不用跟偷脸有大的关系」)。
## 接口 = 批④统一口(b4_owner.gd → `_b4`): on_spawn / on_basic / on_hit / on_damaged / on_magic_hurt / on_death / on_mana_full
##   / on_kill / tick / tick_unit / clear_all; 另加:
##   · `on_unit_cast(u, tgt, stype, cost, echo)` —— MagicbookSynergySystem.after_cast 转来(131 小丑面具)。
##   · `on_any_basic(u, tgt)` —— 任何单位普攻(132 鬼面潜行攻击现形)。
##   · 静态 `phys_absorb` / `fox_amp` —— 伤害管线里调(127 物理护盾 / 128 狐狸增伤)。
##   · `revive(u, d)` —— 两条伤害路径「受到致命伤害时」调(134)。
##
## ── 地雷对照(CLAUDE.md §4) ────────────────────────────────────────
##   §4.1 「X% 最大生命」一律真实 maxHp。 §4.2 单位字典不当键: 在途表存字典本身, 比较 is_same。
##   §4.3 两条伤害路径: 127 物理护盾 / 134 复活 两路都接(battle_damage)。 §4.4 `_t` 跨路累加: 到期时刻存绝对 `_t`。
##   飞行物(127 纸片反击)按速度追着飞、到了才结算; 会走的冲撞(130)每步线段碰撞, 命中名单防重复。
var battle
var vfx = null

const COL_PHYS := Color("#ff9a4a")
const COL_TRUE := Color("#fff4c2")
const SEC_PER_ENERGY := 0.075

# ── 127 纸面具 ──
const PAPER_SHIELD_PCT := [0.25, 0.40, 0.60]   # 登场物理护盾 = 自身最大生命值 ×
const PAPER_COUNTER := [0.30, 0.50, 0.80]      # 反击 = 自身护甲 ×(物理伤害, 固定值)
const PAPER_SPD := 900.0                       # 纸片飞行速度
# ── 128 狐狸面具 ──
const FOX_MAX := [0.15, 0.25, 0.40]            # 最大增伤
const FOX_FULL_DIFF := 2000.0                  # 最大生命值差到这个数时增伤到顶
# ── 129 京剧脸谱 ──
const FACE_IV := 8.0
const FACE_RED_TRUE := [0.08, 0.12, 0.20]      # 红脸: 攻击额外造成 攻击力 × 真实伤害
const FACE_BLACK_FLAT := [5.0, 10.0, 16.0]     # 黑脸: 每段受到的伤害减少
const FACE_BLACK_RES := [10.0, 20.0, 35.0]     # 黑脸: 护甲与魔抗
const FACE_WHITE_ASPD := [0.15, 0.25, 0.40]    # 白脸: 攻击速度
const FACE_WHITE_EN := [3.0, 5.0, 8.0]         # 白脸: 攻击偷取目标龟能(用户 11-25 夜「改成三五八」)
# ── 130 舞狮头 ──
const LION_HP := [900.0, 1600.0, 2500.0]       # 用户 11-26「生命值改为九百、一千六和两千五」
const LION_ATK := [20.0, 40.0, 80.0]
const LION_RES := [20.0, 35.0, 55.0]
const LION_EN_MAX := 100.0
const LION_EN_PER_HIT := 20.0                  # 舞狮每次攻击 +20 龟能(另随时间涨)
const LION_CHARGE_ATK := [2.0, 2.5, 3.0]       # 冲撞 = 舞狮攻击力 ×(用户 11-26「百分比攻击力」)
const LION_STUN := [1.0, 1.25, 1.5]
const LION_SPD := 360.0                        # 冲撞速度(用户 11-26「别太快了」; 普通龟走路 105)
const LION_DIST := 420.0                       # 冲撞距离
const LION_W := 46.0                           # 冲撞判定半宽
const LION_WINDUP := 0.45                      # 冲之前压低身子蓄力
# ── 131 小丑面具 ──
const CLOWN_SEC_PER_100 := [2.0, 2.5, 3.0]     # 嘲讽时长 = 这次技能消耗的龟能 / 100 ×
const CLOWN_R := 400.0
const CLOWN_SHIELD_PCT := [0.10, 0.15, 0.25]
const CLOWN_SHIELD_SEC := 4.0
# ── 132 鬼面 ──
const GHOST_LINE := 0.5
const GHOST_SEC := [3.0, 4.0, 5.0]
const GHOST_REGEN := [0.03, 0.05, 0.08]        # 潜行期间每秒回复 最大生命值 ×
# ── 133 防毒面具 ──
const GAS_IMMUNE := ["burn", "poison", "bleed"]
const GAS_MOVE_PER_PCT := 0.01                 # 每损失 1% 生命值 +1% 移动速度
# ── 134 威尼斯面具 ──
const VEN_SEC := 2.5
const VEN_HEAL := [0.30, 0.45, 0.70]
# ── 135 黄金面具 ──
const GOLD_DELAY := 1.0                        # 面具飞上天到金光落地
const GOLD_CD := 8.0                           # 目标死后冷却
const GOLD_FLAT := [40.0, 80.0, 200.0]         # 每秒真实伤害(固定)
const GOLD_PCT := [0.015, 0.025, 0.05]         # 每秒真实伤害(目标最大生命值 ×)
const GOLD_RAMP := [0.20, 0.25, 0.40]          # 每过 1 秒, 每秒伤害再多起始值的这么多
const GOLD_TICK := 0.25                        # 结算粒度(每秒伤害按 0.25 秒一段打出)
const GOLD_STK_HP := 20.0                      # 每层 +最大生命值(用户 11-26「加二十生命值加二攻击力」)
const GOLD_STK_ATK := 2.0

## 门禁量
var stat := {"paper_counter": 0, "face_swap": 0, "lion_charge": 0, "lion_hit": 0, "clown": 0, "ghost": 0, "gas_block": 0,
	"revive": 0, "gold_beam": 0, "gold_kill": 0}

var _lions: Array = []        # {u, owner, si, en, state, t, dir, from, hit:[]}
var _beams: Array = []        # {owner, ck, si, e, state("cd"/"wind"/"beam"), t, tgt, start, acc}
var _revives: Array = []      # {u, t0, from_hp, to_hp}
var _gold_coins := {"left": 0, "right": 0}
## 本场每件黄金面具新涨的层数(结算时写回背包那一件; 键 = 装备实例键 ck)
var gold_gain := {}


var ow: OtherworldSystem      # 136 千面【里世界】
## 观众此刻看的是不是里世界(画面层; 不进 sim)
var ow_view := false


## 画面: 这个单位此刻该不该隐去(里世界开着时, 不在观众正在看的那个世界里)
func ow_hidden(u: Dictionary) -> bool:
	return ow.active and bool(u.get("_ow", false)) != ow_view


func _init(b) -> void:
	battle = b
	vfx = MaskEqVfx.new(b)
	ow = OtherworldSystem.new(b)


func _fx(method: String, args: Array = []) -> void:
	if vfx != null and vfx.has_method(method):
		vfx.callv(method, args)


# ════════════════════════════════════════ 小工具 ════════════════════════════════════════

func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	var side := str(battle._eff_side(u))
	for o in battle._units:
		if not (o is Dictionary) or not o.get("alive", false):
			continue
		if str(battle._eff_side(o)) == side or bool(o.get("_isEgg", false)) or battle._is_untouchable(o):
			continue
		if OtherworldSystem.separated(u, o):
			continue
		out.append(o)
	return out


func _acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_mask_acc", {})
	return float(d.get(key, 0.0))


func _set_acc(u: Dictionary, key: String, v: float) -> void:
	var d: Dictionary = u.get("_mask_acc", {})
	d[key] = v
	u["_mask_acc"] = d


func _en_gain(u: Dictionary, delta: float) -> float:
	var t := float(battle._t)
	if t < float(u.get("stun_until", 0.0)) or t < float(u.get("channel_until", 0.0)) or bool(u.get("airborne", false)) \
			or t < float(u.get("energy_lock_until", 0.0)):
		return 0.0
	return delta / SEC_PER_ENERGY * maxf(0.0, float(u.get("echarge_perm", 1.0)))


func _nearest_enemy(u: Dictionary, excl: Array = []):
	var best = null
	var bd := INF
	for o in _enemies_of(u):
		var skip := false
		for x in excl:
			if is_same(x, o):
				skip = true
		if skip or battle._is_untargetable(o):
			continue
		var d: float = DetMath.dist(Vector2(u["pos"]), Vector2(o["pos"]))
		if d < bd:
			bd = d
			best = o
	return best


func _true_dmg(src: Dictionary, tgt: Dictionary, amt: float) -> void:
	if not tgt.get("alive", false) or amt < 0.5:
		return
	battle._damage._apply_damage_from(src, tgt, int(round(amt)), COL_TRUE, 0.0, true, true)


static func _si_of(e: Dictionary) -> int:
	return clampi(int(e.get("star", 1)), 1, 3) - 1


func _count(u: Dictionary, eid: String) -> int:
	var n := 0
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == eid:
			n += 1
	return n


# ════════════════════════════════════════ 伤害管线里调的静态口 ════════════════════════════════════════

## 127 纸面具: 物理伤害先扣物理护盾(先于普通盾); 返回剩余伤害。与 012 海藻的魔法护盾对称。
static func phys_absorb(u: Dictionary, d: float, is_phys: bool) -> float:
	if not is_phys or d <= 0.0:
		return d
	var ps: float = float(u.get("phys_shield", 0.0))
	if ps <= 0.0:
		return d
	var ab: float = minf(ps, d)
	u["phys_shield"] = ps - ab
	return d - ab


## 128 狐狸面具: 对最大生命值比自己高的目标增伤(差 2000 到顶)。多件相加。
static func fox_amp(u: Dictionary, tgt: Dictionary) -> float:
	var mx: float = float(u.get("_fox_max", 0.0))
	if mx <= 0.0:
		return 0.0
	var diff: float = float(tgt.get("maxHp", 0.0)) - float(u.get("maxHp", 0.0))
	if diff <= 0.0:
		return 0.0
	return mx * minf(1.0, diff / FOX_FULL_DIFF)


## 133 防毒面具: 灼烧 / 中毒 / 流血 施加前调; true = 免疫(不上层)
func dot_immune(u: Dictionary, type: String) -> bool:
	if not bool(u.get("_gas_mask", false)) or not GAS_IMMUNE.has(type):
		return false
	stat["gas_block"] += 1
	_fx("gas_block", [u])
	return true


## 134 威尼斯面具: 受到致命伤害时调(两条伤害路径都接)。返回改写后的这段伤害(留 1 点血)。
func revive(u: Dictionary, d: float) -> float:
	if not bool(u.get("_ven_ready", false)) or float(u["hp"]) - d > 0.0:
		return d
	u["_ven_ready"] = false
	var si: int = int(u.get("_ven_si", 0))
	var t := float(battle._t)
	stat["revive"] += 1
	u["deathfloor_until"] = maxf(float(u.get("deathfloor_until", 0.0)), t + VEN_SEC)   # 2.5 秒内血量不会再掉到 1 以下
	u["untargetable_until"] = maxf(float(u.get("untargetable_until", 0.0)), t + VEN_SEC)
	battle._damage.channel(u, VEN_SEC)                                                 # 倒地期间不行动
	u["_ven_until"] = t + VEN_SEC
	_revives.append({"u": u, "t0": t, "to": float(u.get("maxHp", 1.0)) * float(VEN_HEAL[si])})
	_fx("venice_down", [u, VEN_SEC])
	return maxf(0.0, float(u["hp"]) - 1.0)


# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════

func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	var ck: String = battle._equip_sys.key_of(u, eid)
	match eid:
		"p2eq_127":   # 纸面具①: 登场物理护盾(打空为止, 不随时间消失 —— 同海藻魔法护盾)
			var amt: float = float(u.get("maxHp", 0.0)) * float(PAPER_SHIELD_PCT[si])
			u["phys_shield"] = float(u.get("phys_shield", 0.0)) + amt
			_fx("paper_shield", [u])
		"p2eq_128":
			u["_fox_max"] = float(u.get("_fox_max", 0.0)) + float(FOX_MAX[si])
		"p2eq_129":   # 京剧脸谱: 开打红脸
			_set_acc(u, "face:" + ck, 0.0)
			_set_acc(u, "facet:" + ck, 0.0)
			_face_enter(u, ck, si, 0)
		"p2eq_130":
			_spawn_lion(u, si)
		"p2eq_132":
			_set_acc(u, "ghost_used:" + ck, 0.0)
		"p2eq_133":
			u["_gas_mask"] = true
			u["_gas_move"] = 0.0
		"p2eq_134":
			u["_ven_ready"] = true
			u["_ven_si"] = maxi(int(u.get("_ven_si", 0)), si)
		"p2eq_135":
			_gold_spawn(u, ck, si)
		"p2eq_136":
			ow.add_carrier(u, si)


func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	var ck: String = battle._equip_sys.key_of(u, eid)
	if eid == "p2eq_129":
		var face := int(_acc(u, "face:" + ck))
		if face == 0:     # 红脸: 额外真实伤害
			_true_dmg(u, tgt, float(FACE_RED_TRUE[si]) * float(u.get("atk", 0.0)))
			_fx("face_red_hit", [u, tgt])
		elif face == 2:   # 白脸: 偷龟能
			var take: float = minf(float(FACE_WHITE_EN[si]), float(tgt.get("energy", 0.0)))
			if take > 0.0:
				tgt["energy"] = float(tgt["energy"]) - take
			u["energy"] = minf(float(u.get("maxEnergy", 100.0)), float(u.get("energy", 0.0)) + float(FACE_WHITE_EN[si]))
			_fx("face_white_steal", [u, tgt])


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 127 纸面具②: 每受到一段攻击或技能伤害, 朝攻击者飞一片纸, 碰到才结算(自身护甲 × 比例 的物理伤害)。持续伤害不触发。
func on_damaged(u: Dictionary, src, _dmg: float, eid: String, si: int) -> void:
	if eid != "p2eq_127" or bool(u.get("_b4_dot", false)) or not (src is Dictionary) or is_same(src, u):
		return
	if not (src as Dictionary).get("alive", false):
		return
	var amt: float = float(u.get("def", 0.0)) * float(PAPER_COUNTER[si])
	if amt < 0.5:
		return
	stat["paper_counter"] += 1
	var s: Dictionary = src
	var ck: String = battle._equip_sys.key_of(u, eid)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	var shot = null
	if vfx != null and vfx.has_method("paper_shot"):
		shot = vfx.paper_shot(u, s)
	var me: Dictionary = u
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), s, PAPER_SPD,
		func(hit: bool) -> void:
			if vfx != null and vfx.has_method("paper_shot_end"):
				vfx.paper_shot_end(shot, hit)
			if not hit or not me.get("alive", false):
				return
			var d: int = battle._phys_after_armor(me, amt, s)
			battle._damage._apply_damage_from(me, s, d, COL_PHYS, 0.0, false, true))
	battle._equip_sys.tally.pop(tp)


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_kill(_killer: Dictionary, _victim: Dictionary, _eid: String, _si: int) -> void:
	pass


## 任何单位普攻: 132 鬼面潜行时攻击即现形; 舞狮攻击攒龟能
func on_any_basic(u: Dictionary, _tgt) -> void:
	if bool(u.get("_ghost_hidden", false)):
		u["_ghost_hidden"] = false
		u["untargetable_until"] = minf(float(u.get("untargetable_until", 0.0)), float(battle._t))
		_fx("ghost_reveal", [u])
	if str(u.get("id", "")) == "_summon_mask_lion":
		for L in _lions:
			if is_same(L["u"], u):
				L["en"] = minf(LION_EN_MAX, float(L["en"]) + LION_EN_PER_HIT)


# ════════════════════════════════════════ 131 小丑面具(释放技能后) ════════════════════════════════════════

func on_unit_cast(u: Dictionary, _tgt, _stype: String, cost: float, _echo: bool) -> void:
	if u.get("equips", []).is_empty() or not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u["equips"]:
		if not (e is Dictionary) or str((e as Dictionary).get("id", "")) != "p2eq_131":
			continue
		var si := _si_of(e)
		es.ck_set(u, e)
		var tl: Array = es.tally.push(u, es.key_of(u, "p2eq_131"))
		stat["clown"] += 1
		var sec: float = maxf(0.0, cost) / 100.0 * float(CLOWN_SEC_PER_100[si])
		var tg: Array = []
		for o in _enemies_of(u):
			if DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= CLOWN_R:
				tg.append(o)
		if sec > 0.0 and not tg.is_empty():
			battle._taunt(u, tg, sec)
		battle._damage._grant_shield(u, float(u.get("maxHp", 0.0)) * float(CLOWN_SHIELD_PCT[si]), CLOWN_SHIELD_SEC)
		_fx("clown_taunt", [u, tg, sec])
		es.tally.pop(tl)
	es.ck_restore(ckp)


# ════════════════════════════════════════ 129 京剧脸谱 ════════════════════════════════════════

## 进入第 face 张脸(0 红 / 1 黑 / 2 白), 先卸掉上一张脸给的属性
func _face_enter(u: Dictionary, ck: String, si: int, face: int) -> void:
	_face_leave(u, ck)
	_set_acc(u, "face:" + ck, float(face))
	match face:
		1:
			u["flat_dr"] = float(u.get("flat_dr", 0.0)) + float(FACE_BLACK_FLAT[si])
			u["base_def"] = float(u.get("base_def", 0.0)) + float(FACE_BLACK_RES[si])
			u["base_mr"] = float(u.get("base_mr", 0.0)) + float(FACE_BLACK_RES[si])
			_set_acc(u, "facegiv:" + ck, 1.0)
			_set_acc(u, "facesi:" + ck, float(si))
			battle._recalc_stats(u)
		2:
			u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + float(FACE_WHITE_ASPD[si])
			_set_acc(u, "facegiv:" + ck, 2.0)
			_set_acc(u, "facesi:" + ck, float(si))
		_:
			_set_acc(u, "facegiv:" + ck, 0.0)
	_fx("face_swap", [u, face])


func _face_leave(u: Dictionary, ck: String) -> void:
	var giv := int(_acc(u, "facegiv:" + ck))
	var si := int(_acc(u, "facesi:" + ck))
	if giv == 1:
		u["flat_dr"] = maxf(0.0, float(u.get("flat_dr", 0.0)) - float(FACE_BLACK_FLAT[si]))
		u["base_def"] = float(u.get("base_def", 0.0)) - float(FACE_BLACK_RES[si])
		u["base_mr"] = float(u.get("base_mr", 0.0)) - float(FACE_BLACK_RES[si])
		battle._recalc_stats(u)
	elif giv == 2:
		u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) - float(FACE_WHITE_ASPD[si])
	_set_acc(u, "facegiv:" + ck, 0.0)


# ════════════════════════════════════════ 130 舞狮头 ════════════════════════════════════════

func _spawn_lion(owner: Dictionary, si: int) -> Dictionary:
	var p = battle._spawn._spawn_summon(owner, "mask_lion", float(LION_HP[si]), float(LION_ATK[si]),
		{"label": "舞狮", "spr_id": "eq-mask-lion", "col_size": 52.0, "hp_w": 40.0,
		 "atk_interval": 1.0, "atk_range": 70.0, "melee": true})
	if p == null:
		return {}
	p["def"] = float(LION_RES[si]); p["base_def"] = p["def"]
	p["mr"] = float(LION_RES[si]); p["base_mr"] = p["mr"]
	p["maxEnergy"] = LION_EN_MAX
	p["energy"] = 0.0
	var rec := {"u": p, "owner": owner, "si": si, "en": LION_EN_MAX if bool(owner.get("_edit_fe", false)) else 0.0,
		"state": "idle", "t": 0.0, "dir": Vector2.RIGHT, "from": Vector2.ZERO, "hit": []}
	_lions.append(rec)
	_fx("lion_spawn", [p])
	return rec


func lion_state(i: int = 0) -> Dictionary:
	return _lions[i] if i < _lions.size() else {}


func _tick_lions(delta: float) -> void:
	for L in _lions:
		var p: Dictionary = L["u"]
		if not p.get("alive", false):
			continue
		match str(L["state"]):
			"idle":
				L["en"] = minf(LION_EN_MAX, float(L["en"]) + _en_gain(p, delta))
				p["energy"] = float(L["en"])
				if float(L["en"]) < LION_EN_MAX:
					continue
				var tgt = p.get("target", null)
				if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
					tgt = _nearest_enemy(p)
				if not (tgt is Dictionary):
					continue
				L["en"] = 0.0
				p["energy"] = 0.0
				battle._magic_syn.on_cast(p, LION_EN_MAX)   # 魔法书【飞弹】: 召唤物放技能也算
				var dv: Vector2 = Vector2((tgt as Dictionary)["pos"]) - Vector2(p["pos"])
				L["dir"] = dv.normalized() if dv.length() > 1.0 else Vector2(1.0 if str(battle._eff_side(p)) == "left" else -1.0, 0.0)
				L["state"] = "wind"
				L["t"] = 0.0
				L["hit"] = []
				battle._damage.channel(p, LION_WINDUP + LION_DIST / LION_SPD + 0.1)
				_fx("lion_windup", [p, L["dir"], LION_WINDUP])
			"wind":
				L["t"] = float(L["t"]) + delta
				if float(L["t"]) >= LION_WINDUP:
					L["state"] = "run"
					L["t"] = 0.0
					L["from"] = Vector2(p["pos"])
					stat["lion_charge"] += 1
					_fx("lion_run", [p, L["dir"]])
			"run":
				var a: Vector2 = Vector2(p["pos"])
				var step: float = LION_SPD * delta
				L["t"] = float(L["t"]) + step
				var b: Vector2 = a + Vector2(L["dir"]) * step
				b = ArenaShape.clamp_in(b, battle.ARENA, 40.0)
				p["pos"] = b
				for o in _enemies_of(p):
					var already := false
					for h in L["hit"]:
						if is_same(h, o):
							already = true
					if already:
						continue
					var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(o["pos"]), a, b)
					if DetMath.dist(q, Vector2(o["pos"])) <= LION_W + float(o.get("col_size", 22.0)) * 0.5:
						(L["hit"] as Array).append(o)
						_lion_hit(L, o)
				if float(L["t"]) >= LION_DIST or b.distance_to(a) < step * 0.5:
					L["state"] = "idle"
					_fx("lion_stop", [p])


func _lion_hit(L: Dictionary, o: Dictionary) -> void:
	var p: Dictionary = L["u"]
	var si := int(L["si"])
	stat["lion_hit"] += 1
	var dmg: int = battle._resolve_dmg(p, float(LION_CHARGE_ATK[si]) * float(p.get("atk", 0.0)), o, false)
	battle._damage._apply_damage_from(p, o, dmg, COL_PHYS, 0.0, false, true)
	if o.get("alive", false):
		battle._damage._knockback(p, o, 0.0)
		battle._damage._stun(o, float(LION_STUN[si]), "mask_lion")
	_fx("lion_hit", [p, o])


# ════════════════════════════════════════ 135 黄金面具 ════════════════════════════════════════

func _gold_spawn(u: Dictionary, ck: String, si: int) -> void:
	var e = _entry_of(u, "p2eq_135", ck)
	## 层数 = 背包里这一件攒下的(gm_stk) + 本场前几路新涨的(换路重建单位字典, 所以本场的另记一本)
	var stk: int = (int((e as Dictionary).get("gm_stk", 0)) if e is Dictionary else 0) + int(gold_gain.get(_gold_key(u, ck), 0))
	if stk > 0:   # 往期攒下的层数: 每层 +最大生命值 +攻击力(只记在这一件上)
		u["maxHp"] = float(u.get("maxHp", 0.0)) + GOLD_STK_HP * stk
		u["hp"] = float(u.get("hp", 0.0)) + GOLD_STK_HP * stk
		u["base_atk"] = float(u.get("base_atk", 0.0)) + GOLD_STK_ATK * stk
		battle._recalc_stats(u)
	_beams.append({"owner": u, "ck": ck, "si": si, "state": "wind0", "t": 0.0, "tgt": null, "start": 0.0, "acc": 0.0, "stk0": stk})


## 找出实例键为 ck 的那一件装备字典(层数记在背包里的那件上)
func _entry_of(u: Dictionary, eid: String, ck: String):
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	var out = null
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == eid:
			es.ck_set(u, e)
			if es.key_of(u, eid) == ck:
				out = e
				break
	es.ck_restore(ckp)
	return out


func beam_state(i: int = 0) -> Dictionary:
	return _beams[i] if i < _beams.size() else {}


func _gold_pick(u: Dictionary):
	var tgt = u.get("target", null)
	if tgt is Dictionary and (tgt as Dictionary).get("alive", false) and not _beamed(tgt) and not battle._is_untouchable(tgt) \
			and str(battle._eff_side(tgt)) != str(battle._eff_side(u)) and not OtherworldSystem.separated(u, tgt):
		return tgt
	var taken: Array = []
	for B in _beams:
		if B["tgt"] is Dictionary:
			taken.append(B["tgt"])
	return _nearest_enemy(u, taken)


func _beamed(o) -> bool:
	for B in _beams:
		if is_same(B["tgt"], o) and str(B["state"]) != "cd":
			return true
	return false


func _tick_beams(delta: float) -> void:
	for B in _beams:
		var u: Dictionary = B["owner"]
		if not u.get("alive", false):
			if B["tgt"] != null:
				_fx("gold_end", [B])
				B["tgt"] = null
			continue
		var si := int(B["si"])
		match str(B["state"]):
			"wind0", "cd":
				B["t"] = float(B["t"]) + delta
				if str(B["state"]) == "cd" and float(B["t"]) < GOLD_CD:
					continue
				var tgt = _gold_pick(u)
				if not (tgt is Dictionary):
					continue
				B["tgt"] = tgt
				B["state"] = "wind"
				B["t"] = 0.0
				stat["gold_beam"] += 1
				_fx("gold_cast", [u, tgt, GOLD_DELAY, B])
			"wind":
				B["t"] = float(B["t"]) + delta
				var tg = B["tgt"]
				if not (tg is Dictionary) or not (tg as Dictionary).get("alive", false):
					B["state"] = "cd"; B["t"] = GOLD_CD   # 还没落地目标就没了: 立刻重新找
					B["tgt"] = null
					_fx("gold_end", [B])
					continue
				if float(B["t"]) >= GOLD_DELAY:
					B["state"] = "beam"
					B["start"] = float(battle._t)
					B["acc"] = 0.0
					_fx("gold_land", [B])
			"beam":
				var tg2 = B["tgt"]
				if not (tg2 is Dictionary) or not (tg2 as Dictionary).get("alive", false):
					B["state"] = "cd"; B["t"] = 0.0; B["tgt"] = null
					_fx("gold_end", [B])
					continue
				var o: Dictionary = tg2
				B["acc"] = float(B["acc"]) + delta
				while float(B["acc"]) >= GOLD_TICK and o.get("alive", false):
					B["acc"] = float(B["acc"]) - GOLD_TICK
					var el: float = float(battle._t) - float(B["start"])
					var dps: float = (float(GOLD_FLAT[si]) + float(GOLD_PCT[si]) * float(o.get("maxHp", 0.0))) \
						* (1.0 + float(GOLD_RAMP[si]) * floorf(el))
					var tl: Array = battle._equip_sys.tally.push(u, str(B["ck"]))
					_true_dmg(u, o, dps * GOLD_TICK)
					battle._equip_sys.tally.pop(tl)
				if not o.get("alive", false):
					_gold_kill(B, o)
					B["state"] = "cd"; B["t"] = 0.0; B["tgt"] = null
					_fx("gold_end", [B])


## 金光打死了东西(什么都算: 统领 / 小将 / 召唤物 / 复制体): 出 1 枚深海币 + 这件面具 +1 层(当场生效)
func _gold_kill(B: Dictionary, victim: Dictionary) -> void:
	var u: Dictionary = B["owner"]
	stat["gold_kill"] += 1
	var side := str(u.get("side", "left"))
	_gold_coins[side] = int(_gold_coins.get(side, 0)) + 1
	var gk := _gold_key(u, str(B["ck"]))
	gold_gain[gk] = int(gold_gain.get(gk, 0)) + 1
	u["maxHp"] = float(u.get("maxHp", 0.0)) + GOLD_STK_HP
	u["hp"] = float(u.get("hp", 0.0)) + GOLD_STK_HP
	u["base_atk"] = float(u.get("base_atk", 0.0)) + GOLD_STK_ATK
	battle._recalc_stats(u)
	_fx("gold_coin", [u, victim])


## 本场层数账的键: 一方 + 龟 + 份号(换路后同一只龟、同一件拿到同一个键)
## ⚠ 小将共用 id "__minion__": 同一方两只小将各带一件黄金面具时会记到一起(罕见; 写回背包时再按槽位区分)
func _gold_key(u: Dictionary, ck: String) -> String:
	return "%s|%s|%s" % [str(u.get("side", "")), str(u.get("id", "")), ck]


## 本场(上路 + 下路 + 决胜)金光打出来的深海币(EquipTickSystem.match_minted 统一出口读)
func gold_minted(side: String = "left") -> int:
	return int(_gold_coins.get(side, 0))


# ════════════════════════════════════════ 帧推进 ════════════════════════════════════════

func tick(delta: float) -> void:
	_tick_lions(delta)
	_tick_beams(delta)
	_tick_revives()
	ow.tick(delta)
	if vfx != null:
		vfx.tick(delta)


func _tick_revives() -> void:
	var t := float(battle._t)
	var keep: Array = []
	for R in _revives:
		var u: Dictionary = R["u"]
		if not u.get("alive", false):
			continue
		var k: float = clampf((t - float(R["t0"])) / VEN_SEC, 0.0, 1.0)
		u["hp"] = maxf(float(u["hp"]), maxf(1.0, float(R["to"]) * k))   # 2.5 秒里血量逐渐涨到 30/45/70%
		if k < 1.0:
			keep.append(R)
		else:
			_fx("venice_up", [u])
	_revives = keep


func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		if eid != "p2eq_129" and eid != "p2eq_132" and eid != "p2eq_133":
			continue
		var si := _si_of(e)
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		match eid:
			"p2eq_129":   # 每 8 秒换脸: 红 → 黑 → 白
				var a := _acc(u, "facet:" + ck) + delta
				if a >= FACE_IV:
					a -= FACE_IV
					stat["face_swap"] += 1
					_face_enter(u, ck, si, (int(_acc(u, "face:" + ck)) + 1) % 3)
				_set_acc(u, "facet:" + ck, a)
			"p2eq_132":   # 生命值第一次降到 50%: 潜行(攻击现形) + 潜行期间每秒回血; 每路一次
				if _acc(u, "ghost_used:" + ck) == 0.0 and float(u["hp"]) <= float(u.get("maxHp", 1.0)) * GHOST_LINE:
					_set_acc(u, "ghost_used:" + ck, 1.0)
					stat["ghost"] += 1
					var t := float(battle._t)
					u["untargetable_until"] = maxf(float(u.get("untargetable_until", 0.0)), t + float(GHOST_SEC[si]))
					u["_ghost_hidden"] = true
					u["_ghost_regen"] = float(GHOST_REGEN[si])
					_fx("ghost_hide", [u, float(GHOST_SEC[si])])
				if bool(u.get("_ghost_hidden", false)):
					if float(battle._t) >= float(u.get("untargetable_until", 0.0)):
						u["_ghost_hidden"] = false
						_fx("ghost_reveal", [u])
					else:
						battle._damage._heal(u, float(u.get("maxHp", 0.0)) * float(u.get("_ghost_regen", 0.0)) * delta)
			"p2eq_133":   # 每损失 1% 生命值 +1% 移动速度(每帧按当前血量重算)
				var lost: float = clampf(1.0 - float(u["hp"]) / maxf(1.0, float(u.get("maxHp", 1.0))), 0.0, 1.0)
				var want: float = lost * 100.0 * GAS_MOVE_PER_PCT * float(_count(u, "p2eq_133"))
				var had: float = float(u.get("_gas_move", 0.0))
				if absf(want - had) > 1e-6:
					u["move_perm"] = float(u.get("move_perm", 1.0)) + (want - had)
					u["_gas_move"] = want
	es.ck_restore(ckp)


func clear_all() -> void:
	_lions.clear(); _beams.clear(); _revives.clear()
	ow.clear_all()
	if vfx != null and vfx.has_method("clear"):
		vfx.clear()


## 一局结束(不是换路): 深海币与层数账清零
func reset_match() -> void:
	_gold_coins = {"left": 0, "right": 0}
	gold_gain.clear()
