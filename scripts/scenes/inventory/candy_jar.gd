class_name InvCandyJar
extends RefCounted
## 背包·糖果罐(打碎领奖)
## 类内名不变;外部名加 battle.

var host

func _init(b) -> void:
	host = b

## ★旧的「右上角独立小面板」已删(2026-08-14)。
##   用户:「点击装备, 下面把出售和什么按钮换成打碎就好了啊」——
##   糖果罐现在是背包格子里的一张卡, 选中后走底部同一条操作栏(InventoryScene._build_jar_op_bar)。
##   这个函数删掉而不是留着不调 —— GDScript 鸭子类型, 留着的死函数照样能被门禁"断言存在"保护住。


func _on_break_jar() -> void:
	var r: Dictionary = GameState.break_candy_jar()
	if r.is_empty():
		return
	_show_jar_reward(r)


func _show_jar_reward(r: Dictionary) -> void:
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(dim)

	var box = Panel.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color("#1c2836"); sb.border_color = Color("#ffd93d")
	sb.set_border_width_all(3); sb.set_corner_radius_all(12)
	## ★2026-09-28 换九宫格金属框(同 `synergy_panel._show_synergy_popup`)。
	##   本屏别的弹框 2026-08-18 都换过了, 这个和羁绊详情框是漏下的两个圆角网页盒。
	##   静止态的运行时探针照不到它们 —— 弹框只在点开之后才建。
	##   `StyleBoxFlat` 留着当 fallback: 贴图缺失时 `UISkin.nine` 原样返回它。
	box.add_theme_stylebox_override("panel", UISkin.nine("panel-frame.png", 20, sb))
	box.position = Vector2(host.W / 2.0 - 260, host.H / 2.0 - 150); box.size = Vector2(520, 300)
	dim.add_child(box)

	var ttl = Label.new()
	## ★不写「(档3)」这种括号计数 —— 括号里塞个数字是策划表口气。
	##   而且 `verify_inventory_layout` ㉖ 明令界面文本里不许出现「档1/档2/档3/档4」,
	##   它只是因为这个弹框不在静止态的屏上才没被数到。改成「第 N 档」两不相犯。
	## ★2026-09-28 去掉句首的 🍬 —— 纯装饰(「糖果罐」三个字就在后面),
	##   而 emoji 的字形来自 NotoEmoji, 与这一屏的像素笔触是两套画法。
	ttl.text = "糖果罐 · 第 %d 档奖励" % int(r.get("tier", 1))
	ttl.add_theme_font_size_override("font_size", 22)
	ttl.add_theme_color_override("font_color", Color("#ffd93d"))
	ttl.position = Vector2(0, 20); ttl.size = Vector2(520, 36)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(ttl)

	## ★「💠」不再拿字符当深海币 —— 这一屏的顶栏 2026-09 就换成了 `ic-deepsea.png`,
	##   `verify_inventory_layout` ④b 专门守着"界面上没有留下拿字符当币的旧写法"
	##   (它扫的是静止态的屏, 所以这个弹框里的漏网之鱼它数不到)。图标画在文字前面。
	var lines: Array = ["深海币 +%d" % int(r.get("coins", 0))]
	var eid = str(r.get("equip", ""))
	if eid != "":
		var edef: Dictionary = DataRegistry.phase2_equipment_by_id.get(eid, {})
		lines.append("获得 %s %s" % [str(edef.get("name", eid)), "★".repeat(int(r.get("star", 1)))])
	if bool(r.get("leveler", false)):
		## ★原文是"🔼 临时等级器 ×1 → 进背包 (点它再点一只龟/小将, 本大轮 +1 级)":
		##   箭头 + 括号注解 = 说明书腔, 而且 35 字在 440px / 18 号字下要排**两行**,
		##   却挤在 30px 高的 Label 里 ⇒ 第二行一直被静默吃掉(所以下面把行高改成 48)。
		lines.append("获得 临时等级器 ×1")

	const Y0 := 80.0
	var y = Y0
	for i in range(lines.size()):
		var l = Label.new()
		l.text = str(lines[i])
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color("#e8f2ff"))
		## 行高 48 = 18 号字排两行的高度(原来 30 = 一行多一点, 换行就静默吃字)。
		## 三行走完 80 + 2×50 + 48 = 228 < 收下键的 234, 仍在 300 高的框里。
		## ★第一行让出 32px 给深海币图标; 其余行顶到 40。
		var lx: float = 72.0 if i == 0 else 40.0
		l.position = Vector2(lx, y); l.size = Vector2(480.0 - lx, 48)
		## ★★2026-09-28 WORD_SMART → ARBITRARY。中文长句**没有空格可断**, WORD_SMART
		##   在这一行上等于不换行 ⇒ 「临时等级器 ×1 收进背包 · 点它再点一只龟或小将,」
		##   那句 **越出弹框内容区 23px**(门禁实测: 框 520×300·边带 13, 该行 size=(440,48))。
		##   同一处理在设置屏的中文段落上已经做过一次 —— 中文一律 ARBITRARY。
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		box.add_child(l)
		y += 50.0

	## 深海币那一行的图标 —— 与顶栏/商店同一张 `ic-deepsea.png`(图标是用户点名允许复用的那一类)。
	var ci = TextureRect.new()
	ci.texture = host.COIN_TEX
	ci.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ci.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ci.position = Vector2(40, Y0 - 2.0); ci.size = Vector2(26, 26)
	box.add_child(ci)

	var ok = Button.new()
	ok.text = "领取"
	ok.add_theme_font_size_override("font_size", 20)
	ok.position = Vector2(200, 234); ok.size = Vector2(120, 44)
	## ★套金属签牌皮 —— 不套就是 Godot 默认皮(圆角纯色)。必须在 size 之后调, 见 UISkin.button 注释。
	UISkin.button(ok, Color("#ffd93d"))
	ok.pressed.connect(func(): dim.queue_free(); host._rebuild())
	box.add_child(ok)


# 消耗品格子 (临时等级器): 不是装备 → 不查装备表/不显星/不参与3合1
