extends Node
## verify_inspect_card_hosts.gd — 说明小卡(inspect_card.gd)在商店 / 背包里: 小木斧那张不出屏幕、超长就卡内上下滑动(2026-10-27)。
##
## 由来: 小木斧 p2eq_096 的说明把四个形态 + 四个造物全列(用户 10-22 定, 内容不删), 局内宽 300 时卡高 1994。
##   局内那张改成「卡头不动、正文到本局在卡内滚动」, 门禁在 verify_replay_controls ⑧(回放场全部装备逐件开)。
##   同一张卡还被商店、背包复用(宿主实现 inspect_card_pos 自己摆位)⇒ 这里在两处各真点开一次小木斧, 两个比例。
## 判据:
##   ① 商店: 真点货架上的小木斧 ⇒ 说明卡整张在屏幕里; 正文在【一层】滚动框里(商店自己的 CardBodyScroll, 不许再套第二层),
##      内容总高 > 可见高、滚动条看得见; 滚轮滚得动; 点卡头不关卡
##   ② 背包: 点背包里那件 3 星小木斧 ⇒ 说明卡和卡底「卖出 / 详情」整张在屏幕里; 卡里若有滚动框, 内容总高 > 可见高
##   ③ 背包没有自己的封顶 ⇒ 一张自造的超长探针卡(40 行)也得收进屏幕、变成卡内滚动(inspect_card 按宿主给的卡顶算可用高度)
## ★走真入口: 商店真点货架格(Viewport.push_input), 背包走真处理函数 `_on_bench_click`。
##
## 跑法: bash godot-quiet.sh res://tests/verify_inspect_card_hosts.tscn --quit-after 500

const SHOP := preload("res://scenes/Shop.tscn")
const INV := preload("res://scenes/Inventory.tscn")
const AXE := "p2eq_096"
const KEYS := ["test_mode", "tutorial_active", "meta_deepsea_coins", "season_level", "season_xp", "season_total_battles",
	"meta_shop_locked", "meta_shop_offer", "meta_shop_battles", "persistent_bench", "persistent_equipped",
	"axe_exp_bar", "axe_exp_total", "axe_stage", "axe_final", "equip_pool", "season_leaders", "candy_jar_count"]
## ★= 实测条数。少一条就红 —— 协程半路报错时 _ready 照样往下走、照样打 ALL PASS。
const MIN_ASSERTS := 24

var _fail := 0
var _n := 0
var _bak := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _btn(p: Vector2, b: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.factor = 1.0
	e.position = p
	e.global_position = p
	get_viewport().push_input(e)


## 一次点按 + 等说明卡排完版(InspectCard 一帧; 商店 _refit_card 两帧、封顶再一帧; 宿主摆位时 inspect_card 再等 4 帧看放不放得下)。
func _click(p: Vector2) -> void:
	_btn(p, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	_btn(p, MOUSE_BUTTON_LEFT, false)
	await _frames(10)


func _dying(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


func _live(root: Node, nm: String) -> Control:
	if root == null:
		return null
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not _dying(c):
			return c
	return null


func _title(c: Control) -> String:
	var t = c.find_child("Title", true, false) if c != null else null
	return str(t.text) if t is Label else ""


## 卡里所有滚动框; 每个 [框, 内容总高, 可见高, 滚动条看得见]。
func _scrolls(c: Control) -> Array:
	var out: Array = []
	if c == null:
		return out
	for s in c.find_children("*", "ScrollContainer", true, false):
		var sc := s as ScrollContainer
		var ch: Control = sc.get_child(0) as Control if sc.get_child_count() > 0 else null
		var content: float = maxf(ch.size.y, ch.get_combined_minimum_size().y) if ch != null else 0.0
		out.append([sc, content, sc.size.y, sc.get_v_scroll_bar().is_visible_in_tree()])
	return out


func _seed() -> void:
	GameState.test_mode = true
	GameState.tutorial_active = false
	GameState.meta_deepsea_coins = 999
	GameState.season_level = 5
	GameState.season_xp = 0
	GameState.season_total_battles = 3
	GameState.meta_shop_locked = false
	GameState.persistent_bench = []
	GameState.persistent_equipped = {}
	GameState.axe_exp_bar = 0
	GameState.axe_exp_total = 0
	GameState.axe_stage = 0
	GameState.axe_final = ""
	GameState.equip_pool = {}
	GameState.season_leaders = ["basic", "stone", "ninja"]
	GameState.candy_jar_count = 0


func _ready() -> void:
	await get_tree().process_frame
	for k in KEYS:
		var v = GameState.get(k)
		_bak[k] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	print("=== 说明小卡在商店 / 背包: 小木斧不出屏、超长卡内滚动 ===")
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		get_tree().root.content_scale_size = Vector2i(1280, 720)
		get_tree().root.size = Vector2i(vp)
		await _frames(2)
		await _shop(vp)
		await _inventory(vp)
	for k in KEYS:
		GameState.set(k, _bak[k])
	print("")
	print("  (共 %d 条断言, 下限 %d)" % [_n, MIN_ASSERTS])
	if _fail == 0 and _n >= MIN_ASSERTS:
		print("ALL PASS — 说明小卡在商店 / 背包不出屏")
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if (_fail > 0 or _n < MIN_ASSERTS) else 0)


# ① ─────────────────────────────────────────────────────────────
func _shop(vp: Vector2) -> void:
	var tag := "%dx%d" % [int(vp.x), int(vp.y)]
	print("── ① 商店 %s ──" % tag)
	_seed()
	var offer: Array = []
	for _i in range(10):
		offer.append({"id": AXE})
	GameState.meta_shop_offer = offer
	GameState.meta_shop_battles = int(GameState.season_total_battles)
	var sc: Control = SHOP.instantiate()
	add_child(sc)
	sc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sc.position = Vector2.ZERO
	sc.size = vp
	await _frames(3)
	sc._rebuild()
	await _frames(4)
	var cell := _live(sc, "ShelfItem0")
	await _click(cell.get_global_rect().get_center() if cell != null else Vector2(-100, -100))
	var c := _live(sc, "InspectCard")
	var r: Rect2 = c.get_global_rect() if c != null else Rect2()
	_ok("① [%s] 分母: 真点货架第 0 格 ⇒ 小木斧的说明卡开了(「%s」)" % [tag, _title(c)], c != null and _title(c).contains("小木斧"))
	_ok("① ★[%s] 卡整张在屏幕里(卡 %s)" % [tag, str(r)], c != null and Rect2(Vector2.ZERO, vp).encloses(r))
	var ss := _scrolls(c)
	_ok("① ★[%s] 正文在一层滚动框里(不套第二层): 内容 %d > 可见 %d、滚动条看得见" % [tag,
		int(ss[0][1]) if ss.size() == 1 else -1, int(ss[0][2]) if ss.size() == 1 else -1],
		ss.size() == 1 and float(ss[0][1]) > float(ss[0][2]) + 0.5 and bool(ss[0][3]), "滚动框 %d 个" % ss.size())
	if c != null and ss.size() == 1:
		var s: ScrollContainer = ss[0][0]
		var p: Vector2 = s.get_global_rect().get_center()
		_btn(p, MOUSE_BUTTON_WHEEL_DOWN, true)
		_btn(p, MOUSE_BUTTON_WHEEL_DOWN, false)
		await _frames(2)
		_ok("① ★[%s] 滚轮在正文上往下滚得动(0 → %d), 卡还开着" % [tag, s.scroll_vertical],
			s.scroll_vertical > 0 and _live(sc, "InspectCard") == c)
		var t := c.find_child("Title", true, false) as Control
		await _click(t.get_global_rect().get_center() if t != null else r.position + Vector2(60, 20))
		_ok("① [%s] 点卡头不关卡" % tag, t != null and _live(sc, "InspectCard") == c)
	remove_child(sc)
	sc.free()
	await _frames(2)


# ② ③ ─────────────────────────────────────────────────────────────
func _inventory(vp: Vector2) -> void:
	var tag := "%dx%d" % [int(vp.x), int(vp.y)]
	print("── ② 背包 %s ──" % tag)
	_seed()
	GameState.persistent_bench = [{"id": AXE, "star": 3}]
	var inv = INV.instantiate()
	add_child(inv)
	await _frames(8)
	inv._on_bench_click(0)
	await _frames(10)
	var c := _live(inv, "ItemInspectCard")
	var r: Rect2 = c.get_global_rect() if c != null else Rect2()
	var screen := Rect2(Vector2.ZERO, vp)
	_ok("② [%s] 分母: 点背包里的 3 星小木斧 ⇒ 说明卡开了(「%s」, 高 %d)" % [tag, _title(c), int(r.size.y)],
		c != null and _title(c).contains("小木斧"))
	_ok("② ★[%s] 卡整张在屏幕里(卡 %s)" % [tag, str(r)], c != null and screen.encloses(r))
	var sell := _live(c, "SellBtn")
	var det := _live(c, inv.DETAIL_BTN_NAME)
	_ok("② [%s] 卡底「卖出 / 详情」都在屏幕里" % tag, sell != null and det != null
		and screen.encloses(sell.get_global_rect()) and screen.encloses(det.get_global_rect()))
	var ss := _scrolls(c)
	var idle := 0
	for s in ss:
		if float(s[1]) <= float(s[2]) + 0.5 or not bool(s[3]):
			idle += 1
	_ok("② [%s] 卡里有滚动框就是真要滚的(%d 个, 内容 ≤ 可见的 %d 个)" % [tag, ss.size(), idle], c != null and idle == 0)
	if sell != null:
		_ok("② [%s] 卡底按钮不在滚动框里(永远看得见)" % tag, ss.is_empty() or not (ss[0][0] as Node).is_ancestor_of(sell))
	## ③ 背包没有自己的封顶 ⇒ 超长卡靠 inspect_card 自己收: 按宿主给的卡顶算可用高度, 正文卡内滚动
	var lines := PackedStringArray()
	for k in range(40):
		lines.append("探针第 %d 行" % k)
	inv._insp.open("probe:tall", null, {"title": "探针长卡", "body": "\n".join(lines), "width": inv.ITEM_CARD_W, "min_px": inv.MIN_FONT_PX})
	await _frames(10)
	var pc: Control = inv._insp.card
	var pr: Rect2 = pc.get_global_rect() if pc != null and is_instance_valid(pc) else Rect2()
	var ps := _scrolls(pc)
	_ok("③ ★[%s] 背包里的超长探针卡整张在屏幕里(卡 %s)" % [tag, str(pr)], pc != null and screen.encloses(pr))
	_ok("③ ★[%s] 而且是卡内滚动: 内容 %d > 可见 %d、滚动条看得见" % [tag, int(ps[0][1]) if ps.size() == 1 else -1,
		int(ps[0][2]) if ps.size() == 1 else -1],
		ps.size() == 1 and str((ps[0][0] as Node).name) == InspectCard.N_SCROLL and float(ps[0][1]) > float(ps[0][2]) + 0.5 and bool(ps[0][3]))
	_ok("③ [%s] 卡头不滚" % tag, ps.size() == 1 and pc.find_child("Title", true, false) != null
		and not (ps[0][0] as Node).is_ancestor_of(pc.find_child("Title", true, false)))
	inv._insp.close()
	inv.queue_free()
	await _frames(3)
