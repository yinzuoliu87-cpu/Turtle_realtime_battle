extends Node
## 探针: 存档**写到一半被杀进程**会怎样?
##
## ★`save()` 是**直接覆写**(`FileAccess.WRITE` 先把文件截断为 0, 再写, 再 close),
##   手机上进程随时可能被系统杀掉 —— 杀在这中间, 盘上就是一份残档。
## ★而 `_load()` 遇到坏 JSON 直接 `return` ⇒ **静默当新档开局**。
const SAVE_PATH := "user://savegame.json"


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		get_tree().quit(1); return
	## ★本探针必须真写盘(要的就是盘上那份文件), 所以 test_mode 关着;
	##   跑在门禁给的独立 APPDATA 里, 碰不到真存档。
	gs.test_mode = false
	## ★存**两次**: `.bak` 是第二次存档时由旧档改名而来的。真实玩家一周要存几百次,
	##   所以「盘上有一份上一次的完整档」是常态; 只存一次是首启那一瞬间的特例。
	gs.season_total_battles = 16
	gs.season_wins = 8
	gs.meta_deepsea_coins = 4000
	gs.save()                       ## 第一次: 建正式档
	gs.season_total_battles = 17
	gs.season_wins = 9
	gs.meta_deepsea_coins = 4321
	gs.save()                       ## 第二次: 旧档变 .bak, 新档就位
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var whole := f.get_as_text() if f != null else ""
	if f != null:
		f.close()
	print("  [探针] 正常存档 %d 字节" % whole.length())

	## —— 模拟「写到一半被杀」: 只写前 60% ——
	var w := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	w.store_string(whole.substr(0, int(whole.length() * 0.6)))
	w.close()
	print("  [探针] 残档 %d 字节(写了 60%%)" % int(whole.length() * 0.6))

	## —— 重新读档(模拟下次启动) ——
	gs.season_total_battles = -1
	gs.season_wins = -1
	gs.meta_deepsea_coins = -1
	gs._load()
	print("  [探针] 残档读回来: 场次=%d 胜场=%d 深海币=%d" % [
		int(gs.season_total_battles), int(gs.season_wins), int(gs.meta_deepsea_coins)])
	if int(gs.season_total_battles) == -1:
		print("  ⇒ ★★★一个字段都没读回来 —— 下次启动就是**全新档**, 一周进度没了, 而且一声不吭")
	elif int(gs.season_total_battles) == 16:
		print("  ⇒ ✅ 回落到 .bak(上一次的完整档): 只丢最后一次存档之后的那点进度, 不是全丢")
	else:
		print("  ⇒ 读回来了: 场次 %d" % int(gs.season_total_battles))
	## 有没有备份可用?
	var bak_ok: bool = FileAccess.file_exists(SAVE_PATH + ".bak")
	print("  [探针] 有没有 .bak 兜底: %s" % str(bak_ok))
	## —— 再写一次(模拟正常存档), 看 .tmp 有没有留在盘上(留着 = 下次启动可能读到它) ——
	gs.save()
	print("  [探针] 存完之后 .tmp 还在吗: %s (应为 false)" % str(FileAccess.file_exists(SAVE_PATH + ".tmp")))
	get_tree().quit(0)
