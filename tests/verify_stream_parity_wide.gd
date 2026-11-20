extends Node
## verify_stream_parity_wide.gd —— 看直播时信息面板 / 点开的小卡 / 📊 统计与「本机直接跑」逐字一致 · 宽覆盖版(2026-11-20)。
## 用户 11-20「直播的时候什么东西没显示，你再看一遍呢，看还有什么 bug」(起因: 宝箱龟财宝条在直播里整条不画)。
## verify_stream_panels_parity 只跑一套固定阵容(basic / stone / bamboo)、只读面板上直接看得见的字 ⇒ 下面这些它一条都照不到:
##   ① 装备往 eq_state 里存了单位 / 节点(021 / 060 / 064 / 068 / 069)⇒ 录流器整张表不发
##   ② @hud 通道每次把 eq_state 盖成只剩头像框那几个读数(播放端 stream_hud)⇒ 装备「本局」全成「暂无记录」、糖果反伤 48% → 8%
##   ③ 选中的那一招 / 海盗船形态 / 竹叶龟本大轮累积: 面板现读本机存档或对手快照, 看直播的一端没有 ⇒ 对面海盗龟显示默认那招
##   ④ 流里是单精度 ⇒ 正好落在 .5 的数(减伤 0.75% / 移速 73.5)四舍五入差 1
##   ⑤ 播放端往带元素类型的数组属性赋值被拒(「Cannot assign contents of Array[Object]」)
## 做法: 每局双方各 3 统领、每只 3 件商店装备、甲乙跨场累积值与技能选择都不同(且非默认); 裁判入口本机跑一遍(同时录流) →
##   按「跟播自己这一局」的入口形状播刚录的流(看的人 = 甲: 本机存档是甲的); 同一批步号上, 每只活着的单位点开信息面板读全部字,
##   再逐个点面板里能点的格(技能 / 装备 / 属性 / 战利品)读弹出的小卡; 📊 四个页签。逐字比, 一条不一致就红。
## 默认跑 3 局(第 1 / 4 / 5 局: 宝箱 / 糖果 / 竹叶 / 海盗 / 龟壳 / 双头 + 060 / 064 / 068 / 069 / 083 …);
##   环境 WIDE_ALL=1 跑满 5 局(28 只龟全上场、全部商店装备都带过; 2026-11-20 修完实测 5 局 0 条不一致)。
## 反向验证(11-20): stream_hud 改回整张替换 ⇒ 红(装备「暂无记录」/ 反伤); 录流器名单去掉 _picked + ship_summoned ⇒ 红(海盗龟)。

const Backend := preload("res://scripts/net/backend.gd")
const FMT := preload("res://scripts/systems/stream/stream_format.gd")
const J := preload("res://tests/_stream_jobs.gd")
const SIM_DT := 1.0 / 60.0
const TABS := ["dealt", "taken", "heal", "shield"]
const EVERY := 700
const MAX_SNAPS := 8
const SEEDS := [2000029, 2000031, 2000033, 2000035, 2000037]
const JOBS_DEFAULT := [0, 3, 4]

var _nat := {}
var _next := 400
var _diffs := {}           # 去重键 → 一行说明
var _n_units := 0
var _n_cards := 0
var _n_tabs := 0
var _seen_pids := {}
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_fails += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("" if cond or detail == "" else "\n      " + detail)])


func _texts(n: Node, out: Array) -> void:
	if n is Label or n is RichTextLabel or n is Button:
		var t := str(n.get("text")).strip_edges()
		if t != "" and (n as CanvasItem).is_visible_in_tree():
			out.append(t.replace("\n", " / "))
	for c in n.get_children():
		_texts(c, out)


func _clickables(n: Node, out: Array) -> void:
	if n is Control and (n as Control).mouse_filter == Control.MOUSE_FILTER_STOP and not (n is BaseButton) \
			and n.get_signal_connection_list("gui_input").size() > 0 and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_clickables(c, out)


func _click(n: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	n.gui_input.emit(ev)


func _capture(b: Node, ub: Dictionary) -> Dictionary:
	var units := {}
	var idxs: Array = ub.keys()
	idxs.sort()
	for i in idxs:
		var u: Dictionary = ub[i]
		if not bool(u.get("alive", false)):
			continue
		b._hud._show_unit_info_panel(u)
		var tx: Array = []
		var cards := {}
		var ip = b.get("_info_panel")
		if ip != null and is_instance_valid(ip):
			_texts(ip, tx)
			var cl: Array = []
			_clickables(ip, cl)
			for k in range(cl.size()):
				_click(cl[k])
				var ic = b._info_sys.card()
				var ct: Array = []
				if ic.card != null and is_instance_valid(ic.card):
					_texts(ic.card, ct)
				cards["%d:%s" % [k, str(ic.key)]] = ct
				ic.close()
		units[i] = {"pid": str(u.get("id", "?")), "panel": tx, "cards": cards}
		b._hud._close_info_panel()
	var stats := {}
	b._on_dmg_stats_toggle()
	var ds = b._dmg_stats
	if ds != null and ds.panel != null and is_instance_valid(ds.panel):
		for tab in TABS:
			ds._tab = tab
			ds.render()
			var st: Array = []
			_texts(ds.panel, st)
			stats[tab] = st
	b._on_dmg_stats_toggle()
	return {"units": units, "stats": stats}


static func _only(a: Array, b: Array) -> Array:
	var out: Array = []
	var pool: Array = b.duplicate()
	for x in a:
		var k := pool.find(x)
		if k >= 0:
			pool.remove_at(k)
		else:
			out.append(x)
	return out


func _note(pid: String, where: String, a: Array, c: Array) -> void:
	var oa := _only(a, c)
	var oc := _only(c, a)
	## 去重: 同一只龟、同一块、同样的「差在哪几行(去掉数字)」只记一次
	var shape := "%s|%s|%s|%s" % [pid, where.get_slice(":", 1), _strip_nums(str(oa)), _strip_nums(str(oc))]
	if _diffs.has(shape):
		return
	_diffs[shape] = "%s · %s：只在本机 %s ｜ 只在流 %s" % [pid, where, str(oa).left(300), str(oc).left(300)]


static func _strip_nums(s: String) -> String:
	var r := RegEx.create_from_string("[0-9.]+")
	return r.sub(s, "#", true)


func _set_carry(gs, k: int) -> void:
	## 跨场累积的那几样(本机存档 / 对手快照里才有, 单位字典上没有): 甲乙给不同的值, 好看出读错了哪一边
	gs.bamboo_growth_hp = 300.0 + 111.0 * k
	gs.chest_treasure_value = 4000.0 + 1500.0 * k
	gs.chest_treasures_won = []
	gs.gambler_wheel_stacks = {"spade": 1 + k, "heart": k}
	gs.incense_marks = 10 + 5 * k
	gs.incense_charge = 800 + 300 * k


func _snap(gs, trio: Array, eqs: Array, gid: String, nm: String, k: int) -> Dictionary:
	gs.reset_dual_lane()
	_set_carry(gs, k)
	gs.season_leaders = trio.duplicate()
	gs.left_team.assign(gs.season_leaders)
	var pe := {}
	for i in range(trio.size()):
		pe[trio[i]] = eqs[i]
	gs.persistent_equipped = pe
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "slot": 0, "id": trio[0], "off": [-100, 160]},
			{"kind": "minion", "role": "front", "equips": [], "off": [150, -200]},
			{"kind": "minion", "role": "back", "equips": []},
		],
		"bottom": [
			{"kind": "leader", "slot": 1, "id": trio[1], "equips": [], "off": [60, -120]},
			{"kind": "leader", "slot": 2, "id": trio[2], "equips": []},
			{"kind": "minion", "role": "back", "equips": []},
		],
	}
	## 技能选择也甲乙不同、且不是默认(默认 = skillPool[1]): 甲选 2、乙选 3(池子不够大时战斗那边自己回落)
	var lo := {}
	for pid in trio:
		lo[pid] = 2 + k
	gs.loadouts = lo
	gs.trainer_skill = "hook"
	gs.season_level = J.LEVEL
	var s: Dictionary = Backend.build_ghost_snapshot(gid, {"name": nm, "avatar": trio[0], "id": gid})
	if s.get("profile") is Dictionary:
		(s["profile"] as Dictionary)["tag"] = "#" + gid.to_upper().left(6)
	return s


func _ready() -> void:
	print("=== verify_stream_parity_wide ===")
	var jobs: Array = [0, 1, 2, 3, 4] if OS.has_environment("WIDE_ALL") else JOBS_DEFAULT
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var pids: Array = []
	for k in DataRegistry.pet_by_id.keys():
		pids.append(str(k))
	pids.sort()
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	shop.sort()
	print("  龟 %d 只 · 商店装备 %d 件" % [pids.size(), shop.size()])
	var ei := 0
	for g in range(SEEDS.size()):
		var six: Array = []
		for k in range(6):
			six.append(pids[(g * 6 + k) % pids.size()])
		var eqA: Array = []
		var eqB: Array = []
		for k in range(3):
			eqA.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
			ei += 3
		for k in range(3):
			eqB.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
			ei += 3
		if not jobs.has(g):
			continue
		var a: Dictionary = _snap(gs, six.slice(0, 3), eqA, "g_pa_%d" % g, "甲%d" % g, 0)
		var b2: Dictionary = _snap(gs, six.slice(3, 6), eqB, "g_pb_%d" % g, "乙%d" % g, 1)
		var job: Dictionary = J.job(a, b2, int(SEEDS[g]))
		print("--- 第 %d 局 种子 %d · 甲 %s · 乙 %s" % [g + 1, SEEDS[g], str(six.slice(0, 3)), str(six.slice(3, 6))])
		await _run_one(job)
	print("")
	print("  分母: 单位面板 %d · 点开的小卡 %d · 统计页签 %d · 上过场的龟 %d 只" % [_n_units, _n_cards, _n_tabs, _seen_pids.size()])
	var keys: Array = _diffs.keys()
	keys.sort()
	_ok("分母 · 单位面板 %d / 小卡 %d / 统计页签 %d / 上场的龟 %d 只" % [_n_units, _n_cards, _n_tabs, _seen_pids.size()],
		_n_units >= 60 and _n_cards >= 1000 and _n_tabs >= 40 and _seen_pids.size() >= 15)
	_ok("★★看直播时面板 / 小卡 / 统计与本机逐字一致(去重后不一致 %d 条)" % keys.size(), keys.is_empty(),
		"\n      ".join(keys.map(func(k) -> String: return str(_diffs[k]).left(400)).slice(0, 12)))
	print("ALL PASS" if _fails == 0 else "FAIL x%d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _run_one(job: Dictionary) -> void:
	_nat = {}
	_next = 400
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if _nat.size() >= MAX_SNAPS or s < _next or str(bt._dl_state) != "fight":
					return
				if rec._step_n % FMT.CONT_EVERY != 0:
					return
				_next = s + EVERY
				var ub := {}
				for i in range(rec._uk.size()):
					var u = rec._uk[i]
					for v in (bt._units as Array):
						if is_same(v, u):
							ub[i] = u
							break
				_nat[s] = _capture(bt, ub)
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("  本机一遍: %d 块 · 拍到 %d 个采样步" % [chunks.size(), _nat.size()])
	if chunks.is_empty() or _nat.is_empty():
		return
	var gs = get_node_or_null("/root/GameState")
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	gs.season_leaders = []
	var lo_a := {}
	for pid in (job["a"] as Dictionary).get("leaders", []):
		lo_a[str(pid)] = 2
	gs.loadouts = lo_a          # 看直播的人 = 甲: 本机存档是甲的技能选择
	gs.foe_loadouts = {}        # 跟播入口不给对手的技能选择
	_set_carry(gs, 0)          # 看直播的人 = 甲(积分赛跟播自己那一局): 本机存档是甲的跨场累积
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, res.get("stream", {})), "seed": RefereeJob.seed_of(job), "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	if p == null:
		_ok("播放端建起来了", false)
		return
	var got := {}
	var guard := 0
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 400000 and got.size() < _nat.size():
		guard += 1
		p.advance(SIM_DT)
		if _nat.has(p.cur_step) and not got.has(p.cur_step):
			var ub := {}
			for i in p.units:
				ub[i] = p.units[i]
			got[p.cur_step] = _capture(b, ub)
		if guard % 60 == 0:
			await get_tree().process_frame
	print("  播放端拍到 %d / %d" % [got.size(), _nat.size()])
	for s in _nat.keys():
		if not got.has(s):
			continue
		var nu: Dictionary = _nat[s]["units"]
		var pu: Dictionary = got[s]["units"]
		for i in nu:
			_n_units += 1
			var na: Dictionary = nu[i]
			var pid := str(na["pid"])
			_seen_pids[pid] = true
			var pa: Dictionary = pu.get(i, {"panel": [], "cards": {}})
			if na["panel"] != pa["panel"]:
				_note(pid, "面板", na["panel"], pa["panel"])
			for ck in (na["cards"] as Dictionary):
				_n_cards += 1
				var cb: Array = (pa["cards"] as Dictionary).get(ck, ["<流里没有这张卡>"])
				if na["cards"][ck] != cb:
					_note(pid, "卡:" + str(ck).get_slice(":", 1) + ":" + str(ck).get_slice(":", 2), na["cards"][ck], cb)
			for ck in (pa["cards"] as Dictionary):
				if not (na["cards"] as Dictionary).has(ck):
					_note(pid, "卡(只在流):" + str(ck), [], pa["cards"][ck])
		var ns: Dictionary = _nat[s]["stats"]
		var ps: Dictionary = got[s]["stats"]
		for tab in TABS:
			if not ns.has(tab):
				continue
			_n_tabs += 1
			if ns[tab] != ps.get(tab, []):
				_note("📊", "统计:" + tab, ns[tab], ps.get(tab, []))
	b.queue_free()
	await get_tree().process_frame
	ReplayRecorder.end_play()
	await get_tree().process_frame
