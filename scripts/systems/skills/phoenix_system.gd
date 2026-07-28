class_name PhoenixSystem
extends RefCounted
## 凤凰·烈焰扇/灼烧系统(从主场景抽出)
## 类内簇函数名不变→内部互调零改动;外部名加 battle. 前缀。

## ★凤凰数值单一事实源(用户2026-07-28 削弱·整只 94.8% 全表第一)。文案在 data/pets.json。
const SCALD_BURN_COEF := 0.6      # 烫伤: 灼烧层数 = ×ATK (1.0→0.6)
const NIRVANA_BURN_COEF := 0.3    # 涅槃(首死复活): 对全体敌灼烧层数 = ×ATK (原走全局 _default_burn_stacks 0.67)
const NIRVANA_HP_PCT := 0.25      # 涅槃: 复活生命 = ×最大生命 (0.30→0.25)
const NIRVANA_ENH_HP_PCT := 0.60  # 强化涅槃: 复活生命 = ×最大生命 (1.00→0.60)

var battle

func _init(b) -> void:
	battle = b

# 凤凰持续喷火 channel (Botworld Flamer式: 一直喷不脉冲; 每0.5s结算伤害; 边喷边kite; 放技能由状态机打断)
func _phoenix_flame_channel(u: Dictionary, tgt: Dictionary, delta: float) -> void:
	u["face_right"] = tgt["pos"].x > u["pos"].x      # 朝向目标(原写的是 u["flip_h"] —— 立绘朝向实际由 face_right 驱动, 那行没人读=死写法·2026-07-19)
	# ★贴地扇形火焰(用户2026-07-15拍板·照兰博Q官方参考): shader扇形(条纹火舌+暗烟裹边+不透明) + 喷嘴白热星芒闪 + 少量火星
	var want: float = (tgt["pos"] - u["pos"]).angle() if (tgt["pos"] - u["pos"]).length() > 1.0 else float(u.get("phx_aim", 0.0))
	if battle._t - float(u.get("phx_aim_t", -9.9)) > 0.4:   # 停喷过0.4s重开→直接对准(不从旧方向扫)
		u["phx_aim"] = want
	u["phx_aim"] = lerp_angle(float(u.get("phx_aim", want)), want, clampf(delta * 5.5, 0.0, 1.0))   # 换目标时锥平滑扫过去(~0.3s·参考: 喷射器有惯性非瞬跳)
	u["phx_aim_t"] = battle._t
	_phoenix_sector_indicator(u, tgt)                # 主视觉: 贴地扇形火焰shader(方向=phx_aim)
	u["phx_core_t"] = float(u.get("phx_core_t", 0.0)) + delta
	while u["phx_core_t"] >= 0.06:                   # 喷嘴白热星芒闪(参考: 嘴部一小簇白热放射光·非贴脸大图)
		u["phx_core_t"] -= 0.06
		_phoenix_nozzle_flash(u, tgt)
	u["phx_spark_t"] = float(u.get("phx_spark_t", 0.0)) + delta
	while u["phx_spark_t"] >= 0.09:                  # 少量飞散火星(细节)
		u["phx_spark_t"] -= 0.09
		_phoenix_flame_puff(u, tgt)
	u["phx_burn_t"] = float(u.get("phx_burn_t", 0.0)) + delta
	while u["phx_burn_t"] >= 0.5:                    # 每0.5s 伤害结算
		u["phx_burn_t"] -= 0.5
		_phoenix_flame_cone(u, tgt)

# 喷火伤害结算: 扇形内全部敌人 0.2ATK×(1+攻速) 魔法 + round(0.07ATK) 灼烧层 (用户2026-06-30)
# 喷火伤害结算: 扇形内全部敌人 0.2ATK×(1+攻速) 魔法 + round(0.07ATK) 灼烧层 (用户2026-06-30)
func _phoenix_flame_cone(u: Dictionary, tgt: Dictionary) -> void:
	var atk: float = u["atk"]
	var aspd: float = 1.0 / maxf(0.05, float(u.get("atk_interval", 0.5)))   # 攻速=1/间隔
	var mag: float = battle.PHX_FLAME_MAG_COEF * atk * (1.0 + aspd)
	var burn_stacks: int = maxi(1, roundi(atk * battle.PHX_FLAME_BURN_COEF))
	var origin: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - origin
	if dir.length() < 1.0:
		return
	var aim: float = float(u.get("phx_aim", dir.angle()))   # 伤害锥=平滑瞄准角(与视觉锥一致·扫到哪烧到哪)
	dir = Vector2(cos(aim), sin(aim))
	var rng: float = float(u.get("atk_range", 400.0))
	var half_cos: float = cos(deg_to_rad(battle.PHX_CONE_HALF_DEG))
	for e in battle._targeting._enemies_of(u):
		if not e.get("alive", false):
			continue
		var to_e: Vector2 = e["pos"] - origin
		var d: float = to_e.length()
		if d > rng or d < 1.0:
			continue
		if dir.dot(to_e / d) < half_cos:
			continue
		battle._damage._apply_damage_from(u, e, battle._resolve_dmg(u, mag, e, true), Color("#4dabf7"))
		battle._damage._apply_dot_stacks(e, "burn", burn_stacks, u)
		battle._vfx._flash(e, Color("#ff8a3a"))

# 单颗喷火苗: 嘴部喷出→沿锥角向外冲(火舌位移感), 软发光blob叠成顺滑火流, 黄白→橙→红透+边冲边长大
# 单颗喷火苗: 嘴部喷出→沿锥角向外冲(火舌位移感), 软发光blob叠成顺滑火流, 黄白→橙→红透+边冲边长大
func _phoenix_nozzle_flash(u: Dictionary, tgt: Dictionary) -> void:   # 喷嘴白热星芒闪(照兰博Q参考: 嘴部一小簇白热放射光·快闪; 替换原贴脸dragon-flame帧=用户2026-07-15"脸上莫名图片")
	var origin: Vector2 = u["pos"]
	var cdir: Vector2 = tgt["pos"] - origin
	if cdir.length() < 1.0:
		return
	var _na: float = float(u.get("phx_aim", cdir.angle()))           # 平滑瞄准角(与锥同步扫)
	cdir = Vector2(cos(_na), sin(_na))
	var mouth: Vector2 = origin + cdir * 34.0                        # 嘴前方(不贴脸)
	var glow := Sprite3D.new()                                       # 白热核心光
	glow.texture = VfxTex._make_fire_glow_tex()
	glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	glow.shaded = false
	glow.transparent = true
	glow.pixel_size = 0.008
	glow.modulate = Color(1.0, 0.98, 0.9, 0.95)
	glow.scale = Vector3(0.7, 0.7, 0.7)
	glow.position = battle._world_pos(mouth, 0.72)
	battle._world.add_child(glow)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(glow, "scale", Vector3(1.25, 1.25, 1.25), 0.1)
	tw.tween_property(glow, "modulate:a", 0.0, 0.1)
	tw.chain().tween_callback(glow.queue_free)
	for i in range(2):                                               # 2道放射白色小光条(星芒感·锥内前向)
		var sa: float = cdir.angle() + battle._juice_rng.randf_range(-0.5, 0.5)
		var endp: Vector2 = mouth + Vector2(cos(sa), sin(sa)) * battle._juice_rng.randf_range(26.0, 60.0)
		battle._bolt_line(mouth, endp, Color(1.0, 0.97, 0.85, 0.9))

func _phoenix_flame_puff(u: Dictionary, tgt: Dictionary) -> void:   # 飞散火星(dragon-flame小火苗动画·喷流上的细节碎火)
	var origin: Vector2 = u["pos"]
	var dir: Vector2 = tgt["pos"] - origin
	if dir.length() < 1.0:
		return
	dir = dir.normalized()
	var rng: float = float(u.get("atk_range", 400.0))
	var base_ang: float = float(u.get("phx_aim", dir.angle()))   # 平滑瞄准角(与锥同步扫)
	var half: float = deg_to_rad(battle.PHX_CONE_HALF_DEG)
	var ang: float = base_ang + battle._juice_rng.randf_range(-half, half) * 0.65   # 收紧火锥→定向喷流(非散开)
	var travel: float = battle._juice_rng.randf_range(rng * 0.55, rng * 1.0)
	var mouth: Vector2 = origin + Vector2(cos(base_ang), sin(base_ang)) * 24.0
	var endp: Vector2 = origin + Vector2(cos(ang), sin(ang)) * travel
	var start_p: Vector2 = mouth.lerp(endp, battle._juice_rng.randf_range(0.0, 0.5))   # 沿喷流线随机起点→火流从口到尖铺满(非全堆在口部=散篝火)
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/sprites/vfx/dragon-flame.png")   # 8帧动画火焰(烧动感·非静态软光点)
	spr.hframes = 8
	spr.frame = battle._juice_rng.randi() % 8
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = 0.006
	spr.modulate = Color(1.0, 0.95, 0.72, 0.95)
	spr.scale = Vector3(0.4, 0.4, 0.4)
	spr.position = battle._world_pos(start_p, 0.95)
	battle._world.add_child(spr)
	var life: float = battle._juice_rng.randf_range(0.26, 0.4)
	var hend: float = 0.95 + battle._juice_rng.randf_range(0.05, 0.5)   # 火星往上飘散
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(spr, "position", battle._world_pos(endp, hend), life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)   # 喷出去(先快后慢)
	tw.tween_property(spr, "scale", Vector3(1.1, 1.1, 1.1), life)      # 边喷边胀
	tw.tween_property(spr, "modulate", Color(0.95, 0.3, 0.06, 0.0), life)   # 黄白→暗红透
	tw.tween_method(func(p: float) -> void:                            # 帧循环=火焰跳动(烧动感)
		if is_instance_valid(spr): spr.frame = int(p * 18.0) % 8
	, 0.0, 1.0, life)
	tw.chain().tween_callback(spr.queue_free)

# 灼烧特效 (自设计, 不用回合制): 燃烧单位身上窜升腾软光小火苗 (黄→红透+缩, 边燃边升)
# 喷火扇形AOE指示: 贴地 淡橙填充 + 亮橙边轮廓 (边界明确, 跟伤害扇形一致); 持续刷新跟目标, 停喷由_tick_effects隐藏
func _phoenix_sector_indicator(u: Dictionary, tgt: Dictionary) -> void:
	var sect = u.get("flame_sector", null)
	if sect == null or not is_instance_valid(sect):
		sect = MeshInstance3D.new()
		sect.mesh = ImmediateMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/flame_cone.gdshader")
		sect.material_override = mat
		sect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		battle._world.add_child(sect)
		u["flame_sector"] = sect
	sect.visible = true
	u["flame_sector_t"] = battle._t + 0.05
	(sect.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.9 + 0.1 * sin(battle._t * 11.0))   # 强度轻跳(烧动)
	var hist: Array = u.get("phx_hist", [])                       # 喷射历史[t,角,开]: 分环回放→停喷火飞完才灭/转向拖尾(用户2026-07-15"完整运动")
	hist.append([battle._t, float(u.get("phx_aim", 0.0)), 1.0])
	while hist.size() > 90: hist.pop_front()
	u["phx_hist"] = hist
	if not _phoenix_build_flame_mesh(u):
		sect.visible = false

func _phoenix_build_flame_mesh(u: Dictionary) -> bool:   # 分环建扇形mesh: 第r环回放r×飞行时间前的(角,开)→火锋推进/停喷外飘/转向弯流全自然涌现; 返回false=全灭
	var sect = u.get("flame_sector", null)
	if sect == null or not is_instance_valid(sect): return false
	var im: ImmediateMesh = sect.mesh
	im.clear_surfaces()
	var hist: Array = u.get("phx_hist", [])
	if hist.is_empty(): return false
	var R := 12
	var N := 12
	var ring_a: Array = []
	var ring_on: Array = []
	var any := false
	for i in range(R + 1):
		var s: Array = battle._phx_hist_sample(hist, battle._t - (float(i) / float(R)) * battle.PHX_FLIGHT_T)
		ring_a.append(float(s[0])); ring_on.append(float(s[1]))
		if float(s[1]) > 0.02: any = true
	if not any: return false
	var origin: Vector2 = u["pos"]
	var half: float = deg_to_rad(battle.PHX_CONE_HALF_DEG)
	var rng: float = float(u.get("atk_range", 400.0)) * 0.92
	var mouth: Vector2 = origin + Vector2(cos(ring_a[0]), sin(ring_a[0])) * 18.0
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(R):
		for j in range(N):
			var f0: float = float(j) / float(N)
			var f1: float = float(j + 1) / float(N)
			var v00: Vector2 = battle._phx_fan_pt(mouth, ring_a[i], half, rng, float(i) / float(R), f0)
			var v01: Vector2 = battle._phx_fan_pt(mouth, ring_a[i], half, rng, float(i) / float(R), f1)
			var v10: Vector2 = battle._phx_fan_pt(mouth, ring_a[i + 1], half, rng, float(i + 1) / float(R), f0)
			var v11: Vector2 = battle._phx_fan_pt(mouth, ring_a[i + 1], half, rng, float(i + 1) / float(R), f1)
			var c0 := Color(1, 1, 1, ring_on[i])
			var c1 := Color(1, 1, 1, ring_on[i + 1])
			var r0: float = float(i) / float(R)
			var r1: float = float(i + 1) / float(R)
			im.surface_set_color(c0); im.surface_set_uv(Vector2(f0, r0)); im.surface_add_vertex(battle._world_pos(v00, 0.12))
			im.surface_set_color(c1); im.surface_set_uv(Vector2(f0, r1)); im.surface_add_vertex(battle._world_pos(v10, 0.12))
			im.surface_set_color(c1); im.surface_set_uv(Vector2(f1, r1)); im.surface_add_vertex(battle._world_pos(v11, 0.12))
			im.surface_set_color(c0); im.surface_set_uv(Vector2(f0, r0)); im.surface_add_vertex(battle._world_pos(v00, 0.12))
			im.surface_set_color(c1); im.surface_set_uv(Vector2(f1, r1)); im.surface_add_vertex(battle._world_pos(v11, 0.12))
			im.surface_set_color(c0); im.surface_set_uv(Vector2(f1, r0)); im.surface_add_vertex(battle._world_pos(v01, 0.12))
	im.surface_end()
	return true

func _phoenix_scald_hit(u: Dictionary, tgt, fb) -> void:
	if is_instance_valid(fb):
		fb.queue_free()
	if tgt == null or not tgt.get("alive", false):
		return
	# 封板: 火球命中先破50%护盾(破盾碎裂)→再落1.5A魔法穿透→灼烧+攻防抗各-15%+治疗削减
	battle._apply_skill_extras(u, tgt, {"shieldBreak": 0.5, "atkDown": 0.15, "defDown": 0.15, "mrDown": 0.15, "healCut": 0.5})
	battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, 1.5, tgt, true), Color("#4dabf7"))   # 1.5ATK魔法(打已破的盾, 更多穿透到血)
	battle._damage._apply_dot_stacks(tgt, "burn", maxi(1, roundi(float(u["atk"]) * SCALD_BURN_COEF)), u)   # 烫伤灼烧层
	battle._vfx._flash(tgt, Color("#ff8a3a"))
	_phoenix_flame_burst(tgt["pos"])

# 火焰爆发: 命中点炸开一圈软光火苗 + 亮环
# 火焰爆发: 命中点炸开一圈软光火苗 + 亮环
func _phoenix_flame_burst(pos2d: Vector2) -> void:
	battle._skill_ring(pos2d, Color(1.0, 0.55, 0.2, 0.7), 52.0)
	for i in range(12):
		var ang: float = TAU * float(i) / 12.0 + battle._juice_rng.randf_range(-0.2, 0.2)
		var d: float = battle._juice_rng.randf_range(10.0, 46.0)
		var p: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * d
		var spr := Sprite3D.new()
		spr.texture = VfxTex._make_fire_glow_tex()
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.pixel_size = 0.009
		spr.modulate = Color(1.0, 0.8, 0.4, 0.95)
		spr.scale = Vector3(0.5, 0.5, 0.5)
		spr.position = battle._world_pos(pos2d, 0.7)
		battle._world.add_child(spr)
		var tw = battle._reg_tween()
		tw.set_parallel(true)
		tw.tween_property(spr, "position", battle._world_pos(p, 0.9 + battle._juice_rng.randf_range(0.0, 0.4)), 0.34)
		tw.tween_property(spr, "scale", Vector3(1.3, 1.3, 1.3), 0.34)
		tw.tween_property(spr, "modulate", Color(0.9, 0.25, 0.05, 0.0), 0.34)
		tw.chain().tween_callback(spr.queue_free)

# 火球抛物线飞行 (t:0→1; 高度 lerp + sin峰=抛起弧线) + 火焰拖尾

# 凤凰·烫伤 ✅: 蓄力投掷火球(1.5ATK魔法+1ATK灼烧+破盾/减攻防抗/治疗削减), 命中爆开 (用户)
func _sk_phoenix_scald(u: Dictionary, tgt) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	var dir: Vector2 = tgt["pos"] - u["pos"]
	if dir.length() < 1.0:
		dir = Vector2(1, 0)
	dir = dir.normalized()
	var mouth: Vector2 = u["pos"] + dir * 18.0
	var fb = Sprite3D.new()
	fb.texture = VfxTex._make_fire_glow_tex()
	fb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fb.shaded = false
	fb.transparent = true
	fb.pixel_size = 0.011
	fb.modulate = Color(1.0, 0.85, 0.45, 0.95)
	fb.scale = Vector3(0.4, 0.4, 0.4)
	fb.position = battle._world_pos(mouth, 1.05)
	battle._world.add_child(fb)
	var tgt_pos: Vector2 = tgt["pos"]
	var tw = battle._reg_tween()
	tw.tween_property(fb, "scale", Vector3(1.9, 1.9, 1.9), 0.30)             # 蓄力(火球长大)
	tw.parallel().tween_property(fb, "modulate", Color(1.0, 0.40, 0.12, 1.0), 0.30)
	tw.tween_method(battle._scald_arc.bind(fb, mouth, tgt_pos), 0.0, 1.0, 0.42)        # 投掷
	tw.tween_callback(_phoenix_scald_hit.bind(u, tgt, fb))

func _sk_phoenix_lavashield(u: Dictionary) -> void:              # 凤凰龟·熔岩盾 (用户2026-07-07: 3.5A护盾4秒+反击0.14A魔法)
	battle._damage._grant_shield(u, u["atk"] * 3.5, 4.0)   # 凤凰熔岩盾4秒(与反击窗口lava_shield_until同步·封板)
	u["lava_shield_until"] = battle._t + 4.0          # 4秒内每受一段攻击反击0.14×ATK魔法(见_apply_damage_from)
	battle._skill_ring(u["pos"], Color(1.0, 0.5, 0.2, 0.5), 50.0)

func _sk_phoenix_haste(u: Dictionary) -> void:                   # 凤凰龟·技三主动 (用户2026-07-07: 自身+50%攻速+50%移速4秒·配合喷火随攻速增伤; 强化涅槃被动在spawn施加)
	u["haste_mult"] = 1.5; u["haste_until"] = battle._t + 4.0          # +50%攻速(复用祝福haste机制)
	u["spd_move_mult"] = 1.5; u["spd_dbf_until"] = battle._t + 4.0     # +50%移速(复用spd_move_mult机制)
	battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 84.0, Color(1.0, 0.55, 0.15, 0.6), 4.0)   # 烈焰加速火环(强化涅槃+50%攻速移速4秒)

