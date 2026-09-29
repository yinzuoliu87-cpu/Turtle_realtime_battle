extends Node
## _probe_three_ids.gd — ③的探针: 设置页 / 排行榜 / 匹配屏三个「号」各自是什么, 换个账号会不会变。
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const MM := preload("res://scripts/scenes/MatchmakingScene.gd")

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	var mm = MM.new()
	print("=== 同一赛季 · 两个不同账号 ===")
	for aid in ["ae08e589-1111-2222-3333-444455556666",
				"7f3b21cc-9999-8888-7777-666655554444"]:
		gs.account_id = aid
		gs.nickname = ""
		gs.season_id = 2
		print("  account_id = %s" % aid)
		print("    设置页显示       = 「匿名 %s」   (account_id.substr(0,8))" % aid.substr(0, 8))
		print("    排行榜显示       = 「%s」   (P2C.display_name → nickname_fallback = 龟主-sha256[0:5])"
			% P2C.display_name(str(gs.nickname), aid))
		print("    匹配屏「我」的 ID = 「%s」   (_display_id(\"me_%%d\" %% season_id))"
			% mm._display_id("me_%d" % int(gs.season_id)))
	print("")
	print("=== 同一个账号 · 换赛季 ===")
	gs.account_id = "ae08e589-1111-2222-3333-444455556666"
	for sid in [1, 2, 3]:
		gs.season_id = sid
		print("  season_id=%d → 匹配屏 ID 「%s」" % [sid, mm._display_id("me_%d" % sid)])
	print("")
	print("=== 设了昵称之后排行榜显示什么 ===")
	gs.nickname = "石头龟主阿龟"
	print("  nickname=「%s」 → 排行榜「%s」" % [gs.nickname, P2C.display_name(str(gs.nickname), str(gs.account_id))])
	print("")
	print("=== _display_id 白名单口径 ===")
	for raw in ["", "#503911", "BOT", "autoplay-b2_COH7", "COH0-11", "ghost_abc"]:
		print("  raw=「%s」 → 「%s」" % [raw, mm._display_id(raw)])
	mm.free()
	get_tree().quit(0)
