class_name LaserBladeVfx
extends "res://scripts/scenes/battle/candy_vfx.gd"
## 010 激光长刃 —— 专属特效(2026-11-27 重做; 只管画面, 不读写对局状态, 不动 RULES_VER)。
## 用户 11-27「装备激光长刃的图标和技能特效都全部再重新做一遍…你是以特效师的身份去做，所以要尽量完美一点」。
## 参考研究 docs/studies/20261127-参考-永恩斩击特效配方.md(永恩 W 扇形斩 / Q 直线斩的发射器配方, 36 个发射器逐个记):
##   最亮的刃只亮 0.1 秒 → 拖尾 / 余光 0.2~0.4 秒 → 地上的痕迹 1.2 秒; 命中 = 三道不同宽度的横斩光 + 四角星 + 冲击环 + 火花;
##   贴图全是灰度形状(tools/assetgen/eq010_laser_tex.py), 颜色在这里 / 着色器里上(白热芯 → 粉 → 红 → 深红)。
##
## 分段(方案见 docs/plans/20261127c-激光长刃重做.md):
##   ① 出手      携带者脚下红光一闪 + 刃高度一颗白星
##   ② 扇形斩    laser_fan.gdshader: 领先刃约 0.1 秒扫完 120°, 后面拖月牙余光 + 三道同心速度纹 + 外缘亮线; 扫过之处沿弧迸火花
##   ③ 命中      刃扫到哪个敌人哪个敌人亮(伤害仍在出手同帧结算, 画面按刃扫到它的时刻出): 三道横斩光 + 四角星 + 冲击环 + 地面光 + 火花
##   ④ 地面熔痕  laser_scorch.gdshader: 刃扫过的地面留扇形焦痕, 熔裂纹 0.5 秒内由红热冷下去, 焦痕 1.2 秒淡出
##   ⑤ 直线追斩  携带者身上竖剑光一闪; laser_beam.gdshader 光带的波前按 LASER_CHOP_SPEED 推进(= 结算那一份速度),
##               身后拖光束余光、地上留一道熔痕; 波碰到谁谁出 ③; 到头后光束从尾巴往前散掉
## 网格挂出处键(VfxTex.tag)、会动的着色器参数挂 stream_shader_params(Cent3dVfx.node) ⇒ 逐帧直播照样看得见;
## 粒子走 _p(游戏钟 + 出生参数) ⇒ 直播只发出生参数。

const SRC := "res://scripts/scenes/battle/laser_blade_vfx.gd"
const T := "res://assets/sprites/vfx/eq010/"
const FAN_SHADER: Shader = preload("res://assets/shaders/laser_fan.gdshader")
const SCORCH_SHADER: Shader = preload("res://assets/shaders/laser_scorch.gdshader")
const BEAM_SHADER: Shader = preload("res://assets/shaders/laser_beam.gdshader")
const FAN_SP := ["prog", "fade"]
const SCORCH_SP := ["prog", "age"]
const BEAM_SP := ["head", "tail"]

const SLASH_H := 0.30          # 刃离地高度(米): 刃扫过敌人腰部
const FAN_LIFE := 0.25         # = EquipSystem.LASER_SLASH_FRAMES × LASER_SLASH_STEP(结算那边等的就是这么久)
const PROG_MAX := 1.9          # 领先刃走到 1 = 扫完; 继续走到 1.9 = 余光按落后距离自然衰减掉
const PROG_POW := 0.72         # 先快后慢: 约 0.10 秒扫完 120°
const SCORCH_LIFE := 0.9
const BEAM_TAIL_SEC := 0.25    # 波到头后光束从尾巴往前散掉的时长
const L_RED := Color(1.0, 0.20, 0.26)
const L_PINK := Color(1.0, 0.62, 0.66)
const L_HOT := Color(1.0, 0.96, 0.92)

var _live: Array = []


func _init(b) -> void:
	super(b)
	rng.seed = 271127


## 直线光带网格: 从本地原点沿 +X 铺 len_m 米、宽 w_m 米(UV.x 沿长 0→1, UV.y 横向 0→1), 离地 y0。
static func gen_strip(len_m: float, w_m: float, y0: float, nu: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(2):
		for i in range(nu + 1):
			var u: float = float(i) / float(nu)
			st.set_uv(Vector2(u, float(j)))
			st.add_vertex(Vector3(u * len_m, y0, (float(j) - 0.5) * w_m))
	for i in range(nu):
		var a: int = i
		var b: int = i + 1
		var c: int = i + nu + 1
		var d: int = c + 1
		for k in [a, c, b, b, c, d]:
			st.add_index(k)
	return VfxTex.tag(st.commit(), "gen_strip", [len_m, w_m, y0, nu], SRC)


func _prog_at(el: float) -> float:
	return PROG_MAX * pow(clampf(el / FAN_LIFE, 0.0, 1.0), PROG_POW)


## 领先刃走到 p(0..1)的那一刻(出手后多少秒)
func _t_of_prog(p: float) -> float:
	return FAN_LIFE * pow(clampf(p, 0.0, 1.0) / PROG_MAX, 1.0 / PROG_POW)


## 2D 方向 dir 转 a 弧度(与 gen_fan 本地角同向: 网格绕 Y 转 yaw_of(dir) 后, 本地角 a 落在 2D 的 dir 转 +a)
static func _rot(dir: Vector2, a: float) -> Vector2:
	return Vector2(dir.x * cos(a) - dir.y * sin(a), dir.x * sin(a) + dir.y * cos(a))


# ════════════════════════════════════════════════════════════════════════════
#  ①②③④ 扇形斩。org / dir = 结算用的那一份(dir 已吸附到 16 档), rng = 判定半径(码), arc = 全角(弧度), hits = 结算打到的人
# ════════════════════════════════════════════════════════════════════════════
func sweep(org: Vector2, dir: Vector2, rng_c: float, arc: float, hits: Array) -> void:
	if battle._world == null:
		return
	var t0: float = battle._t
	var r_m: float = rng_c * battle.WS
	var yaw: float = Cent3dVfx.yaw_of(dir)
	## ② 扇形斩本体(刃高度, 不做深度测试: 刃扫过敌人身上)
	var fan := Cent3dVfx.node(battle._world, Cent3dVfx.gen_fan(0.0, r_m, arc, 0.0, 56, 12), FAN_SHADER, FAN_SP, {"prog": 0.0, "fade": 1.0}, 9)
	fan.position = battle._world_pos(org, SLASH_H)
	fan.rotation.y = yaw
	_live.append({"k": "fan", "node": fan, "t0": t0})
	## ④ 地面熔痕(贴地, 开深度, 压在龟脚下)
	var sc := Cent3dVfx.node(battle._world, Cent3dVfx.gen_fan(0.0, r_m, arc, 0.0, 56, 12), SCORCH_SHADER, SCORCH_SP,
		{"prog": 0.0, "age": 0.0, "life": SCORCH_LIFE, "strip": 0.0, "seed": float(rng.randi_range(0, 999)), "sweep_sec": _t_of_prog(1.0)}, -2)
	sc.position = battle._world_pos(org, 0.02)
	sc.rotation.y = yaw
	_live.append({"k": "scorch_fan", "node": sc, "t0": t0})
	## ① 出手: 脚下红光一闪 + 刃根白星
	var glow: Texture2D = tex(GLOW_TEX)
	var flare: Texture2D = tex(T + "flare.png")
	if glow != null:
		_p(glow, battle._world_pos(org, 0.03), {"texel": 2.6, "life": 0.2, "s0": 0.7, "s1": 1.4, "a0": 0.9, "a1": 0.0, "tint": L_RED, "add": true, "flat": true, "prio": -1, "t0": t0})
	if flare != null:
		_p(flare, battle._world_pos(org + dir * 26.0, SLASH_H + 0.12), {"texel": 1.8, "life": 0.1, "s0": 1.3, "s1": 0.5, "a0": 1.0, "a1": 0.0, "tint": L_HOT, "add": true, "prio": 11, "t0": t0})
	## ② 沿弧迸火花: 刃扫过那一刻从外缘往外甩, 落一点
	if flare != null:
		for i in range(12):
			var f: float = (float(i) + 0.5) / 12.0
			var a: float = lerpf(-arc * 0.5, arc * 0.5, f)
			var out: Vector2 = _rot(dir, a)
			var rr: float = rng_c * rng.randf_range(0.82, 1.0)
			var tang: Vector2 = _rot(dir, a + PI * 0.5)
			var v2: Vector2 = (out * rng.randf_range(0.9, 1.6) + tang * rng.randf_range(0.6, 1.2))
			_p(flare, battle._world_pos(org + out * rr, SLASH_H), {"texel": rng.randf_range(0.35, 0.55), "life": rng.randf_range(0.22, 0.34),
				"vel": Vector3(v2.x, rng.randf_range(0.8, 1.6), v2.y), "grav": 7.0, "s0": 1.0, "s1": 0.4, "a0": 1.0, "a1": 0.0,
				"tint": L_PINK if i % 3 else L_HOT, "add": true, "prio": 11, "t0": t0 + _t_of_prog(f)})
	## ③ 命中: 刃扫到哪个敌人哪个敌人亮
	for o in hits:
		var rel: Vector2 = o["pos"] - org
		var a2: float = atan2(dir.x * rel.y - dir.y * rel.x, dir.x * rel.x + dir.y * rel.y)
		hit(o, dir, t0 + _t_of_prog((a2 + arc * 0.5) / arc))


# ════════════════════════════════════════════════════════════════════════════
#  ③ 命中(扇形斩 / 直线追斩共用)
# ════════════════════════════════════════════════════════════════════════════
func hit(o: Dictionary, dir: Vector2, t_at: float) -> void:
	if battle._world == null:
		return
	var sp: Texture2D = tex(T + "spindle.png")
	var flare: Texture2D = tex(T + "flare.png")
	var ring: Texture2D = tex(T + "ring.png")
	var glow: Texture2D = tex(GLOW_TEX)
	if sp == null or flare == null or ring == null or glow == null:
		return                       # 缺图就不画, 不拿别的图顶替
	var hh: float = float(o.get("height", 0.0))
	var c: Vector3 = battle._world_pos(o["pos"], 0.45 + hh)
	## 三道横斩光: 同形不同大小(永恩 W 命中 225×40 / 175×20 / 140×6), 一道比一道细、一道比一道短命
	_p(sp, c + Vector3(0.0, 0.06, 0.0), {"texel": 1.6, "life": 0.16, "s0": 0.8, "s1": 1.25, "a0": 1.0, "a1": 0.0, "tint": L_RED, "add": true, "prio": 11, "t0": t_at})
	_p(sp, c + Vector3(0.0, -0.04, 0.0), {"texel": 1.25, "life": 0.14, "s0": 0.85, "s1": 1.3, "a0": 1.0, "a1": 0.0, "tint": L_PINK, "add": true, "prio": 12, "t0": t_at})
	_p(sp, c, {"texel": 0.8, "life": 0.1, "s0": 0.9, "s1": 1.3, "a0": 0.8, "a1": 0.0, "tint": L_HOT, "add": true, "prio": 13, "t0": t_at})
	## 四角星 0.1 秒 + 冲击环 0.18 秒 + 地面光
	_p(flare, c, {"texel": 1.4, "life": 0.1, "s0": 1.3, "s1": 0.6, "a0": 0.9, "a1": 0.0, "tint": L_HOT, "add": true, "prio": 13, "t0": t_at})
	_p(ring, c, {"texel": 0.9, "life": 0.18, "s0": 0.45, "s1": 1.3, "a0": 0.9, "a1": 0.0, "tint": L_RED, "add": true, "prio": 12, "t0": t_at})
	_p(glow, battle._world_pos(o["pos"], 0.03), {"texel": 1.8, "life": 0.16, "s0": 0.6, "s1": 1.2, "a0": 0.8, "a1": 0.0, "tint": L_RED, "add": true, "flat": true, "prio": -1, "t0": t_at})
	## 火花: 顺着刃的方向崩出去
	for i in range(6):
		var a: float = rng.randf_range(-1.1, 1.1)
		var v2: Vector2 = _rot(dir, a) * rng.randf_range(1.2, 2.4)
		_p(flare, c, {"texel": rng.randf_range(0.3, 0.5), "life": rng.randf_range(0.2, 0.3), "vel": Vector3(v2.x, rng.randf_range(0.6, 1.8), v2.y),
			"grav": 8.0, "s0": 1.0, "s1": 0.4, "a0": 1.0, "a1": 0.0, "tint": L_PINK if i % 2 else L_HOT, "add": true, "prio": 12, "t0": t_at})


# ════════════════════════════════════════════════════════════════════════════
#  ⑤ 直线追斩: 波前速度 speed(码/秒)= 结算那一份; 推到 reach(码); half_w = 判定半宽(码)
# ════════════════════════════════════════════════════════════════════════════
func chop_begin(org: Vector2, dir: Vector2, reach: float, speed: float, half_w: float) -> Dictionary:
	if battle._world == null:
		return {}
	var t0: float = battle._t
	var len_c: float = reach + 30.0
	var len_m: float = len_c * battle.WS
	var w_m: float = half_w * 2.0 * battle.WS
	var yaw: float = Cent3dVfx.yaw_of(dir)
	var beam := Cent3dVfx.node(battle._world, gen_strip(len_m, w_m, 0.0, 48), BEAM_SHADER, BEAM_SP, {"head": 0.0, "tail": 0.0, "len_m": len_m}, 9)
	beam.position = battle._world_pos(org, SLASH_H)
	beam.rotation.y = yaw
	var sc := Cent3dVfx.node(battle._world, gen_strip(len_m, w_m * 0.55, 0.0, 48), SCORCH_SHADER, SCORCH_SP,
		{"prog": 0.0, "age": 0.0, "life": SCORCH_LIFE, "strip": 1.0, "seed": float(rng.randi_range(0, 999)), "sweep_sec": len_c / speed}, -2)
	sc.position = battle._world_pos(org, 0.02)
	sc.rotation.y = yaw
	var h := {"k": "beam", "node": beam, "scorch": sc, "t0": t0, "len_c": len_c, "speed": speed, "end": -1.0}
	_live.append(h)
	## 出手: 携带者身上竖剑光一闪(永恩 Q 亮刃只亮 0.1 秒) + 脚下红光
	var spv: Texture2D = tex(T + "spindle_v.png")
	var glow: Texture2D = tex(GLOW_TEX)
	if spv != null:
		_p(spv, battle._world_pos(org, 0.7), {"texel": 0.95, "life": 0.12, "s0": 1.2, "s1": 0.8, "a0": 1.0, "a1": 0.0, "tint": L_HOT, "add": true, "prio": 12, "t0": t0})
		_p(spv, battle._world_pos(org, 0.7), {"texel": 1.3, "life": 0.22, "s0": 1.0, "s1": 1.1, "a0": 0.7, "a1": 0.0, "tint": L_RED, "add": true, "prio": 11, "t0": t0})
		if glow != null:
			_p(glow, battle._world_pos(org, 0.7), {"texel": 1.6, "life": 0.18, "s0": 0.8, "s1": 1.2, "a0": 0.7, "a1": 0.0, "tint": L_RED, "add": true, "prio": 10, "t0": t0})
	if glow != null:
		_p(glow, battle._world_pos(org, 0.03), {"texel": 2.4, "life": 0.22, "s0": 0.7, "s1": 1.3, "a0": 0.9, "a1": 0.0, "tint": L_RED, "add": true, "flat": true, "prio": -1, "t0": t0})
	## 波前上那颗亮光(跟着波前走: 速度 = 结算速度, 寿命 = 推到头的时间)
	var flare: Texture2D = tex(T + "flare.png")
	if flare != null:
		var v3: Vector3 = Vector3(dir.x, 0.0, dir.y) * speed * battle.WS
		_p(flare, battle._world_pos(org, SLASH_H + 0.05), {"texel": 1.5, "life": reach / speed, "vel": v3, "s0": 1.0, "s1": 1.0, "a0": 1.0, "a1": 0.85, "tint": L_HOT, "add": true, "prio": 12, "t0": t0})
		if glow != null:
			_p(glow, battle._world_pos(org, SLASH_H), {"texel": 1.8, "life": reach / speed, "vel": v3, "s0": 1.0, "s1": 1.0, "a0": 0.8, "a1": 0.6, "tint": L_RED, "add": true, "prio": 11, "t0": t0})
	return h


func chop_end(h: Dictionary) -> void:
	if not h.is_empty():
		h["end"] = battle._t


## 每帧(battle_render): 推进着色器参数、到时间就收
func tick() -> void:
	var keep: Array = []
	for l in _live:
		var n = l["node"]
		if n == null or not is_instance_valid(n):
			continue
		var el: float = battle._t - float(l["t0"])
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		match str(l["k"]):
			"fan":
				m.set_shader_parameter("prog", _prog_at(el))
				m.set_shader_parameter("fade", 1.0 - smoothstep(FAN_LIFE * 0.75, FAN_LIFE, el))
				if el >= FAN_LIFE + 0.02:
					_free_node(n)
					continue
			"scorch_fan":
				m.set_shader_parameter("prog", minf(1.0, _prog_at(el)))
				m.set_shader_parameter("age", el)
				if el >= SCORCH_LIFE + _t_of_prog(1.0):
					_free_node(n)
					continue
			"beam":
				var head: float = el * float(l["speed"]) / float(l["len_c"])
				m.set_shader_parameter("head", head)
				var scn = l["scorch"]
				var sm: ShaderMaterial = null
				if scn != null and is_instance_valid(scn):
					sm = (scn as MeshInstance3D).material_override as ShaderMaterial
					sm.set_shader_parameter("prog", minf(1.0, head))
					sm.set_shader_parameter("age", el)
				var te: float = float(l["end"])
				if te >= 0.0:
					var tk: float = (battle._t - te) / BEAM_TAIL_SEC
					m.set_shader_parameter("tail", clampf(tk, 0.0, 1.0) * 1.2)
					if tk >= 1.0:
						_free_node(n)
						n = null
				if n == null:
					## 光束收完了; 熔痕交给自己那一条按寿命走完再收(加进 keep, 不在遍历中改 _live)
					if scn != null and is_instance_valid(scn):
						keep.append({"k": "scorch_strip", "node": scn, "t0": l["t0"], "until": SCORCH_LIFE + float(l["len_c"]) / float(l["speed"])})
					continue
			"scorch_strip":
				m.set_shader_parameter("age", el)
				if el >= float(l["until"]):
					_free_node(n)
					continue
		keep.append(l)
	_live = keep


func _free_node(n) -> void:
	if n != null and is_instance_valid(n):
		(n as Node).queue_free()
