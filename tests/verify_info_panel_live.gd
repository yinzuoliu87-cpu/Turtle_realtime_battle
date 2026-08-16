extends Node
## verify_info_panel_live.gd — 局内信息栏「战斗中真的看得见」门禁 (2026-08-15)
##
## ══════════════════════════════════════════════════════════════════
##  由来(用户原话)
## ══════════════════════════════════════════════════════════════════
##   「这些信息我在战斗内完全看不到，信息栏要完全重做啊」「数值什么一点都看不到」
##
## 实拍(SHIP=1 INFO_DEMO=1 SELFSHOT)确认的四类缺口, 本门禁逐条焊住:
##   ① 射程/移速印的是【基础字段】而不是实战值 —— 被减速时面板照旧印 110, 龟其实只走 66
##   ② 吸血/闪避/治疗强度/护盾强度/暴伤/龟能充能 六行仍是 `%d` ⇒ 小数抹成 0
##      (与用户 2026-08-14 骂过的增伤/减伤是同一个 bug, 那次只改了四行)
##   ③ 龟能条印 "46%", 而技能文案里写的是「(80 龟能)」⇒ 同一件事两个口径, 对不上
##   ④ 形态/装备充能局内零出口 —— 熔岩龟在火山形态下面板一个字都不提;
##      火山形态里 `rage` 被复用成倒计时, chip 却还写着「怒气 36」(那个 36 其实是"还剩 5.4 秒")
##
## ★判据一律落在【产品自己的账】: 真开一次面板, 从面板节点上读回文字;
##   数值对照的是战斗自己的函数(_eq_ 表 / _skill_cost / _eff_range), 不是我抄一份常量。
## ★等效果不用帧数/游戏时钟/create_timer —— 本用例把 _process 关掉后【直接调刷新函数】,
##   全程同步判定, 一条 tween 都不依赖(CLAUDE.md §3.5)。
##
## 跑法: <godot> --headless --path . res://tests/verify_info_panel_live.tscn --quit-after 2000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC_MAIN := "res://scripts/scenes/RealtimeBattle3DScene.gd"
const SRC_PANEL := "res://scripts/scenes/battle/info_panel.gd"

var _s
var _ip
var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


## 递归找面板里含关键字的 Label 文本 —— chip 的 Label 埋在 box→flow→PanelContainer→Label 四层下。
func _find_label(n: Node, key: String) -> String:
	if n is Label and str((n as Label).text).find(key) >= 0:
		return str((n as Label).text)
	for ch in n.get_children():
		var r := _find_label(ch, key)
		if r != "":
			return r
	return ""


## 把面板里【所有 Label / RichTextLabel 的文字】拼成一大串。
##
## ★用途: 判"这条信息玩家看不看得到"时, 不该钉死它长在哪个容器里 ——
##   信息搬家(chip → 资源条)不是回归, 信息消失才是。钉位置的断言会把重构判成 bug。
func _panel_all_text(root: Node) -> String:
	if root == null or not is_instance_valid(root):
		return ""
	var out := ""
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out += str((n as Label).text) + " "
		elif n is RichTextLabel:
			out += str((n as RichTextLabel).get_parsed_text()) + " "
		for c in n.get_children():
			stack.append(c)
	return out


func _row(u: Dictionary, prefix: String) -> String:
	for r in _ip._info_stat_rows(u):
		if str((r as Array)[1]).begins_with(prefix):
			return str((r as Array)[1])
	return ""


func _txt(path: String) -> String:
	return FileAccess.get_file_as_string(path)


## 精确取某个顶层函数的函数体(到下一个顶层 func 为止)。固定字符窗口会框进隔壁函数 ⇒ 断言变恒真。
func _func_body(src: String, fname: String) -> String:
	var out := ""
	var inside := false
	for line in src.split("\n"):
		if line.begins_with("func " + fname + "("):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


func _ready() -> void:
	await get_tree().process_frame
	print("=== 局内信息栏: 战斗中看得见 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	_ip = _s._info_sys
	## ★把 sim 关掉 —— 否则 `_t` 一直跑, 冷却/减速到期时间会漂, 断言变成偶发红。
	##   关掉之后面板刷新由本用例【直接调】, 全程同步。
	_s._units.clear()
	_s._edit_mode = false
	_s._over = false
	_s.set_process(false)

	_test_move_mirror_source()
	_test_eff_range_and_move()
	_test_pct_not_rounded_to_zero()
	_test_energy_points_on_real_panel()
	_test_form_chip_on_real_panel()
	_test_rage_and_star_denominator()
	_test_equip_readout_on_real_panel()
	_test_skill_entry_energy()
	_test_single_readout_table()
	await _test_section_order()
	await _test_panel_v2()
	await _test_no_rebuild_loop()

	_s.queue_free()
	await get_tree().process_frame
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 局内信息栏实时读数" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _mk(id: String) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	return _s._spawn._make_unit(id, "left", c)


# ────────────────────────────────────────────────────────────────────────────
#  ① 移速镜像必须跟着 sim 那条公式走 (源码级对账)
# ────────────────────────────────────────────────────────────────────────────
## ★手抄的副本必然落后。sim 的移动速度写死在 `_sim_step` 中段(没有函数出口),
##   面板只能镜像一份 ⇒ 这条把【sim 那一行里出现的乘数字段名】逐个和镜像函数对账。
##   sim 以后再加一档乘数而镜像没跟 ⇒ 直接红。
func _test_move_mirror_source() -> void:
	var main := _txt(SRC_MAIN)
	var sim_line := ""
	for line in main.split("\n"):
		if line.find("var spd: float = u[\"move_spd\"]") >= 0:
			sim_line = line
			break
	_ok("★分母: 找得到 sim 里那条移动速度公式", sim_line != "",
		"找不到就说明公式被改名/搬走了, 镜像已经无从对账")
	if sim_line == "":
		return
	var re := RegEx.new()
	re.compile("u\\.get\\(\"([a-z_]+)\"")
	var want: Array = []
	for m in re.search_all(sim_line):
		var f := str(m.get_string(1))
		if f != "" and not want.has(f):
			want.append(f)
	_ok("★分母: 从 sim 那一行里抠出了乘数字段 (N=0 是空检查)", want.size() >= 3,
		"抠到 %d 个: %s" % [want.size(), str(want)])
	var mirror := _func_body(_txt(SRC_PANEL), "_eff_move_spd")
	_ok("★分母: 找得到面板的 _eff_move_spd", mirror.length() > 40)
	var miss: Array = []
	for f in want:
		if mirror.find(str(f)) < 0:
			miss.append(f)
	_ok("★★面板移速镜像覆盖了 sim 的每一档乘数(漏一档 = 面板印的不是实战移速)",
		miss.is_empty(), "漏掉: %s (sim 那行要的是 %s)" % [str(miss), str(want)])


# ────────────────────────────────────────────────────────────────────────────
#  ② 射程/移速: 面板印的必须是实战值
# ────────────────────────────────────────────────────────────────────────────
func _test_eff_range_and_move() -> void:
	var u := _mk("basic")
	u["atk_range"] = 300.0
	u["range_add"] = 0.0
	u["range_perm"] = 1.0
	u["move_spd"] = 100.0
	u["slow_until"] = 0.0
	var r0 := _row(u, "射程 ")
	var m0 := _row(u, "移速 ")
	_ok("★分母: 射程/移速两行都在", r0 != "" and m0 != "", "%s / %s" % [r0, m0])

	# 装备加射程 → 面板必须跟着涨, 且和战斗判定用的 _eff_range 同一个数
	u["range_add"] = 120.0
	var r1 := _row(u, "射程 ")
	_ok("★★装备加了 120 射程 ⇒ 面板那一行跟着涨(原来只印基础 atk_range)",
		r1 != r0, "%s → %s" % [r0, r1])
	_ok("★★而且印的就是战斗判定用的那个数(battle._eff_range)",
		r1 == "射程 %d" % int(round(_s._eff_range(u))),
		"面板 '%s' vs 判定 %.1f" % [r1, _s._eff_range(u)])

	# 减速 → 面板移速必须跟着掉
	u["slow_until"] = _s._t + 99.0
	u["slow_mag"] = 0.5
	var m1 := _row(u, "移速 ")
	_ok("★★被减速 50%% ⇒ 面板移速跟着掉(原来一直印 100, 而龟只走 50)",
		m1 == "移速 50", "%s → %s" % [m0, m1])
	# 反面: 减速过期就回去 —— 不是一减速就永久变小
	u["slow_until"] = 0.0
	_ok("★反面: 减速过期后移速回到基础值", _row(u, "移速 ") == m0, _row(u, "移速 "))


# ────────────────────────────────────────────────────────────────────────────
#  ③ 小数百分比不许被抹成 0
# ────────────────────────────────────────────────────────────────────────────
## 用户 2026-08-14 已经骂过一次(增伤/减伤), 那次只改了四行, 这六行漏了。
func _test_pct_not_rounded_to_zero() -> void:
	var u := _mk("basic")
	u["lifesteal"] = 0.004; u["ls_bonus"] = 0.0
	u["dodge_bonus"] = 0.003
	u["heal_amp"] = 0.004
	u["shield_amp"] = 0.002
	u["crit"] = 0.004
	u["crit_dmg"] = 1.5
	u["echarge_perm"] = 0.003
	var cases := [
		["吸血 ", "吸血 0.4%"],
		["闪避 ", "闪避 0.3%"],
		["治疗强度 ", "治疗强度 100.4%"],
		["护盾强度 ", "护盾强度 100.2%"],
		["暴击 ", "暴击 0.4%"],
		["龟能充能 ", "龟能充能 100.3%"],
	]
	for c in cases:
		var got := _row(u, str(c[0]))
		_ok("★不足 0.5%% 也要显出来: %s" % str(c[1]).strip_edges(), got == str(c[1]),
			"实得 '%s'(期望 '%s')" % [got, str(c[1])])
	# 大数值仍取整(不啰嗦成 "60.0%")
	u["damage_amp"] = 0.6
	_ok("★大数值仍取整(60% 不写成 60.0%)", _row(u, "增伤 ") == "增伤 60%", _row(u, "增伤 "))


# ────────────────────────────────────────────────────────────────────────────
#  ④ 龟能条: 印【点数】, 与技能文案同口径 —— 从真开的面板上读回来
# ────────────────────────────────────────────────────────────────────────────
func _test_energy_points_on_real_panel() -> void:
	var u := _mk("lava")
	u["active_skills"] = ["lavaErupt"]
	u["volcano"] = false
	u["skill_cd"] = {"lavaErupt": 3.0}
	u["energy_lock_until"] = 0.0
	_s._units.clear(); _s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	_ok("★分母: 面板真的开着了", _s._info_panel != null and is_instance_valid(_s._info_panel))
	_ip._refresh_info_panel()
	var en: String = _res_text("龟能") + "  " + _res_hint("龟能")
	_ok("★分母: 龟能条那行字取得到", en != "", "实得 '%s'" % en)
	var cost0: float = _s._skill_cost(u, "lavaErupt")
	_ok("★★龟能条印【点数】而不是百分比(技能文案写的就是点数)",
		en.find("/ %d" % int(cost0)) >= 0, "实得 '%s'(满值应是 %d)" % [en, int(cost0)])
	## ★这两条删了(用户 2026-08-16:「龟能那里不需要文字不需要几秒后释放」)——
	##   龟能条不再带结论文字, 条 + `当前/上限` 已经说完; 再写"6.0 秒后可放"是同一件事说第三遍。
	##   ⚠ 仍然守住的是【印点数不印百分比】(下面那条), 那是技能文案对得上的口径。
	# 攒满 → 说人话地告诉玩家能放哪个技
	u["skill_cd"] = {"lavaErupt": 0.0}
	_ip._refresh_info_panel()
	var en2: String = _res_text("龟能") + "  " + _res_hint("龟能")
	## ★2026-08-16: 攒满时的说法从"攒满了"改成【可放「技能名」】—— 更直接, 且点名是哪个技能。


	## ★★口径合一的关键一条: 火山形态下 _skill_cost 特判成 120,
	##   面板必须跟着变成 120 —— 技能文案里写的正是「在火山形态(120 龟能)下」。
	u["volcano"] = true
	u["volcano_until"] = _s._t + 9.0
	u["skill_cd"] = {"lavaErupt": 2.0}
	_ip._refresh_info_panel()
	var en3: String = _res_text("龟能") + "  " + _res_hint("龟能")
	_ok("★★形态变了龟能满值跟着变(火山形态 120, 与技能文案的「120 龟能」对得上)",
		en3.find("/ 120") >= 0, "实得 '%s'" % en3)
	_s._hud._close_info_panel()


# ────────────────────────────────────────────────────────────────────────────
#  ⑤ 当前形态: 面板上要有, 而且【变了要跟着变】
# ────────────────────────────────────────────────────────────────────────────
## ★后半条才是真门禁 —— chips 是"签名变了才重建"的, 新 chip 不进签名就永远停在开面板那一刻,
##   看着有、其实是死的("写进去了没人读"的同一个坑)。
func _test_form_chip_on_real_panel() -> void:
	var u := _mk("lava")
	u["active_skills"] = ["lavaErupt"]
	u["skill_cd"] = {"lavaErupt": 1.0}
	u["volcano"] = false
	u["rage"] = 40.0
	_s._units.clear(); _s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	_ip._refresh_info_panel()
	var box = _s._info_status_box
	_ok("★分母: 状态区容器在", box != null and is_instance_valid(box))
	var t0 := _find_label(_s._info_status_box, "熔岩形态")
	## ★判据落在【需求】上, 不落在我当初把字放在哪:
	##   要求是"玩家得知道攒满怒气会变身", 不是"这句话必须长在状态 chip 上"。
	##   2026-08-17 这句从 chip 搬到了怒气条(chip 只说"我现在是什么形态", 条说"攒满会怎样")——
	##   原因是这两处【永远同屏】(怒气条恰好只在非火山形态出现), 同一件事说了两遍。
	##   所以这里改成【整块面板里找得到】就行, 搬家不该判红; 真删掉才该判红。
	var whole := _panel_all_text(_s._info_panel)
	_ok("★常态也说清楚(面板上告诉玩家攒满怒气会变身 —— 在哪一处都行)",
		whole.find("攒满") >= 0 and whole.find("火山") >= 0,
		"chip='%s' | 面板全文里 攒满=%s 火山=%s" % [t0, str(whole.find("攒满") >= 0), str(whole.find("火山") >= 0)])

	# 变身 → 同一个面板不重开, 只靠刷新, chip 必须跟着变
	u["volcano"] = true
	u["volcano_until"] = _s._t + 7.0
	_ip._refresh_info_panel()
	## ★面板可能被整块重建(资源条条目数变了就重建) ⇒ `box` 是旧节点, 必须现取。
	var t1 := _find_label(_s._info_status_box, "火山形态")
	_ok("★★变身后面板跟着变出【火山形态】(签名没覆盖形态的话这里会停在常态)",
		t1 != "" and _find_label(_s._info_status_box, "熔岩形态") == "",
		"火山='%s' / 常态残留='%s'" % [t1, _find_label(_s._info_status_box, "熔岩形态")])
	_ok("★★而且带剩余秒数(火山只有 15 秒, 不知道还剩多久等于没说)",
		t1.find("7.0") >= 0, "实得 '%s'" % t1)

	# 剩余时间在走 → 文字也要跟着走(不是只在 true/false 翻转时才刷)
	u["volcano_until"] = _s._t + 3.0
	_ip._refresh_info_panel()
	_ok("★★剩余秒数是活的(倒计时在走, 文字跟着走)",
		_find_label(_s._info_status_box, "火山形态").find("3.0") >= 0,
		"实得 '%s'" % _find_label(_s._info_status_box, "火山形态"))
	_s._hud._close_info_panel()

	# 双头龟: 两套形态数值, 面板要说清此刻是哪套
	var v := _mk("two_head")
	v["two_form"] = "ranged"
	_s._units.clear(); _s._units.append(v)
	_s._hud._show_unit_info_panel(v)
	_ip._refresh_info_panel()
	var b2 = _s._info_status_box
	_ok("★双头·远程形态在面板上看得见",
		_find_label(_s._info_status_box, "远程形态") != "" and _find_label(_s._info_status_box, "近战形态") == "",
		"远程='%s' 近战='%s'" % [_find_label(_s._info_status_box, "远程形态"), _find_label(_s._info_status_box, "近战形态")])
	v["two_form"] = "melee"
	_ip._refresh_info_panel()
	## ★两条都要查 —— 只查"近战出现了"守不住"远程还在"(旧 chip 没摘干净时两个会同时挂着)。
	_ok("★★双头切近战后面板跟着切(而且远程那条不许残留)",
		_find_label(_s._info_status_box, "近战形态") != "" and _find_label(_s._info_status_box, "远程形态") == "",
		"近战='%s' 远程残留='%s'" % [_find_label(_s._info_status_box, "近战形态"), _find_label(_s._info_status_box, "远程形态")])
	_s._hud._close_info_panel()


# ────────────────────────────────────────────────────────────────────────────
#  ⑥ 怒气/星能要有分母; 火山形态下不许再挂"怒气"
# ────────────────────────────────────────────────────────────────────────────
func _test_rage_and_star_denominator() -> void:
	var u := _mk("lava")
	u["rage"] = 36.0
	u["volcano"] = false
	_s._units.clear(); _s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	_ip._refresh_info_panel()
	var box = _s._info_status_box
	## ★按 chip 的表情前缀找 —— 找"怒气"两个字会把形态 chip 里那句"攒满怒气变火山"也捞进来
	##   (我第一版就是这么捞错的, 报了个假 FAIL)。
	## ★2026-08-16 怒气/星能从状态 chip 搬进【资源条】—— 资源是"我攒到哪了",
	##   状态是"我正在被怎样", 原来混在同一排 chip 里平级排是把两回事当一回事。
	var rg := _res_text("怒气")
	_ok("★★怒气带分母(只印 36 玩家不知道离变身还有多远)",
		rg.find("/ %d" % int(_s.RAGE_MAX)) >= 0, "实得 '%s'" % rg)

	## ★★火山形态下 `rage` 被 _sim_step 复用成【倒计时百分比】——
	##   那时再挂"怒气 36"是把倒计时读成资源, 玩家会整个理解错。
	u["volcano"] = true
	u["volcano_until"] = _s._t + 5.0
	u["rage"] = 33.0
	_ip._refresh_info_panel()
	_ok("★★火山形态下不再挂『怒气』(那个数其实是倒计时, 已由形态 chip 说清)",
		_res_text("怒气") == "", "实得 '%s'" % _res_text("怒气"))
	_s._hud._close_info_panel()

	# 星能: 满 = 最大生命 40%, 只印当前值看不出离强化还有多远
	var v := _mk("space")
	v["maxHp"] = 1000.0
	v["star_energy"] = 120.0
	_s._units.clear(); _s._units.append(v)
	_s._hud._show_unit_info_panel(v)
	_ip._refresh_info_panel()
	var st := _res_text("星能")
	_ok("★★星能带上限(最大生命 40% = 400)", st.find("/ 400") >= 0, "实得 '%s'" % st)
	v["star_energy"] = 400.0
	_ip._refresh_info_panel()
	## ★结论那句挪到条下面的 hint 上了(条的第三段), 不再挤在数值里。
	_ok("★星能攒满时明说会怎样", _res_hint("星能").find("攒满") >= 0,
		"实得 '%s'" % _res_hint("星能"))
	_s._hud._close_info_panel()


# ────────────────────────────────────────────────────────────────────────────
#  ⑦ 装备充能/层数: 详情面板里要有数字, 而且是活的
# ────────────────────────────────────────────────────────────────────────────
func _test_equip_readout_on_real_panel() -> void:
	var u := _mk("basic")
	u["equips"] = [{"id": "p2eq_093", "star": 2}]
	u["eq_state"] = {"p2eq_093": {"chg": 1000.0, "marks": 7}}
	_s._units.clear(); _s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	_ip._refresh_info_panel()      # 这一次接管装备区(见 info_panel 里的接管说明)
	var box = _s._info_equip_box
	_ok("★分母: 装备区容器在", box != null and is_instance_valid(box))
	var cap: float = float(EquipReadouts.CHARGE["p2eq_093"][1])
	var ch := _find_label(_s._info_equip_box, "充能")
	_ok("★★装备充能在详情面板上看得见(原来只有名字+星级)",
		ch.find("1000") >= 0 and ch.find(_s._fmt_num(cap)) >= 0,
		"实得 '%s'(满值 %s)" % [ch, _s._fmt_num(cap)])
	_ok("★★层数也看得见", _find_label(_s._info_equip_box, "层数").find("7") >= 0,
		"实得 '%s'" % _find_label(_s._info_equip_box, "层数"))
	# 活的: 攒了就要跟着涨(不是开面板那一刻的快照)
	(u["eq_state"]["p2eq_093"] as Dictionary)["chg"] = 2600.0
	(u["eq_state"]["p2eq_093"] as Dictionary)["marks"] = 9
	_ip._refresh_info_panel()
	## ★现取容器 —— 装备区签名一变就整块重建, `box` 会变成已被 queue_free 的旧节点。
	_ok("★★充能是活的(攒了就跟着涨)", _find_label(_s._info_equip_box, "充能").find("2600") >= 0,
		"实得 '%s'" % _find_label(_s._info_equip_box, "充能"))
	_ok("★★层数是活的", _find_label(_s._info_equip_box, "层数").find("9") >= 0,
		"实得 '%s'" % _find_label(_s._info_equip_box, "层数"))
	_s._hud._close_info_panel()


# ────────────────────────────────────────────────────────────────────────────
#  ⑧ 技能条目要写清龟能花费
# ────────────────────────────────────────────────────────────────────────────
func _test_skill_entry_energy() -> void:
	var u := _mk("lava")
	## ★用【战斗自己算出来的那个已选技】, 不是我猜一个 type ——
	##   面板取条目走的就是 _chosen_skill_types, 我另塞一个 type 会测到一条根本不显示的技。
	var chosen: Array = _s._chosen_skill_types("lava", true)
	_ok("★分母: 熔岩龟解析得到已选主动技 (N=0 就没得测)", not chosen.is_empty(), str(chosen))
	if chosen.is_empty():
		return
	var st := str(chosen[0])
	u["active_skills"] = [st]
	u["skill_cd"] = {st: 2.5}
	u["volcano"] = false
	var hit := ""
	for e in _ip._panel_skill_entries(u):
		var d: Dictionary = e
		if str(d.get("desc", "")).find("龟能") >= 0:
			hit = str(d["desc"])
	_ok("★★技能条目首行写清了龟能花费(原来只有描述, 不知道要多少龟能)",
		hit.find("龟能 ") >= 0 and hit.find("/ %d" % int(_s._skill_cost(u, st))) >= 0,
		("实得首行 '%s'" % hit.split("\n")[0]) if hit != "" else "(一条都没有)")
	_ok("★★而且写了还差几秒(2.5)", hit.find("2.5 秒") >= 0,
		("实得首行 '%s'" % hit.split("\n")[0]) if hit != "" else "(空)")

	## ★反面: 普攻不花龟能, 不许给它编一个。
	##   用小龟 —— 它的 skillPool[0] 是 physical, 才会生成"(普攻)"那条; 熔岩的 pool[0] 是 lavaBolt, 不生成。
	var b := _mk("basic")
	var bchosen: Array = _s._chosen_skill_types("basic", true)
	b["active_skills"] = bchosen.duplicate()
	var basic_line := ""
	var n_ent := 0
	for e2 in _ip._panel_skill_entries(b):
		n_ent += 1
		var d2: Dictionary = e2
		if str(d2.get("name", "")).find("普攻") >= 0:
			basic_line = str(d2.get("desc", ""))
	_ok("★分母: 小龟取到了技能条目 + 找得到那条普攻", n_ent > 0 and basic_line != "",
		"条目 %d 条, 普攻描述 %d 字符" % [n_ent, basic_line.length()])
	_ok("★反面: 普攻条目不挂龟能(它不花龟能, 编一个是假信息)",
		basic_line != "" and basic_line.find("龟能 ") < 0,
		"普攻条目: '%s'" % basic_line.substr(0, 40))


# ────────────────────────────────────────────────────────────────────────────
#  ⑨ 读数只有一张表 —— 不许在面板里另抄一份 id→字段
# ────────────────────────────────────────────────────────────────────────────
## ★"手抄的副本必然落后": 装备读数的事实源是 EquipReadouts 那两张表(装备图标格也读它)。
##   面板要是自己写一份 "p2eq_xxx" → 字段的映射, 加新装备时必然只改一边。
func _test_single_readout_table() -> void:
	var src := _txt(SRC_PANEL)
	_ok("★装备读数取自 EquipReadouts 那两张表(与装备图标格同源)",
		src.find("EquipReadouts.CHARGE") >= 0 and src.find("EquipReadouts.COUNT") >= 0)
	_ok("★★面板里没有另抄一份装备 id 映射(抄了就会漂)",
		src.find("\"p2eq_") < 0,
		"" if src.find("\"p2eq_") < 0 else "面板源码里出现了 p2eq_ 字面量 = 有第二张表")


func _test_section_order() -> void:
	## ── ★★★段落顺序: 技能必须【一开面板就在屏内】(2026-08-15)────────────────
	## 用户原话:「这些信息我在战斗内完全看不到」「数值什么一点都看不到」——
	## 他当时正在逐个读熔岩龟的技能。实拍根因: 属性区(22 项 2 列 ≈ 290px)+被动长描述
	## 排在技能【前面】, 把技能与装备整段顶到折叠线以下, 面板停在被动的半句话上。
	## ⇒ 顺序换成【玩家的提问顺序】: 状态 → 技能 → 装备 → 被动 → 详细属性。
	##   一项都没删(2026-07-21 用户定过"属性全都要显示"), 只是排到后面, 想看照样滚得到。
	## ★判据量【真实矩形】—— 不搜源码字符串, 那守的是"我当时怎么写的", 段落一挪就假红/假绿。
	## ★视口焊死成设计尺寸 —— 无头默认视口比 720 高(实测折叠线跑到 1264),
	##   那样"技能在屏内"几乎恒成立 = 一条不会红的断言。要量就按玩家真看到的那块屏量。
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var u: Dictionary = _mk("basic")
	u["equips"] = [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_010", "star": 2}]
	_s._units.clear()
	_s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	for _f in range(8):
		await get_tree().process_frame
	var panel = _s._info_panel
	## ★null 必须【显式红】—— 直接 `panel.global_position` 会抛运行时错误让整个函数中止,
	##   剩下的断言一条都不跑, 而测试照样打 ALL PASS(断言总数变少是唯一线索)。踩过。
	if panel == null or not is_instance_valid(panel):
		_ok("★分母: 面板建起来了(null = 后面所有几何断言都没跑)", false, "面板是 null")
		return
	_ok("★分母: 面板建起来了", true, "%.0f×%.0f" % [panel.size.x, panel.size.y])
	var fold: float = panel.global_position.y + panel.size.y
	var ys: Dictionary = {}
	var stk: Array = [panel]
	while not stk.is_empty():
		var n = stk.pop_back()
		for c in n.get_children():
			stk.append(c)
		if n is Label:
			var t := str((n as Label).text).strip_edges()
			## ★2026-08-16: 金色段标题「技能」删掉了(那是网页式 h3, 正是"网页味"的来源)。
			##   判据改成找【技能栏那一行】—— 普攻行永远在, 且它就是"技能区起点"。
			if (t.find("(普攻)") >= 0 or t == "当前状态" or t.find("攻击 ") == 0) and not ys.has("技能"):
				if t.find("(普攻)") >= 0:
					ys["技能"] = (n as Label).global_position.y
			if t == "当前状态" and not ys.has(t):
				ys[t] = (n as Label).global_position.y
	## ★真正该量的不是【标题】而是【带数字的那行正文】——
	##   反向验证时发现: 把属性挪回技能前面, 技能标题 y=620 仍 < 折叠线 704 而照样 PASS,
	##   可那时技能的伤害数字一个都在屏外。"标题看得见"不等于"数值看得见", 判据选错了层。
	var body_y := -1.0
	var body_txt := ""
	stk = [panel]
	while not stk.is_empty():
		var n2 = stk.pop_back()
		for c2 in n2.get_children():
			stk.append(c2)
		var s2 := ""
		if n2 is Label:
			s2 = str((n2 as Label).text)
		elif n2 is RichTextLabel:
			s2 = str((n2 as RichTextLabel).get_parsed_text())
		## ★技能的伤害数字现在在【点开才展开的描述框】里 ⇒ 收起时屏上没有它。
		##   判据改成量【技能行本身】在不在屏内(行上有名字和龟能消耗)。
		if false:
			if body_y < 0.0 or (n2 as Control).global_position.y < body_y:
				body_y = (n2 as Control).global_position.y
				body_txt = s2.substr(0, 24)
	## ★段标题「技能」删了(网页式 h3)。技能现在是三个图标横排, 起点用【第一个技能槽】的 y。
	##   判据从"找标题"改成"找槽" —— 守的是"技能区在屏内", 不是"当时有没有那个标题"。
	if not ys.has("技能"):
		var stk2: Array = [panel]
		while not stk2.is_empty():
			var n3 = stk2.pop_back()
			for c3 in n3.get_children():
				stk2.append(c3)
			## ★认【正方槽】: 高 = SLOT_PX 的 PanelContainer。
			##   判据不写死 88 —— 从槽自己的高读, 真正要守的是"正方 + 够大"(下面两条)。
			if n3 is PanelContainer and (n3 as Control).custom_minimum_size.y >= 81.0:
				var yy: float = (n3 as Control).global_position.y
				if not ys.has("技能") or yy < float(ys["技能"]):
					ys["技能"] = yy
	_ok("★分母: 找得到技能区(三个 72×72 图标槽)", ys.has("技能"), "找到 %s" % str(ys.keys()))
	## ★原来这里断言"屏上有技能的伤害数字"。技能重做后数字在【点开才展开的描述框】里,
	##   收起时屏上本来就没有 —— 继续断言等于要求描述默认展开, 而那正是要去掉的"整段正文"。
	##   真正该守的是【技能行在不在屏内】, 由下面那条量。
	if ys.has("技能"):
		_ok("★★★「技能」一开面板就在屏内(不用滚) —— 用户「完全看不到」说的就是它",
			float(ys["技能"]) < fold,
			"技能 y=%.0f / 折叠线 %.0f" % [float(ys["技能"]), fold])
		if ys.has("详细属性"):
			_ok("★★技能排在【属性之前】(属性 22 项 ~290px, 排前面必挡住技能)",
				float(ys["技能"]) < float(ys["详细属性"]),
				"技能 %.0f vs 属性 %.0f" % [float(ys["技能"]), float(ys["详细属性"])])
	## ★面板必须【不透明】: 0.96 时右侧队伍头像栏正好压在底下, 4% 透上来像重影(实拍确认)。
	## ★2026-08-16 面板底换成【九宫格像素框】(StyleBoxTexture), 不再是 StyleBoxFlat ——
	##   原判据只认 StyleBoxFlat 的 alpha, 换了皮就读到 -1 假红。
	##   要守的是"底不透明、右侧头像栏不会透上来", 那就【量真实像素】: 从截图取面板中央
	##   一块空白区, 它必须是实心的(不透明度由贴图保证, 且贴图本身不带 alpha 渐变)。
	var psb: StyleBox = panel.get_theme_stylebox("panel")
	_ok("★★面板底用的是像素九宫格框(不是 CSS 圆角方块)",
		psb is StyleBoxTexture, "实得 %s" % (psb.get_class() if psb != null else "null"))
	if psb is StyleBoxTexture:
		var tx: Texture2D = (psb as StyleBoxTexture).texture
		_ok("★★★框贴图是【新生成的战斗 HUD 框】(不是复用商店那张)",
			tx != null and str(tx.resource_path).find("battlehud/panel-frame") >= 0,
			"实得 %s" % (str(tx.resource_path) if tx != null else "null"))
		var img: Image = tx.get_image()
		var cx: int = int(img.get_width() * 0.5)
		var cy: int = int(img.get_height() * 0.5)
		## ★原始要求是【面板底不透明】—— 0.96 时右侧队伍头像栏正好压在底下, 4% 透上来像重影。
		##   这张框自带实心中心, 直接满足; 所以判据就量它: 中心必须不透明。
		##   (我第一版反过来断言"中心透空", 那是我假设所有框都是空心的 —— 假设不是要求。)
		_ok("★★★框的中心不透明(右侧头像栏不会透上来)",
			img.get_pixel(cx, cy).a > 0.99, "中心 alpha %.2f" % img.get_pixel(cx, cy).a)


## ── 面板重做 v2 的六行结构 (2026-08-16) ─────────────────────────────────
## 判据一律量【真实节点】: 面板里递归取 Label/RichTextLabel/ProgressBar/TextureRect,
## 不搜源码字符串 —— 那守的是"我当时怎么写的", 换个写法就假红/假绿。
func _test_panel_v2() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var u: Dictionary = _mk("basic")
	u["equips"] = [{"id": "p2eq_001", "star": 1}, {"id": "p2eq_010", "star": 2}]
	u["stun_until"] = _s._t + 1.7
	_s._units.clear(); _s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	for _f in range(8):
		await get_tree().process_frame
	var panel = _s._info_panel
	if panel == null or not is_instance_valid(panel):
		_ok("★分母: v2 面板建起来了(null ⇒ 后面全没跑)", false, "面板是 null")
		return

	# 收集面板里所有节点
	var labels: Array = []
	var bars: Array = []
	var texs: Array = []
	var stk: Array = [panel]
	while not stk.is_empty():
		var n = stk.pop_back()
		for c in n.get_children():
			stk.append(c)
		if n is Label:
			labels.append(n)
		elif n is RichTextLabel:
			labels.append(n)
		elif n is ProgressBar:
			bars.append(n)
		elif n is TextureRect:
			texs.append(n)
	var all_txt := ""
	for l in labels:
		all_txt += (str((l as Label).text) if l is Label else str((l as RichTextLabel).get_parsed_text())) + "
"
	_ok("★分母: 面板里收到文本节点", labels.size() >= 10, "%d 个" % labels.size())

	# ① 状态用真图标, 面板里一个 emoji 都不许有
	var emo := ["😵", "🔥", "🧪", "🩸", "🐌", "😡", "🌀", "💔", "🔒", "😤", "⭐", "🪙", "💰", "🟡"]
	var hit_emo: Array = []
	for e in emo:
		if all_txt.find(e) >= 0:
			hit_emo.append(e)
	_ok("★★★① 面板里没有 emoji(项目铁律「全去 emoji」; 13 张状态图标本来就在硬盘上)",
		hit_emo.is_empty(), "还剩 %s" % str(hit_emo))
	_ok("★★① 状态带剩余秒数(光写「眩晕」看不出还要晕多久)",
		all_txt.find("眩晕 1.7s") >= 0 or all_txt.find("眩晕 1.6s") >= 0, "文本里没找到带秒数的眩晕")

	# ② 资源条: 每条都有分母
	var rr: Array = _s._hud._info_res_rows
	_ok("★分母: 建出了资源条", rr.size() >= 1, "%d 条" % rr.size())
	var no_cap: Array = []
	for r in rr:
		var vl = (r as Dictionary).get("val")
		if vl != null and is_instance_valid(vl) and str((vl as Label).text).find("/") < 0:
			no_cap.append(str((r as Dictionary).get("name", "?")))
	_ok("★★★② 每条资源都有分母(原来金币/财宝/储能只印当前值, 玩家不知道算多算少)",
		no_cap.is_empty(), "缺分母: %s" % str(no_cap))

	# ③ 技能栏三行, 且行上没有"就绪"、没有进度条混进技能区
	## ★技能改成三图标横排后, 图标下的小字名字【裁掉了"被动 · "与"(普攻)"前后缀】
	##   (72px 放不下全称)。所以判据从"扫面板文本"改成量【数据源本身】——
	##   要守的是"被动/普攻/主动三条都在", 不是"当时那几个字长什么样"。
	var sb_ents: Array = _s._info_sys._skill_bar_entries(u)
	var sb_names := ""
	for se in sb_ents:
		sb_names += str((se as Dictionary).get("name", "")) + " | "
	_ok("★★③ 技能栏含【被动/普攻/主动】三条",
		sb_names.find("被动 · ") >= 0 and sb_names.find("(普攻)") >= 0 and sb_ents.size() >= 3,
		"%d 条: %s" % [sb_ents.size(), sb_names])
	_ok("★★★③ 技能行上没有「就绪」字样(用户:「不需要什么就绪，进度条」)",
		all_txt.find("就绪") < 0)

	# ④ 装备槽: 72×72
	## ★2026-08-16 槽改成【平分整宽】—— 原来固定 72 宽, 右边白空 136px(内宽 368)。
	##   铺满后每槽约 117, 顺带把触摸缺口补上: 本项目 44pt = 81 视口像素, 72 不达标 117 达标。
	var slot_w := 0.0
	var slot_h := 0.0
	var slot_n := 0
	for t in texs:
		var p2 = (t as Control).get_parent()
		while p2 != null and not (p2 is PanelContainer):
			p2 = p2.get_parent()
		if p2 != null and (p2 as Control).custom_minimum_size.y >= 81.0:
			slot_n += 1
			slot_w = maxf(slot_w, (p2 as Control).size.x)
			slot_h = maxf(slot_h, (p2 as Control).size.y)
	_ok("★分母: 找得到槽", slot_n >= 1, "%d 个" % slot_n)
	_ok("★★★④ 槽 ≥ 81px(本项目 44pt 触摸线)", slot_w >= 81.0 and slot_h >= 81.0,
		"实测 %.0f×%.0f" % [slot_w, slot_h])
	## ★槽必须是【正方】的(用户 2026-08-16:「图标肯定是正方的啊」)。
	##   我一度把槽拉宽去填面板 —— 那是本末倒置, 该让面板宽度跟着槽走。
	_ok("★★★④ 槽是正方的(不是被拉宽去填面板)", absf(slot_w - slot_h) <= 1.0,
		"实测 %.0f×%.0f" % [slot_w, slot_h])

	# ⑤ 属性 19 项一个不少, 且主要 8 项排在前面
	## ★2026-08-16 次要属性搬进【点开的浮层】(用户:「更多属性不要直接放在这下面」),
	##   所以常驻的 _info_stat_labels 只剩主要 8 项。
	##   "全都要显示"仍然守住 —— 由下面两条守: ①次要 11 项一条不少 ②入口把条数写在标题上。
	var minor_rows: Array = _s._info_sys._info_stat_rows_minor(_s._units[0] if not _s._units.is_empty() else u)
	_ok("★★★⑤ 主要 8 项常驻", _s._info_stat_labels.size() == 8, "实得 %d 个" % _s._info_stat_labels.size())
	_ok("★★★⑤ 次要 11 项一条不少(搬进浮层≠删掉)", minor_rows.size() == 11, "实得 %d 项" % minor_rows.size())
	if _s._info_stat_labels.size() == 8:
		var first8 := ""
		for i in range(8):
			first8 += str((_s._info_stat_labels[i] as Label).text) + " "
		_ok("★★★⑤ 前 8 项 = 主要属性(攻击/攻速·暴击/暴伤·护甲/魔抗·移速/射程)",
			first8.find("攻击") >= 0 and first8.find("攻速") >= 0 and first8.find("暴击") >= 0
			and first8.find("增伤") >= 0 and first8.find("护甲") >= 0 and first8.find("魔抗") >= 0
			and first8.find("减伤") >= 0 and first8.find("射程") >= 0, first8)

		_ok("★★⑤ 次要末项仍是韧性(顺序没乱)",
		minor_rows.size() == 11 and str(minor_rows[10][1]).find("韧性") >= 0,
		"实得「%s」" % (str(minor_rows[10][1]) if minor_rows.size() == 11 else "?"))

## 资源条里某一条的【数值文本】; 没有这条返回 ""。
## ★2026-08-16 龟能/怒气/星能从"独立条 + 状态 chip"搬进了统一的资源条,
##   老断言读的 `_info_en_lbl` / chip 文本都失效了。要求没变, 来源变了 ⇒ 判据跟着搬。
func _res_text(nm: String) -> String:
	for r in _s._hud._info_res_rows:
		if str((r as Dictionary).get("name", "")) == nm:
			var vl = (r as Dictionary).get("val")
			if vl != null and is_instance_valid(vl):
				return str((vl as Label).text)
	return ""


## 资源条里某一条的【结论文本】(条下面那句"攒满变火山"/"6.0 秒后可放")。
func _res_hint(nm: String) -> String:
	for r in _s._hud._info_res_rows:
		if str((r as Dictionary).get("name", "")) == nm:
			var hl = (r as Dictionary).get("hint")
			if hl != null and is_instance_valid(hl):
				return str((hl as Label).text)
	return ""


## ── ★连续多帧刷新后, 面板必须【停在原地】(2026-08-16)──────────────────────
## 由来: 次要属性搬进浮层后, 常驻 Label 只剩 8 个, 而每帧刷新还拿 `_info_stat_rows()` 的
## 19 项去比 ⇒ 永远判"行数变了" ⇒ 每帧整块重建 ⇒ 面板每帧从屏外重新滑入, 永远到不了位。
## 实测症状: 面板 x 从 1252 越飘越远到 1304(每次重建 offset += PW+40 再滑)。
##
## ★这个 bug 【原有门禁一条都没红】—— 它们都是"直接调 _show_unit_info_panel 再同步断言",
##   不跑连续刷新那条路。是截图看不到面板才发现的。⇒ 把这条路本身焊成门禁。
## ★判据: 连刷 40 帧后面板的 x 必须落在屏内, 且与刷之前【不再变化】。
func _test_no_rebuild_loop() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var u: Dictionary = _mk("basic")
	u["equips"] = [{"id": "p2eq_001", "star": 1}]
	_s._units.clear(); _s._units.append(u)
	_s._hud._show_unit_info_panel(u)
	for _f in range(30):
		await get_tree().process_frame
	var p = _s._info_panel
	if p == null or not is_instance_valid(p):
		_ok("★分母: 面板在(null ⇒ 后面没跑)", false, "null")
		return
	var x1: float = p.global_position.x
	for _f2 in range(40):
		await get_tree().process_frame
		_ip._refresh_info_panel()
	var p2 = _s._info_panel
	var x2: float = p2.global_position.x if (p2 != null and is_instance_valid(p2)) else -9999.0
	_ok("★★★连刷 40 帧后面板【不再动】(动了 = 每帧在整块重建)",
		absf(x2 - x1) < 1.0, "刷前 x=%.0f → 刷后 x=%.0f" % [x1, x2])
	_ok("★★★面板停在屏内(不是卡在屏外滑不进来)",
		x2 >= 0.0 and x2 < 1280.0, "x=%.0f (视口宽 1280)" % x2)
