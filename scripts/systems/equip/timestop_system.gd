class_name TimestopSystem
extends RefCounted
## 沙漏时停系统(从 RealtimeBattle3DScene 抽出·2026-07-25)。持 battle 引用回调场景。
## 类内 _ts_* 函数/成员名与原主场景一字不差 → 内部互调零改动;只外部名加 battle. 前缀。

## 【059 沙漏】登场若干秒后蓄力, 然后全场定格。
const TS_START_T := 10.0     # 登场第几秒开始(战斗时钟)
const TS_CHARGE := 1.0       # 蓄力几秒才真的定格
## ★2026-09-06 用户:「沙漏的定格时间调整为4/7/20秒, 在开始时停时立刻获得40/150/300龟能,
##   额外龟能充能速率改为1.5/2/3倍」⇒ 下面三项**从标量改成三档**。
##   改之前 `TS_ECHARGE_MULT`/`TS_INSTANT_ENERGY` 是不分星的标量(2.0 / 15.0),
##   而文案**直接用占位符引它们** —— 变数组后占位符会渲染成 `[1.5, 2, 3]` 这种字面量,
##   所以文案同步改成手写三档(见 data/phase2-equipment.json p2eq_059)。
## ★三项都跟 `_ts_maxstar`(全场最高星)走 —— 因为只有最高星的携带者才进 `casters`
##   (低星本场不生效), 所以"最高星"就是"能动那批人自己的星", 不会错位。
const TS_DUR := [4.0, 7.0, 20.0]                  # 定格时长(秒) ★原 5/10/30
const TS_ECHARGE_MULT := [1.5, 2.0, 3.0]          # 时停期间携带者的龟能充能倍率 ★原 2.0 全星同值
const TS_INSTANT_ENERGY := [40.0, 150.0, 300.0]   # 定格瞬间立即给的龟能 ★原 15.0 全星同值


var battle
var _ts_active: Array = []                # 当前能自由行动的active携带者(空=无时停; 可多个=全场最高星沙漏者敌我并存)
var _ts_remaining := 0.0                  # 时停剩余真实秒
var _ts_charging := false                 # 蓄力中(1s, 世界仍正常)
var _ts_charge_t := 0.0
var _ts_charge_casters: Array = []
var _ts_fired := false                    # 一场一次
var _ts_maxstar := 0                      # 生效沙漏星级(定时长 5/10/30 秒·用户2026-07-19: 1★ 4→5)
var _ts_frozen_tweens: Array = []         # 时停期间被暂停的tween(结束resume)
var _ts_frozen_particles: Array = []      # 时停期间被暂停的GPUParticles3D(speed_scale归零, 结束还原)
var _ts_overlay: CanvasLayer = null       # 时停灰世界叠加层(压暗褪色从携带者扩散; layer5=在UI下→只灰3D世界, 数字/血条保彩)
var _ts_rect: ColorRect = null
var _ts_flash_overlay: CanvasLayer = null # 反色闪叠加层(layer60=在UI上→含全屏UI一起反色)
var _ts_flash_rect: ColorRect = null
var _ts_clock: TextureRect = null         # 时停停摆钟(叠加层顶, 不被褪色)
var _ts_glow_sprs: Array = []             # 携带者身上的【时之砂】sprite(结束移除·名字沿用: dual_lane_flow 在读它)
var _ts_total := 0.0                      # 本次定格的总时长(秒) —— 读数条的分母
var _ts_wave_t := 0.0                     # 释放演出的真实时间累加器
var _ts_aura_sprs: Array = []             # 蓄力段金火气
var _ts_core_sprs: Array = []             # 胸口白金光点
var _ts_core_t := -1.0                    # 光点累加器(<0 = 没亮)
var _ts_sand_t := 0.0                     # 时之砂的**真实时间**累加器 —— 全局 `_t` 在时停里是冻的, 不能拿它推帧

func _init(b) -> void:
	battle = b

func _ts_advance_unit_timers(u: Dictionary, delta: float) -> void:
	# 时停期间全局 battle._t 冻结, 但 active 携带者仍在行动 —— 它身上所有"时间戳型"状态
	# (眩晕/嘲讽/减速/护盾/各种buff的到期时刻) 都是相对 battle._t 记的, battle._t 不走就永远不到期。
	# 用户2026-07-19: "如果在时间暂停的时候自己眩晕了, 为什么会被一直眩晕?" —— 就是这个原因。
	# 修法: 只为该单位把这些到期时刻按真实 delta 前移, 等价于单独为它推进时间。
	for f in battle._TS_TIMER_FIELDS:
		var v: float = float(u.get(f, 0.0))
		if v > battle._t:
			u[f] = maxf(battle._t, v - delta)
	for b in u.get("buffs", []):
		if b is Dictionary and float(b.get("until", 0.0)) > battle._t:
			b["until"] = maxf(battle._t, float(b["until"]) - delta)
	for d in u.get("dots", []):
		if d is Dictionary and float(d.get("until", 0.0)) > battle._t:
			d["until"] = maxf(battle._t, float(d["until"]) - delta)

func _unit_hourglass_star(u: Dictionary) -> int:   # 该单位所装沙漏最高星(0=无)
	var best := 0
	for e in u.get("equips", []):
		if str(e.get("id", "")) == "p2eq_059":
			best = maxi(best, int(e.get("star", 1)))
	return best

func _ts_update_trigger(delta: float) -> void:   # (仅正常态调)第10秒触发蓄力 → 蓄力满释放
	if _ts_charging:
		_ts_charge_t -= delta
		_ts_core_step(delta)   # 胸口白金光点: 蓄力最后 TS_CORE_LEAD 秒亮起(蓄力段世界还在走 ⇒ 走 sim 步长)
		if _ts_charge_t <= 0.0:
			_ts_charging = false
			_ts_fire()
		return
	if _ts_fired or not _ts_active.is_empty() or battle._t < TS_START_T:
		return
	var maxstar := 0
	for u in battle._units:
		if u.get("alive", false):
			maxstar = maxi(maxstar, _unit_hourglass_star(u))
	if maxstar <= 0:
		return
	var casters: Array = []
	for u in battle._units:
		if u.get("alive", false) and _unit_hourglass_star(u) == maxstar:
			casters.append(u)   # 最高星沙漏者(敌我皆算, 低星作废)
	if casters.is_empty():
		return
	_ts_fired = true
	_ts_maxstar = maxstar
	_ts_charging = true
	_ts_charge_t = TS_CHARGE
	_ts_charge_casters = casters
	for c in casters:
		_ts_charge_vfx(c)

func _ts_fire() -> void:
	var casters: Array = _ts_charge_casters.filter(func(x): return x is Dictionary and x.get("alive", false))
	_ts_charge_casters = []
	_ts_free_auras()   # 金火气只活在蓄力段: 释放那一刻交给胸口光点爆开(没人能放也要收掉)
	if casters.is_empty():
		_ts_free_cores()
		return
	_ts_active = casters
	## ★三档下标：只有最高星的沙漏携带者才进 `casters`，所以 `_ts_maxstar` 就是他们自己的星。
	##   时长/倍率/瞬间龟能**必须跟同一个 star**，否则会出现「定格按最高星、龟能按自己星」的错位。
	var _si: int = clampi(_ts_maxstar, 1, 3) - 1
	_ts_remaining = TS_DUR[_si]                        # 2026-09-06: 5/10/30 → 4/7/20
	for _c in casters:
		_c["_ts_echarge"] = TS_ECHARGE_MULT[_si]       # 2026-09-06: 2.0 全星同值 → 1.5/2/3
		if battle._has_energy_system(_c):
			var _ie: float = TS_INSTANT_ENERGY[_si]    # 2026-09-06: 15 全星同值 → 40/150/300
			battle._equip_sys._eq_grant_energy(_c, _ie)
			## ★飘字**不许写死数字** —— 原来这里是硬编码的 "+15龟能"，
			##   常量改成三档后它会漂（同族 memory [[fb-system-coefficient-1-hides-missing-placeholder]]）。
			battle._vfx._float_text(_c["pos"] + Vector2(0, -62), "+%d龟能" % int(_ie), Color("#8fd4ff"))
	_ts_total = _ts_remaining
	_ts_sand_t = 0.0
	_ts_wave_t = 0.0
	_ts_begin_freeze()
	_ts_visual_start()

func _end_timestop() -> void:
	for _c in _ts_active:
		if _c is Dictionary: _c.erase("_ts_echarge")   # 时停结束: 撤掉+100%充能速度
	_ts_resume_freeze()
	_ts_visual_end()
	## ★抹成 0 —— 不抹的话图标框那根条会停在最后一格(044 深海项链踩过的原话教训)。
	for c in _ts_active:
		if c is Dictionary:
			var st: Dictionary = (c.get("eq_state", {}) as Dictionary).get("p2eq_059", {})
			st["ts_pct"] = 0.0
			(c["eq_state"] as Dictionary)["p2eq_059"] = st
	_ts_active = []
	_ts_remaining = 0.0

func _ts_begin_freeze() -> void:   # 暂停时停开始时在跑的所有VFX tween + 粒子(active之后新建的不在此列→照跑)
	_ts_frozen_tweens = []
	for t in battle._sim_tweens:
		if t != null and t.is_valid() and t.is_running():
			t.pause()
			_ts_frozen_tweens.append(t)
	_ts_frozen_particles = []
	_ts_freeze_particles_in(battle._world)

func _ts_freeze_particles_in(n: Node) -> void:
	for c in n.get_children():
		if c is GPUParticles3D and c.speed_scale > 0.0:
			c.set_meta("_ts_spd", c.speed_scale)
			c.speed_scale = 0.0
			_ts_frozen_particles.append(c)
		if c.get_child_count() > 0:
			_ts_freeze_particles_in(c)

func _ts_resume_freeze() -> void:
	for t in _ts_frozen_tweens:
		if t != null and t.is_valid():
			t.play()
	_ts_frozen_tweens = []
	for p in _ts_frozen_particles:
		if is_instance_valid(p):
			p.speed_scale = float(p.get_meta("_ts_spd", 1.0))
	_ts_frozen_particles = []

func _ts_ensure_overlay() -> void:
	if _ts_overlay != null and is_instance_valid(_ts_overlay):
		return
	var vp = battle.get_viewport().get_visible_rect().size
	# --- 灰世界层(layer5, 在UI层10之下 → 只灰3D世界, 数字/血条保彩上浮) ---
	_ts_overlay = CanvasLayer.new()
	_ts_overlay.layer = 5
	battle.add_child(_ts_overlay)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()   # 压暗褪色从center按radius扩散→昏暗冷灰; 但携带者(casters)周围留彩色泡(时之主保持彩色)
	# ★2026-07-11 黑屏排查 A1: hint_screen_texture(读屏幕纹理) 在 gl_compatibility 移动端会导致【整屏黑】。
	#   → 移动端用【不读屏】的等效 shader(半透明冷灰覆盖+径向扩散+携带者彩色泡), 桌面保留原读屏版(带真灰度)。
	#   两版 uniform 完全相同(amount/radius/aspect/casters/caster_n) → _ts_tick_visual 的 set 逻辑不用改。
	if battle._is_mobile():
		sh.code = "shader_type canvas_item;\nuniform float amount : hint_range(0.0,1.0) = 0.0;\nuniform vec2 center = vec2(0.5,0.5);\nuniform float radius = 0.0;\nuniform float aspect = 1.778;\nuniform vec2 casters[4];\nuniform int caster_n = 0;\nuniform float caster_r = 0.115;\nuniform float warp = 0.0;\nuniform float warp_r = 0.0;\nuniform float wave_r = 0.0;\nuniform float wave_dir = -1.0;\nuniform float wave_a = 0.0;\nuniform float grey_front = 0.0;\nuniform float violet = 0.0;\nuniform float hue_flip = 0.0;\nuniform float zoom_blur = 0.0;\nuniform float core_flash = 0.0;\nvoid fragment(){\n\tvec2 d = SCREEN_UV - center; d.x *= aspect;\n\tfloat dist = length(d);\n\tfloat ang = atan(d.y, d.x);\n\tfloat dr = dist - wave_r;\n\tfloat lop = 0.78 + 0.22 * sin(ang * 3.0 + wave_r * 5.0);\n\tfloat core = exp(-pow(dr / 0.030, 2.0));\n\tfloat halo = exp(-pow(dr / 0.11, 2.0)) * 0.55;\n\tfloat ring = clamp(max(core, halo) * lop * wave_a, 0.0, 1.0);\n\tfloat inside = 1.0 - smoothstep(wave_r - 0.02, wave_r + 0.04, dist);\n\tfloat keep = 0.0;\n\tfor(int i=0;i<4;i++){\n\t\tif(i>=caster_n){break;}\n\t\tvec2 cd = SCREEN_UV - casters[i]; cd.x *= aspect;\n\t\tkeep = max(keep, 1.0 - smoothstep(caster_r*0.55, caster_r, length(cd)));\n\t}\n\tfloat grey_a = amount * ((grey_front > 0.5) ? (1.0 - inside) : 1.0) * (1.0 - keep);\n\tfloat passed = (wave_dir < 0.0) ? inside : 1.0;\n\tfloat va = violet * passed * (1.0 - grey_a);\n\tfloat fa = hue_flip * (1.0 - grey_a);\n\tfloat cf = clamp(core_flash * (0.30 + 0.70 * exp(-pow(dist / 0.45, 2.0))), 0.0, 1.0);\n\tvec3 ring_col = mix(vec3(0.62, 0.48, 0.95), vec3(1.0, 0.97, 0.92), core);\n\tvec3 rgb = vec3(0.0);\n\tfloat al = 0.0;\n\tif(va > 0.001){ rgb = vec3(0.55, 0.40, 0.92); al = 0.30 * va; }\n\tif(fa > 0.001){ rgb = mix(rgb, vec3(0.86, 0.84, 0.36), fa); al = max(al, 0.30 * fa); }\n\tif(grey_a > 0.001){ rgb = mix(rgb, vec3(0.03, 0.05, 0.07), grey_a); al = mix(al, 0.82, grey_a); }\n\trgb = mix(rgb, vec3(0.82, 1.0, 0.98), cf);\n\tal = max(al, 0.85 * cf);\n\tCOLOR = vec4(mix(rgb, ring_col, ring), max(al, ring));\n}"
	else:
		sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float amount : hint_range(0.0,1.0) = 0.0;\nuniform vec2 center = vec2(0.5,0.5);\nuniform float radius = 0.0;\nuniform float aspect = 1.778;\nuniform vec2 casters[4];\nuniform int caster_n = 0;\nuniform float caster_r = 0.115;\nuniform float warp = 0.0;\nuniform float warp_r = 0.0;\nuniform float wave_r = 0.0;\nuniform float wave_dir = -1.0;\nuniform float wave_a = 0.0;\nuniform float grey_front = 0.0;\nuniform float violet = 0.0;\nuniform float hue_flip = 0.0;\nuniform float zoom_blur = 0.0;\nuniform float core_flash = 0.0;\nvoid fragment(){\n\tvec2 d = SCREEN_UV - center; d.x *= aspect;\n\tfloat dist = length(d);\n\tfloat ang = atan(d.y, d.x);\n\tfloat dr = dist - wave_r;\n\tfloat lop = 0.78 + 0.22 * sin(ang * 3.0 + wave_r * 5.0);\n\tfloat core = exp(-pow(dr / 0.030, 2.0));\n\tfloat halo = exp(-pow(dr / 0.11, 2.0)) * 0.55;\n\tfloat ring = clamp(max(core, halo) * lop * wave_a, 0.0, 1.0);\n\tfloat inside = 1.0 - smoothstep(wave_r - 0.02, wave_r + 0.04, dist);\n\tfloat keep = 0.0;\n\tfor(int i=0;i<4;i++){\n\t\tif(i>=caster_n){break;}\n\t\tvec2 cd = SCREEN_UV - casters[i]; cd.x *= aspect;\n\t\tkeep = max(keep, 1.0 - smoothstep(caster_r*0.55, caster_r, length(cd)));\n\t}\n\tfloat grey_a = amount * ((grey_front > 0.5) ? (1.0 - inside) : 1.0) * (1.0 - keep);\n\tfloat passed = (wave_dir < 0.0) ? inside : 1.0;\n\tfloat va = violet * passed * (1.0 - grey_a);\n\tfloat fa = hue_flip * (1.0 - grey_a);\n\tfloat cf = clamp(core_flash * (0.30 + 0.70 * exp(-pow(dist / 0.45, 2.0))), 0.0, 1.0);\n\tvec3 ring_col = mix(vec3(0.62, 0.48, 0.95), vec3(1.0, 0.97, 0.92), core);\n\tfloat band = exp(-pow((dist - warp_r) / 0.14, 2.0));\n\tvec2 wdir = dist > 0.0001 ? d / dist : vec2(0.0);\n\twdir.x /= aspect;\n\tvec2 wuv = SCREEN_UV + wdir * warp * band * 0.055;\n\tfloat zb = zoom_blur * passed * clamp(dist, 0.0, 1.2);\n\tvec3 c = vec3(0.0);\n\tfor(int k=0;k<6;k++){\n\t\tfloat s = 1.0 - zb * 0.08 * float(k) / 5.0;\n\t\tc += texture(screen_tex, center + (wuv - center) * s).rgb;\n\t}\n\tc /= 6.0;\n\tfloat y = dot(c, vec3(0.299, 0.587, 0.114));\n\tvec3 vio = clamp(vec3(y) * vec3(0.94, 0.82, 1.16) + vec3(0.05, 0.02, 0.09), 0.0, 1.0);\n\tvec3 flp = clamp(vec3(2.0 * y) - c, 0.0, 1.0);\n\tvec3 col = mix(c, vio, va);\n\tcol = mix(col, flp, fa);\n\tcol = mix(col, vec3(y * 0.47, y * 0.63, y * 0.68), grey_a);\n\tcol = mix(col, vec3(0.82, 1.0, 0.98), cf);\n\tCOLOR = vec4(mix(col, ring_col, ring), 1.0);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amount", 0.0)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("aspect", vp.x / maxf(1.0, vp.y))
	mat.set_shader_parameter("casters", PackedVector2Array())
	mat.set_shader_parameter("caster_n", 0)
	mat.set_shader_parameter("warp", 0.0)
	mat.set_shader_parameter("warp_r", 0.0)
	rect.material = mat
	_ts_overlay.add_child(rect)
	_ts_rect = rect
	# --- 反色闪层(layer60, 在UI层之上 → 反色含全屏UI) ---
	_ts_flash_overlay = CanvasLayer.new()
	_ts_flash_overlay.layer = 60
	battle.add_child(_ts_flash_overlay)
	var frect := ColorRect.new()
	frect.set_anchors_preset(Control.PRESET_FULL_RECT)
	frect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fsh := Shader.new()
	# ★A1: 移动端不读屏 → 反色改成白闪(uniform invert 不变, _ts 逻辑不用改); 桌面保留真反色
	if battle._is_mobile():
		fsh.code = "shader_type canvas_item;\nuniform float invert : hint_range(0.0,1.0) = 0.0;\nvoid fragment(){\n\tCOLOR = vec4(1.0, 1.0, 1.0, invert * 0.6);\n}"
	else:
		fsh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float invert : hint_range(0.0,1.0) = 0.0;\nvoid fragment(){\n\tvec3 c = texture(screen_tex, SCREEN_UV).rgb;\n\tfloat g = dot(c, vec3(0.299,0.587,0.114));\n\tvec3 flat_c = mix(c, vec3(g), 0.35);\n\tCOLOR = vec4(mix(flat_c, vec3(1.0), invert), 1.0);\n}"
	var fmat := ShaderMaterial.new()
	fmat.shader = fsh
	fmat.set_shader_parameter("invert", 0.0)
	frect.material = fmat
	_ts_flash_overlay.add_child(frect)
	_ts_flash_rect = frect

func _ts_casters_screen_uv() -> Vector2:   # active携带者质心的屏幕UV(扩散中心)
	if battle._cam == null or _ts_active.is_empty():
		return Vector2(0.5, 0.5)
	var acc := Vector2.ZERO; var n := 0
	for c in _ts_active:
		var head: Vector3 = battle._world_pos(c["pos"], 1.0)
		if not battle._cam.is_position_behind(head):
			acc += battle._cam.unproject_position(head); n += 1
	if n == 0:
		return Vector2(0.5, 0.5)
	var vp = battle.get_viewport().get_visible_rect().size
	return (acc / float(n)) / Vector2(maxf(1.0, vp.x), maxf(1.0, vp.y))

# 释放: 环出去 → 染紫 → 色相翻转 → 收回(扫过的变暗灰) → 中心白光, 全部由 `_ts_wave_step` 逐帧驱动
func _ts_visual_start() -> void:
	_ts_ensure_overlay()
	var mat: ShaderMaterial = _ts_rect.material
	var fmat: ShaderMaterial = _ts_flash_rect.material
	mat.set_shader_parameter("center", _ts_casters_screen_uv())
	mat.set_shader_parameter("radius", 0.0)
	fmat.set_shader_parameter("invert", 0.0)
	## ★原来这里先放一下【全屏白闪】(layer 60, 连 UI 一起)。参考 clip.mp4 11.00~12.47 秒 45 帧里
	##   **没有全屏白闪**: 爆开的白只在人物胸口(10.83~10.97 秒), 画面是被那一道环【染】过去的。
	## ★灰色只由收回的波前铺(用户原话「能量波经过的地方变灰」), 不另起 tween。
	mat.set_shader_parameter("grey_front", 1.0)
	_ts_wave_step(0.0)
	for c in _ts_active:
		_ts_caster_sand(c)             # 时之砂(替掉原来那颗白球)
	_ts_spawn_clock()                  # 停摆钟浮现

func _ts_visual_end() -> void:   # 解除: 反色再闪 + 回色(时间恢复流动)
	_ts_clear_visual_nodes()
	if _ts_rect != null and is_instance_valid(_ts_rect) and _ts_rect.material != null:
		for _k in ["wave_a", "warp", "violet", "hue_flip", "zoom_blur", "core_flash"]:
			(_ts_rect.material as ShaderMaterial).set_shader_parameter(_k, 0.0)
	if _ts_rect == null or not is_instance_valid(_ts_rect):
		return
	var mat: ShaderMaterial = _ts_rect.material
	var fmat: ShaderMaterial = _ts_flash_rect.material
	var fl = battle.create_tween()
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.0, 0.7, 0.04)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.7, 0.0, 0.1)
	var tw = battle.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.35)

## 【时停剩余时间】写进装备图标框的充能条(0~100 归一化镜像)。
## ★★由来(用户 2026-09-14):「沙漏你是不是参考的 jojo 里 **dio 最终战斗释放的 9 秒时停**?
##   而且…你这个参考的不到位啊」—— 他点的那一段, 戏剧性全在【还剩几秒】上(DIO 数着那 9 秒)。
##   而我们的时停只有一口钟, **剩余时间一个读数都没有**: 玩家不知道它还剩多久。
##   查过 `equip_readouts.gd` —— 059 在 COUNT / CHARGE 两张表里**一条都没有**。
## ★为什么是图标框的条而不是头顶或钟面: 表头那条铁律(用户 2026-08-08)——
##   「充能条和层数不要放头顶, 在装备图标框里」; 044/045 的持续回复也是这么做的。
##   钟面不动是**刻意的**: 钟是像素贴图, 转指针 = 非整数角旋转 = 像素网格当场碎。
## ★分母只能是常量 ⇒ 存 0~100 的归一化镜像, 不存【剩几秒】(时长随星级 4/7/20 变)。
func _ts_bar_mirror() -> void:
	for c in _ts_active:
		if not (c is Dictionary):
			continue
		var st: Dictionary = (c.get("eq_state", {}) as Dictionary).get("p2eq_059", {})
		st["ts_pct"] = clampf(_ts_remaining / maxf(0.001, _ts_total), 0.0, 1.0) * 100.0
		(c["eq_state"] as Dictionary)["p2eq_059"] = st


## 【释放一瞬】五段, 全部照参考逐帧(docs/studies/20260914g-059时停能量场逐帧.md「第五版」一节):
##   用户 2026-09-14「参考视频能量场在 11 秒到 15 秒吧」—— 13~15 秒已经是定格后的静止世界, 能量场本体在 11.0~12.5。
##   | 段     | 参考帧              | 画面 |
##   | out    | #001~#004 (3 帧)    | **一道**粗白紫环从人物冲出画面; 环扫过的地方染淡紫、带径向拖影 |
##   | violet | #005~#016 (0.40 秒) | 整个画面染紫(亮度不变), 拖影慢慢减弱 |
##   | flip   | #017~#029 (0.43 秒) | 色相翻到对面、**亮度不动**(实测亮度相关 +0.86~+0.89, 色度相关转负) |
##   | in     | #030~#034           | 环从画面边收回人物; **环外变暗灰**, 环里还是翻转色 |
##   | flash  | #035~#044 (0.33 秒) | 收到中心那一下白青光铺开再退掉 |
##   「能量波几道」: 三个样本(clip 11 秒 / jgt 430 秒 / jgt 438 秒)出去都是**一道**、收回也是**一道**。
## ★纯函数, 门禁直接调它量段序与每段的量, 不必等真实时间。
static func ts_wave_at(t: float) -> Dictionary:
	var w: Dictionary = {"r": 0.0, "dir": -1.0, "a": 0.0, "grey": 0.0, "warp": 0.0,
		"violet": 0.0, "flip": 0.0, "zoom": 0.0, "flash": 0.0, "phase": "idle"}
	var t1: float = TS_WAVE_OUT
	var t2: float = t1 + TS_WAVE_VIOLET
	var t3: float = t2 + TS_WAVE_FLIP
	var t4: float = t3 + TS_WAVE_IN
	var t5: float = t4 + TS_WAVE_FLASH
	if t < 0.0:
		return w
	if t < t1:
		## 出去: 参考 #001 半宽 0.76 → #002 0.88 到画面边 → #003 同一张停格 → #004 出屏 ⇒ 环在画面里露 3 帧。
		## ★第一版用一条先快后慢曲线, 30fps 实录里环只露 1 帧(第 2 帧半径已 1.04 出屏) ⇒ 读成一闪, 看不出「散开」。
		##   照参考拆三段: 2 帧冲到画面边 → 停 1 帧 → 再冲出屏角。
		var r_o: float = TS_OUT_EDGE_R
		if t < TS_OUT_REACH:
			var x: float = t / TS_OUT_REACH
			r_o = TS_OUT_EDGE_R * (1.0 - (1.0 - x) * (1.0 - x))
		elif t >= TS_OUT_REACH + TS_OUT_HOLD:
			var z: float = (t - TS_OUT_REACH - TS_OUT_HOLD) / maxf(0.001, TS_WAVE_OUT - TS_OUT_REACH - TS_OUT_HOLD)
			r_o = lerpf(TS_OUT_EDGE_R, TS_WAVE_EDGE, z)
		w.merge({"r": r_o, "dir": -1.0, "a": 1.0,
			"warp": 1.0, "violet": 1.0, "zoom": 1.0, "phase": "out"}, true)
	elif t < t2:
		var y: float = (t - t1) / TS_WAVE_VIOLET
		w.merge({"r": TS_WAVE_EDGE, "dir": -1.0, "violet": 1.0, "zoom": lerpf(1.0, 0.4, y), "phase": "violet"}, true)
	elif t < t3:
		var y2: float = (t - t2) / TS_WAVE_FLIP
		w.merge({"r": TS_WAVE_EDGE, "dir": 1.0, "flip": 1.0, "zoom": lerpf(0.4, 0.3, y2), "phase": "flip"}, true)
	elif t < t4:
		var y3: float = (t - t3) / TS_WAVE_IN
		## 收回: 匀速(参考 #030→#034 每帧收 ≈0.11 屏高, 看不出加减速)
		w.merge({"r": TS_WAVE_EDGE * (1.0 - y3), "dir": 1.0, "a": 1.0, "grey": 1.0,
			"warp": 1.0, "flip": 1.0, "zoom": 0.3, "phase": "in"}, true)
	elif t < t5:
		var y4: float = (t - t4) / TS_WAVE_FLASH
		w.merge({"dir": 1.0, "grey": 1.0, "flash": 1.0 - y4, "phase": "flash"}, true)
	else:
		w.merge({"dir": 1.0, "grey": 1.0, "phase": "done"}, true)
	return w


## 把这一刻的量喂给 shader: 波环 / 灰度 / 扭曲 / 染色 **同一个半径**(链最容易断在位置上)。
func _ts_wave_step(t: float) -> void:
	if _ts_rect == null or not is_instance_valid(_ts_rect) or _ts_rect.material == null:
		return
	var w: Dictionary = ts_wave_at(t)
	var m: ShaderMaterial = _ts_rect.material
	m.set_shader_parameter("wave_r", float(w["r"]))
	m.set_shader_parameter("wave_dir", float(w["dir"]))
	m.set_shader_parameter("wave_a", float(w["a"]))
	m.set_shader_parameter("warp", float(w["warp"]))
	m.set_shader_parameter("warp_r", float(w["r"]))
	m.set_shader_parameter("amount", float(w["grey"]))
	m.set_shader_parameter("violet", float(w["violet"]))
	m.set_shader_parameter("hue_flip", float(w["flip"]))
	m.set_shader_parameter("zoom_blur", float(w["zoom"]))
	m.set_shader_parameter("core_flash", float(w["flash"]))


func _ts_tick_visual(_delta: float) -> void:   # 每帧喂携带者屏幕位置给灰shader → 彩色泡跟随移动的时之主
	## ★时之砂按**真实时间**推帧: 全局 `battle._t` 在时停期间是冻结的, 拿它推帧沙会停在原地 ——
	##   而沙正是用来说明"这里的时间还在流"的, 停下来就把意思说反了。
	##   这不是"第二条钟"的那个坑: 时停自己的演出本来就全都活在真实时间上(反色闪/扩散/钟表脉动同理)。
	_ts_bar_mirror()   # 每帧无条件写 —— 漏写一帧条子就会停在上一格(044 那次的教训)
	## 释放演出走**真实时间** —— 全局 `_t` 这一刻是冻的。
	_ts_wave_t += _delta
	_ts_wave_step(_ts_wave_t)
	_ts_core_step(_delta)
	_ts_sand_t += _delta
	var _sf: int = int(_ts_sand_t * TS_SAND_FPS) % TS_SAND_FRAMES
	for g in _ts_glow_sprs:
		if is_instance_valid(g):
			g.frame = _sf
	if _ts_rect == null or not is_instance_valid(_ts_rect) or battle._cam == null:
		return
	var vp = battle.get_viewport().get_visible_rect().size
	var arr := PackedVector2Array()
	for c in _ts_active:
		if arr.size() >= 4:
			break
		var head: Vector3 = battle._world_pos(c["pos"], 1.0)
		if not battle._cam.is_position_behind(head):
			var sp = battle._cam.unproject_position(head)
			arr.append(Vector2(sp.x / maxf(1.0, vp.x), sp.y / maxf(1.0, vp.y)))
	var mat: ShaderMaterial = _ts_rect.material
	mat.set_shader_parameter("casters", arr)
	mat.set_shader_parameter("caster_n", arr.size())

## 【释放一瞬】各段时长(真实秒) —— 照参考 clip.mp4 逐帧数出来的帧数 ÷ 30:
## ★第三版照一张带噪声的测量表做了个 0.7 秒、只在携带者周围跳的涡环(`ts-vortex.png`), 第四版改成屏幕空间波
##   但时长是我拍的(出去 0.75 / 收回 1.00)、中段颜色一点没做。第五版把 11.00~12.47 秒 45 帧逐帧对齐。
const TS_WAVE_OUT := 0.24        # 一道环冲出屏。参考 3 帧到画面边(0.10 秒); 屏角比画面边远 ⇒ 按同速补到 EDGE
const TS_OUT_REACH := 0.067      # 其中: 2 帧冲到画面边(参考 #001→#002)
const TS_OUT_HOLD := 0.033       #       在画面边停 1 帧(参考 #003 与 #002 是同一张)
const TS_OUT_EDGE_R := 0.88      #       画面边的半宽(屏高 = 1; 16:9 画面半宽 0.889)
const TS_WAVE_VIOLET := 0.29     # 染紫(参考 #005~#016 = 0.40 秒, 从环出屏那刻起算已过 0.11)
const TS_WAVE_FLIP := 0.43       # 色相翻转(参考 #017~#029 = 13 帧)
const TS_WAVE_IN := 0.60         # 收回(参考 #030→#034 每帧收 ≈0.11 屏高 ≈ 3.4 屏高/秒 ⇒ EDGE 2.15 要 0.63 秒)
const TS_WAVE_FLASH := 0.33      # 中心白光(参考 #035~#044 = 10 帧)
const TS_WAVE_EDGE := 2.15       # 出屏半径(shader 单位: 屏高=1; 携带者在屏角时最远角 √(1.778²+1²)=2.04, 留余量)
const TS_WAVE_TOTAL := TS_WAVE_OUT + TS_WAVE_VIOLET + TS_WAVE_FLIP + TS_WAVE_IN + TS_WAVE_FLASH

## 【胸口白金光点】参考 10.83~10.97 秒(#025~#029): DIO 胸口正中亮起一个白金光点 → 从胸口爆开、全身发白金光。
##   用户原话「从人物中间爆开, 中间是什么颜色特效」—— 就是这个: 白芯 + 金晕。
## ★像素帧(tools/bake_ts_core.py · 8 帧), 不是软光球: 蓄力末 3 帧「点→变大」, 释放后 5 帧「爆开→碎散」。
## ★帧号走时间累加器不走 tween: 蓄力段世界还在走(sim 步长), 释放后全局 `_t` 冻结(真实时间)。
const TS_CORE_TEX := "res://assets/sprites/vfx/ts-core.png"
const TS_CORE_FRAMES := 8
const TS_CORE_CELL := 40.0
const TS_CORE_YARDS := 71.0        # 40 × 1.775 ⇒ 1 texel : 1 屏幕像素
const TS_CORE_H := 0.75            # 胸口高度(米)
const TS_CORE_LEAD := 0.17         # 蓄力最后几秒亮起(参考 #025~#029 = 5 帧)
const TS_CORE_PRE_FRAMES := 3
const TS_CORE_BURST := 0.25        # 释放后爆开到散完

func _ts_core_spawn(c: Dictionary) -> void:
	var tex = load(TS_CORE_TEX)
	if tex == null:
		return
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = TS_CORE_FRAMES
	s.frame = 0
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画必须 NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	s.no_depth_test = true             # 光点在胸口, 必须压在立绘上
	s.render_priority = 7
	s.pixel_size = (TS_CORE_YARDS * battle.WS) / TS_CORE_CELL
	s.position = battle._world_pos(c["pos"], float(c.get("height", 0.0)) + TS_CORE_H)
	battle._world.add_child(s)
	battle._follow_vfx.append({"spr": s, "unit": c, "h": TS_CORE_H})
	_ts_core_sprs.append(s)

## 蓄力段: 最后 TS_CORE_LEAD 秒亮起并变大; 释放后: 按 `_ts_wave_t` 爆开, 放完自销。
func _ts_core_step(delta: float) -> void:
	if _ts_charging:
		if _ts_charge_t > TS_CORE_LEAD:
			return
		if _ts_core_t < 0.0:
			_ts_core_t = 0.0
			for c in _ts_charge_casters:
				if c is Dictionary and c.get("alive", false):
					_ts_core_spawn(c)
		_ts_core_t += delta
		var pf: int = clampi(int(_ts_core_t / TS_CORE_LEAD * float(TS_CORE_PRE_FRAMES)), 0, TS_CORE_PRE_FRAMES - 1)
		for s in _ts_core_sprs:
			if is_instance_valid(s):
				s.frame = pf
		return
	if _ts_core_sprs.is_empty():
		return
	var bf: int = TS_CORE_PRE_FRAMES + int(_ts_wave_t / TS_CORE_BURST * float(TS_CORE_FRAMES - TS_CORE_PRE_FRAMES))
	if bf >= TS_CORE_FRAMES:
		_ts_free_cores()
		return
	for s in _ts_core_sprs:
		if is_instance_valid(s):
			s.frame = bf

func _ts_free_cores() -> void:
	for s in _ts_core_sprs:
		if is_instance_valid(s):
			s.queue_free()
	_ts_core_sprs = []
	_ts_core_t = -1.0

## 【金火气】参考 10.00~10.80 秒(#000~#024): DIO 喊「The World!」时整个人被金色火焰包着, 火苗一直往上窜。
##   用户原话「**直接是人物冒战斗特效**」—— 蓄力那 1 秒就是这一段(TS_CHARGE = 1.0 与参考 10.0~11.0 同长)。
## ★改之前蓄力段是 10 颗 `_make_fire_glow_tex` 软光球螺旋汇入 + 脚下一道 `_skill_ring` 金环 ——
##   两个都是点名过的禁区形状(无含义白球/圆环), 参考里也没有。
## ★Blender 体积火(tools/blender_ts_aura.py, 同 022 真火那条路) + 参考量出的 6 档金色板;
##   身体那一块留空 ⇒ 龟看得见(火在身侧与头顶往上窜, 不糊在身上)。
const TS_AURA_TEX := "res://assets/sprites/vfx/ts-aura.png"
const TS_AURA_FRAMES := 8
const TS_AURA_CELL := 72.0
const TS_AURA_YARDS := 127.8       # 72 × 1.775 ⇒ 1 texel : 1 屏幕像素
const TS_AURA_H := 1.534           # 半格(72 / 2 × 0.0426) ⇒ 格底齐脚(同 022 真火的定标)
const TS_AURA_FPS := 12.0

func _ts_aura_spawn(c: Dictionary) -> void:
	var tex = load(TS_AURA_TEX)
	if tex == null:
		return
	var s := Sprite3D.new()
	s.texture = tex
	s.hframes = TS_AURA_FRAMES
	s.frame = 0
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false; s.transparent = true
	## ★★火画在龟【身后】: 前两版把身体那块挖空好不盖住龟, 实拍是「龟左右各立一根金柱子」。
	##   参考 DIO 是整团火在身后、身体挡在火前面 ⇒ 实心火 + 渲染优先级比立绘低(立绘接地 shader 是
	##   `depth_prepass_alpha` 透明管线, 默认优先级 0) ⇒ 先画火、再画龟。
	##   不靠往后挪位置: 火的中心比龟高 1.5 米, 离相机反而更近, 按远近排序会排到龟前面。
	##   不做深度测试: 公告板底边会斜插进地板, 开了深度测试火根会被地板吃掉。
	s.no_depth_test = true
	s.render_priority = -1
	s.pixel_size = (TS_AURA_YARDS * battle.WS) / TS_AURA_CELL
	s.position = battle._world_pos(c["pos"], float(c.get("height", 0.0)) + TS_AURA_H)
	battle._world.add_child(s)
	## 蓄力段世界还在走 ⇒ 按游戏钟循环切帧(同 022 真火); 释放那一刻由 `_ts_fire` 收掉
	battle._follow_vfx.append({"spr": s, "unit": c, "h": TS_AURA_H,
		"loop_fps": TS_AURA_FPS, "loop_n": TS_AURA_FRAMES, "loop_t0": battle._t})
	_ts_aura_sprs.append(s)

func _ts_free_auras() -> void:
	for s in _ts_aura_sprs:
		if is_instance_valid(s):
			s.queue_free()
	_ts_aura_sprs = []

## 【时之砂】时停期间绕着携带者走的金沙(tools/bake_ts_sand.py · 8 帧循环)。
## ★它是来【替换一颗白球】的: 原来这里贴的是 150 码的 `VfxTex._make_fire_glow_tex()` 金球,
##   染色法核实过那团白就是它, 而它把携带者**整只盖没了**(并排图: 时停前看得见龟, 时停中只剩一颗球)。
##   两条都踩了 —— ①「无含义白球」是本仓点名过的禁区形状;
##   ②**方向和参考正好相反**: JoJo 那 149 帧里时之主是定格世界中**唯一清晰**的那个, 没有光球罩着。
## ★为什么是沙: 059 就叫【沙漏】, 蓄力那 1 秒已经在放金沙螺旋汇入 ⇒ 同一条因果链的延续, 不是凭空发明。
const TS_SAND_TEX := "res://assets/sprites/vfx/ts-sand.png"
const TS_SAND_FRAMES := 8
const TS_SAND_TEXELS := 36.0      # cell 36×36 texel
const TS_SAND_YARDS := 64.0       # 36 × 1.775 = 63.9 ⇒ **正好 1:1**, 不糊
const TS_SAND_FPS := 12.0         # 8 帧 ÷ 12 = 0.67 秒一圈
## ★★它住在这儿而不是文件顶部: `tooltip_number_audit` 的判据是「文案里的数值必须在
##   `p2eq_059` 字面量 ±2500 字符内」, 把这 9 行注释插在顶部会把 TS_DUR / TS_ECHARGE_MULT /
##   TS_INSTANT_ENERGY 三个【真数值】挤出窗口 ⇒ 当场红。常量放它自己的消费者旁边, 本来也更对。

# 携带者身上的【时之砂】: 一小把金沙绕着他走, 标出"这里的时间还在流"(时之主)。
# ★不是光球 —— 覆盖只有 2.5%(白球那版是整只盖没), 龟必须看得见, 那正是参考里的样子。
# ★不挂 tween: 帧号由 `_ts_tick_visual` 按**真实时间**推(`_ts_sand_t`), 因为全局 `_t` 在时停里是冻的。
func _ts_caster_sand(c: Dictionary) -> void:
	var g := Sprite3D.new()
	g.texture = load(TS_SAND_TEX)
	g.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # 像素画必须 NEAREST
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.hframes = TS_SAND_FRAMES
	g.frame = 0
	g.modulate = Color(1, 1, 1, 1)
	g.pixel_size = (TS_SAND_YARDS * battle.WS) / TS_SAND_TEXELS   # 1 texel = 1 屏幕像素
	g.position = battle._world_pos(c["pos"], 0.7)
	battle._world.add_child(g)
	## 只登记**跟随**(位置), 不登记 `loop_fps`/`anim_fps` —— 那两条都读 `battle._t`(时停时冻结)。
	battle._follow_vfx.append({"spr": g, "unit": c, "h": 0.7})
	_ts_glow_sprs.append(g)

# 停摆钟: 叠加层顶(不被褪色), 半透明浮于屏幕中心, 缓慢脉动
func _ts_spawn_clock() -> void:
	if _ts_overlay == null or not is_instance_valid(_ts_overlay):
		return
	var clk := TextureRect.new()
	clk.texture = load("res://assets/sprites/vfx/ts-clock.png")
	clk.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp = battle.get_viewport().get_visible_rect().size
	var sz := 230.0
	clk.size = Vector2(sz, sz)
	clk.position = Vector2(vp.x * 0.5 - sz * 0.5, vp.y * 0.05)   # 屏幕中心偏上
	clk.pivot_offset = Vector2(sz * 0.5, sz * 0.5)
	clk.modulate = Color(1, 1, 1, 0.0)
	_ts_overlay.add_child(clk)
	_ts_clock = clk
	var tw = battle.create_tween().bind_node(clk).set_loops()  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	tw.tween_property(clk, "modulate:a", 0.30, 0.9).from(0.10)
	tw.tween_property(clk, "modulate:a", 0.15, 0.9)

func _ts_clear_visual_nodes() -> void:
	for g in _ts_glow_sprs:
		if is_instance_valid(g):
			g.queue_free()
	_ts_glow_sprs = []
	_ts_free_cores()
	_ts_free_auras()
	if _ts_clock != null and is_instance_valid(_ts_clock):
		var clk := _ts_clock
		var tw = battle.create_tween()
		tw.tween_property(clk, "modulate:a", 0.0, 0.25)
		tw.tween_callback(clk.queue_free)
	_ts_clock = null

# 蓄力(1s): 携带者身上冒金火气(参考 10.00~10.80 秒) + 头顶沙漏虚影浮现微升; 最后 0.17 秒胸口白金光点亮起(_ts_core_step)
func _ts_charge_vfx(c: Dictionary) -> void:
	_ts_aura_spawn(c)   # 金火气(替掉原来的脚下金环 + 10 颗软光球: 两个都是禁区形状, 参考里也没有)
	# 沙漏虚影
	var hg := Sprite3D.new()
	hg.texture = load("res://assets/sprites/vfx/ts-hourglass.png")
	hg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hg.shaded = false; hg.transparent = true
	hg.modulate = Color(1.0, 0.92, 0.6, 0.0)
	hg.pixel_size = (54.0 * battle.WS) / float(maxi(1, hg.texture.get_height()))
	hg.position = battle._world_pos(c["pos"], 2.4)
	battle._world.add_child(hg)
	var tw = battle.create_tween(); tw.set_parallel(true)
	tw.tween_property(hg, "modulate:a", 0.95, 0.4)
	tw.tween_property(hg, "position", battle._world_pos(c["pos"], 3.0), 1.0).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(hg, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(hg.queue_free)

# 跟随单位的特效: 每帧把 sprite 贴到目标最新世界坐标(含击飞抬升). sprite 被 queue_free 后自动从列表剔除.