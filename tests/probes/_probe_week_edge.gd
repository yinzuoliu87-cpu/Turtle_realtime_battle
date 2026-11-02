extends Node
## 探针: **跨周/跨日边界那几秒**。所有门禁都钉在某天正午, 而 off-by-one 住在边界上。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
const SUN0 := 1789862400          # 2026-09-20 周日 00:00 UTC
const MON0 := SUN0 + 86400        # 周一 00:00 = 换轮时刻


func _show(label: String, ts: int) -> void:
	var ph: String = str(P2.phase_at_utc(ts))
	var live: bool = bool(P2.phase_mode_live(ph))
	print("  %-26s ts=%d  phase=%-9s 吃配额=%-5s 结算类=%s" % [
		label, ts, ph, str(P2.phase_uses_ranked_quota(ph)), str(P2.settle_kind(ph, live))])


func _ready() -> void:
	await get_tree().process_frame
	print("=== 边界秒: 周日→周一(换轮) ===")
	for off in [-2, -1, 0, 1, 2]:
		_show("周一00:00 %+d 秒" % off, MON0 + off)
	print("")
	print("=== 边界秒: 周五→周六(闯关赛开) ===")
	var sat := SUN0 - 86400
	for off in [-2, -1, 0, 1]:
		_show("周六00:00 %+d 秒" % off, sat + off)
	print("")
	print("=== 边界秒: 周六→周日(决赛日开) ===")
	for off in [-2, -1, 0, 1]:
		_show("周日00:00 %+d 秒" % off, SUN0 + off)
	print("")
	print("=== 周的锚: 同一周里 start_of_week 必须恒定 ===")
	var anchors: Dictionary = {}
	for d in range(7):
		for h in [0, 1, 12, 23]:
			var ts: int = MON0 + d * 86400 + h * 3600
			anchors[int(P2.week_anchor_utc(ts))] = true
	print("  一周 28 个采样点算出的周锚个数 = %d (应为 1)" % anchors.size())
	get_tree().quit(0)
