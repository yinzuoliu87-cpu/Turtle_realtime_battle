class_name BasicSlamSystem
extends RefCounted
## 小龟·过肩摔(2026-10-24 重做) —— 方案书 docs/plans/20261024-过肩摔重做.md。
## 用户 2026-10-24「当敌人进入范围，释放过肩刷，应该是小龟加速冲向目标，抱起目标，开一个跳高最后落地，
##   跳高的时候还应该稍微往小龟背后动一点吧，整个特效需要重做，上面的bug也必须修完」; 范围「400吧」。
##
## 流程(全在一条协程里, 每个 sim 步推进一次, 顿帧 / 时停期间停住):
##   ① 冲刺  小龟由慢到快冲向目标的实时位置(目标此时还能动); 追不上 ⇒ 作废
##   ② 抱起  目标锁定, 贴到小龟身前举起
##   ③ 跳高  两只一起起跳(真抛物线: 上升慢、下砸快), 目标从身前越过头顶甩到背后(过头顶后倒过来),
##           整体往小龟背后平移 SLAM_DRIFT_BACK
##   ④ 落地  目标砸在小龟背后: 眩晕 + 主目标伤害 + 以落点为圆心的溅射 + 贴地伤害圈(外径 = 伤害半径)
## 抱不起来的目标(龙蛋 / 免控 / 免击飞 / 已经在别的演出里)⇒ 照样冲过去, 小龟原地单跳砸下(圆心在目标脚下)。
## 正被击飞在半空的目标照样抱(用户要的是「抱起目标」; 龟派气波这类击飞 1.5 秒, 实战常见):
##   抓住那一刻收掉它的击飞物理、从当前高度接着举起; 落地时补发一次落地事件(090 这类靠落地结算的装备不漏)。
##
## 体检九条(方案书 §2.2)在这里的落点:
##   B1 「×最大生命」那段走 `_phys_after_armor`(过护甲 / 减伤 / 虚化) · B2 抱不起来的走原地砸 ·
##   B3 不碰 `no_move` · B4 小龟死了立刻中断、不结算 · B5 溅射圆心恒为落点 ·
##   B6 不抓已在别的演出里的目标、锁只解自己加的 · B7 演出连续无瞬移、顿帧 / 时停停住(血条影子见 battle_render)
##   B8 特效整套重做(见下面「特效」一节)

var battle

## 观测量(门禁读): 最近一次施放走到了哪一步 / 落点 / 结算圆心。
var last_phase := ""
var last_land := Vector2.ZERO
var last_center := Vector2.ZERO

const COL_DMG := Color("#ff9d5c")
const COL_DUST := Color(0.93, 0.84, 0.66)
const COL_RING := Color(1.0, 0.78, 0.48)
const DUST_TEX := "res://assets/sprites/vfx/dust-impact.png"
const CRACK_TEX := "res://assets/sprites/vfx/basic-slam-crack.png"


func _init(b) -> void:
	battle = b


## 分派入口(`_do_skill` 的 "basicSlam")。★名字按 `_sk_*` 约定: 图鉴眩晕来源门禁(verify_codex_status_sources)从派发表点名的 `_sk_*` 顺调用链找眩晕。
func _sk_basic_slam(u: Dictionary, tgt) -> void:
	if tgt == null or not (tgt as Dictionary).get("alive", false):
		tgt = battle._targeting._nearest_enemy(u)
	if tgt == null:
		return
	_run(u, tgt)   # 协程(fire-and-forget)


## 这一步要不要停住: 顿帧 / 时停(小龟或已被抱住的目标被定格)。
func _paused(u: Dictionary, held) -> bool:
	if float(battle._hitstop) > 0.0:
		return true
	if battle._timestop.holds(u):
		return true
	return held != null and battle._timestop.holds(held)


## 抱不抱得起来(抱不起来 ⇒ 原地砸)。
func can_lift(tgt: Dictionary) -> bool:
	if tgt.get("_eggImmune", false) or tgt.get("_isEgg", false):
		return false
	if tgt.get("_knock_immune", false) or battle._damage._is_cc_immune(tgt):
		return false
	return not tgt.get("_slam", false)


func _run(u: Dictionary, tgt: Dictionary) -> void:
	last_phase = "dash"
	u["_slam"] = true
	var owns_u := true
	# ── ① 冲刺 ────────────────────────────────────────────────
	var t := 0.0
	_dust_puff(u["pos"], 130.0)
	var n := 0
	while true:
		await battle._dl_sys.lane_step()
		if not is_instance_valid(battle):
			return
		if not u.get("alive", false) or not battle.is_inside_tree():
			_release(u, owns_u)
			last_phase = "caster_dead"
			return
		if _paused(u, null):
			continue
		if not tgt.get("alive", false):
			_release(u, owns_u)
			last_phase = "target_gone"
			return
		var dt: float = float(battle._frame_sim_dt)
		t += dt
		var to: Vector2 = tgt["pos"] - u["pos"]
		var d: float = DetMath.vlen(to)
		if d <= BasicConsts.SLAM_GRAB_DIST:
			break
		if t >= BasicConsts.SLAM_DASH_TIMEOUT:
			_release(u, owns_u)
			last_phase = "dash_timeout"
			return
		var k: float = clampf(t / BasicConsts.SLAM_DASH_ACCEL_SEC, 0.0, 1.0)
		var spd: float = BasicConsts.SLAM_DASH_V0 + (BasicConsts.SLAM_DASH_VMAX - BasicConsts.SLAM_DASH_V0) * k * k
		var step: float = minf(spd * dt, d - BasicConsts.SLAM_GRAB_DIST * 0.85)
		var dn: Vector2 = DetMath.norm(to)
		u["pos"] = ArenaShape.clamp_in(u["pos"] + dn * maxf(step, 0.0), battle.ARENA, 20)
		u["face_right"] = dn.x > 0.0
		n += 1
		if n % 2 == 0:
			_afterimage(u, Color(1.0, 0.86, 0.62, 0.55), 0.18)
		if n % 5 == 0:
			_dust_puff(u["pos"], 70.0)
	# ── 抱不起来 ⇒ 原地单跳砸下 ──────────────────────────────────
	if not can_lift(tgt):
		await _hop_slam(u, tgt, owns_u)
		return
	# ── ② 抱起 ────────────────────────────────────────────────
	last_phase = "grab"
	tgt["_slam"] = true
	var owns_t := true
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if DetMath.vlen(dir) < 1.0:
		dir = Vector2.RIGHT if bool(u.get("face_right", true)) else Vector2.LEFT
	dir = DetMath.norm(dir)
	var u0: Vector2 = u["pos"]
	var e0: Vector2 = tgt["pos"]
	var hold: Vector2 = u0 + dir * BasicConsts.SLAM_HOLD_FWD
	var tmax: float = float(tgt["maxHp"])
	var tspr = tgt.get("sprite", null)
	var h0 := 0.0
	var caught_air: bool = bool(tgt.get("airborne", false))
	if caught_air:
		h0 = maxf(0.0, float(tgt.get("height", 0.0)))
		tgt["airborne"] = false
		tgt["height"] = 0.0
		tgt["vy"] = 0.0
		tgt["vx"] = 0.0
		tgt["vz"] = 0.0
		tgt.erase("knock_g")
	battle._vfx._flash(tgt)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.6)
	var el := 0.0
	while el < BasicConsts.SLAM_GRAB_SEC:
		await battle._dl_sys.lane_step()
		if not is_instance_valid(battle):
			return
		if not u.get("alive", false) or not battle.is_inside_tree():
			_drop(tgt, tspr, owns_t)
			_release(u, owns_u)
			last_phase = "caster_dead"
			return
		if _paused(u, tgt):
			continue
		el += float(battle._frame_sim_dt)
		var p: float = clampf(el / BasicConsts.SLAM_GRAB_SEC, 0.0, 1.0)
		if tgt.get("alive", false):
			tgt["pos"] = DetMath.vlerp(e0, hold, p)
			tgt["_slam_voff"] = Vector3(0.0, h0 + (BasicConsts.SLAM_HOLD_H - h0) * p, 0.0)
	# ── ③ 跳高 ────────────────────────────────────────────────
	last_phase = "jump"
	var u_land: Vector2 = ArenaShape.clamp_in(u0 - dir * BasicConsts.SLAM_DRIFT_BACK, battle.ARENA, 20)
	var t_land: Vector2 = ArenaShape.clamp_in(u_land - dir * BasicConsts.SLAM_LAND_BACK, battle.ARENA, 20)
	var rise: float = BasicConsts.SLAM_RISE_SEC
	var fall: float = BasicConsts.SLAM_FALL_SEC
	var total: float = rise + fall
	_skill_ring_small(u0)
	_dust_puff(u0, 150.0)
	el = 0.0
	var flipped := false
	n = 0
	while el < total:
		await battle._dl_sys.lane_step()
		if not is_instance_valid(battle):
			return
		if not u.get("alive", false) or not battle.is_inside_tree():
			_drop(tgt, tspr, owns_t)
			_release(u, owns_u)
			last_phase = "caster_dead"
			return
		if _paused(u, tgt):
			continue
		el = minf(el + float(battle._frame_sim_dt), total)
		var h: float = jump_height(el)
		var s: float = el / total
		var sm: float = s * s * (3.0 - 2.0 * s)                         # 平移 / 甩动都走 smoothstep: 起落平滑、中段最快
		u["pos"] = DetMath.vlerp(u0, u_land, sm)
		u["_slam_voff"] = Vector3(0.0, h, 0.0)
		if tgt.get("alive", false):
			var th: float = PI * sm                                      # 0 = 身前, PI/2 = 头顶, PI = 背后
			var c: float = DetMath.dcos(th)
			## 水平: 身前 SLAM_HOLD_FWD → 背后 SLAM_LAND_BACK(相对小龟), 两端正好对上抱起点与落点
			var off: float = (BasicConsts.SLAM_HOLD_FWD + BasicConsts.SLAM_LAND_BACK) * 0.5 * c \
				+ (BasicConsts.SLAM_HOLD_FWD - BasicConsts.SLAM_LAND_BACK) * 0.5
			var base: Vector2 = u["pos"]
			if el >= total:
				base = u_land
			tgt["pos"] = base + dir * off
			var lift: float = BasicConsts.SLAM_HOLD_H * (1.0 - th / PI) + BasicConsts.SLAM_TGT_ARC_H * DetMath.dsin(th)
			tgt["_slam_voff"] = Vector3(0.0, h + lift, 0.0)
			if th > PI * 0.5 and not flipped:
				flipped = true
				if is_instance_valid(tspr):
					tspr.flip_v = true
			## 空中只留一道很淡的拖影(第一版每 3 步一个实心残影, 叠成一竖串小龟, 实拍看着乱)
			n += 1
			if n % 6 == 0 and th < PI * 0.95:
				_afterimage(tgt, Color(1.0, 0.92, 0.78, 0.2), 0.1)
	# ── ④ 落地 ────────────────────────────────────────────────
	last_phase = "land"
	u["pos"] = u_land
	u["_slam_voff"] = Vector3.ZERO
	if is_instance_valid(tspr):
		tspr.flip_v = false
	tgt["_slam_voff"] = Vector3.ZERO
	if tgt.get("alive", false):
		tgt["pos"] = t_land
		stun_target(tgt)
		if caught_air:
			battle._equip_sys.on_unit_landed(tgt)
	last_land = t_land
	_apply_damage(u, tgt, tmax, t_land)
	_land_fx(t_land, u_land)
	if owns_t:
		tgt["_slam"] = false
	_release(u, owns_u)


## 小龟这一刻离地多高(米): 上升段 = 抛物线减速升到顶, 下砸段 = 抛物线加速砸回(两段重力不同 ⇒ 上升慢、下砸快)。
static func jump_height(el: float) -> float:
	var rise: float = BasicConsts.SLAM_RISE_SEC
	var fall: float = BasicConsts.SLAM_FALL_SEC
	var hmax: float = BasicConsts.SLAM_APEX_H
	if el <= rise:
		var q: float = 1.0 - el / rise
		return hmax * (1.0 - q * q)
	var f: float = clampf((el - rise) / fall, 0.0, 1.0)
	return hmax * (1.0 - f * f)


## 抱不起来时: 小龟原地单跳砸下(圆心 = 目标脚下)。
func _hop_slam(u: Dictionary, tgt: Dictionary, owns_u: bool) -> void:
	last_phase = "hop"
	var tmax: float = float(tgt["maxHp"])
	var el := 0.0
	var tot: float = BasicConsts.SLAM_HOP_SEC
	_dust_puff(u["pos"], 120.0)
	while el < tot:
		await battle._dl_sys.lane_step()
		if not is_instance_valid(battle):
			return
		if not u.get("alive", false) or not battle.is_inside_tree():
			_release(u, owns_u)
			last_phase = "caster_dead"
			return
		if _paused(u, null):
			continue
		el = minf(el + float(battle._frame_sim_dt), tot)
		var s: float = el / tot
		u["_slam_voff"] = Vector3(0.0, BasicConsts.SLAM_HOP_H * 4.0 * s * (1.0 - s), 0.0)
	u["_slam_voff"] = Vector3.ZERO
	var c: Vector2 = tgt["pos"]
	if tgt.get("alive", false) and not (tgt.get("_eggImmune", false) or tgt.get("_isEgg", false)):
		stun_target(tgt)
	last_land = c
	_apply_damage(u, tgt, tmax, c)
	_land_fx(c, u["pos"])
	last_phase = "hop_land"
	_release(u, owns_u)


## 眩晕(唯一出处: 图鉴眩晕来源表 `status_sources.gd` 指到这里)。免控由 `_stun` 自己挡。
func stun_target(tgt: Dictionary) -> void:
	battle._damage._stun(tgt, BasicConsts.SLAM_STUN_SEC, "basic_slam")


## 伤害: 主目标 1.0A + 0.2%×ATK×目标最大生命; 落点 350 码内其他敌人 0.3A + 0.13%×ATK×主目标最大生命。
## ★「×最大生命」那段也走 `_phys_after_armor`(过护甲 / 增伤 / 减伤 / 虚化; 体检 B1, 与竹刺 10-16 同一个修法)。
## ★圆心 = 落点 `center`(体检 B5: 原来取主目标当下位置, 主目标半空死了就跑到尸体那里)。
func _apply_damage(u: Dictionary, tgt: Dictionary, tmax: float, center: Vector2) -> void:
	last_center = center
	var atk: float = float(u["atk"])
	if tgt.get("alive", false):
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, BasicConsts.SLAM_MAIN_ATK, tgt)
			+ battle._phys_after_armor(u, atk * BasicConsts.SLAM_MAIN_HP_PER_ATK * tmax, tgt), COL_DMG)
	for o in battle._targeting._enemies_of(u):
		if is_same(o, tgt) or not o.get("alive", false):
			continue
		if DetMath.dist(o["pos"], center) <= BasicConsts.SLAM_SPLASH_RADIUS:
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, BasicConsts.SLAM_SPLASH_ATK, o)
				+ battle._phys_after_armor(u, atk * BasicConsts.SLAM_SPLASH_HP_PER_ATK * tmax, o), COL_DMG)


## 小龟半空阵亡 / 中断: 目标放回地面(当前水平位置), 复位贴图与偏移, 只解自己加的锁, 不结算(体检 B4)。
func _drop(tgt: Dictionary, tspr, owns_t: bool) -> void:
	tgt["_slam_voff"] = Vector3.ZERO
	if is_instance_valid(tspr):
		tspr.flip_v = false
	tgt["pos"] = ArenaShape.clamp_in(tgt["pos"], battle.ARENA, 20)
	if owns_t:
		tgt["_slam"] = false


func _release(u: Dictionary, owns_u: bool) -> void:
	u["_slam_voff"] = Vector3.ZERO
	if owns_u:
		u["_slam"] = false


# ───────────────────────────── 特效 ─────────────────────────────

## 残影: 拷一份当前立绘(帧 / 朝向 / 倒立都照抄), 原地渐隐。
func _afterimage(who: Dictionary, col: Color, life: float) -> void:
	var spr = who.get("sprite", null)
	if battle._world == null or not is_instance_valid(spr):
		return
	var g := Sprite3D.new()
	g.texture = spr.texture
	g.hframes = spr.hframes
	g.vframes = spr.vframes
	g.frame = spr.frame
	g.flip_h = spr.flip_h
	g.flip_v = spr.flip_v
	g.pixel_size = spr.pixel_size
	g.scale = spr.scale
	g.billboard = spr.billboard
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.shaded = false
	g.transparent = true
	g.modulate = col
	g.position = spr.position
	battle._world.add_child(g)
	var tw = battle._reg_tween()
	tw.bind_node(g)
	tw.tween_property(g, "modulate:a", 0.0, life)
	tw.tween_callback(g.queue_free)


func _dust_puff(at: Vector2, size_px: float) -> void:
	battle._burst_vfx(DUST_TEX, at, size_px, 0.12)


## 起跳脚下一圈小尘环(贴地)。
func _skill_ring_small(at: Vector2) -> void:
	battle._skill_ring(at, COL_DUST, 90.0)


## 落地: 贴地伤害圈(外径 = 溅射半径) + 地面裂纹 + 中等尘爆 + 碎屑 + 大震屏 + 顿帧。
func _land_fx(center: Vector2, u_land: Vector2) -> void:
	battle._skill_ring(center, COL_RING, BasicConsts.SLAM_SPLASH_RADIUS)
	battle._skill_ring(u_land, COL_DUST, 120.0)
	if ResourceLoader.exists(CRACK_TEX):
		var cr: Sprite3D = battle._px_ground_sprite(load(CRACK_TEX), center, 190.0, Color(1, 1, 1, 0.95), 0.03)
		cr.name = "BasicSlamCrack"
		var tw = battle._reg_tween()
		tw.bind_node(cr)
		tw.tween_interval(0.7)
		tw.tween_property(cr, "modulate:a", 0.0, 0.5)
		tw.tween_callback(cr.queue_free)
	battle._burst_vfx(DUST_TEX, center, 230.0, 0.3)
	battle._vfx._impact_particles(center, 0.0)
	battle._shake(battle.JUICE_SHAKE_BIG)
	battle._add_hitstop(0.1)
