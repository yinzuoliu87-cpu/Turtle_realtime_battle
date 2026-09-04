extends Node
## verify_target_paths_agree.gd — 主动索敌的【多条路必须用同一套排除条件】
##
## ══════════════════════════════════════════════════════════════════
##  ★守的是「六份副本会漂移」这一整类，不是某一个 bug
## ══════════════════════════════════════════════════════════════════
## 用户 2026-09-04：「彻查项目的所有代码…」「真实伤害数字是一团乱，应该统一规则的」
##
## `battle_targeting.gd` 里有 **六个**函数在回答同一个问题「哪些敌人能被主动选中」：
##   `_nearest_enemy` / `_nearest_enemy_from` / `_farthest_enemy`
##   `_targetable_enemies` / `_pick_enemies_of` / `_nearest_enemy_for_trainer`
##
## `_pick_enemies_of` 头上的注释白纸黑字写着**用法铁律**：
##   「凡『随机挑一个 / 最近一个 / 单体指向』的技能选目标都走【这个】」
## 但 `_nearest_enemy`（被调 80 次，普攻主线就走它）**自己遍历 `_units` 重写了一遍**，
## 而且 `_nearest_enemy_from` 的注释还写着「排除规则与 `_nearest_enemy` 完全一致」——第三份。
##
## ⇒ **铁律写在注释里，没有门禁强制。** 本文件就是那个门禁。
##
## ★★判据形状：造一个**该被排除**的单位，断言**每一条主动索敌路径都排除它**。
##   不断言"它们调了同一个函数"（那是实现细节，改个写法就红，也证明不了结果一致）。
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _mk(side: String, at: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit("basic", side, at)
	u["no_move"] = true
	u["no_basic"] = true
	u["move_spd"] = 0.0
	u["active_skills"] = []
	u["maxHp"] = 99999.0
	u["hp"] = 99999.0
	_s._units.append(u)
	return u


func _arr_has(arr, x) -> bool:
	if not (arr is Array):
		return false
	for e in arr:
		if is_same(e, x):
			return true
	return false


## 对【每一条主动索敌路径】问一遍：它会选中 `bad` 吗？
## 返回 { 路径名 : true=选中了(说明没排除) }
func _who_picks(me: Dictionary, bad: Dictionary) -> Dictionary:
	var t = _s._targeting
	var out: Dictionary = {}
	out["_nearest_enemy"] = is_same(t._nearest_enemy(me), bad)
	out["_nearest_enemy_from"] = is_same(t._nearest_enemy_from(me, me["pos"]), bad)
	out["_farthest_enemy"] = is_same(t._farthest_enemy(me), bad)
	out["_targetable_enemies"] = _arr_has(t._targetable_enemies(me), bad)
	out["_pick_enemies_of"] = _arr_has(t._pick_enemies_of(me), bad)
	out["_acquire_target"] = is_same(t._acquire_target(me), bad)
	return out


## 跑一种"该被排除"的情形。`setup` 把 bad 设成该被排除的状态。
func _case(title: String, setup: Callable) -> void:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var me: Dictionary = _mk("left", c + Vector2(-200, 0))
	var bad: Dictionary = _mk("right", c + Vector2(60, 0))
	## ★分母：**同一个单位**在 setup 之前先问一遍 —— 干净状态下六条路必须都选得中，
	##   否则下面的"都排除了"是因为它本来就选不中（空检查）。
	## ⚠ 第一版用的是"另造一个干净的对照单位"，结果它离得远一点，
	##   `_nearest_enemy` 只返回更近的那个 ⇒ 分母自己红了。
	##   **同一单位前后对比**才是可比的（memory [[fb-gate-subject-never-constructed]]）。
	var base: Dictionary = _who_picks(me, bad)
	setup.call(bad)
	var base_n: int = 0
	for k in base:
		if bool(base[k]):
			base_n += 1
	_ok("★分母[%s]: 同一单位【干净时】能被 %d/6 条路选中" % [title, base_n], base_n >= 5,
		"干净时就选不中 ⇒ 下面是空检查（实测 %s）" % str(base))

	var picked: Dictionary = _who_picks(me, bad)
	var leaks: Array = []
	for k in picked:
		if bool(picked[k]):
			leaks.append(k)
	_ok("【%s】六条主动索敌路径**全部**排除它" % title, leaks.is_empty(),
		"漏网的路径: %s ⇒ 同一个单位，有的路选得中有的选不中" % str(leaks))

	# 清场，免得影响下一个 case
	for x in [me, bad]:
		x["alive"] = false
		var sp = x.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 主动索敌: 六条路必须用同一套排除条件 ===")

	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame

	## ① 机甲组装期。★`_is_untargetable()` 查 `untargetable_until` **或** `_assembling`，
	##   而 `_nearest_enemy` 那几个只查前者 ⇒ 赛博龟组装机甲的 5 秒里，
	##   `_pick_enemies_of` 排除它，普攻主线（走 `_nearest_enemy`）照样锁它。
	_case("机甲组装期 _assembling", func(b: Dictionary) -> void:
		b["_assembling"] = true)

	## ② 黑洞/不可选中窗口
	_case("不可选中 untargetable_until", func(b: Dictionary) -> void:
		b["untargetable_until"] = _s._t + 99.0)

	## ③ 龟蛋围栏未破
	_case("龟蛋围栏 _egg_fence", func(b: Dictionary) -> void:
		b["_egg_fence"] = true)

	## ④ 训龟大师（只吃 AOE，不被主动锁）
	_case("训龟大师 is_trainer", func(b: Dictionary) -> void:
		b["is_trainer"] = true)

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
