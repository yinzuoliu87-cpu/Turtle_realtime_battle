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
var _ts_glow_sprs: Array = []             # 携带者"时之主"金辉光sprite(结束移除)

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
	if casters.is_empty():
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
	_ts_begin_freeze()
	_ts_visual_start()

func _end_timestop() -> void:
	for _c in _ts_active:
		if _c is Dictionary: _c.erase("_ts_echarge")   # 时停结束: 撤掉+100%充能速度
	_ts_resume_freeze()
	_ts_visual_end()
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
		sh.code = "shader_type canvas_item;\nuniform float amount : hint_range(0.0,1.0) = 0.0;\nuniform vec2 center = vec2(0.5,0.5);\nuniform float radius = 0.0;\nuniform float aspect = 1.778;\nuniform vec2 casters[4];\nuniform int caster_n = 0;\nuniform float caster_r = 0.115;\nvoid fragment(){\n\tvec2 d = SCREEN_UV - center; d.x *= aspect;\n\tfloat mask = 1.0 - smoothstep(radius-0.12, radius, length(d));\n\tfloat a = amount * mask;\n\tfloat keep = 0.0;\n\tfor(int i=0;i<4;i++){\n\t\tif(i>=caster_n){break;}\n\t\tvec2 cd = SCREEN_UV - casters[i]; cd.x *= aspect;\n\t\tkeep = max(keep, 1.0 - smoothstep(caster_r*0.55, caster_r, length(cd)));\n\t}\n\ta *= (1.0 - keep);\n\tCOLOR = vec4(0.04, 0.04, 0.08, a * 0.82);\n}"
	else:
		sh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float amount : hint_range(0.0,1.0) = 0.0;\nuniform vec2 center = vec2(0.5,0.5);\nuniform float radius = 0.0;\nuniform float aspect = 1.778;\nuniform vec2 casters[4];\nuniform int caster_n = 0;\nuniform float caster_r = 0.115;\nvoid fragment(){\n\tvec3 c = texture(screen_tex, SCREEN_UV).rgb;\n\tvec2 d = SCREEN_UV - center; d.x *= aspect;\n\tfloat mask = 1.0 - smoothstep(radius-0.12, radius, length(d));\n\tfloat a = amount * mask;\n\tfloat keep = 0.0;\n\tfor(int i=0;i<4;i++){\n\t\tif(i>=caster_n){break;}\n\t\tvec2 cd = SCREEN_UV - casters[i]; cd.x *= aspect;\n\t\tkeep = max(keep, 1.0 - smoothstep(caster_r*0.55, caster_r, length(cd)));\n\t}\n\ta *= (1.0 - keep);\n\tfloat g = dot(c, vec3(0.299,0.587,0.114));\n\tvec3 dim = vec3(g*0.56, g*0.56, g*0.64);\n\tCOLOR = vec4(mix(c, dim, a), 1.0);\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("amount", 0.0)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("aspect", vp.x / maxf(1.0, vp.y))
	mat.set_shader_parameter("casters", PackedVector2Array())
	mat.set_shader_parameter("caster_n", 0)
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
		fsh.code = "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear;\nuniform float invert : hint_range(0.0,1.0) = 0.0;\nvoid fragment(){\n\tvec3 c = texture(screen_tex, SCREEN_UV).rgb;\n\tCOLOR = vec4(mix(c, vec3(1.0)-c, invert), 1.0);\n}"
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

# 释放: ①反色闪 ②压暗褪色从携带者扩散(昏暗冷灰) ③钟+携带者金辉光 (忠实DIO "時よ止まれ")
func _ts_visual_start() -> void:
	_ts_ensure_overlay()
	var mat: ShaderMaterial = _ts_rect.material
	var fmat: ShaderMaterial = _ts_flash_rect.material
	mat.set_shader_parameter("center", _ts_casters_screen_uv())
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("amount", 0.0)
	fmat.set_shader_parameter("invert", 0.0)
	var fl = battle.create_tween()   # ①反色闪(负片一下, 含全屏UI)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.0, 0.92, 0.05)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.92, 0.0, 0.13)
	var sp = battle.create_tween(); sp.set_parallel(true)   # ②压暗褪色从携带者铺开
	sp.tween_method(func(v: float): mat.set_shader_parameter("radius", v), 0.0, 2.1, 0.5).set_ease(Tween.EASE_OUT)
	sp.tween_method(func(v: float): mat.set_shader_parameter("amount", v), 0.0, 1.0, 0.5)
	for c in _ts_active:
		_ts_shock_ring(c["pos"])       # 中心能量涟漪波
		_ts_caster_glow(c)             # ③携带者"时之主"金辉光
	_ts_spawn_clock()                  # 停摆钟浮现

func _ts_visual_end() -> void:   # 解除: 反色再闪 + 回色(时间恢复流动)
	_ts_clear_visual_nodes()
	if _ts_rect == null or not is_instance_valid(_ts_rect):
		return
	var mat: ShaderMaterial = _ts_rect.material
	var fmat: ShaderMaterial = _ts_flash_rect.material
	var fl = battle.create_tween()
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.0, 0.7, 0.04)
	fl.tween_method(func(v: float): fmat.set_shader_parameter("invert", v), 0.7, 0.0, 0.1)
	var tw = battle.create_tween()
	tw.tween_method(func(v: float): mat.set_shader_parameter("amount", v), 1.0, 0.0, 0.35)

func _ts_tick_visual(_delta: float) -> void:   # 每帧喂携带者屏幕位置给灰shader → 彩色泡跟随移动的时之主
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

# 中心能量涟漪: 一圈青白波从pos扩散(时停释放冲击波)
func _ts_shock_ring(pos2d: Vector2) -> void:
	var r := Sprite3D.new()
	var tex := VfxTex._make_fire_glow_tex()
	r.texture = tex
	r.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	r.shaded = false; r.transparent = true
	r.modulate = Color(0.7, 0.92, 1.0, 0.0)
	r.pixel_size = (60.0 * battle.WS) / float(maxi(1, tex.get_width()))
	r.position = battle._world_pos(pos2d, 1.0)
	battle._world.add_child(r)
	var tw = battle.create_tween(); tw.set_parallel(true)   # 视觉波不冻结
	tw.tween_property(r, "modulate:a", 0.85, 0.12)
	tw.tween_property(r, "pixel_size", (900.0 * battle.WS) / float(maxi(1, tex.get_width())), 0.55).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(r, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(r.queue_free)

# 携带者金辉光: 身后金色发光球, 跟随+脉动 (时之主)
func _ts_caster_glow(c: Dictionary) -> void:
	var g := Sprite3D.new()
	var tex := VfxTex._make_fire_glow_tex()
	g.texture = tex
	g.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	g.shaded = false; g.transparent = true
	g.render_priority = -1
	g.modulate = Color(1.0, 0.82, 0.32, 0.0)
	g.pixel_size = (150.0 * battle.WS) / float(maxi(1, tex.get_width()))
	g.position = battle._world_pos(c["pos"], 1.0)
	battle._world.add_child(g)
	battle._follow_vfx.append({"spr": g, "unit": c, "h": 1.0})
	_ts_glow_sprs.append(g)
	var tw = battle.create_tween().bind_node(g).set_loops()   # 脉动(不冻结→时之主持续发光)  # ★bind_node: 目标被 queue_free 后 tween 随之销毁; 否则循环 tween 的 tweener 会瞬间完成 → 单圈时长=0 → 刷 ERROR: Infinite loop detected
	tw.tween_property(g, "modulate:a", 0.7, 0.6).from(0.35)
	tw.tween_property(g, "modulate:a", 0.35, 0.6)

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
	if _ts_clock != null and is_instance_valid(_ts_clock):
		var clk := _ts_clock
		var tw = battle.create_tween()
		tw.tween_property(clk, "modulate:a", 0.0, 0.25)
		tw.tween_callback(clk.queue_free)
	_ts_clock = null

# 蓄力(1s): 携带者头顶沙漏虚影浮现+微升 + 金沙粒从四周螺旋汇入 + 脚下金环
func _ts_charge_vfx(c: Dictionary) -> void:
	battle._skill_ring(c["pos"], Color(1.0, 0.85, 0.35, 0.85), 100.0)
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
	# 金沙粒螺旋汇入(圆粒: 用_make_fire_glow_tex真圆, 非_make_glow_texture方角GradientTexture2D)
	var ptex := VfxTex._make_fire_glow_tex()
	for k in range(10):
		var sp := Sprite3D.new()
		sp.texture = ptex
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false; sp.transparent = true
		sp.modulate = Color(1.0, 0.82, 0.32, 0.9)
		sp.pixel_size = 0.42 / float(maxi(1, ptex.get_width()))
		var ang := TAU * float(k) / 10.0
		var off := Vector2(cos(ang), sin(ang)) * 130.0
		sp.position = battle._world_pos(c["pos"] + off, 1.4)
		battle._world.add_child(sp)
		var stw = battle.create_tween(); stw.set_parallel(true)
		stw.tween_property(sp, "position", battle._world_pos(c["pos"], 1.6), 0.9).set_ease(Tween.EASE_IN)
		stw.tween_property(sp, "modulate:a", 0.0, 0.9)
		stw.chain().tween_callback(sp.queue_free)

# 跟随单位的特效: 每帧把 sprite 贴到目标最新世界坐标(含击飞抬升). sprite 被 queue_free 后自动从列表剔除.