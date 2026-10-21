extends Node
## verify_beta_server_build.gd — 内测服包只连内测服、正式包绝不带内测服(2026-10-21 · 方案书 docs/plans/20261020-内测服.md §4)
##
## 判据(每条配分母):
##   A 导出预设: 有 WinBeta 且带 beta_server; ★其余预设一个都不带(iOS / WinDist / MacDist / Android …); 原文里 beta_server 只出现一次
##   B project.godot: .beta_server 那一组(地址 / key / 直播 / App 名 / 存档目录)都在, 且与正式服那组不同
##   C 切服: 内测服 ⇒ 地址【与】key 一起换成内测服(只换地址不换 key = 401)、不走大陆中转、直播走 /beta/streams;
##     分母: 正式服 ⇒ 正式服地址 / key / 直播 = 原常量(逐字); TURTLE_SERVER=beta|prod 在 debug 进程里认
##   C5 ★内测服少配一项 ⇒ 拿到空(整层停用), 绝不回落到正式服那一项
##   D 时间穿越时的写: 正式包照拦, 内测服包放行(supabase.gd travel_blocks)
##   E 服务端假时间: service_status.clock_offset_sec 解析出来; 内测服叠到 now_utc(), 正式包不叠
##   F 主菜单: 内测服包有「内测服」角标(带服务端时间), 正式包一个节点都不建
## 无头进程没有导出特性标签 ⇒ 用 ServerEnv.beta_override 模拟; 真包另由出包时实跑。

const SE := preload("res://scripts/net/server_env.gd")
const SB := preload("res://scripts/net/supabase.gd")
const NR := preload("res://scripts/net/net_route.gd")
const SW := preload("res://scripts/systems/replay/stream_watch.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")

const PROD_STREAM := "https://stream.turtlearena.xyz/streams"   # 原来写死在 stream_watch.gd 的那个值(逐字)
const BETA_REF := "twxkroptuqbfhmlojjgl"
const PROD_REF := "cjefldecsfpnclhfwriw"

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _env_save(k: String) -> Array:
	return [OS.has_environment(k), OS.get_environment(k)]


func _env_restore(k: String, v: Array) -> void:
	if bool(v[0]):
		OS.set_environment(k, str(v[1]))
	else:
		OS.unset_environment(k)


func _ready() -> void:
	print("=== 内测服包 / 正式包 切服 ===")
	_presets()
	_project()
	_switch()
	_travel()
	_clock()
	await _menu()
	SE.beta_override = -1
	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 内测服包只连内测服 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)


# ── A 导出预设 ─────────────────────────────────────────
func _presets() -> void:
	var cfg := ConfigFile.new()
	_ok("A 分母: 读得到 export_presets.cfg", cfg.load("res://export_presets.cfg") == OK)
	var beta := ""
	var paths := {}
	var leaked: Array = []
	var n := 0
	for sec in cfg.get_sections():
		if not cfg.has_section_key(sec, "name"):
			continue
		n += 1
		var nm := str(cfg.get_value(sec, "name", ""))
		var cf := str(cfg.get_value(sec, "custom_features", ""))
		paths[nm] = str(cfg.get_value(sec, "export_path", ""))
		if nm == "WinBeta":
			beta = sec
		elif cf.contains(SE.FEATURE):
			leaked.append(nm)
	_ok("A 分母: 预设 ≥ 7 个且含正式包四个(iOS / WinDist / MacDist / Android)",
		n >= 7 and paths.has("iOS") and paths.has("WinDist") and paths.has("MacDist") and paths.has("Android"), "n=%d %s" % [n, paths.keys()])
	_ok("A 有 WinBeta 预设且带 beta_server", beta != "" and str(cfg.get_value(beta, "custom_features", "")).contains(SE.FEATURE))
	_ok("A ★其余预设一个都不带 beta_server", leaked.is_empty(), str(leaked))
	var raw := FileAccess.get_file_as_string("res://export_presets.cfg")
	_ok("A ★原文里 beta_server 只出现一次(没有藏在别的字段里)", raw.count(SE.FEATURE) == 1, "count=%d" % raw.count(SE.FEATURE))
	_ok("A WinBeta 导出路径不与 WinDist / WinDevOffline 撞",
		paths.get("WinBeta", "") != "" and paths.get("WinBeta") != paths.get("WinDist") and paths.get("WinBeta") != paths.get("WinDevOffline"))


# ── B project.godot ───────────────────────────────────
func _project() -> void:
	var pg := ConfigFile.new()
	_ok("B 分母: 读得到 project.godot", pg.load("res://project.godot") == OK)
	var url := str(pg.get_value("turtle", "supabase_url", ""))
	var burl := str(pg.get_value("turtle", "supabase_url" + SE.SUFFIX, ""))
	var key := str(pg.get_value("turtle", "supabase_anon_key", ""))
	var bkey := str(pg.get_value("turtle", "supabase_anon_key" + SE.SUFFIX, ""))
	_ok("B 内测服地址 = turtle-beta、不是正式服", burl.contains(BETA_REF) and not burl.contains(PROD_REF) and url.contains(PROD_REF), burl)
	_ok("B 内测服 key 在、且不是正式服那把", bkey.begins_with("sb_publishable_") and bkey != key)
	var bs := str(pg.get_value("turtle", "stream_base" + SE.SUFFIX, ""))
	_ok("B 内测服直播 = /beta/streams", bs.ends_with("/beta/streams") and bs != PROD_STREAM, bs)
	var nm := str(pg.get_value("application", "config/name", ""))
	var bnm := str(pg.get_value("application", "config/name" + SE.SUFFIX, ""))
	var bdir := str(pg.get_value("application", "config/custom_user_dir_name" + SE.SUFFIX, ""))
	var odir := str(pg.get_value("application", "config/custom_user_dir_name.offline_dev", ""))
	_ok("B App 名带「内测服」且与正式包不同", bnm.contains(SE.BADGE_TEXT) and bnm != nm, bnm)
	_ok("B 另用存档目录(与正式包 / 离线测试包都不同)",
		bool(pg.get_value("application", "config/use_custom_user_dir" + SE.SUFFIX, false)) and bdir != "" and bdir != nm and bdir != odir, bdir)


# ── C 切服 ────────────────────────────────────────────
func _switch() -> void:
	var e_url := _env_save(SB.ENV_URL)
	var e_relay := _env_save(NR.ENV_RELAY)
	var e_srv := _env_save(SE.ENV)
	var e_stream := _env_save(SW.ENV_BASE)
	OS.unset_environment(SB.ENV_URL)
	OS.unset_environment(NR.ENV_RELAY)
	OS.unset_environment(SE.ENV)
	OS.unset_environment(SW.ENV_BASE)
	var prod_url := str(ProjectSettings.get_setting("turtle/supabase_url", ""))
	var prod_key := str(ProjectSettings.get_setting("turtle/supabase_anon_key", ""))

	SE.beta_override = 0
	var rs0 := NR.routes()
	_ok("C 分母: 正式服 ⇒ 直连 = 正式服地址", rs0.size() >= 1 and rs0[0] == prod_url.rstrip("/"), str(rs0))
	_ok("C 分母: 正式服 ⇒ key = 正式服那把", SB.anon_key() == prod_key and prod_key != "")
	_ok("C 分母: 正式服 ⇒ 有大陆中转那一条(证明下面「内测服没有」不是空检查)", rs0.size() == 2, str(rs0))
	_ok("C ★正式服直播地址默认值 = 原来写死的常量(逐字)", NR.stream_direct() == PROD_STREAM and SW.BASE == PROD_STREAM, NR.stream_direct())

	SE.beta_override = 1
	var rs1 := NR.routes()
	_ok("C ★内测服 ⇒ 地址换成 turtle-beta", SB.base_url().contains(BETA_REF) and rs1.size() >= 1 and rs1[0].contains(BETA_REF), SB.base_url())
	_ok("C ★内测服 ⇒ key 同时换(只换地址不换 key = 401)", SB.anon_key() != prod_key and SB.anon_key() == str(ProjectSettings.get_setting("turtle/supabase_anon_key" + SE.SUFFIX, "")),
		SB.anon_key().left(20))
	_ok("C ★内测服 ⇒ 不走大陆中转(中转只转发到正式服)", rs1.size() == 1, str(rs1))
	_ok("C 内测服 ⇒ 层是开着的(地址与 key 都有)", SB.enabled())
	_ok("C 内测服 ⇒ 直播走 /beta/streams", SW.base_url().ends_with("/beta/streams") and SW.base_url() != PROD_STREAM, SW.base_url())

	## C5 少配一项 ⇒ 空, 不回落正式服
	var bkey0 = ProjectSettings.get_setting("turtle/supabase_anon_key" + SE.SUFFIX, "")
	ProjectSettings.set_setting("turtle/supabase_anon_key" + SE.SUFFIX, null)
	_ok("C5 ★内测服 key 缺 ⇒ 拿到空(不回落正式服 key), 层停用", SB.anon_key() == "" and not SB.enabled(), SB.anon_key().left(20))
	ProjectSettings.set_setting("turtle/supabase_anon_key" + SE.SUFFIX, bkey0)
	_ok("C5 分母: 还原后内测服 key 回来了", SB.anon_key() == str(bkey0) and SB.enabled())

	## 环境变量(debug 进程)
	SE.beta_override = -1
	OS.set_environment(SE.ENV, "beta")
	_ok("C TURTLE_SERVER=beta ⇒ 内测服(debug 进程)", SE.is_beta() == OS.is_debug_build() and SB.anon_key() != prod_key, "debug=%s" % OS.is_debug_build())
	OS.set_environment(SE.ENV, "prod")
	_ok("C TURTLE_SERVER=prod ⇒ 正式服", not SE.is_beta() and SB.anon_key() == prod_key)
	OS.unset_environment(SE.ENV)
	_ok("C 分母: 什么都不设(无头进程没有特性标签)⇒ 正式服", not SE.is_beta())

	_env_restore(SB.ENV_URL, e_url)
	_env_restore(NR.ENV_RELAY, e_relay)
	_env_restore(SE.ENV, e_srv)
	_env_restore(SW.ENV_BASE, e_stream)
	SE.beta_override = -1


# ── D 时间穿越时的写 ───────────────────────────────────
func _travel() -> void:
	var e_ship := _env_save("SHIP")
	OS.unset_environment("SHIP")
	var k_off: int = P2.travel_offset_sec
	var k_read: bool = P2._travel_env_read
	var k_ovr: int = P2.now_override_ts
	P2.now_override_ts = 0
	P2._travel_env_read = true
	var url := "https://x.invalid/rest/v1/rpc/referee_gauntlet_start"
	_ok("D 分母: 这是一条写请求", SB.is_write_request("POST", url))
	var ok_travel := P2.travel_to_weekday(6, 12, 0)
	_ok("D 分母: 穿越生效", ok_travel and P2.travel_active(), "offset=%d" % P2.travel_offset_sec)
	SE.beta_override = 0
	_ok("D ★正式包: 穿越中写请求照拦", SB.travel_blocks("POST", url))
	_ok("D 正式包角标带「不联网」", P2.travel_badge_text().ends_with(P2.TRAVEL_OFFLINE_SUFFIX), P2.travel_badge_text())
	SE.beta_override = 1
	_ok("D ★内测服包: 穿越中写请求放行", not SB.travel_blocks("POST", url))
	_ok("D 内测服包角标不挂「不联网」", P2.travel_badge_text() != "" and not P2.travel_badge_text().ends_with(P2.TRAVEL_OFFLINE_SUFFIX), P2.travel_badge_text())
	SE.beta_override = -1
	P2.travel_offset_sec = k_off
	P2._travel_env_read = k_read
	P2.now_override_ts = k_ovr
	_env_restore("SHIP", e_ship)


# ── E 服务端假时间 ─────────────────────────────────────
func _clock() -> void:
	var k_off: int = P2.travel_offset_sec
	var k_ovr: int = P2.now_override_ts
	var k_beta: int = P2.beta_clock_offset_sec
	P2.travel_offset_sec = 0
	P2.now_override_ts = 0
	var body := JSON.stringify([{"id": 1, "maintenance": false, "notice": "", "min_client_version": "0.0.0", "clock_offset_sec": 342690}])
	var r := SB.state_from_response(true, 200, body)
	_ok("E 解析出 clock_offset_sec", int(r.get("clock", -1)) == 342690, str(r))
	var r0 := SB.state_from_response(true, 200, JSON.stringify([{"id": 1, "maintenance": false}]))
	_ok("E 分母: 列缺失(老服务端)⇒ 0", int(r0.get("clock", -1)) == 0, str(r0))
	SB.apply_status_response(true, 200, body)
	var base := int(Time.get_unix_time_from_system()) + P2.server_offset()
	SE.beta_override = 1
	var d1 := P2.now_utc() - base
	_ok("E ★内测服包: now_utc() 叠上服务端偏移", absi(d1 - 342690) <= 2, "差 %d" % d1)
	_ok("E 内测服角标带服务端时间", P2.beta_badge_text().begins_with(SE.BADGE_TEXT) and P2.beta_badge_text().contains("服务端时间"), P2.beta_badge_text())
	SE.beta_override = 0
	var d0 := P2.now_utc() - (int(Time.get_unix_time_from_system()) + P2.server_offset())
	_ok("E ★正式包: 服务端回了偏移也不叠", absi(d0) <= 2, "差 %d" % d0)
	_ok("E 正式包: 没有内测服角标", P2.beta_badge_text() == "")
	SE.beta_override = -1
	P2.beta_clock_offset_sec = k_beta
	P2.travel_offset_sec = k_off
	P2.now_override_ts = k_ovr


# ── F 主菜单角标 ───────────────────────────────────────
func _menu_badge(beta: bool) -> String:
	SE.beta_override = 1 if beta else 0
	var menu: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	if menu is Control:
		(menu as Control).set_anchors_preset(Control.PRESET_TOP_LEFT)
		(menu as Control).size = Vector2(1280, 720)
	for _i in range(30):
		await get_tree().process_frame
	var b: Node = menu.find_child(MM.BETA_BADGE_NAME, true, false)
	var t: String = str((b as Label).text) if b is Label else "<none>"
	var ver: Node = null
	for l in menu.find_children("*", "Label", true, false):
		if str((l as Label).text) == "v" + str(ProjectSettings.get_setting("application/config/version", "")):
			ver = l
	if beta:
		_ok("F 分母: 主菜单建出来了(版本号在)", ver != null)
	menu.queue_free()
	await get_tree().process_frame
	SE.beta_override = -1
	return t


func _menu() -> void:
	await get_tree().process_frame   # _ready 里根节点还在建子节点, 直接 add_child 会失败
	var tb: String = await _menu_badge(true)
	_ok("F ★内测服包: 主菜单有「内测服」角标", tb.begins_with(SE.BADGE_TEXT), tb)
	var tp: String = await _menu_badge(false)
	_ok("F ★正式包: 一个角标节点都不建", tp == "<none>", tp)
