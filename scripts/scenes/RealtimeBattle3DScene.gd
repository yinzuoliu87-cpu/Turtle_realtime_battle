extends Node3D
## RealtimeBattle3DScene — 2.5D 战斗核心 (Phase 2, 见 docs/design/2.5D战斗架构方案.md §四.2-4)
## 真阵容在 2.5D 里能打: 读 GameState 配队 / demo 兜底 → Sprite3D billboard + blob影 + HP/龟能 overlay.
## 移动·索敌·普攻·分离·龟能·灭队判定 全复用 2D 版 RealtimeBattleScene 的逻辑口径(数值/公式/STATS),
## 只把 pos: Vector2 当 XZ 平面坐标, 另存 height/vy 给击飞真物理(Y 重力抛物). billboard 永远朝镜头.
## ⚠ Phase 2 只搭 移动+普攻+击飞+龟能 核心循环; 28主动技/59装备/层数DoT 留 Phase 3(_cast_active 是 TODO 钩子).
## ⚠ 占位美术: 立绘从 avatars/ 按 id, 地面/影/血条占位; 数值是 2D 版草案值, 全待 F5 调手感.

# ============================================================================
#  逻辑常量 (1:1 复用 RealtimeBattleScene 口径)
# ============================================================================
const ARENA := Rect2(70, 110, 1140, 520)   # 战场边界 (像素口径, 与 2D 版一致 → 同比例映射到 3D 地面)
const MAX_ENERGY := 100.0
const REGEN_PER_SEC := 14.0                # 龟能每秒回 (≈7s 满)
const SEP_RADIUS := 48.0                   # 单位软分离半径 (像素口径)
const HP_MULT := 3.0                       # HP 倍率 (节奏旋钮, 同 2D)
const SHIELD_CAP_MULT := 1.5

# 28 龟战斗属性 (1:1 复用): id → [melee, move_spd(px/s), atk_interval(s), atk_range(px)]
const STATS := {
	"basic": [true, 105.0, 0.85, 70.0], "stone": [true, 70.0, 1.1, 70.0], "bamboo": [true, 105.0, 0.85, 70.0],
	"angel": [false, 105.0, 0.85, 230.0], "ice": [false, 105.0, 0.85, 230.0], "ninja": [true, 145.0, 0.6, 70.0],
	"two_head": [true, 145.0, 0.85, 70.0], "ghost": [false, 145.0, 0.6, 340.0], "diamond": [true, 70.0, 1.1, 70.0],
	"fortune": [true, 105.0, 0.85, 70.0], "dice": [false, 145.0, 0.6, 230.0], "rainbow": [true, 105.0, 0.85, 70.0],
	"gambler": [false, 145.0, 0.85, 230.0], "hunter": [false, 145.0, 0.6, 340.0], "pirate": [false, 105.0, 0.85, 230.0],
	"candy": [false, 105.0, 0.85, 230.0], "bubble": [false, 70.0, 1.1, 230.0], "line": [false, 145.0, 0.6, 340.0],
	"lightning": [false, 145.0, 0.6, 340.0], "phoenix": [false, 105.0, 0.85, 230.0], "lava": [true, 145.0, 0.85, 70.0],
	"cyber": [false, 105.0, 0.85, 230.0], "crystal": [true, 70.0, 1.1, 70.0], "chest": [true, 105.0, 1.1, 70.0],
	"space": [false, 145.0, 0.85, 340.0], "hiding": [true, 70.0, 1.1, 70.0], "headless": [true, 145.0, 0.85, 70.0],
	"shell": [true, 105.0, 1.1, 70.0],
}
const DEFAULT_STAT := [true, 105.0, 0.85, 70.0]
const LEFT_DEMO := ["stone", "basic", "lightning"]
const RIGHT_DEMO := ["diamond", "ninja", "ghost"]

# 普攻表 (1:1 复用): id → [scale, hits]
const BASIC_ATK := {
	"basic": [0.7, 2], "stone": [0.7, 2], "bamboo": [0.21, 3], "angel": [1.4, 3],
	"ice": [0.5, 6], "ninja": [1.0, 1], "two_head": [1.0, 1], "ghost": [0.65, 1],
	"diamond": [0.7, 1], "fortune": [0.5, 2], "dice": [0.9, 1], "rainbow": [0.7, 2],
	"gambler": [0.45, 3], "hunter": [0.55, 3], "pirate": [0.35, 4], "candy": [1.1, 1],
	"bubble": [0.5, 3], "line": [0.5, 3], "lightning": [1.15, 5], "phoenix": [0.9, 1],
	"lava": [1.0, 1], "cyber": [0.15, 5], "crystal": [0.5, 2], "chest": [1.5, 3],
	"space": [0.4, 3], "hiding": [1.0, 1], "headless": [0.65, 2], "shell": [0.6, 2],
}
const DEFAULT_BASIC := [1.0, 1]

# ============================================================================
#  2.5D 坐标 / 渲染常量
# ============================================================================
const AVATAR_DIR := "res://assets/sprites/avatars/"
const WS := 0.024                         # 像素 → 米 比例 (ARENA 1140×520 px → ≈27×12.5 米地面)
const PIXEL_SIZE := 0.012                 # 立绘 像素→米 (龟约 1.5~2 米高)
const GROUND_LIFT := 0.35                 # 立绘落地基线略抬 → 竖面下缘不插进地面
const SHADOW_BASE := Vector3(1.9, 1.0, 1.0)
const SHADOW_BASE_A := 0.6
const GRAVITY := -22.0                     # 击飞重力 (m/s^2)
const KNOCK_VY := 6.0                      # 击飞竖直初速 (m/s) — 真抛物抬起再砸地
const KNOCK_PUSH := 5.5                    # 击飞横向初速 (米/s, 远离施法者)

# 世界中心: ARENA 像素中心映射到原点 → 单位世界坐标 = (pos - center) * WS
var _arena_center := ARENA.position + ARENA.size * 0.5

# ============================================================================
#  运行时状态
# ============================================================================
var _units: Array = []
var _data_by_id: Dictionary = {}
var _over := false
var _t := 0.0
var _settled := false

var _cam: Camera3D
var _ui_layer: CanvasLayer                # 血条/龟能 overlay + 标题 + 结算 (贴在 3D 之上)
var _world: Node3D                        # 3D 内容挂载点 (SubViewport 内)
var _sub: SubViewport
var _projectiles: Array = []              # 飞行中的 3D 投射物 {node, from, to, tgt, dmg, magic, src, t, dur}

func _ready() -> void:
	_load_pets()
	_build_viewport()
	_build_camera()
	_build_environment()
	_build_ground()
	_build_ui_layer()
	_spawn_teams()
	# DEV 自截图 (SELFSHOT=<秒>): 等若干帧让战斗跑起来再从主视口存盘
	if OS.has_environment("SELFSHOT"):
		_self_screenshot()

func _load_pets() -> void:
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	if f == null:
		push_warning("RealtimeBattle3D: pets.json 打不开")
		return
	var arr = JSON.parse_string(f.get_as_text())
	if arr is Array:
		for p in arr:
			if p is Dictionary and p.has("id"):
				_data_by_id[str(p["id"])] = p

# ----------------------------------------------------------------------------
#  SubViewport 合成: 3D 渲进它 → SubViewportContainer 贴满屏; 2D UI 叠上面.
#  (GL Compatibility 下主窗口截图丢直接渲染的 3D → SubViewport 截图可靠; unproject 1:1 可用)
# ----------------------------------------------------------------------------
func _build_viewport() -> void:
	var vp_size := Vector2i(1280, 720)
	if get_viewport() != null:
		var s := get_viewport().get_visible_rect().size
		if s.x > 1 and s.y > 1:
			vp_size = Vector2i(s)
	var container := SubViewportContainer.new()
	container.name = "ViewportContainer"
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_layer := CanvasLayer.new()
	bg_layer.name = "WorldLayer"
	bg_layer.layer = 0
	add_child(bg_layer)
	bg_layer.add_child(container)
	_sub = SubViewport.new()
	_sub.name = "World3D"
	_sub.size = vp_size
	_sub.transparent_bg = false
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.handle_input_locally = false
	_sub.msaa_3d = Viewport.MSAA_2X
	container.add_child(_sub)
	_world = Node3D.new()
	_world.name = "World"
	_sub.add_child(_world)

func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 50.0
	# 场地上方偏后俯视下来 (3/4). 抬高+拉远以容纳 ~27×12.5 米全场.
	_cam.position = Vector3(0.0, 15.0, 17.0)
	_world.add_child(_cam)
	_cam.look_at(Vector3(0.0, 0.6, 0.0), Vector3.UP)

func _build_environment() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 1.05
	light.light_color = Color(1.0, 0.97, 0.9)
	_world.add_child(light)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.09, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.6, 0.7)
	env.ambient_light_energy = 0.8
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.12, 0.18)
	env.fog_density = 0.01
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var plane := PlaneMesh.new()
	# 地面比竞技场略大一圈 (ARENA 像素 × WS + 边距)
	plane.size = Vector2(ARENA.size.x * WS + 4.0, ARENA.size.y * WS + 4.0)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.22, 0.26)
	mat.roughness = 0.9
	mat.metallic = 0.0
	mi.material_override = mat
	_world.add_child(mi)

func _build_ui_layer() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UIOverlay"
	_ui_layer.layer = 10
	add_child(_ui_layer)
	var title := Label.new()
	title.text = "2.5D 实时战斗 · 3v3 (左队 vs 右队)   [R 重开 · ESC 返回菜单]"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#cfe6ff"))
	title.position = Vector2(24, 16)
	_ui_layer.add_child(title)

# ============================================================================
#  阵容 spawn — 读 GameState.season_leaders, 没有就 demo (1:1 复用 2D 解析)
# ============================================================================
func _spawn_teams() -> void:
	var left := _resolve_left()
	var right := _resolve_right()
	for i in range(left.size()):
		# XZ 落点: 左队靠左 (ARENA 内), 三龟纵向分布. 与 2D _spawn_teams 同口径像素坐标.
		var pos := Vector2(ARENA.position.x + 150, ARENA.position.y + 100 + i * 160)
		_units.append(_make_unit(str(left[i]), "left", pos))
	for i in range(right.size()):
		var pos := Vector2(ARENA.end.x - 150, ARENA.position.y + 100 + i * 160)
		_units.append(_make_unit(str(right[i]), "right", pos))

func _resolve_left() -> Array:
	var ldr := _season_leaders()
	return ldr if ldr.size() >= 1 else LEFT_DEMO.duplicate()

func _resolve_right() -> Array:
	# 有赛季阵容 → 随机 bot 3 龟; demo 时固定对位 (后续 Phase 3 接 ghost 快照)
	if _season_leaders().is_empty():
		return RIGHT_DEMO.duplicate()
	return _random_bot(3)

func _season_leaders() -> Array:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return []
	var ldr = gs.get("season_leaders")
	if not (ldr is Array):
		return []
	var out: Array = []
	for x in ldr:
		if STATS.has(str(x)):
			out.append(str(x))
		if out.size() >= 3:
			break
	return out

func _random_bot(n: int) -> Array:
	var pool: Array = STATS.keys()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Array = []
	for i in range(mini(n, pool.size())):
		var idx := rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out

# ----------------------------------------------------------------------------
#  像素 XZ 坐标 → 3D 世界坐标 (height=Y). center 居中 + WS 缩放.
# ----------------------------------------------------------------------------
func _world_pos(pos: Vector2, height: float) -> Vector3:
	return Vector3((pos.x - _arena_center.x) * WS, height, (pos.y - _arena_center.y) * WS)

func _make_unit(id: String, side: String, pos: Vector2) -> Dictionary:
	var d: Dictionary = _data_by_id.get(id, {})
	var st: Array = STATS.get(id, DEFAULT_STAT)
	var hp := float(d.get("hp", 450)) * HP_MULT

	# --- 立绘 billboard sprite ---
	var tex: Texture2D = _avatar_tex(id)
	var spr := Sprite3D.new()
	spr.name = "Unit_" + id
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = PIXEL_SIZE
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD       # 防透明排序闪烁
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if tex != null:
		spr.offset = Vector2(0.0, tex.get_height() * 0.5)  # 脚底贴地: 图整体上抬半高
	spr.position = _world_pos(pos, GROUND_LIFT)
	_world.add_child(spr)

	# --- blob 暗影 (跟 XZ 不跟 Y) ---
	var shadow := Sprite3D.new()
	shadow.name = "Shadow_" + id
	shadow.texture = _make_blob_texture()
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = 0.01
	shadow.shaded = false
	shadow.transparent = true
	shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	shadow.modulate = Color(1, 1, 1, SHADOW_BASE_A)
	shadow.scale = SHADOW_BASE
	shadow.position = _world_pos(pos, 0.02)
	_world.add_child(shadow)

	# --- 队伍底色环 (脚下, 区分敌我) ---
	var ring := Sprite3D.new()
	ring.texture = _make_ring_texture(Color("#3fa9ff") if side == "left" else Color("#ff5a5a"))
	ring.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ring.axis = Vector3.AXIS_Y
	ring.pixel_size = 0.011
	ring.shaded = false
	ring.transparent = true
	ring.modulate = Color(1, 1, 1, 0.7)
	ring.position = _world_pos(pos, 0.015)
	_world.add_child(ring)

	# --- HP / 龟能 overlay (CanvasLayer 上, 每帧 unproject 定位) ---
	var bar := _make_status_bar(side)
	_ui_layer.add_child(bar["root"])

	return {
		"id": id, "name": str(d.get("name", id)), "side": side,
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"crit": float(d.get("crit", 0.25)), "crit_dmg": 1.5, "pierce": 0.0,
		"melee": bool(st[0]), "move_spd": float(st[1]),
		"atk_interval": float(st[2]), "atk_range": float(st[3]),
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		"shield": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		"dmg_dealt": 0.0,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": ring,
		"bar_root": bar["root"], "hp_fill": bar["hp"], "shield_fill": bar["shield"], "en_fill": bar["en"],
		"spr_base_offy": spr.offset.y,
	}

func _avatar_tex(id: String) -> Texture2D:
	var path := AVATAR_DIR + id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("RealtimeBattle3D: 立绘缺失 %s (占位)" % path)
	return null

# blob 影贴图: radial 渐变 中心黑→边缘透明
func _make_blob_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.55))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128; gt.height = 128
	return gt

# 队伍环贴图: 队色 radial 软环 (占位; 商业版换贴图)
func _make_ring_texture(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.add_point(0.7, Color(col.r, col.g, col.b, 0.0))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.5))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 96; gt.height = 96
	return gt

# 状态条: HP(绿) + 护盾(金, 盖在HP上) + 龟能(蓝, 下一行). 返回各 fill 引用.
func _make_status_bar(side: String) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(60, 14)
	root.size = Vector2(60, 14)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color("#3a0d0d"); hp_bg.position = Vector2(0, 0); hp_bg.size = Vector2(60, 7)
	root.add_child(hp_bg)
	var hp_fill := ColorRect.new()
	hp_fill.color = Color("#39d353"); hp_fill.position = Vector2(0, 0); hp_fill.size = Vector2(60, 7)
	root.add_child(hp_fill)
	var shield_fill := ColorRect.new()
	shield_fill.color = Color("#ffd93d"); shield_fill.position = Vector2(0, 0); shield_fill.size = Vector2(0, 7)
	root.add_child(shield_fill)
	var en_bg := ColorRect.new()
	en_bg.color = Color(0, 0, 0, 0.5); en_bg.position = Vector2(0, 8); en_bg.size = Vector2(60, 4)
	root.add_child(en_bg)
	var en_fill := ColorRect.new()
	en_fill.color = Color("#48c9ff"); en_fill.position = Vector2(0, 8); en_fill.size = Vector2(0, 4)
	root.add_child(en_fill)
	return {"root": root, "hp": hp_fill, "shield": shield_fill, "en": en_fill}

# ============================================================================
#  主循环 (移动 / 索敌 / 普攻 / 龟能 / 击飞物理 — 复用 2D 口径)
# ============================================================================
func _process(delta: float) -> void:
	if not _over:
		_t += delta
		for u in _units.duplicate():
			if not u["alive"]:
				continue
			_tick_unit(u, delta)
		_step_projectiles(delta)
		_check_end()
	_update_world_transforms()
	_update_overlay()

func _tick_unit(u: Dictionary, delta: float) -> void:
	var stunned: bool = _t < u["stun_until"]

	# --- 击飞真物理: vy 受重力, height 积分; 横向同时滑 (XZ 像素坐标方向) ---
	if u["airborne"]:
		u["vy"] += GRAVITY * delta
		u["height"] += u["vy"] * delta
		# 横向滑行换算回像素 (vx/vz 是米/s → /WS = 像素/s)
		u["pos"].x += u["vx"] / WS * delta
		u["pos"].y += u["vz"] / WS * delta
		u["vx"] *= 0.9; u["vz"] *= 0.9
		u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
		u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
		if u["height"] <= 0.0:
			u["height"] = 0.0; u["vy"] = 0.0; u["vx"] = 0.0; u["vz"] = 0.0
			u["airborne"] = false
		return   # 击飞中不移动/不攻击 (覆盖正常行为)

	var tgt = _acquire_target(u)
	if tgt == null:
		# 无敌 → 龟能照回 (但没目标不放技)
		_regen_energy(u, delta, stunned, null)
		return
	var to_t: Vector2 = tgt["pos"] - u["pos"]
	var dist := to_t.length()
	var rng: float = u["atk_range"]

	if not stunned:
		var spd: float = u["move_spd"] * (0.6 if _t < u["slow_until"] else 1.0)
		# 移动: 近战追到射程 / 远程维持射程并风筝 (1:1 复用 2D 逻辑)
		var intent := Vector2.ZERO
		if dist > rng:
			intent = to_t.normalized()
		elif not u["melee"] and dist < rng * 0.7:
			intent = -to_t.normalized()
		intent += _separation(u) * (0.25 if dist <= rng else 1.0)
		if intent.length() > 0.01:
			u["vel"] = intent.normalized() * spd
			u["pos"] += u["vel"] * delta
			u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
			u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)
		# 普攻 (按攻速计时)
		if dist <= rng:
			u["atk_cd"] -= delta
			if u["atk_cd"] <= 0.0:
				_basic_attack(u, tgt)
				u["atk_cd"] = u["atk_interval"]

	_regen_energy(u, delta, stunned, tgt)

# 龟能回满 → 放主动 (Phase 2: 只回满, _cast_active 是 Phase 3 TODO 钩子)
func _regen_energy(u: Dictionary, delta: float, stunned: bool, tgt) -> void:
	if stunned:
		return
	u["energy"] += REGEN_PER_SEC * delta
	if u["energy"] >= MAX_ENERGY:
		u["energy"] = 0.0
		if tgt != null:
			_cast_active(u, tgt)

# --- 索敌: 最近敌 (Phase 2 无嘲讽/untargetable, Phase 3 接) ---
func _acquire_target(u: Dictionary):
	var best = null
	var best_d := INF
	for o in _units:
		if o["side"] == u["side"] or not o["alive"]:
			continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best

func _enemies_of(u: Dictionary) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] != u["side"] and o["alive"]:
			out.append(o)
	return out

func _separation(u: Dictionary) -> Vector2:
	var push := Vector2.ZERO
	for o in _units:
		if o == u or not o["alive"]:
			continue
		var d: Vector2 = u["pos"] - o["pos"]
		var l := d.length()
		if l > 0.01 and l < SEP_RADIUS:
			push += d.normalized() * (1.0 - l / SEP_RADIUS)
	return push * 0.9

# ============================================================================
#  普攻 (复用 2D BASIC_ATK 表 + 伤害公式; 远程发 3D 投射物)
# ============================================================================
func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	var spec: Array = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	var scale: float = spec[0]
	var hits: int = spec[1]
	for i in range(hits):
		if not tgt["alive"]:
			break
		var per := _atk_dmg(u, scale, tgt, false)
		if u["melee"]:
			_apply_damage(u, tgt, per, false)
			if i == 0:
				_flash(tgt); _melee_lunge(u, tgt)
		else:
			_fire_projectile(u, tgt, per, false)

# 伤害公式 (1:1 复用 2D _atk_dmg): base×scale ×暴击 ×(100/(100+resist-pierce))
func _atk_dmg(u: Dictionary, scale: float, tgt: Dictionary, magic: bool) -> int:
	var base: float = u["atk"] * scale
	if randf() < u["crit"]:
		base *= u["crit_dmg"]
	var resist: float = float(tgt["mr"]) if magic else float(tgt["def"])
	resist = maxf(0.0, resist - u["pierce"])
	return maxi(1, int(round(base * (100.0 / (100.0 + resist)))))

# 立绘前冲 (近战命中视觉) — billboard offset 微推再回 (朝镜头, 不用翻 facing)
func _melee_lunge(u: Dictionary, tgt: Dictionary) -> void:
	var spr: Sprite3D = u["sprite"]
	if not is_instance_valid(spr):
		return
	var base := spr.position
	var dir3 := _world_pos(tgt["pos"], 0.0) - _world_pos(u["pos"], 0.0)
	if dir3.length() < 0.01:
		return
	dir3 = dir3.normalized() * 0.25
	var tw := create_tween()
	tw.tween_property(spr, "position", base + dir3, 0.06)
	tw.tween_property(spr, "position", base, 0.1)

# ============================================================================
#  3D 投射物 (远程普攻): 小 billboard 球从攻击者飞向目标, 到达落伤
# ============================================================================
func _fire_projectile(src: Dictionary, tgt: Dictionary, dmg: int, magic: bool) -> void:
	var p := Sprite3D.new()
	p.texture = _make_bolt_texture(Color("#ffe08a") if not magic else Color("#bff0ff"))
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.pixel_size = 0.014
	p.shaded = false
	p.transparent = true
	var from := _world_pos(src["pos"], 1.0)   # 从胸口高度出
	p.position = from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": from, "tgt": tgt, "dmg": dmg, "magic": magic,
		"src": src, "t": 0.0, "dur": 0.16,
	})

func _step_projectiles(delta: float) -> void:
	var keep: Array = []
	for pr in _projectiles:
		var node: Sprite3D = pr["node"]
		if not is_instance_valid(node):
			continue
		pr["t"] += delta
		var tgt: Dictionary = pr["tgt"]
		var to := _world_pos(tgt["pos"], 1.0)
		var frac: float = clampf(pr["t"] / pr["dur"], 0.0, 1.0)
		node.position = pr["from"].lerp(to, frac)
		if frac >= 1.0:
			node.queue_free()
			if tgt["alive"]:
				_apply_damage(pr["src"], tgt, pr["dmg"], pr["magic"])
				_flash(tgt)
			continue
		keep.append(pr)
	_projectiles = keep

func _make_bolt_texture(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 1.0))
	grad.add_point(0.6, Color(col.r, col.g, col.b, 0.9))
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32; gt.height = 32
	return gt

# ============================================================================
#  伤害应用 (复用 2D 口径: 护盾吸收 → HP; 击杀; 飘字) + 击飞物理触发
# ============================================================================
func _apply_damage(src: Dictionary, u: Dictionary, dmg: int, magic: bool) -> void:
	var d := float(dmg)
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	if src != null:
		src["dmg_dealt"] += float(dmg)
	_float_text(u, str(dmg), Color("#ffe08a") if not magic else Color("#bff0ff"))
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

# 击飞 (真物理): 给 vy 初速 + 横向远离施法者 → tick 重力抛物
func _knockback(by: Dictionary, tgt: Dictionary, _dist: float) -> void:
	if tgt["airborne"]:
		return
	var dir: Vector2 = (tgt["pos"] - by["pos"])
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	tgt["airborne"] = true
	tgt["vy"] = KNOCK_VY
	tgt["vx"] = dir.x * KNOCK_PUSH
	tgt["vz"] = dir.y * KNOCK_PUSH

func _kill(u: Dictionary) -> void:
	u["alive"] = false
	# 立绘+影+环 淡出
	for key in ["sprite", "shadow", "ring"]:
		var n = u[key]
		if is_instance_valid(n):
			var tw := create_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.4)
			tw.tween_callback(n.hide)
	if is_instance_valid(u["bar_root"]):
		u["bar_root"].visible = false

func _flash(u: Dictionary) -> void:
	var spr: Sprite3D = u["sprite"]
	if not is_instance_valid(spr):
		return
	spr.modulate = Color(2, 2, 2)
	var tw := create_tween()
	tw.tween_property(spr, "modulate", Color.WHITE, 0.15)

# 飘字: 3D 头顶世界坐标 → 屏幕, 在 UI overlay 上飘 (占位; Phase 3 收口调度)
func _float_text(u: Dictionary, text: String, col: Color) -> void:
	if _cam == null:
		return
	var head := _world_pos(u["pos"], u["height"] + 2.2)
	if _cam.is_position_behind(head):
		return
	var screen: Vector2 = _cam.unproject_position(head)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	l.position = screen
	_ui_layer.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", screen.y - 28.0, 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(l.queue_free)

# ============================================================================
#  主动技 — Phase 3 TODO 钩子 (这里只击退一下做占位反馈, 不实装 28 技/装备)
# ============================================================================
func _cast_active(u: Dictionary, tgt: Dictionary) -> void:
	# 🚧 Phase 3: 28 主动技 / 59 装备 / 层数 DoT 在此接入 (复用 2D _cast_active 注册表).
	#    Phase 2 占位: 龟能满时一次额外重击 + 击飞, 让"攒满龟能放招"的循环可见.
	_float_text(u, "技!", Color("#ffd93d"))
	var dmg := _atk_dmg(u, 1.4, tgt, false)
	if u["melee"]:
		_apply_damage(u, tgt, dmg, false)
		_flash(tgt)
	else:
		_fire_projectile(u, tgt, dmg, false)
	_knockback(u, tgt, 60.0)

# ============================================================================
#  每帧: 3D 节点世界坐标更新 (XZ + 高度) + 影/环随高缩放淡
# ============================================================================
func _update_world_transforms() -> void:
	for u in _units:
		if not u["alive"]:
			continue
		var spr: Sprite3D = u["sprite"]
		var shadow: Sprite3D = u["shadow"]
		var ring: Sprite3D = u["ring"]
		if not is_instance_valid(spr):
			continue
		# 立绘: XZ + Y(高度 + 落地基线抬升). billboard 自动朝镜头, 不翻 facing.
		spr.position = _world_pos(u["pos"], u["height"] + GROUND_LIFT)
		# 影/环: 跟 XZ 不跟 Y (贴地), 随高度缩小变淡
		var s: float = 1.0 - clampf(u["height"] / 3.0, 0.0, 0.7)
		if is_instance_valid(shadow):
			shadow.position = _world_pos(u["pos"], 0.02)
			shadow.scale = SHADOW_BASE * s
			shadow.modulate.a = SHADOW_BASE_A * s
		if is_instance_valid(ring):
			ring.position = _world_pos(u["pos"], 0.015)

# 血条/龟能 overlay: 每帧 unproject 单位头顶 → 屏幕像素 (跟随)
func _update_overlay() -> void:
	if _cam == null:
		return
	for u in _units:
		var root: Control = u["bar_root"]
		if not is_instance_valid(root):
			continue
		if not u["alive"]:
			root.visible = false
			continue
		# 更新 fill 宽度
		u["hp_fill"].size.x = 60.0 * clampf(u["hp"] / u["maxHp"], 0.0, 1.0)
		u["shield_fill"].size.x = 60.0 * clampf(u["shield"] / u["maxHp"], 0.0, 1.0)
		u["en_fill"].size.x = 60.0 * clampf(u["energy"] / MAX_ENERGY, 0.0, 1.0)
		# 头顶世界坐标 → 屏幕
		var head := _world_pos(u["pos"], u["height"] + 2.4)
		if _cam.is_position_behind(head):
			root.visible = false
			continue
		root.visible = true
		var screen: Vector2 = _cam.unproject_position(head)
		root.position = screen - Vector2(30, 8)   # 居中 (条宽 60)

# ============================================================================
#  灭队判定 + 结算横幅 (复用 2D _check_end; 赛季结算 Phase 3 接 GameState)
# ============================================================================
func _check_end() -> void:
	var left_alive := 0
	var right_alive := 0
	for u in _units:
		if u["alive"]:
			if u["side"] == "left": left_alive += 1
			else: right_alive += 1
	if left_alive == 0 or right_alive == 0:
		_over = true
		var won: bool = right_alive == 0
		_show_banner(won)

func _show_banner(won: bool) -> void:
	if _settled:
		return
	_settled = true
	var accent := Color("#ffd93d") if won else Color("#ff6b6b")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55); dim.size = Vector2(1280, 720)
	_ui_layer.add_child(dim)
	var big := Label.new()
	big.text = ("🏆 胜利!" if won else "💀 失败!")
	big.add_theme_font_size_override("font_size", 56)
	big.add_theme_color_override("font_color", accent)
	big.size = Vector2(1280, 80); big.position = Vector2(0, 300)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(big)
	var sub := Label.new()
	sub.text = "[R 再战 · ESC 返回菜单]   (Phase 3 接赛季结算/奖励)"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("#9fb6c9"))
	sub.size = Vector2(1280, 26); sub.position = Vector2(0, 392)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_layer.add_child(sub)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ============================================================================
#  DEV 自截图 (SELFSHOT=<秒>): 等战斗跑起来 + frame_post_draw 保证入帧缓冲
# ============================================================================
func _self_screenshot() -> void:
	var delay := 3.0
	var s := OS.get_environment("SELFSHOT")
	if s.is_valid_float() and s.to_float() > 0.1:
		delay = s.to_float()
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var out := "res://_p2_battle.png"
	if OS.has_environment("SHOT_OUT"):
		out = OS.get_environment("SHOT_OUT")
	img.save_png(out)
	get_tree().quit()
