extends Node
## verify_gauntlet_queue_menu.gd — 周六闯关赛排队中回到主页: 主按钮排队态 / 取消键 / 七处锁 / 「匹配成功」遮罩
##   (2026-10-29 · 方案书 docs/plans/20261029c-闯关赛排队时可回主页.md §4.1 · A7~A13; 产品代码 scripts/scenes/menu_queue.gd、
##    scripts/scenes/queue_found_overlay.gd, 以及 MainMenuScene / SettingsScene / Spar 里转调它的那几行)。
## 用户 10-29「锁定了后，还是能回到主页的，只是不能动背包商店，然后开始战斗你得变按钮，在边上也要有取消按钮」;
##   其余(锁训龟大师 / 教程 / 切磋 / 删号 / 换号, 取消键在左、不二次确认, 配上盖遮罩自动进)是方案书 U1~U6 的建议, 用户「全部今天做完」认可。
##
## 会话用一个假的(`RefereeRun.active` 指向它, 用完还原 null): 有 changed 信号 / state / cell / waited_now() / cancel_queue()。
## 量的全是玩家看到 / 点到的产品节点:
##   ① 主按钮排队态: 「匹配中」/「已等待 …」随墙钟变(0.25 秒一刷)、不挂光晕、面不是亮黄; 点它 = 回排队屏(注入点记账)且默认接的是会话那边的入口
##   ② 取消键: 在排队面左侧、同高、能点范围 ≥ 81; 点它 = 调到会话 cancel_queue; 正在退出 ⇒ 灰 +「正在退出」
##   ③ 七处锁(背包 / 商店 / 训龟大师 / 「?」教程 / 好友切磋 / 删除账号 / 邮箱登录): 画着锁、点了弹被拦卡且那句话对、不换场景;
##      图鉴 / 排行榜 / 好友 / 设置 排队中照常进(真点、真换场景)
##   ④ 会话结束(发信号)⇒ 主按钮恢复「开始战斗」+ 光晕、锁全摘、出队那句当场飘; 解锁后删号 / 邮箱登录 / 切磋 照常
##   ⑤ 会话在主菜单开着时冒出来 ⇒ 当场换成排队态; 会话没发信号就没了 ⇒ 当场恢复
##   ⑥ 「匹配成功」遮罩: 盖住一切(吞点击)、带新音效、约 1.5 秒后调回调恰 1 次、随后自删; 连着配上两次不叠两层; 会话那边加载的就是这一份
## ★等待一律按墙钟: 每步 OS.delay_msec 再走一帧(门禁默认只给 500 帧, 帧数不是尺子)。
## SHOT_OUT=<目录> 且开窗口跑 ⇒ 顺手拍五张(主页排队态 / 背包被拦卡 / 正在退出 / 恢复后 / 遮罩), 自查用; 那时不焊死视口。
## 跑法: TURTLE_SUPABASE=" " TURTLE_BACKEND=" " <godot> --headless --path . res://tests/verify_gauntlet_queue_menu.tscn

const RUN := preload("res://scripts/systems/replay/referee_run.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const SET := preload("res://scripts/scenes/SettingsScene.gd")
const MENU_S := preload("res://scripts/scenes/MainMenuScene.gd")
## 周六 10:00 UTC(闯关赛): verify_mainmenu_layout 那一刻(周四 2026-09-24 00:00)+ 2 天 10 小时。
##   存档种成「已晋级、2 胜 1 负」⇒ 这一刻「开始战斗」亮着 ⇒ 出队后能量到光晕回来; 排队态只会出现在这一天。
const PIN_SAT_TS := 1789603200 + 2 * 86400 + 10 * 3600
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MIN_TAP := 81.0
const OVERLAY_PATH := "res://scripts/scenes/queue_found_overlay.gd"


class FakeRun extends Node:
	signal changed
	var state := ""
	var cell := Vector2i(2, 1)
	var cancels := 0
	var cancel_state := ""
	var base_sec := 64
	var t0 := 0

	func waited_now() -> int:
		return base_sec + (Time.get_ticks_msec() - t0) / 1000

	func cancel_queue() -> bool:
		cancels += 1
		state = cancel_state
		changed.emit()
		return true


var _fail := 0
var _n := 0
var _menu: Control = null
var _shot_dir := ""
var _fakes: Array = []


func _ok(what: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", what, ("   " + detail) if detail != "" else ""])


func _sleep(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		OS.delay_msec(40)
		await get_tree().process_frame


## 等到 cond 成立; 返回等了几秒(墙钟), 超时 = -1。
func _until(cond: Callable, sec: float) -> float:
	var t0 := Time.get_ticks_msec()
	while not bool(cond.call()):
		if Time.get_ticks_msec() - t0 > int(sec * 1000.0):
			return -1.0
		OS.delay_msec(30)
		await get_tree().process_frame
	return float(Time.get_ticks_msec() - t0) / 1000.0


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _new_fake(st: String) -> FakeRun:
	var f := FakeRun.new()
	f.state = st
	f.cancel_state = RW.ST_CANCEL
	f.t0 = Time.get_ticks_msec()
	add_child(f)
	_fakes.append(f)
	return f


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out


## 子树里有 Label 的字含 text 的那一块(page_box / content_root 的直属孩子)。
func _holder(box: Node, text: String) -> Control:
	for c in box.get_children():
		if not (c is Control):
			continue
		for n in _walk(c):
			if n is Label and str((n as Label).text) == text:
				return c as Control
	return null


func _has_lock(holder: Node) -> bool:
	if holder == null:
		return false
	for n in _walk(holder):
		if str(n.name) == str(MENU_S.LOCK_ICON_NAME):
			return true
	return false


func _reason(holder: Node) -> String:
	if holder == null:
		return ""
	for n in _walk(holder):
		if str(n.name) == str(MENU_S.LOCK_REASON_NAME) and n is Label:
			return str((n as Label).text)
	return ""


## 一块入口上那颗可点的按钮(直属孩子里的 Button)。
func _btn(holder) -> Button:
	if holder == null or not is_instance_valid(holder):
		return null
	for c in holder.get_children():
		if c is Button:
			return c as Button
	return null


## 主按钮排队态那颗「回排队屏」的按钮(木框按钮里那颗透明 Button, 不是取消键)。
func _hero_btn(qh: Node) -> Button:
	for c in qh.get_children():
		if c is Button and str(c.name) != MenuQueue.N_CANCEL:
			return c as Button
	return null


## host 不标类型: 门没拦住时主菜单已被换场景释放, 带类型的形参在调用那一刻就报错(那样红的是这里, 不是那扇门)。
func _card(host) -> Node:
	if host == null or not is_instance_valid(host):
		return null
	return host.get_node_or_null(MenuWeekend.BLOCK_CARD_NAME)


func _card_body(host) -> String:
	var c := _card(host)
	if c == null:
		return ""
	var b := c.find_child("Body0", true, false)
	return str((b as Label).text).replace("\n", "") if b is Label else ""


func _clear_card(host) -> void:
	if host == null or not is_instance_valid(host):
		return
	var c := _card(host)
	if c != null:
		host.remove_child(c)
		c.queue_free()


func _menu_alive() -> bool:
	return is_instance_valid(_menu) and _menu.is_inside_tree() and _menu.process_mode != Node.PROCESS_MODE_DISABLED \
		and get_tree().current_scene == _menu


func _shot(name: String) -> void:
	if _shot_dir == "" or DisplayServer.get_name() == "headless":
		return
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var vs := get_viewport().get_visible_rect().size
	get_viewport().get_texture().get_image().save_png("%s/%s_%dx%d.png" % [_shot_dir, name, int(vs.x), int(vs.y)])
	print("  shot ", name)


func _build_menu() -> Control:
	var m: Control = load("res://scenes/MainMenu.tscn").instantiate()
	m.clock_override_ts = PIN_SAT_TS
	get_tree().root.add_child(m)
	if _shot_dir == "":
		m.set_anchors_preset(Control.PRESET_TOP_LEFT)
		m.size = Vector2(1280, 720)
	return m


func _ready() -> void:
	_shot_dir = OS.get_environment("SHOT_OUT")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 GameState autoload")
		get_tree().quit(1)
		return
	gs.test_mode = true
	if _shot_dir == "":
		get_tree().root.size = Vector2i(1280, 720)
	gs.season_total_battles = 3
	gs.season_id = 2
	gs.hearts = 5
	gs.ranked_used = 0
	gs.onboarded = true
	gs.season_leaders = ["phoenix", "pirate", "ninja"]
	gs.season_wins = 12
	gs.promoted = true
	gs.gauntlet_wins = 2
	gs.gauntlet_losses = 1
	print("=== 周六排队中回到主页: 主按钮排队态 / 取消键 / 锁 / 匹配成功遮罩 ===")
	_ok("分母: 钉的那一刻是周六闯关赛、这份存档能开打(排队态只在这一天出现)",
		P2C.phase_at_utc(PIN_SAT_TS) == P2C.PHASE_GAUNTLET and gs.gauntlet_can_play(PIN_SAT_TS))
	_ok("分母: 开局没有残留会话(RefereeRun.active == null)", RUN.active == null)
	_ok("分母: 没有会话 ⇒ 不锁(MenuQueue.locked() 读的就是 queue_locked)", not MenuQueue.locked() and not RW.queue_locked())
	await _part_hero_and_locks()
	await _part_cancel_and_restore()
	await _part_appear_vanish()
	await _part_open_doors()
	await _part_overlay()
	_finish()


## ══ ① ② ③: 会话在排队时进主菜单 ══
func _part_hero_and_locks() -> void:
	var fake := _new_fake(RW.ST_QUEUE)
	RUN.active = fake
	_ok("分母: 假会话在排队 ⇒ 唯一判据 RefereeWatch.queue_locked() 为真", RW.queue_locked())
	_menu = _build_menu()
	await _sleep(2.3)                     # 入场滑入落定(0.85 + 0.06×5 + 0.42 秒)
	get_tree().current_scene = _menu      # 真换场景只换掉主菜单, 不拆门禁自己
	var mq: MenuQueue = _menu._mq()
	var pb: Control = _menu.page_box
	var qh: Control = pb.get_node_or_null(MenuQueue.N_HERO) as Control
	_ok("① ★排队中进主菜单 ⇒ 主按钮是排队态(QueueHero)", qh != null)
	_ok("① 「开始战斗」那颗不在(换成了排队态, 不是叠在上面)", _holder(pb, "开始战斗") == null)
	if qh == null:
		return
	var l1: Label = qh.get_node_or_null(MenuQueue.N_LINE1) as Label
	var l2: Label = qh.get_node_or_null(MenuQueue.N_LINE2) as Label
	_ok("分母: 两行字都在", l1 != null and l2 != null)
	if l1 == null or l2 == null:
		return
	_ok("① 第一行「匹配中」", l1.text == MenuQueue.TXT_MATCHING, l1.text)
	var w0: int = fake.waited_now()
	_ok("① 第二行 = 会话的已等待(RefereeWatch.queue_waited_text, 「已等待 1 分 0x 秒」)",
		l2.text in [RW.queue_waited_text(w0), RW.queue_waited_text(w0 - 1)] and l2.text.begins_with("已等待 1 分 "), l2.text)
	var glow := 0
	var yellow := 0
	for n in _walk(qh):
		if n is MenuCtaGlow:
			glow += 1
		if str(n.name) == str(MENU_S.HERO_FACE_NAME):
			yellow += 1
	_ok("① 不挂呼吸光晕(排队中点它不是开打)", glow == 0, "%d 个" % glow)
	_ok("① 不铺亮黄面(全屏唯一的亮黄留给能开打的那一刻)", yellow == 0, "%d 块" % yellow)
	var face: NinePatchRect = qh.get_node_or_null(MenuQueue.N_FACE) as NinePatchRect
	var fc := Color(0, 0, 0)
	if face != null and face.texture != null:
		var fimg := face.texture.get_image()
		fc = fimg.get_pixel(fimg.get_width() / 2, fimg.get_height() / 2)
	_ok("① 排队面是冷色「进行中」(面中心 蓝 > 红、不是亮黄)", face != null and fc.b > fc.r and fc.r < 0.5, str(fc))
	## 已等待随墙钟走(0.25 秒一刷)
	var s1 := l2.text
	await _sleep(1.3)
	var s2 := l2.text
	var w1: int = fake.waited_now()
	_ok("① ★已等待随墙钟往上走(1.3 秒后变了, 仍是会话那一份)", s1 != s2 and s2 in [RW.queue_waited_text(w1), RW.queue_waited_text(w1 - 1)],
		"%s → %s" % [s1, s2])
	fake.base_sec += 100
	var lat: float = await _until(func() -> bool: return l2.text.begins_with("已等待 2 分 "), 2.0)
	_ok("① ★0.25 秒一刷: 会话的已等待跳到 2 分多, %.2f 秒内屏上跟上(≤ 0.6)" % lat, lat >= 0.0 and lat <= 0.6, l2.text)
	await _shot("menu_queue")
	## ② 取消键几何
	var ck: Button = qh.get_node_or_null(MenuQueue.N_CANCEL) as Button
	_ok("② 分母: 取消键在", ck != null and face != null)
	if ck == null or face == null:
		return
	var rk := ck.get_global_rect()
	var rf := face.get_global_rect()
	print("  ② 取消键 %s / 排队面 %s / 主按钮 %s" % [str(rk), str(rf), str(qh.get_global_rect())])
	_ok("② ★取消键在主按钮左侧(右沿 ≤ 排队面左沿)", rk.end.x <= rf.position.x + 0.5, "%.1f vs %.1f" % [rk.end.x, rf.position.x])
	_ok("② ★取消键与排队面同高(顶、高都对齐)", absf(rk.position.y - rf.position.y) < 1.0 and absf(rk.size.y - rf.size.y) < 1.0)
	_ok("② 取消键能点范围 ≥ %d(触摸线)" % int(MIN_TAP), rk.size.x >= MIN_TAP and rk.size.y >= MIN_TAP, str(rk.size))
	_ok("② 取消键在主按钮那一块里(没探进左边的模式卡)", qh.get_global_rect().grow(0.5).encloses(rk))
	_ok("② 取消键 = 红键 + ✕(不带字、能点)", ck.icon != null and ck.text == "" and not ck.disabled)
	## ① 点主按钮排队态 ⇒ 回排队屏
	_ok("① ★主按钮排队态的默认去处 = 会话那边回排队屏的入口(RefereeRun.open_queue_screen)",
		str(mq.open_queue.get_method()) == "open_queue_screen", str(mq.open_queue))
	var opened: Array = []
	mq.open_queue = func(t: SceneTree) -> void: opened.append(t)
	var hb := _hero_btn(qh)
	_ok("分母: 主按钮那颗可点的按钮在", hb != null)
	if hb != null:
		hb.button_down.emit()
		await _sleep(0.15)
	_ok("① ★点主按钮排队态 ⇒ 回排队屏恰 1 次(不经过选龟)", opened.size() == 1 and mq.opens == 1, "%d / %d" % [opened.size(), mq.opens])
	_ok("① 点它没在主菜单这边自己换场景(去处全交给会话那边)", _menu_alive())
	## ③ 锁: 画
	for nm in ["背包", str(MENU_S.SHOP_LABEL)]:
		var h: Control = pb.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + nm) as Control
		_ok("③ ★[%s] 画着锁 + 底边短签「匹配中」(与商店锁同一种)" % nm, _has_lock(h) and _reason(h) == MenuQueue.TXT_MATCHING, _reason(h))
	var open_sq := 0
	for nm in ["图鉴", "排行榜", "好友"]:
		var h2: Control = pb.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + nm) as Control
		if h2 != null and not _has_lock(h2) and _reason(h2) == "":
			open_sq += 1
	_ok("③ 图鉴 / 排行榜 / 好友 不画锁(%d / 3)" % open_sq, open_sq == 3)
	var tb := _holder(pb, "训龟大师")
	_ok("③ ★[训龟大师] 画着锁 + 短签「匹配中」", _has_lock(tb) and _reason(tb) == MenuQueue.TXT_MATCHING, _reason(tb))
	var help := _holder(_menu.content_root, "?")
	_ok("③ ★[「?」新手教程] 画着锁 + 短签「匹配中」", _has_lock(help) and _reason(help) == MenuQueue.TXT_MATCHING)
	## ③ 锁: 门(真点那颗按钮)
	var doors: Array = [
		["背包", MenuQueue.K_BAG, pb.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + "背包")],
		["商店", MenuQueue.K_SHOP, pb.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + str(MENU_S.SHOP_LABEL))],
		["训龟大师", MenuQueue.K_TRAINER, tb],
		["「?」新手教程", MenuQueue.K_TUTORIAL, help],
	]
	var blocked := 0
	for d in doors:
		if not _menu_alive():
			_ok("③ [%s] 前一扇门把主菜单换走了, 这一扇量不到" % str(d[0]), false)
			continue
		_clear_card(_menu)
		await _frames(1)
		var b := _btn(d[2])
		if b == null:
			_ok("③ 分母: [%s] 找得到那颗按钮" % str(d[0]), false)
			continue
		b.pressed.emit()
		await _frames(2)
		var alive := _menu_alive()
		var body := _card_body(_menu) if alive else "(主菜单被换走了 = 门没拦住)"
		var good: bool = alive and _card(_menu) != null and body == MenuQueue.why(str(d[1]))
		_ok("③ ★[%s] 点了弹被拦卡、不换场景;卡上那句「%s」" % [str(d[0]), body], good)
		if good:
			blocked += 1
		if str(d[0]) == "背包" and _shot_dir != "":
			await _sleep(0.5)                # 卡淡入(T_BASE)落定再拍
			await _shot("menu_queue_bag_card")
	_ok("③ 「?」被拦时教程选择框没开", _menu_alive() and _menu.get_node_or_null("TutorialChoice") == null)
	_clear_card(_menu)
	## ③ 切磋
	_ok("③ ★[好友切磋] 排队中 Spar.my_side_check() = 「%s」" % MenuQueue.TXT_SPAR, Spar.my_side_check() == MenuQueue.TXT_SPAR, Spar.my_side_check())
	var began := Spar.begin({"profile": {"name": "x"}, "dual_lineup": {}}, {})
	_ok("③ [好友切磋] 排队中 begin 不挂上", not began and not Spar.is_active())
	if began:
		Spar.end()
	else:
		blocked += 1
	## ③ 设置: 删除账号 / 邮箱登录(真点设置页那两颗)
	var gs = get_node_or_null("/root/GameState")
	gs.account_id = "11111111-2222-3333-4444-555555555555"
	gs.account_email = "probe@example.com"
	var sc: Control = SET.new()
	sc.acct_override = 1
	add_child(sc)
	await _frames(3)
	## acct_override = 1 进门就开绑定屏(`_maybe_bind_screen`)⇒ 先关掉: 量的是「点邮箱登录」那一下开没开框, 不能拿进门那一个当数
	if sc.get("_email_layer") != null:
		sc._close_email_dialog(sc.get("_email_layer"))
		await _frames(2)
	_ok("分母: 设置页起手没有开着的邮箱框(否则「不开 / 照常开」都是空检查)", sc.get("_email_layer") == null)
	var del_b = sc.find_child(SET.ACCT_ROW_PREFIX + SET.BTN_DELETE, true, false)
	var rec_b = sc.find_child(SET.ACCT_ROW_PREFIX + "BtnRecover", true, false)
	_ok("分母: 设置页建出了「删除账号」「邮箱登录」两颗", del_b is Button and rec_b is Button)
	if del_b is Button and rec_b is Button:
		(del_b as Button).pressed.emit()
		await _frames(2)
		var g1: bool = _card(sc) != null and _card_body(sc) == MenuQueue.why(MenuQueue.K_DELETE) and sc.get_node_or_null(str(sc._ACCT_DEL.LAYER)) == null
		_ok("③ ★[删除账号] 排队中点了弹被拦卡、不开删号框", g1, _card_body(sc))
		_clear_card(sc)
		(rec_b as Button).pressed.emit()
		await _frames(2)
		var g2: bool = _card(sc) != null and _card_body(sc) == MenuQueue.why(MenuQueue.K_RECOVER) and sc.get("_email_layer") == null
		_ok("③ ★[邮箱登录] 排队中点了弹被拦卡、不开邮箱登录框", g2, _card_body(sc))
		_clear_card(sc)
		blocked += int(g1) + int(g2)
	print("  ③ [分母] 排队中拦住 %d / 7 处(背包 / 商店 / 训龟大师 / 教程 / 切磋 / 删号 / 邮箱登录)" % blocked)
	_ok("③ ★分母: 七处都拦住了", blocked == 7, "%d" % blocked)
	set_meta("settings", sc)


## ══ ② ④: 取消 → 正在退出 → 出队后恢复 ══
func _part_cancel_and_restore() -> void:
	if not is_instance_valid(_menu) or _menu.page_box.get_node_or_null(MenuQueue.N_HERO) == null:
		_ok("分母: 主按钮排队态在(上一段没建起来, 这一段全是空检查)", false)
		return
	var fake: FakeRun = RUN.active as FakeRun
	var qh: Control = _menu.page_box.get_node(MenuQueue.N_HERO)
	var ck: Button = qh.get_node(MenuQueue.N_CANCEL)
	ck.pressed.emit()
	await _frames(2)
	_ok("② ★点取消键 ⇒ 调到会话 cancel_queue 恰 1 次(不二次确认)", fake.cancels == 1, "%d" % fake.cancels)
	_ok("② ★正在退出 ⇒ 取消键灰掉(禁用)、换成「正在退出」", ck.disabled and ck.icon == null and ck.text.replace("\n", "") == MenuQueue.TXT_CANCELLING,
		"disabled=%s text=%s" % [str(ck.disabled), ck.text.replace("\n", "")])
	var sb := ck.get_theme_stylebox("disabled")
	_ok("② 灰: 禁用态底座压灰", sb is StyleBoxTexture and (sb as StyleBoxTexture).modulate_color.r < 0.8)
	_ok("② 正在退出时仍锁着(等服务端回话)", RW.queue_locked() and _has_lock(_menu.page_box.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + "背包")))
	await _shot("menu_queue_cancelling")
	## 服务端回「已取消」: 会话写 notice、发 changed、离开排队态
	RW.notice = RW.TXT_QUEUE_LEFT
	fake.state = RW.ST_LEFT
	fake.changed.emit()
	RUN.active = null
	await _frames(2)
	var pb: Control = _menu.page_box
	_ok("④ ★出队 ⇒ 排队态没了", pb.get_node_or_null(MenuQueue.N_HERO) == null)
	var hero := _holder(pb, "开始战斗")
	_ok("④ ★主按钮恢复「开始战斗」", hero != null)
	var glow := 0
	if hero != null:
		for n in _walk(hero):
			if n is MenuCtaGlow:
				glow += 1
	_ok("④ 恢复后呼吸光晕回来(这一刻能开打)", glow == 1, "%d" % glow)
	var still := 0
	for nm in ["背包", str(MENU_S.SHOP_LABEL)]:
		if _has_lock(pb.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + nm)):
			still += 1
	if _has_lock(_holder(pb, "训龟大师")):
		still += 1
	if _has_lock(_holder(_menu.content_root, "?")):
		still += 1
	_ok("④ ★锁全摘了(背包 / 商店 / 训龟大师 / 「?」)", still == 0, "还锁着 %d 处" % still)
	var toast := false
	for c in _menu.get_children():
		if c is Label and str((c as Label).text) == RW.TXT_QUEUE_LEFT:
			toast = true
	_ok("④ ★出队那句「%s」当场飘(人就在主菜单上)" % RW.TXT_QUEUE_LEFT, toast and str(RW.notice) == "")
	_ok("④ 重建不重播滑入(主按钮已在原位、不透明)", hero != null and absf(hero.position.x - float(MENU_S.HERO_POS.x)) < 0.5 and hero.modulate.a > 0.99)
	await _shot("menu_queue_restored")
	## 解锁后那几扇门照常开
	_ok("④ 解锁后切磋照常(my_side_check = \"\")", Spar.my_side_check() == "", Spar.my_side_check())
	var sc = get_meta("settings") if has_meta("settings") else null
	if sc != null and is_instance_valid(sc):
		var del_b = sc.find_child(SET.ACCT_ROW_PREFIX + SET.BTN_DELETE, true, false)
		var rec_b = sc.find_child(SET.ACCT_ROW_PREFIX + "BtnRecover", true, false)
		(del_b as Button).pressed.emit()
		await _frames(2)
		_ok("④ 解锁后「删除账号」照常打开删号框", sc.get_node_or_null(str(sc._ACCT_DEL.LAYER)) != null and _card(sc) == null)
		(rec_b as Button).pressed.emit()
		await _frames(2)
		_ok("④ 解锁后「邮箱登录」照常打开邮箱框", sc.get("_email_layer") != null and _card(sc) == null)
		sc.queue_free()
	## 点到旧的排队态那一刻会话刚好没了(R7): 再判一次, 不去排队屏
	var mq: MenuQueue = _menu._mq()
	var before := mq.opens
	mq._on_hero_tap()
	_ok("④ 会话已结束时点主按钮排队态(竞态)⇒ 不去排队屏", mq.opens == before)


## ══ ⑤: 主菜单开着时会话冒出来 / 没发信号就没了 ══
func _part_appear_vanish() -> void:
	if not is_instance_valid(_menu):
		_ok("分母: 主菜单还在", false)
		return
	var f2 := _new_fake(RW.ST_QUEUE)
	RUN.active = f2
	var w: float = await _until(func() -> bool: return _menu.page_box.get_node_or_null(MenuQueue.N_HERO) != null, 1.5)
	_ok("⑤ 会话在主菜单开着时冒出来 ⇒ %.2f 秒内换成排队态(≤ 0.6)" % w, w >= 0.0 and w <= 0.6)
	_ok("⑤ 同时背包锁上", _has_lock(_menu.page_box.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + "背包")))
	f2.free()                                  # 没发信号就没了(RUN.active 还指着它)
	var w2: float = await _until(func() -> bool: return _holder(_menu.page_box, "开始战斗") != null, 1.5)
	_ok("⑤ ★会话没发信号就没了 ⇒ %.2f 秒内主按钮恢复「开始战斗」(≤ 0.6)" % w2, w2 >= 0.0 and w2 <= 0.6)
	RUN.active = null


## ══ ③ 排队中照常能进的那几扇门(真点、真换场景; 每扇门一个新主菜单) ══
func _part_open_doors() -> void:
	var fake := _new_fake(RW.ST_QUEUE)
	RUN.active = fake
	var doors: Array = [
		["图鉴", "res://scenes/Codex.tscn"],
		["排行榜", "res://scenes/Leaderboard.tscn"],
		["好友", "res://scenes/Friends.tscn"],
		["设置", "res://scenes/Settings.tscn"],
	]
	var went := 0
	for d in doors:
		if is_instance_valid(_menu):
			_menu.queue_free()
		_menu = _build_menu()
		await _sleep(0.3)
		get_tree().current_scene = _menu
		var h: Control = null
		if str(d[0]) == "设置":
			for c in _menu.content_root.get_children():
				if c is Control and c.find_child("IconTex", true, false) != null:
					h = c
		else:
			h = _menu.page_box.get_node_or_null(str(MENU_S.SQ_NAME_PREFIX) + str(d[0])) as Control
		var b := _btn(h)
		if b == null or not MenuQueue.locked():
			_ok("③ 分母: [%s] 排队中找得到那颗按钮" % str(d[0]), false)
			continue
		b.pressed.emit()
		var nav: bool = _menu.process_mode == Node.PROCESS_MODE_DISABLED and _card(_menu) == null
		var w: float = await _until(func() -> bool: return get_tree().current_scene != null \
			and str(get_tree().current_scene.scene_file_path) == str(d[1]), 4.0)
		_ok("③ ★[%s] 排队中照常进(不弹卡、真换到 %s)" % [str(d[0]), str(d[1]).get_file()], nav and w >= 0.0)
		if nav and w >= 0.0:
			went += 1
		var cs := get_tree().current_scene
		if cs != null and cs != self:
			cs.queue_free()
		get_tree().current_scene = self
		_menu = null
		await _frames(2)
	print("  ③ [分母] 排队中照常能进 %d / 4 扇门(图鉴 / 排行榜 / 好友 / 设置)" % went)
	_ok("③ ★分母: 四扇门都照常进", went == 4, "%d" % went)
	RUN.active = null


## ══ ⑥ 「匹配成功」遮罩 ══
func _part_overlay() -> void:
	_ok("⑥ ★会话那边加载的遮罩就是这一份(RefereeRun.OVERLAY)", str(RUN.OVERLAY) == OVERLAY_PATH and load(OVERLAY_PATH) == QueueFoundOverlay,
		str(RUN.OVERLAY))
	if _shot_dir != "":
		_menu = _build_menu()                # 实拍: 盖在主菜单上(配上时人多半在这一屏)
		await _sleep(2.3)
	var hits: Array = []
	var t0 := Time.get_ticks_msec()
	QueueFoundOverlay.show_then(get_tree(), func() -> void: hits.append(Time.get_ticks_msec() - t0))
	await _frames(2)
	var ov := get_tree().root.get_node_or_null(QueueFoundOverlay.NODE) as QueueFoundOverlay
	_ok("⑥ ★遮罩挂在 root 上(换场景也盖得住)", ov != null)
	if ov == null:
		return
	var title := ov.find_child("Title", true, false) as Label
	var sub := ov.find_child("Sub", true, false) as Label
	_ok("⑥ 大字「%s」+ 下一行「%s」" % [QueueFoundOverlay.TXT_TITLE, QueueFoundOverlay.TXT_SUB],
		title != null and title.text == "匹配成功" and sub != null and sub.text == "即将进入对局")
	_ok("⑥ 盖在各屏之上(CanvasLayer layer ≥ 100)", ov.layer >= 100, str(ov.layer))
	var rt := ov.get_node_or_null("Root") as Control
	var vs := get_viewport().get_visible_rect().size
	_ok("⑥ 整屏吞点击(全屏、MOUSE_FILTER_STOP)", rt != null and rt.mouse_filter == Control.MOUSE_FILTER_STOP and rt.size.x >= vs.x - 1 and rt.size.y >= vs.y - 1,
		str(rt.size) if rt != null else "-")
	var sfx := ov.get_node_or_null("Sfx") as AudioStreamPlayer
	_ok("⑥ ★带音效: 播的是新做的 queue_found.wav", sfx != null and sfx.stream != null and str(sfx.stream.resource_path) == QueueFoundOverlay.SFX
		and QueueFoundOverlay.SFX.get_file() == "queue_found.wav")
	await _sleep(0.6)
	await _shot("queue_found_overlay")
	var w_early := 1.0 - float(Time.get_ticks_msec() - t0) / 1000.0
	if w_early > 0.0:
		await _sleep(w_early)
	_ok("⑥ ★1 秒时还没进(遮罩在、回调没调)", hits.is_empty() and is_instance_valid(ov) and ov.calls == 0)
	var wt: float = await _until(func() -> bool: return not hits.is_empty(), 3.0)
	var dt: float = float(hits[0]) / 1000.0 if not hits.is_empty() else -1.0
	_ok("⑥ ★约 1.5 秒后调回调(实测 %.2f 秒, 1.4~2.0)" % dt, dt >= 1.4 and dt <= 2.0)
	var wf: float = await _until(func() -> bool: return get_tree().root.get_node_or_null(QueueFoundOverlay.NODE) == null, 2.0)
	_ok("⑥ ★调完自删(%.2f 秒内, ≤ 1)" % wf, wf >= 0.0 and wf <= 1.0)
	await _sleep(0.3)
	_ok("⑥ 回调恰 1 次", hits.size() == 1, "%d" % hits.size())
	## 连着配上两次: 不叠两层, 两个回调各 1 次
	var h2: Array = []
	QueueFoundOverlay.show_then(get_tree(), func() -> void: h2.append(1))
	await _frames(2)
	QueueFoundOverlay.show_then(get_tree(), func() -> void: h2.append(2))
	await _frames(2)
	var layers := 0
	for c in get_tree().root.get_children():
		if c is QueueFoundOverlay:
			layers += 1
	_ok("⑥ 连着两次 ⇒ 只盖一层", layers == 1, "%d 层" % layers)
	await _until(func() -> bool: return h2.size() >= 2, 3.0)
	await _sleep(0.3)
	_ok("⑥ 两个回调各调 1 次", h2.size() == 2 and h2.has(1) and h2.has(2), str(h2))
	await _until(func() -> bool: return get_tree().root.get_node_or_null(QueueFoundOverlay.NODE) == null, 2.0)


func _finish() -> void:
	RUN.active = null
	RW.notice = ""
	for f in _fakes:
		if is_instance_valid(f):
			f.queue_free()
	if is_instance_valid(_menu):
		_menu.queue_free()
	_ok("收尾: 会话已还原成 null(静态状态不留给后面的测试)", RUN.active == null)
	print("  (用了 %d 帧 · 门禁默认给 500)" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(0 if _fail == 0 else 1)
