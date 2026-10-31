extends Node
## verify_stream_curtain_stats.gd — 看服务器正在算的局(跟播自己这一局 / 赛况板观赛)时: 有幕布、开场与路间按 1 倍走、伤害统计与本机一致。
##
## 用户 2026-10-31(周六闯关, 0.22.6):
##   「所有数据都没有统计啊？」⇒ 战中 📊 面板 / 结算屏读单位身上的 `_st_*` 与各路战报 `_st_lane_hist`, 原来一项都不在状态流里(全是 0)。
##   「就开始匹配的时候就直接两队就开打了，什么都不显示…上半场打完之后马上就清窗，然后下半场开始打」
##     ⇒ 入口拿不到对手完整阵容(no_curtain)⇒ 不建幕布, 开场那段一帧跳过、路间 10 倍走。
## 改法: 录流器把开局状态(`rs`, = 录像里那份 state)、单位统计字段(UKEYS_ST)、各路战报(`slh`)放进流; 播放器收到 `rs` 就照常建幕布。
##
## 同一进程: 先原生跑一局裁判局(录流, 块留在内存), 每步记下幕布状态与统计; 再按「跟播自己这一局」的入口形状播
## (begin_play 只给 dual_active、no_curtain = true、GameState 里的阵容先抹掉 ⇒ 幕布只能靠流里的 rs 建), 逐项比。
## ★分母: 原生幕布那几段的步数、各路战报份数、单位行数都 > 0; 断言里打印。

const J := preload("res://tests/_stream_jobs.gd")
const SIM_DT := 1.0 / 60.0
const GAP := ["overview", "preview", "lane_settle"]
const ROW_KEYS := ["id", "name", "rarity", "_st_multi", "_st_dealt", "_st_taken", "_st_heal", "_st_shield", "_st_kills", "_st_crit",
	"_st_phy", "_st_mag", "_st_tru"]

var _fail := 0
var _n := 0
## 原生: 幕布各段的步数 / 最后一步的各路战报与当前路行
var _nat_gap := {}
var _nat_hist: Array = []
var _nat_cur: Array = []


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


## 一行 → 比对用的签名(只取统计与身份; 装备统计键 `_st_eq|…` 一并带上)
static func _sig(side: String, r: Dictionary) -> String:
	var parts: Array = [side]
	for k in ROW_KEYS:
		parts.append(str(r.get(k, "")))
	var eq: Array = []
	for k in r.keys():
		if str(k).begins_with(EquipTally.ROW_PREFIX):
			eq.append("%s=%s" % [str(k), str(r[k])])
	eq.sort()
	parts.append(",".join(eq))
	return "|".join(parts)


static func _cur_rows(b) -> Array:
	var out: Array = []
	for u in b._units:
		var sd := str(u.get("side", ""))
		if sd == "left" or sd == "right":
			out.append(_sig(sd, b._st_row(u)))
	out.sort()
	return out


static func _hist_rows(b) -> Array:
	var out: Array = []
	for snap in b._st_lane_hist:
		var one: Array = []
		for sd in ["left", "right"]:
			for r in snap[sd]:
				one.append(_sig(sd, r))
		one.sort()
		out.append([str(snap["lane"]), one])
	return out


static func _sum_dealt(rows: Array) -> int:
	var s := 0
	for x in rows:
		s += int(str(x).split("|")[5])
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var job: Dictionary = J.mirror(gs)
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(_s: int) -> void:
				var dl := str(bt._dl_state)
				if dl in GAP:
					_nat_gap[dl] = int(_nat_gap.get(dl, 0)) + 1
				_nat_hist = _hist_rows(bt)
				_nat_cur = _cur_rows(bt)
			, CONNECT_ONE_SHOT)
	var res: Dictionary = await RefereeRunner.run(self, job, hook, {"keep": true})
	var chunks: Array = res.get("stream_chunks", [])
	_ok("分母 · 原生一遍三路打满、录到块(开打 %d 路 · %d 块)" % [int(res.get("fights", 0)), chunks.size()],
		bool(res.get("ok", false)) and int(res.get("fights", 0)) == 3 and chunks.size() > 100)
	_ok("分母 · 原生幕布三段都走过(%s)" % str(_nat_gap), int(_nat_gap.get("overview", 0)) > 60
		and int(_nat_gap.get("preview", 0)) > 60 and int(_nat_gap.get("lane_settle", 0)) > 60)
	_ok("分母 · 原生各路战报 %d 份、当前路 %d 行、伤害合计 %d" % [_nat_hist.size(), _nat_cur.size(),
		_sum_dealt(_nat_cur) + _hist_dealt(_nat_hist)], _nat_hist.size() >= 2 and _nat_cur.size() > 0
		and _sum_dealt(_nat_cur) + _hist_dealt(_nat_hist) > 0)
	var ta: Array = await _play(chunks, res.get("stream", {}), RefereeJob.seed_of(job), "a")
	## B 方视角(周六配对局我是 B): 流是按 A 方录的, 幕布「我方」要换成看的人那一侧 ⇒ 每路战报的胜负 / 比分正好对调
	var tb: Array = await _play(chunks, res.get("stream", {}), RefereeJob.seed_of(job), "b")
	var want: Array = []
	for x in ta:
		want.append(_swap_text(str(x)))
	_ok("分母 · A 方看到的路间战报字样 %d 条(%s)" % [ta.size(), str(ta)], ta.size() >= 4)
	_ok("★★B 方看到的路间战报 = A 方胜负 / 比分对调(%s)" % str(tb), tb == want and not tb.is_empty(), "要 %s" % str(want))
	print("")
	print("  [量] 用了 %d 帧" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS — 跟播 / 观赛有幕布、开场与路间 1 倍、统计与本机一致 (%d 条)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


## A 方字样 → B 方应看到的: 胜利 ↔ 失败, 「我方 X : Y 对方」⇒「我方 Y : X 对方」
static func _swap_text(t: String) -> String:
	if t.begins_with("本战场"):
		return t.replace("胜利", "#").replace("失败", "胜利").replace("#", "失败")
	var re := RegEx.new()
	re.compile("我方 (\\d+) : (\\d+) 对方")
	var m := re.search(t)
	if m != null:
		return t.substr(0, m.get_start()) + "我方 %s : %s 对方" % [m.get_string(2), m.get_string(1)] + t.substr(m.get_end())
	return t


## 幕布浮层里「本战场…」「各路战果…」两行字
static func _settle_texts(pr: Node) -> Array:
	var out: Array = []
	for l in pr.find_children("*", "Label", true, false):
		var t := str((l as Label).text)
		if t.begins_with("本战场") or t.begins_with("各路战果"):
			out.append(t)
	return out


static func _only(a: Array, b: Array) -> Array:
	var out: Array = []
	for x in a:
		if not (x in b):
			out.append(x)
	return out


static func _hist_dealt(h: Array) -> int:
	var s := 0
	for x in h:
		s += _sum_dealt(x[1])
	return s


## 按「跟播自己这一局」(stream_watch.enter_own_live)的入口形状播: 开局状态只给 dual_active, no_curtain。
##   `side` = 看的人是 A 还是 B(ReplayRecorder.play_names.side); 返回路间战报幕布上的胜负 / 比分字样(按出现顺序、去重)。
##   统计与节奏只在 A 那一遍比(B 只换视角, 数据同一份)。
func _play(chunks: Array, meta: Dictionary, seed: int, side: String) -> Array:
	var gs = get_node_or_null("/root/GameState")
	var au = get_node_or_null("/root/Audio")
	if au != null:
		au.mute_sfx = true
	ReplayRecorder.begin_play({"state": {"dual_active": true}})
	ReplayRecorder.pending_play = {}
	ReplayRecorder.play_names = {"side": side} if side == "b" else {}
	## 本机 GameState 里的阵容抹掉: 幕布只能靠流里的 rs 建(否则读到的是原生那一遍留下的阵容, 断言恒真)
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
	_ok("分母 · [%s] 播放模式建起来了" % side, p != null and str(b._replay.mode) == "stream")
	var texts: Array = []
	if p == null:
		return texts
	var calls := {}            # 幕布各段: 推了几次(每次 2 步 = 1 倍)
	var shown := {}            # 幕布各段: 其中幕布浮层在场的次数
	var guard := 0
	var first_dl := ""
	p.advance(0.0)
	while p.state != "ended" and p.state != "error" and guard < 400000:
		guard += 1
		p.advance(2.0 * SIM_DT)
		var dl := str(b._dl_state)
		if first_dl == "" and dl != "":
			first_dl = dl
		if dl in GAP:
			calls[dl] = int(calls.get(dl, 0)) + 1
			var pr = b.get("_dl_present_root")
			if pr != null and is_instance_valid(pr) and (pr as CanvasItem).is_visible_in_tree():
				shown[dl] = int(shown.get(dl, 0)) + 1
				if dl == "lane_settle":
					for t in _settle_texts(pr):
						if not (t in texts):
							texts.append(t)
		if guard % 30 == 0:
			await get_tree().process_frame
	_ok("[%s] 播到结尾" % side, p.state == "ended", "%s %s" % [p.state, p.err])
	if side != "a":
		b.queue_free()
		await get_tree().process_frame
		ReplayRecorder.end_play()
		await get_tree().process_frame
		return texts
	_ok("★流里带来了开局状态(rs), 播放器改成有幕布", p.state_from_stream and not p._no_curtain)
	_ok("★开场没被跳过: 播放头第一次落在「%s」(不是直接开打)" % first_dl, first_dl == "overview" or first_dl == "preview")
	for dl in GAP:
		var nat := int(_nat_gap.get(dl, 0))
		var c := int(calls.get(dl, 0))
		## 1 倍: 每次推 2 步 ⇒ 次数 ≈ 原生步数 / 2(10 倍或一帧跳过时只有 1/10 或 0)
		_ok("★「%s」按 1 倍走: 推了 %d 次 ≈ 原生 %d 步 / 2" % [dl, c, nat], nat > 0 and absi(c * 2 - nat) <= 8)
		_ok("★「%s」幕布浮层在场 %d / %d 次(≥ 80%%)" % [dl, int(shown.get(dl, 0)), c], c > 0 and int(shown.get(dl, 0)) * 10 >= c * 8)
	var ph := _hist_rows(b)
	var pc := _cur_rows(b)
	_ok("★各路战报份数一致(本机 %d / 流 %d)" % [_nat_hist.size(), ph.size()], ph.size() == _nat_hist.size() and ph.size() >= 2)
	var hist_bad: Array = []
	for i in range(mini(ph.size(), _nat_hist.size())):
		if str(ph[i][0]) != str(_nat_hist[i][0]) or ph[i][1] != _nat_hist[i][1]:
			hist_bad.append("第 %d 份 %s: 本机 %s / 流 %s" % [i, str(_nat_hist[i][0]), str(_nat_hist[i][1]).left(300), str(ph[i][1]).left(300)])
	_ok("★★各路战报逐行一致(身份 + 伤害 / 承伤 / 治疗 / 护盾 / 击杀 / 暴击 / 物魔真 / 装备统计)", hist_bad.is_empty() and not ph.is_empty(),
		str(hist_bad.slice(0, 2)))
	_ok("★★最后一路逐行一致(%d 行, 伤害合计 本机 %d / 流 %d)" % [pc.size(), _sum_dealt(_nat_cur), _sum_dealt(pc)],
		pc == _nat_cur and _sum_dealt(pc) > 0, "只在本机 %s\n      只在流 %s" % [str(_only(_nat_cur, pc)), str(_only(pc, _nat_cur))])
	b.queue_free()
	await get_tree().process_frame
	ReplayRecorder.end_play()
	await get_tree().process_frame
	return texts
