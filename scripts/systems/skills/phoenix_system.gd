class_name PhoenixSystem
extends RefCounted
## 凤凰·烈焰扇/灼烧系统(从主场景抽出)
## 类内簇函数名不变→内部互调零改动;外部名加 battle. 前缀。

## ★凤凰数值单一事实源(用户2026-07-28 削弱·整只 94.8% 全表第一)。文案在 data/pets.json。
## 【烫伤】命中先破盾, 再打魔法伤 + 灼烧层 + 四项负面(均同一时长)。
## 【灼烧(普攻·持续喷火)】不随攻速停顿, 每 TICK 秒结算一次。
const FLAME_TICK_SEC := 0.5       # 每几秒结算一次
const FLAME_ARC_DEG := 70.0       # 身前扇形张角(全角·度)·★事实源在这里
const FLAME_ARC_HALF := FLAME_ARC_DEG * 0.5   # 推导, 不另写 35 —— 原来主场景存的就是这个半角
const FLAME_MOVE_MULT := 0.5      # 喷火时移动速度 ×
const SCALD_ATK_COEF := 1.5       # ×ATK 魔法
const SCALD_SHIELD_BREAK := 0.5   # 破坏目标护盾的比例
const SCALD_STAT_DOWN := 0.15     # 攻击力/护甲/魔抗 各降低
const SCALD_HEALCUT := 0.5        # 治疗削减比例
## 灼烧负面的持续 = 主场景通用 BUFF_SEC(_apply_skill_extras 不传 Dur 就吃它),
## 这里【不再另存一份】—— 存了就会和 BUFF_SEC 各走各的。
const SCALD_BURN_COEF := 0.5      # 烫伤: 灼烧层数 = ×ATK (1.0→0.6→0.5·用户2026-07-28)
## 涅槃演出总时长(秒) —— 用户 2026-08-13:「复活需要改为有一个2.5秒的演出」。
## 三拍: 0~0.6 灰烬定格 / 0.6~1.9 聚火升腾 / 1.9~2.5 破壳展翼。
## ★结算(跳血条 + 全体灼烧 + 治疗削减)落在**展翼那一刻**, 不是死的瞬间。
## 【熔岩盾】护盾 + 持盾期反击, 两者同一时长(反击窗口就是护盾窗口)。
const LAVA_SHIELD_COEF := 3.5     # 盾量 = ×ATK
const LAVA_SHIELD_SEC := 4.0      # 持续(秒)·同时是反击窗口
const LAVA_RETALIATE := 0.14      # 每受一段攻击反击 ×ATK 魔法(真值在 battle_damage)
## 【涅槃】首死复活 + 全体灼烧 + 治疗削减(时长走通用 BUFF_SEC)。
const NIRVANA_HEALCUT := 0.5      # 治疗削减比例
## 【强化涅槃】主动的龟能消耗(真值由 SkillEnergy.SKILL_COST 反过来引用本常量)。
const NIRVANA_ENERGY := 120.0
const NIRVANA_SHOW_SEC := 2.5
const NIRVANA_ASH_SEC := 0.6      ## 第一拍: 灰烬定格
const NIRVANA_GATHER_SEC := 1.3   ## 第二拍: 聚火升腾(0.6 → 1.9)
const NIRVANA_BURN_COEF := 0.3    # 涅槃(首死复活): 对全体敌灼烧层数 = ×ATK (原走全局 _default_burn_stacks 0.67)
const NIRVANA_HP_PCT := 0.25      # 涅槃: 复活生命 = ×最大生命 (0.30→0.25)
const NIRVANA_ENH_HP_PCT := 0.60  # 强化涅槃: 复活生命 = ×最大生命 (1.00→0.60)
## 【强化涅槃·主动】自身短时增益
const NIRVANA_ENH_ASPD := 0.50    # 攻击速度 +
const NIRVANA_ENH_SPD := 0.50     # 移动速度 +
const NIRVANA_ENH_SEC := 4.0      # 两项持续(秒)
const NIRVANA_ENH_ATK := 0.20     # 复活后永久 + 攻击力
const NIRVANA_ENH_ASPD_MULT := 1.0 + NIRVANA_ENH_ASPD   # 推导, 不另写 1.5
const NIRVANA_ENH_SPD_MULT := 1.0 + NIRVANA_ENH_SPD

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
	while u["phx_burn_t"] >= FLAME_TICK_SEC:                    # 每0.5s 伤害结算
		u["phx_burn_t"] -= FLAME_TICK_SEC
		_phoenix_flame_cone(u, tgt)

# 喷火伤害结算: 扇形内全部敌人 PHX_FLAME_MAG_COEF(0.2)ATK×(1+攻速) 魔法 + round(PHX_FLAME_BURN_COEF(0.04)×ATK) 灼烧层 (用户2026-06-30; 灼烧 0.07→0.04 用户2026-07-28削弱)
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
	var rng: float = battle._eff_range(u)
	var half_cos: float = cos(deg_to_rad(FLAME_ARC_HALF))
	## ★★这一跳里【离凤凰最近的那个】要走一次 on-hit(用户 2026-08-13:
	##   「火焰每0.5跳的时候给最近的onhit, 比如触发竹叶装备」)。
	##   由来: 喷火走的是范围结算, **一次都不碰 on-hit 钩子** ⇒ 竹弓/金弹/腐蚀这类
	##   "命中时触发"的装备在凤凰身上等于完全不生效。
	##   ★只给【一个】: 扇形里可能站着五个人, 每人都触发一次会让装备特效直接翻五倍。
	##   ★节拍不变(仍是 0.5 秒一跳)、伤害数值也不变 —— 用户明确「那以0.5来吧」。
	var nearest = null
	var nearest_d: float = INF
	var burned: int = 0
	## ★★两趟, 不是一趟(v0.19.145 改): `_apply_damage_from` 内部【本来就会调 `_eq_on_hit`】
	##   (battle_damage.gd:303)。所以 on-hit 装备在凤凰身上**一直是通的**, 只是走 `basic=false`。
	##   v0.19.144 之前我在循环外又补了一次 `_eq_on_hit(u, nearest, ..., true)` ——
	##   那是**第二次**调用: 不看 `basic` 标志的 on-hit 装备, 最近那个敌人每跳被触发两次。
	##   正解: 先定出最近的, 再打伤害时把 `basic` 直接**传进去** ⇒ 每人恰好一次,
	##   最近的那次带普攻标志。
	var cone: Array = []
	for e in battle._targeting._enemies_of(u):
		if not e.get("alive", false):
			continue
		var to_e: Vector2 = e["pos"] - origin
		var d: float = to_e.length()
		if d > rng or d < 1.0:
			continue
		if dir.dot(to_e / d) < half_cos:
			continue
		cone.append(e)
		if d < nearest_d:
			nearest_d = d
			nearest = e
	for e2 in cone:
		var is_near: bool = nearest != null and is_same(e2, nearest)   # ★单位字典比较一律 is_same(CLAUDE.md §3.2)
		battle._damage._apply_damage_from(u, e2, battle._resolve_dmg(u, mag, e2, true), Color("#4dabf7"),
			0.0, false, false, false, false, false, is_near)
		battle._damage._apply_dot_stacks(e2, "burn", burn_stacks, u)
		battle._vfx._flash(e2, Color("#ff8a3a"))
		burned += 1
	## ★on-hit 放在伤害结算【之后】: 有些 on-hit 装备读的是"这一下打了多少",
	##   放前面它读到的是上一跳的账。
	## ★★`basic = true` —— 用户 2026-08-13 明确「我的意思就是触发普攻的 onhit」:
	##   凤凰的喷火**就是它的普攻**(它没有另外的普攻动作), 所以这一跳要当成一次普攻命中,
	##   连"每第 N 次普攻"那类计数器(090 的浪潮、077 的充能…)也一起推进。
	##   我第一版写的 false(按技能命中算), 那样竹叶这类只认普攻的装备照样不触发。
	if nearest is Dictionary and (nearest as Dictionary).get("alive", false):
		## ★on-hit 不在这里调了 —— 它已经在上面那趟 `_apply_damage_from(..., basic=is_near)`
		##   里走过一次。这里只补【普攻计数器】那条钩子, 它不在伤害链上。
		## ★★v0.19.144 补上 v0.19.141 漏掉的另一半(用户实测「143 为什么没触发竹制弓箭」):
		##   装备有【两个】普攻钩子, 上一版只接了 `_eq_on_hit`(每次命中: 腐蚀/毒/金弹…),
		##   而 039 竹制弓箭的判据是「每第 3 段普攻」——它住在 `_eq_on_basic_attack` 的
		##   计数器里, 那个函数只被 `_basic_attack` 调, 而凤凰在 `_sim_step` 里
		##   (`elif u["id"] == "phoenix"`)就分支去喷火了, **一次都没走到 `_basic_attack`**。
		##   ⇒ 同函数里的 008 珊瑚刺 / 017 不沉之锚 / 027 电棍 在凤凰身上也一并复活。
		##   顺序: 放在伤害之后, 与上面 `_eq_on_hit` 同一条纪律(读得到这一跳的账)。
		battle._equip_sys._eq_on_basic_attack(u, nearest)
		u["_phx_onhit_n"] = int(u.get("_phx_onhit_n", 0)) + 1   # 同步触发证据(门禁数它)
		u["_phx_basic_n"] = int(u.get("_phx_basic_n", 0)) + 1   # 普攻计数钩子的独立证据(门禁数它)

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
	var rng: float = battle._eff_range(u)
	var base_ang: float = float(u.get("phx_aim", dir.angle()))   # 平滑瞄准角(与锥同步扫)
	var half: float = deg_to_rad(FLAME_ARC_HALF)
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
	var half: float = deg_to_rad(FLAME_ARC_HALF)
	var rng: float = battle._eff_range(u) * 0.92
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
	battle._apply_skill_extras(u, tgt, {"shieldBreak": SCALD_SHIELD_BREAK, "atkDown": SCALD_STAT_DOWN, "defDown": SCALD_STAT_DOWN, "mrDown": SCALD_STAT_DOWN, "healCut": SCALD_HEALCUT})
	battle._damage._apply_damage_from(u, tgt, battle._atk_dmg(u, SCALD_ATK_COEF, tgt, true), Color("#4dabf7"))   # 1.5ATK魔法(打已破的盾, 更多穿透到血)
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

# 凤凰·烫伤 ✅: 蓄力投掷火球(1.5ATK魔法+SCALD_BURN_COEF(0.5)ATK灼烧+破盾/减攻防抗/治疗削减), 命中爆开 (用户)
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
	battle._damage._grant_shield(u, u["atk"] * LAVA_SHIELD_COEF, LAVA_SHIELD_SEC)   # 凤凰熔岩盾4秒(与反击窗口lava_shield_until同步·封板)
	u["lava_shield_until"] = battle._t + LAVA_SHIELD_SEC          # 4秒内每受一段攻击反击0.14×ATK魔法(见_apply_damage_from)
	battle._skill_ring(u["pos"], Color(1.0, 0.5, 0.2, 0.5), 50.0)

func _sk_phoenix_haste(u: Dictionary) -> void:                   # 凤凰龟·技三主动 (用户2026-07-07: 自身+50%攻速+50%移速4秒·配合喷火随攻速增伤; 强化涅槃被动在spawn施加)
	u["haste_mult"] = NIRVANA_ENH_ASPD_MULT; u["haste_until"] = battle._t + NIRVANA_ENH_SEC          # +50%攻速(复用祝福haste机制)
	u["spd_move_mult"] = 1.5; u["spd_dbf_until"] = battle._t + 4.0     # +50%移速(复用spd_move_mult机制)
	battle._aura_vfx("res://assets/sprites/vfx/fx-glow-ring.png", u, 84.0, Color(1.0, 0.55, 0.15, 0.6), 4.0)   # 烈焰加速火环(强化涅槃+50%攻速移速4秒)


## 涅槃三拍演出。★不用 tween: 计时走 `_pending_shots`(sim 时钟) ——
##   tween 在无头下推不动, 门禁就永远验不了"到点才施加"(CLAUDE.md §3.5)。
##   这里只建节点与逐帧推进的句柄, 真正的"回来"由主场景那条 pending 完成。
func nirvana_show(u: Dictionary, _pct: float) -> void:
	if not is_instance_valid(battle._world):
		return
	var p: Vector2 = Vector2(u["pos"])
	## ① 灰烬定格: 脚下一圈缓慢收拢的余烬环(暗红), 明确"它死了"
	battle._vfx._syn.ground_ring(p, Color(0.55, 0.12, 0.05, 0.85), 46.0, true, NIRVANA_ASH_SEC)
	## ② 聚火升腾: 火星向中心汇聚 + 一根上升火柱
	for i in range(10):
		battle._pending_shots.append({"delay": NIRVANA_ASH_SEC + 0.10 * float(i), "src": u,
			"fn": func() -> void:
				if u.get("alive", false):
					_phoenix_flame_burst(Vector2(u["pos"]))})
	## ③ 破壳展翼: 顶端炸开(横向展开的火焰)
	battle._pending_shots.append({"delay": NIRVANA_SHOW_SEC - 0.12, "src": u, "fn": func() -> void:
		if not u.get("alive", false):
			return
		var q: Vector2 = Vector2(u["pos"])
		_phoenix_flame_burst(q)
		for dx in [-70.0, 70.0]:
			_phoenix_flame_burst(q + Vector2(dx, -18.0))   # 双翼: 左右各炸开一簇
		battle._vfx._syn.ground_ring(q, Color(1.0, 0.72, 0.25, 0.9), 120.0, false, 0.5)})


## 涅槃的【结算侧】: 留 1 血 + 清残留状态 + 演出期不可选中, 到点(2.5 秒)才真正回来。
## ★整段从主场景 `_kill` 搬过来(2026-08-13): 它不在 `_sim_step` 调用链上,
##   按 CLAUDE.md §5「不在 sim 链上的不进主文件」就该住这儿(主文件当时超预算 18 行)。
func nirvana_begin(u: Dictionary, pct: float) -> void:
	## ★★凤凰涅槃 = 一段 2.5 秒的演出(用户 2026-08-13)。原来是一帧完成:
		##   血条瞬间跳满、灼烧同帧施加, 玩家眼里就是"死了又突然站着"。
		##   现在三拍走完才真正回来 —— 结算落在**展翼那一刻**, 与画面同步
		##   (同 070 冲击环 / 收殓金球那条纪律: 效果等演出到达)。
		u["hp"] = 1.0                                  # 演出期留 1 血: 还没"回来"
		u["airborne"] = false; u["vy"] = 0.0; u["vx"] = 0.0; u["vz"] = 0.0   # 半空死的别卡在天上
		u["stun_until"] = 0.0                          # 带着眩晕复活 = 复活了也动不了
		u["untargetable_until"] = battle._t + NIRVANA_SHOW_SEC   # 演出期不可选中/不被 AOE 二次打死
		## ★★★用户实测「凤凰龟复活是问题」的根因(2026-08-13):
		##   `untargetable_until` 只挡【选靶】—— `_apply_damage`(DoT/真伤那条路)
		##   **根本不看它**, 它只挡 `_assembling`(battle_damage.gd:12)。
		##   而演出期我把血设成了 1 并让它在场上站 2.5 秒 ⇒ 任何一跳灼烧/一发溅射
		##   就把它打死, 而且是**真死**(首死复活已经用掉)。玩家看到的就是"复活了又没复活"。
		##   ⇒ 借机甲那套【组装期免疫一切伤害】的旗子: `_assembling` 的四个消费者
		##     (两道伤害闸 + 异常检测跳过 + _is_untargetable)正好全是涅槃演出需要的。
		u["_assembling"] = true
		u["_phx_reborn_t0"] = battle._t
		nirvana_show(u, pct)              # 三拍演出(灰烬 → 聚火 → 展翼)
		battle._pending_shots.append({"delay": NIRVANA_SHOW_SEC, "src": u, "fn": func() -> void:
			if not (u is Dictionary):
				return
			## ★★★这一行【无条件】放在最前面 —— 演出免疫必须解除, 否则凤凰永久无敌
			##   (那比原来的 bug 更糟)。★不能放在下面的 alive 判断之后:
			##   那样一旦有别的路径把它弄死, 旗子就永远留着了。
			u["_assembling"] = false
			if not u.get("alive", false):
				return
			u["hp"] = u["maxHp"] * pct                 # ★展翼那一刻才跳血条
			battle._vfx._float_text(u["pos"] + Vector2(0, -64), "涅槃!", Color("#ffd93d"))
			if u.get("_enh_rebirth", false):
				u["base_atk"] = u["base_atk"] * (1.0 + NIRVANA_ENH_ATK); battle._recalc_stats(u)   # 强化涅槃: 永久+20%攻击
			for o in battle._targeting._enemies_of(u):
				battle._damage._apply_dot_stacks(o, "burn", maxi(1, roundi(float(u["atk"]) * NIRVANA_BURN_COEF)), u)   # ★凤凰专用系数, 不走全局 _default_burn_stacks(0.67) —— 那个熔岩龟也在用
				o["heal_reduce_until"] = battle._t + battle.BUFF_SEC
				o["heal_reduce_pct"] = maxf(float(o.get("heal_reduce_pct", 0.0)), NIRVANA_HEALCUT)
			u["_phx_reborn_done"] = int(u.get("_phx_reborn_done", 0)) + 1   # 同步证据(门禁数它)
		})
