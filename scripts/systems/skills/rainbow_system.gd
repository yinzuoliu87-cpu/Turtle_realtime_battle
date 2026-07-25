class_name RainbowSystem
extends RefCounted
## 彩虹龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _rainbow_enh_prism_proc(u: Dictionary) -> void:            # 强化棱镜4色(用户设计·每5秒抽1): 橙全体友军+10%吸血5s / 黄随机敌灼烧0.67A / 青随机敌冰寒5s / 紫随机敌诅咒5s
	var c: int = battle._battle_rng.randi() % 4
	var es: Array = battle._pick_enemies_of(u)
	match c:
		0:
			for o in battle._allies_of(u):
				battle._buff(o, "lifesteal", 0.1, false, 5.0)
			battle._float_text(u["pos"] + Vector2(0, -60), "橙·全体吸血", Color("#ff9d3c"))
		1:
			if not es.is_empty():
				var t = es[battle._battle_rng.randi() % es.size()]
				battle._apply_dot_stacks(t, "burn", maxi(1, int(round(float(u["atk"]) * 0.67))), u)
		2:
			if not es.is_empty():
				var t2 = es[battle._battle_rng.randi() % es.size()]
				t2["spd_aspd_mult"] = 0.7; t2["spd_dbf_until"] = battle._t + 5.0   # 冰寒-30%攻速5秒
		3:
			if not es.is_empty():
				var t3 = es[battle._battle_rng.randi() % es.size()]
				battle._add_dot(t3, "curse", t3["maxHp"] * 0.05, 5.0, u)             # 诅咒每秒5%maxHp真伤5秒
	battle._skill_ring(u["pos"], Color(0.8, 0.6, 1.0, 0.4), 48.0)

# 棱镜护盾施法特效: 七彩爆发从彩虹龟扩散 + 每友军护盾罩+棱镜色pop (用户2026-07-13补·"棱镜"主题)
func _rainbow_prism_shield_vfx(u: Dictionary) -> void:
	# 施法者: 6色空心环错峰扩散 → 彩虹涟漪(空心+alpha混合→色分明不糊白)
	for i in range(battle._PRISM_RAINBOW.size()):
		var col: Color = battle._PRISM_RAINBOW[i]
		var tw = battle._reg_tween()
		tw.tween_interval(i * 0.07)
		tw.tween_callback(func() -> void:
			if not u.get("alive", false): return
			var r = Sprite3D.new()
			r.texture = VfxTex._make_ring_texture(col)
			r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			r.shaded = false; r.transparent = true
			r.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			r.modulate = Color(col.r, col.g, col.b, 0.95)
			r.pixel_size = (66.0 * battle.WS) / 96.0
			r.position = battle._world_pos(u["pos"], 0.9)
			battle._world.add_child(r)
			var rt = battle._reg_tween(); rt.set_parallel(true)
			rt.tween_property(r, "scale", Vector3.ONE * 4.2, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			rt.tween_property(r, "modulate:a", 0.0, 0.55)
			rt.chain().tween_callback(r.queue_free))
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	# 每友军: 护盾罩(复用现成)
	for o in battle._allies_of(u):
		battle._shield_dome(o)

func _rainbow_storm_tick(u: Dictionary, center: Vector2, radius: float, ti: int) -> void:
	if not u.get("alive", false):
		return
	var col: Color = battle._PRISM_RAINBOW[ti % battle._PRISM_RAINBOW.size()]
	# 每跳: 中心冲击波脉冲(贴地扩散环·当跳色→节拍可感)
	var pulse = Sprite3D.new()
	pulse.texture = VfxTex._make_ring_texture(Color(1, 1, 1))
	pulse.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pulse.axis = Vector3.AXIS_Y
	pulse.shaded = false; pulse.transparent = true
	pulse.modulate = Color(col.r, col.g, col.b, 0.9)
	pulse.position = battle._world_pos(center, 0.08)
	pulse.pixel_size = (60.0 * battle.WS) / 96.0
	battle._world.add_child(pulse)
	var ptw = battle._reg_tween(); ptw.set_parallel(true)
	ptw.tween_property(pulse, "scale", Vector3.ONE * (radius * 2.0 / 60.0), 0.5)
	ptw.tween_property(pulse, "modulate:a", 0.0, 0.5)
	ptw.chain().tween_callback(pulse.queue_free)
	# 圈内敌: 削护甲魔抗 + 伤害 + 碎甲可视化
	for o in battle._enemies_of(u):
		if not o.get("alive", false):
			continue
		if o["pos"].distance_to(center) <= radius:
			battle._buff(o, "def", -0.20, true, 0.65)   # 圈内-20%护甲
			battle._buff(o, "mr", -0.20, true, 0.65)    # 圈内-20%魔抗
			battle._apply_damage_from(u, o, battle._atk_dmg(u, 0.1, o, true), Color("#ff8ad8"))
			battle._apply_damage_from(u, o, int(u["atk"] * 0.05), Color("#fff0a0"), 0.0, true)   # 8跳共0.8魔+0.4真=原值
			battle._storm_shred(o)   # ★碎甲: 把"削护甲魔抗"可视化

# 碎甲: 削防御的可视化(AI棱镜碎片爆在敌人身上)
func _rainbow_storm_end(u: Dictionary) -> void:
	for n in u.get("storm_nodes", []):
		if n == null or not is_instance_valid(n):
			continue
		if n is GPUParticles3D:
			n.emitting = false                       # 停发, 剩余粒子自然消散再销
			var dt = battle._reg_tween(); dt.tween_interval(1.4); dt.tween_callback(n.queue_free)
		else:
			var ft = battle._reg_tween(); ft.tween_interval(0.25); ft.tween_callback(n.queue_free)
	u["storm_nodes"] = []
	var disc = u.get("storm_disc", null)   # 兼容旧字段(防遗留)
	if disc != null and is_instance_valid(disc):
		disc.queue_free()
	u["storm_disc"] = null

