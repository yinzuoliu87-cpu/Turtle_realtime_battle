extends Node2D

## TeamSelectScene — 1:1 移植 PoC src/scenes/TeamSelectScene.ts
##
## PoC 是 1647×955 整图皮 (select-bg.png) + DOM 绝对定位浮层。Godot 视口 1280×720,
## 这里把 PoC regionLayout 字典原值经 1647×955 → 1280×720 线性映射, 程序化建 Control 浮层。
##
## 元素 (全部对齐 PoC):
##   - 整图背景 select-bg.png  (.tscn 里铺)
##   - 标题 "选择你的伙伴" (m6x11 22px 金色)
##   - 返回 / 清空 / 上次阵容 三按钮
##   - 羁绊区 (synergy chip)
##   - 6 阵容槽 (前排3 + 后排3) + 前/后排标签
##   - 选龟网格 (卡片: 72头像 + 稀有度badge + 被动icon + Lv/名)  + 左侧稀有度竖排
##   - 右栏详情 上块(立绘/属性/被动) + 下块(技能 5选3)
##   - 开始按钮 (右下)

# ─── PoC regionLayout 原值 (1647×955 设计空间) — 跟 TS 字典 1:1 ──────────────
const POC_W := 1647.0
const POC_H := 955.0
const RL := {
	"title":      {"x": 588,  "y": 78,  "w": 330, "h": 30},
	"back":       {"x": 431,  "y": 74,  "w": 96,  "h": 36},
	"clear":      {"x": 1022, "y": 83,  "w": 78,  "h": 29},
	"last":       {"x": 1110, "y": 82,  "w": 94,  "h": 29},
	"synergy":    {"x": 183,  "y": 114, "w": 407, "h": 262},
	# 实时 3v3：3 格阵容居中(去回合制 6 格前/后排, 实时自由走位定位无意义, 战斗只读 3 龟 id)
	#   背景图 select-bg.png 烤了 6 格+前/后排横幅 → slotBay 暗托盘盖住它, 上面画 3 格 (代码绘, 居中对齐托盘)
	"slotBay":    {"x": 433,  "y": 120, "w": 766, "h": 233},
	"slot0":      {"x": 615,  "y": 172, "w": 108, "h": 156},
	"slot1":      {"x": 766,  "y": 172, "w": 108, "h": 156},
	"slot2":      {"x": 915,  "y": 172, "w": 108, "h": 156},
	"grid":       {"x": 160,  "y": 375, "w": 1050,"h": 403},
	# 右上信息区上部拆成 4 独立块(立绘/名字/属性/被动)—各自可拖可缩 (用户2026-07-18: 被动属性要能分开调大小)
	"dtPortrait": {"x": 1252, "y": 144, "w": 233, "h": 156},
	"dtName":     {"x": 1251, "y": 276, "w": 233, "h": 26},
	"dtStats":    {"x": 1252, "y": 307, "w": 233, "h": 58},
	"dtPassive":  {"x": 1251, "y": 390, "w": 230, "h": 56},
	"detailBottom":{"x": 1251,"y": 460, "w": 229, "h": 202},
	"start":      {"x": 1258, "y": 715, "w": 214, "h": 68},
}

const RARITY_COLOR: Dictionary = {
	"C":   Color("#06d6a0"), "B": Color("#4cc9f0"), "A": Color("#3a9abf"),
	"S":   Color("#c77dff"), "SS": Color("#ffd93d"), "SSS": Color("#ff6b6b"),
}
# PoC main.js:263 RARITY_ORDER 1:1
const RARITY_ORDER := ["SSS", "SS", "S", "A", "B", "C"]
const SLOT_KEYS := ["pos-0", "pos-1", "pos-2"]   # 实时 3v3：3 格阵容(去前/后排)
const TEAM_DRAFT_PATH := "user://team_draft.json"   # 1:1 PoC localStorage[LS_KEY] — 未确认阵容草稿持久化
const REQUIRED_PETS := 3
const SkillTipButton := preload("res://scripts/scenes/SkillTipButton.gd")   # 技能图标 styled tooltip
const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")        # 龟能花费 单一事实源 (无"CD")

# 特殊占位 mark (1:1 PoC TeamSelectScene.ts:119-121) — 占编队槽但非真龟, 显召唤预留位
const SUMMON_MARK := "_summon"             # 缩头乌龟(hiding) 随从
const CRYSTAL_BALL_MARK := "_crystal-ball" # 水晶龟(crystal)+crystalBall 被动 水晶球
const CANDY_BOMB_MARK := "_candy-bomb"     # 糖果龟(candy)+candyBombPassive 糖果炸弹
# 实时版: 召唤物(随从/水晶球/糖果炸弹) 在战斗中作独立单位现场生成, 不再于选龟界面预留板位
#   → 特殊占位 mark 系统在实时版停用 (_sync_special_slots 已 no-op); _is_special_mark 保留供过滤(恒 false)
const MARK_SLOT_ORDER := [2, 1, 0]

func _is_special_mark(id) -> bool:
	return id == SUMMON_MARK or id == CRYSTAL_BALL_MARK or id == CANDY_BOMB_MARK

@onready var root: Control = $UI/Root
@onready var status_bar: Label = $UI/StatusBar

var team: Array = [null, null, null]   # 实时 3 格阵容, 各 pet_id 或 null
var detail_pet_id: String = ""
var filter_rarity: String = "all"
var _selected_slot_idx: int = -1   # tap-to-swap 选中的满槽 (1:1 PoC selectedSlotIdx)
var _active_slot_idx: int = -1     # 待填的空槽 active (1:1 PoC activeSlotIdx)
var _did_entrance: bool = false    # 入场动画只播一次 (resize 重建不重播)
var _resize_pending: bool = false  # resize 重排去抖
var rng := RandomNumberGenerator.new()

# 运行时建出的节点引用 (refresh 时更新)
var _slot_nodes: Array = []          # 6 个槽 Panel
var _grid_flow: GridContainer = null
var _grid_card_w: float = 116.0      # 每卡宽 = 填满网格行(1:1 PoC .pet-grid minmax(116px,1fr) 卡拉伸铺满, 非固定116留白); _build_grid_region 算
var _synergy_box: HFlowContainer = null
var _dt_portrait: PanelContainer = null   # 右上信息区: 立绘块(独立可拖/缩)
var _dt_name: PanelContainer = null       # 名字+稀有+Lv 块
var _dt_stats: PanelContainer = null      # 属性块(生命/攻击/防御/魔抗)
var _dt_passive: PanelContainer = null    # 被动块
var _detail_bottom: VBoxContainer = null
var _start_btn: Button = null
var _last_btn: Button = null
## 大轮阵容锁定模式 (用户 2026-07-11): season_leaders 已有 3 龟 = 本大轮已锁定 →
##   阵容不可改(灰显/点=只看), 仅 3选1 技能可切; 确认出战直接进匹配. 新赛季(过期清 season_leaders)才回到全选模式.
var _roster_locked: bool = false

# ─── 布局编辑器 (F9 开/关 · 拖动=移动 · 右下角把手=缩放 · F10=导出RL到控制台 · 用户2026-07-18) ───
#   右侧信息区/技能区等区块拖到跟背景框对齐后, 屏上标签直接显示 POC(1647×955) 的 x/y/w/h, 抄回给我 bake 进 RL。
var _rl_override: Dictionary = {}     # 编辑期覆盖 RL {key:{x,y,w,h}} (POC 1647×955 空间)
var _place_reg: Dictionary = {}       # key → 已放置的 Control (编辑期实时重放真内容)
var _edit_mode: bool = false
var _edit_layer: Control = null
var _edit_handles: Dictionary = {}    # key → {handle:Panel, label:Label}
var _drag_key: String = ""
var _drag_mode: String = ""           # "move" / "resize"
var _drag_last: Vector2 = Vector2.ZERO

var _info_popup: Control = null       # 点按信息弹窗(被动/技能·跨PC点击+手机点触)

# 入场 choreography + CTA 脉冲 (1:1 PoC index.html:328/659-687)
var _ent_title: Control = null       # .screen-title
var _ent_top: Array = []             # .select-top (返回/清空/上次)
var _ent_rail: Control = null        # .pg-filter-bar (稀有度导轨)
var _ent_scroll: Control = null      # .pet-grid (唯一有入场动画的元素)
var _rarity_btns: Array = []         # [{btn, key}]


func _ready() -> void:
	rng.randomize()
	if DataRegistry.all_pets.is_empty():
		status_bar.text = "❌ DataRegistry 未加载"
		push_error("[TeamSelect] DataRegistry 没加载!")
		return
	# 大轮已锁定? = season_leaders 已是有效 3 龟. 锁定→预填不清; 未锁(新赛季/首次)→清空全选.
	_roster_locked = _season_roster_ready()
	GameState.clear_team()                       # 归零 left_team/left_slots (内部 typed 赋值; 避免外部给 Array[String] 属性赋无类型 [] 崩)
	if _roster_locked:
		var _lead_typed: Array[String] = []
		for _pid in GameState.season_leaders:
			_lead_typed.append(str(_pid))
		GameState.left_team = _lead_typed        # 供 _load_team 恢复锁定阵容; loadouts 不清(随赛季持久)
	else:
		GameState.loadouts = {}
	# 像素字体主题 (m6x11 英文/数字 + CJK 回退, 1:1 PoC 字体栈) — tscn 之前没挂 theme,
	#   所有 Label 落回 Godot 内置无衬线字 = 字体不对; 挂上后整棵浮层继承。
	var ui_theme: Theme = load("res://assets/themes/default_theme.tres")
	if ui_theme != null:
		root.theme = ui_theme
		status_bar.theme = ui_theme
	# 视口比例由项目级 EXPAND(window/stretch/aspect)保证, 场景切换不再翻转 aspect → 入场丝滑(1:1 PoC
	#   全程不改 canvas 比例)。同步建完(无 await), 首帧即完整布局, 无半成品/撕裂帧。背景铺满见 _ensure_menu_bg。
	_ensure_menu_bg()
	_fit_background()
	_build_ui()
	_load_team()
	_refresh_all()
	if _roster_locked:
		_flash_status("🔒 本大轮阵容已锁定 · 点龟查看并调整 3选1 技能 · 确认出战")
	# 窗口 resize/全屏/最大化 → 重算背景 + 按新尺寸重建浮层 (PoC fitSelectStage 绑 resize; 之前缺 → 铺不满根因)
	get_viewport().size_changed.connect(_on_resize)
	if OS.has_environment("TSEDIT"):
		call_deferred("_toggle_layout_edit")   # 直接开布局编辑器(给用户拖坐标·boot 即进)
	if OS.has_environment("POPUP_DEMO"):
		call_deferred("_demo_popup")            # 自验: 最靠右锚点弹窗是否夹回屏内


## 本大轮阵容是否已锁定 = season_leaders 已是有效的 REQUIRED_PETS 只已知龟 (新赛季 start_new_season 清空 → 回全选).
func _season_roster_ready() -> bool:
	if not (GameState.season_leaders is Array):
		return false
	var n := 0
	for pid in GameState.season_leaders:
		if DataRegistry.pet_by_id.has(str(pid)):
			n += 1
	return n == REQUIRED_PETS


## menu 平铺底 (1:1 PoC html.menu-bg-active::before/after) — 铺满窗口, 垫在 select-bg 舞台后面,
## 非 16:9 时填满舞台外边距 (替代黑边)。挂 UI 层 index 0 (最底, 在 Background select-bg 之下)。
func _ensure_menu_bg() -> void:
	var ui := get_node_or_null("UI")
	if ui == null or ui.has_node("MenuBg"):
		return
	var holder := Control.new()
	holder.name = "MenuBg"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 深绿底 #1a3a2a
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(base)
	# menu-bg-tile.png 512 平铺
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tile)
	# ::after 暗渐变 (8/12/20 @ .15→.25→.40)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.15),
		Color(0.031, 0.047, 0.078, 0.25),
		Color(0.031, 0.047, 0.078, 0.40)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ov)
	ui.add_child(holder)
	ui.move_child(holder, 0)   # 垫到最底 (Background/Root/StatusBar 之上方渲染)


## 背景整图皮 select-bg.png 吃跟浮层同一舞台变换 (居中+scale+offset), 跟 PoC .ts-stage 1:1
func _fit_background() -> void:
	var bg := get_node_or_null("UI/Background")
	if bg == null or not (bg is TextureRect):
		return
	var tr: TextureRect = bg
	# 取消 .tscn 里的 full-rect anchor, 改用显式 stage 矩形
	tr.anchor_left = 0; tr.anchor_top = 0; tr.anchor_right = 0; tr.anchor_bottom = 0
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE   # 拉满给定矩形 (PoC background-size:100% 100%)
	var s := _stage_scale()
	tr.position = _stage_to_screen(Vector2.ZERO)
	tr.size = Vector2(POC_W, POC_H) * s


# ══════════════════════════════════════════════════════════════
# 坐标换算: PoC stage(1647×955) → Godot 视口
#
# PoC fitSelectStage 把 1647×955 舞台居中, scale = min(vw/1647, vh/955) * stageZoom,
# 再 translate(ox, oy)。整图皮 select-bg.png 是舞台底, 所以背景 + 浮层都吃同一变换。
# 不能用之前的非均匀 sx/sy 线性拉伸 (会把背景画好的槽/凹槽/绿按钮错位)。
# stageZoom=1.17 / ox=0 / oy=76 跟 PoC TeamSelectScene.ts bake 值 1:1。
# ══════════════════════════════════════════════════════════════
const STAGE_ZOOM := 1.17
const STAGE_OFFSET := Vector2(0, 76)

func _vp() -> Vector2:
	return Vector2(get_viewport().get_visible_rect().size)


## 舞台缩放: 始终 cover(max) — 用户要"木板盖住绿色"(背景不该露绿). PoC 窗口虽 contain, 但
##   高分辨率/非16:9 下 contain 会露绿底; 改 cover 让木板始终盖满视口(裁边可接受, 槽/UI居中可见).
func _stage_scale() -> float:
	var vp := _vp()
	var sx := vp.x / POC_W
	var sy := vp.y / POC_H
	return max(sx, sy) * STAGE_ZOOM


## PoC 舞台局部坐标 → 屏幕坐标 (居中 + scale + offset, 跟 .ts-stage transform 1:1)
##   PoC oy=76 是 translate 的 CSS/真实像素(scale 后再平移, 不随内容放大); Godot 在 canvas_items
##   stretch 下 _vp()=逻辑1280×720, STAGE_OFFSET 若直接加会被 content-scale 放大 → 高分屏木板比 PoC 多下移
##   (用户报"背景木板下移"). 修: 把偏移按 逻辑/真实 比折算, 使其渲染后恰为 76 真实px (720p 窗口下 =76 不变).
func _stage_to_screen(p: Vector2) -> Vector2:
	var vp := _vp()
	var s := _stage_scale()
	var center := Vector2(POC_W, POC_H) * 0.5
	var off := STAGE_OFFSET
	var win := Vector2(DisplayServer.window_get_size())
	if win.x > 0.5 and win.y > 0.5:
		off = STAGE_OFFSET * (vp / win)   # 逻辑偏移 = 真实偏移 ÷ content-scale → 渲染后 =76 真实px
	return vp * 0.5 + off + (p - center) * s


## 内容缩放系数 — 区域外框已由 _rect/_place 按 stage scale 缩放, 但区域**内部**子元素
## (卡片/间距/头像/徽章/图标/字号/padding) 在 PoC 也吃同一 .ts-stage scale(s).
## 所以所有内容 base px 都要 × _s() 才跟 PoC 同密度 (1280×720 下 s≈0.882).
func _s() -> float:
	return _stage_scale()


## base px → 缩放后整数 px (尺寸/间距/圆角/margin)
func _sp(px: float) -> int:
	return int(round(px * _s()))


## base 字号 → 缩放后整数字号 (至少 1)
func _sf(px: float) -> int:
	return maxi(1, int(round(px * _s())))


func _rect(key: String) -> Rect2:
	var r: Dictionary = _rl_override[key] if _rl_override.has(key) else RL[key]
	var s := _stage_scale()
	var top_left := _stage_to_screen(Vector2(float(r["x"]), float(r["y"])))
	return Rect2(top_left, Vector2(float(r["w"]), float(r["h"])) * s)


## 屏幕坐标 → PoC(1647×955) 局部坐标 (_stage_to_screen 的逆·布局编辑器读回坐标用)
func _screen_to_stage(sp: Vector2) -> Vector2:
	var vp := _vp()
	var s := _stage_scale()
	var center := Vector2(POC_W, POC_H) * 0.5
	var off := STAGE_OFFSET
	var win := Vector2(DisplayServer.window_get_size())
	if win.x > 0.5 and win.y > 0.5:
		off = STAGE_OFFSET * (vp / win)
	return center + (sp - vp * 0.5 - off) / s


## 放置一个 Control 到 PoC 区域 (绝对定位). 顺带登记 key→节点, 供布局编辑器实时重放.
func _place(ctrl: Control, key: String) -> void:
	_place_reg[key] = ctrl
	var rc := _rect(key)
	ctrl.position = rc.position
	ctrl.size = rc.size

## 贴边功能按钮: 放置后夹回可视区 —— cover×1.17舞台在比16:9更宽的屏(iPhone 2.17:1)垂直裁挖>设计余量,
## 贴边按钮(返回/清空/上次/开始)会被裁出屏; 背景画裁边可接受, 按钮必须可点(用户2026-07-16"按钮不超屏不卡住")
func _place_clamped(ctrl: Control, key: String) -> void:
	_place(ctrl, key)
	var vp := _vp()
	ctrl.position.x = clampf(ctrl.position.x, 6.0, maxf(6.0, vp.x - ctrl.size.x - 6.0))
	ctrl.position.y = clampf(ctrl.position.y, 6.0, maxf(6.0, vp.y - ctrl.size.y - 6.0))


# ══════════════════════════════════════════════════════════════
# 布局编辑器 (F9 切换) — 拖块对齐背景框, 屏上/控制台读回 POC(1647×955) 坐标
#   拖块 body=移动, 右下角黄把手=缩放; 松手打印单块坐标; F10 打印整份 RL. 用户2026-07-18.
# ══════════════════════════════════════════════════════════════
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F9:
		_toggle_layout_edit()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F10 and _edit_mode:
		_export_rl()
		get_viewport().set_input_as_handled()


func _toggle_layout_edit() -> void:
	_edit_mode = not _edit_mode
	if _edit_mode:
		_build_edit_layer()
		_flash_status("🔧 布局编辑开: 拖=移动 · 右下角=缩放 · F10导出坐标 · 再按F9关")
	else:
		if is_instance_valid(_edit_layer):
			_edit_layer.queue_free()
		_edit_layer = null
		_edit_handles.clear()
		_drag_key = ""
		_flash_status("布局编辑关")


func _build_edit_layer() -> void:
	if is_instance_valid(_edit_layer):
		_edit_layer.queue_free()
	_edit_handles.clear()
	_edit_layer = Control.new()
	_edit_layer.name = "EditLayer"
	_edit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_layer.z_index = 4096   # 盖在 UI/Root 之上
	var ui := get_node_or_null("UI")
	(ui if ui != null else self).add_child(_edit_layer)
	var tip := Label.new()
	tip.text = "布局编辑 · 拖绿框=移动 · 拖右下角黄块=缩放 · 拖完点右上「保存坐标」→"
	tip.add_theme_color_override("font_color", Color("#ffe6b0"))
	tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	tip.add_theme_constant_override("outline_size", 4)
	tip.add_theme_font_size_override("font_size", 13)
	tip.position = Vector2(12, 4)
	_edit_layer.add_child(tip)
	# 右上角大「保存坐标」按钮 — 点一下写文件, 我直接读, 你不用抄任何东西
	var save_btn := Button.new()
	save_btn.text = "💾 保存坐标"
	save_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.custom_minimum_size = Vector2(150, 40)
	save_btn.position = Vector2(_vp().x - 164, 4)
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color("#2e7d46")
	ssb.set_corner_radius_all(8)
	ssb.set_border_width_all(2)
	ssb.border_color = Color("#7fe6a0")
	save_btn.add_theme_stylebox_override("normal", ssb)
	_edit_layer.add_child(save_btn)
	save_btn.pressed.connect(_save_rl_file)
	for key in _place_reg.keys():   # 只给已放置区块建把手(自动跳过未建的 synergy)
		if is_instance_valid(_place_reg[key]):
			_make_edit_handle(str(key))


func _make_edit_handle(key: String) -> void:
	var rc := _rect(key)
	var handle := Panel.new()
	handle.position = rc.position
	handle.size = rc.size
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.20, 0.85, 0.60, 0.14)
	sb.border_color = Color("#3cf0a0")
	sb.set_border_width_all(2)
	handle.add_theme_stylebox_override("panel", sb)
	_edit_layer.add_child(handle)
	var lbl := Label.new()
	lbl.add_theme_color_override("font_color", Color("#ffffff"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.position = Vector2(4, 2)
	handle.add_child(lbl)
	var grip := Panel.new()
	grip.size = Vector2(18, 18)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color("#ffd93d")
	grip.add_theme_stylebox_override("panel", gsb)
	handle.add_child(grip)
	grip.position = handle.size - grip.size
	_edit_handles[key] = {"handle": handle, "label": lbl, "grip": grip}
	handle.gui_input.connect(func(ev): _handle_input(key, "move", ev))
	grip.gui_input.connect(func(ev): _handle_input(key, "resize", ev))
	_update_edit_label(key)


func _handle_input(key: String, mode: String, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (ev as InputEventMouseButton).pressed:
			_drag_key = key
			_drag_mode = mode
			_drag_last = get_viewport().get_mouse_position()
		elif _drag_key == key:
			_drag_key = ""
			print("[RL] \"%s\": %s" % [key, _rl_line(key)])


func _input(event: InputEvent) -> void:
	if not _edit_mode or _drag_key == "":
		return
	if event is InputEventMouseMotion:
		var mp := get_viewport().get_mouse_position()
		var d := (mp - _drag_last) / _stage_scale()   # 屏幕位移 → POC 位移
		_drag_last = mp
		var r: Dictionary = _rl_val(_drag_key).duplicate()
		if _drag_mode == "move":
			r["x"] = float(r["x"]) + d.x
			r["y"] = float(r["y"]) + d.y
		else:
			r["w"] = maxf(16.0, float(r["w"]) + d.x)
			r["h"] = maxf(16.0, float(r["h"]) + d.y)
		_rl_override[_drag_key] = r
		if is_instance_valid(_place_reg.get(_drag_key)):
			_place(_place_reg[_drag_key], _drag_key)
		var rc := _rect(_drag_key)
		var h: Dictionary = _edit_handles.get(_drag_key, {})
		if h.has("handle") and is_instance_valid(h["handle"]):
			h["handle"].position = rc.position
			h["handle"].size = rc.size
			(h["grip"] as Control).position = (h["handle"] as Control).size - (h["grip"] as Control).size
		_update_edit_label(_drag_key)


func _rl_val(key: String) -> Dictionary:
	return _rl_override[key] if _rl_override.has(key) else RL[key]


func _rl_line(key: String) -> String:
	var r := _rl_val(key)
	return "{\"x\": %d, \"y\": %d, \"w\": %d, \"h\": %d}," % [int(round(float(r["x"]))), int(round(float(r["y"]))), int(round(float(r["w"]))), int(round(float(r["h"])))]


func _update_edit_label(key: String) -> void:
	var h: Dictionary = _edit_handles.get(key, {})
	if not h.has("label") or not is_instance_valid(h["label"]):
		return
	var r := _rl_val(key)
	(h["label"] as Label).text = "%s\nx%d y%d\nw%d h%d" % [key, int(round(float(r["x"]))), int(round(float(r["y"]))), int(round(float(r["w"]))), int(round(float(r["h"])))]


func _export_rl() -> void:
	var out := "\n===== 复制以下 RL (含你拖动后的坐标) =====\nconst RL := {\n"
	for key in RL.keys():
		out += "\t\"%s\": %s\n" % [key, _rl_line(str(key))]
	out += "}\n===== 结束 =====\n"
	print(out)
	_flash_status("📋 已导出 RL 坐标到控制台 (终端复制给我)")


## 保存坐标到文件 — 用户点按钮即写 user://rl_layout.txt, 我直接读回 (免抄免复制)
func _save_rl_file() -> void:
	var out := "const RL := {\n"
	for key in RL.keys():
		out += "\t\"%s\": %s\n" % [key, _rl_line(str(key))]
	out += "}\n"
	var f := FileAccess.open("user://rl_layout.txt", FileAccess.WRITE)
	if f == null:
		_flash_status("❌ 保存失败 (FileAccess null)")
		return
	f.store_string(out)
	f.close()
	print(out)
	_flash_status("💾 已保存 → user://rl_layout.txt (告诉我一声我就读)")


# ══════════════════════════════════════════════════════════════
# 点按信息弹窗 — 被动/技能 点一下弹名+描述 (PC点击 + 手机点触 都行·点空白关)
#   悬停 tooltip 只 PC 有; 手机无 hover → 加点按弹窗补齐. 用户2026-07-18.
# ══════════════════════════════════════════════════════════════
func _close_detail_popup() -> void:
	if is_instance_valid(_info_popup):
		_info_popup.queue_free()
	_info_popup = null


## 自验用: 拿最靠右的锚点弹一个长描述弹窗, 看是否夹回屏内 (POPUP_DEMO 门控)
func _demo_popup() -> void:
	var vp := _vp()
	var anchor := Rect2(vp.x - 90.0, 260.0, 64.0, 64.0)
	_show_detail_popup("测试被动·不屈", "受到致命伤害时一次不死, 保留 1 点生命(每场 1 次)。这段较长描述用于测试自动换行与屏内夹取是否正常, 多写几个字确保会换到第二三行。", Color("#7dffb3"), anchor)


## 直接吃 tooltip_text 文本(首行=名, 其余=描述)转成弹窗, 复用已有全部格式
func _show_detail_popup_from(text: String, accent: Color, anchor: Rect2) -> void:
	var t := text.strip_edges()
	var nl := t.find("\n")
	var ttl := t if nl < 0 else t.substr(0, nl)
	var body := "" if nl < 0 else t.substr(nl + 1)
	_show_detail_popup(ttl.strip_edges(), body.strip_edges(), accent, anchor)


func _show_detail_popup(title_txt: String, body_txt: String, accent: Color, anchor: Rect2) -> void:
	_close_detail_popup()
	var host: Node = get_node_or_null("UI")
	if host == null:
		host = self
	_info_popup = Control.new()
	_info_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_info_popup.mouse_filter = Control.MOUSE_FILTER_STOP   # 全屏 catcher: 点任意处关闭
	_info_popup.z_index = 4000
	host.add_child(_info_popup)
	_info_popup.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_detail_popup())
	var dim := ColorRect.new()   # 轻微压暗 = 一眼看出是弹窗(模态)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.22)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_popup.add_child(dim)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP        # 点面板本身不关(留着读)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.086, 0.13, 0.98)
	psb.border_color = accent
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(_sp(10))
	psb.content_margin_left = _sp(14); psb.content_margin_right = _sp(14)
	psb.content_margin_top = _sp(10); psb.content_margin_bottom = _sp(12)
	panel.add_theme_stylebox_override("panel", psb)
	panel.visible = false
	_info_popup.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _sp(6))
	panel.add_child(vb)
	var tl := Label.new()
	tl.text = title_txt
	tl.add_theme_font_size_override("font_size", _sf(18))
	tl.add_theme_color_override("font_color", accent)
	vb.add_child(tl)
	if body_txt != "":
		var bl := Label.new()
		bl.text = body_txt
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.custom_minimum_size = Vector2(_sp(320), 0)
		bl.add_theme_font_size_override("font_size", _sf(14))
		bl.add_theme_color_override("font_color", Color("#e8eef5"))
		vb.add_child(bl)
	# 尺寸同步算(不靠等帧·避免 size=0 → 夹屏失败跑屏外); 放 anchor 左侧(不挡被点元素), 放不下换右, 最终夹屏内
	var vp := _vp()
	var psz := panel.get_combined_minimum_size()
	psz.x = maxf(psz.x, 40.0)
	psz.y = maxf(psz.y, 20.0)
	var m := float(_sp(10))
	var px := anchor.position.x - psz.x - float(_sp(12))   # 默认放左侧
	if px < m:
		px = anchor.position.x + anchor.size.x + float(_sp(12))   # 左边放不下→放右侧
	var py := anchor.position.y
	px = clampf(px, m, maxf(m, vp.x - psz.x - m))   # 最终夹进屏内(左右)
	py = clampf(py, m, maxf(m, vp.y - psz.y - m))   # 夹进屏内(上下)
	panel.position = Vector2(px, py)
	panel.size = psz
	panel.visible = true


# ══════════════════════════════════════════════════════════════
# 建 UI
# ══════════════════════════════════════════════════════════════
func _build_ui() -> void:
	# 标题 (PoC .ts-title: #ffe6b0 22px, letter-spacing 2px, 阴影)
	var title := Label.new()
	title.text = "选择你的统领"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _sf(22))
	title.add_theme_color_override("font_color", Color("#ffe6b0"))
	_add_text_shadow(title, Vector2(0, 2), Color(0, 0, 0, 0.7))
	root.add_child(title)
	_place(title, "title")
	_ent_title = title

	# 返回 (PoC .ts-overlay-btn: 半透深底 + 金边 + #ffd86b 文字)
	var back := Button.new()
	back.text = "‹ 返回"
	back.add_theme_font_size_override("font_size", _sf(13))
	_style_overlay_btn(back)
	root.add_child(back)
	_place_clamped(back, "back")
	back.pressed.connect(_on_back)

	# 清空 (PoC .ts-frame-btn: 透明底无边, 白字阴影, 坐在画好的框上)
	var clear := Button.new()
	clear.text = "⊘ 清空"
	clear.add_theme_font_size_override("font_size", _sf(12))
	_style_frame_btn(clear)
	root.add_child(clear)
	_place_clamped(clear, "clear")
	clear.pressed.connect(_on_clear_all)

	# 上次阵容 (PoC .ts-frame-btn)
	_last_btn = Button.new()
	_last_btn.text = "🔄 上次阵容"   # ↺(U+21BA) 打包字体链无字形(web/linux豆腐块) → 换 🔄(U+1F504, Noto Emoji 有)
	_last_btn.add_theme_font_size_override("font_size", _sf(12))
	_style_frame_btn(_last_btn)
	root.add_child(_last_btn)
	_place_clamped(_last_btn, "last")
	_last_btn.pressed.connect(_on_restore_last)
	_ent_top = [back, clear, _last_btn]

	# 实时 3v3：去掉回合制「前排/后排」标签 (自由走位下定位无意义)

	# _build_synergy_region()   # 删: 老宠物标签羁绊已弃用 (用户 2026-06-23 "删掉老羁绊"), 改用 11 学派装备系统
	_build_slots()
	_build_grid_region()
	_build_detail_region()

	# 开始按钮 (PoC #poc-btn-confirm: 透明底, #eaffd0 18px 阴影, 坐画好的绿按钮上)
	_start_btn = Button.new()
	_start_btn.disabled = true
	_start_btn.add_theme_font_size_override("font_size", _sf(18))
	_start_btn.text = "请选择 3 只龟"
	_start_btn.add_theme_color_override("font_color", Color("#eaffd0"))
	_start_btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	_start_btn.add_theme_color_override("font_pressed_color", Color("#eaffd0"))
	_start_btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	_start_btn.add_theme_constant_override("shadow_offset_x", 0)
	_start_btn.add_theme_constant_override("shadow_offset_y", 1)
	_start_btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	var _cta_hover := StyleBoxFlat.new()
	_cta_hover.bg_color = Color(1, 1, 1, 0.1)
	_cta_hover.set_corner_radius_all(8)
	_start_btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_start_btn.add_theme_stylebox_override("hover", _cta_hover)
	_start_btn.add_theme_stylebox_override("pressed", _cta_hover)
	_start_btn.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	_start_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	root.add_child(_start_btn)
	_place_clamped(_start_btn, "start")
	_start_btn.pressed.connect(_on_start)

	if not _did_entrance:   # 入场只播一次 (resize 重建不重播)
		_did_entrance = true
		_play_entrance()


## 窗口尺寸变化 → 重算 (PoC fitSelectStage 每次 resize 重算 --ts-scale)。去抖 0.1s 避免拖拽边框时频繁重建。
func _on_resize() -> void:
	if _resize_pending or not is_inside_tree():
		return
	_resize_pending = true
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		_resize_pending = false
		if not is_inside_tree():
			return
		_fit_background()                       # select-bg 按新视口重铺 (menu-bg holder 是 FULL_RECT 自适应)
		for c in root.get_children():           # 浮层位置 bake 在 _build_ui → 按新 stage scale 全重建
			c.queue_free()
		_slot_nodes = []
		_build_ui()                             # _did_entrance 已 true → 不重播入场
		_refresh_all())


# ══════════════════════════════════════════════════════════════
# 入场 choreography (1:1 PoC index.html:659-687 .screen.active)
#   .42s title-drop@.05 → .32s guide@.2 → .45s top-slide-l@.32
#   → .35s filter-fade@.5 → .45s grid-in@.62
# (mode-guide PoC 有, 本实现无对应节点 → 省略其档)
# ══════════════════════════════════════════════════════════════
func _play_entrance() -> void:
	# 原入场: 龟池先空白0.62s→再上浮20px+缩放0.98→1+淡入0.45s (用户2026-07-18「浮现特效很烂」:
	#   空白等待+漂浮缩放=卡顿廉价感)。改成 无延迟·无上浮·无缩放·纯快速淡入0.14s → 干净利落即显。
	if _ent_scroll == null or not is_instance_valid(_ent_scroll):
		return
	_ent_scroll.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_ent_scroll, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 单元素入场: 从 (rest+off, from_scale, alpha0) 经 delay 后 dur 内回到 rest/1/1.
## backwards 填充: 先把起始态摆好 (delay 期间保持隐藏), 再播.
func _entrance(node: Control, off: Vector2, from_scale: float, delay: float, dur: float, trans: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	var rest: Vector2 = node.position
	node.pivot_offset = node.size * 0.5
	node.position = rest + off
	node.scale = Vector2(from_scale, from_scale)
	node.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "position", rest, dur).set_trans(trans).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "scale", Vector2.ONE, dur).set_trans(trans).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(node, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _build_synergy_region() -> void:
	# PoC #ts-rg-synergy: 透明 (坐在画好的羊皮纸上), 标题深色 #4a2f12
	var panel := PanelContainer.new()
	root.add_child(panel)
	_place(panel, "synergy")
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = _sp(10); sb.content_margin_right = _sp(10)
	sb.content_margin_top = _sp(8); sb.content_margin_bottom = _sp(8)
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _sp(6))
	panel.add_child(vb)

	var t := Label.new()
	t.text = "激活羁绊"
	t.add_theme_font_size_override("font_size", _sf(13))
	t.add_theme_color_override("font_color", Color("#4a2f12"))
	vb.add_child(t)

	# PoC .synergy-chips: flex-wrap gap:8 (index.html:495) → HFlowContainer 自动换行
	_synergy_box = HFlowContainer.new()
	_synergy_box.add_theme_constant_override("h_separation", _sp(8))
	_synergy_box.add_theme_constant_override("v_separation", _sp(8))
	_synergy_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_synergy_box)


func _build_slots() -> void:
	_slot_nodes = []
	# 暗托盘: 盖住背景图烤死的 6 格 + 前/后排横幅, 留出干净 3 格区 (木框边沿保留)
	var tray := Panel.new()
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color8(42, 28, 17)            # 木盘色(比格子亮), 格子是更暗的内陷
	tb.set_corner_radius_all(_sp(10))
	tb.border_width_top = 2; tb.border_width_bottom = 2; tb.border_width_left = 2; tb.border_width_right = 2
	tb.border_color = Color8(26, 17, 10)        # 内陷暗边, 给托盘一点深度
	tray.add_theme_stylebox_override("panel", tb)
	root.add_child(tray)
	_place(tray, "slotBay")
	for i in range(3):
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		root.add_child(panel)
		_place(panel, "slot%d" % i)
		# 空槽透明 (露出背景画好的 "+"); 填充后 _refresh_slots 换金边样式
		panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		# 整槽点击 → tap-swap
		var idx := i
		panel.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_slot_click(idx))
		# 拖放: 满槽可拖起 + 任意槽可作落点 (1:1 PoC slot draggable + drop)
		panel.set_drag_forwarding(_slot_drag.bind(panel, idx), _slot_can_drop, _slot_drop.bind(idx))
		# 内容容器
		var vb := VBoxContainer.new()
		vb.name = "Content"
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", _sp(2))
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vb)
		_slot_nodes.append(panel)


func _build_grid_region() -> void:
	var rc := _rect("grid")
	var s := _s()
	# PoC #ts-rg-grid: flex-direction:row gap:10 (index.html:480) — rail(竖排)在区**内左缘**,
	#   pet-grid 接右边. rail 宽 46 (.pg-rarity-btn width:46, index.html:485), rail gap 6 (483).
	var rail_w := 46.0 * s
	var row_gap := 10.0 * s         # #ts-rg-grid gap:10 (rail↔grid)
	# 稀有度竖排导轨 — 放在 grid 区**内**左缘 (非旧版 grid.x-46 的区外)
	var rail := VBoxContainer.new()
	rail.position = rc.position
	rail.add_theme_constant_override("separation", _sp(6))
	root.add_child(rail)
	_ent_rail = rail
	_rarity_btns = []
	for r in ["all", "SSS", "SS", "S", "A", "B", "C"]:
		var b := Button.new()
		b.text = "全部" if r == "all" else r
		b.custom_minimum_size = Vector2(_sp(46), _sp(30))
		b.add_theme_font_size_override("font_size", _sf(13))
		_style_rarity_btn(b, false)
		var key: String = r
		b.pressed.connect(func() -> void:
			filter_rarity = key
			_refresh_grid())
		rail.add_child(b)
		_rarity_btns.append({"btn": b, "key": r})

	# 网格 (ScrollContainer + GridContainer) — 起点右移 (rail宽+row_gap), 宽减同量 (PoC pet-grid 接 rail 右)
	var grid_off := rail_w + row_gap
	var scroll := ScrollContainer.new()
	scroll.position = rc.position + Vector2(grid_off, 0)
	scroll.size = Vector2(rc.size.x - grid_off, rc.size.y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # 隐藏滚动条(进度带)·滚动仍启用(手机拖·PC滚轮)·用户2026-07-18
	root.add_child(scroll)
	_ent_scroll = scroll
	_grid_flow = GridContainer.new()
	# PoC pet-grid: repeat(auto-fill, minmax(116px,1fr)) gap:12 padding:4 (index.html:381-382)。
	#   卡片/间距/padding 都吃 stage scale → 列数 scale 无关 (W*s/(116*s)=W/116), 用缩放后宽与 116*s 算一致。
	var card_w := 116.0 * s
	var gap_s := 12.0 * s
	var pad_s := 4.0 * s
	var _grid_cols: int = maxi(1, int(floor((scroll.size.x - pad_s * 2.0 + gap_s) / (card_w + gap_s))))
	_grid_flow.columns = _grid_cols
	# 每卡宽 = 网格行铺满后均分 (1:1 PoC minmax(116,1fr): 列数定后卡片拉伸填满整行, 不留右侧空白)
	var grid_gap := float(_sp(12))
	_grid_card_w = maxf(card_w, (scroll.size.x - float(_grid_cols - 1) * grid_gap) / float(_grid_cols))
	_grid_flow.add_theme_constant_override("h_separation", _sp(12))
	_grid_flow.add_theme_constant_override("v_separation", _sp(12))
	_grid_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid_flow)


func _build_detail_region() -> void:
	# 上区: 立绘/名字/属性/被动 各自独立成块 (可拖可缩·用户2026-07-18); 内容由 _refresh_detail 填
	_dt_portrait = _make_detail_panel("dtPortrait")
	_dt_name = _make_detail_panel("dtName")
	_dt_stats = _make_detail_panel("dtStats")
	_dt_passive = _make_detail_panel("dtPassive")

	# 下块 (技能 5选3)
	var bot_panel := PanelContainer.new()
	root.add_child(bot_panel)
	_place(bot_panel, "detailBottom")
	bot_panel.add_theme_stylebox_override("panel", _dark_panel())
	_detail_bottom = VBoxContainer.new()
	_detail_bottom.alignment = BoxContainer.ALIGNMENT_CENTER   # PoC #poc-detail-bottom justify-center
	_detail_bottom.add_theme_constant_override("separation", _sp(10))
	bot_panel.add_child(_detail_bottom)


## 建一个独立信息子块面板 (透明底·按 RL key 放置·登记进编辑器·不挡下层点击)
func _make_detail_panel(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	root.add_child(p)
	_place(p, key)
	p.add_theme_stylebox_override("panel", _dark_panel())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.clip_contents = true
	return p


## 透明面板 (PoC .ts-region / .dp-panel — 画框由背景整图皮提供, 内容浮层不画底)
func _clear_panel() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## 给 Label 加投影 (近似 CSS text-shadow)
func _add_text_shadow(lbl: Label, ofs: Vector2, col: Color) -> void:
	lbl.add_theme_constant_override("shadow_offset_x", int(ofs.x))
	lbl.add_theme_constant_override("shadow_offset_y", int(ofs.y))
	lbl.add_theme_color_override("font_shadow_color", col)


## PoC .ts-overlay-btn — 半透深底 + 金边 + #ffd86b 文字 (返回)
func _style_overlay_btn(btn: Button) -> void:
	btn.add_theme_color_override("font_color", Color("#ffd86b"))
	btn.add_theme_color_override("font_hover_color", Color("#ffe6b0"))
	btn.add_theme_color_override("font_pressed_color", Color("#ffd86b"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(20.0/255, 14.0/255, 8.0/255, 0.55)
	sb.border_color = Color(1, 216.0/255, 107.0/255, 0.4)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(74.0/255, 40.0/255, 16.0/255, 0.7)
	sbh.border_color = Color("#ffd86b")
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)


## PoC .ts-frame-btn — 透明底无边 + 白字阴影 (清空/上次阵容, 坐画好的框上)
func _style_frame_btn(btn: Button) -> void:
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	btn.add_theme_constant_override("shadow_offset_x", 0)
	btn.add_theme_constant_override("shadow_offset_y", 1)
	btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	var empty := StyleBoxEmpty.new()
	var sbh := StyleBoxFlat.new()
	sbh.bg_color = Color(1, 1, 1, 0.12)
	sbh.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.add_theme_stylebox_override("disabled", empty)


## PoC .pg-rarity-btn — 非激活: 金边半透; 激活: 金渐变填充 + 深字
func _style_rarity_btn(b: Button, active: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(_sp(7))   # PoC .pg-rarity-btn border-radius:7
	if active:
		sb.bg_color = Color("#e8a830")            # 金渐变近似实色
		sb.border_color = Color("#6b3d10")
		sb.set_border_width_all(1)
		b.add_theme_color_override("font_color", Color("#2a1605"))
		b.add_theme_color_override("font_hover_color", Color("#2a1605"))
		b.add_theme_color_override("font_pressed_color", Color("#2a1605"))
	else:
		sb.bg_color = Color(1, 216.0/255, 107.0/255, 0.06)
		sb.border_color = Color(1, 216.0/255, 107.0/255, 0.25)
		sb.set_border_width_all(1)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		b.add_theme_color_override("font_hover_color", Color("#ffd86b"))
		b.add_theme_color_override("font_pressed_color", Color("#ffd86b"))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _dark_panel() -> StyleBoxEmpty:
	# PoC 右栏 .ts-region/.dp-panel 透明 (画框来自背景图), 不再画暗底盖住画好的凹槽
	return StyleBoxEmpty.new()


# ══════════════════════════════════════════════════════════════
# 刷新
# ══════════════════════════════════════════════════════════════
## 同步特殊占位 (1:1 PoC syncSpecialSlots TeamSelectScene.ts:1842): hiding/crystal/candy 在阵 → 加 mark 槽
func _sync_special_slots() -> void:
	# 实时版停用召唤预留板位: 召唤物在战斗中现场生成, 选龟界面只摆 3 真龟, 不占位.
	#   (回合制 6 格板有空位可预留, 实时 3 格全填 3 龟无空位; 留空函数避免 mark 越界/占位)
	return


func _sync_mark_slot(pet_id: String, mark: String, require_passive: bool, passive_type: String) -> void:
	var has_pet := pet_id in team
	var should_have := has_pet
	if has_pet and require_passive and passive_type != "":
		# crystal/candy 需 loadout 含特定 passive 技能 (PoC syncMarkSlot:1853-1857)
		var pet: Dictionary = DataRegistry.pet_by_id.get(pet_id, {})
		var pool: Array = pet.get("skillPool", [])
		should_have = false
		for i in _get_panel_loadout(pet_id):
			if i >= 0 and i < pool.size() and str((pool[i] as Dictionary).get("type", "")) == passive_type:
				should_have = true
				break
	var idx := team.find(mark)
	if should_have and idx < 0:
		for i in MARK_SLOT_ORDER:   # back-2→front-0
			if team[i] == null:
				team[i] = mark
				break
	elif not should_have and idx >= 0:
		team[idx] = null


func _refresh_all() -> void:
	_sync_special_slots()
	if detail_pet_id == "":
		for id in team:
			if id != null and not _is_special_mark(id):
				detail_pet_id = id
				break
		if detail_pet_id == "" and not DataRegistry.launch_pets.is_empty():
			detail_pet_id = DataRegistry.launch_pets[0]["id"]
	_refresh_slots()
	_refresh_grid()
	_refresh_confirm()
	_refresh_detail()


func _refresh_slots() -> void:
	for i in range(3):
		var panel: PanelContainer = _slot_nodes[i]
		var vb: VBoxContainer = panel.get_node("Content")
		for c in vb.get_children():
			c.queue_free()
		var id = team[i]
		if id == null:
			# 空槽: active(待填, 黄亮边)/ 否则暗格 (背景烤的 "+" 已被 slotBay 托盘盖住 → 代码画暗格 + "+")
			panel.add_theme_stylebox_override("panel", _slot_box("active") if i == _active_slot_idx else _slot_box("empty"))
			var plus := Label.new()
			plus.text = "+"
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.add_theme_font_size_override("font_size", _sf(34))
			plus.add_theme_color_override("font_color", Color8(150, 120, 84))
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(plus)
			continue
		# 满槽/占位: selected(tap-swap 选中, PoC .fg-selected 金亮边)/ 否则普通 filled
		panel.add_theme_stylebox_override("panel", _slot_box("selected" if i == _selected_slot_idx else "filled"))
		if _is_special_mark(id):
			_fill_mark_slot(vb, id)
			continue
		var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
		if pet.is_empty():
			panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			continue
		# PoC .fg-turtle img width:70% — 槽宽(108*s)×0.7
		var av := TextureRect.new()
		var slot_av := _sp(108 * 0.7)   # PoC img width:70% of slot (108 设计宽)
		av.custom_minimum_size = Vector2(slot_av, slot_av)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av_path := "res://assets/sprites/avatars/%s.png" % id
		if ResourceLoader.exists(av_path):
			av.texture = load(av_path)
		vb.add_child(av)
		# PoC .fg-name font-size:10px
		var nm := Label.new()
		nm.text = pet.get("name", "?")
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", _sf(10))
		nm.add_theme_color_override("font_color", RARITY_COLOR.get(pet.get("rarity", "C"), Color.WHITE))
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(nm)


## 槽样式 (1:1 PoC .fg-slot.filled/.fg-selected/.fg-active index.html:280-291)
func _slot_box(kind: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(_sp(12))
	if kind == "empty":   # 实时空格: 暗内陷格 + 微木边 (替代背景图烤死的 "+" 格, 已被 slotBay 托盘盖住)
		sb.bg_color = Color8(24, 17, 12)
		sb.border_color = Color8(72, 50, 30)
		return sb
	if kind == "selected":   # PoC .fg-selected #ffcc00 + glow rgba(255,204,0,.55)
		sb.bg_color = Color(1, 204.0/255, 0, 0.18)
		sb.border_color = Color("#ffcc00")
		sb.shadow_color = Color(1, 204.0/255, 0, 0.55); sb.shadow_size = _sp(6)
	elif kind == "active":   # PoC .fg-active #fff3a0 + glow rgba(255,243,160,.6)
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color("#fff3a0")
		sb.shadow_color = Color(1, 243.0/255, 160.0/255, 0.6); sb.shadow_size = _sp(6)
	else:   # filled: 金边半透底 + 外发光
		sb.bg_color = Color(1, 216.0/255, 107.0/255, 0.1)
		sb.border_color = Color(1, 216.0/255, 107.0/255, 0.7)
		sb.shadow_color = Color(1, 216.0/255, 107.0/255, 0.3); sb.shadow_size = _sp(4)
	return sb


## 渲染特殊占位槽内容 (1:1 PoC .fg-summon TeamSelectScene.ts:591-598): 随从?/水晶球img/糖果炸弹emoji + 彩色名
func _fill_mark_slot(vb: VBoxContainer, mark: String) -> void:
	var nm_text := ""
	var nm_color := Color.WHITE
	if mark == SUMMON_MARK:
		nm_text = "随从"; nm_color = Color("#ffc850")
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_size_override("font_size", _sf(28))
		q.add_theme_color_override("font_color", Color("#ffc850"))
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(q)
	elif mark == CRYSTAL_BALL_MARK:
		nm_text = "水晶球"; nm_color = Color("#9b6bff")
		var img := TextureRect.new()
		img.custom_minimum_size = Vector2(_sp(32), _sp(32))
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cb := "res://assets/sprites/pets/crystal-ball.png"
		if ResourceLoader.exists(cb):
			img.texture = load(cb)
		vb.add_child(img)
	else:   # CANDY_BOMB_MARK
		nm_text = "糖果炸弹"; nm_color = Color("#ff6bd8")
		var e := Label.new()
		e.text = "🍬💣"
		e.add_theme_font_size_override("font_size", _sf(22))
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(e)
	var nm := Label.new()
	nm.text = nm_text
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", _sf(10))
	nm.add_theme_color_override("font_color", nm_color)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)


func _refresh_grid() -> void:
	for c in _grid_flow.get_children():
		c.queue_free()
	# active 稀有度按钮 (PoC .pg-rarity-btn.active = 金渐变填充 + 深字)
	for rb in _rarity_btns:
		var b: Button = rb["btn"]
		_style_rarity_btn(b, rb["key"] == filter_rarity)

	var pets: Array = DataRegistry.launch_pets.duplicate()
	# rarity filter
	if filter_rarity != "all":
		var filtered: Array = []
		for p in pets:
			if p.get("rarity", "") == filter_rarity:
				filtered.append(p)
		pets = filtered
	# sort by rarity (PoC default)
	pets.sort_custom(func(a, b): return RARITY_ORDER.find(a.get("rarity", "C")) < RARITY_ORDER.find(b.get("rarity", "C")))

	for pet in pets:
		_grid_flow.add_child(_make_pet_card(pet))
	# 锁定态: 候选池灰显(去强调) — 表明本大轮不能改阵容; 卡片仍可点=查看详情/调技能, 只是不入队.
	_grid_flow.modulate = Color(1, 1, 1, 0.55) if _roster_locked else Color(1, 1, 1, 1)


func _make_pet_card(pet: Dictionary) -> Control:
	var pid: String = pet["id"]
	var rarity: String = pet.get("rarity", "C")
	var rcolor: Color = RARITY_COLOR.get(rarity, Color.WHITE)
	var selected := pid in team

	# PoC .pet-card 卡 = 纯 Control 叠层: 背景框(满) + 内容(padding内缩, 上→下 头像→meta) + badge(相对卡) + 被动(相对头像)
	var card := Control.new()
	# 宽=填满行均分(≥116, 1:1 PoC minmax(116,1fr) 卡拉伸); 高 ~116. 原固定116²方卡左packed留白=用户报"布局不同"
	card.custom_minimum_size = Vector2(_grid_card_w, _sp(116))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := StyleBoxFlat.new()
	if selected:
		sb.bg_color = Color(1, 216.0/255, 107.0/255, 0.1)
		sb.border_color = Color("#ffd86b")
	else:
		sb.bg_color = Color(74.0/255, 40.0/255, 16.0/255, 0.4)
		sb.border_color = Color(1, 216.0/255, 107.0/255, 0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(_sp(12))
	# 背景框铺满卡 (Panel; 让 badge/被动可绝对叠在卡边而非被 padding 推偏)
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", sb)
	card.add_child(bg)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_set_detail_pet(pid)
			_on_pick_pet(pid))
	# 拖放: 卡片可拖入编队槽 (1:1 PoC .pet-card draggable=true)
	card.set_drag_forwarding(_card_drag.bind(card, pid), Callable(), Callable())

	# 内容: MarginContainer(满卡 + PoC padding:10px 8px 8px) → VBox(头像 → meta, 顶对齐自然流)
	var pad_wrap := MarginContainer.new()
	pad_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad_wrap.add_theme_constant_override("margin_left", _sp(8))
	pad_wrap.add_theme_constant_override("margin_right", _sp(8))
	pad_wrap.add_theme_constant_override("margin_top", _sp(10))
	pad_wrap.add_theme_constant_override("margin_bottom", _sp(8))
	pad_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad_wrap)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN   # 头像在上 meta 紧随 (PoC 自然流, 非垂直居中)
	vb.add_theme_constant_override("separation", _sp(4))   # PoC .pet-avatar margin-bottom:4
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad_wrap.add_child(vb)

	# 头像区 (PoC .pet-avatar min-height:76 position:relative → 被动相对它定位)
	var av_area := Control.new()
	av_area.custom_minimum_size = Vector2(0, _sp(76))
	av_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	av_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(av_area)
	# 72px 全身 idle 动画 (1:1 PoC buildPetImgHTML(pet,72); 默认 paused, hover/selected 才播)
	var av := TextureRect.new()
	av.set_anchors_preset(Control.PRESET_FULL_RECT)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_pet_idle_texture(av, pet, selected)
	av_area.add_child(av)
	# 被动图标 (PoC .pet-passive-icon: 相对**头像**右上探出 top:-8 right:-8)
	var passive_raw = pet.get("passive")
	if passive_raw is Dictionary and not (passive_raw as Dictionary).is_empty():
		var pi_path: String = DataRegistry.passive_icons.get((passive_raw as Dictionary).get("type", ""), "")
		if pi_path.ends_with(".png"):
			var full := "res://assets/sprites/" + pi_path
			if ResourceLoader.exists(full):
				var pcirc := PanelContainer.new()
				pcirc.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var pc_sb := StyleBoxFlat.new()
				pc_sb.bg_color = Color(10.0/255, 14.0/255, 24.0/255, 1.0)
				pc_sb.set_corner_radius_all(_sp(17))
				pc_sb.content_margin_left = _sp(4); pc_sb.content_margin_right = _sp(4)
				pc_sb.content_margin_top = _sp(4); pc_sb.content_margin_bottom = _sp(4)
				pcirc.add_theme_stylebox_override("panel", pc_sb)
				var pic := TextureRect.new()
				pic.texture = load(full)
				pic.custom_minimum_size = Vector2(_sp(26), _sp(26))   # PoC img 26px
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pcirc.add_child(pic)
				pcirc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
				pcirc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
				pcirc.grow_vertical = Control.GROW_DIRECTION_END
				av_area.add_child(pcirc)
				pcirc.position += Vector2(_sp(8), -_sp(8))   # 探出右上 right:-8 top:-8

	# meta 行: Lv + 名 同一行 (PoC .pet-meta flex baseline center gap5)
	var meta := HBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", _sp(5))
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := Label.new()
	lv.text = "Lv.%d" % GameState.get_pet_level(pid)   # PoC pet-card lv=getPetLevel
	lv.add_theme_font_size_override("font_size", _sf(11))
	lv.add_theme_color_override("font_color", Color("#ffd86b"))   # PoC .pet-lv #ffd86b
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(lv)
	var nm := Label.new()
	nm.text = pet.get("name", "?")
	nm.add_theme_font_size_override("font_size", _sf(13))   # PoC .pet-name 13px (无色=浅色继承)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(nm)
	vb.add_child(meta)

	# 稀有度 badge (PoC .pet-rarity-badge 相对**卡片** top:6 left:6) — 挂 card 绝对定位, 渲染最上层
	var badge := _make_rarity_badge(rarity, rcolor)
	badge.position = Vector2(_sp(6), _sp(6))
	card.add_child(badge)

	# hover (1:1 PoC .pet-card:hover translateY(-2)+金边+柔光; 非选中 idle hover才播)
	var base_border: Color = sb.border_color
	card.mouse_entered.connect(func() -> void:
		if not is_instance_valid(card): return
		if card.get_meta("hovered", false): return
		card.set_meta("hovered", true)
		card.set_meta("rest_y", card.position.y)
		sb.border_color = Color("#ffd86b")
		sb.shadow_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.18)
		sb.shadow_size = _sp(6)
		sb.shadow_offset = Vector2(0, _sp(4))
		var t = av.get_meta("idle_tw", null)
		if t is Tween and (t as Tween).is_valid(): (t as Tween).play()
		var tw := card.create_tween()
		tw.tween_property(card, "position:y", card.position.y - 2.0 * _s(), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	card.mouse_exited.connect(func() -> void:
		if not is_instance_valid(card): return
		if not card.get_meta("hovered", false): return
		card.set_meta("hovered", false)
		sb.border_color = base_border
		sb.shadow_size = 0
		if not selected:
			var t = av.get_meta("idle_tw", null)
			if t is Tween and (t as Tween).is_valid():
				(t as Tween).pause()
				if av.texture is AtlasTexture:
					var at := av.texture as AtlasTexture
					at.region = Rect2(0, 0, at.region.size.x, at.region.size.y)
		var rest_y: float = card.get_meta("rest_y", card.position.y)
		var tw := card.create_tween()
		tw.tween_property(card, "position:y", rest_y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))

	return card


## 给 TextureRect 装龟的全身 idle 动画 (1:1 PoC buildPetImgHTML: pet.img 全身 sheet + sprite{} 帧).
##   有 sprite{frameW} → AtlasTexture 逐帧循环(同战斗 makeView 的 fps 公式); 无 sprite{} → 静态 body PNG;
##   img 缺 → avatars 头像回退。PoC 卡片/立绘是会 idle 跳动的全身龟, 非静态头像。
func _apply_pet_idle_texture(tr: TextureRect, pet: Dictionary, autoplay: bool = true) -> void:
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pid := str(pet.get("id", ""))
	var img := str(pet.get("img", ""))
	var img_full := "res://assets/sprites/%s" % img
	var sprite_meta = pet.get("sprite", null)
	if img != "" and ResourceLoader.exists(img_full) and sprite_meta is Dictionary and (sprite_meta as Dictionary).has("frameW"):
		var tex: Texture2D = load(img_full)
		var meta: Dictionary = sprite_meta
		var fw: int = int(meta.get("frameW", tex.get_width()))
		var fh: int = int(meta.get("frameH", tex.get_height()))
		if fw <= 0:
			fw = tex.get_width()
		if fh <= 0:
			fh = tex.get_height()
		var hframes: int = maxi(1, int(floor(float(tex.get_width()) / float(fw))))
		var declared: int = int(meta.get("frames", hframes))
		var n: int = maxi(1, mini(declared, hframes))
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(0, 0, fw, fh)
		tr.texture = atlas
		if n > 1:
			var dur_ms: float = float(meta.get("duration", 800))
			var fps: float = maxf(4.0, roundf(float(n) * 1000.0 / maxf(200.0, dur_ms)))
			var loop_dur: float = float(n) / fps
			var atw := tr.create_tween().set_loops()
			atw.tween_method(
				func(v: float) -> void:
					if is_instance_valid(tr) and tr.texture is AtlasTexture:
						(tr.texture as AtlasTexture).region = Rect2((int(v) % n) * fw, 0, fw, fh),
				0.0, float(n), loop_dur)
			# PoC .sprite-inner 默认 paused, 仅 hover/selected running (index.html:432/434); 立绘 autoplay=true 常驻。
			tr.set_meta("idle_tw", atw)
			if not autoplay:
				atw.pause()
	elif img != "" and ResourceLoader.exists(img_full):
		tr.texture = load(img_full)   # 无 sprite{} → 静态全身 body
	else:
		var av_path := "res://assets/sprites/avatars/%s.png" % pid
		if ResourceLoader.exists(av_path):
			tr.texture = load(av_path)


## PoC .pet-rarity-badge — 圆角填充底 (稀有度色) + 深色字, 左上角
func _make_rarity_badge(rarity: String, rcolor: Color, font_px: int = 11) -> Control:
	# 网格卡 .pet-rarity-badge font:11px / 详情 .dp-rarity font:12px (PoC index.html:405/570)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = rcolor
	sb.set_corner_radius_all(_sp(6))
	sb.content_margin_left = _sp(8); sb.content_margin_right = _sp(8)   # PoC padding 2px 8px
	sb.content_margin_top = _sp(2); sb.content_margin_bottom = _sp(2)
	pc.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = rarity
	lbl.add_theme_font_size_override("font_size", _sf(font_px))
	lbl.add_theme_color_override("font_color", Color("#1a1a2e"))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(lbl)
	return pc


func _refresh_confirm() -> void:
	if _roster_locked:
		_start_btn.disabled = false
		_start_btn.text = "⚔ 确认出战"
		if _last_btn != null:
			_last_btn.disabled = true          # 锁定态禁"上次阵容"
		return
	var placed := 0
	for t in team:
		if t != null and not _is_special_mark(t):   # 特殊占位不计入 3 龟
			placed += 1
	var ready_ok: bool = placed == REQUIRED_PETS
	_start_btn.disabled = not ready_ok
	# PoC #poc-btn-confirm(index.html:518) 显式 animation:none box-shadow:none → 开始按钮无脉冲发光
	#   (.select-cta 通用脉冲被 ID 规则覆盖关掉)。曾自创发光 Panel 已删。
	if placed == 0:
		_start_btn.text = "请选择 3 只龟"
	elif placed < REQUIRED_PETS:
		_start_btn.text = "还需选 %d 只" % (REQUIRED_PETS - placed)
	else:
		_start_btn.text = "⚔ 开始冒险"
	# 上次阵容: 空队 + 有完整存档才可恢复
	var last := _read_last_lineup()
	var can_restore: bool = placed == 0 and last.has("ids") and (last["ids"] as Array).size() == 3
	_last_btn.disabled = not can_restore


# ─── 右栏详情 ──────────────────────────────────────────────────
func _refresh_detail() -> void:
	for cont in [_dt_portrait, _dt_name, _dt_stats, _dt_passive, _detail_bottom]:
		if cont != null:
			for c in cont.get_children():
				c.queue_free()
	if detail_pet_id == "":
		return
	var pet: Dictionary = DataRegistry.pet_by_id.get(detail_pet_id, {})
	if pet.is_empty():
		return
	var rarity: String = pet.get("rarity", "C")
	var rcolor: Color = RARITY_COLOR.get(rarity, Color.WHITE)
	# 数值=base×getLevelBonus(1+(lv-1)×0.05), 仅等级加成不乘稀有(1:1 PoC TeamSelectScene.ts:788-792).
	# 原 Godot 用裸 base + 硬编 Lv.1 → 有等级的龟数值/等级都不对.
	var det_lv: int = GameState.get_pet_level(detail_pet_id)
	var lv_bonus: float = 1.0 + (det_lv - 1) * 0.05
	var hp: int = roundi(pet.get("hp", 0) * lv_bonus)
	var atk: int = roundi(pet.get("atk", 0) * lv_bonus)
	var def_: int = roundi(pet.get("def", 0) * lv_bonus)
	var mr: int = roundi(pet.get("mr", pet.get("def", 0)) * lv_bonus)

	# ── 上块: 立绘(居中+底部辉光) + 名/稀有/Lv 行 + 2列属性 + 被动 ──
	# PoC .dp-portrait: 高156 居中 + 底部 radial 金色辉光; 全身 idle 动画
	# 立绘外包一层等高(156)壳, 壳内底部叠 radial 金辉光(behind) + 立绘(front), 不改 VBox 布局.
	var portrait_wrap := Control.new()
	portrait_wrap.custom_minimum_size = Vector2(0, _sp(156))   # PoC .dp-portrait height:156
	portrait_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_wrap.clip_contents = true
	# 底部 radial 金色辉光 (PoC index.html:563: radial-gradient(ellipse at 50% 80%, rgba(255,216,107,.12), transparent 70%))
	var glow := TextureRect.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.12))   # rgba(255,216,107,.12)
	grad.set_color(1, Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.0))    # transparent 70%
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.8)            # ellipse at 50% 80% (近底部)
	gtex.fill_to = Vector2(0.5, 0.8 + 0.7)        # transparent 70% → 半径 0.7 (纵向)
	gtex.width = 256
	gtex.height = 256
	glow.texture = gtex
	portrait_wrap.add_child(glow)
	# PoC 立绘 = buildPetImgHTML(pet,124) 124px 帧, img max-height 150 (ts:810 / index.html:565).
	#   不撑满壳: 居中一个 124×150(×s) 盒, KEEP_ASPECT_CENTERED 不变形/不放大.
	var portrait := TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_CENTER)
	var pw := float(_sp(124))
	var ph := float(_sp(150))
	portrait.size = Vector2(pw, ph)
	portrait.position = Vector2(-pw * 0.5, -ph * 0.5)   # 居中 (anchor 中心 + 自身一半偏移)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_pet_idle_texture(portrait, pet)
	portrait_wrap.add_child(portrait)            # 立绘在辉光之上
	_dt_portrait.add_child(portrait_wrap)

	# PoC .dp-name-row: 居中, 名 + 填充稀有 badge + Lv
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", _sp(8))
	var nm := Label.new()
	nm.text = pet.get("name", "?")
	nm.add_theme_font_size_override("font_size", _sf(20))
	nm.add_theme_color_override("font_color", rcolor)
	name_row.add_child(nm)
	name_row.add_child(_make_rarity_badge(rarity, rcolor, 12))   # PoC .dp-rarity 填充底 font:12px
	var lvl := Label.new()
	lvl.text = "Lv.%d" % det_lv
	lvl.add_theme_font_size_override("font_size", _sf(13))
	lvl.add_theme_color_override("font_color", Color("#ffd86b"))
	name_row.add_child(lvl)
	_dt_name.add_child(name_row)

	# PoC .dp-stats: 2 列网格 (1fr 1fr)
	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", _sp(12))
	stats_grid.add_theme_constant_override("v_separation", _sp(4))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/hp-icon.png", "生命值", hp))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/atk-icon.png", "攻击力", atk))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/def-icon.png", "防御力", def_))
	stats_grid.add_child(_stat_row("res://assets/sprites/stats/mr-icon.png", "魔抗", mr))
	_dt_stats.add_child(stats_grid)

	# 被动 chip (PoC .dp-passive-chip: 绿底圆角框 + 图标 + 名(#7dffb3) + "被动" pill)
	var passive_raw = pet.get("passive")
	if passive_raw is Dictionary and not (passive_raw as Dictionary).is_empty():
		var passive: Dictionary = passive_raw
		var chip := PanelContainer.new()
		var chip_sb := StyleBoxFlat.new()
		chip_sb.bg_color = Color(125.0/255, 1, 179.0/255, 0.08)
		chip_sb.border_color = Color(125.0/255, 1, 179.0/255, 0.28)
		chip_sb.set_border_width_all(1)
		chip_sb.set_corner_radius_all(_sp(8))
		chip_sb.content_margin_left = _sp(8); chip_sb.content_margin_right = _sp(8)   # PoC .dp-passive-chip padding:5px 8px (L/R 8)
		chip_sb.content_margin_top = _sp(5); chip_sb.content_margin_bottom = _sp(5)   # T/B 5
		chip.add_theme_stylebox_override("panel", chip_sb)
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", _sp(6))
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "" and pi_path.ends_with(".png"):
			var full := "res://assets/sprites/" + pi_path
			if ResourceLoader.exists(full):
				var pic := TextureRect.new()
				pic.texture = load(full)
				pic.custom_minimum_size = Vector2(_sp(34), _sp(34))   # 被动图标调大(用户2026-07-18·原22)
				pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				prow.add_child(pic)
		var pnm := Label.new()
		pnm.text = passive.get("name", "被动")
		pnm.add_theme_font_size_override("font_size", _sf(17))   # 被动名调大(用户2026-07-18·原13)
		pnm.add_theme_color_override("font_color", Color("#7dffb3"))
		pnm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(pnm)
		# "被动" pill
		var tag_pc := PanelContainer.new()
		var tag_sb := StyleBoxFlat.new()
		tag_sb.bg_color = Color(125.0/255, 1, 179.0/255, 0.18)
		tag_sb.set_corner_radius_all(_sp(4))
		tag_sb.content_margin_left = _sp(5); tag_sb.content_margin_right = _sp(5)
		tag_sb.content_margin_top = _sp(1); tag_sb.content_margin_bottom = _sp(1)
		tag_pc.add_theme_stylebox_override("panel", tag_sb)
		var tag_lbl := Label.new()
		tag_lbl.text = "被动"
		tag_lbl.add_theme_font_size_override("font_size", _sf(10))
		tag_lbl.add_theme_color_override("font_color", Color("#7dffb3"))
		tag_pc.add_child(tag_lbl)
		prow.add_child(tag_pc)
		chip.add_child(prow)
		# 被动描述只在 hover 看 (1:1 PoC ts:796/825 "悬浮看描述 省空间") — 不常驻铺文字(撑爆面板的自创)
		var fake_f := {"atk": atk, "def": def_, "mr": mr, "maxHp": hp, "crit": pet.get("crit", 0.25), "lv": det_lv, "passive": passive}
		chip.tooltip_text = "%s\n%s" % [passive.get("name", "被动"), SkillText.render_plain(str(passive.get("brief", "")), fake_f, passive)]
		# 内容 IGNORE 鼠标 → 整 chip 捕获 hover 出 tooltip
		prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pnm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 点/触 被动 → 弹窗看描述 (PC 悬停之外再补点按, 手机唯一途径)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var _passive_tip: String = chip.tooltip_text
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_show_detail_popup_from(_passive_tip, Color("#7dffb3"), chip.get_global_rect()))
		_dt_passive.add_child(chip)

	# ── 下块: 技能 3选1 ──
	_build_skill_picker(pet)


func _stat_row(icon_path: String, label: String, val: int) -> HBoxContainer:
	# PoC .dp-stat: icon + 标签(灰,占满) + 值(白,右对齐)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _sp(6))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ResourceLoader.exists(icon_path):
		var ic := TextureRect.new()
		ic.texture = load(icon_path)
		ic.custom_minimum_size = Vector2(_sp(16), _sp(16))
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(ic)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", _sf(13))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var v := Label.new()
	v.text = str(val)
	v.add_theme_font_size_override("font_size", _sf(13))
	v.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(v)
	return row


# ─── 技能 5选3 (PoC refreshDetailPanel 下块 1:1) ────────────────
func _build_skill_picker(pet: Dictionary) -> void:
	var pid: String = pet["id"]
	var pool: Array = pet.get("skillPool", [])
	var selected: Array = _get_panel_loadout(pid)

	# PoC .dp-section-title "技能"(14px金) + .dp-skill-count "选 3 (N/3)"(11px 白@.5 细体, 非金)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", _sp(4))   # .dp-skill-count margin-left:4
	var title := Label.new()
	title.text = "技能"
	title.add_theme_font_size_override("font_size", _sf(14))
	title.add_theme_color_override("font_color", Color("#ffd86b"))
	title_row.add_child(title)
	var count_lbl := Label.new()
	count_lbl.text = "%d 选 1 (主动/被动)" % maxi(1, pool.size() - 1)   # 普攻(idx0)外的候选数; 收敛成[普攻+3技]后=3选1
	count_lbl.add_theme_font_size_override("font_size", _sf(11))   # PoC .dp-skill-count 11px
	count_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))   # rgba(255,255,255,.5)
	count_lbl.size_flags_vertical = Control.SIZE_SHRINK_END   # 底对齐近 baseline
	title_row.add_child(count_lbl)
	_detail_bottom.add_child(title_row)

	# PoC .dp-skill-icons: flex-wrap 居中 (3+2) — 居中容器包 GridContainer
	var grid_center := CenterContainer.new()
	_detail_bottom.add_child(grid_center)
	var icon_grid := GridContainer.new()
	icon_grid.columns = 3
	icon_grid.add_theme_constant_override("h_separation", _sp(8))
	icon_grid.add_theme_constant_override("v_separation", _sp(8))
	grid_center.add_child(icon_grid)

	for i in range(pool.size()):
		var sk: Dictionary = pool[i]
		var is_fixed: bool = i == 0
		var is_sel: bool = i in selected
		var ico := _make_skill_icon(pet, sk, i, is_fixed, is_sel)
		icon_grid.add_child(ico)

	# 已选技能名列表
	var sel_names := ""
	for i in selected:
		if i >= 0 and i < pool.size():
			sel_names += "✓ %s   " % pool[i].get("name", "?")
	var sel_lbl := Label.new()
	sel_lbl.text = sel_names
	sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_lbl.add_theme_font_size_override("font_size", _sf(12))
	sel_lbl.add_theme_color_override("font_color", Color("#ffd86b"))
	sel_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_bottom.add_child(sel_lbl)


func _make_skill_icon(pet: Dictionary, sk: Dictionary, idx: int, is_fixed: bool, is_sel: bool) -> Control:
	var pid: String = pet["id"]
	var unlocked: Array = _available_skill_indices(pet)
	var is_locked: bool = not (idx in unlocked)   # 恒 false: _available_skill_indices 现在返回全部索引(等级解锁已移除)
	var dev_locked: bool = (not is_fixed) and idx != 1 and not sk.get("impl", false)   # 非默认候选: 未标impl:true(未实装)才"开发中"锁; 实装好的技解锁3选1

	var btn: Button = SkillTipButton.new()   # styled tooltip (PoC .dp-skill-tip 悬浮显名+CD+描述)
	btn.custom_minimum_size = Vector2(_sp(64), _sp(64))   # PoC .dp-skill-ico 64px (index.html:606)
	btn.tooltip_text = _skill_tooltip(pet, sk, idx)
	# 图标
	var icon_rel: String = str(sk.get("icon", ""))
	var tex: Texture2D = null
	if icon_rel != "":
		var full := "res://assets/sprites/" + icon_rel
		if ResourceLoader.exists(full):
			tex = load(full)
	if tex == null:
		var passive_raw = pet.get("passive")
		if sk.get("enhancesPassive", false) and passive_raw is Dictionary:
			var pi: String = DataRegistry.passive_icons.get((passive_raw as Dictionary).get("type", ""), "")
			if pi.ends_with(".png"):
				var pfull := "res://assets/sprites/" + pi
				if ResourceLoader.exists(pfull):
					tex = load(pfull)
	if tex != null:
		btn.icon = tex
		btn.expand_icon = true
	else:
		btn.text = str(sk.get("name", "?")).substr(0, 2)
		btn.add_theme_font_size_override("font_size", _sf(10))

	# 边框态: 选中=金#ffd86b+发光 / 锁=暗 / 基础(fixed)=绿rgba(125,255,179,.6) (PoC index.html:631-632)
	var sbn := StyleBoxFlat.new()
	if is_sel:
		# PoC .dp-skill-ico.selected: bg rgba(255,216,107,.14) + 金边 + glow (index.html:631)
		sbn.bg_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.14)
		sbn.border_color = Color("#ffd86b")
		sbn.shadow_color = Color8(0xff, 0xd8, 0x6b, 102)   # box-shadow 0 0 10px rgba(255,216,107,.4)
		sbn.shadow_size = _sp(8)
	elif is_fixed:
		# PoC .dp-skill-ico.fixed: bg rgba(125,255,179,.08) + 绿边 (index.html:632)
		sbn.bg_color = Color(125.0 / 255.0, 1.0, 179.0 / 255.0, 0.08)
		sbn.border_color = Color8(125, 255, 179, 153)   # rgba(125,255,179,.6)
	else:
		# PoC .dp-skill-ico 基础: bg rgba(255,255,255,.04) + 边 rgba(255,255,255,.1) (index.html:605-607)
		sbn.bg_color = Color(1, 1, 1, 0.04)
		sbn.border_color = Color(1, 1, 1, 0.1)
	sbn.set_border_width_all(2)
	sbn.set_corner_radius_all(_sp(12))
	btn.add_theme_stylebox_override("normal", sbn)
	# hover: 金边高亮 (PoC .dp-skill-ico:hover border #ffd86b.7); locked 不高亮
	if is_locked:
		btn.add_theme_stylebox_override("hover", sbn)
	else:
		var sbh: StyleBoxFlat = sbn.duplicate()
		sbh.border_color = Color(1.0, 216.0 / 255.0, 107.0 / 255.0, 0.7)
		btn.add_theme_stylebox_override("hover", sbh)
	btn.add_theme_stylebox_override("pressed", sbn)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	if is_locked:
		btn.modulate = Color(1, 1, 1, 0.45)   # PoC .dp-skill-ico.locked opacity .45 (index.html:633)
		btn.tooltip_text = "已锁定"   # 【不可达】等级解锁已移除(2026-07-10); 分支留作将来若引入其它锁条件
	elif dev_locked:
		btn.modulate = Color(1, 1, 1, 0.5)
		btn.tooltip_text = "候选技开发中, 当前锁定默认签名技"

	# 角标 (PoC .ico-corner bottom-right, index.html:634-641): lock=Lv4/Lv7 / fixed=基础 / selected=✓
	if is_locked:
		btn.add_child(_make_skill_corner("锁", Color("#2a2f3a"), Color("#ccdddd")))   # 【不可达】同上
	elif dev_locked:
		btn.add_child(_make_skill_corner("开发中", Color("#3a2f2a"), Color("#ddc9a0")))
	elif is_fixed:
		btn.add_child(_make_skill_corner("基础", Color("#7dffb3"), Color("#0a2417")))
	elif is_sel:
		btn.add_child(_make_skill_corner("✓", Color("#ffd86b"), Color("#2a1605")))
	# 强化被动 "+" 角标 (PoC .ico-plus 右上金圈, index.html:614-618)
	if sk.get("enhancesPassive", false) or sk.get("iconPlus", false):
		btn.add_child(_make_ico_plus())

	var clickable: bool = not is_locked and not is_fixed and not dev_locked
	if clickable:
		var ix := idx
		var pi := pid
		btn.pressed.connect(func() -> void: _toggle_skill(pi, ix))
	else:
		btn.disabled = is_locked   # 基础(0) 可点但提示必选
		if is_fixed:
			btn.disabled = false
			var pi2 := pid
			btn.pressed.connect(func() -> void: _flash_status("基础技能必选"))
		elif dev_locked:
			btn.disabled = false
			btn.pressed.connect(func() -> void: _flash_status("该候选技开发中, 暂锁默认签名技"))
	# 点/触 技能图标 → 弹窗看名+龟能+描述 (手机无 hover 的唯一途径; 与选中互不影响)
	var _skinfo: String = _skill_tooltip(pet, sk, idx)
	if not btn.disabled:
		btn.pressed.connect(func() -> void: _show_detail_popup_from(_skinfo, Color("#ffd86b"), btn.get_global_rect()))
	return btn


## PoC .ico-corner (index.html:634-641): 图标右下角小圆角徽章, 探出 6px (bottom:-6 right:-6)。
func _make_skill_corner(txt: String, bg: Color, fg: Color) -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(_sp(8))
	sb.content_margin_left = _sp(3); sb.content_margin_right = _sp(3)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = _sp(1); sb.shadow_offset = Vector2(0, _sp(1))
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", _sf(9))   # PoC .ico-corner 9px 800
	l.add_theme_color_override("font_color", fg)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	pc.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pc.position += Vector2(_sp(6), _sp(6))   # 探出右下 6px
	return pc


## PoC .ico-plus (index.html:614-618): 强化被动技能右上金圈 "+"。
func _make_ico_plus() -> Control:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffd86b")
	sb.set_corner_radius_all(_sp(9))
	sb.content_margin_left = _sp(4); sb.content_margin_right = _sp(4)
	sb.shadow_color = Color(0, 0, 0, 0.5); sb.shadow_size = _sp(1); sb.shadow_offset = Vector2(0, _sp(1))
	pc.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = "+"
	l.add_theme_font_size_override("font_size", _sf(12))
	l.add_theme_color_override("font_color", Color("#2a1605"))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(l)
	pc.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pc.grow_vertical = Control.GROW_DIRECTION_END
	pc.position += Vector2(_sp(6), -_sp(6))   # 探出右上 (top:-6 right:-6)
	return pc


func _skill_tooltip(pet: Dictionary, sk: Dictionary, idx: int = -1) -> String:
	# 数值随存档等级 (1:1 PoC fakeF: base×getLevelBonus, lv=真实等级; 原硬编 lv:1+裸值=等级没同步)
	var tlv: int = GameState.get_pet_level(str(pet.get("id", "")))
	var tb: float = 1.0 + (tlv - 1) * 0.05
	var hp: int = roundi(pet.get("hp", 0) * tb)
	var atk: int = roundi(pet.get("atk", 0) * tb)
	var def_: int = roundi(pet.get("def", 0) * tb)
	var mr: int = roundi(pet.get("mr", pet.get("def", 0)) * tb)
	var fake_f := {"atk": atk, "def": def_, "mr": mr, "maxHp": hp, "crit": pet.get("crit", 0.25), "lv": tlv, "passive": pet.get("passive")}
	var brief: String = SkillText.render_plain(str(sk.get("brief", "")), fake_f, sk)
	var head: String = str(sk.get("name", "?"))
	if SkillEnergy.is_active(str(sk.get("type", ""))):   # 龟能口径(无"CD"): 主动技显龟能花费, 攒满才放
		head += " (龟能%d)" % _skill_energy(sk)
	var body := brief
	# 双形态配对技能 (PoC TeamSelectScene.ts:860-874): 换形龟显近战/火山对应技能
	if idx >= 0:
		var sk_name: String = str(sk.get("name", ""))
		var melee: Array = pet.get("meleeSkills", [])
		if idx < melee.size():
			var ms: Dictionary = melee[idx]
			if str(ms.get("name", "")) != sk_name and ms.get("name", "") != "":
				body += "\n近战：%s — %s" % [ms.get("name", ""), SkillText.render_plain(str(ms.get("brief", "")), fake_f, ms)]
		var volcano: Array = pet.get("volcanoSkills", [])
		if idx < volcano.size() and not sk.get("passiveSkill", false):
			var vs: Dictionary = volcano[idx]
			if not vs.get("passiveSkill", false) and str(vs.get("name", "")) != sk_name and vs.get("name", "") != "":
				body += "\n火山：%s — %s" % [vs.get("name", ""), SkillText.render_plain(str(vs.get("brief", "")), fake_f, vs)]
	return "%s\n%s" % [head, body]


# ─── 技能 5选3 逻辑 (PoC getPanelLoadout / toggleSkillInPanel 1:1) ──
## 实时版 = 【3选1】: idx0 普攻常驻, idx1..3 三个候选【全部可选, 无等级门槛】。
##
## ★2026-07-10 移除了 idx3 需 Lv.4 / idx4 需 Lv.7 的等级解锁 —— 那是回合制 PoC 的
##   `getPetLevel + skillUnlockLevel` 残留, 与用户的 3选1 设计直接冲突:
##     〖用户 2026-06-30 13:16 逐字〗"这只龟现在是3个技能选一个来登场, 其他龟我也会慢慢的
##       将4个可选改为3可选来降低复杂度和提升维护性"
##   而 `pet_levels` 默认 1 且"只调试面板改" → 实机上 idx3 永远 locked,
##   `clickable = not is_locked ...` 使它点不动 → 所谓"3选1"实际是【2选1】, 第三个候选谁也选不到。
##   transcript 里 "解锁" 命中 0 次 = 用户从没要过技能等级解锁。
func _available_skill_indices(pet: Dictionary) -> Array:
	var pool: Array = pet.get("skillPool", [])
	var idxs: Array = []
	for i in range(pool.size()):
		idxs.append(i)
	return idxs


# 4选1: 当前选中的那个候选索引 (1..4); skillPool[0]=普攻不参与选.
func _chosen_candidate(pid: String, pet: Dictionary) -> int:
	var unlocked: Array = _available_skill_indices(pet)
	var lo = GameState.loadouts.get(pid, null)
	var idx := -1
	if lo is int or lo is float:
		idx = int(lo)
	elif lo is Array and not (lo as Array).is_empty():   # 兼容旧"选3"数组: 取首个非普攻
		for v in lo:
			if int(v) >= 1:
				idx = int(v); break
	if idx < 1 or not (idx in unlocked):                 # 无效/未解锁 → 默认首个解锁的候选
		idx = -1
		for u in unlocked:
			if int(u) >= 1:
				idx = int(u); break
		if idx < 0:
			idx = 1
	return idx

func _get_panel_loadout(pid: String) -> Array:
	var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	if pet.is_empty():
		return []
	return [_chosen_candidate(pid, pet)]   # 单选 → [选中候选] (供图标高亮)


func _toggle_skill(pid: String, idx: int) -> void:
	var pet: Dictionary = DataRegistry.pet_by_id.get(pid, {})
	if pet.is_empty():
		return
	if idx == 0:
		_flash_status("普攻自动施放, 无需选择")        # skillPool[0]=普攻
		return
	var unlocked: Array = _available_skill_indices(pet)
	if not (idx in unlocked):
		_flash_status("该技能已锁定")   # 【不可达】等级解锁已移除(2026-07-10)
		return
	# 3选1: idx1=默认签名技恒可选; idx2/3 候选需 impl:true(与按钮层 dev_locked L1250 同一门控)。
	#   旧的 `if idx != 1` 一刀切拦截是陈旧死码, 与 impl 标记矛盾(28龟 idx2/3 全 impl:true) → 已拆, 改成逐技校验。
	var pool: Array = pet.get("skillPool", [])
	if idx < 0 or idx >= pool.size():
		return
	var sk: Dictionary = pool[idx]
	if idx != 1 and not bool(sk.get("impl", false)):
		_flash_status("该候选技开发中, 暂锁默认签名技")
		return
	GameState.loadouts[pid] = idx                       # 3选1: 单选, 点哪个就替换成哪个
	_refresh_slots()
	_refresh_confirm()
	_refresh_detail()


# ══════════════════════════════════════════════════════════════
# 编队交互
# ══════════════════════════════════════════════════════════════
func _set_detail_pet(pid: String) -> void:
	detail_pet_id = pid
	_refresh_detail()


## 点卡片: 有空槽则入队 (PoC onPickPet — 找首个空槽)
func _on_pick_pet(pid: String) -> void:
	if _roster_locked:
		return   # 大轮锁定: 卡片点击只看详情(由 gui_input 的 _set_detail_pet 处理), 不入队
	if pid in team:
		return   # 已在队中, 只查看
	var placed := 0
	for t in team:
		if t != null and not _is_special_mark(t):
			placed += 1
	if placed >= REQUIRED_PETS:
		_flash_status("已选 %d 只, 点击龟或格子可移除" % REQUIRED_PETS)   # 1:1 PoC onPickPet toast(:1556) — 原"⚠队伍已满(3/3)"是自创
		return
	# 优先填 active 槽 (PoC onPickPet:1561), 否则首个空槽
	var empty_idx := -1
	if _active_slot_idx >= 0 and team[_active_slot_idx] == null:
		empty_idx = _active_slot_idx
		_active_slot_idx = -1
	else:
		empty_idx = team.find(null)
	if empty_idx < 0:
		return
	team[empty_idx] = pid
	_sync_special_slots()   # 新龟可能是 hiding/crystal/candy → 加随从占位
	detail_pet_id = pid     # 入队后右栏跟着切到这只 (PoC:1571)
	_save_team()
	_refresh_after_team()
	_refresh_detail()


## 点槽: tap-to-swap (1:1 PoC onSlotClick TeamSelectScene.ts:1579) —
##   满槽首点=选中 / 再点同槽=取消+移除(mark不移) / 再点异满槽=互换 / 空槽=移已选龟来 或 toggle active
func _on_slot_click(idx: int) -> void:
	if _roster_locked:
		if team[idx] != null and not _is_special_mark(team[idx]):
			_set_detail_pet(str(team[idx]))   # 锁定态: 点槽=查看该龟(调技能), 不换位/不移除
		return
	var id = team[idx]
	var is_mark: bool = id != null and _is_special_mark(id)
	# === 满槽路径 ===
	if id != null:
		if _selected_slot_idx == -1:
			_selected_slot_idx = idx           # 首次 tap: 选中
			_active_slot_idx = -1
			_refresh_slots()
			return
		if _selected_slot_idx == idx:
			_selected_slot_idx = -1            # 二次 tap 同槽: 取消选中 + 移除 (mark 不移)
			if not is_mark:
				team[idx] = null
				_sync_special_slots()
				_save_team()
			_refresh_after_team()
			return
		# 二次 tap 不同满槽: SWAP
		var other := _selected_slot_idx
		var other_is_mark: bool = _is_special_mark(team[other])
		if is_mark or other_is_mark:
			# mark 只能移到空格, 不能与满槽互换 (PoC:1609)
			var mark_from := other if other_is_mark else idx
			var target := idx if other_is_mark else other
			var mark_value = team[mark_from]
			if team[target] != null:
				_flash_status("%s 不能被替换" % _mark_label(mark_value))
				_selected_slot_idx = -1
				_refresh_slots()
				return
			team[target] = mark_value
			team[mark_from] = null
		else:
			# 普通 swap
			var tmp = team[other]
			team[other] = team[idx]
			team[idx] = tmp
		_selected_slot_idx = -1
		_save_team()
		_refresh_after_team()
		return
	# === 空槽路径 ===
	# (a) 有选中满槽 → 把已选龟移到这 (PoC:1640)
	if _selected_slot_idx >= 0 and team[_selected_slot_idx] != null:
		team[idx] = team[_selected_slot_idx]
		team[_selected_slot_idx] = null
		_selected_slot_idx = -1
		_sync_special_slots()
		_save_team()
		_refresh_after_team()
		return
	# (b) 空槽 toggle active — 下次点卡片入此槽 (PoC:1651)
	_selected_slot_idx = -1
	_active_slot_idx = -1 if _active_slot_idx == idx else idx
	_refresh_slots()


func _refresh_after_team() -> void:
	_refresh_slots()
	_refresh_grid()
	_refresh_confirm()


func _mark_label(mark) -> String:
	if mark == SUMMON_MARK:
		return "随从位"
	if mark == CRYSTAL_BALL_MARK:
		return "水晶球位"
	return "糖果炸弹位"


# ══════════════════════════════════════════════════════════════
# 拖放 (drag&drop) — 卡片拖入槽 / 满槽间拖动互换 (1:1 PoC dragstart/drop + onDropPet:1160)
#   Godot set_drag_forwarding 把拖放回调转发到本场景, drop 端复用 1:1 的 _on_drop_pet。
# ══════════════════════════════════════════════════════════════
func _make_drag_preview(pet_id: String) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(_sp(56), _sp(56))
	tr.size = Vector2(_sp(56), _sp(56))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = Color(1, 1, 1, 0.8)
	var p := "res://assets/sprites/avatars/%s.png" % pet_id
	if ResourceLoader.exists(p):
		tr.texture = load(p)
	return tr


## 卡片拖起 (drag_func; bind 顺序 → (at_pos, source, pet_id))
func _card_drag(_at_pos: Vector2, source: Control, pet_id: String) -> Variant:
	if _roster_locked:
		return null   # 大轮锁定: 禁拖入
	if pet_id == "":
		return null
	source.set_drag_preview(_make_drag_preview(pet_id))
	return {"pet_id": pet_id}


## 满槽拖起 (drag_func; bind → (at_pos, panel, idx)) — 拖的是该槽里的龟/占位 id
func _slot_drag(_at_pos: Vector2, panel: Control, idx: int) -> Variant:
	if _roster_locked:
		return null   # 大轮锁定: 禁槽间换位
	var id = team[idx]
	if id == null:
		return null
	panel.set_drag_preview(_make_drag_preview(str(id)))
	return {"pet_id": str(id)}


func _slot_can_drop(_at_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("pet_id")


## drop 到槽 (drop_func; bind → (at_pos, data, idx))
func _slot_drop(_at_pos: Vector2, data: Variant, idx: int) -> void:
	if data is Dictionary and (data as Dictionary).has("pet_id"):
		_on_drop_pet(str((data as Dictionary)["pet_id"]), idx)


## 拖放落点处理 (1:1 PoC onDropPet TeamSelectScene.ts:1160)
func _on_drop_pet(pet_id: String, slot_idx: int) -> void:
	if _roster_locked:
		return   # 大轮锁定: 忽略任何落点(防拖放绕过)
	var old_idx := team.find(pet_id)
	var existing = team[slot_idx]
	if existing == pet_id:
		return
	# 拒绝把龟拖到 mark 占位上
	if existing != null and _is_special_mark(existing) and not _is_special_mark(pet_id):
		_flash_status("%s 不能被替换" % _mark_label(existing))
		return
	# 拖 mark 自己: 只能放空格
	if _is_special_mark(pet_id):
		if existing != null:
			_flash_status("%s 只能拖到空格" % _mark_label(pet_id))
			return
		if old_idx >= 0:
			team[old_idx] = null
		team[slot_idx] = pet_id
		_save_team()
		_refresh_after_team()
		return
	# swap: 现有龟放回 dragged 龟的旧槽
	if existing != null and old_idx >= 0:
		team[old_idx] = existing
	elif old_idx >= 0:
		team[old_idx] = null
	# cap 3 (不算 marks) — 仅"从网格拖入空槽"时校验
	if old_idx < 0 and existing == null:
		var placed := 0
		for t in team:
			if t != null and not _is_special_mark(t):
				placed += 1
		if placed >= REQUIRED_PETS:
			_flash_status("已选 3 只, 先移除再放置")
			return
	team[slot_idx] = pet_id
	_sync_special_slots()
	detail_pet_id = pet_id   # 拖入后右栏切到这只 (PoC:1201)
	_save_team()
	_refresh_after_team()
	_refresh_detail()


func _on_clear_all() -> void:
	if _roster_locked:
		_flash_status("本大轮阵容已锁定 · 无法清空(新赛季才能重选)")
		return
	team = [null, null, null]
	_selected_slot_idx = -1
	_active_slot_idx = -1
	_save_team()
	_refresh_after_team()


func _on_restore_last() -> void:
	if _roster_locked:
		return   # 大轮锁定: 禁"上次阵容"覆盖
	var last := _read_last_lineup()
	if not last.has("slotMap"):
		return
	team = [null, null, null]
	_selected_slot_idx = -1
	_active_slot_idx = -1
	var slot_map: Dictionary = last["slotMap"]
	for k in slot_map:
		var si := SLOT_KEYS.find(k)
		if si >= 0:
			team[si] = slot_map[k]
	_refresh_all()


# ══════════════════════════════════════════════════════════════
# 开始 / 返回
# ══════════════════════════════════════════════════════════════
func _on_start() -> void:
	var picked: Array = []
	var slots: Array = []
	for i in range(3):
		# 特殊占位 (随从/水晶球/糖果炸弹) 不进 left_team — 战斗端运行时自动找槽
		if team[i] != null and not _is_special_mark(team[i]):
			picked.append(team[i])
			slots.append(SLOT_KEYS[i])
	if picked.size() != REQUIRED_PETS:
		return

	# 实时版: 选龟只定【我方】3 统领 + 技能 loadout. 对手由下一步「匹配」(Matchmaking) 抽 ghost/bot,
	#   战斗端 RealtimeBattle3DScene 读 season_leaders(左队) + dual_ghost.leaders(右队). 这里不再现场抽对手,
	#   也不走回合制的规则之日/DualLaneMap/Battle.
	var left_typed: Array[String] = []
	for p in picked:
		left_typed.append(p)
	var left_slots_typed: Array[String] = []
	for s in slots:
		left_slots_typed.append(s)
	GameState.left_team = left_typed
	GameState.left_slots = left_slots_typed
	GameState.season_leaders = left_typed.duplicate()   # 战斗左队读这个 (RealtimeBattle3DScene._season_leaders)

	_write_last_lineup()

	# → 匹配动画 (Matchmaking): 抽对手 ghost 写 dual_ghost → 进 2.5D 战斗.
	get_tree().change_scene_to_file("res://scenes/Matchmaking.tscn")


func _on_back() -> void:
	GameState.reset_dungeon()
	GameState.clear_team()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")



# ══════════════════════════════════════════════════════════════
# 持久化 (上次阵容 — PoC lastLineup 1:1, 存 user://lastLineup.json)
# ══════════════════════════════════════════════════════════════
const LAST_PATH := "user://lastLineup.json"

func _read_last_lineup() -> Dictionary:
	if not FileAccess.file_exists(LAST_PATH):
		return {}
	var f := FileAccess.open(LAST_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var parsed = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


func _write_last_lineup() -> void:
	var slot_map: Dictionary = {}
	var ids: Array = []
	for i in range(3):
		if team[i] != null and not _is_special_mark(team[i]):   # 排除特殊占位(summon/crystal/candy): 否则 ids=4 早退→上次阵容永不保存; 恢复时 _refresh_all→_sync_special_slots 重derive
			slot_map[SLOT_KEYS[i]] = team[i]
			ids.append(team[i])
	if ids.size() != 3:
		return
	var f := FileAccess.open(LAST_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"ids": ids, "slotMap": slot_map}))


# 当前阵容临时记忆 (本会话, 进战斗回来还在) — 简化: 用 _read_last_lineup 兜
func _save_team() -> void:
	# 持久化 6 槽阵容草稿 (含未确认的 1-2 龟 + 槽位) → 离开再回来还在 (1:1 PoC saveTeam localStorage[LS_KEY])
	var f := FileAccess.open(TEAM_DRAFT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(team))
		f.close()


func _load_team() -> void:
	# 优先从 GameState 恢复【已确认】阵容 (从战斗返回时); 否则读草稿恢复【未确认】阵容 (1:1 PoC loadTeam)
	if GameState.left_team.size() == 3:
		team = [null, null, null]
		for i in range(GameState.left_team.size()):
			var sk: String = GameState.left_slots[i] if i < GameState.left_slots.size() else SLOT_KEYS[i]
			var si := SLOT_KEYS.find(sk)
			if si < 0:
				si = i
			team[si] = GameState.left_team[i]
		return
	# 草稿恢复 (1:1 PoC loadTeam: 6 槽数组, 验 id 在已知龟内否则置 null)
	if not FileAccess.file_exists(TEAM_DRAFT_PATH):
		return
	var fr := FileAccess.open(TEAM_DRAFT_PATH, FileAccess.READ)
	if fr == null:
		return
	var raw := fr.get_as_text()
	fr.close()
	var parsed = JSON.parse_string(raw)
	if parsed is Array and parsed.size() == team.size():
		for i in range(team.size()):
			var id = parsed[i]
			team[i] = id if (id is String and DataRegistry.pet_by_id.has(id)) else null


# ══════════════════════════════════════════════════════════════
# 工具
# ══════════════════════════════════════════════════════════════
func _flash_status(msg: String) -> void:
	status_bar.text = msg
	# PoC showToast (TeamSelectScene.ts:1975): fade-in .2s → 显示 1.8s → fade-out .2s
	status_bar.modulate = Color(1, 0.9, 0.4, 0.0)
	var tween := create_tween()
	tween.tween_property(status_bar, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.8)
	tween.tween_property(status_bar, "modulate:a", 0.0, 0.2)


## 该技的龟能花费: 【pets.json 的 energyCost 优先】, 缺了才退回 SkillEnergy 类型兜底。
## ★2026-07-10: 与战斗 `_skill_cost`(RealtimeBattle3DScene.gd) 和图鉴 CodexScene 同口径。
##   此前这里只读 SkillEnergy.cost_of() → 彩虹·棱镜护盾 界面显 70 而实战花 50;
##   彩虹·反射 SkillEnergy 表里根本没有 → 显的是兜底值。两处都在骗玩家。
func _skill_energy(sk: Dictionary) -> int:
	var ec = sk.get("energyCost", null)
	if ec != null:
		return int(round(float(ec)))
	return int(round(SkillEnergy.cost_of(str(sk.get("type", "")))))
