extends Node
## 探针: 把「今天」换成「七天全量」, 扫一遍**按星期几分支**的产品函数。
## ★周日那条 bug(v0.19.458)就是这么照出来的。同一把尺子再问几个维度。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400
const DAY := ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]


func _ready() -> void:
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 七天 × 各条按星期几分支的规则 ===")
	print("  %-5s %-9s %-7s %-7s %-7s %s" % ["", "phase", "已上线", "吃配额", "结算类", "赛程条待上线提示"])
	for d in range(7):
		var ts: int = SUN0 + d * 86400 + 12 * 3600
		var ph: String = str(P2.phase_at_utc(ts))
		var live: bool = bool(P2.phase_mode_live(ph))
		var uses: bool = bool(P2.phase_uses_ranked_quota(ph))
		var kind: String = str(P2.settle_kind(ph, live))
		var note: String = str(P2.phase_pending_note(ph))
		print("  %-5s %-9s %-7s %-7s %-7s %s" % [DAY[d], ph, str(live), str(uses), kind,
			("(照常)" if note == "" else note.substr(0, 24))])
	## ★交叉检查: 「不吃配额」的那几天, 是不是都有自己的闸?
	print("")
	print("=== 不吃积分赛配额的天, 必须各有自己的闸 ===")
	for d in range(7):
		var ts2: int = SUN0 + d * 86400 + 12 * 3600
		var ph2: String = str(P2.phase_at_utc(ts2))
		if not bool(P2.phase_uses_ranked_quota(ph2)):
			print("  %s(%s) —— 不吃配额, 它的闸在哪: 见 _battle_block_msg 的分支" % [DAY[d], ph2])
	get_tree().quit(0)
