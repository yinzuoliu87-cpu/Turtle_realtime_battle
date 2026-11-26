"""cent_fix15_wave_head_1127.py —— 普攻冲击罩头部加强 + 二档穿刺改成「波头碰到才结算」(用户 11-27「冲击到的头部…需要更多明显的特效…作为美术设计师…你怎么实现」)
  结算: 二档穿刺不再刺中那一刻全线扣血; 改成一道冲击波从矛尖往目标、再沿穿刺线推 LINE_LEN, 速度 WAVE_SPD(= 演出 16 米/秒),
        每步线段碰撞, 碰到目标身后(沿刺击方向在目标之后)线宽内的敌人才扣 PIERCE_BEHIND + 3 档削甲(项目规矩「飞行物按速度碰到身体才结算」)
        主目标仍是矛尖刺中那一刻扣。
  演出: 冲击罩头部跟着这道波走; 头部加: 激波前沿亮环 + 外贴暗环(亮暗交界当折射边, 不读屏幕纹理: 兼容渲染器移动端读屏会整屏黑, 见 timestop_system 07-11)
        + 更大的核心光 + 横向拉丝光 + 两侧往后甩的火花 + 地面焦痕和小尘团 + 扫到每个敌人炸爆点(闪光 / 冲击环 / 火花 / 轻震)
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


SIM_OLD_START = "\tif tier >= 2:   # 贯穿直线: 目标身后同一条线上的敌人\n"
SIM_NEW_HEAD = '''	if tier >= 2:   # 贯穿直线(11-27 起波头碰到才结算): 从矛尖起一道冲击波沿刺击方向推到目标身后 LINE_LEN, 见 _tick_waves
		var wdir: Vector2 = DetMath.norm(Vector2(t["pos"]) - Vector2(u["pos"])) if DetMath.dist(Vector2(t["pos"]), Vector2(u["pos"])) > 1.0 else Vector2.RIGHT
		var w0: Vector2 = Vector2(u["pos"]) + wdir * WAVE_TIP
		var wv := {"src": u, "pos": w0, "dir": wdir, "t0": Vector2(t["pos"]), "left": maxf(0.0, DetMath.dist(w0, Vector2(t["pos"]))) + LINE_LEN,
			"hit": [t], "tier": tier, "pierced": false}
		_waves.append(wv)
		_fx("cent_wave", [u, wv])
'''


def main():
    rel = "scripts/systems/equip/spear_synergy_system.gd"
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    ## 原「刺中那一刻全线扣」整段换掉: 从 if tier >= 2 到 hits.append_array(behind) / pierce 计数那几行
    i = s.index(SIM_OLD_START)
    j = s.index("\tfor i in range(hits.size()):\n", i)
    old_block = s[i:j]
    assert "hits.append_array(behind)" in old_block, old_block
    s = s[:i] + SIM_NEW_HEAD + s[j:]
    ## 波的推进
    a = "func clear_all() -> void:\n"
    assert s.count(a) == 1
    s = s.replace(a, '''## 二档穿刺冲击波: 每步线段碰撞(项目规矩「会走的波每步碰撞判定」); 只打沿刺击方向在原目标之后的敌人(与旧规则同一条线)
func _tick_waves(delta: float) -> void:
	var keep: Array = []
	for w in _waves:
		var u: Dictionary = w["src"]
		var a: Vector2 = w["pos"]
		var dir: Vector2 = w["dir"]
		var step: float = minf(WAVE_SPD * delta, float(w["left"]))
		var b: Vector2 = a + dir * step
		w["pos"] = b
		w["left"] = float(w["left"]) - step
		if u.get("alive", false):
			for o in battle._targeting._enemies_of(u):
				if not o.get("alive", false):
					continue
				var already := false
				for h in w["hit"]:
					if is_same(h, o):
						already = true
				if already or (Vector2(o["pos"]) - Vector2(w["t0"])).dot(dir) <= 0.0:
					continue
				var q: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(o["pos"]), a, b)
				if DetMath.dist(q, Vector2(o["pos"])) > LINE_W + float(o.get("col_size", 22.0)) * 0.5:
					continue
				(w["hit"] as Array).append(o)
				if not bool(w["pierced"]):
					w["pierced"] = true
					stat["pierce"] += 1
				battle._damage._apply_basic_hit_from(u, o, battle._atk_dmg(u, PIERCE_BEHIND, o), COL_PHYS)
				if int(w["tier"]) >= 3 and o.get("alive", false):
					_shred(o)
				_fx("cent_wave_hit", [w, o])
		if float(w["left"]) > 0.5:
			keep.append(w)
		else:
			_fx("cent_wave_end", [w])
	_waves = keep


func clear_all() -> void:
	_waves.clear()
''')
    a = "\t_tick_cavs(delta)\n\tif vfx != null"
    assert s.count(a) == 1
    s = s.replace(a, "\t_tick_cavs(delta)\n\t_tick_waves(delta)\n\tif vfx != null")
    a = "\t\t_spears.clear()\n\t\t_cavs.clear()\n"
    assert s.count(a) == 1
    s = s.replace(a, "\t\t_spears.clear()\n\t\t_cavs.clear()\n\t\t_waves.clear()\n")
    a = "const PIERCE_BEHIND := 0.5\n"
    assert s.count(a) == 1
    s = s.replace(a, a + "const WAVE_SPD := 667.0              # 11-27 二档穿刺冲击波速度(码/秒) = 演出 16 米/秒\nconst WAVE_TIP := 60.0              # 波从矛尖起(立足点往前约 1.4 米)\n")
    a = "var _cavs: Array = []"
    assert s.count(a) == 1
    s = s.replace(a, "var _waves: Array = []      # 二档穿刺冲击波 {src, pos, dir, t0, left, hit, tier, pierced}\n" + a)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))

    ## ── 演出 ──
    patch("scripts/scenes/battle/spear_eq_vfx.gd", [
        ('''	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": maxf(CENT_SHOCK_SEC, dist / CENT_SHOCK_SPD), "p0": tip, "d3": d3, "dist": dist})
''', '''	## 头部加强(11-27 第二轮「冲击到的头部…需要更多明显的特效」): 激波前沿亮环 + 外贴暗环(折射边) + 横向拉丝光 + 两侧往后甩的火花
	var yaw2: float = Cent3dVfx.yaw_of(Vector2(d3.x, d3.z))
	var te := Cent3dVfx.tex("energy.png")
	var fr_dark := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.42, 1.0, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": te, "open": 1.0, "shell_k": 0.55, "col_mid": Vector3(0.18, 0.08, 0.03), "col_hot": Vector3(0.25, 0.12, 0.05)}, 11)
	var fr_hot := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.2, 0.62, TAU, 0.0, 40, 4), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
		{"tex_energy": te, "open": 1.0, "shell_k": 0.62, "col_mid": Vector3(1.0, 0.8, 0.4), "col_hot": Vector3(1.0, 1.0, 0.95)}, 13)
	for fnode in [fr_dark, fr_hot]:
		(fnode as Node3D).rotation = Vector3(0.0, yaw2, PI * 0.5)
		(fnode as Node3D).position = tip
	var streak := Sprite3D.new()   # 横向拉丝光
	streak.texture = Cent3dVfx.tex("xstar.png")
	streak.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	streak.shaded = false
	streak.transparent = true
	streak.no_depth_test = true
	streak.render_priority = 14
	streak.modulate = Color(1.0, 0.92, 0.7, 0.9)
	streak.pixel_size = 2.6 / float(streak.texture.get_width())
	streak.position = tip
	w.add_child(streak)
	bills.append({"node": streak, "col": streak.modulate, "sx": 3.2})
	var spray := GPUParticles3D.new()
	spray.amount = 36
	spray.lifetime = 0.28
	spray.randomness = 0.7
	spray.local_coords = false
	spray.fixed_fps = 30
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3(-1.0, 0.0, 0.0)
	spm.spread = 38.0
	spm.initial_velocity_min = 2.0
	spm.initial_velocity_max = 5.0
	spm.gravity = Vector3(0.0, -3.0, 0.0)
	spm.scale_min = 0.6
	spm.scale_max = 1.3
	spm.color_ramp = _gold_ramp(1.0)
	spray.process_material = spm
	spray.draw_pass_1 = _mote_quad(0.09)
	spray.position = tip
	spray.rotation = Vector3(0.0, yaw2, 0.0)
	w.add_child(spray)
	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": maxf(CENT_SHOCK_SEC, dist / CENT_SHOCK_SPD), "p0": tip, "d3": d3, "dist": dist,
		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y})


## 二档: 冲击罩头部改跟着结算那道冲击波走(sim 的波头位置), 到头再淡掉
func cent_wave(u: Dictionary, wv: Dictionary) -> void:
	for i in range(_stabs.size() - 1, -1, -1):
		var st: Dictionary = _stabs[i]
		if st.has("u") and is_same(st["u"], u) and not st.has("w"):
			st["w"] = wv
			st["life"] = 99.0
			return


func cent_wave_hit(_wv: Dictionary, o: Dictionary) -> void:
	## 波头扫到一个敌人: 那个人身上炸一下(闪光 + 冲击环 + 火花 + 轻震)
	var op := Vector2(o["pos"])
	_cent_burst(battle._world_pos(op, 1.0), 0.0, 1.3)
	_strip(SV + "spear-hit-spark.png", 6, battle._world_pos(op, 0.6), 1.8, 20.0, false, 6.0 / 20.0, false, null, 0.0)
	var fl := Sprite3D.new()
	fl.texture = Cent3dVfx.tex("glow.png")
	fl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fl.shaded = false
	fl.transparent = true
	fl.no_depth_test = true
	fl.render_priority = 13
	fl.modulate = Color(1.0, 0.95, 0.8, 0.95)
	fl.pixel_size = 2.0 / float(fl.texture.get_width())
	fl.position = battle._world_pos(op, 1.0)
	battle._world.add_child(fl)
	_mfx.append({"node": fl, "nf": 1, "fps": 0.0, "t": 0.0, "life": 0.18, "loop": false, "follow": null, "h": 0.0})
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.15)


func cent_wave_end(wv: Dictionary) -> void:
	for st in _stabs:
		if st.get("w") is Dictionary and is_same(st["w"], wv) and not st.has("end_t"):
			st["end_t"] = float(st["t"])


func _stab_free(st: Dictionary) -> void:
	for p in st["parts"]:
		_free(p["node"])
	for b in st["bills"]:
		_free(b["node"])
	_free(st.get("ring"))
	for f in st.get("front", []):
		_free(f)
	_stop_ps(st.get("spray"))
'''),
        ('''		if k >= 1.0:
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
''', '''		var follow = st.get("w")
		if st.has("end_t"):
			k = maxf(k, 0.55 + 0.45 * (t - float(st["end_t"])) / 0.15)   # 波到头: 0.15 秒淡掉
		if k >= 1.0:
			_stab_free(st)
			continue
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)   # 先快后慢
		var d3: Vector3 = st["d3"]
		var pos: Vector3 = Vector3(st["p0"]) + d3 * float(st["dist"]) * e
		if follow is Dictionary:   # 二档: 头部 = 结算那道冲击波的波头(碰到谁才扣谁)
			pos = battle._world_pos(Vector2(follow["pos"]), float(st.get("h", 1.0)))
			e = clampf(t / 0.25, 0.0, 1.0)
		var fd: float = 1.0 - smoothstep(0.45, 1.0, k)
		## 头部: 前沿亮环 / 暗环跟着波头(亮环一直跳), 两侧火花, 地面焦痕 + 小尘团
		var fi := 0
		for f in st.get("front", []):
			if f != null and is_instance_valid(f):
				(f as Node3D).position = pos + d3 * (0.05 if fi == 1 else -0.02)
				(f as Node3D).scale = Vector3.ONE * lerpf(0.6, 1.15, e) * (1.0 + (0.12 * sin(t * 50.0) if fi == 1 else 0.0))
				var fm: ShaderMaterial = (f as MeshInstance3D).material_override
				fm.set_shader_parameter("t", t)
				fm.set_shader_parameter("fade", fd)
			fi += 1
		var sp0 = st.get("spray")
		if sp0 != null and is_instance_valid(sp0):
			(sp0 as GPUParticles3D).position = pos
			(sp0 as GPUParticles3D).emitting = fd > 0.3
		st["skid"] = float(st.get("skid", 0.0)) + delta
		if float(st["skid"]) >= 0.04 and fd > 0.3:
			st["skid"] = 0.0
			var g2 := Vector2(pos.x / float(battle.WS) + float(battle._arena_center.x), pos.z / float(battle.WS) + float(battle._arena_center.y))
			_ground_glow(g2, 0.9, Color(0.15, 0.07, 0.03, 0.45), 0.6)
			_ground_glow(g2, 0.4, Color(1.0, 0.75, 0.35, 0.7), 0.25)
'''),
        ('''			(bn as Sprite3D).position = pos + d3 * 0.05
			(bn as Sprite3D).scale = Vector3.ONE * fl * lerpf(0.8, 1.15, e)
''', '''			(bn as Sprite3D).position = pos + d3 * 0.05
			var bsx: float = float(b.get("sx", 1.0))
			(bn as Sprite3D).scale = Vector3(bsx, 1.0 / bsx if bsx > 1.0 else 1.0, 1.0) * fl * lerpf(0.8, 1.15, e)
'''),
        ('''	for st in _stabs:
		for p in st["parts"]:
			_free(p["node"])
		for b in st["bills"]:
			_free(b["node"])
		_free(st.get("ring"))
	_stabs.clear()
''', '''	for st in _stabs:
		for p in st["parts"]:
			_free(p["node"])
		for b in st["bills"]:
			_free(b["node"])
		_free(st.get("ring"))
		for f in st.get("front", []):
			_free(f)
		_free(st.get("spray"))
	_stabs.clear()
'''),
        ## 核心光再大一号
        ('''	for b in [["glow.png", 1.1, Color(1.0, 0.95, 0.8, 0.9), 13], ["xstar.png", 1.7, Color(1.0, 0.88, 0.6, 1.0), 14]]:
''', '''	for b in [["glow.png", 1.6, Color(1.0, 0.95, 0.8, 0.95), 13], ["xstar.png", 2.3, Color(1.0, 0.88, 0.6, 1.0), 14]]:
'''),
    ])
    print("ok")


main()
