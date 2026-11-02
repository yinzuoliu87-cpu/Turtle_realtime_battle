extends Node
## 探针: **赛程条七天各说什么**。玩家每天开游戏第一眼读的就是它。
## ★全仓 `strip_now_override` 只有 1 处引用, 还在截图脚本里 ⇒ **没有任何门禁扫过七天**,
##   而「判据挂在星期几上」本仓已栽过五次。
const SUN0 := 1789862400
const DAY := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]


func _texts(n: Node) -> Array:
	var out: Array = []
	var st: Array = [n]
	while not st.is_empty():
		var c = st.pop_back()
		if c is Label and str((c as Label).text).strip_edges() != "":
			out.append(str((c as Label).text).replace("\n", " / "))
		for ch in c.get_children():
			st.append(ch)
	return out


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.season_total_battles = 5
		gs.ranked_used = 5
		gs.hearts = 3
		gs.promoted = false
	await get_tree().process_frame
	var packed = load("res://scenes/MainMenu.tscn")
	for d in range(7):
		var mm = packed.instantiate()
		mm.strip_now_override = SUN0 + d * 86400 + 12 * 3600
		mm.clock_override_ts = SUN0 + d * 86400 + 12 * 3600
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame
		var ts: Array = _texts(mm)
		## 只打含「周/赛/配额/场」的那几行 —— 其余是按钮名
		var keep: Array = []
		for t in ts:
			var s := str(t)
			if s.find("周") >= 0 or s.find("赛") >= 0 or s.find("配额") >= 0 or s.find("场") >= 0:
				keep.append(s.substr(0, 46))
		## 只数**相位格**(休赛/积分赛/闯关赛/决赛日), 不含提示行与资源行
		var cells: Array = []
		for t2 in ts:
			var s2 := str(t2)
			for nm in ["休赛", "积分赛", "闯关赛", "决赛日"]:
				if s2 == nm or s2 == nm + " 今":
					cells.append(s2)
					break
		print("── %s ── 相位格 %d 个: %s" % [DAY[d], cells.size(), str(cells)])
		if cells.size() != 7:
			## 格数不对 ⇒ 把每个相位标签的位置和父链打出来, 认出多的那个是谁
			var st3: Array = [mm]
			while not st3.is_empty():
				var c3 = st3.pop_back()
				if c3 is Label:
					var t3 := str((c3 as Label).text)
					if t3 == "休赛" or t3 == "休赛 今" or t3.begins_with("休赛"):
						var par := ""
						var p3 = c3.get_parent()
						for _k in range(3):
							if p3 == null:
								break
							par += p3.get_class() + "/"
							p3 = p3.get_parent()
						print("       [%s] pos=%s  父链=%s" % [t3.substr(0, 20), str((c3 as Label).get_global_rect().position), par])
				for ch3 in c3.get_children():
					st3.append(ch3)
		for k in keep:
			if k.find("大轮") < 0:
				print("     " + str(k))
		mm.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
