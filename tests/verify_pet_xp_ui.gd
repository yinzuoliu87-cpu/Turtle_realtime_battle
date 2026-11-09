extends Node
## verify_pet_xp_ui.gd —— 龟经验条三处界面(2026-11-09 · 方案书 docs/plans/20261107b-龟等级与经验.md §4.5)
##
## 需求原文(方案书 §4.5): 选龟页、图鉴: 拥有的龟挂等级牌和经验条; 限免龟挂「限免」角标、固定 1 级。
##   结算页: 每只上场龟一条经验条, 「+8 经验」从左往右涨; 升级时等级牌放大回弹 + 升级音效。
## 判据:
##   ① PetXp 纯函数: 曲线换算(69 = 1 级 69/70、70 = 2 级 0/90、1350 = 满级)、赢 8 输 6、没拥有 0、离满级不够一整份只给到封顶
##   ② 结算屏(积分赛·胜): 左栏「龟经验」三只 —— 石头龟 65 经验 +8 = 73 ⇒ 演完 Lv.2、条填到 3/90、「+8」;
##      ★等级牌真的放大回弹过(逐帧采样, 最大缩放 ≥ 1.3, 演完回到 1); 满级竹叶龟「满级」不涨; 没拥有的寒冰龟「限免」;
##      ★本机缓存改成新值(PetLevelsNet.levels 73 / GameState.pet_lv 2); ★同一局结算屏重建 ⇒ 不加第二次(还是 65 → 73)
##   ③ 积分赛·负: +6
##   ④ 不放: 周日封存(+8 / +6 一露就等于说了输赢) / 练习赛 / 表演赛 / 没拉到拥有表
##   ⑤ 选龟卡片: 拥有的挂 XpBar, 填充像素 = 进度; 没拥有的不挂; 详情里限免的龟有「限免龟不获得经验」, 拥有的没有
##   ⑥ 图鉴: 拥有的 Lv 签里挂 CodexXpBar(进度对); 没拥有的不挂
## ★分母: 每一段打印量了几只 / 几张卡。
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_pet_xp_ui.tscn

const SCENE := "res://scenes/RealtimeBattle3D.tscn"
const TS := "res://scenes/TeamSelect.tscn"
const CODEX := preload("res://scenes/Codex.tscn")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const FIX := {"linked": true, "owned": ["stone", "bamboo"],
	"levels": {"stone": {"lv": 1, "xp": 65}, "bamboo": {"lv": 10, "xp": 1350}}}

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _reset_levels() -> void:
	PetLevelsNet.override = FIX.duplicate(true)
	PetLevelsNet.adopt(FIX.duplicate(true))


func _ready() -> void:
	Engine.max_fps = 60
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	get_tree().root.size = Vector2i(1560, 720)
	var keys := ["account_id", "season_leaders", "pet_lv", "lane_results", "dual_active", "finals_pending_reveal", "week_phase",
		"current_lane", "tutorial_active"]
	var bak := {}
	for k in keys:
		var v = gs.get(k)
		bak[k] = v.duplicate() if (v is Dictionary or v is Array) else v
	gs.account_id = "verify-pet-xp-ui"
	gs.tutorial_active = false
	gs.season_leaders = ["stone", "bamboo", "ice"]
	_reset_levels()

	print("=== ① PetXp 纯函数 ===")
	var cases := [[0, 1, 0, 70], [69, 1, 69, 70], [70, 2, 0, 90], [159, 2, 89, 90], [160, 3, 0, 110], [1349, 9, 229, 230]]
	for c in cases:
		var p := PetXp.progress(int(c[0]))
		_ok("经验 %d ⇒ %d 级 %d / %d" % c, int(p["lv"]) == int(c[1]) and int(p["cur"]) == int(c[2]) and int(p["need"]) == int(c[3]), str(p))
	_ok("1350 / 99999 ⇒ 满级", bool(PetXp.progress(1350)["maxed"]) and bool(PetXp.progress(99999)["maxed"]) and int(PetXp.progress(99999)["lv"]) == 10)
	_ok("负数 ⇒ 1 级 0", int(PetXp.progress(-5)["lv"]) == 1 and int(PetXp.progress(-5)["cur"]) == 0)
	_ok("赢 +8 / 输 +6 / 没拥有 0", PetXp.gain(65, true, true) == 8 and PetXp.gain(65, false, true) == 6 and PetXp.gain(65, true, false) == 0)
	_ok("离满级 2 点 ⇒ 只给 2; 满级 ⇒ 0", PetXp.gain(1348, true, true) == 2 and PetXp.gain(1350, true, true) == 0)

	print("=== ②③④ 结算屏左栏「龟经验」 ===")
	var sc = load(SCENE).instantiate()
	get_tree().root.add_child(sc)
	await _frames(30)
	sc.set_process(false)
	sc.set_physics_process(false)
	## ② 积分赛·胜: 采样等级牌缩放(逐帧), 演完量最终状态
	var scr = await _open(sc, "ranked", true)
	var row: Node = scr.find_child("PetXpRow", true, false) if scr != null else null
	_ok("★分母: 左栏建出来了「龟经验」", row != null)
	var stone: Node = row.find_child("PetXp_stone", true, false) if row != null else null
	var max_s := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2600:
		var lvl := stone.find_child("XpLv", true, false) as Label if stone != null else null
		if lvl != null:
			max_s = maxf(max_s, lvl.scale.x)
		await get_tree().process_frame
	var n_items := 0
	if row != null:
		for c in row.get_children():
			if str(c.name).begins_with("PetXp_"):
				n_items += 1
	_ok("★分母: 三只统领都在", n_items == 3, "%d 只" % n_items)
	var lv_s := stone.find_child("XpLv", true, false) as Label if stone != null else null
	var bar_s := stone.find_child("XpBar", true, false) as PetXpBar if stone != null else null
	var note_s := stone.find_child("XpNote", true, false) as Label if stone != null else null
	_ok("★石头龟 65 +8 = 73 ⇒ 演完 Lv.2", lv_s != null and lv_s.text == "Lv.2", lv_s.text if lv_s != null else "null")
	var want_px := floorf(maxf(0.0, bar_s.size.x - 2.0) * 3.0 / 90.0) if bar_s != null else -1.0
	_ok("★石头龟 经验条填到 3/90", bar_s != null and absf(bar_s.frac - 3.0 / 90.0) < 0.002 and bar_s.fill_px() == want_px,
		"frac %.4f px %.0f" % [bar_s.frac if bar_s != null else -1.0, bar_s.fill_px() if bar_s != null else -1.0])
	_ok("★石头龟 「+8」", note_s != null and note_s.text == "+8", note_s.text if note_s != null else "null")
	_ok("★升级那一下等级牌真的放大回弹过(采样最大 ≥ 1.3, 演完回到 1)", max_s >= 1.3 and lv_s != null and absf(lv_s.scale.x - 1.0) < 0.01,
		"最大 %.2f 现在 %.2f" % [max_s, lv_s.scale.x if lv_s != null else -1.0])
	var bam: Node = row.find_child("PetXp_bamboo", true, false) if row != null else null
	var ice: Node = row.find_child("PetXp_ice", true, false) if row != null else null
	var bn := bam.find_child("XpNote", true, false) as Label if bam != null else null
	var inn := ice.find_child("XpNote", true, false) as Label if ice != null else null
	_ok("满级竹叶龟「满级」不涨", bn != null and bn.text == "满级" and (bam.get_meta("xp") as Array) == [1350, 1350])
	_ok("没拥有的寒冰龟「限免」不涨", inn != null and inn.text == "限免" and (ice.get_meta("xp") as Array) == [0, 0])
	_ok("★本机缓存改成新值: PetLevelsNet 73 / GameState.pet_lv 2",
		PetXp.cached_xp("stone") == 73 and int((gs.pet_lv as Dictionary).get("stone", 0)) == 2,
		"%d / %s" % [PetXp.cached_xp("stone"), str((gs.pet_lv as Dictionary).get("stone"))])
	## 同一局结算屏重建: 还是从 65 起算(记在战斗场上), 不会 73 → 81
	var scr2 = await _open(sc, "ranked", true)
	var st2: Node = scr2.find_child("PetXp_stone", true, false) if scr2 != null else null
	_ok("★同一局结算屏重建 ⇒ 不加第二次(65 → 73)", st2 != null and (st2.get_meta("xp") as Array) == [65, 73] and PetXp.cached_xp("stone") == 73,
		str(st2.get_meta("xp") if st2 != null else null))
	## ③ 新一局 · 负: +6
	sc.remove_meta("_pet_xp0")
	_reset_levels()
	var scr3 = await _open(sc, "ranked", false)
	var st3: Node = scr3.find_child("PetXp_stone", true, false) if scr3 != null else null
	_ok("★积分赛·负 ⇒ +6(65 → 71)", st3 != null and (st3.get_meta("xp") as Array) == [65, 71], str(st3.get_meta("xp") if st3 != null else null))
	## ④ 不放
	for kc in [["sealed", "周日封存"], ["practice", "练习赛"], ["exhibition", "表演赛"], ["nofetch", "没拉到拥有表"]]:
		sc.remove_meta("_pet_xp0")
		_reset_levels()
		if kc[0] == "nofetch":
			PetLevelsNet.fetched = false
		var s4 = await _open(sc, str(kc[0]), true)
		_ok("%s ⇒ 不放「龟经验」" % kc[1], s4 != null and s4.find_child("PetXpRow", true, false) == null)
	sc.queue_free()
	await _frames(3)

	print("=== ⑤ 选龟卡片 ===")
	_reset_levels()
	gs.season_leaders = []
	var ts = (load(TS) as PackedScene).instantiate()
	add_child(ts)
	await _frames(20)
	var n_cards := 0
	var bad: Array = []
	for c in (ts._grid_flow as Node).get_children():
		if (c as Node).is_queued_for_deletion():
			continue
		var pid := str((c as Node).get_meta("pet_id", ""))
		if pid == "":
			continue
		n_cards += 1
		var xb := (c as Node).get_node_or_null("XpBar") as PetXpBar
		var want := PetXp.shows_bar(pid)
		if want != (xb != null):
			bad.append("%s 该挂 %s 实际 %s" % [pid, want, xb != null])
		elif xb != null:
			var f := float(PetXp.progress(PetXp.cached_xp(pid))["frac"])
			if absf(xb.frac - f) > 0.001 or xb.fill_px() != floorf(maxf(0.0, xb.size.x - 2.0) * f) or xb.size.x <= 8.0:
				bad.append("%s 进度 %.3f/%.3f 宽 %.0f" % [pid, xb.frac, f, xb.size.x])
	var stone_card := false
	for c in (ts._grid_flow as Node).get_children():
		if str((c as Node).get_meta("pet_id", "")) == "stone" and (c as Node).get_node_or_null("XpBar") != null:
			stone_card = true
	_ok("★分母: 量了 %d 张卡, 拥有的石头龟那张真的挂了经验条" % n_cards, n_cards >= 3 and stone_card)
	_ok("★拥有的挂经验条且进度对, 没拥有的不挂", bad.is_empty(), str(bad.slice(0, 4)))
	## 详情里限免龟的说明(方案书 §4.5「限免龟不获得经验」): 点一只限免的 ⇒ 有「限免龟不获得经验」; 点拥有的 ⇒ 没有
	var free_pid := ""
	for p in WeeklyFree.ALL:
		if PetLevelsNet.is_free_pick(str(p)):
			free_pid = str(p)
			break
	ts._set_detail_pet(free_pid)
	await _frames(3)
	var fnote := ts.find_child("FreeNote", true, false) as Label
	_ok("★详情: 限免的 %s 写着「限免龟不获得经验」" % free_pid, free_pid != "" and fnote != null and fnote.text.contains("不获得经验"))
	ts._set_detail_pet("stone")
	await _frames(3)
	_ok("详情: 拥有的石头龟没有限免说明", ts.find_child("FreeNote", true, false) == null)
	ts.queue_free()
	await _frames(3)

	print("=== ⑥ 图鉴 ===")
	var cx = CODEX.instantiate()
	add_child(cx)
	await _frames(10)
	cx._switch_tab("pets")
	await _frames(4)
	for pc in [["stone", true], ["ice", false]]:
		var pet: Dictionary = {}
		for p in DataRegistry.launch_pets:
			if str((p as Dictionary).get("id", "")) == str(pc[0]):
				pet = p
		cx._codex_detail._show_pet(pet)
		await _frames(3)
		var cb := cx.find_child("CodexXpBar", true, false) as PetXpBar
		if bool(pc[1]):
			var f := float(PetXp.progress(PetXp.cached_xp("stone"))["frac"])
			_ok("★图鉴 石头龟(拥有)Lv 签里挂经验条、进度对", cb != null and absf(cb.frac - f) < 0.001 and cb.size.x > 20.0,
				"frac %.3f/%.3f" % [cb.frac if cb != null else -1.0, f])
		else:
			_ok("图鉴 寒冰龟(没拥有)不挂经验条", cb == null)
	cx.queue_free()
	await _frames(3)

	PetLevelsNet.override = {}
	PetLevelsNet.fetched = false
	PetLevelsNet.owned = []
	PetLevelsNet.levels = {}
	for k in keys:
		gs.set(k, bak[k])
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 龟经验条三处界面" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 建结算屏(做法同 verify_settle_fit._open): kind = ranked / sealed / practice / exhibition / nofetch
func _open(sc, kind: String, won: bool) -> Node:
	var gs = get_node_or_null("/root/GameState")
	if sc._hud._settle != null and is_instance_valid(sc._hud._settle):
		sc._hud._settle.queue_free()
	await get_tree().process_frame
	sc._st_lane_hist = _make_hist()
	sc._units.clear()
	gs.dual_active = true
	gs.current_lane = "final"
	gs.lane_results = {"top": "left", "bottom": "right", "final": "left" if won else "right"}
	gs.finals_pending_reveal = {"round": 1, "match": 0, "bucket": 0} if kind == "sealed" else {}
	gs.week_phase = P2C.PHASE_FINALS if kind == "sealed" else P2C.PHASE_RANKED
	sc._had_season = kind != "practice"
	sc._last_was_exhibition = kind == "exhibition"
	sc._last_reward = 15
	sc._last_settle_kind = P2C.SETTLE_FINALS if kind == "sealed" else (P2C.SETTLE_RANKED if kind != "practice" else "")
	sc._settled = false
	sc._hud._show_banner(won)
	var scr = sc._hud._settle
	if scr == null:
		return null
	await _frames(6)
	return scr


func _row(id: String, nm: String, multi: bool, d: int, alive: bool) -> Dictionary:
	return {"name": nm, "id": id, "is_summon": false, "_st_multi": multi, "rarity": "C",
		"alive": alive, "hp": 0.0, "maxHp": 100.0,
		"_st_dealt": d, "_st_taken": 12345, "_st_heal": 2345, "_st_crit": 0, "_st_kills": 3,
		"_st_shield": 1234, "_st_dealt_by_type": {"phy": d - d / 3, "mag": d / 3, "tru": 0}}


func _make_hist() -> Array:
	var out: Array = []
	for lane in ["top", "bottom", "final"]:
		out.append({"lane": lane,
			"left": [_row("stone", "石头龟", false, 9000, true), _row("minion", "小将", true, 3000, true)],
			"right": [_row("hunter", "猎人龟", false, 8000, true), _row("minion", "小将", true, 1200, true)]})
	return out
