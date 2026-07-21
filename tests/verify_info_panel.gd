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

	# ★0 值的不该占位(否则面板一片 0)
	var plain := {"atk": 10.0, "def": 1.0, "mr": 1.0, "crit": 0.0, "atk_interval": 1.0,
				  "atk_range": 100.0, "move_spd": 50.0}
	var rows2: Array = s._info_stat_rows(plain)
	var txt2 := ""
	for r in rows2:
		txt2 += str((r as Array)[1]) + " | "
	_ok("★没有的属性不占位(0 值不显示)",
		not txt2.contains("治疗强度") and not txt2.contains("闪避") and not txt2.contains("反伤"),
		txt2)
	_ok("★核心行数固定为 7(裸单位)", rows2.size() == 7, "实际 %d 行" % rows2.size())

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
	var ui := src.find("func _unhandled_input")
	var ui_body := src.substr(ui, 4000) if ui >= 0 else ""
	var pl := ui_body.find("_dl_state == \"place\"")
	var pl_body := ui_body.substr(pl, 700) if pl >= 0 else ""
	_ok("★放置阶段也能点空白关面板(这条早退曾把它挡掉)",
		pl_body.contains("_close_info_panel()"),
		"放置阶段仍只能靠 ESC 关" if not pl_body.contains("_close_info_panel()") else "")


## 精确取某个顶层函数的函数体(从它的 func 行到【下一个顶层 func】为止)。
## 用固定字符窗口截会把后面别的函数框进来 → 断言变恒真。
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
