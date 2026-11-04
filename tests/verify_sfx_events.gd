extends Node
## verify_sfx_events.gd —— 音效事件接进游戏了没有(2026-11-04 · A5; 用户「一个乌龟攻击是物理伤害，另外一个也是物理伤害，
##   它们两个音效，你觉得应该是用一样的音效吗？」「我只听最终成果」)。量的是【游戏里真播出去的是哪条】(Audio.recent):
##   ① 事件表(SfxEvents, build_sfx.py 生成)每个文件都在、都载进了 Audio
##   ② ★28 只龟逐只真打一次普攻(_basic_attack → 近战即时 / 弹道推进到落地): 播的是它自己的 atk_<id>, 不是通用命中音
##   ③ 小将普攻照旧通用命中音(没有专属声)
##   ④ 按钮: 上皮肤的按钮按下去播点击音; 字是「返回」播 ui_back、「开始战斗」播 ui_confirm; 同一按钮上两次皮只响一声
##   ⑤ 结算: _show_banner(true) 播 victory、(false) 播 defeat
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_sfx_events.tscn --quit-after 3000

const RTScene := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var au = get_node_or_null("/root/Audio")
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_ok("分母: Audio 在", au != null)
	if au == null:
		_finish()
		return
	au.mute_sfx = false

	## ① 事件表
	var n_ev := 0
	var miss: Array = []
	for ev in SfxEvents.EVENTS:
		n_ev += 1
		if not (ResourceLoader.exists(str(SfxEvents.EVENTS[ev])) and au.has_sfx(ev)):
			miss.append(ev)
	_ok("① 事件表 %d 条全部载进 Audio(匹配成功沿用 queue_found.wav, 不在表里)" % n_ev, n_ev >= 37 and miss.is_empty(), str(miss))

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene._edit_mode = false
	scene._dl_state = "fight"

	## ② 每只龟普攻 → 它自己的声音
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		ids.append(str((p as Dictionary).get("id", "")))
	var wrong: Array = []
	var n_t := 0
	for id in ids:
		var got := await _basic_once(scene, au, id, {})
		n_t += 1
		if not got.has("atk_" + id):
			wrong.append("%s → %s" % [id, str(got)])
	_ok("★② %d 只龟普攻命中播的都是自己那条 atk_<id>" % n_t, n_t >= 28 and wrong.is_empty(), "; ".join(wrong))

	## ③ 小将: 没有专属声 ⇒ 通用命中音
	var gm := await _basic_once(scene, au, "__minion__", {"minion": true, "role": "front", "level": 1})
	var atk_any := false
	for s in gm:
		if str(s).begins_with("atk_"):
			atk_any = true
	_ok("③ 小将普攻照旧通用命中音(不借某只龟的声音)", not atk_any and (gm.has("hit-physical") or gm.has("hit-crit")), str(gm))

	## ④ 按钮
	var cases := [["背包", "ui_click"], ["返回", "ui_back"], ["开始战斗", "ui_confirm"], ["购买", "ui_confirm"]]
	for c in cases:
		var b := Button.new()
		b.text = str(c[0])
		add_child(b)
		UISkin.card_button(b)
		UISkin.button(b)   # 同一个按钮上两次皮
		au.recent.clear()
		b.pressed.emit()
		_ok("④ 按钮「%s」按下 → 只响一声 %s" % [c[0], c[1]], au.recent.size() == 1 and au.recent[0] == str(c[1]), str(au.recent))
		b.queue_free()

	## ⑦ 主总线有限幅器(兜底不削波; 实机录 2 分钟原来 981/1200 个 0.1 秒块贴顶)
	var has_lim := false
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			has_lim = (AudioServer.get_bus_effect(0, i) as AudioEffectHardLimiter).ceiling_db <= -0.9
	_ok("⑦ 主总线挂着限幅器(天花板 ≤ −0.9 dB)", has_lim)
	## ⑨ 总音量 −7 dB(黑箱实玩整局 −25.6 LUFS、我们原来 −11.3; 目标手机常见 −18 左右)。QUIET 跑时主总线是静音 −80, 那时量不到, 只验常量与「不静音时生效」的分支
	if AudioServer.is_bus_mute(0):
		_ok("⑨ 总音量常量 = −7 dB(本次 QUIET 静音, 主总线 −80 由静音接管)", is_equal_approx(float(au.MASTER_TRIM_DB), -7.0))
	else:
		_ok("⑨ 主总线音量 = 总音量常量 −7 dB", is_equal_approx(AudioServer.get_bus_volume_db(0), float(au.MASTER_TRIM_DB)) and float(au.MASTER_TRIM_DB) < -6.0,
			"%.1f dB" % AudioServer.get_bus_volume_db(0))
	## ⑧ 全场命中声同时最多 2 路: 6 只不同的龟同一刻普攻命中 ⇒ 只出 ≤ 2 声(原来按来源出声后 6 声叠加 → 削波)
	au.recent.clear()
	scene._audio_sys._ev_last_t.clear()
	scene._audio_sys._hit_ts.clear()
	scene._t += 5.0
	var six := ["stone", "bamboo", "angel", "ice", "ninja", "pirate"]
	for sid in six:
		scene._audio_sys._sfx_hit(false, {"id": sid}, true)
	var n_hit := 0
	for s in au.recent:
		if str(s).begins_with("atk_") or str(s).begins_with("hit-"):
			n_hit += 1
	_ok("⑧ 6 只龟同一刻普攻命中 ⇒ 命中声 ≤ 2 路(分母 6)", n_hit >= 1 and n_hit <= 2, str(au.recent))
	scene._t += 0.2
	au.recent.clear()
	scene._audio_sys._sfx_hit(false, {"id": "lava"}, true)
	_ok("⑧b 过了窗口(0.2 秒后)新的命中照常出声", au.recent.has("atk_lava"), str(au.recent))

	## ⑥ 结算页奖励: 拿到币 ⇒ 金币格弹出时 reward_normal; 本局升了级 ⇒ 接着 level_up(真入口 _show_banner → 结算页补间)
	scene._settled = false
	scene._had_season = true
	scene._last_reward = 7
	GameState.season_level = 5   # 测试档默认 1 级 ⇒ 快照 0 会被「快照 ≥ 1」挡掉; 造一个 4 → 5 的升级
	scene.set_meta("_season_lv0", 4)
	au.recent.clear()
	scene._hud._show_banner(true)
	## 结算页补间按真实时间走(奖励 0.42 s、升级 1.02 s); 无头帧很快, 按帧数等会不到点 ⇒ 按毫秒等, 最多 3 秒
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and not au.recent.has("level_up"):
		await get_tree().process_frame
	_ok("⑥ 结算页拿到币 ⇒ 播 reward_normal、本局升级 ⇒ 播 level_up", au.recent.has("reward_normal") and au.recent.has("level_up"), str(au.recent))
	scene._had_season = false
	## ⑤ 结算
	for won in [true, false]:
		au.recent.clear()
		scene._settled = false   # _show_banner 结算过一次会拦第二次(同一场景里先测胜再测负)
		scene._hud._show_banner(won)
		await get_tree().process_frame
		var want := "victory" if won else "defeat"
		_ok("⑤ 结算(%s)播 %s" % ["胜" if won else "负", want], au.recent.has(want), str(au.recent))
	_finish()


## 造一个攻击方 + 打不死的假人, 直接打一次普攻, 推进到弹道落地(最多 3 秒), 返回这期间真播出去的音效名。
func _basic_once(scene, au, id: String, spec: Dictionary) -> Array:
	scene._units.clear()
	scene._t += 10.0   # 时钟一直往前走(与真对局一样); 每只龟之间隔开, 不共用「全场最多 2 路」的时间窗
	scene._over = false
	var atk: Dictionary = scene._spawn._make_unit(id, "left", Vector2(600, 400), spec)
	atk["active_skills"] = []
	scene._units.append(atk)
	var d: float = 80.0 if bool(atk.get("melee", false)) else 220.0
	var dummy: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(600.0 + d, 400.0))
	dummy["active_skills"] = []
	dummy["no_basic"] = true
	dummy["no_move"] = true
	dummy["maxHp"] = 1.0e7
	dummy["hp"] = 1.0e7
	scene._units.append(dummy)
	await get_tree().process_frame
	au.recent.clear()
	scene._audio_sys._ev_last_t.clear()
	scene._audio_sys._hit_ts.clear()
	scene._basic_attack(atk, dummy)
	for _i in range(60):
		scene._t += 0.05
		scene._ballistics._step_pending_shots(0.05)
		scene._ballistics._step_projectiles(0.05)
		if not au.recent.is_empty() and float(dummy["hp"]) < 1.0e7:
			break
	return au.recent.duplicate()


func _finish() -> void:
	print("分母: %d 项" % _n)
	if _fail == 0:
		print("ALL PASS — 音效事件接进游戏了(普攻按来源 / 按钮 / 结算)")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
