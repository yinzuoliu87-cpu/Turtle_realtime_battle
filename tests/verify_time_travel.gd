extends Node
## verify_time_travel.gd — 开发包时间穿越(测赛程不用等日子)的门禁 (2026-10-04)
##
## 用户 2026-10-04:「由于现在我们规定好了每周的哪些天是哪些比赛, 那测试的话我们只能等到
##   对应日期, 还是我们有什么更好的办法」。方案书 docs/plans/20261004-时间穿越测试.md。
##
## 量的是**真入口**: 环境变量 `TURTLE_FAKE_NOW` 走 `phase2_config.now_utc()` 第一次读时钟那条路;
## 主菜单赛程条「今」与角标是真把 MainMenu.tscn 建出来数节点; 设置页按钮/弹层是真建 SettingsScene。
##   ① `sat 15:00` ⇒ phase_at_utc(now_utc()) = 闯关赛, 主菜单赛程条「今」落在闯关赛那格, 角标在
##   ② `sun 08:05` ⇒ 决赛日
##   ③ 时间随真实流逝往前走(不是冻住)
##   ④ 正式包条件(SHIP 环境变量 = 项目现成的「按正式包语义跑」开关)下: 环境变量/已有偏移/设置页入口全无效
##   ⑤ 「恢复真实时间」后回到真实, 环境变量不会再冒回来
##   ⑥ 解析: ISO 写法与非法写法
## ★每条都配分母: 「真实时间那天恰好就是周六」时 ① 会碰巧绿 ⇒ ① 同时断言偏移确实非 0,
##   ⑤ 里主菜单回到真实后「今」那格必须跟着真实星期几走(与 ① 的答案是同一把尺子量出来的两个值)。
##
## 跑法:
##   APPDATA=<scratch> TURTLE_BACKEND=" " TURTLE_SUPABASE=" " \
##   <godot> --headless --path . res://tests/verify_time_travel.tscn --quit-after 3000

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")
const TTP := preload("res://scripts/scenes/settings/time_travel_panel.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [name, detail])


func _real() -> int:
	return int(Time.get_unix_time_from_system())


## 模拟「进程刚启动、第一次读时钟」: 环境变量设好, 让缝重新读一次。
func _boot_with_env(v: String) -> void:
	OS.set_environment(P2.TRAVEL_ENV, v)
	P2.travel_offset_sec = 0
	P2._travel_env_read = false


func _collect_text(n: Node, out: Array) -> void:
	if n is Label and (n as Label).visible:
		out.append(str((n as Label).text))
	if n is Button and (n as Button).visible:
		out.append(str((n as Button).text))
	for c in n.get_children():
		_collect_text(c, out)


## 建主菜单, 返回 [赛程条上标了「今」的那些文字, 角标文字("" = 没有)]。
func _menu_probe() -> Array:
	var menu: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	if menu is Control:
		(menu as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(menu as Control).size = Vector2(1280, 720)
	for _i in range(30):
		await get_tree().process_frame
	var txt: Array = []
	_collect_text(menu, txt)
	## 2026-10-06: 赛程从七格横条(「闯关赛 今」那种字)换成弹层里的四张阶段卡 ——
	##   「今」不再是字, 是今天那张卡外面那圈金边(卡下的 `TodayFrame`)。
	##   ⇒ 数**带金边的卡**, 返回它们的标题(`CardTitle`), 判据照旧「恰好一张 + 是哪一阶段」。
	var todays: Array = []
	var cards: Node = menu.find_child(str(MM.WEEK_CARDS_NAME), true, false)
	if cards != null:
		for card in cards.find_children(str(MM.WEEK_CARD_PREFIX) + "*", "", true, false):
			if card.get_node_or_null("TodayFrame") != null:
				var tt: Node = card.find_child("CardTitle", true, false)
				todays.append(str((tt as Label).text) if tt is Label else str(card.name))
	var badge: Node = menu.find_child(MM.TRAVEL_BADGE_NAME, true, false)
	var btxt: String = str((badge as Label).text) if badge is Label else ""
	var total: int = txt.size()
	menu.queue_free()
	await get_tree().process_frame
	return [todays, btxt, total]


func _settings_texts() -> Array:
	var sc: Node = (load("res://scenes/Settings.tscn") as PackedScene).instantiate()
	add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	var txt: Array = []
	_collect_text(sc, txt)
	return [sc, txt]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true   # 不写盘
	## 现场保存(static ⇒ 活过场景切换 ⇒ 必须还原)
	var k_ovr: int = P2.now_override_ts
	var k_off: int = P2.travel_offset_sec
	var k_read: bool = P2._travel_env_read
	var k_ship: bool = OS.has_environment("SHIP")
	var k_ship_v: String = OS.get_environment("SHIP")
	var k_env: String = OS.get_environment(P2.TRAVEL_ENV)
	P2.now_override_ts = 0
	OS.unset_environment("SHIP")

	print("── 0. 前提 ──")
	_ok("★分母: 这个进程是开发包语义(is_debug_build 且没设 SHIP) ⇒ 穿越被允许",
		P2.time_travel_allowed(), "debug=%s" % str(OS.is_debug_build()))

	# ── ① sat 15:00 ──
	print("── ① TURTLE_FAKE_NOW=sat 15:00 ⇒ 闯关赛 ──")
	_boot_with_env("sat 15:00")
	var n1: int = P2.now_utc()
	var d1: Dictionary = Time.get_datetime_dict_from_unix_time(n1)
	_ok("① phase_at_utc(now_utc()) = 闯关赛", P2.phase_at_utc(n1) == P2.PHASE_GAUNTLET, P2.phase_at_utc(n1))
	_ok("① 星期六 15:00 UTC", P2.iso_weekday_utc(n1) == 6 and int(d1.hour) == 15 and int(d1.minute) == 0,
		"wd=%d %02d:%02d" % [P2.iso_weekday_utc(n1), int(d1.hour), int(d1.minute)])
	_ok("① 落在**本周**(真实时间所在那一周)", P2.week_anchor_utc(n1) == P2.week_anchor_utc(_real()))
	_ok("① ★分母: 偏移确实非 0(不是真实时间碰巧就是那一刻)", P2.travel_offset_sec != 0 and P2.travel_active(),
		"offset=%d" % P2.travel_offset_sec)
	var m1: Array = await _menu_probe()
	_ok("① ★分母: 主菜单建出来了", int(m1[2]) > 30, "%d 条字" % int(m1[2]))
	_ok("① 主菜单赛程条恰好一格标「今」, 且是闯关赛那格",
		(m1[0] as Array).size() == 1 and str((m1[0] as Array)[0]).begins_with(str(P2.PHASE_LABEL[P2.PHASE_GAUNTLET])),
		str(m1[0]))
	_ok("① 主菜单角落有「测试时间 周六 15:00 UTC · 不联网」", str(m1[1]) == "测试时间 周六 15:00 UTC · 不联网", "'%s'" % str(m1[1]))

	# ── ② sun 08:05 ──
	print("── ② TURTLE_FAKE_NOW=sun 08:05 ⇒ 决赛日 ──")
	_boot_with_env("sun 08:05")
	var n2: int = P2.now_utc()
	var d2: Dictionary = Time.get_datetime_dict_from_unix_time(n2)
	_ok("② phase_at_utc(now_utc()) = 决赛日", P2.phase_at_utc(n2) == P2.PHASE_FINALS, P2.phase_at_utc(n2))
	_ok("② 星期日 08:05 UTC", P2.iso_weekday_utc(n2) == 7 and int(d2.hour) == 8 and int(d2.minute) == 5,
		"wd=%d %02d:%02d" % [P2.iso_weekday_utc(n2), int(d2.hour), int(d2.minute)])
	_ok("② 中文简写同义: 周日 08:05 解析成同一刻",
		P2.parse_fake_now("周日 08:05", _real()) == P2.parse_fake_now("SUN 08:05", _real()))

	# ── ③ 时间往前走 ──
	print("── ③ 假起点 + 真实流逝 ──")
	var a: int = P2.now_utc()
	var ra: int = _real()
	OS.delay_msec(2100)
	var b: int = P2.now_utc()
	var rb: int = _real()
	_ok("③ 2.1 秒后假时钟也往前走了约 2 秒(不是冻住)", b - a >= 1 and b - a <= 4, "Δ=%d" % (b - a))
	_ok("③ 假时钟走的与真实时钟走的一样多(偏移不变)", (b - rb) == (a - ra) or abs((b - rb) - (a - ra)) <= 1,
		"偏移 %d → %d" % [a - ra, b - rb])

	# ── ④ 正式包条件 ──
	print("── ④ 正式包条件(SHIP) 下一律无效 ──")
	OS.set_environment("SHIP", "1")
	_ok("④ time_travel_allowed() = false", not P2.time_travel_allowed())
	## 已有偏移(上一步 sun 08:05 留下的)也不许生效 —— 判据在每次读时钟时都判
	var r4: int = _real()
	_ok("④ 已有的穿越偏移被无视: now_utc() == 真实时间", abs(P2.now_utc() - r4) <= 1,
		"now_utc-real=%d (offset 仍是 %d)" % [P2.now_utc() - r4, P2.travel_offset_sec])
	## 环境变量设了 + 第一次读时钟 ⇒ 也不生效
	_boot_with_env("sat 15:00")
	_ok("④ 设了 TURTLE_FAKE_NOW 也无效: now_utc() == 真实时间", abs(P2.now_utc() - _real()) <= 1,
		"Δ=%d" % (P2.now_utc() - _real()))
	_ok("④ travel_active() = false / 角标文字为空", not P2.travel_active() and P2.travel_badge_text() == "")
	_ok("④ travel_to() 拒绝并且不留偏移", not P2.travel_to(_real() + 86400) and P2.travel_offset_sec == 0,
		"offset=%d" % P2.travel_offset_sec)
	var m4: Array = await _menu_probe()
	_ok("④ 主菜单不建角标", str(m4[1]) == "", "'%s'" % str(m4[1]))
	var s4: Array = await _settings_texts()
	_ok("④ ★分母: 设置页建出来了", (s4[1] as Array).size() > 5, "%d 条字" % (s4[1] as Array).size())
	_ok("④ 设置页没有「测试时间」入口", not (s4[1] as Array).has("测试时间"), str(s4[1]))
	(s4[0] as Node).queue_free()
	OS.unset_environment("SHIP")
	## 源码那半: release 导出包里 is_debug_build() = false —— 无头门禁跑不出 release 模板,
	##   只能钉住判据就是它, 而且不认 DEVTOOLS(那个能让 release 包里出现调试场)。
	var src: String = FileAccess.get_file_as_string("res://scripts/gamedata/phase2_config.gd").replace(char(13), "")
	var i0: int = src.find("static func time_travel_allowed() -> bool:")
	var body: String = src.substr(i0, src.find("\n\n", i0) - i0) if i0 >= 0 else ""
	_ok("④ ★分母: 切到了 time_travel_allowed 的函数体", body.length() > 40, "%d 字" % body.length())
	_ok("④ 判据 = OS.is_debug_build() 且没有 SHIP, 不认 DEVTOOLS",
		body.find("OS.is_debug_build()") >= 0 and body.find("\"SHIP\"") >= 0 and body.find("DEVTOOLS") < 0)

	# ── ⑤ 恢复真实时间 ──
	print("── ⑤ 恢复真实时间 ──")
	_boot_with_env("sat 15:00")
	_ok("⑤ ★分母: 恢复之前确实在穿越", P2.travel_active() and P2.phase_at_utc(P2.now_utc()) == P2.PHASE_GAUNTLET)
	P2.travel_reset()
	_ok("⑤ travel_reset() 后 now_utc() == 真实时间", abs(P2.now_utc() - _real()) <= 1, "Δ=%d" % (P2.now_utc() - _real()))
	_ok("⑤ 环境变量还在, 但不再冒回来", OS.get_environment(P2.TRAVEL_ENV) == "sat 15:00" and not P2.travel_active())
	var m5: Array = await _menu_probe()
	var real_ph: String = P2.phase_at_utc(_real())
	_ok("⑤ 主菜单角标消失", str(m5[1]) == "", "'%s'" % str(m5[1]))
	_ok("⑤ 赛程条「今」回到真实那一天(%s)" % real_ph,
		(m5[0] as Array).size() == 1 and str((m5[0] as Array)[0]).begins_with(str(P2.PHASE_LABEL[real_ph])),
		str(m5[0]))

	## 设置页入口 → 弹层 → 穿越 → 恢复(手机上走的就是这条)
	print("── ⑤b 设置页「测试时间」弹层 ──")
	OS.unset_environment(P2.TRAVEL_ENV)
	var s5: Array = await _settings_texts()
	var sc: Node = s5[0]
	_ok("⑤b 开发包设置页有「测试时间」入口", (s5[1] as Array).has("测试时间"), str(s5[1]))
	_ok("⑤b 调试场入口还在(并排, 没被挤掉)", str(s5[1]).find("调试场") >= 0)
	sc.call("_open_time_travel")
	await get_tree().process_frame
	var panel = sc.get("tt_panel")
	var layer: Node = sc.find_child(TTP.LAYER_NAME, true, false)
	_ok("⑤b ★分母: 弹层建出来了", panel != null and layer != null)
	if panel != null:
		var ptxt: Array = []
		_collect_text(layer, ptxt)
		_ok("⑤b 弹层里有周一~周日七个按钮", ptxt.has("周一") and ptxt.has("周日"), str(ptxt))
		panel.pick_day(6)
		panel.hour = 15
		panel.minute = 0
		panel.apply()
		var n5: int = P2.now_utc()
		_ok("⑤b 选周六 15:00 → 穿越 ⇒ 闯关赛", P2.phase_at_utc(n5) == P2.PHASE_GAUNTLET and P2.travel_active(),
			P2.travel_label(n5))
		panel.pick_day(7)
		panel.hour = 8
		panel.minute = 0
		panel.nudge(5)
		panel.apply()
		var n6: int = P2.now_utc()
		var d6: Dictionary = Time.get_datetime_dict_from_unix_time(n6)
		_ok("⑤b 选周日 08:00 再 +5 分 → 决赛日 08:05",
			P2.phase_at_utc(n6) == P2.PHASE_FINALS and int(d6.hour) == 8 and int(d6.minute) == 5, P2.travel_label(n6))
		panel.reset()
		_ok("⑤b 弹层「恢复真实时间」⇒ 回到真实", not P2.travel_active() and abs(P2.now_utc() - _real()) <= 1)
		panel.close()
	sc.queue_free()

	# ── ⑥ 解析 ──
	print("── ⑥ 解析 ──")
	## 2026-09-14 周一 00:00 UTC(verify_matchmaking_phase 同一个锚点) + 26 天 = 2026-10-10 周六
	var sat_1010: int = 1789344000 + 26 * 86400 + 15 * 3600
	_ok("⑥ ISO 2026-10-10T15:00Z", P2.parse_fake_now("2026-10-10T15:00Z", _real()) == sat_1010,
		"%d vs %d" % [P2.parse_fake_now("2026-10-10T15:00Z", _real()), sat_1010])
	_ok("⑥ ISO 带秒 / 空格分隔", P2.parse_fake_now("2026-10-10 15:00:30", _real()) == sat_1010 + 30)
	_ok("⑥ 那一刻确实是闯关赛(锚点自检)", P2.phase_at_utc(sat_1010) == P2.PHASE_GAUNTLET)
	var bad: Array = []
	for s in ["fri 25:00", "xyz 10:00", "garbage", "", "2026-10-10T24:00Z", "sat 15:60"]:
		if P2.parse_fake_now(s, _real()) != -1:
			bad.append(s)
	_ok("⑥ 非法写法一律 -1(按真实时间走)", bad.is_empty(), str(bad))
	_boot_with_env("garbage")
	_ok("⑥ 环境变量写坏 ⇒ 不穿越", not P2.travel_active())

	# ── ⑦ 不许穿出本周 ──
	print("── ⑦ 只许在本周(UTC 周一 00:00 ~ 下周一 00:00)内穿越 ──")
	var r7: int = _real()
	var mon0: int = P2.week_anchor_utc(r7)
	var next_wk: String = Time.get_datetime_string_from_unix_time(mon0 + 7 * 86400 + 15 * 3600) + "Z"
	var last_wk: String = Time.get_datetime_string_from_unix_time(mon0 - 86400 + 15 * 3600) + "Z"
	var this_wk: String = Time.get_datetime_string_from_unix_time(mon0 + 5 * 86400 + 15 * 3600) + "Z"
	_ok("⑦ ★分母: 三个 ISO 写法都解析得出来", P2.parse_fake_now(next_wk, r7) > 0
		and P2.parse_fake_now(last_wk, r7) > 0 and P2.parse_fake_now(this_wk, r7) > 0, "%s / %s / %s" % [next_wk, last_wk, this_wk])
	_boot_with_env(next_wk)
	_ok("⑦ 环境变量写下周的日期 ⇒ 拒绝(不穿越)", not P2.travel_active(), next_wk)
	_boot_with_env(last_wk)
	_ok("⑦ 环境变量写上周的日期 ⇒ 拒绝", not P2.travel_active(), last_wk)
	_boot_with_env(this_wk)
	_ok("⑦ ★分母: 本周的完整日期 ⇒ 照常穿越(拒绝不是一刀切)", P2.travel_active()
		and P2.phase_at_utc(P2.now_utc()) == P2.PHASE_GAUNTLET, this_wk)
	P2.travel_reset()
	_ok("⑦ travel_to 下周一 00:00 ⇒ 拒绝", not P2.travel_to(mon0 + 7 * 86400) and not P2.travel_active())
	_ok("⑦ travel_to 本周一 00:00 前一秒 ⇒ 拒绝", not P2.travel_to(mon0 - 1) and not P2.travel_active())
	_ok("⑦ ★边界: 本周一 00:00 整 ⇒ 允许", P2.travel_to(mon0) and P2.travel_active())
	P2.travel_reset()
	var days_ok := 0
	for wd7 in range(1, 8):
		if P2.travel_to_weekday(wd7, 0, 0) and P2.week_anchor_utc(P2.now_utc()) == mon0:
			days_ok += 1
	_ok("⑦ 弹层能选的周一~周日 00:00 全都落在本周、全都允许", days_ok == 7, "%d/7" % days_ok)
	P2.travel_reset()
	## 假时间随真实流逝走出本周 ⇒ 自动回到真实时间
	P2.travel_offset_sec = (mon0 + 7 * 86400 + 5) - _real()
	P2._travel_env_read = true
	_ok("⑦ 假时间走出了本周 ⇒ 自动回到真实时间(不滚进下一周)", not P2.travel_active()
		and P2.travel_offset_sec == 0 and abs(P2.now_utc() - _real()) <= 1, "offset=%d" % P2.travel_offset_sec)

	# ── 还原 ──
	P2.now_override_ts = k_ovr
	P2.travel_offset_sec = k_off
	P2._travel_env_read = k_read
	if k_ship:
		OS.set_environment("SHIP", k_ship_v)
	else:
		OS.unset_environment("SHIP")
	if k_env != "":
		OS.set_environment(P2.TRAVEL_ENV, k_env)
	else:
		OS.unset_environment(P2.TRAVEL_ENV)

	print("\n断言 %d 条, 失败 %d 条" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
