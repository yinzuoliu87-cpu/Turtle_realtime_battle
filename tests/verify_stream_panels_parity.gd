extends Node
## verify_stream_panels_parity.gd — 看服务器算的局（播状态流）时，局内的信息面板与 📊 统计面板和「本机直接跑」逐字一致。
##
## 由来：用户 2026-11-03（积分赛第一天改服务器裁判、手机播流）：
##   「怎么对局内所有的信息系统、统计系统全崩掉了？」「统计面板、伤害统计、装备统计、属性，全坏掉了呀。」
##   探针 tests/probes/_probe_stream_panels.gd 播正式服当天真实流：信息面板属性一栏全是默认值（攻击 0 / 攻速 1.00 / 暴击 0% / 射程 70）——
##   录流器只录了画面要的单位字段，面板读的属性没进流。verify_stream_hud_parity 只比播放时屏上本来就看得见的字，
##   从没在播放模式下点开过信息面板 / 统计各页签，所以一直没红。
##
## 同一进程：先原生跑一局裁判局（同时录流），对局中段若干采样步上：每只活着的单位各点开一次信息面板，读回面板里全部可见文字；
## 再点开 📊，四个页签（造成 / 受到 / 治疗 / 护盾）各读一遍。然后按「跟播自己这一局」的入口形状播刚录的流，
## 在同一批步号上做同样的事，逐字比。不一致时打印两边差的那几行（缺哪个字段从这里看）。
## ★分母：比过的采样步数、单位面板数、统计页签数都 > 0，并打印。
const J := preload("res://tests/_stream_jobs.gd")
const SIM_DT := 1.0 / 60.0
const TABS := ["dealt", "taken", "heal", "shield"]
const EVERY := 1100        # 每隔这么多步（只在交战段）拍一次
const MAX_SNAPS := 6

var _fails := 0
var _nat := {}             # 步号 → {"units": {idx: [文字…]}, "stats": {tab: [文字…]}}
var _next := 600


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] " + name)
	else:
		_fails += 1
		print("  [FAIL] " + name + ("" if detail == "" else "\n      " + detail))


func _ready() -> void:
	print("=== verify_stream_panels_parity ===")
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	var job: Dictionary = J.mirror(gs)
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				if _nat.size() >= MAX_SNAPS or s < _next or str(bt._dl_state) != "fight":
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
	_ok("分母 · 原生一遍录到块（%d 块）、交战段拍到 %d 个采样步" % [chunks.size(), _nat.size()], chunks.size() > 50 and _nat.size() >= 3)
	await _play_and_compare(chunks, res.get("stream", {}), RefereeJob.seed_of(job))
	if _fails == 0:
		print("ALL PASS")
	else:
		print("FAIL x%d" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _texts(n: Node, out: Array) -> void:
	if n is Label or n is RichTextLabel or n is Button:
		var t := str(n.get("text")).strip_edges()
		if t != "" and (n as CanvasItem).is_visible_in_tree():
			out.append(t.replace("\n", " / "))
	for c in n.get_children():
		_texts(c, out)


## 像玩家那样点开：每只活着的单位一个信息面板 + 📊 四个页签。
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
		var ip = b.get("_info_panel")
		if ip != null and is_instance_valid(ip):
			_texts(ip, tx)
		units[i] = tx
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


## 「跟播自己这一局」的入口形状（stream_watch.enter_own_live）：开局状态只给 dual_active、no_curtain、本机阵容抹掉。
func _play_and_compare(chunks: Array, meta: Dictionary, seed: int) -> void:
	var gs = get_node_or_null("/root/GameState")
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {}
	gs.dual_lineup = {}
	gs.dual_ghost = {}
	gs.season_leaders = []
	StreamPlayer.pending = {"source": StreamSource.Mem.new(chunks, meta), "seed": seed, "no_curtain": true}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	add_child(b)
	StreamPlayer.pending = {}
	b.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var p: StreamPlayer = b._replay.player
	_ok("分母 · 播放模式建起来了", p != null and str(b._replay.mode) == "stream")
	if p == null:
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
	_ok("分母 · 播放端在同一批步号上都拍到（%d / %d）" % [got.size(), _nat.size()], got.size() == _nat.size() and got.size() >= 3)
	var n_units := 0
	var n_tabs := 0
	var unit_bad: Array = []
	var stat_bad: Array = []
	var steps: Array = _nat.keys()
	steps.sort()
	for s in steps:
		if not got.has(s):
			continue
		var nu: Dictionary = _nat[s]["units"]
		var pu: Dictionary = got[s]["units"]
		for i in nu:
			n_units += 1
			var a: Array = nu[i]
			var c: Array = pu.get(i, [])
			if not _same_lines(a, c):
				unit_bad.append("步 %d 单位 #%d %s：只在本机 %s ｜ 只在流 %s" % [s, i, (str(a[0]) if a.size() > 0 else "?"),
					str(_only(a, c)).left(400), str(_only(c, a)).left(400)])
		var ns: Dictionary = _nat[s]["stats"]
		var ps: Dictionary = got[s]["stats"]
		for tab in TABS:
			if not ns.has(tab):
				continue
			n_tabs += 1
			if ns[tab] != ps.get(tab, []):
				stat_bad.append("步 %d 页签 %s：只在本机 %s ｜ 只在流 %s" % [s, tab, str(_only(ns[tab], ps.get(tab, []))).left(400),
					str(_only(ps.get(tab, []), ns[tab])).left(400)])
	print("  分母：采样步 %d · 单位面板 %d · 统计页签 %d · 龟能取整按 ±1 放过 %d 处" % [got.size(), n_units, n_tabs, _energy_tol])
	_ok("龟能 ±1 放宽只覆盖个别边界（%d ≤ 面板数 / 20）" % _energy_tol, _energy_tol * 20 <= maxi(n_units, 1))
	_ok("★信息面板（属性 / 技能 / 装备 / 状态）逐字一致（%d 个面板，不一致 %d）" % [n_units, unit_bad.size()],
		n_units >= 10 and unit_bad.is_empty(), "\n      ".join(unit_bad.slice(0, 6)))
	_ok("★📊 统计四页签逐字一致（%d 个页签，不一致 %d）" % [n_tabs, stat_bad.size()],
		n_tabs >= 4 * 3 and stat_bad.is_empty(), "\n      ".join(stat_bad.slice(0, 6)))
	b.queue_free()
	await get_tree().process_frame
	ReplayRecorder.end_play()
	await get_tree().process_frame


## 逐行比; 唯一的放宽: 「龟能  当前 / 上限」上限相同、当前差 ≤ 1 算一致。
##   ★已知未查清（2026-11-03 方案书风险）: 原生在录流器 on_sampled 回调时拍（渲染步之后）, 播放端在采样步拍;
##   龟能 = 冷却进度 × 花费再取整, 卡在整数边界时差 1（52 个面板里 1 个）。其余任何一个字不同都算红。
var _energy_tol := 0
var _energy_re := RegEx.create_from_string("^龟能  (\\d+) / (\\d+)$")

func _same_lines(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if a[i] == b[i]:
			continue
		var ma := _energy_re.search(str(a[i]))
		var mb := _energy_re.search(str(b[i]))
		if ma != null and mb != null and ma.get_string(2) == mb.get_string(2) \
				and absi(int(ma.get_string(1)) - int(mb.get_string(1))) <= 1:
			_energy_tol += 1
			continue
		return false
	return true


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
