extends Node3D
## RealtimeBattle3DScene — 2.5D 战斗核心 (Phase 2, 见 docs/design/2.5D战斗架构方案.md §四.2-4)
## 真阵容在 2.5D 里能打: 读 GameState 配队 / demo 兜底 → Sprite3D billboard + blob影 + HP/龟能 overlay.
## 移动·索敌·普攻·分离·龟能·灭队判定 全复用 2D 版 RealtimeBattleScene 的逻辑口径(数值/公式/STATS),
## 只把 pos: Vector2 当 XZ 平面坐标, 另存 height/vy 给击飞真物理(Y 重力抛物). billboard 永远朝镜头.
## ✅ Phase 3: 效果引擎接入 — 28主动技 + 层数DoT(灼烧/中毒/流血) + 召唤体(3D billboard+blob影) + 变身(双头/熔岩/赛博/龟壳)
##    + 登场被动 + on-hit被动 + 周期被动 + 死亡钩子, 全部从 2D 版逐函数照搬(逻辑/数值不变), 只把
##    VFX 触点(_float_text/_skill_ring/_bolt_line/召唤node/投射物) 换成 3D 等价.
## ⚠ 本轮先不做 59 装备运行时 (留 Phase 3b); _eq_* 钩子在 2D 版有, 这里全部不调用(equips 恒空).
## ⚠ 占位美术: 立绘从 avatars/ 按 id, 地面/影/血条/技能圈占位; 数值是 2D 版草案值, 全待 F5 调手感.

# ============================================================================
#  逻辑常量 (1:1 复用 RealtimeBattleScene 口径)
# ============================================================================
const ARENA := Rect2(70, 110, 1140, 520)   # 战场边界 (像素口径, 与 2D 版一致 → 同比例映射到 3D 地面)
const MAX_ENERGY := 100.0
const REGEN_PER_SEC := 14.0                # 龟能每秒回 (≈7s 满)
const SEP_RADIUS := 48.0                   # 单位软分离半径 (像素口径)
const HP_MULT := 3.0                       # HP 倍率 (节奏旋钮, 同 2D)
const SHIELD_CAP_MULT := 1.5
const RAGE_MAX := 100.0                    # 怒气满 (熔岩变身)
const STACK_DOT_TICK := 1.0                # 各类层数 DoT 每秒结算一次
const BUFF_SEC := 5.0                      # buff/控制/DoT 通用秒数 (规格 "N秒", 待 F5 调)
const CTRL_SEC := 1.5                      # 眩晕/冻结/嘲讽 默认秒数

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
	_inject_equipment()       # 装备注入 (玩家队读 persistent_equipped; demo队塞测试装备) — 须在被动之前
	_apply_spawn_passives()   # 登场被动 (开战即生效: 忍术暴击/怨灵诅咒/冰寒减攻/召唤等)
	_eq_apply_all_stats()     # 开战: 全装备纯属性 / 永久 flag 加到携带者 (spawn 被动之后, 不被覆盖)

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
		"id": id, "name": str(d.get("name", id)), "rarity": str(d.get("rarity", "C")), "side": side,
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": float(d.get("atk", 40)), "def": float(d.get("def", 12)), "mr": float(d.get("mr", 12)),
		"base_atk": float(d.get("atk", 40)), "base_def": float(d.get("def", 12)), "base_mr": float(d.get("mr", 12)),
		"crit": float(d.get("crit", 0.25)), "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
		"melee": bool(st[0]), "move_spd": float(st[1]),
		"atk_interval": float(st[2]), "atk_range": float(st[3]),
		"atk_cd": 0.0, "energy": 0.0, "alive": true,
		# 永久护盾 / 控制 / 旧式灼烧(保留兼容) ----
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		# 层数式 DoT (灼烧/中毒/流血, 1:1 dot.gd 层数衰减模型) ----
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0,
		# 效果积木状态 ----
		"buffs": [], "dots": [],
		"taunt_until": 0.0, "taunt_by": null,
		"dodge_bonus": 0.0, "ls_bonus": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0,
		"summons": [],
		# 装备 (Phase 3b: 恒空, 不触发钩子) ----
		"equips": [], "eq_state": {}, "hp50_fired": false,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": ring, "shadow_base_scale": SHADOW_BASE,
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
	# DoT/buff到期/累积条/周期被动 (1:1 2D _tick_effects)
	_tick_effects(u, delta)
	if not u["alive"]:
		return
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
		# 移动: 近战追到射程 / 远程维持射程并风筝 (1:1 复用 2D 逻辑); no_move 召唤体(糖果炸弹/海盗船)定点
		if not u.get("no_move", false):
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
		# 普攻 (按攻速计时; no_basic 召唤体只靠周期特殊技/掉血)
		if dist <= rng and not u.get("no_basic", false):
			u["atk_cd"] -= delta
			if u["atk_cd"] <= 0.0:
				_basic_attack(u, tgt)
				u["atk_cd"] = u["atk_interval"]

	_regen_energy(u, delta, stunned, tgt)

# 龟能回满 → 放主动 (麻痹时不回, 体现控制价值; 召唤体/被动选项 永不放主动)
func _regen_energy(u: Dictionary, delta: float, stunned: bool, tgt) -> void:
	if stunned or _is_passive_pick(u):
		return
	u["energy"] += REGEN_PER_SEC * delta
	if u["energy"] >= MAX_ENERGY:
		u["energy"] = 0.0
		if tgt != null:
			_cast_active(u, tgt)

# --- 索敌: 被嘲讽则强制打嘲讽来源, 否则最近敌 (跳过 untargetable / 缩头护身随从) ---
func _acquire_target(u: Dictionary):
	if _t < u["taunt_until"] and u["taunt_by"] != null and u["taunt_by"]["alive"]:
		return u["taunt_by"]
	return _nearest_enemy(u)

func _nearest_enemy(u: Dictionary):
	var best = null
	var best_d := INF
	for o in _units:
		if o["side"] == u["side"] or not o["alive"]:
			continue
		if _t < o["untargetable_until"]:   # 黑洞 → 不可被选
			continue
		if o.get("hiding_protected", false):   # 缩头随从: 本体存活时不可被敌单体选中
			var ow = o.get("summon_owner", null)
			if ow != null and ow.get("alive", false):
				continue
		var dd: float = (o["pos"] - u["pos"]).length_squared()
		if dd < best_d:
			best_d = dd; best = o
	return best

# 每单位每帧: DoT 落血 / buff 到期清理 / 层数DoT结算 / 召唤体周期特殊技 / 周期被动 (1:1 2D _tick_effects)
func _tick_effects(u: Dictionary, delta: float) -> void:
	# 旧式灼烧 (兼容 burn_until/burn_dps)
	if _t < u["burn_until"] and u["burn_dps"] > 0.0:
		_raw_lose(u, u["burn_dps"] * delta)
		if not u["alive"]:
			return
	# flat DoT 列表 (诅咒等, raw=真伤穿护盾)
	var keep: Array = []
	for dot in u["dots"]:
		if _t < dot["until"]:
			_raw_lose(u, dot["dps"] * delta)
			if not u["alive"]:
				return
			keep.append(dot)
	u["dots"] = keep
	# 层数式 DoT (灼烧/中毒/流血): 每 STACK_DOT_TICK(1秒) 结算一次出伤+衰减
	u["_dottimer"] = u.get("_dottimer", 0.0) + delta
	while u["_dottimer"] >= STACK_DOT_TICK:
		u["_dottimer"] -= STACK_DOT_TICK
		_tick_dot_stacks(u)
		if not u["alive"]:
			return
	# buff 到期 → 重算属性
	var changed := false
	var kept_buffs: Array = []
	for b in u["buffs"]:
		if _t < b["until"]:
			kept_buffs.append(b)
		else:
			changed = true
	if changed:
		u["buffs"] = kept_buffs
		_recalc_stats(u)
	# 召唤体周期特殊技 + 自损
	if u.get("is_summon", false):
		_tick_summon_special(u, delta)
		if not u["alive"]:
			return
	# 周期被动 (龟自身计时器)
	_tick_periodic_passive(u, delta)
	# 装备周期 tick (每 2.5 秒, EQ_TICK) — A类回合节拍效果
	if not u.get("equips", []).is_empty():
		_eq_tick(u, delta)

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
#  普攻 (复用 2D BASIC_ATK 表 + 伤害公式; 远程发 3D 投射物) + 复杂普攻特判 + on-hit 被动
# ============================================================================
func _basic_attack(u: Dictionary, tgt: Dictionary) -> void:
	var spec: Array = BASIC_ATK.get(u["id"], DEFAULT_BASIC)
	var scale: float = spec[0]
	var hits: int = spec[1]
	# 复杂普攻特判 (基于当前金币/暴击/HP)
	match u["id"]:
		"fortune":  scale = 0.5 + 0.06 * u["gold"]                       # 币越多越疼
		"dice":     scale = 0.9 + u["crit"] * 0.55                       # 暴击率加成
		"space":    scale = 0.4 + 0.06 * (u["hp"] / 100.0)              # 随当前HP (近似)
		"lava":
			if u.get("volcano", false):                                  # 火山形态: 烈焰重击式平A (更重·单段)
				scale = 1.6; hits = 1
		"crystal":  pass
	var per := _atk_dmg(u, scale, tgt)
	for i in range(hits):
		if not tgt["alive"]:
			break
		if u["melee"]:
			_apply_damage_from(u, tgt, per, Color("#ffe08a"))
			if i == 0:
				_flash(tgt); _melee_lunge(u, tgt)
		else:
			_fire_bolt_from(u, tgt, per, Color("#ffe08a"))
	# 普攻 on-hit 被动钩子 (墨迹/电击/结晶叠层 + 猎杀斩杀 等)
	_on_basic_hit(u, tgt)

# 伤害公式 (1:1 复用 2D _atk_dmg): base×scale ×暴击 ×(100/(100+resist-pierce))
func _atk_dmg(u: Dictionary, scale: float, tgt: Dictionary, magic: bool = false) -> int:
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
#  3D 投射物 (远程普攻/技能): 小 billboard 球从攻击者飞向目标, 到达落伤.
#  2D 接口对齐: _fire_bolt_from(src, tgt, dmg, col, from). src 用于 lifesteal/统计/累积 (可 null).
#  col 用于飘字色 (不再区分 magic bool; 物/法分流由 _atk_dmg 时已算进 dmg).
# ============================================================================
func _fire_bolt(from: Vector2, tgt: Dictionary, dmg: int, col: Color) -> void:
	_fire_bolt_from(null, tgt, dmg, col, from)

func _fire_bolt_from(src, tgt: Dictionary, dmg: int, col: Color, from = null) -> void:
	var start2d: Vector2 = from if from != null else (src["pos"] if src != null else tgt["pos"])
	var p := Sprite3D.new()
	p.texture = _make_bolt_texture(col)
	p.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p.pixel_size = 0.014
	p.shaded = false
	p.transparent = true
	var world_from := _world_pos(start2d, 1.0)   # 从胸口高度出
	p.position = world_from
	_world.add_child(p)
	_projectiles.append({
		"node": p, "from": world_from, "tgt": tgt, "dmg": dmg, "col": col,
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
				if pr["src"] != null:
					_apply_damage_from(pr["src"], tgt, pr["dmg"], pr["col"])
				else:
					_apply_damage(tgt, pr["dmg"], pr["col"])
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
#  伤害应用 (1:1 复用 2D: 护盾吸收→HP; 闪避/吸血/统计/累积条/受伤被动; 击杀; 飘字)
# ============================================================================
# 无来源伤害 (DoT 层数结算等)
func _apply_damage(u: Dictionary, dmg: int, col: Color) -> void:
	var d := float(dmg)
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	_float_text(u["pos"] + Vector2(0, -40), str(dmg), col)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

# 来源已知的伤害: 闪避 / 吸血 / 伤害统计 / 累积条(怒气/星能/储能) / 受伤被动. extra_ls=技能额外吸血%; raw=真伤穿盾
func _apply_damage_from(src: Dictionary, u: Dictionary, dmg: int, col: Color, extra_ls: float = 0.0, raw: bool = false, from_equip: bool = false) -> void:
	# 闪避 (目标 dodge_bonus); 瞄准镜054: 攻击者伤害无视闪避 (必中)
	if u.get("dodge_bonus", 0.0) > 0.0 and not src.get("eq_cannot_be_dodged", false) and randf() < u["dodge_bonus"]:
		_float_text(u["pos"] + Vector2(0, -40), "闪避", Color("#cfe6ff"))
		_eq_on_dodge(u)          # on-dodge 钩子 (幽灵墨鱼046: 闪避→永久护盾)
		return
	# 靶向器055: 被标记目标受伤 +20%
	if _t < u.get("eq_marked_until", 0.0):
		dmg = int(dmg * 1.2)
	var d := float(dmg)
	if not raw and u["shield"] > 0.0:
		var ab := minf(u["shield"], d)
		u["shield"] -= ab; d -= ab
	u["hp"] = maxf(0.0, u["hp"] - d)
	_float_text(u["pos"] + Vector2(0, -40), str(dmg), col)
	# 来源累积 ----
	src["dmg_dealt"] += float(dmg)
	# 吸血 (lifesteal 基础 + buff + 技能 extra)
	var ls: float = src.get("lifesteal", 0.0) + src.get("ls_bonus", 0.0) + extra_ls
	if ls > 0.0 and src["alive"]:
		_heal(src, float(dmg) * ls)
	# 怒气 (熔岩造伤25% / 受伤20%)
	if src["id"] == "lava":
		src["rage"] = minf(RAGE_MAX, src["rage"] + float(dmg) * 0.25)
	if u["id"] == "lava":
		u["rage"] = minf(RAGE_MAX, u["rage"] + float(dmg) * 0.20)
	# 星能 (星际造伤62%)
	if src["id"] == "space":
		src["star_energy"] = minf(src["maxHp"] * 0.40, src["star_energy"] + float(dmg) * 0.62)
	# 储能 (龟壳受伤转储能, 上限50%最大HP)
	if u["id"] == "shell":
		u["store_energy"] = minf(u["maxHp"] * 0.50, u["store_energy"] + float(dmg))
	# 双头坚韧 (常驻被动): 每受一段攻击 +1护甲+1魔抗 (各上限20)
	if u["id"] == "two_head":
		var th: int = int(u.get("two_tough", 0))
		if th < 20:
			th += 1; u["two_tough"] = th
			u["base_def"] += 1.0; u["base_mr"] += 1.0; _recalc_stats(u)
	# 石头龟坚壁: 受伤反弹 (5%+1%DEF+0.5%MR)
	if u["id"] == "stone" and src["alive"] and src["side"] != u["side"]:
		var reflect: float = float(dmg) * 0.05 + u["def"] * 0.01 + u["mr"] * 0.005
		if reflect >= 1.0:
			_raw_lose(src, reflect)
	# 装备事件钩子 (on-hit 攻击方 / on-target 防守方 / HP阈值) — 装备自身造的段不再回钩
	if not from_equip:
		if src["alive"] and u["alive"]:
			_eq_on_hit(src, u, dmg)        # on-hit: 攻击者装备 (流血/灼烧/连锁/追击/穿透/标记 等)
		if u["alive"]:
			_eq_on_target(u, src, dmg)     # on-target: 防守者装备 (硬化层/冰封反制 等)
	if u["alive"]:
		_eq_check_hp_threshold(u)          # HP阈值: 首次<50% (深海项链/珍珠耳环)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u, src)

# DoT 落血 (穿护盾, 不弹字防刷屏; 血条体现)
func _raw_lose(u: Dictionary, amt: float) -> void:
	if u["shield"] > 0.0:
		var ab := minf(u["shield"], amt)
		u["shield"] -= ab; amt -= ab
	u["hp"] = maxf(0.0, u["hp"] - amt)
	if u["hp"] <= 0.0 and u["alive"]:
		_kill(u)

# 击飞 (真物理): 给 vy 初速 + 横向远离施法者 → tick 重力抛物 (3D 真抛物, 替代 2D 滑行+假抬升)
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
	# 飞镖056: 任意敌被己方击飞 → 标"靶子", 携带者周期 tick 射镖
	if tgt["side"] != by["side"] and _side_has_equip(by["side"], "p2eq_056"):
		tgt["eq_target_until"] = _t + 99999.0

# 拉近: 把 tgt 拉到 by 面前 to_dist 处 (XZ 平面改 pos)
func _pull(by: Dictionary, tgt: Dictionary, to_dist: float) -> void:
	var dir: Vector2 = (tgt["pos"] - by["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	tgt["pos"] = by["pos"] + dir * to_dist
	tgt["pos"].x = clampf(tgt["pos"].x, ARENA.position.x, ARENA.end.x)
	tgt["pos"].y = clampf(tgt["pos"].y, ARENA.position.y, ARENA.end.y)

# 突进: 把 u 瞬移到 tgt 旁 gap 处 (近战切入; XZ 平面改 pos)
func _dash_to(u: Dictionary, tgt: Dictionary, gap: float) -> void:
	var dir: Vector2 = (u["pos"] - tgt["pos"]).normalized()
	if dir.length() < 0.1: dir = Vector2.RIGHT
	u["pos"] = tgt["pos"] + dir * gap
	u["pos"].x = clampf(u["pos"].x, ARENA.position.x, ARENA.end.x)
	u["pos"].y = clampf(u["pos"].y, ARENA.position.y, ARENA.end.y)

func _kill(u: Dictionary, killer = null) -> void:
	# 首死复活钩子 (天使圣光 / 凤凰涅槃) — 仅作为常驻一次, 1:1 2D
	if not u["reborn_used"] and (u["id"] == "angel" or u["id"] == "phoenix"):
		u["reborn_used"] = true
		var pct: float = 0.30 if u["id"] == "phoenix" else 0.25
		u["hp"] = u["maxHp"] * pct
		u["dots"] = []
		u["dot_stacks"] = {}
		_float_text(u["pos"] + Vector2(0, -64), "复活!", Color("#ffd93d"))
		if u["id"] == "phoenix":                          # 涅槃: 对全体敌灼烧
			for o in _enemies_of(u):
				_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
		return
	u["alive"] = false
	if killer != null and killer.get("alive", false):
		_eq_on_kill(killer, u)             # on-kill: 击杀者装备 (暴君之牙处决回血 等)
	_eq_on_death(u, killer)                # on-death: 阵亡者装备 (复活海螺变虫 / 齿轮折币 / 玩偶熊)
	_on_unit_death(u, killer)
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

# 飘字 (2D 接口对齐): 传像素 XZ 坐标 → 升到头顶世界点 → unproject 到屏幕 → UI overlay 上飘.
#   2D 版传 pos2d=u["pos"]+偏移(px); 这里把 y 偏移(px·往上)换算成 3D 高度抬升, 让"-64"这种头顶字落在头顶.
func _float_text(pos2d: Vector2, text: String, col: Color) -> void:
	if _cam == null:
		return
	# 2D 版 pos2d 含头顶像素偏移; 3D 里统一抬到 ~2.2 米头顶 (billboard 头顶居中, x 偏移忽略)
	var head := _world_pos(pos2d, 2.2)
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

# 技能光圈: 地面上一个躺平的环, 扩散淡出 (2D 接口对齐 _skill_ring(pos, col, radius))
func _skill_ring(pos2d: Vector2, col: Color, radius: float) -> void:
	var r := Sprite3D.new()
	r.texture = _make_ring_texture(col)
	r.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	r.axis = Vector3.AXIS_Y          # 躺平贴地
	r.shaded = false
	r.transparent = true
	r.modulate = Color(col.r, col.g, col.b, 1.0)
	r.position = _world_pos(pos2d, 0.05)
	# pixel_size 让环直径 ≈ radius(px) × WS(米/px); ring 贴图 96px 宽
	var target_ps: float = (radius * 2.0 * WS) / 96.0
	r.pixel_size = target_ps * 0.4
	_world.add_child(r)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "pixel_size", target_ps, 0.35)
	tw.tween_property(r, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(r.queue_free)

# 射线: 两点间一条 3D 直线 (水晶球/机甲激光), 快速淡出 (tween 整体 modulate alpha)
func _bolt_line(a2d: Vector2, b2d: Vector2, col: Color) -> void:
	var im := MeshInstance3D.new()
	var imesh := ImmediateMesh.new()
	im.mesh = imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	imesh.surface_set_color(col)
	imesh.surface_add_vertex(_world_pos(a2d, 1.0))
	imesh.surface_set_color(col)
	imesh.surface_add_vertex(_world_pos(b2d, 1.0))
	imesh.surface_end()
	_world.add_child(im)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(im.queue_free)

# ============================================================================
#  主动技注册表 (28 龟 · 各取规格里的「候选1」) — 逐函数 1:1 搬自 2D 版.
#  完整实装 = ✅ / 简化 = ⚠, 见每条注释. (装备 on-cast 钩子 Phase 3b, 这里不调)
# ============================================================================
func _cast_active(u: Dictionary, tgt: Dictionary) -> void:
	match u["id"]:
		"basic":     _sk_basic_shield(u, tgt)
		"stone":     _sk_stone_armor(u)
		"bamboo":    _sk_bamboo_heal(u)
		"angel":     _sk_angel_bless(u)
		"ice":       _sk_ice_frost(u)
		"ninja":     _sk_ninja_impact(u, tgt)
		"ghost":     _sk_ghost_soulstorm(u, tgt)
		"diamond":   _sk_diamond_unbreak(u)
		"dice":      _sk_dice_allin(u)
		"rainbow":   _sk_rainbow_shield(u)
		"gambler":   _sk_gambler_wild(u, tgt)
		"hunter":    _sk_hunter_hide(u)
		"pirate":    _sk_pirate_volley(u)
		"bubble":    _sk_bubble_shield(u, tgt)
		"line":      _sk_line_link(u)
		"lightning": _sk_lightning_surge(u, tgt)
		"phoenix":   _sk_phoenix_lavashield(u)
		"headless":  _sk_headless_fear(u, tgt)
		"fortune":   _sk_fortune_dice(u)
		"crystal":   _sk_crystal_bulwark(u)
		"chest":     _sk_chest_inventory(u)
		"space":     _sk_space_meteor(u)
		"two_head":  _sk_two_head(u, tgt)
		"lava":      _sk_lava_cast(u, tgt)
		"cyber":     _sk_cyber_cannon(u, tgt)
		"candy":     _sk_candy_armor(u)
		"hiding":    _sk_hiding_defend(u)
		"shell":     _sk_shell_absorb(u, tgt)
		_:           _sk_burst(u, tgt)
	_eq_on_cast(u, tgt)                              # on-cast: 放主动技后装备 (千刃风暴/火炮连射/水晶光束/灼热主动 等)

func _sk_basic_shield(u: Dictionary, tgt: Dictionary) -> void:   # 小龟·龟盾 ✅
	_float_text(u["pos"] + Vector2(0, -64), "龟盾!", Color("#ffd93d"))
	var lost: float = (tgt["maxHp"] - tgt["hp"]) * 0.20
	var raw: float = u["atk"] * 0.7
	var dmg := _atk_dmg(u, 0.7, tgt) + int(lost)
	_apply_damage_from(u, tgt, dmg, Color("#ffe08a"))
	_grant_shield(u, (raw + lost) * 0.80)
	_knockback(u, tgt, 60.0)

func _sk_stone_armor(u: Dictionary) -> void:                     # 石头龟·岩石护甲 ✅
	_float_text(u["pos"] + Vector2(0, -64), "岩石护甲!", Color("#c9a36b"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.24 + o["maxHp"] * 0.05)

func _sk_bamboo_heal(u: Dictionary) -> void:                     # 竹叶龟·自然恢复 ✅
	var allies := _allies_of(u, false)
	if allies.is_empty():
		_heal(u, u["maxHp"] * 0.15)
	else:
		_heal(u, u["maxHp"] * 0.10)
		for o in allies:
			_grant_shield(o, o["maxHp"] * 0.12)
	_float_text(u["pos"] + Vector2(0, -64), "自然恢复!", Color("#39d353"))

func _sk_angel_bless(u: Dictionary) -> void:                     # 天使龟·祝福 ✅
	var ally = _lowest_hp_ally(u)
	if ally == null:
		ally = u
	_grant_shield(ally, u["atk"] * 1.2)
	_buff(ally, "def", 0.2, true)
	_buff(ally, "mr", 0.2, true)
	_float_text(ally["pos"] + Vector2(0, -64), "祝福!", Color("#ffe9a8"))

func _sk_ice_frost(u: Dictionary) -> void:                       # 寒冰龟·冰霜 ✅
	_float_text(u["pos"] + Vector2(0, -64), "冰霜!", Color("#9be7ff"))
	for o in _enemies_of(u):
		_buff(o, "mr", -0.25, true)
		for i in range(10):
			_apply_damage_from(u, o, _atk_dmg(u, 0.1, o, true), Color("#bfe9ff"))
		_skill_ring(o["pos"], Color(0.6, 0.9, 1.0, 0.5), 50.0)

func _sk_ninja_impact(u: Dictionary, tgt: Dictionary) -> void:   # 忍者龟·冲击 ✅
	_float_text(u["pos"] + Vector2(0, -64), "冲击!", Color("#9be7ff"))
	var dir: Vector2 = (tgt["pos"] - u["pos"]).normalized()
	_dash_to(u, tgt, 60.0)
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ff9d5c"))
	_knockback(u, tgt, 50.0)
	for o in _enemies_of(u):
		if o == tgt:
			continue
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#ff9d5c"))

func _sk_ghost_soulstorm(u: Dictionary, tgt: Dictionary) -> void: # 幽灵龟·灵魂风暴 ✅
	_float_text(u["pos"] + Vector2(0, -64), "灵魂风暴!", Color("#c77dff"))
	var cursed: bool = _has_dot(tgt, "curse")
	if cursed:
		_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt, true), Color("#e0b0ff"))
	else:
		for i in range(2):
			_apply_damage_from(u, tgt, _atk_dmg(u, 1.25, tgt, true), Color("#c77dff"))
		_add_dot(tgt, "curse", tgt["maxHp"] * 0.05, BUFF_SEC)

func _sk_diamond_unbreak(u: Dictionary) -> void:                 # 钻石龟·坚不可摧 ✅
	_float_text(u["pos"] + Vector2(0, -64), "坚不可摧!", Color("#9bdcff"))
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true); _buff(u, "mr", 0.2, true)

func _sk_dice_allin(u: Dictionary) -> void:                      # 骰子龟·孤注一掷 ✅
	_float_text(u["pos"] + Vector2(0, -64), "孤注一掷!", Color("#ffd93d"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.2, o), Color("#ffe08a"), 0.30)

func _sk_rainbow_shield(u: Dictionary) -> void:                  # 彩虹龟·棱镜护盾 ✅
	_float_text(u["pos"] + Vector2(0, -64), "棱镜护盾!", Color("#ff8ad8"))
	for o in _allies_of(u):
		_grant_shield(o, u["atk"] * 0.65)

func _sk_gambler_wild(u: Dictionary, tgt: Dictionary) -> void:   # 赌神龟·万能牌 ✅
	_float_text(u["pos"] + Vector2(0, -64), "万能牌!", Color("#ffd93d"))
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#ffe08a"))
	_grant_shield(u, u["atk"] * 0.25)
	_heal(u, u["maxHp"] * 0.05)
	_buff(tgt, "atk", -0.15, true)

func _sk_hunter_hide(u: Dictionary) -> void:                     # 猎人龟·隐蔽 ✅
	_float_text(u["pos"] + Vector2(0, -64), "隐蔽!", Color("#a8ffb0"))
	var tgt = _nearest_enemy(u)
	if tgt != null:
		_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ffe08a"))
	_buff(u, "dodge", 0.25, true)
	_grant_shield(u, u["atk"] * 0.6)

func _sk_pirate_volley(u: Dictionary) -> void:                   # 海盗龟·火炮齐射 ✅
	_float_text(u["pos"] + Vector2(0, -64), "火炮齐射!", Color("#ffb05c"))
	for o in _enemies_of(u):
		for i in range(6):
			_apply_damage_from(u, o, _atk_dmg(u, 0.17, o) + int(o["maxHp"] * 0.017), Color("#ffd07a"))

func _sk_bubble_shield(u: Dictionary, _tgt: Dictionary) -> void: # 泡泡龟·泡泡盾 ✅(简化:无延迟爆裂)
	var ally = _lowest_hp_ally(u)
	if ally == null: ally = u
	_grant_shield(ally, u["atk"] * 1.8)
	_float_text(ally["pos"] + Vector2(0, -64), "泡泡盾!", Color("#aef1ff"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 2.0, o, true), Color("#cdebff"))

func _sk_line_link(u: Dictionary) -> void:                       # 线条龟·连笔 ✅
	_float_text(u["pos"] + Vector2(0, -64), "连笔!", Color("#cccccc"))
	var picked := 0
	for o in _enemies_of(u):
		if picked >= 2: break
		_apply_damage_from(u, o, _atk_dmg(u, 0.8, o), Color("#dddddd"))
		_add_stack(o, "ink", 1, 5)
		picked += 1

func _sk_lightning_surge(u: Dictionary, tgt: Dictionary) -> void: # 闪电龟·涌动 ✅
	_float_text(u["pos"] + Vector2(0, -64), "涌动!", Color("#7ee8ff"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.23, tgt, true), Color("#bff0ff"))
	_add_stack(tgt, "electric", 2, 6)
	_buff(u, "atk", 0.5, true)

func _sk_phoenix_lavashield(u: Dictionary) -> void:              # 凤凰龟·熔岩盾 ✅(反击留TODO)
	_float_text(u["pos"] + Vector2(0, -64), "熔岩盾!", Color("#ff7a33"))
	_grant_shield(u, u["atk"] * 0.75)

func _sk_headless_fear(u: Dictionary, tgt: Dictionary) -> void:  # 无头龟·恐吓 ✅
	_float_text(u["pos"] + Vector2(0, -64), "恐吓!", Color("#a0a0ff"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 0.9, tgt), Color("#ffe08a"))
	_buff(tgt, "atk", -0.20, true)

func _sk_fortune_dice(u: Dictionary) -> void:                    # 财神龟·骰子 ✅
	_float_text(u["pos"] + Vector2(0, -64), "骰子+金币!", Color("#ffd93d"))
	u["gold"] += randi_range(2, 6)
	_heal(u, u["maxHp"] * 0.08)

func _sk_crystal_bulwark(u: Dictionary) -> void:                 # 水晶龟·水晶壁垒 ✅
	_float_text(u["pos"] + Vector2(0, -64), "水晶壁垒!", Color("#c0a8ff"))
	_grant_shield(u, u["atk"] * 0.9)
	for o in _allies_of(u):
		_buff(o, "def", 0.15, true); _buff(o, "mr", 0.15, true)

func _sk_chest_inventory(u: Dictionary) -> void:                 # 宝箱龟·清点财宝 ✅
	_float_text(u["pos"] + Vector2(0, -64), "清点财宝!", Color("#ffcf5c"))
	_heal(u, u["maxHp"] * 0.05)
	var bonus: float = 1.0 + minf(u["dmg_dealt"] / 2000.0, 1.0)
	_grant_shield(u, u["atk"] * 0.6 * bonus)

func _sk_space_meteor(u: Dictionary) -> void:                    # 星际龟·流星暴击 ✅
	_float_text(u["pos"] + Vector2(0, -64), "流星暴击!", Color("#b08cff"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#c9b0ff"))
		_buff(o, "mr", -0.2, true)
	if u["star_energy"] >= u["maxHp"] * 0.40:
		var burst: float = u["star_energy"]
		u["star_energy"] = 0.0
		for o in _enemies_of(u):
			_raw_lose(o, burst)
			_float_text(o["pos"] + Vector2(0, -48), str(int(burst)), Color("#ffd0ff"))

func _sk_candy_armor(u: Dictionary) -> void:                     # 糖果龟·焦糖铠 ✅
	_float_text(u["pos"] + Vector2(0, -64), "焦糖铠!", Color("#ffb0d0"))
	_grant_shield(u, u["atk"] * 0.8)
	_heal(u, u["maxHp"] * 0.10)

# 双头龟·选一套 (demo 默认套1). 每次攒满龟能 → 切形态 + 放新形态这套招.
func _sk_two_head(u: Dictionary, tgt: Dictionary) -> void:       # 双头龟 ✅ 选一套+切换形态
	var set_id: String = u.get("two_set", "1")
	u["two_form"] = "ranged" if u.get("two_form", "melee") == "melee" else "melee"
	var to_ranged: bool = u["two_form"] == "ranged"
	u["melee"] = not to_ranged
	u["atk_range"] = 300.0 if to_ranged else 70.0
	u["atk_interval"] = 1.1 if not to_ranged else 0.8
	if not to_ranged:
		match set_id:
			"1", "3":
				_float_text(u["pos"] + Vector2(0, -64), "近战·锤击!", Color("#ffb05c"))
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt), Color("#ffb05c"))
				_grant_shield(u, u["atk"] * 0.5)
			"2":
				_float_text(u["pos"] + Vector2(0, -64), "近战·吸收!", Color("#ffb05c"))
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.3, tgt), Color("#ffb05c"), 0.35)
	else:
		match set_id:
			"1":
				_float_text(u["pos"] + Vector2(0, -64), "远程·精神干扰!", Color("#b0c0ff"))
				tgt["shield"] *= 0.5
				_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt, true), Color("#c0d0ff"))
				_buff(tgt, "atk", -0.20, true)
			"2":
				_float_text(u["pos"] + Vector2(0, -64), "远程·魔法波!", Color("#b0c0ff"))
				for i in range(4):
					if not tgt["alive"]: break
					_apply_damage_from(u, tgt, _atk_dmg(u, 0.6, tgt, i % 2 == 0), Color("#c0d0ff"))
			"3":
				_float_text(u["pos"] + Vector2(0, -64), "远程·灵能冲击!", Color("#b0c0ff"))
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true) + int(o["maxHp"] * 0.15), Color("#c0d0ff"))

# 熔岩龟·选一套 (demo 默认套A). 龟能满→放【当前形态】(小/火山)这套对应招. 攒怒变身在 _tick_periodic_passive.
func _sk_lava_cast(u: Dictionary, tgt: Dictionary) -> void:      # 熔岩龟·选一套各自触发 ✅
	var set_id: String = u.get("lava_set", "A")
	var volcano: bool = u.get("volcano", false)
	match set_id:
		"A":
			if volcano: _lava_volcano_erupt(u)
			else:       _lava_quake(u)
		"B":
			if volcano: _lava_flame_strike(u, tgt)
			else:       _lava_magma_surge(u, tgt)
		"C":
			if volcano: _lava_magma_stomp(u)
			else:       _lava_spray(u)
		_:
			_lava_quake(u)

func _lava_quake(u: Dictionary) -> void:                         # 小·地裂: 全体魔+削魔抗
	_float_text(u["pos"] + Vector2(0, -64), "地裂!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.7, o, true), Color("#ff9d5c"))
		_buff(o, "mr", -0.2, true)

func _lava_volcano_erupt(u: Dictionary) -> void:                 # 火山·火山爆发: 全体五段+灼烧+回血
	_float_text(u["pos"] + Vector2(0, -64), "火山爆发!", Color("#ff5a2a"))
	for o in _enemies_of(u):
		for i in range(5):
			if not o["alive"]: break
			_apply_damage_from(u, o, _atk_dmg(u, 0.5, o, true), Color("#ff7a33"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
	_heal(u, u["maxHp"] * 0.12)
	_skill_ring(u["pos"], Color(1.0, 0.4, 0.1, 0.5), 130.0)

func _lava_magma_surge(u: Dictionary, tgt: Dictionary) -> void:  # 小·岩浆涌动: 单体魔+永久护盾
	_float_text(u["pos"] + Vector2(0, -64), "岩浆涌动!", Color("#ff7a33"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 1.4, tgt, true), Color("#ff9d5c"))
	_grant_shield(u, u["atk"] * 0.8)

func _lava_flame_strike(u: Dictionary, tgt: Dictionary) -> void: # 火山·烈焰重击: 单体物+吸血
	_float_text(u["pos"] + Vector2(0, -64), "烈焰重击!", Color("#ff5a2a"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.2, tgt), Color("#ff7a33"), 0.30)

func _lava_spray(u: Dictionary) -> void:                         # 小·熔岩喷射: 全体+灼烧
	_float_text(u["pos"] + Vector2(0, -64), "熔岩喷射!", Color("#ff7a33"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.6, o, true), Color("#ff9d5c"))
		_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)

func _lava_magma_stomp(u: Dictionary) -> void:                   # 火山·岩浆践踏: 全体+40%眩晕+回血
	_float_text(u["pos"] + Vector2(0, -64), "岩浆践踏!", Color("#ff5a2a"))
	for o in _enemies_of(u):
		_apply_damage_from(u, o, _atk_dmg(u, 0.9, o, true), Color("#ff7a33"))
		if randf() < 0.40:
			_freeze(o, CTRL_SEC)
	_heal(u, u["maxHp"] * 0.10)

func _sk_cyber_cannon(u: Dictionary, tgt: Dictionary) -> void:   # 赛博龟·能量大炮 ⚠
	_float_text(u["pos"] + Vector2(0, -64), "能量大炮!", Color("#7ee8ff"))
	_dash_to(u, tgt, 80.0)
	for i in range(2):
		_apply_damage_from(u, tgt, _atk_dmg(u, 1.0, tgt), Color("#9bf0ff"))
	var drones: int = u["summons"].size()
	if drones > 0:
		_apply_damage_from(u, tgt, int(u["atk"] * 0.2 * drones), Color("#d0ffff"), 0.0, true)

func _sk_hiding_defend(u: Dictionary) -> void:                   # 缩头乌龟·防御 ⚠
	_float_text(u["pos"] + Vector2(0, -64), "防御!", Color("#9be7ff"))
	_grant_shield(u, u["maxHp"] * 0.20)
	_buff(u, "def", 0.2, true)

func _sk_shell_absorb(u: Dictionary, tgt: Dictionary) -> void:   # 龟壳·吸收 ⚠
	var steal: float = tgt["maxHp"] * 0.10
	_raw_lose(tgt, steal)
	_heal(u, steal)
	_float_text(u["pos"] + Vector2(0, -64), "吸收!", Color("#b0ffd0"))

func _sk_burst(u: Dictionary, tgt: Dictionary) -> void:          # 兜底重击
	_float_text(u["pos"] + Vector2(0, -64), "重击!", Color("#ff9d5c"))
	_apply_damage_from(u, tgt, _atk_dmg(u, 2.5, tgt), Color("#ff9d5c"))
	for o in _enemies_of(u):
		if o != tgt and (o["pos"] - tgt["pos"]).length() <= 110.0:
			_apply_damage_from(u, o, _atk_dmg(u, 1.25, o), Color("#ff9d5c"))
	_skill_ring(tgt["pos"], Color(1.0, 0.6, 0.3, 0.5), 110.0)

# ============================================================================
#  效果积木 (可复用) — 治疗/护盾/控制/buff/DoT/吸血/累积/净化/叠层 (1:1 搬自 2D 版).
#  注: 3D 版血条 overlay 每帧统一刷新, 故去掉 2D 版各处的 _update_bars(u) 调用.
# ============================================================================
func _grant_shield(u: Dictionary, amt: float) -> void:
	u["shield"] = minf(u["shield"] + amt, u["maxHp"] * SHIELD_CAP_MULT)
	_skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.4), 44.0)

func _heal(u: Dictionary, amt: float) -> void:
	if amt <= 0.0: return
	u["hp"] = minf(u["maxHp"], u["hp"] + amt)
	_float_text(u["pos"] + Vector2(0, -40), "+" + str(int(amt)), Color("#39d353"))

func _freeze(u: Dictionary, sec: float = CTRL_SEC) -> void:
	u["stun_until"] = maxf(u["stun_until"], _t + sec)
	_skill_ring(u["pos"], Color(0.6, 0.9, 1.0, 0.6), 48.0)

func _taunt(by: Dictionary, targets: Array, sec: float = BUFF_SEC) -> void:
	for o in targets:
		o["taunt_until"] = _t + sec
		o["taunt_by"] = by

func _buff(u: Dictionary, stat: String, amount: float, pct: bool, sec: float = BUFF_SEC) -> void:
	u["buffs"].append({"stat": stat, "amount": amount, "pct": pct, "until": _t + sec})
	_recalc_stats(u)

func _recalc_stats(u: Dictionary) -> void:
	var acc := {"atk": [0.0, 0.0], "def": [0.0, 0.0], "mr": [0.0, 0.0]}
	var dodge := 0.0
	var ls := 0.0
	for b in u["buffs"]:
		var s: String = b["stat"]
		if s == "dodge":
			dodge += b["amount"]; continue
		if s == "lifesteal":
			ls += b["amount"]; continue
		if not acc.has(s):
			continue
		if b["pct"]:
			acc[s][0] += b["amount"]
		else:
			acc[s][1] += b["amount"]
	u["atk"] = maxf(0.0, u["base_atk"] * (1.0 + acc["atk"][0]) + acc["atk"][1])
	u["def"] = maxf(0.0, u["base_def"] * (1.0 + acc["def"][0]) + acc["def"][1])
	u["mr"]  = maxf(0.0, u["base_mr"]  * (1.0 + acc["mr"][0])  + acc["mr"][1])
	u["dodge_bonus"] = dodge
	u["ls_bonus"] = ls

# flat DoT (诅咒等). dps=每秒落血; 真伤穿护盾. 灼烧/中毒/流血改走 _apply_dot_stacks 层数模型.
func _add_dot(u: Dictionary, tag: String, dps: float, sec: float) -> void:
	u["dots"].append({"tag": tag, "dps": dps, "until": _t + sec})

# 层数式 DoT 施加 (1:1 dot.gd apply_stacks). type∈[burn,poison,bleed]; 多次施加→累加层数. burn 检免疫.
func _apply_dot_stacks(u: Dictionary, type: String, stacks: int, src = null) -> void:
	if u == null or not u.get("alive", false) or stacks <= 0:
		return
	if type == "burn":
		if u.get("_burnImmune", false):
			return
		var passive = u.get("passive", null)
		if passive is Dictionary and passive.get("burnImmune", false):
			return
	var ds: Dictionary = u["dot_stacks"]
	ds[type] = int(ds.get(type, 0)) + stacks
	if src != null:
		u["dot_src"][type] = src

# 灼烧默认层数 = max(1, round(attacker.atk × 0.67))  (1:1 dot.gd default_burn_stacks)
func _default_burn_stacks(attacker: Dictionary) -> int:
	return maxi(1, roundi(float(attacker.get("atk", 0.0)) * 0.67))

func _has_dot(u: Dictionary, tag: String) -> bool:
	if tag == "burn" or tag == "poison" or tag == "bleed":
		return int(u.get("dot_stacks", {}).get(tag, 0)) > 0
	for d in u["dots"]:
		if d["tag"] == tag and _t < d["until"]:
			return true
	return false

# 层数 DoT 每秒结算 (1:1 dot.gd tick). 固定顺序 burn→poison→bleed; 出伤后层数衰减, ≤0 移除.
func _tick_dot_stacks(u: Dictionary) -> void:
	var ds: Dictionary = u.get("dot_stacks", {})
	if ds.is_empty():
		return
	var max_hp: float = u["maxHp"]
	for type in ["burn", "poison", "bleed"]:
		var stacks: int = int(ds.get(type, 0))
		if stacks <= 0:
			continue
		var dmg: int = 0
		var new_val: int = 0
		match type:
			"burn":
				dmg = stacks + roundi(max_hp * stacks * 0.001)
				new_val = floori(stacks * 2.0 / 3.0)
				if _t < u.get("true_fire_until", 0.0):
					_raw_lose(u, float(dmg))
				else:
					_apply_damage(u, dmg, Color("#7aa8ff"))
			"poison":
				dmg = stacks
				new_val = floori(stacks * 3.0 / 4.0)
				_apply_damage(u, dmg, Color("#7ee87e"))
			"bleed":
				dmg = stacks
				new_val = floori(stacks * 3.0 / 4.0)
				_apply_damage(u, dmg, Color("#ff6b6b"))
		ds[type] = maxi(0, new_val)
		if ds[type] <= 0:
			ds.erase(type)
		if not u["alive"]:
			return

func _cleanse(u: Dictionary) -> int:
	var n: int = u["dots"].size()
	u["dots"] = []
	for type in ["burn", "poison", "bleed"]:
		if int(u.get("dot_stacks", {}).get(type, 0)) > 0:
			n += 1
			u["dot_stacks"][type] = 0
	var kept: Array = []
	for b in u["buffs"]:
		if b["amount"] < 0.0:
			n += 1
		else:
			kept.append(b)
	u["buffs"] = kept
	u["slow_until"] = 0.0
	_recalc_stats(u)
	return n

func _add_stack(u: Dictionary, tag: String, n: int, cap: int) -> int:
	var cur: int = u["stacks"].get(tag, 0) + n
	cur = mini(cur, cap)
	u["stacks"][tag] = cur
	return cur

func _consume_stacks(u: Dictionary, tag: String) -> int:
	var c: int = u["stacks"].get(tag, 0)
	u["stacks"][tag] = 0
	return c

# 直线判定: p 是否在 origin 出发 dir 方向的一条宽 width 直线带上 (前方)
func _on_line(origin: Vector2, dir: Vector2, p: Vector2, width: float) -> bool:
	var rel: Vector2 = p - origin
	var along: float = rel.dot(dir)
	if along < 0.0: return false
	var perp: float = (rel - dir * along).length()
	return perp <= width

func _lowest_hp_ally(u: Dictionary):
	var best = null; var bv := INF
	for o in _allies_of(u):
		if o["hp"] < bv:
			bv = o["hp"]; best = o
	return best

func _allies_of(u: Dictionary, include_self: bool = true) -> Array:
	var out: Array = []
	for o in _units:
		if o["side"] == u["side"] and o["alive"] and (include_self or o != u):
			out.append(o)
	return out

# ============================================================================
#  被动系统: 登场被动 / on-hit / 周期被动 (1:1 搬自 2D 版)
# ============================================================================
# 召唤体永远主动平A不放技能; 选被动的龟(暂无)也不放. demo 默认全选主动.
func _is_passive_pick(u: Dictionary) -> bool:
	return u.get("is_summon", false)

func _apply_spawn_passives() -> void:
	for u in _units.duplicate():
		match u["id"]:
			"ninja":
				u["crit"] += 0.30; u["crit_dmg"] += 0.20; u["pierce"] += 8.0
				_buff(u, "dodge", 0.25, false, 9999.0)
			"ghost":
				for o in _enemies_of(u):
					_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
			"ice":
				for o in _enemies_of(u):
					_buff(o, "atk", -0.20, true, BUFF_SEC * 1.5)
					o["slow_until"] = _t + BUFF_SEC * 1.5
			"headless":
				u["lifesteal"] += 0.22
			"dice":
				u["pierce"] += u["def"] + u["mr"]
				u["base_def"] = 0.0; u["base_mr"] = 0.0; _recalc_stats(u)
			"pirate":
				var es := _enemies_of(u)
				if not es.is_empty():
					var v = es[randi() % es.size()]
					_raw_lose(v, v["maxHp"] * 0.25)
			"candy":
				var ce := _enemies_of(u)
				if not ce.is_empty():
					var v = ce[randi() % ce.size()]
					var steal: float = minf(v["maxHp"] * 0.25, v["hp"] - 1.0)
					if steal > 0: _raw_lose(v, steal); _heal(u, steal)
				_spawn_summon(u, "candybomb", u["maxHp"] * 0.40, 0.0, {
					"label": "糖果炸弹", "col_size": 20.0, "hp_w": 24.0,
					"no_basic": true, "no_move": true, "self_decay": 0.08,
					"death_aoe": 1.5,
				})
			"hiding":
				_spawn_hiding_minion(u)
			"crystal":
				_spawn_summon(u, "crystalball", u["maxHp"] * 0.50, u["atk"], {
					"label": "水晶球", "col_size": 20.0, "hp_w": 26.0, "melee": false,
					"move_spd": 90.0, "atk_range": 320.0, "no_basic": true,
					"special": "ray", "special_cd": 2.5, "special_scale": 1.0,
				})
			"lava":
				u["lava_set"] = "A"
			"two_head":
				u["two_set"] = "1"; u["two_form"] = "melee"

func _on_basic_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not tgt["alive"]:
		return
	match u["id"]:
		"line":
			_add_stack(tgt, "ink", 1, 5)
		"lightning":
			var lv := _add_stack(tgt, "electric", 1, 8)
			if lv >= 8:
				_consume_stacks(tgt, "electric")
				_apply_damage_from(u, tgt, int(u["atk"] * 0.82), Color("#bff0ff"), 0.0, true)
		"crystal":
			var cv := _add_stack(tgt, "crystal", 1, 4)
			if cv >= 4:
				_consume_stacks(tgt, "crystal")
				_apply_damage_from(u, tgt, int(tgt["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
				_buff(tgt, "mr", -0.2, true)
	# 猎人猎杀: 攻击后斩杀<14%HP敌
	if u["id"] == "hunter" and tgt["alive"] and tgt["hp"] < tgt["maxHp"] * 0.14:
		_float_text(tgt["pos"] + Vector2(0, -56), "斩杀!", Color("#ff6b6b"))
		var was_alive: bool = tgt["alive"]
		tgt["hp"] = 0.0
		if was_alive:
			_kill(tgt, u)
	# 无头亡灵: 每损1%HP攻击+1%(上限+100%)
	if u["id"] == "headless":
		var lost_pct: float = clampf(1.0 - u["hp"] / u["maxHp"], 0.0, 1.0)
		u["atk"] = u["base_atk"] * (1.0 + lost_pct)

func _tick_periodic_passive(u: Dictionary, delta: float) -> void:
	u["_ptimer"] = u.get("_ptimer", 0.0) + delta
	# --- 熔岩变身: 怒气满100 → 变火山N秒 ---
	if u["id"] == "lava" and u["rage"] >= RAGE_MAX and not u.get("volcano", false):
		u["rage"] = 0.0
		u["volcano"] = true
		u["volcano_until"] = _t + 6.0
		_buff(u, "atk", 0.6, true, 6.0); _buff(u, "def", 0.4, true, 6.0); _buff(u, "mr", 0.4, true, 6.0)
		u["maxHp"] *= 1.3; u["hp"] *= 1.3
		_float_text(u["pos"] + Vector2(0, -70), "变身·火山龟!", Color("#ff5a2a"))
		for o in _enemies_of(u):
			_apply_damage_from(u, o, _atk_dmg(u, 1.0, o, true), Color("#ff7a33"))
			_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
			_heal(u, (o["maxHp"] - o["hp"]) * 0.08)
	if u.get("volcano", false) and _t >= u["volcano_until"]:
		u["volcano"] = false
		u["maxHp"] /= 1.3; u["hp"] = minf(u["hp"], u["maxHp"])
	# --- 赛博浮游炮: 每周期生成1 (上限10) ---
	if u["id"] == "cyber":
		if u["_ptimer"] >= 3.0:
			u["_ptimer"] = 0.0
			var live: Array = []
			for d in u["summons"]:
				if d is Dictionary and d.get("alive", false): live.append(d)
			u["summons"] = live
			if u["summons"].size() < 10:
				var dr = _spawn_summon(u, "drone", u["maxHp"] * 0.12, u["atk"] * 0.25, {
					"label": "浮游炮", "col_size": 16.0, "hp_w": 22.0, "melee": false,
					"move_spd": 110.0, "atk_range": 300.0, "atk_interval": 1.0,
					"no_basic": true, "special": "random_hit", "special_cd": 1.6, "special_scale": 0.25,
				})
				if dr != null: u["summons"].append(dr)
	# --- 石头坚壁: 每秒+护甲 (上限100%开局护甲) ---
	elif u["id"] == "stone":
		if u["_ptimer"] >= STACK_DOT_TICK:
			u["_ptimer"] = 0.0
			if u["def"] < u["base_def"] * 2.0:
				u["base_def"] += u["base_def"] * 0.02; _recalc_stats(u)
	# --- 竹叶生长: 每N秒充能 → 永久+ATK/HP ---
	elif u["id"] == "bamboo":
		if u["_ptimer"] >= 4.0:
			u["_ptimer"] = 0.0
			u["base_atk"] *= 1.06; u["maxHp"] *= 1.04; u["hp"] += u["maxHp"] * 0.08
			_recalc_stats(u)
	# --- 龟壳气场觉醒 + 储能消耗周期 ---
	elif u["id"] == "shell":
		if not u.get("awakened", false) and _t >= 10.0:
			u["awakened"] = true
			_buff(u, "atk", 0.12, true, 9999.0); _buff(u, "def", 0.12, true, 9999.0); _buff(u, "mr", 0.12, true, 9999.0)
			u["crit"] += 0.25; _recalc_stats(u)
			_float_text(u["pos"] + Vector2(0, -70), "气场觉醒!", Color("#b0ffe0"))
		u["_shelltimer"] = u.get("_shelltimer", 0.0) + delta
		if u["_shelltimer"] >= 3.0:
			u["_shelltimer"] = 0.0
			var se: float = u["store_energy"]
			if se >= 1.0:
				u["store_energy"] = 0.0
				for o in _enemies_of(u):
					_apply_damage_from(u, o, int(se * 0.40), Color("#b0ffe0"))
				_grant_shield(u, se * 0.80)
				_float_text(u["pos"] + Vector2(0, -64), "气场释放!", Color("#b0ffe0"))
				_skill_ring(u["pos"], Color(0.7, 1.0, 0.88, 0.5), 120.0)
	# --- 海盗船召唤: 开战~4秒后召唤一次 ---
	if u["id"] == "pirate" and not u.get("ship_summoned", false) and _t >= 4.0:
		u["ship_summoned"] = true
		_spawn_pirate_ship(u)
	# --- 财神聚宝盆: 每秒+2金币 ---
	if u["id"] == "fortune":
		u["_goldtimer"] = u.get("_goldtimer", 0.0) + delta
		if u["_goldtimer"] >= 1.0:
			u["_goldtimer"] = 0.0; u["gold"] += 2

# ============================================================================
#  死亡钩子 (1:1 搬自 2D 版 _on_unit_death; 装备 on-kill/on-death Phase 3b 不调)
# ============================================================================
func _on_unit_death(u: Dictionary, killer) -> void:
	# 召唤体死亡爆炸 (糖果炸弹: 全体敌均摊魔伤)
	if u.get("death_aoe", 0.0) > 0.0:
		var es := _enemies_of(u)
		if not es.is_empty():
			var per: float = u["maxHp"] * u["death_aoe"] / float(es.size())
			for o in es:
				_apply_damage_from(u, o, int(per), Color("#ff8ad8"), 0.0, true, true)
			_skill_ring(u["pos"], Color(1.0, 0.5, 0.8, 0.6), 120.0)
			_float_text(u["pos"] + Vector2(0, -40), "炸!", Color("#ff8ad8"))
	# 缩头本体死亡 → 同步杀掉其随从
	if u["id"] == "hiding":
		for o in _units:
			if o.get("is_summon", false) and o.get("summon_owner", null) == u and o["alive"]:
				o["hp"] = 0.0; o["alive"] = false
				_hide_summon_nodes(o)
	# 赛博龟阵亡 → 浮游炮组装成机甲
	if u["id"] == "cyber":
		_cyber_assemble_mech(u)
	# 财神聚宝盆: 任意单位死亡给所有存活对面财神金币
	for o in _units:
		if o["alive"] and o["id"] == "fortune" and o["side"] != u["side"]:
			o["gold"] += 2
	# 猎人猎杀: 击杀者是猎人 → 窃取属性+叠吸血
	if killer != null and killer["alive"] and killer["id"] == "hunter":
		killer["base_atk"] += u["base_atk"] * 0.14
		killer["lifesteal"] += 0.08
		_recalc_stats(killer)
		_float_text(killer["pos"] + Vector2(0, -64), "猎杀!", Color("#a8ffb0"))
	# 幽灵强化怨灵: 死亡时再诅咒全体敌一次
	if u["id"] == "ghost":
		for o in _enemies_of(u):
			_add_dot(o, "curse", o["maxHp"] * 0.05, BUFF_SEC)
	# 海盗掠夺: 死亡钩锁击杀者 25% 最大HP 真伤
	if u["id"] == "pirate" and killer != null and killer["alive"]:
		_raw_lose(killer, killer["maxHp"] * 0.25)

# ============================================================================
#  召唤系统 (3D 化: billboard 立绘/色块 + blob影, 走同一 _tick_unit) — 逻辑 1:1 搬自 2D 版
# ============================================================================
const HIDING_POOL := ["basic", "stone", "bamboo", "ninja", "dice", "rainbow", "hunter", "pirate", "candy", "bubble", "line", "headless"]

func _spawn_hiding_minion(u: Dictionary) -> void:
	var pick: String = HIDING_POOL[randi() % HIDING_POOL.size()]
	var d: Dictionary = _data_by_id.get(pick, {})
	var st: Array = STATS.get(pick, DEFAULT_STAT)
	var hp: float = float(d.get("hp", 450)) * HP_MULT * 0.40
	var minion = _spawn_summon(u, "minion", hp, float(d.get("atk", 40)) * 0.8, {
		"label": "随从", "spr_id": pick, "col_size": 36.0, "hp_w": 30.0,
		"melee": bool(st[0]), "move_spd": float(st[1]), "atk_interval": float(st[2]), "atk_range": float(st[3]),
		"crit": float(d.get("crit", 0.2)),
	})
	if minion != null:
		minion["minion_kind"] = pick
		minion["hiding_protected"] = true

func _spawn_pirate_ship(u: Dictionary) -> void:
	var ship = _spawn_summon(u, "ship", u["maxHp"] * 1.5, u["atk"], {
		"label": "海盗船", "col_size": 38.0, "hp_w": 44.0, "melee": false,
		"move_spd": 70.0, "atk_range": 360.0, "no_basic": true,
		"special": "cannon", "special_cd": 2.0, "special_scale": 0.2,
	})
	if ship != null:
		_float_text(u["pos"] + Vector2(0, -70), "召唤海盗船!", Color("#ffb05c"))

# 赛博龟阵亡 → 浮游炮全部组装成机甲 (独立单位)
func _cyber_assemble_mech(u: Dictionary) -> void:
	var drones: Array = []
	for o in _units:
		if o.get("is_summon", false) and o["alive"] and o.get("summon_owner", null) == u and o.get("summon_kind", "") == "drone":
			drones.append(o)
	if drones.is_empty():
		return
	var n: int = drones.size()
	var mech_hp: float = u["maxHp"] * 0.5 + 200.0 * HP_MULT * n
	var mech_atk: float = u["base_atk"] * (0.6 + 0.25 * n)
	for d in drones:
		mech_hp += d["hp"]
		d["alive"] = false
		_hide_summon_nodes(d)
	var mech = _spawn_summon(u, "mech", mech_hp, mech_atk, {
		"label": "机甲", "col_size": 40.0, "hp_w": 46.0, "melee": false,
		"move_spd": 130.0, "atk_interval": 1.0, "atk_range": 320.0,
		"special": "mech_blast", "special_cd": 2.5, "special_scale": 1.5,
	})
	if mech != null:
		mech["pos"] = u["pos"]
		_float_text(u["pos"] + Vector2(0, -70), "机甲组装!", Color("#7ee8ff"))
		_skill_ring(u["pos"], Color(0.5, 0.9, 1.0, 0.6), 80.0)

# 召唤独立单位 — 3D 版: billboard 立绘(有 spr_id) 或彩色 billboard + blob影 + 血条 overlay. 走同一 tick.
func _spawn_summon(owner: Dictionary, kind: String, hp: float, atk: float, behavior: Dictionary = {}):
	var pos: Vector2 = owner["pos"] + Vector2(randf_range(-40, 40), randf_range(30, 60))
	pos.x = clampf(pos.x, ARENA.position.x, ARENA.end.x)
	pos.y = clampf(pos.y, ARENA.position.y, ARENA.end.y)
	var col := Color("#3fa9ff") if owner["side"] == "left" else Color("#ff5a5a")
	var spr_id: String = str(behavior.get("spr_id", ""))
	var col_size: float = float(behavior.get("col_size", 22.0))

	# --- 立绘/色块 billboard ---
	var spr := Sprite3D.new()
	spr.name = "Summon_" + kind
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tex: Texture2D = null
	if spr_id != "":
		tex = _avatar_tex(spr_id)
	if tex != null:
		spr.texture = tex
		spr.pixel_size = PIXEL_SIZE * (col_size / 56.0)
		spr.offset = Vector2(0.0, tex.get_height() * 0.5)
	else:
		spr.texture = _make_block_texture(Color(col.r, col.g, col.b, 0.9))
		spr.pixel_size = (col_size * WS) / 64.0
		spr.offset = Vector2(0.0, 32.0)
	spr.position = _world_pos(pos, GROUND_LIFT)
	_world.add_child(spr)

	# --- blob 暗影 ---
	var shadow := Sprite3D.new()
	shadow.texture = _make_blob_texture()
	shadow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shadow.axis = Vector3.AXIS_Y
	shadow.pixel_size = 0.008
	shadow.shaded = false
	shadow.transparent = true
	shadow.modulate = Color(1, 1, 1, SHADOW_BASE_A)
	shadow.scale = SHADOW_BASE * 0.6
	shadow.position = _world_pos(pos, 0.02)
	_world.add_child(shadow)

	# --- HP overlay (召唤体只有血条) ---
	var bar := _make_status_bar(owner["side"])
	bar["shield"].visible = false
	bar["en"].visible = false
	_ui_layer.add_child(bar["root"])

	var hp_w: float = float(behavior.get("hp_w", 28.0))
	var su := {
		"id": "_summon_" + kind, "name": str(behavior.get("label", kind)), "rarity": "C", "side": owner["side"],
		"pos": pos, "vel": Vector2.ZERO,
		"height": 0.0, "vy": 0.0, "vx": 0.0, "vz": 0.0, "airborne": false,
		"hp": hp, "maxHp": hp,
		"atk": atk, "def": 0.0, "mr": 0.0, "base_atk": atk, "base_def": 0.0, "base_mr": 0.0,
		"crit": float(behavior.get("crit", 0.0)), "crit_dmg": 1.5, "pierce": 0.0, "lifesteal": 0.0,
		"melee": bool(behavior.get("melee", kind != "drone")),
		"move_spd": float(behavior.get("move_spd", 0.0 if behavior.get("no_move", false) else 120.0)),
		"atk_interval": float(behavior.get("atk_interval", 1.2)),
		"atk_range": float(behavior.get("atk_range", 280.0 if kind == "drone" else 70.0)),
		"atk_cd": 0.0, "energy": 0.0, "alive": true, "is_summon": true,
		"shield": 0.0, "burn_until": 0.0, "burn_dps": 0.0, "stun_until": 0.0, "slow_until": 0.0,
		"dot_stacks": {}, "_dottimer": 0.0, "dot_src": {}, "true_fire_until": 0.0,
		"buffs": [], "dots": [], "taunt_until": 0.0, "taunt_by": null,
		"dodge_bonus": 0.0, "ls_bonus": 0.0,
		"stacks": {}, "rage": 0.0, "star_energy": 0.0, "store_energy": 0.0, "gold": 0.0,
		"dmg_dealt": 0.0, "reborn_used": false, "untargetable_until": 0.0, "summons": [],
		# 召唤 AI 行为字段 ----
		"summon_kind": kind, "summon_owner": owner, "hp_w": hp_w,
		"no_basic": bool(behavior.get("no_basic", false)),
		"no_move": bool(behavior.get("no_move", false)),
		"summon_special": str(behavior.get("special", "")),
		"special_cd": float(behavior.get("special_cd", 0.0)),
		"special_timer": 0.0,
		"special_scale": float(behavior.get("special_scale", 1.0)),
		"death_aoe": float(behavior.get("death_aoe", 0.0)),
		"self_decay": float(behavior.get("self_decay", 0.0)),
		"equips": [], "eq_state": {}, "hp50_fired": false,
		# 节点引用
		"sprite": spr, "shadow": shadow, "ring": null, "shadow_base_scale": SHADOW_BASE * 0.6,
		"bar_root": bar["root"], "hp_fill": bar["hp"], "shield_fill": bar["shield"], "en_fill": bar["en"],
		"spr_base_offy": spr.offset.y,
	}
	_units.append(su)
	return su

func _hide_summon_nodes(u: Dictionary) -> void:
	for key in ["sprite", "shadow", "ring"]:
		var n = u.get(key, null)
		if is_instance_valid(n):
			n.hide()
	if is_instance_valid(u.get("bar_root", null)):
		u["bar_root"].visible = false

# 召唤体周期特殊技 + 自损 (1:1 搬自 2D 版)
func _tick_summon_special(u: Dictionary, delta: float) -> void:
	if u.get("self_decay", 0.0) > 0.0:
		_raw_lose(u, u["maxHp"] * u["self_decay"] * delta)
		if not u["alive"]:
			return
	var special: String = u.get("summon_special", "")
	if special == "" or u.get("special_cd", 0.0) <= 0.0:
		return
	u["special_timer"] = u.get("special_timer", 0.0) + delta
	if u["special_timer"] < u["special_cd"]:
		return
	u["special_timer"] = 0.0
	var owner = u.get("summon_owner", u)
	if owner == null or not owner.get("alive", false):
		owner = u
	match special:
		"cannon":
			var es := _enemies_of(u)
			if es.is_empty(): return
			var o = es[randi() % es.size()]
			_fire_bolt_from(u, o, _atk_dmg(u, u.get("special_scale", 0.2), o), Color("#ffb05c"))
			_skill_ring(o["pos"], Color(1.0, 0.6, 0.2, 0.45), 40.0)
		"ray":
			var t = _nearest_enemy(u)
			if t == null: return
			_bolt_line(u["pos"], t["pos"], Color("#c9b0ff"))
			for i in range(2):
				if not t["alive"]: break
				_apply_damage_from(u, t, _atk_dmg(u, u.get("special_scale", 1.0), t, true), Color("#c9b0ff"), 0.0, true)
			if t["alive"]:
				var cv := _add_stack(t, "crystal", 1, 4)
				if cv >= 4:
					_consume_stacks(t, "crystal")
					_apply_damage_from(u, t, int(t["maxHp"] * 0.19), Color("#c9b0ff"), 0.0, true)
		"random_hit":
			var es2 := _enemies_of(u)
			if es2.is_empty(): return
			var o2 = es2[randi() % es2.size()]
			_fire_bolt_from(u, o2, _atk_dmg(u, u.get("special_scale", 0.25), o2), Color("#9bf0ff"))
		"mech_blast":
			var low = null; var lv := INF
			for o in _enemies_of(u):
				if o["hp"] < lv: lv = o["hp"]; low = o
			if low == null: return
			_bolt_line(u["pos"], low["pos"], Color("#9bf0ff"))
			for i in range(2):
				if not low["alive"]: break
				_apply_damage_from(u, low, _atk_dmg(u, u.get("special_scale", 1.5) * 0.5, low), Color("#9bf0ff"))

# 纯色块贴图 (召唤体占位, 无立绘时)
func _make_block_texture(col: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, col)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64; gt.height = 64
	return gt

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
		# 影/环: 跟 XZ 不跟 Y (贴地), 随高度缩小变淡 (从各自基准 scale 起算, 召唤体影更小)
		var s: float = 1.0 - clampf(u["height"] / 3.0, 0.0, 0.7)
		if is_instance_valid(shadow):
			var base_sc: Vector3 = u.get("shadow_base_scale", SHADOW_BASE)
			shadow.position = _world_pos(u["pos"], 0.02)
			shadow.scale = base_sc * s
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
		# 更新 fill 宽度 (召唤体只有血条, 宽度按 hp_w 占满 60 槽)
		if u.get("is_summon", false):
			u["hp_fill"].size.x = 60.0 * clampf(u["hp"] / u["maxHp"], 0.0, 1.0)
		else:
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
		if u["alive"] and not u.get("is_summon", false):   # 召唤体不计入胜负判定
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

# ============================================================================
#  装备实时实装 (59件 p2eq_*) — 1:1 搬自 2D 版 RealtimeBattleScene.gd (docs/design/装备实时实装规格.md)
#  数据驱动: 逐星属性复用 P2RT.STATS; 事件钩子 on-hit/on-cast/on-target/on-dodge/on-kill/on-death/HP阈值 + 周期 tick(2.5s).
#  2.5D 适配: 逻辑/数值全照搬; VFX/坐标触点用 Phase3 的 3D 等价 (_float_text/_skill_ring/_bolt_line/_fire_bolt_from/_spawn_summon).
#  分类标注: ✅完整 / ⚠改造(节拍·时长·站位) / 🚧TODO(简化) — 与 2D 版一致.
# ============================================================================
const P2RT := preload("res://scripts/engine/phase2_equip_runtime.gd")
const EQ_TICK := 2.5            # 装备周期触发 = 1回合 ≈ 2.5 秒 (规格)
const EQ_BLEED_SEC := 5.0       # 流血/灼烧 DoT 持续秒 (待F5)
const EQ_BURN_SEC := 5.0

# demo 测试装备 (persistent_equipped 空时): 给每龟塞2-3件有视觉效果的件, 验证效果真触发. (与 2D 版 DEMO_EQUIP 一致)
const DEMO_EQUIP := {
	"stone":     [{"id": "p2eq_016", "star": 2}, {"id": "p2eq_013", "star": 2}],          # 铁壁盾(周期全队护盾)+炙烤海胆(受击硬化)
	"basic":     [{"id": "p2eq_002", "star": 3}, {"id": "p2eq_005", "star": 2}, {"id": "p2eq_023", "star": 2}],  # 海带卷刀(流血)+双生匕首(追击)+灼热火珊瑚(灼烧)
	"lightning": [{"id": "p2eq_026", "star": 2}, {"id": "p2eq_004", "star": 2}],          # 雷电法杖(连锁闪电)+暴君之牙(处决)
	"diamond":   [{"id": "p2eq_016", "star": 2}, {"id": "p2eq_046", "star": 2}],          # 铁壁盾(周期护盾)+幽灵墨鱼(闪避护盾)
	"ninja":     [{"id": "p2eq_002", "star": 3}, {"id": "p2eq_054", "star": 1}, {"id": "p2eq_058", "star": 2}],  # 流血+瞄准镜(必中)+穿甲遗弹(贯穿)
	"ghost":     [{"id": "p2eq_023", "star": 3}, {"id": "p2eq_026", "star": 1}],          # 灼热火珊瑚(灼烧)+雷电法杖(连锁)
}

# 装备注入: 玩家队(left)读 persistent_equipped; demo 阵容兜底塞测试装备.
func _inject_equipment() -> void:
	var gs = get_node_or_null("/root/GameState")
	var pe: Dictionary = {}
	if gs != null and gs.get("persistent_equipped") is Dictionary:
		pe = gs.get("persistent_equipped")
	var use_demo: bool = pe.is_empty()
	for u in _units:
		if u.get("is_summon", false):
			continue
		var key: String = str(u["id"])
		var list: Array = []
		if not use_demo and pe.has(key):
			if u["side"] == "left":
				for it in (pe[key] as Array):
					if it is Dictionary and it.has("id"):
						list.append({"id": str(it["id"]), "star": int(it.get("star", 1))})
		if use_demo and DEMO_EQUIP.has(key):
			list = (DEMO_EQUIP[key] as Array).duplicate(true)
		u["equips"] = list
		for e in list:
			u["eq_state"][str(e["id"])] = {}

# 开战: 全装备纯属性 + 永久 flag 加到携带者 (在 spawn 被动之后, 让属性叠上不被覆盖).
func _eq_apply_all_stats() -> void:
	for u in _units:
		for e in u.get("equips", []):
			_eq_apply_one_stats(u, str(e["id"]), int(e.get("star", 1)))

# 单件逐星属性 → 实时单位字段 (复用 P2RT.STATS; 字段口径换到实时引擎).
func _eq_apply_one_stats(u: Dictionary, item_id: String, star: int) -> void:
	var arr: Array = P2RT.STATS.get(item_id, [])
	var i: int = clampi(star, 1, 3) - 1
	if i < 0 or i >= arr.size():
		_eq_apply_flags(u, item_id, star)
		return
	var st: Dictionary = arr[i]
	if st.has("atk"):
		u["base_atk"] += float(st["atk"])
	if st.has("hp"):
		var add: float = float(st["hp"]) * HP_MULT
		u["maxHp"] += add; u["hp"] += add
	if st.has("crit"):
		u["crit"] += float(st["crit"])
	if st.has("armorPen"):
		u["pierce"] += float(st["armorPen"])
	if st.has("magicPen"):
		u["pierce"] += float(st["magicPen"])
	if st.has("_lifestealPct"):
		u["lifesteal"] += float(st["_lifestealPct"]) / 100.0
	if st.has("def"):
		u["base_def"] += float(st["def"])
	if st.has("mr"):
		u["base_mr"] += float(st["mr"])
	if st.has("critDmg"):
		u["crit_dmg"] += float(st["critDmg"])
	if st.has("_maxEnergy"):
		u["energy"] = minf(MAX_ENERGY - 1.0, u["energy"] + float(st["_maxEnergy"]) * 0.2)
	_recalc_stats(u)
	_eq_apply_flags(u, item_id, star)

# 永久 flag / 初始充能 (受击/闪避/必中类被动开关 + 充能计数器初值).
func _eq_apply_flags(u: Dictionary, item_id: String, star: int) -> void:
	var si: int = clampi(star, 1, 3) - 1
	var stt: Dictionary = u["eq_state"].get(item_id, {})
	match item_id:
		"p2eq_046":   # 幽灵墨鱼: 永久闪避 buff (复用 dodge 系统)
			_buff(u, "dodge", [0.15, 0.25, 0.50][si], false, 99999.0)
			stt["ghost_shield"] = [30.0, 50.0, 120.0][si]
		"p2eq_054":   # 瞄准镜: 必中 (无视目标闪避)
			u["eq_cannot_be_dodged"] = true
		"p2eq_013", "p2eq_014":   # 炙烤海胆 / 深海堡垒甲: 受击硬化层 +def/mr (cap20)
			stt["harden_inc"] = [1.0, 1.5, 2.0][si]
			stt["harden_stacks"] = 0
			stt["harden_shield"] = (50.0 if item_id == "p2eq_013" else 0.0) if si == 0 else ([60.0, 80.0][si - 1] if item_id == "p2eq_013" else 0.0)
			stt["harden_given"] = false
		"p2eq_015":   # 荆棘海胆: 反伤转真伤+施流血
			stt["reflect_pct"] = [10.0, 17.0, 25.0][si] / 100.0
			stt["reflect_bleed"] = [2.0, 2.5, 3.0][si]
		"p2eq_024":   # 龙蛋: 装备即3层吐息
			stt["dragon_stacks"] = 3
		"p2eq_039":   # 竹制弓箭: 生长充能数 (3★=3次)
			stt["bamboo_charges"] = [1, 1, 3][si]
		"p2eq_052":   # 左轮: 6发子弹
			stt["revolver_bullets"] = 6
		"p2eq_027":   # 电棍: 3层电击
			stt["baton_charges"] = 3
		"p2eq_047":   # 重击锤: ATK += maxHp×pct (一次性按当前maxHp折算)
			var pct: float = [0.04, 0.06, 0.15][si]
			u["base_atk"] += u["maxHp"] / HP_MULT * pct
			_recalc_stats(u)
		"p2eq_035":   # 黄铜齿轮: 齿轮层
			stt["gears"] = 0
		"p2eq_017":   # 不沉之锚: 免击飞+免斩杀 (flag)
			u["_knock_immune"] = true
			u["eq_exec_immune"] = true
		"p2eq_036":   # 温泉蛋: 孵化进度 → 满级全队护盾(一次)
			stt["incub"] = 0.0
			stt["incub_given"] = false
			stt["incub_shield"] = [300.0, 400.0, 600.0][si]
	u["eq_state"][item_id] = stt

# ── 工具 ──
func _eq_si(star: int) -> int:
	return clampi(star, 1, 3) - 1

func _eq_first_in_line(u: Dictionary, dir: Vector2, width: float):
	var best = null; var bd := INF
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], width):
			var dd: float = (o["pos"] - u["pos"]).length_squared()
			if dd < bd: bd = dd; best = o
	return best

func _eq_farthest_enemies(u: Dictionary, half: bool) -> Array:
	var es := _enemies_of(u)
	es.sort_custom(func(a, b): return (a["pos"] - u["pos"]).length_squared() > (b["pos"] - u["pos"]).length_squared())
	if half:
		return es.slice(0, maxi(1, es.size() / 2))
	return es

# 某一方是否有存活单位携带某装备 (飞镖靶子标记用)
func _side_has_equip(side: String, item_id: String) -> bool:
	for o in _units:
		if o["side"] == side and o["alive"]:
			for e in o.get("equips", []):
				if str(e["id"]) == item_id:
					return true
	return false

func _count_summons(side: String, kind: String) -> int:
	var c := 0
	for o in _units:
		if o.get("is_summon", false) and o["side"] == side and o["alive"] and str(o.get("summon_kind", "")) == kind:
			c += 1
	return c

# 充能助手: 累加 amt, 达 cap → 清零(保留溢出)并触发 on_full.
func _eq_charge(stt: Dictionary, key: String, amt: float, cap: float, on_full: Callable) -> void:
	var v: float = float(stt.get(key, 0.0)) + amt
	if v >= cap:
		stt[key] = v - cap
		on_full.call()
	else:
		stt[key] = v

# ============================================================================
#  on-hit (每段命中后, attacker 视角)
# ============================================================================
func _eq_on_hit(src: Dictionary, tgt: Dictionary, dmg: int) -> void:
	if src.get("equips", []).is_empty():
		return
	for e in src["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = src["eq_state"].get(iid, {})
		match iid:
			"p2eq_004":   # 暴君之牙: 处决<斩杀线敌
				var line: float = [0.05, 0.07, 0.10][si] + [0.10, 0.15, 0.40][si] * src["crit"]
				if tgt["alive"] and not tgt.get("eq_exec_immune", false) and tgt["hp"] < tgt["maxHp"] * line:
					var was: bool = tgt["alive"]
					tgt["hp"] = 0.0
					if was: _kill(tgt, src)
			"p2eq_002":   # 海带卷刀: 命中→施加流血层
				var bs: int = maxi(1, roundi([0.075, 0.1, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "bleed", bs, src)
			"p2eq_003":   # 锋利鲨齿: 溅射相邻格
				var frac: float = [0.15, 0.28, 0.50][si]
				for o in _enemies_of(src):
					if o != tgt and (o["pos"] - tgt["pos"]).length() <= 70.0:
						_apply_damage_from(src, o, maxi(1, int(dmg * frac)), Color("#ffd07a"), 0.0, false, true)
			"p2eq_005":   # 双生匕首: 概率追击
				if randf() < [0.5, 0.75, 1.0][si]:
					_apply_damage_from(src, tgt, _atk_dmg(src, [0.7, 0.8, 1.0][si], tgt), Color("#ffe08a"), 0.0, false, true)
			"p2eq_023":   # 灼热火珊瑚(被动): 每段额外灼烧 + 充能
				var burn: int = maxi(1, roundi([5.0, 7.0, 10.0][si] + [0.07, 0.11, 0.15][si] * src["atk"]))
				_apply_dot_stacks(tgt, "burn", burn, src)
				_eq_charge(stt, "fire_mana", 1.0, 8.0, func(): _eq_fire_coral_active(src, si))
			"p2eq_009":   # 宽刃弯刀: 充刃能, 满100→直线伤害
				_eq_charge(stt, "blade_energy", [20.0, 20.0, 25.0][si], 100.0, func(): _eq_wide_blade(src, tgt, si))
			"p2eq_026":   # 雷电法杖: 充能25, 满100→连锁闪电
				_eq_charge(stt, "thunder", 25.0, 100.0, func(): _eq_chain_lightning(src, si))
			"p2eq_029":   # 冰封水母: 概率额外魔伤+冻结, 冻结→自护盾
				if randf() < [0.20, 0.25, 0.30][si]:
					_apply_damage_from(src, tgt, [10, 15, 25][si], Color("#bfe9ff"), 0.0, false, true)
					_freeze(tgt, EQ_TICK)
					_grant_shield(src, [20.0, 30.0, 50.0][si])
			"p2eq_055":   # 靶向器: 命中标记目标 (+20% 受伤) 2回合
				tgt["eq_marked_until"] = _t + EQ_TICK * 2.0
			"p2eq_058":   # 穿甲遗弹: 贯穿→身后同列敌
				var frac2: float = [0.25, 0.40, 0.60][si]
				var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
				for o in _enemies_of(src):
					if o != tgt and _on_line(tgt["pos"], dir, o["pos"], 40.0):
						_apply_damage_from(src, o, maxi(1, int(dmg * frac2)), Color("#ffd07a"), 0.0, false, true)
		src["eq_state"][iid] = stt

# 雷电法杖 026: 连锁闪电
func _eq_chain_lightning(src: Dictionary, si: int) -> void:
	var hops: int = [4, 5, 6][si]; var dmg: int = [20, 25, 30][si]
	var hit: Array = []
	var pool := _enemies_of(src)
	if pool.is_empty():
		return
	var cur = pool[randi() % pool.size()]
	var prev: Vector2 = src["pos"]
	for h in range(hops):
		if cur == null:
			break
		hit.append(cur)
		_bolt_line(prev, cur["pos"], Color("#bff0ff"))
		_apply_damage_from(src, cur, dmg, Color("#bff0ff"), 0.0, true, true)
		prev = cur["pos"]
		var nx = null; var bd := INF
		for o in _enemies_of(src):
			if o in hit: continue
			var dd: float = (o["pos"] - cur["pos"]).length_squared()
			if dd < bd: bd = dd; nx = o
		cur = nx

# 宽刃弯刀 009
func _eq_wide_blade(src: Dictionary, tgt: Dictionary, si: int) -> void:
	var dir: Vector2 = (tgt["pos"] - src["pos"]).normalized()
	if dir.length() < 0.1:
		dir = Vector2.RIGHT
	var line_targets: Array = []
	for o in _enemies_of(src):
		if _on_line(src["pos"], dir, o["pos"], 55.0):
			line_targets.append(o)
	var mult: float = ([2.0, 2.5, 3.0][si]) if line_targets.size() <= 1 else 1.0
	for o in line_targets:
		_apply_damage_from(src, o, int([30, 45, 60][si] * mult), Color("#9bf0ff"), 0.0, true, true)
		_apply_damage_from(src, o, int(_atk_dmg(src, [0.5, 0.7, 0.9][si], o) * mult), Color("#9bf0ff"), 0.0, false, true)
	_bolt_line(src["pos"], tgt["pos"] + dir * 200.0, Color("#9bf0ff"))

# 灼热火珊瑚 023(主动满法力)
func _eq_fire_coral_active(src: Dictionary, si: int) -> void:
	_float_text(src["pos"] + Vector2(0, -70), "烈焰爆发!", Color("#ff7a33"))
	for o in _enemies_of(src):
		_apply_dot_stacks(o, "burn", 60, src)
		_skill_ring(o["pos"], Color(1.0, 0.5, 0.2, 0.5), 44.0)

# ============================================================================
#  on-target (受伤时, 防守者视角)
# ============================================================================
func _eq_on_target(u: Dictionary, src: Dictionary, dmg: int) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_013", "p2eq_014":   # 受击硬化: +def/mr (cap20层); 013满层给护盾
				var cur: int = int(stt.get("harden_stacks", 0))
				if cur < 20:
					cur += 1
					var inc: float = float(stt.get("harden_inc", 1.0))
					u["base_def"] += inc; u["base_mr"] += inc
					_recalc_stats(u)
					stt["harden_stacks"] = cur
					if cur >= 20 and not bool(stt.get("harden_given", false)) and float(stt.get("harden_shield", 0.0)) > 0.0:
						stt["harden_given"] = true
						_grant_shield(u, float(stt["harden_shield"]))
			"p2eq_015":   # 荆棘海胆: 反伤真伤 + 施流血给攻击者
				if src.get("alive", false) and src["side"] != u["side"]:
					var refl: float = float(dmg) * float(stt.get("reflect_pct", 0.10))
					if refl >= 1.0:
						_raw_lose(src, refl)
					_apply_dot_stacks(src, "bleed", maxi(1, roundi(float(stt.get("reflect_bleed", 2.0)))), u)
		u["eq_state"][iid] = stt

# ============================================================================
#  on-dodge (闪避后)
# ============================================================================
func _eq_on_dodge(u: Dictionary) -> void:
	for e in u.get("equips", []):
		if str(e["id"]) == "p2eq_046":   # 幽灵墨鱼: 闪避→永久护盾
			var stt: Dictionary = u["eq_state"].get("p2eq_046", {})
			_grant_shield(u, float(stt.get("ghost_shield", 30.0)))

# ============================================================================
#  on-cast (放主动技后)
# ============================================================================
func _eq_on_cast(u: Dictionary, tgt: Dictionary) -> void:
	if u.get("equips", []).is_empty():
		return
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_006":   # 千刃风暴: 一排剑穿过全体敌
				var flat: int = [70, 100, 400][si]; var sc: float = [0.8, 1.3, 4.0][si]
				for o in _enemies_of(u):
					_apply_damage_from(u, o, _atk_dmg(u, sc, o) + flat, Color("#dfe8ff"), 0.0, false, true)
				_skill_ring(u["pos"], Color(0.8, 0.9, 1.0, 0.5), 120.0)
			"p2eq_007":   # 锈蚀阔剑: 斩最近敌一横排+自护盾
				var dir: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var tot := 0
				for o in _enemies_of(u):
					if _on_line(u["pos"], dir, o["pos"], 55.0):
						var dd: int = _atk_dmg(u, [0.5, 0.8, 1.1][si], o) + [20, 35, 60][si]
						_apply_damage_from(u, o, dd, Color("#ffe08a"), 0.0, false, true); tot += dd
				_grant_shield(u, tot * [0.5, 0.75, 1.0][si])
			"p2eq_008":   # 双穿珊瑚刺: 对最远敌
				var far = null; var fd := -1.0
				for o in _enemies_of(u):
					var dd2: float = (o["pos"] - u["pos"]).length_squared()
					if dd2 > fd: fd = dd2; far = o
				if far != null:
					_apply_damage_from(u, far, _atk_dmg(u, [1.0, 1.2, 1.5][si], far), Color("#ffe08a"), 0.0, false, true)
					_apply_damage_from(u, far, int(far["maxHp"] * [0.08, 0.12, 0.18][si]), Color("#bfe9ff"), 0.0, true, true)
			"p2eq_011":   # 饮血护符坠: 连斩随机敌 (衰减)
				var n: int = [5, 6, 8][si]
				var es := _enemies_of(u)
				for k in range(n):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					var decay: float = pow(0.85, k)
					_apply_damage_from(u, o, int((_atk_dmg(u, [0.5, 0.7, 1.0][si], o) + [40, 50, 70][si]) * decay), Color("#ff8aa0"), 0.33, false, true)
			"p2eq_014":   # 深海堡垒甲(主动): 汲取全敌+回血
				var k2: float = [0.8, 1.0, 1.5][si]
				for o in _enemies_of(u):
					_apply_damage_from(u, o, int(k2 * (u["def"] + u["mr"])), Color("#bfe9ff"), 0.0, true, true)
					_heal(u, [40, 65, 130][si])
			"p2eq_022":   # 余烬燃油瓶: 对最近敌灼烧(真火)
				var t2 = _nearest_enemy(u)
				if t2 != null:
					var tf: int = maxi(1, roundi([20, 35, 60][si] + [0.10, 0.15, 0.20][si] * u["atk"]))
					_apply_dot_stacks(t2, "burn", tf, u)
					t2["true_fire_until"] = _t + 5.0
			"p2eq_028":   # 冰霜冻露瓶: 对最近敌魔伤+冰寒(减速)
				var t3 = _nearest_enemy(u)
				if t3 != null:
					_apply_damage_from(u, t3, [40, 60, 100][si], Color("#bfe9ff"), 0.0, true, true)
					t3["slow_until"] = _t + EQ_TICK * 3.0
			"p2eq_030":   # 迷你水晶球A: 沿一列水晶光束+叠层引爆
				var t4 = _nearest_enemy(u)
				if t4 != null:
					var dir2: Vector2 = (t4["pos"] - u["pos"]).normalized()
					for _seg in range([2, 2, 3][si]):
						for o in _enemies_of(u):
							if _on_line(u["pos"], dir2, o["pos"], 50.0):
								_apply_damage_from(u, o, [30, 35, 40][si], Color("#c9b0ff"), 0.0, true, true)
								_eq_crystal_stack(u, o, si)
					_bolt_line(u["pos"], t4["pos"] + dir2 * 200.0, Color("#c9b0ff"))
			"p2eq_031":   # 迷你水晶球B: 对全体敌魔伤+叠层引爆
				for o in _enemies_of(u):
					_apply_damage_from(u, o, [20, 25, 30][si], Color("#c9b0ff"), 0.0, true, true)
					_eq_crystal_stack(u, o, si)
			"p2eq_039":   # 竹制弓箭: 充能内→强化攻击+自回血+永久+maxHP
				var stt2: Dictionary = u["eq_state"].get("p2eq_039", {})
				if int(stt2.get("bamboo_charges", 0)) > 0:
					stt2["bamboo_charges"] = int(stt2["bamboo_charges"]) - 1
					var t5 = _nearest_enemy(u)
					if t5 != null:
						_apply_damage_from(u, t5, [25, 30, 35][si] + int(u["maxHp"] / HP_MULT * 0.20), Color("#a8ffb0"), 0.0, true, true)
					_heal(u, u["maxHp"] * 0.20)
					var grow: float = [90.0, 95.0, 100.0][si] * HP_MULT
					u["maxHp"] += grow; u["hp"] += grow
					_float_text(u["pos"] + Vector2(0, -70), "生长!", Color("#39d353"))
					u["eq_state"]["p2eq_039"] = stt2
			"p2eq_048":   # 黄铜手铳: 射N发, 每发命中直线首敌
				var dir3: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				for _b in range([4, 5, 6][si]):
					var ft = _eq_first_in_line(u, dir3, 36.0)
					if ft != null:
						_apply_damage_from(u, ft, _atk_dmg(u, [0.5, 0.54, 0.6][si], ft), Color("#ffd07a"), 0.0, false, true)
			"p2eq_049":   # 连发弩: 对较远半数敌连射, 按已损血加伤
				for o in _eq_farthest_enemies(u, true):
					var lost: float = clampf((1.0 - o["hp"] / o["maxHp"]) / 0.3, 0.0, 1.0)
					var sc2: float = lerpf(0.8, 1.3, lost)
					for _r in range([1, 2, 3][si]):
						_apply_damage_from(u, o, _atk_dmg(u, sc2, o), Color("#ffd07a"), 0.0, false, true)
			"p2eq_050":   # 幽灵加特林: N发随机分布+永久减甲
				for _g in range([20, 30, 60][si]):
					var es2 := _enemies_of(u)
					if es2.is_empty(): break
					var o = es2[randi() % es2.size()]
					_apply_damage_from(u, o, _atk_dmg(u, [0.1, 0.12, 0.14][si], o), Color("#d0ffff"), 0.0, false, true)
					o["base_def"] = maxf(0.0, o["base_def"] - [1.0, 2.0, 3.0][si]); _recalc_stats(o)
			"p2eq_051":   # 激光手枪: 直线首敌+流血, 身后50%
				var dir4: Vector2 = (_nearest_enemy(u)["pos"] - u["pos"]).normalized() if _nearest_enemy(u) != null else Vector2.RIGHT
				var first = _eq_first_in_line(u, dir4, 50.0)
				if first != null:
					_apply_damage_from(u, first, _atk_dmg(u, [1.5, 2.0, 2.8][si], first), Color("#ff8aa0"), 0.0, false, true)
					_apply_dot_stacks(first, "bleed", maxi(1, roundi(u["atk"] * [0.5, 0.5, 0.6][si])), u)
					for o in _enemies_of(u):
						if o != first and _on_line(first["pos"], dir4, o["pos"], 50.0):
							_apply_damage_from(u, o, _atk_dmg(u, [0.75, 1.0, 1.4][si], o), Color("#ff8aa0"), 0.0, false, true)
			"p2eq_053":   # 霰弹贝古: 扇形N发, 被8+发命中→眩晕
				var hitc: Dictionary = {}
				for _s in range([12, 14, 18][si]):
					var es3 := _enemies_of(u)
					if es3.is_empty(): break
					var o = es3[randi() % es3.size()]
					_apply_damage_from(u, o, _atk_dmg(u, 0.22, o), Color("#ffd07a"), 0.0, false, true)
					hitc[o] = int(hitc.get(o, 0)) + 1
				for o in hitc:
					if int(hitc[o]) >= 8: _freeze(o, EQ_TICK)
			"p2eq_057":   # 狙击长管: 对最低血%敌沿途敌, 击杀则再开
				_eq_sniper(u, si, 0)
			"p2eq_010":   # 激光长刃: 横扫一列, 命中1则竖斩; 回血
				var t6 = _nearest_enemy(u)
				if t6 != null:
					var dir5: Vector2 = (t6["pos"] - u["pos"]).normalized()
					var tot2 := 0; var cnt := 0
					for o in _enemies_of(u):
						if si == 2 or _on_line(u["pos"], dir5, o["pos"], 55.0):
							var dd3: int = _atk_dmg(u, [1.2, 2.5, 5.0][si], o) + [100, 200, 2000][si]
							_apply_damage_from(u, o, dd3, Color("#9bf0ff"), 0.0, false, true); tot2 += dd3; cnt += 1
					if cnt == 1:
						_apply_damage_from(u, t6, _atk_dmg(u, [1.2, 2.5, 5.0][si], t6), Color("#9bf0ff"), 0.0, false, true)
					_heal(u, tot2 * [0.35, 0.8, 1.0][si])

# 水晶叠层 (A/B共用)
func _eq_crystal_stack(src: Dictionary, o: Dictionary, si: int) -> void:
	var lv := _add_stack(o, "p2crystal", 1, 3)
	if lv >= 3:
		_consume_stacks(o, "p2crystal")
		_apply_damage_from(src, o, int(o["maxHp"] * [0.14, 0.17, 0.20][si]), Color("#c9b0ff"), 0.0, true, true)

# 狙击长管 057: 递归开枪
func _eq_sniper(u: Dictionary, si: int, depth: int) -> void:
	if depth >= 12:
		return
	var low = null; var lv := INF
	for o in _enemies_of(u):
		var p: float = o["hp"] / o["maxHp"]
		if p < lv: lv = p; low = o
	if low == null:
		return
	var dir: Vector2 = (low["pos"] - u["pos"]).normalized()
	_bolt_line(u["pos"], low["pos"], Color("#ffe08a"))
	var killed := false
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 36.0):
			var before: bool = o["alive"]
			_apply_damage_from(u, o, _atk_dmg(u, [2.0, 3.0, 7.0][si], o), Color("#ffe08a"), 0.0, false, true)
			if before and not o["alive"]:
				killed = true
	if killed:
		_eq_sniper(u, si, depth + 1)

# ============================================================================
#  on-kill (击杀者视角) — 暴君之牙
# ============================================================================
func _eq_on_kill(killer: Dictionary, _victim: Dictionary) -> void:
	for e in killer.get("equips", []):
		if str(e["id"]) == "p2eq_004":   # 暴君之牙: 处决后回40血
			_heal(killer, 40.0)
			_float_text(killer["pos"] + Vector2(0, -64), "处决!", Color("#ff6b6b"))

# ============================================================================
#  on-death (阵亡者视角) — 复活海螺 / 黄铜齿轮 / 玩偶小熊
# ============================================================================
func _eq_on_death(u: Dictionary, _killer) -> void:
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_033":   # 复活海螺: 阵亡→原位变小虫 (复用 _spawn_summon, 3D 用色块 block)
				var worm = _spawn_summon(u, "worm", [150.0, 200.0, 300.0][si] * HP_MULT, [20.0, 30.0, 40.0][si], {"label": "海螺虫", "col_size": 30.0, "hp_w": 22.0})
				if worm != null:
					worm["pos"] = u["pos"]
					if is_instance_valid(worm["sprite"]): worm["sprite"].position = _world_pos(u["pos"], GROUND_LIFT)
					worm["eq_state"] = {}; worm["equips"] = []
					if si == 2:   # 3★: 标记每周期分裂
						worm["worm_split"] = true
				_float_text(u["pos"] + Vector2(0, -40), "复活海螺!", Color("#c0ffd0"))
			"p2eq_035":   # 黄铜齿轮: 死亡→每层折2深海币 (仅玩家左队计入)
				var gears: int = int(stt.get("gears", 0))
				if gears > 0 and u["side"] == "left":
					var gs = get_node_or_null("/root/GameState")
					if gs != null and gs.get("meta_deepsea_coins") != null:
						gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + gears * 2)
			"p2eq_034":   # 玩偶小熊: 🚧 简化 — 阵亡时召唤大熊 (250生命/50攻击)
				var bear = _spawn_summon(u, "bear", 250.0 * HP_MULT, 50.0, {"label": "大熊", "col_size": 40.0, "hp_w": 30.0})
				if bear != null:
					bear["eq_state"] = {}; bear["equips"] = []

# ============================================================================
#  HP阈值 (首次<50%) — 深海项链 / 珍珠耳环
# ============================================================================
func _eq_check_hp_threshold(u: Dictionary) -> void:
	if u.get("hp50_fired", false) or u["hp"] > u["maxHp"] * 0.5 or not u["alive"]:
		return
	var fired := false
	for e in u.get("equips", []):
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		match iid:
			"p2eq_044":   # 深海项链: 首次<50%回血
				_heal(u, u["maxHp"] * [0.12, 0.27, 0.40][si]); fired = true
			"p2eq_045":   # 珍珠耳环: 首次<50%回血+发火球
				_heal(u, u["maxHp"] * [0.15, 0.29, 0.65][si])
				var balls: int = [1, 1, 2][si]
				var es := _enemies_of(u)
				for b in range(balls):
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_apply_damage_from(u, o, int(o["maxHp"] * [0.08, 0.17, 0.30][si]), Color("#ff7a33"), 0.0, true, true)
					_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
				fired = true
	if fired:
		u["hp50_fired"] = true

# ============================================================================
#  周期 tick (每 2.5 秒) — A类回合节拍效果
# ============================================================================
func _eq_tick(u: Dictionary, delta: float) -> void:
	u["eq_timer"] = u.get("eq_timer", 0.0) + delta
	if u["eq_timer"] < EQ_TICK:
		return
	u["eq_timer"] = 0.0
	for e in u["equips"]:
		var iid: String = str(e["id"]); var si: int = _eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_001":   # 锈蚀短剑: 每周期劈砍最近敌
				var t = _nearest_enemy(u)
				if t != null:
					_apply_damage_from(u, t, _atk_dmg(u, [0.6, 0.75, 1.0][si], t) + int([40, 60, 100][si] * u["crit"]), Color("#ffe08a"), 0.0, false, true)
			"p2eq_012":   # 龟苓膏块: 每周期自护盾
				_grant_shield(u, [30.0, 40.0, 55.0][si])
			"p2eq_016":   # 铁壁盾: 每周期全队(含自己)护盾
				for o in _allies_of(u):
					_grant_shield(o, [15.0, 20.0, 25.0][si])
			"p2eq_018":   # 守护贝壳: 每周期自回血
				_heal(u, [30, 45, 60][si] + u["maxHp"] * [0.05, 0.09, 0.15][si])
			"p2eq_019":   # 海葵药膏: 每周期奶自己+最低血友军
				_heal(u, [30, 45, 60][si] + (u["maxHp"] - u["hp"]) * [0.12, 0.14, 0.18][si])
				var low = _lowest_hp_ally(u)
				if low != null and low != u:
					_heal(low, [30, 45, 60][si] + (low["maxHp"] - low["hp"]) * [0.12, 0.14, 0.18][si])
			"p2eq_020":   # 哑铃: 每周期+锻炼层 + 向最近敌扔哑铃
				var gain: float = [20.0, 25.0, 30.0][si] * HP_MULT
				u["maxHp"] += gain; u["hp"] += gain
				var t2 = _nearest_enemy(u)
				if t2 != null:
					_apply_damage_from(u, t2, int(u["maxHp"] / HP_MULT * [0.05, 0.07, 0.10][si]), Color("#ffe08a"), 0.0, false, true)
			"p2eq_021":   # 守护贝母: 每周期连接攻击最高友军→给护盾+净化
				var best = null; var ba := -1.0
				for o in _allies_of(u):
					if o["atk"] > ba: ba = o["atk"]; best = o
				if best != null:
					_grant_shield(best, [40.0, 60.0, 90.0][si])
					best["dots"] = []; best["dot_stacks"] = {}
			"p2eq_024":   # 龙蛋: 每周期+1吐息, 满3→喷火龙直线扫射
				stt["dragon_stacks"] = int(stt.get("dragon_stacks", 0)) + 1
				if int(stt["dragon_stacks"]) >= 3:
					stt["dragon_stacks"] = 0
					_eq_dragon_breath(u, si)
			"p2eq_025":   # 雷鸣贝壳: 每周期降N道雷各电击随机敌
				for _d in range([1, 2, 3][si]):
					var es := _enemies_of(u)
					if es.is_empty(): break
					var o = es[randi() % es.size()]
					_bolt_line(Vector2(o["pos"].x, ARENA.position.y), o["pos"], Color("#bff0ff"))
					_apply_damage_from(u, o, int(u["atk"]), Color("#bff0ff"), 0.0, true, true)
			"p2eq_027":   # 电棍: 每周期电击随机敌+眩晕, 消耗1层
				if int(stt.get("baton_charges", 0)) > 0:
					var es2 := _enemies_of(u)
					if not es2.is_empty():
						stt["baton_charges"] = int(stt["baton_charges"]) - 1
						var o = es2[randi() % es2.size()]
						_apply_damage_from(u, o, [30, 40, 50][si], Color("#bff0ff"), 0.0, true, true)
						_freeze(o, EQ_TICK)
			"p2eq_035":   # 黄铜齿轮: 每周期+N层
				stt["gears"] = int(stt.get("gears", 0)) + [1, 2, 3][si]
			"p2eq_017":   # 不沉之锚: ⚠简化 — 每周期击飞+眩晕最近敌
				var at = _nearest_enemy(u)
				if at != null:
					_apply_damage_from(u, at, int([0.4, 0.6, 3.0][si] * (u["def"] + u["mr"]) + at["maxHp"] * [0.15, 0.25, 0.70][si]), Color("#9be7ff"), 0.0, false, true)
					_knockback(u, at, 60.0); _freeze(at, EQ_TICK)
			"p2eq_036":   # 温泉蛋: 孵化进度, 满100→全队均摊护盾(一次)
				stt["incub"] = float(stt.get("incub", 0.0)) + 5.0
				if float(stt["incub"]) >= 100.0 and not bool(stt.get("incub_given", false)):
					stt["incub_given"] = true
					var allies := _allies_of(u)
					var per: float = float(stt.get("incub_shield", 300.0)) / maxf(1.0, float(allies.size()))
					for o in allies:
						_grant_shield(o, per)
					_float_text(u["pos"] + Vector2(0, -70), "孵化!", Color("#ffe9a8"))
			"p2eq_042":   # 涟漪药剂: 每周期全队回已损血
				for o in _allies_of(u):
					_heal(o, (o["maxHp"] - o["hp"]) * [0.03, 0.06, 0.10][si])
			"p2eq_043":   # 海浪护符: 每周期+1巨浪层, 满→横排扫敌我
				stt["wave"] = int(stt.get("wave", 0)) + 1
				if int(stt["wave"]) >= [3, 2, 2][si]:
					stt["wave"] = 0
					for o in _allies_of(u):
						_grant_shield(o, [40.0, 95.0, 120.0][si]); o["base_def"] += [2, 3, 5][si]; o["base_mr"] += [2, 3, 5][si]; _recalc_stats(o)
					for o in _enemies_of(u):
						_apply_damage_from(u, o, [60, 110, 200][si], Color("#9be7ff"), 0.0, true, true)
						o["base_def"] = maxf(0.0, o["base_def"] - [2, 3, 5][si]); o["base_mr"] = maxf(0.0, o["base_mr"] - [2, 3, 5][si]); _recalc_stats(o)
			"p2eq_052":   # 左轮: 每周期向随机敌射1发, 子弹0停
				if int(stt.get("revolver_bullets", 0)) > 0:
					var es3 := _enemies_of(u)
					if not es3.is_empty():
						stt["revolver_bullets"] = int(stt["revolver_bullets"]) - 1
						var o = es3[randi() % es3.size()]
						_fire_bolt_from(u, o, _atk_dmg(u, [3.0, 5.0, 9.0][si], o) + [150, 310, 1200][si], Color("#ffd07a"))
			"p2eq_037":   # 蛋糕蜡烛: 3阶段循环
				var ph: int = int(stt.get("candle", 0))
				stt["candle"] = (ph + 1) % 3
				if ph == 1:   # 微弱: 回血
					_heal(u, [20, 30, 44][si] + u["atk"] * [0.5, 0.7, 1.0][si])
				elif ph == 2:   # 燃烧: 随机敌横排魔伤+灼烧
					var t3 = _nearest_enemy(u)
					if t3 != null:
						var dir: Vector2 = (t3["pos"] - u["pos"]).normalized()
						for o in _enemies_of(u):
							if _on_line(u["pos"], dir, o["pos"], 55.0):
								_apply_damage_from(u, o, [20, 30, 44][si] + int(u["atk"] * [0.5, 0.7, 1.0][si]), Color("#ff7a33"), 0.0, true, true)
								_apply_dot_stacks(o, "burn", [20, 30, 40][si], u)
			"p2eq_038":   # 信号放大器: 每周期刷新本回合增伤buff
				var lo: Array = [0.10, 0.25, 0.70]; var hi: Array = [0.16, 0.40, 0.80]
				var amp: float = randf_range(lo[si], hi[si])
				_buff(u, "atk", amp, true, EQ_TICK + 0.1)
			"p2eq_040":   # FPGA板: 每周期抽N个状态当回合生效
				for _k in range([1, 2, 4][si]):
					match randi() % 4:
						0: _heal(u, u["maxHp"] * 0.05); u["base_def"] += 2; u["base_mr"] += 2; _recalc_stats(u)
						1: u["base_atk"] += 5; u["lifesteal"] += 0.04; _recalc_stats(u)
						2: _buff(u, "atk", 0.15, true, EQ_TICK + 0.1)
						3: _buff(u, "def", 0.25, true, EQ_TICK + 0.1)
			"p2eq_056":   # 飞镖: 每周期向所有带"靶子"(被击飞)的敌各射1镖+流血
				for o in _enemies_of(u):
					if _t < o.get("eq_target_until", 0.0):
						o["eq_target_until"] = 0.0
						_fire_bolt_from(u, o, _atk_dmg(u, [1.5, 3.0, 9.0][si], o) + [130, 190, 600][si], Color("#ffd07a"))
						_apply_dot_stacks(o, "bleed", maxi(1, roundi(u["atk"] * 0.1)), u)
		u["eq_state"][iid] = stt
	# 复活海螺3★ 小虫分裂 (简化: worm 单位每周期空位分裂一只)
	if u.get("worm_split", false) and _count_summons(u["side"], "worm") < 4:
		var nw = _spawn_summon(u, "worm", u["maxHp"], u["atk"], {"label": "海螺虫", "col_size": 30.0, "hp_w": 22.0})
		if nw != null:
			nw["eq_state"] = {}; nw["equips"] = []; nw["worm_split"] = true

# 龙蛋喷火龙: 沿随机有敌的朝向直线扫射 (同列友回血/敌魔伤+灼烧)
func _eq_dragon_breath(u: Dictionary, si: int) -> void:
	var es := _enemies_of(u)
	if es.is_empty():
		return
	var anchor = es[randi() % es.size()]
	var dir: Vector2 = (anchor["pos"] - u["pos"]).normalized()
	_bolt_line(u["pos"], anchor["pos"] + dir * 200.0, Color("#ff7a33"))
	for o in _enemies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_apply_damage_from(u, o, _atk_dmg(u, [0.7, 1.0, 2.0][si], o) + [50, 120, 1500][si], Color("#ff7a33"), 0.0, true, true)
			_apply_dot_stacks(o, "burn", _default_burn_stacks(u), u)
	for o in _allies_of(u):
		if _on_line(u["pos"], dir, o["pos"], 60.0):
			_heal(o, _atk_dmg(u, [0.7, 1.0, 2.0][si], o) + [70, 150, 1000][si])
