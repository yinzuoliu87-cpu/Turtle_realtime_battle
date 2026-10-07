extends Node
## verify_replay_controls.gd — 回放体验打磨门禁(方案书 docs/plans/20261005-回放体验打磨.md)
##
## 用户 2026-10-05:「那你给我去模拟下打开窗口看这周比赛回放，找任何不合理的问题，比如玩家手感，ai味，然后全部给我修好」
## 主会话实玩追加: 积分赛打完战绩页没有「回放」(Q3 只录周六) ⇒ 用户改 Q3: 积分赛也录。
##
## ★全程走真入口: 真战斗场打一局**积分赛** → 真结算 → 真实例化战绩页 → 按那一行(`pressed.emit()`)
##   → 真换场景进回放 → 按回放条上的钮(暂停 / 倍速 / 退出) → 收尾卡「再看一遍」「返回战绩」。
##
## 段落:
##   ① 积分赛也录: 录制模式 / 本机录像在 / 上传队列有一条 ph=ranked(不带闯关战绩) / 行 phase=ranked / 战绩页出「回放」
##   ② 操作条: 暂停 ⇒ 喂多少帧 sim 都不走一步; 继续 ⇒ 走; 倍速轮换 1→2→4→1
##   ③ ★倍速不改结果: 同一份录像 1× / 2× / 4× 各播一遍(同样的帧长) ⇒ 三遍都不分叉、校验点逐个比过且个数相同、
##      终局一致; 4× 用的帧数 ≤ 1× 的 1/3(分母: 倍速真的生效了)
##   ④ 收尾卡: 播完出卡(胜负 + 全场时长 + 「再看一遍」「返回战绩」); 「再看一遍」⇒ 真换场景、同一份录像从第 0 步重播;
##      「返回战绩」⇒ 回战绩页; 存档逐字节不变 / GameState 还原
##   ⑤ 主菜单左栏有「战绩」入口(独立一格, ≥ 触控线), 点了真进战绩页
##   ⑥ 两侧单位栏不再有龟蛋那一格(分母: 场上真有蛋); 路名只有「上路 / 下路 / 决胜」
##   ⑦ 2026-10-07 第二轮(用户「回放系统也是个问题呢」):
##      · 战绩页每场一张对局卡; 「观看」只出在有录像的那一张(另造一条没录像的老记录当对照)
##      · 写入侧记下对手(三统领 + 名字), 卡上右边写的就是那个名字
##      · 回放时左上铭牌没了(不许有 ReplayPlate); 顶栏路名牌左边有「回放」小签
##      · 进度条每道刻度下面有路名(上路 / 下路 / 终极), 个数 = 录像里开打的路数

const SB := preload("res://scripts/net/supabase.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const Backend := preload("res://scripts/net/backend.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const ReplayFetcher := preload("res://scripts/systems/replay/replay_fetcher.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")
const RECORD_SCENE := "res://scenes/Record.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const DT := 1.0 / 60.0

var _fail := 0
var _n := 0
var _gs
var _id := ""
var _rec: Dictionary = {}
var _n_real_cp := 0
var _egg_checked := false
var _all_ran := false


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _setup_gs() -> void:
	_gs.reset_dual_lane()
	_gs.test_mode = false
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.week_phase = "ranked"               # ★积分赛(2026-10-05 起也录)
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261005
	_gs.dual_ghost = Backend.make_bot(3, rng)
	_gs.dual_active = true
	_gs.account_id = ME


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	_ok("分母: 后端关着(不往外传)", not SB.enabled())
	_setup_gs()
	_ok("① ★积分赛要录(用户 2026-10-05 改 Q3)", ReplayRecorder.should_record())
	_gs.tutorial_active = true
	_ok("① 教学不录", not ReplayRecorder.should_record())
	_gs.tutorial_active = false
	await _record()
	if _id == "":
		_finish()
		return
	## ⑦ 对照行: 一条没有录像、也没有对手信息的老记录(老存档长这样)。★在取基线之前加, 回放还原比的是含它的那一份。
	(_gs.match_history as Array).append({"result": "lose", "lineup": ["basic", "stone"], "mode": "实时", "turn": 41, "ts": 1})
	_gs.save()
	var base := {"save": FileAccess.get_file_as_bytes(_gs.SAVE_PATH), "state": var_to_bytes(ReplayRecorder.capture_state()),
		"hist": var_to_bytes(_gs.match_history)}
	_ok("分母: 存档文件真的在", (base["save"] as PackedByteArray).size() > 0)
	await _t_controls_and_card(base)
	await _t_speed_same_result()
	await _t_menu_entry()
	_all_ran = true
	_finish()


# ① ─────────────────────────────────────────────────────────────
func _record() -> void:
	print("── ① 真战斗场打一局积分赛 ──")
	var hist0: int = (_gs.match_history as Array).size()
	var q0: int = (_gs.replay_upload_pending as Array).size()
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	_ok("① ★这一局在录(积分赛)", str(s._replay.mode) == "rec", str(s._replay.mode))
	var last := ""
	var stf := 0
	var fights := 0
	var surrendered := false
	var i := 0
	while i < 6000 and (_gs.match_history as Array).size() == hist0:
		var st: String = str(s._dl_state)
		if st != last:
			last = st
			stf = 0
		stf += 1
		if (st == "overview" or st == "lane_settle") and stf == 9:
			s._dl_sys._dl_present_click()
		elif st == "place" and stf == 20 and is_instance_valid(s._dl_go_btn):
			s._dl_go_btn.pressed.emit()
			fights += 1
		elif st == "fight" and stf == 60 and not _egg_checked:
			_check_egg_and_lane(s)
		elif st == "fight" and fights >= 2 and stf == 120 and not surrendered:
			s._do_surrender()
			surrendered = true
		s._process(0.05)
		await get_tree().process_frame
		i += 1
	await _frames(10)
	_id = str(_gs.match_history[0].get("replay_id", "")) if (_gs.match_history as Array).size() > hist0 else ""
	_ok("① ★结算挂上了回放 id", SB.is_uuid(_id), _id)
	_rec = ReplayRecorder.load_record(_id) if _id != "" else {}
	_ok("① ★本机录像在、读得回来", not _rec.is_empty())
	var _h0: Dictionary = _gs.match_history[0] if (_gs.match_history as Array).size() > hist0 else {}
	var _gh: Dictionary = _gs.dual_ghost if _gs.dual_ghost is Dictionary else {}
	var _want_foe: Array = []
	for x in _gh.get("leaders", []):
		if _want_foe.size() < 3:
			_want_foe.append(str(x))
	var _want_nm := str((_gh.get("profile", {}) as Dictionary).get("name", ""))
	_ok("⑦ 分母: 对手快照有统领、有名字", not _want_foe.is_empty() and _want_nm != "", "%s %s" % [str(_want_foe), _want_nm])
	_ok("⑦ ★战绩写下了对手三统领 + 名字(与顶栏同一出处)", _h0.get("foe", []) == _want_foe and str(_h0.get("foe_name", "")) == _want_nm,
		"%s / %s" % [str(_h0.get("foe", [])), str(_h0.get("foe_name", ""))])
	for h in _rec.get("cps", []):
		if str(h) != ReplayRecorder.PLACE_CP:
			_n_real_cp += 1
	_ok("① 分母: 录到的非摆位校验点 %d 个 > 0、两路都开打过" % _n_real_cp, _n_real_cp > 0 and fights >= 2)
	var q: Array = _gs.replay_upload_pending
	var e: Dictionary = {}
	for x in q:
		if x is Dictionary and str((x as Dictionary).get("id", "")) == _id:
			e = x
	_ok("① ★上传队列多了这一条", q.size() == q0 + 1 and not e.is_empty(), "%d→%d" % [q0, q.size()])
	_ok("① ★单子 ph = ranked, 不带闯关战绩(gw0/gl0)、不带决赛坐标",
		str(e.get("ph", "")) == RU.PH_RANKED and not e.has("gw0") and not e.has("fk"), str(e))
	var row: Dictionary = RU.build_row(e, _rec, ME)
	var res: Dictionary = row.get("result", {})
	_ok("① ★行 phase = ranked, result 里没有 gw/gl(赛况板只查 phase=gauntlet, 混不进去)",
		str(row.get("phase", "")) == "ranked" and not res.has("gw") and not res.has("fb"), str(row.get("phase", "")))
	_ok("① 赛况板查询只认 gauntlet", SB.gauntlet_board_query(1).begins_with("phase=eq.gauntlet"))
	_ok("⑥ 分母: 开打后检查过两侧单位栏", _egg_checked)
	s.queue_free()
	await _frames(4)


## ⑥ 两侧单位栏: 场上有蛋, 栏里没有蛋那一格; 路名统一。
func _check_egg_and_lane(s) -> void:
	_egg_checked = true
	var eggs := 0
	var egg_frames := 0
	var frames := 0
	for u in s._units:
		if InfoPanel.is_egg_unit(u):
			eggs += 1
	for col in [s._team_panel_left, s._team_panel_right]:
		if col == null or not is_instance_valid(col):
			continue
		for c in (col as Node).get_children():
			if str(c.name).begins_with("Frame_"):
				frames += 1
		for u in s._units:
			if InfoPanel.is_egg_unit(u) and (col as Node).get_node_or_null("Frame_" + str(u.get("id", ""))) != null:
				egg_frames += 1
	_ok("⑥ 分母: 场上真有蛋(%d 个)、栏里真有单位格(%d 个)" % [eggs, frames], eggs >= 2 and frames >= 2)
	_ok("⑥ ★两侧单位栏里没有龟蛋那一格", egg_frames == 0, "蛋格 %d" % egg_frames)
	## ★2026-10-07 用户:「我们叫上路战场，下路战场，终极战场」(推翻 10-05 统一成的 上路/下路/决胜)。
	_ok("⑥ ★路名唯一出处: 上路战场 / 下路战场 / 终极战场", s._LANE_CN == {"top": "上路战场", "bottom": "下路战场", "final": "终极战场"}, str(s._LANE_CN))
	var hud_t := str(s._dl_hud.text) if s._dl_hud != null else ""
	_ok("⑥ 顶上计时牌写「上路战场 m:ss」(不是「上半场」, 不带【】)", hud_t.begins_with("上路战场 ") and not hud_t.contains("半场"), hud_t)


# ② ④ ─────────────────────────────────────────────────────────────
func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


func _is_record(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() != null \
		and str((n.get_script() as Script).resource_path).ends_with("RecordScene.gd")


func _wait_scene(pred: Callable, max_frames: int = 120) -> Node:
	for _i in range(max_frames):
		var cs := get_tree().current_scene
		if pred.call(cs):
			return cs
		await get_tree().process_frame
	return null


func _named(root: Node, nm: String) -> Node:
	return root.find_child(nm, true, false) if root != null else null


func _t_controls_and_card(base: Dictionary) -> void:
	print("── ② 操作条 / ④ 收尾卡 ──")
	var rs: Node = (load(RECORD_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(rs)
	get_tree().current_scene = rs
	await _frames(3)
	var btn: Button = null
	for b in rs.find_children("ReplayBtn", "Button", true, false):
		if str((b as Button).get_meta("replay_id", "")) == _id:
			btn = b
	_ok("① ★战绩页那一场(积分赛)有「观看」", btn != null and btn.text == "观看", btn.text if btn != null else "")
	## ⑦ 对局卡: 一场一张; 「观看」只在有录像的那张
	var cards: Array = rs.find_children("RecordCard*", "", true, false)
	var hist: Array = _gs.match_history
	var want_btn := 0
	var now: int = ReplayFetcher.P2C.now_utc()
	for k in range(mini(20, hist.size())):
		if ReplayFetcher.has_replay(hist[k], now):
			want_btn += 1
	var with_btn := 0
	var bad := 0
	for k in range(cards.size()):
		var nb: int = (cards[k] as Node).find_children("ReplayBtn", "Button", true, false).size()
		with_btn += 1 if nb > 0 else 0
		if (nb > 0) != (k < hist.size() and ReplayFetcher.has_replay(hist[k], now)):
			bad += 1
	_ok("⑦ 分母: 卡数 = 记录数 %d, 其中有录像的 %d 张、没录像的 ≥1 张" % [hist.size(), want_btn],
		cards.size() == mini(20, hist.size()) and want_btn >= 1 and want_btn < cards.size(), "卡 %d" % cards.size())
	_ok("⑦ ★「观看」只出在有录像的卡上(逐张对)", bad == 0 and with_btn == want_btn, "错 %d / 有钮 %d" % [bad, with_btn])
	var foe_l := (cards[0] as Node).find_child("FoeName", true, false) as Label if not cards.is_empty() else null
	_ok("⑦ ★第一张卡右边写着对手名", foe_l != null and foe_l.text != "" and foe_l.text == str(hist[0].get("foe_name", "~")),
		foe_l.text if foe_l != null else "<无>")
	if btn == null:
		return
	btn.pressed.emit()
	var b = await _wait_scene(_is_battle)
	_ok("② 分母: 进了战斗场、在播", b != null and b._replay.is_playing())
	if b == null:
		return
	b.set_process(false)
	## 先走到开打之后
	var i := 0
	while i < 3000 and str(b._dl_state) != "fight":
		b._process(DT)
		await get_tree().process_frame
		i += 1
	await _frames(2)
	var bar: Node = b._hud._replay_bar
	var pb := _named(bar, RC.N_PAUSE) as Button
	var spd := _named(bar, RC.N_SPEED) as Button
	var ex := _named(bar, RC.N_EXIT) as Button
	_ok("② 分母: 操作条上 暂停 / 倍速 / 退出回放 三颗钮都在", pb != null and spd != null and ex != null and ex.text == "退出回放")
	## ⑦ 左上铭牌删了(与顶栏重复、压开场牌子); 「回放」改成顶栏路名牌旁边的小签。
	_ok("⑦ ★回放时整个战斗场里没有 ReplayPlate", b.find_child("ReplayPlate", true, false) == null)
	var mark := b.find_child("ReplayMark", true, false) as Control
	_ok("⑦ ★顶栏路名牌旁边有「回放」小签(同一行、看得见)", mark != null and mark.is_visible_in_tree()
		and str(mark.get_parent().name) == "LaneRow" and b._dl_hud != null and mark.get_parent() == b._dl_hud.get_parent().get_parent()
		and (mark.find_children("*", "Label", true, false) as Array).size() == 1
		and ((mark.find_children("*", "Label", true, false) as Array)[0] as Label).text == "回放")
	_ok("② 顶栏计时牌写着现在打到哪一路", str(b._dl_hud.text).begins_with("上路战场"), str(b._dl_hud.text))
	var tn := b.find_child("TopName_R", true, false) as Label
	_ok("② 顶栏右边写着对手快照名(看自己的录像)", tn != null
		and tn.text == str(((_rec["state"]["dual_ghost"] as Dictionary).get("profile", {}) as Dictionary).get("name", "~")),
		tn.text if tn != null else "<无>")
	## ⑦ 进度条刻度下的路名
	var nf: int = mini(3, (b._replay.fight_steps() as Array).size())
	var tl_txt: Array = []
	for k in range(3):
		var tl := _named(bar, RC.N_TICK_LBL + str(k)) as Label
		if tl != null:
			tl_txt.append(tl.text)
	_ok("⑦ ★进度条每道刻度下面有路名(个数 = 开打的路数 %d ≥ 2)" % nf,
		nf >= 2 and tl_txt == (["上路", "下路", "终极"] as Array).slice(0, nf), str(tl_txt))
	_ok("② 时间读数「已播 / 全场」", _named(bar, RC.N_TIME) != null and (_named(bar, RC.N_TIME) as Label).text.contains(" / "))
	if pb == null or spd == null:
		return
	## 暂停
	var s0 := int(b._sim_step_n)
	pb.pressed.emit()
	for _k in range(60):
		b._process(0.1)
		await get_tree().process_frame
	var s1 := int(b._sim_step_n)
	_ok("② ★暂停: 喂 60 帧(各 0.1 秒) sim 一步都没走", s1 == s0 and b._replay.paused, "%d→%d" % [s0, s1])
	_ok("② 暂停时按钮写「继续」、屏幕中间出「已暂停」", pb.text == "继续" and _named(bar, RC.N_PAUSED) != null
		and (_named(bar, RC.N_PAUSED) as Control).visible)
	pb.pressed.emit()
	for _k in range(10):
		b._process(DT)
		await get_tree().process_frame
	_ok("② ★继续: sim 接着走", int(b._sim_step_n) > s1 and not b._replay.paused, "%d→%d" % [s1, int(b._sim_step_n)])
	## 倍速轮换
	var seen: Array = []
	for _k in range(3):
		seen.append(spd.text)
		spd.pressed.emit()
	_ok("② 倍速轮换 1 → 2 → 4 → 1", seen == ["1 倍速", "2 倍速", "4 倍速"] and spd.text == "1 倍速", str(seen))
	## 4 倍速播完
	spd.pressed.emit()
	spd.pressed.emit()
	_ok("② 分母: 切到 4 倍速", is_equal_approx(float(b._replay.speed), 4.0))
	i = 0
	while i < 4000 and not b._replay.finished and b._replay.diverged_at < 0:
		b._process(DT)
		await get_tree().process_frame
		i += 1
	_ok("④ ★4 倍速播完没分叉、校验点一个不差(%d / %d)" % [int(b._replay.cp_checked), _n_real_cp],
		b._replay.finished and b._replay.diverged_at < 0 and int(b._replay.cp_checked) == _n_real_cp, b._replay.diverge_why)
	## 收尾卡(最后一击落地后约 1.2 秒出)
	var card: Node = null
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
		card = _named(bar, RC.N_CARD)
		if card != null:
			break
	_ok("④ ★播完出收尾卡", card != null)
	if card == null:
		return
	var ag := _named(card, RC.N_AGAIN) as Button
	var bk := _named(card, RC.N_BACK) as Button
	var title := _named(card, "ReplayResult") as Label
	_ok("④ 卡上: 胜负 + 「再看一遍」+「返回战绩」", ag != null and bk != null and bk.text == "返回战绩"
		and title != null and (title.text == "胜利" or title.text == "失败"), title.text if title != null else "")
	_ok("④ 结算屏没出来(回放不走结算)", b.find_child("SettleScreen", true, false) == null)
	_ok("④ 分母: 操作条收起", not (_named(bar, "ReplayStrip") as Control).visible)
	## 再看一遍
	## ★不在闭包里捕获 b(它马上被换场景释放 ⇒ 「Lambda capture was freed」): 比实例号。
	## ★★实例号必须在按钮【之前】取(2026-10-05 修 CI rc=134 段错误): 原来放在 `await _frames(3)` 之后,
	##   那时旧战斗场已被换场景释放, `b.get_instance_id()` 是对已释放对象调方法 —— 引擎**不报错**,
	##   读的是释放掉的内存(探针: is_instance_valid(b)=false 时照样返回一个数), 内存被复用了就 signal 11。
	##   本地几乎不出; WSL 里同版本 Linux Godot `--max-fps 15` 并行 10 份, 5 份崩, 全崩在这一行。
	var b_id: int = b.get_instance_id()
	ag.pressed.emit()
	await _frames(3)
	var b2 = await _wait_scene(func(n): return _is_battle(n) and n.get_instance_id() != b_id)
	_ok("④ ★「再看一遍」⇒ 新的战斗场、仍在播、同一份录像、从头开始",
		b2 != null and b2._replay.is_playing() and str(b2._replay.rec.get("id", "")) == _id and int(b2._sim_step_n) < 30,
		"step=%d" % (int(b2._sim_step_n) if b2 != null else -1))
	if b2 == null:
		return
	b2.set_process(false)
	_ok("④ 倍速沿用上一次(4 倍)", is_equal_approx(float(b2._replay.speed), 4.0))
	for _k in range(200):
		b2._process(DT)
		await get_tree().process_frame
	_ok("④ 重播没分叉", b2._replay.diverged_at < 0, b2._replay.diverge_why)
	var ex2 := _named(b2._hud._replay_bar, RC.N_EXIT) as Button
	ex2.pressed.emit()
	var back = await _wait_scene(_is_record)
	_ok("④ ★退出回放 ⇒ 回到战绩页", back != null)
	await _frames(3)
	_ok("④ ★存档文件逐字节不变", FileAccess.get_file_as_bytes(_gs.SAVE_PATH) == base["save"])
	_ok("④ ★GameState 还原", var_to_bytes(ReplayRecorder.capture_state()) == base["state"]
		and var_to_bytes(_gs.match_history) == base["hist"])
	_ok("④ 没有挂着的待播 / 备份 / 「再看一遍」", ReplayRecorder.pending_play.is_empty() and not ReplayRecorder._has_backup
		and ReplayRecorder._again.is_empty())
	if back != null:
		back.queue_free()
	await _frames(3)


# ③ ─────────────────────────────────────────────────────────────
## 同一份录像按指定倍速播完(帧长固定 1/60 秒), 返回 {frames, cps, div, fin, end}。
func _play_at(spd: float) -> Dictionary:
	ReplayRecorder.begin_play(_rec)
	var s = RB.new()
	add_child(s)
	s.set_process(false)
	await get_tree().process_frame
	s._replay.speed = spd
	var f := 0
	while f < 30000 and not s._replay.finished and s._replay.diverged_at < 0:
		s._process(DT)
		f += 1
		if f % 8 == 0:
			await get_tree().process_frame
	var out := {"frames": f, "cps": int(s._replay.cp_checked), "div": int(s._replay.diverged_at),
		"why": str(s._replay.diverge_why), "fin": bool(s._replay.finished), "end": ReplayRecorder.digest(s),
		"steps": int(s._sim_step_n)}
	s.queue_free()
	await _frames(3)
	ReplayRecorder.end_play()
	return out


func _t_speed_same_result() -> void:
	print("── ③ 倍速不改结果 ──")
	var r1 := await _play_at(1.0)
	var r2 := await _play_at(2.0)
	var r4 := await _play_at(4.0)
	for p in [["1×", r1], ["2×", r2], ["4×", r4]]:
		var r: Dictionary = p[1]
		_ok("③ ★%s 播完不分叉、校验点 %d = 录到的 %d" % [p[0], int(r["cps"]), _n_real_cp],
			bool(r["fin"]) and int(r["div"]) < 0 and int(r["cps"]) == _n_real_cp, str(r["why"]))
	## ★结算那一步的步号与指纹已由产品自己在 `on_settle` 里逐一比过(对不上就 diverged_at ≥ 0, 上一条会红);
	##   这里再比一次播完那一刻的全场指纹。⚠ 不比 `_sim_step_n`: 多倍速时结算那一帧剩下的几步照样跑, 步号自然多几步。
	_ok("③ ★三种倍速终局指纹完全相同", str(r1["end"]) == str(r2["end"]) and str(r1["end"]) == str(r4["end"]),
		"%s %s %s" % [r1["end"], r2["end"], r4["end"]])
	_ok("③ 分母: 倍速真的生效(4× 用帧 %d ≤ 1× 的 1/3 = %d)" % [int(r4["frames"]), int(r1["frames"]) / 3],
		int(r4["frames"]) * 3 <= int(r1["frames"]) and int(r2["frames"]) < int(r1["frames"]))


# ⑤ ─────────────────────────────────────────────────────────────
func _t_menu_entry() -> void:
	print("── ⑤ 主菜单「战绩」入口 ──")
	var mm: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(mm)
	await _frames(3)
	var t0 := Time.get_ticks_msec()
	Engine.time_scale = 8.0
	while Time.get_ticks_msec() - t0 < 1500:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	## ★2026-10-05 第四轮: 左栏不再单设「战绩」键(用户:「点击整个卡那就不要战绩单独给按钮啊」),
	##   整张左上玩家卡就是战绩入口。
	var ent := mm.find_child(MM.CARD_NAME, true, false) as Control
	_ok("⑤ ★左上玩家卡(战绩入口)在场", ent != null)
	if ent == null:
		mm.queue_free()
		return
	var r := ent.get_global_rect()
	## ★2026-10-05 第三轮: 左栏从「排行榜 | 战绩」对半一行(宽 191)换成方形图标键(88×88) ⇒ 宽 ≥150 那条没有对象了,
	##   守的仍是触控线: 短边 ≥ 81(=44pt), 并且是方的(图标在上、字在下)。
	_ok("⑤ 入口 ≥ 触控线(短边 ≥ 81)", minf(r.size.x, r.size.y) >= 81.0, str(r))
	_ok("⑤ 左栏没有单独的「战绩」键", mm.find_child(str(MM.SQ_NAME_PREFIX) + "战绩", true, false) == null)
	var bt: Button = null
	for c in ent.find_children("*", "Button", true, false):
		bt = c
	get_tree().current_scene = mm
	if bt != null:
		bt.pressed.emit()
	var rs = await _wait_scene(_is_record)
	_ok("⑤ ★点了真进战绩页", rs != null)
	if rs != null:
		rs.queue_free()
	await _frames(3)


func _finish() -> void:
	_ok("★分母: 所有段落都走到了最后", _all_ran)
	print("  [耗帧] 本测试共跑 %d 帧(run-tests.sh frames_for 登记的预算要够)" % Engine.get_process_frames())
	print("")
	if _fail == 0:
		print("ALL PASS — 回放体验打磨 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
