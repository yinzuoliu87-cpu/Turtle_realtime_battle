class_name ShellSystem
extends RefCounted
## 龟壳龟技能系统
## 类内名不变;外部名加 battle.

## ★龟壳数值单一事实源(用户2026-07-28 第一轮削弱·整只 85.5% 全表第三)。文案在 data/pets.json。
const AWAKEN_PCT := 0.06            # 气场觉醒: 每次六属性 +% (0.12→0.06)
const AWAKEN_CRIT := 0.125          # 气场觉醒: 每次暴击率 + (0.25→0.125·两次觉醒后暴击 0.25→0.50 而非 0.75)
## 觉醒时刻(开战后第几秒)。★放在这里而不是主文件: 主文件有架构预算(只改字面量净增 0 行);
##   而且这两个数是【龟壳的规格】, 归属本文件才对。主场景 `_shell_awaken_tick` 直接引用。
const AWAKEN_AT_1 := 10.0
const AWAKEN_AT_2 := 20.0
## 气场储能三件套(原来散在三个文件里的字面量, 文案又各抄一遍):
const STORE_CAP_PCT := 0.50         # 储能上限 = 最大生命 × 此值 (battle_damage.gd 里那条 minf)
const RELEASE_DMG_PCT := 0.40       # 释放: 冲击波对每名敌人 = 储能 × 此值 (物理)
const RELEASE_SHIELD_PCT := 0.80    # 释放: 气场护盾 = 储能 × 此值
const STEALTH_BREAK_MAGIC := 0.5    # 暗影·破隐首发: 额外 ×ATK 魔法 (1.0→0.5)
const DIVE_MAGIC := 2.0             # 暗影俯冲: 落地 ×ATK 魔法 (2.5→2.0)
## ★★★2026-08-22 文案根除分歧: 下面这些原来是**散在代码里的字面量**, 而 pets.json 的文案
##   各写了一遍 —— 两边都能改, 谁也不知道对方 ⇒ 正是"分歧"的来源。
##   抽成常量后文案用 {C:ShellSystem.XXX} 直接引用, 改一处两边同时变, 结构上不可能漂。
const STEALTH_IDLE_SEC := 6.0       # 潜影: 多少秒未受伤进入隐身
const STEALTH_POISON_MULT := 0.5    # 破隐首发: 中毒层数 = ×ATK
const STEALTH_HEALCUT_SEC := 3.0    # 破隐首发: 治疗削减持续秒
const STEALTH_HEALCUT_PCT := 0.5    # 破隐首发: 治疗削减比例
const DIVE_RANGE := 600.0           # 暗影俯冲: 俯冲距离(码)
const BURN_RADIUS := 150.0          # 暗影燃烧区: 半径(码)
const BURN_TICK_SEC := 0.5          # 暗影燃烧区: 每几秒结算一次
const BURN_TICKS := 10              # 暗影燃烧区: 结算几次 ⇒ 总时长 = TICKS × TICK_SEC
const BURN_ATK_MULT := 0.1          # 暗影燃烧区: 每次灼烧层数 = ×ATK
## ★存**语义值**(减速 20%)而不是实现值(移速 ×0.8) —— 文案要写的是前者。
##   存 0.8 的话 {C:...%} 渲染出来是 80, 文案就得手写 20 ⇒ 又是一个没人验的字面量。
const BURN_SLOW_PCT := 0.2          # 暗影燃烧区: 减速比例
const BURN_SLOW_MULT := 1.0 - BURN_SLOW_PCT   # 移速乘数(由上面推导, 不另存一份)
## 燃烧区总时长 = 次数 × 每次间隔。**推导出来**, 不手写第二份。
const BURN_LIFE := BURN_TICKS * BURN_TICK_SEC

## ★★2026-08-25 文案根除: 龟壳普攻的两个数原来一个在主场景(半径), 一个在本文件(溅射比例)。
const BASIC_COEF := 1.0        # 主段 ×ATK(类型物理/真实逐发交替)
## 【复制】抄两个敌方技能轮流放, 各打折。
const COPY_EFFECT := 0.6       # 复制出来的技能只发挥这么多效果(伤害/护盾/治疗/DoT 共用)
## 【吸收】偷目标最大生命并转给自己(双方 maxHp 与当前值同步变)。
const ABSORB_PCT := 0.10       # 偷取 = 目标最大生命 ×
const SPLASH_PCT := 0.5        # 溅射给周围其他敌人的比例(类型跟随主段)

var battle

func _init(b) -> void:
	battle = b

func _shell_guard_fx(u: Dictionary) -> void:   # 守护贝壳018: 双半壳张开→咬合(壳体金闪)→再张开消散 + 脚下治疗圈(用户2026-07-19"做个特效")
	if battle._shellhalf_tex == null: battle._shellhalf_tex = VfxTex._make_shellhalf_texture()
	var base: Vector3 = battle._world_pos(u["pos"], 0.80)   # 罩住龟身(0.50时只罩到腿)
	var open_d = 0.34      # 张开时上下半壳各自的偏移(米)
	var shut_d = 0.03      # 合拢=壳缘贴合
	for k in [1.0, -1.0]:   # +1=上半壳(穹顶朝上), -1=下半壳(翻转·穹顶朝下)
		var sh = Sprite3D.new()
		sh.texture = battle._shellhalf_tex
		sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # 自身护罩=非方向性, billboard即可(不是弹道)
		sh.shaded = false; sh.transparent = true
		sh.no_depth_test = true; sh.render_priority = 6   # 防被地板/身体盖住
		sh.pixel_size = 0.0145                            # ≈1.1m 宽, 与龟体量相称
		sh.flip_v = (k < 0.0)
		sh.modulate = Color(1, 1, 1, 0)
		sh.position = base + Vector3(0, open_d * k, 0)
		battle._world.add_child(sh)
		var tp = battle._reg_tween().bind_node(sh)
		tp.tween_property(sh, "position", base + Vector3(0, shut_d * k, 0), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)   # 咬合(带蓄势)
		tp.tween_interval(0.30)                                                                                                         # 含住=治疗生效
		tp.tween_property(sh, "position", base + Vector3(0, (open_d + 0.22) * k, 0), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)   # 张开散去
		# modulate 全交给一条链(别开第二条 tween 抢同一属性)
		var tf = battle._reg_tween().bind_node(sh)
		tf.tween_property(sh, "modulate", Color(1, 1, 1, 1), 0.12)                    # 淡入
		tf.tween_interval(0.06)
		tf.tween_property(sh, "modulate", Color(1.9, 1.8, 1.35, 1.0), 0.05)           # 咬合瞬间: 壳体过曝金光(取代原环纹理金闪·细扁环只剩左右两段弧=橘色碎屑)
		tf.tween_property(sh, "modulate", Color(1, 1, 1, 1), 0.24)
		tf.tween_interval(0.20)
		tf.tween_property(sh, "modulate", Color(1, 1, 1, 0), 0.32)                    # 散去
		tf.tween_callback(sh.queue_free)
	battle._heal_circle_vfx(u["pos"], 46.0, 0.95)        # 脚下治疗圈

func _shell_basic(u: Dictionary, tgt: Dictionary) -> void:
	_shell_break_stealth(u)                                     # 自己普攻→破隐(设shell_stealth_broke)
	if u.get("shell_stealth_broke", false):                    # 破隐后第一发普攻: +0.5A魔法 + 0.5A毒层 + 3秒50%治疗削减(用户2026-07-28 1.0→0.5)
		u["shell_stealth_broke"] = false
		battle._damage._apply_damage_from(u, tgt, int(u["atk"] * STEALTH_BREAK_MAGIC), Color("#9b3bff"))
		battle._damage._apply_dot_stacks(tgt, "poison", maxi(1, int(round(u["atk"] * STEALTH_POISON_MULT))), u)
		tgt["heal_reduce_until"] = battle._t + STEALTH_HEALCUT_SEC
		tgt["heal_reduce_pct"] = maxf(float(tgt.get("heal_reduce_pct", 0.0)), STEALTH_HEALCUT_PCT)
		battle._vfx._float_text(u["pos"] + Vector2(0, -58), "破隐!", Color("#9b3bff"))
	u["basic_alt"] = not u.get("basic_alt", false)
	var is_true: bool = bool(u["basic_alt"])
	# 主目标命中
	if is_true:
		battle._damage._apply_basic_hit_from(u, tgt, int(u["atk"] * BASIC_COEF), Color("#ffffff"), 0.0, true)   # 真实(穿减伤)
	else:
		battle._damage._apply_basic_hit_from(u, tgt, battle._resolve_dmg(u, u["atk"] * BASIC_COEF, tgt, false), Color("#ff4444"))
	# 近战打击感: 闪白 + 前冲 (同 _emit_basic 近战分支)
	battle._vfx._flash(tgt); battle._melee_lunge(u, tgt)
	# 范围溅射: 主目标120px内其他敌 50%(同类型)
	for e in battle._targeting._enemies_of(u):
		if is_same(e, tgt) or not e.get("alive", false):
			continue
		if (e["pos"] - tgt["pos"]).length() <= battle.SHELL_SPLASH_RADIUS:
			if is_true:
				battle._damage._apply_basic_hit_from(u, e, int(u["atk"] * SPLASH_PCT), Color("#ffffff"), 0.0, true)
			else:
				battle._damage._apply_basic_hit_from(u, e, battle._resolve_dmg(u, u["atk"] * SPLASH_PCT, e, false), Color("#ff4444"))

# 闪电龟·改造普攻(用户2026-06-28逐字"得改造，是一次攻击一道，并有连锁闪电和叠被动"):
#   一道闪电(魔法 0.6×ATK)命中主目标 → 依次接力连锁2跳(每跳260码内最近敌, 伤害×0.6递减 → 0.36A/0.216A)。
#   ★注意: 回合制「闪电打击」的 atkScale=1.15 是【5段总和】, 不是实时单道系数。旧注释写 1.15×ATK 与实装(0.6)不符, 2026-07-10 已订正。
#   0.6 / ×0.6 / 260码 均为实装默认值(用户未指定) → 见权威文档 附录A 调参表。
#   叠层在 _basic_attack 里走 _on_basic_hit(每攻击+1电击层, 满8引爆雷暴). 原始设计=魔法+跳敌+8层雷暴.
func _sk_shell_absorb(u: Dictionary, tgt) -> void:              # 龟壳·吸收(封板): 偷目标10%最大生命→转移(目标maxHp&当前同步减·龟壳maxHp&当前同步增)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var steal: float = tgt["maxHp"] * ABSORB_PCT
	var _hp_before: float = float(tgt["hp"])
	tgt["maxHp"] = maxf(1.0, float(tgt["maxHp"]) - steal)
	tgt["hp"] = minf(float(tgt["hp"]), float(tgt["maxHp"]))     # 目标maxHp+当前同步减
	# ★2026-07-22 用户「像这种偷取最大生命值的…都要统计」: 吸收让目标真的掉了血, 却既不跳伤害字
	#   也不进统计。这里补上 —— 记的是【实际掉的那部分】而不是 steal 全额:
	#   目标满血时二者相等; 目标残血时当前血低于新上限、一滴不掉, 记全额就是凭空多算。
	#   零平衡改动: 血是上面夹出来的, 这里只补记账与飘字。
	# ★用户2026-07-22「龟壳按理说和糖果吸取是同一逻辑的」+「吸取不可以被闪避或暴击」:
	#   把【夹出来的那部分掉血】改走正规真伤路径 → 进统计/跳飘字/走护盾与免死等全套钩子。
	#   ★注意不是"在夹之外再打一次" —— 那会让满血目标掉 2×steal, 是实打实的加强。
	#     做法: 先把 hp 还原, 再由伤害管线扣掉同样的量。数值完全不变, 只是记账口径对了。
	var _hp_lost: int = int(round(_hp_before - float(tgt["hp"])))
	if _hp_lost > 0:
		tgt["hp"] = _hp_before
		battle._damage._apply_damage_from(u, tgt, _hp_lost, Color("#ffffff"), 0.0, true, false, true, true)   # 真伤·必中·不暴击
	u["maxHp"] = float(u["maxHp"]) + steal
	u["hp"] = float(u["hp"]) + steal                            # 龟壳maxHp+当前同步增
	battle._vfx._float_text(u["pos"] + Vector2(0, -52), "+%d" % int(steal), Color("#7fe3a0"))
	var tp: Vector2 = tgt["pos"]                                # 2026-07-17: 4颗红色生命珠鱼贯从目标流向龟壳(删"吸收!"技能名飘字=UI规矩)
	var uref: Dictionary = u
	for i in range(4):
		battle._pending_shots.append({"delay": 0.08 * float(i), "fn": func(): battle._headless_sys._headless_drain_dot(tp, uref), "src": u})

func _shell_dark_flame(pos2d: Vector2, size: float, dur: float) -> void:   # 暗焰喷发(起跳/落地/破隐·2026-07-17): 紫芯+黑烟双层胀开渐隐
	var glow = VfxTex._make_fire_glow_tex()
	for i in range(2):
		var g = Sprite3D.new()
		g.texture = glow
		g.billboard = BaseMaterial3D.BILLBOARD_ENABLED; g.shaded = false; g.transparent = true
		g.pixel_size = (size * (1.0 - 0.35 * float(i)) * battle.WS) / 128.0
		g.modulate = Color(0.5, 0.15, 0.65, 0.9) if i == 0 else Color(0.15, 0.06, 0.2, 0.8)
		g.position = battle._world_pos(pos2d, 0.5 + 0.25 * float(i))
		g.scale = Vector3.ONE * 0.4
		battle._world.add_child(g)
		var gt = battle._reg_tween(); gt.set_parallel(true)
		gt.tween_property(g, "scale", Vector3.ONE * 1.7, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		gt.tween_property(g, "modulate:a", 0.0, dur)
		gt.chain().tween_callback(g.queue_free)

func _shell_burn_patch(pos2d: Vector2, dur: float) -> void:    # 暗焰斑块(Corki火团黑烟式官方帧2026-07-17·暗紫黑): 亮芯+外圈黑烟·烟先散火后灭
	var glow = VfxTex._make_fire_glow_tex()
	var smoke = Sprite3D.new()
	smoke.texture = glow
	smoke.billboard = BaseMaterial3D.BILLBOARD_ENABLED; smoke.shaded = false; smoke.transparent = true
	smoke.pixel_size = (randf_range(60.0, 80.0) * battle.WS) / 128.0
	smoke.modulate = Color(0.12, 0.06, 0.16, 0.0)
	smoke.position = battle._world_pos(pos2d, 0.35)
	battle._world.add_child(smoke)
	var fire = Sprite3D.new()
	fire.texture = glow
	fire.billboard = BaseMaterial3D.BILLBOARD_ENABLED; fire.shaded = false; fire.transparent = true
	var fps0: float = (randf_range(30.0, 42.0) * battle.WS) / 128.0
	fire.pixel_size = fps0
	fire.modulate = Color(0.72, 0.3, 0.95, 0.0)
	fire.position = battle._world_pos(pos2d, 0.25)
	battle._world.add_child(fire)
	var st = battle._reg_tween(); st.set_parallel(true)
	st.tween_property(smoke, "modulate:a", 0.55, 0.15)
	st.tween_property(fire, "modulate:a", 0.9, 0.12)
	st.chain().tween_interval(maxf(0.2, dur - 0.75))
	st.chain().tween_property(smoke, "modulate:a", 0.0, 0.35)   # 烟先散
	st.chain().tween_property(fire, "modulate:a", 0.0, 0.25)    # 火后灭
	st.chain().tween_callback(func() -> void: smoke.queue_free(); fire.queue_free())
	var ft = battle._reg_tween()                                      # 火芯闪动(活火感)
	ft.tween_interval(0.3)
	for i in range(maxi(1, int(dur / 0.4))):
		ft.tween_property(fire, "pixel_size", fps0 * 1.15, 0.2)
		ft.tween_property(fire, "pixel_size", fps0, 0.2)

func _shell_enter_stealth(u: Dictionary) -> void:              # 潜影: 进入隐身(不可被选+半透明); 只有龟壳自己放技能/普攻破隐(AOE不破); 2026-07-17羽化渐隐0.4s+3缕暗雾上腾
	if u.get("shell_stealth", false): return
	u["shell_stealth"] = true
	u["untargetable_until"] = battle._t + 999.0
	var spr = u.get("sprite", null)
	if is_instance_valid(spr):
		var ht = battle._reg_tween()
		ht.tween_property(spr, "modulate:a", 0.4, 0.4)          # 羽化(原瞬变)
	var glow = VfxTex._make_fire_glow_tex()
	for i in range(3):
		var w = Sprite3D.new()
		w.texture = glow
		w.billboard = BaseMaterial3D.BILLBOARD_ENABLED; w.shaded = false; w.transparent = true
		w.pixel_size = 0.006
		w.modulate = Color(0.35, 0.15, 0.5, 0.8)
		var wp: Vector2 = (u["pos"] as Vector2) + Vector2(randf_range(-24.0, 24.0), randf_range(-14.0, 14.0))
		w.position = battle._world_pos(wp, 0.3)
		battle._world.add_child(w)
		var wt = battle._reg_tween(); wt.set_parallel(true)
		wt.tween_property(w, "position", battle._world_pos(wp, randf_range(1.3, 1.8)), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		wt.tween_property(w, "modulate:a", 0.0, 0.6)
		wt.chain().tween_callback(w.queue_free)
	battle._skill_ring(u["pos"], Color(0.4, 0.2, 0.55, 0.5), 46.0)

func _shell_break_stealth(u: Dictionary) -> void:              # 破隐(自己放技能/普攻触发): 清隐身 + 标记破隐首发普攻bonus; 2026-07-17黑雾炸开
	if not u.get("shell_stealth", false): return
	u["shell_stealth"] = false
	u["untargetable_until"] = 0.0
	u["shell_stealth_broke"] = true                            # 破隐后第一发普攻附加(在_shell_basic消费)
	var spr = u.get("sprite", null)
	if is_instance_valid(spr): spr.modulate.a = 1.0
	_shell_dark_flame(u["pos"], 90.0, 0.4)

func _sk_shell_shadow_dive(u: Dictionary, tgt) -> void:        # 龟壳·暗影俯冲(封板·130龟能·Corki库奇式): 俯冲600码→落地2.0A魔法+击退(用户2026-07-28 2.5→2.0)+路径敌→暗影燃烧区150码5s(每0.5s 0.1A灼烧层+减速20%)→进入隐身
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var start: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - start
	if dir.length() < 1.0: dir = Vector2.RIGHT
	dir = dir.normalized()
	var dest: Vector2 = start + dir * DIVE_RANGE
	dest.x = clampf(dest.x, battle.ARENA.position.x, battle.ARENA.end.x)
	dest.y = clampf(dest.y, battle.ARENA.position.y, battle.ARENA.end.y)
	for o in battle._targeting._enemies_of(u):                                    # 落地+路径敌: 2.0A魔法+击退
		if not o.get("alive", false): continue
		if not battle._on_line(start, dir, o["pos"], 75.0): continue
		if o["pos"].distance_to(start) > 620.0: continue
		battle._damage._apply_damage_from(u, o, battle._atk_dmg(u, DIVE_MAGIC, o, true), Color("#9b3bff"))
		battle._damage._knockback(u, o, 60.0, 1.0, 1.4)
	_shell_dark_flame(start, 60.0, 0.5)                         # 起跳点火(Corki官方帧t=1.0起飞喷焰·2026-07-17)
	battle._burst_vfx("res://assets/sprites/vfx/dust-impact.png", start, 90.0, 0.1)
	var uu: Dictionary = u
	u["_slam"] = true                                           # 冲刺滑行0.22s(cyber dash先例·位移演出; 伤害仍施放帧结算=封板)
	var dv = battle._reg_tween()
	dv.tween_method(func(q: float) -> void:
		if uu.get("alive", false): uu["pos"] = start.lerp(dest, q)
	, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	dv.tween_callback(func() -> void:
		uu["_slam"] = false
		if not uu.get("alive", false): return
		_shell_dark_flame(dest, 110.0, 0.6)                     # 落地暗影爆
		battle._burst_vfx("res://assets/sprites/vfx/fx-shock-ring.png", dest, 200.0, 0.1)
		battle._shake(0.1)
		for bi in range(7):                                     # 燃烧区=暗焰斑块群铺150码(Corki火团式·替代原每0.5s重复画环)
			var ba: float = randf() * TAU
			_shell_burn_patch(dest + Vector2(cos(ba), sin(ba)) * randf_range(0.0, 120.0), 5.0)
		var zring = Sprite3D.new()                             # 区界暗紫细环常驻5秒→渐隐
		zring.texture = VfxTex._make_thin_ring_tex()
		zring.billboard = BaseMaterial3D.BILLBOARD_DISABLED; zring.axis = Vector3.AXIS_Y
		zring.shaded = false; zring.transparent = true
		zring.modulate = Color(0.55, 0.2, 0.7, 0.55)
		zring.pixel_size = (300.0 * battle.WS) / 256.0
		zring.position = battle._world_pos(dest, 0.065)
		battle._world.add_child(zring)
		var zt = battle._reg_tween()
		zt.tween_interval(4.5)
		zt.tween_property(zring, "modulate:a", 0.0, 0.5)
		zt.tween_callback(zring.queue_free)
		_shell_enter_stealth(uu))                               # 落地才羽化入隐(原瞬移即隐)
	for si in range(5):                                         # 沿途暗焰痕(纯视觉·Corki沿途火团黑烟·各1.8s烟先散火后灭)
		var sp: Vector2 = start.lerp(dest, (float(si) + 0.5) / 5.0) + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0))
		var st = battle._reg_tween()
		st.tween_interval(0.22 * (float(si) + 0.5) / 5.0)
		st.tween_callback(func() -> void: _shell_burn_patch(sp, 1.8))
	var zc: Vector2 = dest
	for i in range(BURN_TICKS):                                 # 暗影燃烧区(半径/时长/节拍全在常量里, 文案 {C:} 引用同一份)
		var fn = func():
			for o in battle._targeting._enemies_of(u):
				if o.get("alive", false) and o["pos"].distance_to(zc) <= BURN_RADIUS:
					battle._damage._apply_dot_stacks(o, "burn", maxi(1, int(round(u["atk"] * BURN_ATK_MULT))), u)
					o["spd_move_mult"] = BURN_SLOW_MULT
					o["spd_dbf_until"] = battle._t + BURN_TICK_SEC
		battle._pending_shots.append({"delay": float(i) * BURN_TICK_SEC, "fn": fn, "src": u})
	battle._beam_vfx("res://assets/sprites/vfx/fx-trail.png", start, dest, 60.0, Color(0.62, 0.22, 0.72, 0.7), 0.34)   # 暗影猛扑拖影


# ── 选3 多技能: 数据驱动伤害技 + 通用盾/治 (系数取自 pets.json detail 公式) ──
# opts: {phys,magic,true: ×casterATK 的 物理/魔法/真实系数; hp,mr: ×caster maxHp/MR 附加;
#        hits: 视觉段数(伤害总量不变); aoe: 全体敌; rider: 附带(burn/stun/slow/curse/atkdn/mrdn); name,color}
# 忍者·炸弹 (1:1 回合制 _ninja_bomb_throw / PoC ninja.js:523-619 编排 + 用户2026-07-11指定改动):
#   ninja-bomb.png 12帧【全程1.2s播一次】(球→引信→爆闪→火球→蘑菇云·repeat:0不循环); 炸弹【3段弹跳抛物线】0.4s 弹向【当前目标】→
#   引信到 0.8s 引爆(震屏+伤害·此刻帧正好走到爆炸帧8)→蘑菇云再0.4s播完销毁(1.2s)。
#   ★爆炸 = 落点 NINJA_BOMB_RADIUS(400码) 半径内敌人 1.1×ATK 物理 + -25%护甲(5秒·BUFF_SEC)。
#     半径=用户指定(回合制原"对全体敌方"无半径·用户2026-07-11「400码半径」)。放技射程2000码(远程扔·见 _SKILL_CAST_RANGE)。
func _sk_shell_copy(u: Dictionary, tgt) -> void:               # 龟壳·复制(封板·130龟能): 复制2敌方可用技(_COPYABLE白名单)·轮流依次释放(不同帧糊); 60%效果=伤害(dmg_out_mult)+护盾/治疗/DoT(battle._copy_fx_mult)
	var pool: Array = []
	for o in battle._targeting._enemies_of(u):
		for st in o.get("active_skills", []):
			var s = str(st)
			if battle._COPYABLE_SKILLS.has(s) and not pool.has(s):
				pool.append(s)
	pool.shuffle()
	if pool.size() >= 1:                                       # 2026-07-17镜像签名: 施放前两侧紫白残影错位闪现0.35s+白紫环(复制感)
		var glow = VfxTex._make_fire_glow_tex()
		for mi in range(2):
			var mg = Sprite3D.new()
			mg.texture = glow
			mg.billboard = BaseMaterial3D.BILLBOARD_ENABLED; mg.shaded = false; mg.transparent = true
			mg.pixel_size = (60.0 * battle.WS) / 128.0
			mg.modulate = Color(0.85, 0.7, 1.0, 0.85)
			var off: float = 30.0 if mi == 0 else -30.0
			mg.position = battle._world_pos((u["pos"] as Vector2) + Vector2(off, 0.0), 0.7)
			battle._world.add_child(mg)
			var mt = battle._reg_tween(); mt.set_parallel(true)
			mt.tween_property(mg, "position", battle._world_pos((u["pos"] as Vector2) + Vector2(off * 1.8, 0.0), 0.7), 0.35)
			mt.tween_property(mg, "modulate:a", 0.0, 0.35)
			mt.chain().tween_callback(mg.queue_free)
		battle._skill_ring(u["pos"], Color(0.85, 0.7, 1.0, 0.6), 52.0)
		u["dmg_out_mult"] = COPY_EFFECT                                # 60%效果(封板)·即时伤害经_apply_damage_from乘数
		battle._copy_fx_mult = COPY_EFFECT                                    # 60%效果·护盾/治疗/DoT
		battle._do_skill(u, tgt, str(pool[0]))                        # 第1个立即
		battle._copy_fx_mult = 1.0
		u["dmg_out_mult"] = 1.0
	if pool.size() >= 2:                                       # 第2个错峰0.6s(轮流依次·不同时糊帧)
		var p1: String = str(pool[1])
		var uu: Dictionary = u
		var fn = func():
			uu["dmg_out_mult"] = COPY_EFFECT
			battle._copy_fx_mult = COPY_EFFECT
			battle._do_skill(uu, battle._targeting._nearest_enemy(uu), p1)
			battle._copy_fx_mult = 1.0
			uu["dmg_out_mult"] = 1.0
		battle._pending_shots.append({"delay": 0.6, "fn": fn, "src": u})

# ============================================================================
#  效果积木 (可复用) — 治疗/护盾/控制/buff/DoT/吸血/累积/净化/叠层 (1:1 搬自 2D 版).
#  注: 3D 版血条 overlay 每帧统一刷新, 故去掉 2D 版各处的 _update_bars(u) 调用.
# ============================================================================
func _shell_apply_awaken(u: Dictionary) -> void:   # 气场觉醒一次(六属性+6%/暴击+12.5%·用户2026-07-28 12%→6%、25%→12.5%) + 金光爆发特效
	battle._damage._buff(u, "atk", AWAKEN_PCT, true, 9999.0); battle._damage._buff(u, "def", AWAKEN_PCT, true, 9999.0); battle._damage._buff(u, "mr", AWAKEN_PCT, true, 9999.0)
	battle._damage._buff(u, "lifesteal", AWAKEN_PCT, true, 9999.0)   # +6%吸血
	var ah: float = u["maxHp"] * AWAKEN_PCT; u["maxHp"] += ah; u["hp"] += ah   # +6%最大生命
	u["reflect"] = float(u.get("reflect", 0.0)) + AWAKEN_PCT   # 反伤+6% (回合制 auraAwaken.reflectPct=12; reflect是通用字段·受伤端_apply_damage_from已有反弹钩)
	u["crit"] += AWAKEN_CRIT; battle._recalc_stats(u)
	_shell_awaken_vfx(u)

func _shell_awaken_vfx(u: Dictionary) -> void:   # 觉醒金光爆发: 震屏+微顿帧 + 强金闪 + 双金环 + 金光柱 + 金光上腾 + "觉醒"飘字
	battle._shake(battle.JUICE_SHAKE_HEAVY)
	battle._hitstop = maxf(battle._hitstop, 0.06)
	battle._vfx._flash(u, Color(1.0, 0.92, 0.55))
	battle._skill_ring(u["pos"], Color(1.0, 0.84, 0.28, 0.9), 132.0)   # 外金环
	battle._skill_ring(u["pos"], Color(1.0, 0.95, 0.6, 0.9), 76.0)     # 内亮环
	battle._vfx._float_text(u["pos"] + Vector2(0, -88), "觉醒", Color(1.0, 0.86, 0.25))
	# 金光柱: 竖直上冲一束 (醒目, 不怕被伤害数字盖)
	var pil = Sprite3D.new()
	pil.texture = VfxTex._make_fire_glow_tex()
	pil.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pil.shaded = false; pil.transparent = true
	pil.pixel_size = 0.013
	pil.modulate = Color(1.0, 0.9, 0.45, 0.0)
	pil.scale = Vector3(0.55, 2.6, 1.0)
	pil.position = battle._world_pos(u["pos"], 0.7)
	battle._world.add_child(pil)
	var tp = battle._reg_tween(); tp.set_parallel(true)
	tp.tween_property(pil, "modulate:a", 0.9, 0.1)
	tp.tween_property(pil, "position", battle._world_pos(u["pos"], 1.6), 0.55)
	tp.chain().tween_property(pil, "modulate:a", 0.0, 0.28)
	tp.chain().tween_callback(pil.queue_free)
	# 金光上腾粒子 (更多更大)
	for i in range(14):
		var ang: float = TAU * float(i) / 14.0 + battle._juice_rng.randf_range(-0.2, 0.2)
		var dd: float = battle._juice_rng.randf_range(10.0, 50.0)
		var p: Vector2 = u["pos"] + Vector2(cos(ang), sin(ang)) * dd
		var spr = Sprite3D.new()
		spr.texture = VfxTex._make_fire_glow_tex()
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.pixel_size = 0.008
		spr.modulate = Color(1.0, 0.9, 0.45, 0.95)
		spr.scale = Vector3(0.6, 0.6, 0.6)
		spr.position = battle._world_pos(p, 0.5)
		battle._world.add_child(spr)
		var tw = battle._reg_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "position", battle._world_pos(p, 1.95 + battle._juice_rng.randf_range(0.0, 0.6)), 0.6)
		tw.tween_property(spr, "scale", Vector3(1.3, 1.3, 1.3), 0.6)
		tw.tween_property(spr, "modulate", Color(1.0, 0.72, 0.2, 0.0), 0.6)
		tw.chain().tween_callback(spr.queue_free)

func _shell_phase_tick(u: Dictionary, delta: float) -> void:
	# 护盾线性流失 (每帧扣, 不低于0) — 与相位独立, 始终推进
	if float(u.get("shell_shield_decay_rate", 0.0)) > 0.0 and float(u.get("_auraShieldVal", 0.0)) > 0.0:
		u["_auraShieldVal"] = maxf(0.0, float(u["_auraShieldVal"]) - float(u["shell_shield_decay_rate"]) * delta)
		if u["_auraShieldVal"] <= 0.0:
			u["shell_shield_decay_rate"] = 0.0
	# 冲击波扩张 + 逐敌一次性命中 (始终推进, 与相位独立)
	if u.get("shell_sw", null) != null:
		_shell_shockwave_tick(u, delta)
	# 相位推进
	var phase: String = u.get("shell_phase", "store")
	u["shell_timer"] = float(u.get("shell_timer", 0.0)) + delta
	if phase == "store":
		if u["shell_timer"] >= battle.SHELL_STORE_SEC:
			u["shell_timer"] = 0.0
			u["shell_phase"] = "cd"
			_shell_release(u)
	else:  # "cd"
		if u["shell_timer"] >= battle.SHELL_CD_SEC:
			u["shell_timer"] = 0.0
			u["shell_phase"] = "store"

# 释放: 捕获储能→清零→发缓慢冲击波(逐敌×40%物理)+ 获80%储能护盾(5秒流失)
# 释放: 捕获储能→清零→发缓慢冲击波(逐敌×40%物理)+ 获80%储能护盾(5秒流失)
func _shell_release(u: Dictionary) -> void:
	var se: float = float(u.get("store_energy", 0.0))
	u["store_energy"] = 0.0
	u["_auraEnergy"] = 0.0
	if se < 1.0:
		return
	# 1) 缓慢移动冲击波 (Image环贴图, 半径0→520px / 1.8s; 每敌只命中一次)
	_shell_haze(u)                                   # 起手空气扭曲(用户2026-07-17 Q3"开始阶段扭曲角色周围视角和空气")
	_shell_spawn_shockwave(u, int(se * RELEASE_DMG_PCT))
	# 2) 衰减护盾 = 80%储能, 5秒线性流失到0
	var amt: float = se * RELEASE_SHIELD_PCT
	u["_auraShieldVal"] = float(u.get("_auraShieldVal", 0.0)) + amt   # 金色储能护盾(特殊色, 1:1回合制aura盾)
	u["shell_shield_decay_rate"] = amt / battle.SHELL_SHIELD_SEC   # 每秒扣量 (按授予值算, 5秒清)

func _shell_haze(u: Dictionary) -> void:            # 释放起手·空气扭曲拟真(2026-07-17 Q3自设): 双层低alpha金glow反相脉动0.7s+2道气浪环升起
	var glow = VfxTex._make_fire_glow_tex()
	for i in range(2):
		var h = Sprite3D.new()
		h.texture = glow
		h.billboard = BaseMaterial3D.BILLBOARD_ENABLED; h.shaded = false; h.transparent = true
		h.pixel_size = (float(130 + i * 50) * battle.WS) / 128.0
		h.modulate = Color(1.0, 0.9, 0.55, 0.16)
		h.position = battle._world_pos(u["pos"], 0.7)
		h.scale = Vector3.ONE * (1.0 if i == 0 else 0.8)
		battle._world.add_child(h)
		var t = battle._reg_tween()
		for k in range(3):                          # 反相脉动=热浪抖动感
			t.tween_property(h, "scale", Vector3.ONE * (1.18 if i == 0 else 0.66), 0.12)
			t.tween_property(h, "scale", Vector3.ONE * (1.0 if i == 0 else 0.8), 0.12)
		t.tween_property(h, "modulate:a", 0.0, 0.15)
		t.tween_callback(h.queue_free)
	for i in range(2):                              # 气浪环从脚边升起(空气被顶开)
		var r = Sprite3D.new()
		r.texture = VfxTex._make_ring_texture(Color(1, 1, 1, 1))
		r.billboard = BaseMaterial3D.BILLBOARD_ENABLED; r.shaded = false; r.transparent = true
		r.pixel_size = (90.0 * battle.WS) / 96.0
		r.modulate = Color(1.0, 0.92, 0.6, 0.5)
		r.position = battle._world_pos(u["pos"], 0.3)
		battle._world.add_child(r)
		var rt = battle._reg_tween()
		rt.tween_interval(0.18 * float(i))
		rt.tween_property(r, "position", battle._world_pos(u["pos"], 1.6), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.parallel().tween_property(r, "modulate:a", 0.0, 0.5)
		rt.chain().tween_callback(r.queue_free)

# 冲击波节点 (Image环贴图躺平贴地; 绝不用 GradientTexture2D FILL_RADIAL → 会画方角)
# 2026-07-17 Q3"黄色远古冲击波": 双层波带(宽晕带+锐利细线波前)+6颗金星随波带转(远古符文感)
# 冲击波节点 (Image环贴图躺平贴地; 绝不用 GradientTexture2D FILL_RADIAL → 会画方角)
# 2026-07-17 Q3"黄色远古冲击波": 双层波带(宽晕带+锐利细线波前)+6颗金星随波带转(远古符文感)
func _shell_spawn_shockwave(u: Dictionary, dmg: int) -> void:
	var spr = Sprite3D.new()
	spr.texture = VfxTex._make_ring_texture(Color(1.0, 0.84, 0.22, 1.0))
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	spr.axis = Vector3.AXIS_Y                       # 躺平贴地
	spr.shaded = false
	spr.transparent = true
	spr.modulate = Color(1.0, 0.84, 0.22, 1.0)       # 黄色能量波(用户); alpha 起始满, 扩张中淡出
	spr.pixel_size = 0.0001                          # 起始 ~0 (扩张到 520px 直径)
	spr.position = battle._world_pos(u["pos"], 0.06)   # h≥0.06防掉地下(用户2026-07-17"不要特效大部分到地下")
	battle._world.add_child(spr)
	var front = Sprite3D.new()                      # 锐利波前(细线环·晕带+锐前沿=厚重远古)
	front.texture = VfxTex._make_thin_ring_tex()
	front.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	front.axis = Vector3.AXIS_Y
	front.shaded = false; front.transparent = true
	front.modulate = Color(1.0, 0.95, 0.55, 1.0)
	front.pixel_size = 0.0001
	front.position = battle._world_pos(u["pos"], 0.07)
	battle._world.add_child(front)
	var stars: Array = []
	var stex = VfxTex._make_star_texture()
	for i in range(6):                               # 6颗金星嵌波带随波转
		var sp = Sprite3D.new()
		sp.texture = stex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sp.shaded = false; sp.transparent = true
		sp.pixel_size = 0.008
		sp.modulate = Color(1.0, 0.88, 0.4, 0.95)
		sp.position = battle._world_pos(u["pos"], 0.25)
		battle._world.add_child(sp)
		stars.append(sp)
	# 状态: 中心/当前半径/已命中集合(逐敌一次)/伤害/节点
	u["shell_sw"] = {
		"node": spr,
		"node2": front,
		"stars": stars,
		"center": u["pos"],
		"t": 0.0,
		"radius": 0.0,
		"hit": {},          # 用 get_instance_id() 当键, 每敌只算一次
		"dmg": dmg,
		## ★冲击波是【创建时算伤害、扩张途中才逐敌命中】—— 与弹道同一个形状:
		##   飞行期间全局 `_last_dmg_type` 会被场上别的伤害覆写 ⇒ 命中时飘字捡别人的颜色。
		##   捕获创建那一刻的类型, 命中前还原(哨兵 DMGSENTINEL 实测抓到这一条)。
		"dtype": battle._last_dmg_type,
	}

# 冲击波每帧推进: 半径 0→520 / 1.8s; ring 直径=2×radius; 距中心被环刚扫过的敌人吃一次伤害
# 冲击波每帧推进: 半径 0→520 / 1.8s; ring 直径=2×radius; 距中心被环刚扫过的敌人吃一次伤害
func _shell_shockwave_tick(u: Dictionary, delta: float) -> void:
	var sw: Dictionary = u["shell_sw"]
	var spr = sw.get("node", null)
	sw["t"] = float(sw["t"]) + delta
	var frac: float = clampf(float(sw["t"]) / battle.SHELL_SW_SEC, 0.0, 1.0)
	var r: float = battle.SHELL_SW_RADIUS * frac
	sw["radius"] = r
	# 视觉: ring 贴图 96px 宽 → pixel_size 让直径 = 2r(px)×battle.WS(米/px)
	if spr != null and is_instance_valid(spr):
		spr.pixel_size = maxf(0.0001, (r * 2.0 * battle.WS) / 96.0)
		spr.modulate.a = 1.0 - frac * 0.55           # 边扩边淡 (终态 ~0.45, 保持可见到末尾)
	var front = sw.get("node2", null)                # 锐利波前同步扩(2026-07-17双层波带)
	if front != null and is_instance_valid(front):
		front.pixel_size = maxf(0.0001, (r * 2.0 * battle.WS) / 256.0)
		front.modulate.a = 1.0 - frac * 0.35
	var stars: Array = sw.get("stars", [])           # 金星嵌波带随波转
	for si in range(stars.size()):
		var sp = stars[si]
		if sp != null and is_instance_valid(sp):
			var sa: float = TAU * float(si) / 6.0 + frac * 2.0
			sp.position = battle._world_pos((sw["center"] as Vector2) + Vector2(cos(sa), sin(sa)) * r, 0.25)
	# 命中: 距中心 <= 当前半径 且未命中过的敌人 (环刚扫过) 各吃一次
	var center: Vector2 = sw["center"]
	var hit: Dictionary = sw["hit"]
	var dmg: int = int(sw["dmg"])
	if dmg > 0:
		for e in battle._targeting._enemies_of(u):
			var spr_e = e.get("sprite", null)        # 用立绘节点实例id当唯一键(每单位唯一; dict不能取instance_id)
			if spr_e == null or not is_instance_valid(spr_e):
				continue
			var eid: int = spr_e.get_instance_id()
			if hit.has(eid):
				continue
			if (e["pos"] - center).length() <= r:
				hit[eid] = true
				battle._damage.set_dtype(str(sw.get("dtype", battle._last_dmg_type)), e)   # 还原发射时的类型(见上面 "dtype")
				battle._damage._apply_damage_from(u, e, dmg, Color("#b0ffe0"))
	# 结束: 清理节点+状态(node2/stars一并清·不瞬删=波前已淡到0.65alpha自然收)
	if frac >= 1.0:
		if spr != null and is_instance_valid(spr):
			spr.queue_free()
		if front != null and is_instance_valid(front):
			front.queue_free()
		for sp2 in stars:
			if sp2 != null and is_instance_valid(sp2):
				sp2.queue_free()
		u["shell_sw"] = null

# ============================================================================
#  死亡钩子 (1:1 搬自 2D 版 _on_unit_death; 装备 on-kill/on-death Phase 3b 不调)
# ============================================================================