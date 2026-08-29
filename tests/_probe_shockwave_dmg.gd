extends Node
## 探针: 龟壳被动【冲击波】到底吃不吃护甲, 以及那个 600→610 的反常是什么。
##
## 用户 2026-08-27:「肯定是要真物理啊, 物理伤害为啥不吃护甲啊」。
##
## ★方案书里记着一条我【没隔离出来】的反常: 同一发 500 打两个"只差护甲"的靶子,
##   0 护甲扣 600、500 护甲扣 **610**(护甲越高扣得越多)。
##   那次的靶子很可能不只差护甲(稀有度不同 ⇒ 小龟·不屈 按目标稀有度增伤),
##   但**我没证据**, 所以这次把靶子造成【除了 def 之外逐字段相同】, 一次问清楚。
##
## 判据落在**真实扣血**(hp 差), 不是我算的期望值。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_shockwave_dmg.tscn --quit-after 20000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame

	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh: Dictionary = _s._spawn._make_unit("shell", "left", c)
	sh["no_basic"] = true
	sh["no_move"] = true
	sh["crit"] = 0.0                       # ★关掉暴击 —— 否则每次跑出的数不一样, 归因不了
	sh["damage_amp"] = 0.0
	sh["dmg_out_mult"] = 1.0
	print("SWP 施放者 id=%s rarity=%s crit=%.2f amp=%.2f"
		% [str(sh.get("id", "")), str(sh.get("rarity", "")), float(sh.get("crit", 0.0)),
			float(sh.get("damage_amp", 0.0))])

	## ★三个靶子【除了 def 之外逐字段相同】—— 连稀有度都写死
	##   (小龟·不屈按【目标稀有度】增伤 0.20~0.34, 稀有度不同就会造出"护甲越高伤害越高"的假象)
	## ★护甲取【实测分位数】(tests/_probe_armor_dist.gd 量的 387 次真实挨打):
	##   p10=10 · 中位=14 · p75=34 · p90=52 · 最大=85。
	##   ★不再用我自己编的 def=500 —— 那个值全局根本不存在, 拿它说“削了 93%”是编的不是量的。
	var defs := [10.0, 14.0, 34.0, 52.0, 85.0]
	var foes: Array = []
	for i in range(defs.size()):
		var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(60.0 + 40.0 * float(i), 0))
		e["maxHp"] = 1.0e8
		e["hp"] = 1.0e8
		e["def"] = defs[i]
		e["mr"] = 0.0
		e["rarity"] = "C"                  # ★写死: 三个靶子的稀有度必须相同
		e["damage_reduction"] = 0.0
		e["flat_dr"] = 0.0
		e["shield"] = 0.0
		e["dodge"] = 0.0
		e["dodge_bonus"] = 0.0
		e["no_basic"] = true
		e["no_move"] = true
		foes.append(e)
	_s._units.clear()
	_s._units.append(sh)
	_s._units.append_array(foes)
	_s._edit_mode = false
	_s._over = false

	## 分母: 三个靶子除 def 外真的一样
	var keys_differ: Array = []
	for k in foes[0].keys():
		var key := str(k)
		if key in ["pos", "sprite", "def", "home_pos", "_home_pos", "spawn_pos", "bob_phase"]:
			continue
		var v0 = foes[0][k]
		if v0 is Object or v0 is Dictionary or v0 is Array:
			continue
		for j in [1, 2]:
			if foes[j].has(k) and str(foes[j][k]) != str(v0) and not keys_differ.has(key):
				keys_differ.append(key)
	print("SWP 分母·三靶除 def 外仍不同的字段: %s"
		% ("无" if keys_differ.is_empty() else str(keys_differ)))

	## 把储能拉到一个整数好算的值
	var SE := 1250.0                       # 1250 × RELEASE_DMG_PCT(0.40) = 500 基础伤害
	sh["store_energy"] = SE
	var base: int = int(SE * _s._shell_sys.RELEASE_DMG_PCT)
	print("SWP 储能=%.0f ×%.2f ⇒ 基础伤害=%d" % [SE, _s._shell_sys.RELEASE_DMG_PCT, base])

	var hp0: Array = []
	for e in foes:
		hp0.append(float(e["hp"]))

	_s._shell_sys._shell_spawn_shockwave(sh, base)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3500:        # 冲击波 1.8 秒扩满
		await get_tree().process_frame

	print("SWP ── 结果 ──")
	for i in range(foes.size()):
		var took: float = hp0[i] - float(foes[i]["hp"])
		print("SWP  def=%4d  实扣 %.0f   (基础 %d ⇒ 倍率 %.3f)"
			% [int(defs[i]), took, base, took / maxf(1.0, float(base))])
	print("SWP 飘字类型(命中后): %s" % str(_s._last_dmg_type))
	print("SWP_DONE")
	_s.queue_free()
	get_tree().quit(0)
