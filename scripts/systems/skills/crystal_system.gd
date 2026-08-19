class_name CrystalSystem
extends RefCounted
## 水晶龟技能系统
## 类内名不变;外部名加 battle.

## ★水晶数值单一事实源(用户2026-07-28 第一轮加强)。文案在 data/pets.json，改这里要同步改那边。
const BULWARK_ATK := 2.0        # 水晶壁垒: 盾 = ×ATK  (1.0→2.0)
const BULWARK_HP_PCT := 0.10    # 水晶壁垒: 盾 += ×最大生命 (0.05→0.10)
const BURST_MAGIC := 1.2        # 碎晶爆破: 三段合计 ×ATK 魔法 (0.7→0.8→1.2·用户2026-07-29 第五轮: 每段 0.4)
const BURST_TRUE := 1.2         # 碎晶爆破: 三段合计 ×ATK 真实 (0.1→0.3→1.2·用户2026-07-29 第五轮: 每段 0.4)

var battle

func _init(b) -> void:
	battle = b

func _crystal_line_seg(u: Dictionary, si: int, dir: Vector2) -> void:
	if not u.get("alive", false): return
	var origin: Vector2 = u["pos"]
	_crystal_beam(origin, origin + dir * 1500.0, Color("#c9b0ff"))
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if battle._on_line(origin, dir, o["pos"], 55.0):
			battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, float([30, 35, 40][si]), o, true), Color("#bfa8ff"), 0.0, false, true)
			battle._equip_sys._eq_crystal_stack(u, o, si)

func _crystal_spark(pos2d: Vector2, h: float = 0.9) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	if tex == null: return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (26.0 * battle.WS) / float(maxi(1, int(tex.get_height())))
	spr.position = battle._world_pos(pos2d, h)
	spr.modulate = Color(1, 1, 1, 0)
	spr.rotation.z = randf_range(-0.4, 0.4)
	battle._world.add_child(spr)
	var tw = battle._reg_tween()
	tw.tween_property(spr, "modulate:a", 1.0, 0.07)
	tw.tween_interval(0.1)
	tw.tween_property(spr, "modulate:a", 0.0, 0.28)
	tw.tween_callback(spr.queue_free)
	var tw2 = battle._reg_tween()
	tw2.tween_property(spr, "rotation:z", spr.rotation.z + 0.8, 0.45)

# 引爆弹射碎片: 从中心抛物线飞出(升→落)+自旋+末端淡出 (满5引爆用·用户2026-07-16要完整爆炸演出)
# 引爆弹射碎片: 从中心抛物线飞出(升→落)+自旋+末端淡出 (满5引爆用·用户2026-07-16要完整爆炸演出)
func _crystal_shrapnel(pos2d: Vector2) -> void:
	var tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	if tex == null: return
	var spr = Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.pixel_size = (randf_range(14.0, 24.0) * battle.WS) / float(maxi(1, int(tex.get_height())))
	spr.position = battle._world_pos(pos2d, 0.8)
	spr.modulate = Color(1, 1, 1, 1)
	spr.rotation.z = randf() * TAU
	battle._world.add_child(spr)
	var ang: float = randf() * TAU
	var dist: float = randf_range(55.0, 130.0)
	var dst: Vector2 = pos2d + Vector2(cos(ang), sin(ang)) * dist
	var dur: float = randf_range(0.4, 0.6)
	var tw = battle._reg_tween(); tw.set_parallel(true)
	tw.tween_property(spr, "position", battle._world_pos(dst, 0.15), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 水平飞出+落地(QUAD_IN=重力感)
	tw.tween_property(spr, "rotation:z", spr.rotation.z + randf_range(-7.0, 7.0), dur)
	tw.tween_property(spr, "modulate:a", 0.0, 0.18).set_delay(dur - 0.18)
	tw.chain().tween_callback(spr.queue_free)
	var up = battle._reg_tween()                                       # 先升后落(两段高度=抛物线)
	up.tween_property(spr, "position:y", spr.position.y + randf_range(0.2, 0.55), dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# 水晶光束: 亮白核 + 紫辉 + 沿线水晶碎片 (030 直线用)
# 水晶光束: 亮白核 + 紫辉 + 沿线水晶碎片 (030 直线用)
func _crystal_beam(a2d: Vector2, b2d: Vector2, col: Color) -> void:
	battle._bolt_line(a2d, b2d, Color(1.0, 0.95, 1.0, 0.95))
	battle._bolt_line(a2d, b2d, col)
	var n: int = clampi(int((b2d - a2d).length() / 60.0), 1, 20)
	for i in range(1, n + 1):
		_crystal_spark(a2d.lerp(b2d, float(i) / float(n + 1)))

# 可视水晶叠层: 敌身周围绕 n 颗水晶碎片 (n=当前层数, 0=清除)
# 可视水晶叠层: 敌身周围绕 n 颗水晶碎片 (n=当前层数, 0=清除)
func _crystal_stack_set(o: Dictionary, n: int) -> void:
	var arr: Array = o.get("_xtal_shards", [])
	while arr.size() > n:
		var s = arr.pop_back()
		if is_instance_valid(s):
			battle._unfollow_vfx(s)
			s.queue_free()
	var tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	while arr.size() < n and tex != null:
		var idx: int = arr.size()
		var spr = Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.pixel_size = (22.0 * battle.WS) / float(maxi(1, int(tex.get_height())))
		spr.modulate = Color(1, 1, 1, 0)
		battle._world.add_child(spr)
		battle._follow_vfx.append({"spr": spr, "unit": o, "h": 1.5, "orbit_r": 0.34, "orbit_a": float(idx) * TAU / 3.0, "orbit_spd": 2.6})
		var tw = battle._reg_tween()
		tw.tween_property(spr, "modulate:a", 0.95, 0.15)
		arr.append(spr)
	o["_xtal_shards"] = arr

# 水晶满5引爆(用户2026-07-16重做): 爆闪+环 → 6根大水晶尖刺CRACK弹出定格 → 碎裂+14片抛物线弹射 + 冰雾
func _crystal_detonate(pos2d: Vector2) -> void:
	battle._shake(0.14)                                             # 引爆=大事件
	battle._skill_ring(pos2d, Color(0.72, 0.92, 1.0, 0.88), 26.0)   # 内爆环
	battle._skill_ring(pos2d, Color(0.5, 0.78, 1.0, 0.45), 74.0)    # 冲击波外环
	var glow = VfxTex._make_fire_glow_tex()
	var fl = Sprite3D.new()                                  # 中心冰白爆闪
	fl.texture = glow
	fl.modulate = Color(0.9, 0.98, 1.0, 1.0)
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false
	fl.transparent = true
	fl.pixel_size = (40.0 * battle.WS) / float(maxi(1, glow.get_width()))
	fl.position = battle._world_pos(pos2d, 0.9)
	battle._world.add_child(fl)
	var tw = battle._reg_tween()
	tw.set_parallel(true)
	tw.tween_property(fl, "pixel_size", (150.0 * battle.WS) / float(maxi(1, glow.get_width())), 0.26)
	tw.tween_property(fl, "modulate:a", 0.0, 0.26)
	tw.chain().tween_callback(fl.queue_free)
	var mist = Sprite3D.new()                                # 冰雾(淡蓝慢扩散)
	mist.texture = glow
	mist.modulate = Color(0.7, 0.88, 1.0, 0.4)
	mist.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mist.shaded = false
	mist.transparent = true
	mist.pixel_size = (60.0 * battle.WS) / float(maxi(1, glow.get_width()))
	mist.position = battle._world_pos(pos2d, 0.5)
	battle._world.add_child(mist)
	var mtw = battle._reg_tween(); mtw.set_parallel(true)
	mtw.tween_property(mist, "pixel_size", (210.0 * battle.WS) / float(maxi(1, glow.get_width())), 0.8)
	mtw.tween_property(mist, "modulate:a", 0.0, 0.8)
	mtw.chain().tween_callback(mist.queue_free)
	var tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	if tex != null:                                           # 6根大水晶尖刺: CRACK弹出(BACK缓动)→定格→碎裂
		for k in range(6):
			var a: float = k * TAU / 6.0 + randf_range(-0.25, 0.25)
			var off: Vector2 = pos2d + Vector2(cos(a), sin(a)) * randf_range(14.0, 34.0)
			var spike = Sprite3D.new()
			spike.texture = tex
			spike.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spike.shaded = false
			spike.transparent = true
			spike.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			var full: float = (randf_range(52.0, 78.0) * battle.WS) / float(maxi(1, int(tex.get_height())))
			spike.pixel_size = full * 0.15
			spike.position = battle._world_pos(off, randf_range(0.5, 1.1))
			spike.rotation.z = randf_range(-0.5, 0.5)
			spike.modulate = Color(1.25, 1.35, 1.5, 1.0)
			battle._world.add_child(spike)
			var st = battle._reg_tween()
			st.tween_property(spike, "pixel_size", full, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)   # CRACK弹出
			st.tween_interval(0.22)                                                                                   # 定格一拍
			st.tween_property(spike, "modulate:a", 0.0, 0.12)                                                         # 碎裂消失
			st.tween_callback(spike.queue_free)
	var dref: Vector2 = pos2d                                  # 尖刺碎裂时机(0.32s)追加一波弹射碎片
	for k2 in range(8):
		_crystal_shrapnel(pos2d)                                # 即刻第一波
	var dt = battle._reg_tween()
	dt.tween_interval(0.32)
	dt.tween_callback(func() -> void:
		for k3 in range(6):
			_crystal_shrapnel(dref))

## 【031 水晶球B 的扫描登记表】—— 结算走 sim 时钟, 不走 tween。
## ★★★由来(2026-08-14): 原来整段扫描挂在 `tween_method` 上, 而 **tween 在无头下推不动**
##   ⇒ 门禁永远量不到它的伤害。我一度用"同窗隔离"想绕过去, 结果本地判绿、**CI 判红**
##   (A/B 两个值在两次运行间互换 = 在量噪声)。绕不过去, 只能把结算搬出来。
## ★缓动照抄 Godot 的 `TRANS_CUBIC + EASE_IN_OUT`, 保证观感与改前一致:
##   t<0.5 → 4t³ ; 否则 → 1 - (-2t+2)³/2
var _sweeps: Array = []
const SWEEP_SEC := 1.5


## 登记一次扫描。`_eq_crystal_sweep` 只管建节点与起始角, 推进交给这里。
func sweep_begin(u: Dictionary, si: int, reach: float, state: Dictionary,
		im: MeshInstance3D, imesh: ImmediateMesh, mat: StandardMaterial3D, start_a: float) -> void:
	_sweeps.append({"u": u, "si": si, "reach": reach, "state": state,
		"im": im, "imesh": imesh, "mat": mat, "a0": start_a, "el": 0.0})


func tick(delta: float) -> void:
	for i in range(_sweeps.size() - 1, -1, -1):
		var sw: Dictionary = _sweeps[i]
		var im2 = sw["im"]
		if not is_instance_valid(im2):
			_sweeps.remove_at(i)
			continue
		sw["el"] = float(sw["el"]) + delta
		var t: float = clampf(float(sw["el"]) / SWEEP_SEC, 0.0, 1.0)
		## Godot TRANS_CUBIC / EASE_IN_OUT 的原式 —— 不近似, 保证观感不变
		var k: float = 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
		_crystal_sweep_step(float(sw["a0"]) + TAU * k, sw["u"], int(sw["si"]),
			float(sw["reach"]), sw["state"], im2, sw["imesh"], sw["mat"])
		if t >= 1.0:
			_sweeps.remove_at(i)
			im2.queue_free()


func clear_all() -> void:
	for sw in _sweeps:
		if is_instance_valid(sw["im"]):
			(sw["im"] as Node).queue_free()
	_sweeps.clear()


func _crystal_sweep_step(ang: float, u: Dictionary, si: int, reach: float, state: Dictionary, im: MeshInstance3D, imesh: ImmediateMesh, mat: StandardMaterial3D) -> void:
	if not is_instance_valid(im): return
	var center: Vector2 = u["pos"]   # 跟随携带者当前位置(非施法点定死)
	var col = Color("#c9b0ff")
	var dir2: Vector2 = Vector2(cos(ang), sin(ang))
	var perp: Vector2 = dir2.orthogonal()
	var tip2: Vector2 = center + dir2 * reach
	imesh.clear_surfaces()
	# 水晶射线本体: 根部宽→尖端细的发光光束(加色), 是"一道会转的射线"非扇面
	imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var cb = Color(col.r, col.g, col.b, 0.5)    # 根部亮
	var ct = Color(col.r, col.g, col.b, 0.06)   # 尖端淡
	var vA: Vector3 = battle._world_pos(center + perp * 8.0, 1.0)
	var vB: Vector3 = battle._world_pos(center - perp * 8.0, 1.0)
	var vD: Vector3 = battle._world_pos(tip2 + perp * 2.5, 1.0)
	var vE: Vector3 = battle._world_pos(tip2 - perp * 2.5, 1.0)
	imesh.surface_set_color(cb); imesh.surface_add_vertex(vA)
	imesh.surface_set_color(cb); imesh.surface_add_vertex(vB)
	imesh.surface_set_color(ct); imesh.surface_add_vertex(vD)
	imesh.surface_set_color(cb); imesh.surface_add_vertex(vB)
	imesh.surface_set_color(ct); imesh.surface_add_vertex(vE)
	imesh.surface_set_color(ct); imesh.surface_add_vertex(vD)
	imesh.surface_end()
	# 亮白核线(脆生生一道射线中轴)
	imesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	imesh.surface_set_color(Color(1, 0.97, 1, 1.0)); imesh.surface_add_vertex(battle._world_pos(center, 1.0))
	imesh.surface_set_color(Color(col.r, col.g, col.b, 0.22)); imesh.surface_add_vertex(battle._world_pos(tip2, 1.0))
	imesh.surface_end()
	# 沿射线拖水晶碎片(节流每3步)
	state["spk"] = int(state.get("spk", 0)) + 1
	if int(state["spk"]) % 3 == 0:
		_crystal_spark(center + dir2 * (reach * 0.4))
	if u.get("alive", false):        # 携带者死亡后仅转完视觉, 不再从尸体结算伤害
		var prev: float = float(state["prev"])
		for o in battle._targeting._enemies_of(u):
			if not o.get("alive", false): continue
			var ea: float = atan2(float(o["pos"].y) - center.y, float(o["pos"].x) - center.x)
			if battle._ang_in(prev, ang, ea):
				# 伤害 60/130/250 (用户2026-08-01: 3★由 700 削到 250 —— 一次扫过全场敌人, 700 是全表最粗的一根)
				battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, float([60, 130, 250][si]), o, true), Color("#bfa8ff"), 0.0, false, true)
				# 偷魔抗【固定10%】(用户2026-08-01: 原 10/15/50% 随星级 → 3★一扫走对面一半魔抗, 且可叠)
				var steal: float = maxf(0.0, float(o["mr"])) * 0.10   # 真偷取: 目标-X 携带者+X, 永久到战场结束
				if steal > 0.01:
					o["base_mr"] = float(o["base_mr"]) - steal; o["mr"] = float(o["mr"]) - steal
					u["base_mr"] = float(u["base_mr"]) + steal; u["mr"] = float(u["mr"]) + steal
					var samt: int = int(round(steal))
					if samt >= 1:
						battle._vfx._float_text(o["pos"] + Vector2(randf_range(-10.0, 10.0), -46.0), "魔抗-%d" % samt, Color("#c9b0ff"))
				battle._equip_sys._eq_crystal_stack(u, o, si)
				_crystal_spark(o["pos"])
	state["prev"] = ang

func _crystal_spike_line(u: Dictionary) -> void:   # 照小菊R第三击(2026-07-16逐帧): 砸地爆发→发光波头贴地冲出→波头过处水晶刺依次从地底弹出→碎晶地痕渐隐; 命中 1.5A真伤+2结晶+击飞0.8s+50%减速3s
	var tgt = battle._targeting._acquire_target(u)
	var dirv: Vector2 = Vector2.RIGHT if str(u.get("side", "left")) == "left" else Vector2.LEFT
	if tgt != null:
		var dv: Vector2 = (tgt["pos"] as Vector2) - (u["pos"] as Vector2)
		if dv.length() > 1.0: dirv = dv.normalized()
	var origin: Vector2 = u["pos"]
	var tok: int = battle._next_cast_tok()                                       # 命中标记记在敌单位上(⛔不拿字典当Dict键)
	var uu = u
	var segs: int = 22   # 间隔~32码(原12段58码太稀·用户2026-07-16)
	# ① 砸地起手爆发(小菊: 脚前亮爆+尘土)
	battle._skill_ring(origin + dirv * 40.0, Color(0.72, 0.92, 1.0, 0.85), 34.0)
	battle._shake(0.07)
	var glow0 = VfxTex._make_fire_glow_tex()
	var burst = Sprite3D.new()
	burst.texture = glow0
	burst.modulate = Color(0.8, 0.97, 1.0, 0.95)
	burst.billboard = BaseMaterial3D.BILLBOARD_ENABLED; burst.shaded = false; burst.transparent = true
	burst.pixel_size = (30.0 * battle.WS) / float(maxi(1, glow0.get_width()))
	burst.position = battle._world_pos(origin + dirv * 40.0, 0.5)
	battle._world.add_child(burst)
	var bw = battle._reg_tween(); bw.set_parallel(true)
	bw.tween_property(burst, "pixel_size", (90.0 * battle.WS) / float(maxi(1, glow0.get_width())), 0.2)
	bw.tween_property(burst, "modulate:a", 0.0, 0.2)
	bw.chain().tween_callback(burst.queue_free)
	# ② 发光波头贴地冲出(小菊: 滚动推进的能量团·全程0.5s)
	var wend: Vector2 = origin + dirv * battle.SPIKE_LINE_RANGE
	wend.x = clampf(wend.x, battle.ARENA.position.x + 20.0, battle.ARENA.end.x - 20.0)
	wend.y = clampf(wend.y, battle.ARENA.position.y + 14.0, battle.ARENA.end.y - 14.0)
	var head = Sprite3D.new()
	head.texture = glow0
	head.modulate = Color(0.7, 0.95, 1.0, 0.9)
	head.billboard = BaseMaterial3D.BILLBOARD_ENABLED; head.shaded = false; head.transparent = true
	head.pixel_size = (18.0 * battle.WS) / float(maxi(1, glow0.get_width()))
	head.position = battle._world_pos(origin + dirv * 30.0, 0.12)
	battle._world.add_child(head)
	var hw = battle._reg_tween()
	hw.tween_property(head, "pixel_size", (52.0 * battle.WS) / float(maxi(1, glow0.get_width())), 0.12)   # 从砸点由小鼓大(小菊z07→z09·非凭空满大)
	hw.parallel().tween_property(head, "position", battle._world_pos(origin + dirv * 30.0, 0.3), 0.12)
	hw.chain().tween_property(head, "position", battle._world_pos(wend, 0.3), battle.SPIKE_WAVE_TIME)
	hw.parallel().tween_property(head, "modulate:a", 0.75, battle.SPIKE_WAVE_TIME)
	hw.tween_callback(func() -> void:                            # 到头=破碎四散(小菊z11: 团碎成5-8簇甩出0.1s消·非淡出)
		if is_instance_valid(head): head.queue_free()
		for _b2 in range(7):
			_crystal_shrapnel(wend))
	var htex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
	if htex != null:                                             # 3片碎晶伴飞(小菊: 波头是实心翻涌团非软光·用碎晶簇加密度)
		var perp = Vector2(-dirv.y, dirv.x)
		for r in range(3):
			var rid = Sprite3D.new()
			rid.texture = htex
			rid.billboard = BaseMaterial3D.BILLBOARD_ENABLED; rid.shaded = false; rid.transparent = true
			rid.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			rid.pixel_size = (randf_range(16.0, 24.0) * battle.WS) / float(maxi(1, int(htex.get_height())))
			var roff: Vector2 = perp * randf_range(-20.0, 20.0) + dirv * randf_range(-16.0, 10.0)
			rid.position = battle._world_pos(origin + dirv * 30.0 + roff, 0.06)   # 出生贴地(从翻起的土里带出来·非凭空半空)
			rid.rotation.z = randf() * TAU
			rid.modulate = Color(0.85, 0.97, 1.0, 0.95)
			battle._world.add_child(rid)
			var rt = battle._reg_tween(); rt.set_parallel(true)
			rt.tween_property(rid, "position", battle._world_pos(wend + roff, randf_range(0.3, 0.5)), battle.SPIKE_WAVE_TIME)   # 飞行中渐升(贴地→半空=被浪带起)
			rt.tween_property(rid, "rotation:z", rid.rotation.z + randf_range(-9.0, 9.0), battle.SPIKE_WAVE_TIME)
			rt.chain().tween_property(rid, "modulate:a", 0.0, 0.1)
			rt.chain().tween_callback(rid.queue_free)
	for i in range(segs):
		var pref: Vector2 = origin + dirv * (battle.SPIKE_LINE_RANGE * float(i + 1) / float(segs))
		battle._pending_shots.append({"delay": battle.SPIKE_WAVE_TIME * float(i + 1) / float(segs), "fn": func() -> void:
			if not battle.ARENA.has_point(pref): return
			battle._skill_ring(pref, Color(0.62, 0.88, 1.0, 0.5), 22.0)     # 地面破土环
			if randf() < 0.35: _crystal_shrapnel(pref)                # 零星碎屑(22段密度下调频)
			if randf() < 0.3: _crystal_spark(pref + Vector2(randf_range(-16.0, 16.0), randf_range(-10.0, 10.0)), 0.35)
			var tex2: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
			if tex2 != null:                                          # 晶簇=1主刺+1~2侧刺·翻转/角度/大小/色调/停留全随机(用户: 每根不能一模一样)
				var n_spk: int = 2 + (1 if randf() < 0.5 else 0)
				for k_s in range(n_spk):
					var main: bool = k_s == 0
					var spk = Sprite3D.new()
					spk.texture = tex2
					spk.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					spk.shaded = false; spk.transparent = true
					spk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					spk.flip_h = randf() < 0.5
					var sz: float = randf_range(64.0, 96.0) if main else randf_range(30.0, 56.0)
					var fullp: float = (sz * battle.WS) / float(maxi(1, int(tex2.get_height())))
					var soff: Vector2 = Vector2.ZERO if main else Vector2(randf_range(-18.0, 18.0), randf_range(-12.0, 12.0))
					spk.pixel_size = fullp * 0.2
					spk.position = battle._world_pos(pref + soff, 0.05)
					spk.rotation.z = randf_range(-0.45, 0.45)
					var brt: float = randf_range(0.95, 1.35)
					spk.modulate = Color(brt, brt * 1.12, brt * 1.25, 1.0)
					battle._world.add_child(spk)
					var gdur: float = randf_range(0.08, 0.12)
					var htop: float = randf_range(0.5, 0.62) if main else randf_range(0.26, 0.38)
					var st = battle._reg_tween()
					st.set_parallel(true)
					st.tween_property(spk, "pixel_size", fullp, gdur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					st.tween_property(spk, "position", battle._world_pos(pref + soff, htop), gdur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					st.chain().tween_interval(randf_range(0.4, 0.6))
					st.chain().tween_property(spk, "position", battle._world_pos(pref + soff, 0.02), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 缩回地底(升出的对称)
					st.parallel().tween_property(spk, "pixel_size", fullp * 0.15, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
					st.chain().tween_callback(spk.queue_free)
			var scar_tex: Texture2D = load("res://assets/sprites/vfx/crystal-shard.png")
			if scar_tex != null:                                      # 碎晶地痕(小菊翻土痕→冰蓝碎晶·贴地1.1s渐隐)
				for _sc in range(1):   # 22段密度下每段1片痕足够
					var scar = Sprite3D.new()
					scar.texture = scar_tex
					scar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					scar.shaded = false; scar.transparent = true
					scar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
					scar.pixel_size = (randf_range(10.0, 16.0) * battle.WS) / float(maxi(1, int(scar_tex.get_height())))
					scar.position = battle._world_pos(pref + Vector2(randf_range(-24.0, 24.0), randf_range(-14.0, 14.0)), 0.08)
					scar.rotation.z = randf() * TAU
					scar.modulate = Color(0.75, 0.92, 1.0, 0.8)
					battle._world.add_child(scar)
					var sct = battle._reg_tween()
					sct.tween_property(scar, "modulate:a", 0.0, 0.6)   # 土痕0.3-0.5s渐隐(小菊)·取0.6
					sct.tween_callback(scar.queue_free)
			for o in battle._units:
				if not battle._is_hostile(uu, o) or not o.get("alive", false): continue
				if int(o.get("_spike_tok", -1)) == tok: continue
				if (o["pos"] as Vector2).distance_to(pref) > 52.0: continue
				o["_spike_tok"] = tok
				# ★水晶刺从【纯控制零伤害】改成带 1.5A 真实伤害(用户2026-07-29 第五轮)。
				#   壁垒 80 龟能 + 持盾4秒锁龟能, 而唯一输出是"+2层印记" —— 一个技能的伤害部分完全是 0。
				battle._damage._apply_damage_from(uu, o, int(maxf(1.0, uu["atk"] * 1.5)), Color("#ffffff"), 0.0, true)
				_crystal_stack(uu, o, 2)                              # +2层结晶
				battle._knock_up(o, pref, 8.8)                               # 击飞0.8s(滞空=2×8.8/22)
				o["spd_move_mult"] = 0.5
				o["spd_dbf_until"] = battle._t + 3.0                         # 50%减速3秒
		, "src": u})

# 水晶结晶叠层+满5引爆 (普攻/水晶球ray/本体主动共享·同一目标"crystal"层→天然共享层数): 叠n层(上限5)·满5→清零+22%目标最大生命魔法(吃魔抗·封板)+削魔抗-20%+紫辉爆
# 水晶结晶叠层+满5引爆 (普攻/水晶球ray/本体主动共享·同一目标"crystal"层→天然共享层数): 叠n层(上限5)·满5→清零+22%目标最大生命魔法(吃魔抗·封板)+削魔抗-20%+紫辉爆
func _crystal_stack(src: Dictionary, tgt: Dictionary, n: int) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	var cv = battle._add_stack(tgt, "crystal", n, 5)
	if cv >= 5:
		battle._consume_stacks(tgt, "crystal")
		battle._damage._apply_damage_from(src, tgt, battle._mitigate(src, tgt["maxHp"] * 0.22, tgt, true), Color("#9bdcff"), 0.0, false)   # 引爆22%最大生命魔法(吃魔抗·19%→22% 用户2026-07-29 第五轮)
		battle._damage._buff(tgt, "mr", -0.2, true)
		_crystal_detonate(tgt["pos"])

func _crystal_orb_halo(orb: Dictionary) -> void:   # 水晶球常驻脉动光环(跟随·死亡随_follow_vfx自动清·循环tween必bind_node)
	var glow = VfxTex._make_fire_glow_tex()
	var halo = Sprite3D.new()
	halo.texture = glow
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED; halo.shaded = false; halo.transparent = true
	halo.pixel_size = (52.0 * battle.WS) / float(maxi(1, glow.get_width()))
	halo.modulate = Color(0.6, 0.9, 1.0, 0.32)
	battle._world.add_child(halo)
	battle._follow_vfx.append({"spr": halo, "unit": orb, "h": 0.8})
	var tw = battle.create_tween().set_loops()
	tw.bind_node(halo)
	tw.tween_property(halo, "modulate:a", 0.52, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(halo, "modulate:a", 0.28, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# 水晶射线通用演出(球特攻+本体主动同款·用户2026-07-16: 射线要看得见): 蓄力聚能球0.25s→两段厚冰蓝光束(0.15s错峰)→命中碎晶+环; 伤害每段по调用方
# 水晶射线通用演出(球特攻+本体主动同款·用户2026-07-16: 射线要看得见): 蓄力聚能球0.25s→两段厚冰蓝光束(0.15s错峰)→命中碎晶+环; 伤害每段по调用方
func _crystal_ray_vfx(src: Dictionary, tgt: Dictionary, seg_dmg_fn: Callable) -> void:
	var glow = VfxTex._make_fire_glow_tex()
	var ch = Sprite3D.new()                                     # 蓄力聚能球
	ch.texture = glow
	ch.billboard = BaseMaterial3D.BILLBOARD_ENABLED; ch.shaded = false; ch.transparent = true
	ch.pixel_size = (10.0 * battle.WS) / float(maxi(1, glow.get_width()))
	ch.modulate = Color(0.85, 0.97, 1.0, 0.9)
	ch.position = battle._world_pos(src["pos"], 1.0)
	battle._world.add_child(ch)
	var ct = battle._reg_tween()
	ct.tween_property(ch, "pixel_size", (34.0 * battle.WS) / float(maxi(1, glow.get_width())), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ct.tween_callback(func() -> void:
		if is_instance_valid(ch): ch.queue_free())
	var sref: Dictionary = src
	var tref: Dictionary = tgt
	for seg in range(2):
		var last: bool = seg == 1
		battle._pending_shots.append({"delay": 0.25 + 0.15 * float(seg), "fn": func() -> void:
			if not sref.get("alive", false): return
			var a2: Vector2 = sref["pos"]
			var ldir: Vector2 = ((tref["pos"] as Vector2) - a2) if tref.get("alive", false) else Vector2.RIGHT * (1.0 if str(sref.get("side", "left")) == "left" else -1.0)
			if ldir.length() < 1.0: ldir = Vector2.RIGHT
			ldir = ldir.normalized()
			var b2: Vector2 = a2 + ldir * 2000.0                                                                        # 贯穿直线2000码(用户2026-07-16)
			battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", a2, b2, 30.0, Color(1.0, 1.0, 1.0, 0.95), 0.22)   # 白核
			battle._beam_vfx("res://assets/sprites/vfx/fx-energy-beam.png", a2, b2, 52.0, Color(0.55, 0.9, 1.0, 0.6), 0.3)    # 冰蓝晕
			for o in battle._units:                                                                                            # 线上全体敌人各吃一段(用户: 对一条直线敌人造成伤害)
				if not battle._is_hostile(sref, o) or not o.get("alive", false): continue
				if not battle._on_line(a2, ldir, o["pos"], 46.0): continue
				_crystal_spark(o["pos"], 0.8)
				battle._skill_ring(o["pos"], Color(0.62, 0.88, 1.0, 0.5), 26.0)
				seg_dmg_fn.call(sref, o, last)
		, "src": src})

# 水晶龟·水晶球 本体主动(封板L571·70龟能): 朝目标射一道水晶光线=2段共1.0A魔法 + 叠2层结晶(与水晶球随从共享满5引爆)·水晶球随从在spawn gate召唤

func _sk_crystal_bulwark(u: Dictionary) -> void:                 # 水晶龟·水晶壁垒(用户2026-07-16改制/2026-07-28加强): 2A+10%maxHp护盾4秒·持盾锁龟能·盾结束/被打破→700码直线水晶刺·全体友军甲抗+15%4秒
	battle._damage._grant_shield(u, u["atk"] * BULWARK_ATK + u["maxHp"] * BULWARK_HP_PCT, 4.0)
	u["bulwark_until"] = battle._t + 4.0
	u["_bulwark_armed"] = true
	var dome = Sprite3D.new()                                   # 冰蓝水晶罩(随身4秒)
	var dtex: Texture2D = load("res://assets/sprites/vfx/fx-hex-bubble.png")
	if dtex != null:
		dome.texture = dtex
		dome.billboard = BaseMaterial3D.BILLBOARD_ENABLED; dome.shaded = false; dome.transparent = true
		dome.pixel_size = (120.0 * battle.WS) / float(maxi(1, dtex.get_height()))
		dome.modulate = Color(0.62, 0.88, 1.0, 0.0)
		dome.position = battle._world_pos(u["pos"], 0.9)
		battle._world.add_child(dome)
		battle._follow_vfx.append({"spr": dome, "unit": u, "h": 0.9})
		u["_bulwark_dome"] = dome
		var dw = battle._reg_tween()
		dw.tween_property(dome, "modulate:a", 0.55, 0.2)
		dw.tween_interval(3.4)
		dw.tween_property(dome, "modulate:a", 0.0, 0.4)
		dw.tween_callback(func() -> void:
			if is_instance_valid(dome): dome.queue_free())
	for o in battle._targeting._allies_of(u):
		battle._damage._buff(o, "def", 0.15, true, 4.0); battle._damage._buff(o, "mr", 0.15, true, 4.0)
		battle._skill_ring(o["pos"], Color(0.62, 0.88, 1.0, 0.55), 40.0)   # 友军冰蓝强化环

func _sk_crystal_burst(u: Dictionary, tgt) -> void:   # 碎晶爆破: 目标周围350码内每敌3段错峰碎晶坠落(三段共 1.2A魔+1.2A真+每段叠1层结晶·共3层满5引爆·用户2026-07-28加强)
	if tgt == null: tgt = battle._targeting._nearest_enemy(u)
	if tgt == null: return
	var center: Vector2 = tgt["pos"]
	u["energy_lock_until"] = maxf(float(u.get("energy_lock_until", 0.0)), battle._t + 0.65)   # 释放途中锁龟能·放完自动解锁(用户2026-07-16; 三段0.38s+坠落0.16s≈0.55s)
	battle._skill_ring(center, Color(0.6, 0.86, 1.0, 0.5), battle.CRYSTAL_BURST_RADIUS)   # 350码范围环
	var uu = u
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false): continue
		if (o["pos"] as Vector2).distance_to(center) > battle.CRYSTAL_BURST_RADIUS: continue
		var oref: Dictionary = o
		for k in range(3):                                       # 3段碎晶从天坠落(错峰0.14s)
			battle._pending_shots.append({"delay": 0.1 + 0.14 * float(k), "fn": func() -> void:
				if not oref.get("alive", false) or not uu.get("alive", false): return
				var sh = Sprite3D.new()
				sh.texture = load("res://assets/sprites/vfx/crystal-shard.png")
				sh.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				sh.billboard = BaseMaterial3D.BILLBOARD_ENABLED; sh.shaded = false; sh.transparent = true
				sh.pixel_size = (30.0 * battle.WS) / 48.0
				sh.flip_h = randf() < 0.5
				var op2: Vector2 = oref["pos"] + Vector2(randf_range(-14.0, 14.0), randf_range(-8.0, 8.0))
				sh.position = battle._world_pos(op2, 2.4)
				battle._world.add_child(sh)
				var dt = battle._reg_tween()
				dt.tween_property(sh, "position", battle._world_pos(op2, 0.55), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # 坠落
				dt.tween_callback(func() -> void:
					if is_instance_valid(sh): sh.queue_free()
					if not oref.get("alive", false): return
					_crystal_spark(oref["pos"], 0.7)
					battle._damage._apply_damage_from(uu, oref, battle._atk_dmg(uu, BURST_MAGIC / 3.0, oref, true), Color("#9bdcff"))     # 每段 = 总 BURST_MAGIC(1.2A) 魔法 / 3
					battle._damage._apply_damage_from(uu, oref, int(maxf(1.0, uu["atk"] * BURST_TRUE / 3.0)), Color("#ffffff"), 0.0, true)   # 每段 = 总 BURST_TRUE(1.2A) 真实 / 3
					_crystal_stack(uu, oref, 1))
			, "src": u})

func _sk_crystal_orb(u: Dictionary, tgt) -> void:
	if tgt == null or not tgt.get("alive", false):
		return
	battle._skill_ring(u["pos"], Color(0.72, 0.92, 1.0, 0.6), 34.0)     # 本体施法环
	_crystal_ray_vfx(u, tgt, func(sr: Dictionary, tr: Dictionary, last: bool) -> void:
		battle._damage._apply_damage_from(sr, tr, battle._atk_dmg(sr, 0.5, tr, true), Color("#9bdcff"), 0.0, true)   # 每段0.5A魔法(raw避免二次减免·封板)
		if last: _crystal_stack(sr, tr, 2))                      # 末段叠2层结晶(封板)

# 宝箱藏宝图·15件专属战利品池 (封板L592-594·效果取自Phaser chest.js实时适配): 基础/进阶/传说三档
