class_name BubbleSystem
extends RefCounted
## 泡泡龟技能系统
## 类内簇函数名不变;外部名加 battle. 前缀。

var battle

func _init(b) -> void:
	battle = b

# 泡泡盾爆裂: 到期/被打破/挂盾对象死 触发 → 对施法者(src)全体敌2.0A魔法 + 泡沫冲击波 (封板L435·防静默过期丢爆裂)
func _bubble_shield_burst(ally: Dictionary) -> void:
	if float(ally.get("bubble_shield_until", 0.0)) <= 0.0:
		return
	ally["bubble_shield_until"] = 0.0        # 先清(防再入本对象); 即使下面按深度截断, 盾也已消(不会残留再爆)
	if battle._burst_depth >= 32:                    # 死亡链爆裂级联过深 → 截断, 防无限递归卡死(用户2026-07-19猎手抓 bubbleShield)
		if not battle._burst_cap_warned:
			battle._burst_cap_warned = true
			printerr("[battle.GUARD] 泡泡/冰霜盾爆裂级联深度超32→截断(防卡死)")
		return
	battle._burst_depth += 1
	var src = ally.get("bubble_shield_src", null)
	ally.erase("bubble_shield_src")
	if src is Dictionary:
		src["energy_lock_until"] = battle._t          # 盾爆裂(到期/打破/对象死)→解锁施法者龟能(可能提前爆·用户2026-07-15)
		for o in battle._enemies_of(src):
			if o.get("alive", false):
				battle._apply_damage_from(src, o, battle._atk_dmg(src, 2.0, o, true), Color("#cdebff"))
		battle._skill_ring(ally["pos"], Color(0.75, 0.92, 1.0, 0.6), 90.0)   # 泡沫破裂冲击波(全体敌)
		for _bk in range(10): _bubble_rise(ally["pos"] + Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 40.0)))   # 泡沫爆裂四涌
	battle._burst_depth -= 1

func _bubble_gate(pos2d: Vector2) -> void:   # 泡沫门(bubble-burst立绘·涨开脉动淡出)
	var tex := load("res://assets/sprites/skills/bubble-burst.png")
	if tex == null: return
	var g := Sprite3D.new()
	g.texture = tex; g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED; g.shaded = false; g.transparent = true
	g.pixel_size = (185.0 * battle.WS) / float(maxi(1, tex.get_height()))   # 门调大(用户2026-07-15两门要清楚)
	g.position = battle._world_pos(pos2d, 1.2)
	g.modulate = Color(1, 1, 1, 0)
	battle._world.add_child(g)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(g, "modulate:a", 1.0, 0.14)
	tw.tween_property(g, "scale", Vector3.ONE, 0.2).from(Vector3(0.4, 0.4, 0.4)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.35)
	tw.chain().tween_property(g, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(g.queue_free)

func _bubble_wall_erupt(pos2d: Vector2, delay: float) -> void:   # 虚空泡沫墙的一柱: 从地面猛涌起(竖墙·马尔扎哈Q式·用户2026-07-15加大加高·清晰成墙)
	var b = battle._glow_bb(pos2d, 0.15, randf_range(56.0, 78.0), Color(0.6, 0.9, 1.0, 0.92))
	b.scale = Vector3(0.4, 0.4, 0.4)
	var tw = battle._reg_tween()
	tw.tween_interval(delay)
	tw.tween_property(b, "position", battle._world_pos(pos2d, 3.3), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # 猛涌起(高竖墙)
	tw.parallel().tween_property(b, "scale", Vector3(2.1, 2.1, 2.1), 0.22)
	tw.chain().tween_interval(0.2)
	tw.chain().tween_property(b, "material_override:albedo_color", Color(0.6, 0.9, 1.0, 0.0), 0.3)
	tw.chain().tween_callback(b.queue_free)

func _bubble_rise(pos2d: Vector2) -> void:   # 泡沫上涌(青泡上飘·膨胀淡)
	var b = battle._glow_bb(pos2d, 0.3, randf_range(22.0, 40.0), Color(0.6, 0.9, 1.0, 0.8))
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(b, "position", battle._world_pos(pos2d, randf_range(1.0, 1.8)), 0.55)
	tw.tween_property(b, "scale", Vector3.ONE * 1.4, 0.55)
	tw.tween_property(b, "material_override:albedo_color", Color(0.6, 0.9, 1.0, 0.0), 0.55)
	tw.chain().tween_callback(b.queue_free)

# ============================================================================
#  线条龟·连笔 (回合制 lineLink: atkScale=0.8 / duration=3 / transferPct=30 — 附录B-05 补做)
#  画线连接 2 名敌人 3 秒: ①各受 0.8×ATK  ②各叠 1 层墨迹  ③连接期内一方受到伤害的 30%
#  以【真实伤害】传导给另一方(速写融入被动→墨迹系伤害为真实, 用户#1)  ④一方获墨迹另一方同步。
#  连接线特效跟随双方脚底(用户#6"连接两目标脚底的线特效")。
# ============================================================================