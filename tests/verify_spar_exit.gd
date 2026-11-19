extends Node
## verify_spar_exit.gd —— 好友切磋对局里左下角的「退出」(2026-11-19, scripts/scenes/battle/spar_exit.gd)。
## 用户 11-19「然后切磋没有按钮可以退出观看吗」「切磋这个按钮应该做吧」: 11-18 起切磋幕布点不动, 对局里又没有离场的口。
## 判据(真战斗场, 走真入口 Spar.begin; 换屏由 SceneNav.nav_for_test 截下):
##   ① 切磋: 开场就有 SparExit —— 看得见、整颗在屏内左下角、画在 _ui_layer(换路幕布所在层)上面
##   ② 点它 ⇒ 出问框「退出切磋？」, 没换屏; 点「继续观看」⇒ 问框收掉、键还在、仍没换屏
##   ③ 安卓返回键(BackKey.handle) ⇒ 按的是这颗(问框出来); 问框开着再按 ⇒ 继续观看(问框收掉)
##   ④ 点「退出」⇒ 恰好换屏一次、去的是发起切磋的那一页(Spar.back_scene(): 从排行榜发起 ⇒ 排行榜)
##   ⑤ 结算屏的按钮那一步(battle_hud._settle_buttons 切磋支)⇒ 键收起
##   ⑥ 不在切磋(积分赛日普通对局)⇒ 没有这颗键(正式对局局内不放退出, 用户 07-30 / 10-19)
## 反向验证(11-19): battle_hud 去掉挂键那一行 ⇒ ①②③④ 红; 去掉 Spar.is_active() 判断 ⇒ ⑥ 红;
##   _settle_buttons 不调 hide ⇒ ⑤ 红; 离场改回主菜单 ⇒ ④ 红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const AM := preload("res://scripts/systems/replay/abandoned_match.gd")
const SE := preload("res://scripts/scenes/battle/spar_exit.gd")

var _fail := 0
var _n := 0
var _navs: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _setup_gs(gs) -> void:
	gs.reset_dual_lane()
	gs.test_mode = false
	gs.tutorial_active = false
	gs.tutorial = false
	gs.week_phase = "ranked"
	gs.hearts = 4
	gs.season_total_battles = 5
	gs.season_leaders = ["chest", "gambler", "basic"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "chest", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "gambler", "equips": []},
			{"kind": "leader", "slot": 2, "id": "basic", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.persistent_equipped = {}
	gs.trainer_skill = "hook"
	gs.dual_active = false
	gs.dual_ghost = {}


func _ghost() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261119
	var g: Dictionary = Backend.make_bot(3, rng)
	g["profile"] = {"name": "好友甲", "avatar": "stone", "id": "FRND01"}
	return g


func _battle() -> Node:
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	for _i in range(6):
		await get_tree().process_frame
	return s


func _shown(n) -> bool:
	return n != null and is_instance_valid(n) and not (n as Node).is_queued_for_deletion() and (n as CanvasItem).is_visible_in_tree()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	print("=== 切磋对局左下角「退出」 ===")
	var gs = get_node_or_null("/root/GameState")
	AM.clear()
	SceneNav.nav_for_test = func(p: String) -> void: _navs.append(p)

	## ── ①~⑤ 切磋(从排行榜发起 ⇒ 离场回排行榜, 证明不是写死好友页) ──
	_setup_gs(gs)
	_ok("分母 · 挂上切磋", Spar.begin(_ghost(), {"name": "好友甲", "tag": "FRND01", "back": Spar.LEADERBOARD_SCENE}) and Spar.is_active())
	var s = await _battle()
	var vp := Vector2(s.get_viewport().get_visible_rect().size)
	var key: Button = s.find_child(SE.N_EXIT, true, false) as Button
	var lay: CanvasLayer = s.find_child(SE.N_LAYER, true, false) as CanvasLayer
	var r := Rect2()
	if key != null:
		r = key.get_global_rect()
	_ok("① 切磋开场就有「退出」键且看得见", _shown(key), "无" if key == null else "visible=%s" % key.is_visible_in_tree())
	_ok("① 整颗在屏内、靠左下角(左半边 / 下四分之一)", key != null and Rect2(Vector2.ZERO, vp).encloses(r)
		and r.position.x < vp.x * 0.5 and r.end.y > vp.y * 0.75, "%s / 屏 %s" % [str(r), str(vp)])
	_ok("① 画在换路幕布那层(_ui_layer)上面", lay != null and s._ui_layer != null and lay.layer > int(s._ui_layer.layer),
		"%s vs %s" % [str(lay.layer) if lay != null else "无", str(s._ui_layer.layer) if s._ui_layer != null else "无"])

	if key != null:
		key.pressed.emit()
	await get_tree().process_frame
	var ask: Node = s.find_child(SE.N_ASK, true, false)
	_ok("② 点「退出」⇒ 出问框「%s」、没换屏" % SE.TXT_ASK, _shown(ask) and _has_label(ask, SE.TXT_ASK) and _navs.is_empty(), str(_navs))
	var no: Button = s.find_child(SE.N_NO, true, false) as Button
	if no != null:
		no.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("② 点「继续观看」⇒ 问框收掉、键还在、没换屏", not _shown(s.find_child(SE.N_ASK, true, false)) and _shown(key) and _navs.is_empty(),
		str(_navs))

	var r1: String = BackKey.handle(get_tree(), s)
	await get_tree().process_frame
	_ok("③ 安卓返回键 ⇒ 按的是这颗(问框出来)", r1 == BackKey.R_BUTTON and _shown(s.find_child(SE.N_ASK, true, false)) and _navs.is_empty(),
		"%s %s" % [r1, str(_navs)])
	await get_tree().process_frame
	var r2: String = BackKey.handle(get_tree(), s)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("③ 问框开着再按返回 ⇒ 继续观看", r2 == BackKey.R_BUTTON and not _shown(s.find_child(SE.N_ASK, true, false)) and _navs.is_empty(),
		"%s %s" % [r2, str(_navs)])

	if key != null:
		key.pressed.emit()
	await get_tree().process_frame
	var yes: Button = s.find_child(SE.N_YES, true, false) as Button
	if yes != null:
		yes.pressed.emit()
	await get_tree().process_frame
	_ok("④ 点「退出」⇒ 恰好换屏一次、回发起切磋的那一页(排行榜)", _navs == [Spar.LEADERBOARD_SCENE], str(_navs))

	_navs.clear()
	var row := HBoxContainer.new()
	add_child(row)
	s._hud._settle_buttons(row)
	_ok("⑤ 分母: 结算按钮那一步走的是切磋支(有「再来一局」)", row.find_child("SparAgain", true, false) != null)
	_ok("⑤ 结算屏出来 ⇒ 「退出」键收起", key != null and is_instance_valid(key) and not key.is_visible_in_tree())
	row.queue_free()
	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	_ok("分母 · 离场后不在切磋里", not Spar.is_active())

	## ── ⑥ 普通对局(积分赛日) ──
	_setup_gs(gs)
	gs.dual_active = true
	gs.test_mode = true
	var s2 = await _battle()
	_ok("⑥ 分母: 普通对局的界面层建好了", s2._ui_layer != null)
	_ok("⑥ 不在切磋 ⇒ 局内没有「退出」键", s2.find_child(SE.N_EXIT, true, false) == null and s2.find_child(SE.N_LAYER, true, false) == null)
	s2.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	gs.test_mode = false

	SceneNav.nav_for_test = Callable()
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS" if _fail == 0 and _n >= 12 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _has_label(n: Node, text: String) -> bool:
	if n == null:
		return false
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _has_label(c, text):
			return true
	return false
