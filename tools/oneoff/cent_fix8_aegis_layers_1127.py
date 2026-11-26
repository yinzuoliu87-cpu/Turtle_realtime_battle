"""cent_fix8_aegis_layers_1127.py —— 龟甲阵按特效师流程分层重做(方案书 20261126 附录 D, 用户 11-27
  「真正厉害的三 D 美术师肯定不会说只做一层这个盾吧」「一层一层去实现…我们是有这个实力的」)
  层: 外层盾面 / 内层盾面(视差) / 两端翼焰 / 地面扇形 / 扎稳冲击环 / 上飘光点(GPU 粒子) / 受击涟漪 / 穿盾矛光 / 放盾侵蚀 + 碎光片
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

NEW = '''## 龟甲阵(11-27 附录 D, 按特效师流程分层; 用户「真正厉害的三 D 美术师肯定不会说只做一层这个盾吧」): 全部是世界空间 3D 层, 绕 Y 转到举盾方向
##   外层盾面 / 内层盾面(小一圈、纹理反向滚 ⇒ 厚度视差) / 两端翼焰 / 盾前地面扇形 —— 同一个节奏推(张开 → 撑 → 放盾侵蚀)
##   扎稳冲击环(贴地一圈 0.3 秒扩开) / 盾底上飘光点(GPU 粒子) / 受击涟漪(本体掉血那一步, 盾面朝攻击者那点起一圈) /
##   每 0.5 秒穿盾矛光(= 帧条捅出帧) / 放盾: 侵蚀从上往下烧掉 + 碎光片往外迸
##   方向 = 本体朝向那一侧最近的敌人(接近正上 / 正下也算), 举盾那一刻定下
var _aegis: Array = []      # {u, node(外层), parts, ring, motes, t, dir, yaw, off, hp, rips, jab}
var _rays: Array = []       # 穿盾矛光 {node, mat, t}
var _aegis_junk: Array = [] # 放完要再留一会儿的(碎光片粒子) {node, left}
const AEGIS_R := 1.45       # 外层弧半径(米)
const AEGIS_ARC := 2.2      # 张角(弧度, 约 126°)
const AEGIS_H := 3.0        # 盾高(米), 比人高半个身位
const AEGIS_LEAN := 0.35    # 顶部往外翻(米)
const AEGIS_OPEN_SEC := 0.15
const AEGIS_BRK_SEC := 0.3
const AEGIS_JAB_IV := 0.5   # 盾后出刺节奏(= 结算 POKE_IV、帧条捅出帧)
const AEGIS_RAY_SEC := 0.25
const AEGIS_RING_SEC := 0.3


func _aegis_dir(u: Dictionary) -> Vector2:
	var spr = u.get("sprite", null)
	var fx: float = (1.0 if (spr as Sprite3D).flip_h else -1.0) if is_instance_valid(spr) else _face(u).x   # 本体帧条原画朝左, flip_h = 朝右
	var best: Vector2 = Vector2(fx, 0.0)
	var bd := INF
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		var d: Vector2 = Vector2(o["pos"]) - Vector2(u["pos"])
		if d.x * fx < -0.25 * d.length() or d.length() < 1.0:   # 朝向那一侧 + 接近竖直的(上下方)都算
			continue
		if d.length() < bd:
			bd = d.length()
			best = d.normalized()
	return best


func cent_shield(u: Dictionary, sec: float) -> void:
	## 帧条 = 举盾 6 帧 + 撑盾 36 帧(打包脚本里拼好); 整条恰好播满举盾时长 ⇒ 0.4 秒举起, 之后一直撑着, 到点放下回待机
	var sd := _cent_sd("shield", 14.0)
	var nf: int = int(sd.get("frames", 42)) if not sd.is_empty() else 42
	_cent_play(u, "shield", float(nf) / maxf(0.5, sec))   # 42 帧 / 3 秒 = 14 fps: 盾后出刺的捅出帧恰好落在 0.5 / 1.0 / … 秒(= 结算 POKE_IV)
	battle._vfx._flash(u, Color(1.0, 0.9, 0.55), 0.12)   # 扎稳那一下本体闪白金
	cent_shield_off(u)
	if _ok():
		var w: Node3D = battle._world
		var dir := _aegis_dir(u)
		var yaw: float = Cent3dVfx.yaw_of(dir)
		var pos: Vector3 = battle._world_pos(Vector2(u["pos"]), 0.0)
		var te := Cent3dVfx.tex("energy.png")
		var tr := Cent3dVfx.tex("erode.png")
		var inner := Cent3dVfx.node(w, Cent3dVfx.gen_aegis(AEGIS_R - 0.14, AEGIS_ARC * 0.96, AEGIS_H * 0.9, AEGIS_LEAN * 0.8, 24, 10),
			Cent3dVfx.AEGIS_SHADER, Cent3dVfx.AEGIS_SP, {"tex_energy": te, "tex_erode": tr, "layer": 1.0,
			"size_m": Vector2((AEGIS_R - 0.14) * AEGIS_ARC * 0.96, AEGIS_H * 0.9)})
		var outer := Cent3dVfx.node(w, Cent3dVfx.gen_aegis(AEGIS_R, AEGIS_ARC, AEGIS_H, AEGIS_LEAN, 28, 12),
			Cent3dVfx.AEGIS_SHADER, Cent3dVfx.AEGIS_SP, {"tex_energy": te, "tex_erode": tr, "tex_sigil": Cent3dVfx.tex("sigil.png"),
			"layer": 0.0, "size_m": Vector2(AEGIS_R * AEGIS_ARC, AEGIS_H)})
		var parts: Array = [inner, outer]
		for side in [-1.0, 1.0]:
			parts.append(Cent3dVfx.node(w, Cent3dVfx.gen_aegis_flare(AEGIS_R, AEGIS_ARC, AEGIS_H * 0.85, 0.9, side, 8, 10),
				Cent3dVfx.FLARE_SHADER, Cent3dVfx.FLARE_SP, {"tex_flame": Cent3dVfx.tex("flame.png"), "tex_energy": te}))
		parts.append(Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.35, AEGIS_R + 1.6, AEGIS_ARC * 1.04, 0.03, 28, 10),
			Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP, {"tex_energy": te, "shell_k": (AEGIS_R - 0.35) / (AEGIS_R + 1.25)}))
		var ring := Cent3dVfx.node(w, Cent3dVfx.gen_fan(0.2, 2.4, TAU, 0.04, 48, 6), Cent3dVfx.GROUND_SHADER, Cent3dVfx.GROUND_SP,
			{"tex_energy": te, "open": 1.0, "shell_k": 0.05})
		ring.position = pos
		for n in parts:
			(n as Node3D).position = pos
			(n as Node3D).rotation = Vector3(0.0, yaw, 0.0)
		var motes := _aegis_motes(pos, yaw)
		_aegis.append({"u": u, "node": outer, "parts": parts, "ring": ring, "motes": motes, "t": 0.0, "dir": dir, "yaw": yaw,
			"off": -1.0, "hp": float(u.get("hp", 0.0)), "rips": [], "jab": 0})
	_strip(LION_DUST, 7, battle._world_pos(Vector2(u["pos"]), 0.0), 1.6, 16.0, false, 7.0 / 16.0, false, null, 0.0)
	battle._shake(battle.JUICE_SHAKE_HEAVY * 0.5)


func _gold_ramp(a0: float) -> GradientTexture1D:
	var gd := Gradient.new()
	gd.offsets = PackedFloat32Array([0.0, 0.12, 0.7, 1.0])
	gd.colors = PackedColorArray([Color(1.0, 0.9, 0.55, a0), Color(1.0, 0.92, 0.6, 1.0), Color(1.0, 0.7, 0.25, 0.8), Color(1.0, 0.5, 0.1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = gd
	return gt


func _mote_quad(sz: float) -> QuadMesh:
	var qm := QuadMesh.new()
	qm.size = Vector2(sz, sz)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = Cent3dVfx.tex("mote.png")
	sm.no_depth_test = true
	sm.render_priority = 10
	qm.material = sm
	return qm


## 盾底一排金色光点往上飘(撑盾期间一直冒)
func _aegis_motes(pos: Vector3, yaw: float) -> GPUParticles3D:
	var ps := GPUParticles3D.new()
	ps.amount = 36
	ps.lifetime = 1.1
	ps.randomness = 0.6
	ps.local_coords = false
	ps.fixed_fps = 30
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.12, 0.1, AEGIS_R * sin(AEGIS_ARC * 0.5) * 0.95)
	pm.emission_shape_offset = Vector3(AEGIS_R * 0.9, 0.15, 0.0)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.0, 0.3, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	pm.color_ramp = _gold_ramp(0.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.14)
	ps.position = pos
	ps.rotation = Vector3(0.0, yaw, 0.0)
	battle._world.add_child(ps)
	return ps


## 放盾: 碎光片从盾面往外迸、往下落(一次性)
func _aegis_shards(pos: Vector3, yaw: float) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 44
	ps.lifetime = 0.7
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.randomness = 0.8
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.08, AEGIS_H * 0.45, AEGIS_R * sin(AEGIS_ARC * 0.5) * 0.9)
	pm.emission_shape_offset = Vector3(AEGIS_R, AEGIS_H * 0.5, 0.0)
	pm.direction = Vector3(1.0, 0.25, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0.0, -7.0, 0.0)
	pm.scale_min = 1.0
	pm.scale_max = 2.0
	pm.color_ramp = _gold_ramp(1.0)
	ps.process_material = pm
	ps.draw_pass_1 = _mote_quad(0.17)
	ps.position = pos
	ps.rotation = Vector3(0.0, yaw, 0.0)
	ps.emitting = true
	battle._world.add_child(ps)
	_aegis_junk.append({"node": ps, "left": 1.0})


## 穿盾矛光(每 0.5 秒, 跟帧条捅出帧同一刻): 从盾心往前穿出去 2.6 米, 方向在盾的正前方左右略错开
func _aegis_ray(a: Dictionary) -> void:
	var k: int = int(a["jab"])
	var yaw: float = float(a["yaw"]) + [0.0, -0.18, 0.15, -0.08, 0.2][k % 5]
	var wdir := Vector3(cos(yaw), 0.0, -sin(yaw))
	var mi := Cent3dVfx.node(battle._world, Cent3dVfx.gen_ray_cross(2.6, 0.55), Cent3dVfx.RAY_SHADER, Cent3dVfx.RAY_SP,
		{"tex_ray": Cent3dVfx.tex("ray.png"), "prog": 0.0}, 10)
	mi.position = battle._world_pos(Vector2((a["u"] as Dictionary)["pos"]), 0.0) + wdir * (AEGIS_R * 0.85) + Vector3(0.0, 1.35, 0.0)
	mi.rotation = Vector3(0.0, yaw, 0.0)
	_rays.append({"node": mi, "mat": mi.material_override, "t": 0.0})


## 受击涟漪: 本体掉血那一步, 盾面朝最近敌人那一点起一圈(弧上的位置按敌人相对盾正前方的角度算)
func _aegis_ripple(a: Dictionary) -> void:
	var u: Dictionary = a["u"]
	var tg = battle._targeting._nearest_enemy(u)
	var ang := 0.0
	if tg is Dictionary:
		var d: Vector2 = Vector2(tg["pos"]) - Vector2(u["pos"])
		ang = wrapf(atan2(d.y, d.x) - atan2((a["dir"] as Vector2).y, (a["dir"] as Vector2).x), -PI, PI)
	var n: int = (a["rips"] as Array).size()
	(a["rips"] as Array).append(Vector4(clampf(0.5 + ang / AEGIS_ARC, 0.12, 0.88), 0.32 + 0.36 * fmod(float(n) * 0.618, 1.0), 0.0, 1.0))
	if (a["rips"] as Array).size() > 4:
		(a["rips"] as Array).pop_front()


func _aegis_free(a: Dictionary) -> void:
	for n in a.get("parts", []):
		_free(n)
	_free(a.get("ring"))
	_free(a.get("motes"))


## 放盾: 按侵蚀图从上往下烧掉(AEGIS_BRK_SEC) + 碎光片, 烧完再删节点
func cent_shield_off(u: Dictionary) -> void:
	for a in _aegis:
		if is_same(a["u"], u) and float(a["off"]) < 0.0:
			a["off"] = 0.0
			var m = a.get("motes")
			if m != null and is_instance_valid(m):
				(m as GPUParticles3D).emitting = false
			_aegis_shards(battle._world_pos(Vector2(u["pos"]), 0.0), float(a["yaw"]))


func _tick_aegis(delta: float) -> void:
	var keep: Array = []
	for a in _aegis:
		var n = a["node"]
		var u: Dictionary = a["u"]
		if n == null or not is_instance_valid(n):
			_aegis_free(a)
			continue
		if not u.get("alive", false) and float(a["off"]) < 0.0:
			cent_shield_off(u)
		a["t"] = float(a["t"]) + delta
		var t: float = float(a["t"])
		var pos: Vector3 = battle._world_pos(Vector2(u["pos"]), 0.0)
		var on: bool = float(a["off"]) < 0.0
		## 受击涟漪: 掉血那一步起一圈
		var hp: float = float(u.get("hp", 0.0))
		if on and hp < float(a["hp"]) - 0.5:
			_aegis_ripple(a)
		a["hp"] = hp
		var rv: Array = []
		for r in a["rips"]:
			var r4: Vector4 = r
			r4.z += delta
			rv.append(r4)
		a["rips"] = rv
		## 穿盾矛光(0.5 / 1.0 / … 秒)
		var jn: int = int(t / AEGIS_JAB_IV)
		if on and jn > int(a["jab"]):
			a["jab"] = jn
			_aegis_ray(a)
		var ph: float = fmod(t, AEGIS_JAB_IV)
		var fl: float = maxf(0.0, 1.0 - ph / 0.15) if t >= AEGIS_JAB_IV - 0.001 and ph < 0.15 and on else 0.0
		var k: float = 0.0
		if not on:
			a["off"] = float(a["off"]) + delta
			k = minf(1.0, float(a["off"]) / AEGIS_BRK_SEC)
		var op: float = minf(1.0, t / AEGIS_OPEN_SEC)
		var pop: float = 1.0 + 0.08 * sin(PI * clampf(t / 0.24, 0.0, 1.0))   # 张开时整面高度回弹一下
		for i in range((a["parts"] as Array).size()):
			var p = a["parts"][i]
			if p == null or not is_instance_valid(p):
				continue
			(p as Node3D).position = pos
			if i < 2:
				(p as Node3D).scale = Vector3(1.0, pop, 1.0)
			var mat: ShaderMaterial = (p as MeshInstance3D).material_override
			mat.set_shader_parameter("t", t)
			mat.set_shader_parameter("open", op)
			mat.set_shader_parameter("close", k)
			mat.set_shader_parameter("fade", 1.0)
			if i < 2:
				mat.set_shader_parameter("flash", fl)
				for ri in range(4):
					var rr: Vector4 = rv[rv.size() - 1 - ri] if ri < rv.size() else Vector4(0.5, 0.5, 9.0, 0.0)
					mat.set_shader_parameter("rip%d" % ri, rr)
		var mo = a.get("motes")
		if mo != null and is_instance_valid(mo):
			(mo as Node3D).position = pos
		var rg = a.get("ring")
		if rg != null and is_instance_valid(rg):
			var rk: float = t / AEGIS_RING_SEC
			if rk >= 1.0:
				_free(rg)
				a["ring"] = null
			else:
				var rm: ShaderMaterial = (rg as MeshInstance3D).material_override
				rm.set_shader_parameter("shell_k", 0.05 + 0.9 * rk)
				rm.set_shader_parameter("fade", 1.0 - rk * rk)
				rm.set_shader_parameter("t", t)
		if k >= 1.0:
			_aegis_free(a)
			continue
		keep.append(a)
	_aegis = keep
	## 穿盾矛光 / 碎光片的收尾
	var kr: Array = []
	for r in _rays:
		var rn = r["node"]
		if rn == null or not is_instance_valid(rn):
			continue
		r["t"] = float(r["t"]) + delta
		var pk: float = float(r["t"]) / AEGIS_RAY_SEC
		if pk >= 1.0:
			_free(rn)
			continue
		(r["mat"] as ShaderMaterial).set_shader_parameter("prog", pk)
		kr.append(r)
	_rays = kr
	var kj: Array = []
	for j in _aegis_junk:
		j["left"] = float(j["left"]) - delta
		if float(j["left"]) <= 0.0:
			_free(j["node"])
			continue
		kj.append(j)
	_aegis_junk = kj
'''


def main():
    rel = "scripts/scenes/battle/spear_eq_vfx.gd"
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    start = "## 龟甲阵(11-27 第六轮, 用户「这举盾任何方向上都有可能举盾…需要三 D 特效」)"
    end = "## 3 档举盾期间每 0.5 秒刺周围"
    assert s.count(start) == 1 and s.count(end) == 1
    i = s.index(start); j = s.index(end)
    s = s[:i] + NEW + "\n\n" + s[j:]
    a = "\tfor a in _aegis:\n\t\t_free(a[\"node\"])\n\t_aegis.clear()\n"
    assert s.count(a) == 1
    s = s.replace(a, "\tfor a in _aegis:\n\t\t_aegis_free(a)\n\t_aegis.clear()\n\tfor r in _rays:\n\t\t_free(r[\"node\"])\n\t_rays.clear()\n\tfor j in _aegis_junk:\n\t\t_free(j[\"node\"])\n\t_aegis_junk.clear()\n")
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))

    ## 录像台: 演示受击涟漪 —— REC_AEGIS_HITS 时每 0.35 秒给百夫长一下 1 点伤害(录像说明里写明)
    rel = "tests/_rec_eq_stage.gd"
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    a = '\t\tif cen != null and _seen.has("adir%d" % ad_k) and not _seen.has("adoff%d" % ad_k) and ad_t - float(ad_k) * 1.7 > 1.45:\n'
    assert s.count(a) == 1
    s = s.replace(a, '\t\tif cen != null and OS.has_environment("REC_AEGIS_HITS") and ad_k < 8 and int(ad_t / 0.35) != int((ad_t - d) / 0.35):   # 受击涟漪演示: 每 0.35 秒 1 点伤害\n'
                     '\t\t\t_b._damage._apply_damage(cen, 1, Color.WHITE)\n' + a)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok")


main()
