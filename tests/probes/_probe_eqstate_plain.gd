extends Node
## _probe_eqstate_plain.gd —— 哪些单位的哪几格「表」因为混进对象而整份不进直播流(探针, 2026-11-20)。
## 录流器对 UKEYS_INFO 里的字典 / 数组: `_plain_deep` 不过 ⇒ 整份不发(stream_recorder `_samp`)。
## 这里跑 verify_stream_parity_wide 的 5 局里的 3 局, 采样时列出每个不纯的 (龟, 键, 路径, 类型)。

const PA := preload("res://tests/verify_stream_parity_wide.gd")
const SR := preload("res://scripts/systems/stream/stream_recorder.gd")
const J := preload("res://tests/_stream_jobs.gd")

var _hits := {}


func _paths(v, path: String, depth: int, out: Array) -> void:
	if depth > 6:
		out.append(path + " <深度>6>")
		return
	var t := typeof(v)
	if t == TYPE_OBJECT or t == TYPE_CALLABLE or t == TYPE_RID or t == TYPE_SIGNAL:
		out.append("%s <%s>" % [path, type_string(t)])
		return
	if t == TYPE_ARRAY:
		for i in range((v as Array).size()):
			_paths(v[i], "%s[%d]" % [path, i], depth + 1, out)
	elif t == TYPE_DICTIONARY:
		for kk in v:
			_paths(v[kk], "%s.%s" % [path, str(kk)], depth + 1, out)


func _ready() -> void:
	var gs = get_node_or_null("/root/GameState")
	var pa = PA.new()
	var pids: Array = []
	for k in DataRegistry.pet_by_id.keys():
		pids.append(str(k))
	pids.sort()
	var shop: Array = []
	for e in DataRegistry.phase2_equipment:
		if int((e as Dictionary).get("shopAvailable", 0)) == 1:
			shop.append(str((e as Dictionary)["id"]))
	shop.sort()
	var ei := 0
	for g in range(5):
		var six: Array = []
		for k in range(6):
			six.append(pids[(g * 6 + k) % pids.size()])
		var eqA: Array = []
		var eqB: Array = []
		for k in range(3):
			eqA.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
			ei += 3
		for k in range(3):
			eqB.append([{"id": shop[ei % shop.size()], "star": 1 + ei % 3}, {"id": shop[(ei + 1) % shop.size()], "star": 2}, {"id": shop[(ei + 2) % shop.size()], "star": 3}])
			ei += 3
		var a: Dictionary = pa._snap(gs, six.slice(0, 3), eqA, "g_pa_%d" % g, "甲%d" % g, 0)
		var b2: Dictionary = pa._snap(gs, six.slice(3, 6), eqB, "g_pb_%d" % g, "乙%d" % g, 1)
		var job: Dictionary = J.job(a, b2, int(PA.SEEDS[g]))
		var hook := func(bt) -> void:
			bt.ready.connect(func() -> void:
				var rec: StreamRecorder = bt._replay.stream
				rec.on_sampled = func(_s: int) -> void:
					for u in (bt._units as Array):
						for k in SR.UKEYS_INFO:
							var v = (u as Dictionary).get(k)
							var t := typeof(v)
							if (t == TYPE_DICTIONARY or t == TYPE_ARRAY) and not SR._plain_deep(v):
								var out: Array = []
								_paths(v, k, 0, out)
								for p in out:
									var key := "%s | %s" % [str((u as Dictionary).get("id", "?")), _strip_idx(p)]
									_hits[key] = int(_hits.get(key, 0)) + 1
				, CONNECT_ONE_SHOT)
		await RefereeRunner.run(self, job, hook, {"keep": true})
		print("局 %d 跑完" % (g + 1))
	var ks: Array = _hits.keys()
	ks.sort()
	print("不纯的格(龟 | 路径 <类型>) 共 %d 种:" % ks.size())
	for k in ks:
		print("  %s   ×%d" % [k, _hits[k]])
	pa.free()
	get_tree().quit(0)


static func _strip_idx(p: String) -> String:
	return RegEx.create_from_string("\\[[0-9]+\\]").sub(p, "[]", true)
