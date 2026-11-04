extends Node
## verify_arena_theme_pick.gd — 正式对局「每场随机一张图」(用户 2026-10-04 拍板)
##
## 用户原话(从选项里选):「每场随机一张」—— 每场对局从 暗林 / 深礁 / 紫墟 / 赤林 四张里随机一张,
##   原来的 V0_BASE 默认图从正式对局退役。
## 方案书: docs/plans/20261003-四版完整地图.md §6。
##
## 这把尺子量五件事(编号对应派活单的门禁 ①~⑤):
##   ★0 主题只改外观(2026-11-04 改成「开场比数字」, 用户:「一串数字可以表示一张地图, 开场比较这串数字就可以了」):
##      战斗读到的地形只有 `_obstacles`(开路时 `_build_map_props` 写死, 主题只换贴图不换占地)。
##      ⇒ (a) 每张图开到正式对局【开打第一帧】, 「战斗相关那串数字」= 障碍物表(去掉只管外观的 img) + 全场单位 + 随机流状态,
##            五张图(含 V0_BASE)逐字相同; 调试场同理比开场那一帧。
##         (b) 静态白名单: 读地图主题的文件只许是 建场 / 场外装饰 / 录流核对 那几个 —— 战斗逻辑、技能、装备一旦读主题 ⇒ 红。
##      原来五张图各真打 1500 步 + 调试场两个场景五张图各跑一遍 + ④ 端到端再打两局(实测 146 / 162 秒), 换成上面两条后不用真打。
##   ①  多种子下四张都出现、分布大致均匀(打分母)
##   ②  同种子 ⇒ 同主题(纯函数算两遍 + 真建场等于纯函数; 「真建场两次」由这两条推出, 11-04 删掉第二次建场)
##   ③  正式对局不出 V0_BASE; 调试场照旧是进场前那张(开发工具不被弄坏)
##   ④a 选图不消耗战斗随机流: 产品选图入口前后 `_battle_rng.state` 逐位不变
##      (原 ④ 端到端「自己选 vs 强制同一张, 逐步指纹」10-04 反向验证实测抓不到「吃流」, 只有 ④a 抓得到 ⇒ 11-04 删掉 ④ 那两局)
##   ⑤  回放一致在 `verify_replay_roundtrip` 里量(录与播的 ArenaTheme.active 相同)
##
## 反向验证(2026-10-04 做过, 见方案书 §6): 改成 randi 选图 ⇒ ②③红; 改成从 `_battle_rng` 取数选图 ⇒ ④a③红
##   (④ 的端到端指纹对此不敏感, 见 ④a 的注释)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_arena_theme_pick.tscn --quit-after 30000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const SC := preload("res://scripts/referee/det_scenarios.gd")
const Backend := preload("res://scripts/net/backend.gd")

const FORMAL_SEED := 4242             # 正式双路那一局的种子
const FORMAL_FRAMES := 1500           # 开到「开打第一帧」的帧数上限(摆位 → 开打; 到不了开打 ⇒ 分母红)
const ALL5: Array = [AT.V0_BASE, AT.V1_DUSK, AT.V2_REEF, AT.V3_SHOAL, AT.V4_STORM]
## ★0(b) 允许读地图主题的文件(scripts/ autoload/ 下按「ArenaTheme / arena_theme.gd」字样扫)。
##   新增一个读主题的文件 ⇒ 红: 先确认它只管外观(不在 `_sim_step` 调用链上), 再加进这里并写明理由。
const THEME_READERS := {
	"res://scripts/gamedata/arena_theme.gd": "主题表本身",
	"res://scripts/scenes/battle/battle_world_builder.gd": "建场: 贴图 / 场内摆件 / 选图入口; 障碍物占地写死不读主题(★0a 量)",
	"res://scripts/scenes/battle/arena_outer.gd": "场外装饰",
	"res://scripts/systems/stream/stream_recorder.gd": "录流时记下主题名给手机核对",
	"res://scripts/systems/stream/stream_player.gd": "手机核对自己建的是不是同一张图",
}

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 全场指纹(逐 sim 步)。字段与 verify_determinism_cross 同口径 + 时钟与双路状态。
func _fp(s) -> String:
	var parts: Array = ["t=%.4f" % float(s._t), str(s._dl_state)]
	var i := 0
	for u in s._units:
		var p: Vector2 = u.get("pos", Vector2())
		parts.append("%d/%s/%s:%.3f:%.2f:%.2f:%d:%.2f:%.2f:%.2f" % [
			i, str(u.get("id", "?")), str(u.get("side", "?")),
			float(u.get("hp", 0.0)), p.x, p.y,
			1 if bool(u.get("alive", false)) else 0,
			float(u.get("shield", 0.0)), float(u.get("energy", 0.0)), float(u.get("crit", 0.0))])
		i += 1
	return "|".join(parts)


func _first_diff(a: Array, b: Array) -> String:
	for k in range(mini(a.size(), b.size())):
		if str(a[k]) != str(b[k]):
			var sa: PackedStringArray = str(a[k]).split("|")
			var sb: PackedStringArray = str(b[k]).split("|")
			for j in range(mini(sa.size(), sb.size())):
				if sa[j] != sb[j]:
					return "第 %d 步: %s ≠ %s" % [k, sa[j], sb[j]]
			return "第 %d 步" % k
	if a.size() != b.size():
		return "步数 %d ≠ %d" % [a.size(), b.size()]
	return ""


## ★0(a) 「战斗相关那串数字」: 障碍物表(逐件逐键, 去掉只管外观的 img) + 随机流 seed/state + 全场单位(_fp)。
func _sim_sig(s) -> String:
	var parts: Array = ["obs=%d" % (s._obstacles as Array).size()]
	var i := 0
	for ob in s._obstacles:
		var ks: Array = []
		for k in (ob as Dictionary):
			ks.append(str(k))
		ks.sort()
		var kv: Array = []
		for k in ks:
			if k != "img":
				kv.append("%s=%s" % [k, str(ob[k])])
		parts.append("ob%d{%s}" % [i, ",".join(PackedStringArray(kv))])
		i += 1
	parts.append("rng=%d/%d" % [int(s._battle_rng.seed), int(s._battle_rng.state)])
	return "|".join(PackedStringArray(parts)) + "|" + _fp(s)


## ★0(b) 递归扫 .gd, 把出现「ArenaTheme / arena_theme.gd」字样的文件收进 hits。返回扫过的文件数。
func _scan_theme_readers(dir: String, hits: Array) -> int:
	var n := 0
	var da := DirAccess.open(dir)
	if da == null:
		return 0
	for f in da.get_files():
		if f.ends_with(".gd"):
			n += 1
			var p := dir.path_join(f)
			var src := FileAccess.get_file_as_string(p)
			if src.find("ArenaTheme") >= 0 or src.find("arena_theme.gd") >= 0:
				hits.append(p)
	for d in da.get_directories():
		n += _scan_theme_readers(dir.path_join(d), hits)
	return n


# ───────────────────────── 调试场确定性场景(同 verify_determinism_cross 的建法) ─────────────────────────
## frames: 开打后跑几帧(★0 只要开打那一帧的数字 ⇒ 1; ③ 只看主题 ⇒ 1)。sig = 开打后第一帧的「战斗相关那串数字」。
func _run_debug(sc: Dictionary, theme: String, frames: int = 1) -> Dictionary:
	AT.active = theme
	RB.DEBUG_EDIT = true
	OS.set_environment("TURTLE_SEED", str(sc["seed"]))
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var seen_theme: String = AT.active
	var ring: bool = s._world.find_child("ThemeRing", true, false) != null
	s._debug._edit_clear()
	var lo: Dictionary = sc.get("loadouts", {})
	for k in lo:
		GameState.loadouts[str(k)] = int(lo[k])
	s._edit_dummy_killable = true
	s._edit_dummy_hp = 40000.0
	s._edit_full_energy = true
	for p in (sc["pairs"] as Array):
		var pid: String = str(p[0])
		if pid.begins_with("__minion__"):
			var bits: PackedStringArray = pid.split(":")
			s._edit_minion_role = str(bits[1]) if bits.size() > 1 else "front"
			pid = "__minion__"
		var u: Dictionary = s._debug._edit_place_unit(pid, str(p[1]), Vector2(float(p[2]), float(p[3])))
		if (p[4] as Array).size() > 0:
			var el: Array = []
			for e in (p[4] as Array):
				el.append({"id": str(e), "star": 3})
			u["_edit_equips"] = el
		if (p as Array).size() > 5 and bool(p[5]):
			u["active_skills"] = s._resolve_active_skills(pid, false)
			u["skill_idx"] = 0
	s._debug._edit_start_battle()
	var tr: Array = []
	var sig := ""
	for _i in range(frames):
		await get_tree().process_frame
		tr.append(_fp(s))
		if sig == "":
			sig = _sim_sig(s)
	var n_units := (s._units as Array).size()
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	RB.DEBUG_EDIT = false
	return {"tr": tr, "theme": seen_theme, "ring": ring, "sig": sig, "units": n_units}


# ───────────────────────── 正式双路对局 ─────────────────────────
func _setup_gs() -> void:
	var gs = GameState
	gs.reset_dual_lane()
	gs.test_mode = true
	gs.tutorial_active = false
	gs.week_phase = "ranked"               # 积分赛(★2026-10-05 起积分赛也录回放 —— 会往本测试自己那份 user:// 写一份录像, 不影响判据)
	gs.season_leaders = ["basic", "stone", "dice"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "dice", "equips": []},
		],
	}
	gs.persistent_equipped = {}
	gs.season_level = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	gs.dual_ghost = Backend.make_bot(3, rng)
	gs.dual_active = true


## 建一场正式对局。frames=0 ⇒ 只建场不打(量选图用)。
## stop_at_fight: 开到「开打第一帧」就停, 记下那一帧的「战斗相关那串数字」(sig) 与用了几帧(fight_frame)。
func _run_formal(seed_v: int, frames: int, tutorial: bool = false, stop_at_fight: bool = false) -> Dictionary:
	_setup_gs()
	GameState.tutorial_active = tutorial
	RB.DEBUG_EDIT = false
	OS.set_environment("TURTLE_SEED", str(seed_v))
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	var theme: String = AT.active
	var formal: bool = bool(s._world_builder._is_formal_battle())
	var tut: bool = bool(s._world_builder._is_tutorial_battle())
	var tut_gs: bool = bool(GameState.tutorial_active)
	var tr: Array = []
	var st_frames := 0
	var last := ""
	var fought := false
	var sig := ""
	var fight_frame := -1
	var n_units := 0
	for _i in range(frames):
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			st_frames = 0
		st_frames += 1
		if (st == "overview" or st == "lane_settle") and st_frames == 9:
			s._dl_sys._dl_present_click()
		s._process(1.0 / 60.0)
		if str(s._dl_state) == "fight":
			fought = true
		tr.append(_fp(s))
		if stop_at_fight and fought:
			sig = _sim_sig(s)
			fight_frame = _i + 1
			for u in s._units:
				if bool(u.get("alive", false)):
					n_units += 1
			break
		await get_tree().process_frame
	var taken := 0.0
	for u in s._units:
		taken += float(u.get("_st_taken", 0.0))
	## MapProps 是**开路时**才建的(`_build_map_props`, 双路真对局走这条), 所以打完再看
	var props: bool = s._world.find_child("MapProps", true, false) != null
	var ring: bool = s._world.find_child("ThemeRing", true, false) != null
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	GameState.tutorial_active = false
	return {"tr": tr, "theme": theme, "props": props, "ring": ring, "formal": formal, "tut": tut, "tut_gs": tut_gs,
		"fought": fought, "taken": taken, "sig": sig, "fight_frame": fight_frame, "units": n_units}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	GameState.test_mode = true
	GameState.week_anchor_ts = int(SC.PIN_WEEK_ANCHOR)
	var keep_active: String = AT.active
	var keep_forced: String = AT.forced
	AT.forced = ""
	_ok("分母 · 进场前 active 是默认 V0_BASE(下面「调试场照旧」才有对照)", AT.active == AT.V0_BASE, AT.active)

	# ═══ ① 纯函数分布 ═══
	print("=== ① 种子 → 地图: 分布 ===")
	_ok("① 地图池 = 暗林/深礁/紫墟/赤林 四张, 不含 V0_BASE",
		AT.MATCH_POOL == [AT.V1_DUSK, AT.V2_REEF, AT.V3_SHOAL, AT.V4_STORM] and not AT.MATCH_POOL.has(AT.V0_BASE),
		str(AT.MATCH_POOL))
	for kind in ["连续种子 1..4000", "随机 53 位种子 ×4000(= randomize 后 note_battle_seed 的形状)"]:
		var cnt := {}
		var rr := RandomNumberGenerator.new()
		rr.seed = 99
		var N := 4000
		for i in range(N):
			var sd: int = (i + 1) if kind.begins_with("连续") else (rr.randi() | (int(rr.randi() & 0x1FFFFF) << 32))
			var th: String = AT.theme_for_seed(sd)
			cnt[th] = int(cnt.get(th, 0)) + 1
		var lo := N
		var hi := 0
		for th in AT.MATCH_POOL:
			lo = mini(lo, int(cnt.get(th, 0)))
			hi = maxi(hi, int(cnt.get(th, 0)))
		_ok("①%s: 四张都出现、每张占比在 21%%~29%%(分母 N=%d)" % [kind, N],
			cnt.size() == 4 and lo >= int(N * 0.21) and hi <= int(N * 0.29), str(cnt))
		print("  [量] %s: %s" % [kind, str(cnt)])

	# ═══ ② 同种子 ⇒ 同主题(纯函数) ═══
	var same := true
	for sd in [1, 77777, 424242, 4242, 9007199254740991, 123456789012345]:
		same = same and AT.theme_for_seed(sd) == AT.theme_for_seed(sd)
	_ok("② 纯函数: 同一种子算两遍同一张", same)

	# ═══ ★0(b) 静态: 读地图主题的文件只许是白名单那几个(战斗逻辑 / 技能 / 装备不许读) ═══
	print("=== ★0 主题不影响模拟(静态: 谁在读地图主题) ===")
	var readers: Array = []
	var scanned := _scan_theme_readers("res://scripts", readers) + _scan_theme_readers("res://autoload", readers)
	var extra: Array = []
	for p in readers:
		if not THEME_READERS.has(str(p)):
			extra.append(str(p))
	var wl_hit := 0
	for p in THEME_READERS:
		if readers.has(p):
			wl_hit += 1
	_ok("分母 · 扫了 %d 个 .gd, 白名单 %d 个文件里真读主题的 %d 个(扫描真的看得见读主题的文件)" % [scanned, THEME_READERS.size(), wl_hit],
		scanned > 200 and wl_hit >= 4, str(readers))
	_ok("★★0b 读地图主题的文件全在白名单里(新增的先确认只管外观、不在 _sim_step 调用链上, 再登记理由)", extra.is_empty(), str(extra))

	# ═══ ★0(a) 调试场: 五张图开打那一帧的「战斗相关那串数字」逐字相同 ═══
	print("=== ★0 主题不影响模拟(调试场, 比开打那一帧) ===")
	var scs: Array = SC.all()
	for idx in [1, 7]:            # ② 3v3 裸装(骰子吃随机) / ⑧ 受控 PRNG 落点(落点会不会碰到障碍)
		var sc: Dictionary = scs[idx]
		var base: Dictionary = {}
		for th in ALL5:
			var r: Dictionary = await _run_debug(sc, str(th))
			_ok("分母 · %s · %s · 建场时 active 真的是它(themed=%s 有 ThemeRing) · 场上有单位(%d)" % [sc["tag"], th, str(r["ring"]), int(r["units"])],
				str(r["theme"]) == str(th) and bool(r["ring"]) == (str(th) != AT.V0_BASE) and int(r["units"]) >= 2 and str(r["sig"]) != "")
			if th == AT.V0_BASE:
				base = r
			else:
				var d: String = _first_diff([base["sig"]], [r["sig"]])
				_ok("★★0a %s · %s 与 V0_BASE 开打那一帧的数字逐字相同" % [sc["tag"], th], d == "", d)

	# ═══ ★0(a) 正式双路对局: 五张图(强制指定)开到开打第一帧, 「战斗相关那串数字」逐字相同 ═══
	AT.active = AT.V0_BASE        # 上面调试场逐张手动切过; 还原成「玩家进场前」的默认, ③ 才有对照
	print("=== ★0 主题不影响模拟(正式双路对局, 种子 %d, 比开打第一帧) ===" % FORMAL_SEED)
	var fbase: Dictionary = {}
	for th in ALL5:
		AT.forced = str(th)
		var r: Dictionary = await _run_formal(FORMAL_SEED, FORMAL_FRAMES, false, true)
		AT.forced = ""
		_ok("分母 · 正式对局 · %s · 是正式对局(formal=%s) · 用的是它 · 走了 MapProps 那条路 · 第 %d 帧开打 · 场上活着 %d 个" % [th, str(r["formal"]), int(r["fight_frame"]), int(r["units"])],
			bool(r["formal"]) and str(r["theme"]) == str(th) and bool(r["props"]) and bool(r["ring"]) == (str(th) != AT.V0_BASE)
				and bool(r["fought"]) and int(r["units"]) >= 6,
			"theme=%s props=%s ring=%s" % [r["theme"], str(r["props"]), str(r["ring"])])
		if th == AT.V0_BASE:
			fbase = r
			_ok("分母 · 开打那一帧障碍物表非空(比的不是空表): %s" % str(r["sig"]).left(120), str(r["sig"]).find("obs=0|") < 0 and str(r["sig"]).find("|ob0{") >= 0)
		else:
			var d2: String = _first_diff([fbase["sig"]], [r["sig"]])
			_ok("★★0a 正式对局 · %s 与 V0_BASE 开打第一帧的数字逐字相同(障碍物 / 单位 / 随机流)" % th, d2 == "", d2)

	# ④a 直接量随机流状态: 正式对局建好后, 把种子换成 X、记下 state, 调产品的选图入口, state 必须一个位不差。
	#   ★为什么要这一条: ④ 的端到端指纹对「从流里吃掉一个数」不够敏感 —— 2026-10-04 反向验证实测,
	#   把入口改成 `choose_for_battle(_battle_rng.randi(), …)` 后那 1500 步指纹**照样相同**
	#   (这一局的随机消费点稀疏且粗粒度, 错一位抽到的结果碰巧一样)。只有 ③ 因为选错图红了。
	#   ⇒ 状态级断言才是能卡住「吃流」这个形状的尺子。
	_setup_gs()
	OS.set_environment("TURTLE_SEED", str(FORMAL_SEED))
	var s4 = RB.new()
	add_child(s4)
	s4.set_process(false)
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	var probe_ok := true
	var probe_det := ""
	for x in [987654321, 5, 4503599627370495]:
		s4._battle_rng.seed = x
		var st0: int = s4._battle_rng.state
		var th4: String = s4._world_builder.pick_arena_theme()
		var st1: int = s4._battle_rng.state
		probe_ok = probe_ok and st0 == st1 and th4 == AT.theme_for_seed(x)
		probe_det += "%d→%s(state %s) " % [x, th4, "不变" if st0 == st1 else "变了"]
	_ok("★★④a 产品选图入口 pick_arena_theme() 前后 _battle_rng.state 逐位不变, 且选的是种子算出的那张", probe_ok, probe_det)
	var stx: int = s4._battle_rng.state
	s4._battle_rng.randi()
	_ok("④a 分母: 从流里取一个数 state 就会变(这把尺子看得见「吃流」)", s4._battle_rng.state != stx)
	s4.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ═══ ②③ 真建场: 多个种子, 每个建两次 ═══
	print("=== ②③ 真建场选图 ===")
	## ★11-04 每个种子只建一次: 「真建场 == 纯函数」+「纯函数算两遍同一张」⇒ 同种子建两次必然同一张(原第二次建场是重复量)。
	var seen := {}
	var all_ok := true
	var detail := ""
	for sd in [11, 222, 3333, 44444, 555555, 6666666, 77777777, 1234567]:
		var a: Dictionary = await _run_formal(sd, 0)
		seen[str(a["theme"])] = true
		if str(a["theme"]) != AT.theme_for_seed(sd) or not AT.MATCH_POOL.has(str(a["theme"])):
			all_ok = false
		detail += "%d→%s " % [sd, a["theme"]]
	_ok("★②③ 每一场正式对局真建场 == 种子算出的那张、且在四张池里(没有一场是 V0_BASE)", all_ok, detail)
	_ok("分母 · 这 8 个种子覆盖到 ≥3 张不同的图(否则 ② 量不出随机)", seen.size() >= 3, str(seen.keys()))

	# ═══ ③ 开发工具不被弄坏 ═══
	# ═══ ⑥ 教学战斗固定暗林(用户 2026-10-04 拍板「可以」) ═══
	print("=== ⑥ 教学固定暗林 ===")
	var tut_ok := true
	var tut_in := true
	var real_seen := {}
	var real_ok := true
	var tdet := ""
	for sd in [11, 222, 3333, 44444, 555555, 77777777]:
		var t: Dictionary = await _run_formal(sd, 0, true)
		var r: Dictionary = await _run_formal(sd, 0, false)
		tut_ok = tut_ok and str(t["theme"]) == AT.V1_DUSK
		tut_in = tut_in and bool(t["tut"]) and bool(t["tut_gs"]) and not bool(t["formal"])
		real_ok = real_ok and str(r["theme"]) == AT.theme_for_seed(sd) and bool(r["formal"]) and not bool(r["tut"])
		real_seen[str(r["theme"])] = true
		tdet += "%d→教学 %s / 正式 %s  " % [sd, t["theme"], r["theme"]]
	_ok("分母 · 教学那 6 场建场时真的在教学状态(tutorial_active=true · 产品判成教学 · 不算正式对局)", tut_in, tdet)
	_ok("★★⑥ 教学战斗 6 个种子一律是暗林 V1_DUSK", tut_ok, tdet)
	_ok("★⑥ 同样 6 个种子的正式对局照旧按种子随机(等于种子算出的那张)", real_ok, tdet)
	_ok("⑥ 分母: 这 6 个种子的正式对局覆盖到 ≥3 张图(否则「教学恒为暗林」量不出区别)", real_seen.size() >= 3, str(real_seen.keys()))
	AT.forced = AT.V4_STORM
	var tf: Dictionary = await _run_formal(11, 0, true)
	AT.forced = ""
	_ok("⑥ 强制指定在教学里也赢(ARENA_THEME / forced 优先级最高)", str(tf["theme"]) == AT.V4_STORM and bool(tf["tut"]), str(tf["theme"]))

	print("=== ③ 开发工具 ===")
	var dbg: Dictionary = await _run_debug(scs[0], AT.active)   # 不手动改: 用上一场正式对局留下的值进调试场
	_ok("★③ 正式对局之后进调试场 ⇒ 回到进场前那张(V0_BASE), 不带上一场的选图", str(dbg["theme"]) == AT.V0_BASE, str(dbg["theme"]))
	AT.active = AT.V2_REEF
	var dbg2: Dictionary = await _run_debug(scs[0], AT.V2_REEF)
	_ok("③ 调试场里手动指定的主题照旧生效(门禁切主题的老用法)", str(dbg2["theme"]) == AT.V2_REEF, str(dbg2["theme"]))
	AT.forced = AT.V3_SHOAL
	var fz: Dictionary = await _run_formal(FORMAL_SEED, 0)
	AT.forced = ""
	_ok("③ 强制指定(ARENA_THEME 环境变量写的就是它)在正式对局里赢过随机", str(fz["theme"]) == AT.V3_SHOAL, str(fz["theme"]))

	AT.active = keep_active
	AT.forced = keep_forced
	GameState.reset_dual_lane()
	print("")
	if _fail == 0:
		print("ALL PASS — 正式对局按种子随机选图, 主题不影响模拟 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
