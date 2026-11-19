extends Node
## verify_shell_copy_two.gd —— 龟壳【复制】一定偷两个(2026-11-19)
##
## 用户 11-19:「龟壳偷进来不是偷两个吗？为什么我只看到一个？然后偷的图标也只有一个，收放进的也只有一个，不是偷两次吗？」
## 查实(探针 tests/probes/_probe_shell_copy_count.gd): 原来只从**活着的**敌人取, 每只龟只带 1 个主动 ⇒ 对面剩 1 只就只放 1 发。
## 改(我推荐的 A, 用户未表态前先按它做): 这一路上过场的全部敌方单位(活着或已阵亡)都能偷; 能偷的只有 1 个 ⇒ 同一个放两次。
## 数法: ShellVfx 换成计数替身(tests/_shell_fx_counter.gd), 头顶图标个数 = 放了几发。
##   ① 三只都活 ⇒ 2 发、两个不同
##   ② ★只剩 1 只活(另两只已阵亡) ⇒ 仍 2 发、两个不同(阵亡的也能偷)
##   ③ ★全场能偷的只有 1 个 ⇒ 同一个放两次
##   ④ 能偷的那一个在已阵亡的敌人身上 ⇒ 照样偷到、放两次
##   ⑤ 分母: 全是不能偷的 ⇒ 0 发; 训龟大师身上的不算
## 反向验证(11-19): 取池改回 _enemies_of ⇒ ②④ 红; 去掉「只有 1 个就放两次」⇒ ③④ 红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const FXC := preload("res://tests/_shell_fx_counter.gd")

var _s = null
var _n := 0
var _fail := 0


func _ok(t: String, c: bool, d: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if c else "FAIL", t, ("  " + d) if d != "" else ""])


func _mk(id: String, px: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, Vector2(px, 400.0))
	u["hp"] = 100000.0; u["maxHp"] = 100000.0; u["alive"] = true
	u["no_move"] = true; u["atk_interval"] = 9999.0; u["atk_cd"] = 9999.0
	return u


## enemies: [[id, 活着?, 技能覆盖(空 = 默认)], ...] ⇒ 头顶图标列表
func _cast(enemies: Array, extra: Callable = Callable()) -> Array:
	_s._units.clear()
	_s._pending_shots.clear()
	var sh: Dictionary = _mk("shell", 400.0, "left")
	_s._units.append(sh)
	var first_alive = null
	for i in range(enemies.size()):
		var spec: Array = enemies[i]
		var e: Dictionary = _mk(str(spec[0]), 700.0 + 40.0 * i, "right")
		e["alive"] = bool(spec[1])
		if spec.size() > 2:
			e["active_skills"] = (spec[2] as Array).duplicate()
		_s._units.append(e)
		if first_alive == null and e["alive"]:
			first_alive = e
	if extra.is_valid():
		extra.call()
	var fx = FXC.new(_s)
	_s._shell_sys._fx = fx
	_s._shell_sys._sk_shell_copy(sh, first_alive)
	for _k in range(40):
		_s._ballistics._step_pending_shots(0.05)
	return fx.icons


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 龟壳·复制: 一定偷两个 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false

	var i1: Array = _cast([["stone", true], ["ice", true], ["ninja", true]])
	_ok("① 三只都活 ⇒ 2 发、两个不同", i1.size() == 2 and i1[0] != i1[1], str(i1))

	var i2: Array = _cast([["stone", true], ["ice", false], ["ninja", false]])
	_ok("② ★只剩 1 只活(两只已阵亡) ⇒ 仍 2 发", i2.size() == 2, str(i2))
	_ok("② ★两个不同(阵亡的技能也能偷)", i2.size() == 2 and i2[0] != i2[1], str(i2))

	var i3: Array = _cast([["stone", true], ["angel", true, ["angelAscend"]], ["hunter", true, ["hunterStealth"]]])
	_ok("③ ★全场能偷的只有 stoneRockShield ⇒ 同一个放两次", i3 == ["stoneRockShield", "stoneRockShield"], str(i3))

	var i4: Array = _cast([["angel", true, ["angelAscend"]], ["ice", false]])
	_ok("④ ★能偷的那一个在已阵亡的敌人身上 ⇒ 照样偷到、放两次", i4 == ["iceFrost", "iceFrost"], str(i4))

	var i5: Array = _cast([["angel", true, ["angelAscend"]], ["hunter", true, ["hunterStealth"]]])
	_ok("⑤ 分母: 全是不能偷的 ⇒ 0 发", i5.is_empty(), str(i5))
	var i6: Array = _cast([["angel", true, ["angelAscend"]], ["ice", true]], func() -> void:
		(_s._units[2] as Dictionary)["is_trainer"] = true)
	_ok("⑤ 训龟大师身上的不算(另一只又不能偷 ⇒ 0 发)", i6.is_empty(), str(i6))

	_s._units.clear()   # 不用 erase: 单位字典按内容比较会递归(CLAUDE.md §4.2)
	print("=== 共 %d 条, 失败 %d ===" % [_n, _fail])
	if _fail == 0 and _n >= 7:
		print("ALL PASS")
	get_tree().quit(1 if _fail > 0 else 0)
