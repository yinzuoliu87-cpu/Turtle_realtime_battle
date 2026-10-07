extends Node
## 截图用(不是门禁): 把钟钉在 LB_DAY=mon/tue/sat/sun, 喂假服务端 12 行 + 一组 8 人决赛, 打开排行榜。
## 配 --write-movie 用; 跑法见 2026-10-06 排行榜四天那一轮。
const SB := preload("res://scripts/net/supabase.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")
const WEEK := 1790553600
const DAY := 86400
const NAMES := ["潮头龟王", "铁背大师", "珊瑚之影", "深渊旅者", "碧波统领", "岩壳老将",
	"浪里白条", "霜甲先生", "赤焰小将", "沙洲隐士", "雷纹守卫"]

func _row(i: int) -> Dictionary:
	var hp: int = P2C.HEARTS_MAX - (i % 3)
	return {"rank": i + 1, "name": NAMES[i], "tag": "", "account_id": "uid-shot-%d" % i,
		"wins": 14 - i, "hearts": hp, "sweeps": i % 2, "battles": 16 - (i % 2), "title": null}

func _me() -> Dictionary:
	return {"rank": 20, "name": "我自己龟", "tag": "", "account_id": "uid-shot-me", "wins": 6, "hearts": 2,
		"sweeps": 1, "battles": 12, "title": null}

func _spy(_m, url, _h, _b, cb) -> void:
	if str(url).ends_with("/rest/v1/rpc/week_leaderboard"):
		var rows := []
		for i in range(11):
			rows.append(_row(i))
		rows.append(_me())
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": WEEK, "total": 57,
			"rows": rows, "me": _me()})})
	elif str(url).ends_with("/rest/v1/rpc/finals_week_view"):
		var ents := []
		for s in range(8):
			ents.append({"seed": s, "name": NAMES[s], "account_id": "uid-shot-%d" % s})
		var done := {"1-0": 0, "1-1": 0, "1-2": 0, "1-3": 0, "2-0": 0, "2-1": 0, "3-0": 0}
		cb.call({"ok": true, "code": 200, "body": JSON.stringify({"ok": true, "week": WEEK, "now": 0,
			"buckets": [{"bucket": 0, "n": 8, "round": 3, "closed": true, "entrants": ents, "done": done}]})})
	else:
		cb.call({"ok": false, "code": 0, "body": ""})

func _ready() -> void:
	GameState.test_mode = true
	GameState.account_id = "uid-shot-me"
	var d := OS.get_environment("LB_DAY")
	var off := {"mon": 7 * DAY + 10 * 3600, "tue": DAY + 10 * 3600, "sat": 5 * DAY + 15 * 3600,
		"sun": 6 * DAY + 20 * 3600}
	P2C.now_override_ts = WEEK + int(off.get(d, DAY + 10 * 3600))
	OS.set_environment(SB.ENV_URL, "http://shot.local")
	ProjectSettings.set_setting(SB.SETTING_KEY, "shot-anon-key")
	SB._token = "shot-token"
	SB._expires_at = 0
	SB._transport_for_test = _spy
	var inst: Node = (load("res://scenes/Leaderboard.tscn") as PackedScene).instantiate()
	add_child(inst)
	print("[SHOT] day=%s phase=%s" % [d, P2C.phase_at_utc(P2C.now_utc())])
