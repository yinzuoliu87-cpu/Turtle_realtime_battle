extends Node
## verify_shell_stealth_look.gd — 龟壳「潜影」被动形态的画面门禁(用户 2026-11-08 晚)。
##
## 用户:「除了主动的…暗影冲刺，还有被动它在暗影形态下，它应该是怎么样的呢？隐形的话，透明的还是怎么样的？这都没设计啊。」
## 修前实测: 进潜影只把立绘 modulate.a 补到 0.4, 渲染步每帧按 _body_tint 重写 modulate ⇒ 第一帧就盖回不透明, 潜影期间画面上什么都没有。
## 判据全量在 _world 里真的出现的精灵 / 龟壳立绘自己的颜色上(打印分母), 不数我插的调用:
##   ① 潜影期间每一帧立绘都是紫色半透明(透明度 0.45~0.7、蓝 > 红、红 ≤ 0.7), 不被盖回白
##   ② 脚下暗影池: 贴地、压在立绘下、帧在转(≥3 种)、跟着龟壳走、不跟高度走
##   ③ 身上暗火: 公告板、帧在转(≥4 种)、跟着龟壳走
##   ④ 进入烟球: 出现一次、6 格都播到、播完收掉
##   ⑤ 吃范围伤害: 仍在潜影、那几帧立绘被闪亮过、之后回到暗紫
##   ⑥ 破隐: 立绘回到不透明原色、暗影池 / 暗火收掉、破隐烟出现一次 5 格都播到
##   ⑦ 死在潜影里: 暗影池 / 暗火收掉
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_shell_stealth_look.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const SVfx := preload("res://scripts/scenes/battle/shell_vfx.gd")

var _n := 0
var _fail := 0
var _s = null
var _trk := {}          # 精灵 iid → {file, first, last, frames{}, ground, prio, pos_last}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _arena_of(p: Vector3) -> Vector2:
	return Vector2(p.x / _s.WS + _s._arena_center.x, p.z / _s.WS + _s._arena_center.y)


func _scan(step: int) -> void:
	for ch in _s._world.get_children():
		if not (ch is Sprite3D):
			continue
		var sp := ch as Sprite3D
		if sp.texture == null or not sp.visible:
			continue
		var f: String = str(sp.texture.resource_path).get_file()
		if not f.begins_with("shell-shade-"):
			continue
		var iid := sp.get_instance_id()
		var r = _trk.get(iid)
		if r == null:
			r = {"file": f, "first": step, "last": step, "frames": {}, "prio": sp.render_priority,
				"ground": sp.billboard == BaseMaterial3D.BILLBOARD_DISABLED and sp.axis == Vector3.AXIS_Y, "node": sp}
			_trk[iid] = r
		r["last"] = step
		r["frames"][sp.frame] = true
		r["pos_last"] = _arena_of(sp.position)
		r["y_last"] = sp.position.y


func _of(file: String) -> Array:
	var out: Array = []
	for iid in _trk:
		if _trk[iid]["file"] == file:
			out.append(_trk[iid])
	return out


func _unit(id: String, side: String, p: Vector2) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, p)
	u["no_basic"] = true
	u["no_move"] = true
	u["energy"] = 0.0
	u["maxHp"] = 500000.0
	u["hp"] = 500000.0
	return u


func _step(n: int, from: int, sh: Dictionary, mods: Array) -> int:
	for k in range(n):
		for u in _s._units:
			u["energy"] = 0.0
		await get_tree().process_frame
		_scan(from + k)
		var spr = sh.get("sprite", null)
		mods.append((spr as Sprite3D).modulate if spr is Sprite3D else Color(0, 0, 0, 0))
	return from + n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== 龟壳潜影形态 ===")
	OS.set_environment("TURTLE_SEED", "424242")
	_s = RB.new()
	add_child(_s)
	_s._deterministic = true
	for _i in range(30):
		await get_tree().process_frame
	OS.set_environment("TURTLE_SEED", "")
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh := _unit("shell", "left", c + Vector2(-200, 0))
	var buddy := _unit("basic", "left", c + Vector2(-200, 300))
	var foe := _unit("basic", "right", c + Vector2(300, 0))
	_s._units.clear()
	_s._units.append_array([sh, buddy, foe])
	_s._over = false
	var spr: Sprite3D = sh["sprite"]
	var mods: Array = []
	var st := 0
	st = await _step(10, st, sh, mods)
	var m0: Color = mods[-1]
	print("  潜影前立绘颜色 %s" % str(m0))

	## 进入
	_s._shell_sys._shell_enter_stealth(sh)
	mods.clear()
	st = await _step(40, st, sh, mods)
	var bad: Array = []
	for i in range(mods.size()):
		var m: Color = mods[i]
		if m.a < 0.45 or m.a > 0.7 or m.b <= m.r or m.r > 0.7:
			bad.append("%d:%s" % [i, str(m)])
	_ok("★★① 潜影 40 帧里每一帧立绘都是紫色半透明(透明度 0.45~0.7、蓝 > 红、红 ≤ 0.7), 不被盖回白", mods.size() == 40 and bad.is_empty(),
		"分母 %d 帧; 不合格 %s" % [mods.size(), str(bad.slice(0, 4))])
	_ok("★分母: 潜影前立绘是不透明原色(量尺对得上)", m0.a > 0.95 and m0.r > 0.9, str(m0))

	var pool := _of("shell-shade-pool.png")
	var wisp := _of("shell-shade-wisp.png")
	var ent := _of("shell-shade-enter.png")
	_ok("★分母: 暗影池 1 个、暗火 1 个、进入烟球 1 个", pool.size() == 1 and wisp.size() == 1 and ent.size() == 1,
		"池 %d / 火 %d / 烟球 %d" % [pool.size(), wisp.size(), ent.size()])
	var body_prio: int = spr.render_priority
	if spr.material_override is Material:
		body_prio = maxi(body_prio, (spr.material_override as Material).render_priority)
	if pool.size() == 1:
		_ok("★★② 暗影池贴地(躺平)、压在立绘下、帧在转(≥3 种)", pool[0]["ground"] and int(pool[0]["prio"]) < body_prio and (pool[0]["frames"] as Dictionary).size() >= 3,
			"躺平 %s / 优先级 %d vs 立绘 %d / 帧 %s" % [str(pool[0]["ground"]), int(pool[0]["prio"]), body_prio, str((pool[0]["frames"] as Dictionary).keys())])
		_ok("★② 暗影池在龟壳脚下(±5 码)", DetMath.dist(pool[0]["pos_last"], sh["pos"]) <= 5.0, "%.1f 码" % DetMath.dist(pool[0]["pos_last"], sh["pos"]))
	if wisp.size() == 1:
		_ok("★★③ 身上暗火是公告板、帧在转(≥4 种)", not wisp[0]["ground"] and (wisp[0]["frames"] as Dictionary).size() >= 4, str((wisp[0]["frames"] as Dictionary).keys()))
	if ent.size() == 1:
		_ok("★④ 进入烟球 6 格都播到、播完收掉(不常驻)", (ent[0]["frames"] as Dictionary).size() == 6 and not is_instance_valid(ent[0]["node"]),
			"格 %s" % str((ent[0]["frames"] as Dictionary).keys()))

	## 跟着走(含被抬高: 池子留在地上, 暗火跟着抬)
	sh["pos"] = (sh["pos"] as Vector2) + Vector2(160, 40)
	sh["height"] = 1.0
	mods.clear()
	st = await _step(3, st, sh, mods)
	if pool.size() == 1 and wisp.size() == 1:
		var y_pool: float = float(pool[0]["y_last"])
		_ok("★★②③ 龟壳挪了 165 码: 暗影池与暗火都跟到脚下(±5 码)", DetMath.dist(pool[0]["pos_last"], sh["pos"]) <= 5.0 and DetMath.dist(wisp[0]["pos_last"], sh["pos"]) <= 5.0,
			"池 %.1f / 火 %.1f 码" % [DetMath.dist(pool[0]["pos_last"], sh["pos"]), DetMath.dist(wisp[0]["pos_last"], sh["pos"])])
		_ok("★② 龟壳离地 1 米时暗影池仍贴地(< 0.2 米)、暗火跟着抬(> 1 米)", y_pool < 0.2 and float(wisp[0]["y_last"]) > 1.0,
			"池 y=%.2f / 火 y=%.2f" % [y_pool, float(wisp[0]["y_last"])])
	sh["height"] = 0.0

	## 吃范围伤害: 不破隐, 闪一下再回暗紫
	_s._damage._apply_damage_from(foe, sh, 80, Color.RED)
	mods.clear()
	st = await _step(30, st, sh, mods)
	var lit := 0
	for m in mods.slice(0, 8):
		if (m as Color).r > 0.6:
			lit += 1
	var back: Color = mods[-1]
	_ok("★★⑤ 吃伤害仍在潜影、前 8 帧里立绘被闪亮过、30 帧后回到暗紫半透明",
		sh.get("shell_stealth", false) and lit > 0 and back.a < 0.7 and back.b > back.r and back.r <= 0.7,
		"潜影 %s · 闪亮 %d 帧 · 最后 %s" % [str(sh.get("shell_stealth", false)), lit, str(back)])

	## 破隐
	_s._shell_sys._shell_break_stealth(sh)
	mods.clear()
	st = await _step(30, st, sh, mods)   # 破隐烟 5 格 / 12 fps = 0.42 秒 = 25 步, 等够 30 步
	var m1: Color = mods[-1]
	var brk := _of("shell-shade-break.png")
	_ok("★★⑥ 破隐后立绘回到不透明原色", m1.a > 0.95 and m1.r > 0.9, str(m1))
	_ok("★★⑥ 破隐后暗影池 / 暗火收掉", pool.size() == 1 and wisp.size() == 1 and not is_instance_valid(pool[0]["node"]) and not is_instance_valid(wisp[0]["node"])
		and not is_instance_valid(sh.get("_shade_pool", null)))
	_ok("★⑥ 破隐烟出现一次、5 格都播到", brk.size() == 1 and (brk[0]["frames"] as Dictionary).size() == 5,
		"%d 个; 格 %s" % [brk.size(), str((brk[0]["frames"] as Dictionary).keys()) if brk.size() > 0 else ""])

	## 死在潜影里
	_s._shell_sys._shell_enter_stealth(sh)
	st = await _step(10, st, sh, mods)
	var pool2 = sh.get("_shade_pool", null)
	var had2: bool = is_instance_valid(pool2)
	_s._damage._apply_damage(sh, 100000000, Color.WHITE)
	st = await _step(10, st, sh, mods)
	_ok("★⑦ 死在潜影里: 暗影池 / 暗火收掉", had2 and not is_instance_valid(pool2) and not sh.get("alive", true),
		"挂上过 %s · 死了 %s" % [str(had2), str(not sh.get("alive", true))])
	_done()


func _done() -> void:
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有用例没跑到" % _n)
		_fail += 1
	print("—— %d 项, %d 失败 ——" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS")
	get_tree().quit(0 if _fail == 0 else 1)
