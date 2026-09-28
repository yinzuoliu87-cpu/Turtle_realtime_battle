extends Node
## _probe_mmclock.gd — 主菜单「整屏是不是同一天」的剖面探针 (2026-09-28)
##
## 只注入 `clock_override_ts`(整屏那一条缝), **不碰** `strip_now_override`,
## 然后逐日读回三处说的是哪一天:
##   ① 状态行 L2(`_phase_status_line(_now_ts())` 的渲染结果)
##   ② 赛程条里标「今」的那一格
##   ③ 收盘块主行
## 三者说的不是同一天 = 屏幕上挂着两条时钟。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400          # 2026-09-20 周日 00:00 UTC
const WD_CN := ["一", "二", "三", "四", "五", "六", "日"]
const WD_LONG := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]


func _labels(n: Node) -> Array:
	var out: Array = []
	var st: Array = [n]
	while not st.is_empty():
		var c = st.pop_front()
		var t := ""
		if c is Label:
			t = str((c as Label).text)
		elif c is Button:
			## ★★周日那一格是 **Button**(`_finals_entry`)不是 Label ——
			##   只收 Label 的话周日收盘块永远是空, 那是假的空值不是真相。
			t = str((c as Button).text).replace("\n", " / ")
		if t.strip_edges() != "":
			## ★去重: `_place_stroked` 一行字会生出多个描边副本, 不去重的话
			##   ls[1] 拿到的还是第一行(实测), 下面就是在比一个恒等的东西。
			if not out.has(t):
				out.append(t)
		for ch in c.get_children():
			st.append(ch)
	return out


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
		gs.season_total_battles = 5
		gs.ranked_used = 5
		gs.hearts = 3
	await get_tree().process_frame
	var sys_now := int(Time.get_unix_time_from_system())
	print("=== 剖面: 只注入 clock_override_ts, 看整屏说的是不是同一天 ===")
	print("真实系统时钟 = %d  ⇒ ISO 星期几 = %d (%s)"
		% [sys_now, P2.iso_weekday_utc(sys_now), WD_LONG[P2.iso_weekday_utc(sys_now) - 1]])
	print("P2.now_override_ts = %d (分母: 0 = 缝是关的)" % int(P2.now_override_ts))
	var packed = load("res://scenes/MainMenu.tscn")
	if packed == null:
		print("载不到 MainMenu.tscn")
		get_tree().quit(1)
		return
	print("")
	print("%-6s | %-34s | %-10s | %s" % ["注入", "状态行 L2", "条上标今", "收盘块主行"])
	var bad := 0
	for d in range(7):
		var iso: int = 7 if d == 0 else d
		var ts: int = SUN0 + d * 86400 + 12 * 3600
		var mm = packed.instantiate()
		mm.clock_override_ts = ts          # ★只注这一条
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame
		var l2 := "?"
		var two = mm.find_child(mm.STATUS_TWO_LINE, true, false)
		if two != null:
			var ls: Array = _labels(two)
			if ls.size() >= 2:
				l2 = str(ls[1])
		var mark := "-"
		var head := "?"
		var box = mm.find_child("WeekStrip", true, false)
		if box != null:
			for c in box.get_children():
				if not (c is HBoxContainer):
					continue
				for cell in c.get_children():
					var txt: Array = _labels(cell)
					if txt.size() >= 2 and WD_CN.has(str(txt[0])):
						if str(txt[1]).ends_with(" 今"):
							mark = "周" + str(txt[0])
					elif txt.size() >= 1:
						head = str(txt[0])
		var want: String = str(WD_LONG[iso - 1])
		var same: bool = (mark == want)
		if not same:
			bad += 1
		print("%-6s | %-34s | %-10s | %s   %s"
			% [want, l2, mark, head, "" if same else "  ← 不是同一天"])
		mm.queue_free()
		await get_tree().process_frame
	print("")
	print("★分母: 共比对 7 天; 条上标「今」与注入日**不一致**的有 %d 天" % bad)

	## ★★分母二: **不注入**时三者都跟真实时钟走 ——
	##   不验这一条的话, 把三处全都写死成注入值也能让上面全绿。
	var mm0 = packed.instantiate()
	add_child(mm0)
	for _k in range(6):
		await get_tree().process_frame
	var sys_iso: int = P2.iso_weekday_utc(int(Time.get_unix_time_from_system()))
	var mark0 := "-"
	var box0 = mm0.find_child("WeekStrip", true, false)
	if box0 != null:
		for c0 in box0.get_children():
			if not (c0 is HBoxContainer):
				continue
			for cell0 in c0.get_children():
				var t0: Array = _labels(cell0)
				if t0.size() >= 2 and WD_CN.has(str(t0[0])) and str(t0[1]).ends_with(" 今"):
					mark0 = "周" + str(t0[0])
	print("★分母二(不注入): 真实时钟 = %s, 条上标今 = %s, 状态行 = 「%s」  %s"
		% [WD_LONG[sys_iso - 1], mark0, str(mm0._phase_status_line(mm0._now_ts())),
		   "OK" if mark0 == WD_LONG[sys_iso - 1] else "← 没跟真实时钟走"])
	mm0.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
