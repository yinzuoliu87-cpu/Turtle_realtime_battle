class_name CandySystem
extends RefCounted
## 糖果龟技能系统
## 类内名不变;外部名加 battle.

## ★糖果数值单一事实源(用户2026-07-28 削弱·整只 81.5%)。文案在 data/pets.json。
## ★两条召唤路径共用它: 登场召(battle_spawn.gd) / 阵亡补召(本文件) —— 只改一处会造出"第一颗弱、第二颗强"的诡异行为。
const BOMB_DEATH_AOE := 1.0   # 炸弹死亡爆炸: 总伤 = ×炸弹最大生命 (1.5→1.0)

var battle

func _init(b) -> void:
	battle = b

func _sk_candy_hammer(u: Dictionary, tgt) -> void:              # 糖果龟·技能一糖果锤(封板·80龟能): 举糖果锤蓄力→猛砸直线200码·总(1.8A+12%自maxHp)物理由命中敌均分·回血40%(用户2026-07-14做举锤蓄力+落砸)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	battle._anticipate(u)                                              # 蹲身蓄力
	var hammer: Sprite3D = null                                # 举锤→猛砸一气呵成(用户2026-07-15"不连贯"→连续动作·无干等)
	var htex = load("res://assets/sprites/skills/candy-hammer.png")
	if htex != null:
		hammer = Sprite3D.new()
		hammer.texture = htex; hammer.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		hammer.billboard = BaseMaterial3D.BILLBOARD_DISABLED; hammer.shaded = false; hammer.transparent = true
		hammer.pixel_size = (155.0 * battle.WS) / float(maxi(1, htex.get_height()))
		## ★★先入树再摆姿势(2026-08-22)。原来是反的 ⇒ `_candy_hammer_pose` 里读
		##   `hammer.global_transform` 时节点还不在树上, 引擎报
		##   `Condition "!is_inside_tree()" is true. Returning: Transform3D()`,
		##   **首帧的锤子朝向被静默丢掉**(下一帧 tween 才纠正)。
		##   这不是拆场问题 —— 回溯写得很清楚: _sim_step → _do_skill → 这里, 正常战斗中就会发生。
		##   (我一开始猜是拆场时序, 给触手/弹道各加了守卫都没治好 —— 猜三次不如看一次回溯。)
		battle._world.add_child(hammer)
		_candy_hammer_pose(hammer, u["pos"], dir, false, 0.0)
	var uu: Dictionary = u; var d2: Vector2 = dir
	var tw = battle._reg_tween()
	if hammer != null:
		tw.tween_method(func(p: float) -> void: _candy_hammer_pose(hammer, uu["pos"], d2, false, p), 0.0, 1.0, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # 举锤上抬后仰
		tw.tween_method(func(p: float) -> void: _candy_hammer_pose(hammer, uu["pos"], d2, true, p), 0.0, 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 猛砸下挥
	else:
		tw.tween_interval(0.38)
	tw.tween_callback(func() -> void:   # 砸中: 沿线糖爆冲击+震屏+均分伤+回血
		if hammer != null and is_instance_valid(hammer):
			var ht = battle._reg_tween(); ht.tween_interval(0.06); ht.tween_property(hammer, "modulate:a", 0.0, 0.16); ht.tween_callback(hammer.queue_free)
		battle._shake(battle.JUICE_SHAKE_HEAVY)
		for k in range(4):                                     # 沿线糖爆冲击带(从锤头往前铺·200码)
			var at: Vector2 = uu["pos"] + d2 * (55.0 + float(k) * 48.0)
			var bt = battle._reg_tween(); bt.tween_interval(float(k) * 0.03)
			bt.tween_callback(func() -> void: battle._burst_vfx("res://assets/sprites/vfx/candy-burst.png", at, 150.0, 0.35))
		if not uu.get("alive", false): return
		var hits: Array = []
		for o in battle._targeting._enemies_of(uu):
			if o.get("alive", false) and battle._on_line(uu["pos"], d2, o["pos"], 70.0) and o["pos"].distance_to(uu["pos"]) <= 200.0:
				hits.append(o)
		if hits.is_empty(): return
		var per_raw: float = (uu["atk"] * 1.8 + uu["maxHp"] * 0.12) / float(hits.size())
		var dealt: int = 0
		for o in hits:
			var dm: int = battle._mitigate(uu, per_raw, o, false)
			battle._damage._apply_damage_from(uu, o, dm, Color("#ff9ed6")); dealt += dm
		battle._damage._heal(uu, float(dealt) * 0.40))

func _candy_hammer_pose(hammer: Sprite3D, pos2d: Vector2, dir: Vector2, slamming: bool, p: float) -> void:   # 糖果锤姿态: raise=从身侧升头顶后方后仰 / slam=挥到前方下落
	if not is_instance_valid(hammer): return
	var flat: Vector2; var hh: float; var ang: float
	var back: Vector2 = pos2d - dir * 24.0
	var front: Vector2 = pos2d + dir * 82.0
	if not slamming:
		flat = pos2d.lerp(back, p); hh = lerpf(1.1, 3.1, p); ang = lerpf(0.0, (0.75 if dir.x >= 0.0 else -0.75), p)
	else:
		flat = back.lerp(front, p); hh = lerpf(3.1, 0.45, p * p); ang = lerpf((0.75 if dir.x >= 0.0 else -0.75), (-1.2 if dir.x >= 0.0 else 1.2), p)
	hammer.flip_h = dir.x < 0.0
	hammer.position = battle._world_pos(flat, hh)
	if battle._cam != null:
		var tf: Transform3D = hammer.global_transform
		tf.basis = battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), ang)
		hammer.global_transform = tf

func _sk_candy_barrage(u: Dictionary, tgt) -> void:            # 糖果龟·技能二糖衣炮弹(封板·120龟能): 敌最密集区降糖衣炮弹雨8跳·可见糖弹从天落下·落点局部命中(用户2026-07-14全套标准)·友1.5%maxHp盾/敌0.2A+2%maxHp魔法+减速20%
	var es: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false): es.append(o)
	var center: Vector2 = tgt["pos"] if tgt != null else u["pos"]
	if not es.is_empty():
		var c = Vector2.ZERO
		for o in es: c += o["pos"]
		center = c / float(es.size())                            # 单位最密集区域(简化=敌质心)
	battle._skill_ring(center, Color(1.0, 0.62, 0.84, 0.32), 600.0)     # 600码笼罩区淡指示
	var uu: Dictionary = u; var ctr: Vector2 = center
	for i in range(8):                                          # 8跳·每跳8颗糖弹密集散落该区·落点局部结算(用户2026-07-15两次加密→3→6→8颗+炮弹/糖爆调大)
		battle._pending_shots.append({"delay": float(i) * 0.42, "src": u, "fn": func() -> void:
			for b in range(8):
				var ang = randf() * TAU
				var land: Vector2 = ctr + Vector2(cos(ang), sin(ang)) * randf_range(15.0, 430.0)
				_candy_shell_drop(land, func() -> void:          # 糖弹落地: 大糖爆+落点120码局部结算
					battle._burst_vfx("res://assets/sprites/vfx/candy-burst.png", land, 185.0, 0.3)
					for o in battle._units:
						if not o.get("alive", false): continue
						if o["pos"].distance_to(land) > 120.0: continue
						if not battle._is_hostile(uu, o):
							battle._damage._grant_shield(o, uu["maxHp"] * 0.015, 2.0)   # 友军护盾 2%→1.5% 自身最大生命/跳(用户2026-07-30 第六轮)
							# ★削的是它"同时当辅助"那一半: 一场送出的护盾 2378→1647(−31%), 输出身份保留。
							#   龟能同时 120→130 → 释放 4.22→3.90 次, 伤害也跟着 −8%。
						else:
							battle._damage._apply_damage_from(uu, o, battle._resolve_dmg(uu, uu["atk"] * 0.2 + uu["maxHp"] * 0.02, o, true), Color("#ff9ed6"), 0.0, false, true)
							o["spd_move_mult"] = 0.8; o["spd_dbf_until"] = battle._t + 0.5)
			})

func _candy_shell_drop(land2d: Vector2, on_land: Callable) -> void:   # 糖衣炮弹: 从高空翻滚落下到落点→自销调on_land
	var tex = load("res://assets/sprites/skills/candy-shell.png")
	if tex == null:
		if on_land.is_valid(): on_land.call()
		return
	var s = Sprite3D.new()
	s.texture = tex
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED; s.shaded = false; s.transparent = true
	s.pixel_size = (58.0 * battle.WS) / float(maxi(1, tex.get_height()))   # 炮弹调大(用户2026-07-15)
	var from_h = 8.5
	s.position = battle._world_pos(land2d, from_h)
	battle._world.add_child(s)
	var tw = battle._reg_tween()
	tw.tween_method(func(p: float) -> void:
		if not is_instance_valid(s): return
		s.position = battle._world_pos(land2d, maxf(0.2, from_h * (1.0 - p * p)))   # 重力加速下落
		if battle._cam != null:
			var tf = s.global_transform
			tf.basis = battle._vfx.cam_basis() * Basis(Vector3(0, 0, 1), p * TAU * 2.0)   # 翻滚
			s.global_transform = tf
	, 0.0, 1.0, randf_range(0.42, 0.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if is_instance_valid(s): s.queue_free()
		if on_land.is_valid(): on_land.call())

func _sk_candy_bomb_feed(u: Dictionary) -> void:               # 糖果龟·技能三糖果炸弹(封板·喂续命): 炸弹活→上限+25%糖果龟maxHp+治疗10%(喂); 炸弹亡→召新HP=20%糖果龟maxHp (登场召唤+死亡爆炸在spawn/summon)
	var bomb = null
	for o in battle._units:
		if o.get("is_summon", false) and is_same(o.get("summon_owner", null), u) and o.get("summon_kind", "") == "candybomb" and o.get("alive", false):
			bomb = o; break
	if bomb != null:
		bomb["maxHp"] = float(bomb["maxHp"]) + u["maxHp"] * 0.25   # 上限+25%糖果龟maxHp
		bomb["hp"] = minf(float(bomb["maxHp"]), float(bomb["hp"]) + u["maxHp"] * 0.10)   # 治疗10%(喂续命)
		battle._vfx._float_text(bomb["pos"] + Vector2(0, -40), "喂!", Color("#ff9ed6"))
		battle._gambler_sys._gambler_pop(bomb["pos"], float(bomb.get("height", 0.0)) + 0.4, Color(1.0, 0.7, 0.88, 0.85))   # 喂养涨大糖光
		battle._skill_ring(bomb["pos"], Color(1.0, 0.62, 0.84, 0.5), 40.0)
		for _cb in range(4): _candy_bomb_bubble(bomb)            # 一簇糖泡
	else:
		battle._spawn._spawn_summon(u, "candybomb", u["maxHp"] * 0.20, 0.0, {   # 炸弹阵亡→召新(HP=20%糖果龟maxHp)
			"label": "糖果炸弹", "spr_id": "candy-bomb", "col_size": 20.0, "hp_w": 24.0,
			"no_basic": true, "no_move": true, "self_decay": 0.08, "death_aoe": BOMB_DEATH_AOE,
		})

func _candy_sweet_drain(u: Dictionary) -> void:   # 甜蜜掠夺·甜蜜吸取(用户2026-07-15"第8秒生效"): 对最大生命最高敌吸25%maxHp→全回复自己(不杀留1)+粉精华VFX
	if not u.get("alive", false): return
	var ce = battle._targeting._enemies_of(u)
	if ce.is_empty(): return
	var fat: Dictionary = ce[0]
	for e in ce:
		if float(e["maxHp"]) > float(fat["maxHp"]): fat = e
	var steal: float = minf(fat["maxHp"] * 0.25, fat["hp"] - 1.0)
	if steal > 0:
		battle._damage._apply_damage_from(u, fat, maxi(1, int(round(steal))), Color("#ff9ecb"), 0.0, true, false, true, true)   # 真伤·必中·不暴击
		battle._damage._heal(u, steal)
		_candy_drain_fx(u, fat, int(steal))

func _candy_drain_fx(candy: Dictionary, fat: Dictionary, amt: int) -> void:   # 甜蜜掠夺: 粉色精华从最肥敌流向糖果龟+吸取字
	if not candy.get("alive", false): return
	var from2d: Vector2 = fat["pos"]
	var kp: Vector2 = candy["pos"]
	## ★★★用户 2026-08-14:「糖果龟的被动展现方式也要改」。
	##   原来是 4 颗 `_glow_bb`(发光公告板)= **一堆圆光球**飘过来 + 一行字。
	##   圆球没有语义 —— 读不出"糖", 也读不出"生命被抽走"(用户 2026-08-06 反对过
	##   "程序生成的圆敷衍")。
	## 现在改成三拍, 每拍都有含义:
	##   ① 目标脚下【糖化环】收缩 —— "这一只正在被抽"
	##   ② 生命碎成【一颗颗菱形糖粒】(专属纹理·带糖果斜条纹与硬糖高光), 沿弧线被吸走
	##   ③ 糖果龟身上【吸收闪光】+ 回血数字 —— 收在自己身上, 闭环
	## ★糖粒数按吸取量走(6~14 颗): 抽得多就飞得多, 玩家不用读数字也能看出量级。
	var bits: int = clampi(6 + int(amt / 60), 6, 14)
	var tex: Texture2D = VfxTex._make_candy_bit_texture(Color(1.0, 0.55, 0.82))
	# ① 目标脚下糖化环: 先标出"谁被抽了"
	battle._skill_ring(from2d, Color(1.0, 0.45, 0.78, 0.75), 62.0)
	for k in range(bits):
		var ang: float = TAU * float(k) / float(bits) + randf_range(-0.2, 0.2)
		var r0: float = 26.0 + randf_range(0.0, 22.0)
		var start: Vector2 = from2d + Vector2(cos(ang), sin(ang)) * r0
		var bit := Sprite3D.new()
		bit.texture = tex
		bit.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bit.shaded = false
		bit.transparent = true
		bit.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素感, 别糊
		bit.pixel_size = 0.055
		bit.position = battle._world_pos(start, 0.7 + randf_range(0.0, 0.5))
		battle._world.add_child(bit)
		## 弧线: 先向外弹一点再被吸走 —— 直线飞读起来像"发射", 弧线才像"被抽"
		var mid: Vector2 = start + (start - from2d).normalized() * 30.0
		var tw = battle._reg_tween()
		tw.tween_interval(float(k) * 0.035)
		tw.tween_property(bit, "position", battle._world_pos(mid, 1.15), 0.16) 			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(bit, "position", battle._world_pos(kp, 1.0), 0.42) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		var t2 = battle._reg_tween()
		t2.tween_interval(float(k) * 0.035 + 0.40)
		t2.tween_property(bit, "scale", Vector3(0.35, 0.35, 0.35), 0.18)
		t2.parallel().tween_property(bit, "modulate:a", 0.0, 0.18)
		t2.tween_callback(bit.queue_free)
	battle._vfx._float_text(from2d + Vector2(0, -50), "甜蜜掠夺 -" + str(amt), Color("#ff6bb0"))
	# ③ 吸收闪光收在糖果龟身上 —— 让"抽给了谁"看得见
	battle._vfx._flash(candy, Color(1.6, 1.1, 1.4))
	battle._skill_ring(kp, Color(1.0, 0.55, 0.82, 0.55), 46.0)

func _candy_bomb_bubble(u: Dictionary) -> void:   # 糖果炸弹糖泡(粉糖色·上飘·区别中毒绿/酒琥珀)
	var pos2d: Vector2 = u["pos"] + Vector2(randf_range(-14.0, 14.0), randf_range(-2.0, 8.0))
	var spr = battle._glow_bb(pos2d, 0.35, 26.0, Color(1.0, 0.65, 0.86, 0.85))
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(spr, "position", battle._world_pos(pos2d, 1.0), 0.55)
	tw.tween_property(spr, "material_override:albedo_color", Color(1.0, 0.65, 0.86, 0.0), 0.55)
	tw.chain().tween_callback(spr.queue_free)

# 双头龟·选一套 (demo 默认套1). 每次攒满龟能 → 切形态 + 放新形态这套招.
# 双头·双生(改造): 切近战形态加成(maxHp+150%ATK·护甲+25%ATK·魔抗+25%ATK·攻-30%ATK·+110%ATK盾), 切远程撤销