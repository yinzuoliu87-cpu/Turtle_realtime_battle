extends Node
## 探针(下划线开头: 不是门禁): 最重那局原生跑两遍(裁判每帧预算 100ms / 1ms), 对比飘字 Label 序列, 打印多出来的那几条是谁建的(get_stack)。

const J := preload("res://tests/_stream_jobs.gd")


func _run(budget: int) -> Array:
	ReplayRecorder.referee_budget_us = budget
	var out: Array = []
	var cur := [-1]
	var hook := func(n: Node) -> void:
		if not (n is Label):
			return
		var p := n.get_parent()
		if p == null or not (p is CanvasLayer or (p is HBoxContainer and p.get_parent() is CanvasLayer)):
			return
		var st := get_stack()
		var who := ""
		for f in st:
			var fn := str(f.get("function", ""))
			if fn != "<anonymous lambda>" and fn != "_run":
				who += "%s:%d<" % [str(f.get("source", "")).get_file() + ":" + fn, int(f.get("line", 0))]
		out.append([cur[0], (n as Label).text, who.left(400)])
	var bh := func(bt) -> void:
		bt.ready.connect(func() -> void:
			bt.sim_stepped.connect(func() -> void: cur[0] = int(bt._sim_step_n)), CONNECT_ONE_SHOT)
	get_tree().node_added.connect(hook)
	var res: Dictionary = await RefereeRunner.run(self, J.heavy(), bh, {"keep": false})
	get_tree().node_added.disconnect(hook)
	print("NF budget=%d ok=%s steps=%s floats=%d" % [budget, str(res.get("ok")), str(res.get("steps")), out.size()])
	return out


func _ready() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
	OS.set_environment("TURTLE_SEED", "")
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	gs.test_mode = true
	gs.tutorial_active = false
	var a: Array = await _run(100000)
	var b: Array = await _run(1000)
	var i := 0
	var j := 0
	var shown := 0
	while (i < a.size() or j < b.size()) and shown < 30:
		var ea = a[i] if i < a.size() else null
		var eb = b[j] if j < b.size() else null
		if ea != null and eb != null and str(ea[1]) == str(eb[1]) and absi(int(ea[0]) - int(eb[0])) <= 2:
			i += 1
			j += 1
			continue
		shown += 1
		if eb == null or (ea != null and int(ea[0]) <= int(eb[0])):
			print("NF only@100ms ", ea)
			i += 1
		else:
			print("NF only@1ms ", eb)
			j += 1
	print("NF done")
	get_tree().quit(0)
