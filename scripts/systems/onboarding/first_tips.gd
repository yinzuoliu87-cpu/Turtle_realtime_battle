class_name FirstTips
extends RefCounted
## 「第一次遇到」一行提示(账号侧, 不是教程的一部分)—— 方案书 docs/plans/20261020-教程重写.md §3。
##
## 每条只出现一次: 一行短句 + 高亮环, 点任意处或 HOLD_SEC 秒后消失; 不弹窗、不压暗、不挡点击、不暂停。
## 「看过了」记在账号存档 `GameState.first_tips_seen`(随存档 / 云存档走)。
## ★★教程进行中一律不出现、也不写(`can_show` 第一条): 教程是完全隔离的沙盒(memory fb-tutorial-is-full-sandbox),
##   而且沙盒期间 GameState 里是教程状态, 写了也会随沙盒一起丢 —— 这里先挡住, 不靠那一层兜底。
## ★照 CLAUDE.md §5 拆分模板: 主菜单侧只剩一行 `FirstTips.show(...)`。
##
## 已接的条目(其余见方案书 §3 表, 待各自的界面定稿):
##   START_BATTLE 教程刚结束、本大轮 0 场 ⇒ 主菜单「开始战斗」
##   GAUNTLET_DAY 第一次在周六打开主菜单 ⇒ 模式卡
##   FINALS_DAY   第一次在周日打开主菜单 ⇒ 模式卡
##   FIRST_SYNERGY 背包里第一次有羁绊激活 ⇒ 第一条已激活的羁绊行
##   FIRST_MERGE   商店里第一次买到合成升星 ⇒ 左下宝箱里升星的那一格
##   SERVER_MATCH  第一次看周六服务器局(自己那一场) ⇒ 顶部路名计时牌
##   FIRST_TRAINER 第一次打开训龟大师页 ⇒ 展台上的训龟大师立绘
##   FIRST_WEEK    教程结束(走完 / 跳过)后第一次进主菜单 ⇒ 打开「本周赛程」页, 页上一句赛季说明(主菜单 `_first_week`)
##   FIRST_LANES / FIRST_EGG / FIRST_FINAL  第一场正式对战 ⇒ 两路 / 龟蛋 / 终极战场各一句,
##     句子就是教程战斗那三句(data/tutorial-steps.json battle C2 / C5 / C6, 不另抄一份), 挂在同一个战斗事件上
##     (导演 `_attach_first_battle_tips`)。教程战斗里真显示过的那几句, 教程结束时记成看过(不再出第二次)。
##   (用户 2026-10-21: 首启只 1 屏介绍; 赛程放教程最后; 跳过的玩家首进主菜单弹一次赛程, 首场正式对战两路 / 龟蛋 / 终极战场各一次。)
## 措辞参考(方案书 §3 / 实施记录): 云顶之弈 PC 教程原文
##   「Combine three of the same champion to create a stronger, two-star version of that champion.」
##   「Champions have traits and earn bonuses when deployed with other champions that share those traits.」
##   「Champions fight automatically」(https://wiki.leagueoflegends.com/en-us/TFT:Tutorial)。

const START_BATTLE := "start_battle"
const GAUNTLET_DAY := "gauntlet_day"
const FINALS_DAY := "finals_day"
const FIRST_SYNERGY := "first_synergy"
const FIRST_MERGE := "first_merge"
const SERVER_MATCH := "server_match"
const FIRST_TRAINER := "first_trainer"
const FIRST_WEEK := "first_week"
const FIRST_LANES := "first_lanes"
const FIRST_EGG := "first_egg"
const FIRST_FINAL := "first_final"
## 教程战斗步骤 _id(data/tutorial-steps.json battle) → 首场正式对战那一条的键。文字只在步骤表里有一份。
const BATTLE_TIP_KEYS := {"C2": FIRST_LANES, "C5": FIRST_EGG, "C6": FIRST_FINAL}

## 文案 —— 短指令 / 名词(memory fb-no-colloquial-copy)。周末两条的赛制名读 `phase2_config.PHASE_LABEL`, 不手抄。
const TEXT_START := "开始第一场对战"
const TEXT_RULES := "%s · 点击查看规则"
## 「查看羁绊详情」是背包羁绊行自己的提示(synergy_panel.gd), 点开就是详情 ⇒ 这里说同一个动作。
const TEXT_SYNERGY := "羁绊已激活 · 点击查看详情"
## 与背包「?」说明里那一条同一句(InventoryScene 说明面板「3 件同名同星装备自动合成升星」)。
const TEXT_MERGE := "3 件同名同星装备自动合成升星"
## 周六服务器局: 结果在播之前已由服务器定好并记账(referee_watch.gd 头注「账在播之前就记完」)。
const TEXT_SERVER := "本场由服务器判定 · 退出不影响结果"
const TEXT_TRAINER := "训龟大师在战斗中施放所选技能"
## 本周赛程页上那一句(用户 2026-10-21 定稿)。赛制名读 PHASE_LABEL(积分赛 / 闯关赛 / 决赛日), 星期与 phase_of_weekday 一致。
const TEXT_WEEK := "斗龟场每周是一个赛季：周二到周五是%s，周六是%s，周日是%s，争夺本周冠军。每到周一，所有人从同一起点重新开始。"

const HOLD_SEC := 5.0
const FADE_SEC := 0.3
const LAYER := 7000          # 低于教程引导条(8000)与跳过钮(9000)
const NODE_NAME := "FirstTip"

const _P2C := preload("res://scripts/gamedata/phase2_config.gd")


static func _gs() -> Object:
	var tr := Engine.get_main_loop() as SceneTree
	return tr.root.get_node_or_null("/root/GameState") if tr != null and tr.root != null else null


## 这条现在能不能出: 不在教程里、看过首次教程(选择框不与它抢)、这条还没看过。
static func can_show(key: String) -> bool:
	var gs := _gs()
	if gs == null or bool(gs.get("tutorial_active")) or not bool(gs.get("onboarded")):
		return false
	var seen = gs.get("first_tips_seen")
	return not (seen is Dictionary and bool((seen as Dictionary).get(key, false)))


## 记成看过(内存)。★教程中不写(同 can_show 的理由)。
## ★不在这里 `save()`: 第 1 条恰好在教程刚结束那一刻出现, 而「教程结束后存档 = 进教程前那份只差 onboarded」
##   是逐字节守着的(verify_tutorial_skip / verify_tutorial_flow_v3)。标记随下一次正常存档落盘;
##   万一进程在那之前被杀, 代价只是这句提示再出现一次。
static func mark_seen(key: String) -> void:
	var gs := _gs()
	if gs == null or bool(gs.get("tutorial_active")):
		return
	var seen: Dictionary = (gs.get("first_tips_seen") as Dictionary).duplicate() if gs.get("first_tips_seen") is Dictionary else {}
	seen[key] = true
	gs.set("first_tips_seen", seen)


## 周末两条用哪一条(今天不是周六 / 周日 ⇒ "")。
static func weekend_key(phase: String) -> String:
	if phase == _P2C.PHASE_GAUNTLET:
		return GAUNTLET_DAY
	if phase == _P2C.PHASE_FINALS:
		return FINALS_DAY
	return ""


static func text_for(key: String) -> String:
	match key:
		START_BATTLE:
			return TEXT_START
		GAUNTLET_DAY:
			return TEXT_RULES % str(_P2C.PHASE_LABEL.get(_P2C.PHASE_GAUNTLET, ""))
		FINALS_DAY:
			return TEXT_RULES % str(_P2C.PHASE_LABEL.get(_P2C.PHASE_FINALS, ""))
		FIRST_SYNERGY:
			return TEXT_SYNERGY
		FIRST_MERGE:
			return TEXT_MERGE
		SERVER_MATCH:
			return TEXT_SERVER
		FIRST_TRAINER:
			return TEXT_TRAINER
		FIRST_WEEK:
			return TEXT_WEEK % [str(_P2C.PHASE_LABEL.get(_P2C.PHASE_RANKED, "")),
				str(_P2C.PHASE_LABEL.get(_P2C.PHASE_GAUNTLET, "")), str(_P2C.PHASE_LABEL.get(_P2C.PHASE_FINALS, ""))]
	return ""


## 首场正式对战那三句: 教程战斗步骤表里 BATTLE_TIP_KEYS 那几步(原样, 带 trigger / highlight / auto), 每步多一个 `_ft_key`。
##   only_unseen = 只要还能出的(can_show)。读不到步骤表 ⇒ 空。
static func battle_tip_steps(only_unseen: bool) -> Array:
	var out: Array = []
	for st in load("res://scripts/scenes/TutorialGuide.gd").steps_for("battle"):
		var key := str(BATTLE_TIP_KEYS.get(str((st as Dictionary).get("_id", "")), ""))
		if key == "" or (only_unseen and not can_show(key)):
			continue
		var s2: Dictionary = (st as Dictionary).duplicate()
		s2["_ft_key"] = key
		out.append(s2)
	return out


## 出一条: 能出就挂到 host 上并记成看过, 返回那个节点; 不能出 ⇒ null(什么都不做)。
## target = 要圈的控件(跟着它走; 它还没淡入完时先不显示)。
static func show(host: Node, key: String, target: Control) -> Node:
	if host == null or not host.is_inside_tree() or target == null or not can_show(key):
		return null
	var txt := text_for(key)
	if txt == "":
		return null
	mark_seen(key)
	var n := TipNode.new()
	n.name = NODE_NAME
	n.key = key
	n.setup(txt, target)
	host.add_child(n)
	return n


## 战斗场是不是「看自己那一场周六服务器局」: 重算录像那条路(referee_watch.is_watch)或逐帧直播那条路
##   (stream_watch 会话 kind=referee 且带服务器结果)。别人的局 / 周日 / 普通回放 ⇒ 否。
static func is_server_match(battle: Node) -> bool:
	if battle == null:
		return false
	var RW = load("res://scripts/systems/replay/referee_watch.gd")
	if RW.is_watch(battle):
		return true
	var rp = battle.get("_replay")
	if rp == null or str(rp.mode) != "stream":
		return false
	var SW = load("res://scripts/systems/replay/stream_watch.gd")
	var sess: Dictionary = SW.current
	var res = sess.get("result", {})
	return str(sess.get("kind", "")) == str(SW.KIND_REFEREE) and res is Dictionary and not (res as Dictionary).is_empty()


## 顶栏建好时调(topbar_status): 是周六服务器局 ⇒ 圈路名计时牌出一条。
static func server_match_tip(battle: Node, target: Control) -> Node:
	if not is_server_match(battle):
		return null
	return show(battle, SERVER_MATCH, target)


## 一条提示本身。全部控件 MOUSE_FILTER_IGNORE; 点击只「顺带」让它消失, 不吃掉那次点击。
class TipNode extends Node:
	var key := ""
	var _target: Control = null
	var _layer: CanvasLayer = null
	var _ring: ColorRect = null
	var _panel: PanelContainer = null
	var _label: Label = null
	var _t := 0.0
	var _shown := false
	var _closing := false
	var _fade_t := 0.0

	func setup(txt: String, target: Control) -> void:
		_target = target
		process_mode = Node.PROCESS_MODE_ALWAYS
		_layer = CanvasLayer.new()
		_layer.layer = LAYER
		_layer.visible = false
		add_child(_layer)
		_ring = ColorRect.new()
		_ring.color = Color(1, 0.85, 0.25, 0.0)
		_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring.set_script(preload("res://scripts/scenes/tutorial_ring.gd"))
		_layer.add_child(_ring)
		_panel = PanelContainer.new()
		_panel.name = "FirstTipPanel"
		_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.071, 0.110, 0.204, 0.94)
		sb.set_border_width_all(2)
		sb.border_color = Color("#ffd93d")
		sb.content_margin_left = 20; sb.content_margin_right = 20
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		_panel.add_theme_stylebox_override("panel", sb)
		_layer.add_child(_panel)
		_label = Label.new()
		_label.name = "FirstTipText"
		_label.text = txt
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.add_theme_font_size_override("font_size", 22)
		_label.add_theme_color_override("font_color", Color("#fff3c4"))
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		_label.add_theme_constant_override("outline_size", 4)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(_label)

	func text() -> String:
		return _label.text if _label != null else ""

	func is_showing() -> bool:
		return _layer != null and _layer.visible

	## 门禁用: 本层有没有能吃到点击的可见控件(必须恒假)。
	func is_blocking() -> bool:
		if _layer == null or not _layer.visible:
			return false
		for c in _layer.find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree() and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
				return true
		return false

	func panel_rect() -> Rect2:
		return Rect2(_panel.position, _panel.size) if is_showing() else Rect2()

	## 提示条放哪: 依次试 正上方 / 左上 / 左侧 / 右上 / 右侧 / 正下方 / 左下 / 右下, 取第一个「在屏内且不压别的可见文字与按钮」的位置;
	##   一个都不干净 ⇒ 取屏内压得最少的那个。
	##   ★实拍(10-20): 固定放正上方时压住了「开始战斗」正上方那条计数条(♥ 命 · 本周对战)。
	##   ★门禁(10-20 补四条时): 训龟大师技能卡正上方是分组签、商店「背包」左边是返回键 —— 只有 5 个候选时全撞, 原来的兜底直接压上去。
	func _pick_spot(rr: Rect2, sz: Vector2, screen: Rect2) -> Vector2:
		var g := 12.0
		var cands := [
			Vector2(rr.get_center().x - sz.x * 0.5, rr.position.y - g - sz.y),
			Vector2(rr.position.x - g - sz.x, rr.position.y - g - sz.y),
			Vector2(rr.position.x - g - sz.x, rr.get_center().y - sz.y * 0.5),
			Vector2(rr.end.x + g, rr.position.y - g - sz.y),
			Vector2(rr.end.x + g, rr.get_center().y - sz.y * 0.5),
			Vector2(rr.get_center().x - sz.x * 0.5, rr.end.y + g),
			Vector2(rr.position.x - g - sz.x, rr.end.y + g),
			Vector2(rr.end.x + g, rr.end.y + g),
			Vector2(rr.position.x, rr.end.y + g),
			Vector2(rr.end.x - sz.x, rr.end.y + g),
		]
		var avoid := _avoid_rects()
		var best := Vector2(-1, -1)
		var best_n := 1 << 30
		for c in cands:
			var r := Rect2((c as Vector2).round(), sz)
			if not screen.grow(-4.0).encloses(r):
				continue
			var n := 0
			for a in avoid:
				if r.intersects(a as Rect2):
					n += 1
			if n == 0:
				return r.position
			if n < best_n:
				best_n = n
				best = r.position
		if best.x >= 0.0:
			return best
		var p0: Vector2 = cands[0]
		return Vector2(clampf(p0.x, 12.0, screen.size.x - sz.x - 12.0), maxf(8.0, p0.y)).round()

	## 宿主上看得见的文字 / 按钮(目标自己那一块除外; 整屏背景那种大块不算 —— 宽 900 以内都算: 商店成交提示条约 650 宽, 10-20 实拍被压过)。
	func _avoid_rects() -> Array:
		var out: Array = []
		var host := get_parent()
		if host == null:
			return out
		for c in host.find_children("*", "Control", true, false):
			var ctl := c as Control
			if not (ctl is Label or ctl is BaseButton) or not ctl.is_visible_in_tree():
				continue
			if ctl == _target or (_target != null and _target.is_ancestor_of(ctl)) or is_ancestor_of(ctl):
				continue
			if ctl is Label and (ctl as Label).text.strip_edges() == "":
				continue
			var r := ctl.get_global_rect()
			if r.size.x <= 0.0 or r.size.x > 900.0:
				continue
			out.append(r)
		return out

	func _input(ev: InputEvent) -> void:
		## 点任意处 ⇒ 收起。★不 set_input_as_handled: 那一下照常落到底下的按钮上。
		if _shown and ((ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) \
				or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed)):
			_close()

	## 收起: 淡出 FADE_SEC 秒后释放。★不用 tween(门禁 tween_freeze / battle_tween 只认战斗世界侧注册的 tween;
	##   这里是主菜单 UI, 在 _process 里自己数时间即可)。
	func _close() -> void:
		_closing = true

	func _process(dt: float) -> void:
		if _closing:
			_fade_t += dt
			var al: float = clampf(1.0 - _fade_t / FADE_SEC, 0.0, 1.0)
			_panel.modulate.a = al
			_ring.modulate.a = al
			if _fade_t >= FADE_SEC:
				queue_free()
			return
		var TG = load("res://scripts/scenes/TutorialGuide.gd")
		var r: Rect2 = TG.vis_rect(_target) if is_instance_valid(_target) else Rect2()
		if r.size.x <= 0.0:
			_layer.visible = false
			if not is_instance_valid(_target):
				queue_free()
			return
		_layer.visible = true
		_shown = true
		_t += dt
		var rr := r.grow(6.0)
		_ring.position = rr.position
		_ring.size = rr.size
		_ring.queue_redraw()
		var vp: Vector2 = _layer.get_viewport().get_visible_rect().size
		var sz: Vector2 = _panel.get_combined_minimum_size()
		_panel.size = sz
		_panel.position = _pick_spot(rr, sz, Rect2(Vector2.ZERO, vp))
		if _t >= HOLD_SEC:
			_close()
