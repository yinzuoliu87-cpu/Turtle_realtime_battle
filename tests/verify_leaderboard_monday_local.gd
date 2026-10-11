extends Node
## verify_leaderboard_monday_local.gd —— 周一离线时「上周终榜」里自己那一行不许用本周已清零的成绩冒充(2026-10-11 全项目通读 B4)
##
## ★服务端那一路(`_server_rows`)周一已经只钉一行空名次; 本机兜底那一路(`_local_rows`)漏了 ⇒
##   断网的周一, 上周终榜里「我」显示 0 胜满命(本周刚滚出来的存档)。
## ★判据走产品函数: day_phase = 休赛日, 存档本周 0 胜 ⇒ _local_rows 里自己那一行的胜场/命/场次一律是 -1(画「—」)。

const LB := preload("res://scripts/scenes/LeaderboardScene.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _self_row(rows: Array) -> Dictionary:
	for r in rows:
		if bool((r as Dictionary).get("is_self", false)):
			return r
	return {}


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周一离线上周终榜不冒充 ===")
	GameState.test_mode = true
	var m = LB.new()
	m.day_phase = P2.PHASE_REST
	var me := _self_row(m._local_rows())
	_ok("★分母: 本机那一路有自己那一行", not me.is_empty(), str(me))
	_ok("★★周一 ⇒ 自己那一行不拿本周存档冒充上周(胜/命/场次 = -1)",
		int(me.get("wins", 0)) == -1 and int(me.get("hearts", 0)) == -1 and int(me.get("battles", 0)) == -1, str(me))
	m.day_phase = P2.PHASE_RANKED
	var me2 := _self_row(m._local_rows())
	_ok("★对照: 积分赛日照常用存档成绩", int(me2.get("wins", -9)) == int(GameState.season_wins), str(me2))
	m.free()
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
