class_name EqDaggerBatch
extends RefCounted
## eq_dagger_batch.gd —— 匕首羁绊 9 件新装备的效果本体（2026-11-25 · 方案书 docs/plans/20261125-匕首羁绊.md §4.2）
##   108 折叠小刀 · 109 柳叶飞刀 · 110 苦无 · 111 毒牙匕首 · 112 三棱刺 · 113 弯匕 · 114 仪式匕首(+ 专属羁绊「仪式」血契)
##   · 115 暗影匕首(召唤暗影忍者) · 116 黑曜石匕首
##   (第 10 件 = 现有 005 双生匕首, 效果不动, 只改归匕首类型。)
##
## 接口 = 批④统一口(b4_owner.gd → `_b4`): on_spawn / on_basic / on_hit / on_damaged / on_magic_hurt / on_death / on_mana_full
##   / tick / tick_unit / clear_all, 另加 on_kill(击杀钩, equip_system._eq_on_kill 转来)与 on_any_basic(任何单位普攻)。
##
## ── 地雷对照(CLAUDE.md §4) ────────────────────────────────────────
##   §4.1 「X% 最大生命」一律真实 maxHp。 §4.2 单位字典不当键: 在途表存字典本身, 比较 is_same。
##   §4.3 只发伤害、不改伤害流程: 物理 `_resolve_dmg` + `_apply_damage_from(from_equip)`; 魔法同上(magic=true)。
##   §4.4 `_t` 跨路累加: 计时全是逐帧累加(换路单位重建 ⇒ 自然清零)。跨路 / 跨对局的只有 114 血契(见下)。
##   随机: 只有 110 苦无挑随机敌人, 走已播种的 `battle._battle_rng`。
##   会走的飞行物(109 柳叶飞刀 / 115 手里剑): 每步线段碰撞, 命中名单防重复(memory fb-moving-hits-collide-per-step)。
const _BE := preload("res://scripts/net/backend.gd")
var battle
var vfx = null

# ── 108 折叠小刀 ──
const FOLD_BLEED := [80, 140, 210]
# ── 109 柳叶飞刀 ──
const KNIFE_IV := 6.0
const KNIFE_FLAT := [40.0, 70.0, 120.0]
const KNIFE_ATK := 0.6
const KNIFE_SPD := 1100.0
const KNIFE_LEN := 1600.0
const KNIFE_W := 22.0
# ── 110 苦无 ──
const KUNAI_IV := 5.0
const KUNAI_N := [3, 4, 5]
const KUNAI_FLAT := [15.0, 25.0, 40.0]
const KUNAI_ATK := 0.2
const KUNAI_HEAL := [10.0, 18.0, 30.0]
const KUNAI_FLY := 0.3
# ── 111 毒牙匕首 ──
const FANG_POISON_ATK := [0.3, 0.5, 0.8]
# ── 112 三棱刺 ──
const PIERCE_PCT := [0.2, 0.3, 0.45]
# ── 113 弯匕 ──
const KRIS_ASPD := [0.6, 0.9, 1.5]
const KRIS_SEC := 3.0
# ── 114 仪式匕首 + 专属羁绊「仪式」──
const RITUAL_EXEC := 0.10
const RITUAL_CAP := 150
const RITUAL_ATK := [0.6, 1.2, 2.5]
const RITUAL_PEN := [0.2, 0.35, 0.6]
const RITUAL_TEAM_ATK := 0.001
# ── 115 暗影匕首: 暗影忍者 ──
const NINJA_HP := [1500.0, 3000.0, 8000.0]
const NINJA_ATK := [80.0, 160.0, 450.0]
const NINJA_RES := [30.0, 50.0, 90.0]
const NINJA_CRIT := [0.25, 0.35, 0.5]
const NINJA_EN_MAX := 60.0
const NINJA_VANISH := 0.3
const NINJA_STRIKE_MULT := 2.5
const NINJA_RESTEALTH := 1.5
## 影袭现身到刀插下去的前摇(背刺动作第 3 帧 = 插中那一下, 演出按「3 帧 / 这么多秒」播 ⇒ 画面插中 = 结算)
const NINJA_STAB_WINDUP := 0.18
## 背刺之后两名忍者各掷手里剑的前摇(掷剑动作第 3 帧 = 出手)
const SHURIKEN_WINDUP := 0.2
const NINJA_CLONE_HP_PCT := 0.5
const NINJA_CLONE_SEC := 20.0
const NINJA_CLONE_STAT := 0.5
const SHURIKEN_FLAT := [60.0, 120.0, 300.0]
const SHURIKEN_ATK := 1.0
const SHURIKEN_SPD := 1300.0
const SHURIKEN_W := 26.0
# ── 116 黑曜石匕首 ──
const OBS_FLAT := [100.0, 200.0, 600.0]
const OBS_ATK := 0.5
const OBS_MAXHP := [0.03, 0.05, 0.10]
const OBS_HEAL := [60.0, 120.0, 300.0]

const SEC_PER_ENERGY := 0.075
const COL_PHYS := Color("#ff9a4a")
const COL_MAGIC := Color("#4dabf7")

# ── 在途 / 场上状态(换路 clear_all 清空)──
var _lines: Array = []         ## 直线飞行物 {pos, dir, spd, left, w, src, hit:[], kind, si}
var _kunai: Array = []         ## 苦无在途 {src, tgt, t, si}
var _ninjas: Array = []        ## {u, owner, si, en, vanish, tgt, clone(bool), clone_of, until, split_done}
var _obs_tgts: Array = []      ## 身上插着黑曜石匕首的敌人(字典本身, is_same 去重)
## 114 血契: 本场每方的刻数(left 与 GameState.ritual_marks 同步; right 每场从对手快照读一次)
var _marks := {"left": 0, "right": 0}
var _marks_loaded := {}
## 这一局每方新刻了几道(同竹叶龟生长 `grown`): 裁判写进结果单 ritual_new / ritual_new_b, 客户端 RefereeWatch.apply_ritual
##   收到回包才累积进存档(GameState.ritual_marks)。局内不直接写存档 —— 本机看的是直播 / 回放, 真打的是裁判机。
##   ★不随 reset_match 清(那一刻在结算里, 裁判结果单在它之后才读); 每局新建一个对战场景 ⇒ 自然从 0 起。
var ritual_new := {"left": 0, "right": 0}
## 门禁量
var stat := {"fold": 0, "knife": 0, "kunai": 0, "kunai_heal": 0, "fang": 0, "kris": 0, "ritual_exec": 0, "ritual_mark": 0,
	"ninja_strike": 0, "ninja_clone": 0, "shuriken": 0, "obs_embed": 0, "obs_pull": 0}


func _init(b) -> void:
	battle = b
	vfx = DaggerEqVfx.new(b)


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
		out.append(o)
	return out


func _allies_of_side(side: String) -> Array:
	var out: Array = []
	for o in battle._units:
		if o is Dictionary and o.get("alive", false) and str(o.get("side", "")) == side and not bool(o.get("_isEgg", false)) \
				and not battle._is_untouchable(o):
			out.append(o)
	return out


func _side_of(u: Dictionary) -> String:
	var sd := str(u.get("side", ""))
	return sd if (sd == "left" or sd == "right") else "left"


func _phys(src: Dictionary, tgt: Dictionary, base: float, can_crit: bool = true) -> void:
	if not tgt.get("alive", false) or base <= 0.0:
		return
	var dmg: int = battle._resolve_dmg(src, base, tgt, false, can_crit)
	battle._damage._apply_damage_from(src, tgt, dmg, COL_PHYS, 0.0, false, true)


func _magic(src: Dictionary, tgt: Dictionary, base: float, can_crit: bool = true) -> void:
	if not tgt.get("alive", false) or base <= 0.0:
		return
	var dmg: int = battle._resolve_dmg(src, base, tgt, true, can_crit)
	battle._damage._apply_damage_from(src, tgt, dmg, COL_MAGIC, 0.0, false, true)


func _acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_dagger_acc", {})
	return float(d.get(key, 0.0))


func _set_acc(u: Dictionary, key: String, v: float) -> void:
	var d: Dictionary = u.get("_dagger_acc", {})
	d[key] = v
	u["_dagger_acc"] = d


func _en_gain(u: Dictionary, delta: float) -> float:
	var t := float(battle._t)
	if t < float(u.get("stun_until", 0.0)) or t < float(u.get("channel_until", 0.0)) or bool(u.get("airborne", false)) \
			or t < float(u.get("storm_until", 0.0)) or t < float(u.get("energy_lock_until", 0.0)):
		return 0.0
	return delta / SEC_PER_ENERGY * maxf(0.0, float(u.get("echarge_perm", 1.0)))


# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════

func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	match eid:
		"p2eq_112":   # 三棱刺: 攻击和技能无视目标 X% 护甲(百分比破甲通道, 各件相加)
			u["armor_pen_pct"] = float(u.get("armor_pen_pct", 0.0)) + float(PIERCE_PCT[si])
		"p2eq_114":
			_ritual_spawn(u, si)
		"p2eq_115":
			_spawn_ninja(u, si)


func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if eid != "p2eq_108" or not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	## 折叠小刀: 每路开打后携带者的第一次攻击(只那一次)附带流血。单位每路重建 ⇒ 标记自然清零; 多件各自一次(份号)
	var ck: String = battle._equip_sys.key_of(u, eid)
	if _acc(u, "fold:" + ck) > 0.0:
		return
	_set_acc(u, "fold:" + ck, 1.0)
	stat["fold"] += 1
	battle._damage._apply_dot_stacks(tgt, "bleed", int(FOLD_BLEED[si]), u)
	_fx("fold_cut", [u, tgt])


func on_hit(src: Dictionary, tgt: Dictionary, _dmg: float, eid: String, si: int) -> void:
	if not tgt.get("alive", false):
		return
	match eid:
		"p2eq_111":   # 毒牙匕首: 暴击时按攻击力比例给中毒层数
			if bool(src.get("_b4_crit", false)):
				var n := int(floor(float(src.get("atk", 0.0)) * float(FANG_POISON_ATK[si])))
				if n > 0:
					stat["fang"] += 1
					battle._damage._apply_dot_stacks(tgt, "poison", n, src)
					_fx("fang_bite", [tgt])
		"p2eq_114":   # 仪式匕首: 斩杀线 10% 最大生命(攻击和技能)
			_ritual_execute(src, tgt)
		"p2eq_116":   # 黑曜石匕首: 暴击 ⇒ 插一把
			if bool(src.get("_b4_crit", false)):
				_obs_embed(src, tgt, si)


func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 击杀钩(equip_system._eq_on_kill 逐件转来)
func on_kill(killer: Dictionary, _victim: Dictionary, eid: String, si: int) -> void:
	match eid:
		"p2eq_113":   # 弯匕: 击杀后 3 秒攻速暴涨(取较高的一份, 不叠乘)
			stat["kris"] += 1
			var t := float(battle._t)
			var cur: float = float(killer.get("haste_mult", 1.0)) if t < float(killer.get("haste_until", 0.0)) else 1.0
			killer["haste_mult"] = maxf(cur, 1.0 + float(KRIS_ASPD[si]))
			killer["haste_until"] = maxf(float(killer.get("haste_until", 0.0)), t + KRIS_SEC)
			_fx("kris_rush", [killer, KRIS_SEC])
		"p2eq_114":
			_ritual_mark(killer)


## 任何单位普攻(EquipSystem._eq_on_basic_attack 最前面调)
func on_any_basic(u: Dictionary, tgt) -> void:
	var id := str(u.get("id", ""))
	if id == "_summon_shadow_ninja" or id == "_summon_shadow_clone":
		u["untargetable_until"] = minf(float(u.get("untargetable_until", 0.0)), float(battle._t))   # 攻击即现形
		u["_ninja_veil"] = false
		if tgt is Dictionary:
			_fx("ninja_slash", [u, tgt])


func tick(delta: float) -> void:
	_tick_lines(delta)
	_tick_kunai()
	_tick_ninjas(delta)
	_tick_obs()
	_tick_ritual_team()
	if vfx != null:
		vfx.tick(delta)


func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		var iv := 0.0
		match eid:
			"p2eq_109": iv = KNIFE_IV
			"p2eq_110": iv = KUNAI_IV
			_: continue
		var si := clampi(int(e.get("star", 1)), 1, 3) - 1
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		var a := _acc(u, ck) + delta
		if a < iv:
			_set_acc(u, ck, a)
			continue
		_set_acc(u, ck, a - iv)
		var tl: Array = es.tally.push(u, ck)
		match eid:
			"p2eq_109": _throw_knife(u, si, ck)
			"p2eq_110": _throw_kunai(u, si, ck)
		es.tally.pop(tl)
	es.ck_restore(ckp)


func clear_all() -> void:
	_lines.clear(); _kunai.clear(); _ninjas.clear()
	for o in _obs_tgts:
		if o is Dictionary:
			(o as Dictionary).erase("_obs")
	_obs_tgts.clear()
	if vfx != null:
		vfx.clear()


## 一局结束(不是换路): 右方血契重新从对手快照读
func reset_match() -> void:
	_marks_loaded.clear()
	_marks["right"] = 0


# ════════════════════════════════════════ 109 柳叶飞刀 / 115 手里剑(直线飞行物) ════════════════════════════════════════

func _throw_knife(u: Dictionary, si: int, ck: String) -> void:
	var far = null
	var best := -1.0
	for o in _enemies_of(u):
		var d := DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"]))
		if d > best:
			best = d
			far = o
	if not (far is Dictionary):
		return
	stat["knife"] += 1
	_launch(u, Vector2(u["pos"]), Vector2(far["pos"]) - Vector2(u["pos"]), KNIFE_SPD, KNIFE_LEN, KNIFE_W, "knife", si, ck)


func _launch(src: Dictionary, from: Vector2, dir: Vector2, spd: float, length: float, w: float, kind: String, si: int, ck: String = "") -> void:
	var dn: Vector2 = DetMath.norm(dir) if DetMath.vlen(dir) > 0.1 else (Vector2.RIGHT if _side_of(src) == "left" else Vector2.LEFT)
	_lines.append({"pos": from, "dir": dn, "spd": spd, "left": length, "w": w, "src": src, "hit": [], "kind": kind, "si": si, "ck": ck})
	_fx("line_launch", [kind, from, dn, spd, length, src])


func _tick_lines(delta: float) -> void:
	var keep: Array = []
	for L in _lines:
		var step := minf(float(L["spd"]) * delta, float(L["left"]))
		var a: Vector2 = L["pos"]
		var b: Vector2 = a + Vector2(L["dir"]) * step
		var src: Dictionary = L["src"]
		var done := false
		for o in _enemies_of(src):
			var already := false
			for h in L["hit"]:
				if is_same(h, o):
					already = true
					break
			if already:
				continue
			var q: Vector2 = DetMath.seg_closest(Vector2(o["pos"]), a, b)
			if DetMath.dist(q, Vector2(o["pos"])) <= float(L["w"]) + float(o.get("col_r", 20.0)):
				(L["hit"] as Array).append(o)
				_line_hit(L, o)
				if str(L["kind"]) == "knife":   # 柳叶飞刀只打途经的第一个敌人
					done = true
					break
		L["pos"] = b
		L["left"] = float(L["left"]) - step
		if not done and float(L["left"]) > 0.01:
			keep.append(L)
		elif done:
			_fx("line_stop", [str(L["kind"]), b])
	_lines = keep


func _line_hit(L: Dictionary, o: Dictionary) -> void:
	var src: Dictionary = L["src"]
	var si := int(L["si"])
	var tl: Array = battle._equip_sys.tally.push(src, str(L.get("ck", "")))
	match str(L["kind"]):
		"knife":
			_magic(src, o, float(KNIFE_FLAT[si]) + KNIFE_ATK * float(src.get("atk", 0.0)))
			_fx("knife_hit", [o])
		"shuriken":
			_magic(src, o, float(SHURIKEN_FLAT[si]) + SHURIKEN_ATK * float(src.get("atk", 0.0)))
			_fx("shuriken_hit", [o])
	battle._equip_sys.tally.pop(tl)


# ════════════════════════════════════════ 110 苦无 ════════════════════════════════════════

func _throw_kunai(u: Dictionary, si: int, ck: String) -> void:
	var foes := _enemies_of(u)
	if foes.is_empty():
		return
	for i in range(int(KUNAI_N[si])):
		var tgt: Dictionary = foes[battle._battle_rng.randi() % foes.size()]
		stat["kunai"] += 1
		var delay := float(i) * 0.06   # 一把一把连着出手
		_kunai.append({"src": u, "tgt": tgt, "t": float(battle._t) + delay + KUNAI_FLY, "si": si, "ck": ck})
		_fx("kunai_throw", [u, tgt, delay, KUNAI_FLY])


func _tick_kunai() -> void:
	var t := float(battle._t)
	var keep: Array = []
	for k in _kunai:
		if t < float(k["t"]):
			keep.append(k)
			continue
		var src: Dictionary = k["src"]
		var tgt: Dictionary = k["tgt"]
		if not tgt.get("alive", false):
			continue
		var si := int(k["si"])
		var tl: Array = battle._equip_sys.tally.push(src, str(k.get("ck", "")))
		_magic(src, tgt, float(KUNAI_FLAT[si]) + KUNAI_ATK * float(src.get("atk", 0.0)))
		if src.get("alive", false):
			stat["kunai_heal"] += 1
			battle._damage._heal(src, float(KUNAI_HEAL[si]), true)
		battle._equip_sys.tally.pop(tl)
		_fx("kunai_hit", [tgt, src])
	_kunai = keep


# ════════════════════════════════════════ 114 仪式匕首 · 血契 ════════════════════════════════════════

func _side_tier(side: String, t: String) -> int:
	var best := 0
	for u in battle._units:
		if u is Dictionary and str(u.get("side", "")) == side:
			best = maxi(best, int(battle._synergy.tier_for(u, t)))
	return best


## 局外装备卡那一行(背包): 「血契 N / 150」(满了标已满)
static func progress_text(marks: int) -> String:
	var m: int = clampi(marks, 0, RITUAL_CAP)
	if m >= RITUAL_CAP:
		return Lang.t("血契 %d / %d（已满）") % [m, RITUAL_CAP]
	return Lang.t("血契 %d / %d") % [m, RITUAL_CAP]


func marks_of(side: String) -> int:
	return int(_marks.get(side, 0))


func _load_marks(side: String) -> void:
	if bool(_marks_loaded.get(side, false)):
		return
	_marks_loaded[side] = true
	if GameState == null or battle._world_builder._is_dev_tool_battle():
		return
	if side == "left":
		_marks["left"] = clampi(int(GameState.ritual_marks), 0, RITUAL_CAP)
	else:
		_marks["right"] = maxi(int(_marks.get("right", 0)), _BE.ghost_ritual_marks(GameState.dual_ghost))   # 对手快照(同裁判左方的口径)


## 登场: 按已有血契给这件的那一份(攻击 / 护穿, 按星)
func _ritual_spawn(u: Dictionary, si: int) -> void:
	var side := _side_of(u)
	_load_marks(side)
	var n := marks_of(side)
	if n > 0:
		u["base_atk"] = float(u.get("base_atk", 0.0)) + float(RITUAL_ATK[si]) * float(n)
		u["armor_pen"] = float(u.get("armor_pen", 0.0)) + float(RITUAL_PEN[si]) * float(n)
		battle._recalc_stats(u)


func _ritual_execute(src: Dictionary, tgt: Dictionary) -> void:
	if not tgt.get("alive", false) or tgt.get("eq_exec_immune", false):
		return
	if float(tgt["hp"]) >= float(tgt.get("maxHp", 0.0)) * RITUAL_EXEC:
		return
	if battle._damage.execute_saved(tgt):
		return
	stat["ritual_exec"] += 1
	_fx("ritual_execute", [tgt])
	battle._vfx._float_text(tgt["pos"], "-999999", battle._VC.color_of(battle._VC.cls_for("damage", "true", true)), true, "damage", "true")
	tgt["hp"] = 0.0
	var tk: Array = battle._equip_sys.tally.push(null, "")
	battle._kill(tgt, src)
	battle._equip_sys.tally.pop(tk)


## 携带者击杀一名敌人 ⇒ 刻 1 道血契(同一只身上多件仪式匕首: 每件的钩子都会来, 只刻一次 —— 用击杀时刻去重)
func _ritual_mark(killer: Dictionary) -> void:
	var t := float(battle._t)
	if absf(float(killer.get("_ritual_last_t", -99.0)) - t) < 0.0001:
		return
	killer["_ritual_last_t"] = t
	var side := _side_of(killer)
	_load_marks(side)
	if marks_of(side) >= RITUAL_CAP:
		return
	_marks[side] = marks_of(side) + 1
	ritual_new[side] = int(ritual_new.get(side, 0)) + 1
	stat["ritual_mark"] += 1
	## 这一道给场上本方每个仪式匕首携带者的那一份(按各自星级, 每件一份)
	for o in _allies_of_side(side):
		for e in o.get("equips", []):
			if e is Dictionary and str((e as Dictionary).get("id", "")) == "p2eq_114":
				var si := clampi(int((e as Dictionary).get("star", 1)), 1, 3) - 1
				o["base_atk"] = float(o.get("base_atk", 0.0)) + float(RITUAL_ATK[si])
				o["armor_pen"] = float(o.get("armor_pen", 0.0)) + float(RITUAL_PEN[si])
				battle._recalc_stats(o)
	_fx("ritual_mark", [killer, marks_of(side)])


## 「仪式」羁绊那一份: 本方每个单位的攻击力 +RITUAL_TEAM_ATK × 血契(百分比 buff, 同 tag 只一条, 血契变了就改数)
func _tick_ritual_team() -> void:
	for side in ["left", "right"]:
		if _side_tier(side, "仪式") <= 0:
			continue
		_load_marks(side)
		var pct := RITUAL_TEAM_ATK * float(marks_of(side))
		if pct <= 0.0:
			continue
		for o in _allies_of_side(side):
			if absf(float(o.get("_ritual_team_pct", 0.0)) - pct) < 1e-9:
				continue
			o["_ritual_team_pct"] = pct
			var found := false
			for bf in o["buffs"]:
				if str((bf as Dictionary).get("tag", "")) == "ritual_team":
					bf["amount"] = pct
					found = true
			if not found:
				o["buffs"].append({"stat": "atk", "amount": pct, "pct": true, "until": 1.0e12, "tag": "ritual_team"})
			battle._recalc_stats(o)


# ════════════════════════════════════════ 115 暗影匕首 · 暗影忍者 ════════════════════════════════════════

func _spawn_ninja(owner: Dictionary, si: int, clone_of = null) -> Dictionary:
	var is_clone := clone_of is Dictionary
	var k := NINJA_CLONE_STAT if is_clone else 1.0
	var p = battle._spawn._spawn_summon(owner, "shadow_clone" if is_clone else "shadow_ninja",
		float(NINJA_HP[si]) * k, float(NINJA_ATK[si]) * k,
		{"label": "影子忍者" if is_clone else "暗影忍者", "spr_id": "eq-shadow-ninja", "col_size": 44.0, "hp_w": 34.0,
		 "atk_interval": 0.8, "atk_range": 60.0, "melee": true, "crit": float(NINJA_CRIT[si])})
	if p == null:
		return {}
	p["def"] = float(NINJA_RES[si]); p["base_def"] = p["def"]
	p["mr"] = float(NINJA_RES[si]); p["base_mr"] = p["mr"]
	p["maxEnergy"] = NINJA_EN_MAX
	p["energy"] = 0.0
	if is_clone:
		p["pos"] = Vector2((clone_of as Dictionary)["pos"]) + Vector2(0, 40)
		p["_body_tint"] = Color(0.42, 0.3, 0.7, 0.72)   # 影子 = 同一套立绘压成暗紫半透明(演出底色通道, battle_render 读)
	else:
		p["untargetable_until"] = 1.0e9   # 登场隐身: 第一次攻击现形(on_any_basic)
		p["_ninja_veil"] = true
	var rec := {"u": p, "owner": owner, "si": si, "en": NINJA_EN_MAX if bool(owner.get("_edit_fe", false)) else 0.0,
		"vanish": -1.0, "stab": -1.0, "tgt": null, "clone": is_clone, "until": float(battle._t) + NINJA_CLONE_SEC if is_clone else 1.0e12,
		"split_done": false}
	_ninjas.append(rec)
	_fx("ninja_spawn", [p, is_clone])
	return rec


func ninja_state(i: int = 0) -> Dictionary:
	return _ninjas[i] if i < _ninjas.size() else {}


func _tick_ninjas(delta: float) -> void:
	var t := float(battle._t)
	var add: Array = []
	for n in _ninjas:
		var p: Dictionary = n["u"]
		if not p.get("alive", false):
			continue
		if bool(n["clone"]) and t >= float(n["until"]):   # 影子到时消散
			p["hp"] = 0.0
			battle._kill(p)
			_fx("ninja_fade", [p])
			continue
		## 本体首次降到 50% ⇒ 分出影子(持续 20 秒, 一半属性)
		if not bool(n["clone"]) and not bool(n["split_done"]) and float(p["hp"]) <= float(p.get("maxHp", 1.0)) * NINJA_CLONE_HP_PCT:
			n["split_done"] = true
			stat["ninja_clone"] += 1
			add.append([n["owner"], int(n["si"]), p])
		if float(n.get("throw", -1.0)) >= 0.0:   # 掷手里剑前摇(不打断走位 / 普攻判定: 只是延后放出)
			n["throw"] = float(n["throw"]) - delta
			if float(n["throw"]) <= 0.0:
				n["throw"] = -1.0
				_ninja_throw(n)
		if float(n.get("stab", -1.0)) >= 0.0:   # 影袭: 已在目标身后现身, 刀正往下插
			n["stab"] = float(n["stab"]) - delta
			if float(n["stab"]) <= 0.0:
				n["stab"] = -1.0
				_ninja_stab(n)
			continue
		if float(n["vanish"]) >= 0.0:   # 影袭: 化烟消失中
			n["vanish"] = float(n["vanish"]) - delta
			if float(n["vanish"]) <= 0.0:
				n["vanish"] = -1.0
				_ninja_appear(n)
			continue
		n["en"] = minf(NINJA_EN_MAX, float(n["en"]) + _en_gain(p, delta))
		p["energy"] = float(n["en"])
		if float(n["en"]) < NINJA_EN_MAX:
			continue
		var tgt = _lowest_ratio_enemy(p)
		if not (tgt is Dictionary):
			continue
		n["en"] = 0.0
		n["tgt"] = tgt
		n["vanish"] = NINJA_VANISH
		battle._damage.channel(p, NINJA_VANISH + NINJA_STAB_WINDUP + 0.1)
		p["untargetable_until"] = maxf(float(p.get("untargetable_until", 0.0)), t + NINJA_VANISH)
		p["_ninja_veil"] = true
		p["_ninja_gone"] = true   # 化烟这段整个看不见(演出读)
		_fx("ninja_vanish", [p, NINJA_VANISH])
	for a in add:
		_spawn_ninja(a[0], int(a[1]), a[2])


func _lowest_ratio_enemy(p: Dictionary):
	var best = null
	var br := 9.0
	for o in _enemies_of(p):
		var r := float(o["hp"]) / maxf(1.0, float(o.get("maxHp", 1.0)))
		if r < br:
			br = r
			best = o
	return best


## 影袭现身: 化烟结束 ⇒ 闪到目标身后(背对着它的那一侧), 开始往下插(NINJA_STAB_WINDUP 秒后结算)
func _ninja_appear(n: Dictionary) -> void:
	var p: Dictionary = n["u"]
	p["_ninja_gone"] = false
	var tgt = n["tgt"]
	if not p.get("alive", false):
		return
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		tgt = _lowest_ratio_enemy(p)
	if not (tgt is Dictionary):
		p["_ninja_veil"] = false
		return
	n["tgt"] = tgt
	var from := Vector2(p["pos"])
	var away: Vector2 = Vector2(tgt["pos"]) - from
	away = DetMath.norm(away) if DetMath.vlen(away) > 1.0 else (Vector2.RIGHT if _side_of(p) == "left" else Vector2.LEFT)
	p["pos"] = ArenaShape.clamp_in(Vector2(tgt["pos"]) + away * 46.0, battle.ARENA, 30, 20)
	p["face_right"] = Vector2(tgt["pos"]).x > Vector2(p["pos"]).x
	n["stab"] = NINJA_STAB_WINDUP
	## 现身 = 出手(攻击即现形): 登场隐身(到第一次攻击为止)在这一刻结束, 背刺动作全程看得见、也打得到
	p["untargetable_until"] = float(battle._t)
	p["_ninja_veil"] = false
	_fx("ninja_appear", [p, from, NINJA_STAB_WINDUP])


## 影袭插中: 必暴击背刺, 重新隐身; 分身在场时两个忍者各朝这个目标掷一枚手里剑
func _ninja_stab(n: Dictionary) -> void:
	var p: Dictionary = n["u"]
	var tgt = n["tgt"]
	if not p.get("alive", false) or not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		p["_ninja_veil"] = false
		return
	var from := Vector2(p["pos"])
	stat["ninja_strike"] += 1
	p["_assassin_now"] = 0.0001   # 借【刺杀】那条「这一下必暴击」通道(额外暴伤 ≈ 0), 用完即清
	var dmg: int = battle._resolve_dmg(p, NINJA_STRIKE_MULT * float(p.get("atk", 0.0)), tgt, false)
	p.erase("_assassin_now")
	battle._damage._apply_damage_from(p, tgt, dmg, COL_PHYS, 0.0, false, true)
	p["untargetable_until"] = maxf(float(p.get("untargetable_until", 0.0)), float(battle._t) + NINJA_RESTEALTH)
	p["_ninja_veil"] = true
	p["atk_cd"] = maxf(float(p.get("atk_cd", 0.0)), NINJA_RESTEALTH)   # 隐身这 1.5 秒不普攻(否则下一拍普攻就现形, 隐身等于没有; 11-25 录像自查)
	_fx("ninja_strike", [p, tgt, from])
	## 影分身期间: 两个忍者同时朝这个目标各掷一枚手里剑(沿直线飞, 路径上每个敌人吃一次)
	var pair: Array = []
	for m in _ninjas:
		var q: Dictionary = m["u"]
		if q.get("alive", false) and is_same(m["owner"], n["owner"]):
			pair.append(m)
	if pair.size() >= 2:
		for m in pair:
			m["throw"] = SHURIKEN_WINDUP   # SHURIKEN_WINDUP 秒后出手(_tick_ninjas), 朝这个目标
			m["throw_tgt"] = tgt
			_fx("ninja_throw", [m["u"], SHURIKEN_WINDUP])


## 手里剑出手: 朝目标(死了就朝它最后的位置)沿直线飞, 路径上每个敌人吃一次
func _ninja_throw(m: Dictionary) -> void:
	var q: Dictionary = m["u"]
	var tgt = m.get("throw_tgt", null)
	m.erase("throw_tgt")
	if not q.get("alive", false) or not (tgt is Dictionary):
		return
	var d: Vector2 = Vector2(tgt["pos"]) - Vector2(q["pos"])
	var len := DetMath.vlen(d) + 260.0
	stat["shuriken"] += 1
	_launch(q, Vector2(q["pos"]), d, SHURIKEN_SPD, len, SHURIKEN_W, "shuriken", int(m["si"]))


# ════════════════════════════════════════ 116 黑曜石匕首 ════════════════════════════════════════

func _obs_embed(src: Dictionary, tgt: Dictionary, si: int) -> void:
	var arr: Array = tgt.get("_obs", [])
	arr.append({"src": src, "si": si})
	tgt["_obs"] = arr
	var seen := false
	for o in _obs_tgts:
		if is_same(o, tgt):
			seen = true
			break
	if not seen:
		_obs_tgts.append(tgt)
	stat["obs_embed"] += 1
	_fx("obs_embed", [tgt, arr.size()])
	_obs_check(tgt)


## 一把匕首拔出的伤害(过护甲后的实数; 判「够不够杀」与真打用同一个数)
func _obs_one(d: Dictionary, tgt: Dictionary) -> int:
	var src: Dictionary = d["src"]
	var si := int(d["si"])
	var raw := float(OBS_FLAT[si]) + OBS_ATK * float(src.get("atk", 0.0)) + float(OBS_MAXHP[si]) * float(tgt.get("maxHp", 0.0))
	return battle._phys_after_armor(src, raw, tgt)


func _obs_check(tgt: Dictionary) -> void:
	if not tgt.get("alive", false):
		return
	var arr: Array = tgt.get("_obs", [])
	if arr.is_empty():
		return
	var total := 0
	for d in arr:
		total += _obs_one(d, tgt)
	if float(total) < float(tgt["hp"]) + float(tgt.get("shield", 0.0)):
		return
	## 够杀 ⇒ 立即全部拔出
	stat["obs_pull"] += 1
	tgt.erase("_obs")
	_fx("obs_pull", [tgt, arr.size()])
	var heal_by: Array = []
	for d in arr:
		var src: Dictionary = d["src"]
		var tl: Array = battle._equip_sys.tally.push(src, "p2eq_116")
		battle._damage._apply_damage_from(src, tgt, _obs_one(d, tgt), COL_PHYS, 0.0, true, true, false, true)
		battle._equip_sys.tally.pop(tl)
		heal_by.append(d)
	for d in heal_by:
		var src: Dictionary = d["src"]
		if src.get("alive", false):
			battle._damage._heal(src, float(OBS_HEAL[int(d["si"])]))


func _tick_obs() -> void:
	var keep: Array = []
	for o in _obs_tgts:
		if not (o is Dictionary) or not o.get("alive", false) or (o.get("_obs", []) as Array).is_empty():
			continue
		_obs_check(o)
		if o.get("alive", false) and not (o.get("_obs", []) as Array).is_empty():
			keep.append(o)
	_obs_tgts = keep
