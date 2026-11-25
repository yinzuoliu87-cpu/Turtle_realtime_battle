class_name EqBombBatch
extends RefCounted
## eq_bomb_batch.gd —— 炸弹羁绊 10 件 + 剑 2 费武士刀 的效果本体（2026-11-24 · 方案书 docs/plans/20261124f-炸弹羁绊.md §4.2 / §4.3）
##   097 鞭炮 · 098 爆竹筒 · 099 手雷 · 100 烟雾弹 · 101 粘弹 · 102 地雷 · 103 炸药桶 · 104 定时炸弹 · 105 炮筒 · 106 遥控炸弹 · 107 武士刀
##
## 接口 = 批④统一口（EquipSystem.B4_OWNER → `_b4`）：on_spawn / on_basic / on_hit / on_damaged / on_magic_hurt / on_death /
##   on_mana_full / tick / tick_unit / clear_all；另加 `on_any_basic(u, tgt)`（任何单位普攻都经过：烟雾弹潜行现形 + 召唤物攒龟能）。
##
## ── 地雷对照（CLAUDE.md §4）────────────────────────────────────────
##   §4.1 「X% 最大生命」一律真实 maxHp，不除 HP_MULT。
##   §4.2 单位字典不当键：在途表里存字典本身，比较 `is_same`，命中名单用数组 + is_same。
##   §4.3 只发伤害、不改伤害流程：物理走 `_resolve_dmg` + `_apply_damage_from(..., from_equip=true)`；真伤走 raw=true。
##   §4.4 `_t` 跨路累加：本批计时全是【逐帧累加的相对计时】（换路单位重建 ⇒ 自然清零）；
##        唯一要跨路的是 104 的叠层，按 `_food_key`（食物羁绊每路给每只单位贴的跨路身份键）存在系统对象上。
##   随机：只有 097 的几率，走已播种的 `battle._battle_rng`。
##   会走的波 / 弹道（105 重炮、107 剑气波与龙卷风）：每步按线段碰撞，命中名单防重复（memory fb-moving-hits-collide-per-step）。
var battle
## 演出层（可空：没有演出照样结算；门禁不依赖演出）
var vfx = null

# ── 097 鞭炮 ──
const CRACKER_CHANCE := [0.4, 0.7, 1.0]
const CRACKER_R := 100.0
const CRACKER_ATK := [0.35, 0.5, 0.7]
# ── 098 爆竹筒 ──
const TUBE_IV := 6.0
const TUBE_R := 120.0
const TUBE_FLAT := [20.0, 40.0, 70.0]
const TUBE_ATK := 0.2
const TUBE_SHIELD := [60.0, 120.0, 250.0]
const TUBE_SHIELD_SEC := 4.0
# ── 099 手雷 ──
const GRENADE_IV := 6.0
const GRENADE_R := 160.0
const GRENADE_FLAT := [80.0, 150.0, 280.0]
const GRENADE_ATK := 0.6
const GRENADE_SHRED := [10.0, 18.0, 30.0]
const GRENADE_SHRED_SEC := 4.0
const GRENADE_FLY := 0.6
# ── 100 烟雾弹 ──
const SMOKE_IV := 8.0
const SMOKE_SEC := 3.0
const SMOKE_R := 180.0
const SMOKE_PULSE := 1.0
const SMOKE_TRUE_FLAT := [50.0, 90.0, 160.0]
const SMOKE_TRUE_ATK := 0.5
# ── 101 粘弹 ──
const STICKY_IV := 8.0
const STICKY_SLOW := 0.4
const STICKY_FUSE := 2.0
const STICKY_FLAT := [40.0, 70.0, 120.0]
const STICKY_ATK := 0.3
const GOO_SEC := 1.5
const GOO_R := 130.0
const GOO_TICK := 0.5
const GOO_POISON := [5, 10, 18]
const GOO_SLOW := 0.3
# ── 102 地雷 ──
const MINE_COUNT := [3, 4, 5]
const MINE_DMG := [100.0, 180.0, 320.0]
const MINE_STUN := 0.8
const MINE_TRIGGER_R := 45.0
const MINE_BLAST_R := 110.0
## 不摆时默认埋在己方队形中心往前这么远，竖着按颗数等距排开
const MINE_FWD := 220.0
const MINE_GAP := 90.0
## 全队带多件地雷时，第 2 件起的默认列再往前挪这么多(不和第 1 件重叠)
const MINE_COL := 60.0
# ── 103 炸药桶 ──
const BARREL_R := 250.0
const BARREL_PCT := [0.3, 0.45, 0.8]
# ── 104 定时炸弹 ──
const TIMER_IV := 8.0
const TIMER_FUSE := 4.0
const TIMER_FLAT := [200.0, 380.0, 900.0]
const TIMER_ATK := 1.0
const TIMER_R := 120.0
const TIMER_STACK := 0.10
# ── 105 炮筒 ──
const CANNON_HP := [2000.0, 4000.0, 10000.0]
const CANNON_ATK := [70.0, 150.0, 400.0]
## 攻速 0.7 次/秒(用户 11-24「大炮攻速改为0.7」, 取代 0.5)
const CANNON_ASPD := 0.7
const CANNON_IV := 1.0 / CANNON_ASPD
const CANNON_RANGE := 900.0
const CANNON_SPLASH := 80.0
const CANNON_EN_MAX := 100.0
## 重炮每发消耗(用户 11-24「炮弹消耗改为40/35/30」, 取代 45/30/10 与最早的 25/20/10)。重炮期间龟能照全局规则照常涨
##   (攻速 0.7 ⇒ 两炮之间涨 ≈19), 打到 0 才退出
const CANNON_HEAVY_COST := [40.0, 35.0, 30.0]
const CANNON_HEAVY_MULT := 2.0
const CANNON_HEAVY_BLEED := [10, 20, 50]
const CANNON_HEAVY_LEN := 2000.0   # 重炮弹固定飞这么远(用户 11-24「重炮固定移动距离吧，2000码」)
const CANNON_HEAVY_W := 60.0
const CANNON_HEAVY_SPD := 900.0
const CANNON_BACK := 260.0
## 普通炮弹飞行速度(码/秒): 打出去要飞一段才落到目标身上(11-24 用户「普通炮你没弹道出来没」) —— 落到才结算
const CANNON_BALL_SPD := 1100.0
# ── 106 遥控炸弹 ──
const REMOTE_HP := [2500.0, 5000.0, 12000.0]
const REMOTE_RES := [70.0, 130.0, 200.0]
## 每秒损失最大生命值 / 爆炸固定物理伤害(用户 11-24「改为每秒损失4/2/0，物理固定伤害改为150/280/500」, 取代 10/8/0% 与 400/800/2000)
const REMOTE_DECAY := [0.04, 0.02, 0.0]
const REMOTE_R := 600.0
const REMOTE_FLAT := [150.0, 280.0, 500.0]
const REMOTE_TRUE_PCT := [0.08, 0.12, 0.20]
const REMOTE_BLEED := [40, 70, 120]
const REMOTE_FWD := 120.0
# ── 107 武士刀 ──
const KATANA_HP := [700.0, 1300.0, 2700.0]
const KATANA_ATK := [40.0, 75.0, 140.0]
const KATANA_EN_MAX := 60.0
const KATANA_WAVE_LEN := 700.0
const KATANA_WAVE_W := 50.0
## 剑气波 600 码/秒(11-25 用户「这个气波移动太快了」, 取代 1100) ⇒ 700 码走 1.17 秒
const KATANA_WAVE_SPD := 600.0
## 出波前摇: 技能动作「刀压低 → 上挑」, 上挑那一帧才出波(11-25 用户「应该是把刀放下，然后往上挥出一道这个气波」);
##   前摇 + 收招期间小将施法定身(不走、不普攻、不充龟能)
const KATANA_WAVE_WINDUP := 0.35
const KATANA_WAVE_RECOVER := 0.25
## 第 4 下: 蓄力 1.5 秒后甩出龙卷风, 甩完收招 0.3 秒(整段施法定身, 蓄力时不再普攻)
const KATANA_TORNADO_RECOVER := 0.3
const KATANA_WAVE_MULT := 1.5
const KATANA_CHARGE := 1.5
const KATANA_HEAL_TICK := 0.25
const KATANA_HEAL_TOTAL := 0.15
const KATANA_TORNADOES := 3
const KATANA_TORNADO_SPREAD := 0.32
const KATANA_TORNADO_LEN := 800.0
const KATANA_TORNADO_W := 55.0
const KATANA_TORNADO_SPD := 600.0
const KATANA_TORNADO_MULT := 3.0
const KATANA_AIR := 1.0

## ── 召唤物龟能: 照全游戏同一条规则(用户 11-24「龟能增长能按规则来吗」) ──
##   1 点龟能 = SEC_PER_ENERGY 秒(与龟的技能充能 / 斧头召唤物同一个换算: AxeEvolution.SEC_PER_ENERGY),
##   × 自身充能速率(echarge_perm) × 充能减速 debuff; 眩晕 / 击飞 / 引导 / 龟能锁 期间不充(同 RealtimeBattle3DScene._tick_skill_cd)。
##   炮筒重炮状态期间照常充(用户 11-24 方案书拍板「重炮状态中每发照常攒龟能」, 再确认「涨」); 武士刀小将蓄力期间不充。
const SEC_PER_ENERGY := 0.075
func _en_gain(u: Dictionary, delta: float) -> float:
	var t := float(battle._t)
	if t < float(u.get("stun_until", 0.0)) or t < float(u.get("channel_until", 0.0)) or bool(u.get("airborne", false)) \
			or t < float(u.get("storm_until", 0.0)) or t < float(u.get("energy_lock_until", 0.0)):
		return 0.0
	var m: float = float(u.get("echarge_perm", 1.0))
	if t < float(u.get("spd_dbf_until", 0.0)):
		m *= float(u.get("spd_echarge_mult", 1.0))
	return delta / SEC_PER_ENERGY * maxf(0.0, m)


const COL_PHYS := Color("#ff9a4a")
const COL_TRUE := Color("#ffffff")

# ── 在途 / 场上状态（换路 clear_all 清空）──
var _grenades: Array = []      ## {pos, t, src, si}
var _smokes: Array = []        ## {pos, t, owner, si, pulse}
var _stickies: Array = []      ## {tgt, t, src, si}
var _goos: Array = []          ## {pos, t, src, si, tick}
var _mines: Array = []         ## {pos, side, src, si}
var _timers: Array = []        ## {tgt, t, src, si, mult}
var _shreds: Array = []        ## {u, amt, until}
var _lines: Array = []         ## 直线弹道 {pos, dir, spd, left, w, src, hit:[], kind, si}
var _cannons: Array = []       ## {u, owner, si, acc, en, heavy}
var _balls: Array = []         ## 普通炮弹在途 {src, tgt, last, t}
var _remotes: Array = []       ## {u, owner, si, boomed}
var _katanas: Array = []       ## {u, owner, si, en, casts, charge, heal_acc}
## 104 跨路叠层：身份键 → 已绑颗数（一局结束 reset_match 清）
var _timer_stacks: Dictionary = {}
## 门禁量
var stat := {"cracker": 0, "tube": 0, "grenade": 0, "smoke_pulse": 0, "smoke_strike": 0, "sticky": 0, "goo_tick": 0,
	"mine_boom": 0, "barrel": 0, "timer_boom": 0, "cannon_shot": 0, "cannon_heavy": 0, "remote_boom": 0, "katana_wave": 0, "katana_tornado": 0}


func _init(b) -> void:
	battle = b
	vfx = BombEqVfx.new(b)


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


func _allies_of(u: Dictionary) -> Array:
	var out: Array = []
	var side := str(battle._eff_side(u))
	for o in battle._units:
		if o is Dictionary and o.get("alive", false) and str(battle._eff_side(o)) == side and not bool(o.get("_isEgg", false)) \
				and not battle._is_untouchable(o):
			out.append(o)
	return out


func _in_radius(arr: Array, c: Vector2, r: float) -> Array:
	var out: Array = []
	for o in arr:
		if DetMath.dist(Vector2(o["pos"]), c) <= r:
			out.append(o)
	return out


## 物理伤害一段（过护甲、吃出手方护穿、可暴击 = 装备效果同普通装备）
func _phys(src: Dictionary, tgt: Dictionary, base: float) -> void:
	if not tgt.get("alive", false) or base <= 0.0:
		return
	var dmg: int = battle._resolve_dmg(src, base, tgt, false)
	battle._damage._apply_damage_from(src, tgt, dmg, COL_PHYS, 0.0, false, true)


func _true(src: Dictionary, tgt: Dictionary, amt: float) -> void:
	if not tgt.get("alive", false) or amt <= 0.0:
		return
	battle._damage._apply_damage_from(src, tgt, int(round(amt)), COL_TRUE, 0.0, true, true)


func _slow(tgt: Dictionary, mag: float, sec: float) -> void:
	var t := float(battle._t)
	var cur := float(tgt.get("slow_mag", 1.0)) if t < float(tgt.get("slow_until", 0.0)) else 1.0
	tgt["slow_mag"] = minf(cur, mag)
	tgt["slow_until"] = maxf(float(tgt.get("slow_until", 0.0)), t + sec)


func _carry_key(u: Dictionary) -> String:
	var k := str(u.get("_food_key", ""))
	return k if k != "" else "%s|%s" % [str(u.get("side", "")), str(u.get("id", ""))]


## 携带者身上某件装备的第 n 份的累加器（同一件带多份 = 各自独立，memory project-dup-equip-each-independent-1113）
func _acc(u: Dictionary, key: String) -> float:
	var d: Dictionary = u.get("_bomb_acc", {})
	return float(d.get(key, 0.0))


func _set_acc(u: Dictionary, key: String, v: float) -> void:
	var d: Dictionary = u.get("_bomb_acc", {})
	d[key] = v
	u["_bomb_acc"] = d


# ════════════════════════════════════════ 批④统一口 ════════════════════════════════════════

func on_spawn(u: Dictionary, eid: String, si: int) -> void:
	match eid:
		"p2eq_105":
			_spawn_cannon(u, si)
		"p2eq_106":
			_spawn_remote(u, si)
		"p2eq_107":
			_spawn_katana(u, si)


func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if eid != "p2eq_097" or not (tgt is Dictionary) or not tgt.get("alive", false):
		return
	if battle._battle_rng.randf() >= float(CRACKER_CHANCE[si]):
		return
	stat["cracker"] += 1
	var c := Vector2(tgt["pos"])
	var hits: Array = _in_radius(_enemies_of(u), c, CRACKER_R)
	_fx("cracker_burst", [c, tgt, hits])
	for o in hits:
		_phys(u, o, float(CRACKER_ATK[si]) * float(u["atk"]))


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_death(u: Dictionary, eid: String, si: int) -> void:
	if eid != "p2eq_103":
		return
	stat["barrel"] += 1
	var c := Vector2(u["pos"])
	_fx("barrel_blast", [c, BARREL_R, u])
	var amt: float = float(BARREL_PCT[si]) * float(u.get("maxHp", 0.0))
	for o in _in_radius(_enemies_of(u), c, BARREL_R):
		_phys(u, o, amt)


func on_mana_full(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 任何单位普攻（EquipSystem._eq_on_basic_attack 最前面调，不论有没有装备）
func on_any_basic(u: Dictionary, tgt) -> void:
	if bool(u.get("_katana_minion", false)) and tgt is Dictionary:
		_fx("katana_hslash", [u, tgt])   # 107 小将普攻命中的横斩刀光(只管画面)
	if bool(u.get("_smoke_hidden", false)) and float(battle._t) >= float(u.get("untargetable_until", 0.0)):
		u["_smoke_hidden"] = false          # 潜行已自然到期（离开烟雾）⇒ 这一下不算潜行攻击
	if bool(u.get("_smoke_hidden", false)):
		u["_smoke_hidden"] = false
		u["untargetable_until"] = float(battle._t)          # 攻击即现形
		var si := int(u.get("_smoke_si", 0))
		if tgt is Dictionary and tgt.get("alive", false):
			stat["smoke_strike"] += 1
			var by: Array = u.get("_smoke_by", [u, "p2eq_100"])
			var tl: Array = battle._equip_sys.tally.push_for(u, by[0], str(by[1]))   # 伤害源 = 潜行的这只，账记给放烟的那件
			_true(u, tgt, float(SMOKE_TRUE_FLAT[si]) + SMOKE_TRUE_ATK * float(u["atk"]))
			battle._equip_sys.tally.pop(tl)
			_fx("smoke_strike", [Vector2(tgt["pos"]), tgt])


## 每帧（全局一次）：在途 / 场上东西
func tick(delta: float) -> void:
	var t := float(battle._t)
	_tick_grenades(t)
	_tick_smokes(t, delta)
	_tick_stickies(t)
	_tick_goos(t, delta)
	_tick_mines()
	_tick_timers(t)
	_tick_shreds(t)
	_tick_lines(delta)
	_tick_cannons(delta)
	_tick_balls()
	_tick_remotes(delta)
	_tick_katanas(delta)
	if vfx != null:
		vfx.tick(delta)


## 每帧（每个带炸弹 / 武士刀的单位一次，守卫 `_b4_eq`）：定时投放
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
			"p2eq_098": iv = TUBE_IV
			"p2eq_099": iv = GRENADE_IV
			"p2eq_100": iv = SMOKE_IV
			"p2eq_101": iv = STICKY_IV
			"p2eq_104": iv = TIMER_IV
			_: continue
		var si := clampi(int(e.get("star", 1)), 1, 3) - 1
		## 份号：同名多件各自计时、各自记账（第 1 件 = 原 id，第 2 件起 = id#2…）
		es.ck_set(u, e)
		var ck: String = es.key_of(u, eid)
		var a := _acc(u, ck) + delta
		if a < iv:
			_set_acc(u, ck, a)
			continue
		_set_acc(u, ck, a - iv)
		var tl: Array = es.tally.push(u, ck)
		match eid:
			"p2eq_098": _tube(u, si)
			"p2eq_099": _throw_grenade(u, si, ck)
			"p2eq_100": _drop_smoke(u, si, ck)
			"p2eq_101": _throw_sticky(u, si, ck)
			"p2eq_104": _bind_timer(u, si, ck)
		es.tally.pop(tl)
	es.ck_restore(ckp)


## 在途东西落地结算时切回「投放它的那件装备」的统计上下文
func _tl_in(rec: Dictionary) -> Array:
	return battle._equip_sys.tally.push(rec["src"], str(rec.get("ck", "")))


func _tl_out(tl: Array) -> void:
	battle._equip_sys.tally.pop(tl)


func clear_all() -> void:
	for s in _shreds:
		_unshred(s)
	_grenades.clear(); _smokes.clear(); _stickies.clear(); _goos.clear(); _mines.clear()
	_timers.clear(); _shreds.clear(); _lines.clear(); _cannons.clear(); _remotes.clear(); _katanas.clear(); _balls.clear()
	if vfx != null:
		vfx.clear()


## 一局结束（不是换路）：104 跨路叠层清零
func reset_match() -> void:
	_timer_stacks.clear()


# ════════════════════════════════════════ 098 爆竹筒 ════════════════════════════════════════

func _tube(u: Dictionary, si: int) -> void:
	stat["tube"] += 1
	var c := Vector2(u["pos"])
	_fx("tube_blast", [c, TUBE_R, u])
	for o in _in_radius(_enemies_of(u), c, TUBE_R):
		_phys(u, o, float(TUBE_FLAT[si]) + TUBE_ATK * float(u["atk"]))
		battle._damage._knockback(u, o, 0.0, 0.6, 1.0)
	battle._damage._grant_shield(u, float(TUBE_SHIELD[si]), TUBE_SHIELD_SEC)


# ════════════════════════════════════════ 099 手雷 ════════════════════════════════════════

func _throw_grenade(u: Dictionary, si: int, ck: String = "p2eq_099") -> void:
	if _enemies_of(u).is_empty():
		return
	var p: Vector2 = battle._densest_enemy_point(u, GRENADE_R)
	_grenades.append({"pos": p, "t": float(battle._t) + GRENADE_FLY, "src": u, "si": si, "ck": ck})
	_fx("grenade_throw", [Vector2(u["pos"]), p, GRENADE_FLY])


func _tick_grenades(t: float) -> void:
	var keep: Array = []
	for g in _grenades:
		if t < float(g["t"]):
			keep.append(g)
			continue
		var u: Dictionary = g["src"]
		var si := int(g["si"])
		stat["grenade"] += 1
		var tl := _tl_in(g)
		_fx("grenade_blast", [Vector2(g["pos"]), GRENADE_R])
		for o in _in_radius(_enemies_of(u), Vector2(g["pos"]), GRENADE_R):
			_phys(u, o, float(GRENADE_FLAT[si]) + GRENADE_ATK * float(u["atk"]))
			if o.get("alive", false):
				var amt := float(GRENADE_SHRED[si])
				if vfx != null and battle.get("_vfx") != null:
					battle._vfx._float_text(Vector2(o["pos"]) + Vector2(0, -70), Lang.t("护甲 -%d") % int(amt), VisualConstants.color_of("debuff-label"))   # 破甲看得见
				o["def_shred"] = float(o.get("def_shred", 0.0)) + amt
				battle._recalc_stats(o)
				_shreds.append({"u": o, "amt": amt, "until": t + GRENADE_SHRED_SEC})
		_tl_out(tl)
	_grenades = keep


func _unshred(s: Dictionary) -> void:
	var o: Dictionary = s["u"]
	o["def_shred"] = maxf(0.0, float(o.get("def_shred", 0.0)) - float(s["amt"]))
	battle._recalc_stats(o)


func _tick_shreds(t: float) -> void:
	var keep: Array = []
	for s in _shreds:
		if t < float(s["until"]):
			keep.append(s)
		else:
			_unshred(s)
	_shreds = keep


# ════════════════════════════════════════ 100 烟雾弹 ════════════════════════════════════════

func _drop_smoke(u: Dictionary, si: int, ck: String = "p2eq_100") -> void:
	var c := Vector2(u["pos"])
	_smokes.append({"pos": c, "t": float(battle._t) + SMOKE_SEC, "owner": u, "src": u, "si": si, "ck": ck, "pulse": SMOKE_PULSE})
	_fx("smoke_cloud", [c, SMOKE_R, SMOKE_SEC])


func _tick_smokes(t: float, delta: float) -> void:
	var keep: Array = []
	for s in _smokes:
		if t >= float(s["t"]):
			continue
		s["pulse"] = float(s["pulse"]) + delta
		if float(s["pulse"]) >= SMOKE_PULSE:
			s["pulse"] = float(s["pulse"]) - SMOKE_PULSE
			for a in _in_radius(_allies_of(s["owner"]), Vector2(s["pos"]), SMOKE_R):
				stat["smoke_pulse"] += 1
				## 多给 0.1 秒重叠：下一次脉冲前不留空档（待在烟里 = 一直潜行；攻击现形后等下一次脉冲再潜）
				a["untargetable_until"] = maxf(float(a.get("untargetable_until", 0.0)), t + SMOKE_PULSE + 0.1)
				a["_smoke_hidden"] = true
				a["_smoke_si"] = int(s["si"])
				a["_smoke_by"] = [s["owner"], str(s["ck"])]
		keep.append(s)
	_smokes = keep


# ════════════════════════════════════════ 101 粘弹 ════════════════════════════════════════

func _throw_sticky(u: Dictionary, si: int, ck: String = "p2eq_101") -> void:
	var tgt = battle._targeting._nearest_enemy(u)
	if not (tgt is Dictionary):
		return
	_slow(tgt, 1.0 - STICKY_SLOW, STICKY_FUSE)
	_stickies.append({"tgt": tgt, "t": float(battle._t) + STICKY_FUSE, "src": u, "si": si, "ck": ck})
	_fx("sticky_attach", [tgt, STICKY_FUSE, u])


func _tick_stickies(t: float) -> void:
	var keep: Array = []
	for s in _stickies:
		if t < float(s["t"]):
			keep.append(s)
			continue
		var tgt: Dictionary = s["tgt"]
		var u: Dictionary = s["src"]
		var si := int(s["si"])
		var c := Vector2(tgt["pos"])
		stat["sticky"] += 1
		var tl := _tl_in(s)
		_fx("sticky_blast", [c, GOO_R, tgt])
		_phys(u, tgt, float(STICKY_FLAT[si]) + STICKY_ATK * float(u["atk"]))
		_goos.append({"pos": c, "t": t + GOO_SEC, "src": u, "si": si, "tick": GOO_TICK, "ck": str(s.get("ck", ""))})
		_tl_out(tl)
	_stickies = keep


## 粘液：每 GOO_TICK 秒叠一次中毒（1.5 秒内共 3 次：0.5 / 1.0 / 1.5），在里面的敌人持续减速
func _tick_goos(t: float, delta: float) -> void:
	var keep: Array = []
	for g in _goos:
		var u: Dictionary = g["src"]
		var si := int(g["si"])
		var inside := _in_radius(_enemies_of(u), Vector2(g["pos"]), GOO_R)
		for o in inside:
			_slow(o, 1.0 - GOO_SLOW, 0.2)
		g["tick"] = float(g["tick"]) - delta
		if float(g["tick"]) <= 0.0001:
			g["tick"] = float(g["tick"]) + GOO_TICK
			stat["goo_tick"] += 1
			var tl := _tl_in(g)
			for o in inside:
				battle._damage._apply_dot_stacks(o, "poison", int(GOO_POISON[si]), u)
			_tl_out(tl)
		if t < float(g["t"]) - 0.0001:
			keep.append(g)
	_goos = keep


# ════════════════════════════════════════ 102 地雷 ════════════════════════════════════════

## 埋雷（用户 11-24「你上半场是四个，那你下半场也是四个，中间也是四个，而且四个的位置都应该一致」）:
##   地雷按【全队】算，不按「携带者在哪一路」—— 每个战场(上路 / 下路 / 终极)开打时，这一方全队带的每一件地雷都按它的颗数埋一遍。
##   位置存在【那件地雷自己的装备条目】上 `mines = [[dx, dy], …]`，坐标相对本方队形中心(与统领站位 `off` 同一套：左方视角、整数、右方镜像 x)
##   ⇒ 三个战场的雷逐颗同位。存在装备条目上 ⇒ 快照 / 裁判机 / 对手还原本来就把装备原样带着走，不用改快照结构。
##   没摆过 ⇒ 默认位置 `default_mine_off(第几件, 第几颗, 颗数)`(站位图显示的默认用同一个式子)。
## 名单：双路(正式对局 / 裁判机) = 全队名单(我方 GameState.team_p2_equips_for_synergy，对方 dual_ghost 两路规格，与羁绊计数同源)；
##   单路 / 调试场 / 门禁合成单位 = 场上单位身上的装备。
## 由 EquipStatsApply._b4_on_spawn_all 末尾每个战场调一次(换路 clear_all 先清掉上一路的雷)。
func place_team_mines() -> void:
	for side in ["left", "right"]:
		var entries: Array = mine_entries_of(side)
		if entries.is_empty():
			continue
		var src = _mine_src(side)
		if src == null:
			continue
		var fwd := 1.0 if side == "left" else -1.0
		var base: Vector2 = battle._arena_center + Vector2(-float(LineupPos.FORMATION_DX) * fwd, 0.0)
		for k in range(entries.size()):
			var e: Dictionary = entries[k]
			var si: int = clampi(int(e.get("star", 1)), 1, 3) - 1
			var n := int(MINE_COUNT[si])
			var custom: Array = e.get("mines", []) if e.get("mines") is Array else []
			for i in range(n):
				var off: Vector2i = default_mine_off(k, i, n)
				if i < custom.size() and custom[i] is Array and (custom[i] as Array).size() >= 2:
					off = LineupPos.clamp_off(Vector2i(int(custom[i][0]), int(custom[i][1])))
				var p: Vector2 = ArenaShape.clamp_in(LineupPos.to_field(base, off, side), battle.ARENA, 60.0)   # 与站位图同一个岛形(pad 60)
				_mines.append({"pos": p, "side": side, "src": src, "si": si, "ck": "p2eq_102"})
				_fx("mine_place", [p, side])


## 这一方全队带的地雷条目(按名单顺序；站位图的「第几件」与这里同序)
func mine_entries_of(side: String) -> Array:
	var src: Array = []
	if battle.has_method("_is_dual_lane_mode") and battle._is_dual_lane_mode() and GameState != null:
		if side == "left":
			src = GameState.team_p2_equips_for_synergy()
		elif GameState.dual_ghost is Dictionary:
			for lane in ["top", "bottom"]:
				for spec in battle._dual_foe_lane(lane):
					if spec is Dictionary and (spec as Dictionary).get("equips") is Array:
						src.append_array((spec as Dictionary)["equips"])
	else:
		for u in battle._units:
			if u is Dictionary and str(u.get("side", "")) == side and u.get("alive", false):
				src.append_array(u.get("equips", []))
	var out: Array = []
	for e in src:
		if e is Dictionary and str((e as Dictionary).get("id", "")) == "p2eq_102":
			out.append(e)
	return out


## 雷的伤害记在谁头上：场上带地雷的那只优先(吃它的护穿)，没有就这一方第一只活着的单位
func _mine_src(side: String):
	var first = null
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false) or str(u.get("side", "")) != side \
				or bool(u.get("_isEgg", false)) or bool(u.get("is_trainer", false)) or bool(u.get("is_summon", false)):
			continue
		if first == null:
			first = u
		for e in u.get("equips", []):
			if e is Dictionary and str((e as Dictionary).get("id", "")) == "p2eq_102":
				return u
	return first


## 默认地雷位置(相对队形中心)：第 k 件地雷一列，往前 MINE_FWD 码起、每多一件再往前 MINE_COL 码；一列里竖着间隔 MINE_GAP
static func default_mine_off(k: int, i: int, n: int) -> Vector2i:
	return LineupPos.clamp_off(Vector2i(int(MINE_FWD + MINE_COL * float(k)), int(round((float(i) - float(n - 1) * 0.5) * MINE_GAP))))


## 局外装备条目 → 局内装备条目（RealtimeBattle3DScene._inject_equipment 用）：照旧只留 id / star / chg，另外带上地雷的摆位
static func eq_entry(it: Dictionary, chg: int) -> Dictionary:
	var d := {"id": str(it["id"]), "star": int(it.get("star", 1)), "chg": chg}
	if it.get("mines") is Array:
		d["mines"] = (it["mines"] as Array).duplicate(true)
	return d


func _tick_mines() -> void:
	var keep: Array = []
	for m in _mines:
		var u: Dictionary = m["src"]
		var trig := false
		for o in _enemies_of(u):
			if not bool(o.get("airborne", false)) and DetMath.dist(Vector2(o["pos"]), Vector2(m["pos"])) <= MINE_TRIGGER_R:
				trig = true
				break
		if not trig:
			keep.append(m)
			continue
		var si := int(m["si"])
		stat["mine_boom"] += 1
		var tl := _tl_in(m)
		_fx("mine_blast", [Vector2(m["pos"]), MINE_BLAST_R])
		for o in _in_radius(_enemies_of(u), Vector2(m["pos"]), MINE_BLAST_R):
			_phys(u, o, float(MINE_DMG[si]))
			if o.get("alive", false):
				battle._damage._stun(o, MINE_STUN, "p2eq_102")
				if vfx != null and battle.get("_vfx") != null:
					battle._vfx._float_text(Vector2(o["pos"]) + Vector2(0, -70), Lang.t("眩晕"), VisualConstants.color_of("debuff-label"))   # 被炸晕看得见
		_tl_out(tl)
	_mines = keep


# ════════════════════════════════════════ 104 定时炸弹 ════════════════════════════════════════

func _bind_timer(u: Dictionary, si: int, ck: String = "p2eq_104") -> void:
	var tgt = battle._targeting._nearest_enemy(u)
	if not (tgt is Dictionary):
		return
	var k := _carry_key(u) + "|" + ck
	var n: int = int(_timer_stacks.get(k, 0))
	_timer_stacks[k] = n + 1
	_timers.append({"tgt": tgt, "t": float(battle._t) + TIMER_FUSE, "src": u, "si": si, "ck": ck, "mult": 1.0 + TIMER_STACK * float(n)})
	_fx("timer_attach", [tgt, TIMER_FUSE])


## 已绑颗数（门禁 / 面板读）
func timer_stacks_of(u: Dictionary) -> int:
	var pre := _carry_key(u) + "|"
	var n := 0
	for k in _timer_stacks:
		if str(k).begins_with(pre):
			n += int(_timer_stacks[k])
	return n


func _tick_timers(t: float) -> void:
	var keep: Array = []
	for b in _timers:
		if t < float(b["t"]):
			keep.append(b)
			continue
		var tgt: Dictionary = b["tgt"]
		var u: Dictionary = b["src"]
		var si := int(b["si"])
		var c := Vector2(tgt["pos"])
		stat["timer_boom"] += 1
		var tl := _tl_in(b)
		_fx("timer_blast", [c, TIMER_R, tgt])
		var base: float = (float(TIMER_FLAT[si]) + TIMER_ATK * float(u["atk"])) * float(b["mult"])
		for o in _in_radius(_enemies_of(u), c, TIMER_R):
			_phys(u, o, base)
		_tl_out(tl)
	_timers = keep


# ════════════════════════════════════════ 直线弹道（105 重炮 / 107 剑气波 / 龙卷风）════════════════════════════════════════

## `hit` 可传共用的命中名单：107 一次吹出的 3 道龙卷风共用一份 ⇒ 同一个敌人一轮只吃一道
func _launch_line(src: Dictionary, from: Vector2, dir: Vector2, spd: float, length: float, w: float, kind: String, si: int, hit: Array = []) -> void:
	_lines.append({"pos": from, "dir": DetMath.norm(dir), "spd": spd, "left": length, "w": w, "src": src, "hit": hit, "kind": kind, "si": si})
	_fx("line_launch", [kind, from, DetMath.norm(dir), spd, length, src])


func _tick_lines(delta: float) -> void:
	var keep: Array = []
	for L in _lines:
		var step := minf(float(L["spd"]) * delta, float(L["left"]))
		var a: Vector2 = L["pos"]
		var b: Vector2 = a + Vector2(L["dir"]) * step
		var src: Dictionary = L["src"]
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
		L["pos"] = b
		L["left"] = float(L["left"]) - step
		if float(L["left"]) > 0.01:
			keep.append(L)
	_lines = keep


func _line_hit(L: Dictionary, o: Dictionary) -> void:
	var src: Dictionary = L["src"]
	var si := int(L["si"])
	match str(L["kind"]):
		"cannon_heavy":
			_fx("cannon_hit", [o])
			_phys(src, o, CANNON_HEAVY_MULT * float(src["atk"]))
			if o.get("alive", false):
				battle._damage._apply_dot_stacks(o, "bleed", int(CANNON_HEAVY_BLEED[si]), src)
				## 往两边推(用户 11-24「重炮的话我希望的是向两边去击退吧」): 以炮弹飞行线为界, 在线哪一侧就往哪一侧推
				var dv: Vector2 = Vector2(L["dir"])
				var rel: Vector2 = Vector2(o["pos"]) - Vector2(L["pos"])
				var side_s: float = 1.0 if (dv.x * rel.y - dv.y * rel.x) >= 0.0 else -1.0
				var perp: Vector2 = Vector2(-dv.y, dv.x) * side_s
				battle._damage._knockback({"pos": Vector2(o["pos"]) - perp * 10.0, "side": src.get("side", "left")}, o, 0.0, 0.5, 1.6)
		"katana_wave":
			_phys(src, o, KATANA_WAVE_MULT * float(src["atk"]))
		"katana_tornado":
			_phys(src, o, KATANA_TORNADO_MULT * float(src["atk"]))
			if o.get("alive", false):
				battle._damage._knockback(src, o, 0.0, BombSynergySystem.air_vy_mult(float(battle.KNOCK_VY), float(battle.GRAVITY), KATANA_AIR), 0.0)


# ════════════════════════════════════════ 105 炮筒 ════════════════════════════════════════

func _spawn_cannon(owner: Dictionary, si: int) -> void:
	var p = battle._spawn._spawn_summon(owner, "cannon", float(CANNON_HP[si]), float(CANNON_ATK[si]),
		{"label": "炮筒", "spr_id": "eq-cannon", "col_size": 72.0, "hp_w": 44.0,
		 "atk_interval": CANNON_IV, "atk_range": CANNON_RANGE, "melee": false})
	if p == null:
		return
	p["no_basic"] = true          # 普攻由本系统驱动（要攒龟能、要切重炮）
	p["no_move"] = true
	p["move_spd"] = 0.0
	var fwd := 1.0 if str(battle._eff_side(owner)) == "left" else -1.0
	var pos := Vector2(owner["pos"]) - Vector2(CANNON_BACK * fwd, 0.0)
	pos.x = clampf(pos.x, battle.ARENA.position.x + 30.0, battle.ARENA.end.x - 30.0)
	p["pos"] = pos
	if p.has("sprite") and is_instance_valid(p["sprite"]):
		p["sprite"].position = battle._world_pos(p["pos"], battle.GROUND_LIFT)
	## 调试场「满龟能」(主人带 _edit_fe; 正式对局没有这个字段): 一出场就满, 方便看重炮
	## 头顶龟能条: 召唤物带 maxEnergy/energy 就画(BattleRender 自带龟能召唤物那条路), 每帧由 _tick_cannons 同步
	p["maxEnergy"] = CANNON_EN_MAX
	p["energy"] = 0.0
	## 调试场「满龟能」(主人带 _edit_fe; 正式对局没有这个字段): 差 3 炮满能起步 ⇒ 演示里先看到 3 发普通炮再切重炮
	_cannons.append({"u": p, "owner": owner, "si": si, "acc": 0.0, "en": (CANNON_EN_MAX - 3.0 * CANNON_IV / SEC_PER_ENERGY * 0.25) if bool(owner.get("_edit_fe", false)) else 0.0, "heavy": false})


## 门禁读：某门炮筒当前龟能 / 是否重炮
func cannon_state(i: int = 0) -> Dictionary:
	return _cannons[i] if i < _cannons.size() else {}


func _tick_cannons(delta: float) -> void:
	for c in _cannons:
		var p: Dictionary = c["u"]
		if not p.get("alive", false):
			continue
		p["energy"] = float(c["en"])
		if float(battle._t) < float(p.get("stun_until", 0.0)):
			continue
		c["en"] = minf(CANNON_EN_MAX, float(c["en"]) + _en_gain(p, delta))
		p["energy"] = float(c["en"])
		## 龟能一满就进入重炮形态(当场播变身, 不等下一炮) —— 下一炮起是重炮
		if not bool(c["heavy"]) and float(c["en"]) >= CANNON_EN_MAX:
			c["heavy"] = true
			_fx("cannon_heavy_on", [p])
		c["acc"] = float(c["acc"]) + delta
		if float(c["acc"]) < CANNON_IV:
			continue
		var tgt = battle._targeting._nearest_enemy(p)
		if not (tgt is Dictionary) or DetMath.dist(Vector2(p["pos"]), Vector2(tgt["pos"])) > CANNON_RANGE:
			continue
		c["acc"] = float(c["acc"]) - CANNON_IV
		var si := int(c["si"])
		if bool(c["heavy"]):
			stat["cannon_heavy"] += 1
			c["en"] = maxf(0.0, float(c["en"]) - float(CANNON_HEAVY_COST[si]))
			_launch_line(p, Vector2(p["pos"]), Vector2(tgt["pos"]) - Vector2(p["pos"]), CANNON_HEAVY_SPD, CANNON_HEAVY_LEN, CANNON_HEAVY_W, "cannon_heavy", si)
		else:
			stat["cannon_shot"] += 1
			var fly: float = DetMath.dist(Vector2(p["pos"]), Vector2(tgt["pos"])) / CANNON_BALL_SPD
			_balls.append({"src": p, "tgt": tgt, "last": Vector2(tgt["pos"]), "t": float(battle._t) + fly})
			_fx("cannon_fire", [p])
			_fx("cannon_shot", [Vector2(p["pos"]), Vector2(tgt["pos"]), tgt, fly, p])
		## 龟能耗光才退出(方案书「龟能耗光才退出」; 11-24 用户「鬼能都没消耗完，为什么…停止这个技能状态」):
		##   剩的不够一发也照样打重炮、把剩下的扣光, 扣到 0 才回普通炮
		if bool(c["heavy"]) and float(c["en"]) <= 0.0:
			c["heavy"] = false
			_fx("cannon_heavy_off", [p])
		p["energy_view"] = float(c["en"])
		p["energy"] = float(c["en"])


## 普通炮弹落地: 跟着目标走(目标死了 = 落在它最后的位置), 到点才炸、才扣血
func _tick_balls() -> void:
	var t := float(battle._t)
	var keep: Array = []
	for b in _balls:
		var tg: Dictionary = b["tgt"]
		if tg.get("alive", false):
			b["last"] = Vector2(tg["pos"])
		if t < float(b["t"]):
			keep.append(b)
			continue
		var p: Dictionary = b["src"]
		_fx("cannon_ball_hit", [Vector2(b["last"]), tg if tg.get("alive", false) else null])
		for o in _in_radius(_enemies_of(p), Vector2(b["last"]), CANNON_SPLASH):
			_phys(p, o, float(p["atk"]))
	_balls = keep


# ════════════════════════════════════════ 106 遥控炸弹 ════════════════════════════════════════

func _spawn_remote(owner: Dictionary, si: int) -> void:
	var p = battle._spawn._spawn_summon(owner, "remote_bomb", float(REMOTE_HP[si]), 0.0,
		{"label": "遥控炸弹", "spr_id": "eq-remote-bomb", "col_size": 34.0, "hp_w": 40.0,
		 "atk_interval": 1.0, "atk_range": 30.0, "melee": true})
	if p == null:
		return
	p["no_basic"] = true          # 不攻击：只追着敌人走
	p["def"] = float(REMOTE_RES[si]); p["base_def"] = float(REMOTE_RES[si])
	p["mr"] = float(REMOTE_RES[si]); p["base_mr"] = float(REMOTE_RES[si])
	var fwd := 1.0 if str(battle._eff_side(owner)) == "left" else -1.0
	p["pos"] = Vector2(owner["pos"]) + Vector2(REMOTE_FWD * fwd, 0.0)
	if p.has("sprite") and is_instance_valid(p["sprite"]):
		p["sprite"].position = battle._world_pos(p["pos"], battle.GROUND_LIFT)
	_remotes.append({"u": p, "owner": owner, "si": si, "boomed": false, "pos": Vector2(p["pos"])})


func _tick_remotes(delta: float) -> void:
	for r in _remotes:
		if bool(r["boomed"]):
			continue
		var p: Dictionary = r["u"]
		var si := int(r["si"])
		if p.get("alive", false):
			r["pos"] = Vector2(p["pos"])
			var decay: float = float(REMOTE_DECAY[si]) * float(p.get("maxHp", 0.0)) * delta
			if decay > 0.0:
				p["hp"] = float(p["hp"]) - decay
				if float(p["hp"]) > 0.0:
					continue
				p["hp"] = 0.0
				battle._kill(p)
			else:
				continue
		r["boomed"] = true
		_remote_boom(r)


func _remote_boom(r: Dictionary) -> void:
	var owner: Dictionary = r["owner"]
	var p: Dictionary = r["u"]
	var si := int(r["si"])
	var c: Vector2 = r["pos"]
	stat["remote_boom"] += 1
	_fx("remote_blast", [c, REMOTE_R])
	var true_amt: float = float(REMOTE_TRUE_PCT[si]) * float(owner.get("maxHp", 0.0))
	for o in _in_radius(_enemies_of(p), c, REMOTE_R):
		_phys(p, o, float(REMOTE_FLAT[si]))
		_true(p, o, true_amt)
		if o.get("alive", false):
			battle._damage._apply_dot_stacks(o, "bleed", int(REMOTE_BLEED[si]), p)


# ════════════════════════════════════════ 107 武士刀 ════════════════════════════════════════

func _spawn_katana(owner: Dictionary, si: int) -> void:
	var p = battle._spawn._spawn_summon(owner, "katana", float(KATANA_HP[si]), float(KATANA_ATK[si]),
		{"label": "武士刀小将", "spr_id": "eq-katana", "col_size": 46.0, "hp_w": 36.0,
		 "atk_interval": 1.0, "atk_range": 60.0, "melee": true})
	if p == null:
		return
	## 普攻 = 横斩(11-25 用户「普通攻击应该是一个横横斩」): 自带普攻帧表(前摇 / 命中 / 后摇由 AttackRhythm 对齐), 命中画专属刀光、不叠通用火花
	p["_act_rows"] = {"attack": ["vfx/eq-katana-attack.png", 14.0]}
	p["_own_hit_vfx"] = true
	p["_katana_minion"] = true
	p["maxEnergy"] = KATANA_EN_MAX   # 头顶龟能条(见 _spawn_cannon)
	p["energy"] = 0.0
	_katanas.append({"u": p, "owner": owner, "si": si, "en": KATANA_EN_MAX if bool(owner.get("_edit_fe", false)) else 0.0, "casts": 0, "charge": -1.0, "heal_acc": 0.0, "wave_t": -1.0})


func katana_state(i: int = 0) -> Dictionary:
	return _katanas[i] if i < _katanas.size() else {}


func _tick_katanas(delta: float) -> void:
	for k in _katanas:
		var p: Dictionary = k["u"]
		if not p.get("alive", false):
			continue
		if float(k["charge"]) < 0.0:   # 蓄力期间不充(持续状态锁龟能)
			k["en"] = minf(KATANA_EN_MAX, float(k["en"]) + _en_gain(p, delta))
		p["energy"] = float(k["en"])
		if float(k["wave_t"]) >= 0.0:   # 出波前摇: 上挑那一刻出波
			k["wave_t"] = float(k["wave_t"]) - delta
			if float(k["wave_t"]) <= 0.0:
				k["wave_t"] = -1.0
				stat["katana_wave"] += 1
				_launch_line(p, Vector2(p["pos"]), Vector2(k["aim"]), KATANA_WAVE_SPD, KATANA_WAVE_LEN, KATANA_WAVE_W, "katana_wave", int(k["si"]))
			continue
		if float(k["charge"]) >= 0.0:
			k["charge"] = float(k["charge"]) + delta
			k["heal_acc"] = float(k["heal_acc"]) + delta
			while float(k["heal_acc"]) >= KATANA_HEAL_TICK - 0.0001:
				k["heal_acc"] = float(k["heal_acc"]) - KATANA_HEAL_TICK
				var per: float = KATANA_HEAL_TOTAL / (KATANA_CHARGE / KATANA_HEAL_TICK) * float(p.get("maxHp", 0.0))
				battle._damage._heal(p, per)   # 走正式回血(绿字 / 治疗统计 / 重伤减疗都照常), 不直接改 hp
			if float(k["charge"]) >= KATANA_CHARGE - 0.0001:
				k["charge"] = -1.0
				_katana_tornadoes(k)
			continue
		if float(k["en"]) < KATANA_EN_MAX:
			continue
		var tgt = battle._targeting._nearest_enemy(p)
		if not (tgt is Dictionary):
			continue
		k["en"] = 0.0
		k["casts"] = int(k["casts"]) + 1
		if int(k["casts"]) % 4 == 0:
			k["charge"] = 0.0
			k["heal_acc"] = 0.0
			k["aim"] = Vector2(tgt["pos"]) - Vector2(p["pos"])
			battle._damage.channel(p, KATANA_CHARGE + KATANA_TORNADO_RECOVER)
			_fx("katana_charge", [p, KATANA_CHARGE])
		else:
			k["wave_t"] = KATANA_WAVE_WINDUP
			k["aim"] = Vector2(tgt["pos"]) - Vector2(p["pos"])
			battle._damage.channel(p, KATANA_WAVE_WINDUP + KATANA_WAVE_RECOVER)
			_fx("katana_rise", [p, KATANA_WAVE_WINDUP])


func _katana_tornadoes(k: Dictionary) -> void:
	var p: Dictionary = k["u"]
	var aim: Vector2 = k.get("aim", Vector2.RIGHT)
	if DetMath.vlen(aim) < 0.1:
		aim = Vector2.RIGHT if str(battle._eff_side(p)) == "left" else Vector2.LEFT
	var shared: Array = []
	for i in range(KATANA_TORNADOES):
		var ang := (float(i) - float(KATANA_TORNADOES - 1) * 0.5) * KATANA_TORNADO_SPREAD
		stat["katana_tornado"] += 1
		_launch_line(p, Vector2(p["pos"]), DetMath.rotated(aim, ang), KATANA_TORNADO_SPD, KATANA_TORNADO_LEN, KATANA_TORNADO_W, "katana_tornado", int(k["si"]), shared)
