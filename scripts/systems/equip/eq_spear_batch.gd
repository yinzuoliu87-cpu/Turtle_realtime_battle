class_name EqSpearBatch
extends RefCounted
## eq_spear_batch.gd —— 长矛羁绊 10 件新装备的效果本体(2026-11-26 · 方案书 docs/plans/20261126-长矛羁绊.md §4)
##   137 竹矛 · 138 鱼叉 · 139 标枪 · 140 骑枪 · 141 长戟 · 142 盾矛 · 143 方天画戟 · 144 投矛器 · 145 永恒之枪 · 146 圣枪
## 每件单独生效(不靠羁绊档位)。效果与数值 11-26 发给用户看过(用户随后只补了百夫长成长, 未改这张表)。
## 接口 = 批④统一口(b4_owner.gd → `_b4`); 另加静态 `front_block`(142 正面减伤, _apply_damage_from 里调)。
## 飞行物(139 / 144 / 145)一律按速度飞、碰到身体才结算; 144 的矛每步线段碰撞(memory fb-projectiles-have-speed / fb-moving-hits-collide-per-step)。
var battle
var vfx = null

const COL_PHYS := Color("#ff9a4a")
const COL_MAGIC := Color("#4dabf7")
# ── 137 竹矛 ──
const BAMBOO_EVERY := 3
const BAMBOO_PCT := [0.60, 0.80, 1.20]
const BAMBOO_LEN := 220.0
# ── 138 鱼叉 ──
const BARB_SEC := 4.0
const BARB_PER_100 := [15.0, 25.0, 45.0]
# ── 139 标枪 ──
const JAV_IV := 6.0
const JAV_PCT := [1.0, 1.5, 2.5]
const JAV_SPD := 900.0
const JAV_SLOW := 0.30
const JAV_SLOW_SEC := 2.0
# ── 140 骑枪 ──
const LANCE_STEP := 100.0
const LANCE_MAX := 5
const LANCE_PCT := [0.15, 0.20, 0.30]
# ── 141 长戟 ──
const HALB_R := 170.0
const HALB_ARC := 0.5            # cos(60°): 前方 120° 扇形
const HALB_PCT := [0.40, 0.55, 0.75]
# ── 142 盾矛 ──
const SHSP_DR := [0.15, 0.20, 0.30]
const SHSP_EVERY := 5
const SHSP_ARMOR := 0.30
# ── 143 方天画戟 ──
const FTJ_R := 170.0
const FTJ_MIN := 2
const FTJ_PCT := [0.30, 0.45, 0.80]
# ── 144 投矛器 ──
const ATL_IV := 10.0
const ATL_N := [3, 4, 6]
const ATL_PCT := [0.80, 1.20, 2.00]
const ATL_SPD := 850.0
const ATL_LEN := 750.0
const ATL_SPREAD := 0.5          # 扇形总张角(弧度)
const ATL_W := 26.0
# ── 145 永恒之枪 ──
const ETERNAL_IV := 8.0
const ETERNAL_PIN := 1.5
const ETERNAL_PCT := [0.08, 0.12, 0.20]
const ETERNAL_SPD := 1100.0
# ── 146 圣枪 ──
const HOLY_STACKS := 3
const HOLY_DMG := [150.0, 250.0, 500.0]
const HOLY_HEAL := [0.05, 0.08, 0.12]

var stat := {"bamboo": 0, "barb_tick": 0, "jav": 0, "jav_hit": 0, "lance": 0, "halb": 0, "shsp_block": 0, "shsp_counter": 0,
	"ftj": 0, "atl": 0, "atl_hit": 0, "eternal": 0, "eternal_hit": 0, "holy": 0}
var _atl: Array = []      # {src, pos, dir, left, si, hit}


func _init(b) -> void:
	battle = b


func _fx(method: String, args: Array = []) -> void:
	var v = battle._spear_syn.vfx if battle.get("_spear_syn") != null else null
	if v == null and battle.get("_spear_syn") != null:
		battle._spear_syn._fx("noop", [])
		v = battle._spear_syn.vfx
	if v != null and v.has_method(method):
		v.callv(method, args)


func _acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_spear_acc", {})
	return float(d.get(key, 0.0))


func _set_acc(u: Dictionary, key: String, v: float) -> void:
	var d: Dictionary = u.get("_spear_acc", {})
	d[key] = v
	u["_spear_acc"] = d


static func _si_of(e: Dictionary) -> int:
	return clampi(int(e.get("star", 1)), 1, 3) - 1


func _phys(src: Dictionary, o: Dictionary, base: float) -> void:
	if not o.get("alive", false) or base <= 0.0:
		return
	battle._damage._apply_damage_from(src, o, battle._phys_after_armor(src, base, o), COL_PHYS, 0.0, false, true)


func _enemies(u: Dictionary) -> Array:
	var out: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false):
			out.append(o)
	return out


## 142 盾矛: 正面(攻击者在携带者朝向那一侧)来的伤害降低 —— _apply_damage_from 减伤之后、护盾之前调
static func front_block(u: Dictionary, src, d: float) -> float:
	var pct: float = float(u.get("_shsp_dr", 0.0))
	if pct <= 0.0 or not (src is Dictionary) or d <= 0.0:
		return d
	var face_r: bool = bool(u.get("face_right", str(u.get("side", "left")) == "left"))
	var dx: float = float(Vector2((src as Dictionary)["pos"]).x) - float(Vector2(u["pos"]).x)
	if (dx >= 0.0) != face_r:
		return d
	u["_shsp_blocked"] = int(u.get("_shsp_blocked", 0)) + 1
	return d * (1.0 - minf(0.9, pct))


# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════

func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	match eid:
		"p2eq_142":
			u["_shsp_dr"] = 1.0 - (1.0 - float(u.get("_shsp_dr", 0.0))) * (1.0 - float(SHSP_DR[si]))   # 多件乘算叠加
		"p2eq_140":
			_set_acc(u, "lance_last", 0.0)
			u["_lance_from"] = Vector2(u["pos"])


func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	var t: Dictionary = tgt
	var ck: String = battle._equip_sys.key_of(u, eid)
	var atk: float = float(u.get("atk", 0.0))
	match eid:
		"p2eq_137":   # 竹矛: 每第 3 次攻击刺穿目标, 身后一名敌人吃伤害
			var n := int(_acc(u, "bamboo:" + ck)) + 1
			if n < BAMBOO_EVERY:
				_set_acc(u, "bamboo:" + ck, float(n))
				return
			_set_acc(u, "bamboo:" + ck, 0.0)
			var dir: Vector2 = DetMath.norm(Vector2(t["pos"]) - Vector2(u["pos"])) if DetMath.dist(Vector2(t["pos"]), Vector2(u["pos"])) > 1.0 else Vector2.RIGHT
			var best = null
			var bd := INF
			for o in _enemies(u):
				if is_same(o, t):
					continue
				var rel: Vector2 = Vector2(o["pos"]) - Vector2(t["pos"])
				var along: float = rel.dot(dir)
				if along <= 0.0 or along > BAMBOO_LEN or not battle._on_line(Vector2(t["pos"]), dir, Vector2(o["pos"]), 40.0):
					continue
				if along < bd:
					bd = along
					best = o
			if best is Dictionary:
				stat["bamboo"] += 1
				_phys(u, best, float(BAMBOO_PCT[si]) * atk)
				_fx("bamboo_pierce", [u, t, best])
		"p2eq_138":   # 鱼叉: 挂倒钩
			t["_barb_until"] = float(battle._t) + BARB_SEC
			t["_barb_dmg"] = maxf(float(t.get("_barb_dmg", 0.0)), float(BARB_PER_100[si]))
			t["_barb_src"] = u
			if not t.has("_barb_from"):
				t["_barb_from"] = Vector2(t["pos"])
			_fx("barb_on", [t])
		"p2eq_140":   # 骑枪: 用掉全部冲势
			var st := int(_acc(u, "lance:" + ck))
			if st > 0:
				stat["lance"] += 1
				_set_acc(u, "lance:" + ck, 0.0)
				_phys(u, t, float(st) * float(LANCE_PCT[si]) * atk)
				_fx("lance_hit", [u, t, st])
		"p2eq_141":   # 长戟: 前方扇形里的其他敌人
			var fdir: Vector2 = DetMath.norm(Vector2(t["pos"]) - Vector2(u["pos"])) if DetMath.dist(Vector2(t["pos"]), Vector2(u["pos"])) > 1.0 else Vector2.RIGHT
			var hit := false
			for o in _enemies(u):
				if is_same(o, t):
					continue
				var rel2: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
				var dd: float = DetMath.vlen(rel2)
				if dd > HALB_R or dd < 1.0 or DetMath.norm(rel2).dot(fdir) < HALB_ARC:
					continue
				hit = true
				_phys(u, o, float(HALB_PCT[si]) * atk)
			if hit:
				stat["halb"] += 1
			_fx("halb_sweep", [u, fdir])
		"p2eq_146":   # 圣枪: 圣痕 3 层引爆
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
				_fx("holy_mark", [t, nm])
			t["_holy_marks"] = marks


static var _uid_n := 0


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 142 盾矛: 每挨 5 次攻击(持续伤害不算)反刺攻击者
func on_damaged(u: Dictionary, src, _dmg: float, eid: String, si: int) -> void:
	if eid != "p2eq_142" or bool(u.get("_b4_dot", false)) or not (src is Dictionary) or is_same(src, u):
		return
	var ck: String = battle._equip_sys.key_of(u, eid)
	var n := int(_acc(u, "shsp:" + ck)) + 1
	if n < SHSP_EVERY:
		_set_acc(u, "shsp:" + ck, float(n))
		return
	_set_acc(u, "shsp:" + ck, 0.0)
	if not (src as Dictionary).get("alive", false):
		return
	stat["shsp_counter"] += 1
	_phys(u, src, float(u.get("def", 0.0)) * SHSP_ARMOR)
	_fx("shsp_counter", [u, src])


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


# ════════════════════════════════════════ 帧推进 ════════════════════════════════════════

func tick(delta: float) -> void:
	_tick_barbs()
	_tick_atl(delta)


## 138 鱼叉: 挂倒钩的敌人每移动 100 码掉一次血
func _tick_barbs() -> void:
	var t := float(battle._t)
	for o in battle._units:
		if not (o is Dictionary) or not o.has("_barb_from"):
			continue
		if not o.get("alive", false) or t >= float(o.get("_barb_until", 0.0)):
			o.erase("_barb_from")
			o.erase("_barb_dmg")
			continue
		var from: Vector2 = o["_barb_from"]
		var moved: float = DetMath.dist(from, Vector2(o["pos"]))
		if moved >= 100.0:
			o["_barb_from"] = Vector2(o["pos"])
			var src = o.get("_barb_src", null)
			if src is Dictionary:
				stat["barb_tick"] += 1
				battle._damage._apply_damage_from(src, o, battle._phys_after_armor(src, float(o.get("_barb_dmg", 0.0)), o), COL_PHYS, 0.0, false, true)
				_fx("barb_tick", [o])


func tick_unit(u: Dictionary, delta: float) -> void:
	if not u.get("alive", false):
		return
	var es = battle._equip_sys
	var ckp: Array = es.ck_save()
	for e in u.get("equips", []):
		if not (e is Dictionary):
			continue
		var eid := str(e.get("id", ""))
		if not ["p2eq_139", "p2eq_140", "p2eq_143", "p2eq_144", "p2eq_145"].has(eid):
			continue
		var si := _si_of(e)
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		var tl: Array = es.tally.push(u, ck)
		match eid:
			"p2eq_139":
				var a := _acc(u, "jav:" + ck) + delta
				if a >= JAV_IV:
					a -= JAV_IV
					_javelin(u, si, ck)
				_set_acc(u, "jav:" + ck, a)
			"p2eq_140":   # 骑枪: 每移动 100 码攒 1 层冲势(至多 5)
				var from: Vector2 = u.get("_lance_from", Vector2(u["pos"]))
				var mv: float = DetMath.dist(from, Vector2(u["pos"]))
				if mv >= LANCE_STEP:
					u["_lance_from"] = Vector2(u["pos"])
					var st2: int = mini(LANCE_MAX, int(_acc(u, "lance:" + ck)) + int(floor(mv / LANCE_STEP)))
					_set_acc(u, "lance:" + ck, float(st2))
			"p2eq_143":   # 方天画戟: 身边 ≥2 个敌人时每秒横扫一圈
				var near: Array = []
				for o in _enemies(u):
					if DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"])) <= FTJ_R:
						near.append(o)
				var a2 := _acc(u, "ftj:" + ck)
				if near.size() >= FTJ_MIN:
					a2 += delta
					if a2 >= 1.0:
						a2 -= 1.0
						stat["ftj"] += 1
						for o in near:
							_phys(u, o, float(FTJ_PCT[si]) * float(u.get("atk", 0.0)))
						_fx("ftj_spin", [u])
				else:
					a2 = 0.0
				_set_acc(u, "ftj:" + ck, a2)
			"p2eq_144":
				var a3 := _acc(u, "atl:" + ck) + delta
				if a3 >= ATL_IV:
					a3 -= ATL_IV
					_atlatl(u, si)
				_set_acc(u, "atl:" + ck, a3)
			"p2eq_145":
				var a4 := _acc(u, "eter:" + ck) + delta
				if a4 >= ETERNAL_IV:
					a4 -= ETERNAL_IV
					_eternal(u, si, ck)
				_set_acc(u, "eter:" + ck, a4)
		es.tally.pop(tl)
	es.ck_restore(ckp)


## 139 标枪: 最远的敌人; 按速度追着飞, 到了才结算
func _javelin(u: Dictionary, si: int, ck: String) -> void:
	var far = null
	var bd := -1.0
	for o in _enemies(u):
		if battle._is_untargetable(o):
			continue
		var d: float = DetMath.dist(Vector2(o["pos"]), Vector2(u["pos"]))
		if d > bd:
			bd = d
			far = o
	if not (far is Dictionary):
		return
	stat["jav"] += 1
	var me: Dictionary = u
	var tg: Dictionary = far
	var base: float = float(JAV_PCT[si]) * float(u.get("atk", 0.0))
	var node = null
	if battle._spear_syn.vfx != null and battle._spear_syn.vfx.has_method("javelin_fly"):
		node = battle._spear_syn.vfx.javelin_fly(u, tg)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, JAV_SPD,
		func(hit: bool) -> void:
			_fx("javelin_end", [node, hit])
			if not hit or not tg.get("alive", false):
				return
			stat["jav_hit"] += 1
			_phys(me, tg, base)
			var t := float(battle._t)
			var cur_mag: float = float(tg.get("slow_mag", 1.0)) if t < float(tg.get("slow_until", 0.0)) else 1.0
			tg["slow_mag"] = minf(cur_mag, 1.0 - JAV_SLOW)   # 已有更强的减速就留着更强的
			tg["slow_until"] = maxf(float(tg.get("slow_until", 0.0)), t + JAV_SLOW_SEC),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("javelin_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)


## 144 投矛器: 朝敌人最密的方向扇形掷出一排矛, 每根撞到第一个敌人结算
func _atlatl(u: Dictionary, si: int) -> void:
	var foes := _enemies(u)
	if foes.is_empty():
		return
	stat["atl"] += 1
	var c: Vector2 = battle._densest_enemy_point(u, 200.0)
	var base_dir: Vector2 = DetMath.norm(c - Vector2(u["pos"])) if DetMath.dist(c, Vector2(u["pos"])) > 1.0 else Vector2.RIGHT
	var n: int = int(ATL_N[si])
	for i in range(n):
		var k: float = (float(i) / float(maxi(1, n - 1)) - 0.5) * ATL_SPREAD if n > 1 else 0.0
		var dir: Vector2 = base_dir.rotated(k)
		var s := {"src": u, "pos": Vector2(u["pos"]), "dir": dir, "left": ATL_LEN, "si": si}
		_atl.append(s)
		_fx("atl_spear", [s])


func _tick_atl(delta: float) -> void:
	var keep: Array = []
	for s in _atl:
		var u: Dictionary = s["src"]
		var a: Vector2 = s["pos"]
		var step: float = minf(ATL_SPD * delta, float(s["left"]))
		var b: Vector2 = a + Vector2(s["dir"]) * step
		s["pos"] = b
		s["left"] = float(s["left"]) - step
		var hit = null
		var bd := INF
		for o in _enemies(u):
			var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(o["pos"]), a, b)
			var d: float = DetMath.dist(q, Vector2(o["pos"]))
			if d <= ATL_W + float(o.get("col_size", 22.0)) * 0.5:
				var along: float = DetMath.dist(a, q)
				if along < bd:
					bd = along
					hit = o
		if hit is Dictionary:
			stat["atl_hit"] += 1
			_phys(u, hit, float(ATL_PCT[int(s["si"])]) * float(u.get("atk", 0.0)))
			_fx("atl_end", [s, true])
			continue
		if float(s["left"]) > 0.5:
			keep.append(s)
		else:
			_fx("atl_end", [s, false])
	_atl = keep


## 145 永恒之枪: 生命值最高的敌人; 按速度飞到才结算: 钉住 1.5 秒 + 目标最大生命值 % 物理伤害
func _eternal(u: Dictionary, si: int, ck: String) -> void:
	var best = null
	var bh := -1.0
	for o in _enemies(u):
		if battle._is_untargetable(o):
			continue
		if float(o.get("hp", 0.0)) > bh:
			bh = float(o.get("hp", 0.0))
			best = o
	if not (best is Dictionary):
		return
	stat["eternal"] += 1
	var me: Dictionary = u
	var tg: Dictionary = best
	var pct: float = float(ETERNAL_PCT[si])
	var node = null
	if battle._spear_syn.vfx != null and battle._spear_syn.vfx.has_method("eternal_fly"):
		node = battle._spear_syn.vfx.eternal_fly(u, tg)
	var tp: Array = battle._equip_sys.tally.push(u, ck)
	battle._ballistics.launch_flight(u, Vector2(u["pos"]), tg, ETERNAL_SPD,
		func(hit: bool) -> void:
			_fx("eternal_end", [node, hit, tg])
			if not hit or not tg.get("alive", false):
				return
			stat["eternal_hit"] += 1
			_phys(me, tg, float(tg.get("maxHp", 0.0)) * pct)
			if tg.get("alive", false):
				battle._damage._stun(tg, ETERNAL_PIN, "eternal_pin"),
		func(_k: float, p2: Vector2, to2: Vector2) -> void:
			_fx("eternal_step", [node, p2, to2]))
	battle._equip_sys.tally.pop(tp)


func clear_all() -> void:
	_atl.clear()


func reset_match() -> void:
	pass
