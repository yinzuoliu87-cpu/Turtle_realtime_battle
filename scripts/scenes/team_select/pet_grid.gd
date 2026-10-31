class_name PetGrid
extends RefCounted
## 选龟页·龟卡片网格(填充/建卡·稀有度badge和立绘helper留主场景共享)
## ★2026-10-30 选龟页重做(用户「你这还是一股浏览器的感觉啊」): 龟池卡 = 背包同款小卡(UnitCardArt) ——
##   全身立绘 + 金饰框 + 稀有度色名字横幅 + 左上稀有度字母(与页签同字同色); 已上阵 = 立绘压暗 +「已上阵」;
##   右栏正在看的那一只 = 卡外金边。原来是暖铜九宫格 + 半透明圆角稀有度小签 + 被动小圆标(一张 CSS 卡片)。
## 类内名不变;外部名加 battle.

const _TapSlop := preload("res://scripts/util/tap_slop.gd")

var host
## 上次建网格时的筛选(""= 还没建过): 第一次建 / 换了页签 ⇒ 卡片一排排浮上来(2026-10-30 动效)
var _last_filter := ""

func _init(b) -> void:
	host = b

func _refresh_grid() -> void:
	for c in host._grid_flow.get_children():
		c.queue_free()
	## 锁定后不显示龟池(用户 10-30「锁定后的就不用去显示其他龟和稀有度了啊」)⇒ 不建卡
	if host._roster_locked:
		return
	# active 稀有度按钮 (PoC .pg-rarity-btn.active = 金渐变填充 + 深字)
	for rb in host._rarity_btns:
		var b: Button = rb["btn"]
		host._style_rarity_btn(b, rb["key"] == host.filter_rarity)

	var pets: Array = DataRegistry.launch_pets.duplicate()
	# ★教学模式: 只显 3 只教学龟(用户2026-07-23"选龟时下面只显示教学用的三只龟"), 免得新手又懵。
	var _td = host.get_node_or_null("/root/TutorialDirector")
	if _td != null and _td.is_active():
		var keep: Array = _td.FIXED_TEAM
		var filt: Array = []
		for p2 in pets:
			if str(p2.get("id", "")) in keep:
				filt.append(p2)
		if not filt.is_empty():
			pets = filt
	# rarity filter
	if host.filter_rarity != "all":
		var filtered: Array = []
		for p in pets:
			if p.get("rarity", "") == host.filter_rarity:
				filtered.append(p)
		pets = filtered
	# sort by rarity (PoC default)
	pets.sort_custom(func(a, b): return host.RARITY_ORDER.find(a.get("rarity", "C")) < host.RARITY_ORDER.find(b.get("rarity", "C")))

	var sheen_k := 0
	for pet in pets:
		var c := _make_pet_card(pet)
		host._grid_flow.add_child(c)
		## SSS / SS 卡隔几秒扫过一道光(像抽卡游戏里的闪卡), 各张错开
		if str(pet.get("rarity", "")) in ["SSS", "SS"]:
			var b: float = UnitCardArt.border_for(c.custom_minimum_size)
			TsMotion.sheen(c, Rect2(b, b, c.custom_minimum_size.x - 2.0 * b, c.custom_minimum_size.y - 2.0 * b), 0.4 + 0.9 * float(sheen_k % 3))
			sheen_k += 1
	## 第一次建 / 换了页签 ⇒ 卡片一排排浮上来; 换页签时下划线从中间长出来
	if host.get("_motion") != null and host.filter_rarity != _last_filter:
		host._motion.cascade_roster(0.0)
		if _last_filter != "":
			for rb in host._rarity_btns:
				if rb["key"] == host.filter_rarity:
					var ul := (rb["btn"] as Node).get_node_or_null("Underline") as Control
					if ul != null:
						ul.pivot_offset = ul.size * 0.5
						ul.scale = Vector2(0.0, 1.0)
						ul.create_tween().tween_property(ul, "scale", Vector2.ONE, UIPalette.T_BASE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_last_filter = host.filter_rarity
	# 锁定态: 候选池灰显(去强调) — 表明本大轮不能改阵容; 卡片仍可点=查看详情/调技能, 只是不入队.
	host._grid_flow.modulate = Color(1, 1, 1, 0.55) if host._roster_locked else Color(1, 1, 1, 1)


func _make_pet_card(pet: Dictionary) -> Control:
	var pid: String = pet["id"]
	var rarity: String = pet.get("rarity", "C")
	var rcolor: Color = host.RARITY_COLOR.get(rarity, Color.WHITE)
	var selected = pid in host.team
	var focused: bool = pid == host.detail_pet_id

	var card = Control.new()
	card.set_meta("pet_id", pid)   # 教程手势指针找「第一只没上阵的龟」用(TeamSelectScene._tutorial_anchor)
	var sz := Vector2(host._grid_card_w, host._grid_card_h)
	card.custom_minimum_size = sz
	card.size = sz
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# ★手机端滑动(用户2026-07-22「选龟页面也是」):
	#   Control 默认 MOUSE_FILTER_STOP → GUI 事件不冒泡到外层 ScrollContainer, 龟池在触屏上滑不动。
	#   而网格的滚动条设成 SHOW_NEVER(注释还写着"滚动仍启用(手机拖)") → 手机上【完全没有滚动手段】。
	#   解法照抄项目已实机验证的模板 InventoryScene.gd:651: PASS + 按下/抬起位移阈值判点选。
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	## 松手且手指没挪出 16px 才算点选, 否则那是在滑列表。
	## ★2026-10-31 位移改按画布全局坐标量(TapSlop): 原来量卡片自己的局部坐标 —— 卡片跟着手指一起滚,
	##   手机上手指按在卡上往上滑 160px, 松手时相对卡片只挪了 15.7px ⇒ 这只龟被点进了阵容(verify_scroll_touch_sweep 实测)。
	var tap := _TapSlop.new(16.0)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if tap.is_tap(card, ev):
			host._set_detail_pet(pid)
			host._on_pick_pet(pid))
	# 拖放: 卡片可拖入编队槽 (1:1 PoC .pet-card draggable=true)
	# ★手机上必须关掉: Godot 原生 DnD 一旦启动就吃掉手指移动, 滚动永远抢不过它。
	#   触屏改走"点卡片(上面的 _on_pick_pet) → 点槽位"两步。
	## ★跟手那张换成统一的 DragLift(2026-10-30): host._card_drag 照旧判能不能拖、给拖动数据(它在积分赛逐字节守卫里, 一字不动),
	##   它设的 56px 小头像随即被这里的整张卡替掉(引擎设第二张预览时先删第一张, viewport.cpp _gui_set_drag_preview)。
	if not SafeArea.is_mobile():
		card.set_drag_forwarding(func(at: Vector2) -> Variant:
			var d = host._card_drag(at, card, pid)
			if d != null:
				card.set_drag_preview(DragLift.make(card, null, at / card.size, true))
			return d, Callable(), Callable())

	## 卡面(背包同款小卡; 小卡没有装备托条 ⇒ 横幅压低到下沿上方): 窗口底 → 立绘 → (已上阵压暗) → 框 → 横幅 → 稀有度字母
	var kx: float = sz.x / UnitCardArt.NATIVE.x
	var ky: float = sz.y / UnitCardArt.NATIVE.y
	var b: float = UnitCardArt.border_for(sz)
	var bn := Rect2(9.0 * kx, 168.0 * ky, sz.x - 18.0 * kx, 44.0 * ky)
	var pw := Rect2(b, b, sz.x - 2.0 * b, sz.y - 2.0 * b)
	card.add_child(UnitCardArt.window(sz, b))
	## 待机动画: 平时停在第 0 帧, 悬停才动(28 张一起动太花; 下面 hover 里 play / pause)
	var por: Control = UnitCardArt.portrait_anim(pid, pw, bn.position.y + 10.0 * ky, false)
	if por != null:
		card.add_child(por)
	var idle_tw: Tween = null
	if por != null and por.get_node_or_null("Body") != null and (por.get_node("Body") as Node).has_meta("idle_tw"):
		idle_tw = (por.get_node("Body") as Node).get_meta("idle_tw")
	if selected:
		var dim := ColorRect.new()
		dim.name = "InTeamDim"
		dim.color = Color(0.03, 0.02, 0.01, 0.55)
		dim.position = pw.position; dim.size = Vector2(pw.size.x, bn.position.y - pw.position.y)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(dim)
	var fr: Control = UnitCardArt.frame(sz)
	card.add_child(fr)
	card.add_child(UnitCardArt.banner(str(pet.get("name", "?")), rcolor, bn, maxi(13, int(roundf(bn.size.y * 0.6)))))
	## 稀有度字母: 左上(窗口里), 与页签同一个字同一个色 —— 看页签就知道这张算哪一档
	var rt := Label.new()
	rt.name = "RarityTag"
	rt.text = rarity
	rt.add_theme_font_size_override("font_size", maxi(12, int(roundf(sz.y * 0.11))))
	rt.add_theme_color_override("font_color", rcolor)
	rt.add_theme_color_override("font_outline_color", Color("#0d0805"))
	rt.add_theme_constant_override("outline_size", 5)
	## 落在窗口里面、不压框的边带(第一版贴着边带放, verify_ui_consistency 量到越进边带 6px)
	rt.position = Vector2(b + 10.0, b + 9.0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rt)
	## 等级: 右上(窗口里), 实战等级(★10-11: 原读 get_pet_level, 真玩家恒为 1)
	var lv := Label.new()
	lv.name = "Level"
	lv.text = "Lv.%d" % GameState.battle_level_for(pid)
	lv.add_theme_font_size_override("font_size", maxi(12, int(roundf(sz.y * 0.1))))
	lv.add_theme_color_override("font_color", Color("#ffd86b"))
	lv.add_theme_color_override("font_outline_color", Color("#0d0805"))
	lv.add_theme_constant_override("outline_size", 5)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.position = Vector2(b + 10.0, b + 9.0)
	lv.size = Vector2(sz.x - 2.0 * b - 20.0, float(maxi(12, int(roundf(sz.y * 0.1)))) * 1.5)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(lv)
	if selected:
		var tag := Label.new()
		tag.name = "InTeamTag"
		tag.text = "已上阵"
		tag.add_theme_font_size_override("font_size", maxi(13, int(roundf(sz.y * 0.12))))
		tag.add_theme_color_override("font_color", Color("#ffd86b"))
		tag.add_theme_color_override("font_outline_color", Color("#1a0e05"))
		tag.add_theme_constant_override("outline_size", 5)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.position = pw.position; tag.size = Vector2(pw.size.x, bn.position.y - pw.position.y)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tag)
	## 右栏正在看的这一只: 卡外一圈金边
	if focused:
		TsMotion.breathe(UnitCardArt.ring(card, sz, Color("#ffd86b"), 3.0))

	# hover: 框提亮 + 往上抬一点(1:1 PoC .pet-card:hover translateY(-2)) + 龟动起来
	card.mouse_entered.connect(func() -> void:
		if not is_instance_valid(card): return
		if card.get_meta("hovered", false): return
		card.set_meta("hovered", true)
		card.set_meta("rest_y", card.position.y)
		fr.modulate = Color(1.3, 1.22, 1.05)
		if idle_tw != null and idle_tw.is_valid():
			idle_tw.play()
		var tw = card.create_tween()
		tw.tween_property(card, "position:y", card.position.y - 2.0 * host._s(), 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))
	card.mouse_exited.connect(func() -> void:
		if not is_instance_valid(card): return
		if not card.get_meta("hovered", false): return
		card.set_meta("hovered", false)
		fr.modulate = Color.WHITE
		if idle_tw != null and idle_tw.is_valid():
			idle_tw.pause()
		var rest_y: float = card.get_meta("rest_y", card.position.y)
		var tw = card.create_tween()
		tw.tween_property(card, "position:y", rest_y, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT))

	return card


## 右栏换了一只看 ⇒ 金边挪到那张卡上(只挪边, 不重建整个网格)。
func mark_focus() -> void:
	if host._grid_flow == null or not is_instance_valid(host._grid_flow):
		return
	for card in host._grid_flow.get_children():
		if not (card is Control) or (card as Node).is_queued_for_deletion():
			continue
		for r in (card as Node).get_children():
			if r.name == "Ring":
				r.free()
		if str((card as Control).get_meta("pet_id", "")) == host.detail_pet_id:
			TsMotion.breathe(UnitCardArt.ring(card, (card as Control).size, Color("#ffd86b"), 3.0))


## 给 TextureRect 装龟的全身 idle 动画 (1:1 PoC buildPetImgHTML: pet.img 全身 sheet + sprite{} 帧).
##   有 sprite{frameW} → AtlasTexture 逐帧循环(同战斗 makeView 的 fps 公式); 无 sprite{} → 静态 body PNG;
##   img 缺 → avatars 头像回退。PoC 卡片/立绘是会 idle 跳动的全身龟, 非静态头像。
