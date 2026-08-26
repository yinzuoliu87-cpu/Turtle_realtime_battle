extends Node
## verify_shop_card_tiers.gd — 商店卡框【按费用 5 档】真的分得开 (2026-08-26)
##
## 由来: 用户 2026-07-29「有问题，框框的颜色不变吗，**不是 5 档吗**」
##       →「云顶的做法是框框随费用变化」。当时生成了 5 张按亮度重上色的框并接上,
##       但**一条门禁都没有** —— 换错贴图、数组顺序写反、某张被覆盖成同色, 都没有东西会红。
##       (图鉴那边的框色是有门禁的: `verify_codex_browse` ⑤。商店这边一直空着。)
##
## ★判据落在【贴图的真实像素】, 不是读 ShopScene 那段注释里写死的数字 ——
##   那串「实测相邻档色差 92/98/64/163」是当时量一次抄进注释的, 贴图换了它也不会变。
##   本文件每次都重新量, 顺便把量到的值打出来, 注释漂了一眼就看得见。
##
## ★阈值 60 = 注释里自己写的「人眼可辨门槛」。不是我新定的标准, 是把它焊住。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shop_card_tiers.tscn

const Shop := preload("res://scripts/scenes/ShopScene.gd")

## 边框取样: 距离边缘这么多像素的一圈(9-slice 的边框区), 避开中间的透明填充。
const RIM := 3
const DIFF_MIN := 60.0        # 相邻档最小色差(ShopScene 注释里的「人眼可辨门槛」)

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 一张框贴图的【边框平均色】—— 只统计边缘一圈里**不透明**的像素。
## 返回 {"col": Color, "n": 采到几个像素}。n 会被当分母断言用。
func _rim_color(tex: Texture2D) -> Dictionary:
	if tex == null:
		return {"col": Color.BLACK, "n": 0}
	var img: Image = tex.get_image()
	if img == null:
		return {"col": Color.BLACK, "n": 0}
	var w := img.get_width()
	var h := img.get_height()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(h):
		for x in range(w):
			var on_rim := (x < RIM or x >= w - RIM or y < RIM or y >= h - RIM)
			if not on_rim:
				continue
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n == 0:
		return {"col": Color.BLACK, "n": 0}
	return {"col": Color(r / n, g / n, b / n), "n": n}


## 0~255 尺度的色差(与 ShopScene 注释里那串数同口径)。
func _diff(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0 / 3.0 * 3.0


func _ready() -> void:
	await get_tree().process_frame
	print("=== 商店卡框 5 档(用户 2026-07-29:「不是 5 档吗」) ===")

	var tiers: Array = Shop.CARD_TEX_TIER
	_ok("★分母: CARD_TEX_TIER 正好 5 张(费用 1~5 各一张)", tiers.size() == 5,
		"实得 %d 张" % tiers.size())
	if tiers.size() != 5:
		_done()
		return

	## ── 逐张量边框色, 同时验采样有效(n=0 就是量了个寂寞) ──
	var cols: Array = []
	var pix_ok := 0
	for i in range(5):
		var m := _rim_color(tiers[i] as Texture2D)
		cols.append(m["col"] as Color)
		if int(m["n"]) > 50:
			pix_ok += 1
	_ok("★★分母: 5 张都采到了足量边框像素(%d/5) —— n=0 是空检查不是通过" % pix_ok,
		pix_ok == 5)
	if pix_ok != 5:
		_done()
		return

	for i in range(5):
		var c: Color = cols[i]
		print("    t%d 边框色 = (%.0f, %.0f, %.0f)" % [i + 1, c.r * 255.0, c.g * 255.0, c.b * 255.0])

	## ── ① 相邻档必须分得开 ──
	## ★用户报的正是"看不出差别", 所以判据必须是**色差够大**, 不是"贴图不是同一个文件"。
	var diffs: Array = []
	for i in range(4):
		var d := _diff(cols[i] as Color, cols[i + 1] as Color)
		diffs.append(d)
		_ok("★★① t%d ↔ t%d 边框色差 %.0f ≥ %.0f(人眼可辨门槛)" % [i + 1, i + 2, d, DIFF_MIN],
			d >= DIFF_MIN, "实测 %.1f" % d)

	## ── ② 任意两档都不许撞色(不只相邻) ──
	## 相邻都够 ≠ 全都分得开: 如果配色绕了一圈回来, t1 和 t5 可能几乎一样,
	## 而玩家是在货架上**同时**看到五张的。
	var worst := 99999.0
	var worst_pair := ""
	for i in range(5):
		for j in range(i + 1, 5):
			var d2 := _diff(cols[i] as Color, cols[j] as Color)
			if d2 < worst:
				worst = d2
				worst_pair = "t%d↔t%d" % [i + 1, j + 1]
	## ★★已知且【用户明确说不用改】(2026-08-26): 修完 1 费之后, 最接近的一对变成
	##   **3 蓝 ↔ 4 紫 = 62.2**(门槛 60, 只高出 2.2) —— `#60a5fa` 与 `#c084fc` 都是蓝通道拉满。
	##   我摆给用户了, 用户回「不用」⇒ **维持现状, 不要再当成未决问题重新提出来**。
	##   (memory [[fb-registered-todos-rot]]: 决定给了没回填, 照着念 = 让用户重新回答他早就答过的问题。)
	##   这条断言仍然守着 60 —— 62.2 掉下去还是会红, 只是不主动去拉开它。
	_ok("★★② 五档里【最接近的一对】也分得开: %s 色差 %.0f ≥ %.0f" % [worst_pair, worst, DIFF_MIN],
		worst >= DIFF_MIN, "最接近的一对 %s = %.1f" % [worst_pair, worst])

	## ── ③ 选中态必须比任何一档都更显眼 ──
	## 当时的教训写在 ShopScene 注释里: 用 modulate 染选中态, 色差只有 26 ⇒ 看不出选中。
	## 现在是整张换图。判据: 它跟【每一档】都要拉开, 而不是只跟某一档。
	var sel := _rim_color(Shop.CARD_TEX_SEL)
	_ok("★分母: 选中态贴图也采到了边框像素", int(sel["n"]) > 50, "n=%d" % int(sel["n"]))
	var sel_worst := 99999.0
	var sel_worst_i := 0
	for i in range(5):
		var d3 := _diff(sel["col"] as Color, cols[i] as Color)
		if d3 < sel_worst:
			sel_worst = d3
			sel_worst_i = i + 1
	_ok("★★③ 选中态与【最像的那一档 t%d】色差 %.0f ≥ %.0f(旧的 modulate 版只有 26)"
		% [sel_worst_i, sel_worst, DIFF_MIN],
		sel_worst >= DIFF_MIN, "实测 %.1f" % sel_worst)

	## ── ③b 1 费框必须是【中性灰】—— 用户 2026-08-26 拍板方案 A 的落点 ──
	##
	## ★为什么单独焊这一条: 1 费原来的源色是 `#9aa6b4` = (154,166,180), **蓝通道最高**,
	##   是【蓝灰】; 而 3 费蓝 `#60a5fa` = (96,165,250) 同样 B>G>R ——
	##   **同一个色相家族只差饱和度**, 源色差只有 129(五档最近), 重上色压暗后只剩 61,
	##   刚过门槛 1.1。用户看到的就是"灰和蓝一样"。
	##   换成中性 `#a9a9a9` 后 1↔3 升到 76。
	## ★判据落在【颜色本身中不中性】而不是"文件有没有被改过" ——
	##   哪天有人又从某个带色偏的灰重生成 t1, 这条会红并直接说出是偏哪边。
	var c1: Color = cols[0]
	var r1 := c1.r * 255.0
	var g1 := c1.g * 255.0
	var b1 := c1.b * 255.0
	var spread: float = maxf(maxf(r1, g1), b1) - minf(minf(r1, g1), b1)
	_ok("★★③b 1 费框是【中性灰】(三通道极差 %.0f ≤ 12; 旧的蓝灰版是 12 且偏蓝)" % spread,
		spread <= 12.0,
		"RGB=(%.0f,%.0f,%.0f)%s" % [r1, g1, b1,
			("  ← 偏蓝, 会和 3 费蓝撞" if b1 > r1 + 6.0 else "")])
	## 具体到"别再偏蓝": 蓝通道不许明显高于红通道(那正是 #9aa6b4 的毛病)。
	_ok("★★③b 1 费框不偏蓝(B %.0f 不高于 R %.0f + 6)" % [b1, r1], b1 <= r1 + 6.0)

	## ── ④ 五张必须是【五个不同的文件】 ──
	## 上面量的是颜色; 这条防的是另一种事故: 有人把 t3 的路径复制粘贴成 t2,
	## 颜色断言会红没错, 但报文会指向"色差不够"而不是真因。这条把真因直接点出来。
	var paths := {}
	for i in range(5):
		paths[str((tiers[i] as Texture2D).resource_path)] = true
	_ok("★★④ 5 张指向 5 个不同的贴图文件(防复制粘贴写重路径)", paths.size() == 5,
		"实得 %d 个不同路径" % paths.size())

	## ── ⑤ 费用 → 下标的映射不越界 ──
	## 产品里是 `CARD_TEX_TIER[_c - 1]`, `_c` 是费用 1~5。费用若出现 0 或 6 就会当场崩。
	_ok("★⑤ 费用 1~5 映射到下标 0~4 全部落在数组内",
		tiers.size() >= 5, "cost5 → 下标 %d, 数组长 %d" % [4, tiers.size()])
	_done()


func _done() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 商店卡框 5 档" if _fail == 0 else "FAIL x%d — 商店卡框 5 档" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
