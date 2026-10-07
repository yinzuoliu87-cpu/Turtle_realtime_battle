extends Node2D

const TopBar = preload("res://scripts/util/top_bar.gd")
var _top_bar = null

## CodexScene — 图鉴 (4 Tab: 龟/装备/羁绊/状态; 「规则」页签 2026-10-07 按用户「规则页直接删掉，我们没有这东西」整页删除). 1:1 PoC CodexScene.ts 像素布局移植.
## 详情容器 (UI/Detail) 左上 = (340,158) — PoC 原为 (340,150), 2026-08-19 为页签让出 8px → PoC 详情局部坐标直接对应.

@onready var title_lbl: Label = $UI/Title
@onready var tab_bar: Control = $UI/TabBar
@onready var list_bg: ColorRect = $UI/ListBg
@onready var list_scroll: ScrollContainer = $UI/ListScroll
@onready var list_vbox: VBoxContainer = $UI/ListScroll/ListVBox
var _row_press_pos := Vector2.ZERO   # 触屏点选/滑动判定: 记按下位置, 松开位移小才算点选(手机2026-07-18)
var _codex_list := CodexList.new(self)   # 图鉴·左栏列表行构建(龟/装备/状态/分组头/简单行·back_button和共享_add_text/image/portrait/rect留主场景)(2026-07-25 抽出)
var _codex_detail := CodexDetail.new(self)   # 图鉴·右栏详情视图(龟/装备/羁绊(类型)/状态/小将)(2026-07-25 抽出)
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
# ★图鉴数值【不乘稀有度倍率】(2026-10-07): 实时版战斗 `_make_unit` 不乘 rarity_mult,
#   图鉴乘了就是对玩家虚报 3~15%。数值上下文只走 `_ctx_for`(等级缩放与战斗同一个 UnitScaling)。
## 页签 = [id, 页名, 像素图标]。
## ★★2026-09-28 emoji → 像素图标。原来是「🐢 龟 / ⚔ 装备 / 🔗 羁绊 / 💫 状态 / 📜 规则」——
##   那五个字形来自 **NotoEmoji**(回退链第三级), 是**另一套画法**: 抗锯齿矢量描边,
##   而这一屏其余全部是 3~4px 笔触的像素画 ⇒ 同屏两种画法, 正是用户点名的「网页味」。
##   (量法不是我眼睛看的: `tests/verify_no_emoji_icons.gd` 直接问三张字体文件
##    谁有这个码点 —— 只有 NotoEmoji 有 = 它是 emoji 图标。★ ✓ ⚠ 在 NotoSansSC 里,
##    与正文同一套字, 不算。)
## ★图标一律 **32×32 源图按 1x 画**(`icon_max_width = ICON_PX`) —— 不缩放, 不插值。
const ICON_PX := 32
const TABS := [
	["pets", "龟", "res://assets/sprites/ui/icon-turtle.png"],
	["equips", "装备", "res://assets/sprites/ui/icon-equip.png"],
	["synergies", "羁绊", "res://assets/sprites/ui/icon-synergy.png"],
	["status", "状态", "res://assets/sprites/ui/icon-status.png"],
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
	"剑":   {"color": "#ff6b6b", "icon": "res://assets/sprites/tags/tag-sword.png"},
	"奇械": {"color": "#60a5fa", "icon": "res://assets/sprites/tags/tag-gadget.png"},
	"食物": {"color": "#ff7ab8", "icon": "res://assets/sprites/tags/tag-food.png"},
	"盾":   {"color": "#ffd93d", "icon": "res://assets/sprites/tags/tag-shield.png"},
	"药水": {"color": "#22d3ee", "icon": "res://assets/sprites/tags/tag-potion.png"},
	"枪":   {"color": "#fb923c", "icon": "res://assets/sprites/tags/tag-gun.png"},
	"弓箭": {"color": "#9d4edd", "icon": "res://assets/sprites/tags/tag-bow.png"},
	"法器": {"color": "#34d399", "icon": "res://assets/sprites/tags/tag-staff.png"},
	"灵物": {"color": "#c084fc", "icon": "res://assets/sprites/tags/tag-spirit.png"},
	## ★2026-08-15 补上「香火」—— 它 2026-08-13 进了 Phase2Types.TYPES(第 11 个类型),
	##   但这张表没跟着加, 于是羁绊页拿默认值画成 🔗 灰蓝, 而装备页走当时的 Phase2Types 取值口
	##   拿到的默认值是【🗡️ 剑】—— 一件香火装备顶着把剑的图标。两处默认值还不一样。
	"香火": {"color": "#f59e0b", "icon": "res://assets/sprites/tags/tag-incense.png"},
	"遗物": {"color": "#a3e635", "icon": "res://assets/sprites/tags/tag-relic.png"},
	## ★★2026-09-28 补上「斧头」—— **上面那条香火的教训原样重演了一遍**。
	##   斧头 2026-08-31 进了 Phase2Types(第 12 个类型), 这张表又没跟着加,
	##   于是羁绊页又拿默认值画成 🔗。上一次补完没做的那件事是: 让门禁盯住这张表。
	## ⇒ `tools/type_tables_audit.py` 的 SRC 写死 `phase2_types.gd`, 而这是**第五张**
	##   平行表、住在**另一个文件**里 —— 它根本不在审计器视野里。已一并纳入。
	"斧头": {"color": "#94a3b8", "icon": "res://assets/sprites/tags/tag-axe.png"},
}


## 类型的图标 / 强调色 —— 图鉴内【只认这一张表】。
## ★★ 2026-09-28 从 emoji 换成 `assets/sprites/tags/` 的 32×32 像素图标。
##   原来的 emoji 由 NotoEmoji 画(彩色矢量 / 单色线条两种), 而这一屏是 3~4px 的像素笔触
##   ⇒ 同一块屏上三种画法。判据与台账见 `tests/verify_no_emoji_icons.gd` 头注。
## ★★2026-09-28 那个取值口已改名 `icon_of()` 并换成像素图, **兜底值也从【剑】改成空串** ——
##   兜底成别的类型的图, 看上去像是有意设计; 缺了就该空着, 空着才看得见。
##   两张表(本表 TYPE_STYLE 与 Phase2Types.TYPE_ICON)现在由门禁盯着必须指向同一批文件。
## ★★缺的类型返回 **""**(就不画图), 而不是兜底成别的类型的图 ——
##   香火(2026-08-15) 与 斧头(2026-09-28) 两次事故都是“兜底成一把剑 / 一条链”,
##   看上去像是有意设计。空图标 = 缺谁一眼看得见
##   (而 `tools/type_tables_audit.py` 已经盯着这张表的键集)。
func _type_icon(t: String) -> String:
	return str((TYPE_STYLE.get(t, {}) as Dictionary).get("icon", ""))


func _type_color(t: String) -> String:
	return str((TYPE_STYLE.get(t, {}) as Dictionary).get("color", "#4cc9f0"))

var current_tab: String = "pets"
var _items: Array = []
var _sel_idx: int = -1   # 当前选中条目 idx


## ← 返回主菜单 (1:1 PoC CodexScene.ts:68 makeIconButton 40,40 → MainMenuScene). 原 Godot 无 → 图鉴死胡同。
func _add_back_button() -> void:
	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   146 款触屏游戏里返回一律是**扁平薄片**, 没有一款用厚装饰框。
	var _m := SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	_top_bar = TopBar.new($UI, {
		## ★★2026-09-28 去掉页名前的 📖。**不是"没图标可用所以删了"**:
		##   `top_bar.gd` 头注那 146 款触屏游戏的枢纽页里, 顶栏就是「返回箭头 + 紧跟页名」,
		##   **没有一款在页名前挂图标**(规则③ 那六款实例全是裸文字)。
		##   而 📖 来自 NotoEmoji, 与这一屏的像素笔触是两套画法。⇒ 按参考走: 只留字。
		##   四个枢纽页(图鉴/背包/设置/战绩)**一起**改, 不留"两个有图标两个没有"的半拉子。
		"title": "图鉴",
		"palette": TopBar.DEEP,
		"width": 1280.0,
		"safe_left": _m.x,
		"safe_right": _m.z,
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
	})


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):   # ESC 返回主菜单
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


func _ready() -> void:
	if DataRegistry.all_pets.is_empty():
		status_bar.text = "❌ DataRegistry 未加载"
		return
	## ★这行「✓ 28 龟 / 103 装备 / 11 羁绊 / 13 状态 / 7 规则」**和页签上的数字完全重复**
	##   (页签就写着 龟(28) / 装备(103) / 羁绊(11) / 状态(13) / 规则(7)),
	##   而且它浮在左边列表上面 —— 实拍压在最后一只龟「财神龟」那一行上(判据 12 逮到)。
	##   纯冗余 + 遮挡 ⇒ 平时收起来; 只有**数据没加载出来**时才需要它(上面那个 ❌ 分支)。
	status_bar.text = "✓ %d 龟 / %d 装备 / %d 羁绊 / %d 状态" % [
		DataRegistry.all_pets.size(), _equip_tab_count(),
		Phase2Types.TYPES.size(), DataRegistry.status_defs.size()]
	status_bar.visible = false
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
	## SHOT_SKILL=N: 再点开第 N 个技能卡的【详情】后才抓 —— 与 SHOT_SEL 同一个理由。
	##   2026-10-01 加: 专名解释行落在**技能详情**里, 而详情要点「点开看全部」才出来,
	##   没这个开关就只能抓到技能卡列表, 于是我跟用户说「我截不到」—— 那是偷懒的说法,
	##   钩子一直在, 只是少一个开关。SHOT_SKILL=p 表示【被动】。
	if OS.has_environment("SHOT_SKILL") and current_tab == "pets":
		var _kv := OS.get_environment("SHOT_SKILL")
		var _pet: Dictionary = _items[_sel_idx] if (_sel_idx >= 0 and _sel_idx < _items.size()) else {}
		if not _pet.is_empty():
			if _kv == "p":
				_codex_skill_detail = _pet.get("passive", {})
			elif _kv.is_valid_int():
				var _pool: Array = _pet.get("skillPool", [])
				var _ki := int(_kv)
				if _ki >= 0 and _ki < _pool.size():
					_codex_skill_detail = _pool[_ki]
			if not _codex_skill_detail.is_empty():
				_codex_detail._show_pet(_pet)
				await get_tree().process_frame
				await get_tree().process_frame
	## SHOT_DSCROLL=N: 把【详情框内部】滚到第 N 像素再抓。SHOT_SCROLL 滚的是左边的列表,
	##   而详情超出 DETAIL_MAX_H 的那部分在**另一个** ScrollContainer 里 —— 没这个开关,
	##   任何落在折叠线以下的东西(例: 2026-10-01 加的专名解释行)都拍不到, 只能凭空说"加好了"。
	##   SHOT_DSCROLL=-1 表示【滚到底】。
	if OS.has_environment("SHOT_DSCROLL") and is_instance_valid(_detail_scroll):
		var _dv := OS.get_environment("SHOT_DSCROLL")
		if _dv.is_valid_int():
			await get_tree().process_frame
			var _vs := _detail_scroll.get_v_scroll_bar()
			_detail_scroll.scroll_vertical = (int(_vs.max_value) if int(_dv) < 0 else int(_dv))
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
		"tabs":   # 顶部分类页签栏(龟/装备/羁绊/状态)
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
	## ★2026-08-19 加到 81(44pt) 了。之前记的"加高会压住详情面板"是真的, 但那是把页签当成
	##   **不能动的格子**在算 —— 真正的解法是给它腾垂直预算: 标题上移 6、页签上移 18、
	##   四块面板下移 8。列表只少 8px(照样滚), 页签从 30pt 变成 44pt。
	var tab_h := 81.0
	var total_w := TABS.size() * tab_w + (TABS.size() - 1) * tab_gap
	# ★2026-08-01 门禁抓到: 这里写死 1280 —— 而 TabBar 是全宽锚(跟着视口长),
	#   于是 21:9(视口 1680)上整条页签坐在中心【左边 200px】。用真实视口宽算。
	var start_x := (float(get_viewport().get_visible_rect().size.x) - total_w) / 2.0
	# PoC makeTab label 带数量计数: 🐢 龟 (N) / ⚔ 装备 (N) / 🔗 羁绊 (N) / 💫 状态 (N) / 📜 规则 (N)
	# 装备 Tab 计数 = 59 件 p2eq + 消耗品件数 (上线野生=duallane 实际装备池, 非旧 e_ 装备)
	var tab_counts := {
		"pets": DataRegistry.launch_pets.size(), "equips": _equip_tab_count(),
		"synergies": Phase2Types.TYPES.size(), "status": DataRegistry.status_defs.size(),
	}
	for i in TABS.size():
		var t: Array = TABS[i]
		var active: bool = t[0] == current_tab
		var b := Button.new()
		## ★★2026-09-27 去掉**括号计数**。「龟 (28)」「装备 (104)」是后台管理界面的写法
		##   (用户 2026-09-27:「一点也看不出来游戏的味道, 全是 ai 味和网页味」)。
		##   数量不是玩家在这一屏要的信息 —— 他要的是「有哪些龟」, 不是「一共几条记录」。
		b.text = str(t[1])
		## ★图标走 Button 自带的 icon 槽(按钮里塞不进 TextureRect)。
		##   `icon_max_width = 32` = 源图原尺寸 ⇒ **1x, 不缩放**; NEAREST 保住像素笔触。
		if t.size() > 2 and ResourceLoader.exists(str(t[2])):
			b.icon = load(str(t[2]))
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", ICON_PX)
			b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	# 页签换金属签牌: 选中态整块转金(和原来「底金字深」一个意思, 但材质不是纯色块),
	# 未选中压暗到 0.42 —— 明暗差比"底色换个颜色"更容易一眼看出当前在哪一页。
	var tab_sb := UISkin.nine_if_big(170.0, 56.0, "chip-frame.png", 7, sb)
	if tab_sb is StyleBoxTexture:
		# ★第一版把选中态做砸了: chip-frame 本身是中灰板, 乘 (1.0,0.92,0.62) 只得到
		#   暗橄榄色 —— 实拍后「龟(28)」和没选中的几乎分不出来, 而原来是【实心金底深字】,
		#   一眼可辨。**换皮不许把"当前在哪一页"这个信息换没了。**
		#   modulate 允许 >1(HDR), 所以选中态直接过曝成金, 未选中压到 0.34, 明暗差 ~5 倍。
		if active:
			(tab_sb as StyleBoxTexture).modulate_color = Color(2.35, 1.92, 0.86, 1.0)
			fg = Color("#2b2410")
		else:
			(tab_sb as StyleBoxTexture).modulate_color = Color(0.34, 0.36, 0.42, 1.0)
			fg = Color("#ffd93d")
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, tab_sb)
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
			# 11 装备类型羁绊 (2026-08-03 批1 取代 11 学派). 名序按 Phase2Types.TYPES 声明序.
			for sname in Phase2Types.TYPES.keys():
				_items.append({"_type": sname})
				var col: String = _type_color(sname)
				## ★★ 2026-09-28 图标走 `_add_simple_row` 本来就有的第 4 参 `icon_path`
				##   —— 它一直传的是空串, 所以只能把 emoji 拼进名字里。
				## ★第 6 参 `icon_native=true`: 36×36 的图标格里按 **1x = 32px 原尺寸**居中画。
				##   源图就是 32×32, 拉到 36 是 1.125 倍 ⇒ 非整数倍会把像素网格打烂。
				_codex_list._add_simple_row(sname, col, Color(col), _type_icon(sname),
					_items.size() - 1, true)
		"status":
			_codex_list._add_status_rows()
		## ★「规则」页签已删(2026-10-07 用户「规则页直接删掉，我们没有这东西」):
		##   battle-rules.json 的 5 条「XX之日」在实时版战斗里**一条都没生效**, 只有图鉴在读。
		##   (2026-07-11 那句「改制后加入, 现在待做」被这次的原话取代。)
		##   判据: tests/verify_codex_text.gd ⑥ 断言图鉴里没有规则页签、DataRegistry 不再载入规则表。
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
	# 图鉴列表这 36 行是全屏最大的一片「网页味」——半透明底 + 四边描边 = CSS border+rgba。
	# 换成和战斗面板/背包同一张金属九宫格; 选中态(stroke 金)靠 modulate 传递, 不另做图。
	## ★用 slot-frame 不用 panel-frame: 行高只有 52, 而 panel-frame 的金属边带**实测 13px 厚**,
	##   上下各 13 = 26, 只剩 26px 装内容 —— 可头像是 40px ⇒ 实拍头像把上下边框**顶破切开**。
	##   slot-frame 边带 6px, 52 − 12 = 40, 正好装得下头像。**框有它的最小适用行高。**
	var row_sb := UISkin.nine_if_big(LIST_W - 16, row_h, "slot-frame.png", 12, sb)
	if row_sb is StyleBoxTexture:
		var ts := row_sb as StyleBoxTexture
		ts.modulate_color = UISkin.tint_of(stroke)
		ts.content_margin_left = 12; ts.content_margin_right = 12
		ts.content_margin_top = 2; ts.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", row_sb)
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
	# ★hover 高亮必须跟着"这一行现在是什么样式"走。
	#   原来写死 `var sb: StyleBoxFlat = p.get_theme_stylebox("panel")` —— 行换成九宫格
	#   贴图后这个带类型的赋值直接得到 **null**, 一 hover 就 `border_color on Nil` 报错,
	#   而且**只在鼠标真的划过行时才炸**(所以我改完当场截图看不出来, 是全套门禁里
	#   verify_codex_browse 把它逮住的 —— 它会模拟划过)。
	#   同一个坑今晚在龟卡 hover 上踩过一次、当时只修了那一处; 这是第二处。
	p.mouse_entered.connect(func():
		var hb = p.get_theme_stylebox("panel")
		if hb is StyleBoxTexture:
			(hb as StyleBoxTexture).modulate_color = Color(1.45, 1.38, 1.18, 1.0)
		elif hb is StyleBoxFlat:
			(hb as StyleBoxFlat).border_color = Color("#ffd93d"))
	p.mouse_exited.connect(func():
		var hb2 = p.get_theme_stylebox("panel")
		if hb2 is StyleBoxTexture:
			(hb2 as StyleBoxTexture).modulate_color = UISkin.tint_of(stroke)
		elif hb2 is StyleBoxFlat:
			(hb2 as StyleBoxFlat).border_color = stroke)


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
	_fit_detail_frame(bottom)


## ★详情框跟着内容收高(2026-08-15, 用户「图鉴也没搞」)。
## 原来框恒定 550 高, 而多数条目根本填不满 —— 实测最差的一条:
##   规则「烈焰之日」内容底 208 / 框 550 ⇒ 底下空 342px = 【框的 62%】;
##   消耗品 378px(69%) · 状态 356px(65%) · 龟(小将)270px(49%)。
## 一屏之内一半以上是空的黑框, 这就是"版式没搞"最直观的那一眼。
## 收到贴着内容为止; 不低于 DETAIL_MIN_H(太矮的框比空框更怪), 不高于设计高 DETAIL_MAX_H
## (超出的靠 _detail_scroll 滚 —— 那条 2026-08-03 就做好了, 这里不许把它顶破屏幕)。
const DETAIL_MIN_H := 200.0
const DETAIL_MAX_H := 550.0

func _fit_detail_frame(content_bottom: float) -> void:
	var h := clampf(content_bottom + DETAIL_SCROLL_PAD, DETAIL_MIN_H, DETAIL_MAX_H)
	if absf(detail_frame.size.y - h) > 0.5:
		detail_frame.size.y = h
	# 边框是 DetailBg 的全锚子节点 ⇒ 背景一收边框跟着收。不收背景就会剩一圈空框。
	if detail_bg != null and absf(detail_bg.size.y - h) > 0.5:
		detail_bg.size.y = h


func _clear_detail() -> void:
	for c in detail.get_children():
		c.queue_free()


## PoC Phaser 文本以 origin (ox,oy) 锚 (x,y). Godot Label 左上锚 → 换算位置.
##
## ★★2026-09-27 锚点宽度从「字数 × 字号 × 0.62」改成【真量】。
##
## 由来: 图鉴新加的定位签实拍把「近战斗士」推出了金属边带(门禁 `Codex 文字压边带 +4`)。
## 顺着查下去发现**不是那一处的局部问题, 是这个共享漏斗自己错着**, 而且**两个方向都错**:
##
##     「近战斗士」16px  真宽 64.0  估 39.7  ⇒ 居中把字往右推 +12.2 px
##     「Lv 1」   16px  真宽 26.0  估 39.7  ⇒ 居中把字往左拉  -6.8 px
##
## 0.62 是**英文比例字体**的字宽比, 而本项目的字体链是 `m6x11`(像素字, ASCII 实测约
## **0.41 em**) + `Noto Sans SC`(中文**全角 1.0 em**) —— 一个系数覆盖 0.41 与 1.0 两端,
## 无论调成多少都有一半是错的。**换系数是把尺子改到能量过为止, 不是把尺子修对。**
## ⇒ 直接问字体: `Font.get_string_size()`, 与门禁 `verify_ui_consistency._ink_rect`
##   量"真正画出来那块字"用的**是同一行调用**, 两边同尺。
##
## ★`get_theme_font` 要在 `add_child` **之后**问: 主题是顺着场景树往上找的,
##   离树的 Label 拿不到项目主题里那条字体链(会退到引擎内建字体, 量出来的宽是另一码事)。
##   `detail` 是普通 Control(不布局), add_child 不会动 position ⇒ 后置设位置是安全的。
## ★`est_h` 仍按 `字号 × 1.3` 估: 实测 `get_height()` 与它只差 1~2px(垂直锚 oy=0.5
##   ⇒ 落到位置上是 0.5~1px), 而改它会让**整个图鉴每一行文字都动**, 收益不抵风险。
func _add_text(x: float, y: float, text: String, size: int, color: String,
		ox: float = 0.0, oy: float = 0.5, bold: bool = false, w: float = 0.0) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", Color(color))
	if bold:
		lbl.add_theme_constant_override("outline_size", 0)
	if w > 0.0:
		lbl.custom_minimum_size = Vector2(w, 0)
	detail.add_child(lbl)
	var est_w: float = w if w > 0.0 else _ink_w(lbl, text, size)
	var est_h := float(size) * 1.3
	lbl.position = Vector2(x - ox * est_w, y - oy * est_h)
	return lbl


## 一段字在某字号下**真正画出来**有多宽。拿不到字体才退回"按全角算"——
## 宁可估宽(居中时字略偏左、贴边时留白多)也别估窄: 估窄会把字推出框外。
func _ink_w(lbl: Label, text: String, size: int) -> float:
	var f: Font = lbl.get_theme_font("font")
	if f == null:
		return float(text.length()) * float(size)
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


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
	# 这个函数是详情页所有矩形的**唯一漏斗** —— 描边矩形(卡片/图标框)换金属框,
	# 无描边的(分隔线 h=1、实心色块)保持原样: 它们本来就不是"盒子"。
	# 尺寸门槛交给 nine_if_big, 26px 那种小格子会自动退回纯色。
	var box_sb: StyleBox = sb
	if stroke != "" and stroke_w >= 1.0:
		box_sb = UISkin.nine_if_big(w, h, "panel-frame.png", 20, sb)
		if box_sb is StyleBoxTexture:
			var bc := Color(stroke)
			(box_sb as StyleBoxTexture).modulate_color = UISkin.tint_of(bc)
	p.add_theme_stylebox_override("panel", box_sb)
	detail.add_child(p)
	return p


## 图鉴显示用的数值上下文 —— 必须与战斗里**真生成出来的单位**逐数相同。
## ★★2026-10-07(内测前图鉴体检 A/J): 原来这里乘了 `DataRegistry.rarity_mult`(B×1.03 … SSS×1.15),
##   而战斗 `_make_unit`(battle_spawn.gd)**从来不乘稀有度** ⇒ 非 C 龟的血/攻/双抗和所有
##   {N:…ATK} 技能数字在图鉴上虚高 3~15%。等级也读错了: 读的是 `pet_levels`(唯一写入方是图鉴调试面板, 已于同日删除),
##   而战斗读的是赛季等级 ⇒ 见 `_battle_level`。
## 守卫: tests/verify_codex_battle_parity.gd(拿真生成的战斗单位逐项比)。
func _ctx_for(pet: Dictionary) -> Dictionary:
	var lv: int = _battle_level(str(pet.get("id", "")))
	var m: float = UnitScaling.level_multiplier(lv)
	return {
		"atk": roundi(pet.get("atk", 0) * m), "def": roundi(pet.get("def", 0) * m),
		"mr": roundi(pet.get("mr", pet.get("def", 0)) * m), "maxHp": roundi(pet.get("hp", 0) * m),
		"crit": pet.get("crit", 0.0), "lv": lv,
	}


## 这只龟在玩家这一侧开战时**真正吃到的等级** —— 与战斗同一套取法:
##   `RealtimeBattle3DScene._unit_level("left")`(调试强制等级 > 赛季等级)
##   + `battle_spawn._make_unit` 里的 `GameState.temp_level_bonus(id)`(临时等级器)。
## ★不读 `get_pet_level` —— 那个表真玩家恒为 1(写它的调试面板已删), 战斗侧没人读它。
func _battle_level(pet_id: String) -> int:
	var lv: int = GameState.debug_level if GameState.debug_level > 0 else maxi(1, GameState.season_level)
	return lv + GameState.temp_level_bonus(pet_id)


# ─── 龟详情 (1:1 PoC showPetDetail 顶部固定区) ───
# ══════════════════════════════════════════════════════════
## 深海小将的定义已搬到 `scripts/gamedata/minion_codex.gd`(2026-08-20) —— 战斗信息面板也要用同一份,
## 留在这里就会变成"图鉴一份、战斗一份"的手抄。下面两个别名只是为了不改本文件其余引用。
const MINION_KINDS := MinionCodex.MINION_KINDS
const MINION_INFO := MinionCodex.MINION_INFO
## 小将详情页 — 布局对齐 _codex_detail._show_pet(立绘左上 / 名字与属性右上 / 分隔线下技能被动).
var _codex_form_view: bool = false   # 图鉴双形态: false=普通skillPool, true=形态(近战/火山)技能
var _codex_skill_detail: Dictionary = {}   # 内联技能详情视图 (非空=显示该技能完整detail+返回钮, 1:1 PoC view={skillIdx}; 空=技能卡列表)
var _codex_passive_view: bool = false   # 内联被动展开 (true=下方区显示完整被动desc, 1:1 PoC view='passive'; false=技能卡列表)
