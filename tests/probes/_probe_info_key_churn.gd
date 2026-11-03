extends Node
## _probe_info_key_churn.gd —— 2026-11-03：录流器新加的 UKEYS_INFO 里，哪些键在采样之间变得最勤（流体积的大头）。探针，不进门禁。
const J := preload("res://tests/_stream_jobs.gd")

var _cnt := {}
var _last := {}

func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var job: Dictionary = J.mirror(gs)
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(_s: int) -> void:
				for i in range(rec._uk.size()):
					var u = rec._uk[i]
					if not (u is Dictionary):
						continue
					for k in StreamRecorder.UKEYS_INFO:
						var v = (u as Dictionary).get(k)
						var key := "%d/%s" % [i, k]
						if _last.has(key) and typeof(_last[key]) == typeof(v) and _last[key] == v:
							continue
						if typeof(v) == TYPE_OBJECT:
							continue
						_last[key] = (v.duplicate(true) if (v is Dictionary or v is Array) else v)
						_cnt[k] = int(_cnt.get(k, 0)) + 1
			, CONNECT_ONE_SHOT)
	await RefereeRunner.run(self, job, hook, {"keep": false})
	var ks: Array = _cnt.keys()
	ks.sort_custom(func(a, b) -> bool: return int(_cnt[a]) > int(_cnt[b]))
	for k in ks.slice(0, 30):
		print("[CHURN] %6d  %s" % [int(_cnt[k]), k])
	get_tree().quit(0)
