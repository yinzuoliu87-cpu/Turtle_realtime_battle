"""cent_fix17_haze_arrow_1127.py —— 普攻: 热扭曲(读屏幕纹理, 录给用户看) + 突刺气劲从人身前一直拉到冲击罩头部(用户 11-27
  「从角色就稍微…那个方向多一点点…到这个目标就是要长一点…一档和二档之间…长度不一样」)
  箭: 箭尾固定在命中帧矛尖往回 1 米(人身前), 箭头 = 冲击罩头部; 长度随罩子拉长、粗细不变 ⇒ 一档到目标、二档到穿刺线尽头
  热扭曲: 对镜头面片 + cent_haze.gdshader, 跟着罩子头部, 绘制顺序 -2(立绘下面, 只扭地面)
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
def patch(rel, pairs):
    p = os.path.join(ROOT, rel); raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70], s.count(a)); s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
patch("scripts/scenes/battle/cent_3d_vfx.gd", [
 ('const RAY_SP := ["prog"]\n', 'const RAY_SP := ["prog"]\nconst HAZE_SHADER: Shader = preload("res://assets/shaders/cent_haze.gdshader")\nconst HAZE_SP := ["t", "fade", "sz"]\n'),
 ("static func tex(name: String) -> Texture2D:\n",
  "## 面片(XY 平面, 中心在原点): 热扭曲用, 着色器里做公告板\nstatic func gen_quad(w: float, h: float) -> ArrayMesh:\n"
  "\tvar st := SurfaceTool.new()\n\tst.begin(Mesh.PRIMITIVE_TRIANGLES)\n"
  "\tfor q in [[-0.5, -0.5, 0.0, 1.0], [0.5, -0.5, 1.0, 1.0], [0.5, 0.5, 1.0, 0.0], [-0.5, 0.5, 0.0, 0.0]]:\n"
  "\t\tst.set_uv(Vector2(float(q[2]), float(q[3])))\n\t\tst.add_vertex(Vector3(float(q[0]) * w, float(q[1]) * h, 0.0))\n"
  "\tfor k in [0, 1, 2, 0, 2, 3]:\n\t\tst.add_index(k)\n"
  "\treturn VfxTex.tag(st.commit(), \"gen_quad\", [w, h], SRC)\n\n\nstatic func tex(name: String) -> Texture2D:\n"),
])
patch("scripts/scenes/battle/spear_eq_vfx.gd", [
 ('''	var arrow := _dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(u["pos"]), Vector2(d3.x, d3.z), CENT_ARROW_M, 24.0, 0.0, tip.y)
	if arrow != null:
		(_mfx.back() as Dictionary)["loop"] = true   # 帧条循环, 跟罩子同生同灭(_stab_free 删)
		arrow.position = tip - d3 * (CENT_ARROW_M * 0.5 - 0.1)
		arrow.render_priority = 13   # 画在罩子各层(10–12)上面: 箭头在罩子里看得清
''', '''	## 突刺气劲: 箭尾固定在人身前(命中帧矛尖往回 CENT_ARROW_BACK 米), 箭头贴着罩子头部, 长度跟着拉长(粗细不变)
	var tail: Vector3 = tip - d3 * CENT_ARROW_BACK
	var arrow := _dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(u["pos"]), Vector2(d3.x, d3.z), CENT_ARROW_M, 24.0, 0.0, tip.y)
	if arrow != null:
		(_mfx.back() as Dictionary)["loop"] = true   # 帧条循环, 跟罩子同生同灭(_stab_free 删)
		arrow.render_priority = 13   # 画在罩子各层(10–12)上面: 箭头在罩子里看得清
		_arrow_span(arrow, tail, tip)
	## 热扭曲(读屏幕纹理): 跟着罩子头部, 画在立绘下面只扭地面
	var haze := Cent3dVfx.node(w, Cent3dVfx.gen_quad(1.0, 1.0), Cent3dVfx.HAZE_SHADER, Cent3dVfx.HAZE_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "t": 0.0, "fade": 1.0, "sz": 1.6}, -2)
	haze.position = tip
'''),
 ('''		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y, "arrow": arrow})
''', '''		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y, "arrow": arrow, "tail": tail, "haze": haze})


## 突刺气劲从 a 拉到 b: 帧里箭的有效长约 108 / 128 帧宽 ⇒ 横向缩放 = 距离 / (CENT_ARROW_M × 0.84)
func _arrow_span(s: Sprite3D, a: Vector3, b: Vector3) -> void:
	var ln: float = maxf(0.3, a.distance_to(b))
	s.position = (a + b) * 0.5
	s.scale = Vector3(ln / (CENT_ARROW_M * 0.84), 1.0, 1.0)
'''),
 ('''		if ar0 != null and is_instance_valid(ar0):
			(ar0 as Sprite3D).position = pos - d3 * (CENT_ARROW_M * 0.5 - 0.1)
			(ar0 as Sprite3D).modulate = Color(1.0, 1.0, 1.0, fd)
''', '''		if ar0 != null and is_instance_valid(ar0):
			_arrow_span(ar0 as Sprite3D, Vector3(st["tail"]), pos + d3 * 0.1)
			(ar0 as Sprite3D).modulate = Color(1.0, 1.0, 1.0, fd)
		var hz = st.get("haze")
		if hz != null and is_instance_valid(hz):
			(hz as MeshInstance3D).position = pos
			var hm: ShaderMaterial = (hz as MeshInstance3D).material_override
			hm.set_shader_parameter("t", t)
			hm.set_shader_parameter("fade", fd)
			hm.set_shader_parameter("sz", lerpf(1.2, 2.0, e))
'''),
 ('''	_stop_ps(st.get("spray"))
	_free(st.get("arrow"))
''', '''	_stop_ps(st.get("spray"))
	_free(st.get("arrow"))
	_free(st.get("haze"))
'''),
 ('''		_free(st.get("arrow"))
	_stabs.clear()
''', '''		_free(st.get("arrow"))
		_free(st.get("haze"))
	_stabs.clear()
'''),
 ("const CENT_ARROW_M := 2.6     # 突刺气劲长(米), 跟着罩子走\n",
  "const CENT_ARROW_M := 2.6     # 突刺气劲基准长(米): 定粗细; 实际长度 = 人身前 → 罩子头部\nconst CENT_ARROW_BACK := 1.0  # 箭尾在命中帧矛尖往回多少米(人身前一点)\n"),
])
print("ok")
