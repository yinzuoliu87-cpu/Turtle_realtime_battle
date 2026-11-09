"""龟壳复制上下文第三批(2026-11-09): 预检红 5 项里有 3 项是 copy_ctx_1109b 的写法引起的 ——
  ① 多出口函数「改名 + 同名包装」: 图鉴 status_sources 按函数名核常量(_diamond_roll_impact 的眩晕常量)、
    vfx_discipline_audit 按「函数::属性」记存量(_crystal_spike_line::pixel_size)⇒ 改名 = 存量被当新增、出处找不到。
    ⇒ 撤掉改名: 滚球撞击 / 冲刺斩(各只有一个同文件调用处)在调用处包; 泡泡盾爆裂 / 水晶刺在函数体内包。
  ② 主文件 +11 行 > arch_budget 冻结的 8472 ⇒ 补间的建 / 推收进 ShellSystem.tag_tween / step_tween,
    复制上下文里的龟壳从主文件 var _copy_src 挪成 ShellSystem.copy_src。主文件净增 0 行。
"""
ROOT = "C:/Users/Louis/Documents/GitHub/turtle-realtime-godot/"
SH = "battle._shell_sys"


def edit(rel, pairs):
    p = ROOT + rel
    b = open(p, "rb").read().decode("utf-8")
    crlf = "\r\n" in b
    s = b.replace("\r\n", "\n")
    for a, c in pairs:
        assert s.count(a) == 1, (rel, a[:100], s.count(a))
        s = s.replace(a, c)
    open(p, "wb").write((s.replace("\n", "\r\n") if crlf else s).encode("utf-8"))


edit("scripts/systems/skills/diamond_system.gd", [
    ("""func _diamond_roll_impact(u: Dictionary, cp: Vector2, sf: float) -> void:
	var _ct = u.get("_roll_copy")
	u.erase("_roll_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_diamond_roll_impact_body(u, cp, sf)
	%s.ctx_exit_opt(_ct, _cp)


func _diamond_roll_impact_body(u: Dictionary, cp: Vector2, sf: float) -> void:
""" % (SH, SH), """func _diamond_roll_impact(u: Dictionary, cp: Vector2, sf: float) -> void:
"""),
    ("""		_diamond_roll_impact(u, tgt["pos"], sf)
""", """		var _ct = u.get("_roll_copy")   # 龟壳复制期滚的: 撞击照样按 60%%(ShellSystem.ctx_*)
		u.erase("_roll_copy")
		var _cp: Array = %s.ctx_enter_opt(_ct)
		_diamond_roll_impact(u, tgt["pos"], sf)
		%s.ctx_exit_opt(_ct, _cp)
""" % (SH, SH)),
])

edit("scripts/systems/skills/dice_system.gd", [
    ("""func _dice_dash_hit(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
	var _ct = u.get("_dash_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_dice_dash_hit_body(u, tgt, dir)
	%s.ctx_exit_opt(_ct, _cp)


func _dice_dash_hit_body(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
""" % (SH, SH), """func _dice_dash_hit(u: Dictionary, tgt: Dictionary, dir: Vector2) -> void:
"""),
    ("""		_dice_dash_hit(u, tgt, ddir)
""", """		var _cp: Array = %s.ctx_enter_opt(u.get("_dash_copy"))   # 龟壳复制期冲的: 每段斩照样按 60%%(ShellSystem.ctx_*)
		_dice_dash_hit(u, tgt, ddir)
		%s.ctx_exit_opt(u.get("_dash_copy"), _cp)
""" % (SH, SH)),
])

edit("scripts/systems/skills/bubble_system.gd", [
    ("""func _bubble_shield_burst(ally: Dictionary) -> void:
	var _ct = ally.get("bubble_shield_copy")
	ally.erase("bubble_shield_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_bubble_shield_burst_body(ally)
	%s.ctx_exit_opt(_ct, _cp)


func _bubble_shield_burst_body(ally: Dictionary) -> void:
""" % (SH, SH), """func _bubble_shield_burst(ally: Dictionary) -> void:
"""),
    ("""	battle._burst_depth += 1
""", """	battle._burst_depth += 1
	var _ct = ally.get("bubble_shield_copy")   # 龟壳复制期套的盾: 爆裂照样按 60%%(ShellSystem.ctx_*; 下面到 _burst_depth -= 1 之间没有 return)
	ally.erase("bubble_shield_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
""" % SH),
    ("""	battle._burst_depth -= 1
""", """	%s.ctx_exit_opt(_ct, _cp)
	battle._burst_depth -= 1
""" % SH),
])

edit("scripts/systems/skills/crystal_system.gd", [
    ("""func _crystal_spike_line(u: Dictionary) -> void:
	var _ct = u.get("_bulwark_copy")
	u.erase("_bulwark_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	_crystal_spike_line_body(u)
	%s.ctx_exit_opt(_ct, _cp)   # 刺的延后段(_pending_shots)在这里带上 tag


func _crystal_spike_line_body(u: Dictionary) -> void:   # 照小菊R第三击""" % (SH, SH),
     """func _crystal_spike_line(u: Dictionary) -> void:   # 照小菊R第三击"""),
    ("""	var dirv: Vector2""", """	var _ct = u.get("_bulwark_copy")   # 龟壳复制期开的壁垒: 刺照样按 60%%(ShellSystem.ctx_*; 本函数顶层没有 return, 出口在最后)
	u.erase("_bulwark_copy")
	var _cp: Array = %s.ctx_enter_opt(_ct)
	var dirv: Vector2""" % SH),
    ("""				battle._damage.apply_chill(o, SPIKE_SLOW_MULT, 1.0, SPIKE_SLOW_SEC)
		, "src": u})
""", """				battle._damage.apply_chill(o, SPIKE_SLOW_MULT, 1.0, SPIKE_SLOW_SEC)
		, "src": u})
	%s.ctx_exit_opt(_ct, _cp)   # 刺的延后段(上面排进 _pending_shots 的)在这里带上 tag
""" % SH),
])

edit("scripts/systems/skills/shell_system.gd", [
    ("""var _fx = null           # ShellVfx: 复制 / 暗影俯冲的演出
""", """var _fx = null           # ShellVfx: 复制 / 暗影俯冲的演出
var copy_src = null      # 复制期上下文里的龟壳(只在复制窗口里非空; 见 ctx_capture)
"""),
    ("""	if battle._copy_fx_mult == 1.0 or not (battle._copy_src is Dictionary):
		return null
	return [battle._copy_fx_mult, battle._copy_src]
""", """	if battle._copy_fx_mult == 1.0 or not (copy_src is Dictionary):
		return null
	return [battle._copy_fx_mult, copy_src]
"""),
    ("""	var prev: Array = [battle._copy_fx_mult, battle._copy_src, float(src.get("dmg_out_mult", 1.0)), battle._pending_shots.size()]
	battle._copy_fx_mult = float(tag[0])
	battle._copy_src = src
""", """	var prev: Array = [battle._copy_fx_mult, copy_src, float(src.get("dmg_out_mult", 1.0)), battle._pending_shots.size()]
	battle._copy_fx_mult = float(tag[0])
	copy_src = src
"""),
    ("""	battle._copy_fx_mult = float(prev[0])
	battle._copy_src = prev[1]
""", """	battle._copy_fx_mult = float(prev[0])
	copy_src = prev[1]
"""),
    ("""## 技能自己的状态 / 区域 / 协程用: tag 可以是 null(不在复制期建的 ⇒ 什么都不做)。
""", """## sim 补间(主文件 _reg_tween 建 / _step_sim_tweens 推)跟着复制上下文走: 建在复制窗口里 ⇒ 记下, 推的时候还原。
##   收在这里而不在主文件: 主文件是上帝文件, arch_budget 冻结行数(11-09 第一版在主文件里写了 11 行 ⇒ 超预算)。
func tag_tween(t: Tween) -> void:
	if battle._copy_fx_mult != 1.0:
		var ct = ctx_capture()
		if ct != null:
			t.set_meta("_copy", ct)


func step_tween(t: Tween, dt: float) -> void:
	if t.has_meta("_copy"):
		var ct: Array = t.get_meta("_copy")
		var cp: Array = ctx_enter(ct)
		t.custom_step(dt)
		ctx_exit(ct, cp)
	else:
		t.custom_step(dt)


## 技能自己的状态 / 区域 / 协程用: tag 可以是 null(不在复制期建的 ⇒ 什么都不做)。
"""),
])

edit("scripts/scenes/RealtimeBattle3DScene.gd", [
    ("""var _copy_fx_mult: float = 1.0
var _copy_src = null   # 复制期上下文里的龟壳(ShellSystem.ctx_*; 只在复制窗口里非空)
""", """var _copy_fx_mult: float = 1.0
"""),
    ("""			if tw.has_meta("_copy"):   # 龟壳复制期建的补间: 回调里落地的伤害 / 护盾照样按 60%(ShellSystem.ctx_capture)
				var _ct: Array = tw.get_meta("_copy")
				var _cp: Array = _shell_sys.ctx_enter(_ct)
				tw.custom_step(dt)
				_shell_sys.ctx_exit(_ct, _cp)
			else:
				tw.custom_step(dt)
""", """			_shell_sys.step_tween(tw, dt)   # = tw.custom_step(dt); 龟壳复制期建的补间推的时候还原 60%(ShellSystem.tag_tween)
"""),
    ("""	if _copy_fx_mult != 1.0:
		var _ct = _shell_sys.ctx_capture()
		if _ct != null:
			t.set_meta("_copy", _ct)   # 龟壳复制期: 推这条补间时还原 60%(见 _step_sim_tweens)
	t.pause()""", """	t.pause(); _shell_sys.tag_tween(t)"""),
])

edit("tests/verify_copy_effect.gd", [
    ("""or s._copy_src != null):""", """or s._shell_sys.copy_src != null):"""),
])
print("ok")
