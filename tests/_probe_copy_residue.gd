extends Node
## 探针 v2: 龟壳放完【当前被排除的 56 个技能】之后, **过很久还残留什么状态**。
##
## ★v1(`_probe_copy_pollution.gd`) 量的是"技能改了哪些键"—— 那个问题问错了。
##   放技能本来就会改键(加个 5 秒护盾、给自己 buff), 那不叫污染, 用户原话:
##   「比如虚化, 就是给自己 buff 并造成伤害, **我不明白为什么不能复制**」。
##
## ★真正该问的是:「技能演完之后, 龟壳身上还剩下不该剩的东西吗」。
##   ⇒ 两个时间点各拍一次: 放完 0.9 秒(演出期) 和 放完 6 秒(早该结束了)。
##      6 秒那次还留着的、且【对照组没有】的, 才是残留。
##   ⇒ 而且要区分两类残留:
##      · 会自己过期的(`*_until` 已经小于当前时钟) —— 不算, 它只是键还在
##      · 布尔仍为 true / 数值仍非零 / `*_until` 仍在未来 —— **这才是残留**
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_copy_residue.tscn --quit-after 400000

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const CopyRules := preload("res://scripts/gamedata/copy_rules.gd")

var _s = null

## 放技能本来就会动的账目字段 —— 不算残留(它们是"这一发打了多少伤害"这类记账)。
const BOOKKEEPING := ["skill_cd", "skill_gcd_until", "energy", "en_fill", "_last_skill",
	"anim_t", "anim_state", "anim_action", "flash_t", "flash_col", "_atk_voff", "_slam_voff",
	"last_x", "_dottimer", "_ptimer", "shell_timer", "bob_phase", "_awaken_t0", "_sep_target",
	"dmg_dealt", "_st_dealt", "_st_dealt_by_type", "_st_crit", "_st_heal", "_st_shield",
	"_heal_acc", "_heal_acc_start", "_heal_acc_t", "face_right", "_hbrow_stack"]


## 这个键此刻【还是"开着"的】吗 —— 键存在不算, 值还生效才算。
func _still_on(k: String, v) -> bool:
	if v is bool:
		return v
	if k.ends_with("_until"):
		return (v is float or v is int) and float(v) > _s._t     # 还没到期才算
	if v is float or v is int:
		return absf(float(v)) > 0.0001
	if v is String:
		return str(v) != ""
	if v is Array:
		return not (v as Array).is_empty()
	if v is Dictionary:
		return not (v as Dictionary).is_empty()
	return true


func _live_keys(u: Dictionary) -> Dictionary:
	var out := {}
	for k in u.keys():
		var key := str(k)
		if key in BOOKKEEPING:
			continue
		var v = u[k]
		## 单位字典互相引用成环, 不碰对象类字段(CLAUDE.md §3.2)
		if v is Object:
			continue
		if _still_on(key, v):
			out[key] = str(v) if not (v is Dictionary or v is Array) else "…"
	return out


func _build(pos_off: float) -> Array:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var sh: Dictionary = _s._spawn._make_unit("shell", "left", c + Vector2(-140.0 + pos_off, 0))
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
		e["hp"] = 5000.0
		e["no_basic"] = true
		e["no_move"] = true
		foes.append(e)
	_s._units.clear()
	_s._units.append(sh)
	_s._units.append_array(foes)
	_s._edit_mode = false
	_s._over = false
	return [sh, foes]


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

	var todo: Array = []
	for k in _s._IMPL_SKILLS.keys():
		var t := str(k)
		if not CopyRules.can_copy(t, _s._IMPL_SKILLS):
			todo.append(t)
	todo.sort()
	print("RESIDUE_TOTAL %d" % todo.size())

	for stype in todo:
		print("RESIDUE_BEGIN %s" % stype)
		## ── 放技能 ──
		var a := _build(0.0)
		var sh: Dictionary = a[0]
		var foes: Array = a[1]
		_s._do_skill(sh, foes[0], stype)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 6000:      # ★等 6 秒 —— 演出与常见 buff 时长都该结束了
			await get_tree().process_frame
		var after := _live_keys(sh)

		## ── 对照组: 一模一样但【不放技能】, 等一样久 ──
		var b := _build(0.0)
		var sh2: Dictionary = b[0]
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 6000:
			await get_tree().process_frame
		var idle := _live_keys(sh2)

		var residue: Array = []
		for k in after.keys():
			var key := str(k)
			if not idle.has(key):
				residue.append("%s=%s" % [key, str(after[key])])
			elif str(idle[key]) != str(after[key]):
				residue.append("%s=%s(对照 %s)" % [key, str(after[key]), str(idle[key])])
		residue.sort()
		print("RESIDUE_RESULT %s | 6秒后仍生效的残留 %d 项: %s" % [
			stype, residue.size(),
			("无" if residue.is_empty() else " ; ".join(PackedStringArray(residue)))])
		print("RESIDUE_END %s" % stype)

	print("RESIDUE_DONE")
	_s.queue_free()
	get_tree().quit(0)
