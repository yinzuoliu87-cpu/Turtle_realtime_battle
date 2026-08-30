extends Node
## verify_copy_no_lock.gd — 抄来的技能不许在龟壳身上留【长命的锁/哨兵】(2026-08-31)
##
## ★由来: 用户 2026-08-30「一个个看有没有问题」→ 批量台量出
##   `headlessSoulStrike` 会给龟壳设 `energy_lock_until = _t + 999`,
##   而**解锁那一半写在 `if u["id"] == "headless"` 后面, 龟壳永远走不到**
##   ⇒ 龟壳一整场再也放不出技能。同族还有 `diceFate`(crit_fate_until +999)。
##
## ★病根形状: **技能"上效果"那一半是通用的, "卸载"那一半只对原主生效。**
##   全仓 `u["id"] == "<某龟>"` 这样的闸有 71 处; 危险的只是**闸里含"解锁"**的那一小撮。
##   —— 只有"收益"被闸住的(如 lavaErupt 的 lava_pierce_next)是白丢, 不伤人。
##
## ★判据为什么是"长命"而不是"有没有": 技能给施法者上短 buff 是**正当效果**
##   (用户 2026-08-28 明确说过给自己上 buff 算正当结果)。真正的病是
##   **999 这种哨兵值** —— 它的语义是"等某件事发生再解锁", 而那件事龟壳做不到。
##   实测: 正当自身 buff 都在 6 秒内(护盾 1~4s / 加速 1.8s / 虚化 0.9s);
##   哨兵是 999s。15 秒这条线中间空得很干净。
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## 超过这么久 = 哨兵, 不是正当 buff。虫洞飞行那种有界长锁最多 25 秒, 所以放到 40。
const SENTINEL_SEC := 40.0

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
	print("=== 抄来的技能不许留长命锁 ===")
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._sd_stacks = 0

	var all: Array = []
	for st in _s._IMPL_SKILLS.keys():
		if CopyRules.can_copy(str(st), _s._IMPL_SKILLS):
			all.append(str(st))
	all.sort()
	_ok("★分母: 可抄技能扫到 %d 个(<40 就是扫描失效)" % all.size(), all.size() >= 40)

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var bad: Array = []
	var checked := 0
	for st in all:
		_s._units.clear()
		var u: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-200.0, 0.0))
		u["maxHp"] = 1.0e6
		u["hp"] = 1.0e6
		var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(-120.0, 0.0))
		e["maxHp"] = 1.0e6
		e["hp"] = 1.0e6
		e["active_skills"] = [str(st)]
		_s._units.append(u)
		_s._units.append(e)
		_s._shell_sys._sk_shell_copy(u, e)
		for _f in range(6):
			await get_tree().process_frame
		checked += 1
		for k in u.keys():
			var ks := str(k)
			if not ks.ends_with("_until"):
				continue
			var v = u[k]
			if (v is float or v is int) and float(v) - _s._t > SENTINEL_SEC:
				bad.append("%s → %s(+%.0fs)" % [st, ks, float(v) - _s._t])

	_ok("★分母: 真的逐个抄过 %d 个(不是空转)" % checked, checked == all.size())
	_ok("★★抄完之后龟壳身上不许有 > %.0f 秒的锁/哨兵" % SENTINEL_SEC,
		bad.is_empty(), str(bad.slice(0, mini(6, bad.size()))))

	_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 抄来的技能不留长命锁" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
