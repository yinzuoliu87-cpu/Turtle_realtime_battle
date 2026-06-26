extends Node2D

## CodexScene — 图鉴 (5 Tab: 龟/装备/羁绊/状态/规则). 1:1 PoC CodexScene.ts 像素布局移植.
## 详情容器 (UI/Detail) 左上 = PoC detailX,detailY = (340,150) → PoC 详情局部坐标直接对应.

@onready var title_lbl: Label = $UI/Title
@onready var tab_bar: Control = $UI/TabBar
@onready var list_bg: ColorRect = $UI/ListBg
@onready var list_scroll: ScrollContainer = $UI/ListScroll
@onready var list_vbox: VBoxContainer = $UI/ListScroll/ListVBox
@onready var detail_bg: ColorRect = $UI/DetailBg
@onready var detail: Control = $UI/Detail
@onready var status_bar: Label = $UI/StatusBar

const RARITY_COLOR := {
	"C": "#06d6a0", "B": "#4cc9f0", "A": "#3a9abf",
	"S": "#c77dff", "SS": "#ffd93d", "SSS": "#ff6b6b",
}
# ── 二阶段双路装备 (p2eq) 费用/稀有度配色 (装备 Tab 用) ──
# 装备 Tab 不再展示旧 e_ 装备(DataRegistry.all_equipment), 改展示上线野生=duallane 实际用的 59 件 p2eq
#   (DataRegistry.phase2_equipment, data/phase2-equipment.json) 按费用 1→5 分组, 末尾追加 8 件消耗品。
# 费用分组标题色 (费用越高越亮/暖); 稀有度色用于行描边 + 详情副标 (p2eq rarity = 中文档位)。
const COST_COLOR := {
	1: "#94a3b8", 2: "#4cc9f0", 3: "#06d6a0", 4: "#c77dff", 5: "#ffd93d",
}
const P2EQ_RARITY_COLOR := {
	"普通": "#94a3b8", "精良": "#4cc9f0", "稀有": "#06d6a0", "史诗": "#c77dff", "传说": "#ffd93d",
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

# ── 二阶段双路「装备学派」羁绊 (替代旧的 10 龟羁绊; 上线版野生=duallane 用此 11 学派) ──
# 学派定义(名/tag/tiers)取自 Phase2Schools.SCHOOLS; 成员装备由 p2eq-schools.json 反查; 效果文案=学派效果-实装规格.md 逐字转录。
const Phase2Schools := preload("res://scripts/engine/phase2_schools.gd")
# 各学派强调色 + emoji 图标 (无 tag PNG → 用 emoji 占位; 颜色用于列表描边/标题). 11 学派.
const SCHOOL_STYLE := {
	"血牙帮":     {"color": "#ff6b6b", "emoji": "🩸"},
	"深渊议会":   {"color": "#9d4edd", "emoji": "🦠"},
	"玄甲卫队":   {"color": "#94a3b8", "emoji": "🛡"},
	"珊瑚学院":   {"color": "#ff7ab8", "emoji": "🪸"},
	"深海军械库": {"color": "#fb923c", "emoji": "💣"},
	"黑礁猎团":   {"color": "#22d3ee", "emoji": "🎯"},
	"极地小队":   {"color": "#60a5fa", "emoji": "❄"},
	"潮汐议会":   {"color": "#34d399", "emoji": "🌊"},
	"圣甲议会":   {"color": "#ffd93d", "emoji": "✨"},
	"唤灵学会":   {"color": "#c084fc", "emoji": "💀"},
	"远古遗迹":   {"color": "#a3e635", "emoji": "🗿"},
}
# 各档效果文案 (1:1 学派效果-实装规格.md). 每学派 = {common: 通用/全档文案, tiers: [按档增量文案...]}。
#   common 先渲染; tiers[i] 非空则标"N档"(N=SCHOOLS.tiers[i])增量行。阈值数值真值仍以 Phase2Schools.SCHOOLS 为准。
const SCHOOL_EFFECTS := {
	"血牙帮": {
		"common": "全体友方根据已损失生命获得攻击力:每损失 1% 最大生命 → +0.6 / 1 / 1.5 攻击力。\n每个友方单位生命首次跌至 30% 以下时,获得相当于其 100% 攻击力的护盾(每单位每场一次)。",
		"tiers": [],
	},
	"深渊议会": {
		"common": "全队攻击无视目标 12% / 22% / 40% 护甲和魔抗(腐蚀穿透)。\n每回合末,所有敌方单位 +1 层腐蚀(每层使目标受到的伤害 +3% / 4% / 6%,最多叠 5 层)。\n腐蚀满 5 层的敌人,其受到的伤害中 30% 转化为真实伤害(无视护甲、护盾)。",
		"tiers": [],
	},
	"玄甲卫队": {
		"common": "每回合开始,随机将 1/1/2 件「费用 ≤2/3/4 且非3星」的装备临时玄甲化:本回合按高一星级结算其效果(若场上无符合条件装备则不触发)。\n每回合开始,玄甲卫队为全队提供 10/15/20 护盾值。",
		"tiers": [],
	},
	"珊瑚学院": {
		"common": "队伍获得 90/100/110 最大生命值。\n激活时获得 1/2/4 枚珊瑚碎片(潜能)。每件珊瑚学院装备的效果中都含有「×碎片数」的强化项——碎片越多,该装备的效果越强(多一段攻击、多叠几层、多覆盖一个目标等)。碎片为全体珊瑚装备共享的潜能值。",
		"tiers": [],
	},
	"深海军械库": {
		"common": "",
		"tiers": [
			"我方阵营最前方生成第一座炮台:我方回合末选一名敌人轰击,对炮台↔该敌直线上所有命中单位造成 80 物理伤害,并为最低血友军回复(30%×造成伤害)的生命。",
			"+ 中心生成第二座炮台:每回合固定产 100 能量(每持一件军械库装备额外 +20)。第1回合能量→转护盾均摊全队;第2回合能量→化弹幕向敌全体(敌均摊该能量值魔法);此后两回合循环(护盾↔弹幕)。",
			"+ 后方生成第三座炮台:为军械库携带者接通火控,使携带者额外造成 (10 + 每件军械库装备×5)% 真实伤害。",
		],
	},
	"黑礁猎团": {
		"common": "战斗开始获得一张猎杀卡片,玩家拖拽到一个敌方单位指定为猎物(卡片附着于该敌)。\n全队对猎物造成的伤害 +15%/25%/40%。\n猎物被击杀后,卡片自动脱落回收,可再次指定新猎物;每击杀一个猎物 → 全队攻击力永久 +14/26/38(本场累积)。",
		"tiers": [
			"",
			"",
			"【质变·处决】攻击猎物时,若其生命低于 20% → 直接处决(斩首)。",
		],
	},
	"极地小队": {
		"common": "",
		"tiers": [
			"【冻结】全队攻击 15%/25%/40% 概率冻结目标 1 回合(无法行动)。同一目标每回合最多被冻结 1 次,且解冻后 1 回合内免疫冻结(防永冻)。",
			"【僵硬】全队每段攻击额外为目标叠 1 层僵硬(持续4回合,叠加刷新时长),每层攻击力 -2%,最多 20 层(满层 -40% 攻)。",
			"【易碎】被冻结/眩晕的敌人,受到的伤害 +25%。",
		],
	},
	"潮汐议会": {
		"common": "【潮涌·每回合回血】每回合开始,全队回复已损失生命的 4%/7%/10%/12%。\n【退潮·治疗留盾】友军受到治疗时,额外获得等于治疗量 15%/25%/35%/50% 的护盾。\n【大潮·质变·净化】每 3 回合掀起一次大潮:全队每个友军回复 15% 最大生命,并净化 1/1/2/3 个减益(冰冻/灼烧/腐蚀/僵硬等)。",
		"tiers": [],
	},
	"圣甲议会": {
		"common": "",
		"tiers": [
			"获得一个圣盾装备(+150最大生命)。圣盾:每2回合为携带者生成 45 点圣光护盾。圣光护盾存在时,反击敌人的每段伤害造成 2 点真实伤害。该反击伤害与护盾值,团队每有一件圣甲议会装备 +50%。",
			"再获得一个圣盾装备。此外,敌方单位阵亡时,圣盾立即为携带者提供相当于该阵亡单位 30% 最大生命的圣光护盾。",
			"此外,圣甲装备为携带者提供治疗/护盾时,额外提供 20% 治疗量/护盾量 的圣光护盾。圣盾提供的所有圣盾值 +20%。",
		],
	},
	"唤灵学会": {
		"common": "友方单位阵亡时,在原地召唤一只亡魂,继承该单位 20%/30%/45%/65%/100% 攻击力和生命,自动攻击最近的敌人。\n亡魂阵亡时,再召唤一只更弱的亡魂(每次属性 ×0.9 递减),每个单位最多循环复活 0/1/2/3/4 次,之后彻底死亡。",
		"tiers": [],
	},
	"远古遗迹": {
		"common": "龟蛋获得 500/750/1500 最大生命值。\n【远古之力】激活后战斗每过 1 回合,全队永久 +3/+6/+10 攻击力(本场累积,软上限 +300)。\n【觉醒】激活满 8 回合后(固定第8回合)全队进入「觉醒」:已累积远古之力 +50%,之后每回合获得的远古之力翻倍。",
		"tiers": [
			"",
			"",
			"【质变·远古降临】觉醒后每回合开始触发一道远古能量爆发,对全体敌人造成已累积远古之力 150% 的真实伤害。",
		],
	},
}

var current_tab: String = "pets"
var _items: Array = []
var _sel_idx: int = -1   # 当前选中条目 idx (调试面板改等级后刷新用)


## ← 返回主菜单 (1:1 PoC CodexScene.ts:68 makeIconButton 40,40 → MainMenuScene). 原 Godot 无 → 图鉴死胡同。
func _add_back_button() -> void:
	var back := Button.new()
	back.text = "←"
	back.add_theme_font_size_override("font_size", 26)
	back.position = Vector2(20.0, 18.0)
	back.custom_minimum_size = Vector2(44.0, 44.0)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	$UI.add_child(back)
	# 🛠 调试面板 (右上角, 仅 debug 构建显示 — 1:1 PoC DEV_VISIBLE; 设等级/加币/重置/快速对战)
	if OS.is_debug_build():
		var dbg := Button.new()
		dbg.text = "🛠"
		dbg.add_theme_font_size_override("font_size", 22)
		dbg.position = Vector2(1280.0 - 64.0, 18.0)
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
		info.text = "龟币: %d   龟种: %d\n等级分布: %s" % [GameState.coins, DataRegistry.all_pets.size(), summ]
	refresh_info.call()
	vb.add_child(_dbg_label("全体等级"))
	var lv_row := HBoxContainer.new(); lv_row.add_theme_constant_override("separation", 8)
	for lvv in [1, 5, 10]:
		var b := _dbg_btn("全员 Lv.%d" % lvv)
		b.pressed.connect(func() -> void:
			for p in DataRegistry.all_pets:
				GameState.set_pet_level(str(p.get("id", "")), lvv)
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
		GameState.pet_levels = {}; GameState.coins = 0; GameState.save()
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
	# 成就: 首次打开图鉴 (1:1 PoC CodexScene.ts:58 tracker.onCodexOpen()).
	AchievementTracker.on_codex_open()
	if DataRegistry.all_pets.is_empty():
		status_bar.text = "❌ DataRegistry 未加载"
		return
	status_bar.text = "✓ %d 龟 / %d 装备 / %d 羁绊 / %d 状态 / %d 规则" % [
		DataRegistry.all_pets.size(), _equip_tab_count(),
		Phase2Schools.SCHOOLS.size(), DataRegistry.status_defs.size(), DataRegistry.battle_rules.size()]
	# 视口比例由项目级 EXPAND(window/stretch/aspect)保证, 场景切换不翻转 aspect → 入场丝滑(同 TeamSelect)。
	#   同步建完(无 await), 首帧即完整布局, 无半成品/撕裂帧。背景铺满+居中见 _fill_bg_and_center。
	_fill_bg_and_center()
	_build_tab_bar()
	_add_back_button()   # ← 返回主菜单 (1:1 PoC CodexScene.ts:68) — 原漏了→图鉴出不去
	# 标题掉落入场 (PoC CodexScene.ts:65: y -30→50, 400ms back.out) — 仅开场一次
	title_lbl.position.y -= 80.0
	var tt := create_tween()
	tt.tween_property(title_lbl, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var start_tab := "pets"
	if OS.has_environment("SHOT_TAB"):   # dev: 截图指定 tab (供 diff)
		start_tab = OS.get_environment("SHOT_TAB")
	_switch_tab(start_tab)


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
		for n in [list_bg, list_scroll, detail_bg, detail]:
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
		[detail_bg, 360.0, 0.25], [detail, 360.0, 0.25],
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
	var total_w := TABS.size() * tab_w + (TABS.size() - 1) * tab_gap
	var start_x := (1280.0 - total_w) / 2.0
	# PoC makeTab label 带数量计数: 🐢 龟 (N) / ⚔ 装备 (N) / 🔗 羁绊 (N) / 💫 状态 (N) / 📜 规则 (N)
	# 装备 Tab 计数 = 59 件 p2eq + 消耗品件数 (上线野生=duallane 实际装备池, 非旧 e_ 装备)
	var tab_counts := {
		"pets": DataRegistry.launch_pets.size(), "equips": _equip_tab_count(),
		"synergies": Phase2Schools.SCHOOLS.size(), "status": DataRegistry.status_defs.size(),
		"rules": DataRegistry.battle_rules.size(),
	}
	for i in TABS.size():
		var t: Array = TABS[i]
		var active: bool = t[0] == current_tab
		var b := Button.new()
		b.text = "%s (%d)" % [t[1], int(tab_counts.get(t[0], 0))]
		b.position = Vector2(start_x + i * (tab_w + tab_gap), 0)
		b.custom_minimum_size = Vector2(tab_w, 36)
		b.size = Vector2(tab_w, 36)
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
				_add_pet_row(pet)
		"equips":
			_add_equip_rows()
		"synergies":
			# 11 装备学派 (替代旧 10 龟羁绊; 上线野生=duallane 用此). 名序按 Phase2Schools.SCHOOLS 声明序.
			for sname in Phase2Schools.SCHOOLS.keys():
				_items.append({"_school": sname})
				var style: Dictionary = SCHOOL_STYLE.get(sname, {})
				var emoji: String = str(style.get("emoji", "🔗"))
				var col: String = str(style.get("color", "#4cc9f0"))
				# 无 tag PNG → emoji 前缀进名字; 描边用学派色 (列表行 _add_simple_row 复用)
				_add_simple_row("%s %s" % [emoji, sname], col, Color(col), "", _items.size() - 1)
		"status":
			_add_status_rows()
		"rules":
			for r in DataRegistry.battle_rules:
				_items.append(r)
				_add_simple_row(r.get("name", "?"), "#ffd93d", Color("#06d6a0"),
					"res://assets/sprites/rules/%s.png" % r.get("id", ""), _items.size() - 1)
			# 小商店物品池虚拟入口 (1:1 PoC CodexScene.ts:850-862; 绿 #06d6a0 描边, 点开 showShopPoolDetail)
			_items.append({"_shopPool": true})
			_add_simple_row("🛒 小商店物品池", "#06d6a0", Color("#06d6a0"), "", _items.size() - 1)
	if _items.size() > 0:
		_select(0)
	# 列表/详情滑入 (PoC scene.restart 每次切 tab 重播)
	_play_list_detail_intro()


# ─── 列表行 (PoC: 行高52 gap4, bg 0x1a2740@0.85, 描边稀有度色@0.7) ───
func _mono_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "Consolas", "Courier New"])
	f.fallbacks = [load("res://assets/fonts/NotoSansSC-Regular.otf")]   # CJK 网页/iOS 兜底 (SystemFont 在 web 取不到系统字体→中文乱码)
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


func _add_pet_row(pet: Dictionary) -> void:
	var idx := _items.size() - 1
	var rarity: String = pet.get("rarity", "C")
	var col := Color(RARITY_COLOR.get(rarity, "#ffffff")); col.a = 0.7
	var p := _make_row(52, 0.85, col)
	var idx_path := "res://assets/sprites/avatars/%s.png" % pet.get("id", "")
	# 圆头像 (40 直径), PoC addCircularAvatar — 这里用 TextureRect 方框近似 (Godot 无内置圆裁, 1:1 数据正确)
	var av := TextureRect.new()
	av.position = Vector2(6, 6)
	av.custom_minimum_size = Vector2(40, 40); av.size = Vector2(40, 40)
	av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(idx_path):
		av.texture = load(idx_path)
	p.add_child(av)
	# 名字 15px (PoC #fff bold)
	var name_lbl := Label.new()
	name_lbl.text = pet.get("name", "?")
	name_lbl.position = Vector2(56, 0)
	name_lbl.size = Vector2(LIST_W - 16 - 56 - 26, 52)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 15)
	p.add_child(name_lbl)
	# 稀有度文字右对齐 14px 彩
	var rar := Label.new()
	rar.text = rarity
	rar.position = Vector2(LIST_W - 16 - 38, 0)
	rar.size = Vector2(24, 52)
	rar.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rar.add_theme_font_size_override("font_size", 14)
	rar.add_theme_font_override("font", _mono_font())   # PoC CodexScene.ts:199 fontFamily:'monospace'
	rar.add_theme_color_override("font_color", Color(RARITY_COLOR.get(rarity, "#ffffff")))
	p.add_child(rar)
	_connect_row(p, idx, col)


func _add_simple_row(label: String, label_color: String, stroke: Color, icon_path: String, idx: int) -> void:
	var col := stroke; col.a = 0.7
	var p := _make_row(52, 0.85, col)
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var ic := TextureRect.new()
		ic.position = Vector2(6, 8)
		ic.custom_minimum_size = Vector2(36, 36); ic.size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture = load(icon_path)
		p.add_child(ic)
	var lbl := Label.new()
	lbl.text = label
	lbl.position = Vector2(48, 0)
	lbl.size = Vector2(LIST_W - 16 - 56, 52)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(label_color))
	p.add_child(lbl)
	_connect_row(p, idx, col)


# 装备 Tab 总件数 = p2eq(59) + 消耗品件数 (Tab 计数 / 状态栏共用)
func _equip_tab_count() -> int:
	var n: int = DataRegistry.phase2_equipment.size()
	for eq in DataRegistry.all_equipment:
		if eq is Dictionary and eq.get("category", "") == "consumable":
			n += 1
	return n


# ── 装备 Tab 列表: 59 件 p2eq 按费用 1→5 分组 + 末尾 8 件消耗品 (1:1 上线野生=duallane 实际装备池) ──
#   数据源: DataRegistry.phase2_equipment (data/phase2-equipment.json); 消耗品 = all_equipment 中 category=consumable。
#   行描边用稀有度色(P2EQ_RARITY_COLOR), 标题用费用色(COST_COLOR); emoji 前缀进名字(p2eq 无 PNG icon, 只有 emoji)。
func _add_equip_rows() -> void:
	# 费用分组 (1→5)
	for cost in [1, 2, 3, 4, 5]:
		var items := []
		for eq in DataRegistry.phase2_equipment:
			if not (eq is Dictionary):
				continue
			if int(eq.get("cost", 0)) == cost:
				items.append(eq)
		if items.is_empty():
			continue
		var ccol: String = COST_COLOR.get(cost, "#4cc9f0")
		_add_header("▸ 费用 %d (%d)" % [cost, items.size()], ccol)
		for eq in items:
			_items.append(eq)
			var rarity: String = str(eq.get("rarity", ""))
			var stroke: String = P2EQ_RARITY_COLOR.get(rarity, ccol)
			var emoji: String = str(eq.get("emoji", "📦"))
			# emoji 前缀进名字 (p2eq 无 PNG icon → 走 _add_simple_row 空 icon_path 分支)
			_add_simple_row("%s %s" % [emoji, eq.get("name", "?")], "#ffffff", Color(stroke), "", _items.size() - 1)
	# 消耗品分组 (取自 all_equipment category=consumable, 8 件; 有 PNG icon)
	var consumables := []
	for eq in DataRegistry.all_equipment:
		if eq is Dictionary and eq.get("category", "") == "consumable":
			consumables.append(eq)
	if not consumables.is_empty():
		_add_header("▸ 消耗品 (%d)" % consumables.size(), "#06d6a0")
		for eq in consumables:
			_items.append(eq)
			var icon: String = str(eq.get("icon", ""))
			var ipath := "res://assets/sprites/%s" % icon if icon.ends_with(".png") else ""
			_add_simple_row(eq.get("name", "?"), "#ffffff", Color("#06d6a0"), ipath, _items.size() - 1)


func _add_status_rows() -> void:
	var cat_label := {
		"dot": ["DoT (持续伤害)", "#ef4444"], "cc": ["CC (控制)", "#c77dff"],
		"buff": ["Buff (增益)", "#06d6a0"], "debuff": ["Debuff (减益)", "#fbbf24"],
	}
	for cat in ["dot", "cc", "buff", "debuff"]:
		var items := []
		for st in DataRegistry.status_defs:
			if st.get("category", "") == cat:
				items.append(st)
		if items.is_empty():
			continue
		_add_header(cat_label[cat][0], cat_label[cat][1])
		for st in items:
			_items.append(st)
			var icon_key: String = st.get("iconKey", "")
			var ipath := "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", "")
			_add_simple_row(st.get("name", "?"), "#ffd93d", Color(cat_label[cat][1]), ipath, _items.size() - 1)


func _add_header(text: String, color: String) -> void:
	var h := Label.new()
	h.text = text
	h.add_theme_font_size_override("font_size", 14)
	h.add_theme_color_override("font_color", Color(color))
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_left", 14)
	wrap.add_theme_constant_override("margin_top", 4)
	wrap.add_child(h)
	list_vbox.add_child(wrap)


func _connect_row(p: Panel, idx: int, stroke: Color) -> void:
	p.gui_input.connect(func(ev: InputEvent):
		# 鼠标左键 或 触摸 都接 (防 emulate_touch_from_mouse 把点击变 touch 时收不到)
		var clicked: bool = (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and ev.pressed)
		if clicked:
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
		"pets": _show_pet(item)
		"equips": _show_equip(item)
		"synergies": _show_school(item)
		"status": _show_status(item)
		"rules":
			if item.get("_shopPool", false):
				_show_shop_pool()
			else:
				_show_rule(item)


# ══════════════════════════════════════════════════════════
# 详情面板 helper (在 detail 容器内绝对定位; PoC Phaser 坐标=Godot 同坐标)
# ══════════════════════════════════════════════════════════
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
			tw.tween_method(func(fr: float) -> void: spr.frame = int(fr) % idle_n, 0.0, float(idle_n), loop_dur)
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
func _show_pet(pet: Dictionary) -> void:
	_clear_detail()
	var rarity: String = pet.get("rarity", "C")
	var rarity_color: String = RARITY_COLOR.get(rarity, "#ffffff")
	var ctx := _ctx_for(pet)
	var divider_y := 195.0

	# 1) 立绘 170×170 @(100,110) — 全身 idle 动画 sprite (1:1 PoC showPetDetail:285-296), 非头像
	_add_pet_portrait(100, 110, pet, 170.0)

	# 2) 名字 (详情) y30 32px #ffd93d bold; 稀有度标签 14px灰 + 值28px彩
	# PoC L301: `Lv ${lv}.  ${pet.name}` (两空格). 图鉴默认等级 1 (getPetLevel 兜底).
	var mid_x := 220.0
	var lv: int = GameState.get_pet_level(str(pet.get("id", "")))
	_add_text(mid_x, 30, "Lv %d.  %s" % [lv, pet.get("name", "?")], 32, "#ffd93d", 0.0, 0.5, true)
	_add_text(mid_x, 75, "稀有度", 14, "#888888", 0.0, 0.5)
	_add_text(mid_x + 60, 75, rarity, 28, rarity_color, 0.0, 0.5, true)

	# Tag 图标区: 4 tag, x=midX+25+i×70, 图 y130 50×60, 文字 y180 14px
	var tags = pet.get("tags", [])
	if tags is Array:
		var nt: int = mini(tags.size(), 4)
		for i in nt:
			var tag: String = tags[i]
			var cx: float = mid_x + 25 + i * 70.0
			_add_image(cx, 130, "res://assets/sprites/tags/%s标签.png" % tag, 50, 60)
			_add_text(cx, 180, tag, 14, "#58d3ff", 0.5, 0.5, true)

	# 3) 4 属性条 — statColX500 statRowH42; 方块 sqW5 sqH14 gap2 pitch7
	# m = 稀有度倍率 × 等级加成 (1:1 PoC CodexScene:168 RARITY_MULT×getLevelBonus); rarity_mult 取真值表(原硬编1.5/2.0=bug)
	var m: float = float(DataRegistry.rarity_mult.get(rarity, 1.0)) * (1.0 + (lv - 1) * 0.05)
	var stats := [
		{"key": "hp", "label": "最大生命值", "val": roundi(pet.get("hp", 0) * m), "color": "#06d6a0", "div": 40.0},
		{"key": "atk", "label": "攻击力", "val": roundi(pet.get("atk", 0) * m), "color": "#ff9f43", "div": 5.0},
		{"key": "def", "label": "护甲", "val": roundi(pet.get("def", 0) * m), "color": "#ffd93d", "div": 2.5},
		{"key": "mr", "label": "魔抗", "val": roundi(pet.get("mr", pet.get("def", 0)) * m), "color": "#4dabf7", "div": 2.5},
	]
	var stat_col_x := 500.0
	var stat_row_h := 42.0
	var value_x := 700.0
	var bars_start_x := 716.0
	var sq_w := 5.0; var sq_h := 14.0; var sq_pitch := 7.0
	for i in stats.size():
		var st: Dictionary = stats[i]
		var sy := 30.0 + i * stat_row_h
		_add_image(stat_col_x, sy, "res://assets/sprites/stats/%s-icon.png" % st["key"], 26, 26)
		_add_text(stat_col_x + 28, sy, st["label"], 16, "#bbbbbb", 0.0, 0.5)
		_add_text(value_x, sy, str(st["val"]), 24, st["color"], 1.0, 0.5, true)
		var count := int(floor(float(st["val"]) / float(st["div"])))
		for k in count:
			var sq_cx := bars_start_x + k * sq_pitch + sq_w / 2.0
			_add_rect(sq_cx, sy, sq_w, sq_h, st["color"], 1.0)

	# 8) 横分隔线 y195 宽 detailW-40 #ffd93d@0.4 1px
	_add_rect(DETAIL_W / 2.0, divider_y, DETAIL_W - 40, 1, "#ffd93d", 0.4)

	# 9) 被动条框 y213 高50 0x12202a@0.55 + 被动icon 40×40@x50
	var passive: Dictionary = pet.get("passive", {})
	if not passive.is_empty():
		var passive_y := divider_y + 18.0
		# 选中态(被动展开): 边框亮黄 2px@1; 否则蓝 1px@0.5 (1:1 PoC CodexScene.ts:366-393)
		var pbar_stroke: String = "#ffd93d" if _codex_passive_view else "#58d3ff"
		var pbar_sw: float = 2.0 if _codex_passive_view else 1.0
		var pbar_sa: float = 1.0 if _codex_passive_view else 0.5
		_add_rect(DETAIL_W / 2.0, passive_y + 25, DETAIL_W - 40, 50, "#12202a", 0.55, pbar_stroke, pbar_sw, pbar_sa)
		var text_x := 30.0
		var pi_path: String = DataRegistry.passive_icons.get(passive.get("type", ""), "")
		if pi_path != "":
			if pi_path.ends_with(".png"):
				_add_image(50, passive_y + 25, "res://assets/sprites/%s" % pi_path, 40, 40)
				text_x = 80.0
			else:
				_add_text(50, passive_y + 25, pi_path, 32, "#ffffff", 0.5, 0.5)
				text_x = 80.0
		_add_text(text_x, passive_y + 25, "被动 · %s" % passive.get("name", ""), 20, "#58d3ff", 0.0, 0.5, true)
		# hint: 展开→"收起 ▾"金 / 否则"点击查看 ▸"灰 (1:1 PoC CodexScene.ts:385-388)
		var p_hint: String = "收起 ▾" if _codex_passive_view else "点击查看 ▸"
		var p_hint_col: String = "#ffd93d" if _codex_passive_view else "#888888"
		_add_text(DETAIL_W - 30, passive_y + 25, p_hint, 13, p_hint_col, 1.0, 0.5)
		# drill-down: 点被动条 → 内联展开/收起完整 passive desc (1:1 PoC showPetDetail view='passive' toggle, 非弹窗)
		var p_hit := Control.new()
		p_hit.position = Vector2(20, passive_y)
		p_hit.size = Vector2(DETAIL_W - 40, 50)
		p_hit.mouse_filter = Control.MOUSE_FILTER_STOP
		p_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pet_ref2: Dictionary = pet
		p_hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_codex_skill_detail = {}
				_codex_passive_view = not _codex_passive_view
				_show_pet(pet_ref2))
		detail.add_child(p_hit)

	# 10) 技能卡 — 5卡1行 168×260 gap8 @ skStartX20 skStartY282
	_render_skill_cards(pet, ctx)


var _codex_form_view: bool = false   # 图鉴双形态: false=普通skillPool, true=形态(近战/火山)技能
var _codex_skill_detail: Dictionary = {}   # 内联技能详情视图 (非空=显示该技能完整detail+返回钮, 1:1 PoC view={skillIdx}; 空=技能卡列表)
var _codex_passive_view: bool = false   # 内联被动展开 (true=下方区显示完整被动desc, 1:1 PoC view='passive'; false=技能卡列表)

# ─── 技能卡 (1:1 PoC renderSkillListSection) ───
func _render_skill_cards(pet: Dictionary, ctx: Dictionary) -> void:
	# 内联技能详情页 (1:1 PoC showPetDetail view={skillIdx} → renderSkillDetailSection): 顶部"← 返回列表" + 完整 detail
	if not _codex_skill_detail.is_empty():
		_render_skill_detail_inline(pet, ctx, _codex_skill_detail)
		return
	# 内联被动详情 (1:1 PoC showPetDetail view='passive' → renderPassiveDetailSection): 下方区显完整 desc
	if _codex_passive_view and not (pet.get("passive", {}) as Dictionary).is_empty():
		_render_passive_detail_inline(pet, ctx)
		return
	# E1 双形态 (PoC CodexScene.ts:401-405): 近战(meleeSkills 双头) / 火山(volcanoSkills 熔岩)
	var melee = pet.get("meleeSkills", [])
	var volcano = pet.get("volcanoSkills", [])
	var is_melee_form: bool = melee is Array and not (melee as Array).is_empty()
	var form_skills: Array = (melee if is_melee_form else (volcano if volcano is Array else [])) as Array
	var has_form: bool = not form_skills.is_empty()
	var skill_pool = form_skills if (_codex_form_view and has_form) else pet.get("skillPool", [])
	if not (skill_pool is Array):
		return
	var default_idxs = pet.get("defaultSkills", [0, 1, 2])
	var card_w := 168.0; var card_h := 260.0; var gap := 8.0
	var start_x := 20.0; var start_y := 282.0
	var n: int = mini(skill_pool.size(), 5)
	for i in n:
		var sk: Dictionary = skill_pool[i]
		if sk.is_empty():
			continue
		var cx: float = start_x + i * (card_w + gap)
		var is_default: bool = i in default_idxs
		# 技能锁 (1:1 PoC renderSkillListSection): idx3需Lv4, idx4需Lv7; 锁定仍可点开查看, 只挂🔒
		var pet_lv := GameState.get_pet_level(str(pet.get("id", "")))
		var is_locked: bool = (i == 3 and pet_lv < 4) or (i == 4 and pet_lv < 7)
		# 卡背/边框: 锁=暗灰#6b7686 / 默认技能=绿#06d6a0 / 普通=蓝#4a93d6
		var border: String = "#6b7686" if is_locked else ("#06d6a0" if is_default else "#4a93d6")
		var border_w: float = 2.5 if (is_default and not is_locked) else 2.0
		var bg_hex: String = "#141d2a" if is_locked else "#18283c"
		var bg_a: float = 0.7 if is_locked else 0.92
		_add_rect(cx + card_w / 2.0, start_y + card_h / 2.0, card_w, card_h, bg_hex, bg_a, border, border_w, 1.0)
		# 图标 38×38 (skills/<icon>.png), "+" 强化角标
		var icon: String = sk.get("icon", "")
		var enhances: bool = sk.get("enhancesPassive", false)
		var icon_src: String = ""
		if icon != "" and icon.ends_with(".png"):
			icon_src = icon
		elif enhances and not pet.get("passive", {}).is_empty():
			var pic: String = DataRegistry.passive_icons.get(pet.get("passive", {}).get("type", ""), "")
			if pic.ends_with(".png"):
				icon_src = pic
		var name_x: float = cx + 8
		if icon_src != "":
			# PoC skillIconHtml: 图标带金框 socket (深底+金边1.5px radius8); 原裸图无框 (用户报"很多地方技能都没有框")
			var sock := Panel.new()
			var sock_sb := StyleBoxFlat.new()
			sock_sb.bg_color = Color(0.04, 0.06, 0.09, 0.7)
			sock_sb.border_color = Color(1.0, 0.851, 0.4, 0.5)   # PoC border rgba(255,217,102,.5)
			sock_sb.set_border_width_all(2)
			sock_sb.set_corner_radius_all(8)
			sock.add_theme_stylebox_override("panel", sock_sb)
			sock.position = Vector2(cx + 8 + 19 - 22, start_y + 8 + 19 - 22)
			sock.custom_minimum_size = Vector2(44, 44); sock.size = Vector2(44, 44)
			detail.add_child(sock)
			_add_image(cx + 8 + 19, start_y + 8 + 19, "res://assets/sprites/%s" % icon_src, 38, 38)
			name_x = cx + 61
			if enhances or sk.get("iconPlus", false):
				_add_text(cx + 8 + 38 - 6, start_y + 8 - 2, "+", 15, "#06d6a0", 0.5, 0.5, true)
		# 名字 16px (锁=灰)
		var nlbl := _add_text(name_x, start_y + 18, sk.get("name", "?"), 16, ("#bbbbbb" if is_locked else "#ffd93d"), 0.0, 0.5, true)
		nlbl.custom_minimum_size = Vector2(card_w - (name_x - cx) - 8, 0)
		# 类型 chip 行 (锁→Lv.N解锁 / 否则 基础/主动CDn/被动)
		var chip_text := ""
		var chip_color := "#58d3ff"
		if is_locked:
			chip_text = "🔒 Lv.4 解锁" if i == 3 else "🔒 Lv.7 解锁"; chip_color = "#ff8888"
		elif sk.get("passiveSkill", false):
			chip_text = "被动"; chip_color = "#c77dff"
		elif int(sk.get("cd", 0)) == 0:
			chip_text = "基础"; chip_color = "#58d3ff"
		else:
			chip_text = "主动 CD%d" % int(sk.get("cd", 0)); chip_color = "#06d6a0"
		_add_text(cx + 8, start_y + 60, chip_text, 13, chip_color, 0.0, 0.0)
		# 简述 — 富文本 BBCode, 多行 clamp
		var brief := SkillText.render_bbcode(str(sk.get("brief", "")), ctx, sk)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.position = Vector2(cx + 8, start_y + 82)
		rt.custom_minimum_size = Vector2(card_w - 16, card_h - 82 - 8)
		rt.size = Vector2(card_w - 16, card_h - 82 - 8)
		rt.clip_contents = true
		rt.add_theme_font_size_override("normal_font_size", 13)
		rt.add_theme_color_override("default_color", Color("#aaaaaa"))
		rt.text = brief
		detail.add_child(rt)
		# drill-down: 点技能卡 → 内联换页显示完整 detail (1:1 PoC showPetDetail view={skillIdx}→renderSkillDetailSection)
		var hit := Control.new()
		hit.position = Vector2(cx, start_y)
		hit.size = Vector2(card_w, card_h)
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sk_ref: Dictionary = sk
		hit.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_codex_skill_detail = sk_ref
				_show_pet(pet))
		detail.add_child(hit)
	# E1 形态切换钮 (1:1 PoC CodexScene.ts:417-431) — 仅双形态龟显示, 切普通↔形态技能
	if has_form:
		var btn_w := 220.0
		var btn_h := 30.0
		var btn_x := DETAIL_W - 20.0 - btn_w / 2.0
		var btn_y := 262.0
		var label: String
		if is_melee_form:
			label = "🏹 查看 远程形态技能" if _codex_form_view else "⚔️ 查看 近战形态技能"
		else:
			label = "🐢 查看 普通形态技能" if _codex_form_view else "🌋 查看 火山形态技能"
		var bg_hex := "#3a1810" if _codex_form_view else "#2a1430"
		var border_hex := "#58d3ff" if _codex_form_view else "#ff7043"
		var txt_hex := "#9fd8ff" if _codex_form_view else "#ffae80"
		_add_rect(btn_x, btn_y, btn_w, btn_h, bg_hex, 0.92, border_hex, 2.0, 1.0)
		_add_text(btn_x, btn_y, label, 14, txt_hex, 0.5, 0.5, true)
		var hitb := Control.new()
		hitb.position = Vector2(btn_x - btn_w / 2.0, btn_y - btn_h / 2.0)
		hitb.size = Vector2(btn_w, btn_h)
		hitb.mouse_filter = Control.MOUSE_FILTER_STOP
		hitb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var pet_ref: Dictionary = pet
		hitb.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_codex_form_view = not _codex_form_view
				_show_pet(pet_ref))
		detail.add_child(hitb)


## 内联技能详情 (1:1 PoC renderSkillDetailSection CodexScene.ts:532-568): 顶"← 返回列表"(蓝) + 标题行(图标+★+名32px+CD) + 完整 detail #fff 13px
func _render_skill_detail_inline(pet: Dictionary, ctx: Dictionary, sk: Dictionary) -> void:
	# 返回钮 center(70,296) 100×32, fill #1a2740@0.9 边 #58d3ff 1px@0.6; 文字 14px #58d3ff (PoC L539-549)
	_add_rect(70, 296, 100, 32, "#1a2740", 0.9, "#58d3ff", 1, 0.6)
	_add_text(70, 296, "← 返回列表", 14, "#58d3ff", 0.5, 0.5)
	var bhit := Control.new()
	bhit.position = Vector2(20, 280)
	bhit.size = Vector2(100, 32)
	bhit.mouse_filter = Control.MOUSE_FILTER_STOP
	bhit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bhit.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_codex_skill_detail = {}
			_show_pet(pet))   # _codex_form_view 保留 → 返回到形态/普通列表 (PoC isForm?'form-list':'skill-list')
	detail.add_child(bhit)
	# 标题行 (PoC L552-558 addDomHTML(160,283) origin(0,0)): 图标40 inline + ★(默认绿) + 名32px#ffd93d + CD chip 20px#06d6a0
	# 默认技能判定: 形态视图不算默认 (PoC isDefault = !isForm && defaultSkills.includes(idx))
	var is_default := false
	if not _codex_form_view:
		var sp = pet.get("skillPool", [])
		if sp is Array:
			var dfs = pet.get("defaultSkills", [0, 1, 2])
			is_default = (sp as Array).find(sk) in dfs
	# 图标解析同技能卡 (1:1 PoC skillIconHtml): 有png用; 否则 enhancesPassive→取被动图标
	var icon: String = str(sk.get("icon", ""))
	var icon_src: String = ""
	if icon.ends_with(".png"):
		icon_src = icon
	elif sk.get("enhancesPassive", false) and not (pet.get("passive", {}) as Dictionary).is_empty():
		var pic: String = DataRegistry.passive_icons.get(pet.get("passive", {}).get("type", ""), "")
		if pic.ends_with(".png"):
			icon_src = pic
	var cd_i: int = int(sk.get("cd", 0))
	var bb := ""
	if icon_src != "":
		bb += "[img=40x40]res://assets/sprites/%s[/img] " % icon_src
	if is_default:
		bb += "[color=#06d6a0][font_size=28]★[/font_size][/color] "
	bb += "[color=#ffd93d][font_size=32]%s[/font_size][/color]" % str(sk.get("name", "?"))
	if cd_i > 0:
		bb += "　[color=#06d6a0][font_size=20]CD%d[/font_size][/color]" % cd_i
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 内联图标像素锐利
	title.position = Vector2(160, 283)
	title.custom_minimum_size = Vector2(DETAIL_W - 180, 48)
	title.add_theme_font_size_override("normal_font_size", 32)
	title.add_theme_color_override("default_color", Color("#ffffff"))
	title.text = bb
	detail.add_child(title)
	# 完整 detail (PoC L561-567): (20,340) width detailW-40 13px #fff lineHeight1.5, 限高352滚动
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = true
	rt.position = Vector2(20, 340)
	rt.custom_minimum_size = Vector2(DETAIL_W - 40, 352)
	rt.size = Vector2(DETAIL_W - 40, 352)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = SkillText.render_bbcode(str(sk.get("detail", sk.get("brief", ""))), ctx, sk)
	detail.add_child(rt)


## 内联被动详情 (1:1 PoC renderPassiveDetailSection CodexScene.ts:572-582): 完整 desc 占下方区 (20,290) 13px #fff 限高402滚动
func _render_passive_detail_inline(pet: Dictionary, ctx: Dictionary) -> void:
	var passive: Dictionary = pet.get("passive", {})
	if passive.is_empty():
		return
	var full_desc: String = str(passive.get("desc", passive.get("brief", "")))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = true
	rt.position = Vector2(20, 290)
	rt.custom_minimum_size = Vector2(DETAIL_W - 40, 402)
	rt.size = Vector2(DETAIL_W - 40, 402)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = SkillText.render_bbcode(full_desc, ctx, passive)
	detail.add_child(rt)


# ─── 其余 tab 详情 (沿用同详情容器, 数据 1:1) ───
# 装备详情: 消耗品(all_equipment, 有 category=consumable+desc) 与 p2eq(phase2_equipment, 有 cost) 两种数据形态。
func _show_equip(eq: Dictionary) -> void:
	if eq.get("category", "") == "consumable":
		_show_consumable(eq)
	else:
		_show_p2eq(eq)


# ── p2eq 装备详情 (data/phase2-equipment.json 字段) ──
#   头图: emoji 徽章 (无 PNG icon)。名 + 费用 + 类型(series·category) + 学派(schools_of) + 属性(baseStats1) + 效果(effectDesc1/3)。
func _show_p2eq(eq: Dictionary) -> void:
	_clear_detail()
	var cost: int = int(eq.get("cost", 0))
	var rarity: String = str(eq.get("rarity", ""))
	var ccol: String = COST_COLOR.get(cost, "#4cc9f0")
	var rcol: String = P2EQ_RARITY_COLOR.get(rarity, ccol)
	var emoji: String = str(eq.get("emoji", "📦"))
	# 头图区: emoji 徽章框 (中心锚 @(60,70), 同学派详情头图位)
	_add_rect(60, 70, 90, 90, "#12202a", 0.55, rcol, 2.0, 0.9)
	_add_text(60, 70, emoji, 44, rcol, 0.5, 0.5, true)
	# 名 30px 黄 + 费用/稀有度副标
	_add_text(130, 30, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	_add_text(130, 66, "费用 %d" % cost, 14, ccol, 0.0, 0.5, true)
	_add_text(130 + 80, 66, rarity, 14, rcol, 0.0, 0.5, true)
	# 类型行: series · category (剑系 · 轻剑 等)
	# 轻剑/重剑等子类(category)已废 → 类型只显系 (用户 2026-06-23)
	var type_str := str(eq.get("series", ""))
	_add_text(130, 92, type_str, 13, "#888888", 0.0, 0.5)
	# 学派 (可多个, p2eq-schools.json → schools_of); 无 → "—"
	var schools: Array = Phase2Schools.schools_of(str(eq.get("id", "")))
	var school_str := "  /  ".join(PackedStringArray(schools)) if not schools.is_empty() else "—"
	_add_text(130, 116, "学派: %s" % school_str, 13, "#c084fc", 0.0, 0.5, true)

	# 属性 (baseStats1)
	_add_text(20, 158, "属性", 14, "#58d3ff", 0.0, 0.0, true)
	_add_text(20, 184, str(eq.get("baseStats1", "")), 16, "#ffd93d", 0.0, 0.0, true)

	# 效果 (effectDesc1 = 1星基础 / effectDesc3 = 3星升级)
	_add_text(20, 224, "效果", 14, "#58d3ff", 0.0, 0.0, true)
	var bb := str(eq.get("effectDesc1", ""))
	var d3: String = str(eq.get("effectDesc3", ""))
	if d3.strip_edges() != "":
		bb += "\n\n[color=%s][b]%s[/b][/color]" % [rcol, d3]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 248)
	rt.custom_minimum_size = Vector2(DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.add_theme_constant_override("line_separation", 4)
	rt.text = bb
	detail.add_child(rt)


# ── 消耗品详情 (all_equipment category=consumable; 有 PNG icon + desc + target) ──
func _show_consumable(eq: Dictionary) -> void:
	_clear_detail()
	var icon: String = str(eq.get("icon", ""))
	if icon.ends_with(".png"):
		_add_image(90, 90, "res://assets/sprites/%s" % icon, 120, 120, true)
	_add_text(180, 30, eq.get("name", "?"), 30, "#ffd93d", 0.0, 0.5, true)
	_add_text(180, 68, "消耗品", 13, "#06d6a0", 0.0, 0.5, true)
	# 作用目标 (ally=友方 / enemy=敌方)
	var tgt: String = str(eq.get("target", ""))
	var tgt_label: String = str({"ally": "作用于友方", "enemy": "作用于敌方"}.get(tgt, ""))
	if tgt_label != "":
		_add_text(240, 68, tgt_label, 13, "#888888", 0.0, 0.5)
	_add_text(180, 110, "描述", 14, "#58d3ff", 0.0, 0.5, true)
	var desc := SkillText.render_bbcode(str(eq.get("desc", "")), {"atk": 0, "def": 0, "mr": 0, "maxHp": 0}, {})
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(180, 132)
	rt.custom_minimum_size = Vector2(DETAIL_W - 200, 0)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = desc
	detail.add_child(rt)


# ─── 学派(装备套装羁绊) 详情 — 替代旧龟羁绊. 名+tag+档阈值+成员装备+逐档效果文案 ───
#   数据: 学派定义 Phase2Schools.SCHOOLS / 成员装备 p2eq-schools.json(经 _school_members) / 文案 SCHOOL_EFFECTS.
#   沿用龟羁绊详情排版骨架(头图区 + 名/副标 + 下方文本区 + 底部成员清单), 仅换数据源.
func _show_school(item: Dictionary) -> void:
	_clear_detail()
	var sname: String = str(item.get("_school", ""))
	var def: Dictionary = Phase2Schools.SCHOOLS.get(sname, {})
	var style: Dictionary = SCHOOL_STYLE.get(sname, {})
	var color: String = str(style.get("color", "#4cc9f0"))
	var emoji: String = str(style.get("emoji", "🔗"))
	var tag: String = str(def.get("tag", ""))
	var tiers: Array = def.get("tiers", [])
	var members: Array = _school_members(sname)   # [{id,name,emoji}], 该学派全部装备

	# 头图区: 无 tag PNG → 学派色框 + emoji 徽章 (中心锚 @(60,70) 同旧龟羁绊头图位)
	_add_rect(60, 70, 90, 90, "#12202a", 0.55, color, 2.0, 0.9)
	_add_text(60, 70, emoji, 44, color, 0.5, 0.5, true)
	# 名 32px 学派色 + 副标 "羁绊 · [tag]" + 成员件数
	_add_text(130, 36, sname, 32, color, 0.0, 0.5, true)
	_add_text(130, 72, "羁绊 · [%s]" % tag, 14, "#888888", 0.0, 0.5)
	# 档阈值行 (e.g. "激活 3 / 6 / 9 件")
	var thresh := ""
	for i in range(tiers.size()):
		thresh += ("" if i == 0 else " / ") + str(int(tiers[i]))
	_add_text(130, 98, "激活 %s 件   ·   成员装备 %d 件" % [thresh, members.size()], 14, color, 0.0, 0.5, true)

	# 效果文案 (1:1 学派效果-实装规格.md): common 块 + 逐档(若有). RichTextLabel 自动换行(同 _show_status).
	_add_text(20, 150, "羁绊效果", 14, "#58d3ff", 0.0, 0.0, true)
	var fx: Dictionary = SCHOOL_EFFECTS.get(sname, {})
	var bb := ""
	var common: String = str(fx.get("common", ""))
	if common != "":
		bb += common + "\n"
	var fx_tiers: Array = fx.get("tiers", [])
	for i in range(fx_tiers.size()):
		var txt: String = str(fx_tiers[i])
		if txt.strip_edges() == "":
			continue
		var th: int = int(tiers[i]) if i < tiers.size() else 0
		bb += "\n[color=%s][b]%d档[/b][/color]  %s" % [color, th, txt]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = false   # 固定 260px 框 + 超长滚动, 不撑高(防压到下方成员清单 y446)
	rt.scroll_active = true
	rt.position = Vector2(20, 174)
	rt.custom_minimum_size = Vector2(DETAIL_W - 40, 260)
	rt.size = Vector2(DETAIL_W - 40, 260)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.add_theme_constant_override("line_separation", 4)
	rt.text = bb.strip_edges()
	detail.add_child(rt)

	# 成员装备清单 (从 p2eq-schools.json 反查; 名取 phase2_equipment_by_id; emoji 前缀). 多列流式网格.
	var list_y := 446.0
	_add_text(20, list_y, "学派成员装备 (%d):" % members.size(), 14, "#58d3ff", 0.0, 0.0, true)
	# 3 列, 每列宽 (DETAIL_W-40)/3; 行高 24; emoji + 名字 13px
	var cols := 3
	var col_w := (DETAIL_W - 40.0) / float(cols)
	for i in range(members.size()):
		var m: Dictionary = members[i]
		var col := i % cols
		var row := int(i / cols)
		var mx := 24.0 + col * col_w
		var my := list_y + 28.0 + row * 24.0
		_add_text(mx, my, "%s %s" % [str(m.get("emoji", "📦")), str(m.get("name", "?"))], 13, "#cdd6e0", 0.0, 0.0)


## 某学派的成员装备 [{id,name,emoji}], 反查 p2eq-schools.json(经 Phase2Schools.schools_of) + 名/emoji 取 phase2_equipment_by_id.
## 按 p2eq id 升序(= phase2_equipment 声明序), 与设计表一致。
func _school_members(sname: String) -> Array:
	var out: Array = []
	for eq in DataRegistry.phase2_equipment:
		if not (eq is Dictionary):
			continue
		var eid: String = str(eq.get("id", ""))
		if sname in Phase2Schools.schools_of(eid):
			out.append({"id": eid, "name": str(eq.get("name", eid)), "emoji": str(eq.get("emoji", "📦"))})
	return out


func _show_status(st: Dictionary) -> void:
	_clear_detail()
	var icon_key: String = st.get("iconKey", "")
	_add_image(70, 70, "res://assets/sprites/status/%s-icon.png" % icon_key.replace("status-", ""), 100, 100, true)
	var cat_label := {"dot": "DoT 持续伤害", "cc": "CC 控制", "buff": "增益", "debuff": "减益"}
	_add_text(140, 38, st.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	_add_text(140, 78, cat_label.get(st.get("category", ""), st.get("category", "")), 14, "#58d3ff", 0.0, 0.5, true)
	_add_text(20, 150, "说明", 14, "#58d3ff", 0.0, 0.0, true)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 174)
	rt.custom_minimum_size = Vector2(DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 13)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = str(st.get("desc", ""))
	detail.add_child(rt)
	var formula: String = st.get("formula", "")
	if formula != "":
		# "生效公式" header @240 (PoC CodexScene.ts:813-816: 14px#58d3ff bold)
		_add_text(20, 240, "生效公式", 14, "#58d3ff", 0.0, 0.0, true)
		_add_text(20, 264, formula, 14, "#ffd93d", 0.0, 0.0, true)


func _show_rule(r: Dictionary) -> void:
	_clear_detail()
	var icon: String = r.get("icon", "")
	if icon != "":
		_add_image(64, 78, "res://assets/sprites/%s" % icon, 92, 92, true)
	_add_text(130, 40, r.get("name", "?"), 32, "#ffd93d", 0.0, 0.5, true)
	_add_text(130, 78, "战斗规则", 14, "#888888", 0.0, 0.5)
	_add_text(20, 160, "效果", 15, "#58d3ff", 0.0, 0.0, true)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true; rt.fit_content = true; rt.scroll_active = false
	rt.position = Vector2(20, 186)
	rt.custom_minimum_size = Vector2(DETAIL_W - 40, 0)
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_color_override("default_color", Color("#ffffff"))
	rt.text = str(r.get("desc", ""))
	detail.add_child(rt)

# ─── 小商店物品池详情 (1:1 PoC CodexScene.ts:868-938 showShopPoolDetail) ───
# 数据源 = Godot ShopData (scripts/engine/shop_data.gd): BASE_PRICE(:8) / SLOT_DIST(:9-15) / BUFF_POOL(:19-32).
# Godot 无消耗品/普通/独特的具体物品分布表枚举, 只有按 category 抽自 DataRegistry — 与 PoC 一致只展示稀有度分布表, 不展示具体装备清单.
func _show_shop_pool() -> void:
	_clear_detail()
	# 标题 28px #06d6a0 bold @(20,20) origin(0,0) (PoC:872-874)
	_add_text(20, 20, "🛒 小商店", 28, "#06d6a0", 0.0, 0.0, true)
	# 副标题 12px #888 @(20,58) (PoC:875-877)
	_add_text(20, 58, "第 4/8/12 回合开张, 6 格 A~F: A~E 按各自稀有度分布抽, F 恒为重置骰子", 12, "#888888", 0.0, 0.0)

	# 稀有度标签/色 (PoC:879-881)
	var rarity_label := {"buff": "增益", "consumable": "消耗品", "normal": "普通装备", "unique": "独特装备"}
	var rarity_color := {"buff": "#6edc8c", "consumable": "#5ac8dc", "normal": "#aab0c0", "unique": "#ffc846"}
	var rarities := ["buff", "consumable", "normal", "unique"]

	var y := 92.0
	# ▸ 价格 (PoC:885-897); 基准价取自 ShopData.BASE_PRICE
	_add_text(20, y, "▸ 价格 (第一次商店基准, 动态 ±10%, 每次商店整体 +25%)", 14, "#ffd93d", 0.0, 0.0, true)
	y += 24.0
	for r in rarities:
		_add_text(32, y, "· %s" % rarity_label[r], 12, rarity_color[r], 0.0, 0.0, true)
		_add_text(200, y, "🪙 %d" % int(ShopData.BASE_PRICE[r]), 12, "#ffd93d", 0.0, 0.0)
		y += 20.0
	y += 10.0

	# ▸ 每格稀有度分布 (%) (PoC:901-919); 分布取自 ShopData.SLOT_DIST
	_add_text(20, y, "▸ 每格稀有度分布 (%)", 14, "#58d3ff", 0.0, 0.0, true)
	y += 24.0
	var header := "格   "
	for r in rarities:
		header += rarity_label[r] + "  "
	_add_text(32, y, header, 11, "#888888", 0.0, 0.0)
	y += 20.0
	for slot in ["A", "B", "C", "D", "E"]:
		var d: Dictionary = ShopData.SLOT_DIST[slot]
		_add_text(32, y, "%s    %d      %d        %d        %d" % [slot, int(d["buff"]), int(d["consumable"]), int(d["normal"]), int(d["unique"])], 11, "#cdd", 0.0, 0.0)
		y += 18.0
	_add_text(32, y, "F    重置骰子 (重投: 首次 2 币, 之后每次 +1, 进商店重置)", 11, "#bea0ff", 0.0, 0.0)
	y += 30.0

	# ▸ 增益池 (N) (PoC:923-937); 池取自 ShopData.BUFF_POOL
	_add_text(20, y, "▸ 增益池 (%d)" % ShopData.BUFF_POOL.size(), 14, "#6edc8c", 0.0, 0.0, true)
	y += 22.0
	for it in ShopData.BUFF_POOL:
		# 行底 0x12202a@0.6 描边 0x6edc8c@0.35 (PoC:928-929); _add_rect 用中心锚, 行宽 detailW-40 高28 @中心(20+(W-40)/2, y+14)
		_add_rect(20.0 + (DETAIL_W - 40.0) / 2.0, y + 14.0, DETAIL_W - 40.0, 28.0, "#12202a", 0.6, "#6edc8c", 1, 0.35)
		# name #ffd93d bold @(32, y+14) origin(0,0.5) (PoC:930-932)
		_add_text(32, y + 14.0, str(it.get("name", "?")), 12, "#ffd93d", 0.0, 0.5, true)
		# desc #bbb @(32+150, y+14) origin(0,0.5) (PoC:933-935)
		_add_text(32 + 150, y + 14.0, str(it.get("desc", "")), 11, "#bbb", 0.0, 0.5)
		y += 32.0
