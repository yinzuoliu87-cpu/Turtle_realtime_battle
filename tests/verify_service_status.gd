extends Node
## verify_service_status.gd — D-1：服务状态三态，以及主菜单真的会显示维护公告（2026-09-20）
##
## ══════════════════════════════════════════════════════════════════════
##  这份门禁守什么
## ══════════════════════════════════════════════════════════════════════
## `remote_pool.gd` 只有两态（配了 / 没配），连不上就**静默**回落到本地池。
## 平时这是对的，但方案书 U7/§4.7 拍板「版本维护期放在周一休赛，停服 → 发版本 → 开服」——
## 那时玩家只会看到「连不上」，**以为游戏坏了**。静默失败比失败本身危险：失败会被修，静默不会。
##
## ⇒ `SupabaseNet` 给出五个取值，要紧的是这三条**必须互相分得开**：
##   · `ST_OFF`          没配后端 —— **有意关掉**（当前就是），玩家侧什么都不显示
##   · `ST_MAINTENANCE`  服务端**主动**说在维护 —— 这一态才盖掉赛程显示
##   · `ST_UNREACHABLE`  配了但问不到 —— 网络问题，同样**不**喊话
##
## ══════════════════════════════════════════════════════════════════════
##  判据为什么这么写
## ══════════════════════════════════════════════════════════════════════
## ★① 三态**逐个喂真回包**给 `state_from_response()`（纯函数，不碰网络，每条分支都喂得到）。
## ★② **答案必须互不相同** —— 只验「维护时返回 maintenance」的话，一个恒返回 maintenance
##     的实现照样绿。分得开才是这一层存在的全部意义。
## ★③ **不许把"不知道"说成"正常"**：传输失败 / 5xx / 空数组，都必须是 `UNREACHABLE`
##     而不是 `OK`。这是静默失败的源头，单独一条钉住。
## ★★④ **走真入口**：实例化 `MainMenu.tscn`，把状态摆成维护态，断言**屏幕上真有那行字**。
##     只验纯函数的话，这一层完全可能是个「写了没人读」——本项目今天刚修过三个同族的
##     （`week_anchor_ts` / `week_phase` / `backfill_ranked_quota`）。
##     配**分母**：非维护态时那行字**不许**出现，否则「找得到」是恒真式。
## ★⑤ 没配后端时 `fetch_status_async()` **连一个节点都不建**（分母：树上子节点数不变）。
##     门禁进程本来就 `TURTLE_SUPABASE=" "`，这条顺手把"停用真的停用"钉住。

const SB := preload("res://scripts/net/supabase.gd")
const MENU := preload("res://scenes/MainMenu.tscn")

var _ok := 0
var _fail := 0
var _tree: SceneTree = null


func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])


func _ready() -> void:
	_tree = get_tree()
	await get_tree().process_frame
	GameState.test_mode = true
	print("=== D-1 服务状态三态 ===")
	_t_pure()
	_t_not_ok_when_unknown()
	_t_disabled_makes_nothing()
	await _t_real_menu()
	SB._reset_for_test()
	print("")
	print("  (共 %d 条断言)" % (_ok + _fail))
	print("ALL PASS — 服务状态三态" if _fail == 0 else "FAIL x%d" % _fail)
	if _tree != null:
		_tree.quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 三态逐个喂真回包 + ② 答案必须互不相同
# ─────────────────────────────────────────────────────────────
func _t_pure() -> void:
	print("── ① 三态(喂真实形状的回包) ──")
	## 真实回包长这样 —— 是我 2026-09-20 用 curl 打 Supabase 实际取回来的形状
	var body_ok := '[{"id":1,"maintenance":false,"notice":"","min_client_version":"0.0.0"}]'
	var body_mt := '[{"id":1,"maintenance":true,"notice":"周一维护, 21:00 回来","min_client_version":"0.19.418"}]'

	var s_ok := SB.state_from_response(true, 200, body_ok)
	var s_mt := SB.state_from_response(true, 200, body_mt)
	var s_un := SB.state_from_response(false, 0, "")

	_chk("① 正常 → ok", str(s_ok["state"]) == SB.ST_OK, str(s_ok))
	_chk("① 维护 → maintenance", str(s_mt["state"]) == SB.ST_MAINTENANCE, str(s_mt))
	_chk("① 维护时把公告文本取出来了", str(s_mt["notice"]) == "周一维护, 21:00 回来",
		"实得「%s」" % str(s_mt["notice"]))
	_chk("① 连不上 → unreachable", str(s_un["state"]) == SB.ST_UNREACHABLE, str(s_un))
	## ★★② 分母: 三个答案互不相同。少了这条, 一个恒返回同一个值的实现也能绿。
	_chk("② ★★三态互不相同(这才是这一层存在的意义)",
		str(s_ok["state"]) != str(s_mt["state"])
		and str(s_mt["state"]) != str(s_un["state"])
		and str(s_ok["state"]) != str(s_un["state"]),
		"%s / %s / %s" % [str(s_ok["state"]), str(s_mt["state"]), str(s_un["state"])])


# ─────────────────────────────────────────────────────────────
# ③ 不许把"不知道"说成"正常"
# ─────────────────────────────────────────────────────────────
func _t_not_ok_when_unknown() -> void:
	print("── ③ 不许把「不知道」说成「正常」 ──")
	var cases := [
		["传输失败", SB.state_from_response(false, 0, "")],
		["HTTP 500", SB.state_from_response(true, 500, "boom")],
		["HTTP 401(key 不对)", SB.state_from_response(true, 401, '{"message":"No API key found"}')],
		["空数组(那一行不见了)", SB.state_from_response(true, 200, "[]")],
		["不是数组(网关返回了 HTML)", SB.state_from_response(true, 200, "<html>502</html>")],
	]
	var bad := 0
	for c in cases:
		var st: String = str((c[1] as Dictionary)["state"])
		var good: bool = (st == SB.ST_UNREACHABLE)
		if not good:
			bad += 1
		_chk("③ %s → unreachable(不是 ok)" % str(c[0]), good, "实得 %s" % st)
	_chk("③ ★★五种问不到的形状, 一个都没被当成「正常」", bad == 0, "违例 %d/5" % bad)


# ─────────────────────────────────────────────────────────────
# ⑤ 没配后端 ⇒ 什么都不做(连节点都不建)
# ─────────────────────────────────────────────────────────────
func _t_disabled_makes_nothing() -> void:
	print("── ⑤ 没配后端时整层停用 ──")
	## 门禁进程跑在 TURTLE_SUPABASE=" " 下 —— 先把这个前提断言出来, 否则下面是空检查
	_chk("⑤ ★分母: 本进程里这一层确实是停用的", not SB.enabled(),
		"base_url=「%s」" % SB.base_url())
	_chk("⑤ 停用时 service_state() 恒为 off(不暴露内部状态)",
		SB.service_state() == SB.ST_OFF, SB.service_state())
	var before: int = _tree.root.get_child_count()
	SB.fetch_status_async()
	var after: int = _tree.root.get_child_count()
	_chk("⑤ ★停用时连一个节点都不建(发请求的前提是先挂节点)", after == before,
		"树上子节点 %d → %d" % [before, after])


# ─────────────────────────────────────────────────────────────
# ④ ★★走真入口: 主菜单屏幕上真的出现维护公告
# ─────────────────────────────────────────────────────────────
func _find_text(n: Node, needle: String) -> bool:
	if n is Label and str((n as Label).text).contains(needle):
		return true
	for c in n.get_children():
		if _find_text(c, needle):
			return true
	return false


func _n_labels(n: Node) -> int:
	var k := 1 if n is Label else 0
	for c in n.get_children():
		k += _n_labels(c)
	return k


func _t_real_menu() -> void:
	print("── ④ 走真入口: 主菜单真的显示维护公告 ──")
	## ★必须让这一层"看起来是配了的", 否则 service_state() 永远返回 off。
	##   用环境变量开 —— 与产品读配置的是同一条路(`SupabaseNet.base_url`)。
	OS.set_environment("TURTLE_SUPABASE", "https://example.invalid")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "sb_publishable_forgate")
	_chk("④ ★分母: 这一层现在是启用的(否则状态恒为 off, 下面全是空检查)", SB.enabled())

	var NOTICE := "周一维护, 21:00 回来"
	SB._reset_for_test()
	SB.apply_status_response(true, 200,
		'[{"id":1,"maintenance":true,"notice":"%s"}]' % NOTICE)
	_chk("④ ★分母: 状态确实已是维护态", SB.service_state() == SB.ST_MAINTENANCE,
		SB.service_state())

	## ★登录墙(v0.19.440): 本用例测的是**维护公告**不是登录 ——
	##   不给一个已绑定的账号的话, 主菜单一建出来就被墙跳走, 下面全是空检查。
	##   (墙本身由 `verify_login_wall` 守。)
	GameState.account_email = "svc@local"
	var m1 = MENU.instantiate()
	add_child(m1)
	var w := 0
	while w < 600 and not m1.is_node_ready():
		await get_tree().process_frame
		w += 1
	for _i in range(40):
		await get_tree().process_frame
	## ★★量之前把**前提重新钉住**(2026-09-24)。探针实证: 等完那 40 帧之后
	##   `service_state` 已经变成 `unreachable` —— 主菜单自己的 `_sb_poll` 又问了一次,
	##   而门禁里后端没配 ⇒ 问回来就不是维护态了。
	##   满帧率下文字还在屏幕上**只是因为赛程条还没来得及重建**(侥幸, 不是判据成立);
	##   15fps 下真实时间够它重建, 那两行字就被抹掉了。
	## ⇒ 重新喂一次维护态回包 + 显式重建赛程条, 让判据量的是
	##   「维护态 ⇒ 屏幕上有那两行字」本身, 与轮询时机无关。
	SB.apply_status_response(true, 200,
		'[{"id":1,"maintenance":true,"notice":"%s"}]' % NOTICE)
	_chk("④ ★分母: 量之前状态确实还是维护态(前提没被轮询冲掉)",
		SB.service_state() == SB.ST_MAINTENANCE, SB.service_state())
	m1.rebuild_week_strip()
	await get_tree().process_frame
	var n_lab: int = _n_labels(m1)
	_chk("④ ★分母: 主菜单真的建出了 Label(N=0 的话下面是空检查)", n_lab > 0, "%d 个" % n_lab)
	var seen_head: bool = _find_text(m1, "维护中")
	var seen_notice: bool = _find_text(m1, NOTICE)
	_chk("④ ★★屏幕上出现了「维护中」", seen_head)
	_chk("④ ★★屏幕上出现了服务端下发的公告原文", seen_notice, NOTICE)
	m1.queue_free()
	await get_tree().process_frame

	## ── 分母: 非维护态时那两行字【不许】出现, 否则上面"找得到"是恒真式 ──
	SB._reset_for_test()
	SB.apply_status_response(true, 200, '[{"id":1,"maintenance":false,"notice":""}]')
	_chk("④ ★分母: 状态已翻回 ok", SB.service_state() == SB.ST_OK, SB.service_state())
	var m2 = MENU.instantiate()
	add_child(m2)
	w = 0
	while w < 600 and not m2.is_node_ready():
		await get_tree().process_frame
		w += 1
	for _i in range(40):
		await get_tree().process_frame
	_chk("④ ★★非维护态: 屏幕上【没有】「维护中」(证明上面那条不是恒真式)",
		not _find_text(m2, "维护中"))
	_chk("④ ★★非维护态: 也没有那条公告原文", not _find_text(m2, NOTICE))
	m2.queue_free()
	await get_tree().process_frame

	## ★收尾: 把环境还原, 否则同进程后面的用例会看到一个"配了后端"的假象
	OS.set_environment("TURTLE_SUPABASE", " ")
	ProjectSettings.set_setting("turtle/supabase_anon_key", "")
	_chk("④ ★收尾: 环境已还原(这一层回到停用)", not SB.enabled())
