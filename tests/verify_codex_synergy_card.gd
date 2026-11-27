extends Node
## verify_codex_synergy_card.gd — 图鉴羁绊页按云顶羁绊小卡重排 (2026-10-10)
##
## 参考 docs/plans/ref/20261006-云顶装备弹窗/3-tft手游-点羁绊弹小卡.png: 名字 → 一档一行 → 成员头像。
## 原来每一页是一堵字墙(每档 5~6 条【子机制】用「 · 」串成一行、半角标点、「同上」),
##   头顶一行与大标题重复的「装备羁绊」, 成员装备只是一列名字。判据(每个羁绊逐页走真入口):
##   ① 没有「装备羁绊」副标
##   ② (11-27 改版, 用户认了剑的「(3) 一句」版式后铺到全部羁绊; 事实源 Phase2Types.TIER_TABLE)
##      机制句逐条出现(条数 == TIER_TABLE.lines) → 每档一行「(N) 一句」(行数 == 档数, 自上而下不交叠)
##   ③ 每档那一句: 占位符全部展开(不剩 {C: / {STAT / [k]), 不写「档」「越」; 【专名】走高亮色
##   ④ 成员装备 = 图标格(数 == 该类型成员数), 排在标题下、机制句上面(不用滚), 点一下跳到那件装备的图鉴页(走真 gui_input)
## ★每条断言配分母。

const CODEX_SCN := preload("res://scenes/Codex.tscn")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

var _n := 0
var _fail := 0
var _c = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _settle(n: int = 4) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _plain(t: String) -> String:
	return RegEx.create_from_string("\\[[^\\]]*\\]").sub(t.replace("[lb]", "\u0001"), "", true).replace("\u0001", "[")


func _live() -> Array:
	var out: Array = []
	for ch in _c.detail.get_children():
		if not ch.is_queued_for_deletion():
			out.append(ch)
	return out


func _with_meta(meta: String) -> Array:
	var out: Array = []
	for ch in _live():
		if ch.has_meta(meta):
			out.append(ch)
	return out


func _click(c: Control) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = Vector2(10, 10)
		c.gui_input.emit(ev)   # 与玩家点格子同一条路(gui_input → open_equip)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 图鉴羁绊页: 一档一行 + 子机制拆行 + 成员图标格可点 ===")
	_c = CODEX_SCN.instantiate()
	add_child(_c)
	await _settle(8)
	var names: Array = Phase2Types.TYPES.keys()
	_ok("★分母: 羁绊有 ≥10 个", names.size() >= 10, "%d 个" % names.size())

	var bad_sub: Array = []
	var bad_tier: Array = []
	var bad_order: Array = []
	var bad_punct: Array = []
	var bad_key: Array = []
	var bad_member: Array = []
	var n_lines := 0
	var n_key := 0
	var n_tiles := 0
	for si in range(names.size()):
		var tname: String = str(names[si])
		_c._switch_tab("synergies")
		await _settle(2)
		var idx := -1
		for i in range(_c._items.size()):
			if str((_c._items[i] as Dictionary).get("_type", "")) == tname:
				idx = i
		if idx < 0:
			bad_tier.append("%s:不在左栏" % tname)
			continue
		_c._select(idx)
		await _settle(2)
		# ① 副标
		for ch in _live():
			if ch is Label and (ch as Label).text == "装备羁绊":
				bad_sub.append(tname)
		# ② 机制句 + 每档一行「(N) 一句」
		var tiers: Array = (Phase2Types.TYPES[tname] as Dictionary).get("tiers", [])
		var tb: Dictionary = Phase2Types.TIER_TABLE.get(tname, {})
		if tb.is_empty():
			bad_tier.append("%s:TIER_TABLE 没有它" % tname)
			continue
		var intros: Array = _with_meta("codex_syn_intro")
		if intros.size() != (tb.get("lines", []) as Array).size():
			bad_tier.append("%s:机制句 %d 条画了 %d 条" % [tname, (tb.get("lines", []) as Array).size(), intros.size()])
		var badges: Array = _with_meta("codex_syn_tier")
		var lines: Array = _with_meta("codex_syn_line")
		if badges.size() != tiers.size() or lines.size() != tiers.size():
			bad_tier.append("%s:%d档 画了 %d 个(N) / %d 句" % [tname, tiers.size(), badges.size(), lines.size()])
		var prev_bottom := -1.0
		for it in intros:
			var ip: String = _plain((it as RichTextLabel).text)
			if ip.begins_with("【"):
				n_key += 1
				if (it as RichTextLabel).text.find("[color=") != 0:
					bad_key.append("%s:%s" % [tname, ip.substr(0, 8)])
			prev_bottom = maxf(prev_bottom, (it as Control).position.y + (it as Control).get_combined_minimum_size().y)
		for ti in range(tiers.size()):
			var th: int = int(tiers[ti])
			var badge: Control = null
			for bg in badges:
				if int(bg.get_meta("codex_syn_tier")) == th:
					badge = bg
			var ln: RichTextLabel = null
			for l2 in lines:
				if int(l2.get_meta("codex_syn_line")) == th:
					ln = l2
			if badge == null or (badge as Label).text != "(%d)" % th or ln == null:
				bad_tier.append("%s:(%d) 缺" % [tname, th])
				continue
			n_lines += 1
			if ln.position.y + 2.0 < prev_bottom:
				bad_order.append("%s (%d)" % [tname, th])
			prev_bottom = ln.position.y + ln.get_combined_minimum_size().y
			var p: String = _plain(ln.text)
			for junk in ["{C:", "{STAT", "[k]", "档", "越", " · "]:
				if p.find(junk) >= 0:
					bad_punct.append("%s (%d)「%s」含「%s」" % [tname, th, p.substr(0, 12), junk])
			if not RegEx.create_from_string("[0-9]").search(p):
				bad_punct.append("%s (%d) 一个数字都没有「%s」" % [tname, th, p.substr(0, 12)])
		# ④ 成员格
		var want: Array = _c._codex_detail._type_members(tname)
		var tiles: Array = _with_meta("codex_syn_member")
		n_tiles += tiles.size()
		if tiles.size() != want.size() or want.is_empty():
			bad_member.append("%s:成员%d格%d" % [tname, want.size(), tiles.size()])
			continue
		## 11-27 稀有度框: 每格的框 == 那件装备的费用
		for ti2 in range(mini(tiles.size(), want.size())):
			if int(tiles[ti2].get_meta("codex_syn_cost", -1)) != int((want[ti2] as Dictionary).get("cost", -2)):
				bad_member.append("%s:%s 框费用 %s ≠ %s" % [tname, str((want[ti2] as Dictionary).get("id", "")), str(tiles[ti2].get_meta("codex_syn_cost", -1)), str((want[ti2] as Dictionary).get("cost", -2))])
				break
		## 11-27 同类装备按费用从低到高排(用户「按顺序就是一费、二费、三费、四费」): 格子从左到右、从上到下, 费用不降
		var prev_cost := 0
		for tl2 in tiles:
			var cc: int = int(tl2.get_meta("codex_syn_cost", 0))
			if cc < prev_cost:
				bad_member.append("%s:同类装备没按费用排(%d 排在 %d 后面)" % [tname, cc, prev_cost])
				break
			prev_cost = cc
		var first_intro: float = 99999.0
		for it2 in _with_meta("codex_syn_intro"):
			first_intro = minf(first_intro, (it2 as Control).position.y)
		for tl in tiles:
			if (tl as Control).position.y > first_intro:
				bad_member.append("%s:成员格排在机制句下面" % tname)
				break
		var eid: String = str(tiles[tiles.size() - 1].get_meta("codex_syn_member"))
		_click(tiles[tiles.size() - 1])
		await _settle(2)
		var sel = _c._items[_c._sel_idx] if _c._sel_idx >= 0 and _c._sel_idx < _c._items.size() else {}
		if _c.current_tab != "equips" or not (sel is Dictionary) or str(sel.get("id", "")) != eid:
			bad_member.append("%s:点 %s 没跳到装备页(tab=%s)" % [tname, eid, _c.current_tab])
	_ok("★★★① 没有「装备羁绊」副标", bad_sub.is_empty(), str(bad_sub))
	_ok("★分母: 量到的逐档句 ≥ 50", n_lines >= 50, "%d 句" % n_lines)
	_ok("★★★② 机制句逐条出现 + 每档一行「(N) 一句」", bad_tier.is_empty(), str(bad_tier.slice(0, 6)))
	_ok("★★② 机制句在前, 各档自上而下排, 不交叠", bad_order.is_empty(), str(bad_order.slice(0, 6)))
	_ok("★★③ 每档那一句占位符全展开、带数字、不写「档」「越」「 · 」", bad_punct.is_empty(), str(bad_punct.slice(0, 6)))
	_ok("★分母: 以【专名】开头的机制句 ≥ 25", n_key >= 25, "%d 条" % n_key)
	_ok("★★③ 【专名】走高亮色", bad_key.is_empty(), str(bad_key.slice(0, 6)))
	_ok("★分母: 成员格 ≥ 90", n_tiles >= 90, "%d 格" % n_tiles)
	_ok("★★★④ 成员是图标格、排在标题下, 点了跳到那件装备的图鉴页", bad_member.is_empty(), str(bad_member.slice(0, 6)))

	## ③ 「同上」展开成上一档同名那一条(纯函数, 不走场景)
	var view = _c._codex_detail._syn_view
	var t1: PackedStringArray = view.split_tier("每件 +1 · 【僵硬】叠 1 层(持续 5 秒)")
	var t2: PackedStringArray = view.split_tier("每件 +2 · 【僵硬】同上 · 闪避蓄能同上", t1)
	_ok("★★③ 「【X】同上」展开成上一档那条; 上一档没有的「X同上」原样留着",
		t2.size() == 3 and t2[1] == "【僵硬】叠 1 层（持续 5 秒）" and t2[2] == "闪避蓄能同上", str(t2))
	await _t_special_syn()
	_finish()


## ⑤ 特殊羁绊(Phase2Types.TAG_ONLY, 现在是筹码; 用户 11-27「筹码也是羁绊啊…特殊的羁绊…没有羁绊的提供的羁绊效果。但是你图鉴要写啊」):
##   左栏有它 → 详情写「没有羁绊档位」、不出「激活 N 件」和逐档行 → 说明文字逐条出现 → 成员格 = 挂这个标签的装备数(> 0)
func _t_special_syn() -> void:
	_ok("⑤ ★分母: 特殊羁绊名单非空", not Phase2Types.TAG_ONLY.is_empty(), str(Phase2Types.TAG_ONLY))
	for tname in Phase2Types.TAG_ONLY:
		_c._switch_tab("synergies")
		await _settle(2)
		var idx := -1
		for i in range(_c._items.size()):
			if str((_c._items[i] as Dictionary).get("_type", "")) == str(tname):
				idx = i
		_ok("⑤ %s 在图鉴羁绊页左栏" % tname, idx >= 0)
		if idx < 0:
			continue
		_c._select(idx)
		await _settle(2)
		var texts: Array = []
		for ch in _live():
			if ch is Label:
				texts.append(str((ch as Label).text))
			elif ch is RichTextLabel:
				texts.append(str((ch as RichTextLabel).get_parsed_text()))
		var joined: String = " | ".join(texts)
		_ok("⑤ %s 详情写「无羁绊加成」、没有「激活」「羁绊效果」小标题(11-27 起机制句上面不放小标题)" % tname,
			joined.find("无羁绊加成") >= 0 and joined.find("激活") < 0 and joined.find("羁绊效果") < 0, joined.substr(0, 160))
		_ok("⑤ %s 没有逐档行" % tname, _with_meta("codex_syn_tier").is_empty() and _with_meta("codex_syn_line").is_empty())
		var intro: Array = Phase2Types.intro_lines(str(tname))
		_ok("⑤ %s 说明逐条出现(%d 条)" % [tname, intro.size()], intro.size() >= 1 and _with_meta("codex_syn_intro").size() == intro.size(),
			"界面 %d 条" % _with_meta("codex_syn_intro").size())
		var want: int = (_c._codex_detail._syn_view._view_ref.get_ref()._type_members(str(tname)) as Array).size()
		_ok("⑤ %s 成员格 = 挂这个标签的装备 %d 件(> 0)" % [tname, want], want > 0 and _with_meta("codex_syn_member").size() == want,
			"格 %d" % _with_meta("codex_syn_member").size())


func _finish() -> void:
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 图鉴羁绊页一档一行/子机制拆行/成员格可点")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
