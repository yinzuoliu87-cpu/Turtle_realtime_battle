extends Node
const EquipStats = preload("res://scripts/gamedata/equip_stats.gd")
const Phase2Types = preload("res://scripts/gamedata/phase2_types.gd")
## 探针: 商店选中一件货的耗时(直接调 vs 真点击)
## verify_shop_no_rebuild.gd — 商店点一下不整页重建(2026-11-05)
##
## 由来: 用户 2026-11-05「这个商店因为是动态的，然后我任意点击屏幕上一个地方，都会使这个商店重置一下，于是所有图片都卡一下」。
##   查实: 选中一件货 / 点空白收起 / 点等级看概率都调 `_rebuild()` —— 整页(背景、货柜、10 件货、店主、氛围动效)销毁再建,
##   呼吸光 / 斜掠高光 / 店主待机全从头播。改成 `_refresh_popups()`: 只动选中金光、说明卡、概率牌。
## 判据(真鼠标按下 + 松开, 走引擎命中, 写法同 verify_shop_interactions):
##   ① 点货架 / 点同一格收起 / 点另一格 / 点空白 / 点等级开概率 / 再点收起 —— 每一步之后, 背景、10 件货、刷新钮、等级牌、
##      钱袋牌、店主这些节点【还是同一个实例】(没被销毁重建), 且「已拥有」呼吸光的循环补间没被换掉(动画没重播)
##   ② 该出现的出现: 选中金光在被点那格、说明卡开着 / 收起, 概率牌开 / 收
##   ③ 一次点击花的时间 < 同一进程里整页重建的 50%(相对参照, 不跟机器快慢挂钩)
## 跑法: bash godot-quiet.sh res://tests/verify_shop_no_rebuild.tscn

const SHOP := preload("res://scenes/Shop.tscn")
var _fail := 0
var _n := 0
var gs


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


func _ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	get_viewport().push_input(e)


## 一次点按; 返回从松开(点击在松开时生效)到其后 6 帧走完的墙钟微秒 —— 销毁旧节点 / 排版都在后面几帧里
func _click(p: Vector2) -> int:
	_ev(p, true)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	_ev(p, false)
	await _frames(6)
	return Time.get_ticks_usec() - t0


func _dying(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p.is_queued_for_deletion():
			return true
		p = p.get_parent()
	return false


func _live(root: Node, nm: String) -> Control:
	for c in root.find_children(nm, "", true, false):
		if c is Control and (c as Control).is_visible_in_tree() and not _dying(c):
			return c
	return null


func _glow_slot(sc: Node) -> int:
	for i in range(10):
		var b := _live(sc, "ShelfItem%d" % i)
		if b != null and b.find_child("SelGlow", true, false) != null:
			return i
	return -1


func _slot_center(sc: Node, i: int) -> Vector2:
	var b := _live(sc, "ShelfItem%d" % i)
	return b.get_global_rect().get_center() if b != null else Vector2(-100, -100)


## 「不该被重建」的那一批: 名字 → 实例号
func _stable(sc: Node) -> Dictionary:
	var out := {}
	var names := ["CoinPlaque", "LevelPlaque", "ShopRefreshBtn"]
	for i in range(10):
		names.append("ShelfItem%d" % i)
	for nm in names:
		var c := _live(sc, nm)
		out[nm] = c.get_instance_id() if c != null else 0
	## 背景(整页第一层 ColorRect)与店主: 按类型 / 名字里有 Keeper 找
	for c in sc.find_children("*Keeper*", "", true, false):
		if not _dying(c):
			out["keeper:" + str(c.name)] = c.get_instance_id()
	for c in sc.find_children("*", "TextureRect", true, false):
		if not _dying(c) and (c as TextureRect).texture != null and str((c as TextureRect).texture.resource_path).find("backdrop") >= 0:
			out["backdrop"] = c.get_instance_id()
			break
	return out


func _same(a: Dictionary, b: Dictionary) -> Array:
	var bad: Array = []
	for k in a:
		if int(a[k]) == 0 or int(b.get(k, -1)) != int(a[k]) or not is_instance_valid(instance_from_id(int(a[k]))) or _dying(instance_from_id(int(a[k]))):
			bad.append(k)
	return bad


func _ready() -> void:
	await get_tree().process_frame
	gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.meta_deepsea_coins = 999
	gs.season_level = 5
	gs.season_total_battles = 3
	gs.meta_shop_offer = []
	gs.meta_shop_battles = -1
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(2)
	var sc: Control = SHOP.instantiate()
	add_child(sc)
	sc.size = Vector2(1280, 720)
	await _frames(8)
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 2500:
		await get_tree().process_frame
	print("[P] 后台还在加载的脚本 %d 个" % SkillText._warm_pending.size())
	var edef: Dictionary = sc._deco(sc._offer[2])
	var eid := str(edef.get("id", ""))
	var tt := Time.get_ticks_usec()
	var _st: Array = []
	for kv in EquipStats.stat_lines(eid, 1):
		_st.append(InspectCard.eq_stat_row(kv, Color.WHITE))
	print("[P] 属性行 %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0)); tt = Time.get_ticks_usec()
	SkillText._ensure_re()
	print("[P]   _ensure_re(正则 %d 条关键词) %.1f ms" % [SkillText._keyword_re.size(), (Time.get_ticks_usec() - tt) / 1000.0]); tt = Time.get_ticks_usec()
	var src: String = SkillText.equip_full_src(edef)
	print("[P]   equip_full_src %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0)); tt = Time.get_ticks_usec()
	var b1: String = SkillText.plain_to_bb(src, 20)
	print("[P]   plain_to_bb %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0)); tt = Time.get_ticks_usec()
	var bb: String = sc._rich_desc(edef, 1)
	print("[P] 说明正文 _rich_desc %.1f ms (%d 字)" % [(Time.get_ticks_usec() - tt) / 1000.0, bb.length()]); tt = Time.get_ticks_usec()
	var _ib: String = Phase2Types.icon_bb(str(Phase2Types.type_of(eid)), 16)
	print("[P] 类型图标 %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0)); tt = Time.get_ticks_usec()
	var bt := Button.new(); sc._card_button_skin(bt)
	print("[P] 购买钮皮 %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0)); tt = Time.get_ticks_usec()
	var lv: Dictionary = sc._insp.open("probe", null, {"title": "x", "body": bb, "body_px": 20, "width": 400, "min_px": 20, "stats": _st})
	print("[P] InspectCard.open(正文同一段) %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0)); tt = Time.get_ticks_usec()
	sc._insp.close()
	var lv2: Dictionary = sc._insp.open("probe2", null, {"title": "y", "body": bb, "body_px": 20, "width": 400, "min_px": 20, "stats": _st})
	print("[P] 第二次 InspectCard.open %.1f ms" % ((Time.get_ticks_usec() - tt) / 1000.0))
	sc._insp.close()
	await _frames(3)
	for k in range(3):
		var t0 := Time.get_ticks_usec()
		sc._on_select(2)
		var a := Time.get_ticks_usec() - t0
		await _frames(3)
		t0 = Time.get_ticks_usec()
		sc._on_select(2)
		var b := Time.get_ticks_usec() - t0
		await _frames(3)
		print("[T] 直接调 第%d次 选中 %.1f ms · 收起 %.1f ms" % [k + 1, a / 1000.0, b / 1000.0])
	for k in range(3):
		var p := _slot_center(sc, 5)
		_ev(p, true)
		await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		_ev(p, false)
		var a := Time.get_ticks_usec() - t0
		await _frames(3)
		_ev(p, true)
		await get_tree().process_frame
		t0 = Time.get_ticks_usec()
		_ev(p, false)
		var b := Time.get_ticks_usec() - t0
		await _frames(3)
		print("[T] 真点击 第%d次 选中 %.1f ms · 收起 %.1f ms" % [k + 1, a / 1000.0, b / 1000.0])
	get_tree().quit()
