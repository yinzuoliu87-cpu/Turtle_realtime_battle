class_name BambooSystem
extends RefCounted
## 竹龟技能系统
## 类内名不变;外部名加 battle.

## ★★2026-08-22 文案根除: 生长(被动)这一组原来全在**主场景**的 `_tick_unit` 里,
##   一行三元表达式写着两套数(选没选「竹击」)。文案又各手写一遍。
## 【生长·蓄力强化下一发普攻】基础值 / 选了「竹击」后的强化值, 一一对应
const GROW_CD := 6.0             # 每几秒蓄力一次
const GROW_ATK_COEF := 0.75      # 追加魔法 = ×ATK + ×最大生命(下一行)
const GROW_HP_PCT := 0.08
const GROW_HEAL_PCT := 0.08      # 命中后生命球回复 = 最大生命 ×
const GROW_MAXHP_PER_ATK := 0.60 # 永久 + 最大生命 = 基础攻击力 ×(攻击力本身不涨)
const GROW_SMACK_ATK_COEF := 1.0   # ↓ 选「竹击」后的四个强化值
const GROW_SMACK_HP_PCT := 0.13
const GROW_SMACK_HEAL_PCT := 0.12
const GROW_SMACK_MAXHP_PER_ATK := 1.05

var battle

func _init(b) -> void:
	battle = b

# 竹叶强化命中: 敌人身上爆一下大淡绿命中特效(≈上半身大小·一下即散·用户2026-07-11).
func _bamboo_hit_splash(tgt: Dictionary) -> void:
	var tex = VfxTex._make_glow_texture()
	var tw = float(maxi(1, int(tex.get_width())))
	var big: float = (170.0 * battle.WS) / tw          # "很大"≈上半身大小(可调)
	var sp = Sprite3D.new()
	sp.texture = tex
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false; sp.transparent = true
	sp.modulate = Color(0.6, 1.0, 0.62, 0.0)    # 淡绿
	sp.pixel_size = big * 0.55
	sp.position = battle._world_pos(tgt["pos"], float(tgt.get("height", 0.0)) + 0.5)
	battle._world.add_child(sp)
	var t = battle._reg_tween(); t.set_parallel(true)
	t.tween_property(sp, "pixel_size", big, 0.09).set_ease(Tween.EASE_OUT)   # 爆开
	t.tween_property(sp, "modulate:a", 0.9, 0.05)
	t.chain().tween_property(sp, "modulate:a", 0.0, 0.2)                     # 即散
	t.chain().tween_callback(sp.queue_free)

# 全局: 被减速单位行走留短暂泥印(棕色泥渍, 贴地)
func _bamboo_orb_step(t: float, orb: Sprite3D, from_pos: Vector2, to_pos: Vector2, nframes: int, trail: Array) -> void:
	if not is_instance_valid(orb):
		return
	var base: Vector2 = from_pos.lerp(to_pos, t)
	var h: float = 1.0 + 1.5 * 4.0 * t * (1.0 - t)   # 抛物高度弧 (峰+1.5m)
	orb.position = battle._world_pos(base, h)
	if nframes > 1:
		orb.frame = int(t * float(nframes) * 2.0) % nframes
	if t > 0.05 and t < 0.93:
		var seg: int = int(t / 0.046)
		if seg > int(trail[0]):
			trail[0] = seg
			_bamboo_trail_dot(base, h)

func _bamboo_trail_dot(pos2d: Vector2, h: float) -> void:
	var dot = Sprite3D.new()
	dot.texture = VfxTex._make_glow_texture()
	dot.modulate = Color(0.49, 1.0, 0.7, 0.7)   # #7dffb3 绿
	dot.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dot.shaded = false
	dot.transparent = true
	dot.pixel_size = 0.006
	dot.position = battle._world_pos(pos2d, h)
	battle._world.add_child(dot)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(dot, "modulate:a", 0.0, 0.42)
	tw.tween_property(dot, "scale", Vector3.ONE * 0.3, 0.42)
	tw.chain().tween_callback(dot.queue_free)

func _bamboo_burst_step(t: float, b: Sprite3D, nframes: int) -> void:
	if not is_instance_valid(b):
		return
	if nframes > 1:
		b.frame = mini(nframes - 1, int(t * float(nframes)))
	b.modulate.a = 1.0 - maxf(0.0, (t - 0.6) / 0.4)

# 治疗绿光 (港回合制 _play_heal_glow): 绿光球从身体升起淡出 + 绿脉冲贴地环

func _sk_bamboo_smack(u: Dictionary, tgt) -> void:              # 竹叶龟·竹击(用户封板·120龟能): 钩全场最远敌·1.0A物理·眩晕0.5s·拉贴身·冰寒4秒(-20%攻/-20%移速); 蛋免控只吃伤
	var far = null
	var far_d = -1.0
	for o in battle._targeting._pick_enemies_of(u):   # ★单体定向(钩最远一个)走 battle._targeting._pick_enemies_of: 不锁训龟大师(场外·永远最远)+不可选中; 见 §PICK-TARGET(与珊瑚刺同类·用户2026-07-24)
		if not o.get("alive", false): continue
		var d: float = o["pos"].distance_to(u["pos"])
		if d > far_d:
			far_d = d; far = o
	if far == null: return
	var far_pos0: Vector2 = far["pos"]                          # 拉近前的原位(画竹藤用)
	battle._bolt_line(u["pos"], far_pos0, Color(0.22, 0.83, 0.33))     # 伸出竹藤(用户2026-07-06"伸出一条竹藤·打最远的敌人")
	battle._burst_vfx("res://assets/sprites/vfx/bamboo-vine.png", far_pos0, 120.0, 1.0)   # 藤钩勾住
	battle._damage._apply_damage_from(u, far, battle._atk_dmg(u, 1.0, far), Color("#39d353"))
	if not far.get("_eggImmune", false):                        # 蛋/免控只吃伤
		battle._damage._stun(far, 0.5, "_sk_bamboo_smack")
		battle._damage._buff(far, "atk", -0.20, true, 4.0)                     # 冰寒-20%攻4秒
		far["spd_move_mult"] = 0.8; far["spd_dbf_until"] = battle._t + 4.0   # 冰寒-20%移速4秒
		battle._hitstop = maxf(battle._hitstop, 0.05)                          # 抓住瞬间小顿(用户2026-07-11: 拽住得顿一下)
		var ff = far
		var uu = u
		var pull_fn = func() -> void:                           # 顿0.2s后再拽贴身
			if not ff.get("alive", false): return
			var pd: Vector2 = ff["pos"] - uu["pos"]
			if pd.length() > 1.0:
				ff["pos"] = uu["pos"] + pd.normalized() * 60.0     # 竹藤拽到贴身
			battle._bolt_line(uu["pos"], ff["pos"], Color(0.22, 0.83, 0.33))   # 收藤(收线感)
			battle._vfx._impact_particles(ff["pos"], float(ff.get("height", 0.0)))
			battle._skill_ring(uu["pos"], Color(0.22, 0.83, 0.33, 0.4), 54.0)   # 拉到脸上落点环
		battle._pending_shots.append({"delay": 0.2, "src": u, "fn": pull_fn})

func _sk_bamboo_spikes(u: Dictionary, tgt) -> void:            # 竹叶龟·竹刺阵(用户封板·130龟能·科加斯Q式): 当前目标为心300码·蓄力0.6s→竹刺·90%A+15%maxHp物理·击飞1.5s
	if tgt == null: return
	var c: Vector2 = tgt["pos"]
	var uu = u
	var spikes = func() -> void:
		if not uu.get("alive", false): return
		for i in range(14):   # 竹刺齐爆: 300码圈内铺一片从地冒起的绿竹刺(科加斯Q式·用户2026-07-11「要补刺」)
			var ang: float = TAU * float(i) / 14.0 + randf() * 0.45
			var rr: float = sqrt(randf()) * 285.0
			battle._spawn_bamboo_spike(c + Vector2(cos(ang), sin(ang)) * rr, randf_range(0.85, 1.3), 0.5)
		for o in battle._targeting._enemies_of(uu):
			if o.get("alive", false) and o["pos"].distance_to(c) <= 300.0:
				battle._damage._apply_damage_from(uu, o, battle._atk_dmg(uu, 0.9, o) + int(uu["maxHp"] * 0.15), Color("#39d353"))
				battle._spawn_bamboo_spike(o["pos"], 1.5, 0.5)   # 命中点更粗一根竹刺
				if not o.get("_eggImmune", false):
					battle._damage._knockback(uu, o, 70.0, 2.75)                # 击飞【1.5秒】(用户#12"击飞1.5秒"·滞空=2×(6.0×2.75)/22=1.5s·原vy_mult=1.5只给0.82s)
		battle._shake(0.06)
		battle._hitstop = maxf(battle._hitstop, 0.05)
	battle._skill_ring(c, Color(0.22, 0.83, 0.33, 0.4), 300.0)         # 蓄力预警圈
	battle._pending_shots.append({"delay": 0.6, "fn": spikes, "src": u})

func _sk_bamboo_heal(u: Dictionary) -> void:                     # 竹叶龟·自然恢复 ✅
	var allies = battle._targeting._allies_of(u, false)
	battle._vfx._play_heal_glow(u["pos"])
	if allies.is_empty():
		battle._damage._heal(u, u["maxHp"] * 0.15)
	else:
		battle._damage._heal(u, u["maxHp"] * 0.10)
		for o in allies:
			battle._damage._grant_shield(o, o["maxHp"] * 0.12, 4.0)   # 竹叶自然恢复·友军护盾(通用护盾4秒·封板L74)·[原注释误标"寒冰团队护盾"→那是ice commonTeamShield另有其函]
			battle._vfx._play_heal_glow(o["pos"])

