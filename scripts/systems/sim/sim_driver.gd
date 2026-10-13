extends Node
## sim_driver.gd — 模拟玩家「整条流程」驱动(`SIM_DRIVER=1` 才开)。
##
## ══════════════════════════════════════════════════════════════════════
##  用户 2026-10-06:「开 60 个窗口(或者依次)模拟 60 个真实用户打积分赛, 记录不合理的地方,
##   每个界面都要检查」「买装备, 像上周一样, 但这次换不同的龟、不同的技能」「训龟大师也要点」
## ══════════════════════════════════════════════════════════════════════
## 上周 10 个号是人手(op.sh)点的; 用户 10-03 之后 op.sh 抢焦点被禁用 ⇒ 点击只能由游戏自己代。
## 本节点代掉的是**手指**, 不是判断之外的任何东西:
##   · 每一步都走产品自己的入口: 按钮的 `pressed` 信号、或按钮绑定的那个函数
##     (`_go(...)` / `_open_shop()` / `_start_battle_flow()` / `_on_pick_pet()` / `_toggle_skill()` /
##       `_on_select()`+`_on_buy()` / `_on_bench_click()`+`_dl_click()` / 首启教程选择框的按钮)。
##   · 教程引导条**没有按钮**(2026-10-07 重做): 每一步靠玩家的真动作前进, 本节点做的就是那个动作,
##     引导条自己从产品代码里收到事件。★绝不按「跳过教程」(除非 SIM_TUTORIAL=skip 在首启框里选了跳过)。
##   · **不写**任何经济/战斗字段: 钱、命、场次、装备全由产品函数自己改。
##   · 摆位屏「开打」仍由 `autopilot.gd` 按(`SIM_AUTOPILOT=1`), 本文件不碰战斗。
##
## ★默认彻底关掉: 不带 `SIM_DRIVER` 时 `attach()` 第一行 return, 不建节点。
## ★挂在 GameState(autoload)下面, 换场景不丢 —— 入口是 `sim_shot.gd::attach`(GameState._ready 那一行)。
##
## ── 环境变量 ──
##   SIM_SLOT=N           槽位号(1..60), 决定龟/招/买法/大师(见 sim_roster.gd)
##   SIM_SEED=N           买装备的随机种子(默认 = 槽位号 × 7919)
##   SIM_ROUNDS=N         本进程最多开几局积分赛(不含教学); 空/0 = 打到被拦(配额满/没命)为止
##   SIM_QUIT_WHEN_DONE=1 打完(被拦或到局数)自己退出 —— 分批跑时下一批靠它腾位置
##   SIM_TOUR=0           不走「每个界面逛一遍」(默认第一次进主菜单且已打过 ≥1 局时逛一次)
##   SIM_ACCOUNT_ONLY=1   只建号: 等到拿到 account_id(已写盘)就截一张主菜单、记一行事件、退出 —— 什么都不点。
##                        (2026-10-06 用户「下一周…准备大概120个选手」: 这周先把号建好, 下周再打。
##                         sim60.sh 起这种窗口时同时带 ONBOARD=0, 让主菜单不跳进教学 —— 教学留到下周正式打时走。)
##   SIM_SHOT_DIR         命名截图落在这里(与 sim_shot 的 latest.png 同目录); 没给就 user://sim_shots
##   SIM_TUTORIAL=play|skip  首启选择框按哪颗(默认 play = 「开始教程」, 与真新玩家一样走一遍教程;
##                        skip = 「跳过」)。没弹框(ONBOARD=0 / 已看过教程)时不起作用。
##
## ── 产物 ──
##   user://sim_events.jsonl   每件事一行(时间 / 类型 / 数据) —— 台账的原始依据
##   <SHOT_DIR>/<UTC时刻>_<名字>.jpg

const ENV := "SIM_DRIVER"
const _Roster := preload("res://scripts/systems/sim/sim_roster.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

const S_MENU := "res://scenes/MainMenu.tscn"
const S_TEAM := "res://scenes/TeamSelect.tscn"
const S_MATCH := "res://scenes/Matchmaking.tscn"
const S_BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const S_SHOP := "res://scenes/Shop.tscn"
const _TS := preload("res://scripts/gamedata/turtle_stats.gd")
const _EQS := preload("res://scripts/gamedata/equip_stats.gd")
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")
const _AXE := preload("res://scripts/gamedata/axe_evolution.gd")
const S_INV := "res://scenes/Inventory.tscn"
const S_CODEX := "res://scenes/Codex.tscn"
const S_LB := "res://scenes/Leaderboard.tscn"
const S_REC := "res://scenes/Record.tscn"
const S_SET := "res://scenes/Settings.tscn"
const S_TRAINER := "res://scenes/TrainerConfig.tscn"

## 某一屏停留超过这么多秒没换场景 ⇒ 记一条 STUCK(只记一次)。战斗 3 路 + 决胜, 给足。
const STUCK_SEC := {S_BATTLE: 600.0, S_MATCH: 45.0}
const STUCK_DEFAULT := 120.0

const TRAINER_SKILLS := ["magic_stone", "hook", "fury_potion", "whistle", "glacier", "hunt_order", "tame"]
const TOUR_FLAG := "user://sim_tour_done.txt"
const EV_PATH := "user://sim_events.jsonl"


static func enabled() -> bool:
	return OS.get_environment(ENV).strip_edges() != ""


static func attach(host: Node) -> Node:
	if not enabled():
		return null
	## 时钟偏移要在主菜单 _ready 之前就生效(本节点是延迟挂的, 它自己的 _ready 晚于主菜单)
	if OS.get_environment("SIM_CLOCK_OFFSET") != "":
		load("res://scripts/gamedata/phase2_config.gd").now_override_ts = int(Time.get_unix_time_from_system()) + int(OS.get_environment("SIM_CLOCK_OFFSET"))
	var d = load("res://scripts/systems/sim/sim_driver.gd").new()
	d.name = "SimDriver"
	host.add_child.call_deferred(d)
	return d


var _slot := 0
var _roster: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _rounds_cap := 0
var _rounds_started := 0
var _done := false
var _shot_dir := ""
var _scene_path := ""
var _scene_since := 0
var _stuck_noted := false
var _battle_n := 0          # 本进程看到的结算屏次数
var _shop_visits := 0
var _formed_season := -1      # 本进程里已经排过阵的大轮号(每个大轮排一次)
var _econ_only := OS.get_environment("SIM_ECON_ONLY") == "1"   # 离线经济推演(见 _do_menu)
var _acted_id := 0         # 已经处理过的场景实例(同一屏只做一次主动作, 防连点)


## 时钟偏移(2026-10-12 周日统一结算实跑): `SIM_CLOCK_OFFSET=秒` ⇒ 每帧把赛程钟钉在「真实时间 + 偏移」。
##   不走开发包的时间穿越 —— 那条会拦下一切写请求(结果报不上去); 服务端照常用真实时间, 与真实周日同一种关系。
##   不设 = 0 = 什么都不做。
var _clk_off: int = 0


func _process(_dt: float) -> void:
	if _clk_off != 0:
		load("res://scripts/gamedata/phase2_config.gd").now_override_ts = int(Time.get_unix_time_from_system()) + _clk_off


func _ready() -> void:
	_clk_off = int(OS.get_environment("SIM_CLOCK_OFFSET")) if OS.get_environment("SIM_CLOCK_OFFSET") != "" else 0
	if _clk_off != 0:
		load("res://scripts/gamedata/phase2_config.gd").now_override_ts = int(Time.get_unix_time_from_system()) + _clk_off
	process_mode = Node.PROCESS_MODE_ALWAYS
	_slot = maxi(1, int(OS.get_environment("SIM_SLOT"))) if OS.get_environment("SIM_SLOT") != "" else 1
	var sd := OS.get_environment("SIM_SEED")
	_rng.seed = int(sd) if sd != "" else _slot * 7919
	_rounds_cap = int(OS.get_environment("SIM_ROUNDS")) if OS.get_environment("SIM_ROUNDS") != "" else 0
	_shot_dir = OS.get_environment("SIM_SHOT_DIR").strip_edges()
	if _shot_dir == "":
		_shot_dir = OS.get_user_data_dir().path_join("sim_shots")
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	## ★不抢焦点: 窗口不接受激活(用户 2026-10-03「不要干涉我用的那个屏」)。
	##   点击全由本节点走信号/函数, 不需要窗口拿焦点。
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_ev("start", {"slot": _slot, "seed": _rng.seed, "rounds_cap": _rounds_cap,
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"user_dir": OS.get_user_data_dir()})
	_run()


# ═══════════════════════════════ 主循环 ═══════════════════════════════

func _run() -> void:
	## 等 DataRegistry / GameState 读完档
	await _sleep(2.0)
	_roster = _Roster.for_slot(_slot, DataRegistry.all_pets)
	_ev("roster", _roster)
	if OS.get_environment("SIM_ACCOUNT_ONLY").strip_edges() != "":
		await _account_only()
		return
	while is_inside_tree():
		await _sleep(0.5)
		var sc := get_tree().current_scene
		if sc == null:
			continue
		var p := sc.scene_file_path
		if p != _scene_path:
			_ev("scene", {"from": _scene_path, "to": p, "stayed_s": _since()})
			_scene_path = p
			_scene_since = Time.get_ticks_msec()
			_stuck_noted = false
		elif not _stuck_noted and _since() > float(STUCK_SEC.get(p, STUCK_DEFAULT)) and not (_done and p == S_MENU):
			_stuck_noted = true
			_ev("STUCK", {"scene": p, "stayed_s": _since()})
			_shot("STUCK_" + p.get_file().get_basename())
		_drain_guides()
		sc = get_tree().current_scene
		if sc == null or sc.scene_file_path != p or sc.get_instance_id() == _acted_id:
			continue
		match p:
			S_MENU: await _do_menu(sc)
			S_TEAM: await _do_team(sc)
			S_MATCH: await _do_match(sc)
			S_BATTLE: await _do_battle(sc)
			S_SHOP: await _do_shop(sc)
			S_INV: await _do_inventory(sc)
			S_CODEX: await _do_codex(sc)
			S_LB, S_REC, S_SET, S_TRAINER:
				## 不在巡游里却停在这几屏(比如手动点进来的)⇒ 回主菜单
				if _since() > 8.0:
					_acted_id = sc.get_instance_id()
					await _back_to_menu(sc)


# ═══════════════════════════════ 只建号 ═══════════════════════════════

## 等主菜单 `_ready` 里那句 `ensure_signed_in_async()` 把号建出来。
## ★`supabase._store_session` 拿到令牌就 `gs.save()` ⇒ account_id 非空时存档里也有了;
##   再多等 2 秒才退, 给写盘留余量。拿不到(被限流 / 没网)也退, 事件里记 ok=false, 下一批补。
func _account_only() -> void:
	var until := Time.get_ticks_msec() + 120000
	while is_inside_tree() and str(GameState.account_id) == "" and Time.get_ticks_msec() < until:
		await _sleep(1.0)
	var ok := str(GameState.account_id) != ""
	await _sleep(2.0)
	_shot("account_menu")
	_ev("account", {"ok": ok, "account": str(GameState.account_id), "waited_s": _since_start(),
		"version": str(ProjectSettings.get_setting("application/config/version", ""))})
	await _sleep(1.0)
	get_tree().quit()


var _start_ms := Time.get_ticks_msec()
func _since_start() -> float:
	return (Time.get_ticks_msec() - _start_ms) / 1000.0


# ═══════════════════════════════ 主菜单 ═══════════════════════════════

func _do_menu(m: Node) -> void:
	if _done:
		return
	if bool(GameState.tutorial_active):
		return          # 教学中途回到主菜单(不该发生) ⇒ 让 STUCK 去记
	await _sleep(1.5)   # 主菜单 _ready 自己 await 两帧 + 入场动画
	if not _alive(m):
		return
	## ★首启教程选择框(onboarded=false 的号): 像真新玩家一样先在框里选。
	##   不设 _acted_id —— 选「跳过」后还停在这一屏, 下一拍要接着开打。
	if _press_tutorial_choice(m):
		await _sleep(1.0)
		return
	_acted_id = m.get_instance_id()
	## ★周日决赛日: 对阵图的自动驾驶(SimFinalsPilot)判定「本轮备战窗开着、还没买」才回到这里 ⇒ 进商店按自己的打法买、整理背包。
	##   其余时候主菜单交给它(停 3 秒自动进对阵图), 驱动不 _finish —— 周日要一轮一轮打下去(用户 2026-10-12「周日也要跑」)。
	if _P2.phase_at_utc(int(_P2.now_utc())) == _P2.PHASE_FINALS:
		if SimFinalsPilot.shop_pending:
			SimFinalsPilot.shop_pending = false
			_ev("finals_shop", {"key": SimFinalsPilot.shopped_key, "stats": _stats()})
			m.call("_open_shop")
		return
	var block := str(m.call("_battle_block_msg"))
	var played := int(GameState.season_total_battles)
	if _tour_wanted() and (played >= 1 or block != ""):
		await _tour(m)
		return          # 巡游结束时停在主菜单上(新实例) ⇒ 下一拍再决定开不开打
	if block != "":
		_ev("blocked", {"msg": block, "stats": _stats()})
		_shot("menu_blocked")
		_finish("blocked")
		return
	if _rounds_cap > 0 and _rounds_started >= _rounds_cap:
		_ev("rounds_cap", {"n": _rounds_started})
		_shot("menu_rounds_cap")
		_finish("rounds_cap")
		return
	_rounds_started += 1
	## ★SIM_ECON_ONLY=1(只给离线推演用, 用户 2026-10-12「检查加入给一个账号16轮的深海币量，看看几个机器人怎么买」):
	##   第 1 场照常真打(要走选龟 / 锁阵容), 之后不打, 按真实结算公式记一场(RealtimeBattle3DScene 积分赛分支同一条式子),
	##   直接进商店 → 背包。胜负固定: 每第 3 场输(16 场 = 5 负 11 胜, 刚好不出局)。
	if _econ_only and _rounds_started > 1:
		var won := _rounds_started % 3 != 0
		if not won:
			GameState.lose_heart()
		var lost_hearts: int = maxi(0, int(_P2.HEARTS_MAX) - int(GameState.hearts))
		var reward: int = 8 + int(GameState.hearts) + 2 * lost_hearts + (6 if won else 0)
		GameState.meta_deepsea_coins += reward
		GameState.season_total_battles += 1
		GameState.add_season_xp(2)
		if won:
			GameState.season_wins += 1
		GameState.save()
		_ev("econ_settle", {"n": _rounds_started, "won": won, "reward": reward, "stats": _stats()})
		m.call("_open_shop")
		return
	_ev("start_battle", {"n": _rounds_started, "stats": _stats()})
	m.call("_start_battle_flow")


## 主菜单上弹着教程选择框 ⇒ 按 SIM_TUTORIAL 选一颗(默认 play =「开始教程」), 返回 true。
## ★只在选择框(节点 TutorialChoice)里找按钮 —— 教程外壳上也有一颗同名的「跳过教程」(SkipTutorial),
##   驱动绝不能去按那一颗(门禁 verify_tutorial_choice ⑧ 量这条)。
func _press_tutorial_choice(m: Node) -> bool:
	var choice := m.get_node_or_null("TutorialChoice")
	if choice == null:
		return false
	var want := OS.get_environment("SIM_TUTORIAL").strip_edges()
	var bname := "SkipTutorial" if want == "skip" else "StartTutorial"
	var b := choice.find_child(bname, true, false) as Button
	_shot("menu_tutorial_choice")
	_ev("tutorial_choice", {"press": bname, "text": b.text if b != null else ""})
	if b == null:
		_ev("ANOMALY", {"where": "menu", "what": "首启选择框里找不到按钮", "want": bname})
		return true
	b.emit_signal("pressed")
	return true


func _finish(why: String) -> void:
	_done = true
	_ev("done", {"why": why, "stats": _stats()})
	if OS.get_environment("SIM_QUIT_WHEN_DONE").strip_edges() != "":
		await _sleep(3.0)
		get_tree().quit()


# ═══════════════════════════════ 选龟 ═══════════════════════════════

func _do_team(t: Node) -> void:
	await _sleep(1.2)
	if not _alive(t):
		return
	_acted_id = t.get_instance_id()
	var tut := bool(GameState.tutorial_active)
	var locked := bool(t.get("_roster_locked"))
	var want: Array = []
	if tut:
		var td = get_node_or_null("/root/TutorialDirector")
		want = Array(td.FIXED_TEAM) if td != null else []
	else:
		want = _roster.get("pets", [])
	if not locked:
		t.call("_on_clear_all")
		for pid in want:
			await _sleep(0.4)
			if not _alive(t):
				return
			t.call("_on_pick_pet", str(pid))
	## 招式(锁定后也能换招 ——「这一轮的三只龟定了 · 还能换招」)
	if not tut:
		var sp = t.get("_skill_picker")
		var skills: Array = _roster.get("skills", [])
		var leaders: Array = Array(GameState.season_leaders) if locked else want
		for i in range(mini(leaders.size(), skills.size())):
			var pid := str(leaders[i])
			var k: int = (_roster.get("pets", []) as Array).find(pid)
			if k < 0:
				continue    # 锁定的阵容不是本槽位那三只(老存档) ⇒ 不乱改
			await _sleep(0.3)
			if not _alive(t):
				return
			t.call("_set_detail_pet", pid)
			sp.call("_toggle_skill", pid, int(skills[k]))
	_drain_guides()
	await _sleep(0.6)
	if not _alive(t):
		return
	var team_now: Array = t.get("team")
	_ev("team", {"tutorial": tut, "locked": locked, "team": team_now,
		"loadouts": GameState.loadouts.duplicate(true), "start_text": str((t.get("_start_btn") as Button).text)})
	if tut or int(GameState.season_total_battles) == 0:
		_shot("team_" + ("tut" if tut else "ranked_first"))
	var sb := t.get("_start_btn") as Button
	if sb == null or sb.disabled:
		_ev("ANOMALY", {"where": "team", "what": "开打钮不可点", "team": team_now})
		_shot("ANOMALY_team_start_disabled")
		return
	sb.emit_signal("pressed")


# ═══════════════════════════════ 匹配卡 ═══════════════════════════════

## 匹配屏自己 2.2 + 2.6 秒后换场(MatchmakingScene._ready), 这里只截一张「对手卡」——
## 用户 10-04「不能让玩家知道是机器人」⇒ 每一局的对手卡都要留证。
func _do_match(mm: Node) -> void:
	_acted_id = mm.get_instance_id()
	await _sleep(3.2)
	if _alive(mm):
		_shot("match_%02d" % (int(GameState.season_total_battles) + 1))


# ═══════════════════════════════ 战斗 / 结算 ═══════════════════════════════

func _do_battle(b: Node) -> void:
	_acted_id = b.get_instance_id()
	var g: Dictionary = GameState.dual_ghost if GameState.dual_ghost is Dictionary else {}
	var prof: Dictionary = g.get("profile", {}) if g.get("profile") is Dictionary else {}
	_ev("battle_enter", {"tutorial": bool(GameState.tutorial_active),
		"opp_name": str(prof.get("name", "")), "opp_id": str(prof.get("id", "")),
		"opp_ghost": str(g.get("ghost_id", "")), "opp_is_bot": bool(g.get("is_bot", false)),
		"opp_battles": g.get("season_total_battles", null), "opp_leaders": g.get("leaders", []),
		"my_battles": int(GameState.season_total_battles), "week_phase": str(GameState.week_phase)})
	var t0 := Time.get_ticks_msec()
	var settle: Node = null
	while _alive(b):
		var hud = b.get("_hud")
		if hud != null:
			var s = hud.get("_settle")
			if is_instance_valid(s) and s is Node and (s as Node).is_inside_tree():
				settle = s
				break
		if not _stuck_noted and (Time.get_ticks_msec() - t0) / 1000.0 > float(STUCK_SEC[S_BATTLE]):
			_stuck_noted = true
			_ev("STUCK", {"scene": S_BATTLE, "stayed_s": (Time.get_ticks_msec() - t0) / 1000.0,
				"dl_state": str(b.get("_dl_state"))})
			_shot("STUCK_battle")
		await _sleep(1.0)
		_drain_guides()
	if settle == null:
		return
	_battle_n += 1
	await _sleep(2.5)       # 结算屏入场 + 数字滚完
	if not _alive(b) or not is_instance_valid(settle):
		return
	var tut := bool(GameState.tutorial_active)
	_ev("result", {"n": _battle_n, "tutorial": tut, "secs": (Time.get_ticks_msec() - t0) / 1000.0,
		"settle_kind": str(b.get("_last_settle_kind")), "stats": _stats()})
	var tag := "b%02d" % _battle_n
	_shot(tag + "_result")
	if _battle_n <= 2 or (not tut and int(GameState.season_total_battles) <= 1):
		var tabs: Array = settle.get("tab_btns")
		for i in range(1, tabs.size()):
			(tabs[i] as Button).emit_signal("pressed")
			await _sleep(0.8)
			if not _alive(b):
				return
			_shot("%s_result_p%d" % [tag, i + 1])
		if tabs.size() > 0:
			(tabs[0] as Button).emit_signal("pressed")
	var row = settle.get("btn_row")
	var pick: Button = null
	var names: Array = []
	if row is Node:
		for c in (row as Node).get_children():
			if c is Button:
				names.append((c as Button).text)
				var tx := (c as Button).text
				if pick == null and (tx == "前往商店" or tx == "继续" or tx == "完成新手教学"):
					pick = c
		if pick == null:
			for c in (row as Node).get_children():
				if c is Button and (c as Button).text == "返回主菜单":
					pick = c
	_ev("result_buttons", {"buttons": names, "press": pick.text if pick != null else ""})
	if pick == null:
		_ev("ANOMALY", {"where": "result", "what": "结算屏没有可按的按钮", "buttons": names})
		_shot("ANOMALY_result_no_button")
		return
	await _sleep(1.0)
	if _alive(b) and is_instance_valid(pick):
		pick.emit_signal("pressed")


# ═══════════════════════════════ 商店 ═══════════════════════════════

func _do_shop(s: Node) -> void:
	await _sleep(1.5)
	if not _alive(s):
		return
	_acted_id = s.get_instance_id()
	_shop_visits += 1
	var tut := bool(GameState.tutorial_active)
	if _shop_visits <= 2:
		_shot("shop_%02d" % _shop_visits)
	var style := _strategy()
	var bought: Array = []
	var xp_n := 0
	var refreshes := 0
	var coins0 := int(GameState.meta_deepsea_coins)
	var lv0 := int(GameState.season_level)
	## ★教程「购买经验，升到 2 级」: 按产品那颗买经验钮(它的回调会发 level_up 给引导条)。
	if tut:
		var xb = s.get("_tut_xp_btn")
		if is_instance_valid(xb) and xb is Button:
			(xb as Button).emit_signal("pressed")
			xp_n += 1
			await _sleep(0.8)
			if not _alive(s):
				return
	## 小木斧攒满 ⇒ 最终进化四选一(按槽位挑一个; 走商店面板那颗按钮的同一个回调)
	if not tut and _AXE.final_ready(int(GameState.axe_exp_bar), int(GameState.axe_stage), str(GameState.axe_final)):
		var fk: String = str((_AXE.FINALS[_slot % _AXE.FINALS.size()] as Dictionary)["key"])
		s.get("_axe_panel").call("_pick", fk)
		_ev("axe_final", {"pick": fk, "ok": str(GameState.axe_final) == fk})
		await _sleep(0.5)
		if not _alive(s):
			return
	## ① 先把等级升到本策略此刻的目标(留出本策略的底钱)
	var fast_mid: bool = style == 2 and int(GameState.season_level) >= 8 and int(GameState.season_level) < _P2.MAX_LEVEL
	var fast_rolls: int = _rng.randi_range(0, 4)
	var fast_new_high := 0
	## 速升: 升级前先把货架上「已有同款」的钱留出来 —— 原来钱几乎全进升级, 一场只买得起 0~2 件, 一路全是 ★1
	var dup_hold := _dup_budget(s) if style == 2 else 0
	if not tut and not fast_mid:      # 速升 8~9 级: 先看货架有没有 4~5 费 / 能合的, 剩下的钱才升级(见 ③)
		while int(GameState.season_level) < _target_level() \
				and int(GameState.meta_deepsea_coins) >= _P2.BUY_XP_COST + _reserve() + dup_hold and xp_n < 8:
			if not _buy_xp(s):
				break
			xp_n += 1
			await _sleep(0.3)
			if not _alive(s):
				return
	## ② 买: 每一步挑分最高的一件; 没有「同款 / 合星」可买时按策略刷新去找
	var refresh_cap: int = [30, 2, 25 if _rolling_down() else 2][style]
	## 追三星的号: 没到目标等级前不狂刷(先升到位再刷 = 真人的 slow roll), 只刷 1 次
	if style == 0 and int(GameState.season_level) < _target_level():
		refresh_cap = 1
	for _step in range(40):
		if not _alive(s):
			return
		var offer: Array = s.get("_offer")
		var best_i := -1
		var best_score := -1.0
		for i in range(offer.size()):
			if offer[i] == null:
				continue
			var d: Dictionary = s.call("_deco", offer[i])
			if int(s.call("_price", d)) > int(GameState.meta_deepsea_coins):
				continue
			var sc := _offer_score(s, d, tut)
			if sc > best_score:
				best_score = sc
				best_i = i
		var want_refresh := not tut and best_score < 300.0 and refreshes < refresh_cap \
				and int(GameState.meta_deepsea_coins) >= 2 + _refresh_floor()
		if style == 2 and int(GameState.season_level) < 7:
			want_refresh = want_refresh and best_score < 0.0     # 速升: 低等级不刷, 钱留着升级
		if fast_mid:
			## 用户「允许每轮刷0到4次随机这样子吧」: 每次进店随机定 0~4 次, 找 4~5 费或同款; 留够买一件的钱
			want_refresh = not tut and best_score < 400.0 and refreshes < fast_rolls \
				and int(GameState.meta_deepsea_coins) >= 2 + 3
		if style == 2 and _rolling_down():
			want_refresh = not tut and best_score < 300.0 and refreshes < refresh_cap 				and int(GameState.meta_deepsea_coins) >= 2 + 4     # 8 级大刷: 找 4~5 费, 留够买一件 4 费的钱
		if want_refresh and (best_score < 0.0 or style == 0 or _owned_gear_n() >= 3):
			refreshes += 1
			s.call("_on_refresh")
			_ev("shop_refresh", {"coins": int(GameState.meta_deepsea_coins), "best": best_score})
			await _sleep(0.5)
			continue
		if best_i < 0 or best_score < 0.0:
			break
		if fast_mid and best_score < 400.0:
			break                                               # 速升 8~9 级: 只顺手拿 4~5 费 / 合星的, 别的钱留着升级
		## ★16 场推演(10-12 第二版): 8 级后每场买 5~7 件新 4~5 费、升级 0 次, 停在 8 级 + 24 件 ★1 卖不完
		##   ⇒ 新的 4~5 费每次进店最多 1 件, 其余钱全进升级(冲 10 级)。同款 / 合星不受限。
		if fast_mid and best_score >= 576.0 and best_score < 1000.0 and fast_new_high >= 1 \
				and int(s.call("_owned_count", str((s.call("_deco", offer[best_i]) as Dictionary).get("id", "")), 1)) == 0:
			break
		var eid := str((s.call("_deco", offer[best_i]) as Dictionary).get("id", ""))
		s.call("_on_select", best_i)      # 两步购买: 点卡选中 → 面板里点「买下」
		await _sleep(0.4)
		if not _alive(s):
			return
		var c_before := int(GameState.meta_deepsea_coins)
		var n_before := GameState.persistent_bench.size()
		s.call("_on_buy", best_i)
		bought.append({"id": eid, "paid": c_before - int(GameState.meta_deepsea_coins), "score": int(best_score)})
		if fast_mid and _cost_of(eid) >= 4 and best_score >= 576.0 and best_score < 1000.0:
			fast_new_high += 1
		await _sleep(0.4)
		if tut and bought.size() >= 1:
			break
		if c_before == int(GameState.meta_deepsea_coins) and n_before == GameState.persistent_bench.size():
			break                                               # 产品没收这笔(背包满等), 别死循环
	## ③ 剩下的钱: 速升 / 均衡 拿去买经验(留底钱); 追三星的号不升, 钱留到下一轮刷新
	if not tut and style != 0:
		while _alive(s) and int(GameState.season_level) < _P2.MAX_LEVEL \
				and int(GameState.meta_deepsea_coins) >= _P2.BUY_XP_COST + _reserve() and xp_n < 10 \
				and not _rolling_down():
			if not _buy_xp(s):
				break
			xp_n += 1
			await _sleep(0.3)
	_ev("shop", {"visit": _shop_visits, "tutorial": tut, "style": style, "strategy": STRAT_NAMES[style],
		"coins_before": coins0, "coins_after": int(GameState.meta_deepsea_coins), "bought": bought,
		"refreshes": refreshes, "xp_buys": xp_n, "axe": [int(GameState.axe_stage), int(GameState.axe_exp_bar), str(GameState.axe_final)], "stars": _star_hist(), "battles": int(GameState.season_total_battles),
		"level": [lv0, int(GameState.season_level)], "bench_n": GameState.persistent_bench.size()})
	await _sleep(0.8)
	if not _alive(s):
		return
	if _shop_visits <= 2:
		_shot("shop_%02d_after" % _shop_visits)
	## 顶栏「🎒 背包」那颗钮绑的就是这一句(ShopScene.gd TopBar left_actions → _go_inventory;
	##   教程里它先报「点击背包」那一步, 再走导演推进)。
	s.call("_go_inventory")


# ═══════════════════════ 购物策略(2026-10-12 用户「别搞蠢ai」) ═══════════════════════
## 用户原话:「装备的话不止二星啊，最高是3星，策略得知道啥时候买3星，什么时候先升等级去找高费装备，
##   你可以想想不同的策略，但千万别搞蠢ai」。方案书 docs/plans/20261012-模拟号购物策略.md。
## 三种打法(槽位 mod 3; p01..p120 各 40 个):
##   0 低费追三星: 停在 Lv5(全队 8 件位)狂刷, 把 1~2 费的同款凑到 ★3; 有 2 件 ★3 或打满 9 场后再往上升。
##   1 均衡:       等级跟真人中位(bot 表 +1), 先凑同款, 没同款刷 2 次, 剩钱升级。
##   2 速升找高费: 早升到 Lv7(第 5 场前后), 买当前能买到的最高费; Lv7 起才刷新去找 4~5 费并凑 ★2。
## 共同规矩: 能合出 ★3 / ★2 的那一件永远先买; 追合成的件装统领(小将身上的不进合成池);
##   装满后好件换掉差件、背包里落单的低值件卖掉; 攻装给输出、防装给坦克。
const STRAT_NAMES := ["低费追三星", "均衡", "速升找高费"]
const FAST_LV := [1, 3, 4, 5, 6, 7, 7, 8, 8, 8, 9, 9, 9, 10, 10, 10, 10]


func _strategy() -> int:
	return _slot % 3


func _n_star3() -> int:
	var n := 0
	for it in _all_gear():
		if int(it.get("star", 1)) >= 3:
			n += 1
	return n


## 本策略此刻想到的等级。
func _target_level() -> int:
	var b := int(GameState.season_total_battles)
	## ★用户 2026-10-12:「机器人打完第一把…手里有些钱就应该升一级然后买4件装备…因为3级有4件容量」
	##   ⇒ 追三星 / 均衡: 前两场后只升到 3 级, 剩下的钱买满 4 件位(原来追三星第 1 场就把 16 币砸到 4 级, 只剩钱买 2 件)。
	##   用户「这就是一个策略的例子」⇒ 不是人人都这么开: 速升照自己的激进曲线(第 2 场后就冲 4 级)。
	if b <= 2 and _strategy() != 2:
		return 3
	match _strategy():
		0:
			if b <= 4:
				return 4
			if _n_star3() >= 2 or b >= 13:
				return 8 if b >= 13 else 7
			return 7 if b >= 9 else 5
		1:
			return clampi(_P2.bot_level_for_battles(b), 1, _P2.MAX_LEVEL)   # 真人中位(396 条真人快照量出来的那条曲线)
		_:
			return int(FAST_LV[clampi(b, 0, FAST_LV.size() - 1)])   # 一路冲 10 级(用户「得到10级才能追」)


## 升级时留的底钱。
func _reserve() -> int:
	return [4, 4, 2][_strategy()]   # 本游戏存钱没有利息 ⇒ 不压钱(16 场推演: 均衡每场压着 12~15 币)


## 刷新时至少留着能买一件的钱。
func _refresh_floor() -> int:
	return [1, 3, 3][_strategy()]


func _cost_of(eid: String) -> int:
	return maxi(1, int((DataRegistry.phase2_equipment_by_id.get(eid, {}) as Dictionary).get("cost", 1)))


## 一件装备的「份量」= 费 × 3^(星-1)(与卖出退池的份数同一口径)。换装 / 卖件都按它比。
func _gear_val(it: Dictionary) -> float:
	return float(_cost_of(str(it.get("id", "")))) * pow(3.0, float(maxi(1, int(it.get("star", 1))) - 1))


## 商店里一件货的分。<0 = 不买。
func _offer_score(s: Node, d: Dictionary, tut: bool) -> float:
	var eid := str(d.get("id", ""))
	var cost := _cost_of(eid)
	if tut:
		return float(cost)
	## 小木斧只能有一把; 已有再买 = 整笔化成 +20 砍伐经验(ShopScene._on_buy)。想养斧的号见斧就买, 进化到最终造物为止。
	if eid == "p2eq_096" and GameState.axe_owned():
		return 450.0 if _wants_one_piece(eid) and str(GameState.axe_final) == "" else -1.0
	var own1 := int(s.call("_owned_count", eid, 1))
	var own2 := int(s.call("_owned_count", eid, 2))
	var style := _strategy()
	## 速升到 8 级: 花了约 176 币升级换的是 4~5 费的出货率(8 级 4 费 17% / 5 费 9%), 回头合低费 ★2 等于这笔钱白花,
	##   而且三种打法会变成一种(用户问「到8级后仍优先买低费同款…有什么问题吗」)。面板中位: 1 费★2 21 ≈ 4 费★1 18,
	##   但上限 4 费★2 35 / 5 费★2 90 / 4 费★3 100 只有走高费拿得到。
	## 顺序: 合出 ★3(1000) > 合出 4~5 费 ★2(640~650) > 新 5 费(600) > 4~5 费同款第 2 件(540~550) > 新 4 费(560 不到 5 费) > 低费同款(140~160)
	if style == 2 and int(GameState.season_level) >= 8:
		if own2 >= 2 and own1 >= 2:
			return 1000.0 + cost
		if own1 >= 2:
			return 600.0 + cost * 10 if cost >= 4 else 400.0 + cost * 10
		if cost >= 4:
			if own1 == 1 or own2 >= 1:
				return 500.0 + cost * 10
			var room8 := int(GameState.team_equip_cap()) - int(GameState.team_equipped_count()) - _bench_gear_n()
			if room8 <= 0 and (_bench_gear_n() >= 1 or float(cost) < _worst_owned_val() * 1.5):
				return -1.0                                         # 位子满了: 只换掉明显更差的, 不囤
			return 480.0 + cost * 24 + _syn_gain(eid) * 0.5   # 新 4 费 576 / 新 5 费 600
		## 用户「那一到3费不管吗，可以升3星2费呢，遇到了要留吧」⇒ 手里已有的 1~3 费同款照买(往 ★2 / ★3 凑)
		if own1 == 1 or own2 >= 1:
			return 420.0 + cost * 10 + own2 * 50
	if own2 >= 2 and own1 >= 2:
		return 1000.0 + cost                   # 这一买直接合出 ★3
	if own1 >= 2:
		return 600.0 + cost * 10               # 这一买合出 ★2
	if own1 == 1 or own2 >= 1:
		if style == 0 and cost >= 3 and own2 == 0:
			return 150.0 + cost                # 追三星的号: 高费同款排在低费同款后面
		return 300.0 + cost * 10 + own2 * 50 + (20.0 if _is_core(eid) else 0.0)   # 往 ★2 / ★3 走一步
	## 新款: 背包快满 / 装不下又不比身上最差那件好 ⇒ 不买
	if GameState.persistent_bench.size() >= _P2.BENCH_CAP - 2:
		return -1.0
	## 位子已经被(身上 + 背包里待装的)占满: 只有明显更好的(≥ 手里最差那件 1.5 倍)才买, 且背包里最多压 1 件备用
	##   ★10-12 离线首测: 原来拿「身上最差」比, 进店时身上还没装 ⇒ 最差 = 0 ⇒ 什么都过, 2 个位子买了 5 件
	var room := int(GameState.team_equip_cap()) - int(GameState.team_equipped_count()) - _bench_gear_n()
	if room <= 0:
		var w := _worst_owned_val()
		var future_syn := _syn_gain(eid) > 0.0 and _bench_gear_n() < 2     # 为以后的羁绊囤货(用户「或买未来羁绊要用到的装备」)
		if not future_syn and (_bench_gear_n() >= 2 or w <= 0.0 or float(cost) < w * 1.5):
			return -1.0
	var syn := _syn_gain(eid)
	match style:
		0:
			if (cost > 2 and not (syn > 0.0 and cost <= 3)) or _open_singles() >= 3:
				return -1.0
			return 100.0 + (3 - cost) * 5 + syn * 0.6      # 追三星: 走高为主, 羁绊只是加分
		1:
			if _open_singles() >= 5 and syn <= 0.0:
				return -1.0
			return 100.0 + cost * 10 + syn                 # 均衡: 更偏走宽(凑羁绊)
		_:
			var lvn := int(GameState.season_level)
			var min_cost := 1 if lvn < 5 else (2 if lvn < 7 else (3 if lvn < 8 else 4))
			if syn > 0.0:
				min_cost -= 1                               # 对口羁绊的件放宽一档费
			if cost < min_cost:
				return -1.0
			return 100.0 + cost * 20 + syn * 0.8
	return -1.0


## 手里(身上 + 背包)最差那件的份量。一件都没有 = 0。
func _worst_owned_val() -> float:
	var w := INF
	for e in _equipped_list():
		w = minf(w, _gear_val(e["it"]))
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("kind", "")) != "item":
			w = minf(w, _gear_val(it))
	return 0.0 if w == INF else w


## 全队身上的装备: [{it, kind, pid / lane+idx, cell}]。羁绊赠送件不算(不能卸不能卖)。
func _equipped_list() -> Array:
	var out: Array = []
	var dl: Dictionary = GameState.get_dual_lineup()
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			var u = arr[i]
			if not (u is Dictionary):
				continue
			var eqs: Array = []
			if str(u.get("kind", "")) == "leader":
				eqs = GameState.persistent_equipped.get(str(u.get("id", "")), [])
			else:
				eqs = u.get("equips", []) if u.get("equips", null) is Array else []
			for c in range(eqs.size()):
				var it = eqs[c]
				if it is Dictionary and not GameState.is_synergy_grant(it):
					out.append({"it": it, "kind": str(u.get("kind", "")), "pid": str(u.get("id", "")),
						"lane": lane, "idx": i, "cell": c})
	return out


# ═══════════════════════ 羁绊(2026-10-12 用户「有考虑羁绊吗」) ═══════════════════════
## 规则(phase2_types.gd): 每件装备一个类型; 身上装的、按 id 去重的同类型件数到阈值即激活(3/6/9 或 2/5/8/10)。
## 「走宽(凑羁绊) 与 走高(合 3★) 互斥」是设计本意(同一件带两件只算 1)⇒ 三种打法各有偏重:
##   追三星偏走高(羁绊 ×0.6) / 均衡偏走宽(×1.0) / 速升找高费 ×0.8。
## 每个号定一个主羁绊 + 一个副羁绊:
##   主: 按三只统领的多数定位 —— 物理输出(刺客 / 射手 / 斗士)→ 剑 / 枪 / 弓箭; 法师 → 法器 / 药水;
##       坦克 → 盾 / 奇械; 辅助 → 药水 / 食物; 同一类里按槽位错开。
##   副: 灵物 / 遗物 / 奇械 / 法器(2 件就激活的那几类)里按槽位挑一个, 不与主相同。
var _core_cache: Array = []
var _core_season := -1


func _core_types() -> Array:
	if int(GameState.season_id) == _core_season and not _core_cache.is_empty():
		return _core_cache
	var votes := {"dps": 0, "mage": 0, "tank": 0, "sup": 0}
	for pid in GameState.lineup_leader_ids():
		var role := str(_TS.ROLE.get(str(pid), ""))
		if role.contains("坦克"):
			votes["tank"] += 1
		elif role.contains("辅助"):
			votes["sup"] += 1
		elif role.contains("法师"):
			votes["mage"] += 1
		else:
			votes["dps"] += 1
	var top := "dps"
	for k in ["dps", "mage", "tank", "sup"]:
		if int(votes[k]) > int(votes[top]):
			top = k
	var pools := {"dps": ["剑", "枪", "弓箭"], "mage": ["法器", "药水"], "tank": ["盾", "奇械"], "sup": ["药水", "食物"]}
	var prim_list: Array = pools[top]
	var prim: String = prim_list[_slot % prim_list.size()]
	var sec_list: Array = ["灵物", "遗物", "奇械", "法器"].filter(func(x): return x != prim)
	var sec: String = sec_list[(_slot / 3) % sec_list.size()]
	_core_cache = [prim, sec]
	_core_season = int(GameState.season_id)
	return _core_cache


## 香火石(093·香火 1 件激活)与小木斧(096·斧头 1 件激活, 激活后抬高商店出货概率): 谁都值得带 1 件。
const ONE_PIECE_SYN := ["p2eq_093", "p2eq_096"]


## 用户 2026-10-12「不一定每个机器人都要买香火和小木斧, 真人不会这么做的」⇒ 只有部分号想要:
##   用户「太多了，减半吧」⇒ 香火石 槽位 mod 10 ∈ {0,1}(20%) · 小木斧 槽位 mod 8 == 0(12.5%)。其余号把它们当普通货看。
func _wants_one_piece(eid: String) -> bool:
	if eid == "p2eq_093":
		return _slot % 10 <= 1
	if eid == "p2eq_096":
		return _slot % 8 == 0
	return false


func _is_core(eid: String) -> bool:
	if eid in ONE_PIECE_SYN and not _wants_one_piece(eid):
		return false
	if eid in ONE_PIECE_SYN:
		for g in _all_gear():
			if str(g.get("id", "")) == eid:
				return false
		return true
	for ty in _P2T.types_of(eid):
		if str(ty) in _core_types():
			return true
	return false


## 买这件新款对羁绊的分: 不对口 / 已经有同 id = 0; 对口 = 主 60 / 副 35; 再买一件就升档 +40。
func _syn_gain(eid: String) -> float:
	if not _is_core(eid):
		return 0.0
	for g in _all_gear():
		if str(g.get("id", "")) == eid:
			return 0.0
	if eid in ONE_PIECE_SYN:
		return 70.0                          # 买到就激活一档
	var core := _core_types()
	var g := 0.0
	var rows: Array = GameState.synergy_rows()
	for ty in _P2T.types_of(eid):
		var tys := str(ty)
		if not (tys in core):
			continue
		g = maxf(g, 60.0 if tys == str(core[0]) else 35.0)
		for r in rows:
			if str(r["t"]) == tys and int(r["need"]) == 1:
				g += 40.0
		## 还一件都没装: 第一档阈值 2 的那类(副)买第 1 件也算往前一步, 不额外加
	return g


## 换装 / 选装用的「有效份量」: 对口羁绊 ×1.4。
func _eff_val(it: Dictionary) -> float:
	return _gear_val(it) * (1.4 if _is_core(str(it.get("id", ""))) else 1.0)


## 速升打法的「大刷」阶段 = 已到 10 级。
##   ★用户 2026-10-12:「凑出 3 件 4 费以上？这是不可以的概率太低了，得到10级才能追，但期间遇到需要得4费可以去拿」
##   ⇒ 8~9 级不停下刷: 钱先升级, 货架上刚好有 4~5 费 / 能合出 ★2 的才顺手买; 10 级才大刷找高费。
## 货架上「手里已有同款」的那几件一共要多少钱(速升升级前先留出来)。
func _dup_budget(s: Node) -> int:
	var total := 0
	var offer: Array = s.get("_offer")
	for o in offer:
		if o == null:
			continue
		var d: Dictionary = s.call("_deco", o)
		var eid := str(d.get("id", ""))
		if eid == "p2eq_096":
			continue
		if int(s.call("_owned_count", eid, 1)) >= 1 or int(s.call("_owned_count", eid, 2)) >= 1:
			total += int(s.call("_price", d))
	return total


func _rolling_down() -> bool:
	return _strategy() == 2 and int(GameState.season_level) >= _P2.MAX_LEVEL




## 买经验 —— 与商店那颗经验钮的 `pressed` 回调逐字同一段(`GameState.buy_season_xp()` 成功则 `_rebuild()`)。
func _buy_xp(s: Node) -> bool:
	if GameState.buy_season_xp():
		s.call("_rebuild")
		return true
	return false


## 已拥有的装备件数(背包 + 全队已装上)。
func _owned_gear_n() -> int:
	return _all_gear().size()


## 还没凑齐的★1 款数(某 id 的 ★1 只有 1~2 件)。≥4 种时不再开新款, 只追同款 —— 摊太开永远合不出来。
func _open_singles() -> int:
	var c := {}
	for it in _all_gear():
		if int(it.get("star", 1)) == 1:
			var k := str(it.get("id", ""))
			c[k] = int(c.get(k, 0)) + 1
	var n := 0
	for k in c:
		if int(c[k]) % 3 != 0:
			n += 1
	return n


func _all_gear() -> Array:
	var out: Array = []
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("kind", "")) != "item":
			out.append(it)
	for side in GameState.persistent_equipped:
		var v = GameState.persistent_equipped[side]
		if v is Array:
			for it in v:
				if it is Dictionary:
					out.append(it)
		elif v is Dictionary:
			for k in v:
				var arr = v[k]
				if arr is Array:
					for it in arr:
						if it is Dictionary:
							out.append(it)
	return out


## 全部装备的星级分布 {1: n, 2: n, 3: n}(记进 shop 事件, 用来量「是不是全是★1」)。
func _star_hist() -> Dictionary:
	var h := {1: 0, 2: 0, 3: 0}
	var all: Array = []
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("kind", "")) != "item":
			all.append(it)
	for e in _equipped_list():
		all.append(e["it"])
	for it in all:
		var st := int(it.get("star", 1))
		h[st] = int(h.get(st, 0)) + 1
	return h


func _bench_gear_n() -> int:
	var n := 0
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("kind", "")) != "item":
			n += 1
	return n


# ═══════════════════════════════ 背包 ═══════════════════════════════

func _do_inventory(v: Node) -> void:
	await _sleep(1.5)
	if not _alive(v):
		return
	_acted_id = v.get_instance_id()
	var tut := bool(GameState.tutorial_active)
	var equipped: Array = []
	var swaps: Array = []
	var sold: Array = []
	var formed := {}
	if not tut:
		formed = await _arrange_lineup(v)
		if not _alive(v):
			return
	for _k in range(14):
		if not _alive(v):
			return
		## ★10-12 逐场阵容(p11 第 8~10 场 10/12 有空位, 背包里瞄准镜 / 小木斧没装):
		##   原来只看「最好那件」, 它装不上(追合成的件只装统领, 统领满了)就整轮收工 ⇒ 按份量从高到低逐件试。
		var bi := -1
		var tgt := {}
		for cand in _bench_gear_by_value():
			var tt := _equip_target(GameState.persistent_bench[cand])
			if not tt.is_empty():
				bi = cand
				tgt = tt
				break
		if bi < 0:
			break
		var before := GameState.persistent_bench.size()
		v.call("_on_bench_click", bi)          # 点背包里那件(选中)
		await _sleep(0.35)
		if not _alive(v):
			return
		v.call("_dl_click", str(tgt["lane"]), int(tgt["idx"]))   # 点布阵框里那只(装上)
		await _sleep(0.45)
		equipped.append({"to": tgt, "ok": GameState.persistent_bench.size() < before})
		if GameState.persistent_bench.size() >= before:
			## 产品自己飘的那句话(InventoryScene._toast 建的 Label 名叫 "Toast")—— 分清是产品拒了还是驱动点错了
			var toasts: Array = []
			for tl in v.find_children("Toast", "Label", true, false):
				toasts.append((tl as Label).text)
			var lane_now: Array = GameState.get_dual_lineup().get(str(tgt["lane"]), [])
			var unit_now = lane_now[int(tgt["idx"])] if int(tgt["idx"]) < lane_now.size() else {}
			_ev("ANOMALY", {"where": "inventory", "what": "点了装备+点了单位, 背包件数没少", "target": tgt,
				"toast": toasts, "sel_bench": v.get("_sel_bench"), "bench": GameState.persistent_bench.duplicate(true),
				"unit": unit_now, "team": [GameState.team_equipped_count(), GameState.team_equip_cap()]})
			_shot("ANOMALY_inventory_equip")
			break
	## 全队装满后: 背包里最好那件比身上最差那件明显好(份量 ≥1.5 倍)⇒ 卸下差的、装上好的
	if not tut:
		for _w in range(4):
			if not _alive(v):
				return
			var bi := _best_bench_gear()
			if bi < 0 or GameState.team_has_equip_room():
				break
			var best_it: Dictionary = GameState.persistent_bench[bi]
			var worst := _worst_equipped()
			if worst.is_empty() or _eff_val(best_it) < _eff_val(worst["it"]) * 1.5:
				break
			var ops = v.get("_inv_ops")
			if str(worst["kind"]) == "leader":
				ops.call("_unequip_at", str(worst["pid"]), int(worst["cell"]))
			else:
				ops.call("_unequip_minion_at", str(worst["lane"]), int(worst["idx"]), int(worst["cell"]))
			await _sleep(0.35)
			var bi2 := _best_bench_gear()
			var tgt := _equip_target(GameState.persistent_bench[bi2]) if bi2 >= 0 else {}
			if tgt.is_empty():
				break
			v.call("_on_bench_click", bi2)
			await _sleep(0.3)
			v.call("_dl_click", str(tgt["lane"]), int(tgt["idx"]))
			await _sleep(0.4)
			swaps.append({"out": worst["it"], "in": best_it, "to": tgt})
		## 背包快满: 卖掉落单的低值件(不卖正在凑合成的同款)
		for _q in range(6):
			if not _alive(v):
				return
			if GameState.persistent_bench.size() < _P2.BENCH_CAP - 3:
				break
			var si := _junk_bench_idx()
			if si < 0:
				break
			var it: Dictionary = GameState.persistent_bench[si]
			v.call("_on_bench_click", si)
			await _sleep(0.3)
			v.get("_inv_ops").call("_sell_selected")
			await _sleep(0.35)
			sold.append(it)
	_ev("inventory", {"tutorial": tut, "equipped": equipped, "swaps": swaps, "sold": sold, "formation": formed,
		"lineup": _lineup_record(), "battles": int(GameState.season_total_battles), "level": int(GameState.season_level),
		"team_equipped": GameState.team_equipped_count(), "team_cap": GameState.team_equip_cap(),
		"bench_n": GameState.persistent_bench.size(), "stars": _star_hist(), "core": _core_types(),
		"synergy": GameState.synergy_rows().slice(0, 3)})
	if _shop_visits <= 2:
		_shot("inventory_%02d" % _shop_visits)
	await _sleep(0.8)
	if not _alive(v):
		return
	if tut:
		## 教程最后一步「点击完成教程」—— 按产品那颗钮(InventoryScene._build_tut_finish)。
		var fb = v.get("_tut_finish_btn")
		if is_instance_valid(fb) and fb is Button:
			_ev("tutorial_finish", {"label": (fb as Button).text, "guide": _guide_text()})
			(fb as Button).emit_signal("pressed")
		else:
			_ev("ANOMALY", {"where": "inventory", "what": "教程里找不到「完成教程」钮"})
	else:
		get_tree().change_scene_to_file(S_MENU)   # 顶栏返回钮绑的就是这一句


## 本场整理完之后的完整阵容(用户 2026-10-12「每场得装备阵容有记录对吧」):
##   [{lane, pos, kind, id(统领龟 id / 小将), role(小将前后排), gear: ["p2eq_xxx★n", ...]}] + 背包里没装的。
func _lineup_record() -> Dictionary:
	var units: Array = []
	var dl: Dictionary = GameState.get_dual_lineup()
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			var u = arr[i]
			if not (u is Dictionary):
				continue
			var kind := str(u.get("kind", ""))
			var eqs: Array = []
			if kind == "leader":
				eqs = GameState.persistent_equipped.get(str(u.get("id", "")), [])
			else:
				eqs = u.get("equips", []) if u.get("equips", null) is Array else []
			var gear: Array = []
			for it in eqs:
				if it is Dictionary:
					gear.append("%s★%d" % [str(it.get("id", "")), int(it.get("star", 1))])
			units.append({"lane": lane, "pos": i, "kind": kind, "id": str(u.get("id", "")),
				"role": str(u.get("role", "")) if kind == "minion" else "", "gear": gear})
	var bench: Array = []
	for it in GameState.persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("id", "")) != "":
			bench.append("%s★%d" % [str(it.get("id", "")), int(it.get("star", 1))])
	return {"units": units, "bench": bench}

## 背包里的装备按有效份量从高到低的下标(临时等级器不算)。
func _bench_gear_by_value() -> Array:
	var idx: Array = []
	var bench: Array = GameState.persistent_bench
	for i in range(bench.size()):
		var it = bench[i]
		## 羁绊赠送件(圣光护盾 095)由 sync_synergy_grants 管, 装上会被收回背包 ⇒ 不碰(10-13 实跑 3 条 ANOMALY)
		if it is Dictionary and str((it as Dictionary).get("id", "")) != "" and str((it as Dictionary).get("kind", "")) != "item" 				and not GameState.is_synergy_grant(it):
			idx.append(i)
	idx.sort_custom(func(a, b): return _eff_val(bench[a]) > _eff_val(bench[b]))
	return idx


## 背包里最值得装的那件(份量最大; 临时等级器不算)。
func _best_bench_gear() -> int:
	var bench: Array = GameState.persistent_bench
	var best := -1
	var bv := -1.0
	for i in range(bench.size()):
		var it = bench[i]
		if not (it is Dictionary) or str((it as Dictionary).get("id", "")) == "" \
				or str((it as Dictionary).get("kind", "")) == "item" or GameState.is_synergy_grant(it):
			continue
		var val := _eff_val(it)
		if val > bv:
			bv = val
			best = i
	return best


## 身上份量最小的那件。
func _worst_equipped() -> Dictionary:
	var w: Dictionary = {}
	var wv := INF
	for e in _equipped_list():
		var val := _eff_val(e["it"])
		if val < wv:
			wv = val
			w = e
	return w


## 背包里该卖的那件: ★1、手里同款只有这一件、份量最小。没有就 -1。
func _junk_bench_idx() -> int:
	var cnt := {}
	for it in _all_gear():
		var k := "%s|%d" % [str(it.get("id", "")), int(it.get("star", 1))]
		cnt[k] = int(cnt.get(k, 0)) + 1
	var bench: Array = GameState.persistent_bench
	var best := -1
	var bv := INF
	for i in range(bench.size()):
		var it = bench[i]
		if not (it is Dictionary) or str((it as Dictionary).get("kind", "")) == "item" or GameState.is_synergy_grant(it):
			continue
		if int(it.get("star", 1)) != 1 or int(cnt.get("%s|1" % str(it.get("id", "")), 0)) > 1:
			continue
		var val := _gear_val(it)
		if val < bv:
			bv = val
			best = i
	return best


## 装备是攻装还是防装: ★1 那档的数值里攻(atk + crit)和防(hp / def / mr)哪边大。1 = 攻, -1 = 防, 0 = 两边差不多。
func _gear_side(eid: String) -> int:
	var rows = _EQS.STATS.get(eid, [])
	if not (rows is Array) or (rows as Array).is_empty() or not ((rows as Array)[0] is Dictionary):
		return 0
	var r: Dictionary = (rows as Array)[0]
	var off := float(r.get("atk", 0)) + float(r.get("crit", 0)) * 60.0
	var dfn := float(r.get("hp", 0)) / 8.0 + (float(r.get("def", 0)) + float(r.get("mr", 0))) * 1.5
	if off > dfn * 1.3:
		return 1
	if dfn > off * 1.3:
		return -1
	return 0


## 单位想要哪边的装备: 1 = 输出(刺客 / 射手 / 法师 / 后排小将), -1 = 坦克 / 辅助 / 前排小将, 0 = 斗士。
func _unit_side(u: Dictionary) -> int:
	if str(u.get("kind", "")) == "minion":
		return 1 if str(u.get("role", "front")) == "back" else -1
	var role := str(_TS.ROLE.get(str(u.get("id", "")), ""))
	if role.contains("坦克") or role.contains("辅助"):
		return -1
	if role.contains("斗士"):
		return 0
	return 1


## 这件装给谁: 有空位的单位里挑最对口的(攻装给输出、防装给坦克); 同分统领优先 ——
##   追合成的件必须在统领身上(小将身上的不进合成池)。全队满 ⇒ 空。
func _equip_target(it: Dictionary = {}) -> Dictionary:
	if not GameState.team_has_equip_room():
		return {}
	var side := _gear_side(str(it.get("id", ""))) if not it.is_empty() else 0
	var chasing := false
	if not it.is_empty() and int(it.get("star", 1)) < 3:
		var k := "%s" % str(it.get("id", ""))
		var n := 0
		for g in _all_gear():
			if str(g.get("id", "")) == k and int(g.get("star", 1)) == int(it.get("star", 1)):
				n += 1
		chasing = n >= 2
	var dl: Dictionary = GameState.get_dual_lineup()
	var best: Dictionary = {}
	var bs := -INF
	for lane in ["top", "bottom"]:
		var arr: Array = dl.get(lane, [])
		for i in range(arr.size()):
			var u = arr[i]
			if not (u is Dictionary):
				continue
			var want := str(u.get("kind", ""))
			var eqs: Array = []
			if want == "leader":
				var pid := str(u.get("id", ""))
				if pid == "":
					continue
				eqs = GameState.persistent_equipped.get(pid, [])
			elif want == "minion":
				## ★小将身上的装备【进】合成池(GameState.auto_merge_all 2026-07-18 起扫 dual_lineup)。
				##   我原来照 equip_ops 里一句过时注释以为不进, 加了「追合成的件不给小将 / 小将不叠同款」两条限制
				##   ⇒ 对子只能在背包里干等、装备位空着(用户 10-12「这一路下来没机会升星吗」)。已删。
				eqs = u.get("equips", []) if u.get("equips", null) is Array else []
			else:
				continue
			if GameState._cap_count(eqs) >= _P2.UNIT_EQUIP_CAP:
				continue
			var us := _unit_side(u)
			var sc := 0.0
			if side != 0 and us != 0:
				sc = 2.0 if side == us else -2.0
			sc += 1.0 if want == "leader" else 0.0
			sc -= 0.1 * GameState._cap_count(eqs)
			if sc > bs:
				bs = sc
				best = {"lane": lane, "idx": i, "kind": want, "id": str(u.get("id", ""))}
	return best


# ═══════════════════════ 布阵(2026-10-12 用户「小将和统领的站位…不能千篇一律」) ═══════════════════════
## 原来 120 个号全是默认阵: 上路 2 统领 + 1 前排小将 / 下路 1 统领 + 前后排小将各 1。
## 现在按三只统领的定位排:
##   · 哪两只同路: 模板 A(槽位/3 偶数)把「最肉的 + 最能打的」放一路; 模板 B 把两只近战放一路、远程单走。
##   · 两统领那路放 上路 还是 下路: 按槽位再错开一位。
##   · 小将前后排: 同路统领全是远程 ⇒ 小将站前排挡刀; 全是近战 ⇒ 小将站后排输出; 混着 ⇒ 一前一后。
## 每个大轮只排一次(换轮后阵容重选, 再排一次)。走产品真入口: 点两格互换(_dl_click)、点小将切前后排(_dl_toggle_role)。
func _arrange_lineup(v: Node) -> Dictionary:
	if int(GameState.season_id) == _formed_season:
		return {}
	var dl: Dictionary = GameState.get_dual_lineup()
	var leaders: Array = []      # [{slot, id, melee, side}]
	for lane in ["top", "bottom"]:
		for u in dl.get(lane, []):
			if u is Dictionary and str(u.get("kind", "")) == "leader" and str(u.get("id", "")) != "":
				var pid := str(u.get("id", ""))
				var st = _TS.STATS.get(pid, [])
				var melee: bool = bool(st[0]) if st is Array and (st as Array).size() > 0 else true
				if pid in _TS.ROLE_MELEE_EXEMPT:
					melee = true
				leaders.append({"slot": int(u.get("slot", 0)), "id": pid, "melee": melee, "side": _unit_side(u)})
	if leaders.size() != 3:
		return {}
	## 选出同路的两只
	var pair: Array = []
	var tmpl := (_slot / 3) % 2
	if tmpl == 0:
		var tank: Dictionary = leaders[0]
		var dps: Dictionary = leaders[0]
		for l in leaders:
			if int(l["side"]) < int(tank["side"]):
				tank = l
			if int(l["side"]) > int(dps["side"]):
				dps = l
		pair = [tank, dps] if tank != dps else [leaders[0], leaders[1]]
	else:
		var mel := leaders.filter(func(l): return bool(l["melee"]))
		pair = [mel[0], mel[1]] if mel.size() >= 2 else ([leaders[0], leaders[1]] if mel.size() == 0 else [mel[0], leaders.filter(func(l): return not bool(l["melee"]))[0]])
	var solo: Dictionary = leaders.filter(func(l): return l != pair[0] and l != pair[1])[0]
	var pair_lane := "top" if ((_slot / 6) % 2 == 0) else "bottom"
	var solo_lane := "bottom" if pair_lane == "top" else "top"
	## 目标: 每格放哪只(统领按 slot 认; 小将按原来的顺序依次填)
	var want := {pair_lane: [int(pair[0]["slot"]), int(pair[1]["slot"]), -1], solo_lane: [int(solo["slot"]), -1, -1]}
	var order: Array = [["top", 0], ["top", 1], ["top", 2], ["bottom", 0], ["bottom", 1], ["bottom", 2]]
	var swaps := 0
	for k in range(order.size()):
		var lane: String = order[k][0]
		var pos: int = order[k][1]
		var need: int = int(want[lane][pos])
		var cur: Dictionary = GameState.get_dual_lineup()
		if _unit_fits(cur, lane, pos, need):
			continue
		var found := -1
		for j in range(k + 1, order.size()):
			if _unit_fits(cur, str(order[j][0]), int(order[j][1]), need):
				found = j
				break
		if found < 0:
			continue
		v.call("_dl_click", str(order[found][0]), int(order[found][1]))   # 点一格(选中)
		await _sleep(0.25)
		v.call("_dl_click", lane, pos)                                      # 点另一格(互换)
		await _sleep(0.3)
		swaps += 1
		if not _alive(v):
			return {}
	## 小将前后排
	var roles := []
	var fin: Dictionary = GameState.get_dual_lineup()
	for lane in ["top", "bottom"]:
		var arr: Array = fin[lane]
		var mel := 0
		var rng := 0
		for u in arr:
			if u is Dictionary and str(u.get("kind", "")) == "leader":
				var lid := str(u.get("id", ""))
				var st = _TS.STATS.get(lid, [])
				if (st is Array and (st as Array).size() > 0 and bool(st[0])) or lid in _TS.ROLE_MELEE_EXEMPT:
					mel += 1
				else:
					rng += 1
		var mi := 0
		for i in range(arr.size()):
			var u = GameState.get_dual_lineup()[lane][i]
			if not (u is Dictionary) or str(u.get("kind", "")) != "minion":
				continue
			var role := "front"
			if mel > 0 and rng == 0:
				role = "back"
			elif mel > 0 and rng > 0:
				role = "front" if mi % 2 == 0 else "back"
			elif mel == 0 and rng == 0:
				role = "front" if mi % 2 == 0 else "back"
			if str(u.get("role", "front")) != role:
				v.call("_dl_toggle_role", lane, i)
				await _sleep(0.25)
			roles.append("%s%d=%s" % [lane, i, role])
			mi += 1
	_formed_season = int(GameState.season_id)
	var res := {"template": tmpl, "pair": [pair[0]["id"], pair[1]["id"]], "pair_lane": pair_lane,
		"solo": solo["id"], "swaps": swaps, "minion_roles": roles}
	_ev("formation", res)
	return res


## 这一格上的单位是不是 need 要的(need ≥0 = 那个 slot 的统领; -1 = 任一小将)。
func _unit_fits(dl: Dictionary, lane: String, pos: int, need: int) -> bool:
	var arr: Array = dl.get(lane, [])
	if pos >= arr.size() or not (arr[pos] is Dictionary):
		return false
	var u: Dictionary = arr[pos]
	if need >= 0:
		return str(u.get("kind", "")) == "leader" and int(u.get("slot", -1)) == need
	return str(u.get("kind", "")) == "minion"



# ═══════════════════════════════ 图鉴 ═══════════════════════════════

func _do_codex(c: Node) -> void:
	if _since() > 8.0:
		_acted_id = c.get_instance_id()
		await _back_to_menu(c)


# ═══════════════════════════════ 每个界面逛一遍 ═══════════════════════════════

func _tour_wanted() -> bool:
	if OS.get_environment("SIM_TOUR").strip_edges() == "0":
		return false
	return not FileAccess.file_exists(TOUR_FLAG)


func _tour(m: Node) -> void:
	_ev("tour_begin", {})
	var seen: Array = []
	_shot("tour_01_menu"); seen.append("主菜单")
	## ① 赛程页(点右下模式卡 —— 它的 pressed 绑的就是 _open_week_popup)
	m.call("_open_week_popup")
	await _sleep(1.2)
	if _alive(m):
		_shot("tour_02_week"); seen.append("赛程页")
		m.call("_close_week_popup")
	## ② 右上「?」(pressed → _on_tutorial: 弹「新手教程」选择框) → 点「取消」
	await _sleep(0.6)
	if _alive(m):
		m.call("_on_tutorial")
		await _sleep(1.0)
		var ov := m.get_node_or_null("TutorialChoice")
		_shot("tour_03_help"); seen.append("帮助?")
		if ov == null:
			_ev("ANOMALY", {"where": "tour", "what": "点 ? 没弹出教程选择框"})
		else:
			var later := ov.find_child("CancelTutorial", true, false) as Button
			if later != null:
				later.emit_signal("pressed")
			else:
				_ev("ANOMALY", {"where": "tour", "what": "选择框里找不到「取消」"})
	## ③ 以下每一项: 主菜单上的入口 → 等进场 → 截图 → 用那一屏自己的返回钮回来
	var steps := [
		["tour_04_inventory", "背包", S_INV, func(mm): mm.call("_go", "Inventory")],
		["tour_05_shop", "商店", S_SHOP, func(mm): mm.call("_open_shop")],
		["tour_06_codex", "图鉴", S_CODEX, func(mm): mm.call("_go", "Codex")],
		["tour_07_leaderboard", "排行榜", S_LB, func(mm): mm.call("_go", "Leaderboard")],
		["tour_08_record", "战绩(点玩家卡)", S_REC, func(mm): mm.call("_open_record")],
		["tour_09_settings", "设置", S_SET, func(mm): mm.call("_go", "Settings")],
		["tour_10_trainer", "训龟大师", S_TRAINER, func(mm): mm.call("_go", "TrainerConfig")],
	]
	for st in steps:
		var menu := await _wait_scene(S_MENU, 20.0)
		if menu == null:
			_ev("ANOMALY", {"where": "tour", "what": "回不到主菜单", "before": st[1]})
			break
		await _sleep(1.5)
		if not _alive(menu):
			continue
		(st[3] as Callable).call(menu)
		var sc := await _wait_scene(str(st[2]), 8.0)
		if sc == null:
			## 没进去(例: 商店锁着只飘一行字) —— 截下主菜单上那句提示
			_shot(str(st[0]) + "_blocked")
			_ev("tour_step", {"step": st[1], "entered": false})
			seen.append(str(st[1]) + "(未进入)")
			continue
		await _sleep(2.5)
		if not _alive(sc):
			continue
		_shot(str(st[0]))
		seen.append(str(st[1]))
		await _tour_extra(str(st[2]), sc)
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path != S_MENU:
			await _back_to_menu(cur)
	_ev("tour_end", {"seen": seen})
	var f := FileAccess.open(TOUR_FLAG, FileAccess.WRITE)
	if f != null:
		f.store_string(Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())))
		f.close()


## 个别屏在截完首图之后再多点一下。
func _tour_extra(path: String, sc: Node) -> void:
	match path:
		S_CODEX:
			sc.call("_switch_tab", "equips")
			await _sleep(1.2)
			if _alive(sc):
				_shot("tour_06b_codex_equips")
		S_REC:
			var rb := sc.find_children("ReplayBtn", "Button", true, false)
			_ev("record", {"rows": GameState.match_history.size(), "replay_buttons": rb.size()})
			if rb.size() > 0:
				(rb[0] as Button).emit_signal("pressed")
				var bt := await _wait_scene(S_BATTLE, 20.0)
				if bt != null:
					await _sleep(8.0)
					_shot("tour_08b_replay")
					_ev("replay", {"opened": true})
				else:
					_shot("tour_08b_replay_failed")
					_ev("replay", {"opened": false, "code": str(sc.get("last_replay_code")) if _alive(sc) else "?",
						"msg": str(sc.get("last_replay_msg")) if _alive(sc) else "?"})
		S_TRAINER:
			## 「训龟大师也要点」: 按槽位挑一招 + 一个形象, 再点「保存」
			var cards: Array = sc.get("_skill_cards")
			var want: String = TRAINER_SKILLS[(_slot - 1) % TRAINER_SKILLS.size()]
			for c in cards:
				if str(c[1]) == want:
					(c[0] as Button).emit_signal("pressed")
			await _sleep(0.6)
			var apps: Array = sc.get("_appear_cards")
			if apps.size() > 0:
				(apps[(_slot - 1) % apps.size()][0] as Button).emit_signal("pressed")
			await _sleep(0.8)
			if not _alive(sc):
				return
			_shot("tour_10b_trainer_picked")
			sc.call("_save_and_back")
			await _sleep(0.5)
			_ev("trainer", {"skill": str(GameState.trainer_skill), "appearance": str(GameState.trainer_appearance),
				"wanted": want})


## 用这一屏自己的返回钮回主菜单。
func _back_to_menu(sc: Node) -> void:
	if not _alive(sc):
		return
	if sc.has_method("_on_back"):
		sc.call("_on_back")          # 选龟 / 设置
	elif sc.has_method("_save_and_back"):
		sc.call("_save_and_back")    # 训龟大师
	else:
		get_tree().change_scene_to_file(S_MENU)   # TopBar on_back 绑的就是这一句
	await _wait_scene(S_MENU, 10.0)


# ═══════════════════════════════ 新手引导 ═══════════════════════════════

## 引导条没有按钮(2026-10-07 重做) —— 这里只**记账**: 当前显示的那一句换了就记一行事件,
##   事后对照「每一步是不是都出现过、按什么顺序」。推进靠本节点做的真动作。
var _last_guide := ""
var _guide_n := 0
func _drain_guides() -> void:
	var t := _guide_text()
	if t != _last_guide:
		_last_guide = t
		if t != "":
			_guide_n += 1
			_ev("guide_step", {"n": _guide_n, "text": t, "scene": _scene_path})
			_shot("guide_%02d" % _guide_n)


func _guide_text() -> String:
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(n) and n.has_method("is_showing") and not n.is_queued_for_deletion() and bool(n.call("is_showing")):
			return str(n.call("current_text"))
	return ""


# ═══════════════════════════════ 小工具 ═══════════════════════════════

func _sleep(sec: float) -> void:
	var until := Time.get_ticks_msec() + int(sec * 1000.0)
	while is_inside_tree() and Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _since() -> float:
	return (Time.get_ticks_msec() - _scene_since) / 1000.0 if _scene_since > 0 else 0.0


func _alive(n) -> bool:
	return n != null and is_instance_valid(n) and (n as Node).is_inside_tree() \
		and get_tree() != null and get_tree().current_scene == n


func _wait_scene(path: String, timeout: float) -> Node:
	var until := Time.get_ticks_msec() + int(timeout * 1000.0)
	while is_inside_tree() and Time.get_ticks_msec() < until:
		var sc := get_tree().current_scene
		if sc != null and sc.scene_file_path == path:
			return sc
		await get_tree().process_frame
	return null


func _stats() -> Dictionary:
	return {"battles": int(GameState.season_total_battles), "wins": int(GameState.season_wins),
		"hearts": int(GameState.hearts), "ranked_used": int(GameState.ranked_used),
		"coins": int(GameState.meta_deepsea_coins), "level": int(GameState.season_level),
		"leaders": Array(GameState.season_leaders) if GameState.season_leaders is Array else [],
		"account": str(GameState.account_id)}


func _ev(kind: String, data: Dictionary) -> void:
	var line := JSON.stringify({"t": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())), "slot": _slot,
		"kind": kind, "data": data})
	print("[SIMDRV] ", line)
	var f: FileAccess
	if FileAccess.file_exists(EV_PATH):
		f = FileAccess.open(EV_PATH, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(EV_PATH, FileAccess.WRITE)
	if f != null:
		f.store_line(line)
		f.close()


func _shot(name: String) -> void:
	## 无头时没有渲染器(dummy 贴图恒 null): 硬取会报 `Parameter "t" is null`, 而那条会进生产的客户端报错表、混进真人玩家的报错里
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	var ts := Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system())).replace("-", "").replace(":", "")
	var p := _shot_dir.path_join("%s_%s.jpg" % [ts, name])
	img.save_jpg(p, 0.85)
	_ev("shot", {"name": name, "path": p})
