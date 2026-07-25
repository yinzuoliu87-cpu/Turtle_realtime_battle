class_name ChestSystem
extends RefCounted
## 宝箱龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

# 宝箱·藏宝图(封板L590-594·完整15件专属池): 造成伤害积累财宝值(=dmg_dealt), 过阈值开专属战利品(分档池·不重复)+回血, 一场最多5件
func _chest_treasure_tick(u: Dictionary) -> void:
	# 大轮制(用户2026-07-16): 我方真实对局=财宝值跨场累积(GameState)·阈值1000/2500/4500/7000/12000·开出=一大轮常驻; demo/敌侧=单场旧制
	var season_mode: bool = (not battle._review_demo()) and str(u.get("side", "")) == "left" and GameState != null and not u.get("is_summon", false)
	var opened: int
	if season_mode:
		var synced: float = float(u.get("_ttl_synced", 0.0))
		var cur: float = float(u.get("dmg_dealt", 0.0))
		if cur > synced:
			GameState.chest_treasure_value += cur - synced
			u["_ttl_synced"] = cur
		opened = (GameState.chest_treasures_won as Array).size()
		if opened >= 5:
			return
		if float(GameState.chest_treasure_value) < float(battle._CHEST_THRESH[opened]):
			return
	else:
		opened = int(u.get("chest_opened", 0))
		if opened >= 5:
			return
		var lvl_mult: float = 1.0 + 0.03 * float(maxi(0, int(u.get("level", 1)) - 1))   # 阈值随等级+3%/级(单场旧制)
		var thresh: Array = [80.0, 130.0, 240.0, 360.0, 590.0]
		if float(u.get("dmg_dealt", 0.0)) < float(thresh[opened]) * lvl_mult:
			return
	u["chest_opened"] = opened + 1
	var group: String = ["basic", "basic", "adv", "adv", "legend"][opened]   # 第1-2箱基础/3-4进阶/5传说
	var heal_pct: float = [0.08, 0.08, 0.11, 0.11, 0.15][opened]
	var tid: String = _chest_pick_treasure(u, group)
	if tid != "":
		_chest_apply_treasure(u, tid)
		if u.get("chest_greed", false): _chest_greed_apply(u, 1)   # 贪婪: 新开1件→+4%攻+7%最大生命
		if (not battle._review_demo()) and str(u.get("side", "")) == "left" and GameState != null and not u.get("is_summon", false):
			GameState.chest_treasures_won.append(tid)              # 大轮常驻装备(用户2026-07-16)+当场落盘防丢
			GameState.save()
		battle._float_text(u["pos"] + Vector2(0, -72), "开箱! " + str(battle._CHEST_TREASURE_NAME.get(tid, tid)), Color("#ffd93d"))
		var ipath: String = "res://assets/sprites/equip/chest-t-%s.png" % tid   # 头顶弹出战利品图标(用户2026-07-15: 看清开了什么)
		if ResourceLoader.exists(ipath):
			var ic = Sprite3D.new()
			ic.texture = load(ipath)
			ic.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			ic.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ic.shaded = false; ic.transparent = true
			ic.pixel_size = (44.0 * battle.WS) / 32.0
			ic.modulate = Color(1, 1, 1, 0.0)
			ic.position = battle._world_pos(u["pos"], 2.3)
			battle._world.add_child(ic)
			var it = battle._reg_tween()
			it.tween_property(ic, "modulate:a", 1.0, 0.12)
			it.parallel().tween_property(ic, "scale", Vector3(1.25, 1.25, 1.25), 0.25).from(Vector3(0.5, 0.5, 0.5)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			it.tween_interval(0.9)
			it.tween_property(ic, "position", battle._world_pos(u["pos"], 2.9), 0.3)
			it.parallel().tween_property(ic, "modulate:a", 0.0, 0.3)
			it.tween_callback(ic.queue_free)
	battle._heal(u, u["maxHp"] * heal_pct)
	battle._skill_ring(u["pos"], Color(1.0, 0.85, 0.2, 0.5), 52.0)

func _chest_pick_treasure(u: Dictionary, group: String) -> String:   # 该档随机1件(不重复)·档抽光→退回全池任意未拥有
	var owned: Dictionary = u.get("chest_treasures", {})
	var avail: Array = []
	for tid in battle._CHEST_TREASURE_POOL.get(group, []):
		if not owned.has(tid): avail.append(tid)
	if avail.is_empty():
		for g in ["basic", "adv", "legend"]:
			for tid in battle._CHEST_TREASURE_POOL[g]:
				if not owned.has(tid): avail.append(tid)
	if avail.is_empty(): return ""
	return str(avail[battle._battle_rng.randi() % avail.size()])

func _chest_apply_treasure(u: Dictionary, tid: String) -> void:   # 逐件bespoke效果(属性即时应用·机制类置flag由钩子读)
	if not u.has("chest_treasures"): u["chest_treasures"] = {}
	u["chest_treasures"][tid] = true
	match tid:
		"dagger":         battle._buff(u, "atk", 0.25, true, 99999.0)                                              # 短刃: +25%攻
		"wood_shield":    battle._buff(u, "def", 0.20, true, 99999.0); battle._buff(u, "mr", 0.20, true, 99999.0)          # 木盾: +20%双抗
		"rum":            u["chest_rum_t"] = 0.0                                                             # 朗姆酒: 每10秒回8%maxHp(周期tick读flag)
		"blood_dice":     u["crit"] = float(u.get("crit", 0.0)) + 0.35                                       # 血筛子: +35%暴击
		"chain":          u["chest_aoe_mult"] = 2.0                                                          # 锁链: 砸击AOE距离/射程翻倍(_chest_basic钩子)
		"stone":          u["chest_rock_bonus"] = float(u.get("chest_rock_bonus", 0.0)) + 1.0                # 石头: 砸击额外+100%护甲+100%魔抗(_chest_basic钩子)
		"long_sword":     battle._buff(u, "atk", 0.45, true, 99999.0)                                               # 长剑: +45%攻
		"bloodblade":     u["lifesteal"] = float(u.get("lifesteal", 0.0)) + 0.25                             # 嗜血之刃: +25%吸血
		"flint":          pass                                                                               # 火石: 命中→灼烧(_apply_damage_from钩子·防循环)
		"gem_armor":      battle._buff(u, "def", 0.25, true, 99999.0); battle._buff(u, "mr", 0.25, true, 99999.0); u["maxHp"] += 60.0; u["hp"] += 60.0   # 宝石甲: +25%双抗+60血
		"poison":         pass                                                                               # 毒箭: 命中→治疗削减-50%5秒(_apply_damage_from钩子·防循环)
		"phoenix_statue": u["_chest_revive"] = true                                                          # 凤凰雕像: 首死25%最大生命复活(_kill钩子)
		"crown":          battle._buff(u, "atk", 0.40, true, 99999.0); u["crit"] = float(u.get("crit", 0.0)) + 0.40; u["crit_dmg"] = float(u.get("crit_dmg", 1.5)) + 0.25; u["lifesteal"] = float(u.get("lifesteal", 0.0)) + 0.15   # 王冠: +40攻/+40暴/+25爆伤/+15吸血
		"thunder":        pass                                                                               # 雷刃: 命中叠金闪电满5引爆1.0A真伤(_apply_damage_from钩子·防循环)
		"starlight":      u["chest_starlight"] = true                                                        # 星辉: 所有伤害转真实(battle._apply_damage_from raw钩子·armor全绕层过局限留F5)

func _chest_pick_equip(costs: Array) -> String:
	var pool: Array = []
	for eq in DataRegistry.phase2_equipment:
		if int(eq.get("cost", 0)) in costs:
			pool.append(str(eq.get("id", "")))
	if pool.is_empty():
		return ""
	return str(pool[battle._battle_rng.randi() % pool.size()])

func _chest_basic(u: Dictionary, tgt: Dictionary) -> void:       # 普攻·宝箱砸击(封板): K'Sante一段Q式·朝目标前方短直线AOE·各1A物理(近战扫一小片非单体)
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var aoe_mult: float = float(u.get("chest_aoe_mult", 1.0))       # 锁链loot将来翻倍AOE距离/射程钩子(=1未装)
	var reach: float = 170.0 * aoe_mult
	var halfw: float = 62.0 * aoe_mult
	var rock: float = float(u.get("chest_rock_bonus", 0.0))         # 石头loot将来额外+100%护甲+100%魔抗钩子(=0未装)
	var bonus: int = int((u["def"] + u["mr"]) * rock)
	# 逐帧订正(2026-07-16问责轮): 一段Q=砸地→金波头0.18s推进→扫到谁谁炸(错峰)→贴地燃金痕依次铺→尽头残亮头熄灭
	var wave_t: float = 0.18                                        # 波头跑完170码用时(s16砸→s21到敌≈0.15-0.2s)
	var uu: Dictionary = u
	for o in battle._enemies_of(u):
		if not o.get("alive", false): continue
		var rel: Vector2 = o["pos"] - u["pos"]
		var along: float = rel.dot(dir)
		if along < -18.0 or along > reach: continue
		if (rel - dir * along).length() > halfw: continue
		var oref: Dictionary = o
		battle._pending_shots.append({"delay": wave_t * clampf(along / reach, 0.0, 1.0), "fn": func() -> void:   # 波头扫到才结算(近先远后)
			if not oref.get("alive", false) or not uu.get("alive", false): return
			battle._apply_damage_from(uu, oref, battle._atk_dmg(uu, 1.0, oref) + bonus, Color("#ffd93d"))
			battle._burst_vfx("res://assets/sprites/vfx/treasure-slam.png", oref["pos"], 130.0)                  # 命中放射爆闪(s21·波到才炸)
		, "src": u})
	# ① 砸点层(s16): 尘环+金爆+轻震
	battle._shake(0.05)
	battle._skill_ring(u["pos"] + dir * 42.0, Color(1.0, 0.85, 0.3, 0.7), 30.0)
	battle._burst_vfx("res://assets/sprites/vfx/treasure-slam.png", u["pos"] + dir * 46.0, 120.0)
	# ② 金波头推进(0.18s冲到尽头→残亮头0.3s熄灭·不凭空消失)
	var glowt = VfxTex._make_fire_glow_tex()
	var wh = Sprite3D.new()
	wh.texture = glowt
	wh.billboard = BaseMaterial3D.BILLBOARD_ENABLED; wh.shaded = false; wh.transparent = true
	wh.pixel_size = (44.0 * battle.WS) / float(maxi(1, glowt.get_width()))
	wh.modulate = Color(1.0, 0.85, 0.35, 0.95)
	wh.position = battle._world_pos(u["pos"] + dir * 46.0, 0.18)
	battle._world.add_child(wh)
	var wt = battle._reg_tween()
	wt.tween_property(wh, "position", battle._world_pos(u["pos"] + dir * reach, 0.18), wave_t)
	wt.tween_property(wh, "pixel_size", (20.0 * battle.WS) / float(maxi(1, glowt.get_width())), 0.3)   # 尽头残亮头收小熄灭(s26远端)
	wt.parallel().tween_property(wh, "modulate:a", 0.0, 0.3)
	wt.chain().tween_callback(wh.queue_free)
	# ③ 贴地痕迹(height压到0.06·原0.5悬空是错的): 冲击带短亮+燃金痕渐隐
	battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + dir * reach, 96.0, Color(1.0, 0.85, 0.25, 0.7), 0.16, 0.06)
	battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", u["pos"], u["pos"] + dir * reach, 58.0, Color(1.0, 0.6, 0.15, 0.5), 0.6, 0.06)
	# ④ 尘旋圈随波头依次留下(s26·非同帧全出)
	for r in range(3):
		var rq: float = 0.3 + 0.28 * float(r)
		var rp: Vector2 = u["pos"] + dir * (reach * rq)
		battle._pending_shots.append({"delay": wave_t * rq, "fn": func() -> void:
			battle._skill_ring(rp, Color(1.0, 0.8, 0.35, 0.4), 26.0)
		, "src": u})

func _chest_coin_spray(pos2d: Vector2, n: int) -> void:        # 金币弹飞(抛物线落地淡出·命中反馈)
	var ctex: Texture2D = load("res://assets/sprites/vfx/storm-coin.png")
	if ctex == null: return
	for k in range(n):
		var ck = Sprite3D.new()
		ck.texture = ctex
		ck.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		ck.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ck.shaded = false; ck.transparent = true
		ck.pixel_size = 0.024 + 0.006 * randf()
		ck.position = battle._world_pos(pos2d, 0.5)
		battle._world.add_child(ck)
		var ang: float = randf() * TAU
		var dst: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * randf_range(40.0, 90.0)
		var dur: float = randf_range(0.35, 0.5)
		var tw = battle._reg_tween(); tw.set_parallel(true)
		tw.tween_property(ck, "position", battle._world_pos(dst, 0.05), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(ck, "modulate:a", 0.0, 0.15).set_delay(dur - 0.15)
		tw.chain().tween_callback(ck.queue_free)
		var up = battle._reg_tween()
		up.tween_property(ck, "position:y", ck.position.y + randf_range(0.15, 0.4), dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
func _chest_greed_apply(u: Dictionary, n: int) -> void:        # 贪婪(技三打包被动): 每携带1件装备永久+4%攻+7%最大生命 (单位=登场base快照·不复利)
	if n <= 0: return
	u["base_atk"] = float(u["base_atk"]) + float(u.get("chest_greed_atk_unit", 0.0)) * n
	var hb: float = float(u.get("chest_greed_hp_unit", 0.0)) * n
	u["maxHp"] = float(u["maxHp"]) + hb
	u["hp"] = float(u["hp"]) + hb
	battle._recalc_stats(u)

func _chest_loot_row(parent: VBoxContainer, tid: String) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var icon_box = PanelContainer.new()
	var isb = StyleBoxFlat.new()
	isb.bg_color = Color("#0c141c")
	isb.set_border_width_all(2); isb.border_color = Color("#ffd93d")
	isb.set_corner_radius_all(5)
	icon_box.add_theme_stylebox_override("panel", isb)
	icon_box.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon_box)
	var ipath = "res://assets/sprites/equip/chest-t-%s.png" % tid
	if ResourceLoader.exists(ipath):
		var ic = TextureRect.new()
		ic.texture = load(ipath)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon_box.add_child(ic)
	var tcol = VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 1)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tcol)
	var nl = Label.new()
	nl.text = str(battle._CHEST_TREASURE_NAME.get(tid, tid))
	nl.add_theme_font_size_override("font_size", 14)
	nl.add_theme_color_override("font_color", Color("#ffd93d"))
	tcol.add_child(nl)
	var dl = Label.new()
	dl.text = str(battle._CHEST_TREASURE_DESC.get(tid, ""))
	dl.add_theme_font_size_override("font_size", 12)
	dl.add_theme_color_override("font_color", Color("#c9d4de"))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_child(dl)

# 技能条目 [{name, desc}]: 取该龟已选的主动技 (走 _chosen_skill_types) + 普攻名 (skillPool[0]).
## 小将技能文案表 —— 小将 id 是 "__minion__", pets.json 里【没有】这个条目,
## 于是 _panel_skill_entries 查不到 pool → 详情面板整个「技能」区不渲染
## (用户 2026-07-21:「小将的技能描述要在面板里去显示」)。
## 文案取自各技能实现函数的头注释(那里就是权威描述), 数值口径见对应 _sk_* 实现。