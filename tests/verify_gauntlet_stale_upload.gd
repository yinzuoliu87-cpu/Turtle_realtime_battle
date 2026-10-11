extends Node
## verify_gauntlet_stale_upload.gd —— 周六快照过了 30 分钟也要补传(2026-10-11 全项目通读·赛制第 5 条)
##
## ★读码发现: 上传队列把超过 FRESH_SNAPSHOT_SEC(30 分钟)的周六快照直接销单(理由写的是「匹配层按 30 分钟过滤,
##   补上去也没人打得到」), 而匹配层 2026-09-26 起已改成「同标签: 新鲜优先、没有就用隔夜的, 都没有才机器人」。
##   ⇒ 断网/后台超过 30 分钟的人, 那份周六快照永远传不上去, 同战绩的真人对手白白变少。
## ★判据走产品的纯函数 drop_reason: 2 小时前的周六快照 ⇒ 不销单; 跨周的照样销单(对照)。

const GU := preload("res://scripts/net/ghost_uploader.gd")
const P2 := preload("res://scripts/gamedata/phase2_config.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 周六快照过期也补传 ===")
	var now: int = int(Time.get_unix_time_from_system())
	var wk: int = P2.week_anchor_utc(now)
	var e := {"tbl": GU.TBL_GAUNTLET, "wk": wk, "gw": 2, "gl": 1, "acc": "",
		"snap": {"leaders": ["basic"], "gl_ts": now - 7200}}
	_ok("★分母: 这条单子格式合法(不是因为格式被销)", GU._malformed(e) == "", GU._malformed(e))
	_ok("★★2 小时前的周六快照 ⇒ 不销单(匹配层会用隔夜的同标签快照)", GU.drop_reason(e, now, "") == "",
		"drop_reason=%s" % GU.drop_reason(e, now, ""))
	_ok("★对照: 跨周的照样销单", GU.drop_reason(e, wk + GU.WEEK_SEC + 1, "").begins_with("week_over"),
		GU.drop_reason(e, wk + GU.WEEK_SEC + 1, ""))
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
