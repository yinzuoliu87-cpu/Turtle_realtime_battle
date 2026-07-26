class_name GhostSystem
extends RefCounted
## 幽灵龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _ghost_leaders() -> Array:
	var gs = battle.get_node_or_null("/root/GameState")
	if gs == null:
		return []
	var dg = gs.get("dual_ghost")
	if not (dg is Dictionary):
		return []
	var ldr = (dg as Dictionary).get("leaders", [])
	if not (ldr is Array):
		return []
	var out: Array = []
	for x in ldr:
		if battle.STATS.has(str(x)):
			out.append(str(x))
		if out.size() >= 3:
			break
	return out

# 幽魂命中: 幽绿灵体怨气(幽环 + 几缕glow飘散)
func _ghost_touch_hit(at2d: Vector2) -> void:
	battle._skill_ring(at2d, Color(0.5, 1.0, 0.75, 0.55), 46.0)
	var gt = VfxTex._make_glow_texture()
	for k in range(5):
		var m = Sprite3D.new()
		m.texture = gt
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.shaded = false; m.transparent = true
		m.modulate = Color(0.55, 1.0, 0.78, 0.85)
		m.pixel_size = (22.0 * battle.WS) / float(maxi(1, gt.get_height()))
		m.position = battle._world_pos(at2d, 1.0)
		battle._world.add_child(m)
		var ang: float = float(k) * TAU / 5.0 + 0.3
		var dest: Vector2 = at2d + Vector2(cos(ang), sin(ang)) * randf_range(28.0, 50.0)
		var mtw = battle._reg_tween()
		mtw.tween_method(_ghost_mote_step.bind(m, at2d, dest), 0.0, 1.0, 0.3)
		mtw.tween_callback(m.queue_free)

func _ghost_mote_step(pf: float, m, from2d: Vector2, dest: Vector2) -> void:
	if not is_instance_valid(m):
		return
	m.position = battle._world_pos(from2d.lerp(dest, pf), lerpf(1.0, 1.5, pf))
	m.modulate.a = lerpf(0.85, 0.0, pf)

# 诅咒·头顶骷髅标记(专属curse-mark·跟随中咒者·咒散/死亡自动消)
# 诅咒·头顶骷髅标记(专属curse-mark·跟随中咒者·咒散/死亡自动消)
func _ghost_curse_mark(u: Dictionary) -> void:
	var m = Sprite3D.new()
	m.texture = load("res://assets/sprites/vfx/curse-mark.png")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.shaded = false; m.transparent = true
	m.modulate = Color(1, 1, 1, 0.92)
	m.pixel_size = (30.0 * battle.WS) / 64.0
	battle._world.add_child(m)
	u["_curse_mark"] = m
	battle._follow_vfx.append({"spr": m, "unit": u, "h": 2.0})

# 诅咒·一缕黑紫怨气升腾
# 诅咒·一缕黑紫怨气升腾
func _ghost_curse_wisp(at2d: Vector2) -> void:
	var m = Sprite3D.new()
	m.texture = VfxTex._make_glow_texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	m.shaded = false; m.transparent = true
	m.modulate = Color(0.55, 0.2, 0.72, 0.75)
	m.pixel_size = (18.0 * battle.WS) / float(maxi(1, m.texture.get_height()))
	var off = Vector2(randf_range(-22.0, 22.0), randf_range(-14.0, 14.0))
	m.position = battle._world_pos(at2d + off, 0.4)
	battle._world.add_child(m)
	var mtw = battle._reg_tween()
	mtw.set_parallel(true)
	mtw.tween_property(m, "position", battle._world_pos(at2d + off, 1.9), 0.6)
	mtw.tween_property(m, "modulate:a", 0.0, 0.6)
	mtw.chain().tween_callback(m.queue_free)


# 幽冥突袭·延迟命中(第2帧): 1.5A魔法+80%吸血+25%闪避4s(经_sk_dmg保真)+击退抛飞
func _ghost_phantom_hit(u: Dictionary, tgt) -> void:
	if not u.get("alive", false): return
	if not (tgt is Dictionary) or not tgt.get("alive", false): tgt = battle._nearest_enemy(u)
	if tgt == null: return
	battle._sk_dmg(u, tgt, {"magic": 1.5, "hits": 1, "lifesteal": 0.8, "selfDodge": 0.25, "selfDodgeDur": 4.0, "name": "幻影!", "color": Color("#c77dff")})
	if tgt.get("alive", false):
		battle._knockback(u, tgt, 0.0, 1.4, 0.45)   # 击退抛飞

# 幽灵·技1 幽冥突袭(用户2026-07-11「用回合制特效」): 1.5A魔法+80%吸血+25%闪避4s(经_sk_dmg保真) + 回合制幻影(ghost-phantom)+触碰(ghost-touch)图 + 击退抛飞juggle
func _sk_ghost_phantom(u: Dictionary, tgt) -> void:
	if tgt == null: tgt = battle._nearest_enemy(u)
	if tgt == null: return
	battle._vfx._play_anim_vfx("res://assets/sprites/vfx/ghost-phantom.png", tgt["pos"], 155.0, 15.0, 1.5)   # 幻影(回合制vfx/5帧·上移·用户2026-07-11)
	battle._vfx._play_anim_vfx("res://assets/sprites/vfx/ghost-touch.png", tgt["pos"], 125.0, 17.0, 1.4)      # 触碰(vfx/7帧·上移)
	battle._shake(0.08)
	battle._pending_shots.append({"delay": 0.11, "src": u, "fn": _ghost_phantom_hit.bind(u, tgt)})   # 命中延到动画第2帧算(~0.11s·用户2026-07-11)

func _sk_ghost_soulstorm(u: Dictionary, tgt: Dictionary) -> void: # 幽灵龟·灵魂风暴 ✅
	var cursed: bool = battle._has_dot(tgt, "curse")
	if cursed:
		battle._apply_damage_from(u, tgt, int(u["atk"] * 2.5), Color("#e0b0ff"), 0.0, true)   # 有诅咒→2.5A真伤(处决感·用户2026-07-09"打有诅咒是真伤")
	else:
		for i in range(2):
			battle._apply_damage_from(u, tgt, battle._atk_dmg(u, 1.25, tgt, true), Color("#c77dff"))   # 无诅咒→2段共2.5A魔法(用户2026-07-09"打无诅咒目标是魔法")
		battle._add_dot(tgt, "curse", tgt["maxHp"] * 0.05, 10.0, u)   # 技2诅咒10秒(用户2026-07-11·被动登场诅咒仍5s)
	battle._vfx._play_anim_vfx("res://assets/sprites/vfx/ghost-storm.png", tgt["pos"], 135.0, 15.0, 1.1)   # 灵魂风暴(回合制vfx/8帧·逐帧播·用户2026-07-11纠正:原误用skills/单帧图)
	battle._skill_ring(tgt["pos"], Color(0.78, 0.49, 1.0, 0.6), 92.0)
	battle._shake(0.1)

func _sk_ghost_phase(u: Dictionary, tgt: Dictionary) -> void:    # 幽灵龟·虚化 (用户2026-07-08): 虚化4秒受物理伤害-90% + 对目标2段共1.2A真伤
	u["phase_until"] = battle._t + 4.0
	u["energy_lock_until"] = battle._t + 4.0   # 虚化时锁龟能条(用户2026-07-11·复用energy_lock_until→_tick_skill_cd锁)
	for i in range(2):
		battle._apply_damage_from(u, tgt, int(u["atk"] * 0.6), Color("#c77dff"), 0.0, true)   # 真实(穿减伤)
	battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 78.0, Color(0.78, 0.49, 1.0, 0.55), 4.0)   # 虚化紫环(虚化4秒·跟随)
	battle._skill_ring(u["pos"], Color(0.7, 0.45, 1.0, 0.78), 92.0)   # 虚化入场幽紫脉冲(用户2026-07-11)
	var _pr2 = battle._reg_tween()
	_pr2.tween_interval(0.08)
	_pr2.tween_callback(battle._skill_ring.bind(u["pos"], Color(0.6, 0.4, 0.95, 0.5), 145.0))
	battle._shake(0.06)

