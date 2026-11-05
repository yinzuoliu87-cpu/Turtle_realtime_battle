extends Node
## verify_sfx_events.gd —— 音效事件接进游戏了没有。量的是【游戏里真播出去的是哪条】(Audio.recent)。
## 2026-11-04 · A5 起; ★2026-11-05 音效全部重做(用户「旧的那个普攻、伤害音效、盾音效，全部都要重做，全部都要达到云顶的标准」
##   「原来的音效要删掉」「云顶音效怎么做的？每个技能怎么做的这个音效？」) ⇒ 照云顶 / LoL 的拆法改判据:
##   ① 事件表(SfxEvents, build_sfx_v2.py 生成)每个变体文件都在、都载进 Audio; ①b 旧音效(ev/ 与 PoC 七条)删干净了, 表里不许再指向它们
##   ② ★28 只龟逐只真打一次普攻(_basic_attack → 推进到命中): 出手播 bas_<id>、命中播 bah_<id>
##   ②b 普攻暴击 ⇒ 这只龟自己的 crit_<id>
##   ③ 小将普攻 ⇒ 公共 g_hit / g_crit(不借某只龟的声音), 也没有出手声
##   ④ 按钮 · ⑤ 结算 · ⑥ 奖励 · ⑦ 限幅器 · ⑨ 总音量(沿用)
##   ⑧ 全场命中声同一窗口 1 路
##   ⑩ 放技能: 87 个技能各播 sk_<技能类型>; 火山形态三条; 不给技能类型 ⇒ 不出声(没有 cast_<龟 id> 退路了); ⑩b 真入口 _cast_skill
##   ⑩e ★技能命中: 放过技能之后这只龟的技能伤害播 skh_<技能类型>(分母 = 表里有命中声的技能数)
##   ⑩f ★装备: 装备上下文里的伤害 / 治疗 / 护盾播 eq_<编号>; 持续回复类(龟甲片)上下文里的治疗不出声; 没有自己声音的装备伤害走公共声、不冒充技能命中
##   ⑪ 放技能播放器比普攻高 6~8 dB · ⑫ 阵亡 g_death / 开战
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

	## ① 事件表(含每个变体文件)
	var n_ev := 0
	var n_file := 0
	var miss: Array = []
	var old_ref: Array = []
	for ev in SfxEvents.EVENTS:
		n_ev += 1
		if not au.has_sfx(ev):
			miss.append(ev)
		for p in SfxEvents.VARIANTS.get(ev, [SfxEvents.EVENTS[ev]]):
			n_file += 1
			if not ResourceLoader.exists(str(p)):
				miss.append(str(p))
			if not str(p).begins_with("res://assets/audio/sfx/v2/"):
				old_ref.append(str(p))
	_ok("① 事件表 %d 条 / %d 个变体文件全部在、全部载进 Audio" % [n_ev, n_file], n_ev >= 300 and n_file >= n_ev and miss.is_empty(), str(miss))
	## ①b 旧音效删干净: ev/ 目录没了, PoC 七条与方波合成的两条也没了, 表里不指向 v2 以外
	var gone: Array = []
	for f in ["res://assets/audio/sfx/hit-physical.wav", "res://assets/audio/sfx/hit-crit.wav", "res://assets/audio/sfx/heal.wav",
			"res://assets/audio/sfx/shield-gain.wav", "res://assets/audio/sfx/shield-break.wav", "res://assets/audio/sfx/defeat.wav",
			"res://assets/audio/sfx/rebirth.wav", "res://assets/audio/sfx/queue_found.wav", "res://assets/audio/sfx/studio_intro.wav"]:
		if FileAccess.file_exists(f):
			gone.append(f)
	if DirAccess.dir_exists_absolute("res://assets/audio/sfx/ev"):
		gone.append("res://assets/audio/sfx/ev/")
	_ok("①b 旧音效全部删除(9 个旧文件 + ev/ 目录), 事件表只指向 v2", gone.is_empty() and old_ref.is_empty(), str(gone) + " " + str(old_ref))

	var scene = RTScene.new()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.set_process(false)
	scene.set_physics_process(false)
	scene._edit_mode = false
	scene._dl_state = "fight"

	## ② 每只龟普攻 → 自己的出手 + 命中
	var ids: Array = []
	for p in DataRegistry.launch_pets:
		ids.append(str((p as Dictionary).get("id", "")))
	var wrong: Array = []
	var n_t := 0
	for id in ids:
		var got := await _basic_once(scene, au, id, {})
		n_t += 1
		if not (got.has("bas_" + id) and (got.has("bah_" + id) or got.has("crit_" + id))):   # 这一下刚好暴击 ⇒ 播的是 crit_<id>
			wrong.append("%s → %s" % [id, str(got)])
	_ok("★② %d 只龟普攻: 出手播 bas_<id>、命中播 bah_<id>(暴击时 crit_<id>; 云顶 BasicAttack_OnCast + OnHit)" % n_t, n_t >= 28 and wrong.is_empty(), "; ".join(wrong))
	## ②b 普攻暴击 ⇒ 这只龟自己的暴击声
	var cw2: Array = []
	for id in ids:
		scene._t += 1.0
		scene._audio_sys._hit_ts.clear()
		scene._audio_sys._ev_last_t.clear()
		au.recent.clear()
		scene._audio_sys._sfx_hit(true, {"id": id}, true)
		if not au.recent.has("crit_" + id):
			cw2.append("%s → %s" % [id, str(au.recent)])
	_ok("②b %d 只龟普攻暴击各播自己的 crit_<id>" % ids.size(), ids.size() >= 28 and cw2.is_empty(), "; ".join(cw2))

	## ③ 小将: 公共命中声, 没有出手声
	var gm := await _basic_once(scene, au, "__minion__", {"minion": true, "role": "front", "level": 1})
	var own_any := false
	for s in gm:
		if str(s).begins_with("bah_") or str(s).begins_with("bas_"):
			own_any = true
	_ok("③ 小将普攻播公共 g_hit / g_crit(不借某只龟的声音、没有出手声)", not own_any and (gm.has("g_hit") or gm.has("g_crit")), str(gm))

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

	## ⑦ 主总线有限幅器
	var has_lim := false
	for i in range(AudioServer.get_bus_effect_count(0)):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter:
			has_lim = (AudioServer.get_bus_effect(0, i) as AudioEffectHardLimiter).ceiling_db <= -0.9
	_ok("⑦ 主总线挂着限幅器(天花板 ≤ −0.9 dB)", has_lim)
	## ⑨ 总音量 −7 dB
	if AudioServer.is_bus_mute(0):
		_ok("⑨ 总音量常量 = −7 dB(本次 QUIET 静音, 主总线 −80 由静音接管)", is_equal_approx(float(au.MASTER_TRIM_DB), -7.0))
	else:
		_ok("⑨ 主总线音量 = 总音量常量 −7 dB", is_equal_approx(AudioServer.get_bus_volume_db(0), float(au.MASTER_TRIM_DB)) and float(au.MASTER_TRIM_DB) < -6.0,
			"%.1f dB" % AudioServer.get_bus_volume_db(0))
	## ⑧ 全场命中声同一窗口最多 1 路
	au.recent.clear()
	scene._audio_sys._ev_last_t.clear()
	scene._audio_sys._hit_ts.clear()
	scene._t += 5.0
	var six := ["stone", "bamboo", "angel", "ice", "ninja", "pirate"]
	for sid in six:
		scene._audio_sys._sfx_hit(false, {"id": sid}, true)
	var n_hit := 0
	for s in au.recent:
		if str(s).begins_with("bah_") or str(s).begins_with("g_hit") or str(s).begins_with("crit_"):
			n_hit += 1
	_ok("⑧ 6 只龟同一刻普攻命中 ⇒ 命中声只出 1 路(分母 6)", n_hit == 1, str(au.recent))
	scene._t += 0.2
	au.recent.clear()
	scene._audio_sys._sfx_hit(false, {"id": "lava"}, true)
	_ok("⑧b 过了窗口(0.2 秒后)新的命中照常出声", au.recent.has("bah_lava"), str(au.recent))

	## ⑩ 放技能: 每个技能一条 sk_<技能类型>
	var sw: Array = []
	var n_s := 0
	var skill_types: Array = []
	for p in DataRegistry.launch_pets:
		var pool: Array = (p as Dictionary).get("skillPool", [])
		for si in range(1, mini(4, pool.size())):
			var st: String = str((pool[si] as Dictionary).get("type", ""))
			scene._t += 1.0
			scene._audio_sys._cast_ts.clear()
			au.recent.clear()
			var u: Dictionary = scene._spawn._make_unit(str(p["id"]), "left", Vector2(600, 400))
			scene._audio_sys.sfx_skill_cast(u, VfxTiers.NORMAL, st)
			n_s += 1
			skill_types.append([str(p["id"]), st])
			if not au.recent.has("sk_" + st):
				sw.append("%s/%s → %s" % [str(p["id"]), st, str(au.recent)])
	_ok("⑩ %d 个技能放出时各播自己那条 sk_<技能类型>" % n_s, n_s >= 84 and sw.is_empty(), "; ".join(sw))
	var vw: Array = []
	for pair in [["lavaQuake", "sk_volcanoErupt"], ["lavaSurge", "sk_volcanoSmash"], ["lavaErupt", "sk_lavaRampage"]]:
		var lv: Dictionary = scene._spawn._make_unit("lava", "left", Vector2(600, 400))
		lv["volcano"] = true
		scene._t += 1.0
		scene._audio_sys._cast_ts.clear()
		au.recent.clear()
		scene._audio_sys.sfx_skill_cast(lv, VfxTiers.NORMAL, pair[0])
		if not au.recent.has(pair[1]):
			vw.append("%s → %s" % [pair[0], str(au.recent)])
	_ok("⑩d 火山形态三个技能播火山那三条", vw.is_empty(), "; ".join(vw))
	scene._t += 1.0
	scene._audio_sys._cast_ts.clear()
	au.recent.clear()
	scene._audio_sys.sfx_skill_cast(scene._spawn._make_unit("stone", "left", Vector2(600, 400)))
	_ok("⑩a 不给技能类型 ⇒ 不出声(旧的 cast_<龟 id> 退路已删)", au.recent.is_empty(), str(au.recent))
	## ⑩e ★技能命中: 放过技能后, 这只龟的非普攻伤害播 skh_<技能类型>
	var hw: Array = []
	var n_h := 0
	for pr in skill_types:
		if not SfxEvents.EVENTS.has("skh_" + str(pr[1])):
			continue
		var u2: Dictionary = scene._spawn._make_unit(str(pr[0]), "left", Vector2(600, 400))
		scene._t += 1.0
		scene._audio_sys._cast_ts.clear()
		scene._audio_sys._skh_ts.clear()
		scene._audio_sys.sfx_skill_cast(u2, VfxTiers.NORMAL, str(pr[1]))
		scene._t += 0.4
		au.recent.clear()
		scene._audio_sys._sfx_hit(false, u2, false)
		n_h += 1
		if not au.recent.has("skh_" + str(pr[1])):
			hw.append("%s/%s → %s" % [pr[0], pr[1], str(au.recent)])
	_ok("★⑩e %d 个技能放出后, 它的技能伤害播自己的 skh_<技能类型>" % n_h, n_h >= 55 and hw.is_empty(), "; ".join(hw))
	## ⑩f ★装备
	var carrier: Dictionary = scene._spawn._make_unit("basic", "left", Vector2(600, 400))
	scene._t += 2.0
	au.recent.clear()
	scene._audio_sys._sfx_hit(false, carrier, false, "p2eq_025")
	var eq_dmg_ok: bool = au.recent.has("eq_025")
	scene._t += 2.0
	au.recent.clear()
	var tl0: Array = scene._equip_sys.tally.push(carrier, "p2eq_018")
	scene._audio_sys._sfx_heal()
	var eq_heal_ok: bool = au.recent.has("eq_018")
	scene._equip_sys.tally.pop(tl0)
	scene._t += 2.0
	au.recent.clear()
	var tl1: Array = scene._equip_sys.tally.push(carrier, "p2eq_016")
	scene._audio_sys._sfx_shield_gain()
	var eq_sh_ok: bool = au.recent.has("eq_016")
	scene._equip_sys.tally.pop(tl1)
	scene._t += 2.0
	au.recent.clear()
	var tl2: Array = scene._equip_sys.tally.push(carrier, "p2eq_091")
	scene._audio_sys._sfx_heal()
	var quiet_ok: bool = au.recent.is_empty()
	scene._equip_sys.tally.pop(tl2)
	scene._t += 2.0
	scene._audio_sys.sfx_skill_cast(carrier, VfxTiers.NORMAL, "basicBarrage")
	scene._t += 0.4
	au.recent.clear()
	scene._audio_sys._sfx_hit(false, carrier, false, "p2eq_003")   # 鲨齿溅射: 没有自己的声音
	var no_fake: bool = not au.recent.has("skh_basicBarrage") and au.recent.has("g_skill_hit")
	_ok("★⑩f 装备伤害播 eq_025 / 治疗播 eq_018 / 护盾播 eq_016; 龟甲片持续回复不出声; 没有自己声音的装备伤害走公共声不冒充技能",
		eq_dmg_ok and eq_heal_ok and eq_sh_ok and quiet_ok and no_fake,
		"伤害 %s 治疗 %s 护盾 %s 静默 %s 不冒充 %s · 最后 %s" % [eq_dmg_ok, eq_heal_ok, eq_sh_ok, quiet_ok, no_fake, str(au.recent)])
	var n_eq := 0
	for ev in SfxEvents.EVENTS:
		if str(ev).begins_with("eq_"):
			n_eq += 1
	_ok("⑩g 装备音效 ≥ 80 件(有触发时刻的都有; 纯属性的不出声)", n_eq >= 80, "%d 件" % n_eq)

	scene._units.clear()
	scene._t += 5.0
	var ice: Dictionary = scene._spawn._make_unit("ice", "left", Vector2(600, 400))
	var foe: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(700, 400))
	foe["maxHp"] = 1.0e7; foe["hp"] = 1.0e7
	scene._units.append(ice); scene._units.append(foe)
	scene._audio_sys._cast_ts.clear(); scene._audio_sys._ev_last_t.clear()
	au.recent.clear()
	scene._cast_skill(ice, foe, "iceFrost")
	_ok("⑩b ★真入口: _cast_skill(寒冰·冰霜) 播 sk_iceFrost", au.recent.has("sk_iceFrost"), str(au.recent))
	## ⑪ 层次: 放技能播放器比普攻高 6~8 dB(普攻层 ATK_GAIN −7 dB; 成品文件里技能放出再高 3 dB, build_sfx_v2 TARGET_RMS)
	var _sv: float = au.sfx_volume
	au.sfx_volume = 0.8
	scene._t += 5.0
	scene._audio_sys._hit_ts.clear(); scene._audio_sys._ev_last_t.clear()
	scene._audio_sys._sfx_hit(false, {"id": "stone"}, true)
	var v_atk: float = _last_player_db(au)
	scene._t += 1.0
	scene._audio_sys._cast_ts.clear()
	scene._audio_sys.sfx_skill_cast(scene._spawn._make_unit("stone", "left", Vector2(600, 400)), VfxTiers.ULTIMATE, "stoneTaunt")
	var v_cast: float = _last_player_db(au)
	au.sfx_volume = _sv
	_ok("⑪ 放技能播放器比普攻高 6~8 dB(普攻层压低 7 dB)", v_cast - v_atk > 6.0 and v_cast - v_atk < 8.0, "普攻 %.1f · 放技能 %.1f dB" % [v_atk, v_cast])
	## ⑫ 阵亡 / 开战
	scene._t += 5.0
	au.recent.clear()
	scene._kill(foe, ice)
	var died_ok: bool = au.recent.has("g_death")
	var sm: Dictionary = scene._spawn._make_unit("basic", "right", Vector2(800, 400))
	sm["is_summon"] = true
	scene._units.append(sm)
	scene._t += 1.0
	au.recent.clear()
	scene._kill(sm, ice)
	_ok("⑫ 单位阵亡(真入口 _kill) 播 g_death; 召唤物阵亡不播", died_ok and not au.recent.has("g_death"), "召唤物那次: %s" % str(au.recent))
	au.recent.clear()
	scene._dl_sys._dl_fight_start_dramatize()
	_ok("⑫b 开战演出播 fight_start", au.recent.has("fight_start"), str(au.recent))
	## ⑬ 旧录像里的旧事件名照样出声(映射到新名)
	var lg: Array = []
	for pr in [["hit-physical", "g_hit"], ["atk_stone", "bah_stone"], ["cast_iceFrost", "sk_iceFrost"], ["unit_death", "g_death"], ["shield-gain", "g_shield_gain"]]:
		au.recent.clear()
		au.play_sfx(str(pr[0]))
		if not au.recent.has(str(pr[1])):
			lg.append("%s → %s" % [pr[0], str(au.recent)])
	_ok("⑬ 旧录像里的旧事件名映射到新名出声", lg.is_empty(), "; ".join(lg))

	## ⑥ 结算页奖励
	scene._settled = false
	scene._had_season = true
	scene._last_reward = 7
	GameState.season_level = 5
	scene.set_meta("_season_lv0", 4)
	au.recent.clear()
	scene._hud._show_banner(true)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and not au.recent.has("level_up"):
		await get_tree().process_frame
	_ok("⑥ 结算页拿到币 ⇒ 播 reward_normal、本局升级 ⇒ 播 level_up", au.recent.has("reward_normal") and au.recent.has("level_up"), str(au.recent))
	scene._had_season = false
	## ⑤ 结算
	for won in [true, false]:
		au.recent.clear()
		scene._settled = false
		scene._hud._show_banner(won)
		await get_tree().process_frame
		var want := "victory" if won else "defeat"
		_ok("⑤ 结算(%s)播 %s" % ["胜" if won else "负", want], au.recent.has(want), str(au.recent))
	_finish()


## Audio 最后建出来的那个 AudioStreamPlayer 的音量(play_sfx 每次 add_child 一个临时播放器)。
func _last_player_db(au) -> float:
	for i in range(au.get_child_count() - 1, -1, -1):
		var c = au.get_child(i)
		if c is AudioStreamPlayer and c.stream != null:
			return float(c.volume_db)
	return -999.0


## 造一个攻击方 + 打不死的假人, 直接打一次普攻, 推进到弹道落地(最多 3 秒), 返回这期间真播出去的音效名。
func _basic_once(scene, au, id: String, spec: Dictionary) -> Array:
	scene._units.clear()
	scene._t += 10.0
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
	scene._audio_sys._swing_ts.clear()
	scene._basic_attack(atk, dummy)
	for _i in range(60):
		scene._t += 0.05
		scene._ballistics._step_pending_shots(0.05)
		scene._ballistics._step_projectiles(0.05)
		if au.recent.size() >= 2 and float(dummy["hp"]) < 1.0e7:
			break
	return au.recent.duplicate()


func _finish() -> void:
	print("分母: %d 项" % _n)
	if _fail == 0:
		print("ALL PASS — 音效 v2 接进游戏了(普攻出手 / 命中 / 暴击 · 技能放出 / 命中 · 装备 · 公共)")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
