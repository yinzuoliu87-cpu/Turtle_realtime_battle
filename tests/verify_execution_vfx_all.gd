extends Node

## verify_execution_vfx_all.gd — 三处「处决」都得有演出，不许只跳一句浮字 (2026-10-02)
##
## 【由来】方案书 `20260906b` 登记着：
##   「**处决零演出**：004 的处决、药水【斩首】、弓箭【处决】三处都只有一句 `-999999` 浮字。
##     **没有门禁**，未动」
## 查下来**那条登记已经烂了**——药水与弓箭 2026-08-14 就接上了 `SynergyVfx.execution()`，
## 只有 004 还是裸浮字。⇒ 补 004，并把这条「没有门禁」一起补掉。
##
## 【为什么必须有判据】三处是**同一件事**（血线以下直接抹杀），而它们住在三个不同的文件里：
##   `equip_system.gd` / `bow_synergy_system.gd` / `potion_synergy_system.gd`
## 没有判据的话，任何一处被改回「只跳浮字」都不会红——而那正是它过去两个月的状态。
##
## ★判据分两层，缺一不可：
##   ① **源码层**：三处都调了 `execution(`（不调 = 根本没演出）
##   ② **行为层**：真跑一次 004 的处决，世界里**确实多出铡刀节点**
##      —— 只验源码会放过「调了但函数内部早退」。

const EXEC_SITES := {
	"res://scripts/systems/equip/equip_system.gd": "004 暴君之牙",
	"res://scripts/systems/equip/bow_synergy_system.gd": "弓箭【处决】",
	"res://scripts/systems/equip/potion_synergy_system.gd": "药水【斩首】",
}

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	# ── ① 源码层：三处都调了 execution( ──
	var missing: Array[String] = []
	var n_read := 0
	for f in EXEC_SITES:
		var src := FileAccess.get_file_as_string(f)
		if src == "":
			missing.append("%s 读不到" % str(EXEC_SITES[f]))
			continue
		n_read += 1
		if not src.contains("execution("):
			missing.append("%s 只跳浮字, 没调 execution(" % str(EXEC_SITES[f]))
	print("  [分母] 处决点 %d 处, 读到源码 %d 份" % [EXEC_SITES.size(), n_read])
	_ok("★分母: 三份源码都读得到(读不到会让下一条恒真)", n_read == EXEC_SITES.size(),
		"只读到 %d 份" % n_read)
	_ok("★三处处决都接了演出(不是只跳一句 -999999 浮字)", missing.is_empty(), str(missing))

	# ── ② 行为层：真调一次 execution()，世界里确实多出铡刀 ──
	## ★不走 tween、不等帧：`execution()` 建完铡刀就 `_adopt(blade, "exec_blade")`,
	##   所以建出来那一刻就数得到（本仓 §3.5：数值测试不许依赖 tween 跑完）。
	var scene := load("res://scenes/RealtimeBattle3D.tscn")
	_ok("★分母: 战斗场景载得到", scene != null)
	if scene == null:
		_finish()
		return
	var s = scene.instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var vfx = s._vfx
	_ok("★分母: 拿到 _vfx / _syn", vfx != null and vfx._syn != null)
	if vfx == null or vfx._syn == null:
		_finish()
		return
	var before := _count_blades(s)
	vfx._syn.execution(Vector2(300.0, 300.0), SynergyVfx.COL_EXEC_FANG)
	await get_tree().process_frame
	var after := _count_blades(s)
	print("  [分母] 世界里 exec_blade 节点: %d → %d" % [before, after])
	_ok("★调一次 execution 真的在世界里多出一把铡刀(光调不画 = 等于没演出)", after == before + 1,
		"%d → %d" % [before, after])
	## ★反面：不调它就不该凭空多出来（否则上一条可能数的是别的东西）。
	var b2 := _count_blades(s)
	await get_tree().process_frame
	_ok("★★反面: 不调 execution 时数目不变(证明上一条数的就是它建的那个)",
		_count_blades(s) == b2, "%d → %d" % [b2, _count_blades(s)])

	_finish()


## 世界里打了 `exec_blade` 标记的节点数。
## ⚠ 第一版我数的是**节点名** —— 而 `_adopt(n, kind)` 做的是 `n.set_meta(META_KEY, kind)`,
##   **它根本不改名字** ⇒ 永远数到 0, 判据当场假红。这是判据的错不是产品的错。
func _count_blades(s) -> int:
	var n := 0
	var w = s._world
	if w == null:
		return 0
	for c in w.get_children():
		if c.has_meta(SynergyVfx.META_KEY) and str(c.get_meta(SynergyVfx.META_KEY)) == "exec_blade":
			n += 1
	return n


func _finish() -> void:
	print("ALL PASS — 三处处决都有演出" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
