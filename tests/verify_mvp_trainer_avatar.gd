extends Node
## verify_mvp_trainer_avatar —— 结算屏 MVP 是训龟大师时, 头像不许是空的。
## 由来: 2026-10-06 60 人实操 B3-1「本场 MVP 是训龟大师时, 名字左边的头像位是空的」
##   (p22/shots/20261006T165321_b10_result.jpg)。根因: SettleScreen.avatar 只认 avatars/<id>.png
##   与 pets/<id>.png, 训龟大师两张都没有 ⇒ texture = null。修法: _st_row 记下战场立绘路径+帧格, avatar 取首帧。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SS := preload("res://scripts/scenes/battle/settle_screen.gd")
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fails += 1


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var t: Dictionary = s._spawn._make_unit(s.TRAINER_ID, "left", c, {"trainer": true})
	_ok("分母: 造出来的是训龟大师", bool(t.get("is_trainer", false)), str(t.get("id", "")))
	var tid := str(t.get("id", ""))
	_ok("分母: 训龟大师确实没有 avatars/<id>.png(否则这条测的不是兜底)",
		not ResourceLoader.exists("res://assets/sprites/avatars/%s.png" % tid), tid)
	var row: Dictionary = s._st_row(t)
	_ok("统计行记下了战场立绘路径", str(row.get("_st_portrait", "")) != "", str(row.get("_st_portrait", "")))
	for k in row:
		var v = row[k]
		_ok("统计行仍是纯标量: " + str(k), not (v is Object or v is Dictionary or v is Array))
	var av: TextureRect = SS.avatar(row, 64.0)
	_ok("★MVP 头像有贴图(不是空的)", av.texture != null)
	if av.texture != null:
		var sz: Vector2 = av.texture.get_size()
		_ok("取的是单帧不是整张帧表(宽高都 ≤ 64)", sz.x <= 64.0 and sz.y <= 64.0, str(sz))
	## 反面: 龟照旧走 avatars/<id>.png, 兜底不抢它
	var b: Dictionary = s._spawn._make_unit("basic", "left", c)
	var avb: TextureRect = SS.avatar(s._st_row(b), 64.0)
	_ok("龟的头像照旧是 avatars/basic.png", avb.texture != null and str(avb.texture.resource_path).ends_with("avatars/basic.png"),
		str(avb.texture.resource_path) if avb.texture != null else "null")
	av.free()
	avb.free()
	s.queue_free()
	await get_tree().process_frame
	if _fails == 0:
		print("ALL PASS — 训龟大师当 MVP 有头像")
	else:
		print("FAIL x%d" % _fails)
	get_tree().quit()
