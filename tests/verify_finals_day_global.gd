extends Node
## verify_finals_day_global.gd — 周日决赛日全局层(方案书 docs/plans/20261031c-周日赛事界面重做.md 块 M ④⑤⑥⑨ · G16 / J-2 / J-3 / 8-1 / 9-1)
##
## 由来(2026-10-31 彩排 + 百款调研): 开赛提醒只在主菜单开着时跨 18:00 / 冠军杯赛开赛 飘一句, 人在对阵图 / 商店 / 观战页收不到, 没晋级的人直接 return;
##   商业游戏(LoL Clash 右上角赛程小卡 / MCC 每页顶栏倒计时 / HB2·8BP「轮到你」/ 梦幻西游全服广播)的共同做法:
##   倒计时每一页都看得到; 轮到我时不论在哪页都弹; 开播时刻 / 结果走全服跑马灯。改法: autoload `FinalsDay`(scripts/ui/finals_day_layer.gd)。
##
## A 什么时候在场: 只在周日 17:30 收盘后 + 玩家的屏; 门禁 / 子节点挂法 / 周六 / 周日 17:30 前 / 周一一律不出(不乱弹)。
## B 条上那一行(晋级者 / 观众 / 第 1 轮就输 × 一整晚逐时刻): 正文 / 倒计时 / 开播签 / 点了去哪; 备战时写「不调整就沿用当前阵容」(⑨)。
##   ★一整晚每 30 秒扫一遍, 条宽 ≤ BAR_MAX_W(主菜单顶上玩家卡与货币条之间的空)。
## C 摆在哪: 主菜单 / 商店 / 背包 / 设置 / 对阵图 × 两比例, 条的点击区(81 高)不压这一屏任何看得见的按钮; ★故意在条的位置放一颗按钮 ⇒ 条让开(尺子会动)。
##   观战页(战斗场)先试底下、点条不跳走。
## D 30 秒弹窗: 开播前 30 秒内弹(35 秒不弹)、一场只弹一次、在商店也弹、观众不弹; 没开播点「观看」⇒ 开播那一拍自动进; 刚开播进来弹「开播中」, 晚了不弹。
## E 跑马灯: 开屏那一拍只当底(已发生的不刷); 揭晓那一拍才播「X 晋级 C 组决赛」(开播中不播 = 不剧透); 别组只播组冠军; 冠军杯赛开播时刻 / 冠军杯赛冠军;
##   开赛前 10 分钟「小组赛 18:00 开赛」; 字真在走。
## F 在场守到冠军杯赛决出 ⇒ 记「看过了」(收盘补看不再弹)。
##
## 跑法: bash godot-quiet.sh res://tests/verify_finals_day_global.tscn --quit-after 500(入场滑入用 _settle 推到头, 不按帧等; 实测 ~210 帧)

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const M := preload("res://scripts/ui/finals_day_model.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const L := preload("res://scripts/ui/finals_day_layer.gd")
const RC := preload("res://scripts/ui/finals_day_recap.gd")
const W := preload("res://scripts/ui/finals_day_watch.gd")
const FX := preload("res://tests/_finals_day_fixture.gd")

const MON := 1789344000
const SUN := MON + 6 * 86400
const H := 3600
const MI := 60
const KEYS := ["promoted", "season_wins", "gauntlet_wins", "gauntlet_losses", "season_total_battles", "test_mode", "hearts"]

var _n := 0
var _fail := 0
var _bak := {}
var fx
var fd
var host: Control


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", nm, ("   " + detail) if detail != "" else ""])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 周日决赛日全局层: 小条 / 30 秒弹窗 / 跑马灯 ===")
	for k in KEYS:
		_bak[k] = GameState.get(k)
	GameState.test_mode = true
	fx = FX.new(MON)
	fd = get_node_or_null("/root/FinalsDay")
	_ok("★分母: autoload FinalsDay 在场(project.godot 注册)", fd != null and fd.get_script() == L)
	if fd == null:
		_done()
		return
	host = Control.new()
	host.name = "FakeScreen"
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	_t_active()
	_t_lines()
	await _t_width()
	await _t_place()
	await _t_popup()
	await _t_marquee()
	_t_recap_mark()
	_done()


func _done() -> void:
	if fd != null:
		fd.test_host = null
		fd.tick()
	F.override = {}
	P2.now_override_ts = 0
	for k in _bak.keys():
		GameState.set(k, _bak[k])
	print("  (用了 %d 帧; 默认预算 500)" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _who(kind: String) -> void:
	GameState.hearts = int(P2.HEARTS_MAX)
	GameState.season_total_battles = 3
	GameState.promoted = kind != "plain"
	GameState.season_wins = int(P2.PROMOTE_WINS) if kind != "plain" else 2
	GameState.gauntlet_wins = int(P2.GAUNTLET_WINS_IN) if kind != "plain" else 0
	GameState.gauntlet_losses = 0
	fx.me_in = kind != "plain"
	fx.group_wins[FX.MY_GROUP] = {"1-1": 0} if kind == "out" else {"1-1": 1, "2-0": 1}


## 钉钟 + 喂这一刻服务端会给的数据 + 拍一下。
func _at(ts: int, kind: String = "") -> void:
	if kind != "":
		_who(kind)
	P2.now_override_ts = ts
	F.override = fx.feeds(ts)
	fd.tick()


# ───────────────────────────── A 在不在场 ─────────────────────────────

func _t_active() -> void:
	print("--- A 什么时候在场 ---")
	fd.test_host = null
	_at(SUN + 18 * H + 10 * MI, "in")
	_ok("A ★门禁进程(没指定这一屏 · 无头 · 后端没配 · 当前场景是测试)⇒ 不出(不乱弹)", not fd.bar.visible and not fd.active_at(SUN + 18 * H + 10 * MI))
	_ok("A ★无头进程(陪练号 / 裁判机 / 门禁)不挂; 后端没配不挂; 有窗口 + 后端 ⇒ 挂", not L.gate_ok("headless", true)
		and not L.gate_ok("Windows", false) and L.gate_ok("Windows", true) and L.gate_ok("iOS", true))
	fd.test_host = host
	_at(SUN + 18 * H + 10 * MI)
	_ok("A ★分母: 指定了这一屏 ⇒ 周日 18:10 条在", fd.bar.visible and fd.active_at(SUN + 18 * H + 10 * MI))
	for c in [["周六 20:00", MON + 5 * 86400 + 20 * H, false], ["周日 17:29(闯关赛还没收盘)", SUN + 17 * H + 29 * MI, false],
			["周日 17:31", SUN + 17 * H + 31 * MI, true], ["周日 23:59", SUN + 24 * H - 60, true], ["周一 00:00:01", SUN + 24 * H + 1, false]]:
		_at(int(c[1]))
		_ok("A [%s] 条%s" % [c[0], "在" if bool(c[2]) else "不出"], fd.bar.visible == bool(c[2]))
	var bad := Control.new()
	bad.scene_file_path = "res://scenes/FirstLaunch.tscn"
	_ok("A 首启 / 匹配 / 裁判这类屏不在名单里(scene_key 不认)", not (L.scene_key(bad) in L.SCENES) and "BracketMap" in L.SCENES and "Shop" in L.SCENES
		and "RealtimeBattle3D" in L.SCENES and "MainMenu" in L.SCENES)
	bad.free()


# ───────────────────────────── B 条上那一行 ─────────────────────────────

func _line(ts: int, kind: String) -> Dictionary:
	_who(kind)
	var f: Dictionary = fx.feeds(ts)
	var mn: Dictionary = M.my_next(kind != "plain", f["group"], f["cup"], ts)
	return L.bar_line(ts, f["group"], f["cup"], f["groups"], mn)


func _t_lines() -> void:
	print("--- B 条上那一行(一整晚逐时刻) ---")
	var seat := SUN + 18 * H
	var cup := SUN + int(P2.FINALS_START_HOUR_UTC) * H
	var r1 := M.round_name(4, 1)
	var r2 := M.round_name(4, 2)
	var t_mine: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][0])
	var r2_at: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[1]["round_at"])
	var t_end1: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][1])
	var flip1: int = seat + 480
	var cup_live := M.stage_line(fx.cup(cup + 9 * MI), 1)
	## [标签, 时刻, 人, 正文, 倒计时(秒, -1 = 不显示), 开播签, 点了去看哪一场(组号, -1 = 对阵图)]
	## ★2026-11-01 文案改写(方案书 20261101e, 用户「一定要按照商业游戏的口吻」): 正文一件事(不再「· 观看」「备战中 · 未调整阵容…」); 能点的那一档右边单列「观看」(act);
	##   「开播中」红签只在**真有一场在播**时亮(原来整段小组赛都亮)。保持阵容那句规则挪到对阵图备战屏(⑨)。
	var rows: Array = [
		["17:40 晋级者", SUN + 17 * H + 40 * MI, "in", "%s %s 开赛" % [P2.STAGE_GROUP, P2.local_hhmm(seat)], 20 * MI, false, -1],
		["17:40 观众", SUN + 17 * H + 40 * MI, "plain", "%s %s 开赛" % [P2.STAGE_GROUP, P2.local_hhmm(seat)], 20 * MI, false, -1],
		["★18:01 备战中(⑨)", seat + 60, "in", "%s备战剩余" % r1, 120, false, -1],
		["18:05 备战结束等翻面", seat + 5 * MI, "in", "你的%s %s 开播" % [r1, P2.local_hhmm(flip1)], flip1 - seat - 5 * MI, false, -1],
		## ★小组赛同一轮所有场同时开播(用户 10-31 纠正): 18:08 翻面即开播, 我那场没有「几点开播」那一态
		## 开播中: 左边红签「开播中」, 正文只说是哪一场(不重复「开播中」), 右边「观看」
		["18:10 我的比赛开播中(本轮同时开播)", seat + 10 * MI, "in", "你的%s" % r1, -1, true, FX.MY_GROUP],
		["我那场揭晓后 · 等决赛备战", t_end1 + 10, "in", "%s备战 %s 开始" % [r2, P2.local_hhmm(r2_at)], r2_at - t_end1 - 10, false, -1],
		["18:13 决赛备战中(⑨)", seat + 13 * MI, "in", "%s备战剩余" % r2, r2_at + 180 - seat - 13 * MI, false, -1],
		["18:10 观众(6 组 × 2 场同时开播)", seat + 10 * MI, "plain", "%s 12 场" % P2.STAGE_GROUP, -1, true, 0],
		["18:10 第 1 轮就输的人(结果还没揭晓)", seat + 10 * MI, "out", "你的%s" % r1, -1, true, FX.MY_GROUP],
		["18:40 第 1 轮就输了(等冠军杯赛)", SUN + 18 * H + 40 * MI, "out", "%s %s 开赛" % [P2.STAGE_CUP, P2.local_hhmm(cup)], cup - SUN - 18 * H - 40 * MI, false, -1],
		["18:40 观众(等冠军杯赛)", SUN + 18 * H + 40 * MI, "plain", "%s %s 开赛" % [P2.STAGE_CUP, P2.local_hhmm(cup)], cup - SUN - 18 * H - 40 * MI, false, -1],
		["冠军杯赛 +9 分 观众", cup + 9 * MI, "plain", cup_live, -1, true, int(P2.FINALS_CUP_BUCKET)],
		["22:00 观众", SUN + 22 * H, "plain", "冠军杯赛冠军：小辉同学", -1, false, -1],
	]
	for r in rows:
		var ln := _line(int(r[1]), str(r[2]))
		var tag := "B [%s]" % str(r[0])
		var tgt: Dictionary = ln.get("target", {})
		var tb := int((tgt.get("b", {}) as Dictionary).get("bucket", -1)) if not tgt.is_empty() else -1
		_ok("%s 「%s」" % [tag, r[3]], str(ln["body"]) == str(r[3]) and str(ln["head"]) == "决赛日", "%s | %s" % [ln["head"], ln["body"]])
		_ok("%s 倒计时 %d 秒 · 开播签 %s · 点了%s" % [tag, int(r[4]), str(r[5]), ("去看 %d 组那一场" % int(r[6])) if int(r[6]) >= 0 else "去对阵图"],
			int(ln["cd"]) == int(r[4]) and bool(ln["live"]) == bool(r[5]) and tb == int(r[6]) and bool(ln["tap"]),
			"cd=%d live=%s 去=%d" % [int(ln["cd"]), str(ln["live"]), tb])
		_ok("%s 右边「观看」只在能直达那一场时出现" % tag, (str(ln.get("act", "")) == "观看") == (int(r[6]) >= 0), str(ln.get("act", "")))
	_who("in")
	var f: Dictionary = fx.feeds(seat + 10 * MI)
	var lb := L.bar_line(seat + 10 * MI, f["group"], f["cup"], f["groups"], M.my_next(true, f["group"], f["cup"], seat + 10 * MI), true)
	_ok("B 观战页上点条不跳走(会把正在看的那一场关掉), 也就不写「· 观看」", not bool(lb["tap"]) and str(lb["body"]) == "你的%s" % r1 and str(lb["act"]) == "", str(lb["body"]))


# ───────────────────────────── 条宽 ─────────────────────────────

func _t_width() -> void:
	print("--- B ★一整晚每 30 秒: 条宽 ≤ %.0f ---" % L.BAR_MAX_W)
	fd.test_host = host
	var worst := 0.0
	var wtxt := ""
	var k := 0
	var zb: Array = []
	for kind in ["in", "plain", "out"]:
		var t := SUN + 17 * H + 31 * MI
		while t < SUN + 21 * H:
			_at(t, kind)
			var w: float = fd.bar.get_combined_minimum_size().x
			k += 1
			for l in fd.bar.find_children("*", "Label", true, false):
				if (l as Label).is_visible_in_tree() and str((l as Label).text).find("直播") >= 0 and zb.size() < 3:
					zb.append(str((l as Label).text))
			if w > worst:
				worst = w
				wtxt = str(fd.line.get("body", ""))
			t += 30
	_ok("B ★分母: 扫了 %d 个时刻(三种人 × 17:31~21:00)" % k, k > 1200)
	_ok("B ★一整晚条上一个「直播」都没有(周日是服务器算好再播, 叫「开播中」)", zb.is_empty() and str((fd.bar.live_chip.find_child("FdBarLiveText", true, false) as Label).text) == "开播中", str(zb))
	_ok("B ★最宽的一行也 ≤ %.0f(主菜单顶上放得下)" % L.BAR_MAX_W, worst <= L.BAR_MAX_W and worst > 200.0, "%.0f「%s」" % [worst, wtxt])


# ───────────────────────────── C 摆在哪 ─────────────────────────────

func _seed() -> void:
	GameState.season_total_battles = 3
	GameState.onboarded = true


func _scene(nm: String) -> Node:
	_seed()
	var ps = load("res://scenes/%s.tscn" % nm)
	if ps == null:
		return null
	var inst = ps.instantiate()
	if nm == "MainMenu":
		inst.clock_override_ts = SUN + 18 * H + 13 * MI
	add_child(inst)
	return inst


func _t_place() -> void:
	print("--- C 摆在哪(两比例 × 五屏) ---")
	_who("in")
	for vp in [Vector2i(1560, 720), Vector2i(1280, 960)]:
		get_tree().root.size = vp
		await get_tree().process_frame
		for nm in ["MainMenu", "Shop", "Inventory", "Settings", "BracketMap"]:
			var inst = _scene(nm)
			if inst == null:
				_ok("C [%s] 载入" % nm, false)
				continue
			for _i in range(10):
				await get_tree().process_frame
			_settle()                                   # 入场滑入一律推到落定(量落点, 不量半路)
			fd.test_host = inst
			_at(SUN + 18 * H + 13 * MI)
			var blk: Array = fd.blockers()
			var sz: Vector2 = fd.bar.size
			var hr: Rect2 = fd.hit_rect(_bar_pos(), sz)
			var vr := Rect2(Vector2.ZERO, Vector2(vp))
			var hit_any := []
			for b in blk:
				if hr.intersects(b as Rect2):
					hit_any.append(str(b))
			var tag := "C [%s %dx%d]" % [nm, vp.x, vp.y]
			_ok("%s ★分母: 这一屏量到 %d 个可点的东西" % [tag, blk.size()], blk.size() >= 3)
			_ok("%s ★条的点击区(81 高)不压任何一个、条整条在屏内(候选位 %d)" % [tag, int(fd.slot)], hit_any.is_empty()
				and vr.encloses(Rect2(_bar_pos(), sz)) and fd.bar.visible, str(hit_any))
			_ok("%s 点击区就在条上(宽同条、竖向罩住条)" % tag, (fd._hit as Control).visible and absf((fd._hit as Control).size.y - 81.0) < 0.5
				and Rect2((fd._hit as Control).position, (fd._hit as Control).size).encloses(Rect2(_bar_pos(), sz)))
			if nm == "MainMenu" and vp.x == 1560:
				_ok("%s 主菜单: 条在顶上正中(玩家卡与货币条之间)" % tag, int(fd.slot) == L.SLOT_TOP)
				## ★尺子会动: 在条那个位置放一颗按钮 ⇒ 条必须让开
				var blocker := Button.new()
				blocker.position = _bar_pos()
				blocker.size = Vector2(fd.bar.size.x, 60)
				inst.add_child(blocker)
				var was := int(fd.slot)
				_at(SUN + 18 * H + 13 * MI)
				hr = fd.hit_rect(_bar_pos(), fd.bar.size)
				_ok("%s ★故意在条的位置放一颗按钮 ⇒ 条换到别的候选位、不压它" % tag, int(fd.slot) != was
					and not hr.intersects(Rect2(blocker.global_position, blocker.size)), "候选位 %d → %d" % [was, int(fd.slot)])
				blocker.queue_free()
			fd.test_host = host
			inst.queue_free()
			await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	## 观战页: 先试底下
	var bt := Control.new()
	bt.scene_file_path = "res://scenes/RealtimeBattle3D.tscn"
	bt.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bt)
	fd.test_host = bt
	_at(SUN + 18 * H + 13 * MI)
	_ok("C 观战页: 顶上是双方血量 / VS(不是按钮量不出来)⇒ 条先放底下正中、点条不跳走", int(fd.slot) == L.SLOT_BOTTOM and not bool(fd.line["tap"])
		and not (fd._hit as Control).visible)
	## 别的屏登记「别压我」(AVOID_GROUP)⇒ 条让开
	var bar_c := Label.new()
	bar_c.text = "下一场条"
	bar_c.position = _bar_pos()
	bar_c.size = Vector2(fd.bar.size.x, 40)
	bt.add_child(bar_c)
	bar_c.add_to_group(L.AVOID_GROUP)
	_at(SUN + 18 * H + 13 * MI)
	_ok("C ★不是按钮但登记了「%s」的东西 ⇒ 条也让开" % L.AVOID_GROUP, int(fd.slot) != L.SLOT_BOTTOM
		and not fd.hit_rect(_bar_pos(), fd.bar.size).intersects(Rect2(bar_c.global_position, bar_c.size)), "候选位 %d" % int(fd.slot))
	## 别的屏登记停靠位(DOCK_GROUP)⇒ 条居中贴在那块地上, 不再自己找
	var dock := Control.new()
	dock.position = Vector2(300, 400)
	dock.size = Vector2(600, 60)
	bt.add_child(dock)
	dock.add_to_group(L.DOCK_GROUP)
	_at(SUN + 18 * H + 13 * MI)
	var c_dock := Rect2(_bar_pos(), fd.bar.size).get_center()
	_ok("C ★别的屏登记了停靠位「%s」⇒ 条居中贴在那块地上" % L.DOCK_GROUP, int(fd.slot) == L.SLOT_DOCK
		and c_dock.distance_to(Rect2(dock.global_position, dock.size).get_center()) < 1.5, "候选位 %d · 中心 %s" % [int(fd.slot), str(c_dock)])
	dock.queue_free()
	bt.queue_free()
	fd.test_host = host
	await get_tree().process_frame


# ───────────────────────────── D 30 秒弹窗 ─────────────────────────────

## 把树上所有在跑的补间一口气推到头(入场滑入 / 淡入落定)。按帧等会量到半路(无头一帧极短)。
func _settle() -> void:
	for tw in get_tree().get_processed_tweens():
		if tw.is_valid() and tw.is_running():
			tw.custom_step(30.0)


## 条此刻该在的位置(换位时条有 0.25 秒滑过去的动画, 量落点不量半路)。
func _bar_pos() -> Vector2:
	return fd.slot_pos_any(int(fd.slot), fd.bar.size)


func _popup() -> Node:
	return fd.popup if fd.popup != null and is_instance_valid(fd.popup) else null


func _t_popup() -> void:
	print("--- D 「你的半决赛 30 秒后开播」顶部横幅 ---")
	fd.test_host = host
	fd.popped = {}
	fd._close_popup()
	var seat := SUN + 18 * H
	var t_mine: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][0])
	_at(t_mine - 35, "in")
	_ok("D 开播前 35 秒 ⇒ 还不弹", _popup() == null)
	F.avatars[MON] = {"#T201": "bamboo"}
	_at(t_mine - 25)
	var p = _popup()
	var r1 := M.round_name(4, 1)
	var want_sub := "吃货一枚 对 Kiki"      # 哪一场写在标题「你的半决赛…」里, 第二行只写对阵(不用「·」拼)
	_ok("D ★开播前 25 秒 ⇒ 弹「你的%s 25 秒后开播」+「%s」" % [r1, want_sub],
		p != null and str(p.title.text) == "你的%s 25 秒后开播" % r1 and str(p.sub.text) == want_sub,
		"%s / %s" % [str(p.title.text) if p else "-", str(p.sub.text) if p else "-"])
	_ok("D ★横幅左边双方头像 + VS 盾徽(对手 Kiki 是他真头像)", p != null and p.find_child("FdPopMe", true, false) != null
		and p.find_child("FdPopVs", true, false) != null
		and str(((p.find_child("FdPopOpp", true, false) as Control).get_node("Face") as TextureRect).texture.resource_path).ends_with("bamboo.png"))
	var ring_f0: float = float(p.ring.frac)
	_at(t_mine - 24)
	_ok("D 下一秒倒数跟着走(24 秒)、圆环少一格", p != null and str(p.title.text) == "你的%s 24 秒后开播" % r1
		and int(p.ring.secs) == 24 and float(p.ring.frac) < ring_f0 and absf(float(p.ring.frac) - 24.0 / 30.0) < 0.01, "%.3f → %.3f" % [ring_f0, float(p.ring.frac)])
	var w0: float = p.watch.modulate.r
	var wmax := 0.0
	for _i in range(30):
		p._process(0.05)
		wmax = maxf(wmax, absf(p.watch.modulate.r - w0))
	_ok("D ★「观看」亮色呼吸(推 1.5 秒亮度变过)", wmax > 0.15, "%.2f" % wmax)
	_ok("D 按钮是卡片动作钮(UISkin.card_button 那一种, 不是木牌)、触摸线 81", p != null and p.watch.custom_minimum_size.y >= 81.0
		and p.watch.get_theme_stylebox("normal") is StyleBoxFlat and (p.watch.get_theme_stylebox("normal") as StyleBoxFlat).bg_color == Color("#6a3f1c"))
	_ok("D ★从顶上滑下来(刚弹出时在屏外, 落点是顶上正中)", fd.popup_home().y <= 12.0 and absf(fd.popup_home().x + p.size.x * 0.5
		- get_viewport().get_visible_rect().size.x * 0.5) < 1.0)
	## 没开播就点「观看」⇒ 不硬开, 开播那一拍自动进
	fd.last_watch = {}
	p.watch.pressed.emit()
	_ok("D ★没开播就点「观看」⇒ 不硬开(还在弹窗里), 键变「开播后自动进入」", _popup() != null and fd.last_watch.is_empty()
		and str(p.watch.text) == "开播后自动进入" and p.watch.disabled)
	_at(t_mine + 1)
	_ok("D ★开播那一拍 ⇒ 自动进我那一场(C 组 · 1-1)、弹窗收起", _popup() == null or _popup().is_queued_for_deletion() or float(_popup().modulate.a) < 1.0
		and true, str(fd.last_watch))
	_ok("D ★…去看的就是我那一场", int(fd.last_watch.get("bucket", -1)) == FX.MY_GROUP and int(fd.last_watch.get("r", 0)) == 1
		and int(fd.last_watch.get("m", -1)) == 1, str(fd.last_watch))
	_at(t_mine + 5)
	_ok("D 一场只弹一次(同一场不再弹)", _popup() == null or (_popup() as Node).is_queued_for_deletion())
	## 刚开播才进来 ⇒ 弹「开播中」; 晚了(超过 60 秒)不弹
	fd.popped = {}
	fd._close_popup()
	_at(t_mine + 35, "in")
	p = _popup()
	_ok("D 开播 35 秒后才进来 ⇒ 弹「你的%s开播中」(圆环换成红圈)" % M.round_name(4, 1), p != null and str(p.title.text) == "你的%s开播中" % M.round_name(4, 1)
		and int(p.ring.secs) < 0)
	p.later_pressed.emit()
	_at(t_mine + 36)
	_ok("D 点「稍后」⇒ 收起、这一场不再弹", _popup() == null)
	fd.popped = {}
	_at(t_mine + 95)
	_ok("D 开播 95 秒后才进来 ⇒ 不弹(条上挂着「开播中」红签 + 「观看」)", _popup() == null and bool(fd.line["live"]) and str(fd.line["act"]) == "观看")
	## 观众不弹 / 在商店也弹
	fd.popped = {}
	_at(t_mine - 20, "plain")
	_ok("D 观众(没有自己的比赛)⇒ 不弹", _popup() == null)
	var shop = _scene("Shop")
	for _i in range(30):
		await get_tree().process_frame
	fd.test_host = shop
	fd.popped = {}
	_at(t_mine - 20, "in")
	_ok("D ★人在商店 ⇒ 也弹(不论在哪一屏)", _popup() != null and str(_popup().title.text) == "你的%s 20 秒后开播" % M.round_name(4, 1))
	fd._close_popup()
	fd.test_host = host
	shop.queue_free()
	await get_tree().process_frame
	## ★横幅在主菜单两比例都不挡任何按钮(玩家卡 / 货币条 / ? / ⚙ / 左列 / 决赛日卡 / 主按钮)
	for vp in [Vector2i(1560, 720), Vector2i(1280, 960)]:
		get_tree().root.size = vp
		await get_tree().process_frame
		var mm = _scene("MainMenu")
		for _i in range(10):
			await get_tree().process_frame
		_settle()                                   # 入场滑入一律推到落定(量落点, 不量半路)
		fd.test_host = mm
		fd.popped = {}
		_at(t_mine - 20, "in")
		var pp = _popup()
		var hr := Rect2(fd.popup_home(), pp.size if pp != null else Vector2.ZERO)
		var blk: Array = fd.blockers()
		var hit := []
		for bb in blk:
			if hr.intersects(bb as Rect2):
				hit.append(str(bb))
		_ok("D ★[主菜单 %dx%d] 横幅(落点 %s)不压主菜单任何一颗按钮(分母 %d 颗)、整张在屏内" % [vp.x, vp.y, str(hr), blk.size()],
			pp != null and blk.size() >= 8 and hit.is_empty() and Rect2(Vector2.ZERO, Vector2(vp)).encloses(hr), str(hit))
		fd._close_popup()
		fd.test_host = host
		mm.queue_free()
		await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	## ★尺子会动: 正中那个落点左沿放一颗按钮 ⇒ 横幅往右让开、不压它
	var vw := get_viewport().get_visible_rect().size.x
	var x_mid := roundf((vw - fd._POP.W) / 2.0)
	var nb := Button.new()
	nb.position = Vector2(x_mid - 20.0, 0.0)
	nb.size = Vector2(44, 81)
	host.add_child(nb)
	fd.test_host = host
	var hp: Vector2 = fd.popup_home()
	_ok("D ★正中压到一颗按钮 ⇒ 横幅左右挪开(落点 x %.0f → %.0f)、不压它" % [x_mid, hp.x], hp.x != x_mid
		and not Rect2(hp, Vector2(fd._POP.W, fd._POP.H)).intersects(Rect2(nb.position, nb.size)))
	nb.queue_free()
	await get_tree().process_frame
	F.avatars.erase(MON)


# ───────────────────────────── E 跑马灯 ─────────────────────────────

func _mq_reset() -> void:
	fd._facts_prev = null
	fd._had_data = false
	fd.marquee.queue.clear()
	fd.marquee.played.clear()
	fd.marquee.current = ""
	fd.marquee._busy = false
	fd.popped = {}
	fd._close_popup()


func _t_marquee() -> void:
	print("--- E 跑马灯 ---")
	fd.test_host = host
	var seat := SUN + 18 * H
	var t_mine_end: int = int(fx.timeline(4, seat, {"1-1": 1, "2-0": 1}, true)[0]["slots"]["1-1"][1])
	_mq_reset()
	_at(t_mine_end - 5, "in")
	_ok("E ★开屏那一拍只当底: 早已揭晓的(C 组第 1 场)不刷", (fd.marquee.played as Array).is_empty())
	_at(t_mine_end - 1)
	_ok("E ★我那场还在播(结果已在服务端)⇒ 不播「晋级」(不剧透)", (fd.marquee.played as Array).is_empty())
	_at(t_mine_end + 1)
	var want := "吃货一枚 晋级 %s%s" % [M.sheet_name(fx.my_group(t_mine_end)), M.round_name(4, 2)]
	_ok("E ★揭晓那一拍 ⇒ 播「%s」" % want, (fd.marquee.played as Array).has(want) or (fd.marquee.queue as Array).has(want),
		str(fd.marquee.played) + str(fd.marquee.queue))
	## 字真在走
	var lb: Label = fd.marquee._lb
	var x0 := lb.position.x
	for _i in range(40):
		await get_tree().process_frame
	_ok("E ★跑马灯的字真在从右往左走", fd.marquee.visible and lb.position.x < x0 - 5.0, "%.0f → %.0f" % [x0, lb.position.x])
	## 别组的半决赛结果不播(6 组同时打不刷屏), 组冠军播
	_mq_reset()
	var fin_end: int = int(fx.timeline(4, seat, {}, true)[1]["slots"]["2-0"][1])
	_at(fin_end - 2, "in")
	_at(fin_end + 1)
	var all: Array = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	var champs := 0
	for s in all:
		if str(s).find("冠军，晋级%s" % P2.STAGE_CUP) >= 0:
			champs += 1
	_ok("E 各组决赛揭晓 ⇒ 播组冠军(「X 夺得 A 组冠军，晋级冠军杯赛」, 队列只留最新 6 句)", champs >= 5 and str(all).find("夺得 %s冠军" % ChampionData.group_name(0)) >= 0, str(all))
	_mq_reset()
	_at(seat + 11 * MI + 25, "in")
	_at(seat + 11 * MI + 35)
	all = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	var other_semis := 0
	for s in all:
		if str(s).find("晋级 ") >= 0 and str(s).find(M.sheet_name(fx.my_group(seat + 11 * MI + 35))) < 0:
			other_semis += 1
	_ok("E 别组第 1 场揭晓不播(只播我那一组)", other_semis == 0, str(all))
	## ★小组赛同一轮所有场同时开播(用户 10-31 纠正) ⇒ 翻面那一拍只播一句「C 组 半决赛开播」, 不分「第 1 场 / 第 2 场」
	_mq_reset()
	fd.popped = {"%d:1-1" % FX.MY_GROUP: true}       # 我那场的开播横幅算弹过(横幅在场时跑马灯先等, 这里只量跑马灯)
	_at(seat + 8 * MI - 2, "in")
	_at(seat + 8 * MI + 1)
	all = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	var cg := M.sheet_name(fx.my_group(seat + 8 * MI + 1))
	var grp_live := []
	for s0 in all:
		if str(s0).begins_with(cg):
			grp_live.append(str(s0))
	_ok("E ★小组翻面 ⇒ 我那一组只播一句「%s%s开播」(同时开播不分第几场)" % [cg, M.round_name(4, 1)],
		grp_live == ["%s%s开播" % [cg, M.round_name(4, 1)]], str(all))
	## 观众: 各组同一轮同时开播 ⇒ 一句「小组赛 半决赛开播 · 6 组同时进行」(不逐组刷 6 句)
	_mq_reset()
	_at(seat + 8 * MI - 2, "plain")
	_at(seat + 8 * MI + 1)
	all = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	_ok("E ★观众: 小组翻面 ⇒ 只播一句「%s%s开播，6 组同时进行」" % [P2.STAGE_GROUP, M.round_name(4, 1)],
		all == ["%s%s开播，6 组同时进行" % [P2.STAGE_GROUP, M.round_name(4, 1)]], str(all))
	## 冠军杯赛: 排进档期就播开播时刻
	_mq_reset()
	var cup := SUN + int(P2.FINALS_START_HOUR_UTC) * H
	_at(cup + 8 * MI - 2, "plain")
	_at(cup + 8 * MI + 1)
	all = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	var t2: int = int(fx.timeline(6, cup, {})[0]["slots"]["1-3"][0])
	var want_up := "%s %s 开播" % [load("res://scripts/ui/finals_copy.gd").join(P2.STAGE_CUP, M.round_name(6, 1) + "第 2 场"), P2.local_hhmm(t2)]
	_ok("E ★冠军杯赛翻面 ⇒ 播「%s」(时刻来自服务端档期)" % want_up, all.has(want_up), str(all))
	_mq_reset()
	var final_end: int = int(fx.timeline(6, cup, {})[2]["slots"]["3-0"][1])
	_at(final_end - 2, "plain")
	_at(final_end + 1)
	all = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	_ok("E 决赛揭晓 ⇒ 播「小辉同学 夺得冠军杯赛冠军」", all.has("小辉同学 夺得冠军杯赛冠军"), str(all))
	_mq_reset()
	_at(seat - 10 * MI - 2, "plain")
	_at(seat - 10 * MI + 1)
	all = (fd.marquee.played as Array) + (fd.marquee.queue as Array)
	_ok("E 开赛前 10 分钟 ⇒ 播「小组赛 %s 开赛」" % P2.local_hhmm(seat), all.has("%s %s 开赛" % [P2.STAGE_GROUP, P2.local_hhmm(seat)]), str(all))


# ───────────────────────────── F 守到最后 ─────────────────────────────

func _t_recap_mark() -> void:
	print("--- F 在场守到冠军杯赛决出 ⇒ 记「看过了」 ---")
	var cup := SUN + int(P2.FINALS_START_HOUR_UTC) * H
	var final_end: int = int(fx.timeline(6, cup, {})[2]["slots"]["3-0"][1])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RC.SEEN_PATH))
	fd._cup_open_seen = false
	_at(final_end + 30, "in")
	_ok("F 开屏时冠军杯赛已经决出(没守到)⇒ 不记", not RC.seen(MON))
	_at(final_end - 30, "in")
	_at(final_end + 1)
	_ok("F ★亲眼见到「没决出 → 决出」⇒ 记下, 收盘补看不再弹", RC.seen(MON))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RC.SEEN_PATH))
