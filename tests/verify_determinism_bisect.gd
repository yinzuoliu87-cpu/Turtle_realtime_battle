extends Node
## verify_determinism_bisect.gd — ★**一次性测量用的门禁**，把「场景 ③ 跨平台分叉」二分到具体装备
##
## ══════════════════════════════════════════════════════════════════════
##  它是临时的，测完就删
## ══════════════════════════════════════════════════════════════════════
## 2026-09-26：`verify_determinism_cross` 在 CI（ubuntu/glibc）上的实测结果是
## **9 个场景里 8 个与本地（Windows/MSVC libm）逐位相同**，只有
## 「③ 3v3 满装备（每只 3 件 3★）」的摘要不同：
##   实得 4d3cb4c2376b18ac / 金标 e2e0a124d2326863
##
## ⇒ 不一致被圈在那 18 件装备里。**为什么要一次性门禁而不是探针**：
##   探针（`tests/_probe_*.gd`）不会被 `run-tests.sh` 自动发现 ⇒ **CI 不会跑它**，
##   而我需要的恰恰是 Linux 那一侧的数。所以只能做成 `verify_*`，
##   靠「金标对不上就红 ⇒ 失败日志推到 `ci-logs` 分支」把 Linux 侧的摘要取回来。
##   ⚠ 这意味着**这一次提交的 CI 是故意红的**，它就是测量本身。测完连同金标一起删。
##
## ══════════════════════════════════════════════════════════════════════
##  为什么分两层而不是直接单件
## ══════════════════════════════════════════════════════════════════════
## 单件场景（一只龟带一件 vs 一个假人）有个致命问题：**那件装备可能一次都没触发**
## （很多装备靠命中/充能/周期，节奏和满场时完全不同）⇒ 它没跑过，当然不分叉，
## 于是 PASS **洗不清它**（memory `fb-gate-subject-never-constructed`）。
## ⇒ 第一层保持 ③ **原样的 6 只龟、原样的站位**，只是**一次只给一只龟她那 3 件**，
##   战斗节奏与 ③ 接近 ⇒ 装备照原样触发。第二层再把命中的那只拆成单件。
## ★两层的结论必须互相印证：第一层指出的那只龟，第二层里必定有她的某一件在分叉。
##   对不上就说明分叉不在装备上，而在「几件装备同时在场」这种组合效应里。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_determinism_bisect.tscn --quit-after 40000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SC := preload("res://tests/_det_scenarios.gd")

const GOLDEN_PATH := "res://tests/golden/determinism_bisect.json"
const FRAMES := 600

var _fail := 0
var _n := 0
var _digests := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## ★与 `verify_determinism_cross._fp()` 逐字同一个口径 —— 换一个字这份二分就白做了。
func _fp(scene) -> String:
	var parts: Array = []
	var i := 0
	for u in scene._units:
		parts.append("%d/%s/%s:%.3f:%.2f:%.2f:%d:%.2f:%.1f:%.2f:%d:%.4f" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)),
			float((u.get("pos", Vector2()) as Vector2).x),
			float((u.get("pos", Vector2()) as Vector2).y),
			1 if bool(u.get("alive", false)) else 0,
			float(u.get("shield", 0.0)),
			float(u.get("gold", 0.0)),
			float(u.get("energy", 0.0)),
			int(u.get("prism_color", -1)),
			float(u.get("crit", 0.0))])
		i += 1
	return "|".join(parts)


func _run(pairs: Array) -> Array:
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	s._debug._edit_clear()
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in pairs:
		var u: Dictionary = s._debug._edit_place_unit(str(p[0]), str(p[1]),
			Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
	s._debug._edit_start_battle()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var uniq := {}
	for _i in range(FRAMES):
		await get_tree().process_frame
		var f := _fp(s)
		uniq[f] = true
		ctx.update(f.to_utf8_buffer())
	var taken := 0.0
	for u2 in s._units:
		taken += float(u2.get("_st_taken", 0.0))
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return [(ctx.finish() as PackedByteArray).hex_encode(), uniq.size(), taken]


## 场景 ③ 的原始摆位 —— **从共用表里取**，不许在这里手抄一份
## （抄了就可能量的不是同一局，而那会让整份二分的结论失效）。
func _sc3() -> Array:
	for sc in SC.all():
		if str((sc as Dictionary)["tag"]).begins_with("③"):
			return (sc as Dictionary)["pairs"] as Array
	return []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)

	var base: Array = _sc3()
	_ok("★分母: 从共用表里取到场景 ③ 的 %d 只单位" % base.size(), base.size() == 6,
		"%d 只" % base.size())
	if base.size() != 6:
		get_tree().quit(1)
		return

	var golden: Dictionary = _load_golden()
	var missing: Array = []

	## ── 第一层: 一次只给一只龟她那 3 件, 其余全裸 ──
	for k in range(base.size()):
		var pairs: Array = []
		for j in range(base.size()):
			var p: Array = (base[j] as Array).duplicate(true)
			if j != k:
				p[4] = []
			pairs.append(p)
		var who: String = str((base[k] as Array)[0])
		var eqs: Array = (base[k] as Array)[4]
		var tag := "L1·只给 %s 带 %s" % [who, ",".join(PackedStringArray(eqs))]
		await _one(tag, pairs, golden, missing)

	## ── 第二层: 18 件逐件(携带者保持原位, 其余全裸) ──
	for k2 in range(base.size()):
		var who2: String = str((base[k2] as Array)[0])
		for e in ((base[k2] as Array)[4] as Array):
			var pairs2: Array = []
			for j2 in range(base.size()):
				var p2: Array = (base[j2] as Array).duplicate(true)
				p2[4] = [str(e)] if j2 == k2 else []
				pairs2.append(p2)
			await _one("L2·%s 只带 %s" % [who2, str(e)], pairs2, golden, missing)

	if not missing.is_empty():
		print("")
		print("  ★金标缺 %d 条。整段存成 %s:" % [missing.size(), GOLDEN_PATH])
		print(JSON.stringify(_digests, "  "))
		_ok("★金标覆盖全部 %d 条(缺的那些这一轮没被量到)" % _digests.size(), false,
			"%d 条缺" % missing.size())

	print("")
	if _fail == 0:
		print("ALL PASS — 跨平台分叉二分 (%d/%d)" % [_n, _n])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _n - _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _one(tag: String, pairs: Array, golden: Dictionary, missing: Array) -> void:
	OS.set_environment("TURTLE_SEED", "424242")
	var r: Array = await _run(pairs)
	OS.set_environment("TURTLE_SEED", "")
	var dig: String = str(r[0])
	_digests[tag] = dig
	## 分母: 这一局真的在推进 —— 不然摘要是"静止画面"的摘要, 相同得毫无意义
	_ok("分母 · %s · 真的在推进(不同指纹 %d, 承伤 %.0f)" % [tag, int(r[1]), float(r[2])],
		int(r[1]) > 1 and float(r[2]) > 0.0)
	if golden.has(tag):
		_ok("★%s" % tag, dig == str(golden[tag]),
			"实得 %s / 金标 %s" % [dig.substr(0, 16), str(golden[tag]).substr(0, 16)])
	else:
		missing.append(tag)
		print("  [MISS] %s ⇒ %s" % [tag, dig])


func _load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		print("  [MISS] 金标文件不存在: %s" % GOLDEN_PATH)
		return {}
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if f == null:
		return {}
	var p = JSON.parse_string(f.get_as_text())
	f.close()
	return p if p is Dictionary else {}
