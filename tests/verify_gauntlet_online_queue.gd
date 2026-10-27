extends Node
## verify_gauntlet_online_queue.gd — 周六闯关改在线排队(客户端)。方案书 docs/plans/20261027b-闯关赛在线瑞士轮.md §4.4 / §6。
##
## 用户 10-27「我按下了匹配…一定是要我这边匹配之后，我这个阵容处于锁定状态。…当我等到了另外一个对手也锁定了他的这个阵容…才互相匹配」
##   「只动周六，别把之前的积分赛给动了」「周六周日我们讲究是在线啊」(陪练号是真客户端在线, 与真人同一套排队)。
## 全程走产品自己的入口: 真匹配屏 → `referee_run.gd` → 注入传输(假服务器, 不连网); W 段走真 HTTP(本机假服务器 tests/_route_http.gd)。
##
## 段落(每条断言带分母):
##   P  纯函数: 三条排队 RPC 的请求体 / 回包解析(waiting / paired / 取消时已配上 / 拒收原因 / 404 / 断网)
##   A  ★join → waiting(等待界面: 格子战绩 + 已等待秒数 + card_button「取消匹配」; 不翻 VS 卡; 落排队单)→ 每 2 秒心跳 →
##      第 4 次心跳 paired(a)⇒ 翻 VS 卡、换任务单 → 裁判算完 ⇒ 进现有观看流程(裁判局、名字照旧)、账按服务器
##   B  ★同样一份但我是 b: 胜负 / 战绩按服务端给的(B 视角, 客户端不翻)、播录像时左边写对手名右边写我、战绩页那一行带 side
##   C  等待中取消: 「取消匹配」⇒ 正在退出(按钮灰、不重复发)⇒ 回主菜单、排队单销掉、没有对局; 「←」同样是出队不是直接走
##   D  取消时已配上 ⇒ 照配上处理(再心跳一次拿对手卡 → VS 卡 → 任务单), 不回主菜单
##   E  心跳回 expired / none ⇒「已退出排队」回主菜单、排队单销掉; 收盘(reason closed)/ 配上的那一局算失败(job_failed)各给对应的话
##   F  join 回 update_required / finished / stale ⇒ 屏上原因、不排队不心跳; stale 以账本为准;
##      404(服务端没有排队)⇒ 与断网同一句, 不退回旧入口 referee_gauntlet_start(服务端线 10-27: 周六客户端别再调它)
##   G  杀进程 / 断网后主菜单补查排队单: 配上了 ⇒ 按任务号补记(B 视角)/ 过期 ⇒ 销单 / 还在队里 ⇒ 出队 / 上周的 ⇒ 销 / 问不到 ⇒ 留着
##   W  真 HTTP: 进队与心跳真的发到服务器(服务器那边数), 取消真的发出去
##   S  陪练号(sim_driver)走排队: 卡死线 = 排队上限 + 等裁判上限 + 余量; 真驱动整条流程: waiting → paired → 看完 → 商店 → 再排 →
##      等待超时 ⇒ 按「取消匹配」⇒ 收工(queue_timeout), 全程不报 STUCK
##   R  ★积分赛一行不动: 积分赛走的函数与 84d2d853(改动前)逐字节相同(行尾归一); 周六专用的那几个只从闯关日分支可达
##   Q  服务端迁移在仓库里时: 三条 RPC 的形参与本机请求体对账(还没落盘 ⇒ 打 PEND, 不算通过)
##   V  ★看的人口径(2026-10-27 主会话「B 看到自己被写成『对方』, 必须改」): 我是 B 时对局顶栏 / 本战场胜负 / 各路战果 / 龟蛋生命 /
##      结算屏「我方」「敌方」两页 / 各路胜负牌 / 我方 MVP / 战报两列 / 单位面板「友军」都是 B 自己; A 照旧(A 段同一组断言);
##      战绩页回放我在右边那一行 ⇒ 按存下的 side 给名字; 开关只在「正在播 + 入口给了 side=b」时生效(假战场三种状态 + 静态: 谁能给 side=b)
##   S 段另量陪练号周末参数: SIM_SHOP_MIN/MAX_SEC(两局之间逛店)/ SIM_SKIP_WATCH(账记完不看直播直接去商店)/
##      SIM_EXPECT_CELL(本机 / 服务端格子对不上 ⇒ cell_mismatch 收工)
## 反向验证(改坏 → 红 → 逐字节还原): 去掉进队后的心跳 ⇒ A / E / W 红; B 方不按 side 摆名字 ⇒ B 红; B 方客户端再翻一次胜负 ⇒ B 红;
##   viewer_side 恒 "a" / 结算屏两页不按看的人 ⇒ V 红; 不逛店 / 不跳过观看 / 不查格子 ⇒ S 红。
## GATE_ONLY=A,B,S(逗号分隔段名)⇒ 只跑这几段(反向验证省时间用; 门禁本身不设)。

const SB := preload("res://scripts/net/supabase.gd")
const NR := preload("res://scripts/net/net_route.gd")
const RN := preload("res://scripts/net/referee_net.gd")
const RW := preload("res://scripts/systems/replay/referee_watch.gd")
const RU := preload("res://scripts/systems/replay/replay_uploader.gd")
const RF := preload("res://scripts/systems/replay/replay_fetcher.gd")
const LS := preload("res://scripts/systems/replay/live_spectate.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const MMK := preload("res://scripts/scenes/MatchmakingScene.gd")
const BE := preload("res://scripts/net/backend.gd")
const BP := preload("res://scripts/referee/bot_pool.gd")
const Board := preload("res://scripts/systems/replay/gauntlet_board.gd")
const Drv := preload("res://scripts/systems/sim/sim_driver.gd")
const H := preload("res://tests/_route_http.gd")
const MMK_SCENE := "res://scenes/Matchmaking.tscn"
const MENU_SCENE := "res://scenes/MainMenu.tscn"
const ME := "11111111-2222-4333-8444-555555555555"
const MID := "5b2c2a3b-4d5e-4f60-8a7b-9c0d1e2f3a4b"
const MID2 := "6c3d3b4c-5e6f-4071-9b8c-0d1e2f3a4b5c"
const JOIN := "gauntlet_queue_join"
const POLL := "gauntlet_queue_poll"
const CANCEL := "gauntlet_queue_cancel"
const START := "referee_gauntlet_start"
const STATUS := "referee_job_status"
const SQL := "res://server/supabase/migrations/20261027_gauntlet_online_queue.sql"

## ── R 段基线: 84d2d853(改动前)里积分赛走的函数。生成法: tests 头注 R 段 / 回报里的 gen 脚本 ──
##   单元 = 第 0 列 `func` / `static func` / `class` 那一行起、到下一行顶格非空为止(行尾归一成 LF、去掉末尾空行);
##   digest = sha256(按名字排序的 「名字\n单元sha256\n」 串起来); views = 去掉「if … PHASE_GAUNTLET / _gauntlet_now …:」那一段之后的单元 sha256。
##   ★将来有意改积分赛的代码: 重新生成这张表并在提交里写明理由(这张表只证明「这一次」没动积分赛)。
const RANKED_BASE := "84d2d853"
const RANKED := {
	"scripts/scenes/MatchmakingScene.gd": {
		"digest": "27e540b58fdfe58747342238f5e0ae6625e68510c07051d9b0364e9b062b2771",
		"views": {},
		"sat_only": ["_server_pick", "_on_referee_changed", "_leave_later"],
		"units": [
			"_bg", "_bold_font", "_build_cancel_btn", "_build_card", "_build_searching", "_build_vs", "_center", "_display_id",
			"_fade_to_black", "_font", "_note_recent", "_on_cancel", "_opponent_from_ghost", "_pick_gauntlet_local",
			"_player_profile", "_radar_ping", "_ready", "_ref_label", "_shockwave", "card_id_text", "class _RingFx",
		],
	},
	"scripts/systems/sim/sim_driver.gd": {
		"digest": "82aa6b708927bca6f00a30f9ab2dd04ce88f9f4b578dd4ae4c45a08a86ecab5e",
		"views": {"stuck_limit": "249c0a8120123e0922fcd539dd090b34a6c7f3d0b40a590947a134823e5be79a", "_do_match": "ba0505964df1b434b7f0ec774d2371d9cb95b6869140166520e8a5b475f9676b", "_do_menu": "da531d0881e93941022065cb369a014ec36d604d103fcd294dd15b768b6e6b21", "_do_shop": "366a597e0ab76a1d45f40d2532021528328e34c2555a7c6f64b58e4d06a805f6"},
		"sat_only": [],
		"units": [
			"_account_only", "_alive", "_all_gear", "_arrange_lineup", "_back_to_menu", "_bench_gear_by_value", "_bench_gear_n",
			"_best_bench_gear", "_buy_xp", "_core_types", "_cost_of", "_do_battle", "_do_codex", "_do_first_launch",
			"_do_inventory", "_do_team", "_drain_guides", "_dup_budget", "_eff_val", "_ensure_en_nick", "_equip_target",
			"_equipped_list", "_ev", "_finish", "_gear_side", "_gear_val", "_guide_text", "_is_core", "_junk_bench_idx",
			"_lineup_record", "_n_star3", "_offer_score", "_open_singles", "_owned_gear_n", "_press_tutorial_choice",
			"_process", "_quit_when_done", "_ready", "_refresh_floor", "_reserve", "_rolling_down", "_run", "_shot", "_since",
			"_since_start", "_sleep", "_star_hist", "_stats", "_strategy", "_syn_gain", "_target_level", "_tour", "_tour_extra",
			"_tour_wanted", "_unit_fits", "_unit_side", "_wait_scene", "_wants_one_piece", "_worst_equipped",
			"_worst_owned_val", "attach", "enabled",
		],
	},
	"scripts/net/backend.gd": {
		"digest": "354eb64780f65dcf9f1995d989c585468fa99b59e3b4fa95394eb419fd82756e",
		"views": {},
		"sat_only": [],
		"units": [
			"_bot_season_record", "_bot_trainer_skill", "_drop_stale_schema", "_ensure_seeded", "_is_self_ghost", "_load_seed",
			"_migrate_brackets_to_battles", "_seed_level", "_seed_record", "_seed_season_id", "_shuffle", "_tally",
			"_tally_exact", "build_ghost_snapshot", "drop_week_snapshots", "ensure_finals_entry",
			"ensure_gauntlet_entry_snapshot", "fake_person_tag", "finals_push_snapshot", "find_gauntlet_opponent",
			"find_opponent", "gauntlet_bot_battles", "gauntlet_pool_find", "ghost_lanes_broken", "ghost_level",
			"ghost_owner_tag", "is_sparring", "lead_of", "leaderboard", "load_pool", "make_bot", "make_match_rng", "my_tag",
			"owner_tag_of_id", "person_key", "player_display_name", "player_ghost_id", "pool_add", "pool_find_battles",
			"pool_reach", "prefetch_gauntlet_pool", "profile_tag", "reach_of", "report_finals_entry", "report_finals_if_any",
			"report_finals_result", "retry_finals_report", "save_pool", "seed_as_human", "seed_person_of", "self_prefix",
			"self_season_prefix", "upload_gauntlet_ghost", "upload_ghost", "wipe_week_snapshots",
		],
	},
	"scripts/scenes/TeamSelectScene.gd": {
		"digest": "6a892ce285733787d44ac20400a697495bdb24d7e7b4e0886819e526f9ee60e8",
		"views": {},
		"sat_only": [],
		"units": [
			"_add_text_shadow", "_apply_pet_idle_texture", "_build_grid_region", "_build_synergy_region", "_build_ui",
			"_card_drag", "_close_detail_popup", "_content_band", "_content_scale", "_dark_panel", "_demo_popup",
			"_ensure_letterbox", "_ensure_menu_bg", "_fit_background", "_flash_status", "_grow_to_touch", "_input",
			"_is_special_mark", "_load_team", "_lockout_toast", "_make_drag_preview", "_make_rarity_badge", "_mark_label",
			"_on_back", "_on_clear_all", "_on_drop_pet", "_on_pick_pet", "_on_resize", "_on_restore_last", "_on_start",
			"_place", "_place_clamped", "_play_entrance", "_raise_edge_btns", "_read_last_lineup", "_ready", "_rect",
			"_refresh_after_team", "_refresh_all", "_refresh_confirm", "_refresh_synergy_chips", "_rl_line", "_rl_val", "_s",
			"_save_team", "_season_roster_ready", "_set_detail_pet", "_sf", "_show_detail_popup", "_show_detail_popup_from",
			"_skill_energy", "_sp", "_space_top_pair", "_stage_scale", "_stage_to_screen", "_style_rarity_btn",
			"_sync_special_slots", "_tut_next_pet", "_tut_notify", "_tut_notify_team_filled", "_tut_on", "_tut_union_rect",
			"_tutorial_anchor", "_unhandled_key_input", "_vp", "_write_last_lineup", "tut_text_vars",
		],
	},
}

var _fail := 0
var _n := 0
var _pend := 0
var _gs
var _hits := {}
var _poll_t: Array = []           # 每次心跳到达假服务器的本机毫秒
var _join_body: Dictionary = {}
var _join_hdr: Array = []
var _sc: Dictionary = {}          # 本段假服务器的剧本(见 _reset_sc)
var _sc_polls := 0                # 本段收到的心跳次数
var _paired_now := false
var _held: Array = []             # 「取消」回话先扣着(量「正在退出」那一刻)
var _job := 300
var _done := false
var _srv_won := false
var _srv_gw := 0
var _srv_gl := 0
var _srv_b: Dictionary = {}       # 对手快照(机器人池那一份; 真人 / 陪练号同形)
var _rec_b64 := ""
var _rec_mid := MID
var _rec_a_b64 := ""         # A 段那一局的录像(S 段驱动再用一次)
var _srv_auto := false        # true ⇒ 假服务器的账本 = 本机战绩 + 这一局赢(S 段驱动一个进程打好几局)


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("   " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "   ", detail)


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _hit(name: String) -> int:
	return int(_hits.get(name, 0))


## 墙钟上限等条件(CLAUDE.md §3.5: 等网络 / 计时器用墙钟)。
func _wait(pred: Callable, ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_gs = get_node_or_null("/root/GameState")
	_ok("★分母: 拿到 GameState", _gs != null)
	if _gs == null:
		_finish()
		return
	OS.set_environment("TURTLE_SEED", "")
	OS.set_environment("SIM_QUIT_WHEN_DONE", "")
	P2C.now_override_ts = P2C.week_anchor_utc(int(Time.get_unix_time_from_system())) + 5 * 86400 + 12 * 3600
	_setup_gs()
	_net_fake()
	_ok("分母: 时间钉在周六、闯关赛上线、开关开", P2C.phase_at_utc(P2C.now_utc()) == P2C.PHASE_GAUNTLET
		and P2C.phase_mode_live(P2C.PHASE_GAUNTLET) and RW.gauntlet_on())
	if _seg("R"):
		_t_r()
	if _seg("Q"):
		_t_q()
	if _seg("P"):
		_t_p()
	if _seg("V"):
		_t_v()
	if _seg("A"):
		await _t_a()
	if _seg("B"):
		await _t_b()
	if _seg("C"):
		await _t_c()
	if _seg("D"):
		await _t_d()
	if _seg("E"):
		await _t_e()
	if _seg("F"):
		await _t_f()
	if _seg("G"):
		await _t_g()
	if _seg("W"):
		await _t_w()
	if _seg("S"):
		await _t_s()
	_cleanup()
	_finish()


## GATE_ONLY 没设 ⇒ 每段都跑。
func _seg(name: String) -> bool:
	var o := OS.get_environment("GATE_ONLY").strip_edges()
	return o == "" or Array(o.split(",")).has(name)


func _setup_gs() -> void:
	_gs.test_mode = true
	_gs.account_id = ME
	_gs.tutorial_active = false
	_gs.onboarded = true
	_gs.reset_dual_lane()
	_gs.season_leaders = ["basic", "stone", "bamboo"]
	_gs.left_team.assign(_gs.season_leaders)
	_gs.dual_lineup = {
		"top": [{"kind": "leader", "slot": 0, "id": "basic", "equips": []},
			{"kind": "minion", "role": "front", "equips": []}],
		"bottom": [{"kind": "leader", "slot": 1, "id": "stone", "equips": []},
			{"kind": "leader", "slot": 2, "id": "bamboo", "equips": []},
			{"kind": "minion", "role": "back", "equips": []}],
	}
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	var pe := {}
	var k := 0
	for pid in _gs.season_leaders:
		var l: Array = []
		for _j in range(2):
			l.append({"id": str(shop[k % shop.size()]), "star": 2})
			k += 1
		pe[pid] = l
	_gs.persistent_equipped = pe
	_gs.week_anchor_ts = P2C.week_anchor_utc(P2C.now_utc())
	_gs.promoted = true
	_gs.hearts = int(P2C.HEARTS_MAX)
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 0
	_gs.battles_total = 9
	_gs.referee_pending = {}
	_gs.referee_flags = {RN.K_FINALS: false, RN.K_GAUNTLET: true}
	_gs.dual_active = true
	var anchor: int = P2C.week_anchor_utc(P2C.now_utc())
	_gs.close_card_ranked_wk = anchor          # 主菜单收盘卡本周记成已弹(S 段走真主菜单, 量的不是它)
	_gs.close_card_gauntlet_wk = anchor


func _net_fake() -> void:
	OS.set_environment(SB.ENV_URL, "http://referee.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "referee-anon-key")
	SB._transport_for_test = _transport
	SB._reset_auth_for_test()
	SB._token = "tok"
	SB._expires_at = int(Time.get_unix_time_from_system()) + 3600


func _cleanup() -> void:
	var cs := get_tree().current_scene
	if cs != null and is_instance_valid(cs) and cs != self:
		cs.queue_free()
	P2C.now_override_ts = 0
	OS.set_environment(SB.ENV_URL, " ")
	ProjectSettings.set_setting(SB.SETTING_KEY, "")
	SB._transport_for_test = Callable()
	SB._token = ""
	MMK._may_leave_for_test = Callable()
	LS.pending = {}
	RW.notice = ""
	RW.skip_play = false
	for k in ["SIM_SLOT", "SIM_ROUNDS", "SIM_TOUR", "SIM_QUEUE_GIVEUP_SEC", "SIM_SHOP_MIN_SEC", "SIM_SHOP_MAX_SEC", "SIM_EXPECT_CELL", "SIM_SKIP_WATCH"]:
		OS.set_environment(k, "")
	_gs.referee_flags = {}
	_gs.referee_pending = {}


## 新的一段: 假服务器换剧本。
##   join: waiting(默认)/ paired / 404 / 拒收原因; pair_after: 前几次心跳回 waiting(-1 = 一直等);
##   poll_end: 到点不配而回它(expired / none); side: a / b; cancel: cancelled / paired; no_mid: 配上的回包不带录像号;
##   hold_cancel: 取消的回话先扣着; poll_offline: 心跳一律问不到。
func _reset_sc(sc: Dictionary) -> void:
	_sc = sc
	_sc_polls = 0
	_paired_now = false
	_poll_t.clear()
	_held.clear()
	_join_body = {}
	_done = false
	_job += 1
	_srv_b = BP.one(maxi(int(_gs.season_total_battles), int(_gs.gauntlet_wins) + int(_gs.gauntlet_losses)),
		int(_gs.gauntlet_wins), int(_gs.gauntlet_losses), _job % 6)


func _opp_card() -> Dictionary:
	return {"profile": _srv_b["profile"], "leaders": _srv_b["leaders"]}


func _paired_body() -> String:
	var d := {"ok": true, "status": "paired", "job_id": _job, "side": str(_sc.get("side", "a")), "opp": _opp_card(),
		"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "waited_sec": _sc_polls * 2}
	if not bool(_sc.get("no_mid", false)):
		d["match_id"] = _rec_mid
	return JSON.stringify(d)


func _waiting_body() -> String:
	var sc_cell: Array = _sc.get("srv_cell", [int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)])   # srv_cell: 服务端账本上的格子与本机不同
	return JSON.stringify({"ok": true, "status": "waiting", "gw": int(sc_cell[0]), "gl": int(sc_cell[1]),
		"waited_sec": _sc_polls * 2})


func _transport(m, u, h, b, cb) -> void:
	var url := str(u)
	if url.find("/auth/v1/") >= 0:
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({
			"access_token": "tok", "refresh_token": "r2", "expires_in": 3600,
			"user": {"id": ME, "is_anonymous": true}})})
		return
	var i := url.find("/rest/v1/rpc/")
	var rpc := url.substr(i + 13).split("?")[0] if i >= 0 else ""
	if rpc != "":
		_hits[rpc] = _hit(rpc) + 1
	match rpc:
		"referee_flags":
			cb.call({"ok": true, "code": 200, "body": "{\"finals_on\":false,\"gauntlet_on\":true}"})
			return
		JOIN:
			var j = JSON.parse_string(str(b))
			_join_body = j if j is Dictionary else {}
			_join_hdr = Array(h) if (h is PackedStringArray or h is Array) else []
			var jm := str(_sc.get("join", "waiting"))
			if jm == "404":
				cb.call({"ok": true, "code": 404, "body": "{\"code\":\"PGRST202\"}"})
			elif jm == "paired":
				_paired_now = true
				cb.call({"ok": true, "code": 200, "body": _paired_body()})
			elif jm == "waiting":
				cb.call({"ok": true, "code": 200, "body": _waiting_body()})
			else:
				var gw := 2 if jm == "stale" else int(_gs.gauntlet_wins)
				var gl := 1 if jm == "stale" else int(_gs.gauntlet_losses)
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": jm, "gw": gw, "gl": gl})})
			return
		POLL:
			_poll_t.append(Time.get_ticks_msec())
			_sc_polls += 1
			if bool(_sc.get("poll_offline", false)):
				cb.call({"ok": false, "code": 0, "body": ""})
				return
			var pa := int(_sc.get("pair_after", -1))
			if not _paired_now and pa >= 0 and _sc_polls > pa:
				var pe := str(_sc.get("poll_end", ""))
				if pe != "":
					var eb := {"ok": true, "status": pe}
					if str(_sc.get("poll_reason", "")) != "":
						eb["reason"] = str(_sc["poll_reason"])
					cb.call({"ok": true, "code": 200, "body": JSON.stringify(eb)})
					return
				_paired_now = true
			cb.call({"ok": true, "code": 200, "body": _paired_body() if _paired_now else _waiting_body()})
			return
		CANCEL:
			var reply: Dictionary
			if str(_sc.get("cancel", "cancelled")) == "paired":
				_paired_now = true
				reply = {"ok": true, "code": 200, "body": JSON.stringify({"ok": false, "reason": "paired", "job_id": _job,
					"side": str(_sc.get("side", "a"))})}
			else:
				reply = {"ok": true, "code": 200, "body": "{\"ok\":true,\"status\":\"cancelled\"}"}
			if bool(_sc.get("hold_cancel", false)):
				_held.append([cb, reply])
				return
			cb.call(reply)
			return
		START:
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "job_id": _job, "match_id": _rec_mid,
				"opp": _opp_card(), "gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses)})})
			return
		STATUS:
			if not _done:
				cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "pending", "match_id": _rec_mid})})
				return
			var dgw := int(_gs.gauntlet_wins) + 1 if _srv_auto else _srv_gw
			var dgl := int(_gs.gauntlet_losses) if _srv_auto else _srv_gl
			cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "status": "done", "match_id": _rec_mid,
				"won": true if _srv_auto else _srv_won, "score": 0, "gw": dgw, "gl": dgl, "coins": 0, "error": null})})
			return
	if str(m) == "GET" and url.find("/rest/v1/matches?") >= 0 and url.find("match_id=eq." + _rec_mid) >= 0:
		_hits["matches_get"] = _hit("matches_get") + 1
		cb.call({"ok": true, "code": 200, "body": JSON.stringify([{"match_id": _rec_mid, "replay": _rec_b64}])})
		return
	cb.call({"ok": true, "code": 200, "body": "[]"})


# ───────────────────────────── 场景小工具 ─────────────────────────────
func _open_mmk() -> Node:
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	_gs.dual_opponent = {}
	var m: Node = (load(MMK_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(m)
	get_tree().current_scene = m
	return m


func _close(m) -> void:
	if m != null and is_instance_valid(m):
		(m as Node).queue_free()
	await _frames(3)


func _run_of(m):
	if m == null or not is_instance_valid(m):
		return null
	var r = (m as Node).get("_ref_run")
	return r if r != null and is_instance_valid(r) else null


func _state(m) -> String:
	var r = _run_of(m)
	return str(r.state) if r != null else ""


func _status_text(m) -> String:
	if m == null or not is_instance_valid(m):
		return ""
	var l := (m as Node).find_child("RefereeStatus", true, false) as Label
	return l.text if l != null else ""


func _label(m, nm: String) -> Label:
	if m == null or not is_instance_valid(m):
		return null
	var l := (m as Node).find_child(nm, true, false) as Label
	return l if l != null and not l.is_queued_for_deletion() else null


func _cancel_btn(m) -> Button:
	if m == null or not is_instance_valid(m):
		return null
	var b := (m as Node).find_child(MMK.QUEUE_CANCEL, true, false) as Button
	return b if b != null and not b.is_queued_for_deletion() else null


func _has_label(root, text: String) -> bool:
	if root == null or not is_instance_valid(root):
		return false
	for c in (root as Node).find_children("*", "Label", true, false):
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion() and str((c as Label).text) == text:
			return true
	return false


func _is_battle(n) -> bool:
	return n != null and is_instance_valid(n) and n.get_script() == RB


func _snap() -> Dictionary:
	return {"gw": int(_gs.gauntlet_wins), "gl": int(_gs.gauntlet_losses), "coins": int(_gs.meta_deepsea_coins),
		"bt": int(_gs.battles_total), "mh": (_gs.match_history as Array).size(),
		"pending": (_gs.referee_pending as Dictionary).duplicate()}


func _play_to_end(b: Node) -> void:
	b.set_process(false)
	var guard := 0
	while guard < 4000 and not b._replay.finished and b._replay.diverged_at < 0:
		b._process(0.13)
		guard += 1
		if guard % 6 == 0:
			await get_tree().process_frame


func _settle_title(b: Node) -> String:
	var pr: Node = b.find_child("PageResult", true, false)
	if pr == null:
		return ""
	for c in pr.find_children("*", "Label", true, false):
		if str((c as Label).text) == "胜利" or str((c as Label).text) == "失败":
			return (c as Label).text
	return ""


## 一个节点下面所有 Label 的字(去掉首尾空白)。
func _texts(n) -> Array:
	var out: Array = []
	if n == null or not is_instance_valid(n):
		return out
	for c in (n as Node).find_children("*", "Label", true, false):
		out.append(str((c as Label).text).strip_edges())
	return out


## 战绩页上录像号是 id 的那颗「观看」。
func _watch_btn_of(rs: Node, id: String) -> Button:
	if rs == null or not is_instance_valid(rs):
		return null
	for c in rs.find_children("*", "Button", true, false):
		if str((c as Button).get_meta("replay_id", "")) == id and not (c as Button).disabled:
			return c as Button
	return null


## ★看的人口径(对局放完、结算屏在场时量)。me = 录像里「我方」那一侧(我是 a ⇒ left / 我是 b ⇒ right)。
func _viewer_checks(b: Node, tag: String, me: String, my_name: String, foe_name: String) -> void:
	var foe := "left" if me == "right" else "right"
	_ok("%s ★看的人那一侧 = %s(viewer_side %s)" % [tag, me, "b" if me == "right" else "a"],
		ReplayRecorder.viewer_side(b) == ("b" if me == "right" else "a") and ReplayRecorder.my_side(b) == me and ReplayRecorder.foe_side(b) == foe)
	## ① 对局顶栏: 我这一侧写我的名字
	var tb = b._hud._topbar
	var nl := str(tb.name_l.text).strip_edges() if tb != null and tb.name_l != null else "?"
	var nr := str(tb.name_r.text).strip_edges() if tb != null and tb.name_r != null else "?"
	_ok("%s ★对局顶栏: 我这一侧(%s)写我「%s」、对面写对手「%s」" % [tag, me, my_name, foe_name],
		(nl if me == "left" else nr) == my_name and (nr if me == "left" else nl) == foe_name, "左 %s / 右 %s" % [nl, nr])
	## ② 一路结束的幕布: 让左方输掉这一路 ⇒ 右方赢
	b._dl_pending_loser = "left"
	b._dl_sys._dl_build_present_overlay("lane_settle")
	var root: Node = b._dl_present_root
	var l_res := root.find_child("LaneSettleResult", true, false) as Label if root != null else null
	var l_rec := root.find_child("LaneSettleRecord", true, false) as Label if root != null else null
	var l_egg := root.find_child("LaneSettleEggs", true, false) as Label if root != null else null
	var want_res := "本战场胜利" if me == "right" else "本战场失败"
	_ok("%s ★本战场结果(左方输了这一路)⇒「%s」" % [tag, want_res], l_res != null and l_res.text == want_res, l_res.text if l_res != null else "无")
	var lrs: Dictionary = GameState.lane_results if GameState.lane_results is Dictionary else {}
	var mw := 0
	var fw := 0
	for k in lrs.keys():
		if str(lrs[k]) == me:
			mw += 1
		else:
			fw += 1
	if not lrs.has(str(GameState.current_lane)):
		if me == "right":
			mw += 1
		else:
			fw += 1
	var want_rec := "各路战果    我方 %d : %d 对方" % [mw, fw]
	_ok("%s ★各路战果: 「我方」数的是我这一侧赢的路(分母 %d 路)" % [tag, mw + fw], l_rec != null and l_rec.text == want_rec and mw + fw >= 1,
		"%s / 想要 %s" % [l_rec.text if l_rec != null else "无", want_rec])
	var eh: Dictionary = GameState.egg_hp if GameState.egg_hp is Dictionary else {}
	var want_egg := "龟蛋生命  我方 %d  ·  对方 %d" % [int(eh.get(me, 0.0)), int(eh.get(foe, 0.0))]
	_ok("%s ★龟蛋生命: 「我方」是我这一侧的蛋(两颗蛋不同血: %s)" % [tag, str(int(eh.get(me, 0.0)) != int(eh.get(foe, 0.0)))],
		l_egg != null and l_egg.text == want_egg, "%s / 想要 %s" % [l_egg.text if l_egg != null else "无", want_egg])
	b._dl_sys._dl_clear_present_overlay()
	## ②b 对阵幕布: 我的名字用「我方」的绿、对手用红(名字左右照实)
	b._dl_sys._dl_build_present_overlay("preview")
	var col_me := Color()
	var col_foe := Color()
	for c in (b._dl_present_root as Node).find_children("*", "Label", true, false) if b._dl_present_root != null else []:
		## 看自己当 a 的局入口不给名字 ⇒ 写「我方 / 对方」(与改之前相同); 我是 b ⇒ 写两个人的名字
		var tx := str((c as Label).text).strip_edges()
		if tx == my_name or tx == "我方":
			col_me = (c as Label).get_theme_color("font_color")
		elif tx == foe_name or tx == "对方":
			col_foe = (c as Label).get_theme_color("font_color")
	_ok("%s ★对阵幕布: 我这一列(%s)的名字是我方的绿、对面是红" % [tag, me], col_me == Color("#9ae6b0") and col_foe == Color("#ff9b9b"),
		"%s / %s" % [str(col_me), str(col_foe)])
	b._dl_sys._dl_clear_present_overlay()
	## ③ 结算屏「我方」「敌方」两页
	var scr = b._hud._settle
	if scr == null or not is_instance_valid(scr):
		_ok("%s 分母: 结算屏在场" % tag, false)
		return
	var views: Array = scr.lane_views()
	var mine_rows: Array = (views[0] as Dictionary)[me] if not views.is_empty() else []
	var foe_rows: Array = (views[0] as Dictionary)[foe] if not views.is_empty() else []
	var mn := {}
	var fn := {}
	for r in mine_rows:
		mn[str(b._st_name(r))] = true
	for r in foe_rows:
		fn[str(b._st_name(r))] = true
	var only_m: Array = []
	var only_f: Array = []
	for k in mn.keys():
		if not fn.has(k):
			only_m.append(k)
	for k in fn.keys():
		if not mn.has(k):
			only_f.append(k)
	## 召唤物那一行名字前面有「└ 」(挂在主人下面), 比名字时去掉
	var t0: Array = (_texts(scr._grids[0][0]) if not (scr._grids[0] as Array).is_empty() else []).map(
		func(x: String) -> String: return x.trim_prefix("└").strip_edges())
	var t1: Array = (_texts(scr._grids[1][0]) if not (scr._grids[1] as Array).is_empty() else []).map(
		func(x: String) -> String: return x.trim_prefix("└").strip_edges())
	var bad0: Array = []
	var bad1: Array = []
	for k in only_m:
		if not t0.has(k):
			bad0.append("缺 " + str(k))
		if t1.has(k):
			bad1.append("多 " + str(k))
	for k in only_f:
		if t0.has(k):
			bad0.append("多 " + str(k))
		if not t1.has(k):
			bad1.append("缺 " + str(k))
	_ok("%s 分母: 两队各有对面没有的单位(我这一侧独有 %d / 对面独有 %d)" % [tag, only_m.size(), only_f.size()], only_m.size() > 0 and only_f.size() > 0)
	_ok("%s ★结算屏「我方」页 = 我这一侧(%s)的单位" % [tag, me], bad0.is_empty() and only_m.size() > 0, str(bad0))
	_ok("%s ★结算屏「敌方」页 = 对面那一侧的单位" % tag, bad1.is_empty() and only_f.size() > 0, str(bad1))
	## ④ 各路胜负牌
	var want_pl: Array = []
	for ln in ["top", "bottom", "final"]:
		if lrs.has(ln):
			want_pl.append("胜" if str(lrs[ln]) == me else ("负" if str(lrs[ln]) == foe else "平"))
	var got_pl: Array = []
	for t in _texts(scr.find_child("LaneResults", true, false)):
		if t == "胜" or t == "负" or t == "平":
			got_pl.append(t)
	_ok("%s ★各路胜负牌按我这一侧(%d 路)" % [tag, want_pl.size()], want_pl.size() > 0 and got_pl == want_pl, "%s / 想要 %s" % [str(got_pl), str(want_pl)])
	## ⑤ 我方 MVP
	var mi: int = b._hud._st_mvp_index(mine_rows)
	if mi >= 0:
		_ok("%s ★本场 MVP 是我这一侧的「%s」" % [tag, str(b._st_name(mine_rows[mi]))],
			_texts(scr.find_child("MvpRow", true, false)).has(str(b._st_name(mine_rows[mi]))))
	## ⑥ 战报浮层两列
	b._on_dmg_stats_toggle()
	var ds = b._dmg_stats
	_ok("%s ★战报浮层: 「我方」那一列是 %s、「敌方」那一列是 %s" % [tag, me, foe], ds != null and ds._sides == [me, foe] and (ds._cols as Array).size() == 2,
		str(ds._sides) if ds != null else "无")
	if ds != null and ds.panel != null:
		ds.panel.visible = false
	## ⑦ 单位面板「友军 / 敌方」
	var u_me = null
	var u_foe = null
	for u in b._units:
		if bool(u.get("_isEgg", false)):
			continue
		if u_me == null and str(u.get("side", "")) == me:
			u_me = u
		if u_foe == null and str(u.get("side", "")) == foe:
			u_foe = u
	if u_me != null and u_foe != null:
		b._hud._show_unit_info_panel(u_me)
		var a_ok := _texts(b._info_panel).any(func(x: String) -> bool: return x.begins_with("友军"))
		b._hud._show_unit_info_panel(u_foe)
		var f_ok := _texts(b._info_panel).any(func(x: String) -> bool: return x.begins_with("敌方"))
		b._hud._close_info_panel()
		_ok("%s ★单位面板: 我这一侧的单位写「友军」、对面写「敌方」" % tag, a_ok and f_ok)
	else:
		print("  (%s 场上剩下的单位不够两边各一只, 单位面板这一条不量)" % tag)


## 门禁当服务器: 按交上来的快照, 由裁判程序真算一局(与裁判机同一套代码)。a / b = 左右两份快照。返回 A 赢了吗; 算不成 ⇒ null。
func _referee(a: Dictionary, b: Dictionary, mid: String):
	var job: Dictionary = JSON.parse_string(JSON.stringify({"v": 1, "job_id": _job, "match_id": mid, "mode": "gauntlet",
		"key": {"week": 1}, "seed": 2000023 + _job, "client_version": ReplayRecorder.client_version(), "a": a, "b": b}))
	var res: Dictionary = await RefereeRunner.run(self, job)
	if not bool(res.get("ok", false)):
		return null
	_rec_b64 = str(res.get("replay_b64", ""))
	_rec_mid = mid
	return bool(res.get("a_won", false))


## `UISkin.card_button` 的样子(与商店「购买」同一种): 每个状态的 StyleBoxFlat 底色 / 边色一致, 不是木牌贴图。
func _is_card_button(bt: Button) -> bool:
	if bt == null:
		return false
	var ref := Button.new()
	UISkin.card_button(ref)
	var same := true
	for st in ["normal", "hover", "pressed", "disabled"]:
		var a := bt.get_theme_stylebox(st)
		var r := ref.get_theme_stylebox(st)
		if not (a is StyleBoxFlat) or not (r is StyleBoxFlat) or (a as StyleBoxFlat).bg_color != (r as StyleBoxFlat).bg_color \
				or (a as StyleBoxFlat).border_color != (r as StyleBoxFlat).border_color:
			same = false
	ref.free()
	return same


# ───────────────────────────── R 积分赛一行不动 ─────────────────────────────
func _units(text: String) -> Dictionary:
	var rx := RegEx.create_from_string("^(static func|func|class) ([A-Za-z_0-9]+)")
	var lines := text.replace("\r\n", "\n").split("\n")
	var out := {}
	var i := 0
	while i < lines.size():
		var m := rx.search(lines[i])
		if m == null:
			i += 1
			continue
		var nm := ("class " if m.get_string(1) == "class" else "") + m.get_string(2)
		var j := i + 1
		while j < lines.size() and (lines[j] == "" or lines[j].begins_with("\t") or lines[j].begins_with(" ")):
			j += 1
		var body: Array = Array(lines.slice(i, j))
		while not body.is_empty() and str(body[-1]) == "":
			body.pop_back()
		out[nm] = "\n".join(PackedStringArray(body))
		i = j
	return out


func _indent(l: String) -> int:
	var k := 0
	while k < l.length() and l[k] == "\t":
		k += 1
	return k


## 去掉「if … PHASE_GAUNTLET / _gauntlet_now …:」那一段(含更深缩进的行) = 积分赛日走得到的样子。
func _ranked_view(body: String) -> String:
	var lines := body.split("\n")
	var out: Array = []
	var i := 0
	while i < lines.size():
		var l: String = lines[i]
		var st := l.strip_edges()
		if st.begins_with("if ") and (st.contains("PHASE_GAUNTLET") or st.contains("_gauntlet_now")) and st.ends_with(":"):
			var d := _indent(l)
			i += 1
			while i < lines.size() and (lines[i].strip_edges() == "" or _indent(lines[i]) > d):
				i += 1
			continue
		out.append(l)
		i += 1
	return "\n".join(PackedStringArray(out))


func _digest(us: Dictionary, names: Array) -> String:
	var ns := names.duplicate()
	ns.sort()
	var acc := ""
	for nm in ns:
		acc += "%s\n%s\n" % [nm, str(us.get(nm, "")).sha256_text()]
	return acc.sha256_text()


func _t_r() -> void:
	print("── R 积分赛一行不动(与 %s 逐字节比, 行尾归一) ──" % RANKED_BASE)
	var git_ok := _git_has_base()
	for f in RANKED.keys():
		var spec: Dictionary = RANKED[f]
		var names: Array = spec["units"]
		var cur := _units(FileAccess.get_file_as_string("res://" + str(f)))
		var missing: Array = []
		for nm in names:
			if not cur.has(nm):
				missing.append(nm)
		var dg := _digest(cur, names)
		var bad: Array = []
		if dg != str(spec["digest"]) and git_ok:
			var base := _units(_git_show(str(f)))
			for nm in names:
				if str(base.get(nm, "")) != str(cur.get(nm, "?")):
					bad.append(nm)
		print("    %s 比了 %d 个: %s" % [f, names.size(), ", ".join(PackedStringArray(names))])
		_ok("★R %s: 积分赛走的 %d 个函数与改动前逐字节相同" % [str(f).get_file(), names.size()],
			names.size() > 0 and missing.is_empty() and dg == str(spec["digest"]), "缺 %s · 变了 %s" % [str(missing), str(bad)])
		var views: Dictionary = spec["views"]
		for vn in views.keys():
			_ok("★R %s::%s 去掉闯关日那一段后与改动前逐字节相同(积分赛日走的那几行一字没动)" % [str(f).get_file(), vn],
				cur.has(vn) and _ranked_view(str(cur[vn])).sha256_text() == str(views[vn]))
		## 本次新加 / 改过的(周六专用)只从闯关日分支可达: 引用它的积分赛函数里, 去掉闯关日那一段就再也看不到它
		if git_ok:
			var base2 := _units(_git_show(str(f)))
			var sat: Array = (spec["sat_only"] as Array).duplicate()
			for nm in cur.keys():
				if not base2.has(nm):
					sat.append(nm)
			var leak: Array = []
			for nm in sat:
				var tok := RegEx.create_from_string("\\b%s\\b" % str(nm).replace("class ", ""))
				for un in cur.keys():
					if sat.has(un) or un == nm:
						continue
					if tok.search(_ranked_view(str(cur[un]))) != null:
						leak.append("%s ← %s" % [nm, un])
			print("    %s 周六专用(改过 / 新加)%d 个: %s" % [f, sat.size(), ", ".join(PackedStringArray(sat))])
			_ok("★R %s: 周六专用的 %d 个只从闯关日分支可达(积分赛函数去掉闯关日那一段后不再引用)" % [str(f).get_file(), sat.size()],
				leak.is_empty(), str(leak))
	if git_ok:
		## 基线表就是 84d2d853 的: 从 git 现取一遍, 摘要一致(证明表不是照着改动后抄的)
		var prov: Array = []
		for f in RANKED.keys():
			if _digest(_units(_git_show(str(f))), RANKED[f]["units"]) != str(RANKED[f]["digest"]):
				prov.append(f)
		_ok("★R 基线表 = git show %s 现算(出处可复核)" % RANKED_BASE, prov.is_empty(), str(prov))
	else:
		print("  [PEND] R 本机取不到 %s(浅克隆): 基线出处与「只从闯关日可达」两条没复核, 摘要比对照常" % RANKED_BASE)
		_pend += 1
	var mm := FileAccess.get_file_as_string("res://scripts/scenes/MatchmakingScene.gd").replace("\r\n", "\n")
	_ok("★R 匹配屏: 周六服务器那一支仍是「开关开 ⇒ _server_pick 后 return」(在积分赛挑对手之前)",
		mm.find("if _gauntlet_now and _RW.gauntlet_on():\n\t\t_server_pick(exclude, _rng)\n\t\treturn") > 0)


func _git_has_base() -> bool:
	var out: Array = []
	var rc := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "cat-file", "-e", RANKED_BASE + "^{commit}"], out, true)
	return rc == 0


## ★读原始字节再按 UTF-8 解(OS.execute 在 Windows 上按本地代码页解 git 的输出, 中文注释全坏 ⇒ 摘要永远对不上)。
func _git_show(f: String) -> String:
	var d := OS.execute_with_pipe("git", PackedStringArray(["-C", ProjectSettings.globalize_path("res://"), "show",
		"%s:%s" % [RANKED_BASE, f]]), true)
	var fa = d.get("stdio", null)
	if not (fa is FileAccess):
		return ""
	var buf := PackedByteArray()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		var chunk: PackedByteArray = (fa as FileAccess).get_buffer(65536)
		if chunk.is_empty():
			if not OS.is_process_running(int(d.get("pid", -1))):
				break
			continue
		buf.append_array(chunk)
	return buf.get_string_from_utf8()


# ───────────────────────────── Q 服务端形参对账 ─────────────────────────────
func _t_q() -> void:
	print("── Q 服务端迁移的形参 = 本机请求体 ──")
	if not FileAccess.file_exists(SQL):
		print("  [PEND] Q 服务端迁移 %s 还没落盘(SQL 线在写): 合并后这一段才真比" % SQL.get_file())
		_pend += 1
		return
	var t := FileAccess.get_file_as_string(SQL).replace("\r\n", "\n")
	var want := {JOIN: RN.queue_join_body(1, {}, 0).keys(), POLL: RN.queue_week_body(1).keys(), CANCEL: RN.queue_week_body(1).keys()}
	for fn in want.keys():
		## 取最后一份定义(create or replace function public.X(…))的形参: 本机交的键 = 前几个形参, 其余形参都要有默认值
		var a := t.rfind("create or replace function public.%s(" % fn)
		var a2 := t.find("(", a) + 1 if a >= 0 else -1
		var sig := t.substr(a2, t.find(")", a2) - a2) if a >= 0 else ""
		var got: Array = []
		var rest_ok := true
		var k := 0
		for part in sig.split(","):
			var p := part.strip_edges()
			if p == "":
				continue
			got.append(p.split(" ")[0])
			if k >= (want[fn] as Array).size() and not p.contains(" default "):
				rest_ok = false
			k += 1
		var head: Array = got.slice(0, (want[fn] as Array).size())
		_ok("★Q %s(%s): 本机交的键 = 前 %d 个形参, 其余都有默认值" % [fn, ", ".join(PackedStringArray(got)), (want[fn] as Array).size()],
			a >= 0 and head == want[fn] and rest_ok, sig.replace("\n", " "))
	_ok("Q 服务端 B 方查任务回 B 的视角(胜负取反、战绩取 gw_b / gl_b)⇒ 客户端记账不翻", t.contains("'gw', j.result->'ledger'->'gw_b'"))
	_ok("Q 配对局 matches.result 带 gw_b / gl_b(赛况板据此认右边也是主人)", t.contains("res := res || jsonb_build_object('gw_b', v_gw_b, 'gl_b', v_gl_b);"))


# ───────────────────────────── P 纯函数 ─────────────────────────────
func _t_p() -> void:
	print("── P 请求体 / 回包解析 ──")
	_ok("P 进队请求体恰好 3 个键: 周 / 锁定的阵容 / 第几场(没有对手 / 种子; 版本走请求头)",
		RN.queue_join_body(1, {"a": 1}, 2).keys() == ["p_week", "p_snapshot", "p_match_no"])
	_ok("P 心跳 / 取消请求体恰好 1 个键: 周", RN.queue_week_body(1).keys() == ["p_week"])
	var w := RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"waiting\",\"gw\":2,\"gl\":1,\"waited_sec\":37}")
	_ok("P waiting: 格子 2-1、已等 37 秒", str(w.get("err", "?")) == "" and str(w["status"]) == RN.Q_WAITING
		and int(w["gw"]) == 2 and int(w["gl"]) == 1 and int(w["waited"]) == 37, str(w))
	var opp := {"profile": {"name": "kevin_99", "avatar": "ninja", "id": "g_x", "tag": "#ABCDEF"}, "leaders": ["ninja", "dice", "pirate"]}
	var pd := RN.parse_queue(true, 200, JSON.stringify({"ok": true, "status": "paired", "job_id": 9, "side": "b", "match_id": MID, "opp": opp}))
	_ok("P paired: 任务号 / 我是 b / 录像号 / 对手卡片", str(pd.get("err", "?")) == "" and int(pd["job_id"]) == 9 and str(pd["side"]) == "b"
		and str(pd["match_id"]) == MID and str(((pd["opp"] as Dictionary)["profile"] as Dictionary)["name"]) == "kevin_99", str(pd))
	_ok("P paired 缺 side / 任务号 ⇒ server(不认半截配对)",
		str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"paired\",\"job_id\":9}").get("err", "")) == "server"
		and str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"paired\",\"side\":\"a\"}").get("err", "")) == "server")
	var cp := RN.parse_queue(true, 200, "{\"ok\":false,\"reason\":\"paired\",\"job_id\":11,\"side\":\"a\"}")
	_ok("P ★取消回「来不及, 已配上」⇒ 当 paired(这一局照样算), 没卡片 / 录像号 = 空", str(cp.get("err", "?")) == ""
		and str(cp["status"]) == RN.Q_PAIRED and int(cp["job_id"]) == 11 and (cp["opp"] as Dictionary).is_empty() and str(cp["match_id"]) == "", str(cp))
	var rs: Array = []
	for why in ["update_required", "finished", "stale", "closed"]:
		rs.append(str(RN.parse_queue(true, 200, "{\"ok\":false,\"reason\":\"%s\",\"gw\":3,\"gl\":1}" % why).get("err", "")))
	_ok("P 拒收原因原样(update_required / finished / stale / closed)", rs == ["update_required", "finished", "stale", "closed"], str(rs))
	_ok("P stale 带账本战绩", int(RN.parse_queue(true, 200, "{\"ok\":false,\"reason\":\"stale\",\"gw\":3,\"gl\":1}").get("gw", -1)) == 3)
	var jf := RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"none\",\"reason\":\"job_failed\",\"job_id\":5}")
	_ok("P none 带 reason(job_failed / closed 原样带出)", str(jf.get("status", "")) == RN.Q_NONE and str(jf.get("reason", "")) == "job_failed"
		and str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"expired\",\"reason\":\"closed\"}").get("reason", "")) == "closed", str(jf))
	_ok("P expired / none / cancelled 状态原样", str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"expired\"}").get("status", "")) == RN.Q_EXPIRED
		and str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"none\"}").get("status", "")) == RN.Q_NONE
		and str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"cancelled\"}").get("status", "")) == RN.Q_CANCELLED)
	_ok("P 断网 = offline / 404 = unavailable / 认不出的状态 = server", str(RN.parse_queue(false, 0, "").get("err", "")) == "offline"
		and str(RN.parse_queue(true, 404, "").get("err", "")) == "unavailable"
		and str(RN.parse_queue(true, 200, "{\"ok\":true,\"status\":\"pending\"}").get("err", "")) == "server")
	_ok("P 等待界面文案: 「正在寻找 2 胜 1 负的对手」/「已等待 37 秒」/「已等待 1 分 05 秒」",
		RW.queue_cell_text(2, 1) == "正在寻找 2 胜 1 负的对手" and RW.queue_waited_text(37) == "已等待 37 秒"
		and RW.queue_waited_text(65) == "已等待 1 分 05 秒")
	var banned: Array = []
	for s in [RW.TXT_QUEUE_CELL, RW.TXT_QUEUE_WAITED, RW.TXT_QUEUE_CANCEL, RW.TXT_QUEUE_CANCELLING, RW.TXT_QUEUE_LEFT, RW.TXT_QUEUE_LOST]:
		for w2 in ["你", "吧", "啦", "呢", "哦", "！", "!", "稍等", "马上"]:
			if str(s).contains(w2):
				banned.append("%s ∋ %s" % [s, w2])
	_ok("P 等待界面文案不口语化、不用「你 + 动词」(UI 规矩)", banned.is_empty(), str(banned))


# ───────────────────────────── V 看的人口径的开关 ─────────────────────────────
func _t_v() -> void:
	print("── V 看的人口径的开关只在「正在播 + side=b」时生效 ──")
	var keep: Dictionary = ReplayRecorder.play_names.duplicate()
	var rp := ReplayRecorder.new(null)     # 只用它的 mode / is_playing(构造只记下战场引用)
	var fake := {"_replay": rp}
	ReplayRecorder.play_names = {"l": "x", "r": "y", "side": "b"}
	var got := {}
	for md in ["", "play", "stream", "resume", "rec", "referee"]:
		rp.mode = md
		got[md] = ReplayRecorder.viewer_side(fake)
	_ok("V ★入口给了 side=b: 只有正在播(play / stream)才是 b; 正常对局 / 录制 / 中途退出补打 / 裁判跑局一律 a", got == {"": "a", "play": "b",
		"stream": "b", "resume": "a", "rec": "a", "referee": "a"}, str(got))
	rp.mode = "play"
	ReplayRecorder.play_names = {"l": "x", "r": "y"}
	_ok("V 入口没给 side(看自己当 a 的局 / 看别人的局)⇒ a", ReplayRecorder.viewer_side(fake) == "a"
		and ReplayRecorder.my_side(fake) == "left" and ReplayRecorder.foe_side(fake) == "right")
	_ok("V 没有战场(null)⇒ a", ReplayRecorder.viewer_side(null) == "a")
	ReplayRecorder.play_names = {"l": "x", "r": "y", "side": "b"}
	ReplayRecorder.end_play()
	_ok("V ★离场(end_play)清掉 side ⇒ 下一局不论哪条入口都从 a 起", not ReplayRecorder.play_names.has("side"), str(ReplayRecorder.play_names))
	ReplayRecorder.play_names = keep
	## 静态: 谁能给出 side = b —— 只有周六配对局那两处(RefereeWatch.watch_names / 战绩页按存下的 side 调它)
	var hits: Array = []
	_scan_lit("res://scripts", "\"side\": \"b\"", hits)
	_scan_lit("res://autoload", "\"side\": \"b\"", hits)
	hits.sort()
	_ok("V ★静态: 代码里写出 side=b 的只有 referee_watch.gd(watch_names)与 RecordScene.gd(我在右边那一行)",
		hits == ["res://scripts/scenes/RecordScene.gd", "res://scripts/systems/replay/referee_watch.gd"], str(hits))
	var rw := FileAccess.get_file_as_string("res://scripts/systems/replay/referee_watch.gd")
	_ok("V 静态: watch_names 只在 side == b 时给名字(其余 {} ⇒ 与改之前同一句 play)", rw.contains("if str(view.get(\"side\", \"a\")) != \"b\":\n\t\treturn {}"))


func _scan_lit(dir: String, lit: String, hits: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string(dir.path_join(f)).find(lit) >= 0:
			hits.append(dir.path_join(f))
	for sd in d.get_directories():
		_scan_lit(dir.path_join(sd), lit, hits)


# ───────────────────────────── A 我是 a ─────────────────────────────
func _t_a() -> void:
	print("── A join → waiting → 心跳 → paired(a) → 现有观看流程 ──")
	_reset_sc({"join": "waiting", "pair_after": 3, "side": "a"})
	var s0 := _snap()
	var st0 := _hit(START)
	var m: Node = await _open_mmk()
	var got := await _wait(func() -> bool: return _hit(JOIN) > 0 and _state(m) == RW.ST_QUEUE, 10000)
	_ok("A 分母: 进了队(join 1 次)、状态 = 排队中", got and _hit(JOIN) == 1, "%s / %d" % [_state(m), _hit(JOIN)])
	var jk: Array = _join_body.keys()
	jk.sort()
	_ok("A ★进队请求体 = 周 / 锁定的阵容(三统领)/ 第几场 = gw + gl", jk == ["p_match_no", "p_snapshot", "p_week"]
		and int(_join_body["p_week"]) == P2C.week_anchor_utc(P2C.now_utc())
		and ((_join_body["p_snapshot"] as Dictionary).get("leaders", []) as Array).size() == 3
		and int(_join_body["p_match_no"]) == int(s0["gw"]) + int(s0["gl"]), str(_join_body.keys()))
	var vh := false
	for x in _join_hdr:
		if str(x).begins_with(SB.HDR_CLIENT_VERSION + ":") and str(x).contains(ReplayRecorder.client_version()):
			vh = true
	_ok("A 版本走请求头 %s(服务端版本闸靠它)" % SB.HDR_CLIENT_VERSION, vh, str(_join_hdr))
	await _frames(10)
	var cell := _label(m, MMK.QUEUE_CELL)
	var wl := _label(m, MMK.QUEUE_WAITED)
	var bt := _cancel_btn(m)
	_ok("A ★等待界面: 「正在寻找 1 胜 0 负的对手」", cell != null and cell.text == RW.queue_cell_text(1, 0), cell.text if cell != null else "无")
	var w0 := wl.text if wl != null else ""
	_ok("A ★等待界面: 已等待秒数「已等待 N 秒」", wl != null and w0.begins_with("已等待 ") and w0.ends_with(" 秒"), w0)
	_ok("A ★等待界面: 有「取消匹配」按钮、是 card_button(不是木牌)", bt != null and bt.text == RW.TXT_QUEUE_CANCEL and _is_card_button(bt)
		and not bt.disabled, bt.text if bt != null else "无")
	var btns: Array = []
	for c in m.find_children("*", "Button", true, false):
		if (c as Button).visible and not (c as Node).is_queued_for_deletion():
			btns.append((c as Button).text)
	_ok("A ★阵容锁定: 这一屏只有「←」与「取消匹配」两颗(没有去商店 / 背包的路)", btns.size() == 2 and btns.has(RW.TXT_QUEUE_CANCEL), str(btns))
	## ★2026-10-27 实拍逮到: 格子战绩一度落进屏底那一行状态字(y 578), 4:3 上雷达环正好从字上划过 —— 原来那条只比文字的断言照样绿。
	var st_lb := _label(m, "RefereeStatus")
	_ok("A ★格子战绩写在找对手那一屏的副标题上(不是屏底状态行): 屏上不再有「正在匹配对手…」、状态行空着",
		cell != null and cell.position.y < MMK.QUEUE_WAITED_Y and not _has_label(m, "正在匹配对手…") and (st_lb == null or st_lb.text == ""),
		"%s / %s" % [str(cell.position) if cell != null else "无", st_lb.text if st_lb != null else "无"])
	var far: Array = []
	for lb in [cell, wl]:
		if lb == null:
			continue
		var tw: float = (lb as Label).get_theme_font("font").get_string_size((lb as Label).text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			(lb as Label).get_theme_font_size("font_size")).x
		var cx: float = (lb as Label).position.x + (lb as Label).size.x / 2.0
		var y0: float = (lb as Label).position.y
		var y1: float = y0 + (lb as Label).size.y
		for p in [Vector2(cx - tw / 2.0, y0), Vector2(cx + tw / 2.0, y0), Vector2(cx - tw / 2.0, y1), Vector2(cx + tw / 2.0, y1)]:
			if (p as Vector2).distance_to(MMK.RADAR_C) > MMK.RADAR_START_R:
				far.append("%s %s" % [(lb as Label).name, str(p)])
	_ok("A ★等待界面两行字都在雷达环起跳半径 %.0f 以内(环不压字; 分母 2 行 × 4 角)" % MMK.RADAR_START_R, cell != null and wl != null and far.is_empty(), str(far))
	if cell != null and wl != null and bt != null:
		var r0 := Rect2(cell.position, cell.size)
		var r1 := Rect2(wl.position, wl.size)
		var r2 := Rect2(bt.position, bt.size)
		_ok("A 等待界面三样不叠(格子战绩 / 已等待 / 取消匹配)", not r0.intersects(r1) and not r1.intersects(r2) and not r0.intersects(r2),
			"%s %s %s" % [str(r0), str(r1), str(r2)])
	_ok("A ★没配上之前不翻 VS 卡(没有「匹配成功」、没有对手卡)", not _has_label(m, "匹配成功") and (_gs.dual_opponent as Dictionary).is_empty())
	_ok("A ★进队就落排队单(没有任务号; 排队时杀进程靠它补)", RW.is_queue_bill(_gs.referee_pending)
		and int((_gs.referee_pending as Dictionary).get("week", 0)) == P2C.week_anchor_utc(P2C.now_utc()), str(_gs.referee_pending))
	await _wait(func() -> bool: return _sc_polls >= 1, 6000)
	await _frames(20)
	var w1 := wl.text if wl != null and is_instance_valid(wl) else ""
	_ok("A 已等待秒数在走(%s → %s)" % [w0, w1], w1 != w0 and w1.begins_with("已等待 "))
	var nm := str((_srv_b.get("profile", {}) as Dictionary).get("name", ""))
	got = await _wait(func() -> bool: return _has_label(m, nm), 15000)
	_ok("A ★心跳 %d 次后配上(前 3 次 waiting), 才翻 VS 卡「%s」" % [_sc_polls, nm], got and _sc_polls == 4
		and str((_gs.dual_opponent as Dictionary).get("name", "")) == nm, "心跳 %d 次" % _sc_polls)
	var gaps: Array = []
	for i in range(1, _poll_t.size()):
		gaps.append(int(_poll_t[i]) - int(_poll_t[i - 1]))
	var gap_ok := gaps.size() >= 3
	for g in gaps:
		if int(g) < 1500 or int(g) > 3500:
			gap_ok = false
	_ok("A ★心跳每 %.0f 秒一次(间隔 %s 毫秒, 分母 %d)" % [RW.QUEUE_POLL_SEC, str(gaps), gaps.size()], gap_ok)
	_ok("A 配上后等待界面拆掉", _cancel_btn(m) == null and _label(m, MMK.QUEUE_WAITED) == null)
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_SETTLING, 5000)
	var pd: Dictionary = _gs.referee_pending
	_ok("A ★排队单换成任务单(任务号 %d、录像号、我是 a ⇒ 不带 side 键, 与改之前同形)" % _job, int(pd.get("job_id", -1)) == _job
		and str(pd.get("match_id", "")) == MID and not pd.has("side") and not RW.is_queue_bill(pd), str(pd))
	_ok("A 屏上「%s」(接回现有等结果那一步)" % RW.TXT_SETTLING, _status_text(m) == RW.TXT_SETTLING, _status_text(m))
	_ok("A ★一次都没走「当场回对手快照」那条(referee_gauntlet_start)", _hit(START) == st0)
	var aw = await _referee(_join_body["p_snapshot"], _srv_b, MID)
	_ok("分母: 裁判按交上来的两份快照真算完一局(a = 我)", aw != null)
	if aw == null:
		await _close(m)
		return
	_rec_a_b64 = _rec_b64
	_srv_won = bool(aw)
	_srv_gw = int(s0["gw"]) + (1 if _srv_won else 0)
	_srv_gl = int(s0["gl"]) + (0 if _srv_won else 1)
	_done = true
	got = await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 20000)
	var b: Node = get_tree().current_scene if got else null
	_ok("A ★进了现有观看流程: 战斗场在播服务器那一份(裁判局)", b != null and b._replay.is_playing() and b._replay.is_live()
		and str(b._replay.live.kind) == LS.KIND_REFEREE and str(b._replay.rec.get("id", "")) == MID)
	if b == null:
		return
	_ok("A 我是 a ⇒ 名字照旧(左 = 看的人自己, 不额外给名字)", ReplayRecorder.play_names.is_empty(), str(ReplayRecorder.play_names))
	_ok("A ★账按服务器记(%d-%d)、单子清掉" % [_srv_gw, _srv_gl], int(_gs.gauntlet_wins) == _srv_gw and int(_gs.gauntlet_losses) == _srv_gl
		and (_gs.referee_pending as Dictionary).is_empty())
	await _play_to_end(b)
	await _wait(func() -> bool: return is_instance_valid(b) and b.find_child("SettleScreen", true, false) != null, 5000)
	_ok("A 结算屏胜负 = 服务器(%s)" % ("胜利" if _srv_won else "失败"), _settle_title(b) == ("胜利" if _srv_won else "失败"), _settle_title(b))
	## 看的人口径: 我是 a ⇒ 一切照旧(我方 = 左)
	await _viewer_checks(b, "A", "left", str(ReplayRecorder.viewer_name),
		str((_srv_b.get("profile", {}) as Dictionary).get("name", "")))


# ───────────────────────────── B 我是 b ─────────────────────────────
func _t_b() -> void:
	print("── B 同样一份但我是 b ──")
	_reset_sc({"join": "waiting", "pair_after": 1, "side": "b", "no_mid": true})
	_rec_mid = MID2                   # 服务端这一局的录像号(配上的回包不带它, 客户端从任务状态里拿)
	var s0 := _snap()
	var m: Node = await _open_mmk()
	var nm := str((_srv_b.get("profile", {}) as Dictionary).get("name", ""))
	var got := await _wait(func() -> bool: return _has_label(m, nm), 15000)
	_ok("B 分母: 心跳 1 次后配上(我是 b)、VS 卡是对手「%s」" % nm, got and _sc_polls == 2, "心跳 %d 次" % _sc_polls)
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_SETTLING, 5000)
	var pd: Dictionary = _gs.referee_pending
	_ok("B 任务单带 side = b; 配上回包没给录像号 ⇒ 用任务状态里的那个补上", int(pd.get("job_id", -1)) == _job and str(pd.get("side", "")) == "b"
		and str(pd.get("match_id", "")) == MID2, str(pd))
	## 服务器那一局: a = 对手(先锁定的那一边), b = 我交上去的阵容
	var aw = await _referee(_srv_b, _join_body["p_snapshot"], MID2)
	_ok("分母: 裁判真算完一局(a = 对手, b = 我)", aw != null)
	if aw == null:
		await _close(m)
		return
	## 服务端对 B 回 B 的视角: 胜负 = 录像里右方赢没赢, 战绩 = B 自己的账本
	_srv_won = not bool(aw)
	_srv_gw = int(s0["gw"]) + (1 if _srv_won else 0)
	_srv_gl = int(s0["gl"]) + (0 if _srv_won else 1)
	_done = true
	got = await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 20000)
	var b: Node = get_tree().current_scene if got else null
	_ok("B 分母: 进了观看流程(录像号用任务状态里的那个)", b != null and str(b._replay.rec.get("id", "")) == MID2
		and str(b._replay.live.kind) == LS.KIND_REFEREE)
	if b == null:
		return
	var me := str(BE.player_display_name())
	var sn: Dictionary = ReplayRecorder.side_names(b._replay.rec, ReplayRecorder.viewer_name)
	_ok("B ★名字换边: 左 = 对手「%s」、右 = 我「%s」(录像左方是 a)" % [nm, me], str(ReplayRecorder.play_names.get("l", "")).strip_edges() == nm
		and str(ReplayRecorder.play_names.get("r", "")) == me and str(sn.get("l", "")).strip_edges() == nm and str(sn.get("r", "")) == me,
		"%s / %s" % [str(ReplayRecorder.play_names), str(sn)])
	_ok("B ★胜负按服务端给的 B 视角记(%s; 客户端不再翻)" % ("胜" if _srv_won else "负"),
		int(_gs.gauntlet_wins) == _srv_gw and int(_gs.gauntlet_losses) == _srv_gl
		and str(((_gs.match_history as Array)[0] as Dictionary).get("result", "")) == ("win" if _srv_won else "lose"))
	var row: Dictionary = (_gs.match_history as Array)[0]
	_ok("B 战绩页那一行: 我在右边(side = b)、对手名、录像号", str(row.get("side", "")) == "b" and str(row.get("foe_name", "")) == nm
		and str(row.get("replay_id", "")) == MID2, str(row))
	await _play_to_end(b)
	await _wait(func() -> bool: return is_instance_valid(b) and b.find_child("SettleScreen", true, false) != null, 5000)
	_ok("B ★结算屏胜负 = 服务端给 B 的那一个(%s)" % ("胜利" if _srv_won else "失败"), _settle_title(b) == ("胜利" if _srv_won else "失败"),
		_settle_title(b))
	## ★看的人口径: 我是 b ⇒ 「我方」= 右边(B 自己的名字与数据)
	await _viewer_checks(b, "B", "right", me, nm)
	## 战绩页回放(我在右边那一行): 按存下的 side 给名字, 「我方」仍是右边
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(3)
	_ok("B ★离开那一局后开关清掉(side 不漏到下一局)", not ReplayRecorder.play_names.has("side"), str(ReplayRecorder.play_names))
	var rs: Node = (load("res://scenes/Record.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(rs)
	get_tree().current_scene = rs
	await _wait(func() -> bool: return _watch_btn_of(rs, MID2) != null, 5000)
	var wb := _watch_btn_of(rs, MID2)
	_ok("B 分母: 战绩页那一行(我在右边)有「观看」", wb != null)
	if wb != null:
		wb.emit_signal("pressed")
		got = await _wait(func() -> bool: return _is_battle(get_tree().current_scene), 15000)
		var b2: Node = get_tree().current_scene if got else null
		_ok("B ★战绩页回放: 名字左 = 对手「%s」、右 = 我「%s」、看的人 = b" % [nm, me], b2 != null
			and str(ReplayRecorder.play_names.get("l", "")).strip_edges() == nm and str(ReplayRecorder.play_names.get("r", "")) == me
			and ReplayRecorder.viewer_side(b2) == "b", str(ReplayRecorder.play_names))
		if b2 != null:
			await _frames(30)
			var tb = b2._hud._topbar
			_ok("B ★战绩页回放的对局顶栏: 右边写我「%s」" % me, tb != null and str(tb.name_r.text).strip_edges() == me
				and str(tb.name_l.text).strip_edges() == nm, "%s / %s" % [str(tb.name_l.text) if tb != null else "?", str(tb.name_r.text) if tb != null else "?"])
			b2.queue_free()
			await _frames(3)
	_rec_mid = MID


# ───────────────────────────── C 等待中取消 ─────────────────────────────
func _t_c() -> void:
	print("── C 等待中取消 ──")
	var dests: Array = []
	MMK._may_leave_for_test = func(dest: String) -> bool:
		dests.append(dest)
		return false
	_reset_sc({"pair_after": -1, "cancel": "cancelled", "hold_cancel": true})
	var s0 := _snap()
	var c0 := _hit(CANCEL)
	RW.notice = ""
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _state(m) == RW.ST_QUEUE and _cancel_btn(m) != null, 10000)
	var bt := _cancel_btn(m)
	_ok("C 分母: 排队中、有「取消匹配」", bt != null and _state(m) == RW.ST_QUEUE)
	if bt == null:
		await _close(m)
		return
	bt.emit_signal("pressed")
	await _frames(3)
	bt = _cancel_btn(m)
	_ok("C ★按下 ⇒ 发出队(1 次)、正在退出: 按钮灰「%s」" % RW.TXT_QUEUE_CANCELLING, _hit(CANCEL) == c0 + 1 and _state(m) == RW.ST_CANCEL
		and bt != null and bt.disabled and bt.text == RW.TXT_QUEUE_CANCELLING)
	m.get("_cancel_btn").emit_signal("pressed")
	await _frames(3)
	_ok("C 正在退出时再按「←」不重复发、也不先走", _hit(CANCEL) == c0 + 1 and dests.is_empty())
	for hc in _held:
		(hc[0] as Callable).call(hc[1])
	_held.clear()
	await _wait(func() -> bool: return not dests.is_empty(), 5000)
	_ok("C ★服务端回「已取消」⇒ 回主菜单(一次)、主菜单不飘字", dests == [MMK.MENU_SCENE] and RW.notice == "", str(dests))
	var s1 := _snap()
	_ok("C ★排队单销掉、没有对局: 战绩 / 币 / 场次 / 战绩页都没动、没查过任务", (s1["pending"] as Dictionary).is_empty()
		and s1["gw"] == s0["gw"] and s1["gl"] == s0["gl"] and s1["coins"] == s0["coins"] and s1["mh"] == s0["mh"])
	await _close(m)
	## C2: 排队中按左上「←」= 出队, 不是直接走
	dests.clear()
	_reset_sc({"pair_after": -1, "cancel": "cancelled"})
	var c1 := _hit(CANCEL)
	m = await _open_mmk()
	await _wait(func() -> bool: return _state(m) == RW.ST_QUEUE, 10000)
	m.get("_cancel_btn").emit_signal("pressed")
	await _wait(func() -> bool: return not dests.is_empty(), 5000)
	_ok("C ★排队中按「←」⇒ 先出队(发 1 次取消), 回话之后才回主菜单", _hit(CANCEL) == c1 + 1 and dests == [MMK.MENU_SCENE]
		and (_gs.referee_pending as Dictionary).is_empty(), str(dests))
	MMK._may_leave_for_test = Callable()
	await _close(m)


# ───────────────────────────── D 取消时已配上 ─────────────────────────────
func _t_d() -> void:
	print("── D 点取消的一瞬间刚好配上 ──")
	var dests: Array = []
	MMK._may_leave_for_test = func(dest: String) -> bool:
		dests.append(dest)
		return false
	_reset_sc({"pair_after": -1, "cancel": "paired", "side": "a"})
	var m: Node = await _open_mmk()
	await _wait(func() -> bool: return _state(m) == RW.ST_QUEUE and _cancel_btn(m) != null, 10000)
	var p0 := _sc_polls
	_cancel_btn(m).emit_signal("pressed")
	var nm := str((_srv_b.get("profile", {}) as Dictionary).get("name", ""))
	var got := await _wait(func() -> bool: return _has_label(m, nm), 8000)
	_ok("D ★取消回「已配上」⇒ 再心跳一次拿对手卡片 ⇒ 翻 VS 卡「%s」(照配上处理)" % nm, got and _sc_polls > p0)
	await _wait(func() -> bool: return _status_text(m) == RW.TXT_SETTLING, 5000)
	_ok("D ★接回等结果那一步、任务单(任务号 %d)、没回主菜单" % _job, _state(m) == RW.ST_WAIT
		and int((_gs.referee_pending as Dictionary).get("job_id", -1)) == _job and dests.is_empty(), "%s %s" % [_state(m), str(dests)])
	MMK._may_leave_for_test = Callable()
	await _close(m)
	_gs.referee_pending = {}


# ───────────────────────────── E 心跳回 expired / none ─────────────────────────────
func _t_e() -> void:
	print("── E 心跳回 expired / none ⇒ 已退出排队 ──")
	## [状态, reason, 主菜单飘的那一句]: 过期 / 不在队里 ⇒「已退出排队」; 收盘 ⇒ 不在时段; 配上的那一局算失败 ⇒ 请重新开战
	for row in [[RN.Q_EXPIRED, "", RW.TXT_QUEUE_LEFT], [RN.Q_NONE, "", RW.TXT_QUEUE_LEFT],
			[RN.Q_EXPIRED, "closed", RW.TXT_CLOSED], [RN.Q_NONE, "job_failed", RW.TXT_FAILED]]:
		var pe := str(row[0])
		var dests: Array = []
		MMK._may_leave_for_test = func(dest: String) -> bool:
			dests.append(dest)
			return false
		RW.notice = ""
		_reset_sc({"pair_after": 1, "poll_end": pe, "poll_reason": str(row[1])})
		var s0 := _snap()
		var m: Node = await _open_mmk()
		await _wait(func() -> bool: return not dests.is_empty(), 12000)
		pe = "%s%s" % [pe, (" · " + str(row[1])) if str(row[1]) != "" else ""]
		_ok("E ★%s: 心跳 %d 次后回主菜单、主菜单飘「%s」" % [pe, _sc_polls, row[2]], dests == [MMK.MENU_SCENE]
			and RW.notice == str(row[2]) and _sc_polls == 2, "%s / %s" % [str(dests), RW.notice])
		_ok("E %s: 排队单销掉、战绩没动" % pe, (_gs.referee_pending as Dictionary).is_empty() and int(_gs.gauntlet_wins) == int(s0["gw"]))
		MMK._may_leave_for_test = Callable()
		RW.notice = ""
		await _close(m)


# ───────────────────────────── F join 拒收 / 404 ─────────────────────────────
func _t_f() -> void:
	print("── F join 拒收 ──")
	## update_required 放最后: 它会让本机网络层整体挡写(SupabaseNet._server_said_update), 量完要还原
	var want := {"finished": RW.TXT_FINISHED, "stale": RW.TXT_STALE, "update_required": RW.TXT_UPDATE}
	for why in want.keys():
		_reset_sc({"join": why})
		var gw0 := int(_gs.gauntlet_wins)
		var gl0 := int(_gs.gauntlet_losses)
		var m: Node = await _open_mmk()
		await _wait(func() -> bool: return _status_text(m) == str(want[why]), 10000)
		await _frames(20)
		_ok("F ★%s ⇒ 屏上「%s」" % [why, want[why]], _status_text(m) == str(want[why]), _status_text(m))
		_ok("F %s ⇒ 不排队: 没心跳、没有等待界面、没有排队单 / 任务单、不翻 VS 卡" % why, _sc_polls == 0 and _cancel_btn(m) == null
			and (_gs.referee_pending as Dictionary).is_empty() and not _has_label(m, "匹配成功"))
		if why == "stale":
			_ok("F stale ⇒ 本机战绩对齐到账本 2-1(%d-%d → %d-%d)" % [gw0, gl0, int(_gs.gauntlet_wins), int(_gs.gauntlet_losses)],
				int(_gs.gauntlet_wins) == 2 and int(_gs.gauntlet_losses) == 1)
			_gs.gauntlet_wins = gw0
			_gs.gauntlet_losses = gl0
		if why == "update_required":
			_ok("F update_required ⇒ 本机网络层记下「服务端要更新」(挡墙同一条判据)", SB.update_required())
			SB._server_said_update = false
		await _close(m)
	_reset_sc({"join": "404"})
	var st0 := _hit(START)
	var m2: Node = await _open_mmk()
	await _wait(func() -> bool: return _status_text(m2) == RW.TXT_NEED_SERVER, 10000)
	await _frames(20)
	_ok("F ★服务端还没有排队(404)⇒「%s」, 不退回旧入口(一次都没调 %s)、不排队、没有单子" % [RW.TXT_NEED_SERVER, START],
		_status_text(m2) == RW.TXT_NEED_SERVER and _hit(START) == st0 and _sc_polls == 0
		and (_gs.referee_pending as Dictionary).is_empty(), _status_text(m2))
	await _close(m2)
	_gs.referee_pending = {}


# ───────────────────────────── G 主菜单补查排队单 ─────────────────────────────
func _t_g() -> void:
	print("── G 杀进程 / 断网后主菜单补查排队单 ──")
	var wk: int = P2C.week_anchor_utc(P2C.now_utc())
	## G1 配上了(我是 b)、裁判已算完 ⇒ 按任务号补记, B 视角
	_reset_sc({"pair_after": 0, "side": "b"})
	_paired_now = true
	_done = true
	var s0 := _snap()
	_srv_won = true
	_srv_gw = int(s0["gw"]) + 1
	_srv_gl = int(s0["gl"])
	_gs.referee_pending = RW.queue_bill(wk, int(s0["gw"]), int(s0["gl"]))
	var got: Array = []
	var st0 := _hit(STATUS)
	var sent: bool = RW.resume_if_any(func(v: Dictionary) -> void: got.append(v))
	await _wait(func() -> bool: return not got.is_empty(), 5000)
	_ok("G1 ★排队单 + 已配上 ⇒ 心跳 → 换任务单 → 查任务 → 补记一次(胜)", sent and got.size() == 1 and _hit(STATUS) > st0
		and bool((got[0] as Dictionary).get("won", false)))
	_ok("G1 补记后: 战绩 = 服务端给 B 的账本 %d-%d、单子清掉、战绩页那一行 side = b" % [_srv_gw, _srv_gl],
		int(_gs.gauntlet_wins) == _srv_gw and int(_gs.gauntlet_losses) == _srv_gl and (_gs.referee_pending as Dictionary).is_empty()
		and str(((_gs.match_history as Array)[0] as Dictionary).get("side", "")) == "b")
	## G2 过期 ⇒ 销单, 不查任务
	_reset_sc({"pair_after": 0, "poll_end": RN.Q_EXPIRED})
	_gs.referee_pending = RW.queue_bill(wk, int(_gs.gauntlet_wins), int(_gs.gauntlet_losses))
	st0 = _hit(STATUS)
	RW.resume_if_any()
	await _wait(func() -> bool: return (_gs.referee_pending as Dictionary).is_empty(), 5000)
	_ok("G2 ★排队单 + 已过期 ⇒ 销单、没查任务", (_gs.referee_pending as Dictionary).is_empty() and _hit(STATUS) == st0 and _sc_polls == 1)
	## G3 还在队里(杀进程后十几秒内重开)⇒ 出队、销单
	_reset_sc({"pair_after": -1, "cancel": "cancelled"})
	_gs.referee_pending = RW.queue_bill(wk, int(_gs.gauntlet_wins), int(_gs.gauntlet_losses))
	var c0 := _hit(CANCEL)
	RW.resume_if_any()
	await _wait(func() -> bool: return (_gs.referee_pending as Dictionary).is_empty(), 5000)
	_ok("G3 ★排队单 + 还在队里 ⇒ 主菜单不是等待界面: 出队(1 次)、销单", (_gs.referee_pending as Dictionary).is_empty()
		and _hit(CANCEL) == c0 + 1)
	## G4 上一周的排队单 ⇒ 直接销, 不发请求
	_reset_sc({"pair_after": -1})
	_gs.referee_pending = RW.queue_bill(wk - 7 * 86400, 0, 0)
	var p0 := _hit(POLL)
	var s4: bool = RW.resume_if_any()
	_ok("G4 上周的排队单 ⇒ 销单、不发请求", not s4 and (_gs.referee_pending as Dictionary).is_empty() and _hit(POLL) == p0)
	## G5 问不到 ⇒ 留着
	_reset_sc({"pair_after": -1, "poll_offline": true})
	_gs.referee_pending = RW.queue_bill(wk, int(_gs.gauntlet_wins), int(_gs.gauntlet_losses))
	RW.resume_if_any()
	await _wait(func() -> bool: return _sc_polls >= 1, 5000)
	await _frames(10)
	_ok("G5 问不到 ⇒ 排队单留着下次", RW.is_queue_bill(_gs.referee_pending) and _sc_polls == 1)
	_gs.referee_pending = {}
	## 排队单不会被当成任务单记账
	_ok("G 排队单没有任务号 ⇒ settle 认不到它(不会凭空记一场)", RW.settle(_gs, -1, {"won": 1, "gw": 9, "gl": 9}).is_empty())


# ───────────────────────────── W 真 HTTP ─────────────────────────────
func _t_w() -> void:
	print("── W 真走网(本机假服务器, 服务器那边数) ──")
	var srv = H.new()
	add_child(srv)
	_ok("W 分母: 本机假服务器起来了", srv.start(19471), str(srv.port))
	srv.rpc_body = "{\"ok\":true,\"status\":\"waiting\",\"gw\":1,\"gl\":0,\"waited_sec\":0,\"finals_on\":false,\"gauntlet_on\":true}"
	NR._reset_for_test()
	NR.routes_override = PackedStringArray([srv.base()])
	NR.save_path_override = "user://gauntlet_queue_gate_route.cfg"
	SB._reset_for_test()
	SB._reset_auth_for_test()
	SB._transport_for_test = Callable()
	SB._token = "gate-token"
	SB._expires_at = 0
	var flags0: Dictionary = (_gs.referee_flags as Dictionary).duplicate()
	_ok("W 分母: 后端指到本机假服务器", SB.enabled() and SB.base_url() == srv.base(), SB.base_url())
	srv.reqs.clear()
	var dests: Array = []
	MMK._may_leave_for_test = func(dest: String) -> bool:
		dests.append(dest)
		return false
	var m: Node = await _open_mmk()
	var got := await _wait(func() -> bool: return _state(m) == RW.ST_QUEUE, 10000)
	_ok("W ★进队真发到服务器(POST %s 1 次)、排队中" % JOIN, got and srv.count("POST", "/rest/v1/rpc/" + JOIN) == 1, _state(m))
	await _wait(func() -> bool: return srv.count("POST", "/rest/v1/rpc/" + POLL) >= 2, 8000)
	_ok("W ★心跳真发到服务器(5 秒内 ≥ 2 次 POST %s)" % POLL, srv.count("POST", "/rest/v1/rpc/" + POLL) >= 2,
		str(srv.count("POST", "/rest/v1/rpc/" + POLL)))
	srv.rpc_body = "{\"ok\":true,\"status\":\"cancelled\",\"finals_on\":false,\"gauntlet_on\":true}"
	var bt := _cancel_btn(m)
	if bt != null:
		bt.emit_signal("pressed")
	await _wait(func() -> bool: return not dests.is_empty(), 8000)
	_ok("W ★取消真发到服务器(POST %s 1 次)⇒ 回主菜单" % CANCEL, srv.count("POST", "/rest/v1/rpc/" + CANCEL) == 1
		and dests == [MMK.MENU_SCENE], str(dests))
	MMK._may_leave_for_test = Callable()
	await _close(m)
	NR._reset_for_test()
	NR.routes_override = PackedStringArray()
	NR.save_path_override = ""
	SB._reset_for_test()
	SB._reset_auth_for_test()
	_net_fake()
	_gs.referee_flags = flags0
	_gs.referee_pending = {}
	srv.queue_free()
	await _frames(2)


# ───────────────────────────── S 陪练号(sim_driver)走排队 ─────────────────────────────
func _t_s() -> void:
	print("── S 陪练号(sim_driver)走排队 ──")
	OS.set_environment("SIM_QUEUE_GIVEUP_SEC", "")
	var cap: float = RW.POLL_SEC * float(RW.poll_max())
	_ok("S ★闯关日匹配屏卡死线 = 排队上限 %.0f + 等裁判上限 %.0f + 余量 %.0f" % [Drv.QUEUE_GIVEUP_DEFAULT, cap, Drv.STUCK_MATCH_REFEREE_SLACK],
		is_equal_approx(Drv.stuck_limit(Drv.S_MATCH, P2C.PHASE_GAUNTLET), Drv.QUEUE_GIVEUP_DEFAULT + cap + Drv.STUCK_MATCH_REFEREE_SLACK)
		and Drv.stuck_limit(Drv.S_MATCH, P2C.PHASE_GAUNTLET) > Drv.queue_giveup_sec(), str(Drv.stuck_limit(Drv.S_MATCH, P2C.PHASE_GAUNTLET)))
	OS.set_environment("SIM_QUEUE_GIVEUP_SEC", "7")
	_ok("S SIM_QUEUE_GIVEUP_SEC=7 ⇒ 排队上限 7、卡死线跟着 7 + %.0f + %.0f" % [cap, Drv.STUCK_MATCH_REFEREE_SLACK],
		is_equal_approx(Drv.queue_giveup_sec(), 7.0)
		and is_equal_approx(Drv.stuck_limit(Drv.S_MATCH, P2C.PHASE_GAUNTLET), 7.0 + cap + Drv.STUCK_MATCH_REFEREE_SLACK))
	_ok("S 积分赛日匹配屏仍是 45 秒、别的屏不变", is_equal_approx(Drv.stuck_limit(Drv.S_MATCH, P2C.PHASE_RANKED), 45.0)
		and is_equal_approx(Drv.stuck_limit(Drv.S_BATTLE, P2C.PHASE_GAUNTLET), 600.0))
	## 真驱动整条流程, 一个进程打三局(调度器拉号时传的那几个环境变量都给上):
	##   第 1 局: 排队 2 次心跳后配上 → 看完 → 结算 → 商店(逛 SIM_SHOP_MIN~MAX 秒, 照常买)→ 背包 → 主菜单
	##   第 2 局: SIM_SKIP_WATCH=1 ⇒ 配上、账一记完就去商店(不进战斗场)→ 逛够 → 背包 → 主菜单
	##   第 3 局: 一直没人 ⇒ 等到上限(7 秒)按「取消匹配」⇒ 回主菜单 ⇒ 收工 queue_timeout
	_gs.gauntlet_wins = 1                 # 前面几段把战绩推到了晋级线上; 驱动这一段从 1-0 起
	_gs.gauntlet_losses = 0
	_gs.referee_pending = {}
	_gs.meta_deepsea_coins = 0            # 没什么钱可花 ⇒ 店里本来待不久, 「逛够 N 秒」才量得出来
	_reset_sc({"pair_after": 2, "side": "a", "cancel": "cancelled"})
	_srv_auto = true
	_rec_mid = MID
	if _rec_a_b64 == "":                  # 只跑 S 段(GATE_ONLY)时 A 段没算过: 这里算一局给第 1 局播
		await _referee(RW.my_snapshot(), _srv_b, MID)
		_rec_a_b64 = _rec_b64
	_rec_b64 = _rec_a_b64
	var j0 := _hit(JOIN)
	var c0 := _hit(CANCEL)
	var mh0: int = (_gs.match_history as Array).size()
	var env := {"SIM_SLOT": "3", "SIM_ROUNDS": "3", "SIM_TOUR": "0", "SIM_QUEUE_GIVEUP_SEC": "7",
		"SIM_SHOP_MIN_SEC": "18", "SIM_SHOP_MAX_SEC": "22", "SIM_EXPECT_CELL": "1-0", "SIM_SKIP_WATCH": ""}
	for k in env.keys():
		OS.set_environment(k, str(env[k]))
	_ok("S 分母: 逛店区间 = [18, 22] 秒、调度器以为的格子 = 1-0", Drv.shop_dwell_range() == Vector2(18, 22) and Drv.expect_cell() == Vector2i(1, 0))
	var ev0 := _ev_size()
	var d = await _start_driver()
	var stage := 0
	var t_pair := -1
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300000 and not bool(d.get("_done")):
		## 观看那一局按 8 倍放(驱动的等待都按墙钟走, 不受影响); 别的屏照常
		var cs := get_tree().current_scene
		Engine.time_scale = 8.0 if _is_battle(cs) else 1.0
		## 裁判算一局要时间: 配上 3 秒后才回「算完」(像真的一样在匹配屏停一会儿)
		if _paired_now and t_pair < 0:
			t_pair = Time.get_ticks_msec()
		if t_pair >= 0 and not _done and Time.get_ticks_msec() - t_pair > 3000:
			_done = true
		if stage == 0 and _is_battle(cs):
			stage = 1                     # 第 1 局开播: 第 2 局 1 次心跳后配上、不看
			_reset_sc_keep({"pair_after": 1, "cancel": "cancelled"})
			_done = false
			t_pair = -1
			OS.set_environment("SIM_SKIP_WATCH", "1")
		elif stage == 1 and _paired_now and cs != null and str(cs.scene_file_path) == Drv.S_SHOP:
			stage = 2                     # 第 2 局记完账进店了: 第 3 局一直没人
			_reset_sc_keep({"pair_after": -1, "cancel": "cancelled"})
		await get_tree().process_frame
	Engine.time_scale = 1.0
	var evs := _sim_events(ev0)
	var kinds: Array = []
	for e in evs:
		kinds.append(str((e as Dictionary).get("kind", "")))
	print("    驱动事件 %d 条: %s" % [kinds.size(), " ".join(PackedStringArray(kinds))])
	_ok("S 分母: 驱动记了事件(%s)" % ProjectSettings.globalize_path(Drv.EV_PATH), kinds.size() >= 10, str(kinds.size()))
	_ok("S ★第 1 局: 排队等过 → 配上 → 看完到结算(result 1 次)", kinds.count("queue_wait") >= 1 and kinds.count("queue_paired") >= 1
		and kinds.count("result") == 1, "result %d" % kinds.count("result"))
	_ok("S ★第 2 局(SIM_SKIP_WATCH=1): 配上后不进战斗场、账记完直接去商店(watch_skipped 1 次; 全程只进过 1 次战斗场)",
		kinds.count("watch_skipped") == 1 and kinds.count("queue_paired") == 2 and kinds.count("battle_enter") == 1,
		"skipped %d / paired %d / battle %d" % [kinds.count("watch_skipped"), kinds.count("queue_paired"), kinds.count("battle_enter")])
	_ok("S ★不看也照样记账: 两局都记进战绩(1-0 → %d-%d, 战绩页 +%d)" % [int(_gs.gauntlet_wins), int(_gs.gauntlet_losses),
		(_gs.match_history as Array).size() - mh0], int(_gs.gauntlet_wins) == 3 and (_gs.match_history as Array).size() - mh0 == 2)
	## 逛店: 每一次 shop_dwell 想逛的秒数在区间里, 离店时在店里待的时间 ≥ 想逛的
	var dw: Array = []
	var stays: Array = []
	for e in evs:
		var dd: Dictionary = (e as Dictionary).get("data", {})
		if str((e as Dictionary).get("kind", "")) == "shop_dwell":
			dw.append(float(dd.get("want_s", -1.0)))
		elif str((e as Dictionary).get("kind", "")) == "scene" and str(dd.get("from", "")) == Drv.S_SHOP:
			stays.append(float(dd.get("stayed_s", 0.0)))
	var dw_ok := dw.size() == 2 and stays.size() == 2
	for i in range(mini(dw.size(), stays.size())):
		if float(dw[i]) < 18.0 or float(dw[i]) > 22.0 or float(stays[i]) + 0.3 < float(dw[i]):
			dw_ok = false
	_ok("S ★两局之间逛店: 想逛 %s 秒(都在 [18, 22] 里)、实际在店里 %s 秒(≥ 想逛的; 分母 %d 次进店)" % [str(dw), str(stays), stays.size()], dw_ok)
	_ok("S ★第 3 局: 再排(join 共 %d 次)、等到上限 ⇒ 按「取消匹配」(出队 %d 次)⇒ 收工 queue_timeout" % [_hit(JOIN) - j0, _hit(CANCEL) - c0],
		_hit(JOIN) - j0 == 3 and kinds.count("queue_timeout") == 1 and _hit(CANCEL) - c0 == 1 and _done_why(evs) == "queue_timeout"
		and bool(d.get("_done")), "why=%s" % _done_why(evs))
	_ok("S ★全程不报 STUCK", kinds.count("STUCK") == 0)
	_ok("S 收工后停在主菜单", get_tree().current_scene != null and str(get_tree().current_scene.scene_file_path) == MENU_SCENE,
		str(get_tree().current_scene.scene_file_path) if get_tree().current_scene != null else "")
	d.queue_free()
	await _frames(3)
	## SIM_EXPECT_CELL ①: 本机战绩不在调度器以为的格子 ⇒ 不排, 收工 cell_mismatch
	_gs.gauntlet_wins = 1
	_gs.gauntlet_losses = 0
	_reset_sc({"pair_after": -1, "cancel": "cancelled"})
	OS.set_environment("SIM_ROUNDS", "1")
	OS.set_environment("SIM_SKIP_WATCH", "")
	OS.set_environment("SIM_EXPECT_CELL", "0-2")
	j0 = _hit(JOIN)
	ev0 = _ev_size()
	d = await _start_driver()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and not bool(d.get("_done")):
		await get_tree().process_frame
	evs = _sim_events(ev0)
	_ok("S ★SIM_EXPECT_CELL=0-2、本机 1-0 ⇒ 不排(join 0 次)、收工 cell_mismatch", _done_why(evs) == "cell_mismatch" and _hit(JOIN) == j0
		and _kind_count(evs, "cell_mismatch") == 1, "why=%s join+%d" % [_done_why(evs), _hit(JOIN) - j0])
	d.queue_free()
	await _frames(3)
	## SIM_EXPECT_CELL ②: 本机对得上、服务端账本(进队回的格子)对不上 ⇒ 出队、收工 cell_mismatch
	_reset_sc({"pair_after": -1, "cancel": "cancelled", "srv_cell": [0, 1]})
	OS.set_environment("SIM_EXPECT_CELL", "1-0")
	j0 = _hit(JOIN)
	c0 = _hit(CANCEL)
	ev0 = _ev_size()
	d = await _start_driver()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and not bool(d.get("_done")):
		await get_tree().process_frame
	evs = _sim_events(ev0)
	_ok("S ★本机 1-0 对得上、服务端回 0-1 ⇒ 进队 1 次、马上出队 1 次、收工 cell_mismatch", _done_why(evs) == "cell_mismatch"
		and _hit(JOIN) - j0 == 1 and _hit(CANCEL) - c0 == 1 and _kind_count(evs, "cell_mismatch") == 1,
		"why=%s join+%d cancel+%d" % [_done_why(evs), _hit(JOIN) - j0, _hit(CANCEL) - c0])
	d.queue_free()
	await _frames(3)
	_srv_auto = false
	RW.skip_play = false
	for k in env.keys():
		OS.set_environment(k, "")


## 起一个驱动(当前场景换成真主菜单, 驱动挂在门禁节点下; 环境变量调用方先设好)。
func _start_driver():
	var old := get_tree().current_scene
	if old != null and is_instance_valid(old) and old != self:
		old.queue_free()
	await _frames(2)
	var menu: Node = (load(MENU_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	var d = Drv.new()
	d.name = "SimDriverGate"
	add_child(d)
	return d


func _ev_size() -> int:
	return FileAccess.get_file_as_bytes(Drv.EV_PATH).size() if FileAccess.file_exists(Drv.EV_PATH) else 0


func _done_why(evs: Array) -> String:
	var why := ""
	for e in evs:
		if str((e as Dictionary).get("kind", "")) == "done":
			why = str(((e as Dictionary).get("data", {}) as Dictionary).get("why", ""))
	return why


func _kind_count(evs: Array, k: String) -> int:
	var n := 0
	for e in evs:
		if str((e as Dictionary).get("kind", "")) == k:
			n += 1
	return n


## 换剧本但不换对手 / 任务号(驱动那一段: 第二次排队)。
func _reset_sc_keep(sc: Dictionary) -> void:
	_sc = sc
	_sc_polls = 0
	_paired_now = false


func _sim_events(from: int) -> Array:
	if not FileAccess.file_exists(Drv.EV_PATH):
		return []
	var raw := FileAccess.get_file_as_bytes(Drv.EV_PATH)
	var txt := raw.slice(from).get_string_from_utf8()
	var out: Array = []
	for l in txt.split("\n"):
		if l.strip_edges() == "":
			continue
		var j = JSON.parse_string(l)
		if j is Dictionary:
			out.append(j)
	return out


func _finish() -> void:
	print("")
	print("  (共 %d 条断言 · 待合并 %d 处 · %d 帧 · %.1f 秒)" % [_n, _pend, Engine.get_process_frames(), Time.get_ticks_msec() / 1000.0])
	print("ALL PASS — 周六闯关在线排队(客户端)" if _fail == 0 and _n >= 60 else "FAIL x%d (断言 %d 条)" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
