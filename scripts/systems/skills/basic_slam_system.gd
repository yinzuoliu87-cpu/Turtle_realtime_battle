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
## ── 特效素材: 全部过肩摔专用的逐帧像素图(tools/build_basic_slam_vfx.py 生成; 2026-10-24 重做) ──
## 用户 10-24「为什么搞公用？」「全部是不是动画？」⇒ 不再用公用 skill-ring / dust-impact / 程序粒子。
## 参考 LoL 瑟提 R 落地逐帧(docs/studies/20261024b-过肩摔落地逐帧.md)。
const FX_SHOCK := "res://assets/sprites/vfx/basic-slam-shock.png"     # 贴地冲击环 8 帧 128²; 末帧外沿半径 SHOCK_LAST_R 像素
const FX_CRATER := "res://assets/sprites/vfx/basic-slam-crater.png"   # 贴地陷坑 8 帧 64²: 0~3 裂开 / 4 完整 / 5~7 碎散
const FX_ERUPT := "res://assets/sprites/vfx/basic-slam-erupt.png"     # 立着的土刺爆冠 7 帧 160×72(两侧高、中间低)
const FX_DUST := "res://assets/sprites/vfx/basic-slam-dust.png"       # 立着的扬尘团 7 帧 56×40
const FX_ROCKS := "res://assets/sprites/vfx/basic-slam-rocks.png"     # 石块 4 种 12²(一种一格, 不是动画)
const FX_FLASH := "res://assets/sprites/vfx/basic-slam-flash.png"     # 砸中闪光 4 帧 56²
const SHOCK_CELL := 128.0
const SHOCK_LAST_R := 62.0
## 落地时间线(秒, 落地 = 0)。每段的帧时长都在下面 `_land_fx` 里写死成数组 —— 一眼看得出节奏。
const LAND_ROCK_N := 8
const LAND_DUST_N := 8
const LAND_DUST_R0 := 70.0        # 扬尘团从离落点多远起卷(码)
const LAND_DUST_R1 := 230.0       # 卷到多远(码)
const TGT_GETUP_SEC := 0.3        # 目标仰面摔在地上多久再翻过来(眩晕 0.5 秒之内)


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
	u["land_t"] = battle.JUICE_LAND_SEC          # 落地压扁回弹(击飞落地同一套, battle_vfx._juice_scale_for)
	tgt["_slam_voff"] = Vector3.ZERO
	if tgt.get("alive", false):
		tgt["pos"] = t_land
		tgt["land_t"] = battle.JUICE_LAND_SEC
		stun_target(tgt)
		if caught_air:
			battle._equip_sys.on_unit_landed(tgt)
	last_land = t_land
	_apply_damage(u, tgt, tmax, t_land)
	_land_fx(t_land, u_land)
	_getup_later(tgt, tspr)   # 仰面砸在地上 TGT_GETUP_SEC 秒, 再翻过来(不再一帧翻正)
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
	u["land_t"] = battle.JUICE_LAND_SEC
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
	## ★落地不顿帧(用户 10-24「顿啥啊」): 单段 ≥ 60 的通用重击顿帧(battle_vfx._impact)这一下也不触发。
	battle._hitstop_mute += 1
	if tgt.get("alive", false):
		battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, BasicConsts.SLAM_MAIN_ATK, tgt)
			+ battle._phys_after_armor(u, atk * BasicConsts.SLAM_MAIN_HP_PER_ATK * tmax, tgt), COL_DMG)
	for o in battle._targeting._enemies_of(u):
		if is_same(o, tgt) or not o.get("alive", false):
			continue
		if DetMath.dist(o["pos"], center) <= BasicConsts.SLAM_SPLASH_RADIUS:
			battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, BasicConsts.SLAM_SPLASH_ATK, o)
				+ battle._phys_after_armor(u, atk * BasicConsts.SLAM_SPLASH_HP_PER_ATK * tmax, o), COL_DMG)
	battle._hitstop_mute -= 1


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


## 一段逐帧动画: `durs` = 每帧停多久(秒, 长度 = 帧数)。走 sim 步(`_reg_tween`), 播完自删。
## `flat` = 躺平贴地(俯视素材); 否则正对镜头、底边贴在 `h` 高度(立着的素材, 不会一半插进地里)。
func _frames(path: String, at: Vector2, h: float, ps: float, flat: bool, durs: Array, nm: String = "") -> Sprite3D:
	if battle._world == null or not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.hframes = durs.size()
	sp.frame = 0
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.transparent = true
	sp.pixel_size = ps
	if flat:
		sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sp.axis = Vector3.AXIS_Y      # ★AXIS_Y 本身就是躺平, 不再转 -90°(memory fb-axis-y-plus-rotation-cancels)
	else:
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.offset = Vector2(0.0, float(tex.get_height()) * 0.5)   # 底边贴在锚点上
	sp.position = battle._world_pos(at, h)
	if nm != "":
		sp.name = nm
	battle._world.add_child(sp)
	var tw = battle._reg_tween()
	tw.bind_node(sp)
	for k in range(durs.size()):
		var kk: int = k
		tw.tween_callback(func() -> void: sp.frame = kk)
		tw.tween_interval(float(durs[k]))
	tw.tween_callback(sp.queue_free)
	return sp


## 冲刺 / 起跳脚下的小扬尘(专用尘团, 立着)。
func _dust_puff(at: Vector2, size_px: float) -> void:
	_frames(FX_DUST, at, 0.02, size_px * battle.WS / 56.0, false, [0.04, 0.05, 0.05, 0.06, 0.06, 0.06, 0.06])


## 冲击环(贴地): 外沿最后一帧 = `radius` 码。起跳用小的, 落地用伤害半径。
func _shock(at: Vector2, radius: float, durs: Array, nm: String = "") -> Sprite3D:
	return _frames(FX_SHOCK, at, 0.05, radius * battle.WS / SHOCK_LAST_R, true, durs, nm)


## 目标仰面砸在地上 TGT_GETUP_SEC 秒再翻过来(带一次压扁) —— 原来落地那一帧直接从倒立翻正。
func _getup_later(tgt: Dictionary, tspr) -> void:
	if not is_instance_valid(tspr):
		return
	var tw = battle._reg_tween()
	tw.bind_node(tspr)   # 立绘被释放(换路 / 死亡淡完)⇒ tween 自动 kill, 回调不再被调(tools/tween_capture_audit.py 修法①)
	tw.tween_interval(TGT_GETUP_SEC)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(tspr) or tgt.get("_slam", false):
			return   # 已经被别的演出抓走(它自己管倒立)
		tspr.flip_v = false
		if tgt.get("alive", false):
			tgt["land_t"] = battle.JUICE_LAND_SEC)


## 起跳脚下一圈小冲击环(贴地, 专用素材)。
func _skill_ring_small(at: Vector2) -> void:
	_shock(at, 90.0, [0.03, 0.03, 0.04, 0.04, 0.05, 0.05, 0.05, 0.05])


## 落地(瑟提 R 的层次, 落地 = 0 秒):
##   0      砸中闪光(立着 4 帧) · 陷坑逐帧裂开(贴地 0~3 帧 0.13 秒) · 冲击环逐帧扩散(贴地 8 帧 0.45 秒, 末帧外沿 = 350 码伤害半径)
##   0      土刺爆冠(立着 7 帧, 两侧高中间低, 摆在落点后面一点 ⇒ 摔在中间的目标露在前面) · 大震屏
##   0      石块 8 块(4 种)按抛物线飞出, 0.55 秒落地后淡掉
##   0.06   扬尘团 8 团(立着 7 帧)沿地面从 70 码卷到 230 码
##   0.6    陷坑完整停留到 1.1 秒, 再逐帧碎散(5~7 帧)
##   ★不顿帧(用户 10-24「顿啥啊」)。
func _land_fx(center: Vector2, u_land: Vector2) -> void:
	_frames(FX_FLASH, center, 0.5, 150.0 * battle.WS / 56.0, false, [0.03, 0.04, 0.04, 0.03], "BasicSlamFlash")
	_frames(FX_CRATER, center, 0.03, 230.0 * battle.WS / 64.0, true,
		[0.03, 0.03, 0.03, 0.04, 0.97, 0.12, 0.12, 0.12], "BasicSlamCrater")
	_shock(center, BasicConsts.SLAM_SPLASH_RADIUS, [0.04, 0.05, 0.05, 0.06, 0.06, 0.06, 0.06, 0.07], "BasicSlamShock")
	_frames(FX_ERUPT, center + Vector2(0.0, -14.0), 0.0, 300.0 * battle.WS / 160.0, false,
		[0.03, 0.04, 0.05, 0.06, 0.06, 0.06, 0.06], "BasicSlamErupt")
	_shock(u_land, 110.0, [0.03, 0.03, 0.04, 0.04, 0.05, 0.05, 0.05, 0.05])
	_rocks(center)
	var tw = battle._reg_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(func() -> void: _dust_ring(center))
	battle._shake(battle.JUICE_SHAKE_BIG)


## 石块: 8 块绕落点一圈抛出(方向固定错开, 不用随机数), 抛物线 0.55 秒落地, 再淡掉。
func _rocks(center: Vector2) -> void:
	if battle._world == null or not ResourceLoader.exists(FX_ROCKS):
		return
	var tex: Texture2D = load(FX_ROCKS)
	for i in range(LAND_ROCK_N):
		var ang: float = TAU * float(i) / float(LAND_ROCK_N) + 0.35 * float(i % 3)
		var dirv := Vector2(DetMath.dcos(ang), DetMath.dsin(ang))
		var dist: float = 110.0 + 25.0 * float((i * 5) % 4)
		var apex: float = 1.3 + 0.35 * float((i * 3) % 4)
		var dur: float = 0.5 + 0.05 * float(i % 3)
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.hframes = 4
		sp.frame = i % 4
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sp.shaded = false
		sp.transparent = true
		sp.pixel_size = (22.0 + 4.0 * float(i % 2)) * battle.WS / 12.0
		sp.flip_h = (i % 2) == 1
		sp.position = battle._world_pos(center, 0.3)
		battle._world.add_child(sp)
		var tw = battle._reg_tween()
		tw.bind_node(sp)
		tw.tween_method(func(t: float) -> void:
			var p2: Vector2 = center + dirv * (dist * t)
			sp.position = battle._world_pos(p2, 0.3 + apex * 4.0 * t * (1.0 - t)), 0.0, 1.0, dur)
		tw.tween_property(sp, "modulate:a", 0.0, 0.18)
		tw.tween_callback(sp.queue_free)


## 扬尘团: 8 团绕落点一圈, 沿地面从 LAND_DUST_R0 卷到 LAND_DUST_R1(立着的专用尘团, 7 帧)。
func _dust_ring(center: Vector2) -> void:
	for i in range(LAND_DUST_N):
		var ang: float = TAU * (float(i) + 0.5) / float(LAND_DUST_N)
		var dirv := Vector2(DetMath.dcos(ang), DetMath.dsin(ang))
		var sp: Sprite3D = _frames(FX_DUST, center + dirv * LAND_DUST_R0, 0.02, (95.0 + 15.0 * float(i % 2)) * battle.WS / 56.0, false,
			[0.05, 0.07, 0.08, 0.1, 0.1, 0.1, 0.1])
		if sp == null:
			continue
		sp.flip_h = (i % 2) == 1
		var tw = battle._reg_tween()
		tw.bind_node(sp)
		tw.tween_method(func(t: float) -> void:
			sp.position = battle._world_pos(center + dirv * (LAND_DUST_R0 + (LAND_DUST_R1 - LAND_DUST_R0) * (1.0 - (1.0 - t) * (1.0 - t))), 0.02),
			0.0, 1.0, 0.6)
