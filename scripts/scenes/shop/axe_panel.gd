class_name AxePanel
extends RefCounted
## 商店里的【小木斧·砍伐进度】面板 + 【最终造物四选一】(2026-09-01)
##
## ══════════════════════════════════════════════════════════════════
##  ★为什么要有它
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-01:「用户难道就这么玩吗，则怎么选择最终造物呢，进度条呢」。
##
## 到 v0.19.311 为止, 砍伐经验/进化/最终造物的**机制全做完了、门禁也全绿**,
## 但玩家**一样都看不见**:
##   · 经验在涨, 屏幕上没有任何地方显示它 ⇒ 玩家不知道自己在攒东西
##   · `final_ready()` 会变 true, 但**没有任何入口能选** ⇒ 最终进化永远发生不了
## 这就是"门禁全绿但功能不可玩"——**门禁量的是我实现的东西, 不是玩家玩得到的东西**。
##
## ⇒ 这个面板补上两样:
##   ① 进度条: 当前形态 + 「砍伐经验 N/M」+ 一条实心条(照商店头部那条等级经验条的写法)
##   ② 四选一: `final_ready()` 时长出四个按钮; 选完本大轮锁定(未决点 ⑩)
##
## ★照 CLAUDE.md §5 的拆分模板(dmg_stats_panel.gd): RefCounted + 构造注入宿主,
##   ShopScene 侧只剩两行调用。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const EID := "p2eq_096"

## 配色与商店头部那条等级经验条保持一致 —— 同一个界面里两条进度条不该长得不一样。
const BAR_BG := "#16293a"
const BAR_FILL := "#d9a441"      # 木质暖黄, 与等级条的 #ffd93d 区分开(那条是"大轮等级")
const BAR_FULL := "#7ee081"      # 攒满待进化 → 变绿, 提示"可以了"

var host = null


func _init(h) -> void:
	host = h


## 玩家现在【有没有资格】看到这个面板。
## ★口径: 拥有(背包或身上)就显示 —— 经验是赛季级的, 卖掉也不回退,
##   所以只要这大轮碰过它就该看得见自己的进度。
static func should_show(gs) -> bool:
	if gs == null:
		return false
	if gs.has_method("axe_owned") and gs.axe_owned():
		return true
	## 卖掉了但攒过经验 ⇒ 照样给看(否则玩家会以为进度没了)
	return int(gs.get("axe_exp_total")) > 0


## 在 (x, y) 处画出面板, 返回**用掉的高度**(调用方据此往下排版)。
func build(parent: Node, x: float, y: float, w: float) -> float:
	var gs = host.get_node_or_null("/root/GameState")
	if gs == null or not should_show(gs):
		return 0.0
	var stage_i: int = int(gs.axe_stage)
	var fin: String = str(gs.axe_final)
	var bar: int = int(gs.axe_exp_bar)
	var total: int = int(gs.axe_exp_total)
	var disp: Dictionary = AE.display(stage_i, fin)
	var ready: bool = AE.final_ready(bar, stage_i, fin)
	var need: int = AE.need_for_next(stage_i)
	var h := 0.0

	# ── 标题行: 当前形态 + 历史累计 ──
	var t := Label.new()
	t.text = "🪓 %s" % str(disp["name"])
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#ffd93d"))
	t.position = Vector2(x, y)
	t.size = Vector2(w * 0.55, 28)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(t)
	var tot := Label.new()
	## ★"历史累计"要显示 —— 召唤物的血/攻公式读的是它(未决点 ⑥), 玩家看不到它
	##   就不知道自己的斧头为什么越打越强。
	tot.text = "累计 %d" % total
	tot.add_theme_font_size_override("font_size", 17)
	tot.add_theme_color_override("font_color", Color("#9fb4c8"))
	tot.position = Vector2(x + w * 0.55, y)
	tot.size = Vector2(w * 0.45, 28)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(tot)
	h += 32.0

	# ── 进度条 ──
	var lbl := Label.new()
	lbl.text = ("砍伐经验 %d/%d（可做最终进化）" % [bar, need]) if ready \
		else ("砍伐经验 %d/%d" % [bar, need])
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(BAR_FULL if ready else "#9fb4c8"))
	lbl.position = Vector2(x, y + h)
	lbl.size = Vector2(w, 24)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
	h += 26.0
	var bg := ColorRect.new()
	bg.color = Color(BAR_BG)
	bg.position = Vector2(x, y + h)
	bg.size = Vector2(w, 16)
	parent.add_child(bg)
	var fl := ColorRect.new()
	fl.color = Color(BAR_FULL if ready else BAR_FILL)
	fl.position = Vector2(x, y + h)
	## ★分母用 `need` 而不是写死 —— 每一档的阈值不一样(80/110/130/160/400)
	fl.size = Vector2(w * clampf(float(bar) / float(maxi(1, need)), 0.0, 1.0), 16)
	parent.add_child(fl)
	h += 22.0

	## ★"怎么攒"**不在这里重复** —— 效果描述里已经有「砍伐经验：购买 +15／每场 +10／…」那一行,
	##   同一块面板上说两遍既占地方又显得没做完。省下的 26px 留给四选一按钮。

	# ── 最终造物四选一(只在攒够 400 且没选过时出现) ──
	if ready:
		var tip := Label.new()
		tip.text = "选一个最终造物（本大轮锁定，选完不能改）"
		tip.add_theme_font_size_override("font_size", 16)
		tip.add_theme_color_override("font_color", Color(BAR_FULL))
		tip.position = Vector2(x, y + h)
		tip.size = Vector2(w, 24)
		parent.add_child(tip)
		h += 26.0
		var bw: float = (w - 18.0) / 4.0
		for i in range(AE.FINALS.size()):
			var f: Dictionary = AE.FINALS[i]
			var b := Button.new()
			b.text = str(f["name"])
			b.add_theme_font_size_override("font_size", 15)
			b.position = Vector2(x + float(i) * (bw + 6.0), y + h)
			b.size = Vector2(bw, 40)
			## ★用 bind 传 key —— 循环变量在 lambda 里会被最后一轮覆盖(经典坑)
			b.pressed.connect(_pick.bind(str(f["key"])))
			parent.add_child(b)
		h += 46.0
	return h


## 选定最终造物 —— **只是转发**给 `GameState.axe_pick_final()`。
## ★不在这里直接写 `axe_final` / `axe_exp_bar`: 我第一版就是那么写的,
##   被自己的门禁「scripts/ 下没有文件直接赋值这三个字段」当场抓住(verify_axe_evolution ④)。
##   状态归 GameState 管, UI 只负责画和转发。
func _pick(key: String) -> void:
	var gs = host.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("axe_pick_final"):
		return
	if gs.axe_pick_final(key) and host.has_method("_rebuild"):
		host._rebuild()
