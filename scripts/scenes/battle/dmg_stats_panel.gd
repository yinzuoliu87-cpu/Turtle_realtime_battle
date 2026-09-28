## 战中【战报】浮层 (右上角统计键开关) — 从 RealtimeBattle3DScene.gd 抽出·2026-07-19
##
## ★★2026-09-28 整块换皮换词(用户:「一点也看不出来游戏的味道, 全是 ai 味和网页味,
##   文字语言也是」)。改前这块浮层是**全战斗 UI 里网页味最集中的一处**, 逐项:
##     圆角 8 的半透明底板 + 2px 描边 ＝ CSS 卡片 → 九宫格金属框(panel-frame)
##     `⚔🛡💚🔵` 四个 emoji 页签              → stats/ 那四张真图标(项目 2026-08-16 就定了全去 emoji)
##     Godot 默认皮的 4 个页签键 + 裸字 ✕      → UISkin 金属签牌三态
##     圆角 4 / `rgba(1,1,1,.05)` 空轨 / 纯色段 → 凹槽(bar-frame) + 液面(_bar_fill_skin)
##     两行裸标签「我方/敌方」压着一列数字      → 队伍签牌 + 名次牌 + 定宽右对齐数值
##   共用件一律从 `InfoPanel` 借(为此把它的 `_bar_frame`/`_bar_fill_skin` 改成 static),
##   不在这里照抄 —— 血条的光和战报的光必须是同一种光。
##
## 样式源流(历史): 1:1 回合制 DmgStatsPanel 的 4 Tab / 双列 rows / 0.4s 自刷。
## 与战斗场的耦合全部走【依赖注入】: 构造时传入 ui_layer 和「取某方单位列表」的回调,
## 本类不认识 _units / _world / 战斗状态。
##
## 注意: 结算统计表【不在此文件】—— 它在 battle_hud.gd 里
## (_build_stats_panel 建面板 / _stats_column 建一队一列), 是另一套 5 列样式
## (龟/造成伤害/承受伤害/治疗量/击杀)。★2026-08-02 更正: 原注释写"仍留在战斗场里"
## 且写"7列表格" —— 两处都过期了(表已搬进 HUD 层, 列也在 2026-08-02 从 7 列减到 5 列)。
class_name DmgStatsPanel
extends RefCounted

const UIPalette = preload("res://scripts/util/ui_palette.gd")
## 语义色引用 UIPalette 单一色表(2026-07-22)。
## ★★alpha 从 0.6/0.65 提到 0.92(2026-09-28)。原来的半透明是配合"色块压在半透明底板上"
##   那一版的; 现在分段条画在**真凹槽**里(见 `make_bar`), 底本来就是暗的 ——
##   再半透明就成了蒙一层灰纱, 三种伤害类型的色相全被拉到一起、分不出段。
const COL_PHY := Color(UIPalette.PHYS, 0.92)
const COL_MAG := Color(UIPalette.MAGIC, 0.92)
const COL_TRU := Color(UIPalette.TRUE_DMG, 0.92)
const COL_HEAL := Color(UIPalette.HEAL, 0.92)
const COL_SHIELD := Color(UIPalette.SHIELD_VALUE, 0.92)
## 页签图标目录。
## ★★用真图标不用 emoji(2026-09-28)。项目 2026-08-16 就定了「全去 emoji」
##   (根治绿块 + 跨平台一致), 状态签那一轮换完了, **这四个页签是漏网的最后一处** ——
##   `⚔ 造成 / 🛡 承受 / 💚 治疗 / 🔵 护盾` 这四个 emoji 是整块浮层里最刺眼的"ai 味"。
## ★这四张不是新做的, 也不算"借别件的素材": `assets/sprites/stats/` 这套核心属性图标
##   本来就是"攻击/防御/生命/护盾"的通用基元(资产借用审计的 GENERIC 白名单里正含 `-icon`),
##   战斗信息面板的属性行用的就是同一批 —— 一屏之内同一件事同一张图才叫一致。
const TAB_ICON := "res://assets/sprites/stats/"
## [key, 页签名, 图标]。
## ★★页签名与结算战报表的列名【逐字一致】—— 同一件事两处两种叫法是最省事也最没必要的
##   不一致(2026-08-17「HP vs 生命」那次的教训)。两处同日一起改:
##     造成伤害 → **打出** / 承受伤害 → **扛住** / 治疗量 → **治疗**
##   (理由见 `battle_hud._stats_column` 的表头注释: 主动语态的短动词, 不是规格书的
##    被动名词短语; 也**不是**被否过的"出伤/承伤"那种行话缩写。)
##   护盾这一页结算表里没有, 所以它没有对面。
const TABS := [
	["dealt", "打出", "atk-icon.png"],
	["taken", "扛住", "def-icon.png"],
	["heal", "治疗", "hp-icon.png"],
	["shield", "护盾", "shield-icon.png"],
]
## 页签图标在按钮里的显示宽度。★原图 32×32, 缩到 16 是【整数 1/2 倍】——
##   非整数倍缩像素图会把像素网格打烂(`tools/vfx_discipline_audit.py` A 条那条教训)。
const TAB_ICON_PX := 16
## 名次牌配色: 冠亚季各一色, 第四名之后一律暗铜。
## ★"名次形态差异"是这块浮层从 Excel 变回战报的关键 —— 一列等宽等色的数字谁排第一都一样,
##   而战报要让人**一眼看出这场谁扛的**(结算表那边靠 MVP 角标做的是同一件事)。
const RANK_COL := [Color("#ffd93d"), Color("#dbe7f2"), Color("#d08a4a")]
const RANK_DIM := Color("#5d6d7e")
## 名次牌占的宽度。★三档金属牌与第四名之后的裸数字【必须一样宽】, 否则名字的起笔位置
##   会随名次跳(第 3 行有牌、第 4 行没牌 ⇒ 两行的名字对不齐, 比没有名次牌更乱)。
const RANK_W := 28.0
## 分段条的高度。★16 不是 12: 条框九宫格(`bar-frame.png` 96×24 · 上下边距各 6)要求
##   目标高度**大于 12** 才有中段, 12 时中段一行不剩、框被压没 —— 这个坑
##   `info_panel._info_resource_row` 的头注里已经栽过两次(头像框 32→56 / 资源条 24→14),
##   直接照它最后落到的 16 走, 不再自己试。
const BAR_H := 16.0
## 数值列的固定宽度。★Godot 没有 CSS 的 `font-variant-numeric: tabular-nums`,
##   等价手段是【定宽列 + 右对齐】: 个位永远落在同一条竖线上, 三位数和五位数也不会错位。
##   (只右对齐不定宽不行 —— 名字那一列是弹簧, 名字长短会把数字推得左右乱跳。)
const VAL_W := 62.0

var panel: Control = null                 # 浮层本体(默认隐)
var _cols: Array = []                     # [左队 rows VBox, 右队 rows VBox]
var _tab: String = "dealt"                # 当前 Tab: dealt/taken/heal/shield
var _tab_btns: Array = []
var _ui_layer: CanvasLayer = null
var _units_of: Callable                   # func(side: String) -> Array

func setup(ui_layer: CanvasLayer, units_of: Callable) -> void:
	_ui_layer = ui_layer
	_units_of = units_of

## 📊 开关 (1:1 回合制 _on_dmg_stats_toggle)
func toggle() -> void:
	if panel == null:
		build()
	panel.visible = not panel.visible
	if panel.visible:
		_to_front()
		render()


## ★每次显示都把面板提到 _ui_layer 最前。
##
## 为什么必须这么做(探针实测, 不是防御性写法):
##   同一 CanvasLayer 内【树序 = 绘制层级】, 后 add_child 的画在上面。
##   而 _spawn_dual_lane 【每一路】都会重建左右队头像栏(battle_spawn.gd:180)、
##   摇杆、法术盘, 它们 add_child 后落到子节点列表末尾 →
##   本面板(首次点开时才建, 更早)就被压到下面去了。
##   探针数字: 开局 面板 index=21 / 左队栏 15(面板在上);
##             换一次路后 面板 19 / 左队栏 20(面板被盖住), 且两者几何真重叠。
##   用户 2026-07-30 报的正是「在下半战场统计面板还会被遮住」。
##   ★同一个根因也解释了"面板半透"的错觉 —— 底板其实 alpha 0.97 几乎不透明,
##     是【三路对阵总览幕布】后 add_child 画在了它上面。
func _to_front() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var par := panel.get_parent()
	if par != null:
		par.move_child(panel, par.get_child_count() - 1)

## 当前 Tab 的标量值 (排序/显示)
static func val(u: Dictionary, tab: String) -> int:
	match tab:
		"dealt": return int(u.get("_st_dealt", 0))
		"taken": return int(u.get("_st_taken", 0))
		"heal": return int(u.get("_st_heal", 0))
		"shield": return int(u.get("_st_shield", 0))
	return 0

## 当前 Tab 的分段条 [[值,色],...]: 造成/承受按类型三段, 治疗/护盾单段.
static func parts(u: Dictionary, tab: String) -> Array:
	if tab == "dealt" or tab == "taken":
		var bt: Dictionary = u.get("_st_dealt_by_type" if tab == "dealt" else "_st_taken_by_type", {})
		return [
			[int(bt.get("phy", 0)), COL_PHY],
			[int(bt.get("mag", 0)), COL_MAG],
			[int(bt.get("tru", 0)) + int(bt.get("dot", 0)), COL_TRU],
		]
	elif tab == "heal":
		return [[int(u.get("_st_heal", 0)), COL_HEAL]]
	return [[int(u.get("_st_shield", 0)), COL_SHIELD]]

## 分段条: 金属凹槽(九宫格条框) + 分段液面; 段按值 stretch_ratio, 余量露出槽底。
##
## ★★2026-09-28 从"CSS 进度条"改成"槽里的液面"。原来这三行逐项都是网页的长相:
##     `set_corner_radius_all(4)` = border-radius / 空轨 `rgba(1,1,1,.05)` = 半透明白纱 /
##     `ColorRect` 纯色分段 = `<div style="background:#f44">`。
##   用户 2026-08-16 原话「**血条, 龟能条都跟网页一样**」说的就是这种形状; 信息面板
##   2026-08-17 那一轮已经把血条/龟能条/资源条全换成"凹槽 + 液面"了,
##   **这块浮层是漏掉的那一处**(它不在 `verify_info_panel_fits` 的扫描范围里, 判据看不见)。
## ★两个共用件都从 `InfoPanel` 借: 槽框 `_bar_frame` / 液面 `_bar_fill_skin`
##   (为此把那两个函数改成了 `static`, 行为一字未动)。**不在这里照抄** ——
##   抄一次永远落后一次(memory `fb-hand-rolled-copies-drift`), 而且抄了之后
##   "血条的光"和"战报的光"就会各自漂。
## ★槽框先入树 ⇒ 画在下层; 液面【内缩 6/4】画在框里面, 不压框沿(与 `_info_bar` 同一套)。
##   贴图缺失时 `_bar_frame` 返回 null, 这时不内缩 —— 否则条会凭空瘦一圈。
static func make_bar(bar_parts: Array, col_max: int) -> Control:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(0, BAR_H)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.clip_contents = true
	var wsb := StyleBoxFlat.new()
	## 槽底: 深色实底 + 直角。凹槽的底本来就该是暗的(光进不去), 不是蒙一层白纱。
	wsb.bg_color = Color(0.03, 0.055, 0.09, 0.90)
	wsb.set_corner_radius_all(0)
	wrap.add_theme_stylebox_override("panel", wsb)
	var frame := InfoPanel._bar_frame(wrap)
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	if frame != null:
		hb.offset_left = 6.0; hb.offset_right = -6.0
		hb.offset_top = 4.0; hb.offset_bottom = -4.0
	hb.add_theme_constant_override("separation", 0)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var used := 0
	for part in bar_parts:
		var v: int = int(part[0])
		if v <= 0:
			continue
		var seg := Panel.new()
		var ssb := StyleBoxFlat.new()
		ssb.set_corner_radius_all(0)
		## 液面分层(主体压暗一档 + 顶部 3px 亮带) —— 与血条/龟能条走同一个函数,
		## 所以三处的"光打在液面上"是同一种光, 不会各调一份。
		InfoPanel._bar_fill_skin(ssb, part[1])
		seg.add_theme_stylebox_override("panel", ssb)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = float(v)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(seg)
		used += v
	var rem: int = maxi(0, col_max - used)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.size_flags_stretch_ratio = maxf(0.0001, float(rem))
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(spacer)
	wrap.add_child(hb)
	return wrap

## 一行: [名次牌] 名(左绿/右红, 召唤体缩进) + 右对齐数值 / 下方分段条; 阵亡整行半透.
##
## ★`rank` = 本列内按当前页签值排出的名次(从 1 起, 0 = 不显示名次)。
##   有了它这一行才有"形态": 冠亚季三档金属名次牌 + 头名的名字与数字各大一档,
##   第四名之后是暗铜数字。原来每一行长得一模一样, 扫一眼只是一摞数字 = Excel。
func make_row(u: Dictionary, side: String, col_max: int, rank: int = 0) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	if not bool(u.get("alive", true)):
		row.modulate.a = 0.4
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	if rank > 0:
		top.add_child(_rank_badge(rank))
	var nm := Label.new()
	nm.text = ("↳ " if u.get("is_summon", false) else "") + str(u.get("name", u.get("id", "")))
	## 头名字号大一档 —— 名次差异不能只挂在一个小角标上(玩家扫的是名字, 不是角标)。
	nm.add_theme_font_size_override("font_size", 16 if rank == 1 else 15)
	nm.add_theme_color_override("font_color", Color(UIPalette.SIDE_LEFT) if side == "left" else Color(UIPalette.SIDE_RIGHT))
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	## ★不许 clip_text: 它会把最小宽度压成 1px, 而同一行里有弹簧 ⇒ 名字被挤成一个像素
	##   (字还在、一个像素都看不见)。同一个坑 `info_panel._info_resource_row` 栽过。
	nm.clip_text = false
	top.add_child(nm)
	var v := Label.new()
	v.text = str(val(u, _tab))
	v.add_theme_font_size_override("font_size", 16 if rank == 1 else 14)
	v.add_theme_color_override("font_color", RANK_COL[0] if rank == 1 else Color("#e6edf3"))
	## 定宽 + 右对齐 = 这里的 tabular-nums(见 VAL_W 头注): 个位永远在同一条竖线上。
	v.custom_minimum_size = Vector2(VAL_W, 0.0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(v)
	row.add_child(top)
	row.add_child(make_bar(parts(u, _tab), col_max))
	return row


## 名次牌: 冠亚季是【金属签牌 + 深色数字】, 第四名之后只留一个暗铜数字。
## ★两者**占同样宽**(RANK_W) —— 否则第 3 行有牌、第 4 行没牌, 名字的起笔位置就会跳,
##   比不做名次牌更乱(这条是先量了再定的, 不是拍的: 牌自带左右内边距 3+3, 所以牌里的
##   数字只给 RANK_W-6, 加回内边距刚好还是 RANK_W)。
func _rank_badge(rank: int) -> Control:
	var lb := Label.new()
	lb.text = str(rank)
	lb.add_theme_font_size_override("font_size", UIPalette.F_SUB)
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rank > 3:
		lb.custom_minimum_size = Vector2(RANK_W, 0.0)
		lb.add_theme_color_override("font_color", RANK_DIM)
		return lb
	lb.custom_minimum_size = Vector2(RANK_W - 6.0, 0.0)
	lb.add_theme_color_override("font_color", Color("#20160a"))   # 牌面是亮金属 ⇒ 数字要深
	var holder := PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = RANK_COL[rank - 1]
	fb.set_corner_radius_all(0)                 # 直角: 圆角矩形是 CSS 的长相
	fb.content_margin_left = 3; fb.content_margin_right = 3
	fb.content_margin_top = 1; fb.content_margin_bottom = 1
	## 有签牌贴图就用它(金属倒角 + 四角铆钉), 没有才退回上面那块纯色 —— 与面板别处同一条退路。
	## ★`chip-frame` 源图 48×24 · 边距 7 ⇒ 最小可用 14×14, 而这块牌约 28×20, 装得下。
	var sb := UISkin.nine("chip-frame.png", 7, fb)
	if sb is StyleBoxTexture:
		var st := sb as StyleBoxTexture
		st.modulate_color = RANK_COL[rank - 1]
		st.content_margin_left = 3; st.content_margin_right = 3
		st.content_margin_top = 1; st.content_margin_bottom = 1
	holder.add_theme_stylebox_override("panel", sb)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lb)
	return holder

## 一块【金属名牌】: 签牌九宫格 + 一行字。浮层标题「战报」与两列的队伍名牌都走它。
##
## ★单一出处: 这两处要的是同一个东西, 抄第二遍就是"手抄的副本必然落后"
##   (memory `fb-hand-rolled-copies-drift` —— 今天已经因为它把 `_bar_frame` 改成了 static)。
## ★状态色走 `modulate_color` 而不是各做一张图 —— 与 `UISkin` 铁律②同一条。
##   牌面提亮之后字要看得清, 所以 `tint_of` 只给牌, 字用原色。
func _plate(txt: String, tint: Color, fsize: int) -> Control:
	var box := PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(tint.r, tint.g, tint.b, 0.16)
	fb.set_border_width_all(0)                   # ★不画描边: 1px 描边矩形就是 CSS `border:1px solid`
	fb.set_corner_radius_all(0)
	fb.content_margin_left = 10; fb.content_margin_right = 10
	fb.content_margin_top = 2; fb.content_margin_bottom = 2
	var sb := UISkin.nine("chip-frame.png", 7, fb)
	if sb is StyleBoxTexture:
		var st := sb as StyleBoxTexture
		st.modulate_color = UISkin.tint_of(tint)
		st.content_margin_left = 10; st.content_margin_right = 10
		st.content_margin_top = 2; st.content_margin_bottom = 2
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lb := Label.new()
	lb.text = txt
	lb.add_theme_font_size_override("font_size", fsize)
	lb.add_theme_color_override("font_color", tint)
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lb)
	return box


## 浮层骨架: 金属框 + 名牌「战报」 + 4 个图标页签 / 双列 rows / 0.4s 自刷.
func build() -> void:
	panel = Panel.new()
	# ★y 56→100: 顶部 PK 条 2026-07-30 加宽加厚后占到 y≈67, 双路文字行到 94 ——
	#   原来的 56 会让面板标题栏钻到血条下面。100 是"贴着 HUD 下沿"。
	panel.position = Vector2(12, 100)
	# ★高度按内容自适应(见 render 末尾): 固定 430 时只有 5 行数据, 下半截一片空白(实拍看出来的)。
	#   这里给个初值, render 每次按真实行数收紧。
	panel.size = Vector2(540, 430)
	panel.visible = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	## ★★2026-09-28 换九宫格金属框。原来是 `圆角 8 + 2px 金棕描边 + 半透明底` ——
	##   也就是 CSS `border-radius:8px; border:2px solid; background:rgba()`,
	##   用户点名的"网页味"三件套齐了。战斗信息面板 2026-08-16/17 两轮已经换成
	##   `battlehud/panel-frame.png`(深蓝金属 + 青内沿 + 四角铜铆钉),
	##   **这块浮层是全战斗 UI 里最后一个圆角 CSS 方块**。
	## ★退回分支不是摆设: PNG 没 `.import` 时 `ResourceLoader.exists()` 返回 false
	##   且一句报错都没有(UISkin 头注那个静默坑) ⇒ 兜底的 `psb` 也要是能看的,
	##   所以它一起改成了直角。
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.055, 0.075, 0.11, 0.97)
	psb.border_color = Color("#6b5430")
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", UISkin.nine("panel-frame.png", 20, psb))
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	## ★内边距从 14/12 放到 22/20 —— 框艺术本身约 14px 厚, 14 会让内容压在框和铆钉上
	##   (信息面板量出来的那组数就是 22/22/20/18, 这里照抄, 不自己再试一遍)。
	vb.offset_left = 22; vb.offset_top = 20; vb.offset_right = -22; vb.offset_bottom = -18
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	vb.add_child(tabs)
	## ★★浮层自己的名牌。原来这块浮层【一个标题都没有】, 只有四个 emoji 页签 ——
	##   玩家不知道自己点开的是什么, 而唯一说明它是什么的 tooltip 在屏幕另一头那个键上。
	##   叫「战报」不叫「伤害统计」: 后者是后台报表的说法(结算屏那张表同日一起改了名)。
	tabs.add_child(_plate("战报", Color("#ffd93d"), 17))
	_tab_btns = []
	for pair in TABS:
		var b := Button.new()
		b.text = str(pair[1])
		b.add_theme_font_size_override("font_size", 15)
		## 图标走按钮自己的 icon 槽, 不另建 TextureRect —— 少一层节点, 且对齐由按钮负责。
		var ip: String = TAB_ICON + str(pair[2])
		if ResourceLoader.exists(ip):
			b.icon = load(ip)
			b.add_theme_constant_override("icon_max_width", TAB_ICON_PX)
			b.add_theme_constant_override("h_separation", 5)
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		## ★★金属签牌皮。原来这四个键是【Godot 默认主题】—— 圆角纯色, 是"没游戏味"
		##   最直接的来源。`verify_click_targets_alive` 有一条判据专门守这个
		##   (「不许有还用 Godot 默认皮的按钮」), 但它只扫主菜单那几屏 + 战斗信息面板,
		##   **这块浮层在它的视野外** —— 判据看不见的地方就是它的盲区。
		UISkin.button(b, Color("#b9c8d8"))
		var key: String = pair[0]
		b.pressed.connect(func() -> void: _tab = key; render())
		tabs.add_child(b)
		_tab_btns.append({"btn": b, "key": key})
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# ★关闭按钮(用户 2026-07-30 报"交互很奇怪"): 原来只能【再点右上角那个统计按钮】关,
	#   而面板在左上角、按钮在右上角 —— 鼠标要横跨整屏才关得掉。这里就近放一个 ✕。
	# ★必须放在 TABS 循环【之后】—— 我第一版插在循环前, ✕ 跑到了 Tab 行最左边(实拍才看出来)。
	var close := Button.new()
	close.text = "✕"
	close.add_theme_font_size_override("font_size", 16)
	close.add_theme_color_override("font_color", Color("#d7e3ef"))
	## ★★同样换金属签牌皮。原来两个 `StyleBoxEmpty` = **一个完全没有皮的裸字**:
	##   既看不出它是按钮, 也看不出点击范围有多大(用户 2026-07-30 报过"交互很奇怪")。
	UISkin.button(close, Color("#8fa4bb"))
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close.process_mode = Node.PROCESS_MODE_ALWAYS
	close.custom_minimum_size = Vector2(34, 26)
	close.pressed.connect(func() -> void: panel.visible = false)
	var sp := Control.new()                      # 弹性占位: 把 ✕ 顶到最右
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(sp)
	tabs.add_child(close)

	vb.add_child(cols)
	_cols = []
	for side_label in [["我方", "left"], ["敌方", "right"]]:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 4)
		## ★队伍名牌, 不是一行裸标签 —— 裸标签压着一列数字就是表格的 `<th>` + 数据行,
		##   也就是"Excel 感"的来源。签牌把它变成"这一队的牌子"。
		colv.add_child(_plate(str(side_label[0]),
			Color(UIPalette.SIDE_LEFT) if side_label[1] == "left" else Color(UIPalette.SIDE_RIGHT), 15))
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		colv.add_child(rows)
		cols.add_child(colv)
		_cols.append(rows)
	_ui_layer.add_child(panel)
	var t := Timer.new()
	t.wait_time = 0.4
	t.autostart = true
	## ★★2026-08-21 修一条冒烟间歇红(实测 6 次红 3 次):
	##   `ERROR: Lambda capture at index 0 was freed. Passed "null" instead.`
	##   原来这个闭包**捕获了局部变量 `panel`(一个 Node)**。冒烟用的是 `inst.free()`
	##   ——立即释放、最恶劣时序; Timer 与 panel 同一帧没掉时, 引擎去绑那个已释放的捕获就报错。
	##
	## ★规律: **闭包捕获 Node 不安全, 捕获 RefCounted 安全** ——
	##   Node 被 free 就没了(捕获变野); 而 RefCounted 被 Callable 引用着, 引用不掉到 0 就不会没。
	##   `self` 是 RefCounted(本类) ⇒ 改成只捕获 self、用成员 `panel`, 并在里面 is_instance_valid。
	t.timeout.connect(func() -> void:
		if panel != null and is_instance_valid(panel) and panel.visible:
			render())
	panel.add_child(t)

## 重建两列 rows: 各列按当前 Tab 值降序; Tab active 高亮.
func render() -> void:
	if _cols.size() < 2:
		return
	# ★每次自刷(0.4s)都重新提到最前 —— 只在"点开时"提是不够的:
	#   【面板开着的时候换路】, 新建的头像栏/摇杆/法术盘会盖上来, 而那时不会再调 toggle()。
	#   放在 render 里让它自愈, 最多 0.4 秒就回到最前。
	_to_front()
	for tb in _tab_btns:
		var active: bool = tb["key"] == _tab
		var b := tb["btn"] as Button
		b.add_theme_color_override("font_color", Color("#ffffff") if active else Color("#8b949e"))
		## ★★选中态靠【整块牌的明暗】, 不只靠字色(2026-09-28)。
		##   原来四块牌长得一模一样, 唯一差别是字色 #ffffff vs #8b949e —— 得盯着字
		##   才知道自己在看哪一页。现在没选的那三块整体压暗一档, 图标跟着暗,
		##   选中的那块是正常亮度 = "按下去的那块签牌"。
		##   (不重新调 `UISkin.button` —— 那会每 0.4 秒重建 5 个 StyleBox 当垃圾。)
		b.modulate = Color(1.0, 1.0, 1.0, 1.0) if active else Color(0.60, 0.65, 0.72, 1.0)
	var sides := ["left", "right"]
	for ci in range(2):
		var side: String = sides[ci]
		var rows_vb: VBoxContainer = _cols[ci]
		for c in rows_vb.get_children():
			rows_vb.remove_child(c)
			c.queue_free()
		var list: Array = _units_of.call(side)
		var tab := _tab
		list.sort_custom(func(a, b): return val(a, tab) > val(b, tab))
		var col_max := 1
		for u in list:
			col_max = maxi(col_max, val(u, tab))
		## ★名次 = 排完序之后的下标 + 1(上面刚按当前页签值降序排过)。
		##   ⚠ 名次是**每列各自算**的: 两队各有自己的第一名, 这块浮层是两份战报并排,
		##   不是一张总榜(把两队混在一起排会让"我方第一"变成"全场第三", 读不出本队的主力)。
		for i in range(list.size()):
			rows_vb.add_child(make_row(list[i], side, col_max, i + 1))

	# ★按内容收紧高度: 固定 430 时只有 5 行数据、下半截一片空白。
	#   Control 不会自己撑高/收缩, 得手算: 取两列里较高的一列 + 上下留白。
	var need := 0.0
	for c in _cols:
		var col := c as VBoxContainer
		if col == null:
			continue
		var hh := 0.0
		for ch in col.get_children():
			if ch is Control and (ch as Control).visible:
				hh += (ch as Control).get_combined_minimum_size().y + 4.0
		need = maxf(need, hh)
	if need > 0.0:
		## ★★2026-09-28 上下都调了, 两处都是**算出来的**不是拍的:
		##   · 固定开销 96 → 112: 内边距从 14/12 放到 22/20(金属框艺术约 14px 厚) = +16,
		##     页签行换成签牌后也高了一点。96 会让最后一行被框的下沿压住。
		##   · 上限 430 → 480: 每行的分段条从 12 长到 16(条框九宫格要求 >12, 见 BAR_H),
		##     8 行就多吃 32px; 430 会把最后一行切掉。
		##     480 仍然放得下: 浮层顶在 y=100, 100+480=580 < 720(也 < iPad 的 960)。
		panel.size.y = clampf(need + 112.0, 170.0, 480.0)
