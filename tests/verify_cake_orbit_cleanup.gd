extends Node
## verify_cake_orbit_cleanup.gd — 069 糖糕的绕转精灵, 换路撤场必须被收掉
##
## 由来(2026-08-20): `clear_all()` 自称"把还在飞的演出全清掉", 而 069 糖糕绕转的三个精灵
## 原本不在它的清理范围内 —— 本测试焊住"它说清干净就真的清干净"。
##
## ⚠ **诚实记录: 这不是在守一个现存的 bug**。我最初判定"换路时糕会冻在战场上", **判错了** ——
##   `clear_all()` 本来就没有调用者(它的头注写着原因: 换路整个重建 `_world`, 本层节点跟着销毁)。
##   我还拿"改动前 smoke 0 条报错 / 改动后 1 条"当证据, 而那条报错**连跑三次是 0/1/0 的偶发** ——
##   **在会随机失败的进程上做 N=1 对比, 什么都证明不了**(memory 里就有这条, 今晚第三次踩)。
##
## ★判据量的是**真实的节点数**, 不是"有没有调过那个函数" —— 后者数的是我插的标记。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	print("=== 069 糖糕绕转的撤场 ===")

	var vfx = scn._equip_sys._food_sys._vfx if scn._equip_sys._food_sys != null else null
	_ok("★分母: 食物演出层在场", vfx != null)
	if vfx == null:
		_done(scn)
		return

	## ★判据只盯**这几个精灵本身**, 不数 `_world` 的子节点总数 ——
	##   战斗场还在陆续生成单位, 数总数会随无关活动变, 在门禁的并行负载下必红(实测: 单跑绿、并行红)。
	##   (memory: 测试不稳别跟随机较劲 —— 把判据改成对无关变化不敏感, 而不是去钉住环境。)
	var u := {"pos": Vector2(400, 300)}
	var h1: Dictionary = vfx.cake_orbit_make(u, 3)
	var h2: Dictionary = vfx.cake_orbit_make(u, 3)
	var mine: Array = []
	for hh in [h1, h2]:
		for sp in (hh.get("spr", []) as Array):
			mine.append(sp)
	_ok("① 造两组绕转 → 拿到 6 个精灵", mine.size() == 6, "实测 %d" % mine.size())
	var alive0 := 0
	for sp in mine:
		if is_instance_valid(sp):
			alive0 += 1
	_ok("① 六个都活着", alive0 == 6, "存活 %d" % alive0)

	vfx.clear_all()
	await get_tree().process_frame   # queue_free 是延迟的
	await get_tree().process_frame
	var alive1 := 0
	for sp in mine:
		if is_instance_valid(sp):
			alive1 += 1
	_ok("★★换路撤场后这六个全被收掉", alive1 == 0, "还活着 %d 个" % alive1)

	## ★反面: 不撤场就不该自己消失 —— 否则上面那条即使不接线也会绿
	var h3: Dictionary = vfx.cake_orbit_make(u, 3)
	await get_tree().process_frame
	await get_tree().process_frame
	var alive2 := 0
	for sp in (h3.get("spr", []) as Array):
		if is_instance_valid(sp):
			alive2 += 1
	_ok("★反面: 没撤场时仍活着(证明上面不是自然消失)", alive2 == 3, "存活 %d" % alive2)
	vfx.clear_all()

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 糖糕绕转撤场" if _fail == 0 else "FAIL")
	_done(scn)


func _done(scn) -> void:
	if is_instance_valid(scn):
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
