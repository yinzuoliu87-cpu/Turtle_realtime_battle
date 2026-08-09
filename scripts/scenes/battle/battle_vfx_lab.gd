# 不用 class_name: 需 --import 注册后才可用, 宿主改用 preload 常量引用(同 map_editor.gd)。
extends Node

## ════════════════════════════════════════════════════════════════════════════
##  🔬 特效调试台 VFXLAB —— 干净黑场 + 可控相机 + 逐件配置 + 定时自截图
##  (dev-only 开发工具, 全程 `OS.has_environment("VFXLAB")` 闸, 正式对局零影响)
## ════════════════════════════════════════════════════════════════════════════
##
## ── 为什么有它 ────────────────────────────────────────────────────────────
## 以前看特效是拿 1280×720 全场截图, 在一堆海草/礁石/血条/徽章里找那几个像素,
## 然后眯着眼判断。**低效而且判断不可靠** —— 上一轮就因此把地图上的绿色海草装饰
## 误判成了 091 的甲片, 写了一整条错的结论。
## 这个台子的目的是**让判断变得可靠**: 场上只剩单位、特效、弹道; 镜头能真的推到脸上。
##
## ── 一条命令跑一件 ────────────────────────────────────────────────────────
## ```bash
## VFXLAB=1 VFXLAB_CASE=p2eq_089 \
##   "/c/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe" \
##   --path . res://scenes/RealtimeBattle3D.tscn
## ```
## ★**不能加 `--headless`** —— 无头没有真实渲染, 截出来是空图**而且不报错**。
## 拍完自动退出; 截图默认存 `res://_vfxlab_<case>_<i>.png`(已进 .gitignore)。
##
## ── 环境变量 ──────────────────────────────────────────────────────────────
## | 变量 | 作用 |
## |---|---|
## | `VFXLAB=1` | 总开关 |
## | `VFXLAB_CASE=<id>` | 跑哪一件。`list` = 打印已登记的 case 后退出 |
## | `VFXLAB_ZOOM=<倍数>` | 覆盖配置表的相机倍数。**真拉近**(改 fov), 不是截图后放大 |
## | `VFXLAB_FOCUS=carrier\|enemy\|ally\|summon\|mid\|point` | 镜头锁谁 |
## | `VFXLAB_FOCUS_XY=x,y` | `focus=point` 时的场地坐标 |
## | `VFXLAB_TEXT=1` | 显示伤害飘字(默认全关 —— 数字常常正好挡住要看的特效) |
## | `VFXLAB_GRID=1` | 地上铺 100 码网格(量特效尺寸用; 默认关, 免得干扰读形状) |
## | `VFXLAB_SHAKE=1` | 保留震屏(默认压掉 —— 高倍数下震屏会把画面甩飞) |
## | `VFXLAB_SPEED=<倍>` | `Engine.time_scale`。0.25 = 慢动作细看 |
## | `VFXLAB_SHOTS=t1,t2,…` | 覆盖拍摄时刻(**游戏秒**) |
## | `VFXLAB_OUT=<前缀>` | 截图路径前缀(默认 `res://_vfxlab_<case>`) |
## | `VFXLAB_HOLD=1` | 不拍不退, 挂着让人自己看(窗口摆到屏幕右侧垂直居中) |
##
## ★★★跑法铁律(用户 2026-08-07 明令):【命令行必须加 `--position 5000,5000`】把窗口挪到屏幕外。
##   多路 agent 并行时窗口会互相抢焦点、糊满用户的屏幕, 他没法工作。
##   ★挪到屏幕外【不影响截图】—— `SELFSHOT` 抓的是**视口纹理**
##   (`get_viewport().get_texture().get_image()`), 不是屏幕截图, 只要窗口在渲染就行,
##   不需要它出现在人眼前。实测: 1280x720 满画面、非黑像素 100%。
##   ⚠ `--headless` 仍然不行 —— 那个是真的不渲染, 截出来是空的**而且不报错**。
##   ⚠ `VFXLAB_HOLD=1` 是【专门开给用户看】的模式, 只有主会话在用户在场时才用; agent 一律不要用。
## | `VFXLAB_STAR` `VFXLAB_CARRIER` `VFXLAB_DUR` | 覆盖配置表对应字段 |
##
## ── 它怎么复用现有东西(而不是重写一套) ──────────────────────────────────
## · **单位摆放**: 完全走 `EQDEMO_*` 那条老路 —— 台子在建场之前把配置表翻译成
##   `EQDEMO_EQUIP / _STAR / _CARRIER / _ALLIES / _ENEMIES / _ENEMY_ATTACKS / …` 环境变量,
##   然后 `battle_spawn._spawn_teams()` 照常跑。**一行摆位逻辑都没有重写。**
## · **满龟能**: 复用调试场的 `battle._debug._edit_apply_full_energy`。
## · **法力条**: 走法器羁绊真实入口 `battle._staff_syn.add_mana` —— 灌满就真的触发,
##   不是伪造一个"看起来放了"的演出(memory [[fb-verify-must-run-the-real-path]])。
## · **黑场**: 复用已有的 `BLACKMAP` env(环境背景纯黑), 地面/装饰/远景那一层
##   由 `battle_world_builder._build_ground` 的 VFXLAB 闸直接不建。
## · **自截图**: 复用 `_self_screenshot` 的机制(`await RenderingServer.frame_post_draw`
##   + `get_viewport().get_texture().get_image()`), 只是排程换成"按游戏秒的时刻列表"。
##
## ── 每次开台都会打一份【场上花名册】 ────────────────────────────────────
## 每个单位的 `id / 阵营 / 场地坐标 / hp / 有没有立绘`。看图时**对着名单认人, 不靠猜** ——
## "上一轮把海草当成甲片"的根因就是靠猜。`spr=✗` 的行尤其要看:
## 那是**没有美术的召唤物**, 会被渲染成一个白色发光球, 极容易被误读成"某个特效"。
##
## ── 五条踩过的坑, 已经写进代码里 ────────────────────────────────────────
## 1. **相机每帧被写回**: `battle_render._update_camera_shake` 每帧无条件
##    `_cam.position = _cam_zoom_base`。所以镜头不能只设一次, 必须每帧写 `_cam_zoom_base`。
## 2. **`_t` 会冻结**: 战斗判定结束后 `_sim_step` 不再 `_t += dt`(CLAUDE.md §3.5)。
##    拍摄排程用游戏秒, 但**另挂一条墙钟看门狗** —— 卡住就把剩下的拍完退出,
##    而不是永远挂在那里。
## 3. **血条每帧会自己显回来**: `_update_overlay` 每帧按存活重设 `bar_root.visible`,
##    所以"藏 UI"必须每帧做一次, 设一次没用。
## 4. **光标会进截图**: 它不是系统光标, 是 `CursorTheme` 自绘的绿龟爪(CanvasLayer 4096),
##    `MOUSE_MODE_HIDDEN` 关不掉。见 `_hide_cursor`。
## 5. **`EQDEMO` 的敌人距离本来不准**: 敌人坐标相对"评审居中位"算, 而携带者在不带友军时
##    走的是通用出生位 ⇒ 实测差了一倍多。台子自己重摆阵型(见 `_relayout_units`),
##    让配置表里的 `enemy_dist` 真的等于"隔多少码"。

const VfxLabCases := preload("res://scripts/gamedata/vfxlab_cases.gd")

## 相机 fov 下限。Godot 允许到 1°, 留一点余量防浮点抖。
const FOV_MIN := 1.2
const FOV_MAX := 90.0
## 看门狗: 游戏钟停滞超过这么多墙钟秒 ⇒ 判定"推不动了", 把剩余拍摄立刻补完再退。
const STALL_WALL_SEC := 6.0

var battle
var cfg: Dictionary = {}

var _fov0 := 40.0                  # 建场时的原始 fov(zoom 的基准)
var _cam_off := Vector3.ZERO       # 相机相对焦点的固定偏移(= 默认机位 − 默认注视点)
var _zoom := 4.0
var _focus := "carrier"
var _focus_xy := Vector2.ZERO
var _focus_h := 1.0
var _text_on := false
var _keep_shake := false
var _ui_snapshot: Array = []       # post_spawn 时 _ui_layer 已有的子节点(每帧压回 hidden)
var _shots: Array = []
var _out_prefix := ""
var _hold := false
var _armed := false                # post_spawn 跑过了没(没跑过 _process 什么都别做)


func _init(b) -> void:
	battle = b
	name = "VfxLab"


# ════════════════════════════════════════════════════════════════════════════
#  ① 建场【之前】: 把配置表翻译成 EQDEMO_* 环境变量
#     —— 必须在 _build_environment / _spawn_teams 之前, 它们是读 env 的
# ════════════════════════════════════════════════════════════════════════════
## 返回 false = 【不要继续建场】(VFXLAB_CASE=list: 只打一份清单就退)。
func pre_build() -> bool:
	var case_id: String = OS.get_environment("VFXLAB_CASE") if OS.has_environment("VFXLAB_CASE") else ""
	if case_id == "" or case_id == "list":
		print("[VFXLAB] 已登记的 case:")
		for i in VfxLabCases.ids():
			var c: Dictionary = VfxLabCases.get_case(str(i))
			print("  %-18s ★%d  %s" % [str(i), int(c["star"]), str(c["note"])])
		print("[VFXLAB] 用法: VFXLAB=1 VFXLAB_CASE=p2eq_089 godot --path . res://scenes/RealtimeBattle3D.tscn")
		battle.get_tree().quit()
		return false
	cfg = VfxLabCases.get_case(case_id)
	# ── env 覆盖(临场调参不用改表) ──
	if OS.has_environment("VFXLAB_STAR"):    cfg["star"] = int(OS.get_environment("VFXLAB_STAR"))
	if OS.has_environment("VFXLAB_TIER"):    cfg["tier"] = int(OS.get_environment("VFXLAB_TIER"))
	if OS.has_environment("VFXLAB_CARRIER"): cfg["carrier"] = OS.get_environment("VFXLAB_CARRIER")
	if OS.has_environment("VFXLAB_ZOOM"):    cfg["zoom"] = float(OS.get_environment("VFXLAB_ZOOM"))
	if OS.has_environment("VFXLAB_FOCUS"):   cfg["focus"] = OS.get_environment("VFXLAB_FOCUS")
	if OS.has_environment("VFXLAB_DUR"):     cfg["dur"] = float(OS.get_environment("VFXLAB_DUR"))
	if OS.has_environment("VFXLAB_FOCUS_XY"):
		var parts: PackedStringArray = OS.get_environment("VFXLAB_FOCUS_XY").split(",")
		if parts.size() >= 2:
			cfg["focus_xy"] = Vector2(float(parts[0]), float(parts[1]))
	if OS.has_environment("VFXLAB_SHOTS"):
		var sl: Array = []
		for s in OS.get_environment("VFXLAB_SHOTS").split(","):
			if str(s).strip_edges() != "":
				sl.append(float(str(s).strip_edges()))
		cfg["shots"] = sl

	_zoom = maxf(0.2, float(cfg.get("zoom", 4.0)))
	_focus = str(cfg.get("focus", "carrier"))
	_focus_xy = cfg.get("focus_xy", Vector2.ZERO)
	_focus_h = float(cfg.get("focus_h", 1.0))
	_text_on = OS.has_environment("VFXLAB_TEXT")
	_keep_shake = OS.has_environment("VFXLAB_SHAKE")
	_shots = (cfg.get("shots", []) as Array).duplicate()
	_hold = OS.has_environment("VFXLAB_HOLD") or _shots.is_empty()
	_out_prefix = OS.get_environment("VFXLAB_OUT") if OS.has_environment("VFXLAB_OUT") else ("res://_vfxlab_" + case_id)

	# ── 翻译成 EQDEMO_*: 摆位这条路一行都不重写 ──
	OS.set_environment("EQDEMO_EQUIP", str(cfg["eq"]))
	OS.set_environment("EQDEMO_STAR", str(int(cfg["star"])))
	OS.set_environment("EQDEMO_CARRIER", str(cfg["carrier"]))
	OS.set_environment("EQDEMO_ENEMIES", str(maxi(1, int(cfg["enemies"]))))
	OS.set_environment("EQDEMO_DUMMYHP", str(float(cfg["enemy_hp"])))
	OS.set_environment("EQDEMO_ENEMY1", str(float(cfg["enemy_dist"])))
	OS.set_environment("EQDEMO_GAP", str(float(cfg["enemy_gap"])))
	if int(cfg["allies"]) > 0:
		OS.set_environment("EQDEMO_ALLIES", str(int(cfg["allies"])))
	if bool(cfg["enemy_attacks"]):
		OS.set_environment("EQDEMO_ENEMY_ATTACKS", "1")
	if bool(cfg["attacker"]):
		OS.set_environment("EQDEMO_ATTACKER", "1")
	if str(cfg.get("eq2", "")) != "":
		OS.set_environment("EQDEMO_EQUIP2", str(cfg["eq2"]))   # ★第二件【不同】装备: 凑羁绊档位
	OS.set_environment("BLACKMAP", "1")     # 环境背景纯黑(复用已有 env)
	OS.set_environment("NO_TRAINER", "1")   # 场外监视者是干扰项, 不要

	if OS.has_environment("VFXLAB_SPEED"):
		Engine.time_scale = maxf(0.02, float(OS.get_environment("VFXLAB_SPEED")))

	print("[VFXLAB] case=%s%s eq=%s%s ★%d carrier=%s allies=%d enemies=%d attack=%s hit_back=%s zoom=%.1f focus=%s" % [
		case_id, ("" if bool(cfg.get("_registered", false)) else "(未登记·缺省配置)"),
		str(cfg["eq"]), ("+" + str(cfg["eq2"]) if str(cfg.get("eq2", "")) != "" else ""),
		int(cfg["star"]), str(cfg["carrier"]), int(cfg["allies"]), int(cfg["enemies"]),
		str(bool(cfg["attacker"])), str(bool(cfg["enemy_attacks"])), _zoom, _focus])
	print("[VFXLAB] note: %s" % str(cfg.get("note", "")))
	return true


## 给我方装一档羁绊。★没有它, **金弹这一整条机制在台上永远不会触发** ——
## `_queue_shots` 的金弹计数只在 `tier_for(src, "枪") > 0` 时才走, 而台子默认零羁绊。
## 079 的招牌机制就是"金弹时回血翻倍", 台上看不到金弹 = 这件装备的看点根本没上演。
## (2026-08-08 补: 之前逐件评审 077/078/079/080 全程都没看过金弹, 就是缺这一行。)
func _apply_tier() -> void:
	var t: int = int(cfg.get("tier", 0))
	if t <= 0:
		return
	var syn: String = str(cfg.get("tier_syn", "枪"))
	battle._synergy._by_side["left"] = {syn: t}
	print("[VFXLAB] 羁绊: 我方 %s %d 档 ⇒ 金弹每 %d 发出一次" % [syn, t, [4, 3, 2][clampi(t - 1, 0, 2)]])


# ════════════════════════════════════════════════════════════════════════════
#  ② 建场 + spawn【之后】: 清场 / 改单位 / 摆相机 / 开拍
# ════════════════════════════════════════════════════════════════════════════
func post_spawn() -> void:
	if cfg.is_empty():
		return
	_build_dark_floor()
	if OS.has_environment("VFXLAB_GRID"):
		_build_grid()
	_hide_ui_once()
	_relayout_units()
	_tune_units()
	_apply_tier()
	# 相机: 记下原始 fov 与"机位相对注视点"的固定偏移 —— 之后每帧只平移这个刚体, 不再 look_at
	if battle._cam != null and is_instance_valid(battle._cam):
		_fov0 = float(battle._cam.fov)
		_cam_off = battle._cam_base - battle.CAM_TARGET
	_hide_cursor()
	_print_roster()
	_armed = true
	_apply_camera()
	if _hold:
		_place_window_right_middle()
		print("[VFXLAB] HOLD 模式: 不拍不退。Ctrl+C / 关窗口结束。")
	else:
		_shot_loop()


# ── 暗地板: 给贴地特效一个参照面, 又不像正式地图那样有装饰/水域/礁石干扰 ──
## ★不是"把地图调暗", 是**根本不建**(`_build_ground` 里 VFXLAB 直接 return),
##   然后在这里放一张自己的板。这样 tile/装饰/远景/光柱/氛围粒子一个都不会出现。
func _build_dark_floor() -> void:
	if battle._world == null or not is_instance_valid(battle._world):
		return
	var mi := MeshInstance3D.new()
	mi.name = "VfxLabFloor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(battle.ARENA.size.x * battle.WS * 2.4 + 200.0,
					  battle.ARENA.size.y * battle.WS * 2.4 + 200.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.050, 0.053, 0.070)   # 近黑但不是纯黑 —— 纯黑分不出"有没有地面"/贴地特效贴在哪
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.02, 0.0)   # 略沉: 贴地特效(环 0.05 / 影 0.02)全在它上面, 不 z-fight
	battle._world.add_child(mi)


# ── 100 码网格(VFXLAB_GRID=1): 量特效尺寸用 ──
## ★为什么默认关: 它本身就是画面干扰。要"读形状"时关着, 要"量多大"时打开。
func _build_grid() -> void:
	if battle._world == null or not is_instance_valid(battle._world):
		return
	var root := Node3D.new()
	root.name = "VfxLabGrid"
	battle._world.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.20, 0.26)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var step := 100.0                       # 100 场地像素 = 100 码
	var a: Rect2 = battle.ARENA
	var thick := 0.012
	var x := a.position.x
	while x <= a.end.x:
		var bx := MeshInstance3D.new()
		var mx := BoxMesh.new()
		mx.size = Vector3(thick, 0.004, a.size.y * battle.WS)
		bx.mesh = mx
		bx.material_override = mat
		bx.position = battle._world_pos(Vector2(x, a.position.y + a.size.y * 0.5), 0.001)
		root.add_child(bx)
		x += step
	var y := a.position.y
	while y <= a.end.y:
		var bz := MeshInstance3D.new()
		var mz := BoxMesh.new()
		mz.size = Vector3(a.size.x * battle.WS, 0.004, thick)
		bz.mesh = mz
		bz.material_override = mat
		bz.position = battle._world_pos(Vector2(a.position.x + a.size.x * 0.5, y), 0.001)
		root.add_child(bz)
		y += step


# ── 藏 UI ──
## 默认: 整个 `_ui_layer` 直接 `visible=false` —— 血条/徽章/PK 条/按钮/队伍面板/飘字全没。
## `VFXLAB_TEXT=1`: 层留着(飘字要它), 改成**逐个藏**已有的 UI, 每帧还要压一次(见 _process)。
## ★"关的方式要可靠" = 不是把它们移出屏幕, 是真的不显示。
## ★`cfg["ui"] = true` / `VFXLAB_UI=1`: **保留 UI 层**。
##   由来(2026-08-08 用户:「充能条和层数不要放头顶, 在装备图标框里」):
##   充能进度与层数的正规出口是**头像下的装备格**(PANEL_CHARGE / PANEL_COUNT),
##   那是 UI。台子默认把 UI 全关(黑场只留特效), 于是这两件装备的核心读数
##   **在台子上永远看不到** —— 台子的判据反而挡住了要评审的东西。
func _hide_ui_once() -> void:
	if battle._ui_layer == null or not is_instance_valid(battle._ui_layer):
		return
	if bool(cfg.get("ui", false)) or OS.has_environment("VFXLAB_UI"):
		# ★不是"整层 UI 全开" —— 那样 VS 条/血条/飘字全回来了, 台子就不是干净黑场。
		#   只留**队伍面板**(装备图标框在它里面)。
		# ★★做法是【整层关掉 + 把面板搬到独立层】, 不是"逐个隐藏其余子节点":
		#   本函数只跑一次, 而单位血条/伤害飘字是**之后**才挂进 _ui_layer 的 ——
		#   逐个隐藏漏得掉它们(第一版实拍里血条和飘字确实还在)。整层 visible=false 才管得住后来的。
		battle._ui_layer.visible = false
		var keep := CanvasLayer.new()
		keep.name = "VFXLabKeepUI"
		keep.layer = battle._ui_layer.layer + 1
		battle.add_child(keep)
		for pn in [battle._team_panel_left, battle._team_panel_right]:
			if pn != null and is_instance_valid(pn) and pn.get_parent() != null:
				pn.get_parent().remove_child(pn)
				keep.add_child(pn)
		return
	if not _text_on:
		battle._ui_layer.visible = false
		return
	_ui_snapshot.clear()
	for c in battle._ui_layer.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
			_ui_snapshot.append(c)


# ── 重新摆位: 把整个阵型摆到场地正中, 并让 enemy_dist 真的等于"敌人离携带者多少码" ──
##
## ★★这一条是台子跑起来第一分钟就被花名册抓出来的**既有坑**(不是台子引入的):
##   `EQDEMO` 的敌人坐标写的是 `_cx - 150 + ENEMY1`(相对"评审居中位"),
##   而携带者只有在 `left.size() > 1`(带了友军)时才真的被摆到 `_cx - 250`;
##   **一个友军都不带时**携带者走的是通用出生位 `ARENA.position + (150, 100)` = (220, 210)。
##   ⇒ 实测 077: 携带者 (220,210) / 假人 (1138,474), **相隔 918 码而不是配置里写的 420**,
##     小手枪的 700 码射程根本够不着, 它得先跑过去 —— 而这在画面上看着就像"枪不开火"。
##
## ⇒ 台子自己把坐标钉死: 阵型中心 = 场地中心, 携带者在左、敌人依次在右。
##   ★仍然复用 `_spawn_teams` 造好的单位(装备注入/登场被动/羁绊全都跑过了),
##     这里**只改 pos** —— 不是另写一套 spawn。
##   ★左队整体按同一个位移平移(不是逐个摆) ⇒ 已经生成好的召唤物(小手枪/炮台/浮游炮)
##     与携带者的相对位置原样保住, 不会被摆到别处去。
func _relayout_units() -> void:
	var carrier = _first(func(u): return u.get("_eqdemo_carrier", false))
	if carrier == null:
		return
	var n_en: int = maxi(1, int(cfg.get("enemies", 1)))
	var dist: float = float(cfg.get("enemy_dist", 260.0))
	var gap: float = float(cfg.get("enemy_gap", 420.0))
	var span: float = dist + float(n_en - 1) * gap
	var cx: float = battle.ARENA.position.x + battle.ARENA.size.x * 0.5
	var cy: float = battle.ARENA.position.y + battle.ARENA.size.y * 0.5
	var anchor := Vector2(clampf(cx - span * 0.5, battle.ARENA.position.x + 80.0, battle.ARENA.end.x - 80.0), cy)
	var delta: Vector2 = anchor - Vector2(carrier["pos"])
	var ai := 0
	## ★★假人默认【不放技能】(2026-08-09)。由来: 090 浪潮台上携带者 14 秒只普攻 2 次,
	##   探针查出是 `_sk_basic_strike` —— **假人是 basic 龟, 它自己放技能把携带者眩晕了 1.65 秒**,
	##   眩晕期间不能普攻 ⇒ 凑不齐"第三下" ⇒ 浪潮一次都不触发, 而我差点判成"演出没做"。
	##   `enemy_attacks` 只管普攻, 管不住技能 —— 这是两回事。
	##   想看假人放技能的用例, 在 case 里写 `enemy_skills: true`。
	if not bool(cfg.get("enemy_skills", false)):
		for su in battle._units:
			if su is Dictionary and not (su as Dictionary).get("_eqdemo_carrier", false):
				## ⚠ 只锁 `energy_lock_until` **不够** —— 那道闸挡的是"龟能继续充",
				##   而假人**开局就带能量**, 照样立刻放得出来(实测: 锁了之后携带者仍在 t=0.77
				##   被 `_sk_basic_strike` 眩晕 1.65 秒)。⇒ 直接把主动技能表清空, 从源头断掉。
				su["active_skills"] = []
				su["energy_lock_until"] = 1.0e9
	## ★`carrier_silent`: 连**携带者自己的**主动技也关掉。由来(2026-08-09): 090 的浪潮靠
	##   "每第三次普攻"触发, 而携带者是 basic 龟 —— 它的 `_sk_basic_strike` 第一行就是
	##   `_stun(u, 1.65, ...)`【全程定身自己】, 能量一满就把自己钉 1.65 秒 ⇒ 14 秒只普攻 2 次,
	##   浪潮一次都发不出来。这是**产品的正确行为**, 错在台子: 要看的是装备的浪潮, 不是龟的技能。
	if bool(cfg.get("carrier_silent", false)):
		for cu in battle._units:
			if cu is Dictionary and (cu as Dictionary).get("_eqdemo_carrier", false):
				cu["active_skills"] = []
				cu["energy_lock_until"] = 1.0e9
	var ei := 0
	for u in battle._units:
		if not (u is Dictionary):
			continue
		if str(u.get("side", "")) == "left":
			if u.get("_eqdemo_carrier", false) or u.get("is_summon", false):
				u["pos"] = _clamp_arena(Vector2(u["pos"]) + delta)     # 携带者与它的召唤物: 整体平移
			else:
				ai += 1
				u["pos"] = _clamp_arena(anchor + Vector2(-170.0, (-1.0 if ai % 2 == 1 else 1.0) * 150.0 * ceilf(float(ai) * 0.5)))
		else:
			u["pos"] = _clamp_arena(anchor + Vector2(dist + float(ei) * gap, 0.0))
			ei += 1
		# ★`_home_pos` **只在它本来就存在时才写**(memory [[fb-home-pos-only-if-exists]]):
		#   凭空创建这个键会激活"每帧拖回原位"的评审假人归位, 把单位永久钉死。
		if u.has("_home_pos"):
			u["_home_pos"] = u["pos"]


func _clamp_arena(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, battle.ARENA.position.x + 30.0, battle.ARENA.end.x - 30.0),
				   clampf(p.y, battle.ARENA.position.y + 30.0, battle.ARENA.end.y - 30.0))


# ── 按配置改单位: 携带者血量 / 可死 / 满龟能 ──
func _tune_units() -> void:
	var hp_pct: float = clampf(float(cfg.get("carrier_hp", 1.0)), 0.01, 1.0)
	var mortal: bool = bool(cfg.get("mortal", false))
	var fast_e: bool = bool(cfg.get("fast_energy", false))
	for u in battle._units:
		if not (u is Dictionary) or not u.get("_eqdemo_carrier", false):
			continue
		if mortal:
			# ★`battle_spawn` 的携带者分支写死 `deathfloor_until = 999999`(携带者永不死) ——
			#   094 这类"死了才生效"的件必须把它擦掉, 否则永远看不到效果, 而且不报错。
			u.erase("deathfloor_until")
			u.erase("_review_dummy")
		# ★`aspd` 覆盖携带者攻速(倍数)。由来(2026-08-08): 090 的浪潮是**每第三次普攻**才发,
		#   而探针实测携带者 18 秒只普攻了 4 次(t=3.80/5.43/7.07/10.67, 第一拳还要等到 3.8 秒
		#   —— 因为 mana_kick 让它开局就跳起来砸, 放技能期间不能普攻) ⇒ 全程只有 1 片浪潮,
		#   还正好落在两个拍点中间。**台子配错了, 不是特效坏了。**
		#   同 079 那条"allies=1 是必须的": 触发条件没配对, 就会把"没看见"读成"没做"。
		var aspd_k: float = float(cfg.get("aspd", 0.0))
		if aspd_k > 0.0:
			# ⚠ 写 `atk_interval` 没用 —— `_recalc_stats` 会按基础值重算把它冲掉(实测改完仍是 5 拳/14 秒)。
			#   攻速的正确入口是 **`aspd_perm`**(永久攻速乘子), 079 的 `carrier_aps` 就是按它算的。
			u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) * aspd_k
			battle._recalc_stats(u)
		if hp_pct < 1.0:
			u["hp"] = float(u["maxHp"]) * hp_pct
			battle._equip_sys._eq_check_hp_threshold(u)   # 走真实阈值入口(044/045 这类救命件靠它)
		if fast_e:
			# 复用调试场的满龟能(技能即就绪 + 回充 ×4)。它读 battle._edit_full_energy, 先打开。
			battle._edit_full_energy = true
			battle._debug._edit_apply_full_energy(u)


# ════════════════════════════════════════════════════════════════════════════
#  ③ 每帧: 相机 / 压震屏 / 压 UI
# ════════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	if not _armed:
		return
	_apply_camera()
	if not _keep_shake:
		battle._shake_amp = 0.0     # 高倍数下震屏会把画面整个甩出去
	if _text_on:
		_repress_ui()


## 藏光标。★`Input.MOUSE_MODE_HIDDEN` **不够** —— 本项目的光标不是系统光标,
## 是 `autoload/CursorTheme.gd` 自绘的一只绿龟爪(顶层 CanvasLayer, layer=4096),
## 它会**画进视口**因而进截图。台子第一版就在图上留了一坨绿色小方块,
## 而 memory 里正好记着「截图里神秘绿像素块 = 绿龟爪光标, 非 bug 别排查」——
## 这正是本台子要根治的那类"看到一个东西靠猜它是什么"。
func _hide_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	var ct = battle.get_node_or_null("/root/CursorTheme")
	if ct == null:
		return
	for c in ct.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false


## 场上花名册 —— **这条是台子的核心价值之一, 不是日志噪音**。
##
## ★上一轮那条错结论(把地图上的绿色海草当成 091 的甲片)的根因就是
##   「看到一个东西, 靠猜它是什么」。黑场解决了"背景里有杂物", 但没解决"画面上这一坨是谁"。
##   把每个单位的 id / 阵营 / 场地坐标 / **有没有立绘** 打出来, 看图时就是对着名单认人,
##   而不是猜。`spr=✗` 尤其重要 —— 没有立绘的召唤物会被渲染成一个白色发光球
##   (`battle_spawn._spawn_summon` 的 else 分支), 看图时极容易被当成"某个特效"。
func _print_roster() -> void:
	print("[VFXLAB] ── 场上花名册 (场地坐标, 与 ARENA %s 同口径) ──" % str(battle.ARENA))
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var tag := ""
		if u.get("_eqdemo_carrier", false): tag = "携带者"
		elif u.get("is_summon", false): tag = "召唤物:" + str(u.get("summon_kind", "?"))
		elif str(u.get("side", "")) == "right": tag = "假人"
		else: tag = "友军"
		# ★不能只看 `sprite.texture != null` —— 没有立绘的召唤物**也有** texture,
		#   `_spawn_summon` 的 else 分支给它塞了 `VfxTex._make_fire_glow_tex()`(队色发光球)。
		#   真正的判据是**帧字典里有没有图**(`idle_sd.tex`), 那才是"有没有美术"。
		var has_art: bool = (u.get("idle_sd", {}) as Dictionary).get("tex", null) != null
		print("    %-14s %-10s %-5s pos=(%.0f, %.0f)  hp=%.0f/%.0f  spr=%s" % [
			tag, str(u.get("id", "?")), str(u.get("side", "")),
			float(u["pos"].x), float(u["pos"].y),
			float(u.get("hp", 0.0)), float(u.get("maxHp", 0.0)),
			("✓" if has_art else "✗ 无立绘(渲染成队色发光球)")])


## ★这一段每帧都要做, 不能只做一次:
##   · `_update_overlay` 每帧按存活重设 `bar_root.visible`
##   · 头顶徽章(叠层/状态行)是**用到才建**的, 建出来默认可见
func _repress_ui() -> void:
	for c in _ui_snapshot:
		if is_instance_valid(c):
			(c as CanvasItem).visible = false
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var br = u.get("bar_root", null)
		if is_instance_valid(br):
			br.visible = false
		for k in ["_hbrow_stack", "_hbrow_status"]:
			for b in (u.get(k, []) as Array):
				if is_instance_valid(b):
					b.visible = false


## 真·拉近: 改 fov(等效长焦), **不是**把截图放大。
## ★为什么用 fov 而不是把相机推近:
##   推近会撞近裁剪面、透视变形、贴地特效被地板切; 长焦既不动机位又更"平",
##   读形状反而更准。fov 最低 1.2° ⇒ 最大约 35 倍, 够把 10 像素的东西撑满半屏。
func _apply_camera() -> void:
	if battle._cam == null or not is_instance_valid(battle._cam):
		return
	var f: Vector2 = _focus_point()
	var w: Vector3 = battle._world_pos(f, _focus_h)
	# ★必须写 `_cam_zoom_base` —— `battle_render._update_camera_shake` 每帧
	#   无条件 `_cam.position = _cam_zoom_base`, 只写 `_cam.position` 下一帧就被冲掉。
	battle._cam_zoom_base = w + _cam_off
	battle._cam.position = battle._cam_zoom_base
	battle._cam.fov = clampf(
		rad_to_deg(2.0 * atan(tan(deg_to_rad(_fov0 * 0.5)) / _zoom)), FOV_MIN, FOV_MAX)


func _focus_point() -> Vector2:
	match _focus:
		"point":
			return _focus_xy
		"enemy":
			var e = _first(func(u): return str(u.get("side", "")) == "right" and not u.get("is_summon", false))
			return Vector2(e["pos"]) if e != null else battle._arena_center
		"ally":
			var a = _first(func(u): return str(u.get("side", "")) == "left" and not u.get("_eqdemo_carrier", false) and not u.get("is_summon", false) and not u.get("is_trainer", false))
			return Vector2(a["pos"]) if a != null else _carrier_pos()
		"summon":
			var s = _first(func(u): return u.get("is_summon", false) and str(u.get("side", "")) == "left")
			return Vector2(s["pos"]) if s != null else _carrier_pos()
		"mid":
			var m = _first(func(u): return str(u.get("side", "")) == "right" and not u.get("is_summon", false))
			return (_carrier_pos() + Vector2(m["pos"])) * 0.5 if m != null else _carrier_pos()
		_:
			return _carrier_pos()


## ★携带者死了也照样返回它最后的位置 —— 094 的碑就立在那儿, 镜头不能跟着丢。
func _carrier_pos() -> Vector2:
	var c = _first(func(u): return u.get("_eqdemo_carrier", false))
	return Vector2(c["pos"]) if c != null else battle._arena_center


func _first(pred: Callable):
	for u in battle._units:
		if u is Dictionary and bool(pred.call(u)):
			return u
	return null


# ════════════════════════════════════════════════════════════════════════════
#  ④ 拍摄: 按【游戏秒】排程 + 墙钟看门狗
# ════════════════════════════════════════════════════════════════════════════
## ★为什么排程用游戏钟而看门狗用墙钟(CLAUDE.md §3.5 的两面):
##   · "第 4 秒的画面"说的是**战斗第 4 秒** ⇒ 只有 `battle._t` 是对的尺子
##     (`create_timer` 走未钳制 delta, `Engine.time_scale` 一改就全错)
##   · 但 `_t` 在战斗判定结束后**直接冻结** ⇒ 光靠它会永远挂着。
##     所以另拿墙钟盯着: 游戏钟 STALL_WALL_SEC 秒没动 ⇒ 把剩下的拍完立刻退。
func _shot_loop() -> void:
	# 灌法力: 走真实入口, 满了就真的触发那件法器(不是伪造演出)
	var kick: float = float(cfg.get("mana_kick", 0.0))
	if kick > 0.0:
		var kw: int = Time.get_ticks_msec()
		while battle._t < 1.0 and Time.get_ticks_msec() - kw < int(STALL_WALL_SEC * 1000.0):
			await get_tree().process_frame   # ★墙钟兜底: `_t` 可能根本不推进(战斗已判定结束), 不能死等
		for u in battle._units:
			if u is Dictionary and u.get("_eqdemo_carrier", false):
				battle._staff_syn.add_mana(u, kick)
				print("[VFXLAB] mana_kick %.0f → 法器档=%d" % [kick, int(battle._staff_syn.tier_of(u))])
				break

	var idx := 0
	for t in _shots:
		var want: float = float(t)
		var last_t: float = battle._t
		var last_wall: int = Time.get_ticks_msec()
		while battle._t < want:
			await get_tree().process_frame
			if absf(battle._t - last_t) > 0.0005:
				last_t = battle._t
				last_wall = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - last_wall > int(STALL_WALL_SEC * 1000.0):
				print("[VFXLAB] ⚠ 游戏钟停滞(t=%.2f, 目标 %.2f) —— 补拍剩余并退出" % [battle._t, want])
				break
		await RenderingServer.frame_post_draw
		var img: Image = battle.get_viewport().get_texture().get_image()
		var path: String = "%s_%d.png" % [_out_prefix, idx]
		img.save_png(path)
		print("[VFXLAB] shot %d → %s   (目标 %.2fs / 实到 %.2fs / 视口 %dx%d)" % [
			idx, path, want, battle._t, img.get_width(), img.get_height()])
		idx += 1
	print("[VFXLAB] 完成 %d 张, 退出。" % idx)
	battle.get_tree().quit()


## HOLD 模式把窗口摆到屏幕右侧垂直居中(给人看的时候不挡别的东西)。
func _place_window_right_middle() -> void:
	var scr: Vector2i = DisplayServer.screen_get_size()
	var win: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_position(Vector2i(
		maxi(0, scr.x - win.x - 40), maxi(0, int((scr.y - win.y) * 0.5))))
