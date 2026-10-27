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
##   ⑧ 2026-10-27 用户截图(铜管手铳说明断在「上限为 1」): 回放里从信息面板点开的装备小卡不许被底部操作条挡住
##      —— 全部装备逐件 3 星开一遍, 张张整张在屏幕里、在操作条之上、不挪层; 操作条上面放不下的长卡(小木斧本来 1994 px)
##      改成卡内上下滑动: 内容总高 > 可见高, 滚轮 / 手指拖动滚得动, 点卡不关卡, 滚到底看得到最后一行

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
		elif st == "fight" and stf == 1:
			## 2026-10-19 对局里没有摆位屏: 演出完同一步自动开打(原来这里按「开始战斗」)。
			fights += 1
		elif st == "fight" and stf == 60 and not _egg_checked:
			_check_egg_and_lane(s)
		elif st == "fight" and fights >= 2 and stf == 120 and not surrendered:
			s._forfeit_match()
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
	await _t_inspect_card_over_bar(b, bar)
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


# ⑧ ─────────────────────────────────────────────────────────────
## 信息面板从右滑入走真实时间(0.22 秒, battle_hud._show_unit_info_panel) ⇒ 按墙钟等它停稳, 不按帧数。
func _wait_slide() -> void:
	await _frames(2)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 400:
		await get_tree().process_frame


func _canvas_layer_of(n: Node) -> CanvasLayer:
	var p: Node = n.get_parent() if n != null else null
	while p != null and not (p is CanvasLayer):
		p = p.get_parent()
	return p as CanvasLayer


## 小卡里的卡内滚动框(InspectCard.N_SCROLL); 没有 = null。
func _card_scroll(c: Control) -> ScrollContainer:
	if c == null or not is_instance_valid(c):
		return null
	return c.find_child(InspectCard.N_SCROLL, true, false) as ScrollContainer


## 滚动框里内容的总高(里面那层 VBox 排完版的高)。
func _scroll_content_h(sc: ScrollContainer) -> float:
	if sc == null or sc.get_child_count() == 0:
		return 0.0
	return maxf((sc.get_child(0) as Control).size.y, (sc.get_child(0) as Control).get_combined_minimum_size().y)


## 往视口里推真的鼠标事件(走 GUI → 没人吃才到战斗场 _unhandled_input, 与玩家点屏同一条路)。
func _push_btn(p: Vector2, btn: MouseButton, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.factor = 1.0
	e.position = p
	e.global_position = p
	if down and btn == MOUSE_BUTTON_LEFT:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(e)


func _push_move(p: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m)


## 小卡 / 信息面板都还开着(点卡没有把它们关掉)。
func _still_open(b, ic, k: String) -> bool:
	return ic.card != null and is_instance_valid(ic.card) and str(ic.key) == k \
		and b._info_panel != null and is_instance_valid(b._info_panel)


## 用户 2026-10-27 截图: 回放里点信息面板上的装备, 左边弹出的说明小卡(inspect_card.gd)下半截被底部操作条挡住 ——
##   铜管手铳(p2eq_077, 3 星)的说明断在「上限为 1」。操作条在 _ui_layer 上面一层(ReplayLayer), 小卡挂在 _ui_layer。
## ⇒ 从真信息面板的装备槽, 把【全部】装备逐件按 3 星开一遍: 每张整张都在屏幕里、也在操作条上沿之上, 没有一张挪层。
##   ★不只测铜管手铳: 长卡才会撞, 哪件最长会随文案变 ⇒ 全量过。
## ★2026-10-27 第二轮: 小木斧(p2eq_096)3 星宽 300 时高 1994, 原来放哪都装不下(点名豁免 + 挪层压住「退出回放」)。
##   内容不删(用户 10-22 定四个形态、四个造物全列)⇒ 放不下的卡改成卡内上下滑动: 卡头不动, 正文到「本局」在滚动框里;
##   豁免删掉, 改成断言「超长的卡有滚动框, 内容总高 > 可见高」, 并真推滚轮 / 手指拖动 / 点卡, 量滚得动、卡不被关掉。
## 分母: 件数 / 与操作条横向重叠的张数 / 按改前摆法会被挡的张数 / 本来最高那张多高 / 滚动的张数。
func _t_inspect_card_over_bar(b, bar: Node) -> void:
	print("── ⑧ 回放中装备说明小卡不被操作条挡住 ──")
	var strip := _named(bar, "ReplayStrip") as Control
	var rl := b.get_node_or_null("ReplayLayer") as CanvasLayer
	_ok("⑧ 分母: 操作条看得见、挂在 ReplayLayer(比 _ui_layer 高)", strip != null and strip.is_visible_in_tree()
		and rl != null and rl.is_ancestor_of(strip) and rl.layer > int(b._ui_layer.layer))
	if strip == null or rl == null:
		return
	var sr: Rect2 = strip.get_global_rect()
	var vp: Vector2 = Vector2(b.get_viewport().get_visible_rect().size)
	## 信息面板自己: 场上每个能点的单位(蛋不能点)逐个开面板, 面板里看得见的叶子控件(字 / 图标 / 槽)一个都不许压在操作条底下。
	var covered: Array = []
	var n_leaf := 0
	var n_unit := 0
	var low := 0.0
	var low_who := ""
	for x in b._units:
		if not (x is Dictionary) or float(x.get("hp", 0.0)) <= 0.0 or InfoPanel.is_egg_unit(x):
			continue
		b._hud._show_unit_info_panel(x)
		await _wait_slide()
		var p0 := b._info_panel as Control
		if p0 == null or not is_instance_valid(p0):
			continue
		n_unit += 1
		var pr: Rect2 = p0.get_global_rect()
		for c in p0.find_children("*", "Control", true, false):
			var cc := c as Control
			if cc == null or not cc.is_visible_in_tree() or cc.get_child_count() > 0 or cc.size.x <= 0.0 or cc.size.y <= 0.0:
				continue
			var cr: Rect2 = cc.get_global_rect().intersection(pr)     # 滚动容器裁掉的部分本来就看不见
			if cr.size.x <= 0.0 or cr.size.y <= 0.0:
				continue
			n_leaf += 1
			if cr.end.y > low:
				low = cr.end.y
				low_who = "%s 的 %s" % [str(x.get("id", "")), cc.name]
			if cr.intersects(sr):
				covered.append("%s:%s(%s)@y%d..%d" % [str(x.get("id", "")), cc.name, cc.get_class(), int(cr.position.y), int(cr.end.y)])
		b._hud._close_info_panel()
		await _frames(2)
	print("    [⑧] 信息面板: 单位 %d 个 / 叶子控件 %d 个 / 最低的内容到 y=%d (%s) / 操作条 x %d..%d y≥%d" % [
		n_unit, n_leaf, int(low), low_who, int(sr.position.x), int(sr.end.x), int(sr.position.y)])
	_ok("⑧ ★信息面板里的内容没被操作条盖住(场上 %d 个单位逐个开, 叶子控件 %d 个)" % [n_unit, n_leaf],
		n_unit >= 4 and n_leaf >= 40 and covered.is_empty(), "%d 个被盖: %s" % [covered.size(), str(covered.slice(0, 6))])
	## 开小卡用的龟(不是召唤物 / 训龟师), 优先挑身上带装备的
	var u: Dictionary = {}
	for x in b._units:
		if not (x is Dictionary) or float(x.get("hp", 0.0)) <= 0.0 or InfoPanel.is_egg_unit(x) \
				or bool(x.get("is_summon", false)) or bool(x.get("is_trainer", false)):
			continue
		if u.is_empty() or ((u.get("equips", []) as Array).is_empty() and not (x.get("equips", []) as Array).is_empty()):
			u = x
	_ok("⑧ 分母: 场上有一只能点开信息面板的龟", not u.is_empty(), "%s 装备 %d 件" % [str(u.get("id", "")), (u.get("equips", []) as Array).size()])
	if u.is_empty():
		return
	b._hud._show_unit_info_panel(u)
	await _wait_slide()
	var panel := b._info_panel as Control
	var row: Node = panel.find_child("EquipRow", true, false) if panel != null and is_instance_valid(panel) else null
	var anchor: Control = (row.get_child(0) as Control) if row != null and row.get_child_count() > 0 else null
	_ok("⑧ 分母: 信息面板开着、装备槽在(小卡从这里开)", anchor != null and anchor.is_visible_in_tree(),
		str(anchor.get_global_rect()) if anchor != null else "<无>")
	if anchor == null:
		return
	## 全部装备逐件 3 星
	var ids: Array = DataRegistry.phase2_equipment_by_id.keys()
	ids.sort()
	var ic = b._info_sys.card()
	var room: float = sr.position.y - InspectCard.EDGE - InspectCard.TOP_Y     # 卡能用的总高(卡顶 TOP_Y 到条顶 − EDGE)
	var not_open: Array = []
	var bad: Array = []
	var off: Array = []
	var raised: Array = []
	var idle_scroll: Array = []
	var tall_flat: Array = []
	var head_scrolls: Array = []
	var scrolled: Array = []
	var n_ok := 0
	var n_hov := 0
	var n_would_hit := 0
	var leak := 0
	var max_h := 0.0
	var max_id := ""
	var fit_h := 0.0
	var fit_id := ""
	var seen077 := false
	var r077 := Rect2()
	var ay: float = anchor.get_global_rect().position.y - 6.0
	for e in ids:
		var eid := str(e)
		b._info_sys._open_equip_card(u, eid, 3, anchor)
		await _frames(3)                   # 摆位等一帧排完版按真实高度收; 放不下的那帧装滚动框, 再一帧收到整行
		var c: Control = ic.card
		if c == null or not is_instance_valid(c) or str(ic.key) != "eq:" + eid:
			not_open.append(eid)
			continue
		n_ok += 1
		var r: Rect2 = c.get_global_rect()
		if _canvas_layer_of(c) != b._ui_layer:
			raised.append("%s → %s" % [eid, str(_canvas_layer_of(c).name) if _canvas_layer_of(c) != null else "<无层>"])
		if r.position.x < sr.end.x and r.end.x > sr.position.x:
			n_hov += 1
		## 这张卡本来(不滚)有多高 = 卡高 − 滚动框可见高 + 滚动框里内容总高
		var sc := _card_scroll(c)
		var nat: float = r.size.y
		if sc != null:
			nat = r.size.y - sc.size.y + _scroll_content_h(sc)
			scrolled.append(eid)
			if _scroll_content_h(sc) <= sc.size.y + 0.5 or not sc.get_v_scroll_bar().is_visible_in_tree():
				idle_scroll.append("%s 内容 %d ≤ 可见 %d 或没滚动条" % [eid, int(_scroll_content_h(sc)), int(sc.size.y)])
			var tl := c.find_child("Title", true, false)
			var srow := c.find_child("StatRow", true, false)
			if (tl != null and sc.is_ancestor_of(tl)) or (srow != null and sc.is_ancestor_of(srow)) \
					or not sc.is_ancestor_of(ic.live.get("body")):
				head_scrolls.append(eid)
		elif r.size.y > room + 0.5:
			tall_flat.append("%s(%d px > 可用 %d)" % [eid, int(r.size.y), int(room)])
		## 改之前的摆法(顶边对齐装备槽, 只防出屏幕底边)会不会撞上操作条 —— 分母: 这条判据真有对象
		if clampf(ay, 50.0, maxf(50.0, vp.y - nat - 8.0)) + nat > sr.position.y:
			n_would_hit += 1
		if r.end.y > sr.position.y:
			bad.append("%s 底 %d > 条顶 %d" % [eid, int(r.end.y), int(sr.position.y)])
		if r.position.y < InspectCard.TOP_Y - 0.5 or r.position.x < 0.0 or r.end.y > vp.y or r.end.x > vp.x:
			off.append("%s %s" % [eid, str(r)])
		if nat > max_h:
			max_h = nat
			max_id = eid
		if sc == null and r.size.y > fit_h:
			fit_h = r.size.y
			fit_id = eid
		if eid == "p2eq_077":
			seen077 = true
			r077 = r
		ic.close()
		await get_tree().process_frame
		if is_instance_valid(c) or ic.card != null:
			leak += 1
	print("    [⑧] 装备 %d 件 / 开出 %d / 横向与操作条重叠 %d / 改前摆法会被挡 %d / 卡内滚动 %d 张 %s / 本来最高 %s %d px / 可用高 %d / 操作条 %s / 视口 %s" % [
		ids.size(), n_ok, n_hov, n_would_hit, scrolled.size(), str(scrolled), max_id, int(max_h), int(room), str(sr), str(vp)])
	_ok("⑧ 分母: 全部 %d 件装备都按 3 星开出了小卡, 且张张与操作条横向重叠(%d)" % [ids.size(), n_hov],
		ids.size() >= 50 and n_ok == ids.size() and n_hov == n_ok, "没开出: %s" % str(not_open.slice(0, 6)))
	_ok("⑧ 分母: 按改前的摆法会被操作条挡住的有 %d 张(判据真有对象)" % n_would_hit, n_would_hit >= 1)
	_ok("⑧ ★每张小卡都收在操作条上沿之上(%d 张, 不再有挪层豁免)" % n_ok, n_ok > 0 and bad.is_empty(),
		"%d 张被挡: %s" % [bad.size(), str(bad.slice(0, 6))])
	_ok("⑧ ★没有一张卡挪层去压操作条(张张都挂在 _ui_layer, 没有 InspectTopLayer)", n_ok > 0 and raised.is_empty()
		and b.get_node_or_null("InspectTopLayer") == null, str(raised.slice(0, 6)))
	_ok("⑧ ★每张小卡都整张在屏幕里(卡顶 ≥ %d、卡底 ≤ 视口底; 没有豁免)" % int(InspectCard.TOP_Y), n_ok > 0 and off.is_empty(),
		str(off.slice(0, 4)))
	_ok("⑧ ★超长的卡有卡内滚动框(本来比可用高 %d 高、却没滚动框的: 0 张)" % int(room), n_ok > 0 and tall_flat.is_empty(),
		str(tall_flat.slice(0, 6)))
	_ok("⑧ ★小木斧 p2eq_096 (3 星, 本来 %d px) 是卡内滚动" % int(max_h if max_id == "p2eq_096" else 0.0),
		scrolled.has("p2eq_096") and max_id == "p2eq_096" and max_h > room, "滚动的: %s / 最高 %s" % [str(scrolled), max_id])
	_ok("⑧ ★有滚动框的卡: 内容总高 > 可见高、滚动条看得见(%d 张)" % scrolled.size(), not scrolled.is_empty() and idle_scroll.is_empty(),
		str(idle_scroll.slice(0, 4)))
	_ok("⑧ ★卡头(名字 / 属性行)不滚、正文在滚动框里", not scrolled.is_empty() and head_scrolls.is_empty(), str(head_scrolls))
	_ok("⑧ ★铜管手铳 p2eq_077 (3 星, 用户截图那件) 测到了", seen077,
		"y %d..%d 高 %d / 条顶 %d" % [int(r077.position.y), int(r077.end.y), int(r077.size.y), int(sr.position.y)])
	_ok("⑧ 分母: 不滚的卡里最高的 %s 高 %d px ≥ 300(长卡真的被测到; 本来最高 %s %d px)" % [fit_id, int(fit_h), max_id, int(max_h)],
		fit_h >= 300.0)
	_ok("⑧ 每张关掉都真删了(不残留)", n_ok > 0 and leak == 0 and b.find_children("InspectCard", "", true, false).is_empty(), "残留 %d" % leak)
	## 自造一张比可用高还高的探针长卡(与装备文案无关): 照样卡内滚动、留在 _ui_layer、收在操作条之上; close() 照样删干净。
	var lines := PackedStringArray()
	for k in range(40):
		lines.append("探针第 %d 行" % k)
	ic.open("probe:tall", anchor, {"title": "探针长卡", "body": "\n".join(lines)})
	await _frames(3)
	var tc: Control = ic.card
	var tsc := _card_scroll(tc)
	var tr: Rect2 = tc.get_global_rect() if tc != null and is_instance_valid(tc) else Rect2()
	_ok("⑧ ★探针长卡(内容 %d > 可见 %d) ⇒ 卡内滚动、仍挂 _ui_layer、卡底 %d ≤ 条顶 %d" % [
		int(_scroll_content_h(tsc)), int(tsc.size.y if tsc != null else 0.0), int(tr.end.y), int(sr.position.y)],
		tsc != null and _scroll_content_h(tsc) > tsc.size.y and _canvas_layer_of(tc) == b._ui_layer
		and tr.end.y <= sr.position.y and tr.position.y >= InspectCard.TOP_Y - 0.5)
	var had_tc: bool = tc != null and is_instance_valid(tc)
	ic.close()
	await get_tree().process_frame
	_ok("⑧ ★带滚动框的卡 close() 照样删掉", had_tc and not is_instance_valid(tc) and ic.card == null
		and b.find_children("InspectCard", "", true, false).is_empty())
	## 最后一段会点战场空白把面板关掉 ⇒ 放在最后
	await _t_card_scroll_input(b, ic, u, anchor, sr)
	b._hud._close_info_panel()
	await _frames(2)


## 小木斧那张: 滚动条看得见 / 滚到底看得到最后一行 / 鼠标滚轮滚得动 / 手机按住拖动滚得动 / 点卡不关卡;
##   反面: 点战场空白照样关面板(证明点按真的走到了战斗场 _unhandled_input, 上面「不关」不是因为点击根本没送到)。
func _t_card_scroll_input(b, ic, u: Dictionary, anchor: Control, sr: Rect2) -> void:
	b._info_sys._open_equip_card(u, "p2eq_096", 3, anchor)
	await _frames(3)
	var c: Control = ic.card
	var sc := _card_scroll(c)
	_ok("⑧ 分母: 小木斧那张开着、有卡内滚动框", c != null and is_instance_valid(c) and sc != null)
	if sc == null:
		return
	var k := str(ic.key)
	var vbar := sc.get_v_scroll_bar()
	var cr: Rect2 = c.get_global_rect()
	var br: Rect2 = vbar.get_global_rect()
	_ok("⑧ ★滚动条看得见、在卡里(条 %s / 卡 %s)" % [str(br), str(cr)], vbar.is_visible_in_tree() and br.size.y >= 60.0
		and cr.encloses(br) and br.end.y <= sr.position.y)
	## 滚到底: 最后一行(「本局」那一行)整行落在滚动框里看得见的那一段
	sc.scroll_vertical = int(vbar.max_value)
	await _frames(2)
	var last := ic.live.get("extra") as Control
	var vis: Rect2 = sc.get_global_rect()
	var lr: Rect2 = last.get_global_rect() if last != null else Rect2()
	_ok("⑧ ★滚到底看得到最后一行「本局」(行 y %d..%d / 可见 y %d..%d)" % [int(lr.position.y), int(lr.end.y), int(vis.position.y), int(vis.end.y)],
		last != null and sc.scroll_vertical > 0 and lr.position.y >= vis.position.y - 0.5 and lr.end.y <= vis.end.y + 0.5)
	sc.scroll_vertical = 0
	await _frames(2)
	var p: Vector2 = vis.get_center()
	## 鼠标滚轮
	_push_btn(p, MOUSE_BUTTON_WHEEL_DOWN, true)
	_push_btn(p, MOUSE_BUTTON_WHEEL_DOWN, false)
	await _frames(2)
	var s_wheel: int = sc.scroll_vertical
	_ok("⑧ ★鼠标滚轮往下滚得动(0 → %d), 卡和面板都还开着" % s_wheel, s_wheel > 0 and _still_open(b, ic, k))
	## 手机按住拖动: Godot 的 ScrollContainer 只在有触屏时开拖动滚 ⇒ 无头里打开「鼠标模拟触屏」(手机上本来就是触屏)
	var emu0: bool = Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	_push_btn(p, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	var q := p
	for _i in range(6):
		q += Vector2(0, -30)
		_push_move(q, Vector2(0, -30))
		await get_tree().process_frame
	_push_btn(q, MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	var s_drag: int = sc.scroll_vertical
	Input.emulate_touch_from_mouse = emu0
	_ok("⑧ ★手指按住往上拖 180 px 滚得动(%d → %d), 松手后卡和面板都还开着" % [s_wheel, s_drag],
		DisplayServer.is_touchscreen_available() == emu0 and s_drag >= s_wheel + 100 and _still_open(b, ic, k),
		"拖完 %d" % s_drag)
	## 点一下卡头、点一下正文: 都不关卡、不关面板
	var head := c.find_child("Title", true, false) as Control
	for tp in [head.get_global_rect().get_center() if head != null else cr.position + Vector2(40, 20), vis.get_center()]:
		_push_btn(tp, MOUSE_BUTTON_LEFT, true)
		await get_tree().process_frame
		_push_btn(tp, MOUSE_BUTTON_LEFT, false)
		await _frames(2)
	_ok("⑧ ★点卡头 / 点正文: 卡和面板都还开着", head != null and _still_open(b, ic, k))
	## 反面: 同样的点法点在战场空白(卡左边) ⇒ 面板和卡都关了
	var blank := Vector2(cr.position.x * 0.5, (sr.position.y + 50.0) * 0.5)
	_push_btn(blank, MOUSE_BUTTON_LEFT, true)
	await get_tree().process_frame
	_push_btn(blank, MOUSE_BUTTON_LEFT, false)
	await _frames(3)
	_ok("⑧ 反面: 同样的点法点战场空白 %s ⇒ 面板和卡都关了(点按真的送到了战斗场)" % str(blank),
		(b._info_panel == null or not is_instance_valid(b._info_panel)) and (ic.card == null or not is_instance_valid(ic.card)))
	ic.close()
	await get_tree().process_frame


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
