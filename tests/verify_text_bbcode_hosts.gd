extends Node
## verify_text_bbcode_hosts.gd — 【文案落点吃不吃 BBCode】(2026-10-02)
##
## 由来: 2026-10-01 把技能/装备文案做成了带颜色、带内联属性图标(`[img]`)、带加粗的 BBCode。
## 但一段 BBCode 落到 `Label` 上, Godot 会把标记【原样印给玩家】——
## 实拍留证: 选龟页被动 chip 的 tooltip 当场印出 `[color=#ff4444]+20%[/color]`
## (普查与证据照片见 `docs/plans/20261002-文案落点BBCode普查.md`)。
##
## ★这条门禁量的是【产品自己的账】, 不是我插的标记:
##   · tooltip 这一侧 —— 真调控件自己的 `_make_custom_tooltip()`, 看它吐出来的
##     宿主里有没有 `bbcode_enabled` 的 `RichTextLabel`, 并且那个 RichTextLabel
##     的 `get_parsed_text()`(= 屏幕上真正的字) 里**不许再剩标记**。
##   · 常驻文字这一侧 —— 把整屏遍历一遍, 任何 `Label.text` 里出现 BBCode 标记就红。
##     (Label.text 就是屏幕上的字, 没有第二层解释。)
##
## ★反向验证(都试过会红):
##   · 去掉 `detail_panel.gd` 的 `chip.set_script(RichTooltip)` → ① 红(宿主不是 RichTextLabel)
##   · 去掉 `dual_lane_flow.gd` 的 `box.set_script(RichTooltip)` → ② 红
##   · `InventoryScene` 把 `equip_brief_bb` 改回 `equip_brief` → ③ 的分母红(tooltip 里没有图标)
##   · `battle_render._render_skill_text` 改回 `render_plain` → ④ 红(战斗描述一个颜色都没有)
##
## 跑法(必须 headless, 本机开窗口会蓝屏):
##   <godot> --headless --audio-driver Dummy --path . res://tests/verify_text_bbcode_hosts.tscn --quit-after 900

const TSS := preload("res://scenes/TeamSelect.tscn")
const INV := preload("res://scenes/Inventory.tscn")
const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

## BBCode 里【会被当标记吃掉】的开头。只列我们真的会产出的那几种
## (`SkillText.html_to_bbcode` 只吐 color/b/i/img/font_size)。
const BB_MARKS := ["[color=", "[/color]", "[img", "[b]", "[/b]", "[i]", "[/i]", "[font_size="]

var _fail := 0
## ★跑过的断言条数 —— 一条 SCRIPT ERROR 就能把半个测试静默跳掉而照样 ALL PASS
##   (memory [[fb-null-readback-makes-test-silently-abort]] 就是这一类)。末尾对账。
var _checks := 0
## 四节加起来应该跑到的条数(① 4 + ② 4 + ③ 3 + ④ 6 = 17)。
## 改了断言数量记得改它 —— 它存在的意义就是「少跑了要红」。
const EXPECT_CHECKS := 17


func _ok(n: String, c: bool, d: String = "") -> void:
	_checks += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true

	print("=== 文案落点: 吃不吃 BBCode ===")
	await _t1_team_select()
	await _t2_battle_equip_chip()
	await _t3_inventory_cell()
	await _t4_battle_skill_desc()

	print("  [分母] 这一轮真的跑了 %d 条断言(应该 %d 条)" % [_checks, EXPECT_CHECKS])
	if _checks < EXPECT_CHECKS:
		_fail += 1
		print("  [FAIL] ★★有断言被静默跳过了(看上面有没有 SCRIPT ERROR)")
	print("ALL PASS — 文案落点 BBCode 宿主" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# ══════════════════════════════════════════════════════════════
# ① 选龟页: 整屏扫一遍 —— 带 BBCode 的 tooltip 必须有能渲染它的宿主;
#    常驻 Label 里一个标记都不许有。
# ══════════════════════════════════════════════════════════════
func _t1_team_select() -> void:
	print("  ── ① 选龟页 ──")
	var scene = TSS.instantiate()
	add_child(scene)
	for _i in range(8):
		await get_tree().process_frame
	## ★挑一只【真有被动】的龟 —— 没被动就没有那个 chip, 整条断言会变成空检查。
	var pid := ""
	for p in DataRegistry.all_pets:
		var pv = (p as Dictionary).get("passive")
		if pv is Dictionary and not (pv as Dictionary).is_empty() \
				and str((pv as Dictionary).get("brief", "")).strip_edges() != "":
			pid = str((p as Dictionary).get("id", ""))
			break
	_ok("★分母: 找得到一只带被动简述的龟", pid != "", "pid=%s" % pid)
	if pid == "":
		scene.queue_free()
		return
	scene.detail_pet_id = pid
	scene._detail._refresh_detail()
	for _i2 in range(4):
		await get_tree().process_frame

	var n_ctrl := 0
	var n_bb_tip := 0
	var bad_host: Array = []
	var bad_label: Array = []
	var stack: Array = [scene]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			n_ctrl += 1
			var c := n as Control
			var tt := str(c.tooltip_text)
			if _has_bb(tt):
				n_bb_tip += 1
				var why := _tip_host_problem(c, tt)
				if why != "":
					bad_host.append("%s: %s" % [c.get_class(), why])
			if n is Label and _has_bb(str((n as Label).text)):
				bad_label.append("%s |%s|" % [c.get_class(), str((n as Label).text).substr(0, 48)])
		for ch in n.get_children():
			stack.append(ch)
	print("    [分母] 扫了 %d 个 Control, 其中 tooltip 带 BBCode 的 %d 个" % [n_ctrl, n_bb_tip])
	_ok("★分母: 选龟页上确实有带 BBCode 的 tooltip(0 个 = 空检查)", n_bb_tip >= 1,
		"%d 个" % n_bb_tip)
	_ok("★★① 每个带 BBCode 的 tooltip 都有能渲染它的宿主", bad_host.is_empty(),
		str(bad_host.slice(0, 4)))
	_ok("★★① 屏上没有任何 Label 在原样印 BBCode 标记", bad_label.is_empty(),
		str(bad_label.slice(0, 4)))
	scene.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════
# ② 战斗内对阵预览的 44×44 装备格(dual_lane_flow._dl_equip_chip)
# ══════════════════════════════════════════════════════════════
func _t2_battle_equip_chip() -> void:
	print("  ── ② 战斗·对阵预览 44×44 装备格 ──")
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	## 挑一件【文案里真有关键词】的装备 —— 否则 `equip_brief_bb` 不产出任何标记,
	## 判据会退化成"空串也算过"。
	var eid := ""
	for e in DataRegistry.phase2_equipment:
		var ed: Dictionary = e
		if _has_bb(SkillText.equip_brief_bb(ed, 13)):
			eid = str(ed.get("id", ""))
			break
	_ok("★分母: 找得到一件文案能上色的装备", eid != "", "eid=%s" % eid)
	if eid != "":
		var chip: Control = s._dl_sys._dl_equip_chip(eid, 2)
		_ok("★分母: 这个格子就是 44×44", chip.custom_minimum_size == Vector2(44, 44),
			str(chip.custom_minimum_size))
		var tt := str(chip.tooltip_text)
		_ok("★分母: 它的 tooltip 正文真带 BBCode(不然这条判据是空的)", _has_bb(tt),
			tt.substr(0, 60))
		var why := _tip_host_problem(chip, tt)
		_ok("★★② 44×44 装备格的 tooltip 吃 BBCode", why == "", why)
		chip.queue_free()
	s.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════
# ③ 背包格子 —— 宿主早就对了, 这里守的是【喂进去的是不是 _bb 版】
# ══════════════════════════════════════════════════════════════
func _t3_inventory_cell() -> void:
	print("  ── ③ 背包装备格 ──")
	var scene = INV.instantiate()
	add_child(scene)
	for _i in range(6):
		await get_tree().process_frame
	var eid := ""
	for e in DataRegistry.phase2_equipment:
		var ed: Dictionary = e
		if SkillText.equip_brief_bb(ed, 13).contains("[img") and str(ed.get("effectBrief", "")) != "":
			eid = str(ed.get("id", ""))
			break
	_ok("★分母: 找得到一件简述里带内联属性图标的装备", eid != "", "eid=%s" % eid)
	if eid != "":
		var cell: Control = scene._equip_cell({"id": eid, "star": 2}, 0, Vector2.ZERO)
		var tt := str(cell.tooltip_text)
		var why := _tip_host_problem(cell, tt)
		_ok("★★③ 背包格子的 tooltip 吃 BBCode", why == "", why)
		## ★这条才是本次改的东西: 以前喂的是 `equip_brief`(纯文本) ⇒ tooltip 里
		##   一个 `[img]` 都没有, 玩家在格子上看不到属性图标, 而同屏操作栏有。
		_ok("★★③ 效果那段喂的是 _bb 版(tooltip 里有内联属性图标)", tt.contains("[img"),
			tt.substr(0, 80))
		cell.queue_free()
	scene.queue_free()
	await get_tree().process_frame


# ══════════════════════════════════════════════════════════════
# ④ 战斗信息面板的技能描述 —— 控件早就是 RichTextLabel, 一直没人喂它 BBCode
# ══════════════════════════════════════════════════════════════
func _t4_battle_skill_desc() -> void:
	print("  ── ④ 战斗·信息面板技能描述 ──")
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame
	var u := {"atk": 100.0, "maxHp": 1000.0, "hp": 1000.0, "def": 10.0, "mr": 10.0,
		"crit": 0.0, "level": 1, "id": "basic"}
	var tpl := "造成 {N:0.7*ATK} 点物理伤害, 并提升攻击力。"
	var out: String = s._render._render_skill_text(tpl, u, {})
	_ok("★分母: 占位符仍被算成数字(ATK=100 → 70)",
		out.contains("70") and not out.contains("{N:"), out.substr(0, 70))
	_ok("★★④ 战斗描述带颜色标记(原来 _strip_html 把它扒光了)", out.contains("[color="),
		out.substr(0, 70))
	_ok("★★④ 战斗描述带内联属性图标", out.contains("[img"), out.substr(0, 90))
	## ★收这段字的那个控件必须真的吃 BBCode —— 走产品自己的入口建面板, 不自己造控件。
	var ents: Array = s._info_sys._skill_bar_entries(u)
	_ok("★分母: 取得到技能条目", ents.size() >= 1, "%d 条" % ents.size())
	if ents.size() >= 1:
		var e0: Dictionary = ents[ents.size() - 1]
		s._hud._show_unit_info_panel(u)
		await get_tree().process_frame
		s._info_sys._show_detail(s._info_panel, "bbtest", str(e0.get("name", "")),
			str(e0.get("desc", "")), e0, u)
		for _i in range(3):
			await get_tree().process_frame
		var rt := _first_rtl(s._info_panel)
		_ok("★★④ 描述框是开了 bbcode 的 RichTextLabel",
			rt != null and rt.bbcode_enabled, "rt=%s" % ("null" if rt == null else "有"))
		if rt != null:
			## 屏幕上真正的字里不许剩标记 —— 剩了就说明标记没被当标记吃掉。
			_ok("★★④ 屏幕上的字里没有残留标记", not _has_bb(rt.get_parsed_text()),
				rt.get_parsed_text().substr(0, 70))
	s.queue_free()
	await get_tree().process_frame


# ── 工具 ───────────────────────────────────────────────────────
func _has_bb(t: String) -> bool:
	for m in BB_MARKS:
		if t.contains(m):
			return true
	return false


## 这个控件的 tooltip 宿主【能不能渲染 BBCode】。能 → 返回 ""; 不能 → 返回原因。
## ★走控件自己的 `_make_custom_tooltip()` —— 这就是 Godot 真正会调的那一个,
##   不是我另写一份"它应该长什么样"。没有这个方法 = Godot 造系统的纯 Label。
func _tip_host_problem(c: Control, tip: String) -> String:
	if not c.has_method("_make_custom_tooltip"):
		return "没有 _make_custom_tooltip ⇒ 系统纯 Label tooltip"
	var host = c._make_custom_tooltip(tip)
	if host == null:
		return "_make_custom_tooltip 返回 null ⇒ 系统纯 Label tooltip"
	var rt := _first_rtl(host)
	var problem := ""
	if rt == null:
		problem = "宿主里没有 RichTextLabel"
	elif not rt.bbcode_enabled:
		problem = "RichTextLabel 没开 bbcode_enabled"
	elif _has_bb(rt.get_parsed_text()):
		problem = "渲染后仍残留标记: " + rt.get_parsed_text().substr(0, 40)
	if host is Node:
		(host as Node).free()
	return problem


func _first_rtl(root) -> RichTextLabel:
	if root == null:
		return null
	var q: Array = [root]
	while not q.is_empty():
		var n = q.pop_back()
		if n is RichTextLabel:
			return n
		if n is Node:
			for ch in (n as Node).get_children():
				q.append(ch)
	return null
