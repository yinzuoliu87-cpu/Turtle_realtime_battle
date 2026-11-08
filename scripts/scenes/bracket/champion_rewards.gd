class_name ChampionRewards
extends CanvasLayer
## champion_rewards.gd —— 奖励一件一页(G11): 先出物件, 再滚数字, 深海币最后飞进顶栏才算入账。
## 依据 学到的.md C-4(Clash / Golf Clash / 皇室战争: 一件一页、先物件后数字、飞进顶栏)、3-11(每项停一拍)、
##   研究笔记 §6(页码点 + 每页一个主按钮, 动画播完才给按钮; 之前点屏只跳动画)。
## ★这是**演出**, 不是发奖: 深海币每轮打完当场已入账(`GameState.finals_settle_sealed`), 头衔由 `sync_titles` 记。
##   这一层只把「拿到了什么」一件一件演给玩家看。
## ★版式(主会话 10-31 逐帧审改): 居中一张大奖励卡(冠军卡框)—— 物件大、名字大、说明一行; 背后整屏不透明压暗
##   (竞技场背景 + 暗幕, 看不出后面那一屏的字); 「已获得 / 已入账」章砸下去有冲击(2.6 倍回弹 + 尘 + 卡片一震 + 一下亮)。
##
## 用法: var r := ChampionRewards.open(host, {"pages": ChampionData.reward_pages(titles),
##            "coin_target": 顶栏深海币图标的屏幕坐标(可选), "coin_from": 入账前余额(可选)})
##        r.coins_landed.connect(func(n): 顶栏数字 += n)   # 给了 coin_target 时由宿主自己涨数
##        r.finished.connect(...)                          # 最后一页点「完成」(层已自删)
## 没给 coin_target ⇒ 飞进本层右上角自画的深海币小条(数字从 coin_from 滚到新值)。

signal page_shown(index: int)
signal coins_landed(amount: int)
signal finished

const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")
const FX := preload("res://scripts/scenes/bracket/champion_fx.gd")
const COIN_FLY := preload("res://scripts/util/coin_fly.gd")   # 主菜单 / 商店的入账动画: 拆份规则与「看过的余额」都跟它同一份

const LAYER := 97
const ANIM_TITLE := 1.8
const ANIM_COINS := 2.6
const STAMP_IN := 0.55         # 章在这一页动画结束前多久砸下
const STAMP_DUR := 0.2          # 从 2.6 倍砸到 1 倍(先慢后快, 砸实那一下最狠)

var data: Dictionary = {}
var auto_advance := true
var page := -1
var t := 0.0
var skips := 0
var landed := 0                # 已飞到的深海币(按份额累计)
var vp := Vector2(1280, 720)
var c := Vector2(640, 360)
var card_rect := Rect2()       # 奖励卡在屏幕上的矩形
var _root: Control
var _box: Control              # 卡片(框 + 光 + 这一页的内容), 盖章时整张一震
var _fx                        # 卡外: 尘 / 彩带
var _fx_in                     # 卡内: 物件背后的光(裁在卡里)
var _page_root: Control
var _fly_root: Control
var _n := {}
var _chip_val: Label
var _btn: Button
var _flash: ColorRect
var _flash_k := 0.0
var _done := false


static func create(d: Dictionary) -> ChampionRewards:
	var s := ChampionRewards.new()
	s.data = d
	return s


static func open(host: Node, d: Dictionary) -> ChampionRewards:
	var s := create(d)
	host.add_child(s)
	return s


func pages() -> Array:
	var a = data.get("pages", [])
	return a if a is Array else []


func anim_of(i: int) -> float:
	if i < 0 or i >= pages().size():
		return 0.0
	return ANIM_COINS if str((pages()[i] as Dictionary).get("kind", "")) == "coins" else ANIM_TITLE


func node(nm: String) -> Node:
	return _root.find_child(nm, true, false) if _root != null else null


func coin_target() -> Vector2:
	if data.get("coin_target", null) is Vector2:
		return data["coin_target"]
	return Vector2(vp.x - 150.0, 46.0)


func _ready() -> void:
	layer = LAYER
	vp = data["vp"] if data.get("vp", null) is Vector2 else get_viewport().get_visible_rect().size   # 门禁量两种比例时直接给
	c = vp * 0.5
	_root = Control.new()
	_root.name = "RewardsRoot"
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)
	## 整屏不透明: 竞技场背景(铺满)+ 暗幕 —— 后面那一屏一个字都透不出来
	var bg := UI.tex_rect(UI.TEX_BG, vp, "RewardsBg")
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.position = Vector2.ZERO
	bg.modulate = Color(0.42, 0.38, 0.44, 1.0)
	_root.add_child(bg)
	UI.box(_root, Rect2(Vector2.ZERO, vp), Color(0.02, 0.01, 0.03, 0.6), "Dim")
	_fx = FX.new()
	_fx.size = vp
	_root.add_child(_fx)
	## 奖励卡
	var cw := minf(vp.x - 200.0, 760.0)
	var chh := minf(vp.y - 190.0, 500.0)
	card_rect = Rect2(c.x - cw * 0.5, c.y - 36.0 - chh * 0.5, cw, chh)
	_box = Control.new()
	_box.name = "RewardCard"
	_box.position = card_rect.position
	_box.size = card_rect.size
	_box.pivot_offset = card_rect.size * 0.5
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_box)
	UI.box(_box, Rect2(10, 10, cw - 20, chh - 20), Color("#17111a"), "CardBody")
	var clip := Control.new()
	clip.name = "CardGlow"
	clip.position = Vector2(14, 14)
	clip.size = Vector2(cw - 28, chh - 28)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(clip)
	_fx_in = FX.new()
	_fx_in.size = clip.size
	clip.add_child(_fx_in)
	var ft := UI.tex(UI.TEX_FRAME)
	if ft != null:
		var np := NinePatchRect.new()
		np.name = "CardFrame"
		np.texture = ft
		np.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var m := int(ft.get_width() * 0.28)
		np.patch_margin_left = m
		np.patch_margin_right = m
		np.patch_margin_top = m
		np.patch_margin_bottom = m
		np.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		np.size = Vector2(cw, chh)
		np.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box.add_child(np)
	_page_root = Control.new()
	_page_root.name = "Page"
	_page_root.size = card_rect.size
	_page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_page_root)
	_fly_root = Control.new()
	_fly_root.name = "Fly"
	_fly_root.size = vp
	_fly_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fly_root)
	if not (data.get("coin_target", null) is Vector2) and _has_coins():
		_build_chip()
	_btn = UI.button("下一个", 300, "BtnNext", true)
	_btn.position = Vector2(c.x - 150, minf(card_rect.end.y + 22.0, vp.y - UI.BTN_H - 12.0))
	_btn.pressed.connect(_on_next)
	_root.add_child(_btn)
	_flash = UI.box(_root, Rect2(Vector2.ZERO, vp), Color(1, 1, 1, 0), "WhiteFlash")
	_show_page(0)


func _has_coins() -> bool:
	for p in pages():
		if str((p as Dictionary).get("kind", "")) == "coins":
			return true
	return false


func _build_chip() -> void:
	var tg := coin_target()
	var pl := UI.plate(_root, Rect2(tg.x - 34, tg.y - 26, 196, 52), UI.BRONZE, UI.PLATE, "CoinChip")
	UI.tex_at(pl, UI.TEX_COIN, Vector2(34, 26), Vector2(32, 32), "CoinChipIcon")
	_chip_val = UI.label_in(pl, Rect2(62, 0, 124, 52), "", 28, UI.TXT, false, "CoinChipValue", HORIZONTAL_ALIGNMENT_LEFT)
	_update_chip()


func _update_chip() -> void:
	if _chip_val == null:
		return
	var base := int(data.get("coin_from", -1))
	_chip_val.text = str(base + landed) if base >= 0 else ("+%d" % landed if landed > 0 else "0")


func _show_page(i: int) -> void:
	page = i
	t = 0.0
	_n = {}
	for holder in [_page_root, _fly_root]:
		for ch in (holder as Control).get_children():
			(holder as Control).remove_child(ch)     # ★先摘下再释放: 同名新节点进来时旧的还在树上会被引擎改名
			ch.queue_free()
	_btn.visible = false
	_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_btn.text = "完成" if i >= pages().size() - 1 else "下一个"
	var p: Dictionary = pages()[i] if i < pages().size() else {}
	var n := pages().size()
	var w := card_rect.size.x
	UI.label_in(_page_root, Rect2(0, 30, w, 28), "奖励 %d / %d" % [i + 1, n], 22, UI.TXT_DIM, false, "PageCount")
	for k in range(n):
		UI.box(_page_root, Rect2(w * 0.5 - (n * 22) * 0.5 + k * 22 + 4, 62, 12, 12), UI.GOLD if k <= i else Color(UI.GOLD, 0.25),
			"PageDot%d" % k)
	if str(p.get("kind", "")) == "coins":
		_build_coins(p)
	else:
		_build_title(p)
	_fx_in.rays_center = (_n["obj_c"] as Vector2) - Vector2(14, 14)
	_fx_in.rays_radius = card_rect.size.x * 0.75
	_fx_in.rays_alpha = 0.0
	_apply()
	page_shown.emit(i)


## 卡内的竖向排布(卡高 500 时): 标题 86~140 · 物件中心 ≈ 0.45 高 · 说明 0.72 高。
func _build_title(p: Dictionary) -> void:
	var w := card_rect.size.x
	var h := card_rect.size.y
	UI.label_in(_page_root, Rect2(0, 84, w, 56), "获得头衔", 48, UI.GOLD, true, "PageTitle")
	_n["obj_c"] = Vector2(w * 0.5, h * 0.46)
	_n["obj"] = UI.ribbon(_page_root, _n["obj_c"], 480, str(p.get("name", "")), 60, "gold", "TitleRibbon")
	_n["obj_y"] = (_n["obj"] as Control).position.y
	_n["sub"] = UI.label_in(_page_root, Rect2(0, h * 0.70, w, 40), str(p.get("sub", "")), 28, UI.TXT, false, "PageSub")
	_n["stamp"] = _stamp("已获得", (_n["obj_c"] as Vector2) + Vector2(200, -64))


func _build_coins(p: Dictionary) -> void:
	var w := card_rect.size.x
	var h := card_rect.size.y
	UI.label_in(_page_root, Rect2(0, 84, w, 56), "深海币入账", 48, UI.GOLD, true, "PageTitle")
	_n["obj_c"] = Vector2(w * 0.5, h * 0.42)
	_n["obj"] = UI.tex_at(_page_root, UI.TEX_COIN, _n["obj_c"], Vector2(128, 128), "CoinIcon")
	_n["num"] = UI.label_in(_page_root, Rect2(0, h * 0.56, w, 76), "+0", 72, UI.GOLD, true, "CoinAmount")
	_n["sub"] = UI.label_in(_page_root, Rect2(0, h * 0.74, w, 40), str(p.get("sub", "")), 28, UI.TXT, false, "PageSub")
	_n["stamp"] = _stamp("已入账", (_n["obj_c"] as Vector2) + Vector2(170, -40))
	var flyers: Array = []
	var portions: Array = COIN_FLY.split(int(p.get("amount", 0)))
	_n["portions"] = portions
	var src := card_rect.position + (_n["obj_c"] as Vector2)
	for k in range(portions.size()):
		var f := UI.tex_at(_fly_root, UI.TEX_COIN, src, Vector2(32, 32), "FlyCoin%d" % k)
		f.visible = false
		flyers.append(f)
	_n["fly"] = flyers
	_n["src"] = src
	_n["amount"] = int(p.get("amount", 0))


func _stamp(text: String, at: Vector2) -> Control:
	var st := Control.new()
	st.name = "Stamp"
	st.size = Vector2(200, 76)
	st.pivot_offset = st.size * 0.5
	st.position = at - st.size * 0.5
	st.rotation = -0.18
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_root.add_child(st)
	UI.box(st, Rect2(0, 0, 200, 76), Color("#e2484e"))
	UI.box(st, Rect2(5, 5, 190, 66), Color("#5e1c20"))
	UI.box(st, Rect2(9, 9, 182, 58), Color("#e2484e"))
	UI.box(st, Rect2(12, 12, 176, 52), Color("#6e2026"))
	UI.label_in(st, Rect2(0, 0, 200, 76), text, 36, Color("#ffe3e3"), true, "StampText")
	st.modulate.a = 0.0
	return st


func _process(dt: float) -> void:
	if auto_advance:
		advance(minf(dt, 0.1))


func advance(dt: float) -> void:
	if _done or page < 0:
		return
	t += dt
	_fx.step(dt)
	_fx_in.step(dt)
	_apply()


## 点屏: 这一页直接到终态(币全部入账、章盖好、按钮出现)。
func skip_beat() -> void:
	if _done or page < 0:
		return
	if t < anim_of(page):
		skips += 1
		t = anim_of(page)
		_apply()


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (ev as InputEventMouseButton).pressed:
		skip_beat()
		_root.accept_event()


func _on_next() -> void:
	if page >= pages().size() - 1:
		_done = true
		finished.emit()
		queue_free()
		return
	_show_page(page + 1)


func _apply() -> void:
	var p: Dictionary = pages()[page] if page < pages().size() else {}
	var a := anim_of(page)
	## 卡片入场(每页都从 0.9 倍弹到 1 倍)
	var kc := UI.seg(t, 0.0, 0.3)
	_page_root.modulate.a = UI.seg(t, 0.0, 0.18)
	_flash_k = 0.0
	if str(p.get("kind", "")) == "coins":
		_apply_coins(t)
	else:
		_apply_title(t)
	_fx_in.rays_alpha = 0.42 * UI.seg(t, 0.15, 0.6)
	## 盖章: 2.6 倍砸下、回弹落定 → 尘 + 卡片一震 + 一下亮
	var ts := a - STAMP_IN
	var ks := UI.seg(t, ts, ts + STAMP_DUR)
	var st: Control = _n.get("stamp", null)
	var shake := 0.0
	if st != null:
		st.modulate.a = UI.seg(t, ts, ts + 0.05)
		var after_hit := t - (ts + STAMP_DUR)
		var rebound := 0.14 * sin(PI * UI.seg(after_hit, 0.0, 0.16)) if after_hit >= 0.0 else 0.0
		st.scale = Vector2.ONE * (lerpf(2.6, 1.0, UI.ease_in(ks)) - rebound)
		if t >= ts + STAMP_DUR and not _n.has("stamp_hit"):
			_n["stamp_hit"] = true
			_fx.dust(card_rect.position + st.position + Vector2(st.size.x * 0.5, st.size.y), 26, 150.0)
		var after := t - (ts + STAMP_DUR)
		if after >= 0.0 and after < 0.14:
			shake = 1.0 - after / 0.14
			_flash_k = maxf(_flash_k, 0.22 * shake)
	_box.scale = Vector2.ONE * lerpf(0.9, 1.0, UI.ease_back(kc))
	_box.position = card_rect.position + Vector2(sin(t * 90.0) * 6.0 * shake, cos(t * 70.0) * 3.0 * shake)
	_flash.color.a = _flash_k
	if t >= a and not _btn.visible:
		_btn.visible = true
		_btn.mouse_filter = Control.MOUSE_FILTER_STOP


## 头衔缎带从卡顶落下(回弹)+ 扬尘彩带 + 一下亮 → 说明一行。
func _apply_title(tt: float) -> void:
	var obj: Control = _n["obj"]
	var k := UI.seg(tt, 0.05, 0.5)
	obj.position.y = lerpf(-obj.size.y, float(_n["obj_y"]), UI.ease_back(k))
	obj.modulate.a = UI.seg(tt, 0.05, 0.15)
	if tt >= 0.5 and not _n.has("dust"):
		_n["dust"] = true
		var oc := card_rect.position + (_n["obj_c"] as Vector2)
		_fx.dust(oc + Vector2(0, obj.size.y * 0.45), 24, 280.0)
		_fx.burst(oc, 36, 420.0)
	_flash_k = maxf(_flash_k, 0.35 * (1.0 - UI.seg(tt, 0.5, 0.62)) if tt >= 0.5 else 0.0)
	(_n["sub"] as Control).modulate.a = UI.seg(tt, 0.6, 0.9)


## 币先弹出来 → 数字滚到 +N → 一枚枚飞进顶栏, 到一枚涨一次。
func _apply_coins(tt: float) -> void:
	var obj: Control = _n["obj"]
	var k := UI.seg(tt, 0.0, 0.35)
	var bob := sin(tt * 3.0) * 4.0 if k >= 1.0 else 0.0
	obj.scale = Vector2.ONE * lerpf(0.3, 1.0, UI.ease_back(k))
	obj.position.y = roundf((_n["obj_c"] as Vector2).y - obj.size.y * 0.5 + bob)
	obj.modulate.a = UI.seg(tt, 0.0, 0.12)
	var amount: int = _n["amount"]
	var kr := UI.seg(tt, 0.35, 1.15)
	(_n["num"] as Label).text = "+%d" % int(round(float(amount) * UI.ease_out(kr)))
	(_n["sub"] as Control).modulate.a = UI.seg(tt, 0.8, 1.1)
	var flyers: Array = _n["fly"]
	var src: Vector2 = _n["src"]
	var dst := coin_target()
	var arrived := 0
	for i in range(flyers.size()):
		var f: Control = flyers[i]
		var t0 := 1.2 + 0.07 * float(i)
		var kf := UI.seg(tt, t0, t0 + 0.55)
		f.visible = kf > 0.0 and kf < 1.0
		var e := UI.ease_in(kf)
		var p := src.lerp(dst, e) + Vector2(0, -180.0 * sin(PI * e))
		f.position = p - f.size * 0.5
		f.scale = Vector2.ONE * lerpf(1.0, 0.7, e)
		if kf >= 1.0:
			arrived += 1
	var new_landed := 0
	for i in range(arrived):
		new_landed += int(_n["portions"][i])
	if new_landed != landed:
		landed = new_landed
		_update_chip()
	if arrived == flyers.size() and not flyers.is_empty() and not _n.has("land_emitted"):
		_n["land_emitted"] = true
		## ★演过一遍入账 ⇒ 记成「玩家看过的余额」, 回主菜单 / 进商店时 CoinFly 不再把这一笔重飞一遍。
		if int(data.get("coin_from", -1)) >= 0:
			COIN_FLY.seen = maxi(COIN_FLY.seen, int(data["coin_from"]) + amount)
		coins_landed.emit(amount)
