extends Node
## verify_spawn_busy_root 用的替身场景(下划线开头: 不是门禁)。
##   `_ready` / `_exit_tree` 各调一次挂在类上的钩子(一次性: 调完就清, 退出进程时不会再调一遍)。
##   钩子放在类上(static)而不是实例上: 新场景是 `change_scene_to_packed` 现建的实例, 测试手里没有它。

static var on_ready: Callable = Callable()
static var on_exit: Callable = Callable()


func _ready() -> void:
	if on_ready.is_valid():
		var f := on_ready
		on_ready = Callable()
		f.call()


func _exit_tree() -> void:
	if on_exit.is_valid():
		var f := on_exit
		on_exit = Callable()
		f.call()
