"""cent_fix11_landing_1127.py —— 百夫长登场按特效师流程分层(研究稿 20261127-普攻冲击罩参考 · R 落地插矛 / R 冲击 / R 下坠彗星)
  下坠: 本体裹一组尖朝下的彗星罩(暗 / 金 / 叠加 + 流光), 一路往上留星尘
  插矛: 矛周围竖直光罩(暗 / 金 / 叠加) + 地面亮光(下垫暗光) + 横向星芒 + 星点往上飘, 一直到本人砸下
  砸地: 亮闪 0.15 秒 + 暗光 0.45 秒垫底 + 土浪环往外推 + 两道金色余震环 + 碎石迸射 + 星尘迸射(原有裂坑 / 整岛地裂 / 震屏保留)
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

HELPERS = '''## 登场分层(11-27, 研究稿 R 落地插矛 / R 冲击 / R 下坠彗星)
const DOWN := Vector3(0.0, 0.0, -PI * 0.5)   # 本地 +X 转成朝下(抛物面尖端朝地, 口朝上)


## 一组同形锥(尖端朝下): [着色器, 长, 口径, 往后错开(米), 参数, 绘制顺序]
func _cone_set(spec: Array, pos: Vector3, rot: Vector3) -> Array:
	var parts: Array = []
	for sp in spec:
		var prm: Dictionary = (sp[4] as Dictionary).duplicate()
		prm["prog"] = 0.0
		prm["fade"] = 1.0
		var mi := Cent3dVfx.node(battle._world, Cent3dVfx.gen_shock(float(sp[1]), float(sp[2]), 8, 20), sp[0], CONE_SP, prm, int(sp[5]))
		mi.rotation = rot
		mi.position = pos
		parts.append({"node": mi, "off": float(sp[3])})
	return parts


func _cone_set_tick(parts: Array, pos: Vector3, axis: Vector3, t: float, fade: float, vis: bool) -> void:
	for p in parts:
		var n = p["node"]
		if n == null or not is_instance_valid(n):
			continue
		(n as MeshInstance3D).visible = vis
		(n as MeshInstance3D).position = pos - axis * float(p["off"])
		var m: ShaderMaterial = (n as MeshInstance3D).material_override
		m.set_shader_parameter("prog", t * 8.0)
		m.set_shader_parameter("fade", fade)


func _cone_set_free(parts) -> void:
	if parts is Array:
		for p in parts:
			_free(p["node"])


## 连续冒的粒子(星尘 / 星点): 方向 = 世界方向
func _stream_ps(pos: Vector3, dir: Vector3, amount: int, life: float, v0: float, v1: float, spread: float, sz: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = life
	ps.randomness = 0.7
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0.0, -0.5, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _gold_ramp(0.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(sz)
	ps.position = pos
	battle._world.add_child(ps)
	return ps


func _stop_ps(ps) -> void:
	if ps != null and is_instance_valid(ps):
		(ps as GPUParticles3D).emitting = false
		_aegis_junk.append({"node": ps, "left": 1.2})


## 一次性迸射(碎石用彩色贴图 + 普通混合; 星尘用金色光点 + 叠加)
func _burst_ps(pos: Vector3, amount: int, life: float, v0: float, v1: float, spread: float, grav: float, sz: float, rock: bool) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = life
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.randomness = 0.8
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0.0, grav, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.8
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	if rock:
		var gd := Gradient.new()
		gd.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
		gd.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		var gt := GradientTexture1D.new()
		gt.gradient = gd
		pm.color_ramp = gt
		var qm := QuadMesh.new()
		qm.size = Vector2(sz, sz)
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = Cent3dVfx.tex("rock.png")
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		qm.material = sm
		ps.draw_pass_1 = qm
	else:
		pm.color_ramp = _gold_ramp(1.0)
		ps.draw_pass_1 = _mote_quad(sz)
	ps.process_material = pm
	ps.position = pos
	ps.emitting = true
	battle._world.add_child(ps)
	_aegis_junk.append({"node": ps, "left": life + 0.4})


## 贴地的单张光(亮光 / 暗光垫底): 统一推帧最后 0.15 秒淡掉删除
func _ground_glow(pos2: Vector2, size_m: float, col: Color, life: float) -> void:
	var s := _strip(Cent3dVfx.AT + "glow.png", 1, battle._world_pos(pos2, 0.06), size_m, 0.0, false, life, true, null, 0.0)
	if s != null:
		s.modulate = col


## 一圈往外推的环(土浪 / 余震): 半径 r 米, rd 秒扩完
func _ring_wave(pos2: Vector2, r: float, rd: float, mid: Color, hot: Color, delay: float) -> void:
	if not _ok():
		return
	var ring := Cent3dVfx.node(battle._world, Cent3dVfx.gen_fan(0.1, r, TAU, 0.08, 56, 6), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "open": 1.0, "shell_k": 0.0, "fade": 0.0,
		 "col_mid": Vector3(mid.r, mid.g, mid.b), "col_hot": Vector3(hot.r, hot.g, hot.b)}, 0)
	ring.position = battle._world_pos(pos2, 0.0)
	_stabs.append({"parts": [], "bills": [], "ring": ring, "t": -delay, "life": rd + delay, "rd": rd, "p0": Vector3.ZERO, "d3": Vector3.ZERO, "dist": 0.0})


func cent_land(p: Dictionary, sec: float) -> void:
'''

COMET_SPEC = '''[
		[CONE_MIX, 3.4, 1.05, 0.0, {"col": Vector4(0.2, 0.06, 0.02, 0.5), "rim_mix": 0.45, "tail": 0.55, "apex": 0.2}, 10],
		[CONE_MIX, 2.8, 0.85, 0.0, {"col": Vector4(1.0, 0.74, 0.25, 0.6), "rim_mix": 0.7, "tail": 0.5, "apex": 1.0}, 11],
		[CONE_ADD, 3.4, 0.95, 0.0, {"col": Vector4(0.85, 0.28, 0.1, 0.55), "rim_mix": 0.5, "tail": 0.45, "apex": 0.6}, 12],
		[CONE_MIX, 6.5, 1.15, 0.3, {"col": Vector4(1.0, 0.95, 0.8, 0.8), "rim_mix": 0.0, "tail": 0.6, "apex": 0.0, "streaks": 20.0}, 12],
	]'''

PLANT_SPEC = '''[
		[CONE_MIX, 2.6, 0.55, 0.0, {"col": Vector4(0.25, 0.05, 0.02, 0.45), "rim_mix": 0.5, "tail": 0.6, "apex": 0.3}, 10],
		[CONE_ADD, 2.2, 0.42, 0.0, {"col": Vector4(1.0, 0.7, 0.3, 0.6), "rim_mix": 0.6, "tail": 0.55, "apex": 1.2}, 12],
		[CONE_ADD, 2.6, 0.5, 0.0, {"col": Vector4(0.9, 0.15, 0.08, 0.45), "rim_mix": 0.5, "tail": 0.5, "apex": 0.6}, 12],
	]'''


def main():
    rel = "scripts/scenes/battle/spear_eq_vfx.gd"
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")

    def rep(a, b):
        nonlocal s
        assert s.count(a) == 1, (a[:70], s.count(a))
        s = s.replace(a, b)

    rep("func cent_land(p: Dictionary, sec: float) -> void:\n", HELPERS)
    ## 下坠彗星罩 + 星尘: 落地前 CENT_DROP_SEC 才出现
    rep('\t_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec), "mk": mk, "sp": sp, "tr": tr, "planted": false, "ghost": 0.0})\n',
        '\tvar comet: Array = _cone_set(' + COMET_SPEC + ', battle._world_pos(Vector2(p["pos"]), CENT_DROP_H), DOWN) if _ok() else []\n'
        '\t_cone_set_tick(comet, Vector3.ZERO, Vector3.DOWN, 0.0, 1.0, false)\n'
        '\t_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec), "mk": mk, "sp": sp, "tr": tr, "planted": false, "ghost": 0.0,\n'
        '\t\t"comet": comet, "dust": null, "plant_fx": [], "plant_ps": null})\n')
    rep('''			l["ghost"] = float(l["ghost"]) - delta
''', '''			## 彗星罩裹着本体往下砸(尖端在脚下), 一路往上留星尘
			var hb: float = CENT_DROP_H * (1.0 - k * k)
			_cone_set_tick(l["comet"], battle._world_pos(Vector2(u["pos"]), hb - 0.3), Vector3.DOWN, t, 1.0, k < 1.0)
			if l.get("dust") == null and _ok():
				l["dust"] = _stream_ps(battle._world_pos(Vector2(u["pos"]), hb), Vector3.UP, 50, 0.6, 0.5, 2.0, 30.0, 0.12)
			var dps = l.get("dust")
			if dps != null and is_instance_valid(dps):
				(dps as GPUParticles3D).position = battle._world_pos(Vector2(u["pos"]), hb + 1.0)
			l["ghost"] = float(l["ghost"]) - delta
''')
    rep('''				if kk >= 1.0 and not bool(l["planted"]):
					l["planted"] = true
''', '''				if kk >= 1.0 and not bool(l["planted"]):
					l["planted"] = true
					## 插矛: 竖直光罩 + 地面亮光(下垫暗光) + 横向星芒 + 星点往上飘, 一直到本人砸下
					var up2 := Vector2(u["pos"])
					var rest: float = maxf(0.2, float(l["sec"]) - t + 0.1)
					_ground_glow(up2, 5.5, Color(0.14, 0.05, 0.02, 0.55), rest)
					_ground_glow(up2, 3.4, Color(1.0, 0.78, 0.38, 0.9), rest)
					l["plant_fx"] = _cone_set(''' + PLANT_SPEC.replace("\n\t\t", "\n\t\t\t\t\t\t").replace("\n\t]", "\n\t\t\t\t\t]") + ''', battle._world_pos(up2, 0.05), DOWN)
					l["plant_ps"] = _stream_ps(battle._world_pos(up2, 0.3), Vector3.UP, 40, 1.0, 2.0, 4.0, 15.0, 0.12)
					var fl := Sprite3D.new()   # 横向星芒(插地那一下)
					fl.texture = Cent3dVfx.tex("xstar.png")
					fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					fl.shaded = false
					fl.transparent = true
					fl.no_depth_test = true
					fl.render_priority = 14
					fl.modulate = Color(1.0, 0.88, 0.6, 1.0)
					fl.pixel_size = 2.0 / float(fl.texture.get_width())
					fl.scale = Vector3(3.0, 0.35, 1.0)
					fl.position = battle._world_pos(up2, 0.4)
					battle._world.add_child(fl)
					_mfx.append({"node": fl, "nf": 1, "fps": 0.0, "t": 0.0, "life": 0.35, "loop": false, "follow": null, "h": 0.0})
''')
    ## 插好之后: 竖直光罩一直闪(跟着时间推流光)
    rep('''		if t >= sec or not u.get("alive", false):
			u["_slam_voff"] = Vector3.ZERO
''', '''		if bool(l["planted"]):
			_cone_set_tick(l["plant_fx"], battle._world_pos(Vector2(u["pos"]), 0.05), Vector3.DOWN, t, 1.0, true)
		if t >= sec or not u.get("alive", false):
			u["_slam_voff"] = Vector3.ZERO
			_cone_set_free(l.get("comet"))
			_cone_set_free(l.get("plant_fx"))
			_stop_ps(l.get("dust"))
			_stop_ps(l.get("plant_ps"))
''')
    ## 砸地
    rep('''	battle._shake(battle.JUICE_SHAKE_HEAVY)
	_island_cracks(Vector2(p["pos"]))''', '''	battle._shake(battle.JUICE_SHAKE_HEAVY)
	## 研究稿 R 冲击: 亮闪 → 暗光垫底 → 土浪环 + 两道余震环 + 碎石 / 星尘迸射
	var c2 := Vector2(p["pos"])
	_ground_glow(c2, 12.0, Color(0.12, 0.05, 0.02, 0.6), 0.5)
	_ground_glow(c2, 8.0, Color(1.0, 0.85, 0.5, 1.0), 0.18)
	_ring_wave(c2, 9.0, 0.55, Color(0.55, 0.4, 0.25), Color(0.85, 0.72, 0.5), 0.0)       # 土浪
	_ring_wave(c2, 6.5, 0.25, Color(1.0, 0.62, 0.14), Color(1.0, 0.95, 0.8), 0.0)        # 余震环 1
	_ring_wave(c2, 13.0, 0.35, Color(1.0, 0.62, 0.14), Color(1.0, 0.95, 0.8), 0.08)      # 余震环 2
	if _ok():
		_burst_ps(battle._world_pos(c2, 0.3), 40, 0.9, 5.0, 10.0, 70.0, -14.0, 0.26, true)    # 碎石
		_burst_ps(battle._world_pos(c2, 0.5), 60, 0.8, 3.0, 7.0, 60.0, -3.0, 0.13, false)     # 星尘
	_island_cracks(Vector2(p["pos"]))''')
    ## 环的扩开时长可调
    rep('''			var rk: float = t / 0.22
''', '''			var rk: float = maxf(0.0, t) / float(st.get("rd", 0.22))
''')
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok")


main()
