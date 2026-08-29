extends Node
## 探针: 让龟壳逐个释放【当前被排除的 57 个技能】, 量它到底会不会"污染自身状态"。
##
## 用户 2026-08-28:「有用吗」→ 我的回答: 数源码没用(今晚已错四次), **试才有用**。
## 那条白名单规则的顾虑原文是「否则从龟壳放会污染自身状态」——
## 这件事可以直接跑出来, 不用猜。
##
## 每个技能一套【全新的龟壳 + 全新的敌人】, 互不干扰:
##   · 放之前记下龟壳身上所有键值 + 敌人总血 + 场上单位数
##   · 走真入口 battle._do_skill(shell, tgt, stype)
##   · 等若干帧让延时/弹道结算
##   · 放之后再记一次, 报: 新增了哪些键 / 改了哪些键 / 打出多少伤害 / 多出几个单位
##   · 每个技能前后打标记行, 引擎报错落在哪两个标记之间就归谁
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_copy_pollution.tscn --quit-after 60000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")

var _s = null

## 这些键是【放技能本来就会变的】, 不算污染 —— 报告里单独归类, 不混进"新增键"。
const EXPECTED := ["skill_cd", "skill_gcd_until", "energy", "en_fill", "_last_skill",
	"anim_t", "anim_state", "flash_t", "flash_col", "_atk_voff", "_slam_voff", "last_x"]


func _snapshot(u: Dictionary) -> Dictionary:
	var out := {}
	for k in u.keys():
		var key := str(k)
		var v = u[k]
		## 只记标量与小结构 —— 单位字典之间互相引用成环, 深拷会卡死(CLAUDE.md §3.2)
		if v is bool or v is int or v is float or v is String:
			out[key] = v
		elif v is Vector2:
			out[key] = "V2"
		elif v is Array:
			out[key] = "Array(%d)" % (v as Array).size()
		elif v is Dictionary:
			out[key] = "Dict(%d)" % (v as Dictionary).size()
		else:
			out[key] = "obj"
	return out


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

	## 取【当前不在白名单、但在 _do_skill 分派表里】的技能 —— 就是"被排除的那批"
	var todo: Array = []
	for k in _s._IMPL_SKILLS.keys():
		var t := str(k)
		if not CopyRules.can_copy(t, _s._IMPL_SKILLS):
			todo.append(t)
	todo.sort()
	print("PROBE_TOTAL %d" % todo.size())

	## ★★对照组: 同一套场景跑两遍 —— 一遍放技能, 一遍【什么都不放】。
	##   两边都等同样长的时间, 差出来的才是技能干的。
	##   (第一版没有对照组 ⇒ 每个技能都报出同一批"新增键"(_auraEnergy/_awaken_t0/...),
	##    那是龟壳自己被动 tick 出来的, 我量的是"时间流逝"而不是"技能污染"。)
	for stype in todo:
		print("PROBE_BEGIN %s" % stype)
		var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
		## 全新龟壳 + 3 个全新敌人 —— 每个技能互不干扰
		var sh: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
		sh["atk"] = 120.0
		sh["maxHp"] = 6000.0
		sh["hp"] = 3000.0
		sh["no_basic"] = true
		sh["no_move"] = true
		sh["energy"] = 999.0
		var foes: Array = []
		for i in range(3):
			var e: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(90.0 + 55.0 * float(i), 0))
			e["maxHp"] = 5000.0
			e["hp"] = 5000.0        # ★正常血量 —— 用 1e7 会让"%最大生命"类技能算出 240 万这种假数字
			e["no_basic"] = true
			e["no_move"] = true
			foes.append(e)
		_s._units.clear()
		_s._units.append(sh)
		_s._units.append_array(foes)
		_s._edit_mode = false
		_s._over = false

		var hp0: float = 0.0
		for e in foes:
			hp0 += float(e["hp"])
		var n0: int = _s._units.size()

		_s._do_skill(sh, foes[0], stype)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 900:
			await get_tree().process_frame
		var cast_state := _snapshot(sh)
		var hp1: float = 0.0
		for e in foes:
			hp1 += float(e["hp"])
		var n1: int = _s._units.size()

		## ── 对照组: 一模一样地再建一次, 但【不放技能】, 等同样久 ──
		var sh2: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-140, 0))
		sh2["atk"] = 120.0
		sh2["maxHp"] = 6000.0
		sh2["hp"] = 3000.0
		sh2["no_basic"] = true
		sh2["no_move"] = true
		sh2["energy"] = 999.0
		var foes2: Array = []
		for i in range(3):
			var e2: Dictionary = _s._spawn._make_unit("basic", "right", c + Vector2(90.0 + 55.0 * float(i), 0))
			e2["maxHp"] = 5000.0
			e2["hp"] = 5000.0
			e2["no_basic"] = true
			e2["no_move"] = true
			foes2.append(e2)
		_s._units.clear()
		_s._units.append(sh2)
		_s._units.append_array(foes2)
		var m0: int = _s._units.size()
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 900:
			await get_tree().process_frame
		var idle_state := _snapshot(sh2)
		var m1: int = _s._units.size()

		## ── 差分: 只有【放了技能才有、不放没有】的才算这个技能干的 ──
		var added: Array = []
		var changed: Array = []
		for k in cast_state.keys():
			var key := str(k)
			if key in EXPECTED:
				continue
			if not idle_state.has(key):
				added.append(key)                                   # 对照组没有 = 技能加的
			elif str(idle_state[key]) != str(cast_state[key]):
				changed.append(key)                                 # 两边都有但值不同 = 技能改的
		added.sort()
		changed.sort()
		print("PROBE_RESULT %s | dmg=%d | 技能加的键=%s | 技能改的键=%s | 召唤 %d(对照 %d)" % [
			stype, int(hp0 - hp1),
			("无" if added.is_empty() else ",".join(PackedStringArray(added))),
			("无" if changed.is_empty() else ",".join(PackedStringArray(changed))),
			n1 - n0, m1 - m0])
		print("PROBE_END %s" % stype)

	print("PROBE_DONE")
	_s.queue_free()
	get_tree().quit(0)
