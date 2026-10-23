extends Node
## 截图用(不是门禁): 排行榜「全部名次」—— 假服务端 N 人(默认 137)、我第 ME 名(默认 118)。
## 拍两张: 开屏(第 1 名起一屏 + 钉住的我) / 按「我的位置」之后(滚到我那一段)。
## 跑法(要渲染, 不能 --headless; 窗口放右屏):
##   LB_SHOT_OUT=C:/tmp/lbag/shot_1560 <godot> --path . res://tests/_shot_lb_all_ranks.tscn --resolution 1560x720 --position 2000,80 --audio-driver Dummy
##   人少那一张: LB_SHOT_N=3 LB_SHOT_ME=2 LB_SHOT_OUT=... (同上)
## ★2026-10-23 排行榜重做: 每行多带 `lead`(第一只统领 id, 服务端迁移后下发) ⇒ 截图里头像是真的;
##   第 5 名与第 9 名同名(重名才露玩家 ID 那条); 第 12 名不带 lead(看默认头像)。
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const WEEK := 1790553600
const DAY := 86400
const ME := "uid-shot-me"
const NAMES := ["潮头龟王", "铁背大师", "珊瑚之影", "深渊旅者", "碧波统领", "岩壳老将", "浪里白条", "霜甲先生",
	"铁背大师", "沙洲隐士", "雷纹守卫", "青苔行者", "白沙渡客", "暗礁潜者", "云纹壳主", "落潮渔翁"]
const LEADS := ["stone", "ninja", "phoenix", "ice", "basic", "lava", "pirate", "angel", "mech", "bamboo",
	"lightning", "", "crystal", "ghost", "space", "hunter"]

var _total := 137
var _me_rank := 118


func _row(rk: int) -> Dictionary:
	if rk == _me_rank:
		return {"rank": rk, "name": "我自己龟", "tag": "#K7Q2MX", "account_id": ME, "wins": 2, "hearts": 3,
			"sweeps": 0, "battles": 11, "title": null, "lead": "basic"}
	var nm: String = str(NAMES[(rk - 1) % NAMES.size()]) + ("" if rk <= NAMES.size() else str(rk))
	return {"rank": rk, "name": nm, "tag": _tag(rk), "account_id": "uid-shot-%d" % rk,
		"wins": maxi(0, 15 - rk / 10), "hearts": P2C.HEARTS_MAX - (rk % P2C.HEARTS_MAX), "sweeps": rk % 2,
		"battles": 16 - (rk % 5), "title": null, "lead": str(LEADS[(rk - 1) % LEADS.size()])}


## 玩家 ID 的长相照真号(`#` + 6 位大写字母数字)。
func _tag(rk: int) -> String:
	var cs := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	var s := "#"
	var v := rk * 7919 + 104729
	for _i in range(6):
		s += cs[v % cs.length()]
		v = v / cs.length() + rk * 31
	return s


func _spy(_m, url, _h, body, cb) -> void:
	if str(url).ends_with("/rest/v1/rpc/week_leaderboard_page"):
		var bj = JSON.parse_string(str(body))
		var off: int = int((bj as Dictionary).get("p_offset", 0))
		var lim: int = int((bj as Dictionary).get("p_limit", 50))
		var rows := []
		for rk in range(off + 1, mini(_total, off + lim) + 1):
			rows.append(_row(rk))
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": WEEK, "total": _total,
			"offset": off, "rows": rows, "me": _row(_me_rank)})})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _ready() -> void:
	GameState.test_mode = true
	GameState.account_id = ME
	if OS.get_environment("LB_SHOT_N") != "":
		_total = maxi(1, int(OS.get_environment("LB_SHOT_N")))
	if OS.get_environment("LB_SHOT_ME") != "":
		_me_rank = int(OS.get_environment("LB_SHOT_ME"))
	_me_rank = mini(_me_rank, _total)
	P2C.now_override_ts = WEEK + 2 * DAY + 12 * 3600
	OS.set_environment(SB.ENV_URL, "http://shot.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "shot-anon-key")
	SB._token = "shot-token"
	SB._expires_at = 0
	SB._transport_for_test = _spy
	var out := OS.get_environment("LB_SHOT_OUT")
	if out == "":
		out = "C:/tmp/lbag/shot"
	var inst: Node = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(inst)
	for _i in range(30):
		await get_tree().process_frame
	## ★`SupabaseNet._week_lb_row` 只搬它认识的键 —— 服务端加 `lead` 之后那里要跟着放行(主会话那一刀)。
	##   在那之前截图走假传输会把 `lead` 丢掉、头像全是名字首字 ⇒ 这里把整榜(带 lead)直接交给本屏画,
	##   画法与回包到了之后完全同一条(`_render(rows, 服务端, 总数, 我, 列表长)`)。
	## LB_SHOT_MARKS=1: 前四名挂头衔(冠军 / 亚军 / 四强 / 进入决赛日), 看「名字 + 玩家 ID + 头衔」一行挤不挤。
	var marks: Array = [P2C.TITLE_CHAMPION, P2C.TITLE_RUNNER_UP, P2C.TITLE_SEMIFINAL, P2C.TITLE_FINALS_DAY] \
		if OS.get_environment("LB_SHOT_MARKS") == "1" else []
	var all := []
	for rk in range(1, _total + 1):
		all.append(_row(rk).merged({"is_self": rk == _me_rank,
			"title": str(marks[rk - 1]) if rk <= marks.size() else ""}, true))
	var me: Dictionary = _row(_me_rank).merged({"is_self": true, "title": ""}, true)
	inst.call("_render", all, "server", _total, me, _total)
	for _i in range(390):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "_1_open.png")
	(inst.get("jump_btn") as Button).pressed.emit()
	for _i in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "_2_jump.png")
	print("[SHOT] saved ", out)
	get_tree().quit(0)
