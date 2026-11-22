extends Node
## verify_stream_head_badges.gd —— 头顶叠层 / 状态徽章: 看直播(积分赛跟播 / 观战 / 录像)时与本机一样画; 换路不留残徽章(2026-11-22)
##
## 由来: 用户 11-22「闪电龟被动的图标现在是看不到吗？这是什么 bug 吗？」「那诸如此类肯定还有很多问题啊」。
##   全场排查(tests/probes/_probe_cover_sweep)量出两件:
##   ① 播放端(stream_player)从不排头顶徽章 —— 本机是 sim 步里 `_tick_unit → _layout_head_badges` 排的, 播放端不跑 sim ⇒
##      同一局本机可见 149 个、播放端 0 个(探针 tests/probes/_probe_stream_badges), 层数字段流里一直有。
##      积分赛是服务器裁判、手机播流 ⇒ 玩家在线上对局里从来看不到电击 / 墨迹 / 结晶 / 赛博充能层数。
##      另外赛博充能层 / 猎杀印记两个字段不在录流名单里, 补了排版也画不出来。
##   ② 换路清场(_dl_clear_units)收了立绘 / 影子 / 血条, 没收头顶徽章 ⇒ 活着进下一路的单位的徽章留在原地,
##      5 局里约四分之一的采样画面上挂着没有主人的徽章(例: 赛博芯片「8」停在终极大战场一块空地上)。
##
## 做法同 verify_stream_parity_wide: 裁判入口本机跑一局并录流(三路打满), 再按跟播入口播刚录的流;
##   两边在同一批采样步上按种类数画面上可见的徽章(可见 / 没排队删除 / 缩放 > 0.05), 逐种比。
##   本机那一遍每个采样步顺带数「不在任何现存单位徽章池里、却还可见」的徽章, 播放端同样数。
## 判据:
##   ⓪ 分母: 两局里电击 / 墨迹 / 结晶 / 赛博充能 / 猎杀印记各自在本机出现过(数到 0 = 空检查)
##   ① 每一种: 播放端数量 ≥ 本机的 90%(采样那一刻正在弹入起点的会差一两个)
##   ② 本机换路后没有残留徽章(采样覆盖换路前后; 至少走过两路)
##   ③ 播放端也没有残留徽章
## 反向验证(11-22):
##   去掉 stream_player `_render` 里那段排版 ⇒ ① 全红(播放端 0);
##   去掉 _dl_clear_units 里的 `_free_head_badges` ⇒ ② 红;
##   录流名单去掉 cyber_ai_charge ⇒ ① 赛博充能红。

const W := preload("res://tests/verify_stream_parity_wide.gd")
const J := preload("res://tests/_stream_jobs.gd")
const FMT := preload("res://scripts/systems/stream/stream_format.gd")
const SIM_DT := 1.0 / 60.0
const KINDS := ["电击", "墨迹", "结晶", "赛博充能", "猎杀印记"]
## 两局: 甲带会叠层的龟, 乙是挨叠层的; 第二局有赛博(充能层) / 结晶 / 猎人(猎杀印记)
const GAMES := [
	{"a": ["lightning", "line", "ninja"], "b": ["phoenix", "pirate", "rainbow"], "seed": 2000035},
	{"a": ["cyber", "crystal", "hunter"], "b": ["basic", "stone", "ice"], "seed": 2000041,
		"lo_a": {"cyber": 3, "hunter": 1}},   # 赛博选智能AI(登场 3 层充能) / 猎人选瞄准射击(命中挂猎杀印记); 借来的快照默认甲一律选第 2 技
]

var _n := 0
var _fail := 0
var _nat := {}          # 采样步 → {种类: 个数}
var _nat_tot := {}
var _pl_tot := {}
var _nat_orph := 0
var _nat_orph_ex := ""
var _pl_orph := 0
var _pl_orph_ex := ""
var _nat_lanes := {}
var _steps := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("" if cond or detail == "" else "  " + detail)])


func _kind(c: Control) -> String:
	var ic := c.get_node("icon") as TextureRect
	var f := ic.texture.resource_path.get_file() if ic.texture != null else ""
	var num := str((c.get_node("num") as Label).text)
	match f:
		"lightning-storm-icon.png": return "电击"
		"ink-mark-icon.png": return "墨迹"
		"crystal-shard.png": return "结晶"
		"hunter-mark.png": return "猎杀印记"
		"hijack-chip.png": return "赛博充能" if num != "" else "侵入"
	return f


func _is_badge(c) -> bool:
	return c is Control and c.get_node_or_null("icon") != null and c.get_node_or_null("num") != null


## 画面上可见的徽章按种类数; 顺带数不在任何现存单位池里的(残留)
func _count(b: Node, unit_list: Array) -> Array:
	var owned := {}
	for u in unit_list:
		if u is Dictionary:
			for k in ["_hbrow_stack", "_hbrow_status"]:
				for x in (u as Dictionary).get(k, []):
					if is_instance_valid(x):
						owned[(x as Object).get_instance_id()] = true
	var by := {}
	var orph := 0
	var ex := ""
	for c in b._ui_layer.get_children():
		if not _is_badge(c) or not c.visible or c.is_queued_for_deletion():
			continue
		if not owned.has(c.get_instance_id()):
			orph += 1
			if ex == "":
				ex = "%s「%s」@%s" % [_kind(c), (c.get_node("num") as Label).text, str(c.position.round())]
			continue
		if c.scale.x <= 0.05:
			continue
		var k := _kind(c)
		by[k] = int(by.get(k, 0)) + 1
	return [by, orph, ex]


func _add(tot: Dictionary, by: Dictionary) -> void:
	for k in by:
		tot[k] = int(tot.get(k, 0)) + int(by[k])


func _ready() -> void:
	print("=== verify_stream_head_badges ===")
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var w = W.new()
	for gi in range(GAMES.size()):
		var g: Dictionary = GAMES[gi]
		var a: Dictionary = w._snap(gs, g["a"], [[], [], []], "g_hb_a%d" % gi, "甲", 0)
		var b2: Dictionary = w._snap(gs, g["b"], [[], [], []], "g_hb_b%d" % gi, "乙", 1)
		if g.has("lo_a") and a.get("loadouts") is Dictionary:
			for pid in (g["lo_a"] as Dictionary):
				(a["loadouts"] as Dictionary)[pid] = int(g["lo_a"][pid])
		print("--- 第 %d 局 · 甲 %s · 乙 %s" % [gi + 1, str(g["a"]), str(g["b"])])
		await _run_one(J.job(a, b2, int(g["seed"])))
	w.free()
	print("")
	print("  采样步 %d · 本机走过的路(换路纪元) %s" % [_steps, str(_nat_lanes.keys())])
	print("  本机 %s" % str(_nat_tot))
	print("  播放 %s" % str(_pl_tot))
	for k in KINDS:
		_ok("⓪ 分母 · 本机画过「%s」徽章(%d 个)" % [k, int(_nat_tot.get(k, 0))], int(_nat_tot.get(k, 0)) > 0)
	for k in KINDS:
		var nv := int(_nat_tot.get(k, 0))
		var pv := int(_pl_tot.get(k, 0))
		_ok("① ★看直播时「%s」徽章与本机一样画(本机 %d / 播放 %d)" % [k, nv, pv],
			nv > 0 and float(pv) >= float(nv) * 0.9,
			"播放端少画 —— 看直播 / 录像 / 积分赛跟播时这种层数玩家看不见")
	_ok("② ★本机换路后没有残留徽章(%d 个采样步里共 %d 个, 走过 %d 路)" % [_steps, _nat_orph, _nat_lanes.size()],
		_nat_orph == 0 and _nat_lanes.size() >= 2, "例 " + _nat_orph_ex)
	_ok("③ ★播放端没有残留徽章(%d 个)" % _pl_orph, _pl_orph == 0, "例 " + _pl_orph_ex)
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 头顶徽章直播一致 / 换路不残留" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _run_one(job: Dictionary) -> void:
	_nat = {}
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if rec._step_n % FMT.CONT_EVERY != 0 or s % 30 != 0:
					return
				var r := _count(bt, bt._units)
				_nat[s] = r[0]
				_nat_lanes[int(bt._dl_sys.lane_epoch)] = true
				if int(r[1]) > 0:
					_nat_orph += int(r[1])
					if _nat_orph_ex == "":
						_nat_orph_ex = "换路纪元 %d · %s" % [int(bt._dl_sys.lane_epoch), str(r[2])]
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	print("  本机一遍: %d 块 · 采样 %d 步" % [chunks.size(), _nat.size()])
	if chunks.is_empty():
		_ok("录到了流", false)
		return
	var gs = get_node_or_null("/root/GameState")
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	gs.season_leaders = []
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
	var guard := 0
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 400000:
		guard += 1
		p.advance(SIM_DT)
		if _nat.has(p.cur_step):
			var r := _count(b, p.units.values())
			_add(_nat_tot, _nat[p.cur_step])
			_add(_pl_tot, r[0])
			_steps += 1
			if int(r[1]) > 0:
				_pl_orph += int(r[1])
				if _pl_orph_ex == "":
					_pl_orph_ex = "步 %d · %s" % [p.cur_step, str(r[2])]
			_nat.erase(p.cur_step)
		if guard % 60 == 0:
			await get_tree().process_frame
	print("  播放端: 状态 %s · 剩 %d 个采样步没对上" % [p.state, _nat.size()])
	b.queue_free()
	await get_tree().process_frame
