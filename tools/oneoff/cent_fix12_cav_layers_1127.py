"""cent_fix12_cav_layers_1127.py —— 骑兵冲锋按特效师流程分层(研究稿 20261127-普攻冲击罩参考 · R 下坠 / 滑行彗星那一行)
  能量罩(原有) + 暗色外壳垫底 + 包身亮光晕(下垫暗光) + 马头往后的尾流(流光) + 一路星尘 + 地上沟痕(暗沟 + 发光线, 慢慢淡掉)
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


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

    rep('''		_cav_nodes.append({"c": c, "node": n, "parts": parts, "dust_t": 0.0, "bow": bow, "bt": 0.0})
''', '''		## 研究稿 R 彗星 / 滑行彗星: 暗色外壳垫底 + 包身亮光晕(下垫暗光) + 马头往后的尾流 + 一路星尘
		var dk := Cent3dVfx.node(battle._world, Cent3dVfx.gen_sheath(4.2, 1.35, 16, 28), Cent3dVfx.SHEATH_SHADER, Cent3dVfx.SHEATH_SP,
			{"t": 0.0, "fade": 1.0, "col_edge": Vector3(0.16, 0.07, 0.03), "col_hot": Vector3(0.3, 0.14, 0.05)}, 9)
		dk.scale = Vector3(1.06, 0.95, 0.85)
		dk.rotation = bow.rotation
		var fxc := {"dark": dk, "bills": [], "wake": [], "ps": null}
		for b in [["glow.png", 4.2, Color(0.14, 0.06, 0.02, 0.4), 8], ["glow.png", 3.2, Color(1.0, 0.8, 0.4, 0.35), 13]]:
			var gs := Sprite3D.new()
			gs.texture = Cent3dVfx.tex(str(b[0]))
			gs.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			gs.shaded = false
			gs.transparent = true
			gs.no_depth_test = true
			gs.render_priority = int(b[3])
			gs.modulate = b[2]
			gs.pixel_size = float(b[1]) / float(gs.texture.get_width())
			battle._world.add_child(gs)
			fxc["bills"].append({"node": gs, "col": b[2]})
		fxc["wake"] = _cone_set([
			[CONE_MIX, 5.5, 1.3, 0.0, {"col": Vector4(0.18, 0.08, 0.03, 0.35), "rim_mix": 0.4, "tail": 0.7, "apex": 0.0}, 9],
			[CONE_MIX, 5.0, 1.15, 0.0, {"col": Vector4(1.0, 0.92, 0.72, 0.75), "rim_mix": 0.0, "tail": 0.65, "apex": 0.0, "streaks": 22.0}, 12],
		], battle._world_pos(Vector2(c["pos"]), 1.0), Vector3(0.0, Cent3dVfx.yaw_of(dir), 0.0))
		fxc["ps"] = _stream_ps(battle._world_pos(Vector2(c["pos"]), 1.2), Vector3(-dir.x, 0.4, -dir.y), 80, 0.6, 1.0, 3.0, 25.0, 0.11)
		_cav_nodes.append({"c": c, "node": n, "parts": parts, "dust_t": 0.0, "bow": bow, "bt": 0.0, "fxc": fxc, "trench_t": 0.0})
''')
    rep('''				bm.set_shader_parameter("fade", clampf(float(r3["c"]["left"]) / (SpearSynergySystem.CAV_SPD * 0.25), 0.0, 1.0) * minf(1.0, float(r3["bt"]) / 0.15))
''', '''				var cf: float = clampf(float(r3["c"]["left"]) / (SpearSynergySystem.CAV_SPD * 0.25), 0.0, 1.0) * minf(1.0, float(r3["bt"]) / 0.15)
				bm.set_shader_parameter("fade", cf)
				var fxc = r3.get("fxc")
				if fxc is Dictionary:
					var cd2: Vector2 = Vector2(r3["c"]["dir"])
					var shell_p: Vector3 = battle._world_pos(cp + cd2 * 10.0, 1.15)
					var dk = fxc.get("dark")
					if dk != null and is_instance_valid(dk):
						(dk as MeshInstance3D).position = shell_p
						var dm: ShaderMaterial = (dk as MeshInstance3D).material_override
						dm.set_shader_parameter("t", float(r3["bt"]))
						dm.set_shader_parameter("fade", cf)
					for gb in fxc["bills"]:
						if gb["node"] != null and is_instance_valid(gb["node"]):
							(gb["node"] as Sprite3D).position = shell_p
							var gc: Color = gb["col"]
							(gb["node"] as Sprite3D).modulate = Color(gc.r, gc.g, gc.b, gc.a * cf)
					var d3c := Vector3(cd2.x, 0.0, cd2.y)
					_cone_set_tick(fxc["wake"], battle._world_pos(cp + cd2 * 70.0, 1.0), d3c, float(r3["bt"]), cf, true)
					var wp = fxc.get("ps")
					if wp != null and is_instance_valid(wp):
						(wp as GPUParticles3D).position = battle._world_pos(cp, 1.2)
					## 地上沟痕: 暗沟 + 发光线(研究稿 MakerTrench 暗沟 + 发光裂纹), 每 0.05 秒落一点, 暗沟留 1 秒、亮线留 0.35 秒
					r3["trench_t"] = float(r3.get("trench_t", 0.0)) + delta
					if float(r3["trench_t"]) >= 0.05 and cf > 0.3:
						r3["trench_t"] = 0.0
						_ground_glow(cp - cd2 * 30.0, 1.3, Color(0.16, 0.08, 0.03, 0.45), 1.0)
						_ground_glow(cp - cd2 * 30.0, 0.55, Color(1.0, 0.72, 0.3, 0.8), 0.35)
''')
    rep('''		if is_same(r["c"], c):
			_free(r["node"])
			_free(r.get("bow"))
''', '''		if is_same(r["c"], c):
			_free(r["node"])
			_free(r.get("bow"))
			_cav_fx_free(r.get("fxc"), false)
''')
    rep('''func cent_cav_end(c: Dictionary) -> void:
''', '''func _cav_fx_free(fxc, hard: bool) -> void:
	if not (fxc is Dictionary):
		return
	_free(fxc.get("dark"))
	for gb in fxc.get("bills", []):
		_free(gb["node"])
	_cone_set_free(fxc.get("wake"))
	if hard:
		_free(fxc.get("ps"))
	else:
		_stop_ps(fxc.get("ps"))


func cent_cav_end(c: Dictionary) -> void:
''')
    rep('''	for r4 in _cav_nodes:
		_free(r4.get("bow"))
''', '''	for r4 in _cav_nodes:
		_free(r4.get("bow"))
		_cav_fx_free(r4.get("fxc"), true)
''')
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok")


main()
