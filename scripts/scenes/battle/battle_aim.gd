class_name BattleAim
extends RefCounted
## 训龟大师战场瞄准子系统(R2·2026-07-26 从主 sim 文件抽出还债·见 tools/arch_budget.json _debt_note)。
##   ① 圆盘(移动端)/按住Q(PC) 瞄准输入 ② 按技能类型的战场指示器(方向带/箭头/射程圈/落点圈)。
##   共享状态仍挂 battle(_disc_aiming/_disc_aim_dir/_q_aiming/_aim_ind·被 battle_render/输入共用),
##   本模块只搬"逻辑函数"。RefCounted + 构造注入 battle(照 dmg_stats_panel/battle_render 模板)。
##   类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

## 移动端圆盘回调(battle_hud 里 Callable(battle._aim, "_on_spell_aim") 接): 拖动=瞄准 / 松手=施放。
func _on_spell_aim(phase: String, screen_off: Vector2) -> void:
	match phase:
		"update":
			var tr0 = battle._my_trainer()
			battle._disc_aiming = screen_off.length() > 0.01 and tr0 != null and battle._trainer_sys._trainer_ticks_active()
			battle._disc_aim_dir = _disc_off_to_field(tr0, screen_off) if tr0 != null else Vector2.ZERO   # 存战场偏移(与PC统一尺度)
		"cast":
			battle._disc_aiming = false
			if not battle._trainer_sys._trainer_ticks_active():
				return
			var tr = battle._my_trainer()
			if tr != null:
				battle._trainer_sys._cast_active(tr, _disc_off_to_field(tr, screen_off))
		_:
			battle._disc_aiming = false

## 圆盘拖动的屏幕偏移 → 战场偏移(target点 = 大师pos + 返回值)。拖满(≈R*1.4像素)=技能射程, 半拖=半射程。
## 方向技(钩锁/冰川)只用方向, 幅度无所谓; 点目标技(怒火药水)靠幅度定落点距离。
func _disc_off_to_field(trainer: Dictionary, screen_off: Vector2) -> Vector2:
	if screen_off.length() < 0.01:
		return Vector2.RIGHT
	var sid: String = str(trainer.get("_tr_active", "hook"))
	var rng: float = float(battle.TRAINER_SKILLS.get(sid, {}).get("range", 600.0))
	if rng <= 0.0:
		rng = 600.0
	var frac: float = clampf(screen_off.length() / (SpellDisc.R * 1.4), 0.0, 1.0)
	return screen_off.normalized() * rng * frac

## R2 战场瞄准指示器(按技能类型·持久节点·每帧更新·瞄准结束 _clear_aim_indicator 清):
##   方向技(钩锁/冰川)= 地面方向带(冰川带宽90·钩锁细+高亮会勾到的敌); 点目标技(怒火)= 射程圈 + 落点预览圈。
func _draw_aim_indicator() -> void:
	if battle._world == null:
		return
	var tr = battle._my_trainer()
	if tr == null:
		_clear_aim_indicator(); return
	var u: Dictionary = tr                                  # 显式类型(否则 u["pos"] 下标报"对null下标")
	var sid: String = str(u.get("_tr_active", ""))
	if sid == "" or not battle.TRAINER_SKILLS.has(sid):
		_clear_aim_indicator(); return
	if str(battle._aim_ind.get("sid", "")) != sid:          # 换技能 → 重建
		_clear_aim_indicator(); battle._aim_ind["sid"] = sid
	var info: Dictionary = battle.TRAINER_SKILLS[sid]
	var aim_type: String = str(info.get("aim", "dir"))
	var rng: float = float(info.get("range", 600.0))
	if rng <= 0.0:
		rng = 600.0
	var from2d: Vector2 = u["pos"]
	var dir: Vector2 = battle._disc_aim_dir.normalized() if battle._disc_aim_dir.length() > 0.01 else Vector2.RIGHT
	if aim_type == "point":                                 # 怒火: 射程圈 + 落点圈(战场偏移·夹到射程)
		var pt: Vector2 = from2d + battle._disc_aim_dir.limit_length(rng)
		_aim_ring("ring", from2d, rng, Color(1.0, 0.7, 0.35, 0.45))
		_aim_ring("land", pt, 300.0, Color(1.0, 0.55, 0.25, 0.85))
	else:                                                   # 钩锁/冰川: 方向带 + 末端箭头
		var w: float = 90.0 if sid == "glacier" else 34.0
		var col: Color = Color(0.55, 0.85, 1.0, 0.30) if sid == "glacier" else Color(0.5, 0.9, 1.0, 0.32)
		_aim_band("band", from2d, dir, rng, w, col)
		_aim_arrow("arrow", from2d + dir * rng, dir, maxf(30.0, w * 0.7), Color(col.r, col.g, col.b, 0.92))
		if sid == "hook":                                   # 高亮会勾到的第一个敌
			var t = battle._trainer_sys._hook_first_target(u, dir)
			if t != null:
				_aim_ring("tgt", t["pos"], 52.0, Color(1.0, 0.42, 0.42, 0.95))
			else:
				_aim_free("tgt")

## 更新/建一个指示环(持久·不淡出·躺平贴地·恒在最上层)。
func _aim_ring(key: String, center2d: Vector2, radius_px: float, col: Color) -> void:
	var s = battle._aim_ind.get(key)
	if s == null or not is_instance_valid(s):
		s = Sprite3D.new()
		s.texture = VfxTex._make_ring_texture(col)
		s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		s.axis = Vector3.AXIS_Y
		s.shaded = false; s.transparent = true; s.no_depth_test = true
		battle._world.add_child(s); battle._aim_ind[key] = s
	s.modulate = col
	s.pixel_size = (radius_px * 2.0 * battle.WS) / 96.0
	s.position = battle._world_pos(center2d, 0.06)

## 更新/建一个方向带(PlaneMesh·躺平·半透明·恒在最上层)。X=沿方向长, Z=垂直宽。
func _aim_band(key: String, from2d: Vector2, dir: Vector2, length: float, width: float, col: Color) -> void:
	var m = battle._aim_ind.get(key)
	if m == null or not is_instance_valid(m):
		m = MeshInstance3D.new()
		var pm := PlaneMesh.new(); pm.size = Vector2(1.0, 1.0)   # 单位面·靠 scale 定尺寸
		m.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		m.material_override = mat
		battle._world.add_child(m); battle._aim_ind[key] = m
	(m.material_override as StandardMaterial3D).albedo_color = col
	var mid: Vector2 = from2d + dir * (length * 0.5)
	m.position = battle._world_pos(mid, 0.05)
	m.scale = Vector3(length * battle.WS, 1.0, width * battle.WS)
	m.rotation = Vector3(0.0, -atan2(dir.y, dir.x), 0.0)

## 更新/建方向型末端箭头(ArrayMesh 三角·躺平·尖头朝 dir·恒在最上层)。tip2d=箭尖落点。
func _aim_arrow(key: String, tip2d: Vector2, dir: Vector2, size: float, col: Color) -> void:
	var m = battle._aim_ind.get(key)
	if m == null or not is_instance_valid(m):
		m = MeshInstance3D.new()
		var am := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		# 单位三角: 尖头在原点(+X 前), 底边在 -X。scale/rotation 定尺寸朝向。
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(0.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.6), Vector3(-1.0, 0.0, -0.6)])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.mesh = am
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		m.material_override = mat
		battle._world.add_child(m); battle._aim_ind[key] = m
	(m.material_override as StandardMaterial3D).albedo_color = col
	m.position = battle._world_pos(tip2d, 0.05)
	m.scale = Vector3(size * battle.WS, 1.0, size * battle.WS)
	m.rotation = Vector3(0.0, -atan2(dir.y, dir.x), 0.0)

func _aim_free(key: String) -> void:
	var n = battle._aim_ind.get(key)
	if n != null and is_instance_valid(n): n.queue_free()
	battle._aim_ind.erase(key)

## 瞄准结束: 清掉所有指示器节点。
func _clear_aim_indicator() -> void:
	for k in battle._aim_ind.keys():
		if k == "sid": continue
		var n = battle._aim_ind[k]
		if n != null and is_instance_valid(n): n.queue_free()
	battle._aim_ind = {}

## R2 PC 按住 Q 瞄准: 按下进入(有主动技才进) / 每帧刷方向(鼠标→大师) / 松开朝鼠标释放。
func _begin_q_aim() -> void:
	if not battle._trainer_sys._trainer_ticks_active():
		return
	var tr = battle._my_trainer()
	if tr == null:
		return
	var u: Dictionary = tr
	var sid: String = str(u.get("_tr_active", ""))
	if sid == "" or not battle.TRAINER_SKILLS.has(sid):   # 选了被动(无主动Q)→ 不进瞄准
		return
	battle._q_aiming = true

func _end_q_aim_and_cast() -> void:
	if not battle._q_aiming:
		return
	battle._q_aiming = false
	battle._disc_aiming = false
	_clear_aim_indicator()
	battle._trainer_sys._player_cast_hook()               # 朝鼠标方向释放(_player_cast_hook 取鼠标向)

func _update_q_aim() -> void:                             # 每帧(battle_render)调: 按住Q时刷新瞄准方向 + 亮指示器
	if not battle._q_aiming:
		return
	var tr = battle._my_trainer()
	if tr == null:
		battle._q_aiming = false; battle._disc_aiming = false; return
	var u: Dictionary = tr
	var mp: Vector2 = battle.get_viewport().get_mouse_position() if battle.get_viewport() != null else Vector2.ZERO
	battle._disc_aim_dir = battle._screen_to_field(mp) - u["pos"]
	battle._disc_aiming = true
