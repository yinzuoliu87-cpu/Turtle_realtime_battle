extends Node
## _probe_lane_residue.gd — 探针(只读·不进门禁): 换路之后 `_world` 里还剩什么?
##
## 用户 2026-08-10:「还有很多特效残留问题」。
## 换路时 `_dl_clear_units()` 只 free【单位自己的】节点(sprite/shadow/contact/ring/flame_sector/bar_root),
## **`_world` 本身不重建** ⇒ 任何挂在 `_world` 下、其所属层的 `clear()` 没被调的节点都会活到下一路。
##
## 这个探针不猜, 直接量:
##   ① 跑一段真实战斗(让各路特效自然发生)
##   ② 记下 `_world` 的子节点直方图(按类名 + 名字前缀)
##   ③ 走真实的换路撤场 `_dl_build_lane_field()`
##   ④ 再记一次 —— **差集就是残留**
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_lane_residue.tscn --quit-after 4000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s


func _hist() -> Dictionary:
	var h: Dictionary = {}
	if _s == null or _s._world == null or not is_instance_valid(_s._world):
		return h
	for c in _s._world.get_children():
		if not is_instance_valid(c):
			continue
		var k: String = "%s / %s" % [c.get_class(), str(c.name).split("@")[0]]
		h[k] = int(h.get(k, 0)) + 1
	return h


func _ready() -> void:
	await get_tree().process_frame
	print("=== 换路残留探针 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(20):
		await get_tree().process_frame

	# ① 跑一段真实战斗 —— 让技能/装备/羁绊的特效自然发生
	var w := 0.0
	while w < 6.0:
		await get_tree().process_frame
		w += get_process_delta_time()
	var before: Dictionary = _hist()
	var n_before := 0
	for k in before:
		n_before += int(before[k])
	print("  跑了 %.1f 秒后, _world 子节点 %d 个 / %d 类" % [w, n_before, before.size()])

	# ② 走真实的换路撤场
	_s._dl_sys._dl_build_lane_field()
	for _i in range(6):
		await get_tree().process_frame

	var after: Dictionary = _hist()
	var n_after := 0
	for k in after:
		n_after += int(after[k])
	print("  换路后, _world 子节点 %d 个 / %d 类" % [n_after, after.size()])
	print("")
	print("  ── 换路后仍然活着的(按数量降序) ──")
	var keys: Array = after.keys()
	keys.sort_custom(func(a, b): return int(after[a]) > int(after[b]))
	for k in keys:
		print("    %-46s x%d   (换路前 x%d)" % [str(k), int(after[k]), int(before.get(k, 0))])

	_s.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
