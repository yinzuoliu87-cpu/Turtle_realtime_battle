"""cent_fix9_stab_layers_1127.py —— 普攻冲击罩按特效师流程分层(研究稿 docs/studies/20261127-普攻冲击罩参考-潘森Q强化飞矛配方.md)
  同一个抛物面罩叠 4 层(深褐暗层压对比 / 金色主层 / 叠加红橙中层 / 橙色流动填充)+ 外套一层高速流光;
  头部叠加光晕 + 十字星芒(逐帧闪); 出手那一下矛尖一圈垂直于刺击方向的径向冲击环; 火花粒子往前迸。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

OLD_TAIL = '''	## 外层: 白金薄罩, 大、冲得远; 内层: 小、亮、紧贴矛尖, 冲得近(两层错开读得出厚度)
	_shock(tip, d3, Cent3dVfx.gen_shock(1.6, 0.85, 8, 20), {"prog": 0.0, "fade": 1.0, "rings": 3.0, "rim_pow": 1.4, "tail": 0.45,
		"col_a": Vector3(1.0, 0.98, 0.9), "col_b": Vector3(1.0, 0.6, 0.14)}, CENT_SHOCK_SEC, CENT_SHOCK_DIST, Vector3(0.5, 0.5, 0.5), Vector3(1.35, 1.35, 1.35), 9.0)
	_shock(tip - d3 * 0.1, d3, Cent3dVfx.gen_shock(1.0, 0.45, 6, 16), {"prog": 0.0, "fade": 1.0, "rings": 2.0, "rim_pow": 1.1, "tail": 0.5,
		"col_a": Vector3(1.0, 1.0, 1.0), "col_b": Vector3(1.0, 0.8, 0.35)}, CENT_SHOCK_SEC * 0.8, CENT_SHOCK_DIST * 0.55, Vector3(0.6, 0.6, 0.6), Vector3(1.1, 1.1, 1.1), 7.0)
'''

NEW_TAIL = '''	var yaw: float = Cent3dVfx.yaw_of(Vector2(d3.x, d3.z))
	var w: Node3D = battle._world
	## 罩: 同一个抛物面叠 4 层 + 流光层(研究稿「方法」1–4): [着色器, 长, 口径, 起始缩放, 结束缩放, 往后错开(米), 参数, 绘制顺序]
	var spec: Array = [
		[CONE_MIX, 1.9, 0.62, 0.55, 1.35, 0.0, {"col": Vector4(0.22, 0.07, 0.02, 0.55), "rim_mix": 0.35, "tail": 0.5, "apex": 0.2}, 10],    # 暗层: 亮的下面垫一层深褐, 沙地上压得住
		[CONE_MIX, 1.5, 0.5, 0.5, 1.25, 0.0, {"col": Vector4(1.0, 0.72, 0.22, 0.6), "rim_mix": 0.7, "tail": 0.5, "apex": 0.9}, 11],       # 主亮层(短一点)
		[CONE_ADD, 1.9, 0.55, 0.5, 1.3, 0.0, {"col": Vector4(0.75, 0.25, 0.12, 0.55), "rim_mix": 0.5, "tail": 0.45, "apex": 0.6}, 12],    # 叠加发光中层
		[CONE_MIX, 1.9, 0.56, 0.5, 1.3, 0.0, {"col": Vector4(0.95, 0.35, 0.06, 0.4), "rim_mix": 0.2, "tail": 0.55, "apex": 0.3, "rings": 3.0}, 11],   # 流动填充(波纹往后退)
		[CONE_MIX, 2.6, 0.75, 0.55, 1.4, 0.15, {"col": Vector4(1.0, 0.95, 0.8, 0.8), "rim_mix": 0.0, "tail": 0.6, "apex": 0.0, "streaks": 22.0}, 12],   # 流光: 一条条往后飞
	]
	var parts: Array = []
	for sp in spec:
		var prm: Dictionary = (sp[6] as Dictionary).duplicate()
		prm["prog"] = 0.0
		prm["fade"] = 1.0
		var mi := Cent3dVfx.node(w, Cent3dVfx.gen_shock(float(sp[1]), float(sp[2]), 8, 24), sp[0], CONE_SP, prm, int(sp[7]))
		mi.rotation = Vector3(0.0, yaw, 0.0)
		parts.append({"node": mi, "s0": float(sp[3]), "s1": float(sp[4]), "off": float(sp[5])})
	## 头: 叠加光晕 + 十字星芒(研究稿 Missle Head Glow / leading star)
	var bills: Array = []
	for b in [["glow.png", 1.1, Color(1.0, 0.95, 0.8, 0.9), 13], ["xstar.png", 1.7, Color(1.0, 0.88, 0.6, 1.0), 14]]:
		var s := Sprite3D.new()
		s.texture = Cent3dVfx.tex(str(b[0]))
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.no_depth_test = true
		s.render_priority = int(b[3])
		s.modulate = b[2]
		s.pixel_size = float(b[1]) / float(s.texture.get_width())
		s.position = tip
		w.add_child(s)
		bills.append({"node": s, "col": b[2]})
	## 出手: 矛尖一圈垂直于刺击方向的径向冲击环(研究稿 Temp_Mesh 径向网格)
	var ring := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.05, 0.9, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "open": 1.0, "shell_k": 0.05}, 12)
	ring.position = tip
	ring.rotation = Vector3(0.0, yaw, PI * 0.5)   # 扇面本来平躺(XZ 面), 绕 Z 转 90° 立成垂直于刺击方向
	## 火花往前迸
	var ps := GPUParticles3D.new()
	ps.amount = 16
	ps.lifetime = 0.32
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.randomness = 0.7
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.0, 0.0)
	pm.spread = 22.0
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0.0, -4.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.1)
	ps.position = tip
	ps.rotation = Vector3(0.0, yaw, 0.0)
	ps.emitting = true
	w.add_child(ps)
	_aegis_junk.append({"node": ps, "left": 0.6})
	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": CENT_SHOCK_SEC, "p0": tip, "d3": d3, "dist": CENT_SHOCK_DIST})


func _tick_stabs(delta: float) -> void:
	var keep: Array = []
	for st in _stabs:
		st["t"] = float(st["t"]) + delta
		var t: float = float(st["t"])
		var k: float = t / float(st["life"])
		var rg = st.get("ring")
		if rg != null and is_instance_valid(rg):
			var rk: float = t / 0.22
			if rk >= 1.0:
				_free(rg)
				st["ring"] = null
			else:
				var rm: ShaderMaterial = (rg as MeshInstance3D).material_override
				rm.set_shader_parameter("shell_k", 0.05 + 0.9 * rk)
				rm.set_shader_parameter("fade", 1.0 - rk * rk)
				rm.set_shader_parameter("t", t)
		if k >= 1.0:
			for p in st["parts"]:
				_free(p["node"])
			for b in st["bills"]:
				_free(b["node"])
			_free(st.get("ring"))
			continue
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # 先快后慢
		var d3: Vector3 = st["d3"]
		var pos: Vector3 = Vector3(st["p0"]) + d3 * float(st["dist"]) * e
		var fd: float = 1.0 - smoothstep(0.45, 1.0, k)
		for p in st["parts"]:
			var n = p["node"]
			if n == null or not is_instance_valid(n):
				continue
			(n as MeshInstance3D).position = pos - d3 * float(p["off"])
			(n as MeshInstance3D).scale = Vector3.ONE * lerpf(float(p["s0"]), float(p["s1"]), e)
			var mat: ShaderMaterial = (n as MeshInstance3D).material_override
			mat.set_shader_parameter("prog", t * 8.0)
			mat.set_shader_parameter("fade", fd)
		var fl: float = 0.75 + 0.5 * fmod(t * 37.0, 1.0)   # 星芒逐帧闪(研究稿 leading star 寿命 0.2 秒、每秒 20 颗)
		for b in st["bills"]:
			var bn = b["node"]
			if bn == null or not is_instance_valid(bn):
				continue
			(bn as Sprite3D).position = pos + d3 * 0.05
			(bn as Sprite3D).scale = Vector3.ONE * fl * lerpf(0.8, 1.15, e)
			var c: Color = b["col"]
			(bn as Sprite3D).modulate = Color(c.r, c.g, c.b, c.a * fd)
		keep.append(st)
	_stabs = keep
'''


def main():
    rel = "scripts/scenes/battle/spear_eq_vfx.gd"
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    assert s.count(OLD_TAIL) == 1
    s = s.replace(OLD_TAIL, NEW_TAIL)
    a = "const CENT_SHOCK_DIST := 2.0\n"
    assert s.count(a) == 1
    s = s.replace(a, a + 'const CONE_MIX: Shader = preload("res://assets/shaders/cent_cone_mix.gdshader")\n'
                         'const CONE_ADD: Shader = preload("res://assets/shaders/cent_cone_add.gdshader")\n'
                         'const CONE_SP := ["prog", "fade"]\n'
                         'var _stabs: Array = []   # 普攻冲击罩 {parts, bills, ring, t, life, p0, d3, dist}\n')
    a = "\t_tick_shocks(delta)\n"
    assert s.count(a) == 1
    s = s.replace(a, a + "\t_tick_stabs(delta)\n")
    a = "\tfor sk in _shocks:\n\t\t_free(sk[\"node\"])\n\t_shocks.clear()\n"
    assert s.count(a) == 1
    s = s.replace(a, a + "\tfor st in _stabs:\n\t\tfor p in st[\"parts\"]:\n\t\t\t_free(p[\"node\"])\n\t\tfor b in st[\"bills\"]:\n\t\t\t_free(b[\"node\"])\n\t\t_free(st.get(\"ring\"))\n\t_stabs.clear()\n")
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok")


main()
