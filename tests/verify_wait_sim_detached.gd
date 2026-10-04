extends Node
## verify_wait_sim_detached.gd — 离开战斗场景时, 正在等 sim 的协程不许报错 (2026-10-03 周六实操台账 S8)
##
## 现象: 点「返回主菜单 / 前往商店」离开结算屏时日志出
##   `Parameter "data.tree" is null` + `Invalid access to property or key 'process_frame' on a base object of type 'null instance'`
##   at `_wait_sim` ← `_eq_broadsword` / `_eq_wide_blade`。
## 根因: 场景已从树上摘下、还没真正释放时, `is_instance_valid(self)` 仍真, 而 `get_tree()` 已是 null。
## ★判据: 起一个真战斗场, 开一个 `_wait_sim` 协程, 把场景从树上摘下, 再推几帧 ——
##   门禁的致命正则会抓 SCRIPT ERROR; 这里再配一条分母: 协程确实在等(没有一开始就返回)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail := 0
var _n := 0
var _done := false

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _fire_and_forget_waiter(s) -> void:
	await s._wait_sim(30.0)
	_done = true


func _ready() -> void:
	await get_tree().process_frame
	print("=== 离场时等 sim 的协程不许报错 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	for _i in range(5):
		await get_tree().process_frame
	_fire_and_forget_waiter(s)   # 故意不等: 要它挂着等 sim, 再把场景摘下树
	for _i in range(3):
		await get_tree().process_frame
	_ok("★分母: 协程真的在等(30 秒的 sim 等待没有一开始就结束)", not _done)
	remove_child(s)                      # 与切场景同形: 摘下树, 还没释放
	for _i in range(10):
		await get_tree().process_frame
	_ok("★★摘下树之后协程自己收场(原 bug: 每帧 get_tree() 为 null 报错)", _done)
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 离场协程" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
