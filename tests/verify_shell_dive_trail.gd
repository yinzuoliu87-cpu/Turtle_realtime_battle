extends Node
## verify_shell_dive_trail.gd — 龟壳「暗影俯冲」改成库奇 W 式「匀速飞 + 沿途火道」(用户 2026-11-08)的结算门禁。
##
## 用户 11-08:「龟壳暗影冲刺…参考英雄联盟的库奇的 W 技能，它并不是瞬移，而是它是慢慢飞到另外一个地方，
##   然后在它飞行之间的那个飞行的那个过道，留下一条长达多少多少码的这个燃烧火道，持续造成灼烧伤害。」
## 判据全量在单位字典的结算结果上(位置 / 血量 / 减速到期时刻 / 灼烧层数), 不数我插的调用:
##   ① 不是瞬移: 第 1 步只挪了一点、0.4 秒在半路(±15 码)、落地在 路程 / DIVE_SPEED 秒(±2 步)
##   ② 飞过谁才打谁: 路径上的敌人掉血那一步 = 龟壳飞到离它 TRAIL_WIDTH/2 以内那一步(不是出手那一帧); 近的先挨
##   ③ 火道铺满整条路: 起点附近、落点附近两名(在宽度内)都被灼烧 + 减速; 宽度外那名、路线外那名始终没事
##   ④ 火道上每一处烧 BURN_TICKS 跳(= BURN_LIFE 秒), 先落先灭(起点那名最后一跳早于落点那名)
##   ⑤ 龟壳半路死了: 火道停在它死的地方 —— 死之前飞过的那名照烧, 落点那名一跳都没有; 龟壳不再往前挪
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shell_dive_trail.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const HZ := 60.0                   # 确定性模式: 每帧恰一步, 一步 1/60 秒
const STEPS := 420                 # 7 秒: 飞 0.8 + 每一处烧 5 秒 + 余量

var _n := 0
var _fail := 0
var _s = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _unit(id: String, side: String, p: Vector2, knock_immune: bool) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, p)
	u["no_basic"] = true
	u["no_move"] = true
	u["energy"] = 0.0
	if side == "right":
		u["maxHp"] = 500000.0
		u["hp"] = 500000.0
	if knock_immune:
		u["_knock_immune"] = true   # 钉在原地量火道(被撞那一下照样掉血, 只是不飞走)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 龟壳暗影俯冲: 匀速飞 + 沿途火道 ===")
	OS.set_environment("TURTLE_SEED", "424242")   # 固定地图 / 障碍 / 随机流(被撞飞的那名落在哪不跟地图抽签走)
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true
	for _i in range(30):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	await _run_full()
	await _run_killed()
	_done()


## 摆一局: 龟壳在左, 路线朝 +x。返回 {sh, start, dest, L, dir, ...各敌人}。
func _setup() -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var start: Vector2 = c + Vector2(-320, 0)
	var sh := _unit("shell", "left", start, false)
	var buddy := _unit("basic", "left", c + Vector2(-320, 380), false)   # 龟壳死了左边还有人, 对局不结束
	var tgt := _unit("basic", "right", c + Vector2(240, 0), true)        # 目标(定方向)
	var dir: Vector2 = DetMath.norm(tgt["pos"] - start)
	var dest: Vector2 = ArenaShape.clamp_in(start + dir * ShellSystem.DIVE_RANGE, _s.ARENA)
	var L: float = DetMath.dist(start, dest)
	var hw: float = ShellSystem.TRAIL_WIDTH * 0.5
	var nrm := Vector2(-dir.y, dir.x)
	var d := {"sh": sh, "start": start, "dest": dest, "L": L, "dir": dir, "hw": hw, "tgt": tgt,
		"e_hit": _unit("basic", "right", start + dir * 200.0, false),                       # 路线正中, 会被撞飞
		"b0": _unit("basic", "right", start + dir * 30.0 + nrm * (hw - 15.0), true),         # 起点附近、宽度内
		"b_mid": _unit("basic", "right", start + dir * 150.0 - nrm * (hw - 15.0), true),     # 前段、宽度内
		"b_end": _unit("basic", "right", start + dir * (L - 20.0) - nrm * (hw - 25.0), true),  # 落点附近、宽度内
		"b_out": _unit("basic", "right", start + dir * 300.0 + nrm * (hw + 25.0), true),     # 宽度外 25 码
		"b_far": _unit("basic", "right", start + dir * 300.0 + nrm * 260.0, true)}           # 离路线 260 码
	_s._units.clear()
	_s._units.append_array([sh, buddy, tgt, d["e_hit"], d["b0"], d["b_mid"], d["b_end"], d["b_out"], d["b_far"]])
	_s._over = false
	_s._battle_rng.seed = 424242
	seed(20261108)
	return d


## 跑 STEPS 步, 记每名敌人: 第一次掉血那一步、每次减速被刷新那一步、灼烧层数最大值; 龟壳每步位置。
## kill_at >= 0: 那一步把龟壳打死。
func _play(d: Dictionary, kill_at: int) -> Dictionary:
	var keys := ["tgt", "e_hit", "b0", "b_mid", "b_end", "b_out", "b_far"]
	var rec := {}
	for k in keys:
		rec[k] = {"hp0": float(d[k]["hp"]), "hit": -1, "slow": [], "dbf": float(d[k].get("spd_dbf_until", 0.0)), "burn": 0}
	var path: Array = []
	_s._do_skill(d["sh"], d["tgt"], "shellShadow")
	for step in range(STEPS):
		for u in _s._units:
			u["energy"] = 0.0
		if step == kill_at:
			_s._damage._apply_damage(d["sh"], 1000000000, Color.WHITE)
		await get_tree().process_frame
		path.append(d["sh"]["pos"])
		for k in keys:
			var u: Dictionary = d[k]
			var r: Dictionary = rec[k]
			if int(r["hit"]) < 0 and float(u["hp"]) < float(r["hp0"]) - 0.5:
				r["hit"] = step
			var du: float = float(u.get("spd_dbf_until", 0.0))
			if du > float(r["dbf"]) + 0.0001:
				(r["slow"] as Array).append(step)
				r["dbf"] = du
			r["burn"] = maxi(int(r["burn"]), int((u["dot_stacks"] as Dictionary).get("burn", 0)))
	return {"rec": rec, "path": path}


func _run_full() -> void:
	print("— 完整飞完 —")
	var d := _setup()
	var start: Vector2 = d["start"]
	var dir: Vector2 = d["dir"]
	var L: float = d["L"]
	var out: Dictionary = await _play(d, -1)
	var path: Array = out["path"]
	var rec: Dictionary = out["rec"]
	print("  路程 %.0f 码 · 速度 %.0f 码/秒 · 火道宽 %.0f 码 · 每一处 %.1f 秒 / %d 跳" % [L, ShellSystem.DIVE_SPEED, ShellSystem.TRAIL_WIDTH, ShellSystem.BURN_LIFE, ShellSystem.BURN_TICKS])

	## ① 不是瞬移
	var land := -1
	for i in range(path.size()):
		if DetMath.dist(path[i], d["dest"]) < 1.0:
			land = i
			break
	var want_land: int = int(round(L / ShellSystem.DIVE_SPEED * HZ))
	var s1: float = DetMath.dot((path[0] as Vector2) - start, dir)
	var half_i: int = int(round(0.4 * HZ)) - 1
	var s_half: float = DetMath.dot((path[half_i] as Vector2) - start, dir)
	_ok("★分母: 路程够长(≥ 500 码, 场地没把落点夹短)", L >= 500.0, "%.0f 码" % L)
	_ok("★★① 不是瞬移: 第 1 步只挪了 ≤ 30 码", s1 > 0.0 and s1 <= 30.0, "%.1f 码" % s1)
	_ok("★★① 0.4 秒时在半路(按匀速应在 %.0f 码, ±15)" % (ShellSystem.DIVE_SPEED * 0.4), absf(s_half - ShellSystem.DIVE_SPEED * 0.4) <= 15.0, "%.1f 码" % s_half)
	_ok("★★① 落地在第 %d 步左右(路程 / 速度, ±2 步)" % want_land, land >= 0 and absi(land - want_land) <= 2, "第 %d 步" % land)

	## ② 飞过谁才打谁
	var eh: Dictionary = rec["e_hit"]
	var be: Dictionary = rec["b_end"]
	## 龟壳飞到离 e_hit 不超过半宽那一刻: 路程 200 - hw
	var want_eh: int = int(round((200.0 - d["hw"]) / ShellSystem.DIVE_SPEED * HZ))
	_ok("★★② 路线中段那名在龟壳飞到身边那一步才掉血(约第 %d 步, ±3), 不是出手那一帧" % want_eh,
		int(eh["hit"]) >= 3 and absi(int(eh["hit"]) - want_eh) <= 3, "第 %d 步" % int(eh["hit"]))
	_ok("★★② 近的先挨、远的后挨(中段早于落点那名)", int(eh["hit"]) >= 0 and int(be["hit"]) > int(eh["hit"]) + 20,
		"中段第 %d 步 / 落点第 %d 步" % [int(eh["hit"]), int(be["hit"])])
	_ok("★② 被撞的那名被击退(离开了原位)", DetMath.dist(d["e_hit"]["pos"], start + dir * 200.0) > 20.0,
		"离原位 %.0f 码" % DetMath.dist(d["e_hit"]["pos"], start + dir * 200.0))

	## ③ 火道铺满整条路 / 宽度外没事
	var b0: Dictionary = rec["b0"]
	_ok("★★③ 起点附近(宽度内)那名被灼烧 + 减速", int(b0["burn"]) > 0 and (b0["slow"] as Array).size() > 0,
		"灼烧最多 %d 层 · 减速 %d 次" % [int(b0["burn"]), (b0["slow"] as Array).size()])
	_ok("★★③ 落点附近(宽度内)那名被灼烧 + 减速", int(be["burn"]) > 0 and (be["slow"] as Array).size() > 0,
		"灼烧最多 %d 层 · 减速 %d 次" % [int(be["burn"]), (be["slow"] as Array).size()])
	for k in ["b_out", "b_far"]:
		var r: Dictionary = rec[k]
		_ok("★③ %s(路线外)始终没掉血、没减速、没灼烧" % k, int(r["hit"]) < 0 and (r["slow"] as Array).is_empty() and int(r["burn"]) == 0,
			"掉血第 %d 步 · 减速 %d 次 · 灼烧 %d 层" % [int(r["hit"]), (r["slow"] as Array).size(), int(r["burn"])])

	## ④ 每一处烧 BURN_TICKS 跳, 先落先灭
	var n0: int = (b0["slow"] as Array).size()
	var ne: int = (be["slow"] as Array).size()
	_ok("★★④ 起点那名、落点那名各被火道烧 %d 跳(= %.1f 秒)" % [ShellSystem.BURN_TICKS, ShellSystem.BURN_LIFE],
		n0 == ShellSystem.BURN_TICKS and ne == ShellSystem.BURN_TICKS, "起点 %d 跳 %s / 落点 %d 跳 %s" % [n0, str(b0["slow"]), ne, str(be["slow"])])
	_ok("★★④ 先落先灭: 起点那名最后一跳早于落点那名", n0 > 0 and ne > 0 and int(b0["slow"][-1]) < int(be["slow"][-1]),
		"起点最后第 %d 步 / 落点最后第 %d 步" % [int(b0["slow"][-1]) if n0 > 0 else -1, int(be["slow"][-1]) if ne > 0 else -1])
	_ok("★④ 落点那名第一跳在龟壳飞到之后(不早于第 %d 步)" % (want_land - 2), ne > 0 and int(be["slow"][0]) >= want_land - 2,
		"第 %d 步" % (int(be["slow"][0]) if ne > 0 else -1))


func _run_killed() -> void:
	print("— 龟壳半路死了 —")
	var d := _setup()
	var kill_at: int = int(round(0.35 * HZ))          # 0.35 秒: 约飞到 262 码处
	var out: Dictionary = await _play(d, kill_at)
	var path: Array = out["path"]
	var rec: Dictionary = out["rec"]
	var start: Vector2 = d["start"]
	var dir: Vector2 = d["dir"]
	var s_dead: float = DetMath.dot((path[kill_at] as Vector2) - start, dir)
	var s_last: float = DetMath.dot((path[-1] as Vector2) - start, dir)
	_ok("★分母: 龟壳真死了", not d["sh"].get("alive", true))
	_ok("★⑤ 龟壳死后不再往前挪(死的那一步 %.0f 码 · 最后 %.0f 码)" % [s_dead, s_last], absf(s_last - s_dead) <= 15.0 and s_dead < 330.0)
	var bm: Dictionary = rec["b_mid"]
	var be: Dictionary = rec["b_end"]
	_ok("★★⑤ 死之前飞过的那名(150 码处)照烧满 %d 跳" % ShellSystem.BURN_TICKS, (bm["slow"] as Array).size() == ShellSystem.BURN_TICKS,
		"%d 跳" % (bm["slow"] as Array).size())
	_ok("★★⑤ 火道停在龟壳死的地方: 落点那名一跳都没有、也没被撞", (be["slow"] as Array).is_empty() and int(be["burn"]) == 0 and int(be["hit"]) < 0,
		"减速 %d 次 · 灼烧 %d 层 · 掉血第 %d 步" % [(be["slow"] as Array).size(), int(be["burn"]), int(be["hit"])])


func _done() -> void:
	if _n < 18:
		print("  [FAIL] ★分母: 断言只有 %d 条(<18) —— 有用例没跑到" % _n)
		_fail += 1
	print("—— %d 项, %d 失败 ——" % [_n, _fail])
	if _fail == 0 and _n > 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
