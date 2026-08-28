class_name EliteSystem
extends RefCounted
const SkillForms = preload("res://scripts/gamedata/skill_forms.gd")
## 精英龟技能系统
## 类内名不变;外部名加 battle.

var battle

func _init(b) -> void:
	battle = b

func _elite_anim(u: Dictionary, action: String) -> void:
	if not (u.get("is_elite", false) and u.get("alive", false)):
		return
	if not is_instance_valid(u.get("sprite", null)):
		return
	if u.get("anim_action", "") == "death":
		return
	var e = battle.ACTION_ELITE.get(action, null)
	if e == null:
		return
	var asd = battle._resolve_action(str(e[0]), float(e[1]))
	if asd.is_empty():
		return
	battle._set_anim_sheet(u, asd, action, false)
	_elite_fix_norm(u, asd)


# PixelLab 96×96 动作帧的实测常量 (2026-07-21, 逐帧量 bbox 得到, 七张图完全一致):
#   第0帧内容 = [高 47, 底行 71] —— 角色本体高 47px, 脚底在第 71 行, 脚下空 25px。
#   (后续帧 bbox 更大是刀光/环形斩的特效超出本体, 不能当本体尺寸用。)
func _elite_fix_norm(u: Dictionary, sd: Dictionary) -> void:
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr):
		return
	var nk = battle.ANIM_NORM.get(battle._anim_key(u), null)
	if nk == null:
		return          # 没登记归一数据的单位不动它(用通用规则)
	var act_body: float = float(nk[0])
	var feet_row: float = float(nk[1])
	var idle_body: float = float(nk[2])
	var frame_h: float = float(int(sd.get("frame_h", 96)))
	# ①本体大小对齐 idle
	var idle_px: float = float(u.get("idle_px", battle.PIXEL_SIZE))
	spr.pixel_size = idle_px * (idle_body / maxf(1.0, act_body))
	# ②脚底对齐: 通用规则用 frame_h*0.5(假设内容顶到帧底), 但这里脚下空着一截,
	#    照抄会让角色整个悬空(精英实测约 0.94m)。按实测脚底行反推。
	spr.offset = Vector2(0.0, feet_row - frame_h * 0.5)


## 近战小将专属动作(2026-07-22) —— 与 _elite_anim 同构, 只是查 ACTION_MELEE。
##   ★只对【前排近战】小将生效: 三种小将共用 id, 不加这道判断会把三叉戟帧套到远程/精英身上。
# ───── 精英小将·虐杀原形改造(用户2026-07-16): Blade普攻/Blade Frenzy旋刃/Whipfist铁锁/Hammerfist铁锤/Consume吞噬 ─────
func _elite_basic(u: Dictionary, tgt: Dictionary) -> void:      # 普攻·长手刃(Blade): 1A物理+黑红刀光; 第5击旋刃; <15%HP先吞噬
	if _elite_try_consume(u, tgt):
		return
	u["_eb_n"] = int(u.get("_eb_n", 0)) + 1
	if u["_eb_n"] % 5 == 0:
		_elite_whirl(u)
		return
	var dirv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)
	dirv = dirv.normalized() if dirv.length() > 1.0 else Vector2.RIGHT
	battle._emit_basic(u, tgt, battle._atk_dmg(u, 1.0, tgt), Color("#e05555"), 0)
	_elite_slash_arc(tgt["pos"], dirv)

func _elite_mist(pos2d: Vector2, h: float, n: int = 3) -> void:  # 黑红雾团(变形通用语言: 黑主体+暗红筋络·每次幻化都爆一口)
	var glow = VfxTex._make_fire_glow_tex()
	for k in range(n):
		var m = Sprite3D.new()
		m.texture = glow
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.shaded = false; m.transparent = true
		m.pixel_size = (randf_range(26.0, 46.0) * battle.WS) / float(maxi(1, glow.get_width()))
		m.modulate = Color(0.12, 0.02, 0.03, 0.75) if k % 2 == 0 else Color(0.5, 0.07, 0.09, 0.6)
		m.position = battle._world_pos(pos2d + Vector2(randf_range(-18.0, 18.0), randf_range(-12.0, 12.0)), h + randf_range(-0.15, 0.25))
		battle._world.add_child(m)
		var tw = battle._reg_tween(); tw.set_parallel(true)
		tw.tween_property(m, "pixel_size", m.pixel_size * 1.6, 0.3)
		tw.tween_property(m, "modulate:a", 0.0, 0.3)
		tw.chain().tween_callback(m.queue_free)

func _elite_debris(pos2d: Vector2, n: int) -> void:             # 砸地碎块粒子(黑块+暗红·抛物线飞散落地淡出)
	var glow = VfxTex._make_fire_glow_tex()
	for k in range(n):
		var db = Sprite3D.new()
		db.texture = glow
		db.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		db.shaded = false; db.transparent = true
		db.pixel_size = (randf_range(8.0, 16.0) * battle.WS) / float(maxi(1, glow.get_width()))
		db.modulate = Color(0.1, 0.03, 0.03, 1.0) if k % 3 != 0 else Color(0.55, 0.1, 0.1, 0.95)
		db.position = battle._world_pos(pos2d, 0.3)
		battle._world.add_child(db)
		var ang: float = randf() * TAU
		var dst: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * randf_range(40.0, 110.0)
		var dur: float = randf_range(0.3, 0.5)
		var tw = battle._reg_tween(); tw.set_parallel(true)
		tw.tween_property(db, "position", battle._world_pos(dst, 0.05), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(db, "modulate:a", 0.0, 0.15).set_delay(dur - 0.15)
		tw.chain().tween_callback(db.queue_free)
		var up = battle._reg_tween()
		up.tween_property(db, "position:y", db.position.y + randf_range(0.3, 0.8), dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _elite_slash_arc(pos2d: Vector2, dirv: Vector2) -> void:    # 黑红刀光(暗色系·区别其他龟亮色)
	var t: Texture2D = load("res://assets/sprites/vfx/ninja-slash.png")
	if t == null: return
	var sl = Sprite3D.new()
	sl.texture = t
	sl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sl.shaded = false; sl.transparent = true
	sl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sl.pixel_size = (86.0 * battle.WS) / float(maxi(1, t.get_height()))
	sl.position = battle._world_pos(pos2d, 0.8)
	sl.rotation.z = atan2(-dirv.y, dirv.x) + randf_range(-0.3, 0.3)
	sl.modulate = Color(0.75, 0.12, 0.15, 0.95)
	sl.flip_h = randf() < 0.5
	battle._world.add_child(sl)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(sl, "pixel_size", sl.pixel_size * 1.25, 0.16)
	tw.tween_property(sl, "modulate:a", 0.0, 0.18)
	tw.chain().tween_callback(sl.queue_free)

func _elite_whirl(u: Dictionary) -> void:                        # 被动3·旋刃(Blade Frenzy·2026-07-16重做: 专属双黑刃扫1.25圈+稠密拖影·不复用忍者刀光): 200码1.3A物理+吸血50%
	_elite_anim(u, "whirl")
	_elite_mist(u["pos"], 0.7, 5)
	battle._skill_ring(u["pos"], Color(0.55, 0.08, 0.1, 0.7), 200.0)
	battle._skill_ring(u["pos"], Color(0.3, 0.05, 0.06, 0.5), 120.0)
	var uu = u
	var btex: Texture2D = load("res://assets/sprites/vfx/bio-blade.png")
	if btex != null:
		var bps: float = (150.0 * battle.WS) / float(maxi(1, btex.get_width()))   # 刃长150码
		var blades: Array = []
		for b in range(2):                                        # 双刃对称180°
			var bl = Sprite3D.new()
			bl.texture = btex
			bl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			bl.shaded = false; bl.transparent = true
			bl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			bl.pixel_size = bps
			battle._world.add_child(bl)
			blades.append(bl)
		var ghost_last = [0.0]
		var swp = battle._reg_tween()
		swp.tween_method(func(q: float) -> void:
			if not uu.get("alive", false): return
			var aa: float = q * TAU * 1.25                         # 扫1.25圈
			for b2 in range(blades.size()):
				var bl2 = blades[b2]
				if not is_instance_valid(bl2): continue
				var ba: float = aa + float(b2) * PI
				bl2.position = battle._world_pos((uu["pos"] as Vector2) + Vector2(cos(ba), sin(ba)) * 105.0, 0.65)
				bl2.rotation.z = -ba - PI * 0.5                    # 刃对齐切线
				bl2.modulate = Color(1, 1, 1, 1.0 - maxf(0.0, q - 0.78) / 0.22)
			if aa - ghost_last[0] >= 0.22:                         # 稠密拖影: 每0.22rad×双刃留渐隐残影(扫过的面填满)
				ghost_last[0] = aa
				for b3 in range(2):
					var ga: float = aa + float(b3) * PI
					var gh = Sprite3D.new()
					gh.texture = btex
					gh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					gh.shaded = false; gh.transparent = true
					gh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					gh.pixel_size = bps
					gh.position = battle._world_pos((uu["pos"] as Vector2) + Vector2(cos(ga), sin(ga)) * 105.0, 0.65)
					gh.rotation.z = -ga - PI * 0.5
					gh.modulate = Color(0.7, 0.15, 0.18, 0.55)
					battle._world.add_child(gh)
					var gt = battle._reg_tween()
					gt.tween_property(gh, "modulate:a", 0.0, 0.22)
					gt.tween_callback(gh.queue_free)
		, 0.0, 1.0, 0.42)
		swp.tween_callback(func() -> void:
			for bl3 in blades:
				if is_instance_valid(bl3): bl3.queue_free())
	var total: int = 0
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if (o["pos"] as Vector2).distance_to(u["pos"]) > 200.0: continue
		var dmg: int = battle._atk_dmg(u, 1.3, o)
		battle._damage._apply_damage_from(u, o, dmg, Color("#e05555"))
		total += dmg
		var dv: Vector2 = (o["pos"] as Vector2) - (u["pos"] as Vector2)
		_elite_slash_arc(o["pos"], dv.normalized() if dv.length() > 1.0 else Vector2.RIGHT)
	if total > 0:
		battle._damage._heal(u, float(total) * 0.5)                              # 吸血50%(生物质回收)
func _elite_try_consume(u: Dictionary, tgt: Dictionary) -> bool:   # 被动1·吞噬(Consume·用户拍板: 1.5s演出不中断/演出期95%减伤/回复=触发瞬间目标剩余HP×2(用户2026-07-19)/只偷主动技)
	if tgt == null or not tgt.get("alive", false): return false
	if tgt.get("_eggImmune", false) or tgt.get("_consuming", false): return false
	if float(tgt.get("hp", 0.0)) >= float(tgt.get("maxHp", 1.0)) * 0.15: return false
	var uu = u
	var tref: Dictionary = tgt
	var heal_amt: float = maxf(0.0, float(tgt["hp"])) * 2.0   # 回复=目标剩余生命的2倍(用户2026-07-19: 原1倍)
	tgt["_consuming"] = true
	_elite_anim(u, "consume")   # 扑抓动作 (放在所有 early-return 之后 = 只有真吞噬才播)
	battle._damage._stun(tgt, 1.7, "_elite_try_consume", true)
	tgt["untargetable_until"] = maxf(float(tgt.get("untargetable_until", 0.0)), battle._t + 1.7)
	u["_slam"] = true                                             # 精英站桩播1.5s(不中断)
	# 用户2026-07-19: 原本"可被攻击不免伤"→改为吞噬期间95%减伤(1.5s后撤回)
	u["damage_reduction"] = float(u.get("damage_reduction", 0.0)) + 0.95
	battle._pending_shots.append({"delay": 1.5, "src": u, "fn": func() -> void:
		u["damage_reduction"] = maxf(0.0, float(u.get("damage_reduction", 0.0)) - 0.95)})
	var glow = VfxTex._make_fire_glow_tex()
	var tends: Array = []
	for k in range(3):                                            # 黑红卷须×3绕目标螺旋收紧(40→8码)
		var td = Sprite3D.new()
		td.texture = glow
		td.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		td.shaded = false; td.transparent = true
		td.pixel_size = (randf_range(20.0, 30.0) * battle.WS) / float(maxi(1, glow.get_width()))
		td.modulate = Color(0.15, 0.02, 0.03, 0.85) if k % 2 == 0 else Color(0.5, 0.07, 0.09, 0.7)
		td.position = battle._world_pos(tgt["pos"], 0.5)
		battle._world.add_child(td)
		tends.append(td)
	var tsp = tgt.get("sprite", null)
	var drv = battle._reg_tween()
	drv.tween_method(func(q: float) -> void:
		if is_instance_valid(tsp):
			var dk: float = 1.0 - 0.85 * q
			tsp.modulate = Color(dk, dk * 0.9, dk * 0.9, 1.0)     # 染黑
			tsp.scale = Vector3.ONE * (1.0 - 0.45 * q)            # 缩小(被吸收感)
		for i2 in range(tends.size()):
			var td2 = tends[i2]
			if not is_instance_valid(td2): continue
			var aa: float = q * 9.0 + float(i2) * TAU / 3.0
			var rr: float = 40.0 - 32.0 * q
			td2.position = battle._world_pos((tref["pos"] as Vector2) + Vector2(cos(aa), sin(aa)) * rr, 0.35 + 0.3 * (1.0 + sin(aa * 0.7)) * 0.5)
	, 0.0, 1.0, 1.45)
	battle._pending_shots.append({"delay": 1.5, "fn": func() -> void:   # 吞噬完成: 黑丝缕流入→回血→击杀→偷放主动技
		for td3 in tends:
			if is_instance_valid(td3): td3.queue_free()
		if not uu.get("alive", false):                            # 精英已亡: 放开目标(保守)
			if tref.get("alive", false):
				tref["_consuming"] = false
				var tsp0 = tref.get("sprite", null)
				if is_instance_valid(tsp0):
					tsp0.modulate = Color(1, 1, 1, 1)
					tsp0.scale = Vector3.ONE
			return
		uu["_slam"] = false
		var tp: Vector2 = tref["pos"]
		_elite_mist(tp, 0.5, 5)
		for k3 in range(9):                                       # 黑丝缕×9流入精英体内(原作: 整个人化作黑丝缕被吸收)
			var strand = Sprite3D.new()
			strand.texture = glow
			strand.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			strand.shaded = false; strand.transparent = true
			strand.pixel_size = (randf_range(10.0, 18.0) * battle.WS) / float(maxi(1, glow.get_width()))
			strand.modulate = Color(0.4, 0.05, 0.07, 0.9)
			var sp0: Vector2 = tp + Vector2(randf_range(-26.0, 26.0), randf_range(-16.0, 16.0))
			strand.position = battle._world_pos(sp0, randf_range(0.3, 0.9))
			battle._world.add_child(strand)
			var stw = battle._reg_tween(); stw.set_parallel(true)
			stw.tween_property(strand, "position", battle._world_pos(uu["pos"] as Vector2, 0.6), randf_range(0.22, 0.36)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			stw.tween_property(strand, "modulate:a", 0.0, 0.1).set_delay(0.24)
			stw.chain().tween_callback(strand.queue_free)
		var stype: String = _elite_steal_skill_type(tref)
		if tref.get("_consume_demo", false) and tref.get("alive", false):   # 评审demo: 复活18%循环看
			tref["_consuming"] = false
			tref["hp"] = float(tref["maxHp"]) * 0.18
			var tsp1 = tref.get("sprite", null)
			if is_instance_valid(tsp1):
				tsp1.modulate = Color(1, 1, 1, 1)
				tsp1.scale = Vector3.ONE
		elif tref.get("alive", false):
			battle._kill(tref, uu)                                        # 正常击杀管线(统计/死亡钩子照走)
		battle._damage._heal(uu, heal_amt)                                        # 回复=吞噬瞬间目标剩余HP×2(用户2026-07-19)
		uu["haste_until"] = battle._t + 5.0; uu["haste_mult"] = 1.5       # 吞噬完成: 5秒+50%攻速(用户2026-07-19)
		battle._vfx._float_text(uu["pos"] + Vector2(0, -62), "吞噬! +50%攻速", Color("#ff6a6a"))
		battle._vfx._flash(uu, Color(1.5, 0.95, 0.95))
		battle._skill_ring(uu["pos"] as Vector2, Color(0.55, 0.08, 0.1, 0.7), 46.0)
		if stype != "":                                            # 以自己属性立即放一次目标主动技(用户拍板: 只放主动)
			battle._pending_shots.append({"delay": 0.35, "fn": func() -> void:
				if not uu.get("alive", false): return
				var et = battle._targeting._acquire_target(uu)
				if et == null: return
				_elite_mist(uu["pos"] as Vector2, 0.8, 3)
				battle._do_skill(uu, et, stype)
			, "src": uu})
	, "src": u})
	return true

func _elite_steal_skill_type(tref: Dictionary) -> String:        # 吞噬偷技: 目标主动技(passiveSkill不放·未实装不放·无技能不放) — 吞噬小将→放小将技=设计正确(用户2026-07-18确认非bug·撤回上次误加的排除)
	for a in tref.get("active_skills", []):
		var stype = str(a)
		if stype == "": continue
		if bool((battle._skill_meta.get(stype, {}) as Dictionary).get("passiveSkill", false)): continue
		if battle._IMPL_SKILLS.has(stype): return stype
	return ""

func _elite_spike(pos2d: Vector2, big: bool) -> void:            # 单根黑刺(Groundspike): 地底BACK弹出→定格→缩回·3变体随机
	var vs = ["bio-spike-a", "bio-spike-b", "bio-spike-c"]
	var tex: Texture2D = load("res://assets/sprites/vfx/%s.png" % vs[randi() % 3])
	if tex == null: return
	var spk = Sprite3D.new()
	spk.texture = tex
	spk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spk.shaded = false; spk.transparent = true
	spk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var sz: float = randf_range(95.0, 140.0) if big else randf_range(70.0, 105.0)   # 加大(用户2026-07-16'更大更明显')
	var fullp: float = (sz * battle.WS) / float(maxi(1, int(tex.get_height())))
	spk.pixel_size = fullp * 0.2
	spk.flip_h = randf() < 0.5
	spk.position = battle._world_pos(pos2d, 0.05)
	spk.rotation.z = randf_range(-0.35, 0.35)
	spk.modulate = Color(1.25, 1.1, 1.1, 1.0)                      # 提亮(暗地上要明显)
	battle._world.add_child(spk)
	battle._skill_ring(pos2d, Color(0.55, 0.09, 0.1, 0.55), 22.0)         # 破土
	var rgt2: Texture2D = VfxTex._make_fire_glow_tex()
	var rg = Sprite3D.new()                                       # 根部暗红光晕(衬出刺)
	rg.texture = rgt2
	rg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rg.shaded = false; rg.transparent = true
	rg.pixel_size = (randf_range(24.0, 34.0) * battle.WS) / float(maxi(1, rgt2.get_width()))
	rg.modulate = Color(0.7, 0.1, 0.12, 0.6)
	rg.position = battle._world_pos(pos2d, 0.12)
	battle._world.add_child(rg)
	var rgt = battle._reg_tween()
	rgt.tween_property(rg, "modulate:a", 0.0, 0.5)
	rgt.tween_callback(rg.queue_free)
	var htop: float = randf_range(0.5, 0.66) if big else randf_range(0.34, 0.5)
	var st = battle._reg_tween(); st.set_parallel(true)
	st.tween_property(spk, "pixel_size", fullp, randf_range(0.08, 0.12)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	st.tween_property(spk, "position", battle._world_pos(pos2d, htop), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	st.chain().tween_interval(randf_range(0.45, 0.62))
	st.chain().tween_property(spk, "position", battle._world_pos(pos2d, 0.02), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.parallel().tween_property(spk, "pixel_size", fullp * 0.15, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	st.chain().tween_callback(spk.queue_free)

func _sk_elite_hammer(u: Dictionary, tgt) -> void:               # 技能·铁锤(100龟能·Hammerfist·2026-07-16细节轮): 举拳蓄力0.35s→往下砸→碎块+尘环→60°锥500码刺浪; 每第3次跳很高(5.2)空中蓄力1s→下锤700码全域
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	if _elite_try_consume(u, tgt):   # 用户2026-07-19: 铁拳也能触发吞噬(目标<15%血时优先吞)
		return
	## ★"这一发是普通还是强化"【只由 SkillForms 说了算】(2026-08-28)。
	##   原来是 `+1` 之后判 `% 3 == 0`; 现在改成【放之前】问 SkillForms(判据 `% 3 == 2`),
	##   两者对同一串计数【逐值等价】(门禁 verify_skill_forms 拿产品真实序列逐发对过),
	##   但好处是: 技能栏图标与这里读的是**同一个判据**, 而且龟壳复制能钉住形态。
	var big: bool = SkillForms.current_index(u, "eliteHammer") == 1
	## 钉住时不推进自己的计数器 —— 龟壳是"照着放一次", 不该改自己的节奏。
	if not SkillForms.is_pinned(u, "eliteHammer"):
		u["_hammer_n"] = int(u.get("_hammer_n", 0)) + 1
	_elite_anim(u, "hammer_big" if big else "hammer")   # 每第3次=跃起强化版, 换另一套帧
	var uu = u
	var dirv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)
	dirv = dirv.normalized() if dirv.length() > 1.0 else Vector2.RIGHT
	var ftex: Texture2D = load("res://assets/sprites/vfx/bio-fist.png")
	_elite_mist(u["pos"], 0.9, 4)                                 # 武器黑雾幻化
	if not big:
		# ── 普通: 拳举高1.7蓄力0.35s变大→0.08s往下砸→撞击(碎块9+双尘环+震屏+黑雾)→锥形刺浪
		u["_slam"] = true
		var origin: Vector2 = u["pos"]
		var slam_p: Vector2 = origin + dirv * 46.0
		var tok: int = battle._next_cast_tok()
		if ftex != null:
			var fs = Sprite3D.new()
			fs.texture = ftex
			fs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			fs.shaded = false; fs.transparent = true
			fs.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			fs.pixel_size = (26.0 * battle.WS) / float(maxi(1, ftex.get_height()))
			fs.position = battle._world_pos(slam_p, 1.7)                  # 举高
			battle._world.add_child(fs)
			var ft = battle._reg_tween()
			ft.tween_property(fs, "pixel_size", (60.0 * battle.WS) / float(maxi(1, ftex.get_height())), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)   # 蓄力变大
			ft.tween_property(fs, "position", battle._world_pos(slam_p, 0.12), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)                            # 往下砸
			ft.tween_property(fs, "modulate:a", 0.0, 0.16)
			ft.tween_callback(fs.queue_free)
		battle._pending_shots.append({"delay": 0.43, "fn": func() -> void:   # 撞击帧(0.35蓄+0.08砸)
			if not uu.get("alive", false): return
			uu["_slam"] = false
			battle._shake(0.11)
			battle._skill_ring(slam_p, Color(0.55, 0.1, 0.12, 0.8), 46.0)
			battle._skill_ring(slam_p, Color(0.35, 0.06, 0.08, 0.5), 110.0)
			_elite_debris(slam_p, 9)
			_elite_mist(slam_p, 0.25, 5)
		, "src": u})
		for step in range(8):
			var dist: float = 500.0 * float(step + 1) / 8.0
			var sref: int = step
			battle._pending_shots.append({"delay": 0.43 + 0.052 * float(step + 1), "fn": func() -> void:
				if not uu.get("alive", false): return
				var n_sp: int = 4 + int(float(sref) * 1.2)   # 加密(近4→远12根/波)
				for k in range(n_sp):
					var aoff: float = deg_to_rad(randf_range(-30.0, 30.0))
					var pp: Vector2 = origin + dirv.rotated(aoff) * (dist + randf_range(-20.0, 20.0))
					if battle.ARENA.has_point(pp): _elite_spike(pp, false)
				for o in battle._units:
					if not battle._is_hostile(uu, o) or not o.get("alive", false): continue
					if int(o.get("_espk_tok", -1)) == tok: continue
					var rel: Vector2 = (o["pos"] as Vector2) - origin
					if rel.length() > dist + 40.0 or rel.length() < dist - 40.0: continue
					if absf(rel.angle_to(dirv)) > deg_to_rad(30.0): continue
					o["_espk_tok"] = tok
					battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, 4.0, o, true), Color("#9bdcff"))   # 普通施法 1.5→4.0 ATK魔法(用户2026-07-19)
					battle._knock_up(o, origin, 5.5)
			, "src": u})
	else:
		# ── 每第3次(Elbow Drop+Groundspike Graveyard): 0.35s跳很高(5.2)→空中蓄力1.0s(巨拳顶举变大+预警圈脉动)→0.12s砸落→大撞击(碎块16+黑雾8+双环+重震)→700码全域10波
		u["_slam"] = true
		u["untargetable_until"] = battle._t + 1.6                         # 滞空不可索敌可受伤(照熔岩)
		var center: Vector2 = u["pos"]
		var tok2: int = battle._next_cast_tok()
		battle._skill_ring(center, Color(0.55, 0.1, 0.12, 0.5), 700.0)   # 预警大圈
		var wr = battle._reg_tween()                                     # 蓄力期预警再脉动2次
		wr.tween_interval(0.6)
		wr.tween_callback(func() -> void:
			if uu.get("alive", false): battle._skill_ring(uu["pos"] as Vector2, Color(0.6, 0.12, 0.14, 0.45), 700.0))
		wr.tween_interval(0.45)
		wr.tween_callback(func() -> void:
			if uu.get("alive", false): battle._skill_ring(uu["pos"] as Vector2, Color(0.65, 0.14, 0.16, 0.5), 700.0))
		var fs2: Sprite3D = null
		if ftex != null:                                           # 空中巨拳(蓄力1s变大·悬在头顶)
			fs2 = Sprite3D.new()
			fs2.texture = ftex
			fs2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			fs2.shaded = false; fs2.transparent = true
			fs2.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			fs2.pixel_size = (30.0 * battle.WS) / float(maxi(1, ftex.get_height()))
			fs2.position = battle._world_pos(center, 6.0)
			battle._world.add_child(fs2)
			var fg = battle._reg_tween()
			fg.tween_interval(0.35)
			fg.tween_property(fs2, "pixel_size", (88.0 * battle.WS) / float(maxi(1, ftex.get_height())), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var jt = battle._reg_tween()
		jt.tween_method(func(q: float) -> void:                    # 跳很高
			if uu.get("alive", false): uu["height"] = q * 5.2
		, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		jt.tween_interval(1.0)                                     # 空中蓄力1秒(用户2026-07-16定)
		jt.tween_method(func(q: float) -> void:                    # 砸落(快)
			if uu.get("alive", false): uu["height"] = (1.0 - q) * 5.2
		, 0.0, 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		jt.tween_callback(func() -> void:
			if is_instance_valid(fs2):                             # 巨拳随砸下→撞地淡出
				var fd = battle._reg_tween()
				fd.tween_property(fs2, "position", battle._world_pos(uu["pos"] as Vector2 if uu.get("alive", false) else center, 0.15), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				fd.tween_property(fs2, "modulate:a", 0.0, 0.2)
				fd.tween_callback(fs2.queue_free)
			if not uu.get("alive", false): return
			uu["_slam"] = false
			uu["height"] = 0.0
			var c2: Vector2 = uu["pos"]
			battle._shake(battle.JUICE_SHAKE_HEAVY)
			battle._shake(0.16)
			battle._skill_ring(c2, Color(0.65, 0.13, 0.15, 0.9), 100.0)
			battle._skill_ring(c2, Color(0.45, 0.08, 0.1, 0.6), 240.0)
			_elite_debris(c2, 16)
			_elite_mist(c2, 0.3, 8)
			for step2 in range(10):
				var dist2: float = 700.0 * float(step2 + 1) / 10.0
				var sref2: int = step2
				battle._pending_shots.append({"delay": 0.05 * float(step2 + 1), "fn": func() -> void:
					var n_sp2: int = 8 + sref2 * 2   # 加密(8→26根/波)
					for k2 in range(n_sp2):
						var aa2: float = randf() * TAU
						var pp2: Vector2 = c2 + Vector2(cos(aa2), sin(aa2)) * (dist2 + randf_range(-25.0, 25.0))
						if battle.ARENA.has_point(pp2): _elite_spike(pp2, true)
					for o2 in battle._units:
						if not battle._is_hostile(uu, o2) or not o2.get("alive", false): continue
						if int(o2.get("_espk_tok", -1)) == tok2: continue
						var dd2: float = (o2["pos"] as Vector2).distance_to(c2)
						if dd2 > dist2 + 45.0 or dd2 < dist2 - 45.0: continue
						o2["_espk_tok"] = tok2
						battle._damage._apply_damage_from(uu, o2, battle._atk_dmg(uu, 6.0, o2, true), Color("#9bdcff"))   # 第三段 3.0→6.0 ATK魔法(用户2026-07-19)
						battle._knock_up(o2, c2, 13.2)
				, "src": uu}))
