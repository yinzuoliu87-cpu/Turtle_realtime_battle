extends Node
## verify_topbar_states.gd — 顶部栏(PK 条)五种状态上屏的东西对不对(2026-10-07 顶部栏重做)
##
## 用户拍板(逐字): 「中间弄vs，计时放在VS下面」「我们这又不是倒计时」
##   「百分比和数值可以加，但这么搞很丑啊」「加时、团灭、破蛋的新显示方案行」
##
## 走真实建场入口(蛋只有 _dl_build_lane_field 才会生), 一步一步喂 sim(_deterministic + _sim_step),
## 渲染路(_pk_tick / _dl_update_hud)也手动按同一步长喂 —— 不靠帧率、不等 tween。
## 判据量的是【屏幕上的节点】: 计时牌的字与颜色、徽章读数、戳/大字是否可见、填充宽度、路点颜色、碎片数。
##
##   A 平时:   计时牌「上路战场 m:ss」正着走 / 头像 / 名字 / 三路点 / 百分比斜牌挂在条外端下面
##   B 加时:   一次性大字「加时！」(1.2 秒后收) / 牌子「加时 0:4x」橙红 / 两枚徽章 +25%→+50% 且换档会跳一下 /
##             点徽章出一行说明、点别处关 / 旧句子「加时 +X%增伤 · 治疗-50%」与头顶「决胜!」都不再出现
##   C 团灭:   那一侧「团灭」戳 + 头像压灰 + 主条清空 / 那一侧蛋副条变亮(围栏破), 另一侧仍压暗 /
##             牌子「破蛋 0:10」倒数, 最后 3 秒变红
##   D 定局路: 路点按 lane_results 上队色 / 牌子「破蛋定胜负」
##   E 蛋碎:   那一侧蛋副条当场清空 + 碎片 / 结算照常走
##
## 跑法: SHIP=1 <godot> --headless --audio-driver Dummy --path . res://tests/verify_topbar_states.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const DL := preload("res://scripts/scenes/battle/dual_lane_flow.gd")
const DT := 1.0 / 60.0
const NEED := 44   # 分母: 断言条数一条不能少(少了 = 半路中止)

var _n := 0
var _fail := 0
var s = null
var gs = null
var h = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1560, 720)
	gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.season_level = 5
	gs.nickname = "海带拌饭"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	gs.dual_active = true
	gs.current_lane = "top"
	gs.lane_results = {}
	print("=== 顶部栏五种状态 ===")
	s = RB.new()
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	s._deterministic = true
	s.set_process(false)
	h = s._hud
	await _t_normal()
	await _t_overtime()
	await _t_wipe()
	await _t_decider()
	await _t_egg_break()
	_done()


# ── A ─────────────────────────────────────────────────────────────
func _t_normal() -> void:
	print("  ── A 平时 ──")
	await _fresh("top")
	var tb = h._topbar
	_ok("A0 ★分母: 双路模式, 顶栏状态层与计时牌都建出来了(牌子挂在 PK 条里的 LanePlate 上)",
		tb != null and s._dl_hud != null and is_instance_valid(s._dl_hud)
		and str(s._dl_hud.get_parent().name) == "LanePlate" and h._pk_bar.is_ancestor_of(s._dl_hud))
	_go(2.2)
	var t1: String = s._dl_hud.text
	_go(3.0)
	var t2: String = s._dl_hud.text
	_ok("A1 计时牌写「上路战场 m:ss」", _re("^上路战场 \\d+:\\d\\d$", t1) and _re("^上路战场 \\d+:\\d\\d$", t2), "%s / %s" % [t1, t2])
	_ok("A2 ★计时【正着走】(不是倒计时): 3 秒后读数变大", _secs(t2) - _secs(t1) == 3, "%s → %s" % [t1, t2])
	_ok("A3 计时牌平时是金黄", _col(s._dl_hud) == DL.DL_PLATE_COL, str(_col(s._dl_hud)))
	_ok("A4 两端头像都拿到了领队立绘, 右边那只翻过来朝里", tb.port_l.texture != null and tb.port_r.texture != null
		and tb.port_r.flip_h and not tb.port_l.flip_h)
	var g: Dictionary = gs.dual_ghost
	_ok("A5 名字: 左 = 自己的显示名, 右 = 对手快照里的名字", tb.name_l.text == str(Backend.player_display_name())
		and tb.name_r.text == str(g["profile"]["name"]) and tb.name_l.visible and tb.name_r.visible,
		"%s / %s" % [tb.name_l.text, tb.name_r.text])
	_ok("A6 三路点: 3 颗, 现在打第 1 颗, 一路都没打完 ⇒ 三颗芯都是暗的",
		tb.dot_cores.size() == 3 and tb.current_dot() == 0 and _all_dark(tb.dot_cores))
	var bar_r: Rect2 = (h._pk_bar as Control).get_global_rect()
	var tl: Rect2 = h._pk_tag_l.get_global_rect()
	var tr: Rect2 = h._pk_tag_r.get_global_rect()
	_ok("A7 ★百分比斜牌挂在主条【下面】(不压在条里)", tl.position.y >= bar_r.position.y + h.PK_H - 0.5
		and tr.position.y >= bar_r.position.y + h.PK_H - 0.5, "条顶 %.0f 牌顶 %.0f" % [bar_r.position.y, tl.position.y])
	_ok("A8 ★两块斜牌各贴自己那一侧的外端", absf(tl.position.x - bar_r.position.x) < 0.5 and absf(tr.end.x - bar_r.end.x) < 0.5,
		"条 x[%.0f..%.0f] 左牌 %.0f 右牌止 %.0f" % [bar_r.position.x, bar_r.end.x, tl.position.x, tr.end.x])
	_ok("A9 斜牌读数: 百分比 + 绝对血量", h._pk_lab_l.text.ends_with("%") and h._pk_lab_l2.text != "", h._pk_lab_l.text + " " + h._pk_lab_l2.text)
	_ok("A10 平时: 徽章 / 团灭戳 / 加时大字都不出现",
		not tb.badge_amp.visible and not tb.badge_heal.visible and not tb.stamps["left"].visible
		and not tb.stamps["right"].visible and not tb.splash.visible)


# ── B ─────────────────────────────────────────────────────────────
func _t_overtime() -> void:
	print("  ── B 加时 ──")
	var tb = h._topbar
	var floats0: int = _count_float_text("决胜!")
	s._sd_t0 = s._t - (s.SD_START - 0.05)
	_go(0.2)
	_ok("B0 ★分母: 进加时了(第 1 档)", s._sd_stacks == 1, "stacks=%d" % s._sd_stacks)
	_ok("B1 ★一次性大字「加时！」出现了", tb.splash.visible and tb.splash_lab.text == "加时！")
	_ok("B2 ★头顶那一排「决胜!」飘字不再出现", _count_float_text("决胜!") == floats0)
	var t: String = s._dl_hud.text
	_ok("B3 计时牌变成「加时 0:4x」(正着走, 接着这一路的钟)", _re("^加时 0:4\\d$", t), t)
	_ok("B4 计时牌橙红", _col(s._dl_hud) == DL.DL_PLATE_OT_COL, str(_col(s._dl_hud)))
	_ok("B5 ★旧句子「加时 +X%增伤 · 治疗-50%」已删(牌子上没有句子)", not t.contains("增伤") and not t.contains("治疗") and not t.contains("·"), t)
	_ok("B6 两枚徽章都亮: 增伤 +25% / 治疗 -50%", tb.badge_amp.visible and tb.badge_heal.visible
		and tb.badge_amp_lab.text == "+25%" and tb.badge_heal_lab.text == "-50%",
		"%s / %s" % [tb.badge_amp_lab.text, tb.badge_heal_lab.text])
	_go(SplashWait())
	_ok("B7 ★大字是一次性的: 1.2 秒后收掉", not tb.splash.visible)
	s._sd_t0 = s._t - (s.SD_START + s.SD_STEP - 0.05)
	_go(0.1)
	_ok("B8 ★换档: 第 2 档徽章读数 +50%", s._sd_stacks == 2 and tb.badge_amp_lab.text == "+50%",
		"stacks=%d %s" % [s._sd_stacks, tb.badge_amp_lab.text])
	_ok("B9 换档那一下徽章会跳(放大)", tb.badge_amp.scale.x > 1.05, "scale=%.3f" % tb.badge_amp.scale.x)
	# 点徽章: 走真输入(push_input 到徽章中心), 不直接调回调
	await get_tree().process_frame
	_click(tb.badge_amp.get_global_rect().get_center())
	await get_tree().process_frame
	_ok("B10 ★点增伤徽章 ⇒ 出一行说明, 数字来自战斗常量", tb.popup.visible and tb.popup_lab.text == tb.badge_text("amp")
		and tb.popup_lab.text.contains("%d%%" % int(round(s.SD_AMP_PER * 100.0))), tb.popup_lab.text)
	_click(Vector2(get_viewport().get_visible_rect().size) * Vector2(0.5, 0.8))
	await get_tree().process_frame
	_ok("B11 ★点别处 ⇒ 说明关掉", not tb.popup.visible and not tb.catcher.visible)
	_click(tb.badge_heal.get_global_rect().get_center())
	await get_tree().process_frame
	_ok("B12 点治疗徽章 ⇒ 治疗那一行", tb.popup.visible and tb.popup_lab.text == tb.badge_text("heal")
		and tb.popup_lab.text.contains("50%"), tb.popup_lab.text)
	_go(tb.POPUP_LIFE + 0.2)
	_ok("B13 说明不点也会自己消失", not tb.popup.visible)


static func SplashWait() -> float:
	return 1.3


# ── C ─────────────────────────────────────────────────────────────
func _t_wipe() -> void:
	print("  ── C 团灭 + 破蛋倒数 ──")
	await _fresh("top")
	var tb = h._topbar
	_ok("C0 换了一场: 不在加时 ⇒ 徽章收起、牌子回到路名", not tb.badge_amp.visible and s._dl_hud.text.begins_with("上路战场"), s._dl_hud.text)
	_wipe("right")
	_go(0.15)
	_ok("C1 ★分母: 右方团灭 ⇒ 破蛋窗口", s._dl_state == "eggwindow" and s._dl_wiped_side == "right",
		"state=%s wiped=%s" % [s._dl_state, s._dl_wiped_side])
	_ok("C2 ★右侧主条盖「团灭」戳, 左侧没有", tb.stamps["right"].visible and not tb.stamps["left"].visible
		and _stamp_text(tb.stamps["right"]) == "团灭")
	_ok("C3 团灭那一侧头像压灰, 另一侧不压", tb.port_r.modulate.r < 0.5 and tb.port_l.modulate.r > 0.95,
		"%s / %s" % [str(tb.port_r.modulate), str(tb.port_l.modulate)])
	_go(1.5)
	_ok("C4 右侧主条清空(填充宽 0)", h._pk_fill_r.size.x < 0.5, "%.1f px" % h._pk_fill_r.size.x)
	_ok("C5 ★右侧蛋副条变亮(围栏破 = 能打了), 左侧仍压暗(围栏在)",
		h._pk_egg_r.modulate.r > 1.05 and absf(h._pk_egg_l.modulate.r - 0.58) < 0.01,
		"右 %.2f 左 %.2f" % [h._pk_egg_r.modulate.r, h._pk_egg_l.modulate.r])
	var t1: String = s._dl_hud.text
	_ok("C6 计时牌「破蛋 0:0x」蛋壳色", _re("^破蛋 0:0\\d$", t1) and _col(s._dl_hud) == DL.DL_PLATE_EGG_COL, t1)
	_go(2.0)
	var t2: String = s._dl_hud.text
	_ok("C7 ★破蛋这一个是【倒数】(2 秒后读数小 2)", _secs(t1) - _secs(t2) == 2, "%s → %s" % [t1, t2])
	var rem: float = s._dl_window_until - s._t
	_go(rem - 2.5)
	_ok("C8 ★最后 3 秒变红", _col(s._dl_hud) == DL.DL_PLATE_URGENT_COL and _secs(s._dl_hud.text) <= 3, s._dl_hud.text)
	_ok("C9 团灭不是加时: 徽章不出", not tb.badge_amp.visible)


# ── D ─────────────────────────────────────────────────────────────
func _t_decider() -> void:
	print("  ── D 终极战场(定局) ──")
	gs.lane_results = {"top": "left", "bottom": "right"}
	await _fresh("final")
	var tb = h._topbar
	_go(0.3)
	_ok("D1 ★路点: 上路我方赢 = 绿, 下路对方赢 = 紫, 正在打第 3 颗",
		tb.dot_cores[0].modulate == h.PK_BLUE and tb.dot_cores[1].modulate == h.PK_RED and tb.current_dot() == 2
		and _all_dark([tb.dot_cores[2]]), "%s %s" % [str(tb.dot_cores[0].modulate), str(tb.dot_cores[1].modulate)])
	_ok("D2 牌子写「终极战场 m:ss」", _re("^终极战场 \\d+:\\d\\d$", s._dl_hud.text), s._dl_hud.text)
	_wipe("left")
	_go(0.2)
	_ok("D3 ★定局路团灭 ⇒「破蛋定胜负」(窗口无限, 不倒数)", s._dl_state == "eggwindow" and s._dl_hud.text == "破蛋定胜负",
		s._dl_hud.text)
	_ok("D4 左侧团灭戳", tb.stamps["left"].visible and not tb.stamps["right"].visible)


# ── E ─────────────────────────────────────────────────────────────
func _t_egg_break() -> void:
	print("  ── E 蛋碎 ──")
	var tb = h._topbar
	var egg: Dictionary = {}
	for u in s._units:
		if u.get("_isEgg", false) and str(u.get("egg_side_lr", "")) == "left":
			egg = u
	_ok("E0 ★分母: 左蛋在场且有血、副条非空", not egg.is_empty() and float(egg["hp"]) > 0.0 and h._pk_egg_l.size.x > 1.0,
		"副条 %.1f px" % h._pk_egg_l.size.x)
	s._damage._apply_damage(egg, int(egg["hp"]) + 99999, Color.WHITE, null, "tru", false)
	s._sim_step(DT, false, false)
	s._dl_sys._dl_update_hud()
	_ok("E1 ★蛋碎当场(同一步)副条清空 —— 不等 0.1 秒采样", h._pk_egg_l.size.x < 0.5, "%.1f px" % h._pk_egg_l.size.x)
	_ok("E2 ★碎片崩出来了", tb.shard_count() >= 10, "碎片 %d" % tb.shard_count())
	_ok("E3 结算照常走(整场结束)", s._dl_state == "done" and s._over, "state=%s" % s._dl_state)
	for _i in range(60):
		h._pk_tick(DT)
	_ok("E4 碎片 1 秒内收干净(不留节点)", tb.shard_count() == 0, "剩 %d" % tb.shard_count())


# ── 工具 ──────────────────────────────────────────────────────────
func _fresh(lane: String) -> void:
	gs.current_lane = lane
	s._over = false
	s._dl_sys._dl_clear_units()
	await get_tree().process_frame
	s._dl_sys._dl_build_lane_field()
	await get_tree().process_frame
	s._dl_sys._dl_start_fight()
	h._pk_lane = ""
	## 开打前那块介绍幕是按真实时间淡出再销毁的(0.22 秒, 淡出期间它的子面板仍吃点击) —— 等它真走掉,
	##   否则 B 组点徽章会点在它上面(真玩家要到开打后才点得到徽章, 那时它早没了)。
	await get_tree().create_timer(0.4).timeout
	_go(0.05)


## sim 与渲染路按同一步长喂 sec 秒。
func _go(sec: float) -> void:
	var n: int = maxi(1, int(round(sec / DT)))
	for _i in range(n):
		s._sim_step(DT, false, false)
		h._pk_tick(DT)
		if s._dl_hud != null and is_instance_valid(s._dl_hud):
			s._dl_sys._dl_update_hud()


func _wipe(side: String) -> void:
	for u in s._units:
		if not u.get("alive", false) or u.get("_isEgg", false) or u.get("is_trainer", false):
			continue
		if str(s._eff_side(u)) != side:
			continue
		u["shield"] = 0.0
		s._kill(u)


func _click(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	get_viewport().push_input(mv)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = p
		ev.global_position = p
		get_viewport().push_input(ev)


func _re(pat: String, t: String) -> bool:
	var r := RegEx.new()
	r.compile(pat)
	return r.search(t) != null


## 「上路战场 1:05」→ 65
func _secs(t: String) -> int:
	var r := RegEx.new()
	r.compile("(\\d+):(\\d\\d)$")
	var m := r.search(t)
	return -999 if m == null else int(m.get_string(1)) * 60 + int(m.get_string(2))


func _col(l: Label) -> Color:
	return l.get_theme_color("font_color")


func _all_dark(cores: Array) -> bool:
	for c in cores:
		var m: Color = (c as CanvasItem).modulate
		if m.r > 0.2 or m.g > 0.2 or m.b > 0.2:
			return false
	return true


func _stamp_text(pc: Control) -> String:
	for ch in pc.get_children():
		if ch is Label:
			return (ch as Label).text
	return ""


func _count_float_text(t: String) -> int:
	var n := 0
	for nd in get_tree().get_nodes_in_group(BattleHud.UI_TRANSIENT_GROUP):
		if nd is Label and (nd as Label).text == t:
			n += 1
	return n


func _done() -> void:
	print("")
	print("断言 %d 条" % _n)
	if _fail == 0 and _n >= NEED:
		print("ALL PASS — 顶部栏: 平时计时正走 / 加时大字+徽章 / 团灭戳+蛋副条亮 / 破蛋倒数 / 定局 / 蛋碎")
	else:
		print("FAIL x%d (断言 %d / 需 %d)" % [_fail, _n, NEED])
	get_tree().quit(1 if _fail > 0 or _n < NEED else 0)
