extends Node
## 援军小将录屏台(不是门禁, 2026-10-29): 决胜战场里左方(蓝方 = 我方)一个人都没有 ⇒ 上「援军小将」, 放一次「四面合围」。
## 方案书 docs/plans/20261029-终极战场援军小将.md; 机制 scripts/systems/skills/reserve_system.gd、
##   scripts/scenes/battle/dual_lane_flow.gd 的 _dl_survivor_specs(左方幸存名单为空 ⇒ 援军小将)。
##
## 时间线(游戏内秒; --write-movie 下 = 视频秒, 每帧恰好 1/fps):
##   0 s    真战斗场 RealtimeBattle3D.tscn 进树。进场那一帧还在「三路开战」幕布上、场上是空的 ⇒
##          当场把对局状态改成「上路我方赢 / 下路对方赢 → 决胜」, 左方幸存名单为空, 右方是下路活下来的
##          两只龟 + 一只远程小将(带残血), 换成决胜那一幕对阵(左列 = 援军小将)。
##   3 s    点掉对阵幕(同玩家「点击继续」, 走 _dl_present_click 真入口) → 真建决胜战场、开打。
##   开打   给援军小将满龟能(四面合围冷却清零 —— 录制专用, 正常要攒 135 龟能 ≈ 10 秒)。
##   出手   四道气波在目标前后左右同时出现、往中间合围 → 命中飘字(红 = 物理段, 蓝 = 魔法段)。
##   收尾   这一轮气波全部结算后再录 6 秒, 且总长不少于 14 秒、最多 25 秒, 然后自己 get_tree().quit()。
##
## 跑法 —— 录视频(窗口只开右屏、静音):
##   SHIP=1 TURTLE_SUPABASE=" " TURTLE_BACKEND=" " APPDATA=<单独目录> XDG_DATA_HOME=<同一目录> \
##   <godot> --path . --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 1960,60 \
##     --write-movie <输出目录>/reserve_minion.avi --fixed-fps 30 --quit-after 2000 res://tests/_rec_reserve_minion.tscn
##   · SHIP=1 关 demo 劫持(CLAUDE.md §4); TURTLE_SUPABASE / TURTLE_BACKEND 置空 = 不连后端。
##   · --audio-driver Dummy: 音箱不出声; Movie Maker 本来就从 Dummy 驱动取混音写进 .avi(声音照样录进去)。
##   · --quit-after 2000 只是兜底(本台 25 秒内一定自己 quit; 2000 帧 = 30fps 下 66 秒 / 60fps 下 33 秒)。
##   · APPDATA / XDG_DATA_HOME 指一个单独目录: 不读玩家真存档里的设置(静音 / 大师形象等), 也不会写真存档
##     (本台还置了 test_mode, save() 空转)。
##   · 要 60fps 就 --fixed-fps 60, 时间线不变(按游戏秒算, 不按帧数)。
## 跑法 —— 无头自查(不出画面): 同上去掉 --write-movie / --resolution / --position / --rendering-driver,
##   加 --headless --audio-driver Dummy。[REC] 行逐条记录; 结尾 "REC OK"(退出码 0)或 "REC FAIL: 原因"(退出码 1)。
## 可选环境变量: REC_PREVIEW_SEC = 对阵幕停几秒(默认 3; 0 = 一进场就点掉) · REC_TAIL_SEC = 最后一轮气波结算后再录几秒(默认 6)
##   · REC_PROBE=1 = 气波在场的每帧打援军小将 / 敌人 / 气波的坐标(查判定用)。
## 立绘 / 动作 / 气波 / 演出都是援军小将自己的素材(reserve_system.gd + reserve_vfx.gd), 对阵幕名字「援军小将」。

const BATTLE_SCENE := "res://scenes/RealtimeBattle3D.tscn"
const Backend := preload("res://scripts/net/backend.gd")
const SEED := 20261029          ## 只用来定地图与随机数序列(两次录出来是同一张图); 播完种立刻关掉「每帧一步」
const LEVEL := 6
const N_LEFT := 10              ## 左方本周已打场数 ⇒ 援军小将属性 ×(1 + 4% × 10) = 1400 血 / 70 攻
const MIN_TOTAL := 14.0
const MAX_TOTAL := 25.0

var _bt: Node = null
var _el := 0.0                  ## 本台自己的钟: 累加 _process 的 delta(Movie Maker 下恰好是视频时间)
var _preview_sec := 3.0
var _tail_sec := 6.0
var _clicked := false
var _fight_logged := false
var _cd_set := false
var _cd_prev := -1.0
var _casts := 0
var _cast_at := -1.0
var _waves_now := 0
var _waves_max := 0
var _waves_seen := false
var _resolved_at := -1.0
var _rounds := 0                ## 已结算完的气波轮数(一次出手 = 一轮四道)
var _mag_prev := 0
var _hits := 0
var _phy_prev := 0
var _left_ok := false
var _right_n := 0
var _done := false


func _env_f(k: String, dflt: float) -> float:
	var s := OS.get_environment(k).strip_edges()
	return float(s) if s.is_valid_float() else dflt


func _ready() -> void:
	_preview_sec = maxf(0.0, _env_f("REC_PREVIEW_SEC", 3.0))
	_tail_sec = maxf(1.0, _env_f("REC_TAIL_SEC", 6.0))
	var ct := get_node_or_null("/root/CursorTheme")
	if ct != null and ct.get("_layer") is CanvasLayer:
		(ct.get("_layer") as CanvasLayer).visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		_fail("没有 GameState")
		return
	gs.test_mode = true
	gs.tutorial_active = false
	var a := _snap_a(gs)
	var b: Dictionary = a.duplicate(true)
	b["profile"] = {"name": "紫方", "avatar": "stone", "id": "g_rec_b"}
	b["ghost_id"] = "g_rec_b"
	## 对局状态走裁判同一条路(RefereeRunner.run 第 33~41 行): 任务单 → state_for → apply_state。
	var job := {"v": 1, "job_id": 1, "match_id": "6f1c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b", "mode": "gauntlet",
		"key": {"week": 1, "account": "t"}, "seed": SEED, "client_version": ReplayRecorder.client_version(),
		"level": LEVEL, "a": a, "b": b}
	job = JSON.parse_string(JSON.stringify(job))
	var seed0 := OS.get_environment("TURTLE_SEED")
	OS.set_environment("TURTLE_SEED", str(SEED))
	_bt = (load(BATTLE_SCENE) as PackedScene).instantiate()
	var st: Dictionary = RefereeJob.state_for(job, Callable(_bt, "_foe_normalize_lane"))
	if st.has("_error"):
		_fail("state_for: " + str(st["_error"]))
		return
	gs.reset_dual_lane()
	ReplayRecorder.apply_state(st)
	ReplayRecorder.pending_play = {}
	ReplayRecorder.pending_referee = {}
	gs.season_total_battles = N_LEFT
	add_child(_bt)
	## 种子已播完(地图已按它选好) ⇒ 关掉「每帧恰一步」, 改走交互累加器: sim 时间 = Σ delta, 与帧率无关
	##   (stream_player.gd 同一手法)。不关的话 30fps 录出来是半速。
	_bt._deterministic = false
	if seed0 == "":
		OS.unset_environment("TURTLE_SEED")
	else:
		OS.set_environment("TURTLE_SEED", seed0)
	if str(_bt._dl_state) != "overview":
		_fail("进场后不在三路总览幕(实际 %s) —— 没法在建场前换成决胜" % str(_bt._dl_state))
		return
	## 进场时 _spawn_teams 把分路重置成上路(battle_spawn.gd:30~41), 战场此刻还没建(幕布期间场上是空的)。
	##   ⇒ 这里把状态换成「上路我方赢 / 下路对方赢 → 决胜」:
	##   · 左方: 上路赢了, 但活下来的只有召唤物(幸存名单不收召唤物) ⇒ 名单为空 ⇒ 援军小将
	##   · 右方: 下路活下来的石头龟 / 竹叶龟 / 远程小将, 各带残血(幸存者回 30% 已损生命之后的样子)
	gs.current_lane = "final"
	gs.lane_results = {"top": "left", "bottom": "right"}
	var eqs: Array = _shop_ids()
	gs.dual_survivors = {"left": [], "right": [
		{"kind": "leader", "id": "stone", "hp_frac": 0.58, "equips": [{"id": str(eqs[1 % eqs.size()]), "star": 1}]},
		{"kind": "leader", "id": "bamboo", "hp_frac": 0.46, "equips": [{"id": str(eqs[2 % eqs.size()]), "star": 1}]},
		{"kind": "minion", "role": "back", "elite": false, "hp_frac": 0.71},
	]}
	gs.egg_hp = {"left": 3300.0, "right": 3900.0}
	var old = _bt._dl_present_root
	_bt._dl_sys._dl_clear_present_overlay()
	if old != null and is_instance_valid(old):
		(old as CanvasItem).visible = false        # 总览幕直接藏掉(它自己的淡出 tween 照走、走完自己 queue_free)
	_bt._dl_sys._dl_enter_present("preview")
	if _bt._dl_present_root != null and is_instance_valid(_bt._dl_present_root):
		_bt._dl_present_root.modulate.a = 1.0     # 第一帧就是不透明的对阵幕(淡入 tween 从当前值 1 走到 1)
	print("[REC] 进场: 决胜对阵幕, 左方幸存 %d 只, 右方幸存 %d 只" % [
		(gs.dual_survivors["left"] as Array).size(), (gs.dual_survivors["right"] as Array).size()])


## 与 verify_reserve_minion._snap_a 同形: 三统领(普通龟 / 石头龟 / 竹叶龟)各带一件商店装备。
func _snap_a(gs) -> Dictionary:
	gs.reset_dual_lane()
	gs.season_leaders = ["basic", "stone", "bamboo"]
	gs.left_team.assign(gs.season_leaders)
	var shop: Array = _shop_ids()
	var pe := {}
	var k := 0
	for pid in gs.season_leaders:
		pe[pid] = [{"id": str(shop[k % shop.size()]), "star": 1}]
		k += 1
	gs.persistent_equipped = pe
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic"},
			{"kind": "minion", "role": "front", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	gs.loadouts = {"basic": 1, "stone": 2}
	gs.trainer_skill = "hook"
	gs.season_level = LEVEL
	gs.season_total_battles = N_LEFT
	return Backend.build_ghost_snapshot("g_rec_a", {"name": "蓝方", "avatar": "basic", "id": "g_rec_a"})


func _shop_ids() -> Array:
	var out: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			out.append(str((e as Dictionary)["id"]))
	if out.is_empty():
		out.append("p2eq_001")
	return out


func _fielded(side: String) -> Array:
	var out: Array = []
	for u in _bt._units:
		if u.get("alive", false) and str(u.get("side", "")) == side and not u.get("_isEgg", false) \
				and not u.get("is_trainer", false) and not u.get("is_summon", false):
			out.append(u)
	return out


func _reserve() -> Dictionary:
	for u in _bt._units:
		if u.get("_isMinion", false) and str(u.get("minion_role", "")) == "reserve":
			return u
	return {}


## 场上还在的气波弹体(Sprite3D, 贴图 = ReserveSystem.WAVE_TEX)。
func _wave_nodes() -> Array:
	var out: Array = []
	var w = _bt.get("_world")
	if w == null or not is_instance_valid(w):
		return out
	for c in (w as Node).get_children():
		if c is Sprite3D and (c as Sprite3D).texture != null \
				and (c as Sprite3D).texture.resource_path in [ReserveSystem.WAVE_TEX, ReserveSystem.WAVE_DIR_TEX]:
			out.append(c)
	return out


func _hp_line(side: String) -> String:
	var parts: Array = []
	for u in _fielded(side):
		parts.append("%s %d/%d" % [str(u.get("name", "?")), int(round(float(u["hp"]))), int(round(float(u["maxHp"])))])
	return ", ".join(parts)


func _process(delta: float) -> void:
	if _done or _bt == null or not is_instance_valid(_bt):
		return
	_el += delta
	if not _clicked:
		if _el >= _preview_sec:
			_clicked = true
			print("[REC] %.2fs 点掉对阵幕(状态 %s)" % [_el, str(_bt._dl_state)])
			_bt._dl_sys._dl_present_click()
		return
	var r := _reserve()
	if not _fight_logged and str(_bt._dl_state) == "fight":
		_fight_logged = true
		var l: Array = _fielded("left")
		var rr: Array = _fielded("right")
		_right_n = rr.size()
		_left_ok = l.size() == 1 and not r.is_empty() and is_same(l[0], r) and str(r.get("name", "")) == ReserveConsts.NAME
		print("[REC] %.2fs 开打 · 车道 %s · 左方: %s · 右方: %s" % [_el, str(GameState.current_lane),
			", ".join(l.map(func(u): return "%s(role=%s)" % [str(u.get("name")), str(u.get("minion_role", "-"))])),
			", ".join(rr.map(func(u): return str(u.get("name"))))])
		if not r.is_empty():
			print("[REC]   援军小将 血 %d · 攻 %.1f · 双抗 %.1f/%.1f · 远程 %s · 射程 %d · 技能 %s · 龟能 %s" % [
				int(float(r["maxHp"])), float(r["atk"]), float(r["def"]), float(r["mr"]), str(not bool(r.get("melee", true))),
				int(float(r.get("atk_range", 0.0))), str(r.get("active_skills")), str(r.get("energy_cost"))])
	if r.is_empty():
		_check_end()
		return
	_follow_cam(r)
	## 满龟能: 四面合围冷却清零(只做一次; 非空字典 ⇒ _tick_skill_cd 不会再懒初始化成满冷却)
	if not _cd_set and str(_bt._dl_state) == "fight":
		_cd_set = true
		var cds: Dictionary = r.get("skill_cd", {})
		cds[ReserveConsts.SKILL] = 0.0
		r["skill_cd"] = cds
		print("[REC] %.2fs 援军小将满龟能(四面合围冷却清零)" % _el)
	var cd: float = float((r.get("skill_cd", {}) as Dictionary).get(ReserveConsts.SKILL, -1.0))
	if _cd_set and _cd_prev >= 0.0 and cd > _cd_prev + 1.0:
		_casts += 1
		if _cast_at < 0.0:
			_cast_at = _el
		print("[REC] %.2fs ★四面合围 第 %d 次出手(冷却 %.2f → %.2f) · 右方: %s" % [_el, _casts, _cd_prev, cd, _hp_line("right")])
	_cd_prev = cd
	var wn: Array = _wave_nodes()
	if wn.size() != _waves_now:
		var ps: Array = wn.map(func(n): return "(%.1f, %.1f)" % [(n as Node3D).global_position.x, (n as Node3D).global_position.z])
		print("[REC] %.2fs 场上气波 %d 道 %s" % [_el, wn.size(), " ".join(ps)])
		if wn.size() > 0:
			_waves_seen = true
		elif _waves_seen and _casts > _rounds:
			_rounds = _casts
			_resolved_at = _el
			print("[REC] %.2fs 第 %d 轮气波全部结算" % [_el, _rounds])
	if OS.has_environment("REC_PROBE") and wn.size() > 0:
		var eps: Array = []
		for e in _fielded("right"):
			var wp: Vector3 = _bt._world_pos(e["pos"], 0.0)
			eps.append("%s(%.1f,%.1f)" % [str(e.get("name")), wp.x, wp.z])
		var rp: Vector3 = _bt._world_pos(r["pos"], 0.0)
		print("[PROBE] %.2fs 小将(%.1f,%.1f) 敌 %s 波 %s" % [_el, rp.x, rp.z, " ".join(eps),
			" ".join(wn.map(func(n): return "(%.1f,%.1f)" % [(n as Node3D).global_position.x, (n as Node3D).global_position.z]))])
	_waves_now = wn.size()
	_waves_max = maxi(_waves_max, _waves_now)
	var dt: Dictionary = r.get("_st_dealt_by_type", {})
	var mag := int(dt.get("mag", 0))
	var phy := int(dt.get("phy", 0))
	if mag > _mag_prev:
		_hits += 1
		print("[REC] %.2fs ★气波命中: 魔法段 +%d(物理 +%d) · 右方: %s" % [_el, mag - _mag_prev, phy - _phy_prev, _hp_line("right")])
	_mag_prev = mag
	_phy_prev = phy
	_check_end()


## 镜头(录制专用): 开打后约 1 秒内从全景推近到 REC_ZOOM 倍(默认 2.0), 之后每帧平滑跟住「援军小将 ↔ 离它最近的敌人」中点。
##   走游戏自己的缩放 / 平移字段(_cam_zoom / _cam_pan → _apply_cam_zoom), 不改游戏代码。
var _cam_k := 0.0
func _follow_cam(r: Dictionary) -> void:
	var st := str(_bt._dl_state)
	if st != "fight" and st != "eggwindow":
		return
	var p: Vector2 = r["pos"]
	var foes: Array = _fielded("right")
	if not foes.is_empty():
		var best: Dictionary = foes[0]
		for e in foes:
			if ((e["pos"] as Vector2) - p).length() < ((best["pos"] as Vector2) - p).length():
				best = e
		p = (p + (best["pos"] as Vector2)) * 0.5
	var wp: Vector3 = _bt._world_pos(p, 0.0)
	var want := Vector3(wp.x - _bt.CAM_TARGET.x, 0.0, wp.z - _bt.CAM_TARGET.z)
	_cam_k = minf(_cam_k + 0.0025, 0.08)
	_bt._cam_pan = (_bt._cam_pan as Vector3).lerp(want, _cam_k)
	_bt._cam_zoom = lerpf(float(_bt._cam_zoom), _env_f("REC_ZOOM", 2.0), _cam_k)
	_bt._apply_cam_zoom()


func _check_end() -> void:
	var enough: bool = _rounds >= 1 and _el >= maxf(_resolved_at + _tail_sec, MIN_TOTAL)
	if not enough and _el < MAX_TOTAL:
		return
	_done = true
	var why: Array = []
	if not _left_ok:
		why.append("左方上场的不是唯一一只援军小将")
	if _right_n < 2:
		why.append("右方幸存不足 2 只(%d)" % _right_n)
	if _casts < 1:
		why.append("四面合围一次都没放")
	if _waves_max < ReserveConsts.WAVES:
		why.append("同时在场的气波最多 %d 道(应 %d)" % [_waves_max, ReserveConsts.WAVES])
	if _hits < 1:
		why.append("气波没打中任何人(援军小将魔法伤害 0)")
	if _el < 12.0 or _el > MAX_TOTAL + 0.5:
		why.append("总长 %.1f 秒不在 12~25 秒" % _el)
	var rv := _reserve()
	print("[REC] 收尾 %.2fs · 出手 %d 次 · 同时气波最多 %d 道 · 命中事件 %d 次 · 首次出手 %.2fs · 结算 %.2fs · 援军小将 %s" % [
		_el, _casts, _waves_max, _hits, _cast_at, _resolved_at,
		"不在场" if rv.is_empty() else (("%d/%d" % [int(round(float(rv["hp"]))), int(round(float(rv["maxHp"])))]) if rv.get("alive", false) else "已阵亡")])
	if why.is_empty():
		print("REC OK")
		get_tree().quit(0)
	else:
		print("REC FAIL: " + " / ".join(why))
		get_tree().quit(1)


func _fail(msg: String) -> void:
	_done = true
	print("REC FAIL: " + msg)
	get_tree().quit(1)
