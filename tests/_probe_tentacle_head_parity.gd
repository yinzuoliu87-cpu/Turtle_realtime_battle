extends Node
## _probe_tentacle_head_parity.gd — 「动作 100% 用 8 月那版」的逐帧对账(探针; 用户 2026-10-31 要求「新旧中心线逐点误差 < 1e-4」)。
## 现行 TentacleVfx(只换了渲染) 与 HEAD 版 tentacle_vfx.gd 同场同帧驱动: 同样的 dt 序列(含不规则帧长)、同样的拍击 / 点刺 / 搬家,
##   每帧比两边 `_tents[k]["center"](链式模拟这一帧的节点, 未量化)`。HEAD 版源码不进仓库: 由 TENT_HEAD_SRC 指向一份
##   `git show HEAD:scripts/systems/equip/tentacle_vfx.gd` 的导出文件, 运行时去掉 class_name 动态编译。
## 跑法: TENT_HEAD_SRC=<路径> bash godot-quiet.sh res://tests/_probe_tentacle_head_parity.tscn --quit-after 30000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	await get_tree().process_frame
	await get_tree().process_frame
	var path: String = OS.get_environment("TENT_HEAD_SRC")
	var src: String = FileAccess.get_file_as_string(path)
	if src.is_empty():
		print("[parity] FAIL 读不到 HEAD 源码: ", path)
		get_tree().quit(1)
		return
	src = src.replace("class_name TentacleVfx\n", "")
	## HEAD 之后 VfxTex.tag 去掉了第 5 个参数(录流节拍, 第二路删的); 只在建网格那两行用到, 与中心线无关
	src = src.replace(", SRC, sev)", ", SRC)")
	var gs := GDScript.new()
	gs.source_code = src
	if gs.reload() != OK:
		print("[parity] FAIL HEAD 源码编译失败")
		get_tree().quit(1)
		return
	var ov = gs.new(_s)
	var nv = _s._tentacle_vfx
	for v in [nv, ov]:
		v.clear()
		v.preview_lock = true
		v.ensure_forced("left", 2)
		v.ensure_forced("right", 2)
	var r0: Vector2 = nv.root_pos("left", 0)
	var aim_a := r0 + Vector2(1.0, -0.5).normalized() * 320.0
	var aim_b := r0 + Vector2(0.3, 1.0).normalized() * 280.0
	var dts := [1.0 / 60.0, 1.0 / 60.0, 1.0 / 52.0, 1.0 / 60.0, 1.0 / 71.0, 1.0 / 60.0, 1.0 / 45.0]
	var worst := 0.0
	var worst_at := ""
	var frames := 0
	var pts_n := 0
	var st_mis := 0
	for f in range(1500):
		var dt: float = dts[f % dts.size()]
		_s._t += dt
		## 同一帧对两边下同样的指令
		for v in [nv, ov]:
			if f == 260:
				v.strike("left", 0, aim_a, 1.0)
				v.strike("right", 1, aim_b, 1.0)
			if f == 520:
				v.strike("left", 1, aim_b, 0.25)
			if f == 700:
				v.relocate("left", 0, r0 + Vector2(200.0, 60.0))
			if f == 1000:
				v.strike("left", 0, aim_b, 1.0)
				v.strike("left", 1, aim_a, 1.0)
		nv.tick(dt)
		ov.tick(dt)
		for k in nv._tents:
			if not ov._tents.has(k):
				st_mis += 1
				continue
			var a: Dictionary = nv._tents[k]
			var b: Dictionary = ov._tents[k]
			if int(a["state"]) != int(b["state"]):
				st_mis += 1
			var ca: PackedVector3Array = a.get("center", PackedVector3Array())
			var cb: PackedVector3Array = b.get("center", PackedVector3Array())
			if ca.size() != cb.size():
				st_mis += 1
				continue
			for i in range(ca.size()):
				var d: float = ca[i].distance_to(cb[i])
				pts_n += 1
				if d > worst:
					worst = d
					worst_at = "帧 %d %s 点 %d 状态 %d ts %.3f" % [f, k, i, int(a["state"]), float(a["ts"])]
		frames += 1
	print("[parity] 对账 %d 帧 · %d 个点 · 状态 / 点数不一致 %d 次 · 最大逐点误差 %.9f m (%s)" % [frames, pts_n, st_mis, worst, worst_at])
	var ok: bool = frames > 1000 and pts_n > 100000 and st_mis == 0 and worst < 1e-4
	print("[parity] ", "ALL PASS — 中心线与 HEAD 逐帧逐点一致" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
