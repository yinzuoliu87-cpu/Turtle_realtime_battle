extends Node
## _reset_save_runner.gd — 给 tools/reset_test_account.py 用：把一份云存档载入 → 走产品的 `GameState.reset_save()` → 导出要上云的那一份。
## 环境变量：RESET_IN = 输入 payload（json 文件）、RESET_OUT = 输出 payload。只在隔离的 user:// 里跑（工具负责设 APPDATA / XDG_DATA_HOME）。
## 输出只含输入里有的键（客户端上传本来就不带设备本地键）；打印重置前后的关键数，工具据此核对。

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var src_path := OS.get_environment("RESET_IN")
	var out_path := OS.get_environment("RESET_OUT")
	if gs == null or src_path == "" or out_path == "":
		print("[RESET] FAIL 缺 GameState / RESET_IN / RESET_OUT")
		get_tree().quit(1)
		return
	var src = JSON.parse_string(FileAccess.get_file_as_string(src_path))
	if not (src is Dictionary):
		print("[RESET] FAIL 输入解不开 ", src_path)
		get_tree().quit(1)
		return
	gs.test_mode = true   # save() 不落盘：只在内存里重置、导出
	gs._apply_save_dict((src as Dictionary).duplicate(true))
	print("[RESET] 载入后 nick=%s lv=%s battles=%s wins=%s hearts=%s" % [str(gs.nickname), str(gs.season_level),
		str(gs.season_total_battles), str(gs.season_wins), str(gs.hearts)])
	gs.reset_save()
	var full: Dictionary = gs.cloud_payload()
	var out := {}
	for k in (src as Dictionary).keys():
		if full.has(k):
			out[k] = full[k]
	print("[RESET] 重置后 nick=%s lv=%s battles=%s wins=%s hearts=%s keys=%d/%d" % [str(gs.nickname), str(gs.season_level),
		str(gs.season_total_battles), str(gs.season_wins), str(gs.hearts), out.size(), (src as Dictionary).size()])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[RESET] OK")
	get_tree().quit(0)
