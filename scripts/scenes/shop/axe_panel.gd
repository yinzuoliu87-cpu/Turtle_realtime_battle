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
## ★★2026-09-28: 槽底色不再在这里定 —— 两条条都走 `ShopScene._pixel_bar`,
##   槽是九宫格金属贴图画的, 底色由贴图自己带。原来的 `BAR_BG := "#16293a"` 随之删掉
##   (留着就是个没人读的常量, 而"写了没人读"是本仓专门立过门禁的一整类毛病)。
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
	## ★32 → 30: 标签本身 28 高, 原来留 4px 行距 —— 收成 2px, 省下的 2px 归下面
	##   四选一按钮加高用(40→44 达标触控线)。面板总高不变, 不会新压到购买按钮。
	h += 30.0

	# ── 进度条 ──
	var lbl := Label.new()
	## ★★全角括号那一句改成平白的后缀(2026-09-28 去 ai 味)。
	##   ⚠ 前半段「砍伐经验 %d/%d」**一个字都不能动** —— `verify_axe_shop_codex`
	##     断言的就是屏幕上有「砍伐经验 40/80」这串(它是"玩家真的看得见进度"的分母)。
	lbl.text = ("砍伐经验 %d/%d · 可以做最终进化了" % [bar, need]) if ready \
		else ("砍伐经验 %d/%d" % [bar, need])
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(BAR_FULL if ready else "#9fb4c8"))
	lbl.position = Vector2(x, y + h)
	lbl.size = Vector2(w, 24)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
	h += 24.0   # ★26 → 24: 同上, 行距从 2px 收成 0(标签 24 高), 省的 2px 也归按钮
	## ★★2026-09-28 走宿主的 `_pixel_bar` —— 原来这里是「底一块 ColorRect + 填一块」,
	##   与商店头部那条等级经验条**各写一份**的纯色矩形(= CSS 进度条)。
	##   本文件头上那句「同一个界面里两条进度条不该长得不一样」现在才真正做到:
	##   两条走同一个函数, 想改样子只有一处可改(手抄的副本必然落后)。
	## ★分母用 `need` 而不是写死 —— 每一档的阈值不一样(80/110/130/160/400)
	## ★不加 `has_method` 兜底: 兜底会把"函数没了"变成"条不见了"——
	##   一条**静默消失的进度条**正是本文件要修的那种 bug(机制做完了玩家看不见)。
	##   宁可当场报错。宿主永远是 ShopScene(构造时注入的就是它)。
	host._pixel_bar(parent as Control, Vector2(x, y + h), Vector2(w, 16),
		float(bar) / float(maxi(1, need)), Color(BAR_FULL if ready else BAR_FILL))
	h += 22.0

	## ★"怎么攒"**不在这里重复** —— 效果描述里已经有「砍伐经验：购买 +15／每场 +10／…」那一行,
	##   同一块面板上说两遍既占地方又显得没做完。省下的 26px 留给四选一按钮。

	# ── 最终造物四选一(只在攒够 400 且没选过时出现) ──
	if ready:
		var tip := Label.new()
		## ★全角括号 + 逗号分句那一套是说明书体(「（本大轮锁定，选完不能改）」)。
		##   换成一句话说完, 分句用本仓通行的「·」而不是括号嵌套。
		tip.text = "挑一个最终造物 · 这一大轮定了就不能改"
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
			## ★高 40 → 44: 移动端触摸目标下限(`ShopScene.MIN_TOUCH_H`)。
			##   4px 从上面两段的行距里省出来(32→30 / 26→24), 面板总高一点没变。
			b.size = Vector2(bw, 44)
			## ★用 bind 传 key —— 循环变量在 lambda 里会被最后一轮覆盖(经典坑)
			b.pressed.connect(_pick.bind(str(f["key"])))
			## ★★这四个按钮一直是 **Godot 默认皮**(圆角纯灰) —— 全屏 UI 一致性门禁
			##   的「没有还用默认皮的按钮」是全局断言, 但它只在 `final_ready` 时才建,
			##   门禁跑的是全新档 ⇒ **从来没被量到过**(memory `fb-gate-subject-never-constructed`)。
			##   走宿主的 `_skin_button` = 与商店其余按钮同一张深海金属签牌。
			host._skin_button(b)
			parent.add_child(b)
		h += 50.0
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
