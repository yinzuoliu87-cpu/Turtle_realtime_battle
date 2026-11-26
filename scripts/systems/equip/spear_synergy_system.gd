class_name SpearSynergySystem
extends RefCounted
## 长矛羁绊【百夫长】(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md)
##
## 用户 11-26(原话摘要, 全文见方案书第 1 节):
##   「羁绊效果是召唤物的形式…二五八十档」「高血量中等输出的战士…登场时会有群控」「有自己的普攻…独特的技能和被动…每次升档…属性进行强化，同时技能…有更加多的效果」
##   「开始第八秒，或者团队生命值低于百分之六十时…登场」「击飞半径是全场」「(击飞)时长是所有档固定的…伤害…百分之一百五十的召唤物的魔法伤害」
##   「每个独特的长矛类装备…每个星级都会使这个…最大生命值和攻击提升一个百分比」
##
## ── 规则 ──────────────────────────────────────────────────────
## · 每一路一次: 开打第 SUMMON_AT 秒, 或我方团队生命值(统领 + 小将, 死的算 0)低于 TEAM_HP_LINE, 先到先算 ⇒ 百夫长从天而降。
## · 登场: 全场所有敌人击飞 KNOCK_SEC 秒, 受到百夫长攻击力 ENTRY_COEF 的魔法伤害(里世界里的人不算 —— 走 _is_hostile)。
## · 属性 = 档位底子 × (1 + 每件不同长矛的星级合计 × STAR_PCT); 护甲魔抗只按档位。
## · 普攻(逐档叠加): 1 近战突刺 / 2 贯穿直线, 身后的敌人吃 PIERCE_BEHIND, 线上都吃攻击特效 / 3 每刺削线上每个敌人 1 护甲 1 魔抗(每人至多 SHRED_CAP)
##   / 4 每第 THROW_EVERY 下改成掷矛: 扔向最远的敌人, 按速度飞、沿途贯穿 THROW_COEF, 矛不回手。
## · 技能【龟甲阵】(龟能满): 1 举盾 SHIELD_SEC 秒减伤 SHIELD_DR / 2 放盾横扫周围每个敌人 SWEEP_COEF 魔法 / 3 举盾期间每 POKE_IV 秒刺周围 POKE_COEF 魔法
##   / 4 横扫后我方身后地图边缘冲出 CAV_N 名持矛骑兵, 各冲一名随机敌人, 路上碰到的每个敌人吃 CAV_COEF 物理 + 击飞击退(每步线段碰撞)。
const SUMMON_AT := 8.0
const TEAM_HP_LINE := 0.60
const KNOCK_SEC := 1.5
const CENT_KNOCK_VY := 16.5            # 滞空 = 2 × 16.5 / 22 = 1.5 秒
const ENTRY_COEF := 1.5
## 从天而降的时长: 召唤那一刻人在高处(不可选中、不行动), 落地那一步才结算全场击飞 + 魔法伤害(画面与结算同一刻;
##   11-26 夜用户「召唤物的登场，登场动画…别敷衍了」—— 原来召唤那一帧就结算, 人还在半空)
const LAND_SEC := 0.7
const HP := [1600.0, 2600.0, 3600.0, 5200.0]
const ATK := [48.0, 72.0, 104.0, 144.0]
const RES := [45.0, 70.0, 110.0, 140.0]
const STAR_PCT := 0.03
const RANGE := 110.0              # 长柄: 比一般近战(70)够得远
const LINE_LEN := 260.0           # 贯穿那条线从目标往后再延多远
const LINE_W := 34.0
const PIERCE_BEHIND := 0.5
const SHRED_CAP := 30.0
const THROW_EVERY := 4
const THROW_COEF := 2.0
const THROW_SPD := 900.0
const THROW_W := 30.0
const EN_MAX := 100.0
const SEC_PER_ENERGY := 0.075
const SHIELD_SEC := 3.0
const SHIELD_DR := 0.20
const SWEEP_R := 260.0
const SWEEP_COEF := 1.2
const POKE_IV := 0.5
const POKE_R := 200.0
const POKE_COEF := 0.4
const CAV_N := 4
const CAV_SPD := 520.0
const CAV_COEF := 1.5
const CAV_W := 40.0
const CAV_VY := 8.25              # 骑兵撞飞滞空 0.75 秒
const CAV_MAX := 2200.0           # 冲锋最长距离(到不了就散)
const ID := "_summon_centurion"
const COL_PHYS := Color("#ff9a4a")
const COL_MAGIC := Color("#4dabf7")

var battle
var vfx = null
var _lane_t0 := -1.0
var _done := {"left": false, "right": false}
var _cents: Array = []      # {u, side, tier, n_atk, en, state, t, poke}
var _spears: Array = []     # 掷出的矛 {src, pos, dir, left, hit:[]}
var _cavs: Array = []       # 骑兵 {src, pos, tgt, dir, hit:[], left}
## 门禁量
var stat := {"summon": 0, "entry_hits": 0, "pierce": 0, "shred": 0, "throw": 0, "throw_hit": 0, "shield": 0, "sweep": 0, "poke": 0, "cav": 0, "cav_hit": 0}


func _init(b) -> void:
	battle = b


func _fx(method: String, args: Array = []) -> void:
	if vfx == null:
		var sc = load("res://scripts/scenes/battle/spear_eq_vfx.gd") if ResourceLoader.exists("res://scripts/scenes/battle/spear_eq_vfx.gd") else null
		vfx = sc.new(battle) if sc != null else null
	if vfx != null and vfx.has_method(method):
		vfx.callv(method, args)


func side_tier(side: String) -> int:
	var t := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			t = maxi(t, int(battle._synergy.tier_for(u, "长矛")))
	return t


## 这一方全阵容里每件不同长矛的星级合计(同名只算一件, 取最高星)
func star_sum(side: String) -> int:
	var best := {}
	for e in _roster_equips(side):
		if not (e is Dictionary):
			continue
		var id := str((e as Dictionary).get("id", ""))
		if not battle.Phase2Types.types_of(id).has("长矛"):
			continue
		best[id] = maxi(int(best.get(id, 0)), clampi(int((e as Dictionary).get("star", 1)), 1, 3))
	var n := 0
	for k in best:
		n += int(best[k])
	return n


func _roster_equips(side: String) -> Array:
	var out: Array = []
	if side == "left" and GameState != null and GameState.has_method("team_p2_equips_for_synergy"):
		for it in GameState.team_p2_equips_for_synergy():
			out.append(it)
	elif side == "right" and GameState != null and GameState.dual_ghost is Dictionary and battle.has_method("_dual_foe_lane"):
		for lane in ["top", "bottom"]:
			for spec in battle._dual_foe_lane(lane):
				if spec is Dictionary:
					out.append_array((spec as Dictionary).get("equips", []))
	if not out.is_empty():
		return out
	for u in battle._units:   # 退路: 场上单位(合成门禁 / 演示台)
		if u is Dictionary and str(u.get("side", "")) == side and not bool(u.get("is_summon", false)) and not bool(u.get("_mask_copy", false)):
			out.append_array(u.get("equips", []))
	return out


## 我方团队生命值比例(统领 + 小将; 死的算 0; 召唤物 / 龟蛋 / 训龟大师 / 面具复制体不算)
func team_hp_ratio(side: String) -> float:
	var cur := 0.0
	var mx := 0.0
	for u in battle._units:
		if not (u is Dictionary) or str(u.get("side", "")) != side:
			continue
		if bool(u.get("is_summon", false)) or bool(u.get("_isEgg", false)) or battle._is_untouchable(u) or bool(u.get("_mask_copy", false)):
			continue
		mx += float(u.get("maxHp", 0.0))
		if u.get("alive", false):
			cur += maxf(0.0, float(u.get("hp", 0.0)))
	return cur / mx if mx > 0.0 else 1.0


func tick(delta: float) -> void:
	var t0 := float(battle._sd_t0)
	if t0 != _lane_t0:
		_lane_t0 = t0
		_done = {"left": false, "right": false}
		_cents.clear()   # 换路: 单位字典整体重建, 上一路的百夫长 / 飞矛 / 骑兵全部作废
		_spears.clear()
		_cavs.clear()
	if not bool(battle.get("_over")):
		var el: float = float(battle._t) - t0
		for side in ["left", "right"]:
			if bool(_done[side]):
				continue
			var tier := side_tier(side)
			if tier <= 0:
				continue
			if el >= SUMMON_AT or team_hp_ratio(side) < TEAM_HP_LINE:
				_done[side] = true
				summon(side, tier)
	_tick_cents(delta)
	_tick_spears(delta)
	_tick_cavs(delta)
	if vfx != null and vfx.has_method("tick"):
		vfx.tick(delta)


## 召唤百夫长(门禁可直接调)
func summon(side: String, tier: int) -> Dictionary:
	var owner = null
	for u in battle._units:
		if u is Dictionary and u.get("alive", false) and str(u.get("side", "")) == side and not bool(u.get("is_summon", false)) \
				and not bool(u.get("_isEgg", false)) and not battle._is_untouchable(u):
			owner = u
			break
	if not (owner is Dictionary):
		return {}
	## 直接调用(门禁 / 演示台)时也对齐路次并记成这一路已召过 —— 否则下一帧 tick 当成换路把它清掉, 或到第 8 秒再召一只
	if float(battle._sd_t0) != _lane_t0:
		_lane_t0 = float(battle._sd_t0)
		_done = {"left": false, "right": false}
	_done[side] = true
	var ti: int = clampi(tier, 1, 4) - 1
	var k: float = 1.0 + float(star_sum(side)) * STAR_PCT
	var p = battle._spawn._spawn_summon(owner, "centurion", float(HP[ti]) * k, float(ATK[ti]) * k,
		{"label": "百夫长", "spr_id": "eq-centurion", "col_size": 60.0, "hp_w": 44.0, "atk_interval": 1.0, "atk_range": RANGE, "melee": true})
	if p == null:
		return {}
	p["def"] = float(RES[ti]); p["base_def"] = p["def"]
	p["mr"] = float(RES[ti]); p["base_mr"] = p["mr"]
	p["maxEnergy"] = EN_MAX
	p["energy"] = 0.0
	p["_cent_tier"] = tier
	## 落点: 我方阵地往前(两军之间偏我方)
	var cx: float = float(battle._arena_center.x)
	var fwd: float = -1.0 if side == "left" else 1.0
	p["pos"] = battle._dl_sys.clamp_place_side(Vector2(cx + fwd * 220.0, float(battle._arena_center.y)), side) if battle.get("_dl_sys") != null else Vector2(cx + fwd * 220.0, float(battle._arena_center.y))
	var rec := {"u": p, "side": side, "tier": tier, "n_atk": 0, "en": 0.0, "state": "landing", "t": 0.0, "poke": 0.0}
	_cents.append(rec)
	stat["summon"] += 1
	p["untargetable_until"] = float(battle._t) + LAND_SEC
	battle._damage.channel(p, LAND_SEC)
	_fx("cent_land", [p, LAND_SEC])
	return rec


## 落地: 全场敌人击飞 1.5 秒 + 150% 攻击力魔法伤害(门禁可直接调, 跳过下落)
func _land(r: Dictionary) -> void:
	if str(r.get("state", "")) != "landing":
		return
	r["state"] = "idle"
	r["t"] = 0.0
	var p: Dictionary = r["u"]
	p["untargetable_until"] = minf(float(p.get("untargetable_until", 0.0)), float(battle._t))
	_fx("cent_impact", [p])
	for o in battle._targeting._enemies_of(p):
		if not o.get("alive", false):
			continue
		stat["entry_hits"] += 1
		var dmg: int = battle._resolve_dmg(p, ENTRY_COEF * float(p.get("atk", 0.0)), o, true, false)
		battle._damage._apply_damage_from(p, o, dmg, COL_MAGIC, 0.0, false, true)
		if o.get("alive", false):
			battle._knock_up(o, Vector2(o["pos"]) + Vector2(0.0, 1.0), CENT_KNOCK_VY)


func cent_state(i: int = 0) -> Dictionary:
	return _cents[i] if i < _cents.size() else {}


func _rec_of(u: Dictionary) -> Dictionary:
	for r in _cents:
		if is_same(r["u"], u):
			return r
	return {}


## 普攻(EquipSystem._eq_on_basic_attack 最前面经 on_any_basic 转来): 整段接管, 原普攻不打(`_basic_replaced`)
func on_any_basic(u: Dictionary, tgt) -> void:
	if str(u.get("id", "")) != ID or not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	var r: Dictionary = _rec_of(u)
	if r.is_empty():
		return
	var tier := int(r["tier"])
	u["_basic_replaced"] = true
	r["n_atk"] = int(r["n_atk"]) + 1
	## 4 档: 每第 4 下掷矛(扔向最远的敌人)
	if tier >= 4 and int(r["n_atk"]) % THROW_EVERY == 0:
		_throw(u)
		return
	var t: Dictionary = tgt
	var hits: Array = [t]
	if tier >= 2:   # 贯穿直线: 目标身后同一条线上的敌人
		var dir: Vector2 = DetMath.norm(Vector2(t["pos"]) - Vector2(u["pos"])) if DetMath.dist(Vector2(t["pos"]), Vector2(u["pos"])) > 1.0 else Vector2.RIGHT
		var behind: Array = []
		for o in battle._targeting._enemies_of(u):
			if is_same(o, t) or not o.get("alive", false):
				continue
			var rel: Vector2 = Vector2(o["pos"]) - Vector2(t["pos"])
			var along: float = rel.dot(dir)
			if along <= 0.0 or along > LINE_LEN:
				continue
			if battle._on_line(Vector2(t["pos"]), dir, Vector2(o["pos"]), LINE_W):
				behind.append(o)
		hits.append_array(behind)
		if not behind.is_empty():
			stat["pierce"] += 1
	for i in range(hits.size()):
		var o: Dictionary = hits[i]
		var sc: float = 1.0 if i == 0 else PIERCE_BEHIND
		battle._damage._apply_basic_hit_from(u, o, battle._atk_dmg(u, sc, o), COL_PHYS)
		if tier >= 3 and o.get("alive", false):
			_shred(o)
	_fx("cent_thrust", [u, t, hits.size()])


## 3 档: 削 1 护甲 1 魔抗, 每个敌人至多 30(当路有效 —— 换路重建单位字典自然清零)
func _shred(o: Dictionary) -> void:
	var cur: float = float(o.get("_cent_shred", 0.0))
	if cur >= SHRED_CAP:
		return
	o["_cent_shred"] = cur + 1.0
	o["def_shred"] = float(o.get("def_shred", 0.0)) + 1.0
	o["mr_shred"] = float(o.get("mr_shred", 0.0)) + 1.0
	battle._recalc_stats(o)
	stat["shred"] += 1


func _farthest_enemy(u: Dictionary):
	var best = null
	var bd := -1.0
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false) or battle._is_untargetable(o):
			continue
		var d: float = DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"]))
		if d > bd:
			bd = d
			best = o
	return best


func _throw(u: Dictionary) -> void:
	var f = _farthest_enemy(u)
	if not (f is Dictionary):
		return
	stat["throw"] += 1
	var dir: Vector2 = DetMath.norm(Vector2(f["pos"]) - Vector2(u["pos"]))
	var left: float = DetMath.dist(Vector2(f["pos"]), Vector2(u["pos"])) + 80.0
	var s := {"src": u, "pos": Vector2(u["pos"]), "dir": dir, "left": left, "hit": []}
	_spears.append(s)
	_fx("cent_throw", [u, s])


func _tick_spears(delta: float) -> void:
	var keep: Array = []
	for s in _spears:
		var u: Dictionary = s["src"]
		var a: Vector2 = s["pos"]
		var step: float = minf(THROW_SPD * delta, float(s["left"]))
		var b: Vector2 = a + Vector2(s["dir"]) * step
		s["pos"] = b
		s["left"] = float(s["left"]) - step
		for o in battle._targeting._enemies_of(u):
			if not o.get("alive", false):
				continue
			var already := false
			for h in s["hit"]:
				if is_same(h, o):
					already = true
			if already:
				continue
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(o["pos"]), a, b)
			if DetMath.dist(q, Vector2(o["pos"])) <= THROW_W + float(o.get("col_size", 22.0)) * 0.5:
				(s["hit"] as Array).append(o)
				stat["throw_hit"] += 1
				battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, THROW_COEF, o), COL_PHYS, 0.0, false, true)
				_fx("cent_spear_hit", [o])
		if float(s["left"]) > 0.5:
			keep.append(s)
		else:
			_fx("cent_spear_drop", [s])
	_spears = keep


## 技能【龟甲阵】
func _tick_cents(delta: float) -> void:
	for r in _cents:
		var u: Dictionary = r["u"]
		if not u.get("alive", false):
			if str(r["state"]) == "shield":
				_shield_off(r)
			continue
		var tier := int(r["tier"])
		match str(r["state"]):
			"landing":
				r["t"] = float(r["t"]) + delta
				if float(r["t"]) >= LAND_SEC:
					_land(r)
			"idle":
				r["en"] = minf(EN_MAX, float(r["en"]) + _en_gain(u, delta))
				u["energy"] = float(r["en"])
				if float(r["en"]) < EN_MAX:
					continue
				r["en"] = 0.0
				u["energy"] = 0.0
				r["state"] = "shield"
				r["t"] = 0.0
				r["poke"] = 0.0
				u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + SHIELD_DR
				battle._damage.channel(u, SHIELD_SEC + 0.05)
				battle._magic_syn.on_cast(u, EN_MAX)
				stat["shield"] += 1
				_fx("cent_shield", [u, SHIELD_SEC])
			"shield":
				r["t"] = float(r["t"]) + delta
				if tier >= 3:
					r["poke"] = float(r["poke"]) + delta
					while float(r["poke"]) >= POKE_IV:
						r["poke"] = float(r["poke"]) - POKE_IV
						_ring_magic(u, POKE_R, POKE_COEF, "poke")
						_fx("cent_poke", [u])
				if float(r["t"]) >= SHIELD_SEC:
					_shield_off(r)
					if tier >= 2:
						_ring_magic(u, SWEEP_R, SWEEP_COEF, "sweep")
						_fx("cent_sweep", [u])
					if tier >= 4:
						_cavalry(u, str(r["side"]))


func _shield_off(r: Dictionary) -> void:
	var u: Dictionary = r["u"]
	r["state"] = "idle"
	u["damage_reduction"] = maxf(0.0, float(u.get("damage_reduction", 0.0)) - SHIELD_DR)
	_fx("cent_shield_off", [u])


func _ring_magic(u: Dictionary, rad: float, coef: float, key: String) -> void:
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false) or DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) > rad:
			continue
		stat[key] += 1
		var dmg: int = battle._resolve_dmg(u, coef * float(u.get("atk", 0.0)), o, true, false)
		battle._damage._apply_damage_from(u, o, dmg, COL_MAGIC, 0.0, false, true)


func _en_gain(u: Dictionary, delta: float) -> float:
	var t := float(battle._t)
	if t < float(u.get("stun_until", 0.0)) or bool(u.get("airborne", false)) or t < float(u.get("energy_lock_until", 0.0)):
		return 0.0
	return delta / SEC_PER_ENERGY * maxf(0.0, float(u.get("echarge_perm", 1.0)))


## 4 档: 我方身后的地图边缘冲出 4 名持矛骑兵, 各冲一名随机敌人
func _cavalry(u: Dictionary, side: String) -> void:
	var foes: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false):
			foes.append(o)
	if foes.is_empty():
		return
	var ar: Rect2 = battle.ARENA
	var x0: float = ar.position.x + 30.0 if side == "left" else ar.position.x + ar.size.x - 30.0
	for i in range(CAV_N):
		var tgt: Dictionary = foes[battle._battle_rng.randi() % foes.size()]
		var y0: float = ar.position.y + ar.size.y * (0.2 + 0.6 * float(i) / float(maxi(1, CAV_N - 1)))
		var p0 := ArenaShape.clamp_in(Vector2(x0, y0), ar, 20.0)
		var dir: Vector2 = DetMath.norm(Vector2(tgt["pos"]) - p0)
		var c := {"src": u, "pos": p0, "dir": dir, "tgt": tgt, "hit": [], "left": CAV_MAX}
		_cavs.append(c)
		stat["cav"] += 1
		_fx("cent_cav", [c])


func _tick_cavs(delta: float) -> void:
	var keep: Array = []
	for c in _cavs:
		var u: Dictionary = c["src"]
		var a: Vector2 = c["pos"]
		var tgt = c["tgt"]
		var dir: Vector2 = c["dir"]
		var step: float = minf(CAV_SPD * delta, float(c["left"]))
		var b: Vector2 = a + dir * step
		c["pos"] = b
		c["left"] = float(c["left"]) - step
		for o in battle._targeting._enemies_of(u):
			if not o.get("alive", false):
				continue
			var already := false
			for h in c["hit"]:
				if is_same(h, o):
					already = true
			if already:
				continue
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(o["pos"]), a, b)
			if DetMath.dist(q, Vector2(o["pos"])) <= CAV_W + float(o.get("col_size", 22.0)) * 0.5:
				(c["hit"] as Array).append(o)
				stat["cav_hit"] += 1
				var dmg: int = battle._resolve_dmg(u, CAV_COEF * float(u.get("atk", 0.0)), o, false, false)
				battle._damage._apply_damage_from(u, o, dmg, COL_PHYS, 0.0, false, true)
				if o.get("alive", false):
					battle._knock_up(o, Vector2(o["pos"]) - dir * 40.0, CAV_VY)
				_fx("cent_cav_hit", [c, o])
		## 冲过目标所在处再跑一段就散(出了岛也散)
		var passed: bool = tgt is Dictionary and (Vector2(tgt["pos"]) - b).dot(dir) < -160.0
		if float(c["left"]) > 0.5 and not passed and ArenaShape.in_rect_shape(b, battle.ARENA, -40.0):
			keep.append(c)
		else:
			_fx("cent_cav_end", [c])
	_cavs = keep


func clear_all() -> void:
	_cents.clear()
	_spears.clear()
	_cavs.clear()
	if vfx != null and vfx.has_method("clear"):
		vfx.clear()


func reset_match() -> void:
	_lane_t0 = -1.0
	_done = {"left": false, "right": false}
