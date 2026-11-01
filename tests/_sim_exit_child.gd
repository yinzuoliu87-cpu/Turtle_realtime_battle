extends Node
## verify_sim_exit_clean 的子进程(2026-11-01 U3)。不单独跑。
## 起来之后: 记下「闪退标记在不在」(ErrorReporter 开机就写 user://running.flag), 再挂一个真的 sim_driver,
##   调它的 `_finish("exit_on_pair")` —— 与补格子的陪练号配上就下线是同一条退出路径(SIM_QUIT_WHEN_DONE=1 ⇒ 3 秒后 get_tree().quit())。
## CHILD_HANG=1 ⇒ 只记标记、不退(父进程硬杀它, 当对照)。

const Drv := preload("res://scripts/systems/sim/sim_driver.gd")
const MARK := "user://sim_exit_child.txt"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var f := FileAccess.open(MARK, FileAccess.WRITE)
	f.store_string("flag=%d" % (1 if FileAccess.file_exists(ErrorReporter.FLAG_PATH) else 0))
	f.close()
	if OS.get_environment("CHILD_HANG") == "1":
		return
	var d = Drv.new()
	d.name = "SimDriverChild"
	add_child(d)
	await get_tree().process_frame
	d.call("_finish", "exit_on_pair")
