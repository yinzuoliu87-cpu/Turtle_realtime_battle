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

func _sk_bubble_shield(u: Dictionary, _tgt: Dictionary) -> void: # 泡泡龟·泡泡盾(封板L435·80龟能): 给最脆友军1.8A泡泡盾(4秒)·到期/被打破/挂盾对象死→爆裂对施法者全体敌2.0A魔法
	var ally = battle._lowest_hp_ally(u)
	if ally == null: ally = u
	_bubble_shield_burst(ally)                       # 若该对象已挂着上一发泡泡盾未爆→先结算(防覆盖丢爆裂)
	battle._grant_shield(ally, u["atk"] * 1.8, 4.0)         # 1.8A泡泡盾·4秒限时(通用护盾原语)
	ally["bubble_shield_until"] = battle._t + 4.0           # 泡泡爆裂追踪(独立于通用shield_until): 到期/盾清零/对象死 任一→爆裂
	ally["bubble_shield_src"] = u
	u["energy_lock_until"] = battle._t + 4.0                # 泡泡盾期间锁龟能(用户2026-07-15·盾在=不充能不放其它·爆裂时解锁·复用energy_lock_until)
	battle._skill_ring(ally["pos"], Color(0.7, 0.9, 1.0, 0.55), 46.0)
	var dtex = load("res://assets/sprites/vfx/fx-hex-bubble.png")   # 泡泡盾罩(跟随友军·4秒)
	if dtex != null:
		var dome = Sprite3D.new()
		dome.texture = dtex; dome.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		dome.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dome.shaded = false; dome.transparent = true
		dome.pixel_size = (108.0 * battle.WS) / float(maxi(1, dtex.get_height()))
		dome.modulate = Color(0.75, 0.92, 1.0, 0.0)
		dome.position = battle._world_pos(ally["pos"], 0.9)
		battle._world.add_child(dome)
		battle._follow_vfx.append({"spr": dome, "unit": ally, "h": 0.9})
		var tw = battle._reg_tween()
		tw.tween_property(dome, "modulate:a", 0.85, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(3.5)
		tw.tween_property(dome, "modulate:a", 0.0, 0.34)
		tw.tween_callback(dome.queue_free)

func _sk_bubble_burst(u: Dictionary, tgt) -> void:              # 泡泡龟·泡泡爆破(马尔扎哈Q式·用户设计): 消耗当前泡泡值40%→目标两侧泡沫门·门间敌每个受=消耗泡泡值魔法+0.8A物理(无沉默)
	if tgt == null or not tgt.get("alive", false): return
	var consumed: float = float(u.get("bubble_store", 0.0)) * 0.40   # 修: 原读"bubble"(从不设=恒0→爆破无泡泡伤害bug)→"bubble_store"(受伤累积的真泡泡值·同被动/累积口径)
	u["bubble_store"] = maxf(0.0, float(u.get("bubble_store", 0.0)) - consumed)
	var c: Vector2 = tgt["pos"]
	var dirp: Vector2 = tgt["pos"] - u["pos"]
	var perp: Vector2 = (dirp.orthogonal().normalized() if dirp.length() > 1.0 else Vector2.UP) * 175.0
	var g1: Vector2 = c + perp                                  # 严格马尔扎哈Q(虚空幽视·用户2026-07-15"按LoL Q怎么动"): 目标两侧现两门→延迟→门间竖起虚空泡沫墙(连接两门·猛涌起)→墙起时结算伤害
	var g2: Vector2 = c - perp
	_bubble_gate(g1)                                            # ① 先现两门(portals)
	_bubble_gate(g2)
	var uu: Dictionary = u; var cc: Vector2 = c; var gg1: Vector2 = g1; var gg2: Vector2 = g2; var cons: float = consumed
	var wt = battle._reg_tween()
	wt.tween_interval(0.2)                                      # ② 门开→短延迟(LoL Q有延迟)
	wt.tween_callback(func() -> void:                          # ③ 门间竖起泡沫墙(从中心向两端展开·每点从地面猛涌起) + 墙起时命中结算
		for k in range(20):
			var t: float = float(k) / 19.0
			_bubble_wall_erupt(gg1.lerp(gg2, t), absf(t - 0.5) * 0.12)
		battle._skill_ring(cc, Color(0.5, 0.9, 1.0, 0.6), 200.0)
		if not uu.get("alive", false): return
		for o in battle._enemies_of(uu):
			if o.get("alive", false) and o["pos"].distance_to(cc) <= 200.0:   # 门间200码带内敌
				battle._apply_damage_from(uu, o, int(battle._mitigate(uu, cons, o, true)) + battle._atk_dmg(uu, 0.8, o), Color("#cdebff")))   # 消耗泡泡值魔法(吃魔抗)+0.8A物理(封板L437)

func _sk_bubble_bind(u: Dictionary, tgt) -> void:
	if tgt == null:
		return
	battle._stun(tgt, 3.0, "_sk_bubble_bind")   # 泡泡束缚定身3秒(用户设计·原CTRL_SEC=1.5)
	tgt["bind_until"] = battle._t + 3.0
	tgt["bind_shred"] = 1.0 if int(u.get("level", 1)) <= 5 else 2.0   # 减甲量按等级(detail: 1-5级=1/6-10级=2)
	tgt["bind_acc"] = 0.0
	var btex = load("res://assets/sprites/skills/bubble-bind.png")   # 气泡牢笼: 罩住目标3秒·跟随(用户设计)
	if btex != null:
		var cage = Sprite3D.new()
		cage.texture = btex; cage.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		cage.billboard = BaseMaterial3D.BILLBOARD_ENABLED; cage.shaded = false; cage.transparent = true
		cage.pixel_size = (118.0 * battle.WS) / float(maxi(1, btex.get_height()))
		cage.position = battle._world_pos(tgt["pos"], 0.9)
		cage.modulate = Color(1, 1, 1, 0)
		battle._world.add_child(cage)
		battle._follow_vfx.append({"spr": cage, "unit": tgt, "h": 0.9})
		var tw = battle._reg_tween()
		tw.tween_property(cage, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(2.55)
		tw.tween_property(cage, "modulate:a", 0.0, 0.3)
		tw.tween_callback(cage.queue_free)
	battle._skill_ring(tgt["pos"], Color(0.5, 0.9, 1.0, 0.5), 54.0)

# 骰子·命运骰子: 随机 +40%~130% 暴击5秒; 超100%部分每1%→1.5%暴伤 (crit 单独计时还原)
