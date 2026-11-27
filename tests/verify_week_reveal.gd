extends Node
## verify_week_reveal.gd —— 本周羁绊开周揭晓(方案书 docs/plans/20261127b-本周羁绊开周揭晓.md §6 验收)。
## ① 触发: 周一(休赛 / 换版)不放; 周二起放; 放过(记了 week_reveal_<周锚点>)这一周不再放; 下一周又放; 没过教程 / 没有周 不放。
## ② 内容: 10 张卡 = WeeklySynergy.of_week(同一份); 上线周「新」= 6 个新羁绊; 之后「新」= 上周没有的; 16 个羁绊每个都有图标与一句简介。
## ③ 实建: 浮层建得出 10 张卡、名字与本周一致; 点一下(发牌中)直接全部翻开; 再点一下收起, 浮层最后被删。
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")
const L := 1795996800          # 上线周 11-30 周一 00:00 UTC
var _fail := 0
var _n := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	_n += 1
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node("/root/GameState")
	gs.tutorial_active = false
	gs.onboarded = true
	gs.first_tips_seen = {}
	gs.week_anchor_ts = L
	print("== ① 触发")
	_ok("周一(休赛)不放", not WeekReveal.due(gs, L + 3600))
	_ok("周二放", WeekReveal.due(gs, L + 86400 + 3600))
	_ok("周日(决赛日)也放(这周还没看过)", WeekReveal.due(gs, L + 6 * 86400 + 3600))
	FirstTips.mark_seen(WeekReveal.SEEN_PREFIX + str(L))
	_ok("看过之后这一周不再放", not WeekReveal.due(gs, L + 2 * 86400))
	gs.week_anchor_ts = L + 7 * 86400
	_ok("下一周周二又放", WeekReveal.due(gs, L + 8 * 86400 + 3600))
	gs.onboarded = false
	_ok("没过教程不放", not WeekReveal.due(gs, L + 8 * 86400 + 3600))
	gs.onboarded = true
	gs.week_anchor_ts = 0
	_ok("没有周(演示 / 冷启动)不放", not WeekReveal.due(gs, L + 8 * 86400 + 3600))
	print("== ② 内容")
	_ok("上线周「新」= 6 个新羁绊", WeekReveal.fresh_of(L) == WeeklySynergy.LAUNCH_NEW, str(WeekReveal.fresh_of(L)))
	var nx: int = L + 7 * 86400
	var fr: Array = WeekReveal.fresh_of(nx)
	var ok_fr := true
	for t in fr:
		if WeeklySynergy.of_week(L).has(t) or not WeeklySynergy.of_week(nx).has(t):
			ok_fr = false
	_ok("之后各周「新」= 本周有、上周没有", ok_fr and fr.size() <= 10, str(fr))
	var miss: Array = []
	for t in WeeklySynergy.ALL:
		if _P2T.icon_of(t) == "" or not ResourceLoader.exists(_P2T.icon_of(t)) or WeekReveal.blurb(t).strip_edges() == "":
			miss.append(t)
	_ok("16 个羁绊都有图标与简介(分母 %d)" % WeeklySynergy.ALL.size(), miss.is_empty(), str(miss))
	print("== ③ 实建")
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child(host)
	gs.first_tips_seen = {}
	var done := [false]
	var r := WeekReveal.play(host, L, func() -> void: done[0] = true)
	var names: Array = []
	for c in r.cards:
		names.append(str((c["root"] as Control).name).trim_prefix("Card_"))
	_ok("10 张卡 = 本周 10 个(同顺序)", names == WeeklySynergy.of_week(L), str(names))
	_ok("放的同时记成看过", not FirstTips.can_show(WeekReveal.SEEN_PREFIX + str(L)))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	r._on_input(ev)
	var opened := 0
	for c in r.cards:
		if (c["front"] as Control).visible:
			opened += 1
	_ok("发牌中点一下 ⇒ 全部翻开、进停留", r.stage == 2 and opened == 10, "stage %d 翻开 %d" % [r.stage, opened])
	r._on_input(ev)
	var t0 := Time.get_ticks_msec()
	while not done[0] and Time.get_ticks_msec() - t0 < 3000:   # 收起动画按真实时间走(约 1.3 秒), 最多等 3 秒
		await get_tree().process_frame
	await get_tree().process_frame
	_ok("再点一下 ⇒ 收起、回调、浮层删掉", done[0] and host.get_child_count() == 0, "done %s 子节点 %d" % [str(done[0]), host.get_child_count()])
	print("分母 %d 条" % _n)
	print("ALL PASS" if _fail == 0 else "FAILED %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
