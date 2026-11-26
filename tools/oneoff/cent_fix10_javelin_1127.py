"""cent_fix10_javelin_1127.py —— 百夫长掷矛飞矛按特效师流程分层(研究稿 20261127-普攻冲击罩参考 · Q 普通飞矛那一行)
  矛头罩 3 层(暗 / 金 / 叠加发光) + 矛头光晕 + 暗头光 + 横向前导星芒 + 身后流光拖尾 + 暗拖尾 + 一路火花;
  出手: 径向冲击环; 命中: 径向冲击环 + 火花迸射。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

HELPERS = '''## 掷矛飞矛分层(11-27, 研究稿 Q 普通飞矛): 跟着飞矛走的一组层, 矛头在飞矛节点往前 JAV_HEAD 米处
const JAV_HEAD := 1.15


func _jav_fx(head: Vector3, yaw: float) -> Dictionary:
	var w: Node3D = battle._world
	## [着色器, 长, 口径, 往后错开(米), 参数, 绘制顺序]
	var spec: Array = [
		[CONE_MIX, 1.1, 0.34, 0.0, {"col": Vector4(0.2, 0.06, 0.02, 0.5), "rim_mix": 0.4, "tail": 0.5, "apex": 0.2}, 10],     # 暗罩
		[CONE_MIX, 0.9, 0.28, 0.0, {"col": Vector4(1.0, 0.74, 0.25, 0.65), "rim_mix": 0.65, "tail": 0.5, "apex": 1.0}, 11],    # 金罩
		[CONE_ADD, 1.1, 0.32, 0.0, {"col": Vector4(0.8, 0.3, 0.12, 0.55), "rim_mix": 0.5, "tail": 0.45, "apex": 0.6}, 12],    # 叠加发光罩
		[CONE_MIX, 3.2, 0.3, 0.3, {"col": Vector4(1.0, 0.95, 0.8, 0.75), "rim_mix": 0.0, "tail": 0.7, "apex": 0.0, "streaks": 16.0}, 12],   # 流光拖尾
		[CONE_MIX, 3.6, 0.36, 0.3, {"col": Vector4(0.18, 0.1, 0.05, 0.35), "rim_mix": 0.3, "tail": 0.75, "apex": 0.0}, 9],    # 暗拖尾
	]
	var parts: Array = []
	for sp in spec:
		var prm: Dictionary = (sp[4] as Dictionary).duplicate()
		prm["prog"] = 0.0
		prm["fade"] = 1.0
		var mi := Cent3dVfx.node(w, Cent3dVfx.gen_shock(float(sp[1]), float(sp[2]), 8, 20), sp[0], CONE_SP, prm, int(sp[5]))
		mi.rotation = Vector3(0.0, yaw, 0.0)
		mi.position = head
		parts.append({"node": mi, "off": float(sp[3])})
	var bills: Array = []
	## [贴图, 宽(米), 颜色, 绘制顺序, 横向拉伸]
	for b in [["glow.png", 1.2, Color(0.12, 0.05, 0.02, 0.5), 9, 1.0], ["glow.png", 0.9, Color(1.0, 0.95, 0.8, 0.85), 13, 1.0],
			["xstar.png", 1.4, Color(1.0, 0.9, 0.65, 0.9), 14, 2.2]]:
		var s := Sprite3D.new()
		s.texture = Cent3dVfx.tex(str(b[0]))
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.transparent = true
		s.no_depth_test = true
		s.render_priority = int(b[3])
		s.modulate = b[2]
		s.pixel_size = float(b[1]) / float(s.texture.get_width())
		s.scale = Vector3(float(b[4]), 1.0 / sqrt(float(b[4])), 1.0)
		s.position = head
		w.add_child(s)
		bills.append({"node": s, "sx": float(b[4])})
	var ps := GPUParticles3D.new()   # 一路火花(往后落下)
	ps.amount = 40
	ps.lifetime = 0.35
	ps.randomness = 0.6
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(-1.0, 0.15, 0.0)
	pm.spread = 18.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0.0, -2.5, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.08)
	ps.position = head
	ps.rotation = Vector3(0.0, yaw, 0.0)
	w.add_child(ps)
	return {"parts": parts, "bills": bills, "ps": ps, "t": 0.0}


func _jav_tick(fx: Dictionary, head: Vector3, d3: Vector3, delta: float) -> void:
	fx["t"] = float(fx.get("t", 0.0)) + delta
	var t: float = float(fx["t"])
	for p in fx["parts"]:
		var n = p["node"]
		if n != null and is_instance_valid(n):
			(n as MeshInstance3D).position = head - d3 * float(p["off"])
			((n as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("prog", t * 9.0)
	var fl: float = 0.8 + 0.4 * fmod(t * 31.0, 1.0)
	for b in fx["bills"]:
		var bn = b["node"]
		if bn != null and is_instance_valid(bn):
			(bn as Sprite3D).position = head
			var sx: float = float(b["sx"])
			(bn as Sprite3D).scale = Vector3(sx, 1.0 / sqrt(sx), 1.0) * (fl if sx > 1.0 else 1.0)
	var ps = fx.get("ps")
	if ps != null and is_instance_valid(ps):
		(ps as GPUParticles3D).position = head
		(ps as GPUParticles3D).emitting = true


func _jav_free(fx) -> void:
	if not (fx is Dictionary):
		return
	for p in fx.get("parts", []):
		_free(p["node"])
	for b in fx.get("bills", []):
		_free(b["node"])
	var ps = fx.get("ps")
	if ps != null and is_instance_valid(ps):
		(ps as GPUParticles3D).emitting = false
		_aegis_junk.append({"node": ps, "left": 0.4})


## 径向冲击环 + 火花迸射(出手 / 命中共用; 底层元素)
func _cent_burst(pos: Vector3, yaw: float, ring_m: float) -> void:
	if not _ok():
		return
	var w: Node3D = battle._world
	var ring := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.05, ring_m, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": Cent3dVfx.tex("energy.png"), "open": 1.0, "shell_k": 0.05}, 12)
	ring.position = pos
	ring.rotation = Vector3(0.0, yaw, PI * 0.5)
	var ps := GPUParticles3D.new()
	ps.amount = 18
	ps.lifetime = 0.35
	ps.one_shot = true
	ps.explosiveness = 1.0
	ps.randomness = 0.7
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1.0, 0.2, 0.0)
	pm.spread = 50.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0.0, -6.0, 0.0)
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.1)
	ps.position = pos
	ps.rotation = Vector3(0.0, yaw, 0.0)
	ps.emitting = true
	w.add_child(ps)
	_aegis_junk.append({"node": ps, "left": 0.6})
	_stabs.append({"parts": [], "bills": [], "ring": ring, "t": 0.0, "life": 0.25, "p0": pos, "d3": Vector3.ZERO, "dist": 0.0})


func cent_throw(u: Dictionary, s: Dictionary) -> void:
'''


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

    rep("func cent_throw(u: Dictionary, s: Dictionary) -> void:\n", HELPERS)
    rep('''	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 2.4)
	if n != null:
		_spear_nodes.append({"s": s, "node": n})
''', '''	var n := _proj("spear-pilum.png", Vector2(s["pos"]), Vector2(s["dir"]), 2.4)
	if n != null:
		var d2: Vector2 = Vector2(s["dir"]).normalized()
		var d3 := Vector3(d2.x, 0.0, d2.y)
		var yaw: float = Cent3dVfx.yaw_of(d2)
		var head: Vector3 = battle._world_pos(Vector2(s["pos"]), 1.0) + d3 * JAV_HEAD
		_cent_burst(battle._world_pos(Vector2(s["pos"]), 1.0), yaw, 1.1)   # 出手: 径向冲击环 + 火花
		_spear_nodes.append({"s": s, "node": n, "fx": _jav_fx(head, yaw), "d3": d3})
''')
    rep('''func cent_spear_hit(o: Dictionary) -> void:
''', '''func cent_spear_hit(o: Dictionary) -> void:
	_cent_burst(battle._world_pos(Vector2(o["pos"]), 1.0), 0.0, 1.0)   # 命中: 径向冲击环 + 火花迸射
''')
    rep('''	for r in _spear_nodes:
		if is_same(r["s"], s):
			_free(r["node"])
''', '''	for r in _spear_nodes:
		if is_same(r["s"], s):
			_free(r["node"])
			_jav_free(r.get("fx"))
''')
    rep('''	for r in _spear_nodes:
		var n = r["node"]
		if n != null and is_instance_valid(n):
			(n as Sprite3D).position = battle._world_pos(Vector2(r["s"]["pos"]), 1.0)
''', '''	for r in _spear_nodes:
		var n = r["node"]
		if n != null and is_instance_valid(n):
			(n as Sprite3D).position = battle._world_pos(Vector2(r["s"]["pos"]), 1.0)
			if r.get("fx") is Dictionary:   # 百夫长飞矛: 分层特效跟着矛头
				_jav_tick(r["fx"], (n as Sprite3D).position + Vector3(r["d3"]) * JAV_HEAD, Vector3(r["d3"]), delta)
''')
    rep('''	for arr in [_spear_nodes, _cav_nodes, _ropes, _shields, _swv, _fall]:
''', '''	for r5 in _spear_nodes:   # 清场直接删(不进 _aegis_junk: 它在上面已经清过)
		var f5 = r5.get("fx")
		if f5 is Dictionary:
			for p5 in f5.get("parts", []):
				_free(p5["node"])
			for b5 in f5.get("bills", []):
				_free(b5["node"])
			_free(f5.get("ps"))
	for arr in [_spear_nodes, _cav_nodes, _ropes, _shields, _swv, _fall]:
''')
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok")


main()
