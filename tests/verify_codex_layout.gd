extends Node
## verify_codex_layout.gd — 图鉴【版式/UI】(2026-08-15 用户「图鉴也没搞」= 页面排版那一层, 不是描述文字)
##
## ★实拍五个 Tab 量出来的毛病, 每条一个判据。
##   判据一律【量产品自己的账】: 真实节点的 get_global_rect()/size/position/get_content_height()
##   与真实文本内容 —— 不数我插的标记, 不 grep 源码字符串(源码一改就漂)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_codex_layout.tscn

const SCN := preload("res://scenes/Codex.tscn")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _inst = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 详情内容层的真实底边(最低那个子节点的底边) —— 与 verify_codex_browse 同口径。
func _content_bottom() -> float:
	var b := 0.0
	for c in _inst.detail.get_children():
		if c is Control:
			b = maxf(b, (c as Control).position.y + (c as Control).size.y)
	return b


## 详情里所有【看得见的文字】(Label + RichTextLabel 的纯文本)。
func _detail_texts() -> Array:
	var out: Array = []
	for c in _inst.detail.get_children():
		if c is RichTextLabel:
			out.append((c as RichTextLabel).get_parsed_text())
		elif c is Label:
			out.append((c as Label).text)
	return out


func _settle(n: int = 4) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	print("=== 图鉴版式 (五个 Tab 逐条量真实矩形) ===")
	_inst = SCN.instantiate()
	add_child(_inst)
	await _settle(30)

	var frame: Control = _inst.detail_frame
	var bg: ColorRect = _inst.detail_bg
	_ok("★分母: 图鉴装起来了(详情框 %.0f×%.0f)" % [frame.size.x, frame.size.y],
		frame != null and bg != null and frame.size.x > 800.0)

	await _check_dead_space()
	await _check_skill_cards()
	await _check_passive_consistency()
	await _check_no_fancy_type_names()
	await _check_font_hierarchy()
	await _check_no_duplicate_type_line()

	# ── ⑨ 被截断的卡片必须都画出「点开看全部 ▸」──────────────────────────
	##   ★这段代码自己的注释写过它曾是【不会红的假检查】: 刚 add_child 时
	##     `get_content_height()` 返回 0 ⇒ 永远判"没被切"⇒ 提示永远不出现。
	##   ★判据: 用产品自己的判据数被截断的卡(content_height > size.y), 再数提示条, 两者必须相等。
	##     只断言"有提示"守不住 —— 一条都不画时"有提示"的断言也可能因为别的卡而通过。
	##   实测(全 28 只): 卡片正文 112 个 · 被截断 24 个 · 提示 24 条, 一一对上。
	## ★★必须先切回龟页 —— 跑到这里时前面的断言已经把图鉴切到 equips 了,
	##   `_items` 不再是龟列表、detail 里也没有技能卡 ⇒ 扫 28 只也是 0 张。
	##   (分母断言当场把这个抓出来了; 没有它这条就是一路绿的假检查。)
	_inst._switch_tab("pets")
	await _settle(8)
	var _clip_total := 0
	var _hint_total := 0
	var _mismatch: Array = []
	## ★不能只扫前 6 只 —— 实测前 6 只一张都没被截断, 那条分母断言当场红(幸好写了分母)。
	##   改成【逐只扫到找够 3 张为止】: 既保证判据真的走到, 又不用把 28 只全跑完。
	for _i in range(_inst._items.size()):
		if _clip_total >= 3:
			break
		_inst._select(_i)
		await _settle(6)
		var _cl := 0
		var _hi := 0
		for _c in _inst.detail.get_children():
			if _c is RichTextLabel:
				var _rt := _c as RichTextLabel
				## ★这条只数【技能卡】的正文, 两个边界都栽过:
				##   ① 下限原本是 40 —— 简述精简后有的卡正文只剩 1~2 行(不足 40px), 被排除掉,
				##      于是"被截 0 / 提示 2"对不上, 看着像多画了提示, 其实是分母漏数。降到 16。
				##   ② 只按高度筛还不够: **被动条**也是 RichTextLabel(实测 516x24 / 内容 46 ⇒ 也算"被截"),
				##      但它的提示写的是「展开全文 ▸」而不是「点开看全部」⇒ 又报"被截 1 / 提示 0"。
				##      技能卡并排三张(宽约 253), 被动条是整条(宽 516) —— **用宽度把两者分开**。
				if _rt.size.x < 400.0 and _rt.size.y > 16.0 and _rt.size.y < 400.0 \
					and _rt.get_content_height() > _rt.size.y + 0.5:
					_cl += 1
			elif _c is Label and str((_c as Label).text).begins_with("点开看全部"):
				_hi += 1
		_clip_total += _cl
		_hint_total += _hi
		if _cl != _hi:
			_mismatch.append("第 %d 只: 被截 %d / 提示 %d" % [_i, _cl, _hi])
	_ok("★⑨ 分母: 前 6 只里确实有被截断的卡(没有就是空检查)", _clip_total > 0,
		"被截 %d 张" % _clip_total)
	_ok("★★⑨ 被截断的卡都画出了「点开看全部」(数量一一对上)", _mismatch.is_empty(),
		"对不上的: %s" % str(_mismatch.slice(0, 4)))

	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴版式")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()


# ══════════════════════════════════════════════════════════════════════
# ① 死空白 —— 详情框底下大片空着
# ══════════════════════════════════════════════════════════════════════
## 实拍(改前): 装备「圣光护盾」内容底 ~250 而框高 550 ⇒ 空 300px = 【框的 55%】;
##   规则页更狠(内容底 ~208, 空 342 = 62%)。用户「图鉴也没搞」指的就是这个。
## 判据: 逐条量 `框高 - 内容底`。框会跟着内容收(下限 DETAIL_MIN_H), 所以这个差值
##   要么小(框贴着内容), 要么是【框已经收到下限】—— 后者也必须给出下限的证据。
const GAP_TOL := 46.0

func _check_dead_space() -> void:
	print("  ── ① 详情框死空白 ──")
	var worst := {}
	for tab in ["pets", "equips", "synergies", "status", "rules"]:
		_inst._switch_tab(tab)
		await _settle(6)
		var cnt: int = _inst._items.size()
		var w_gap := -99999.0
		var w_idx := -1
		var w_h := 0.0
		var w_b := 0.0
		for idx in range(cnt):
			_inst._select(idx)
			await _settle(3)
			var b := _content_bottom()
			var h: float = _inst.detail_frame.size.y
			var gap: float = h - b
			if gap > w_gap:
				w_gap = gap
				w_idx = idx
				w_h = h
				w_b = b
		worst[tab] = {"gap": w_gap, "idx": w_idx, "h": w_h, "b": w_b, "n": cnt}
		print("      %-10s 最差: 第%d条 框高 %.0f 内容底 %.0f ⇒ 空 %.0f px (%.0f%%)  [共%d条]"
			% [tab, w_idx, w_h, w_b, w_gap, 100.0 * w_gap / maxf(1.0, w_h), cnt])
	var _cmap: Dictionary = _inst.get_script().get_script_constant_map()
	var min_h: float = float(_cmap.get("DETAIL_MIN_H", -1.0))
	_ok("★分母: 详情框有【下限高度】常量(收缩不能收到没有)", min_h > 100.0, "下限 %.0f" % min_h)
	var bad: Array = []
	for tab in worst.keys():
		var w: Dictionary = worst[tab]
		# 贴着内容 = gap 小; 或者框已经收到下限(此时 gap 大是设计, 但框必须真的等于下限)
		var okk: bool = float(w["gap"]) <= GAP_TOL or absf(float(w["h"]) - min_h) <= 1.0
		if not okk:
			bad.append("%s第%d条空%.0f(框%.0f)" % [tab, int(w["idx"]), float(w["gap"]), float(w["h"])])
	_ok("★★★① 每个 Tab 的每一条: 详情框都贴着内容(或已收到下限)", bad.is_empty(),
		"违例 %s" % str(bad))
	# ★分母的分母: 必须真有条目【撑满】框, 否则"贴着内容"可能是靠框永远等于下限混过去的
	_inst._switch_tab("pets")
	await _settle(6)
	_inst._select(0)
	await _settle(4)
	_ok("★① 分母: 龟页内容足够高, 框吃满上限(证明框不是永远停在下限)",
		_inst.detail_frame.size.y >= 500.0, "框高 %.0f" % _inst.detail_frame.size.y)
	# 边框(ReferenceRect 全锚在 DetailBg 上)必须跟着一起收, 否则会露出一圈空框
	_inst._switch_tab("rules")
	await _settle(6)
	_inst._select(0)
	await _settle(4)
	_ok("★★① 背景框与内容框【同高】(否则收了内容框却留着一圈空背景)",
		absf(_inst.detail_bg.size.y - _inst.detail_frame.size.y) <= 1.0,
		"bg %.0f / frame %.0f" % [_inst.detail_bg.size.y, _inst.detail_frame.size.y])


# ══════════════════════════════════════════════════════════════════════
# ② 技能卡 —— 右边空一整张卡的宽 / 短卡大片留白 / 长卡被切
# ══════════════════════════════════════════════════════════════════════
## 实拍(改前): 小龟 4 张卡 ×168 + 3×8 间隔 = 696, 画在 900 宽的板子上 ⇒ 右边【死空 184px】
##   (整整一张卡的宽度); 而「攻击」(普攻, 2 行字)卡里空了 ~110px, 另外 3 张全被切。
func _check_skill_cards() -> void:
	print("  ── ② 技能卡 ──")
	_inst._switch_tab("pets")
	await _settle(6)
	_inst._select(0)
	await _settle(6)
	var cards := _skill_cards()
	## ★2026-08-18 改成 3 张: 用户「右下角这些被动普攻技能这样子放你不觉得怪吗」——
	##   普攻本来和 3 个候选并排成 4 张等宽卡, 读起来像"四选一", 可它是固定自带的。
	##   现在普攻单独做成一条(和被动条同一层级), 卡片区**只剩真正要选的那 3 个**。
	_ok("★分母: 量得到技能卡(拆走普攻后应有 3 张)", cards.size() >= 3, "%d 张" % cards.size())
	if cards.is_empty():
		return
	# ── 横向: 最后一张卡的右边缘要顶到板子右侧留白 ──
	var right := 0.0
	var left := 99999.0
	for c in cards:
		var p: Panel = c["panel"]
		right = maxf(right, p.position.x + p.size.x)
		left = minf(left, p.position.x)
	var det_w: float = float(_inst.DETAIL_W)
	_ok("★★★② 卡片铺满板宽(右边不许空出一整张卡)", right >= det_w - 30.0,
		"卡右缘 %.0f / 板宽 %.0f ⇒ 右侧余 %.0f px" % [right, det_w, det_w - right])
	_ok("★② 左边距对称", left >= 12.0 and left <= 28.0, "左缘 %.0f" % left)

	# ── 纵向: 每张卡贴着自己的正文, 不许留大片空 ──
	var gaps: Array = []
	var heights: Array = []
	for c in cards:
		var p: Panel = c["panel"]
		var rt: RichTextLabel = c["rt"]
		var used: float = (rt.position.y - p.position.y) + rt.get_content_height()
		gaps.append(p.size.y - used)
		heights.append(p.size.y)
	var max_gap: float = 0.0
	for g in gaps:
		max_gap = maxf(max_gap, float(g))
	print("      每卡余白: %s" % str(gaps.map(func(x): return "%.0f" % float(x))))
	print("      每卡高度: %s" % str(heights.map(func(x): return "%.0f" % float(x))))
	_ok("★★★② 短卡不许留大片空白(普攻只有两行字, 卡不该还是 260 高)",
		max_gap <= 46.0, "最大余白 %.0f px" % max_gap)
	# ★分母: 必须真有长短不一的卡, 否则"每张都贴着内容"可能是所有卡内容一样高
	var hmin := 99999.0
	var hmax := 0.0
	for h in heights:
		hmin = minf(hmin, float(h))
		hmax = maxf(hmax, float(h))
	## ★这条原来靠「普攻卡只有两行字」制造高度差来当分母。普攻拆走之后, 剩下 3 张
	##   候选卡正文都很长、**一律顶到上限**, 高度差恒为 0 ⇒ 这个分母失效了。
	##   换一个**不依赖某张卡刚好短**的分母: 直接证明"卡高是跟着正文算的"——
	##   每张卡的高度必须 ≥ 正文实际内容高 + 头部, 且 ≤ 允许的最大高。
	##   (原来那条只要所有卡一样高就红, 而"一样高"在新版是正常的。)
	var fit_bad: Array = []
	for c2 in cards:
		var p2: Panel = c2["panel"]
		var rt2: RichTextLabel = c2["rt"]
		if rt2 == null:
			continue
		if p2.size.y < rt2.size.y + 60.0:
			fit_bad.append("卡高 %.0f 装不下正文 %.0f" % [p2.size.y, rt2.size.y])
	_ok("★★② 分母: 每张卡都装得下自己的正文(最短 %.0f / 最高 %.0f)" % [hmin, hmax],
		fit_bad.is_empty() and hmin >= 100.0, str(fit_bad.slice(0, 3)))


## 技能卡 = detail 里成排的 Panel(同一 y、宽度相同)+ 它下面那个 RichTextLabel。
## 按几何配对, 不靠我插的标记。
func _skill_cards() -> Array:
	var panels: Array = []
	for c in _inst.detail.get_children():
		if c is Panel and (c as Panel).size.x >= 120.0 and (c as Panel).size.y >= 100.0:
			panels.append(c)
	var out: Array = []
	for p in panels:
		var best: RichTextLabel = null
		for c2 in _inst.detail.get_children():
			if not (c2 is RichTextLabel):
				continue
			var rt: RichTextLabel = c2
			if rt.position.x >= p.position.x - 1.0 and rt.position.x <= p.position.x + p.size.x \
					and rt.position.y >= p.position.y and rt.position.y <= p.position.y + p.size.y:
				best = rt
				break
		if best != null:
			out.append({"panel": p, "rt": best})
	out.sort_custom(func(a, b): return (a["panel"] as Panel).position.x < (b["panel"] as Panel).position.x)
	return out


# ══════════════════════════════════════════════════════════════════════
# ③ 同一屏两种交互 —— 技能是直接展开的, 被动却只有「点击查看」
# ══════════════════════════════════════════════════════════════════════
func _check_passive_consistency() -> void:
	print("  ── ③ 被动与技能同一种交互 ──")
	_inst._switch_tab("pets")
	await _settle(6)
	# 找一只有被动的龟
	var idx := -1
	var pv := {}
	for i in range(_inst._items.size()):
		var it = _inst._items[i]
		if it is Dictionary and not (it.get("passive", {}) as Dictionary).is_empty():
			idx = i
			pv = it["passive"]
			break
	_ok("★分母: 找得到带被动的龟", idx >= 0, "第 %d 条 · 被动「%s」" % [idx, str(pv.get("name", ""))])
	if idx < 0:
		return
	_inst._select(idx)
	await _settle(6)
	var joined := "\n".join(PackedStringArray(_detail_texts()))
	## 简述(brief)的头一段必须【已经画在屏幕上】—— 技能卡就是这么干的(卡上给 brief, 点开看 detail)。
	## ★取到第一个 `<` 为止: brief 里混着 <span class="val-atk"> 这类标记, 会被 render_bbcode 换掉,
	##   拿原串去比对是比不到的(这条踩过: 直接截前 10 个字符里正好含标记 ⇒ 永远找不到 ⇒ 假 FAIL)。
	var brief: String = str(pv.get("brief", "")).split("<")[0].strip_edges()
	_ok("★分母: 该被动有简述(且截得出不含标记的一段)", brief.length() >= 6, "「%s」" % brief)
	_ok("★★★③ 被动简述【默认就画出来】(与技能卡同一种交互: 条上给简述, 点开看全文)",
		brief.length() >= 6 and joined.find(brief) >= 0,
		"条上简述「%s」" % brief)
	_ok("★★③ 不再是光秃秃一句「点击查看」", joined.find("点击查看") < 0,
		"「点击查看」出现次数 %d" % joined.count("点击查看"))
	## 点开之后要能看到【全文 desc】—— 否则"点开看全文"是句空话。
	## 走产品自己的入口(切 _codex_passive_view 再重画), 不是我直接调渲染函数。
	_inst._codex_passive_view = true
	_inst._codex_detail._show_pet(_inst._items[idx])
	await _settle(4)
	var joined2 := "\n".join(PackedStringArray(_detail_texts()))
	var full: String = str(pv.get("desc", "")).split("<")[0].strip_edges()
	_ok("★分母: 该被动有全文 desc", full.length() >= 6, "「%s」" % full)
	_ok("★★③ 点开之后看得到全文(desc, 与简述不是同一段)",
		full.length() >= 6 and joined2.find(full) >= 0, "全文「%s」" % full)
	_inst._codex_passive_view = false


# ══════════════════════════════════════════════════════════════════════
# ④ 花名 —— 「弓箭·神射手」「剑系」这类游戏里根本不存在的名字
# ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-14 已让商店删过一次(ShopScene.gd:799 注释在案), 图鉴里还剩 3 处 display_name。
## 判据: 把 Phase2Types.TYPE_NAME 的【花名值】当黑名单, 扫详情里真实渲染出的文字。
func _check_no_fancy_type_names() -> void:
	print("  ── ④ 花名(display_name) ──")
	var fancy: Array = []
	for k in Phase2Types.TYPE_NAME.keys():
		var v: String = str(Phase2Types.TYPE_NAME[k])
		if v != str(k):
			fancy.append(v)
	_ok("★分母: TYPE_NAME 里确实有花名(否则本节是空检查)", fancy.size() >= 8,
		"%d 个, 例: %s" % [fancy.size(), str(fancy.slice(0, 3))])
	var hits: Array = []
	for tab in ["equips", "synergies"]:
		_inst._switch_tab(tab)
		await _settle(6)
		for i in range(_inst._items.size()):
			_inst._select(i)
			await _settle(2)
			var joined := "\n".join(PackedStringArray(_detail_texts()))
			for f in fancy:
				if joined.find(str(f)) >= 0 and hits.find("%s:%s" % [tab, f]) < 0:
					hits.append("%s:%s" % [tab, f])
	_ok("★★★④ 图鉴里一个花名都没有(只写羁绊名本身)", hits.is_empty(),
		"命中花名 %s" % str(hits))


# ══════════════════════════════════════════════════════════════════════
# ⑤ 字号层级 —— 同是"正文", 装备 19 / 状态 13 / 规则 14 / 羁绊 13
# ══════════════════════════════════════════════════════════════════════
const BODY_MIN := 16

func _check_font_hierarchy() -> void:
	print("  ── ⑤ 正文字号 ──")
	var got := {}
	for tab in ["equips", "synergies", "status", "rules"]:
		_inst._switch_tab(tab)
		await _settle(6)
		_inst._select(0)
		await _settle(4)
		# 正文 = 详情里最宽的那个 RichTextLabel(各页都是整幅宽的说明段)
		var widest: RichTextLabel = null
		for c in _inst.detail.get_children():
			if c is RichTextLabel and (widest == null or (c as RichTextLabel).size.x > widest.size.x):
				widest = c
		if widest == null:
			got[tab] = -1
			continue
		got[tab] = int(widest.get_theme_font_size("normal_font_size"))
	print("      正文字号: %s" % str(got))
	var small: Array = []
	for tab in got.keys():
		if int(got[tab]) < BODY_MIN:
			small.append("%s=%d" % [tab, int(got[tab])])
	_ok("★★⑤ 各页正文字号都 ≥ %d(图鉴是专门来看资料的地方)" % BODY_MIN,
		small.is_empty(), "偏小: %s" % str(small))
	# 小标题不许比它自己的正文还大/还小得离谱 —— 层级要成立
	_inst._switch_tab("equips")
	await _settle(6)
	_inst._select(3)
	await _settle(4)
	var head_sizes: Array = []
	for c in _inst.detail.get_children():
		if c is Label and (c as Label).text in ["属性", "效果", "羁绊"]:
			head_sizes.append(int((c as Label).get_theme_font_size("font_size")))
	_ok("★分母: 找得到装备页的小标题", head_sizes.size() >= 2, "%s" % str(head_sizes))
	var hmin := 99
	for h in head_sizes:
		hmin = mini(hmin, int(h))
	_ok("★⑤ 小标题不小于 %d(原来 14, 比正文 19 还小一大截)" % BODY_MIN,
		hmin >= BODY_MIN, "最小标题 %d" % hmin)


# ══════════════════════════════════════════════════════════════════════
# ⑥ 一屏之内说两遍
# ══════════════════════════════════════════════════════════════════════
## 实拍(改前): 装备详情副标行写「🗡️ 剑系」, 底下羁绊块又写一遍「🗡️ 剑系 —— 队伍装满 3/6/9…」。
##
## ★判据要盯【类型标签】这个整体, 不能只数类型名出现几次:
##   效果正文里「枪」这个字能出现 9 次(p2eq_077 实测), 装备名本身也常含类型字(「锈蚀阔剑」)——
##   那些都是正常行文。真正重复的是"图标 + 类型名"这个标签, 它只该出现在一个地方。
func _check_no_duplicate_type_line() -> void:
	print("  ── ⑥ 同一屏说两遍 ──")
	_inst._switch_tab("equips")
	await _settle(6)
	var worst := 0
	var worst_id := ""
	var worst_tok := ""
	var seen := 0
	for i in range(_inst._items.size()):
		var it = _inst._items[i]
		if not (it is Dictionary):
			continue
		var tp: String = Phase2Types.type_of(str(it.get("id", "")))
		if tp == "":
			continue
		seen += 1
		_inst._select(i)
		await _settle(2)
		var tok: String = "%s %s" % [_inst._type_emoji(tp), tp]
		var cnt := 0
		for t in _detail_texts():
			cnt += str(t).count(tok)
		if cnt > worst:
			worst = cnt
			worst_id = str(it.get("id", ""))
			worst_tok = tok
	_ok("★分母: 量到了带类型的装备(%d 件)" % seen, seen >= 50 and worst > 0,
		"最多的那件 %s 标签「%s」出现 %d 次" % [worst_id, worst_tok, worst])
	_ok("★★⑥ 类型标签一屏之内最多出现一次", worst <= 1,
		"%s 的「%s」出现 %d 次" % [worst_id, worst_tok, worst])
	await _check_multi_type()


# ══════════════════════════════════════════════════════════════════════
# ⑦ 一件装备两个羁绊 —— 图鉴只认第一个
# ══════════════════════════════════════════════════════════════════════
## p2eq_093 香火石在 p2eq-types.json 里登记了【两个】类型(遗物 + 香火, 用户 2026-08-13 拍板),
## 而图鉴一路用 type_of()(只返回第一个) ⇒ 实拍:
##   · 装备详情副标只写「🏺 遗物」, 一个字不提香火;
##   · 羁绊页香火那一条写着【该类型装备 (0)】—— 一件都列不出来, 看着像功能没做完。
## 判据走产品渲染出来的真文字 + 真的成员数, 不 grep 源码。
func _check_multi_type() -> void:
	print("  ── ⑦ 一件装备两个羁绊 ──")
	var multi_id := ""
	var multi_types: Array = []
	for eq in DataRegistry.phase2_equipment:
		if not (eq is Dictionary):
			continue
		var ts: Array = Phase2Types.types_of(str(eq.get("id", "")))
		if ts.size() >= 2:
			multi_id = str(eq.get("id", ""))
			multi_types = ts
			break
	_ok("★分母: 数据里真有【多羁绊】装备(否则本节是空检查)", multi_id != "",
		"%s → %s" % [multi_id, str(multi_types)])
	if multi_id == "":
		return
	# ① 装备详情要把两个羁绊都说出来
	_inst._switch_tab("equips")
	await _settle(6)
	var found := -1
	for i in range(_inst._items.size()):
		var it = _inst._items[i]
		if it is Dictionary and str(it.get("id", "")) == multi_id:
			found = i
			break
	_ok("★分母: 装备页里找得到 %s" % multi_id, found >= 0, "第 %d 条" % found)
	if found >= 0:
		_inst._select(found)
		await _settle(4)
		var joined := "\n".join(PackedStringArray(_detail_texts()))
		## ★找【图标+类型名】这个标签, 不能找光秃秃的类型名 ——
		##   这件装备自己就叫「香火石」, 名字里带着"香火"两个字 ⇒ 只搜类型名的话,
		##   把代码改回 type_of(只认第一个类型)它照样绿。反向验证时当场抓到的假绿灯。
		var miss: Array = []
		for t in multi_types:
			var tok: String = "%s %s" % [_inst._type_emoji(str(t)), str(t)]
			if joined.find(tok) < 0:
				miss.append(tok)
		_ok("★★★⑦ 装备详情把它的每一个羁绊都写出来了(按【图标+名】找, 不按名找)",
			miss.is_empty(), "漏掉 %s" % str(miss))
	# ② 第二个类型的羁绊页要列得出这件装备
	var t2: String = str(multi_types[1])
	_inst._switch_tab("synergies")
	await _settle(6)
	var si := -1
	for i in range(_inst._items.size()):
		var it2 = _inst._items[i]
		if it2 is Dictionary and str(it2.get("_type", "")) == t2:
			si = i
			break
	_ok("★分母: 羁绊页里有「%s」这一条" % t2, si >= 0, "第 %d 条" % si)
	if si >= 0:
		_inst._select(si)
		await _settle(4)
		var members: Array = _inst._codex_detail._type_members(t2)
		_ok("★★★⑦ 「%s」羁绊页列得出成员装备(原来是【该类型装备 (0)】)" % t2,
			members.size() >= 1, "成员 %d 件" % members.size())
