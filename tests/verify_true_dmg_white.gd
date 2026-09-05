extends Node
## verify_true_dmg_white.gd — 真实伤害的飘字【必须是白色】, 而且两条伤害路一样白
##
## ══════════════════════════════════════════════════════════════════
##  ★由来: 用户 2026-09-03 逐字「我现在告诉你真实伤害统一白色」
##          「跳出方法不应该是向上淡出, 必须按规矩」
##          「什么叫真实伤害, 颜色等等规矩, 你在害用户」
## ══════════════════════════════════════════════════════════════════
## 调查结论(方案书 docs/plans/20260903b-伤害飘字统一收口.md §2.2):
##   `_apply_damage_from` 早就按类型统一取色(`_ncol`, 调用点传的 col 被忽略),
##   `_apply_damage` 却直接用调用点传的 `col`
##   ⇒ **同一种真伤, 两条路跳出来颜色不一样** —— CLAUDE.md §3.3
##     「改伤害逻辑必须两条都改」在这里就是只做了一条。
##
## ★★判据落在**读回真实 Label 节点的 font_color**, 不是扫源码调用点 ——
##   方案书 §4.3 写明了: 扫调用点是扫死参数(那条路上的 col 压根不生效),
##   颜色由取色逻辑决定, 所以判据只能落在取色后的结果上。
##
## ★★★这条门禁**不许放宽成"颜色是某个亮色"**: 收口前那 4 处传的是
##   紫 #c8b0ff / 紫 #a06cd5 / 暗红 #8b2e4a / 金 #ffd166, 宽判据会把它们全放过。
##   判据卡死在 UIPalette.TRUE_DMG 上(memory [[fb-judge-must-fit-the-shape]])。

const UIPalette := preload("res://scripts/util/ui_palette.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


## 数一遍 UI 层里所有 Label 的 font_color(飘字都是 `_make_num_label` 建的 Label)。
## 返回 [Label, ...] —— 调用前后各取一次, 差集就是这一发打出来的飘字。
func _labels(scn) -> Array:
	var out: Array = []
	var stack: Array = [scn._ui_layer]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is Label:
			out.append(n)
		for c in (n as Node).get_children():
			stack.append(c)
	return out


func _new_label(scn, before: Array):
	for l in _labels(scn):
		var seen := false
		for b in before:
			if is_same(b, l):
				seen = true
				break
		if not seen:
			return l
	return null


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	## 清场: 用干净合成单位, 不拿随机 spawn 的真单位
	## (memory [[fb-ci-vs-local-divergence]]: 随机队伍会带盾/flat_dr, CI 上偶发红)
	for u in scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	scn._units.clear()
	var cx: float = scn.ARENA.position.x + scn.ARENA.size.x * 0.5
	var cy: float = scn.ARENA.position.y + scn.ARENA.size.y * 0.5

	## ★三个靶子放在**不同位置** —— `_float_text` 有同帧合并
	##   (同 pos + 同 dmg_type + 同帧 ⇒ 累加进已在跳的那个数字, 不新建节点),
	##   挤在一处会让后两发读不到自己的 Label。
	var targets: Array = []
	for i in range(4):     # 4 个: ①真伤 ②另一条路 ③物理 ④魔法(2026-09-05 收口后各占一个, 免得飘字合并)
		var t: Dictionary = scn._spawn._make_unit("basic", "right", Vector2(cx + 60.0 * float(i), cy - 90.0 * float(i)))
		t["no_move"] = true
		t["no_basic"] = true
		t["move_spd"] = 0.0
		t["active_skills"] = []
		t["maxHp"] = 999999.0
		t["hp"] = 999999.0
		t["shield"] = 0.0
		t["deathfloor_until"] = 999999.0
		scn._units.append(t)
		targets.append(t)
	var src: Dictionary = scn._spawn._make_unit("basic", "left", Vector2(cx - 300.0, cy))
	src["no_move"] = true
	src["no_basic"] = true
	src["active_skills"] = []
	scn._units.append(src)
	await get_tree().process_frame

	var WHITE: Color = Color(UIPalette.TRUE_DMG)
	print("── ① `_apply_damage` 这条路: 真伤传主题紫, 玩家必须看到白 ──")
	var b0: Array = _labels(scn)
	## 传一个**明显不是白**的紫 —— 收口前 gremlin_gun.gd:76 传的就是这个色。
	scn._damage._apply_damage(targets[0], 137, Color("#a06cd5"), src, "tru")
	await get_tree().process_frame
	var l1 = _new_label(scn, b0)
	_ok("★分母: 这一发真的建出了飘字 Label", l1 != null,
		"没建出来 = 下面那条是空检查(UI 层 Label 数 %d → %d)" % [b0.size(), _labels(scn).size()])
	if l1 != null:
		var c1: Color = (l1 as Label).get_theme_color("font_color")
		_ok("① 真伤飘字是白色(实读 #%s, 传进去的是紫 #a06cd5)" % c1.to_html(false),
			c1.is_equal_approx(WHITE),
			"读回 %s ≠ 标准白 %s —— 调用点的主题色漏出去了" % [c1.to_html(false), WHITE.to_html(false)])

	print("── ② 另一条路 `_apply_damage_from` 打真伤, 颜色必须**一样** ──")
	var b1: Array = _labels(scn)
	## raw=true = 真伤(不吃护甲/魔抗)。这条路按类型统一取色, 传什么 col 都会被覆盖。
	scn._damage._apply_damage_from(src, targets[1], 137, Color("#8b2e4a"), 0.0, true)
	await get_tree().process_frame
	var l2 = _new_label(scn, b1)
	_ok("★分母: 另一条路也真的建出了飘字 Label", l2 != null,
		"没建出来 = 下面那条是空检查")
	if l1 != null and l2 != null:
		var c1b: Color = (l1 as Label).get_theme_color("font_color")
		var c2: Color = (l2 as Label).get_theme_color("font_color")
		_ok("② 两条伤害路打同一种真伤, 读回的颜色相同(#%s vs #%s)"
			% [c1b.to_html(false), c2.to_html(false)], c1b.is_equal_approx(c2),
			"两条路不一致 —— 这正是 CLAUDE.md §3.3 说的『只改了一条』")

	## ══════════════════════════════════════════════════════════════════
	##  ③④ 物理红 / 魔法蓝 —— 2026-09-05 收口（用户「修吧」）
	## ══════════════════════════════════════════════════════════════════
	## ★这两条原本是**反过来**写的（断言「物理仍用调用点的色」），因为 2026-09-03
	##   用户只点了真伤、说物理/魔法「别，记录好到下一个方案里去做」。
	##   09-05 我拿探针把三种 bucket 的飘字颜色**读回来**给他看：
	##     tru 传紫→实读白 ✅ / mag 传橙→实读橙 ❌ / phy 传绿→实读绿 ❌
	##   最能说明问题的是 `axe_final_forms.gd:161` 炽天使回旋镖——**已经吃了魔抗**
	##   却跳橙色数字；同一发魔法伤害走另一条路是蓝的。用户看完拍板「修吧」。
	##
	## ★★**分母换了个形状**：原来 ③ 兼任 ① 的分母（"不是所有 bucket 都返回白"）。
	##   现在三种都被强制了，那个分母失效 ⇒ 改成断言**三个颜色互不相同**。
	##   如果取色逻辑退化成"永远返回白"，⑤ 会当场红。
	print("── ③④ 物理必红 · 魔法必蓝(与真伤同一张表) ──")
	var got_cols: Dictionary = {}
	var idx := 2
	for row in [["phy", "#39d353", UIPalette.PHYS, "③ 物理"], ["mag", "#ffb347", UIPalette.MAGIC, "④ 魔法"]]:
		var bN: Array = _labels(scn)
		scn._damage._apply_damage(targets[idx], 137 + idx, Color(str(row[1])), src, str(row[0]))
		await get_tree().process_frame
		var lN = _new_label(scn, bN)
		_ok("★分母: %s 那一发也建出了飘字 Label" % str(row[3]), lN != null,
			"没建出来 = 下面那条是空检查")
		if lN != null:
			var cN: Color = (lN as Label).get_theme_color("font_color")
			got_cols[str(row[0])] = cN
			_ok("%s伤害被强制成规矩色(传进去 %s, 实读 #%s, 应为 %s)"
					% [str(row[3]), str(row[1]), cN.to_html(false), str(row[2])],
				cN.is_equal_approx(Color(str(row[2]))),
				"还是调用点传的色 —— 收口没生效")
		idx += 1

	## ⑤ 新分母：三色互不相同（顶替原 ③ 的分母角色）
	got_cols["tru"] = Color(UIPalette.TRUE_DMG)
	var distinct: Dictionary = {}
	for k in got_cols:
		distinct[(got_cols[k] as Color).to_html(false)] = true
	_ok("⑤ ★分母: 三种伤害类型读回来的颜色**互不相同**(%d 种) —— 否则上面全是恒真式"
			% distinct.size(),
		distinct.size() == 3 and got_cols.size() == 3,
		"只有 %d 种不同色 ⇒ 取色逻辑可能退化成了'永远返回同一个色'" % distinct.size())

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
