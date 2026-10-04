extends Node
## verify_autopilot_finals.gd — 模拟窗口的周日自动驾驶 (2026-10-04)
## 用户:「整个右屏现在都是你的，我在用左屏」⇒ 周日流程不许靠动鼠标点。
## ① 默认关: 不带 SIM_AUTOPILOT 时一个节点都不建(玩家永远走不到这里)
## ② 开着: 对阵图上只点开 `should_fetch_opponent` 放行的那一场(产品自己的判定), 一场只点一次
## ★替身只实现对阵图被调用的四个成员, 判定逻辑仍是替身里那张「哪一场是我的」表 ——
##   真场景的 should_fetch_opponent 由 verify_bracket_map / verify_finals_feed 守。

var _fail := 0
var _n := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


class FakeMap extends Node:
	var _await_match := Vector2i(-1, -1)
	var opened: Array = []
	func cur() -> Dictionary:
		return {"size": 6, "round": 1, "done": {}}
	func should_fetch_opponent(r: int, m: int) -> bool:
		return r == 1 and m == 3            # 只有第 1 轮第 3 场是「我的、对手已定」
	func _on_match_opened(r: int, m: int) -> void:
		opened.append(Vector2i(r, m))
		_await_match = Vector2i(r, m)       # 与真场景同: 开了就进入等对手


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周日自动驾驶 ===")
	var had: bool = OS.has_environment(SimAutopilot.ENV)
	var env0: String = OS.get_environment(SimAutopilot.ENV)

	OS.set_environment(SimAutopilot.ENV, " ")      # 空白 = 停用(与 autopilot.gd 同约定)
	var f0 := FakeMap.new()
	add_child(f0)
	var d0 = SimFinalsPilot.attach_bracket(f0)
	for _i in range(140):
		await get_tree().process_frame
	_ok("①★★默认关: 不建节点、一场都不点", d0 == null and f0.opened.is_empty(), str(f0.opened))
	f0.queue_free()

	OS.set_environment(SimAutopilot.ENV, "1")
	var f1 := FakeMap.new()
	add_child(f1)
	var d1 = SimFinalsPilot.attach_bracket(f1)
	for _i in range(400):
		await get_tree().process_frame
	_ok("②★分母: 开着时真的建了驾驶节点", d1 != null)
	_ok("②★★只点开了「我的」那一场(第 1 轮第 3 场), 而且只点一次(等对手期间不重复点)",
		f1.opened == [Vector2i(1, 3)], str(f1.opened))
	f1.queue_free()

	if had:
		OS.set_environment(SimAutopilot.ENV, env0)
	else:
		OS.unset_environment(SimAutopilot.ENV)
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 周日自动驾驶" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
