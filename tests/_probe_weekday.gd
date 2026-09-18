extends Node
## 一次性探针: 核实 Godot 的 weekday 口径(我在 phase2_config 里假设 0=周日)。
## 别猜 —— 拿已知答案的样本量一遍(memory fb-verify-check-can-fail)。
const P2 := preload("res://scripts/gamedata/phase2_config.gd")
func _ready() -> void:
	## 已知: 2026-09-14 是周一, 2026-09-17 是周四, 2026-09-19 周六, 2026-09-20 周日
	var samples := {
		"2026-09-14 周一": 1789344000, "2026-09-17 周四": 1789603200,
		"2026-09-19 周六": 1789776000, "2026-09-20 周日": 1789862400,
	}
	for k in samples:
		var ts: int = int(samples[k])
		var d: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
		print("  %s → godot weekday=%s  日期=%04d-%02d-%02d  ISO=%d  阶段=%s"
			% [k, str(d.get("weekday")), int(d.get("year")), int(d.get("month")), int(d.get("day")),
			P2.iso_weekday_utc(ts), P2.phase_at_utc(ts)])
	print("PROBE_DONE")
	get_tree().quit(0)
