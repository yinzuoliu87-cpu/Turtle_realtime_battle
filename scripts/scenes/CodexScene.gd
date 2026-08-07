extends Node2D

## CodexScene — 图鉴 (5 Tab: 龟/装备/羁绊/状态/规则). 1:1 PoC CodexScene.ts 像素布局移植.
## 详情容器 (UI/Detail) 左上 = PoC detailX,detailY = (340,150) → PoC 详情局部坐标直接对应.

@onready var title_lbl: Label = $UI/Title
@onready var tab_bar: Control = $UI/TabBar
@onready var list_bg: ColorRect = $UI/ListBg
@onready var list_scroll: ScrollContainer = $UI/ListScroll
@onready var list_vbox: VBoxContainer = $UI/ListScroll/ListVBox
var _row_press_pos := Vector2.ZERO   # 触屏点选/滑动判定: 记按下位置, 松开位移小才算点选(手机2026-07-18)
var _codex_list := CodexList.new(self)   # 图鉴·左栏列表行构建(龟/装备/状态/分组头/简单行·back_button和共享_add_text/image/portrait/rect留主场景)(2026-07-25 抽出)
var _codex_detail := CodexDetail.new(self)   # 图鉴·右栏详情视图(龟/装备/羁绊(类型)/状态/规则/小将 13渲染函数)(2026-07-25 抽出)
@onready var detail_bg: ColorRect = $UI/DetailBg
# ★2026-08-03 详情改可滚动。这里【故意】做了一次换名:
#   detail_frame = 场景里那个固定 900×550 的框(UI/DetailBg 画着边框)——入场 tween / 居中偏移打它;
#   detail       = 框内新建的【内容层】——所有 detail.add_child(…) 的绝对坐标语义完全不变。
#   这样 20 处 host.detail.add_child 一行都不用改, 而内容超高时能滚到底(原来直接裁尾)。
@onready var detail_frame: Control = $UI/Detail
var detail: Control                       # 内容层(ScrollContainer 的子)——在 _ready 里建
var _detail_scroll: ScrollContainer
@onready var status_bar: Label = $UI/StatusBar

const RARITY_COLOR := {
	"C": "#06d6a0", "B": "#4cc9f0", "A": "#3a9abf",
	"S": "#c77dff", "SS": "#ffd93d", "SSS": "#ff6b6b",
}
# ── 二阶段双路装备 (p2eq) 费用/稀有度配色 (装备 Tab 用) ──
# 装备 Tab 不再展示旧 e_ 装备(DataRegistry.all_equipment), 改展示上线野生=duallane 实际用的 59 件 p2eq
#   (DataRegistry.phase2_equipment, data/phase2-equipment.json) 按费用 1→5 分组, 末尾追加 8 件消耗品。
# 费用分组配色 (费用越高越"贵": 灰→绿→蓝→紫→金 · 1:1 常见档位色 · 2费=绿/3费=蓝·用户2026-07-27修): 组标题 + 行描边 都用它。
#   (装备数据只有 cost、无 rarity 字段, 不按品质分色。原 const P2EQ_RARITY_COLOR 从没被用过 → 删掉的死代码。)
const COST_COLOR := {
	1: "#94a3b8", 2: "#06d6a0", 3: "#4cc9f0", 4: "#c77dff", 5: "#ffd93d",
}
# 稀有度倍率取 DataRegistry.rarity_mult (=rarity-mult.json {S:1.09…}, 同战斗引擎 fighter.gd:127 + PoC pets.ts RARITY_MULT)。
# 原硬编 {S:1.5/SS:1.75/SSS:2.0} 是自创错值 → 图鉴数值全部虚高且与实战/PoC不符 (用户报"数值不太对")。
const TABS := [
	["pets", "🐢 龟"], ["equips", "⚔ 装备"], ["synergies", "🔗 羁绊"],
	["status", "💫 状态"], ["rules", "📜 规则"],
]
# PoC 详情内部排版宽 (CodexScene.ts: pets/synergy/status/rule detailW=900, equip=920)
const DETAIL_W := 900.0
const LIST_W := 280.0

# ── 羁绊 = 装备【类型】(10 个)。2026-08-03 批1: 学派系统已删除, 类型成为唯一羁绊维度(方案书 D1/D2) ──
# 类型定义(阈值/逐档文案)取自 Phase2Types; 成员装备由 p2eq-types.json 反查。
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")   # 类型(10)映射: p2eq-types.json
const SkillEnergy := preload("res://scripts/systems/skill_energy.gd")   # 龟能花费 单一事实源 (跟战斗同口径)
const EquipStats := preload("res://scripts/gamedata/equip_stats.gd")   # 装备属性 单一事实源 STATS (跟战斗/背包同口径; 2026-07-23 从回合制P2RT抽出)
const TurtleStats := preload("res://scripts/gamedata/turtle_stats.gd")    # 龟战斗属性 单一事实源(移速/攻速/射程, 跟战斗同源·点5)

# 技能在实时版里的角色: passive(被动) / basic(普攻,不花龟能) / active(主动,花龟能). 跟战斗 BASIC_ATK+改造一致.
#   普攻=skillPool[0] (忍者已改回近战刺客: 斩击=普攻idx0, 冲击转被动auto-dash不占技位).
func _skill_role(pet_id: String, sk: Dictionary, i: int) -> String:
	if sk.get("passiveSkill", false):
		return "passive"
	return "basic" if i == 0 else "active"


## ★龟能事实源必须与战斗一致: 战斗 `_skill_cost()` = pets.json 的 `energyCost` 优先, 缺则 SkillEnergy 表兜底。
## 原来图鉴只读 SkillEnergy.cost_of(type) → 两处对不上就在骗玩家:
##   · 彩虹「护盾」: 战斗 50, 图鉴显 70 (type "shield" 是多龟共用的通用键, 一个值套不了所有龟)
##   · 彩虹「反射」: SkillEnergy 表里根本没有 rainbowReflect → 图鉴显【龟能 0】, 战斗实际 110
func _skill_energy(sk: Dictionary) -> int:
	if sk.has("energyCost"):
		return int(round(float(sk["energyCost"])))
	return int(round(SkillEnergy.cost_of(str(sk.get("type", "")))))

# 各类型强调色 + emoji (无 tag PNG → 用 emoji 占位; 颜色用于列表描边/标题)。★2026-08-03 批1:
#   原来这里是 11 学派的 SCHOOL_STYLE + 66 行 SCHOOL_EFFECTS 文案。学派系统已整体删除(方案书 D1),
#   羁绊只剩【类型】这一维。逐档效果文案的事实源改为 Phase2Types.TIER_DESCS ——
#   ★不再在图鉴里手抄一份: 原来 SCHOOL_EFFECTS 是"实时版口径"、phase2_schools.gd 是"回合制口径",
#   两份互相矛盾且都自称权威(方案书 §4.1 表格第 3 行点名了这件事)。现在只有一份。
const TYPE_STYLE := {
	"剑":   {"color": "#ff6b6b", "emoji": "🗡️"},
	"奇械": {"color": "#60a5fa", "emoji": "⚙️"},
	"食物": {"color": "#ff7ab8", "emoji": "🍖"},
	"盾":   {"color": "#ffd93d", "emoji": "🛡️"},
	"药水": {"color": "#22d3ee", "emoji": "🧪"},
	"枪":   {"color": "#fb923c", "emoji": "🔫"},
	"弓箭": {"color": "#9d4edd", "emoji": "🏹"},
	"法器": {"color": "#34d399", "emoji": "🔮"},
	"灵物": {"color": "#c084fc", "emoji": "🐙"},
	"遗物": {"color": "#a3e635", "emoji": "🏺"},
}

var current_tab: String = "pets"
var _items: Array = []
var _sel_idx: int = -1   # 当前选中条目 idx (调试面板改等级后刷新用)


## ← 返回主菜单 (1:1 PoC CodexScene.ts:68 makeIconButton 40,40 → MainMenuScene). 原 Godot 无 → 图鉴死胡同。
func _add_back_button() -> void:
	var back := Button.new()
	back.text = "←"
	back.add_theme_font_size_override("font_size", 26)
	var _m := SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	back.position = Vector2(maxf(20.0, _m.x), _m.y)   # 手机刘海/圆角: 左上角留安全区(桌面仍是 20/18)
	back.custom_minimum_size = Vector2(44.0, 44.0)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	$UI.add_child(back)
	# 🛠 调试面板 (右上角, 仅 debug 构建显示 — 1:1 PoC DEV_VISIBLE; 设等级/加币/重置/快速对战)
	if OS.is_debug_build():
		var dbg := Button.new()
		dbg.text = "🛠"
		dbg.add_theme_font_size_override("font_size", 22)
		dbg.position = Vector2(float(get_viewport().get_visible_rect().size.x) - 64.0 - SafeArea.insets(Vector2(get_viewport().get_visible_rect().size)).z, 18.0)
		dbg.custom_minimum_size = Vector2(44.0, 44.0)
		dbg.focus_mode = Control.FOCUS_NONE
		dbg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		dbg.pressed.connect(_toggle_debug_overlay)
		$UI.add_child(dbg)


## 🛠 调试面板 (1:1 PoC MenuDebugOverlay): 设全体等级/加币/重置/快速对战 (dev 工具)
func _toggle_debug_overlay() -> void:
	var ex := get_node_or_null("DebugOverlay")
	if ex:
		ex.queue_free()
		return
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.name = "DebugOverlay"
	add_child(layer)
	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0, 0, 0, 0.55)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			layer.queue_free())
	layer.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)
	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#141d2e"); sb.border_color = Color("#58a6ff"); sb.set_border_width_all(2); sb.set_corner_radius_all(10)
	sb.content_margin_left = 22; sb.content_margin_right = 22; sb.content_margin_top = 18; sb.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); box.add_child(vb)
	var title := Label.new(); title.text = "🛠 调试面板"; title.add_theme_font_size_override("font_size", 20); title.add_theme_color_override("font_color", Color("#58a6ff")); vb.add_child(title)
	var info := Label.new(); info.add_theme_font_size_override("font_size", 13); info.add_theme_color_override("font_color", Color("#9aa6b2")); vb.add_child(info)
	var refresh_info := func() -> void:
		var lv_count: Dictionary = {}
		for p in DataRegistry.all_pets:
			var l: int = GameState.get_pet_level(str(p.get("id", "")))
			lv_count[l] = int(lv_count.get(l, 0)) + 1
		var summ := ""
		for k in lv_count:
			summ += "Lv%d×%d  " % [k, lv_count[k]]
		var force := ("强制全体 Lv.%d (含对手)" % GameState.debug_level) if GameState.debug_level > 0 else "强制等级: 关"
		info.text = "龟币: %d   龟种: %d\n等级分布: %s\n战斗: %s" % [GameState.coins, DataRegistry.all_pets.size(), summ, force]
	refresh_info.call()
	vb.add_child(_dbg_label("全体等级 (战斗内强制两队同档)"))
	var lv_row := HBoxContainer.new(); lv_row.add_theme_constant_override("separation", 8)
	for lvv in [1, 2, 5, 10]:
		var b := _dbg_btn("全员 Lv.%d" % lvv)
		b.pressed.connect(func() -> void:
			GameState.debug_level = lvv                          # 战斗: 强制全体单位等级(两队同档, 见战斗基础-策划焊死.md §三)
			for p in DataRegistry.all_pets:
				GameState.set_pet_level(str(p.get("id", "")), lvv)   # 图鉴显示: 各龟等级
			if _sel_idx >= 0:
				_select(_sel_idx)
			refresh_info.call())
		lv_row.add_child(b)
	vb.add_child(lv_row)
	vb.add_child(_dbg_label("龟币"))
	var coin_row := HBoxContainer.new(); coin_row.add_theme_constant_override("separation", 8)
	for amt in [100, 500]:
		var b := _dbg_btn("+%d 龟币" % amt)
		b.pressed.connect(func() -> void:
			GameState.coins += amt; GameState.save(); refresh_info.call())
		coin_row.add_child(b)
	vb.add_child(coin_row)
	var reset := _dbg_btn("重置 (等级+龟币)")
	reset.pressed.connect(func() -> void:
		GameState.pet_levels = {}; GameState.coins = 0; GameState.debug_level = 0; GameState.save()
		if _sel_idx >= 0:
			_select(_sel_idx)
		refresh_info.call())
	vb.add_child(reset)
	var close := _dbg_btn("× 关闭")
	close.pressed.connect(func() -> void: layer.queue_free())
	vb.add_child(close)


func _dbg_label(txt: String) -> Label:
	var l := Label.new(); l.text = txt; l.add_theme_font_size_override("font_size", 14); l.add_theme_color_override("font_color", Color("#ffd93d"))
	return l


func _dbg_btn(txt: String) -> Button:
	var b := Button.new(); b.text = txt; b.add_theme_font_size_override("font_size", 14); b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _ready() -> void:
	if DataRegistry.all_pets.is_empty():
		status_bar.text = "❌ DataRegistry 未加载"
		return
	status_bar.text = "✓ %d 龟 / %d 装备 / %d 羁绊 / %d 状态 / %d 规则" % [
		DataRegistry.all_pets.size(), _equip_tab_count(),
		Phase2Types.TYPES.size(), DataRegistry.status_defs.size(), DataRegistry.battle_rules.size()]
	# 视口比例由项目级 EXPAND(window/stretch/aspect)保证, 场景切换不翻转 aspect → 入场丝滑(同 TeamSelect)。
	#   同步建完(无 await), 首帧即完整布局, 无半成品/撕裂帧。背景铺满+居中见 _fill_bg_and_center。
	_build_detail_scroll()
	_fill_bg_and_center()
	_build_tab_bar()
	_add_back_button()   # ← 返回主菜单 (1:1 PoC CodexScene.ts:68) — 原漏了→图鉴出不去
	# 标题掉落入场 (PoC CodexScene.ts:65: y -30→50, 400ms back.out) — 仅开场一次
	title_lbl.position.y -= 80.0
	var tt := create_tween()
	tt.tween_property(title_lbl, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	list_vbox.mouse_filter = Control.MOUSE_FILTER_PASS   # 列表容器透传触摸→ScrollContainer 可触屏拖滑(手机2026-07-18)
	var start_tab := "pets"
	if OS.has_environment("SHOT_TAB"):   # dev: 截图指定 tab (供 diff)
		start_tab = OS.get_environment("SHOT_TAB")
	_switch_tab(start_tab)
	# ★分帧预热图标缓存(2026-08-01 修「点装备那里会卡一下」): 首次进装备页要读 67 张 PNG(~200ms),
	#   提前摊到进图鉴之后的若干帧里, 点页签那一下就不会卡。call_deferred 免得挡住 _ready。
	_codex_list.warm_icons.call_deferred(get_tree())
	if OS.has_environment("CODEX_SHOT"):   # dev: 图鉴自截图(SHOT_TAB=equips CODEX_SHOT=秒 SHOT_OUT=路径)·验框色等·截完自退
		_codex_selfshot()
		return
	var _td = get_node_or_null("/root/TutorialDirector")
	if _td != null:
		_td.attach_guide(self, "codex")        # 分步引导(带高亮: 分类页签)
		_td.attach_next_button(self, "codex")  # 右上"打第二把"推进钮

## dev 图鉴自截图: 等 CODEX_SHOT 秒(默认1.2·让入场动画落定)→ 抓主视口存 SHOT_OUT → 退。可选滚动到 SHOT_SCROLL 像素。
func _codex_selfshot() -> void:
	var s := OS.get_environment("CODEX_SHOT")
	var delay := s.to_float() if s.is_valid_float() and s.to_float() > 0.1 else 1.2
	await get_tree().create_timer(delay).timeout
	# SHOT_SEL=N: 先选中第 N 条再抓 —— 照 ShopScene._shop_selfshot 的同名开关。
	#   没它就只能抓到"默认选中第 0 条", 想验精英小将(在列表末尾)的详情排版根本抓不到。
	#   SHOT_SEL=-1 表示【最后一条】。
	if OS.has_environment("SHOT_SEL"):
		var _sv := OS.get_environment("SHOT_SEL")
		if _sv.is_valid_int():
			var _si := int(_sv)
			if _si < 0:
				_si = _items.size() + _si
			if _si >= 0 and _si < _items.size():
				_select(_si)
				await get_tree().process_frame
				await get_tree().process_frame
	if OS.has_environment("SHOT_SCROLL") and is_instance_valid(list_scroll):
		list_scroll.scroll_vertical = int(OS.get_environment("SHOT_SCROLL"))
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OS.get_environment("SHOT_OUT") if OS.has_environment("SHOT_OUT") else "res://_codex.png")
	get_tree().quit()


## 新手引导高亮锚点(用户2026-07-23 D)。名字→屏幕矩形; 解析不到返回空 Rect2(本步不挖洞)。
func _tutorial_anchor(anchor: String) -> Rect2:
	match anchor:
		"tabs":   # 顶部分类页签栏(龟/装备/羁绊/状态/规则)
			if tab_bar != null and is_instance_valid(tab_bar):
				return tab_bar.get_global_rect()
	return Rect2()


# ── 背景铺满 + 内容居中 (1:1 PoC menu-bg-active 边距 + 1280×720 画布居中) ──
func _fill_bg_and_center() -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	# UI/Background (全锚 ColorRect, EXPAND 下自动填满窗口) 叠 menu 平铺 + 暗渐变
	var bg := get_node_or_null("UI/Background")
	if bg != null and not bg.has_node("Tile"):
		if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
			var tile := TextureRect.new()
			tile.name = "Tile"
			tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存512²纹理 (resize只做一次, 消除进场景LANCZOS卡顿)
			tile.stretch_mode = TextureRect.STRETCH_TILE
			tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 比视口大一格(512) + 漂移循环 (1:1 PoC @keyframes menuBgDrift 25s linear) — 图鉴画布也会动, 与主菜单一致
			tile.size = Vector2(vp.x + 512, vp.y + 512)
			tile.position = Vector2(-512, -512)
			bg.add_child(tile)
			if not (GameState != null and GameState.perf_lite):   # 低画质: 不跑常驻背景漂移 tween
				var drift := tile.create_tween().set_loops()
				drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
		grad.colors = PackedColorArray([
			Color(0.031, 0.047, 0.078, 0.15),
			Color(0.031, 0.047, 0.078, 0.25),
			Color(0.031, 0.047, 0.078, 0.40)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
		gt.width = 8; gt.height = 128
		var ov := TextureRect.new()
		ov.name = "Grad"
		ov.set_anchors_preset(Control.PRESET_FULL_RECT)
		ov.texture = gt
		ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ov.stretch_mode = TextureRect.STRETCH_SCALE
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(ov)
	# 绝对定位面板补居中偏移 (Title/TabBar 全宽锚已自动居中, StatusBar 底部不动)
	var dx := maxf(0.0, (vp.x - 1280.0) / 2.0)
	var dy := maxf(0.0, (vp.y - 720.0) / 2.0)
	if dx > 0.5 or dy > 0.5:
		for n in [list_bg, list_scroll, detail_bg, detail_frame]:
			if n != null:
				n.position += Vector2(dx, dy)


# ── 列表/详情滑入 (1:1 PoC CodexScene.ts:127-138; PoC 每次切 tab scene.restart 重播) ──
# 列表左滑 x-360→0 + alpha (420ms delay150); 详情右滑 x+360→0 + alpha (420ms delay250).
# base x 各 tween 前先记一次, 防多次重播累积漂移.
var _intro_base_x := {}

func _play_list_detail_intro() -> void:
	# 列表从左 (-360), 详情从右 (+360); [节点, 起点偏移, 延迟]
	var specs := [
		[list_bg, -360.0, 0.15], [list_scroll, -360.0, 0.15],
		[detail_bg, 360.0, 0.25], [detail_frame, 360.0, 0.25],
	]
	for s in specs:
		var n: Control = s[0]
		var off: float = s[1]
		var dly: float = s[2]
		if not _intro_base_x.has(n):
			_intro_base_x[n] = n.position.x   # 记录布局基准 x (仅首次)
		var base_x: float = _intro_base_x[n]
		n.position.x = base_x + off
		n.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(n, "position:x", base_x, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(dly)
		tw.tween_property(n, "modulate:a", 1.0, 0.42).set_delay(dly)


# ─── Tab 按钮 (PoC makeTab: 170×36 间隔8; active 0xffd93d / inactive 0x1a2740; 文字15px bold) ───
func _build_tab_bar() -> void:
	for c in tab_bar.get_children():
		c.queue_free()
	var tab_w := 170.0
	var tab_gap := 8.0
	# ★手机板触控热区: 页签高 36 视口像素 = 手机上 20pt, 远低于 iOS HIG 44pt。
	#   页签是主导航, 点不中的代价最大 → 加到 56(30pt)。宽 170 本来就够。
	var tab_h := 56.0
	var total_w := TABS.size() * tab_w + (TABS.size() - 1) * tab_gap
	# ★2026-08-01 门禁抓到: 这里写死 1280 —— 而 TabBar 是全宽锚(跟着视口长),
	#   于是 21:9(视口 1680)上整条页签坐在中心【左边 200px】。用真实视口宽算。
	var start_x := (float(get_viewport().get_visible_rect().size.x) - total_w) / 2.0
	# PoC makeTab label 带数量计数: 🐢 龟 (N) / ⚔ 装备 (N) / 🔗 羁绊 (N) / 💫 状态 (N) / 📜 规则 (N)
	# 装备 Tab 计数 = 59 件 p2eq + 消耗品件数 (上线野生=duallane 实际装备池, 非旧 e_ 装备)
	var tab_counts := {
		"pets": DataRegistry.launch_pets.size(), "equips": _equip_tab_count(),
		"synergies": Phase2Types.TYPES.size(), "status": DataRegistry.status_defs.size(),
		"rules": DataRegistry.battle_rules.size(),
	}
	for i in TABS.size():
		var t: Array = TABS[i]
		var active: bool = t[0] == current_tab
		var b := Button.new()
		b.text = "%s (%d)" % [t[1], int(tab_counts.get(t[0], 0))]
		b.position = Vector2(start_x + i * (tab_w + tab_gap), 0)
		b.custom_minimum_size = Vector2(tab_w, tab_h)
		b.size = Vector2(tab_w, tab_h)
		b.add_theme_font_size_override("font_size", 15)
		_style_tab(b, active)
		var tid: String = t[0]
		b.pressed.connect(func(): _switch_tab(tid))
		tab_bar.add_child(b)


func _style_tab(b: Button, active: bool) -> void:
	# active 底 0xffd93d 字深 #1a1a2e; inactive 底 0x1a2740 字 #ffd93d. 金边 2px.
	var fill := Color("#ffd93d") if active else Color("#1a2740")
	fill.a = 0.9
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	var fg := Color("#1a1a2e") if active else Color("#ffd93d")
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)


func _switch_tab(tab: String) -> void:
	current_tab = tab
	_build_tab_bar()
	_items = []
	for c in list_vbox.get_children():
		c.queue_free()
	# 顶 padding 8 (PoC padding=8)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 8)
	list_vbox.add_child(pad)
	match tab:
		"pets":
			for pet in DataRegistry.launch_pets:
				_items.append(pet)
				_codex_list._add_pet_row(pet)
			# 深海小将(用户2026-07-19「图鉴里补上小将的信息」): 不是龟, 不在 pets.json 里,
			# 战斗中由 _make_unit(spec.minion) 现场造 → 只能用虚拟条目, 数值/技能全部照 RealtimeBattle3DScene 抄
			_codex_list._add_group_header("深海小将")   # 页签计数仍是「龟(28)」, 小将不算龟 → 拿分隔条把两段划开(用户2026-07-19)
			for mk in MINION_KINDS:
				_items.append({"_minion": mk["kind"]})
				_codex_list._add_simple_row(str(mk["name"]), "#cdd9c2", Color("#7a8a96"),
					"res://assets/sprites/pets/%s" % mk["img"], _items.size() - 1)
		"equips":
			_codex_list._add_equip_rows()
		"synergies":
			# 10 装备类型羁绊 (2026-08-03 批1 取代 11 学派). 名序按 Phase2Types.TYPES 声明序.
			for sname in Phase2Types.TYPES.keys():
				_items.append({"_type": sname})
				var style: Dictionary = TYPE_STYLE.get(sname, {})
				var emoji: String = str(style.get("emoji", "🔗"))
				var col: String = str(style.get("color", "#4cc9f0"))
				# 无 tag PNG → emoji 前缀进名字; 描边用学派色 (列表行 _codex_list._add_simple_row 复用)
				_codex_list._add_simple_row("%s %s" % [emoji, sname], col, Color(col), "", _items.size() - 1)
		"status":
			_codex_list._add_status_rows()
		"rules":
			for r in DataRegistry.battle_rules:
				_items.append(r)
				_codex_list._add_simple_row(r.get("name", "?"), "#ffd93d", Color("#06d6a0"),
					"res://assets/sprites/rules/%s.png" % r.get("id", ""), _items.size() - 1)
			# 「小商店物品池」虚拟入口已删 (R3 2026-07-11): 那是回合制/PoC 局内金币小商店(第4/8/12场开张),
			#   实时版 V2 经济已挪局外深海币商店, 战斗内无小商店 → 该页描述玩家永远遇不到的机制, 属知识库分歧, 删除。
			#   规则之日 battle_rules 目前未在实时版战斗生效, 但【用户 2026-07-11 定: 改制后加入, 现在待做】→ rules Tab 保留不删。
	if _items.size() > 0:
		_select(0)
	# 列表/详情滑入 (PoC scene.restart 每次切 tab 重播)
	_play_list_detail_intro()


# ─── 列表行 (PoC: 行高52 gap4, bg 0x1a2740@0.85, 描边稀有度色@0.7) ───
## ★★缓存(2026-08-01 修「点装备那里会卡一下」, 用户报):
##   原来【每调用一次就 new 一个 SystemFont】—— 而 SystemFont 要去系统字体库里按名查找,
##   实测每次约 3ms。左栏每一行的稀有度标签都调它一次 → 装备页 67 行 ≈ 200ms 的【单次阻塞】,
##   60fps 下就是卡住十几帧。实测: 切"装备"页签 208ms, 而其余页签只要 6~38ms。
##   ★字体是不可变资源, 全场景共用一个实例即可; 用 static 让跨场景实例也只查一次。
static var _mono_cached: Font = null

func _mono_font() -> Font:
	if _mono_cached != null:
		return _mono_cached
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Consolas", "Courier New"])
	f.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
	_mono_cached = f
	return f


func _make_row(row_h: float, fill_a: float, stroke: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(LIST_W - 16, row_h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a2740"); sb.bg_color.a = fill_a
	sb.border_color = stroke
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	# 居中行 (左右各 8 留白对应 listW-16)
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 8)
	wrap.add_theme_constant_override("margin_right", 8)
	wrap.add_child(p)
	list_vbox.add_child(wrap)
	return p


func _equip_tab_count() -> int:
	var n: int = DataRegistry.phase2_equipment.size()
	for eq in DataRegistry.all_equipment:
		if eq is Dictionary and eq.get("category", "") == "consumable":
			n += 1
	return n


func _row_passthrough(node: Node) -> void:   # 行内视觉控件全设 IGNORE, 让触摸/拖动透传到行 Panel→再到 ScrollContainer(否则子控件吞掉拖动=手机滑不动·2026-07-18)
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row_passthrough(c)

func _connect_row(p: Panel, idx: int, stroke: Color) -> void:
	p.mouse_filter = Control.MOUSE_FILTER_PASS   # 触屏拖动透传到 ScrollContainer→列表可滑(手机2026-07-18)
	var wrap := p.get_parent()
	if wrap is Control: (wrap as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	_row_passthrough(p)                          # 行内子控件不吞触摸
	p.gui_input.connect(func(ev: InputEvent):
		# 触屏: 按下记位置, 松开时位移小才算"点选"(位移大=在滑动列表→不选). 鼠标左键同理.
		var down: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and ev.pressed)
		var up: bool = (ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and not ev.pressed)
		if down:
			_row_press_pos = ev.position
		elif up and ev.position.distance_to(_row_press_pos) < 14.0:
			_select(idx))
	p.mouse_entered.connect(func():
		var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
		sb.border_color = Color("#ffd93d"))
	p.mouse_exited.connect(func():
		var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
		sb.border_color = stroke)


func _select(idx: int) -> void:
	if idx < 0 or idx >= _items.size():
		return
	_sel_idx = idx
	_codex_form_view = false   # 切换条目重置双形态视图 (回普通技能)
	_codex_skill_detail = {}   # 切换条目重置内联技能详情 (回技能卡列表)
	_codex_passive_view = false   # 切换条目重置被动展开 (回技能卡列表)
	var item: Dictionary = _items[idx]
	match current_tab:
		"pets":
			if item.has("_minion"): _codex_detail._show_minion(str(item["_minion"]))
			else: _codex_detail._show_pet(item)
		"equips": _codex_detail._show_equip(item)
		"synergies": _codex_detail._show_type(item)
		"status": _codex_detail._show_status(item)
		"rules": _codex_detail._show_rule(item)


# ══════════════════════════════════════════════════════════
# 详情面板 helper (在 detail 容器内绝对定位; PoC Phaser 坐标=Godot 同坐标)
# ══════════════════════════════════════════════════════════
## ── 详情可滚动 (2026-08-03) ────────────────────────────────────────────
## 原来是 detail.clip_contents=true 直接【裁尾】: 长条目(熔岩双形态/多技能龟)后半截看不见。
## 现在框内套一层 ScrollContainer, 内容层仍是绝对定位 Control → 调用侧零改动。
const DETAIL_SCROLL_PAD := 14.0   # 底部留白, 免得最后一行贴着边框

func _build_detail_scroll() -> void:
	detail_frame.clip_contents = true       # 框仍然裁: 滚动内容不许画出边框
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_detail_scroll.follow_focus = false
	detail_frame.add_child(_detail_scroll)
	detail = Control.new()
	detail.name = "DetailContent"
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 自己不吃事件→滚轮/拖滑落到 ScrollContainer
	_detail_scroll.add_child(detail)


## 每帧重算内容底边 —— 【不能只算一次】:
##   RichTextLabel(fit_content=true) 的高度是【布局之后】才定的, 建完当帧读 size.y 拿到 0;
##   技能卡展开/收起(_codex_skill_detail)也会改高度, 一次性算完立刻过期。
## 顺带把纯展示的 RichTextLabel 设成 PASS: 它默认 STOP, 会把滚轮/触屏拖动吃掉
##   (同 list_vbox / 列表行的既有做法, 见 _ready 与列表构建)。可点的 hit 区仍是 STOP, 不动。
func _process(_dt: float) -> void:
	if detail == null:
		return
	var bottom := 0.0
	for c in detail.get_children():
		if not (c is Control):
			continue
		var ctl := c as Control
		if c is RichTextLabel and ctl.mouse_filter == Control.MOUSE_FILTER_STOP:
			ctl.mouse_filter = Control.MOUSE_FILTER_PASS
		bottom = maxf(bottom, ctl.position.y + ctl.size.y)
	var want := bottom + DETAIL_SCROLL_PAD
	if absf(detail.custom_minimum_size.y - want) > 0.5:
		detail.custom_minimum_size.y = want


func _clear_detail() -> void:
	for c in detail.get_children():
		c.queue_free()


## PoC Phaser 文本以 origin (ox,oy) 锚 (x,y). Godot Label 左上锚 → 换算位置.
func _add_text(x: float, y: float, text: String, size: int, color: String,
		ox: float = 0.0, oy: float = 0.5, bold: bool = false, w: float = 0.0) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", Color(color))
	if bold:
		lbl.add_theme_constant_override("outline_size", 0)
	var est_w := w if w > 0.0 else float(text.length()) * size * 0.62
	var est_h := float(size) * 1.3
	lbl.position = Vector2(x - ox * est_w, y - oy * est_h)
	if w > 0.0:
		lbl.custom_minimum_size = Vector2(w, 0)
	detail.add_child(lbl)
	return lbl


## 居中锚的图片 (PoC addDomImage 默认中心锚) → Godot 左上 = 中心 - size/2
## 尺寸死锁: EXPAND_IGNORE_SIZE + size + custom_minimum_size + clip_contents,
## 防原图大尺寸撑爆 (TextureRect 默认随纹理原生像素膨胀).
func _add_image(cx: float, cy: float, path: String, w: float, h: float,
		keep_aspect: bool = false) -> TextureRect:
	if not ResourceLoader.exists(path):
		return null
	var tr := TextureRect.new()
	tr.texture = load(path)
	tr.clip_contents = true
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# keep_aspect → 等比内缩居中 (KEEP_ASPECT, 不是 native-centered); 否则铺满
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT if keep_aspect else TextureRect.STRETCH_SCALE
	detail.add_child(tr)
	# 添加后再死锁尺寸/位置 (plain Control 父级不布局, 但 add_child 会按纹理重置 size → 必须后置)
	tr.position = Vector2(cx - w / 2.0, cy - h / 2.0)
	tr.custom_minimum_size = Vector2(w, h)
	tr.size = Vector2(w, h)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tr.position = Vector2(cx - w / 2.0, cy - h / 2.0)
	tr.size = Vector2(w, h)
	return tr


## 龟详情全身立绘 (1:1 PoC CodexScene.ts:285-296: 全身 spritesheet idle 动画, contain-fit 进 box, 非头像)。
##   有 sprite{frameW/H/frames/duration} → Sprite2D 多帧 + idle tween; 无 → 静态全身 img; 都缺 → 头像兜底。
##   帧/fps/缩放与 battle makeView 同算法 (BattleScene.gd:528-549), contain-fit = min(box/fw, box/fh)。
func _add_pet_portrait(cx: float, cy: float, pet: Dictionary, box: float) -> void:
	var fid: String = str(pet.get("id", ""))
	var img: String = str(pet.get("img", ""))
	var img_full := "res://assets/sprites/%s" % img
	if img == "" or not ResourceLoader.exists(img_full):
		_add_image(cx, cy, "res://assets/sprites/avatars/%s.png" % fid, box, box, true)
		return
	var tex: Texture2D = load(img_full)
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(cx, cy)
	var sprite_meta = pet.get("sprite", null)
	if sprite_meta is Dictionary and (sprite_meta as Dictionary).has("frameW"):
		var meta: Dictionary = sprite_meta
		var fw: int = maxi(1, int(meta.get("frameW", tex.get_width())))
		var fh: int = maxi(1, int(meta.get("frameH", tex.get_height())))
		var hf: int = maxi(1, int(floor(float(tex.get_width()) / float(fw))))
		var vf: int = maxi(1, int(floor(float(tex.get_height()) / float(fh))))
		# ★换表前先把 frame 归零 —— setter 会立即用新乘积校验当前 frame。
		#   图鉴切龟时**复用同一个精灵**: 从 4 行网格(可达 27)切到 7 帧单行时,
		#   设 vframes 那一瞬乘积掉到 7 而 frame 还是旧值 ⇒ 越界。
		#   与 RealtimeBattle3DScene._set_anim_sheet 是同一个坑(那里有长注释)。
		spr.frame = 0
		spr.hframes = hf; spr.vframes = vf; spr.frame = 0
		var frame_total: int = hf * vf
		var idle_n: int = maxi(1, mini(int(meta.get("frames", frame_total)), frame_total - 1))
		var sf: float = minf(box / float(fw), box / float(fh))   # contain-fit (PoC 详情用 contain 非锁高)
		spr.scale = Vector2(sf, sf)
		if idle_n > 1:
			var dur_ms: float = float(meta.get("duration", 800))
			var fps: float = maxf(4.0, roundf(float(idle_n) * 1000.0 / maxf(200.0, dur_ms)))
			var loop_dur: float = float(idle_n) / fps
			var tw := spr.create_tween().set_loops()   # 绑 spr, 切龟清 detail 时自动停
			# ★同族钳制: idle_n 来自元数据, 贴图未必真有那么多帧
			tw.tween_method(func(fr: float) -> void:
				spr.frame = int(fr) % maxi(1, mini(idle_n, int(spr.hframes) * int(spr.vframes)))
			, 0.0, float(idle_n), loop_dur)
	else:
		var sf2: float = minf(box / float(maxi(1, tex.get_width())), box / float(maxi(1, tex.get_height())))
		spr.scale = Vector2(sf2, sf2)
	detail.add_child(spr)


func _add_rect(cx: float, cy: float, w: float, h: float, color: String, a: float,
		stroke: String = "", stroke_w: float = 0.0, stroke_a: float = 1.0) -> Panel:
	var p := Panel.new()
	p.position = Vector2(cx - w / 2.0, cy - h / 2.0)
	p.custom_minimum_size = Vector2(w, h); p.size = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color); sb.bg_color.a = a
	if stroke != "":
		sb.border_color = Color(stroke); sb.border_color.a = stroke_a
		sb.set_border_width_all(int(stroke_w))
	p.add_theme_stylebox_override("panel", sb)
	detail.add_child(p)
	return p


func _ctx_for(pet: Dictionary) -> Dictionary:
	# 1:1 PoC petToCtx(CodexScene.ts:167): m = rarity_mult × getLevelBonus(1+(lv-1)×0.05); lv=实际等级 (技能{N:ATK}/{LV}随等级变)
	var lv: int = GameState.get_pet_level(str(pet.get("id", "")))
	var m: float = float(DataRegistry.rarity_mult.get(pet.get("rarity", "C"), 1.0)) * (1.0 + (lv - 1) * 0.05)
	return {
		"atk": roundi(pet.get("atk", 0) * m), "def": roundi(pet.get("def", 0) * m),
		"mr": roundi(pet.get("mr", pet.get("def", 0)) * m), "maxHp": roundi(pet.get("hp", 0) * m),
		"crit": pet.get("crit", 0.0), "lv": lv,
	}


# ─── 龟详情 (1:1 PoC showPetDetail 顶部固定区) ───
# ══════════════════════════════════════════════════════════
# 深海小将 (虚拟图鉴条目 — 非龟, pets.json 里没有)
#
# 【事实源】RealtimeBattle3DScene.gd `_make_unit` 的 is_minion 分支 + `_sk_minion_*` / `_elite_*`.
# 这里的每个数字都是从那段代码抄的, 改小将数值时【必须同步这张表】, 否则图鉴就开始骗人。
# 注意 scripts/gamedata/phase2_minion.gd 是回合制遗留壳(名字叫"深海小将精英", 数值也不同), 不是事实源。
# ══════════════════════════════════════════════════════════
const MINION_KINDS := [
	{"kind": "front", "name": "近战小将", "img": "minion.png"},
	{"kind": "back",  "name": "远程小将", "img": "minion-back.png"},
	{"kind": "elite", "name": "精英小将", "img": "minion-elite.png"},
]

## Lv1 数值 + 说明. hp/atk 随等级 ×1.05^(lv-1) 复利, 双抗定值(与 _make_unit 一致).
const MINION_INFO := {
	"front": {
		"name": "近战小将", "img": "minion.png", "role": "前排 · 近战",
		"hp": 750, "atk": 42, "def": 13, "mr": 13, "interval": 0.85, "range": 70, "spd": 105,
		"skill_name": "人体浪板", "skill_cost": 120,
		"skill_desc": "射程 2000。高高跃起并回复 2×攻击力 生命(离目标太近则先后跳拉开)，射出铁链将目标眩晕并把自己拉过去；接触瞬间造成 [color=#ff9f43]目标 10% 最大生命[/color] 物理伤害，随后踩着目标滑行——对被踩者持续造成 2×攻击力 物理伤害，沿途敌人受到 1.5×攻击力 物理伤害并被击退，最后跳下。",
	},
	"back": {
		"name": "远程小将", "img": "minion-back.png", "role": "后排 · 远程",
		"hp": 750, "atk": 45, "def": 7, "mr": 7, "interval": 0.85, "range": 400, "spd": 105,
		"skill_name": "追踪火箭筒", "skill_cost": 120,
		"skill_desc": "射程 2000。蓄力 1.5 秒后发射一枚慢速追踪导弹，命中处核爆：400 码范围内造成 [color=#ff9f43]4×攻击力[/color] 物理伤害，并使命中的敌人受到的治疗降低 50%，持续 4 秒。",
	},
	"elite": {
		"name": "精英小将", "img": "minion-elite.png", "role": "统领位补位 · 近战",
		"hp": 1000, "atk": 50, "def": 16, "mr": 20, "interval": 1.54, "range": 90, "spd": 105,
		"skill_name": "铁锤", "skill_cost": 100,
		"skill_desc": "射程 500。举拳蓄力 0.35 秒后砸地，对身前 60° 锥形 500 码内造成 [color=#ff9f43]4×攻击力[/color] 魔法伤害；每第 3 次改为高高跃起、空中蓄力 1 秒后下锤，覆盖 700 码全域并造成 [color=#ff9f43]6×攻击力[/color] 魔法伤害。",
		"passives": [
			{"name": "长手刃 (普攻)", "desc": "普攻造成 1×攻击力 物理伤害，每第 5 击附带旋刃。"},
			{"name": "吞噬", "desc": "目标生命低于 15% 时发动，1.5 秒演出期间自身获得 [color=#ff9f43]95% 伤害减免[/color]，完成后回复 [color=#ff9f43]目标剩余生命的 2 倍[/color]，并获得持续 5 秒的 50% 攻速提升，同时窃取目标的主动技能。普攻、铁锁、铁拳与强化普攻都能触发。"},
			{"name": "铁锁", "desc": "冷却 5 秒。锁定 150~350 码之间的敌人，链射命中后使其眩晕 0.4 秒、拉到自己身后，并造成 1×攻击力 魔法伤害。"},
		],
	},
}

## 小将详情页 — 布局对齐 _codex_detail._show_pet(立绘左上 / 名字与属性右上 / 分隔线下技能被动).
var _codex_form_view: bool = false   # 图鉴双形态: false=普通skillPool, true=形态(近战/火山)技能
var _codex_skill_detail: Dictionary = {}   # 内联技能详情视图 (非空=显示该技能完整detail+返回钮, 1:1 PoC view={skillIdx}; 空=技能卡列表)
var _codex_passive_view: bool = false   # 内联被动展开 (true=下方区显示完整被动desc, 1:1 PoC view='passive'; false=技能卡列表)
