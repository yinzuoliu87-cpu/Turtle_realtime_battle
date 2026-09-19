## 枢纽页顶栏 —— 返回 / 页名 / 右侧动作，全项目一套规则。
##
## ★★为什么有它（2026-09-19，用户「这个按钮你不要看原项目的，原项目的就丑啊」）：
##   九个屏九种返回键（圆圈 ← / 木框「← 返回」/ 青方框 / 深灰框 / 木框「← 取消」/
##   金色「保存并返回」），而我给的第一个建议是「统一成木框，因为九个里三个已经是」——
##   **那是数自家人头，不是手艺**，而那三个正是被否掉的那批。
##
## ★这套规则是从 **599 张 / 146 个触屏游戏**的枢纽页（Game UI Database
##   `plat=2` 触屏 × Inventory/Equipping/Buying/Currency-Store/Collection/Codex/
##   Leaderboards/Profile/Loadout/Team 十类）逐张看出来的，不是我拍的：
##
##   ① **返回键永远是扁平薄片，和它所在那条栏同一套皮。**
##      146 款里**没有一款**用「四角包边的厚木框/金属框」做返回 ——
##      那种厚框只用在**主 CTA**（"开始战斗"那种）上。
##      把最重的视觉分量给最不重要的动作，是我们现在的做法。
##   ② **整页用箭头，叠加面板用 ✕。** Octopath(H348-367) 两个都有：
##      左上 `←` 回上一层、右上 `✕` 关掉整个面板。
##   ③ **六款互不相干的游戏做到了同一个结构**：左上返回箭头 + 紧跟当前页名，
##      右上资源条末尾一枚 `⌂` 回主菜单 —— Arknights(H020) / Disney Mirrorverse(H106)
##      / Shadow Fight Arena(H446) / Smash Legends(H464) / Super Brawl Universe(H488)
##      / Wind Runner(H563)；Dropmix(H134) 是同族变体（左 `‹` / 居中标题 / 右 `?`）。
##   ④ 要么**带字就大而清楚**，要么**纯图标就完全不带字** ——
##      不存在「小字缩在大框中间」（我们阵容屏那个 78×85 的框里字只占中间一条）。
##
## ★**统一的是规则不是长相**：每屏传自己的配色（木桌屏暖色 / 深色屏冷色），
##   所以不会出现「木框按钮压在深蓝面板上」那种两套语言并存。
##
## 用法（照 `dmg_stats_panel.gd` 的拆分模板：RefCounted + 构造注入）：
##
##   const TopBar = preload("res://scripts/util/top_bar.gd")
##   var bar := TopBar.new(self, {
##       "title": "背包",
##       "on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
##       "palette": TopBar.WOOD,          # 或 TopBar.DEEP
##       "actions": [["?", func(): _help()], ["⌂", func(): _home()]],
##   })
class_name TopBar
extends RefCounted

## ★44pt 触控下限 = 81 视口像素（本项目 1pt = 1.846px，见 info_panel.gd:1332）。
## 排行榜那个 120×44 的返回键实测只有 **24pt**，本原语不许再出现这种。
const TOUCH_MIN := 81.0

## 栏高。比触控下限多 6px 余量，让薄片上下各留 3px 不贴死。
const BAR_H := 87.0
## 薄片本体高（扁平那一条）。★不是整条栏高 —— 参考里的返回都是"栏里的一小片"。
const CHIP_H := 58.0
const CHIP_MIN_W := 81.0     # 纯图标时的宽 = 触控下限
const PAD_X := 18.0          # 薄片离屏幕边
const GAP := 10.0            # 薄片与页名之间
const ACT_GAP := 12.0        # 右侧动作之间

## 两套配色。★只是【取值不同】，结构完全一样 —— 这就是"统一规则不统一长相"。
##   bg/边/字 三个色 + 一个按下态。
const WOOD := {                                    # 木桌世界（阵容/主菜单系）
	"bar": Color(0.16, 0.11, 0.07, 0.86),
	"chip": Color(0.28, 0.19, 0.11, 0.95),
	"edge": Color(0.78, 0.62, 0.32, 1.0),
	"text": Color(0.97, 0.90, 0.74, 1.0),
	"press": Color(0.40, 0.28, 0.15, 1.0),
}
const DEEP := {                                    # 深色界面（背包/商店/图鉴/排行榜/战绩）
	"bar": Color(0.05, 0.09, 0.14, 0.86),
	"chip": Color(0.11, 0.17, 0.24, 0.95),
	"edge": Color(0.35, 0.60, 0.78, 1.0),
	"text": Color(0.88, 0.94, 1.0, 1.0),
	"press": Color(0.18, 0.28, 0.38, 1.0),
}

var bar: Control = null            # 顶栏本体（调用方定位/入场）
var back_btn: Button = null
var title_label: Label = null
var action_btns: Array = []        # 右侧动作，顺序与传入一致

var _pal: Dictionary = DEEP
var _width: float = 1280.0


func _init(host: Node, opts: Dictionary) -> void:
	_pal = opts.get("palette", DEEP)
	_width = float(opts.get("width", 1280.0))

	bar = Control.new()
	bar.name = "TopBar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size = Vector2(_width, BAR_H)
	## ★★**先挂进树再建子节点**: 节点不在树里时解析不到项目主题的字体,
	##   `get_minimum_size()` / `get_theme_font()` 都会拿默认值(字号 16 而不是 26)。
	##   第一版我就是在建完才 `host.add_child(bar)`, 于是量出来的标题宽偏小,
	##   商店薄片直接**压在「包」字上** —— 量了真实对象, 但量在它还没布局的时刻。
	if host is Node:
		(host as Node).add_child(bar)

	## 栏底：一条通栏的薄底。★不是九宫格厚框 —— 见文件头 ①。
	var plate := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = _pal["bar"]
	psb.border_width_bottom = 2
	psb.border_color = Color(_pal["edge"].r, _pal["edge"].g, _pal["edge"].b, 0.35)
	plate.add_theme_stylebox_override("panel", psb)
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(plate)

	## ★安全区：手机刘海/圆角那侧 inset 可达 44pt，薄片要让开。
	##   调用方把 `SafeArea.margins(...)` 算出来的左/上传进来。
	var sl: float = maxf(PAD_X, float(opts.get("safe_left", 0.0)))
	var sr: float = maxf(PAD_X, float(opts.get("safe_right", 0.0)))

	## ── 左上：返回薄片 ─────────────────────────────────────
	var back_text := str(opts.get("back_text", "←"))
	back_btn = _chip(back_text, opts.get("on_back", Callable()))
	back_btn.position = Vector2(sl, (BAR_H - TOUCH_MIN) / 2.0)
	bar.add_child(back_btn)

	## ── 紧跟当前页名 ★参考里六款全是这个顺序（返回→页名），不是页名居中 ──
	var title := str(opts.get("title", ""))
	if title != "":
		title_label = Label.new()
		title_label.text = title
		title_label.add_theme_font_size_override("font_size", 26)
		title_label.add_theme_color_override("font_color", _pal["text"])
		title_label.position = Vector2(sl + back_btn.size.x + GAP, 0.0)
		title_label.size = Vector2(520.0, BAR_H)
		title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(title_label)

	## ── 左侧横向导航（跟在页名后面）──
	##   ★参考里【去另一个枢纽页】的入口都紧跟在标题后（Botworld 的
	##   Loadout/Inventory/Robopedia、Shadow Fight 的 YOUR TEAM|EMOTES），
	##   而不是挤到右边跟资源条抢位。
	var lx: float = sl + back_btn.size.x + GAP
	if title_label != null:
		## ★★量**真实 Label** 的最小宽, 不用公式估 ——
		##   第一版我按字符数算(中文 26 / 拉丁 14.3), 实拍出来
		##   「商店」那枚薄片几乎贴在「背包」两字上。
		##   本项目记过: **公式算出来的不算, 要量真实对象**。
		var tf: Font = title_label.get_theme_font("font")
		var tw: float = 0.0
		if tf != null:
			tw = tf.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		else:
			tw = title_label.get_minimum_size().x
		lx += tw + GAP * 2.0
	for a2 in opts.get("left_actions", []):
		var lb := _chip(str((a2 as Array)[0]), (a2 as Array)[1] as Callable)
		if (a2 as Array).size() > 2 and (a2 as Array)[2] is Dictionary:
			var lo: Dictionary = (a2 as Array)[2]
			if bool(lo.get("disabled", false)):
				lb.disabled = true
				lb.modulate = Color(1, 1, 1, 0.45)
			if str(lo.get("tooltip", "")) != "":
				lb.tooltip_text = str(lo.get("tooltip", ""))
		lb.position = Vector2(lx, (BAR_H - TOUCH_MIN) / 2.0)
		lx += lb.size.x + ACT_GAP
		bar.add_child(lb)
		action_btns.append(lb)

	## ── 右上：动作（`⌂` 回主菜单 / `?` 帮助），与返回**同款同高** ──
	##   ★这一条是判据之一：右侧动作和返回长得不一样，就是"一屏两套语言"，
	##     我们背包现在正是（左边木框皮 + 右边手写深底小方框）。
	var acts: Array = opts.get("actions", [])
	var x := _width - sr
	## 每条动作 = [文本, Callable] 或 [文本, Callable, {disabled, tooltip}]。
	## ★禁用态要能表达 —— 商店在打完第一场前是锁着的,
	##   而「直接不画按钮」会让玩家以为没这条路(原 `InventoryScene` 注释就这么写的)。
	for i in range(acts.size() - 1, -1, -1):
		var a: Array = acts[i]
		var b := _chip(str(a[0]), a[1] as Callable)
		if a.size() > 2 and a[2] is Dictionary:
			var ao: Dictionary = a[2]
			if bool(ao.get("disabled", false)):
				b.disabled = true
				b.modulate = Color(1, 1, 1, 0.45)
			if str(ao.get("tooltip", "")) != "":
				b.tooltip_text = str(ao.get("tooltip", ""))
		x -= b.size.x
		b.position = Vector2(x, (BAR_H - TOUCH_MIN) / 2.0)
		x -= ACT_GAP
		bar.add_child(b)
		action_btns.push_front(b)


## 追加一枚右侧动作（给“顶栏建完之后才知道要不要这个键”的屏）。
## ★返回按钮本身，调用方自己定位 —— 有的屏右侧已经被资源条占着。
func add_right_action(txt: String, cb: Callable, o: Dictionary = {}) -> Button:
	var b := _chip(txt, cb)
	if bool(o.get("disabled", false)):
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.45)
	if str(o.get("tooltip", "")) != "":
		b.tooltip_text = str(o.get("tooltip", ""))
	b.position = Vector2(_width - PAD_X - b.size.x, (BAR_H - TOUCH_MIN) / 2.0)
	bar.add_child(b)
	action_btns.append(b)
	return b


## ★★把「薄片皮」单独抽成**静态函数** —— 给那些**有自己布局系统的屏**用。
##   阵容屏有一整套命名定位槽(`_place_clamped`)+入场动画(`_ent_top`)+resize 重建，
##   硬塞一条整宽顶栏会跟它打架。但【规则】得一致：同一张皮、同一条触控线。
##   ★如果另写一份就是本项目记过的「手抄的副本必然落后」—— 所以走同一个函数。
static func apply_chip_skin(b: Button, pal: Dictionary, icon_only: bool = false) -> void:
	b.add_theme_font_size_override("font_size", 38 if icon_only else 22)
	for ck in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(ck, pal["text"])
	var old := b.get_node_or_null("chip_plate")
	if old != null:
		old.free()

	## ★★**图标型：零盒子**。六款参考里 Disney Mirrorverse(H106)/
	##   Shadow Fight(H446)/Super Brawl(H488) 三款就是裸箭头无框。
	if icon_only:
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(st, empty)
		return

	## ★★**文字型：扫平的矩形底，直接当 Button 自己的 stylebox**。
	##   ★第一版我把底板做成**子节点** —— 子节点画在父的文字**之上**,
	##   换成不透明九宫格后**文字直接被盖没了**(实拍只剩空框)。
	##   ★第二版用 `StyleBoxFlat + 圆角 + 四边半透边框` —— 那正是本项目
	##   `verify_ui_consistency` 叫做【网页盒】的签名(CSS border+rgba), 全套当场红。
	##   ⇒ 现在：**不透明底 + 零边框 + 零圆角** —— 两条签名都不沾,
	##   而且它正是 Arknights(H020) 那种扁平矩形薄片的长相。
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(pal["chip"].r, pal["chip"].g, pal["chip"].b, 1.0)
	sb.set_corner_radius_all(0)
	sb.set_border_width_all(0)
	## 上下内缩：按钮本体是 81 高(热区), 画出来的那片只有 CHIP_H 高。
	var inset: float = (TOUCH_MIN - CHIP_H) / 2.0
	sb.expand_margin_top = -inset
	sb.expand_margin_bottom = -inset
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = Color(pal["chip"].r * 1.35, pal["chip"].g * 1.35, pal["chip"].b * 1.35, 1.0)
	var pr := sb.duplicate() as StyleBoxFlat
	pr.bg_color = Color(pal["press"].r, pal["press"].g, pal["press"].b, 1.0)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", sb)
	b.add_theme_stylebox_override("disabled", sb)


## 一枚薄片。纯图标 → 正方(≥触控线)；带字 → 按字宽撑开。
func _chip(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	## 宽：纯图标(≤2 字符)取正方且不低于触控线；带字按内容算再夹一次下限。
	var icon_only: bool = txt.length() <= 2
	var w: float = CHIP_MIN_W
	if not icon_only:
		w = maxf(CHIP_MIN_W, float(txt.length()) * 17.0 + 44.0)
	b.size = Vector2(w, TOUCH_MIN)
	b.custom_minimum_size = Vector2(w, TOUCH_MIN)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	## ★皮走**同一个**静态函数 —— 不在这里再抄一份。
	apply_chip_skin(b, _pal, icon_only)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

