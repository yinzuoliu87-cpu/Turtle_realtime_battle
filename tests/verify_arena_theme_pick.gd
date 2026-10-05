extends Node
## verify_arena_theme_pick.gd — 正式对局「每场随机一张图」(用户 2026-10-04 拍板)
##
## 用户原话(从选项里选):「每场随机一张」—— 每场对局从 暗林 / 深礁 / 紫墟 / 赤林 四张里随机一张,
##   原来的 V0_BASE 默认图从正式对局退役。
## 方案书: docs/plans/20261003-四版完整地图.md §6。
##
## 这把尺子量五件事(编号对应派活单的门禁 ①~⑤):
##   ★0 主题只改外观: 同种子同阵容, 五张图(含 V0_BASE)下**逐 sim 步**全场指纹逐字相同
##      —— 调试场两个确定性场景 + 一场真正的正式双路对局(走 `_build_map_props` 那条路)。
##   ①  多种子下四张都出现、分布大致均匀(打分母)
##   ②  同种子 ⇒ 同主题(纯函数 + 真建场两次都对上)
##   ③  正式对局不出 V0_BASE; 调试场照旧是进场前那张(开发工具不被弄坏)
##   ④  选图不消耗战斗随机流: 让它自己选 vs 强制指定成同一张, 逐步指纹必须相同
##      (分母: 种子改一下指纹就变 —— 证明这一局真的在读随机流, 否则 ④ 是空检查)
##   ⑤  回放一致在 `verify_replay_roundtrip` 里量(录与播的 ArenaTheme.active 相同)
##
## 反向验证(2026-10-04 做过, 见方案书 §6): 改成 randi 选图 ⇒ ②③红; 改成从 `_battle_rng` 取数选图 ⇒ ④a③红
##   (④ 的端到端指纹对此不敏感, 见 ④a 的注释)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_arena_theme_pick.tscn --quit-after 30000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const AT := preload("res://scripts/gamedata/arena_theme.gd")
const SC := preload("res://tests/_det_scenarios.gd")
const Backend := preload("res://scripts/net/backend.gd")

const FORMAL_SEED := 4242             # 正式双路那一局的种子
const FORMAL_FRAMES := 1500           # 摆位 → 开打 → 打 ~20 秒
const ALL5: Array = [AT.V0_BASE, AT.V1_DUSK, AT.V2_REEF, AT.V3_SHOAL, AT.V4_STORM]

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


# ───────────────────────── 调试场确定性场景(同 verify_determinism_cross 的建法) ─────────────────────────
func _run_debug(sc: Dictionary, theme: String) -> Dictionary:
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
	for _i in range(int(sc["frames"])):
		await get_tree().process_frame
		tr.append(_fp(s))
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	RB.DEBUG_EDIT = false
	return {"tr": tr, "theme": seen_theme, "ring": ring}


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
func _run_formal(seed_v: int, frames: int, tutorial: bool = false) -> Dictionary:
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
	for _i in range(frames):
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			st_frames = 0
		st_frames += 1
		if (st == "overview" or st == "lane_settle") and st_frames == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and st_frames == 25 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
		s._process(1.0 / 60.0)
		if str(s._dl_state) == "fight":
			fought = true
		tr.append(_fp(s))
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
		"fought": fought, "taken": taken}


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

	# ═══ ★0 主题只改外观 —— 调试场两个确定性场景, 五张图逐步指纹相同 ═══
	print("=== ★0 主题不影响模拟(调试场) ===")
	var scs: Array = SC.all()
	for idx in [1, 7]:            # ② 3v3 裸装(骰子吃随机) / ⑧ 受控 PRNG 落点(落点会不会碰到障碍)
		var sc: Dictionary = scs[idx]
		var base: Dictionary = {}
		for th in ALL5:
			var r: Dictionary = await _run_debug(sc, str(th))
			_ok("分母 · %s · %s · 建场时 active 真的是它(themed=%s 有 ThemeRing)" % [sc["tag"], th, str(r["ring"])],
				str(r["theme"]) == str(th) and bool(r["ring"]) == (str(th) != AT.V0_BASE))
			if th == AT.V0_BASE:
				base = r
				var uq := {}
				for f in r["tr"]:
					uq[str(f)] = true
				_ok("分母 · %s · 这一局真的在推进(%d 步, 不同指纹 %d 个)" % [sc["tag"], (r["tr"] as Array).size(), uq.size()],
					uq.size() > 50)
			else:
				var d: String = _first_diff(base["tr"], r["tr"])
				_ok("★★0 %s · %s 与 V0_BASE 逐步指纹逐字相同(%d 步)" % [sc["tag"], th, (r["tr"] as Array).size()], d == "", d)

	# ═══ ★0 正式双路对局: 五张图(强制指定)逐步指纹相同 ═══
	AT.active = AT.V0_BASE        # 上面调试场逐张手动切过; 还原成「玩家进场前」的默认, ③ 才有对照
	print("=== ★0 主题不影响模拟(正式双路对局, 种子 %d) ===" % FORMAL_SEED)
	var fbase: Dictionary = {}
	var by_theme := {}
	for th in ALL5:
		AT.forced = str(th)
		var r: Dictionary = await _run_formal(FORMAL_SEED, FORMAL_FRAMES)
		AT.forced = ""
		by_theme[str(th)] = r
		_ok("分母 · 正式对局 · %s · 是正式对局(formal=%s) · 用的是它 · 走了 MapProps 那条路" % [th, str(r["formal"])],
			bool(r["formal"]) and str(r["theme"]) == str(th) and bool(r["props"]) and bool(r["ring"]) == (str(th) != AT.V0_BASE),
			"theme=%s props=%s ring=%s" % [r["theme"], str(r["props"]), str(r["ring"])])
		if th == AT.V0_BASE:
			fbase = r
			_ok("分母 · 正式对局真的开打并打出伤害(fought=%s 承伤 %.0f)" % [str(r["fought"]), float(r["taken"])],
				bool(r["fought"]) and float(r["taken"]) > 0.0)
		else:
			var d2: String = _first_diff(fbase["tr"], r["tr"])
			_ok("★★0 正式对局 · %s 与 V0_BASE 逐步指纹逐字相同(%d 步)" % [th, (r["tr"] as Array).size()], d2 == "", d2)

	# ═══ ④ 选图不消耗战斗随机流 ═══
	print("=== ④ 自己选图 vs 强制同一张 ===")
	var auto: Dictionary = await _run_formal(FORMAL_SEED, FORMAL_FRAMES)
	var want: String = AT.theme_for_seed(FORMAL_SEED)
	_ok("③ 正式对局(不强制)选出的是种子算出的那张(%s), 不是 V0_BASE" % want,
		str(auto["theme"]) == want and str(auto["theme"]) != AT.V0_BASE, str(auto["theme"]))
	var d4: String = _first_diff((by_theme[want] as Dictionary)["tr"], auto["tr"])
	_ok("★★④ 让它自己选 与 强制指定成同一张 ⇒ 逐步指纹逐字相同(选图没从 _battle_rng 取数)", d4 == "", d4)
	var other: Dictionary = await _run_formal(FORMAL_SEED + 1, FORMAL_FRAMES)
	var d4b: String = _first_diff(auto["tr"], other["tr"])
	_ok("④ 分母: 种子改一下指纹就变(这局真的在读随机流, ④ 不是空检查)", d4b != "", d4b)

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
	var seen := {}
	var all_ok := true
	var twice_ok := true
	var detail := ""
	for sd in [11, 222, 3333, 44444, 555555, 6666666, 77777777, 1234567]:
		var a: Dictionary = await _run_formal(sd, 0)
		var b: Dictionary = await _run_formal(sd, 0)
		seen[str(a["theme"])] = true
		if str(a["theme"]) != AT.theme_for_seed(sd) or not AT.MATCH_POOL.has(str(a["theme"])):
			all_ok = false
		if str(a["theme"]) != str(b["theme"]):
			twice_ok = false
		detail += "%d→%s/%s " % [sd, a["theme"], b["theme"]]
	_ok("★② 同一种子真建场两次 ⇒ 两次同一张", twice_ok, detail)
	_ok("★③ 每一场正式对局都在四张池里、且等于种子算出的那张(没有一场是 V0_BASE)", all_ok, detail)
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
