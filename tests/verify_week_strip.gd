extends Node
## verify_week_strip.gd — 赛程条**七天全量** (2026-09-27)
##
## ══════════════════════════════════════════════════════════════════════
##  为什么要这一份
## ══════════════════════════════════════════════════════════════════════
## 赛程条是**玩家每天开游戏第一眼读的那行字** —— 今天是什么日子、这周走到哪了。
## 而它的可注入时钟 `strip_now_override` **全仓只有 1 处引用, 还在截图脚本里**
## ⇒ 它的每日内容**没有任何门禁扫过**, 而本仓「判据挂在星期几上」已经栽过五次
## (v0.19.446 一轮修了四条; v0.19.458 的周日无限刷也是同一族)。
##
## ★判据不是「今天那格对不对」那一格, 而是**七天各有确定答案**:
##   一天一天列会再漏一次 —— v0.19.458 漏的就是四天名单里没有的那一天。
##
## ★★只量**条内**那 7 格(`WeekStrip` 那个容器)。2026-09-27 探针扫全屏时
##   把右侧「今天是什么日子」指示块的标签也数了进来, 凭空多出一格
##   (x=812 vs 条内 x=126) ⇒ **判据宽一格就会造出假 bug**。
##   名字只用来定位, 判据仍是**相位序列**(与 `phase_of_weekday` 这个唯一出处比)。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400          # 2026-09-20 周日 00:00 UTC
## 星期几短名 —— 与产品 `MainMenuScene._WD_CN` 同形。日格靠它认。
const WD_CN := ["一", "二", "三", "四", "五", "六", "日"]
const WD_LONG := ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

var _pass := 0
var _fail := 0


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [nm, detail])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [nm, detail])


## 条内每一格的两行字: [星期几, 相位名(可能带「今」)]
func _cells(strip: Node) -> Array:
	var out: Array = []
	for cell in strip.get_children():
		var st: Array = [cell]
		var txt: Array = []
		while not st.is_empty():
			var n = st.pop_front()
			if n is Label and str((n as Label).text).strip_edges() != "":
				txt.append(str((n as Label).text))
			for ch in n.get_children():
				st.append(ch)
		## ★★只认**日格**: 首行是星期几短名。
		##   条里还合法地挂着一个**提示/倒计时块**(「本地 周六 00:00 收盘」+「距收盘 N 天」),
		##   它不是日格。第一版判据没分开, 七天里六天都报「8 格」——
		##   **判据宽一格就会造出假 bug**(与 2026-09-27 探针那次同一个坑)。
		if txt.size() >= 2 and WD_CN.has(str(txt[0])):
			out.append(txt)
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
	print("=== 赛程条七天全量 ===")
	var packed = load("res://scenes/MainMenu.tscn")
	_ok("★分母: 载得到 MainMenu.tscn", packed != null)
	if packed == null:
		_done()
		return

	## 唯一出处: 这一周七天各是什么相位
	var want: Array = []
	for wd in range(1, 8):
		want.append(str(P2.PHASE_LABEL.get(str(P2.phase_of_weekday(wd)), "?")))
	_ok("★分母: 七个相位名都取得到(取不到 = 下面全在比 '?')",
		not want.has("?"), str(want))

	var today_marks: Array = []
	for d in range(7):
		## d=0 是周日 ⇒ ISO 星期几 = 7; d=1..6 → 1..6
		var iso: int = 7 if d == 0 else d
		var mm = packed.instantiate()
		var ts: int = SUN0 + d * 86400 + 12 * 3600
		mm.strip_now_override = ts
		mm.clock_override_ts = ts
		add_child(mm)
		for _i in range(6):
			await get_tree().process_frame

		var box = mm.find_child("WeekStrip", true, false)
		_ok("%s ★分母: 赛程条建出来了" % WD_LONG[iso - 1], box != null)
		if box == null:
			mm.queue_free()
			await get_tree().process_frame
			continue
		var hb = null
		for c in box.get_children():
			if c is HBoxContainer:
				hb = c
				break
		_ok("%s ★分母: 条里有格子容器" % WD_LONG[iso - 1], hb != null)
		if hb == null:
			mm.queue_free()
			await get_tree().process_frame
			continue

		var cells: Array = _cells(hb)
		_ok("%s 恰好 7 格(不是 6 也不是 8)" % WD_LONG[iso - 1], cells.size() == 7,
			"实测 %d" % cells.size())

		## ① 相位序列必须与唯一出处一字不差
		var got: Array = []
		var marked := 0
		var marked_wd := -1
		for k in range(cells.size()):
			var nm: String = str((cells[k] as Array)[1])
			if nm.ends_with(" 今"):
				marked += 1
				marked_wd = k + 1
				nm = nm.substr(0, nm.length() - 2)
			got.append(nm)
		_ok("%s ★★相位序列 == `phase_of_weekday` 的答案" % WD_LONG[iso - 1],
			got == want, "实测 %s" % str(got))

		## ② 恰好一格标「今」, 且就是今天
		_ok("%s ★★★恰好一格标「今」" % WD_LONG[iso - 1], marked == 1, "标了 %d 格" % marked)
		_ok("%s ★★★标「今」的那格就是今天(第 %d 格)" % [WD_LONG[iso - 1], iso],
			marked_wd == iso, "标在第 %d 格" % marked_wd)
		today_marks.append(marked_wd)

		## ③ 星期几那一行也要对得上(格子顺序不许反)
		var wd_row: Array = []
		for k2 in range(cells.size()):
			wd_row.append(str((cells[k2] as Array)[0]))
		_ok("%s ★星期几那行是周一→周日" % WD_LONG[iso - 1], wd_row == WD_CN, str(wd_row))

		mm.queue_free()
		await get_tree().process_frame

	## ④ 七天标的格子必须各不相同 —— 全标在同一格 = 那个override根本没生效
	var uniq: Dictionary = {}
	for m in today_marks:
		uniq[int(m)] = true
	_ok("★★★七天标「今」的位置**各不相同**(全一样 = 注入时钟没生效, 上面全是恒真)",
		uniq.size() == today_marks.size() and today_marks.size() == 7,
		"七天标在 %s" % str(today_marks))
	_done()


func _done() -> void:
	print("  ★分母: 本测试共 %d 条断言" % (_pass + _fail))
	if _fail == 0:
		print("ALL PASS — 赛程条七天全量")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)
