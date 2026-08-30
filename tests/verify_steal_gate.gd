extends Node
## verify_steal_gate.gd — 【偷技/抄技必须走同一道闸】(2026-08-31)
##
## ★由来: 用户 2026-08-30 让我把龟壳复制的 82 个技能一个个看, 查出 3 个
##   "抄了会崩 / 会把龟壳废掉一整场"的, 进了 CopyRules.UNCOPYABLE。
##   但**精英小将的【吞噬】是同一个机制**(偷敌人主动技再放出来), 走的却是另一套实现,
##   它只过滤了"被动技"与"未实装", **黑名单一个都不看**。
##   实测(tests/_probe_devour.gd): 8 个黑名单技能全偷得到, 其中
##     · headlessSoulStrike → 小将龟能锁还剩 998 秒 + 射程 +60(废掉一整场)
##     · angelAscend        → 射程永久 +25
##
## ★判据必须【两头都问】: 黑名单的一个都不许偷 **且** 正常技能照旧偷得到。
##   只问前一半的话, 把 `_elite_steal_skill_type` 改成永远返回 "" 也会全绿
##   —— 那是把功能删了, 不是修好了。
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 偷技/抄技同一道闸 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	var block: Array = CopyRules.UNCOPYABLE.keys()
	_ok("★分母: 黑名单非空(%d 条) —— 空名单会让下面恒真" % block.size(), block.size() >= 5,
		str(block))

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var vic: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(40.0, 0.0))
	_s._units.append(vic)

	## ① 黑名单一个都不许被吞噬偷到
	var stolen: Array = []
	for st in block:
		vic["active_skills"] = [str(st)]
		if _s._elite_sys._elite_steal_skill_type(vic) != "":
			stolen.append(str(st))
	_ok("① ★★吞噬不许偷到黑名单里的技能(龟壳抄不了的, 小将也不该偷得到)",
		stolen.is_empty(), "偷到了 %s" % str(stolen))

	## ② ★分母的另一半: 正常技能必须【照旧偷得到】。
	##    没有这条, 把函数改成永远返回 "" 也会绿 —— 那是删功能不是修 bug。
	var okc: Array = []
	var missed: Array = []
	for st in ["bambooSmack", "iceFreeze", "lavaQuake", "minionBodysurf"]:
		if not _s._IMPL_SKILLS.has(st):
			continue
		vic["active_skills"] = [st]
		if _s._elite_sys._elite_steal_skill_type(vic) == st:
			okc.append(st)
		else:
			missed.append(st)
	_ok("② ★★正常技能照旧偷得到(挡多了也是错)", missed.is_empty() and okc.size() >= 3,
		"偷得到 %s / 偷不到 %s" % [str(okc), str(missed)])

	## ③ 两边用的是同一个判据函数, 不是各写一份
	var src := FileAccess.get_file_as_string("res://scripts/systems/skills/elite_system.gd")
	_ok("③ ★分母: 源码读得到", src.length() > 3000, "%d 字" % src.length())
	_ok("③ 吞噬走的是 CopyRules.can_copy(), 不是自己抄一份名单",
		src.contains("CopyRules.can_copy("))

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 5:
		print("  [FAIL] ★分母: 断言只有 %d 条(<5)" % _n)
		_fail += 1
	print("ALL PASS — 偷技/抄技同一道闸" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
