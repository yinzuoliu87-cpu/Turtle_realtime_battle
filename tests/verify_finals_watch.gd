extends Node
## verify_finals_watch.gd — 周日开播: 开场 VS + 观战页(方案书 docs/plans/20261031c-周日赛事界面重做.md §4 C ①⑤⑥⑦ · G6 G17 G19 G20 G24)
##
## 量需求本身:
##   A 纯函数: 对阵图一组 → 这一场的身份(谁对谁 / 我是谁 / 轮次名 / 第几场 / 下一场); 阶段标签; 拔河条; 三路灯
##   B ★开场 VS(G6): 轮次名 + 双方名牌(名字 / 头像 / 来历 / 战绩)+ 双方锁定阵容按路逐只翻出 + 迷你对阵点亮本场 +「阵容已锁定 · 服务器实时演算」
##      + 3 → 2 → 1 →「开战」自己走完收掉; 约 6 秒; 决赛整套换金; 两种比例下各块不重叠、不出屏
##   C ★接线: 周日开播按时进来 ⇒ 播放前先出开场 VS; 迟到(G17)⇒ 不放 VS、默认实时、有「从头看」(按下 = 播放器跳到开头, 再按回直播);
##      不是决赛日 / 是回放 ⇒ 这一层不建
##   D ★观战页(G19 G20 G24): 阶段标签「冠军杯赛半决赛第 1 场」+「开播中」; 比分条 + 三路灯(赢一路亮一盏); 拔河条跟着单位表的剩余血量走;
##      下一场条; 固定表情助威(按下飘起来, 连点有间隔); 路间幕布上压「上路战场战果 / X 赢得上路 / 1 : 0」;
##      收尾出来后这几样收起; 不出现胜率 / 本场还剩 / 观看人数; 两种比例下不重叠、不出屏、不压退出键
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_finals_watch.tscn
## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 观战页那几句去掉「·」拼接 / 口语(「去看」「输给」「拿下」), 期望值跟着改, 判据(量哪个节点、几时出现)一个不动。

const RC := preload("res://scripts/scenes/battle/replay_controls.gd")
const VS := preload("res://scripts/scenes/battle/finals_vs_intro.gd")
const HUD := preload("res://scripts/scenes/battle/finals_watch_hud.gd")
const Ctx := preload("res://scripts/scenes/battle/finals_ctx.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


class FakePlayer extends RefCounted:
	var controls := false
	var hold_text := ""
	var state := "playing"
	var first_step := 0
	var applied := 0
	var paused := false
	var speed := 1.0
	var seeks: Array = []
	func seek(t: int) -> bool:
		seeks.append(t)
		applied = t
		return true
	func total_steps() -> int:
		return 6720


class FakeReplay extends RefCounted:
	var mode := "stream"
	var live = null
	var rec: Dictionary = {}
	var finished := false
	var diverged_at := -1
	var speed := 1.0
	var paused := false
	var player = null
	func is_live() -> bool:
		return live != null and mode == "play"
	func total_steps() -> int:
		return 6720
	func fight_steps() -> Array:
		return [600, 2400, 4800]
	func cycle_speed() -> float:
		return speed


class FakeHud extends RefCounted:
	var exits := 0
	func _replay_exit() -> void:
		exits += 1


class FakeBattle extends Node:
	var _replay
	var _hud
	var _dmg_stats = null
	var _ui_layer: CanvasLayer = null
	var _sim_step_n := 0
	var _units: Array = []
	var _dl_state := "overview"
	var _dl_pending_loser := ""


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


const STAGE := {"cup": true, "group": 0, "round": 2, "rounds": 3, "round_name": "半决赛", "next_name": "决赛", "match_i": 1, "match_n": 2}
const NEXT := {"a": "甲乙丙", "b": "丁戊己", "at": 0, "r": 2, "m": 1}
const PN := {"l": "", "r": "", "pair": ["吃货一枚", "小辉同学"], "me": -1, "stage": STAGE, "next": NEXT, "view": "finals",
	"bucket": 1000000, "mini": {"n": 8, "r": 2, "m": 0},
	"cards": [{"origin": "B 组冠军", "record": "闯关 9 胜 2 负"}, {"group": 4, "record": "闯关 8 胜 3 负", "title": "卫冕"}]}


func _ready() -> void:
	print("=== 周日开播: 开场 VS + 观战页 ===")
	var gs = get_node("/root/GameState")
	gs.test_mode = true
	var keep := {"lr": gs.lane_results, "cur": gs.current_lane, "ld": gs.season_leaders, "dg": gs.dual_ghost, "lu": gs.dual_lineup,
		"pn": ReplayRecorder.play_names, "vn": ReplayRecorder.viewer_name, "rs": ReplayRecorder.return_scene, "sw": SW.current}
	gs.season_leaders = ["angel", "stone", "bamboo"]
	gs.dual_lineup = {"top": [{"kind": "leader", "slot": 0}, {"kind": "minion", "role": "front"}],
		"bottom": [{"kind": "leader", "slot": 1}, {"kind": "leader", "slot": 2}, {"kind": "minion", "role": "back"}]}
	gs.dual_ghost = {"leaders": ["candy", "ninja", "ghost"], "lane_assign": {"top": ["candy"], "bottom": ["ninja", "ghost"]},
		"minions": {"top": [{"role": "front"}, {"role": "back"}], "bottom": [{"role": "front"}]},
		"profile": {"name": "小辉同学", "avatar": "candy"}}
	_t_pure()
	await _t_vs()
	await _t_wiring()
	await _t_hud()
	gs.lane_results = keep["lr"]
	gs.current_lane = keep["cur"]
	gs.season_leaders = keep["ld"]
	gs.dual_ghost = keep["dg"]
	gs.dual_lineup = keep["lu"]
	ReplayRecorder.play_names = keep["pn"]
	ReplayRecorder.viewer_name = keep["vn"]
	ReplayRecorder.return_scene = keep["rs"]
	SW.current = keep["sw"]
	print("=== %d 项, %d FAIL ===" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)


# A ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	## 冠军杯 8 人: 第 1 轮全打完(done 全), 第 2 轮已翻面(round = 3), 档期: 第 2 轮 m1 先播、m0 后播
	var b := {"size": 8, "round": 3, "bucket": P2C.FINALS_CUP_BUCKET, "me": 2, "closed": false, "round_at": 5000,
		"names": ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7"],
		"done": {"1-0": 0, "1-1": 1, "1-2": 0, "1-3": 1, "2-0": 1, "2-1": 0},
		"seq": {"v": 1, "until": 6000, "p": {"2-1": [1000, 1200], "2-0": [1225, 1500]}}}
	var f: Dictionary = Ctx.from_bucket(b, 2, 1, 1100, "finals")
	_ok("A 分母: 这一场拿到身份", not f.is_empty(), str(f))
	var st: Dictionary = f.get("stage", {})
	_ok("A 轮次: 冠军杯 · 半决赛 / 下一轮叫决赛 / 第 1 / 2 场(按档期先后, m1 先播)", bool(st.get("cup", false))
		and str(st.get("round_name", "")) == "半决赛" and str(st.get("next_name", "")) == "决赛" and int(st.get("match_i", 0)) == 1
		and int(st.get("match_n", 0)) == 2, str(st))
	var pair: Array = f.get("pair", [])
	_ok("A 谁对谁 / 我不在这一场(me = -1)", pair.size() == 2 and str(pair[0]) != "" and str(pair[1]) != "" and int(f.get("me", 9)) == -1, str(f))
	var nx: Dictionary = f.get("next", {})
	_ok("A ★下一场 = 本轮档期里的下一场(m0, 1225 开播)", int(nx.get("m", -1)) == 0 and int(nx.get("at", 0)) == 1225 and str(nx.get("a", "")) != "",
		str(nx))
	var f0: Dictionary = Ctx.from_bucket(b, 2, 0, 1300, "finals")
	_ok("A 本轮最后一场 ⇒ 下一场 = 下一轮第一场(决赛, 两边由 done 推出)", int((f0["next"] as Dictionary).get("r", 0)) == 3
		and str((f0["next"] as Dictionary).get("a", "")) != "" and str((f0["next"] as Dictionary).get("b", "")) != "", str(f0))
	b["me"] = 0
	_ok("A 我在这一场 ⇒ me = 我在 pair 里的位置", int(Ctx.from_bucket(b, 1, 0, 1300, "finals").get("me", -1)) == 0)
	_ok("A 阶段标签「冠军杯赛半决赛第 1 场」/ 小组「小组赛 C 组决赛」(组名一律字母)(只一场不写场次)",
		Ctx.stage_tag(STAGE) == "冠军杯赛半决赛第 1 场"
		and Ctx.stage_tag({"group": 3, "round": 2, "rounds": 2, "round_name": "决赛", "match_i": 1, "match_n": 1}) == "小组赛 C 组决赛",
		Ctx.stage_tag(STAGE))
	_ok("A 「观看 甲乙丙 对 丁戊己」/ 下一场条 / 出局那一句", Ctx.go_label(NEXT) == "观看 甲乙丙 对 丁戊己"
		and Ctx.next_line(NEXT) == "下一场：甲乙丙 对 丁戊己" and Ctx.out_line(STAGE, "乙") == "止步半决赛，不敌 乙"
		and Ctx.go_label({}) == "")
	_ok("A 下一场时刻还没排(备战结束到翻面之间)⇒ 下一场条写「下一场即将开播：甲 对 乙」",
		Ctx.next_line({"a": "甲", "b": "乙", "at": 0, "settling": true}) == "下一场即将开播：甲 对 乙")
	var tg: Array = Ctx.tug([{"side": "left", "hp": 300.0, "alive": true}, {"side": "right", "hp": 100.0, "alive": true},
		{"side": "right", "hp": 500.0, "alive": false}])
	_ok("A ★拔河条 = 活着的单位剩余血量之比(死了的不算): 300 : 100 ⇒ 0.75", is_equal_approx(Ctx.tug_frac(tg), 0.75), str(tg))
	var lp: Array = Ctx.lamps({"top": "left"}, "bottom")
	_ok("A 三路灯: 上路亮左 / 下路正在打 / 终极未到; 比分 1 : 0", str(lp) == str([["top", "left", false], ["bottom", "", true], ["final", "", false]])
		and str(Ctx.lamp_score(lp)) == str([1, 0]), str(lp))


# B ─────────────────────────────────────────────────────────────
func _vs_info(gold: bool) -> Dictionary:
	var st := STAGE.duplicate()
	if gold:
		st = {"cup": true, "round": 3, "rounds": 3, "round_name": "决赛"}
	return {"title": Ctx.round_title(st), "sub": "第 1 / 2 场" if not gold else "", "gold": gold, "note": Ctx.TXT_LOCKED,
		"mini": {"n": 8, "r": 3 if gold else 2, "m": 0},
		"cards": {"left": {"name": "吃货一枚", "pid": "angel", "origin": "B 组冠军", "record": "闯关 9 胜 2 负"},
			"right": {"name": "小辉同学", "pid": "candy", "origin": "E 组冠军", "record": "闯关 8 胜 3 负", "title": "卫冕"}},
		"lineups": {"left": [["top", [{"pid": "angel", "minion": false}, {"pid": "", "minion": true}]],
				["bottom", [{"pid": "stone", "minion": false}, {"pid": "bamboo", "minion": false}, {"pid": "", "minion": true}]]],
			"right": [["top", [{"pid": "candy", "minion": false}, {"pid": "", "minion": true}, {"pid": "", "minion": true}]],
				["bottom", [{"pid": "ninja", "minion": false}, {"pid": "ghost", "minion": false}, {"pid": "", "minion": true}]]]}}


func _t_vs() -> void:
	for gold in [false, true]:
		var tag := "决赛(金)" if gold else "半决赛"
		var host := Control.new()
		host.size = Vector2(1560, 720)
		add_child(host)
		var v := VS.new()
		var done_calls := [0]
		v.on_done = func() -> void: done_calls[0] += 1
		var root: Control = v.build(host, _vs_info(gold), Vector2(1560, 720))
		_ok("B %s 分母: 建出开场 VS" % tag, root != null and root.name == VS.N_ROOT)
		var tl := root.find_child(VS.N_TITLE, true, false) as Label
		_ok("B %s ① 轮次名「%s」" % [tag, "冠军杯赛决赛" if gold else "冠军杯赛半决赛"], tl != null
			and tl.text == ("冠军杯赛决赛" if gold else "冠军杯赛半决赛"), tl.text if tl != null else "<无>")
		var crest := root.find_child(VS.N_CREST, true, false) as TextureRect
		_ok("B %s ★决赛整套换金: 徽章 = %s, 轮次名金字" % [tag, "vs-crest-gold" if gold else "vs-crest"], crest != null and crest.texture != null
			and crest.texture.resource_path.get_file() == ("vs-crest-gold.png" if gold else "vs-crest.png")
			and ((tl.get_theme_color("font_color") == VS.COL_GOLD) == gold))
		if gold:
			host.queue_free()
			await _frames(1)
			continue
		var nl := root.find_child(VS.N_NAME + "left", true, false) as Label
		var nr := root.find_child(VS.N_NAME + "right", true, false) as Label
		var ol := root.find_child(VS.N_ORIGIN + "right", true, false) as Label
		var rr := root.find_child(VS.N_RECORD + "left", true, false) as Label
		_ok("B ① 名牌: 名字 / 来历(带头衔「E 组冠军（卫冕）」(组号 4 ⇒ E 组, ChampionData.group_name))/ 本周战绩", nl != null and nl.text == "吃货一枚" and nr != null and nr.text == "小辉同学"
			and ol != null and ol.text == "E 组冠军（卫冕）" and rr != null and rr.text == "闯关 9 胜 2 负")
		var chips: Array = root.find_children(VS.N_CHIP + "*", "", true, false)
		_ok("B ① ★双方锁定阵容按路摆开(5 + 6 = 11 只)", chips.size() == 11, str(chips.size()))
		var avr := (root.find_child(VS.N_CARD + "left", true, false) as Node).find_child("Portrait", true, false) as Control
		_ok("B ① ★整屏要满: 名牌头像 ≥ 160(%.0f)、阵容头像 ≥ 72(%.0f)、名字 40 号" % [avr.size.x if avr != null else -1.0,
			(chips[0] as Control).size.x if not chips.is_empty() else -1.0], avr != null and avr.size.x >= 160.0
			and not chips.is_empty() and (chips[0] as Control).size.x >= 72.0 and nl.get_theme_font_size("font_size") >= 40)
		var mini := root.find_child(VS.N_MINI, true, false) as Control
		_ok("B ① ★迷你对阵点亮本场那条线(2-0)", mini != null and str(mini.get_meta("lit", "")) == "2-0")
		v.pose(2.0)
		var cr_r: Rect2 = crest.get_global_rect()
		_ok("B ① ★迷你对阵在盾徽正下方居中、放大(宽 %.0f)" % (mini.size.x if mini != null else -1.0), mini != null
			and mini.position.y >= cr_r.end.y and absf(mini.position.x + mini.size.x * 0.5 - 780.0) <= 2.0 and mini.size.x >= 300.0)
		var note := root.find_child(VS.N_NOTE, true, false) as Label
		_ok("B ① 一行实话「双方阵容已锁定，由服务器实时演算」", note != null and note.text == "双方阵容已锁定，由服务器实时演算")
		## 时间轴
		v.pose(0.0)
		var card_l := root.find_child(VS.N_CARD + "left", true, false) as Control
		var x_mid: float = 0.0
		v.pose(0.45)
		x_mid = card_l.position.x
		v.pose(1.0)
		_ok("B ② ★名牌真的在滑入(0.45 秒 x=%.0f → 1.0 秒 x=%.0f)" % [x_mid, card_l.position.x], absf(x_mid - card_l.position.x) > 20.0)
		v.pose(0.82)
		var cs_mid: float = crest.scale.x
		v.pose(1.2)
		_ok("B ② ★徽章砸下(0.82 秒 ×%.2f → 1.2 秒 ×%.2f)" % [cs_mid, crest.scale.x], cs_mid > 1.2 and is_equal_approx(crest.scale.x, 1.0))
		var seq_ok := true
		for i in range(v._chips.size()):
			var t0: float = v._chips[i][1]
			v.pose(t0 - 0.02)
			var before: float = (v._chips[i][0] as Control).modulate.a
			v.pose(t0 + 0.3)
			var after: float = (v._chips[i][0] as Control).modulate.a
			if before > 0.0 or after < 1.0:
				seq_ok = false
		var t_last: float = v._chips[v._chips.size() - 1][1]
		_ok("B ② ★阵容逐只翻出(每只到点才出现; 最后一只 %.1f 秒, 在倒数之前)" % t_last, seq_ok and t_last < VS.T_COUNT)
		_ok("B ② 倒数 3 → 2 → 1(3.2 / 3.8 / 4.5 秒), 之前之后都没有", VS.count_at(3.2) == 3 and VS.count_at(3.8) == 2
			and VS.count_at(4.5) == 1 and VS.count_at(2.9) == 0 and VS.count_at(5.1) == 0)
		v.pose(5.2)
		var go := root.find_child(VS.N_GO, true, false) as Label
		_ok("B ② 「开战」5 秒起出现(大字美术字)", go != null and go.visible and go.text == "开战" and go.get_node_or_null(Ctx.ART_NODE) != null)
		var cnt_l := root.find_child(VS.N_COUNT, true, false) as Label
		v.pose(3.8)
		_ok("B ② 倒数数字是美术字(3.8 秒 = 2 ⇒ bt-n2)", cnt_l != null and cnt_l.text == "2"
			and (cnt_l.get_node(Ctx.ART_NODE) as TextureRect).texture.resource_path.get_file() == "bt-n2.png")
		_ok("B ② ★总长 %.1f 秒(G6: 约 6 秒, 5.5~6.5)" % VS.DUR, VS.DUR >= 5.5 and VS.DUR <= 6.5)
		## 两种比例版式(2.8 秒: 名牌 / 阵容 / 迷你对阵 / 那一行都在)
		await _vs_layout()
		## 自己走完收掉
		v.t = VS.DUR - 0.02
		var tw := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tw < 1000 and not bool(v.done):
			await get_tree().process_frame
		await _frames(1)
		_ok("B ② ★不点也会自己走完、收掉、回调一次", bool(v.done) and int(done_calls[0]) == 1 and not is_instance_valid(root))
		var v2 := VS.new()
		v2.build(host, _vs_info(false), Vector2(1560, 720))
		var had := get_tree().get_nodes_in_group(Ctx.BAR_DOCK).filter(func(n): return str(n.name) == VS.N_BAR_DOCK).size()
		v2.finish()
		var left := get_tree().get_nodes_in_group(Ctx.BAR_DOCK).filter(func(n): return str(n.name) == VS.N_BAR_DOCK).size()
		_ok("B ② 收掉那一刻(同一帧)停靠位已退组, 全局小条不会挑到正在消失的那一块(收掉前 %d / 后 %d)" % [had, left], had == 1 and left == 0)
		host.queue_free()
		await _frames(1)


func _vs_layout() -> void:
	var bad: Array = []
	var nr := 0
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		var host := Control.new()
		host.size = vp
		add_child(host)
		var v := VS.new()
		var root: Control = v.build(host, _vs_info(false), vp)
		v.t = 2.9                          # 每帧接着从这里往前走(不然下一帧又从 0 摆回去)
		v.pose(2.9)
		var vb := root.find_child("VSBody", true, false) as Control
		if vb == null or absf(vb.position.y - roundf((vp.y - minf(vp.y, 720.0)) * 0.5)) > 0.5:
			bad.append("%s 版心没有竖向居中(%s)" % [str(vp), str(vb.position) if vb != null else "<无>"])
		await _frames(1)
		var rects: Array = []
		for nm in [VS.N_TITLE, VS.N_SUB, VS.N_CREST, VS.N_MINI, VS.N_NOTE, VS.N_BAR_DOCK]:
			var nd := root.find_child(nm, true, false) as Control
			if nd != null:
				rects.append([nm, _ink(nd)])
		for side in ["left", "right"]:
			for nm in [VS.N_NAME, VS.N_ORIGIN, VS.N_RECORD]:
				var nd := root.find_child(nm + side, true, false) as Control
				if nd != null:
					rects.append([nm + side, _ink(nd)])
		for ch in root.find_children(VS.N_CHIP + "*", "", true, false):
			rects.append([(ch as Node).name, (ch as Control).get_global_rect()])
		for i in range(rects.size()):
			nr += 1
			var ri: Rect2 = rects[i][1]
			if not Rect2(Vector2.ZERO, vp).encloses(ri.grow(-1.0)):
				bad.append("%s %s 出屏 %s" % [str(vp), rects[i][0], str(ri)])
			for j in range(i + 1, rects.size()):
				if ri.grow(-1.0).intersects((rects[j][1] as Rect2).grow(-1.0)):
					bad.append("%s %s × %s" % [str(vp), rects[i][0], rects[j][0]])
		v.finish()
		host.queue_free()
		await _frames(1)
	_ok("B ③ ★两种比例(1560×720 / iPad 逻辑 1280×960): 轮次名 / 名牌 / 徽章 / 阵容 / 迷你对阵 / 那一行两两不重叠、不出屏(量了 %d 块)" % nr,
		bad.is_empty() and nr >= 40, str(bad))


func _ink(nd: Control) -> Rect2:
	var r := nd.get_global_rect()
	if nd is Label and str((nd as Label).text) != "":
		var l := nd as Label
		var w: float = l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		var x0: float = r.position.x
		if l.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
			x0 += (r.size.x - w) * 0.5
		elif l.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
			x0 += r.size.x - w
		return Rect2(x0, r.position.y, w, r.size.y)
	return r


# C ─────────────────────────────────────────────────────────────
func _make(pn: Dictionary, late_sec: int, controls: bool = false) -> Array:
	ReplayRecorder.play_names = pn.duplicate(true)
	ReplayRecorder.viewer_name = "看客"
	ReplayRecorder.return_scene = "res://scenes/BracketMap.tscn"
	var now := 100000
	SW.current = {"kind": "premiere", "id": "x", "premiere": {"kind": "premiere", "flip_ts": now - late_sec, "srv_now": now,
		"t_ms": Time.get_ticks_msec(), "key": "k"}}
	var fb := FakeBattle.new()
	fb._replay = FakeReplay.new()
	fb._replay.player = FakePlayer.new()
	fb._replay.player.controls = controls
	fb._hud = FakeHud.new()
	fb._ui_layer = CanvasLayer.new()
	fb._ui_layer.layer = 10
	fb.add_child(fb._ui_layer)
	add_child(fb)
	var ui = RC.new(fb)
	ui.build()
	return [fb, ui]


func _t_wiring() -> void:
	var pn := PN.duplicate(true)
	var made: Array = _make(pn, 2)
	var fb: Node = made[0]
	var ui = made[1]
	_ok("C ★按时进来(开播 2 秒): 建了观战页, 先放开场 VS(播放器此刻还在开场幕布那一段)", ui.hud != null and ui.vs != null
		and fb.find_child(VS.N_ROOT, true, false) != null and not bool(ui.hud.late))
	var vsr: Node = fb.find_child(VS.N_ROOT, true, false)
	var crest_names: Array = []
	if vsr != null:
		for l in vsr.find_children("*", "Label", true, false):
			crest_names.append((l as Label).text)
	_ok("C 开场 VS 的内容取自这一局: 名牌名字 = 录像两边(吃货一枚 / 小辉同学), 来历取入口, 阵容取开局状态(2 + 3 / 3 + 3)",
		crest_names.has("吃货一枚") and crest_names.has("小辉同学") and crest_names.has("B 组冠军")
		and vsr.find_children(VS.N_CHIP + "*", "", true, false).size() == 11, str(crest_names))
	_ok("C 按时进来没有「从头看」(本来就从头)", fb.find_child(HUD.N_FROM_START, true, false) == null)

	fb.queue_free()
	await _frames(2)
	## 迟到 60 秒
	made = _make(pn, 60)
	fb = made[0]
	ui = made[1]
	var fs := fb.find_child(HUD.N_FROM_START, true, false) as Button
	_ok("C ★迟到 60 秒(G17): 不放开场 VS, 默认实时, 左上有「从头看」", ui.hud != null and bool(ui.hud.late) and ui.vs == null
		and fs != null and fs.text == "从头看")
	## 观战页已经在场时再放开场 VS(先建观战页、后放 VS 的那一条路): 观战页那一块停靠位当场收起, 全局小条认 VS 那一块
	var hdk := fb.find_child(HUD.N_BAR_DOCK, true, false) as Control
	var hdk_was: bool = hdk != null and hdk.visible
	ui.start_vs()
	var vdk := fb.find_child(VS.N_BAR_DOCK, true, false) as Control
	var fdw = get_node_or_null("/root/FinalsDay")
	var pk := Rect2()
	if fdw != null:
		fdw.test_host = fb
		pk = fdw.dock_rect()
		fdw.test_host = null
	_ok("C ★开场 VS 一出来(同一帧), 观战页那一块停靠位收起、全局小条认 VS 那一块(不在两块之间跳)", hdk_was and vdk != null
		and not hdk.visible and pk.is_equal_approx(vdk.get_global_rect()), str(pk))
	ui.vs.finish()
	if fs != null:
		fs.pressed.emit()
		var pl = fb._replay.player
		_ok("C ★按「从头看」⇒ 播放器跳到开头(seek 0), 键变「回到直播」", pl.seeks.size() == 1 and int(pl.seeks[0]) == 0 and fs.text == "回到直播",
			str(pl.seeks))
		fs.pressed.emit()
		_ok("C ★再按 ⇒ 跳回此刻该到的那一步(≈ 60 秒 × 60 = 3600)", pl.seeks.size() == 2 and int(pl.seeks[1]) >= 3590 and int(pl.seeks[1]) <= 3700
			and fs.text == "从头看", str(pl.seeks))
	fb.queue_free()
	await _frames(2)
	## 不是决赛日(周六 / 战绩页)/ 是回放 ⇒ 不建
	made = _make({"l": "甲", "r": "乙"}, 2)
	_ok("C 不是决赛日(入口没给轮次)⇒ 不建观战页 / 不放 VS", made[1].hud == null and made[1].vs == null)
	made[0].queue_free()
	made = _make(pn, 2, true)
	_ok("C 回放(有操作条)⇒ 不建观战页 / 不放 VS", made[1].hud == null and made[1].vs == null)
	made[0].queue_free()
	await _frames(2)


# D ─────────────────────────────────────────────────────────────
func _t_hud() -> void:
	var gs = get_node("/root/GameState")
	var pn := PN.duplicate(true)
	var made: Array = _make(pn, 60)
	var fb: Node = made[0]
	var ui = made[1]
	var h = ui.hud
	if h == null:
		_ok("D 分母: 建了观战页", false)
		return
	var tag := fb.find_child(HUD.N_TAG, true, false) as Control
	var labels: Array = []
	for l in tag.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	_ok("D ① ★左上阶段标签「开播中」(带一明一暗的点)+「冠军杯赛半决赛第 1 场」", labels.has("开播中")
		and labels.has("冠军杯赛半决赛第 1 场") and tag.find_child("LiveDot", true, false) != null, str(labels))
	var fs_bad: Array = []
	for l in tag.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("冠军杯赛") and (l as Label).get_theme_font_size("font_size") < 26:
			fs_bad.append("阶段标签")
	for side in ["left", "right"]:
		var ol := fb.find_child(HUD.N_ORIGIN + side, true, false) as Label
		if ol == null or ol.get_theme_font_size("font_size") < 22:
			fs_bad.append("来历 " + side)
	var nxl := (fb.find_child(HUD.N_NEXT, true, false) as Node).find_children("*", "Label", true, false)
	if nxl.is_empty() or (nxl[0] as Label).get_theme_font_size("font_size") < 24:
		fs_bad.append("下一场条")
	_ok("D ① 小字手机一眼可读: 阶段标签 ≥ 26 / 来历 ≥ 22 / 下一场条 ≥ 24", fs_bad.is_empty(), str(fs_bad))
	gs.lane_results = {"top": "left"}
	gs.current_lane = "bottom"
	ui.refresh()
	_ok("D ② ★比分条: 上路左边赢 ⇒ 1 : 0(三路灯就是对局顶栏那一排三路点, 按路赢家着色; 比分贴在它两侧)",
		(fb.find_child(HUD.N_SCORE + "left", true, false) as Label).text == "1" and (fb.find_child(HUD.N_SCORE + "right", true, false) as Label).text == "0")
	## 顶栏在场时比分贴着三路点两侧(造一个假的三路点: 比分该跟着它走)
	var dots := Control.new()
	dots.name = "LaneDots"
	dots.position = Vector2(700, 70)
	dots.size = Vector2(60, 16)
	fb._ui_layer.add_child(dots)
	h._anchors.clear()
	ui.refresh()
	var sl := fb.find_child(HUD.N_SCORE + "left", true, false) as Control
	var sr := fb.find_child(HUD.N_SCORE + "right", true, false) as Control
	_ok("D ② ★比分贴在三路点两侧(左分右沿 %.0f ≤ 700, 右分左沿 %.0f ≥ 760, 竖向对齐)" % [sl.get_global_rect().end.x, sr.get_global_rect().position.x],
		sl.get_global_rect().end.x <= 700.0 and sl.get_global_rect().end.x >= 680.0 and sr.get_global_rect().position.x >= 760.0
		and sr.get_global_rect().position.x <= 780.0 and absf(sl.get_global_rect().get_center().y - 78.0) <= 2.0)
	dots.queue_free()
	h._anchors.clear()
	_ok("D ② 两侧来历「B 组冠军」/「E 组冠军」(组号 → 字母, ChampionData.group_name)", (fb.find_child(HUD.N_ORIGIN + "left", true, false) as Label).text == "B 组冠军"
		and (fb.find_child(HUD.N_ORIGIN + "right", true, false) as Label).text == "E 组冠军")
	## 拔河条跟着单位表
	## 按墙钟等(CLAUDE.md §3.5: 无头帧率极高, 按帧数等平滑追不上)
	fb._units = [{"side": "left", "hp": 300.0, "alive": true}, {"side": "right", "hp": 100.0, "alive": true}]
	var tug := fb.find_child(HUD.N_TUG, true, false)
	var tw := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 2000 and float(tug.get_meta("frac", 0.5)) < 0.72:
		await get_tree().process_frame
	var f1 := float(tug.get_meta("frac", 0.5))
	fb._units = [{"side": "left", "hp": 100.0, "alive": true}, {"side": "right", "hp": 300.0, "alive": true}]
	tw = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 2000 and float(tug.get_meta("frac", 0.5)) > 0.28:
		await get_tree().process_frame
	var f2 := float(tug.get_meta("frac", 0.5))
	_ok("D ③ ★拔河条跟着此刻的剩余血量推(300:100 ⇒ %.2f, 换成 100:300 ⇒ %.2f)" % [f1, f2], f1 > 0.65 and f2 < 0.35)
	var nx := fb.find_child(HUD.N_NEXT, true, false)
	var ntxt := ""
	if nx != null:
		for l in (nx as Node).find_children("*", "Label", true, false):
			ntxt = (l as Label).text
	_ok("D ④ 下一场条「下一场：甲乙丙 对 丁戊己」", ntxt == "下一场：甲乙丙 对 丁戊己", ntxt)
	## 助威
	var key := fb.find_child(HUD.N_CHEER_KEY, true, false) as Button
	var row := fb.find_child(HUD.N_CHEERS, true, false) as Control
	_ok("D ⑤ 分母: 右下一颗助威键, 四个固定表情平时收着", key != null and row != null and not row.visible
		and fb.find_children(HUD.N_CHEER + "*", "Button", true, false).size() == 4)
	key.pressed.emit()
	_ok("D ⑤ 按助威键 ⇒ 展开四个表情; 下一场条让位", row.visible and not (fb.find_child(HUD.N_NEXT, true, false) as Control).visible)
	var ck := fb.find_child(HUD.N_CHEER + "fire", true, false) as Button
	ck.pressed.emit()
	var fx := fb.find_children(HUD.N_CHEER_FX + "*", "", true, false)
	_ok("D ⑤ ★点一个表情 ⇒ 飘出一个同款、表情排收起、下一场条回来", h.cheers_sent == 1 and fx.size() == 1 and not row.visible
		and (fb.find_child(HUD.N_NEXT, true, false) as Control).visible)
	key.pressed.emit()
	ck.pressed.emit()
	_ok("D ⑤ 连点有间隔(紧接着第二下不飘)", h.cheers_sent == 1)
	if row.visible:
		key.pressed.emit()
	var y0: float = (fx[0] as Control).position.y if not fx.is_empty() else 0.0
	var tw2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw2 < 400:
		await get_tree().process_frame
	var y1: float = (fx[0] as Control).position.y if not fx.is_empty() and is_instance_valid(fx[0]) else y0
	_ok("D ⑤ ★表情真的往上飘(y %.0f → %.0f)" % [y0, y1], y1 < y0 - 5.0)
	## 路间幕布
	fb._dl_state = "lane_settle"
	fb._dl_pending_loser = "right"
	gs.lane_results = {}
	gs.current_lane = "top"
	ui._names = {"l": "吃货一枚", "r": "小辉同学"}
	ui.refresh()
	var bk := fb.find_child(HUD.N_BREAK, true, false) as Control
	var btxt: Array = []
	for l in bk.find_children("*", "Label", true, false):
		btxt.append((l as Label).text)
	var bdl := bk.find_child("BreakDigit_left", true, false) as Label
	var bdr := bk.find_child("BreakDigit_right", true, false) as Label
	_ok("D ⑥ ★路间幕布压一块「上路战场战果 / 吃货一枚 赢得上路 / 1 : 0」, 顶上比分条收起", bk.visible and btxt.has("上路战场战果")
		and btxt.has("吃货一枚 赢得上路") and bdl != null and bdl.text == "1" and bdr != null and bdr.text == "0"
		and not (fb.find_child(HUD.N_TUG, true, false) as Control).visible, str(btxt))
	var trow := bk.find_child("BreakTitleArt", true, false)
	var ttex := ""
	if trow != null and trow.find_child(Ctx.ART_NODE, true, false) != null:
		ttex = ((trow.find_child(Ctx.ART_NODE, true, false) as TextureRect).texture.resource_path.get_file())
	_ok("D ⑥ ★路间那一块是转播插卡不是对话框: 整屏深底(盖住幕布面板)+ 缎带上路名美术字(%s)+ 比分美术字(领先金 / 落后灰)" % ttex,
		bk.size.x >= bk.get_viewport_rect().size.x - 1.0 and bk.find_child("BreakRibbon", true, false) != null and ttex == "bt-lane-top.png"
		and (bdl.get_node(Ctx.ART_NODE) as TextureRect).texture.resource_path.get_file() == "bt-n1.png"
		and (bdr.get_node(Ctx.ART_NODE) as TextureRect).texture.resource_path.get_file() == "bt-g0.png")
	_ok("D ⑥ 路间那一块写下一路「接下来：下路战场」; 左上标签 / 来历跟着顶栏一起让开(不孤零零飘在幕布上)", btxt.has("接下来：下路战场")
		and not (fb.find_child(HUD.N_TAG, true, false) as Control).visible and not (fb.find_child(HUD.N_ORIGIN + "left", true, false) as Control).visible)
	## 插卡期间全局小条停在缎带上方正中(不落到左下角压住退出键); 观战页那一块停靠位让出来
	var bdk := bk.find_child(HUD.N_BREAK_DOCK, true, false) as Control
	var rib := bk.find_child("BreakRibbon", true, false) as Control
	var fd0 = get_node_or_null("/root/FinalsDay")
	var picked := Rect2()
	if fd0 != null:
		fd0.test_host = fb
		picked = fd0.dock_rect()
		fd0.test_host = null
	_ok("D ⑥ ★插卡期间小条停在缎带上方正中(%s), 不压缎带 / 退出键; 观战页那一块收起" % str(picked), bdk != null and rib != null
		and bdk.is_visible_in_tree() and not (fb.find_child(HUD.N_BAR_DOCK, true, false) as Control).visible
		and picked.is_equal_approx(bdk.get_global_rect()) and not bdk.get_global_rect().intersects(rib.get_global_rect())
		and bdk.get_global_rect().end.y < rib.get_global_rect().position.y + 1.0)
	fb._dl_state = "fight"
	ui.refresh()
	_ok("D ⑥ 开打后那一块收起、比分条回来", not bk.visible and (fb.find_child(HUD.N_TUG, true, false) as Control).visible)
	## ★全局决赛日小条(autoload FinalsDay): 观战页给它一块停靠位(拔河条下面正中), 自己那几样登记让路; 它真的认这一块
	var fd = get_node_or_null("/root/FinalsDay")
	var dk := fb.find_child(HUD.N_BAR_DOCK, true, false) as Control
	if fd != null and dk != null:
		fd.test_host = fb
		var drr: Rect2 = fd.dock_rect()
		var av := 0
		for nm in [HUD.N_TAG, HUD.N_TUG, HUD.N_SCORE + "left", HUD.N_NEXT, HUD.N_CHEER_KEY]:
			var nd := fb.find_child(nm, true, false)
			if nd != null and nd.is_in_group(Ctx.BAR_AVOID):
				av += 1
		_ok("D ⑩ ★全局决赛日小条停在观战页给的那一块(拔河条下面正中 %s), 比分条 / 阶段标签 / 下一场条 / 助威键都登记了让路(%d / 5)" % [str(drr), av],
			drr.size.x > 0.0 and drr.is_equal_approx(dk.get_global_rect()) and dk.position.y > (fb.find_child(HUD.N_TUG, true, false) as Control).position.y
			and av == 5, str(drr))
		fd.test_host = null
	else:
		_ok("D ⑩ 分母: 全局决赛日小条在场(autoload FinalsDay)", false, "fd=%s dock=%s" % [str(fd), str(dk)])
	## 两种比例版式(这一份是 1560×720 的视口; iPad 另建一份在 iPad 逻辑 1280×960 的宿主上)
	await _hud_layout(fb, ui)
	## 收尾出来后收起
	ui._end_card(true, false)
	ui.refresh()
	_ok("D ⑦ 收尾出来后观战页那几样收起(比分条 / 助威 / 下一场条)", not (fb.find_child(HUD.N_TUG, true, false) as Control).visible
		and not (fb.find_child(HUD.N_CHEER_KEY, true, false) as Control).visible and not (nx as Control).visible)
	var banned := ["胜率", "本场还剩", "观看人数", "人在看"]
	var hit: Array = []
	for l in fb.find_children("*", "Label", true, false):
		for w in banned:
			if (l as Label).text.find(w) >= 0:
				hit.append((l as Label).text)
	_ok("D ⑧ 不出现胜率 / 本场还剩 / 观看人数", hit.is_empty(), str(hit))
	fb.queue_free()
	await _frames(2)


func _hud_layout(fb0: Node, ui0) -> void:
	var bad: Array = []
	var nr := 0
	for vp in [Vector2(1560, 720), Vector2(1280, 960)]:
		var host := Control.new()
		host.size = vp
		add_child(host)
		var h := HUD.new(fb0, ui0)
		var root: Control = h.build(host, vp, Vector4(18, 18, 18, 18), {"l": "吃货一枚", "r": "小辉同学"})
		await _frames(1)
		var rects: Array = []
		rects.append(["tag", (root.find_child(HUD.N_TAG, true, false) as Control).get_global_rect()])
		for nm in [HUD.N_SCORE + "left", HUD.N_SCORE + "right", HUD.N_ORIGIN + "left", HUD.N_ORIGIN + "right", HUD.N_TUG, HUD.N_NEXT,
				HUD.N_CHEER_KEY, HUD.N_FROM_START, HUD.N_BAR_DOCK]:
			var nd := root.find_child(nm, true, false) as Control
			if nd != null:
				rects.append([nm, _ink(nd)])
		## 退出键(左下角, 回放条那颗)与法术圆盘(右下角)的位置
		rects.append(["exit", Rect2(18, vp.y - 18 - 60, 60, 60)])
		rects.append(["disc", Rect2(vp.x - 18 - SpellDisc.R * 2.0, vp.y - 18 - SpellDisc.R * 2.0, SpellDisc.R * 2.0, SpellDisc.R * 2.0)])
		## 表情排展开时: 不压退出键 / 圆盘 / 助威键(下一场条那时让位, 不算)
		h.toggle_cheers()
		var row := root.find_child(HUD.N_CHEERS, true, false) as Control
		var rr: Rect2 = Rect2(row.position, row.size)
		for k in ["exit", "disc"]:
			for it in rects:
				if str(it[0]) == k and rr.intersects((it[1] as Rect2).grow(-1.0)):
					bad.append("%s 表情排 × %s" % [str(vp), k])
		if rr.intersects((root.find_child(HUD.N_CHEER_KEY, true, false) as Control).get_global_rect().grow(-1.0)) or rr.position.x < 0.0:
			bad.append("%s 表情排压助威键 / 出屏 %s" % [str(vp), str(rr)])
		h.toggle_cheers()
		for i in range(rects.size()):
			nr += 1
			var ri: Rect2 = rects[i][1]
			if not Rect2(Vector2.ZERO, vp).encloses(ri.grow(-1.0)):
				bad.append("%s %s 出屏 %s" % [str(vp), rects[i][0], str(ri)])
			for j in range(i + 1, rects.size()):
				if ri.grow(-1.0).intersects((rects[j][1] as Rect2).grow(-1.0)):
					bad.append("%s %s × %s" % [str(vp), rects[i][0], rects[j][0]])
		h._disconnect()
		host.queue_free()
		await _frames(1)
	_ok("D ⑨ ★两种比例: 阶段标签 / 比分 / 三路灯 / 来历 / 拔河条 / 下一场条 / 助威栏 / 从头看 / 退出键两两不重叠、不出屏(量了 %d 块)" % nr,
		bad.is_empty() and nr >= 20, str(bad))
