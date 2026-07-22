extends Node
## verify_info_panel.gd — 守卫「局内详情面板」的四项改造(用户 2026-07-21 需求2)
##
##   2a 属性区要显示更多属性(治疗强度/护盾强度/闪避率等)
##   2b 小将的技能描述要能显示
##   2c 面板里所有数值要实时变化(原实现是一次性快照, 作者自己在源码里写了「从不刷新」)
##   2d 点空白处就退出面板, 去掉 ✖ 按钮
##
## ★这些都属于「改坏了不报错、只是界面上少个东西/不动了」, 只能靠测试守。

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SRC := "res://scripts/scenes/RealtimeBattle3DScene.gd"

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var s = RTScene.new()
	add_child(s)
	await get_tree().process_frame

	_test_stat_rows(s)
	_test_minion_skills(s)
	_test_live_refresh()
	_test_no_close_button()
	_test_placeholder_rendered(s)

	s.queue_free()
	print("ALL PASS — 详情面板(更多属性/小将技能/实时刷新/点空白关)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 2a. 属性区能显示新增的那些属性
func _test_stat_rows(s) -> void:
	# 造一只带全套新属性的单位
	var u := {
		"atk": 100.0, "def": 20.0, "mr": 15.0, "crit": 0.25, "atk_interval": 1.2,
		"atk_range": 300.0, "move_spd": 80.0, "maxHp": 1000.0, "hp": 600.0,
		"lifesteal": 0.10, "dodge_bonus": 0.15, "heal_amp": 0.30, "shield_amp": 0.25,
		"crit_dmg": 2.0, "armor_pen": 12.0, "magic_pen": 8.0, "reflect": 0.20,
		"tenacity": 0.35, "damage_reduction": 0.12, "damage_amp": 0.18, "echarge_perm": 0.40,
	}
	var rows: Array = s._info_stat_rows(u)
	var txt := ""
	for r in rows:
		txt += str((r as Array)[1]) + " | "
	# 用户点名要的三项
	_ok("★属性区含『治疗强度』", txt.contains("治疗强度"), txt)
	_ok("★属性区含『护盾强度』", txt.contains("护盾强度"))
	_ok("★属性区含『闪避』", txt.contains("闪避"))
	# 其余补充项
	for k in ["吸血", "暴伤", "护甲穿透", "魔法穿透", "反伤", "韧性", "减伤", "增伤", "龟能充能"]:
		_ok("属性区含『%s』" % k, txt.contains(k))
	# 核心 7 项恒在
	for k in ["攻击", "护甲", "魔抗", "暴击", "攻速", "射程", "移速"]:
		_ok("核心属性『%s』恒显示" % k, txt.contains(k))

	# ★用户 2026-07-21 第二轮明确「全都要显示啊」→ 裸单位也必须列全, 不能因为是 0 就藏起来。
	#   (第一版做成"有值才显示", 结果没装备的龟看不到治疗强度/护盾强度/闪避那几行。)
	var plain := {"atk": 10.0, "def": 1.0, "mr": 1.0, "crit": 0.0, "atk_interval": 1.0,
				  "atk_range": 100.0, "move_spd": 50.0}
	var rows2: Array = s._info_stat_rows(plain)
	var txt2 := ""
	for r in rows2:
		txt2 += str((r as Array)[1]) + " | "
	_ok("★裸单位也把所有属性列全(不因为是0就藏)",
		txt2.contains("治疗强度") and txt2.contains("护盾强度") and txt2.contains("闪避")
		and txt2.contains("反伤") and txt2.contains("韧性"),
		txt2)
	# ★★口径: 治疗/护盾强度是【乘算】(amt *= 1+amp), 基准是 100% 而不是 0
	#   —— 用户指出「治疗和护盾强度不是100%吗」, 原来显示成 +0% 是口径错误。
	_ok("★治疗强度基准 = 100%(乘算口径, 不是 +0%)", txt2.contains("治疗强度 100%"), txt2)
	_ok("★护盾强度基准 = 100%", txt2.contains("护盾强度 100%"))
	_ok("★暴伤基准 = 150%(crit_dmg 默认 1.5)", txt2.contains("暴伤 150%"))
	_ok("★龟能充能基准 = 100%", txt2.contains("龟能充能 100%"))
	# 加算类基准仍是 0
	_ok("加算类(闪避/反伤)基准为 0%", txt2.contains("闪避 0%") and txt2.contains("反伤 0%"))
	_ok("属性行数稳定(裸单位与满属性单位一致=恒显示)",
		rows2.size() == rows.size(), "裸 %d 行 / 满 %d 行" % [rows2.size(), rows.size()])

	# ★不许用 emoji 当图标(本项目已全去 emoji 根治绿块)
	var bad_icon := 0
	for r in rows:
		var ic := str((r as Array)[0])
		if ic != "" and not ic.begins_with("res://"):
			bad_icon += 1
	_ok("★图标只用真图片或留空, 不用 emoji", bad_icon == 0, "非法图标 %d 个" % bad_icon)


## 2b. 小将技能描述
func _test_minion_skills(s) -> void:
	var tbl: Dictionary = RTScene.MINION_SKILL_DESC
	_ok("小将技能文案表存在", tbl.size() >= 3, "%d 条" % tbl.size())
	for k in ["minionBodysurf", "minionRocket", "eliteHammer"]:
		_ok("小将技能『%s』有文案" % k, tbl.has(k) and str(tbl[k].get("desc", "")).length() > 10)

	# ★真正走一遍面板取条目的路径: 小将 pets.json 里没有条目, 必须靠这张表兜底
	var minion := {"id": "__minion__", "side": "left", "active_skills": ["minionRocket"]}
	var ents: Array = s._panel_skill_entries(minion)
	_ok("★小将能取到技能条目(原来这里是空的→技能区整块不渲染)", ents.size() >= 1,
		"取到 %d 条" % ents.size())
	if ents.size() > 0:
		var e: Dictionary = ents[0]
		_ok("小将技能条目有名字与描述",
			str(e.get("name", "")) != "" and str(e.get("desc", "")).length() > 10,
			"%s: %s" % [e.get("name", ""), str(e.get("desc", "")).substr(0, 30)])


## 2c. 实时刷新
func _test_live_refresh() -> void:
	var src := _src()
	_ok("★有 _refresh_info_panel(动态刷新函数)", src.contains("func _refresh_info_panel"))
	# 必须挂在每帧调用的 _update_team_panels 里。
	# ★函数体要【精确取到下一个顶层 func 为止】—— 我第一版用 substr(idx, 3000) 取固定窗口,
	#   把后面 `func _refresh_info_panel` 的【定义】也框了进去, 于是把挂钩删掉测试照样绿(假通过)。
	#   这个假通过是靠"故意改坏"才发现的, 所以反向验证不能省。
	var body := _func_body(src, "_update_team_panels")
	var hooked := body.contains("_refresh_info_panel()")
	_ok("★_refresh_info_panel 挂在每帧的 _update_team_panels 里", hooked,
		"" if hooked else "没挂上=面板还是静态快照(函数体 %d 字符)" % body.length())
	_ok("★取到的函数体不含它自己的定义(证明边界没框过头)",
		not body.contains("func _refresh_info_panel"))
	# 刷新要改已存在节点, 不是每帧重建(重建会打断滚动+每帧分配节点)
	_ok("刷新持有 HP 条/龟能条/属性行的节点引用",
		src.contains("_info_hp_bar") and src.contains("_info_en_bar") and src.contains("_info_stat_labels"))
	# 源码里那句「一次性快照, 从不刷新」的旧注释不该再留着误导人
	_ok("★旧注释『一次性快照, 从不刷新』已清除(否则会误导后来人)",
		not src.contains("详情面板整体是一次性快照"))

	# ★★用户点名的「下面的技能伤害数值」也要实时 —— 这块第一版整个漏了:
	#   面板直接贴 pets.json 原文, 于是 {N:0.7*ATK} / {{ATK}} 这类【占位符原样漏到界面上】。
	#   图鉴一直走 SkillText 渲染, 战斗面板没接。
	_ok("★战斗场接入了 SkillText 模板渲染器", src.contains("const SkillText := preload"))
	_ok("★有 _render_skill_text(把占位符按当前属性算成数字)",
		src.contains("func _render_skill_text"))
	var rb := _func_body(src, "_refresh_info_panel")
	_ok("★技能描述纳入每帧刷新(伤害数值跟着属性变)",
		rb.contains("_info_skill_lbls"), "刷新函数体 %d 字符" % rb.length())
	_ok("★被动描述也纳入每帧刷新", rb.contains("_info_passive_tpl"))
	# ★「当前状态」chips(护盾/灼烧/眩晕/怒气…)在战斗中变得最频繁, 原来也是建一次就不动
	_ok("★状态 chips 纳入刷新(护盾/灼烧/眩晕会跟着变)", rb.contains("_info_status_box"),
		"" if rb.contains("_info_status_box") else "状态区还是死的")
	_ok("★状态用签名节流(不每帧无脑重建节点→不闪不掉帧)",
		src.contains("func _status_signature") and rb.contains("_info_status_sig"))
	# 面板取技能条目时必须渲染, 不能再直接 _strip_html 原文
	var pe := _func_body(src, "_panel_skill_entries")
	_ok("★技能条目走模板渲染(不再原样贴 pets.json)",
		pe.contains("_render_skill_text"), "仍在直接 _strip_html 原文 = 占位符会漏出来")


## 2d. 去掉 ✖ + 点空白关
func _test_no_close_button() -> void:
	var src := _src()
	var has_btn := src.contains("close_btn")
	_ok("★面板不再有 ✖ 关闭按钮", not has_btn, "仍有 close_btn" if has_btn else "")
	# 点空白关闭的逻辑要在(普通战斗 + 放置阶段 都要能关)
	var n_close := src.count("_close_info_panel()")
	_ok("点空白/ESC 关闭逻辑仍在", n_close >= 3, "_close_info_panel 调用 %d 处" % n_close)
	# ★要在 _unhandled_input 里面找那处放置阶段早退 —— 全文搜 `_dl_state == "place"`
	#   会命中别处(第一次我就这么搜错了, 报了假 FAIL)。
	# ★字符窗口两头都是坑, 2026-07-22 一天之内两个方向都踩了:
	#   窗口太小 → substr(ui,4000) 再 substr(pl,700) 实际只剩 255 字符, 把 _close_info_panel()
	#              切在窗口外 → 假 FAIL(我差点据此去"修"一个根本没坏的功能);
	#   窗口太大 → 放开成 substr(pl) 取到函数尾, 而 _unhandled_input 里 _close_info_panel()
	#              共 3 处, 后面普通战斗分支那处顶包 → 把放置分支的调用删掉照样绿(实测过), 断言变哑。
	#   所以必须【按缩进精确切出这一个分支】, 且下面留了一条自检不许再放宽。
	var ui_body := _func_body(src, "_unhandled_input")
	var pl_body := _branch_body(ui_body, "_dl_state == \"place\"")
	_ok("★放置阶段也能点空白关面板(这条早退曾把它挡掉)",
		pl_body.contains("_close_info_panel()"),
		"放置阶段仍只能靠 ESC 关(切出的分支 %d 字符)" % pl_body.length())
	# ★自检: 切出来的必须【只是这一个分支】。放置分支自己以 _dl_handle_place_input 收尾,
	#   若切片漏到了后面的普通战斗分支, 就会把 unproject/_open_info_panel 那些一起框进来。
	_ok("切片没漏到隔壁分支(否则上一条会变成恒真的哑断言)",
		pl_body.contains("_dl_handle_place_input") and not pl_body.contains("_open_info_panel"),
		"切出 %d 字符, 含隔壁分支内容" % pl_body.length())


## 按【缩进】切出 anchor 所在的那一个分支: 从含 anchor 的行起, 到下一条缩进
## ≤ 该行缩进的非空行为止。字符数窗口切不准分支边界(小了漏内容、大了框进隔壁)。
func _branch_body(body: String, anchor: String) -> String:
	var lines := body.split("\n")
	var start := -1
	var base := 0
	var out := ""
	for i in lines.size():
		var l := str(lines[i])
		if start < 0:
			if l.contains(anchor):
				start = i
				base = l.length() - l.lstrip("\t").length()
				out = l + "\n"
			continue
		var stripped := l.strip_edges()
		if stripped != "" and (l.length() - l.lstrip("\t").length()) <= base:
			break
		out += l + "\n"
	return out


## 精确取某个顶层函数的函数体(从它的 func 行到【下一个顶层 func】为止)。
## 用固定字符窗口截会把后面别的函数框进来 → 断言变恒真。
## ★行为级: 真渲染一段带占位符的模板, 出来的必须是【数字】而不是 {N:...}
## 用户 2026-07-21 在面板截图里直接看到了 "{N:0.7*ATK}" 和 "{{ATK}}" 漏在界面上。
func _test_placeholder_rendered(s) -> void:
	var u := {"atk": 100.0, "maxHp": 1000.0, "hp": 1000.0, "def": 10.0, "mr": 10.0,
			  "crit": 0.0, "level": 1, "id": "basic"}
	var tpl := "造成 {N:0.7*ATK} 点物理伤害"
	var out: String = s._render_skill_text(tpl, u, {})
	_ok("★占位符被算成数字(不再原样漏到界面)",
		not out.contains("{N:") and not out.contains("{{"), "渲染结果: %s" % out)
	# ATK=100 → 0.7*ATK = 70, 结果里应出现 70
	_ok("★算出来的数值正确(ATK=100 → 0.7×ATK=70)", out.contains("70"), "渲染结果: %s" % out)
	# 属性变了, 渲染结果要跟着变(这就是"实时"的本质)
	u["atk"] = 200.0
	var out2: String = s._render_skill_text(tpl, u, {})
	_ok("★★属性变化后重渲染的数字跟着变(ATK翻倍→140)",
		out2.contains("140") and out2 != out, "ATK=200 渲染: %s" % out2)


func _func_body(src: String, fname: String) -> String:
	var lines := src.split("\n")
	var out := ""
	var inside := false
	for line in lines:
		if line.begins_with("func " + fname + "("):
			inside = true
			continue
		if inside and line.begins_with("func "):
			break
		if inside:
			out += line + "\n"
	return out


func _src() -> String:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
