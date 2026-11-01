extends Node
## verify_finals_copy.gd — 决赛日「玩家看到的字」(方案书 docs/plans/20261101e-决赛日文案与赛前页.md)
##
## 由来: 用户 2026-11-01 看 18:00 前的对阵图(没晋级的号):
##   「哎呦，未晋级的玩家是看不到别人的分组吗？还是什么情况呢？」
##   「但是作为玩家看到的东西是什么呢？你觉得玩家看到合理吗？然后切记你的所有语句，一定要按照商业游戏的口吻去来，
##    一定要按照规则来，不要乱乱用这种语句。」
## 主会话实拍查到三类: ① 分组前没晋级的人整页只有「未晋级 · 需通过周六闯关赛」一把锁; ② 「·」拼短语的日志腔;
##   ③ 同一屏时刻打架(18:05: 底栏「下一场 18:08」、卡片「约 18:03」(已过去)、主按钮「下一轮 3 分 0 秒后开播」)。
##
## ① 赛前页(分组前): 没晋级 / 晋级两种人都有 倒计时 + 本周晋级名单(人数 + 名字) + 今晚赛程(时刻读常量); 名单拿不到时页照样在
## ② 逐句扫: 晋级 / 没晋级 / 第 1 轮出局 × 一整晚 13 个时刻 × 两张页签(对阵图 + 全局小条)+ 主菜单 5 个时刻, 屏上**看得见的每一句**
##    过禁用模式(「·」拼接 / 指令 / 口语 / 内部词 / 钟点式倒计时 /「约 xx:xx」)。★判据先拿改前原句证明会红(_t_judge_self)。
## ③ 同屏时刻: 预告时刻不在过去; 处境句的开播时刻 = 下一行倒计时; 小条正文时刻 = 小条倒计时; 3 秒后所有倒计时少 3 秒(不冻住)。
##
## 跑法: bash godot-quiet.sh res://tests/verify_finals_copy.tscn --quit-after 3000

const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const M := preload("res://scripts/ui/finals_day_model.gd")
const F := preload("res://scripts/ui/finals_day_feed.gd")
const CP := preload("res://scripts/ui/finals_copy.gd")
const Q := preload("res://scripts/net/finals_qualified.gd")
const TP := preload("res://tests/_finals_text_probe.gd")
const FX := preload("res://tests/_finals_day_fixture.gd")
const PRE := preload("res://scripts/scenes/bracket/bracket_preseat.gd")

const MON := 1789344000                  # 2026-09-14 周一 00:00 UTC(与实拍台 / 其余决赛日门禁同一周)
const SUN := MON + 6 * 86400
const H := 3600
const MI := 60
const KEYS := ["promoted", "season_wins", "gauntlet_wins", "gauntlet_losses", "season_total_battles", "test_mode", "hearts",
	"nickname", "first_tips_seen", "onboarded"]
## 一整晚的时刻(分钟): 收盘 / 分组前 / 分组 / 备战 / 等开播 / 半决赛开播 / 组决赛 / 两段之间 / 冠军杯赛前 / 冠军杯赛 1/4 / 场间 / 决赛 / 收盘后
const HMS := [17 * 60 + 30, 17 * 60 + 56, 18 * 60, 18 * 60 + 2, 18 * 60 + 5, 18 * 60 + 9, 18 * 60 + 20, 18 * 60 + 40,
	18 * 60 + 59, 19 * 60 + 5, 19 * 60 + 10, 19 * 60 + 40, 20 * 60 + 30]
const MENU_HMS := [17 * 60 + 30, 18 * 60 + 5, 18 * 60 + 40, 19 * 60 + 5, 20 * 60 + 30]

## ② 禁用模式。[正则, 为什么]
const BAN := [
	["·", "「·」把两件事拼成一行(日志腔): 一行一件事, 要两件事就两行 / 「标签：值」"],
	["需通过|请刷新|自动刷新|点「|点击观看|可继续观看|仅可观战", "给观众下指令 / 教程腔(观众做不到, 或界面自己会做)"],
	["就沿用|不调整就|拿下|输给|去看|还没有|打完|省下|照发|看看", "口语"],
	["桶|查询中|正在查询|连线|收盘|自动分组", "内部词 / 开发状态(载入只写「正在载入」)"],
	["(?<![\\d:])\\d{1,2}:\\d{2}:\\d{2}(?![\\d:])|(?<![\\d:])\\d:\\d{2}(?![\\d:])", "钟点式倒计时(「2:58」「0:29:58」读着像几点几分, 用户 10-04)"],
	["约 ?\\d{2}:\\d{2}", "「约 xx:xx」预告(会过去, 也不是开播时刻)"],
	["下一轮.*后开播", "「下一轮 X 后开播」(第 1 轮也这么写; 轮次名归处境句)"],
	["[一-鿿]\\d|\\d[一-鿿]", "汉字与数字之间少空格(全游戏「24 人」「第 2 场」「1/4 决赛」都留空格)"],
]
## ★改前原句(2026-11-01 主会话实拍 + 走查), 每一句都必须被 BAN 判红 —— 判据会 FAIL 的证明
const OLD := ["未晋级 · 需通过周六闯关赛", "无法连接服务器 · 30 秒后自动刷新", "本轮备战已结束 · 等待开赛",
	"下一轮 3 分 0 秒后开播", "未分组 · 18:00 自动分组", "组冠军得「组冠军」头衔 · 每轮 +6 深海币", "约 18:03",
	"周日 · 决赛日", "小组赛 · 未晋级", "冠军杯赛 · 未开赛", "观战 · A 组 · 半决赛备战中", "你的半决赛 · 对手 Kiki · 备战中",
	"你止步半决赛 · 可继续观看其他对局", "备战中 · 不调整就沿用当前阵容", "你的决赛开播中 · 观看", "2:58", "0:29:58",
	"点「观看开播」进入对阵图", "本周 24 人进入决赛日 · 6 组", "今天 18:00 小组赛 · 19:00 冠军杯赛", "去看 小辉同学 对 阿笨",
	"止步半决赛 · 输给 Kiki", "双方阵容已锁定 · 服务器实时演算", "收盘", "正在查询分组"]
## 改后同类句子不许误报(判据刚好卡住形状)
const NEW_OK := ["本周未晋级决赛日", "无法连接服务器", "阵容已锁定", "距开播 3 分 00 秒", "18:00 公布分组", "冠军奖励：「组冠军」头衔",
	"决赛日", "小组赛", "冠军杯赛", "半决赛备战中", "你的半决赛对手：Kiki", "你止步半决赛", "未调整阵容时沿用当前阵容",
	"你的决赛开播中", "2 分 58 秒", "29 分 58 秒", "18:08", "本周晋级 24 人，分为 6 组", "观看 小辉同学 对 阿笨",
	"止步半决赛，不敌 Kiki", "双方阵容已锁定，由服务器实时演算", "正在载入", "1/4 决赛", "冠军杯赛 19:00 开赛"]

var _n := 0
var _fail := 0
var _bak := {}
var fx
var fd
var _seen_items := 0                      # 扫过的句子总数(分母)
var _seen_screens := 0
var _bad_lines: Dictionary = {}           # 句子 → 第一次见到的屏


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", nm, ("   " + detail) if detail != "" else ""])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 决赛日文案与时刻 ===")
	for k in KEYS:
		_bak[k] = GameState.get(k)
	GameState.test_mode = true
	fd = get_node_or_null("/root/FinalsDay")
	_ok("★分母: autoload FinalsDay 在场", fd != null)
	_t_judge_self()
	await _t_preseat()
	await _t_matrix()
	await _t_menu()
	_t_pure()
	_done()


# ══════════════════════════════ 判据 ══════════════════════════════

## 一句话踩了哪一条禁用模式(""= 干净)。
static func banned(t: String) -> String:
	for b in BAN:
		var re := RegEx.new()
		re.compile(str(b[0]))
		if re.search(t) != null:
			return str(b[1])
	return ""


## 一句里所有「HH:MM」(两位小时)⇒ 分钟数。
static func clocks(t: String) -> Array:
	var out: Array = []
	var re := RegEx.new()
	re.compile("(?<![\\d:])(\\d{2}):(\\d{2})(?![\\d:])")
	for m in re.search_all(t):
		out.append(int(m.get_string(1)) * 60 + int(m.get_string(2)))
	return out


## 一句里的时长(「1 小时 05 分 09 秒」「3 分 00 秒」「9 秒」)⇒ 秒; 没有 = -1。
static func dur_of(t: String) -> int:
	var re := RegEx.new()
	re.compile("(?:(\\d+) 小时 )?(?:(\\d+) 分 )?(\\d+) 秒")
	var m := re.search(t)
	if m == null:
		return -1
	return int(m.get_string(1) if m.get_string(1) != "" else "0") * 3600 + int(m.get_string(2) if m.get_string(2) != "" else "0") * 60 \
		+ int(m.get_string(3))


## 「HH:MM」(设备时区)⇒ 这一天里的那一刻(unix)。
static func clock_ts(now: int, minute_of_day: int) -> int:
	var d: Dictionary = P2.local_dict(now)
	var sod := int(d.get("hour", 0)) * 3600 + int(d.get("minute", 0)) * 60 + int(d.get("second", 0))
	return now - sod + minute_of_day * 60


## ③ 一屏的时刻判据。返回问题列表(空 = 一致)。`items` = 采集器的产物。
static func time_issues(items: Array, now: int) -> Array:
	var bad: Array = []
	var bar_body := ""
	var bar_cd := ""
	var status := ""
	var tip := ""
	for it in items:
		var t := str(it["text"])
		var nm := str(it["path"]).get_file()
		if nm == "FdBarBody":
			bar_body = t
		elif nm == "FdBarCd":
			bar_cd = t
		elif nm == "HeroStatus":
			status = t
		elif t.begins_with("距开播") or t.begins_with("距下一场开播"):
			tip = t
		## R1 预告时刻不在过去: 带「开播 / 开赛 / 开始 / 下一场 / 约」的句子, 以及底部「下一场」卡上那个单独的时刻
		var predictive := t.contains("开播") or t.contains("开赛") or t.contains("开始") or t.contains("下一场") or t.contains("约") \
			or str(it["path"]).contains("NextMatch")
		if predictive and not t.contains("已"):
			for c in clocks(t):
				if clock_ts(now, int(c)) < now - 59:
					bad.append("已过去的预告时刻「%s」" % t)
		## 倒计时不为负 / 不写「0 秒」挂着
		if (t.begins_with("距") or nm == "FdBarCd") and dur_of(t) == 0:
			bad.append("倒计时停在 0「%s」" % t)
	## R2 处境句「HH:MM 开播」与下一行「距开播 X」同一刻
	if status.contains("开播") and not clocks(status).is_empty() and tip != "" and not tip.begins_with("距下一场"):
		var at := clock_ts(now, int(clocks(status)[0]))
		var c2 := now + dur_of(tip)
		if c2 < at or c2 >= at + 60:
			bad.append("处境句「%s」与倒计时「%s」对不上" % [status, tip])
	## R3 小条正文的时刻与小条倒计时同一刻
	if not clocks(bar_body).is_empty() and dur_of(bar_cd) >= 0:
		var at2 := clock_ts(now, int(clocks(bar_body)[0]))
		var c3 := now + dur_of(bar_cd)
		if c3 < at2 or c3 >= at2 + 60:
			bad.append("小条「%s」与倒计时「%s」对不上" % [bar_body, bar_cd])
	return bad


func _t_judge_self() -> void:
	print("── ② / ③ 判据自检(改前原句必须判红, 改后同类句不许误报) ──")
	var miss: Array = []
	for t in OLD:
		if banned(str(t)) == "":
			miss.append(t)
	_ok("★改前原句 %d 句全部判红" % OLD.size(), miss.is_empty(), str(miss))
	var fp: Array = []
	for t in NEW_OK:
		if banned(str(t)) != "":
			fp.append("%s ← %s" % [t, banned(str(t))])
	_ok("改后同类句 %d 句不误报" % NEW_OK.size(), fp.is_empty(), str(fp))
	## ③ 拿 18:05 那一屏的原样(主会话 bracket_1805.png)喂进去 ⇒ 必须报「已过去」; 改后那一屏 ⇒ 干净
	var now := SUN + 18 * H + 5 * MI + 2
	var old_screen := [{"text": "下一场 · 半决赛", "path": "/root/X/NextMatch/@Label@1"}, {"text": "约 18:03", "path": "/root/X/NextMatch/@Label@2"},
		{"text": "小组赛 · 下一场 18:08 开播", "path": "/root/X/FdBarBody"}, {"text": "2 分 58 秒", "path": "/root/X/FdBarCd"},
		{"text": "你的半决赛 18:08 开播", "path": "/root/X/HeroStatus"}, {"text": "距开播 8 分 00 秒", "path": "/root/X/@Label@3"}]
	var oi := time_issues(old_screen, now)
	_ok("★③ 改前那一屏判红(约 18:03 已过去 + 处境句与倒计时差 5 分钟)", oi.size() >= 2, str(oi))
	var new_screen := [{"text": "18:08", "path": "/root/X/NextMatch/@Label@2"}, {"text": "小组赛下一场 18:08 开播", "path": "/root/X/FdBarBody"},
		{"text": "2 分 58 秒", "path": "/root/X/FdBarCd"}, {"text": "你的半决赛 18:08 开播", "path": "/root/X/HeroStatus"},
		{"text": "距开播 2 分 58 秒", "path": "/root/X/@Label@3"}]
	var ni := time_issues(new_screen, now)
	_ok("③ 改后那一屏不误报", ni.is_empty(), str(ni))


# ══════════════════════════════ 搭屏 ══════════════════════════════

func _state(kind: String) -> void:
	fx = FX.new(MON)
	if kind == "out":
		fx.group_wins[FX.MY_GROUP] = {"1-1": 0}
	fx.me_in = kind != "plain"
	GameState.test_mode = true
	GameState.hearts = int(P2.HEARTS_MAX)
	GameState.season_total_battles = 7
	GameState.nickname = "吃货一枚"
	GameState.onboarded = true
	GameState.first_tips_seen = {"finals_day": true, "gauntlet_day": true, "start_battle": true, "first_week": true}
	GameState.promoted = fx.me_in
	GameState.season_wins = int(P2.PROMOTE_WINS) if fx.me_in else 2
	GameState.gauntlet_wins = int(P2.GAUNTLET_WINS_IN) if fx.me_in else 0
	GameState.gauntlet_losses = 0
	Q.override = fx.qualified()


func _set_clock(ts: int, host: Node) -> void:
	P2.now_override_ts = ts
	F.override = fx.feeds(ts)
	if host != null and host.get("_now_override") != null:
		host.set("_now_override", ts)
	if host != null and host.get("clock_override_ts") != null:
		host.set("clock_override_ts", ts)


func _bracket(ts: int) -> Node:
	_set_clock(ts, null)
	var bm = (load("res://scenes/BracketMap.tscn") as PackedScene).instantiate()
	var f: Dictionary = fx.feeds(ts)
	if not ((f["group"] as Dictionary).is_empty() and (f["groups"] as Array).is_empty()):
		bm.set_data(f["group"] if not (f["group"] as Dictionary).is_empty() else (f["groups"] as Array)[0], f["cup"], ts)
	else:
		bm.set_data({"ok": false, "reason": "not_entered" if not fx.me_in else "not_seated"}, f["cup"], ts)
	bm.set_week({"buckets": f["groups"], "cup": f["cup"], "srv_now": ts, "recv_at": ts})
	add_child(bm)
	for _i in range(4):
		await get_tree().process_frame
	if fd != null:
		fd.test_host = bm
		fd.tick()
	await get_tree().process_frame
	return bm


func _collect() -> Array:
	return TP.collect(get_tree().root, Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size))


func _drop(host: Node) -> void:
	if fd != null:
		fd.test_host = null
		fd.tick()
	if host != null and is_instance_valid(host):
		remove_child(host)
		host.free()
	await get_tree().process_frame


## 一屏: 逐句扫 ② + 时刻 ③; 再走 3 秒看倒计时真在动(③ 不冻住)。
func _judge_screen(tag: String, host: Node, ts: int) -> void:
	var items := _collect()
	_seen_screens += 1
	for it in items:
		_seen_items += 1
		var why := banned(str(it["text"]))
		if why != "" and not _bad_lines.has(str(it["text"])):
			_bad_lines[str(it["text"])] = "%s ‹%s› %s" % [tag, str(it["path"]).get_file(), why]
	var ti := time_issues(items, ts)
	if not ti.is_empty():
		_ok("③ %s 同屏时刻一致" % tag, false, str(ti))
	## 3 秒后再采一次: 所有倒计时少 3 秒(±1)
	var before := {}
	for it in items:
		var d := dur_of(str(it["text"]))
		if d > 0 and (str(it["text"]).begins_with("距") or str(it["path"]).get_file() in ["FdBarCd", "PreseatCountdown", "PrepCountdown"]):
			before[str(it["path"])] = d
	if before.is_empty():
		return
	_set_clock(ts + 3, host)
	if fd != null:
		fd.tick()
	## 各屏按墙钟刷字(对阵图 0.5 秒一拍、主菜单 1 秒一拍): 不干等, 直接调那一拍(主菜单 `_sb_poll` / 对阵图 `_refresh_lines`)
	if host != null and host.has_method("_sb_poll"):
		host._sb_poll()
	for _i in range(3):
		await get_tree().process_frame
	if host != null and host.has_method("_refresh_lines"):
		host._refresh_lines()
	if host != null and host.get("_stage") != null:
		host._stage.refresh_texts()
		host._chrome.refresh_texts()
	var frozen: Array = []
	for it in _collect():
		var p := str(it["path"])
		if before.has(p):
			var d2 := dur_of(str(it["text"]))
			var moved := int(before[p]) - d2
			if moved < 2 or moved > 4:
				frozen.append("%s %d→%d" % [p.get_file(), int(before[p]), d2])
	_ok("③ %s 倒计时在走(+3 秒)" % tag, frozen.is_empty(), str(frozen))
	_set_clock(ts, host)


# ══════════════════════════════ ① 赛前页 ══════════════════════════════

func _texts_under(host: Node, root_name: String) -> Array:
	var out: Array = []
	var r := host.find_child(root_name, true, false)
	if r == null:
		return out
	for it in TP.collect(r, Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)):
		out.append(str(it["text"]))
	return out


func _t_preseat() -> void:
	print("── ① 分组前的赛前页 ──")
	var ts := SUN + 17 * H + 56 * MI
	var seat: int = M.seat_ts(ts)
	var cup: int = M.cup_ts(ts)
	for kind in ["plain", "in"]:
		_state(kind)
		var bm = await _bracket(ts)
		var root: Node = bm.find_child(PRE.N_ROOT, true, false)
		_ok("①%s ★赛前页在场(Preseat)" % kind, root != null and (root as CanvasItem).is_visible_in_tree())
		var cd := bm.find_child(PRE.N_COUNT, true, false) as Label
		_ok("①%s 倒计时 = 距分组开赛(%s)" % [kind, cd.text if cd else "无"], cd != null and cd.text == CP.dur(seat - ts))
		var title := bm.find_child(PRE.N_TITLE, true, false) as Label
		_ok("①%s 倒计时前面那半句「距小组赛开始」" % kind, title != null and title.text == "距%s开始" % P2.STAGE_GROUP)
		## 晋级名单: 人数 + 名字(与服务端 finals_qualified_list 同一份, 一个不少)
		var cnt := bm.find_child(PRE.N_LIST_COUNT, true, false) as Label
		_ok("①%s 名单人数「%d 人」" % [kind, int(fx.qualified()["n"])], cnt != null and cnt.text == "%d 人" % int(fx.qualified()["n"]),
			cnt.text if cnt else "无")
		## 名单在滚动框里(看得见的只有前十几行), 名字按行节点读, 不按屏上可见读
		var row_names: Array = []
		var lst := bm.find_child(PRE.N_LIST, true, false)
		var row_nodes: Array = lst.find_children(PRE.N_ROW + "*", "", true, false) if lst != null else []
		for rn in row_nodes:
			for ch in (rn as Node).get_children():
				if ch is Label:
					row_names.append(str((ch as Label).text))
					break
		var names_ok := true
		for it in (fx.qualified()["list"] as Array):
			names_ok = names_ok and str(it["name"]) in row_names
		_ok("①%s 名单 %d 行、名字逐个对上" % [kind, row_nodes.size()], row_nodes.size() == int(fx.qualified()["n"]) and names_ok,
			"rows=%d" % row_nodes.size())
		## 今晚赛程: 两段、时刻读常量(设备时区)
		var sched := _texts_under(bm, PRE.N_SCHED)
		_ok("①%s 今晚赛程: %s %s / %s %s" % [kind, CP.at(seat), P2.STAGE_GROUP, CP.at(cup), P2.STAGE_CUP],
			CP.at(seat) in sched and P2.STAGE_GROUP in sched and CP.at(cup) in sched and P2.STAGE_CUP in sched, str(sched))
		_ok("①%s 资格写成条件, 不写指令" % kind, ("参赛资格：周六闯关赛 %d 胜" % int(P2.GAUNTLET_WINS_IN)) in sched)
		var badge := bm.find_child(PRE.N_BADGE, true, false)
		_ok("①%s 「已晋级」签 %s" % [kind, "在" if kind == "in" else "不在"], (badge != null) == (kind == "in"))
		var vis := _collect()
		var lock := false
		for it in vis:
			if str(it["text"]).contains("未晋级"):
				lock = true
		_ok("①%s 原来那把锁(「未晋级 …」)不在屏上" % kind, not lock)
		await _drop(bm)
	## 名单拿不到(服务端没部署 / 断网): 页照样在, 名单那张写几点公布
	_state("plain")
	Q.override = {}
	var bm2 = await _bracket(ts)
	var em := bm2.find_child(PRE.N_EMPTY, true, false) as Label
	_ok("① 名单拿不到 ⇒ 页仍在、名单卡写「%s 公布」" % CP.at(seat), bm2.find_child(PRE.N_ROOT, true, false) != null and em != null
		and em.text == "%s 公布" % CP.at(seat), em.text if em else "无")
	await _drop(bm2)
	## 不该出的时候不出: 分组之后 / 周一看上周 / 周六
	_state("plain")
	for case in [["18:20 分组之后", SUN + 18 * H + 20 * MI], ["周一", MON + 7 * 86400 + 10 * H], ["周六", SUN - 86400 + 20 * H]]:
		var bm3 = await _bracket(int(case[1]))
		_ok("① %s 不出赛前页" % str(case[0]), bm3.find_child(PRE.N_ROOT, true, false) == null)
		## 这几屏是「没有我这一组」的说明框(周六 / 周一 / 名单接口没回): 也过 ② 逐句扫(结果并进下面「对阵图」那一条)
		await _judge_screen("① " + str(case[0]), bm3, int(case[1]))
		await _drop(bm3)
	Q.override = {}


# ══════════════════════════════ ② ③ 一整晚 ══════════════════════════════

func _t_matrix() -> void:
	print("── ② 逐句扫 / ③ 同屏时刻: 3 种人 × %d 个时刻 × 两张页签 ──" % HMS.size())
	for kind in ["plain", "in", "out"]:
		_state(kind)
		for hm in HMS:
			var ts := SUN + int(hm) * MI
			var bm = await _bracket(ts)
			var tag := "%s %02d:%02d" % [kind, int(hm) / 60, int(hm) % 60]
			await _judge_screen(tag + " " + str(bm._view), bm, ts)
			bm.pick_view("finals" if str(bm._view) != "finals" else "bucket")
			for _i in range(3):
				await get_tree().process_frame
			if fd != null:
				fd.tick()
			await _judge_screen(tag + " " + str(bm._view), bm, ts)
			await _drop(bm)
	_ok("★分母: 扫了 %d 屏、%d 句" % [_seen_screens, _seen_items], _seen_screens >= 70 and _seen_items >= 1500)
	var lines: Array = []
	for t in _bad_lines:
		lines.append("「%s」%s" % [t, _bad_lines[t]])
	_ok("② 对阵图 + 全局小条: 屏上没有一句踩禁用模式", lines.is_empty(), "\n      " + "\n      ".join(PackedStringArray(lines)))
	_bad_lines.clear()


func _t_menu() -> void:
	print("── ② / ③ 主菜单(决赛日卡 / 模式卡 / 主按钮 / 全局小条) ──")
	var n0 := _seen_screens
	for kind in ["plain", "in", "out"]:
		_state(kind)
		for hm in MENU_HMS:
			var ts := SUN + int(hm) * MI
			_set_clock(ts, null)
			StudioIntro.played = true
			var mm = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
			mm.clock_override_ts = ts
			add_child(mm)
			for _i in range(4):
				await get_tree().process_frame
			mm._wk().fd.feed_override = fx.feeds(ts)
			if fd != null:
				fd.test_host = mm
				fd.tick()
			for _i in range(3):
				await get_tree().process_frame
			await _judge_screen("menu %s %02d:%02d" % [kind, int(hm) / 60, int(hm) % 60], mm, ts)
			await _drop(mm)
	_ok("★分母: 主菜单扫了 %d 屏" % (_seen_screens - n0), _seen_screens - n0 == 3 * MENU_HMS.size())
	var lines: Array = []
	for t in _bad_lines:
		lines.append("「%s」%s" % [t, _bad_lines[t]])
	_ok("② 主菜单: 屏上没有一句踩禁用模式", lines.is_empty(), "\n      " + "\n      ".join(PackedStringArray(lines)))
	_bad_lines.clear()


# ══════════════════════════════ 纯函数那几句(屏上要等特定时机才出的) ══════════════════════════════

func _t_pure() -> void:
	print("── ② 观战页 / 跑马灯 / 收盘补看 那几句 ──")
	var Ctx = load("res://scripts/scenes/battle/finals_ctx.gd")
	var PS = load("res://scripts/systems/replay/premiere_schedule.gd")
	var BMS = load("res://scripts/scenes/BracketMapScene.gd")
	var st_cup := {"cup": true, "round_name": "半决赛", "match_i": 1, "match_n": 2, "round": 2, "rounds": 3}
	var st_grp := {"group": 2, "round_name": "决赛", "round": 2, "rounds": 2}
	var lines := [Ctx.TXT_LOCKED, Ctx.round_title(st_cup), Ctx.round_title(st_grp), Ctx.stage_tag(st_cup),
		Ctx.go_label({"a": "小辉同学", "b": "阿笨"}), Ctx.next_line({"a": "小辉同学", "b": "阿笨", "at": SUN + 19 * H + 12 * MI}),
		Ctx.next_line({"a": "小辉同学", "b": "阿笨", "settling": true}), Ctx.out_line(st_cup, "Kiki"), PS.TXT_SETTLE,
		BMS.shop_tip(true, 150, true), BMS.shop_tip(false, 0, true), BMS.cup_soon_head(0), BMS.cup_soon_head(3000),
		BMS.cup_solo_text({"names": ["风起"], "tags": ["#P0101"]}), BMS.round_tip(1, 4, 0), BMS.round_tip(1, 4, 200)]
	for r in ["already_asked", "wrong_round", "not_in_bucket", "empty_snapshot", "shop_open", "settled", "update_required", "net", "?"]:
		lines.append(BMS.opponent_tip({"ok": false, "reason": r, "asked": 3}, true))
	lines.append(BMS.opponent_tip({"ok": true, "name": "Kiki"}, true))
	## 跑马灯一整晚(观众 / 我那一组)
	for kind in ["plain", "in"]:
		_state(kind)
		for hm in HMS:
			var ts := SUN + int(hm) * MI
			var f: Dictionary = fx.feeds(ts)
			for v in M.facts(f["groups"], f["cup"], ts, FX.MY_GROUP if kind == "in" else -1).values():
				lines.append(str(v))
	var bad: Array = []
	for t in lines:
		if str(t) != "" and banned(str(t)) != "":
			bad.append("「%s」%s" % [t, banned(str(t))])
	_ok("② %d 句(观战页名牌 / 下一场条 / 出局句 / 对手提示 / 跑马灯)不踩禁用模式" % lines.size(), bad.is_empty(),
		"\n      " + "\n      ".join(PackedStringArray(bad)))
	## 全决赛日只有一种时长写法 / 一套轮次名
	_ok("时长一种写法: 3 分 00 秒 / 1 小时 05 分 09 秒 / 9 秒", CP.dur(180) == "3 分 00 秒" and CP.dur(3909) == "1 小时 05 分 09 秒"
		and CP.dur(9) == "9 秒" and M.clock_text(180) == CP.dur(180) and BMS.countdown_text(180) == CP.dur(180)
		and Ctx.span_text(180) == CP.dur(180))
	var L = load("res://scripts/gamedata/bracket_layout.gd")
	var Hero = load("res://scripts/scenes/bracket/bracket_hero.gd")
	var Bk = load("res://scripts/gamedata/bracket.gd")
	var same := true
	for n in [2, 4, 6, 8, 16, 32]:
		for r in range(1, 6):
			if r <= int(Bk.rounds_for(n)):
				same = same and L.round_label(n, r) == CP.round_name(n, r) and Hero.round_name(n, r) == CP.round_name(n, r) \
					and M.round_name(n, r) == CP.round_name(n, r)
	_ok("轮次名一套: 主菜单 / 全局小条 / 对阵图 / 观战页同一个函数(6 人表第 1 轮 = %s)" % CP.round_name(6, 1),
		same and CP.round_name(6, 1) == "1/4 决赛" and CP.round_name(8, 3) == "决赛")


func _done() -> void:
	if fd != null:
		fd.test_host = null
		fd.tick()
	F.override = {}
	Q.override = {}
	P2.now_override_ts = 0
	for k in _bak.keys():
		GameState.set(k, _bak[k])
	print("  (用了 %d 帧)" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
