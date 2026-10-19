extends Node
## 截图用(不是门禁): 排行榜「全部名次」—— 假服务端 137 人、我第 118 名。
## 拍两张: 开屏(第 1~10 名 + 钉住的我) / 按「我的位置」之后(滚到我那一段)。
## 跑法(要渲染, 不能 --headless; 窗口放屏外):
##   LB_SHOT_OUT=C:/tmp/lbag/shot_1280 <godot> --path . res://tests/_shot_lb_all_ranks.tscn --resolution 1280x720 --position 5000,5000 --audio-driver Dummy
##   LB_SHOT_OUT=C:/tmp/lbag/shot_1560 <godot> --path . res://tests/_shot_lb_all_ranks.tscn --resolution 1560x720 --position 5000,5000 --audio-driver Dummy
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const WEEK := 1790553600
const DAY := 86400
const TOTAL := 137
const ME_RANK := 118
const ME := "uid-shot-me"
const NAMES := ["潮头龟王", "铁背大师", "珊瑚之影", "深渊旅者", "碧波统领", "岩壳老将", "浪里白条", "霜甲先生",
	"赤焰小将", "沙洲隐士", "雷纹守卫", "青苔行者", "白沙渡客", "暗礁潜者", "云纹壳主", "落潮渔翁"]


func _row(rk: int) -> Dictionary:
	if rk == ME_RANK:
		return {"rank": rk, "name": "我自己龟", "tag": "", "account_id": ME, "wins": 2, "hearts": 3, "sweeps": 0,
			"battles": 11, "title": null}
	var nm: String = str(NAMES[(rk - 1) % NAMES.size()]) + ("" if rk <= NAMES.size() else str(rk))
	return {"rank": rk, "name": nm, "tag": "", "account_id": "uid-shot-%d" % rk,
		"wins": maxi(0, 15 - rk / 10), "hearts": 8 - (rk % 8), "sweeps": rk % 2, "battles": 16 - (rk % 5), "title": null}


func _spy(_m, url, _h, body, cb) -> void:
	if str(url).ends_with("/rest/v1/rpc/week_leaderboard_page"):
		var bj = JSON.parse_string(str(body))
		var off: int = int((bj as Dictionary).get("p_offset", 0))
		var lim: int = int((bj as Dictionary).get("p_limit", 50))
		var rows := []
		for rk in range(off + 1, mini(TOTAL, off + lim) + 1):
			rows.append(_row(rk))
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": WEEK, "total": TOTAL,
			"offset": off, "rows": rows, "me": _row(ME_RANK)})})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})


func _ready() -> void:
	GameState.test_mode = true
	GameState.account_id = ME
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
	for _i in range(420):
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
