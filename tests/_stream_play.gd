extends RefCounted
## 逐帧直播 S2 门禁共用: 「原生跑一遍(同时录流)」与「按流播一遍」, 各在同一批步号拍快照(下划线开头: 不是门禁)。
## 被 verify_stream_parity / verify_stream_seek / verify_stream_no_sim preload。
##
## 快照形状(两边同一个函数 `snap` 拍, 只是「单位 idx → 字典」「节点 id → 节点」的来源不同):
##   units: idx → [pos, height, hp, shield, alive, maxHp]
##   nodes: id → [类名, visible, position, rotation, scale, frame, 贴图路径, modulate]
##   census: `_world` 子树里所有没被删的节点, 按类名计数(包括地图、单位外观、渲染步按状态造的特效)
##   floats: 这一步新冒出来的飘字文本(按 `_ui_layer` 里新加的 Label 文本, 不经录流器)

const J := preload("res://tests/_stream_jobs.gd")
const SIM_DT := 1.0 / 60.0


static func _units_of(units_by_idx: Dictionary) -> Dictionary:
	var out := {}
	for idx in units_by_idx:
		var u: Dictionary = units_by_idx[idx]
		out[int(idx)] = [u.get("pos", Vector2.ZERO), float(u.get("height", 0.0)), float(u.get("hp", 0.0)),
			float(u.get("shield", 0.0)), bool(u.get("alive", false)), float(u.get("maxHp", 0.0)),
			"%s/%s land=%s hitsq=%s swing=%s windup=%s air=%s vy=%s fl=%s hs=%s" % [str(u.get("id", "")), str(u.get("side", "")),
				str(u.get("land_t")), str(u.get("hitsq_t")), str(u.get("swing_t")), str(u.get("windup_t")), str(u.get("airborne")),
				str(u.get("vy")), str(u.get("flash_t")), str(u.get("hp"))] + " @n=%s spr=%s alive=%s manual=%s" % [str(u.get("@n")),
				str(u.get("sprite")), str(u.get("alive")), str(u.get("_manual_anim"))]]
	return out


static func _tex_key(t) -> String:
	if t == null or not is_instance_valid(t):
		return ""
	var p := str((t as Resource).resource_path)
	if p != "" and p.find("::") < 0:
		return p
	return "<gen:%s>" % (t as Object).get_class()


static func _nodes_of(nodes_by_id: Dictionary) -> Dictionary:
	var out := {}
	for id in nodes_by_id:
		var n = nodes_by_id[id]
		if n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion() or not (n as Node).is_inside_tree():
			continue
		var pp := (n as Node).get_parent()
		var row: Array = [(n as Node).get_class(), true, null, null, null, -1, "", null, ("%s %s" % [pp.get_class(), pp.name]) if pp != null else "", ""]
		if n is Node3D:
			var n3: Node3D = n
			row[1] = n3.visible
			row[2] = n3.position
			row[3] = n3.rotation
			row[4] = n3.scale
		if n is Sprite3D:
			var sp: Sprite3D = n
			row[5] = sp.frame
			row[6] = _tex_key(sp.texture)
			row[7] = sp.modulate
		elif n is Label3D:
			row[7] = (n as Label3D).modulate
		elif n is MeshInstance3D:
			var m: Mesh = (n as MeshInstance3D).mesh
			if m != null:
				var mp := str(m.resource_path)
				row[9] = mp if (mp != "" and mp.find("::") < 0) else ("<proc:%s>" % m.get_class() if (m is ArrayMesh or m is ImmediateMesh) else "<param:%s>" % m.get_class())
		out[int(id)] = row
	return out


static func census(world: Node) -> Dictionary:
	var out := {}
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c.is_queued_for_deletion():
				continue
			var k := c.get_class()
			out[k] = int(out.get(k, 0)) + 1
			stack.append(c)
	return out


## 原生一侧: 录流器的单位表 / 节点表(只借它的 idx / id 做对应, 量的是真节点本身)。
static func snap_native(rec: StreamRecorder) -> Dictionary:
	var ub := {}
	for i in range(rec._uk.size()):
		var u = rec._uk[i]
		for v in (rec.battle._units as Array):
			if is_same(v, u):
				ub[i] = u
				break
	var nb := {}
	var own := {}
	for t in rec._tn:
		nb[(t as StreamRecorder.TN).id] = (t as StreamRecorder.TN).n
		if (t as StreamRecorder.TN).unit != null:
			own[(t as StreamRecorder.TN).id] = "%d %s" % [(t as StreamRecorder.TN).uidx, (t as StreamRecorder.TN).ukey]
	var out := {"units": _units_of(ub), "nodes": _nodes_of(nb), "census": census(rec.battle._world), "own": own}
	if OS.get_environment("S2_DIAG") != "":
		out["loose"] = loose(rec.battle._world, nb)
	return out


## 播放一侧
static func snap_player(p: StreamPlayer) -> Dictionary:
	var out := {"units": _units_of(p.units), "nodes": _nodes_of(p.mirror.nodes), "census": census(p.battle._world)}
	if OS.get_environment("S2_DIAG") != "":
		out["loose"] = loose(p.battle._world, p.mirror.nodes)
	return out


## 诊断: `_world` 子树里不在镜像表里的节点(地图 / 渲染步造的), 「类名 名字 ← 父类名」计数。
static func loose(world: Node, mirrored: Dictionary) -> Dictionary:
	var ids := {}
	for k in mirrored:
		var n = mirrored[k]
		if n != null and is_instance_valid(n):
			ids[(n as Object).get_instance_id()] = true
	var out := {}
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if c.is_queued_for_deletion():
				continue
			stack.append(c)
			if ids.has(c.get_instance_id()):
				continue
			var nm := str(c.name)
			if nm.begins_with("@"):
				nm = "@"
			var tx := ""
			if c is Sprite3D and (c as Sprite3D).texture != null:
				tx = str((c as Sprite3D).texture.resource_path).get_file()
			elif c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				tx = (c as MeshInstance3D).mesh.get_class()
			var k2 := "%s %s [%s %s] <- %s %s" % [c.get_class(), nm, tx, str(c.get_meta_list()), n.get_class(), str(n.name).left(20)]
			out[k2] = int(out.get(k2, 0)) + 1
	return out


## 跑一局裁判局(录流, 块留在内存), 在 `want(录流器已录步数)` 为真的步拍原生快照(键是 sim 步号)。返回 {res, snaps{步号: 快照}, floats{步号: [文本]}, state}。
static func record_referee(host: Node, job: Dictionary, want: Callable) -> Dictionary:
	var snaps := {}
	var floats := {}
	var cur := [-1]
	var hook := func(bt) -> void:
		bt.ready.connect(func() -> void:
			var rec: StreamRecorder = bt._replay.stream
			rec.on_sampled = func(s: int) -> void:
				cur[0] = s
				if want.call(rec._step_n):
					snaps[s] = snap_native(rec)
			, CONNECT_ONE_SHOT)
	var fl := _float_hook(floats, cur)
	host.get_tree().node_added.connect(fl)
	var res: Dictionary = await RefereeRunner.run(host, job, hook, {"keep": true})
	host.get_tree().node_added.disconnect(fl)
	var st := {}
	var b64 := str(res.get("replay_b64", ""))
	if b64 != "":
		var r: Dictionary = ReplayRecorder.decode(Marshalls.base64_to_raw(b64))
		st = r.get("state", {})
	return {"res": res, "snaps": snaps, "floats": floats, "state": st, "seed": RefereeJob.seed_of(job)}


## 飘字普查: `_ui_layer` 下新加的 Label(飘字的数字本体), 记 [当前步, 文本]。两边同一个口径。
static func _float_hook(floats: Dictionary, cur: Array) -> Callable:
	return func(n: Node) -> void:
		if not (n is Label):
			return
		var p := n.get_parent()
		if p == null:
			return
		if not (p is CanvasLayer or (p is HBoxContainer and p.get_parent() is CanvasLayer)):
			return
		var s: int = int(cur[0])
		if not floats.has(s):
			floats[s] = []
		(floats[s] as Array).append(str((n as Label).text))


## 建一个播放模式的战斗场(手机侧)。`state` = 录像里的 GameState 那几个键(换路幕布读阵容); 调用方负责事后还原 GameState。
static func make_player_battle(host: Node, chunks: Array, meta: Dictionary, seed: int, state: Dictionary, limit: int = -1) -> Node:
	var src := StreamSource.Mem.new(chunks, meta)
	src.limit = limit
	if not state.is_empty():
		ReplayRecorder.apply_state(state)
	StreamPlayer.pending = {"source": src, "seed": seed}
	var b: Node = (load("res://scenes/RealtimeBattle3D.tscn") as PackedScene).instantiate()
	host.add_child(b)
	StreamPlayer.pending = {}
	return b
