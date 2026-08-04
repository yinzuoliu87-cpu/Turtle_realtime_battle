extends Node
## verify_synergy_popup.gd — 背包·羁绊详情弹框【每一档都画得出、且文案没被吃掉】（2026-08-04）
##
## ★为什么要有它：逐类型评审（v0.19.4~v0.19.11）之后，探针一量发现弹框是**坏的**，
##   而且是"不报错、不留痕、玩家只是看不到"的那种坏：
##   ① `for ti in [1, 2, 3]` —— **档数写死成 3**。而奇械/法器/灵物/遗物是 `[2,5,8,10]` 四档
##      ⇒ **这四个类型的顶档在背包里根本不画**（图鉴那边正常，所以更难发现）。
##   ② 每档一个**固定 66px** 的 Label（620 宽 · 14 号字 ≈ 3 行 ≈ 120 字），
##      而评审后盾档1 有 209 字、弓箭三档 189/163/164 …
##      ⇒ **10 个类型里 6 个的文案被截断**。
##
## ★判据是「量真实渲染出来的东西」，不是「量我自己写进去的数」——
##   memory [[fb-write-without-reader-and-fake-gates]]：门禁模拟公式 ≠ 量真实对象。
##   所以这里真的 `_show_synergy_popup()` 建出节点，再从节点树上读回 bbcode 与几何。
##
## 守五组：
##   ① ★分母：十个类型全都弹得出框（不是只测一个）
##   ② ★每个类型的**每一档**都出现在弹框文本里（写死 3 档时四个类型立刻红）
##   ③ 文案**逐字完整**（不截断）—— 用 `TIER_DESCS` 原文去弹框文本里找
##   ④ 弹框不出设计框（1280×720）边界，且正文区高度 > 0
##   ⑤ 正文控件必须**能滚动**（`scroll_active`）—— 内容比框高时不滚就是又一次截断
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_synergy_popup.tscn

const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const InvScene := preload("res://scripts/scenes/InventoryScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 背包·羁绊详情弹框 ===")
	var host = InvScene.new()
	add_child(host)
	await get_tree().process_frame
	await get_tree().process_frame

	var built := 0
	var miss_tier: Array = []      # 某一档整段没出现在弹框里
	var truncated: Array = []      # 文案没逐字出现（被截断/被改写）
	var geo_bad: Array = []
	var box_h: Dictionary = {}     # 类型 → 弹框高度（验"框高真的随内容变"）
	var no_scroll: Array = []
	var total_tiers := 0

	for t in Phase2Types.TYPES:
		var tname: String = str(t)
		var descs: Array = Phase2Types.TIER_DESCS.get(tname, [])
		if descs.is_empty():
			continue
		# 真的建一次弹框（当前档取 1）
		host._inv_synergy._show_synergy_popup(tname, 1)
		await get_tree().process_frame
		var rt: RichTextLabel = _find_rt(host)
		var box: Panel = _find_box(host)
		if rt == null or box == null:
			geo_bad.append("%s 没建出弹框" % tname)
			_clear(host)
			continue
		built += 1
		var body: String = rt.get_parsed_text()          # ★读【渲染后】的纯文本, 不是我塞进去的 bbcode
		for i in range(descs.size()):
			var d: String = str(descs[i])
			if d.strip_edges() == "":
				continue
			total_tiers += 1
			if body.find(d) < 0:
				# 分清是"整档没画"还是"画了但被吃掉"：拿前 20 字再找一次
				if body.find(d.substr(0, 20)) < 0:
					miss_tier.append("%s 档%d 【整段没出现】" % [tname, i + 1])
				else:
					truncated.append("%s 档%d 出现了但不完整(%d 字)" % [tname, i + 1, d.length()])
		# 几何：不出设计框、正文区有高度
		if box.position.y < 0.0 or box.position.y + box.size.y > InvScene.H + 0.5:
			geo_bad.append("%s 弹框出界 y=%.0f h=%.0f (设计框高 %.0f)"
				% [tname, box.position.y, box.size.y, InvScene.H])
		if rt.size.y <= 20.0:
			geo_bad.append("%s 正文区高度只有 %.0f" % [tname, rt.size.y])
		if not rt.scroll_active:
			no_scroll.append(tname)
		box_h[tname] = box.size.y
		_clear(host)

	_ok("① ★分母: 十个类型全都弹得出框(建出 %d 个)" % built, built == 10, "只建出 %d 个" % built)
	_ok("① ★分母: 逐条比对了 %d 档文案" % total_tiers, total_tiers >= 30, "只比到 %d 档" % total_tiers)
	_ok("② ★每个类型的【每一档】都画得出来(档数写死成 3 时, 四个四档类型立刻红)",
		miss_tier.is_empty(), "%d 条: %s" % [miss_tier.size(), str(miss_tier.slice(0, 6))])
	_ok("③ ★文案逐字完整, 没有被框高吃掉",
		truncated.is_empty(), "%d 条: %s" % [truncated.size(), str(truncated.slice(0, 6))])
	_ok("④ 弹框不出设计框边界, 正文区有高度", geo_bad.is_empty(), str(geo_bad.slice(0, 4)))
	_ok("⑤ ★正文可滚动(内容比框高时不滚就是又一次截断)", no_scroll.is_empty(), str(no_scroll))
	# ⑥ ★框高真的【随内容变】。变异测出来的缺口: 把 bh 写回固定 320 时上面五条全绿 ——
	#   因为开了滚动, 固定矮框"能看全, 只是要一直滚"。那不是坏, 但也不是我声称做到的事;
	#   声称了就要守。判据: 文案最长的类型, 框比最短的类型【明显高】。
	var hs: Array = box_h.values()
	hs.sort()
	var span: float = (float(hs[hs.size() - 1]) - float(hs[0])) if hs.size() >= 2 else 0.0
	_ok("⑥ ★框高随内容变(最高 %.0f vs 最矮 %.0f, 差 %.0f)"
		% [float(hs[hs.size() - 1]) if hs.size() > 0 else 0.0, float(hs[0]) if hs.size() > 0 else 0.0, span],
		span >= 60.0, "只差 %.0f —— 框高多半是写死的" % span)

	# ★反向自证：最长的那条文案确实超过"一个固定 66px Label"能装的量 ——
	#   否则这条门禁在未来文案变短后会退化成恒真式。
	var longest := 0
	for t2 in Phase2Types.TIER_DESCS:
		for d2 in Phase2Types.TIER_DESCS[t2]:
			longest = maxi(longest, str(d2).length())
	_ok("★自证: 最长文案 %d 字, 确实超过旧的固定 66px Label(约 120 字)" % longest, longest > 120,
		"最长才 %d 字 —— 这条门禁已退化成恒真式, 需要换判据" % longest)

	host.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 羁绊弹框" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _find_rt(n: Node) -> RichTextLabel:
	for c in n.get_children():
		if c is RichTextLabel:
			return c
		var r := _find_rt(c)
		if r != null:
			return r
	return null


func _find_box(n: Node) -> Panel:
	for c in n.get_children():
		if c is ColorRect:
			for d in c.get_children():
				if d is Panel:
					return d
	return null


## 关掉弹框（点暗幕那条路）
func _clear(host) -> void:
	for c in host.get_children():
		if c is ColorRect and c.get_child_count() > 0 and c.get_child(0) is Panel:
			c.free()
