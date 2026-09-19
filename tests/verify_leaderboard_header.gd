extends Node
## verify_leaderboard_header — 排行榜【表头说的量】必须就是【行里画的量】。
##
## ★★为什么有它（2026-09-19，实拍巡检当场看见的）：
##   A8 改排序那轮我改了标题、改了每行文案、改了比较器，**漏了表头那一行**
##   ⇒ 屏幕上表头写着「击杀蛋数」，而数据是「0胜 · ♥5 · 0横扫」。
##   而 `verify_leaderboard_sort`（11 条）**一条都没红** —— 它只测
##   `Backend.leaderboard()` 这个函数，没有任何判据看得见 UI 上的字。
##   这就是本项目记过的「手抄的副本必然落后」：同一个概念在两处各写一遍。
##
## ★判据走**真场景实例**，读活节点的 `text`，不是在源码里找字符串：
##   源码子串匹配是假判据 —— 把 `_row_labels(...)` 整条删掉它照样绿。
##
## ★判据形状是**对账**不是"含不含某个词"：
##   三组「表头词 ↔ 行里词」逐项配对，两边都得出现；
##   外加一枚**刚好卡住那次漂移**的钉子：表头不许出现行里根本没有的旧量词。

const COLS := [
	["胜", "胜"],       # 表头写「胜」 ↔ 行里写「0胜」
	["余命", "♥"],      # 表头写「余命」 ↔ 行里用 ♥ 图标
	["横扫", "横扫"],
]
## ★过期量词：A8 之前榜是按这个排的。表头里再出现它 = 又漂了一次。
const STALE_TERMS := ["蛋数", "击杀蛋"]

var _pass := 0
var _fail := 0


func _ok(label: String, cond: bool, extra: String = "") -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s  %s" % [label, extra])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [label, extra])


func _collect_labels(n: Node, out: Array) -> void:
	if n is Label:
		out.append(n as Label)
	for c in n.get_children():
		_collect_labels(c, out)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true

	var ps: PackedScene = load("res://scenes/Leaderboard.tscn")
	_ok("① ★分母: Leaderboard.tscn 载得进来", ps != null)
	if ps == null:
		_done()
		return
	var inst: Node = ps.instantiate()
	add_child(inst)
	## ★等它自己把行画完（本屏在 `_ready` 里同步建节点，一帧足够；多等两帧保险）。
	await get_tree().process_frame
	await get_tree().process_frame

	var labels: Array = []
	_collect_labels(inst, labels)
	## ★分母：节点真建出来了。没有这一条，下面每条都会因为"一个 Label 都没有"而恒真。
	_ok("① ★分母: 屏上真的建出了 Label", labels.size() >= 5, "共 %d 个" % labels.size())

	var texts: Array = []
	for l in labels:
		texts.append(str((l as Label).text))

	## ── ② 找到表头那一格 与 数据行那一格 ─────────────────────────
	##   表头那一格 = 含「排名」的那一行里最后一格；数据行 = 含「胜」且含「横扫」的。
	var header := ""
	var row := ""
	var has_rank := false
	for s in texts:
		if str(s) == "排名":
			has_rank = true
		## ★数据行的真形状是 `"%d胜 · ♥%d · %d横扫"` —— **必含 ♥**。
		##   第一版只要求「含横扫 且 含·」, 结果把**标题**
		##   「🏆 排行榜 · 胜场 → 余命 → 横扫」拓成了数据行 ⇒ ③ 当场红。
		##   判据没卡住形状 = 被测对象不在场。
		if str(s).contains("横扫") and str(s).contains("♥"):
			if row == "":
				row = str(s)
	## 表头第三格：与「排名」「玩家」同属一行，取那一批里既不是「排名」也不是「玩家」的短串。
	for s in texts:
		var t := str(s)
		if t == "排名" or t == "玩家":
			continue
		if t.length() <= 12 and not t.contains("#") and (t.contains("胜") or t.contains("蛋")) \
				and not t.contains("♥") and not t.contains("("):
			header = t
			break

	_ok("② ★分母: 找得到表头行(有「排名」这一格)", has_rank)
	_ok("② ★分母: 找得到表头的成绩列", header != "", "实得 %s" % header)
	_ok("② ★分母: 找得到一条数据行", row != "", "实得 %s" % row)
	if header == "" or row == "":
		_done()
		return

	## ── ③ 逐项对账：表头说的三个量，行里都得真有 ──────────────
	for c in COLS:
		var h: String = str(c[0])
		var r: String = str(c[1])
		_ok("③ 表头含「%s」" % h, header.contains(h), "表头=%s" % header)
		_ok("③ 行里含「%s」(表头说的量行里真有)" % r, row.contains(r), "行=%s" % row)

	## ── ④ 钉住那次漂移：表头不许出现行里根本没有的旧量词 ──────
	for st in STALE_TERMS:
		_ok("④ ★表头不含过期量词「%s」(A8 漏改的就是这一格)" % st,
			not header.contains(st), "表头=%s" % header)

	_done()


func _done() -> void:
	var total := _pass + _fail
	if _fail == 0:
		print("ALL PASS — 排行榜表头对账 (%d/%d)" % [_pass, total])
	else:
		print("FAILED — 排行榜表头对账 (%d/%d)" % [_pass, total])
	get_tree().quit(1 if _fail > 0 else 0)
