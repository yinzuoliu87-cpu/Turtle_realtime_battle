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
##       `_on_select()`+`_on_buy()` / `_on_bench_click()`+`_dl_click()` / 引导条的「下一步」钮)。
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
##   SIM_SHOT_DIR         命名截图落在这里(与 sim_shot 的 latest.png 同目录); 没给就 user://sim_shots
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
var _acted_id := 0         # 已经处理过的场景实例(同一屏只做一次主动作, 防连点)


func _ready() -> void:
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
		await _drain_guides()
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


# ═══════════════════════════════ 主菜单 ═══════════════════════════════

func _do_menu(m: Node) -> void:
	if _done:
		return
	if bool(GameState.tutorial_active):
		return          # 教学中途回到主菜单(不该发生) ⇒ 让 STUCK 去记
	await _sleep(1.5)   # 主菜单 _ready 自己 await 两帧 + 入场动画
	if not _alive(m):
		return
	_acted_id = m.get_instance_id()
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
	_ev("start_battle", {"n": _rounds_started, "stats": _stats()})
	m.call("_start_battle_flow")


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
	await _drain_guides()
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
		await _drain_guides()
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
	var style := _slot % 3      # 0 装备优先 / 1 均衡 / 2 升级优先
	var bought: Array = []
	var xp_n := 0
	var refreshed := false
	var coins0 := int(GameState.meta_deepsea_coins)
	var lv0 := int(GameState.season_level)
	## 升级优先: 先买经验(留够一件 1 费的钱)
	if style == 2 and not tut:
		while int(GameState.meta_deepsea_coins) >= _P2.BUY_XP_COST + 2 and int(GameState.season_level) < _P2.MAX_LEVEL and xp_n < 3:
			if not _buy_xp(s):
				break
			xp_n += 1
			await _sleep(0.4)
			if not _alive(s):
				return
	for _round in range(8):
		if not _alive(s):
			return
		## 不囤货: 背包里没装上的件数 > 全队空位 + 1(留一件凑合成)⇒ 不再买
		if not tut:
			var free_slots: int = maxi(0, int(GameState.team_equip_cap()) - int(GameState.team_equipped_count()))
			if _bench_gear_n() > free_slots:
				break
		var offer: Array = s.get("_offer")
		var cands: Array = []
		for i in range(offer.size()):
			if offer[i] == null:
				continue
			var price := int(s.call("_price", s.call("_deco", offer[i])))
			if price <= int(GameState.meta_deepsea_coins):
				cands.append(i)
		if cands.is_empty():
			if style == 0 and not refreshed and not tut and int(GameState.meta_deepsea_coins) >= 2 + 3:
				refreshed = true
				s.call("_on_refresh")
				_ev("shop_refresh", {"coins": int(GameState.meta_deepsea_coins)})
				await _sleep(0.6)
				continue
			break
		var i: int = int(cands[_rng.randi() % cands.size()])
		var eid := str((s.call("_deco", offer[i]) as Dictionary).get("id", ""))
		s.call("_on_select", i)      # 两步购买: 点卡选中 → 面板里点「买下」
		await _sleep(0.4)
		if not _alive(s):
			return
		var c_before := int(GameState.meta_deepsea_coins)
		s.call("_on_buy", i)
		bought.append({"id": eid, "paid": c_before - int(GameState.meta_deepsea_coins)})
		await _sleep(0.5)
		if bought.size() >= (2 if tut else 4):
			break
	## 均衡: 剩的钱买一次经验
	if style == 1 and not tut and _alive(s):
		if int(GameState.meta_deepsea_coins) >= _P2.BUY_XP_COST and _buy_xp(s):
			xp_n += 1
	_ev("shop", {"visit": _shop_visits, "tutorial": tut, "style": style, "coins_before": coins0,
		"coins_after": int(GameState.meta_deepsea_coins), "bought": bought, "xp_buys": xp_n,
		"level": [lv0, int(GameState.season_level)], "bench_n": GameState.persistent_bench.size()})
	await _sleep(0.8)
	if not _alive(s):
		return
	if _shop_visits <= 2:
		_shot("shop_%02d_after" % _shop_visits)
	if tut:
		await _press_tut_next()
	else:
		## 顶栏「🎒 背包」那颗钮绑的就是这一句(ShopScene.gd TopBar left_actions)
		get_tree().change_scene_to_file(S_INV)


## 买经验 —— 与商店那颗经验钮的 `pressed` 回调逐字同一段(`GameState.buy_season_xp()` 成功则 `_rebuild()`)。
func _buy_xp(s: Node) -> bool:
	if GameState.buy_season_xp():
		s.call("_rebuild")
		return true
	return false


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
	for _k in range(14):
		if not _alive(v):
			return
		var bi := _first_bench_gear()
		if bi < 0:
			break
		var tgt := _equip_target()
		if tgt.is_empty():
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
			_ev("ANOMALY", {"where": "inventory", "what": "点了装备+点了单位, 背包件数没少", "target": tgt})
			break
	_ev("inventory", {"tutorial": tut, "equipped": equipped,
		"team_equipped": GameState.team_equipped_count(), "team_cap": GameState.team_equip_cap(),
		"bench_n": GameState.persistent_bench.size()})
	if _shop_visits <= 2:
		_shot("inventory_%02d" % _shop_visits)
	await _sleep(0.8)
	if not _alive(v):
		return
	if tut:
		await _press_tut_next()
	else:
		get_tree().change_scene_to_file(S_MENU)   # 顶栏返回钮绑的就是这一句


func _first_bench_gear() -> int:
	var bench: Array = GameState.persistent_bench
	for i in range(bench.size()):
		if bench[i] is Dictionary and str((bench[i] as Dictionary).get("id", "")) != "":
			return i
	return -1


## 下一件装给谁: 统领优先(按 lane 顺序), 统领都满了给小将。全队满 ⇒ 空。
func _equip_target() -> Dictionary:
	if not GameState.team_has_equip_room():
		return {}
	var dl: Dictionary = GameState.get_dual_lineup()
	for want in ["leader", "minion"]:
		for lane in ["top", "bottom"]:
			var arr: Array = dl.get(lane, [])
			for i in range(arr.size()):
				var u = arr[i]
				if not (u is Dictionary) or str(u.get("kind", "")) != want:
					continue
				var eqs: Array = []
				if want == "leader":
					var pid := str(u.get("id", ""))
					if pid == "":
						continue
					eqs = GameState.persistent_equipped.get(pid, [])
				else:
					eqs = u.get("equips", []) if u.get("equips", null) is Array else []
				if GameState._cap_count(eqs) < _P2.UNIT_EQUIP_CAP:
					return {"lane": lane, "idx": i, "kind": want, "id": str(u.get("id", ""))}
	return {}


# ═══════════════════════════════ 图鉴(教学那一站) ═══════════════════════════════

func _do_codex(c: Node) -> void:
	if not bool(GameState.tutorial_active):
		if _since() > 8.0:
			_acted_id = c.get_instance_id()
			await _back_to_menu(c)
		return
	_acted_id = c.get_instance_id()
	await _sleep(2.0)
	if _alive(c):
		_shot("codex_tut")
		await _press_tut_next()


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
	## ② 右上「?」(pressed → _on_tutorial: 弹「先下场练练」确认框) → 点「等会儿」
	await _sleep(0.6)
	if _alive(m):
		m.call("_on_tutorial")
		await _sleep(1.0)
		var ov := m.get_node_or_null("TutorialConfirm")
		_shot("tour_03_help"); seen.append("帮助?")
		if ov == null:
			_ev("ANOMALY", {"where": "tour", "what": "点 ? 没弹出确认框"})
		else:
			var later := _find_button(ov, "等会儿")
			if later != null:
				later.emit_signal("pressed")
			else:
				_ev("ANOMALY", {"where": "tour", "what": "确认框里找不到「等会儿」"})
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

## 引导条(TutorialGuide)在就一步一步点「下一步 / 知道了 / 完成」。上限防死循环。
func _drain_guides() -> void:
	for _i in range(20):
		var g := _guide()
		if g == null:
			return
		var row = g.get("_btn_row")
		var nxt: Button = null
		if row is Node:
			for c in (row as Node).get_children():
				if c is Button and not (c as Node).is_queued_for_deletion():
					nxt = c      # 最后一颗 = 下一步/完成(跳过钮在它前面)
		if nxt == null:
			return
		var idx := int(g.get("_idx"))
		nxt.emit_signal("pressed")
		_ev("guide_next", {"idx": idx, "label": nxt.text})
		await _sleep(0.6)


func _guide() -> Node:
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if is_instance_valid(n) and n.get("_btn_row") != null and not n.is_queued_for_deletion():
			return n
	return null


## 教学里商店/背包/图鉴右上那颗「下一站」钮(TutorialDirector.attach_next_button 建的)。
func _press_tut_next() -> void:
	await _drain_guides()
	for n in get_tree().get_nodes_in_group("tut_overlay"):
		if n is CanvasLayer:
			for c in n.get_children():
				if c is Button:
					_ev("tut_next", {"label": (c as Button).text})
					(c as Button).emit_signal("pressed")
					return
	_ev("ANOMALY", {"where": _scene_path, "what": "教学里找不到「下一站」钮"})


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


func _find_button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
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
