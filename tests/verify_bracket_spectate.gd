extends Node
## verify_bracket_spectate — 周日对阵图手机实拍的四处(2026-10-04, 用户「改」)
##
## 用户在手机上(2340×1080, 本周没晋级, 决赛 08:24 UTC 已打完)看到:
##   · 冠军页签「冠军赛 · 未开赛」+ 正文「本周按各组自己算冠军 · 你这一组的冠军就是本周冠军」
##   · 我这一组页签「我这一组 · 还没分」+ 正文「本周没有你这一组 · 周六闯关赛晋级才进得来」
##   · 两张图上的顶栏都只铺到屏幕约 70%, 右边是黑的
## 四处修法与判据:
##   ① 我这一组: 页签字与正文**同一份判断**(`_bucket_kind()`), 三态 未晋级 / 等分组 / 已分组
##   ② 冠军页: 跨组没上线时叫「本周冠军」, 列各组冠军(名字 + #ID); 全部 / 部分 / 一组都没决出
##   ③ 观赛: 没晋级的人看得到本周各组的对阵(只读); 服务端没部署时不报错、退回「未晋级」;
##      **当前轮结果不许漏** —— 假传输塞一份「服务端写错了」的回包, 客户端第二道锁要筛掉
##   ④ 顶栏宽 == 视口宽(1280×720 与 2340×1080), 同一原语的其他屏一起量
## ★走真入口: 页签字读真按钮, 正文读真 Label, 网络走 `_transport_for_test`(量真实发出的请求)。

const MAP := preload("res://scripts/scenes/BracketMapScene.gd")
const SB := preload("res://scripts/net/supabase.gd")
const L := preload("res://scripts/gamedata/bracket_layout.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

const SUN0 := 1789862400                 # 2026-09-20 周日 00:00 UTC
const SUN_EARLY := SUN0 + 7 * 3600       # 分组(08:00 UTC)之前
const SUN_NOON := SUN0 + 12 * 3600       # 分组之后、冠军签表(20:00)之前

## 用 `TopBar` 原语的枢纽屏(与 verify_top_bar 同源; 阵容屏只借薄片皮、没有整条栏; 匹配屏是过场, 理由见 verify_top_bar)
const SCREENS := ["Record", "Settings", "Leaderboard", "Inventory", "Codex", "Shop"]

var _n := 0
var _fail := 0
var _reqs: Array = []
var _week_reply: Dictionary = {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 周日对阵图: 页签三态 / 本周冠军 / 观赛 / 顶栏通宽 ===")
	await _t_tabs()
	await _t_champ()
	await _t_spectate()
	await _t_topbar()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 对阵图观赛" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _tab(m, i: int) -> String:
	return str((m._tabs.get_child(i) as Button).text)


func _mk(bucket: Dictionary, now: int, week = null):
	var m = MAP.new()
	add_child(m)
	await get_tree().process_frame
	m.set_data(bucket, {}, now)
	if week != null:
		m.set_week(week)
	await get_tree().process_frame
	return m


# ─────────────────────────────────────────────────────────────
# ① 我这一组: 三态, 页签与正文同一份判断
# ─────────────────────────────────────────────────────────────
func _t_tabs() -> void:
	print("── ① 我这一组 三态 ──")
	## 纯函数: 每一档的后缀
	var kinds := [MAP.EK_SEATED, MAP.EK_NO_GROUP, MAP.EK_SPECTATE, MAP.EK_NOT_SEATED,
		MAP.EK_TOO_FEW, MAP.EK_UNREACHABLE, MAP.EK_WAIT]
	var seen := {}
	for k in kinds:
		var sfx := str(MAP.bucket_tab_suffix(k))
		seen[sfx] = true
		_ok("① 后缀 %s ⇒「我这一组%s」不再出现「还没分」" % [k, sfx], sfx.find("还没分") < 0, sfx)
	_ok("① ★没晋级 ⇒ 未晋级", MAP.bucket_tab_suffix(MAP.EK_NO_GROUP) == " · 未晋级")
	_ok("① ★观赛也是没晋级(同一档字)", MAP.bucket_tab_suffix(MAP.EK_SPECTATE) == " · 未晋级")
	_ok("① ★晋级了、还没到分组时间 ⇒ 等分组", MAP.bucket_tab_suffix(MAP.EK_NOT_SEATED) == " · 等分组")
	_ok("① ★分好组了 ⇒ 不带后缀(与原来一样)", MAP.bucket_tab_suffix(MAP.EK_SEATED) == "")

	## 真屏: 三种真实输入 → 页签字 / 正文 / 分类
	var cases := [
		["没晋级", {}, SUN_NOON, MAP.EK_NO_GROUP, "我这一组 · 未晋级", "晋级才进得来"],
		["晋级·分组前(服务端 not_seated)", {"reason": "not_seated", "entered": 6}, SUN_NOON,
			MAP.EK_NOT_SEATED, "我这一组 · 等分组", "还没分组"],
		["晋级·分组前(服务端还回 too_few)", {"reason": "too_few", "entered": 6}, SUN_EARLY,
			MAP.EK_NOT_SEATED, "我这一组 · 等分组", "还没分组"],
		["已分组", {"size": 4, "round": 1, "me": 1, "names": ["阿龟", "小乙", "老丙", "丁丁"],
			"done": {}}, SUN_NOON, MAP.EK_SEATED, "我这一组", ""],
	]
	var kinds_seen := {}
	for c in cases:
		var m = await _mk(c[1], int(c[2]))
		var kind := str(m._bucket_kind())
		var t0 := _tab(m, 0)
		kinds_seen[kind] = true
		_ok("① 真屏[%s] 分类 = %s" % [c[0], c[3]], kind == str(c[3]), kind)
		_ok("① ★真屏[%s] 页签 =「%s」" % [c[0], c[4]], t0 == str(c[4]), t0)
		## ★★页签与正文同一份判断: 页签后缀 == 由正文那份分类算出的后缀
		_ok("① ★★真屏[%s] 页签字从正文那份分类出(不是两处各判各的)" % c[0],
			t0 == "我这一组" + MAP.bucket_tab_suffix(str(m._empty_kind())),
			"页签「%s」/ 正文分类 %s" % [t0, str(m._empty_kind())])
		if str(c[5]) != "":
			_ok("① 真屏[%s] 正文可见且说的是这件事" % c[0],
				m._empty_lb.visible and str(m._empty_lb.text).find(str(c[5])) >= 0,
				str(m._empty_lb.text))
		else:
			_ok("① 真屏[%s] 画的是对阵(没有空态框)" % c[0], not m._empty_lb.visible)
		m.queue_free()
		await get_tree().process_frame
	_ok("① ★分母: 三态真的走到了三个不同分类", kinds_seen.size() == 3, str(kinds_seen.keys()))


# ─────────────────────────────────────────────────────────────
# ② 本周冠军(跨组总决赛没上线)
# ─────────────────────────────────────────────────────────────
func _week_body(buckets: Array) -> String:
	return JSON.stringify({"ok": true, "week": SUN0, "now": SUN_NOON, "buckets": buckets})


func _b2(no: int, a: String, b: String, round_no: int, closed: bool, done: Dictionary) -> Dictionary:
	return {"bucket": no, "n": 2, "round": round_no, "closed": closed, "done": done,
		"entrants": [{"seed": 0, "name": a, "account_id": "uid-%s" % a},
			{"seed": 1, "name": b, "account_id": "uid-%s" % b}]}


func _champ_text(bucket: Dictionary, week_body: String) -> Array:
	var wk: Dictionary = SB.parse_finals_week(true, 200, week_body, "uid-zz", 1)
	var m = await _mk(bucket, SUN_NOON, wk)
	m.set_view(L.VIEW_FINALS)
	await get_tree().process_frame
	var out := [str(m._empty_kind()), str(m._empty_lb.text), _tab(m, 1), bool(m._empty_lb.visible)]
	m.queue_free()
	await get_tree().process_frame
	return out


func _t_champ() -> void:
	print("── ② 本周冠军 ──")
	_ok("② ★分母: 跨组总决赛确实没上线(这一节量的就是这种情况)", not MAP.CROSS_BUCKET_LIVE)
	_ok("② ★上线前页签叫「本周冠军」", MAP.finals_tab_text(0) == "本周冠军", MAP.finals_tab_text(0))
	## 2 人组: 决赛 = 第 1 轮第 0 场; 坐次 0/1 = 种子 0/1 ⇒ 「1-0 = 1」就是种子 1 夺冠, 手算得出来
	_ok("② ★分母: 2 人组的坐次就是种子(下面的手算冠军成立)",
		preload("res://scripts/gamedata/bracket.gd").seed_at_seat(1, 2) == 1)
	var tag_b := P2C.player_tag("uid-乙龟")
	var tag_c := P2C.player_tag("uid-丙龟")
	_ok("② ★分母: 两个号算得出来且不同", tag_b != "" and tag_b != tag_c, "%s / %s" % [tag_b, tag_c])

	var all := await _champ_text({}, _week_body([
		_b2(0, "甲龟", "乙龟", 1, true, {"1-0": 1}),
		_b2(1, "丙龟", "丁龟", 1, true, {"1-0": 0})]))
	print("  ② 全部决出: 「%s」" % str(all[1]).replace("\n", " / "))
	_ok("② 全部决出: 分类 = 各组冠军这一档", all[0] == MAP.EK_FINALS_LOCAL, all[0])
	_ok("② ★全部决出: 页签「本周冠军」, 不再是「冠军赛 · 未开赛」", all[2] == "本周冠军", all[2])
	_ok("② ★★全部决出: 说「全部决出」并列出两组冠军(名字 + #ID)",
		str(all[1]).find("全部决出") >= 0 and str(all[1]).find("乙龟 " + tag_b) >= 0
		and str(all[1]).find("丙龟 " + tag_c) >= 0, all[1])
	_ok("② ★全部决出: 败者不上榜", str(all[1]).find("甲龟") < 0 and str(all[1]).find("丁龟") < 0, all[1])
	_ok("② ★★不再对没晋级的人说「你这一组」", str(all[1]).find("你这一组") < 0, all[1])

	var part := await _champ_text({}, _week_body([
		_b2(0, "甲龟", "乙龟", 1, true, {"1-0": 1}),
		_b2(1, "丙龟", "丁龟", 1, false, {})]))
	print("  ② 部分决出: 「%s」" % str(part[1]).replace("\n", " / "))
	_ok("② ★★部分决出: 「决赛进行中」+ 已决出 1/2 + 已决出的那位",
		str(part[1]).find("决赛进行中") >= 0 and str(part[1]).find("1/2") >= 0
		and str(part[1]).find("乙龟") >= 0, part[1])
	_ok("② 部分决出: 没打完那组不许出冠军", str(part[1]).find("丙龟") < 0 and str(part[1]).find("丁龟") < 0, part[1])

	var none := await _champ_text({}, _week_body([
		_b2(0, "甲龟", "乙龟", 1, false, {}), _b2(1, "丙龟", "丁龟", 1, false, {})]))
	_ok("② ★一组都没决出: 「决赛进行中」且一个名字都不报",
		str(none[1]).find("决赛进行中") >= 0 and str(none[1]).find("龟") < 0, none[1])
	var empty := await _champ_text({}, _week_body([]))
	_ok("② 本周一个组都没有: 说什么时候公布, 不编冠军", str(empty[1]).find("公布") >= 0, empty[1])
	_ok("② ★★三档说的是三句不同的话(否则上面有一条是蒙的)",
		all[1] != part[1] and part[1] != none[1] and all[1] != none[1])

	## 观赛接口没上线(回包里没有 buckets 键): 没晋级的人 ⇒ 不编、不说「你这一组」、不说「全部决出」
	var off := await _champ_text({}, "")
	_ok("② ★接口没上线 + 没晋级: 不说「你这一组」也不说「全部决出」",
		str(off[1]).find("你这一组") < 0 and str(off[1]).find("全部决出") < 0 and off[3], off[1])
	## 接口没上线 + 我自己那一组打完了: 至少报出我那一组的冠军(这是手机上那一刻真实可得的信息)
	var mine := {"size": 2, "round": 1, "me": 0, "closed": true, "bucket": 0,
		"names": ["甲龟", "乙龟"], "tags": ["", tag_b], "done": {"1-0": 1}}
	var off2 := await _champ_text(mine, "")
	_ok("② 接口没上线 + 我那一组已决出: 报出冠军, 但不冒称「全部决出」",
		str(off2[1]).find("乙龟") >= 0 and str(off2[1]).find("全部决出") < 0, off2[1])

	## ★★第二道锁: 服务端写错一行、把当前轮的决赛结果漏下来 ⇒ 客户端不许报冠军
	var leak := await _champ_text({}, _week_body([_b2(0, "甲龟", "乙龟", 1, false, {"1-0": 1})]))
	_ok("② ★★★当前轮的决赛结果(未翻面)漏下来 ⇒ 冠军页不报冠军",
		str(leak[1]).find("乙龟") < 0 and str(leak[1]).find("甲龟") < 0, leak[1])


# ─────────────────────────────────────────────────────────────
# ③ 观赛: 走真网络入口, 假传输塞服务端回包
# ─────────────────────────────────────────────────────────────
func _spy(method, url, headers, body, cb) -> void:
	_reqs.append({"method": str(method), "url": str(url), "body": str(body)})
	if str(url).ends_with("/finals_week_view"):
		cb.call(_week_reply)
	elif str(url).ends_with("/finals_view"):
		cb.call({"ok": true, "code": 200, "body": '{"ok":false,"reason":"not_entered"}'})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _poll_round(m) -> void:
	m._pull()
	for _i in range(4):
		await get_tree().process_frame
	m._on_poll()
	await get_tree().process_frame


func _count_ticks(n: Node) -> int:
	var c := 0
	if n is Label and str((n as Label).text).begins_with("✓"):
		c += 1
	for ch in n.get_children():
		c += _count_ticks(ch)
	return c


func _t_spectate() -> void:
	print("── ③ 观赛 ──")
	var _env0: String = OS.get_environment(SB.ENV_URL)
	var _envk = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	_ok("③ ★分母: 后端真的打开了(关着的话下面全是空检查)", SB.enabled())
	var gs = get_node_or_null("/root/GameState")
	var acc0 := str(gs.account_id) if gs != null else ""
	if gs != null:
		gs.account_id = "uid-zz"            # 不在任何一组里 = 没晋级
	SB._token = "gate-token"
	SB._transport_for_test = _spy
	SB.finals_clear()
	SB.finals_week_clear()
	P2C.now_override_ts = SUN_NOON

	## ── 服务端还没部署 finals_week_view(PostgREST 回 404) ──
	_week_reply = {"ok": true, "code": 404,
		"body": '{"code":"PGRST202","message":"Could not find the function public.finals_week_view"}'}
	_reqs.clear()
	var m = MAP.new()
	add_child(m)
	for _i in range(4):
		await get_tree().process_frame
	m._on_poll()
	await get_tree().process_frame
	var wreq: Array = _reqs.filter(func(r): return str(r["url"]).ends_with("/finals_week_view"))
	_ok("③ ★分母: 真的发了 finals_week_view 请求", wreq.size() >= 1, str(_reqs.size()))
	if not wreq.is_empty():
		_ok("③ 请求带的是本周锚点", str(wreq[0]["body"]).find(str(P2C.week_anchor_utc(SUN_NOON))) >= 0,
			str(wreq[0]["body"]))
	_ok("③ ★★没部署 ⇒ 缓存标「暂时没有」, 不是「问不到」",
		str(SB.finals_week_cached().get("reason", "")) == "unavailable", str(SB.finals_week_cached()))
	_ok("③ ★★没部署 ⇒ 屏幕照旧说「未晋级」(不报错、不画半张图)",
		str(m._bucket_kind()) == MAP.EK_NO_GROUP and _tab(m, 0) == "我这一组 · 未晋级"
		and m._empty_lb.visible and not m._spec_bar.visible,
		"%s / %s" % [str(m._bucket_kind()), _tab(m, 0)])

	## ── 上线了: 下一次轮询自动变成观赛 ──
	## ★回包里故意塞两样服务端**不该**给的东西: 当前轮的结果(2-0 / 第二组 1-0)、一份阵容快照。
	var body := JSON.stringify({"ok": true, "week": SUN0, "now": SUN_NOON, "buckets": [
		{"bucket": 0, "n": 4, "round": 2, "closed": false,
			"done": {"1-0": 0, "1-1": 1, "2-0": 0},
			"entrants": [
				{"seed": 0, "name": "阿龟", "account_id": "uid-a", "snapshot": {"leaders": ["basic"]}},
				{"seed": 1, "name": "小乙", "account_id": "uid-b"},
				{"seed": 2, "name": "老丙", "account_id": "uid-c"},
				{"seed": 3, "name": "丁丁", "account_id": "uid-d"}]},
		{"bucket": 1, "n": 2, "round": 1, "closed": false, "done": {"1-0": 1},
			"entrants": [{"seed": 0, "name": "戊龟", "account_id": "uid-e"},
				{"seed": 1, "name": "己龟", "account_id": "uid-f"}]}]})
	_week_reply = {"ok": true, "code": 200, "body": body}
	await _poll_round(m)
	_ok("③ ★★上线后不用重开: 下一次轮询就变成观赛", str(m._bucket_kind()) == MAP.EK_SPECTATE,
		str(m._bucket_kind()))
	_ok("③ ★★页签仍是「未晋级」(观赛与没晋级同一档字, 页签与正文同源)",
		_tab(m, 0) == "我这一组 · 未晋级", _tab(m, 0))
	_ok("③ 观赛那一行可见, 说清「只能看」", m._spec_bar.visible and str(m._spec_lb.text).find("只能看") >= 0,
		str(m._spec_lb.text))
	_ok("③ 画的是第 1 组(4 人), 不是空态框", int(m.cur().get("size", 0)) == 4 and not m._empty_lb.visible,
		"size=%d" % int(m.cur().get("size", 0)))
	_ok("③ ★观众的种子号 = -1", int(m.cur().get("me", 0)) == -1)
	var dn: Dictionary = m.cur().get("done", {})
	_ok("③ ★分母: 已翻面的两场在(第 1 轮)", dn.has("1-0") and dn.has("1-1"), str(dn))
	_ok("③ ★★★当前轮(第 2 轮)的结果没漏进来", not dn.has("2-0"), str(dn))
	_ok("③ ★★★屏幕上的「✓」只有已翻面的两场", _count_ticks(m._canvas) == 2,
		"✓ 条数 = %d" % _count_ticks(m._canvas))
	_ok("③ ★★阵容快照没进缓存", str(SB.finals_week_cached()).find("snapshot") < 0
		and str(SB.finals_week_cached()).find("leaders") < 0)
	var clickable := 0
	var nmatch := 0
	for r in range(1, 3):
		for mm in range(preload("res://scripts/gamedata/bracket.gd").matches_in_round(4, r)):
			nmatch += 1
			if m.can_open(r, mm) or m.should_fetch_opponent(r, mm):
				clickable += 1
	_ok("③ ★★只读: %d 场一场都点不动(不会替人去问对手)" % nmatch, nmatch == 3 and clickable == 0,
		"可点 %d" % clickable)
	_ok("③ 观众不显示「备战购物」那一行", m._shop_row == null or not m._shop_row.visible,
		str(m._shop_row.text) if m._shop_row != null else "")
	m._spec_step(1)
	await get_tree().process_frame
	_ok("③ 换到下一组(2 人)", int(m.cur().get("size", 0)) == 2 and str(m._spec_lb.text).find("第 2 组") >= 0,
		str(m._spec_lb.text))
	_ok("③ ★★★第二组当前轮的决赛结果也没漏", (m.cur().get("done", {}) as Dictionary).is_empty()
		and _count_ticks(m._canvas) == 0, str(m.cur().get("done", {})))
	## 冠军页也用这一份: 第二组没翻面 ⇒ 一个冠军都没有
	m.set_view(L.VIEW_FINALS)
	await get_tree().process_frame
	_ok("③ 冠军页(同一份数据): 两组都没决出 ⇒ 决赛进行中", str(m._empty_lb.text).find("决赛进行中") >= 0,
		str(m._empty_lb.text))
	_ok("③ 冠军页上观赛那一行不出现", not m._spec_bar.visible)
	m.queue_free()
	await get_tree().process_frame

	## ── 问不到(网络断) 不许抹掉已经到手的观赛数据 ──
	var keep: int = (SB.finals_week_cached().get("buckets", []) as Array).size()
	_week_reply = {"ok": false, "code": 0, "body": ""}
	SB._finals_week_inflight = false
	SB.fetch_finals_week_async(P2C.week_anchor_utc(SUN_NOON))
	for _i in range(4):
		await get_tree().process_frame
	_ok("③ ★网络抖一下, 观赛数据还在", keep == 2
		and (SB.finals_week_cached().get("buckets", []) as Array).size() == keep)

	## 收尾: 全部还原(static 活过本测试)
	P2C.now_override_ts = 0
	SB._transport_for_test = Callable()
	SB.finals_clear()
	SB.finals_week_clear()
	SB._token = ""
	if gs != null:
		gs.account_id = acc0
	OS.set_environment(SB.ENV_URL, _env0)
	ProjectSettings.set_setting(SB.SETTING_KEY, _envk)
	_ok("③ ★收尾: 后端已关回去", not SB.enabled())


# ─────────────────────────────────────────────────────────────
# ④ 顶栏宽 == 视口宽
# ─────────────────────────────────────────────────────────────
func _find_bar(n: Node) -> Control:
	if n is Control and n.name == "TopBar":
		return n as Control
	for ch in n.get_children():
		var f := _find_bar(ch)
		if f != null:
			return f
	return null


func _t_topbar() -> void:
	print("── ④ 顶栏通宽 ──")
	for sz in [Vector2i(1280, 720), Vector2i(2340, 1080)]:
		get_tree().root.size = sz
		for _i in range(3):
			await get_tree().process_frame
		var vp: Vector2 = get_viewport().get_visible_rect().size
		print("  窗口 %dx%d ⇒ 视口 %.0fx%.0f" % [sz.x, sz.y, vp.x, vp.y])
		if sz.x == 2340:
			_ok("④ ★分母: 宽屏下视口真的比设计宽 1280 宽(否则这一档量不出东西)", vp.x > 1281.0,
				"%.0f" % vp.x)
		var hosts: Array = ["Bracket"] + SCREENS
		for h in hosts:
			var inst: Node = null
			if h == "Bracket":
				inst = MAP.new()
			else:
				inst = (load("res://scenes/%s.tscn" % h) as PackedScene).instantiate()
			add_child(inst)
			for _i in range(30):
				await get_tree().process_frame
			var bar := _find_bar(inst)
			if bar == null:
				_ok("④ [%s %dx%d] 找到顶栏" % [h, sz.x, sz.y], false)
			else:
				var r := bar.get_global_rect()
				_ok("④ ★★[%s %dx%d] 顶栏 = 视口通宽" % [h, sz.x, sz.y],
					absf(r.position.x) < 0.5 and absf(r.size.x - vp.x) < 0.5,
					"x=%.0f w=%.0f 视口 %.0f" % [r.position.x, r.size.x, vp.x])
				## 右侧动作(若有)贴着右沿, 不停在 1280 那条线上
				var right_edge := 0.0
				for b in bar.get_children():
					if b is Button and (b as Button).visible and (b as Button).get_global_rect().position.x > vp.x * 0.5:
						right_edge = maxf(right_edge, (b as Button).get_global_rect().end.x)
				if right_edge > 0.0:
					_ok("④ [%s %dx%d] 右侧动作贴右沿" % [h, sz.x, sz.y],
						right_edge <= vp.x + 0.5 and right_edge >= vp.x - 120.0,
						"右沿 %.0f / 视口 %.0f" % [right_edge, vp.x])
			inst.queue_free()
			for _i in range(2):
				await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	await get_tree().process_frame
