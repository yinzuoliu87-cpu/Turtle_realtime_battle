extends Node
## 探针(11-08): ⑯ 赛博齐射 —— 种子甲 / 乙 / 甲 三遍, 分清「全局 RNG」还是「上一遍残留状态」, 并打进齐射时的 _t
const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")


func _ready() -> void:
	await get_tree().process_frame
	var r1: Array = await _salvo_run(11)
	var r2: Array = await _salvo_run(97)
	var r3: Array = await _salvo_run(11)
	var r4: Array = await _salvo_run(97)
	print("PROBE 11=%s | 97=%s | 11=%s | 97=%s" % [r1[0], r2[0], r3[0], r4[0]])
	get_tree().quit(0)


func _salvo_run(gseed: int) -> Array:
	RB.DEBUG_EDIT = false          # ★上面的场景把它置真(调试场) ⇒ 不复位的话本局处于编辑态, _fight_on 恒假, 齐射永不结算
	var s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	## ★2026-10-12: 这 40 帧原来按真实 delta 推战斗钟 ⇒ 进齐射时 `_t` 随机器快慢不同
	##   (探针 tests/probes/_probe_salvo_flaky.gd: 本机 6 遍全是 12,0,18,12 · --max-fps 15 下 6 遍全是 12,0,12,18,
	##   正是 0.19.566 CI 红的那一份) ⇒ det 模式让每帧恰一步, 与帧率无关。
	s._deterministic = true
	add_child(s)
	for _i in range(40):
		await get_tree().process_frame
	s._units.clear()
	s._trainer_sys.clear_flights()
	var ar: Rect2 = s.ARENA
	var ctr: Vector2 = ar.position + ar.size * 0.5
	var cyber: Dictionary = _salvo_unit(s, "left", ctr)
	cyber["drone_n"] = 6
	cyber["_drones"] = []
	for _k in range(6):
		var sp := Sprite3D.new()
		s._world.add_child(sp)
		cyber["_drones"].append({"spr": sp})
	s._units.append(cyber)
	var foes: Array = []
	for k in range(8):
		var fx: float = ar.position.x + ar.size.x * (0.15 + 0.1 * float(k))
		var fy: float = ar.position.y + ar.size.y * (0.2 + 0.6 * float(k % 3) / 2.0)
		var f: Dictionary = _salvo_unit(s, "right", Vector2(fx, fy))
		foes.append(f)
		s._units.append(f)
	s._dbg_salvo_picks.clear()
	seed(gseed)
	s._battle_rng.seed = 20261010
	s.set_process(false)          # ★步数由我喂: 一次一个 SIM_DT ⇒ 两遍走的 sim 步数逐个相同(不吃机器快慢)
	s._cyber_sys._cyber_assemble_mech(cyber)
	for w in range(150):          # 2.5 游戏秒: 齐射在 1.35 秒选靶 + 0.45 秒蓄力光球(挂 sim 钟)末尾结算
		s._process(s.SIM_DT)
		if w % 10 == 0:
			await get_tree().process_frame
	var parts: Array = []
	var tot := 0.0
	for f in foes:
		var lost: float = float(f["maxHp"]) - float(f["hp"])
		tot += lost
		parts.append("%.0f" % lost)
	print("  [量] ⑯ 齐射那一遍: dl_state=%s edit=%s over=%s 选靶=%d 承伤=%s" % [str(s._dl_state), str(s._edit_mode), str(s._over), s._dbg_salvo_picks.size(), ",".join(parts)])
	print("  [量] 齐射开算时 _t=%.4f 场上单位 %d 待结算 %d 钩子 %d" % [float(s._t), s._units.size(), s._pending_shots.size(), s._trainer_sys._flights.size()])
	var out := [",".join(parts), s._dbg_salvo_picks.size(), tot]
	s.queue_free()
	for _i in range(4):
		await get_tree().process_frame
	return out


func _salvo_unit(s, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit("green", side, pos)
	u["maxHp"] = 30000.0; u["hp"] = 30000.0
	u["shield"] = 0.0; u["flat_dr"] = 0.0
	u["_home_pos"] = pos
	return u


