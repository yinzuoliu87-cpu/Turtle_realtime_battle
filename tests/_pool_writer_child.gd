extends Node
## _pool_writer_child.gd —— verify_pool_atomic_write 的子进程: 不停地 save_pool 一份大池子, 等着被父进程杀。
## 每存完一份就把计数写进 MARK(父进程看到 ≥2 才开始挑时刻杀)。
## ★自己 25 秒后退出 —— 父进程万一先死, 不留孤儿进程。

const Backend := preload("res://scripts/net/backend.gd")
const PATH := "user://pool_atomic_killtest.json"
const MARK := "user://pool_atomic_killtest.mark"
const ROWS := 12000


static func big_pool(tag: int) -> Dictionary:
	var arr: Array = []
	for i in ROWS:
		arr.append({"name": "killtest-%05d" % i, "season_total_battles": 8, "tag": tag,
			"team": ["t01", "t02", "t03"], "equips": ["p2eq_001", "p2eq_075", "p2eq_096"],
			"hp": [1200, 980, 1430], "wins": i % 7, "losses": i % 5})
	return {Backend.POOL_KEY: {"8": arr}}


func _ready() -> void:
	var pool := big_pool(0)
	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 25000:
		pool[Backend.POOL_KEY]["8"][0]["tag"] = n
		Backend.save_pool(pool, PATH)
		n += 1
		var f := FileAccess.open(MARK, FileAccess.WRITE)
		if f != null:
			f.store_string(str(n))
			f.close()
	get_tree().quit(0)
