extends Node
## _smoke_beta_server.gd — 内测服真网络冒烟(手动跑, 不进门禁: 要真网络、会在内测服留一个匿名号)
##   2026-10-21 方案书 docs/plans/20261020-内测服.md 验收「客户端切服」的真入口那一半。
## 用法(无头, 临时存档目录, 不设 TURTLE_SUPABASE):
##   TURTLE_SERVER=beta APPDATA=<临时> XDG_DATA_HOME=<临时> godot --headless --path . res://tests/_smoke_beta_server.tscn
## 走真入口: 建主菜单(它自己 ensure_signed_in_async + fetch_status_async), 等令牌与服务状态回来, 打印:
##   连的是哪台 / 拿到令牌没有 / 账号 id / 服务状态 / 服务端假时间偏移 / 主菜单角标。
##   ★正式服地址出现在任何一项里 ⇒ FAIL。

const SE := preload("res://scripts/net/server_env.gd")
const SB := preload("res://scripts/net/supabase.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const MM := preload("res://scripts/scenes/MainMenuScene.gd")
const BETA_REF := "twxkroptuqbfhmlojjgl"
const PROD_REF := "cjefldecsfpnclhfwriw"


func _ready() -> void:
	await get_tree().process_frame
	print("[smoke] is_beta=%s base=%s key=%s…" % [SE.is_beta(), SB.base_url(), SB.anon_key().left(22)])
	var menu: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000:
		await get_tree().create_timer(0.25).timeout
		if SB.access_token() != "" and SB.ask_count() > 0 and SB.service_state() != SB.ST_UNKNOWN:
			break
	await get_tree().create_timer(1.0).timeout
	var badge: Node = menu.find_child(MM.BETA_BADGE_NAME, true, false)
	var gs = get_node_or_null("/root/GameState")
	var acct := str(gs.get("account_id")) if gs != null and "account_id" in gs else "?"
	print("[smoke] token=%s auth_tries=%d account_id=%s" % [SB.access_token() != "", SB.auth_try_count(), acct])
	print("[smoke] service_state=%s asked=%d beta_clock_offset=%d now_utc-real=%d" % [SB.service_state(), SB.ask_count(),
		P2.beta_clock_offset(), P2.now_utc() - int(Time.get_unix_time_from_system())])
	print("[smoke] menu_badge=%s" % (str((badge as Label).text) if badge is Label else "<none>"))
	var ok := SE.is_beta() and SB.base_url().contains(BETA_REF) and not SB.base_url().contains(PROD_REF) \
		and SB.access_token() != "" and SB.service_state() == SB.ST_OK and badge != null
	print("[smoke] %s" % ("ALL PASS — 内测服冒烟" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
