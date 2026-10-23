extends Node
## verify_spar_isolation.gd — 好友切磋不进常规赛(方案书 docs/plans/20261023-好友切磋.md §6 第一条)
##
## 用户 2026-10-23「切记不会去叠比如香火石，宝箱龟被动的层数，因为是不在常规赛里的，
##   切磋是当前的背包阵容vs好友的最新背包阵容」
##
##   A 真打一场切磋(我方: 宝箱龟 + 赌神龟 + 香火石 + 小木斧; 对方: 机器人快照), 走真入口 `Spar.begin` → 战斗场 → 离场
##     ⇒ 切磋前后 `_save_dict()` **逐键相同**; 存档文件逐字节相同; user:// 下没有多出 / 改动任何文件
##       (录像 / 待结算单 / 快照上传队列); 战绩 / 上传队列(备份不还原的那几个)也没动。
##   B 分母: 局内**确实**写过跨场累积(香火 / 赌神 / 斧头 至少一样变了) + 一个「以后新加的写入点」(局内手动改深海币)
##     ⇒ 证明 A 不是因为这一局什么都没写才绿。
##   C 第一层: 打到结算(`_settled`)、不录像(`mode == ""`)、没有待结算单、不计赛季(`_had_season == false`)、
##     结算屏写「切磋 · 不计入赛季进度」、按钮是「再来一局 / 返回好友」。
##   D 再来一局: 离场还原后按同一份快照重新挂上; 不再来 ⇒ 还原。
##   E 切磋期间云端拉回的存档: 不当场落(会被还原盖掉), 离场还原之后才落。
##   F 我这边开不了: 教程中 / 统领没选满。
##
## 反向验证(2026-10-23 做过, 见方案书 §8): 去掉 `_settle_season` 那一行(第一层) ⇒ C / A(战绩、上传队列、文件)红;
##   去掉 `Spar.end()` 的还原(第二层) ⇒ A(`_save_dict` 逐键)红。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Backend := preload("res://scripts/net/backend.gd")
const AM := preload("res://scripts/systems/replay/abandoned_match.gd")
const MAX_FRAMES := 24000
## 局内会写、跨场累积的(分母 B: 至少一样真的变了)。
const CARRY := ["incense_charge", "incense_marks", "gambler_wheel_stacks", "axe_exp_total", "axe_exp_bar"]

var _fail := 0
var _n := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _setup_gs(gs) -> void:
	gs.reset_dual_lane()
	gs.test_mode = false                     # ★要量真存档: 第二层自己会把它打开(门禁每个测试一份独立 user://)
	gs.tutorial_active = false
	gs.tutorial = false
	gs.week_phase = "ranked"                 # 积分赛日: 一局普通对局会扣命 / 加场次 / 录像 / 上传, 账最多
	gs.hearts = 4
	gs.season_total_battles = 5
	gs.season_leaders = ["chest", "gambler", "basic"]
	gs.left_team.assign(gs.season_leaders)
	gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "chest", "equips": []}, {"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "gambler", "equips": []},
			{"kind": "leader", "slot": 2, "id": "basic", "equips": []}, {"kind": "minion", "role": "back", "equips": []}],
	}
	gs.persistent_equipped = {"basic": [{"id": "p2eq_093", "star": 3}], "gambler": [{"id": "p2eq_096", "star": 1}]}
	gs.season_level = 6
	gs.incense_marks = 3
	gs.incense_charge = 1500
	gs.chest_treasure_value = 40.0
	gs.gambler_wheel_stacks = {"spade": 1}
	gs.trainer_skill = "hook"
	gs.dual_active = false
	gs.dual_ghost = {}
	gs.get_install_uid()                     # 设备身份 / 默认昵称第一次用到时才生成(与切磋无关) ⇒ 起点前先生成, 免得被当成切磋写的
	gs.default_nickname()


func _ghost() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var g: Dictionary = Backend.make_bot(3, rng)
	g["profile"] = {"name": "好友甲", "avatar": "stone", "id": "FRND01"}
	return g


## user:// 下全部文件(相对路径 → 字节摘要)。
func _files() -> Dictionary:
	var out := {}
	_walk("user://", out)
	return out


func _walk(dir: String, out: Dictionary) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var p := dir.path_join(f)
		if p.begins_with("user://logs/"):
			continue                         # 引擎自己的运行日志(每帧都在写, 与切磋无关)
		out[p] = FileAccess.get_file_as_bytes(p).hex_encode().sha256_text()
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue
		_walk(dir.path_join(sub), out)


func _diff_keys(a: Dictionary, b: Dictionary) -> Array:
	var out: Array = []
	for k in a:
		if not b.has(k) or var_to_str(a[k]) != var_to_str(b[k]):
			out.append(k)
	for k in b:
		if not a.has(k):
			out.append(k)
	return out


func _find_label(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _find_label(c, text):
			return true
	return false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	AM.clear()

	# ── F 我这边开不了 ──
	_setup_gs(gs)
	gs.tutorial_active = true
	_ok("★F 教程中不能切磋(不挂上)", Spar.my_side_check() != "" and not Spar.begin(_ghost(), {}) and not Spar.is_active(),
		Spar.my_side_check())
	gs.tutorial_active = false
	gs.season_leaders = []
	_ok("★F 统领没选满不能切磋", Spar.my_side_check() != "" and not Spar.is_active(), Spar.my_side_check())

	# ── D 再来一局 / 还原(不进战斗场, 只量模块本身) ──
	_setup_gs(gs)
	var d0: Dictionary = gs._save_dict().duplicate(true)
	_ok("分母 · D 挂上了", Spar.begin(_ghost(), {"name": "好友甲", "tag": "FRND01"}) and Spar.is_active() and bool(gs.test_mode))
	gs.incense_charge = 3999
	Spar._again = true
	Spar.end()
	_ok("★D 再来一局: 离场先还原, 再按同一份快照挂上",
		Spar.is_active() and int(gs.incense_charge) == 1500 and bool(gs.test_mode)
			and str((gs.dual_ghost.get("profile", {}) as Dictionary).get("id", "")) == "FRND01",
		"active=%s 香火=%d test_mode=%s" % [Spar.is_active(), int(gs.incense_charge), gs.test_mode])
	Spar.end()
	_ok("★D 不再来: 还原成切磋之前那一份(test_mode 也还原)",
		not Spar.is_active() and not bool(gs.test_mode) and _diff_keys(d0, gs._save_dict()).is_empty(),
		str(_diff_keys(d0, gs._save_dict())))

	# ── A/B/C 真打一场 ──
	_setup_gs(gs)
	gs.save()                                # 起点落盘(下面比文件)
	var pre: Dictionary = gs._save_dict().duplicate(true)   # ★深拷贝: 局内香火石把 chg 直接写进装备字典(同一个引用)
	var pre_files: Dictionary = _files()
	var pre_hist: int = (gs.match_history as Array).size()
	var pre_up := var_to_str([gs.ghost_upload_pending, gs.replay_upload_pending, gs.replay_pending_id])
	_ok("分母 · 起点存档在盘上", pre_files.has("user://savegame.json"), str(pre_files.keys()))
	_ok("分母 · A 挂上切磋", Spar.begin(_ghost(), {"name": "好友甲", "tag": "FRND01"}))
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	s._deterministic = true
	var mode0 := str(s._replay.mode)
	var pend0: bool = not AM.read().is_empty()
	var st_frames := 0
	var last := ""
	var fights := 0
	var done_frames := 0
	var poked := false
	for _i in range(MAX_FRAMES):
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			st_frames = 0
		st_frames += 1
		if st == "overview" and st_frames == 9:
			s._dl_sys._dl_present_click()
		s._process(s.SIM_DT)
		if st != "fight" and str(s._dl_state) == "fight":
			fights += 1
			if not poked:
				## B 第二条分母: 一个「以后新加的、没有闸」的写入点(第二层要兜住它)
				gs.meta_deepsea_coins = int(gs.meta_deepsea_coins) + 7
				poked = true
		await get_tree().process_frame
		if str(s._dl_state) == "done":
			done_frames += 1
			if done_frames > 5:
				break
	## 结算屏在蛋碎后晚 EGG_BREAK_BANNER_DELAY 秒(真实钟)才出 ⇒ 按墙钟等它(CLAUDE.md §3.5)。
	var w0 := Time.get_ticks_msec()
	while not bool(s._settled) and Time.get_ticks_msec() - w0 < 8000:
		await get_tree().process_frame
	var mid: Dictionary = gs._save_dict().duplicate(true)
	var touched: Array = []
	for k in CARRY:
		if var_to_str(mid.get(k)) != var_to_str(pre.get(k)):
			touched.append("%s %s→%s" % [k, var_to_str(pre.get(k)), var_to_str(mid.get(k))])
	_ok("分母 · 这一局打完了(开打 %d 次, %s)" % [fights, str(s._dl_state)], str(s._dl_state) == "done" and fights >= 2)
	_ok("★B 分母: 局内确实写过跨场累积(香火 / 赌神 / 斧头至少一样)", not touched.is_empty(), str(touched))
	_ok("★B 分母: 「以后新加的写入点」局内确实写进了内存", int(mid.get("meta_deepsea_coins", 0)) == int(pre.get("meta_deepsea_coins", 0)) + 7)
	_ok("★C 打到了结算(结算函数确实被调过)", bool(s._settled))
	_ok("★C 不计赛季(_had_season = false)", not bool(s._had_season))
	_ok("★C 不录像 / 不直播(录像模式为空)", mode0 == "", "mode=%s" % mode0)
	_ok("★C 没有待结算单", not pend0 and AM.read().is_empty())
	var scr: Node = s._hud._settle if s._hud != null else null
	_ok("★C 结算屏写「%s」" % Spar.SUBTITLE, scr != null and _find_label(scr, Spar.SUBTITLE))
	_ok("★C 结算屏按钮「再来一局 / 返回好友」, 没有「前往商店」",
		scr != null and scr.find_child("SparAgain", true, false) != null and scr.find_child("SparBack", true, false) != null
			and not _find_label(scr, s._hud.SHOP_BTN_TEXT))
	s.queue_free()
	for _g in range(4):
		await get_tree().process_frame
	var post: Dictionary = gs._save_dict().duplicate(true)
	var dk := _diff_keys(pre, post)
	var dv := ""
	for k in dk:
		dv += " | %s: %s → %s" % [k, JSON.stringify(pre.get(k)).left(300), JSON.stringify(post.get(k)).left(300)]
	_ok("★★A 切磋前后存档逐键相同(%d 个键)" % pre.size(), dk.is_empty() and pre.size() > 50, "不同: %s%s" % [str(dk), dv])
	_ok("★A 离场后不在切磋里、test_mode 还原", not Spar.is_active() and not bool(gs.test_mode))
	var post_files: Dictionary = _files()
	var fd := _diff_keys(pre_files, post_files)
	_ok("★★A user:// 下没有多出 / 改动任何文件(存档 / 录像 / 待结算单)", fd.is_empty(), "不同: %s" % str(fd))
	_ok("★A 战绩没多一行", (gs.match_history as Array).size() == pre_hist, "%d → %d" % [pre_hist, (gs.match_history as Array).size()])
	_ok("★A 上传队列 / 待挂录像没动",
		var_to_str([gs.ghost_upload_pending, gs.replay_upload_pending, gs.replay_pending_id]) == pre_up)

	# ── E 切磋期间云端拉回的存档 ──
	_setup_gs(gs)
	var cloud: Dictionary = gs._save_dict().duplicate(true)
	cloud["nickname"] = "云端那份"
	Spar.begin(_ghost(), {})
	gs.apply_cloud_payload(cloud, 42)
	var during := str(gs.nickname)
	Spar.end()
	_ok("★E 切磋期间不当场落(否则离场还原会把它盖掉)", during != "云端那份", "切磋中昵称=%s" % during)
	_ok("★E 离场还原之后落下了", str(gs.nickname) == "云端那份" and int(gs.cloud_rev) == 42,
		"昵称=%s rev=%d" % [str(gs.nickname), int(gs.cloud_rev)])

	print("ALL PASS — 好友切磋不进常规赛 (%d 项)" % _n if _fail == 0 else "FAIL x%d / %d" % [_fail, _n])
	get_tree().quit()
