extends Node
## verify_online_only.gd — 游戏必须联网(2026-11-01 · 方案书 docs/plans/20261101b-游戏必须联网.md)
##
## 用户 2026-11-01:「我们不应该有什么这种本地排名，我们这个游戏就一定要是要联网的，就是不可能说断网还可以匹配，
##   断网可以打，这是肯定不行的，不能有什么这种本地。」
##
## 模拟正式包(`OnlineGate.release_override = true`)+ 后端打开(环境变量 + key)+ 传输一律回「连不上」
##   (`SupabaseNet._transport_for_test`, 不碰网络), 逐个入口真按下去; 换屏走 `SceneNav.nav_for_test` 记下来(不真换)。
## 判据:
##   A 判据本身: 正式包要求联网、开发缝关上; 调试构建(门禁 / 开发机)不要求; 源码判据 = OS.is_debug_build()
##     + 离线测试包, 不认 SB.enabled() / SHIP / DEVTOOLS / 环境变量(不然 `TURTLE_SUPABASE=" "` 在正式包里就能开出离线局)
##   I 连得上: 第一次先问(不同步放行), 问到 OK ⇒ resume 恰好一次、框自己关; 20 秒内再点同步放行、不再问;
##     I2 主菜单开着很久后断网(状态停在旧 OK 上): 再点要先问, 问不到不放行
##   H 维护中: 框说维护, 不放行
##   C 去匹配屏(选龟「出战」/ 周六排队回匹配屏都走 SceneNav): 没换屏、弹框; 重试仍断网 ⇒ 仍拦;
##     网络回来按重试 ⇒ 接着去匹配屏(恰好一次); 「返回」只关框; 分母: 别的屏不拦
##   B 主菜单「开始战斗」: 没进选龟、没置 dual_active, 弹框说对战; 分母: 开发缝下同一入口照常去选龟
##   D 排行榜: 不画本机排名(source=offline / 0 行 / 没有「本地记录」角标), 弹框说排行榜, 「返回」回主菜单;
##     正式包 + 后端没配同样; 分母: 开发缝下同一份池子画得出本机那一路(≥2 行 + 角标)
##   E 商店: 买装备 / 买经验 / 换一批 一个币都没动、弹框说购买; 分母: 开发缝下同一笔真成交
##   F 教程: 「开始教程」没进教程(没进沙盒、没换屏), 选择框还在、框盖在上面
##   G 切磋「再来一局」: 没换屏, 弹框说切磋
##   S 静态: 本机排名一类代码只许出现在开发缝后面 / 挑对手只在匹配屏(过了 SceneNav 那一道)/ 不许绕过 SceneNav 去匹配屏;
##     ★扫描器先拿旧写法证明会红(内嵌旧代码片段; 本机取得到提交 c25f88c3 时再拿那一版的排行榜全文比一次)
## 反向验证(改坏 → 红 → 逐字节还原): 去掉 SceneNav 那一道 ⇒ C 红; 去掉主菜单那一道 ⇒ B 红; `_fallback` 不看开发缝 ⇒ D/S 红;
##   商店 `_online_or_wait` 恒真 ⇒ E 红; 教程那一道 ⇒ F 红; 切磋那一道 ⇒ G 红; required() 改认 SB.enabled() ⇒ A 红;
##   连上了不调 resume ⇒ I / C 红; ready_now() 不看新不新鲜(只认问到过 OK)⇒ I2 红。

const SB := preload("res://scripts/net/supabase.gd")
const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const SHOP := preload("res://scenes/Shop.tscn")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MENU := "res://scenes/MainMenu.tscn"
const LB_SCENE := "res://scenes/Leaderboard.tscn"
const SEED_PATH := "res://tests/_setup_lb_rows.gd"
const MATCH := "res://scenes/Matchmaking.tscn"
const TEAM := "res://scenes/TeamSelect.tscn"
const BATTLE := "res://scenes/RealtimeBattle3D.tscn"
const THU_TS := 1793275200          # 2026-10-29 周四 12:00 UTC(积分赛日)
const OLD_COMMIT := "c25f88c3"      # 改动前(排行榜断网退回本机排名的最后一版)

## 本机排名一类的字(只许出现在开发缝那一路的角标常量里)。
const LOCAL_RANK_WORDS := ["本地记录", "本机记录", "本地排名", "本机排名", "本地排行", "本机排行", "离线排名", "离线排行", "非实时排名"]

var _n := 0
var _fail := 0
var _net := "down"                  # down / up / maint
var _reqs: Array = []
var _navs: Array = []
var _had_env := false
var _env0 := ""
var _key0 = ""
var _acc0 := ""
var _tok0 := ""
var _exp0 := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _frames(k: int) -> void:
	for _i in range(k):
		await get_tree().process_frame


func _transport(m, u, _h, _b, cb) -> void:
	_reqs.append("%s %s" % [str(m), str(u)])
	if _net == "down":
		cb.call({"ok": false, "code": 0, "body": ""})
		return
	if str(u).find("/rest/v1/service_status") >= 0:
		var row := {"maintenance": _net == "maint", "notice": "维护公告(门禁)" if _net == "maint" else "",
			"min_client_version": ""}
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([row])})
		return
	cb.call({"ok": false, "code": 0, "body": ""})   # 其余请求一律失败(这里测的不是它们)


func _status_asks() -> int:
	var k := 0
	for r in _reqs:
		if str(r).find("/rest/v1/service_status") >= 0:
			k += 1
	return k


## 每一段开头: 断网、清掉「看到过 OK」、清掉服务状态与换屏记录。
func _fresh(net: String = "down") -> void:
	_net = net
	OnlineGate._reset_for_test()
	SB._reset_for_test()
	_navs.clear()


func _wall_text(w: OnlineWall) -> String:
	return "%s | %s" % [w._title.text, w._body.text] if w != null else "<无框>"


func _close(w: OnlineWall) -> void:
	if w != null and is_instance_valid(w):
		w._back.pressed.emit()
	await _frames(2)


func _ready() -> void:
	print("=== 游戏必须联网(正式包断网不给本地替代) ===")
	_setup()
	_t_static()
	_t_predicate()
	await _t_gate_up()
	await _t_maint()
	await _t_nav()
	await _t_menu()
	await _t_leaderboard()
	await _t_shop()
	await _t_tutorial()
	await _t_spar()
	_cleanup()
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 游戏必须联网 (%d/%d)" % [_n, _n])
	else:
		print("FAILED — 游戏必须联网 (%d 条红 / %d)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)


func _setup() -> void:
	GameState.test_mode = true
	_had_env = OS.has_environment(SB.ENV_URL)
	_env0 = OS.get_environment(SB.ENV_URL)
	_key0 = ProjectSettings.get_setting(SB.SETTING_KEY, "")
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "gate-anon-key")
	SB._transport_for_test = _transport
	_acc0 = str(GameState.account_id)
	_tok0 = str(SB._token)
	_exp0 = int(SB._expires_at)
	GameState.account_id = "11111111-2222-3333-4444-555555555555"
	SB._token = "gate-token"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 7200   # 令牌新鲜 ⇒ 不发登录请求(这里测的不是登录)
	OnlineGate.release_override = true
	SceneNav.nav_for_test = func(p: String) -> void: _navs.append(p)
	_fresh()


func _cleanup() -> void:
	OnlineGate.release_override = false
	OnlineGate._reset_for_test()
	SceneNav.nav_for_test = Callable()
	SB._transport_for_test = Callable()
	SB._reset_for_test()
	SB._token = _tok0
	SB._expires_at = _exp0
	GameState.account_id = _acc0
	if _had_env:
		OS.set_environment(SB.ENV_URL, _env0)
	else:
		OS.unset_environment(SB.ENV_URL)
	ProjectSettings.set_setting(SB.SETTING_KEY, _key0)
	Spar.active = false
	Spar._again = false


# ───────────────────────────── A 判据本身 ─────────────────────────────
func _t_predicate() -> void:
	print("── A 判据本身 ──")
	OnlineGate.release_override = false
	_ok("A 开发缝: 调试构建里不要求联网(门禁 / 开发机靠它跑)", OS.is_debug_build() and not OnlineGate.required()
		and OnlineGate.dev_offline_ok(), "debug=%s" % OS.is_debug_build())
	OnlineGate.release_override = true
	_ok("A 模拟正式包: 要求联网、开发缝关上", OnlineGate.required() and not OnlineGate.dev_offline_ok())
	var src := FileAccess.get_file_as_string("res://scripts/net/online_gate.gd")
	var body := _func_body(src, "required")
	_ok("A 分母: 读到 required() 的函数体", body.length() > 20, "len=%d" % body.length())
	_ok("A ★源码判据 = OS.is_debug_build() + 离线测试包 + 门禁缝", body.find("OS.is_debug_build()") >= 0
		and body.find("offline_dev()") >= 0 and body.find("release_override") >= 0, body)
	var bad := []
	for w in ["enabled()", "SHIP", "DEVTOOLS", "get_environment", "has_environment", "service_state"]:
		if body.find(w) >= 0:
			bad.append(w)
	_ok("A ★不认后端开关 / 环境变量(正式包里 TURTLE_SUPABASE=\" \" 也开不出离线局)", bad.is_empty(), str(bad))
	_ok("A 门禁缝默认关(玩家路径一字不动)", src.find("static var release_override: bool = false") >= 0)
	var sn := FileAccess.get_file_as_string("res://scripts/util/scene_nav.gd")
	_ok("A SceneNav 的门禁缝默认关", sn.find("static var nav_for_test: Callable = Callable()") >= 0)


# ───────────────────────────── I 连得上 ⇒ 放行 ─────────────────────────────
func _t_gate_up() -> void:
	print("── I 连得上 ⇒ 问一次就放行 ──")
	_fresh("up")
	var hits := [0]
	var r := func() -> void: hits[0] += 1
	var a0 := _status_asks()
	var passed := OnlineGate.check(self, OnlineGate.WHAT_MATCH, r)
	_ok("I 第一次: 没亲眼看到过 OK ⇒ 先去问(不同步放行)", not passed and hits[0] == 0)
	await _frames(6)
	_ok("I ★问到连得上 ⇒ resume 恰好一次、框自己关掉", hits[0] == 1 and OnlineWall.find(self) == null,
		"hits=%d wall=%s" % [hits[0], OnlineWall.find(self)])
	_ok("I 分母: 真的问了服务状态", _status_asks() - a0 >= 1, "asks=%d" % (_status_asks() - a0))
	var a1 := _status_asks()
	var p2 := OnlineGate.check(self, OnlineGate.WHAT_MATCH, r)
	_ok("I 刚看到过 OK ⇒ 同步放行、不再问", p2 and _status_asks() == a1 and hits[0] == 1)
	## I2 主菜单开着很久之后断网: 网络层的服务状态还停在上一次的 OK 上(没人再问过), 但那是 FRESH_MS 之前看到的
	##   ⇒ 要先问, 问不到不放行(只看「问到过 OK」就等于没拦)。
	_net = "down"
	OnlineGate._ok_ms = Time.get_ticks_msec() - OnlineGate.FRESH_MS - 1
	_ok("I2 分母: 网络层状态还停在旧的 OK 上", OnlineGate.verdict() == "ok", OnlineGate.verdict())
	var p3 := OnlineGate.check(self, OnlineGate.WHAT_MATCH, r)
	await _frames(6)
	var w3 := OnlineWall.find(self)
	_ok("I2 ★旧的 OK 不算数: 先去问, 问不到不放行、弹框", not p3 and hits[0] == 1 and w3 != null and w3.state == "fail",
		"passed=%s hits=%d %s" % [p3, hits[0], _wall_text(w3)])
	await _close(w3)


# ───────────────────────────── H 维护中 ─────────────────────────────
func _t_maint() -> void:
	print("── H 维护中 ──")
	_fresh("maint")
	var hits := [0]
	OnlineGate.check(self, OnlineGate.WHAT_MATCH, func() -> void: hits[0] += 1)
	await _frames(6)
	var w := OnlineWall.find(self)
	_ok("H ★维护中: 不放行, 框说维护(带公告)", w != null and w.state == "maintenance" and hits[0] == 0
		and w._title.text == OnlineWall.TXT_MAINT_TITLE and w._body.text.find("维护公告") >= 0, _wall_text(w))
	await _close(w)


# ───────────────────────────── C 去匹配屏 ─────────────────────────────
func _t_nav() -> void:
	print("── C 去匹配屏(SceneNav 那一道) ──")
	_fresh("down")
	var host := get_tree().current_scene
	SceneNav.go(get_tree(), MATCH)
	await _frames(6)
	var w := OnlineWall.find(host)
	_ok("C ★断网去匹配屏: 没换屏", _navs.is_empty(), str(_navs))
	_ok("C 弹「无法连接服务器」, 正文说对战", w != null and w.state == "fail" and w._title.text == OnlineWall.TXT_TITLE
		and w._body.text == OnlineWall.TXT_BODY % OnlineGate.WHAT_MATCH and w._box.visible, _wall_text(w))
	if w == null:
		return
	_ok("C 框吃点击 + 两颗卡片钮(重试 / 返回)", w._dim.mouse_filter == Control.MOUSE_FILTER_STOP and w._retry.visible
		and w._back.visible and w._retry.has_theme_stylebox_override("normal") and w._retry.text == OnlineWall.TXT_RETRY)
	var p0 := w.probe_count
	w._retry.pressed.emit()
	await _frames(6)
	_ok("C 重试仍断网: 仍不换屏、框还在", _navs.is_empty() and OnlineWall.find(host) == w and w.probe_count == p0 + 1
		and w.state == "fail", "navs=%s probes=%d" % [str(_navs), w.probe_count])
	_net = "up"
	w._retry.pressed.emit()
	await _frames(6)
	_ok("C ★网络回来按重试: 接着去匹配屏(恰好一次)、框关掉", _navs == [MATCH] and OnlineWall.find(host) == null, str(_navs))
	_fresh("down")
	SceneNav.go(get_tree(), MATCH)
	await _frames(4)
	await _close(OnlineWall.find(host))
	_ok("C 「返回」: 只关框、不换屏", OnlineWall.find(host) == null and _navs.is_empty(), str(_navs))
	SceneNav.go(get_tree(), "res://scenes/Codex.tscn")
	_ok("C 分母: 去别的屏不拦(拦的只是匹配屏)", _navs == ["res://scenes/Codex.tscn"], str(_navs))


# ───────────────────────────── B 主菜单「开始战斗」 ─────────────────────────────
func _t_menu() -> void:
	print("── B 主菜单「开始战斗」 ──")
	_fresh("down")
	GameState.hearts = int(P2.HEARTS_MAX)
	GameState.season_total_battles = 0
	GameState.dual_active = false
	var menu = load(MENU).instantiate()
	add_child(menu)
	await _frames(4)
	menu.clock_override_ts = THU_TS
	_ok("B 分母: 这一刻别的闸都不拦(积分赛日 · 满命 · 没打满)", str(menu._battle_block_msg(THU_TS)) == "",
		str(menu._battle_block_msg(THU_TS)))
	_navs.clear()
	menu._start_battle_flow()
	await _frames(6)
	var w := OnlineWall.find(menu)
	_ok("B ★断网点「开始战斗」: 没进选龟(没换屏、没置 dual_active)", not _navs.has(TEAM) and not GameState.dual_active,
		"navs=%s dual=%s" % [str(_navs), GameState.dual_active])
	_ok("B 主菜单上弹「无法连接服务器」, 正文说对战", w != null and w.state == "fail"
		and w._body.text == OnlineWall.TXT_BODY % OnlineGate.WHAT_MATCH, _wall_text(w))
	await _close(w)
	OnlineGate.release_override = false
	menu._start_battle_flow()
	_ok("B 分母: 开发缝下同一个入口照常去选龟(拦住它的是联网这一道)", _navs.has(TEAM), str(_navs))
	OnlineGate.release_override = true
	GameState.dual_active = false
	remove_child(menu)
	menu.queue_free()
	await _frames(2)


# ───────────────────────────── D 排行榜 ─────────────────────────────
func _lb_open() -> Node:
	var lb = load(LB_SCENE).instantiate()
	add_child(lb)
	await _frames(12)
	return lb


func _lb_close(lb: Node) -> void:
	if lb != null and is_instance_valid(lb):
		remove_child(lb)
		lb.queue_free()
	await _frames(2)


func _t_leaderboard() -> void:
	print("── D 排行榜 ──")
	var seed = load(SEED_PATH)
	_ok("D 分母: 种子脚本在(本机池里灌 14 个别人)", seed != null and seed.has_method("run"))
	if seed == null:
		return
	seed.run()
	_fresh("down")
	var lb = await _lb_open()
	var w := OnlineWall.find(lb)
	_ok("D ★断网: 不画本机排名(source=offline、0 行、没有「本地记录」角标)", str(lb.source) == LB.SRC_OFFLINE
		and (lb.shown_rows as Array).is_empty() and lb.find_child("LbSourceMark", true, false) == null,
		"source=%s rows=%d" % [str(lb.source), (lb.shown_rows as Array).size()])
	_ok("D 排行榜上弹「无法连接服务器」, 正文说排行榜", w != null and w.state == "fail"
		and w._body.text == OnlineWall.TXT_BODY % OnlineGate.WHAT_RANK, _wall_text(w))
	_navs.clear()
	await _close(w)
	_ok("D 「返回」回主菜单", _navs == [MENU], str(_navs))
	await _lb_close(lb)
	## 正式包 + 后端没配(环境变量置空): 一个请求都发不出 ⇒ 同样不画本机
	OS.set_environment(SB.ENV_URL, " ")
	_fresh("down")
	lb = await _lb_open()
	_ok("D ★正式包 + 后端没配: 同样不画本机排名", str(lb.source) == LB.SRC_OFFLINE and (lb.shown_rows as Array).is_empty()
		and OnlineWall.find(lb) != null, "source=%s" % str(lb.source))
	await _lb_close(lb)
	## 分母: 开发缝(调试构建 + 后端没配)下同一份池子画得出本机那一路 —— 上面两条不是「池子本来就空」
	OnlineGate.release_override = false
	lb = await _lb_open()
	_ok("D 分母: 开发缝下同一份池子画得出本机那一路(≥2 行 + 「本地记录」角标)", str(lb.source) == LB.SRC_LOCAL
		and (lb.shown_rows as Array).size() >= 2 and lb.find_child("LbSourceMark", true, false) != null,
		"source=%s rows=%d" % [str(lb.source), (lb.shown_rows as Array).size()])
	OnlineGate.release_override = true
	await _lb_close(lb)
	OS.set_environment(SB.ENV_URL, "http://gate.local")
	seed.clear()


# ───────────────────────────── E 商店 ─────────────────────────────
func _t_shop() -> void:
	print("── E 商店 ──")
	_fresh("down")
	GameState.meta_deepsea_coins = 999
	GameState.season_level = 5
	GameState.season_xp = 0
	GameState.season_total_battles = 3
	GameState.meta_shop_locked = false
	GameState.meta_shop_offer = []
	GameState.meta_shop_battles = -1
	var sc = SHOP.instantiate()
	add_child(sc)
	await _frames(6)
	var idx := -1
	for i in range((sc._offer as Array).size()):
		if sc._offer[i] != null:
			idx = i
			break
	_ok("E 分母: 货架上有货、币够", idx >= 0 and int(GameState.meta_deepsea_coins) == 999, "idx=%d" % idx)
	if idx < 0:
		return
	var ids0 := _offer_ids(sc)
	sc._on_buy(idx)
	await _frames(4)
	var w := OnlineWall.find(sc)
	_ok("E ★断网买装备: 一个币没动、货还在", int(GameState.meta_deepsea_coins) == 999 and sc._offer[idx] != null,
		"coins=%d" % int(GameState.meta_deepsea_coins))
	_ok("E 弹框, 正文说购买", w != null and w._body.text == OnlineWall.TXT_BODY % OnlineGate.WHAT_BUY, _wall_text(w))
	await _close(w)
	var lv0 := int(GameState.season_level)
	var xp0 := int(GameState.season_xp)
	sc._on_buy_xp()
	await _frames(4)
	_ok("E ★断网买经验: 币、等级、经验都没动", int(GameState.meta_deepsea_coins) == 999 and int(GameState.season_level) == lv0
		and int(GameState.season_xp) == xp0 and OnlineWall.find(sc) != null)
	await _close(OnlineWall.find(sc))
	sc._on_refresh()
	await _frames(4)
	_ok("E ★断网换一批: 币没动、货没换", int(GameState.meta_deepsea_coins) == 999 and _offer_ids(sc) == ids0
		and OnlineWall.find(sc) != null)
	await _close(OnlineWall.find(sc))
	OnlineGate.release_override = false
	sc._on_buy(idx)
	_ok("E 分母: 开发缝下同一笔真成交(币少了)", int(GameState.meta_deepsea_coins) < 999,
		"coins=%d" % int(GameState.meta_deepsea_coins))
	OnlineGate.release_override = true
	remove_child(sc)
	sc.queue_free()
	await _frames(2)


func _offer_ids(sc: Node) -> Array:
	var out: Array = []
	for e in sc._offer:
		out.append(str((e as Dictionary).get("id", "")) if e is Dictionary else "")
	return out


# ───────────────────────────── F 教程 ─────────────────────────────
func _t_tutorial() -> void:
	print("── F 新手教程 ──")
	_fresh("down")
	var host := Control.new()
	host.name = "TutHost"
	add_child(host)
	var ov := TutorialChoice.open(host, false)
	var st := ov.find_child("StartTutorial", true, false) as Button if ov != null else null
	_ok("F 分母: 选择框和「开始教程」在", st != null and not bool(GameState.tutorial_active))
	if st == null:
		return
	st.pressed.emit()
	await _frames(6)
	var w := OnlineWall.find(host)
	_ok("F ★断网按「开始教程」: 没进教程(没进沙盒、没换屏)", not bool(GameState.tutorial_active) and not _navs.has(TEAM),
		"tutorial_active=%s navs=%s" % [GameState.tutorial_active, str(_navs)])
	_ok("F 选择框还在, 上面盖「无法连接服务器」(正文说新手教程)", is_instance_valid(ov) and not ov.is_queued_for_deletion()
		and w != null and w._body.text == OnlineWall.TXT_BODY % OnlineGate.WHAT_TUTORIAL, _wall_text(w))
	await _close(w)
	_ok("F 「返回」之后选择框仍在(可以再按)", is_instance_valid(ov) and not ov.is_queued_for_deletion())
	remove_child(host)
	host.queue_free()
	await _frames(2)


# ───────────────────────────── G 切磋「再来一局」 ─────────────────────────────
func _t_spar() -> void:
	print("── G 切磋「再来一局」 ──")
	_fresh("down")
	Spar.active = true
	Spar._again = false
	Spar.again(get_tree())
	await _frames(6)
	var w := OnlineWall.find(get_tree().current_scene)
	_ok("G ★断网「再来一局」: 没换屏", not _navs.has(BATTLE) and not Spar._again, str(_navs))
	_ok("G 弹框, 正文说切磋", w != null and w._body.text == OnlineWall.TXT_BODY % OnlineGate.WHAT_SPAR, _wall_text(w))
	await _close(w)
	OnlineGate.release_override = false
	Spar.again(get_tree())
	_ok("G 分母: 开发缝下同一个入口照常重开", _navs.has(BATTLE), str(_navs))
	OnlineGate.release_override = true
	Spar.active = false
	Spar._again = false


# ───────────────────────────── S 静态 ─────────────────────────────
## 旧写法(改动前 LeaderboardScene._fetch_now 原样): 服务端榜问不到 ⇒ 当场画本机排名, 不看是不是正式包。
const OLD_SHAPE := """func _fetch_now() -> void:
	if not is_inside_tree():
		return
	if not _request_page(0, true):
		_render(_local_rows(), SRC_LOCAL, -1)
"""


func _t_static() -> void:
	print("── S 静态 ──")
	var files := _gd_files("res://scripts") + _gd_files("res://autoload")
	_ok("S 分母: 扫到的源文件", files.size() > 150, "n=%d" % files.size())
	## S1 本机排名只许从开发缝放行: 每个 `_local_rows(` 调用所在的函数里, 调用之前得有 `OnlineGate.dev_offline_ok()`
	var v1: Array = []
	var calls := 0
	for f in files:
		var r := _scan_local_rows(FileAccess.get_file_as_string(f), f)
		v1.append_array(r[0])
		calls += int(r[1])
	_ok("S1 分母: 本机排名的调用点找到了", calls >= 1, "calls=%d" % calls)
	_ok("S1 ★本机排名只在开发缝后面(OnlineGate.dev_offline_ok)", v1.is_empty(), str(v1))
	var old_r := _scan_local_rows(OLD_SHAPE, "旧写法")
	_ok("S1 ★扫描器认得旧写法(内嵌的改动前片段会红)", (old_r[0] as Array).size() == 1, str(old_r[0]))
	var old_txt := _git_show(OLD_COMMIT, "scripts/scenes/LeaderboardScene.gd")
	if old_txt != "":
		var og := _scan_local_rows(old_txt, "c25f88c3")
		_ok("S1 ★拿改动前那一版排行榜全文扫: 4 处本机排名全红", (og[0] as Array).size() == 4, str(og[0]))
	else:
		print("  [PEND] 本机取不到 %s(浅克隆): 只用内嵌旧片段证明扫描器会红" % OLD_COMMIT)
	## S2 用本机池排名次的原语只许在 `_local_rows` 里调
	var v2: Array = []
	for f in files:
		if f.ends_with("/backend.gd"):
			continue
		for hit in _calls_in(FileAccess.get_file_as_string(f), "Backend.leaderboard("):
			if not (f.ends_with("/LeaderboardScene.gd") and str(hit) == "_local_rows"):
				v2.append("%s::%s" % [f.get_file(), hit])
	_ok("S2 ★用本机池排名次(Backend.leaderboard)只许在排行榜的开发缝那一路", v2.is_empty(), str(v2))
	## S3 本机排名一类的字只许出现在开发缝的角标常量里
	var v3: Array = []
	for f in files:
		var lines := FileAccess.get_file_as_string(f).split("\n")
		for i in range(lines.size()):
			var code := _code_of(lines[i])
			for lit in _literals(code):
				for wd in LOCAL_RANK_WORDS:
					if str(lit).find(wd) >= 0 and not (f.ends_with("/LeaderboardScene.gd") and code.begins_with("const FALLBACK_MARK")):
						v3.append("%s:%d %s" % [f.get_file(), i + 1, wd])
	_ok("S3 ★「本地记录 / 本地排名 …」只在开发缝的角标里", v3.is_empty(), str(v3))
	## S4 挑对手只在匹配屏(和 SIM 驱动)里 —— 去匹配屏要过 SceneNav 那一道
	var v4: Array = []
	for f in files:
		if f.ends_with("/backend.gd"):
			continue
		var t := FileAccess.get_file_as_string(f)
		for nm in ["find_opponent(", "find_gauntlet_opponent("]:
			if _calls_in(t, nm).size() > 0 and not (f.ends_with("/MatchmakingScene.gd") or f.ends_with("/sim_driver.gd")):
				v4.append("%s → %s" % [f.get_file(), nm])
	_ok("S4 ★本机挑对手只在匹配屏后面(过了联网那一道)", v4.is_empty(), str(v4))
	## S5 不许绕过 SceneNav 直接切到匹配屏
	var v5: Array = []
	for f in files:
		var lines5 := FileAccess.get_file_as_string(f).split("\n")
		for i in range(lines5.size()):
			var c5 := _code_of(lines5[i])
			if c5.find("change_scene_to_file") >= 0 and (c5.find("Matchmaking") >= 0 or c5.find("S_MATCH") >= 0
					or c5.find("MATCHMAKING") >= 0):
				v5.append("%s:%d" % [f.get_file(), i + 1])
	_ok("S5 ★没有绕过 SceneNav 直接切到匹配屏的", v5.is_empty(), str(v5))
	## S6 SceneNav 那一道在真换屏之前
	var sn := FileAccess.get_file_as_string("res://scripts/util/scene_nav.gd")
	var go_body := _func_body(sn, "go")
	var gi := go_body.find("OnlineGate.check(")
	_ok("S6 ★SceneNav.go: 先过联网那一道, 再换屏(门禁缝也在它后面)", gi >= 0 and gi < go_body.find("change_scene_to_file")
		and gi < go_body.find("nav_for_test.call") and sn.find("\"res://scenes/Matchmaking.tscn\"") >= 0, go_body)


## 一份源码里 `_local_rows(` 的调用点: 返回 [违规列表, 调用数]。违规 = 所在函数里调用之前没有 `OnlineGate.dev_offline_ok()`。
func _scan_local_rows(text: String, fname: String) -> Array:
	var bad: Array = []
	var n := 0
	var cur_fn := ""
	var fn_text := ""
	var lines := text.split("\n")
	for i in range(lines.size()):
		var ln := str(lines[i]).replace("\r", "")
		var hdr := _func_name(ln)
		if hdr != "":
			cur_fn = hdr
			fn_text = ""
		var code := _code_of(ln)
		if code.find("_local_rows(") >= 0 and hdr != "_local_rows":
			n += 1
			if fn_text.find("OnlineGate.dev_offline_ok()") < 0:
				bad.append("%s:%d(%s)" % [fname.get_file(), i + 1, cur_fn])
		fn_text += code + "\n"
	return [bad, n]


## 一份源码里调用了 needle 的函数名列表(每处一条)。
func _calls_in(text: String, needle: String) -> Array:
	var out: Array = []
	var cur_fn := ""
	for ln in text.split("\n"):
		var l := str(ln).replace("\r", "")
		var hdr := _func_name(l)
		if hdr != "":
			cur_fn = hdr
		var code := _code_of(l)
		var k := code.find(needle)
		if k >= 0 and code.find("func " + needle) < 0:
			## 只认真调用: 前一个字符不是标识符(不把 `my_find_opponent(` 算进来)
			if k == 0 or not _ident_char(code[k - 1]) or needle.begins_with("Backend."):
				out.append(cur_fn)
	return out


func _ident_char(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_"


## 顶格 `func x(` / `static func x(` ⇒ "x"; 否则 ""。
func _func_name(line: String) -> String:
	var l := line
	if l.begins_with("static func "):
		l = l.substr(7)
	if not l.begins_with("func "):
		return ""
	var p := l.find("(")
	return l.substr(5, p - 5).strip_edges() if p > 5 else ""


## 函数体(从 `func name(` 那一行到下一个顶格 func / static func / const / var 之前)。
func _func_body(text: String, name: String) -> String:
	var lines := text.split("\n")
	var out := ""
	var on := false
	for ln in lines:
		var l := str(ln).replace("\r", "")
		if on and (l.begins_with("func ") or l.begins_with("static func ") or l.begins_with("const ")
				or l.begins_with("static var ") or l.begins_with("var ")):
			break
		if _func_name(l) == name:
			on = true
		if on:
			out += _code_of(l) + "\n"
	return out


## 去掉行尾注释(引号外的 `#`)。整行注释 ⇒ ""。
func _code_of(line: String) -> String:
	var inq := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if inq != "":
			if c == "\\":
				i += 2
				continue
			if c == inq:
				inq = ""
		elif c == "\"" or c == "'":
			inq = c
		elif c == "#":
			return line.substr(0, i).strip_edges(false, true)
		i += 1
	return line.strip_edges(false, true)


## 一行代码里的字符串字面量(双引号)。
func _literals(code: String) -> Array:
	var out: Array = []
	var i := 0
	while i < code.length():
		if code[i] == "\"":
			var j := i + 1
			var s := ""
			while j < code.length() and code[j] != "\"":
				if code[j] == "\\":
					j += 1
				else:
					s += code[j]
				j += 1
			out.append(s)
			i = j + 1
		else:
			i += 1
	return out


func _gd_files(root: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(root)
	if d == null:
		return out
	d.list_dir_begin()
	var nm := d.get_next()
	while nm != "":
		var p := root.path_join(nm)
		if d.current_is_dir():
			if not nm.begins_with("."):
				out.append_array(_gd_files(p))
		elif nm.ends_with(".gd"):
			out.append(p)
		nm = d.get_next()
	d.list_dir_end()
	return out


func _git_show(sha: String, f: String) -> String:
	var out: Array = []
	var rc := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "show", "%s:%s" % [sha, f]], out, true)
	if rc != 0 or out.is_empty():
		return ""
	return str(out[0])
