"""eternal_field_1126.py —— 145 灼烧圈改成携带者周围的力场(用户 11-26 深夜「这个要跟着携带者移动啊，相当于携带者周围一个力场一样的东西啊」)
3D 低穹顶罩 + 地面从脚下往外渐暗 + 携带者身上往上窜的火 + 绕身转的火星 + 每秒罩面鼓亮; 取代上一版「地上一大圈火舌墙」。
一次性; 原行尾二进制读写, 每处替换次数核对。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, n in pairs:
        assert s.count(a) == n, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/battle/cent_3d_vfx.gd", [
    ("""## 十字交叉两片(沿 +X 长 ln 米, 宽 w 米): 穿盾矛光""", """## 低穹顶(145 灼烧力场, 11-26 深夜): 底圆半径 r 米、顶高 h 米, 中心在本地原点; UV.x 绕一圈 0→1, UV.y 地面 0 → 顶 1
static func gen_dome(r: float, h: float, nu: int, nv: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(nv + 1):
		var v: float = float(j) / float(nv)
		var th: float = v * PI * 0.5
		for i in range(nu + 1):
			var u: float = float(i) / float(nu)
			var a: float = TAU * u
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(cos(a) * cos(th) * r, sin(th) * h, sin(a) * cos(th) * r))
	_grid_index(st, nu, nv)
	st.generate_normals()
	return VfxTex.tag(st.commit(), "gen_dome", [r, h, nu, nv], SRC)


## 十字交叉两片(沿 +X 长 ln 米, 宽 w 米): 穿盾矛光""", 1),
    ("""const SHEATH_SP := ["t", "fade"]
""", """const SHEATH_SP := ["t", "fade"]
const FIELD_SHADER: Shader = preload("res://assets/shaders/eternal_field.gdshader")
const FIELD_SP := ["t", "grow", "pulse", "fade", "stack"]
""", 1),
])

VF = "scripts/scenes/battle/spear_eq_vfx.gd"
p = os.path.join(ROOT, VF)
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = s.index("## ⑦ 灼烧圈(跟着携带者;")
b = s.index("var _eter_embers: Array = []\n")
NEW = """## ⑦ 灼烧力场(跟着携带者; 用户 11-26 深夜「相当于携带者周围一个力场一样的东西」, 取代上一版地上一大圈火舌墙) —— 分层:
##   力场罩: 3D 低穹顶(Cent3dVfx.gen_dome, 半径 = 结算半径), 只画菲涅尔轮廓 + 贴地火线 + 往上流的热浪丝, 大部分透明不挡人
##   地面: 整圆, 脚下最亮往外渐暗 + 边上一道暗焦痕(压对比)
##   携带者身上: 一圈 Aseprite 手画火舌贴着身子往上窜(前矮后高) + 火星绕身转圈上升 —— 看得出力场是从他身上发出来的
##   每秒跳伤害: 罩面由内往外鼓一下亮一下(pulse) + 圈内挨烧的人身上舔一下火; 叠加: 罩更浓、身上火更高; 结束: 罩缩回、火落下
const ETER_DOME_H := 0.42       # 罩高 = 半径 × (低穹顶, 不压住画面)
const ETER_BODY_FLAMES := 7
const ETER_BODY_R := 18.0       # 身上火舌离身体中心(码)
const ETER_BODY_H := 1.5        # 身上火舌高(米)
const ETER_GROW := 0.3
const ETER_SHRINK := 0.45
var _eter_rings: Array = []     # {me, dome, disc, flames[_mfx 条], t, life, stack, ember, en, pulse}


func eternal_burn(me: Dictionary, r: float, sec: float) -> void:
	if not _ok():
		return
	var stack := 1
	for rr in _eter_rings:
		if is_same(rr["me"], me):
			stack += 1
	var rm: float = r * float(battle.WS)
	var te := Cent3dVfx.tex("energy.png")
	var dome := Cent3dVfx.node(battle._world, Cent3dVfx.gen_dome(rm, rm * ETER_DOME_H, 48, 10), Cent3dVfx.FIELD_SHADER, Cent3dVfx.FIELD_SP,
		{"tex_energy": te, "layer": 0.0, "grow": 0.0, "stack": float(stack)}, 8)
	var disc := Cent3dVfx.node(battle._world, Cent3dVfx.gen_fan(0.0, rm, TAU, 0.0, 48, 8), Cent3dVfx.FIELD_SHADER, Cent3dVfx.FIELD_SP,
		{"tex_energy": te, "layer": 1.0, "grow": 0.0, "stack": float(stack)}, -2)
	var ring := {"me": me, "dome": dome, "disc": disc, "flames": [], "t": 0.0, "life": sec, "stack": stack, "ember": 0.0, "en": 0, "pulse": 0.0}
	for i in range(ETER_BODY_FLAMES):
		var sp := _strip(SV + "eternal-flame-tongue.png", 8, battle._world_pos(Vector2(me["pos"]), 0.0), ETER_BODY_H, 12.0, true, sec, false, null, 0.0)
		if sp != null:
			var f: Dictionary = _mfx.back()
			f["t"] = float(i % 8) / 12.0 * 1.37   # 帧错开
			(ring["flames"] as Array).append(f)
	_eter_rings.append(ring)
	_eter_place(ring)


func eternal_burn_tick(me: Dictionary, _r: float) -> void:
	for ring in _eter_rings:
		if is_same(ring["me"], me):
			ring["pulse"] = 1.0


func eternal_burn_lick(e: Dictionary) -> void:
	var s := _strip(SV + "eternal-flame-tongue.png", 8, battle._world_pos(Vector2(e["pos"]), 0.0), 0.9, 16.0, false, 0.5, false, e, 0.0)
	if s != null:
		s.render_priority = 9


func _eter_place(ring: Dictionary) -> void:
	var me: Dictionary = ring["me"]
	var c := Vector2(me["pos"])
	var t: float = float(ring["t"])
	var life: float = float(ring["life"])
	var grow: float = clampf(t / ETER_GROW, 0.0, 1.0) * clampf((life - t) / ETER_SHRINK, 0.0, 1.0)
	grow = 1.0 - (1.0 - grow) * (1.0 - grow)
	for key in ["dome", "disc"]:
		var n = ring[key]
		if n == null or not is_instance_valid(n):
			continue
		(n as Node3D).position = battle._world_pos(c, 0.02 if key == "disc" else 0.0)
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		m.set_shader_parameter("t", t)
		m.set_shader_parameter("grow", grow)
		m.set_shader_parameter("pulse", float(ring["pulse"]))
	var fl: Array = ring["flames"]
	var hm: float = 1.0 + 0.2 * float(int(ring["stack"]) - 1)
	for i in range(fl.size()):
		var n = (fl[i] as Dictionary)["node"]
		if n == null or not is_instance_valid(n):
			continue
		var a: float = TAU * float(i) / float(fl.size()) + t * 0.8
		var front: float = (sin(a) + 1.0) * 0.5
		var sp := n as Sprite3D
		var h: float = lerpf(ETER_BODY_H * 1.15, ETER_BODY_H * 0.7, front) * hm * grow * (1.0 + 0.25 * float(ring["pulse"]))
		sp.position = battle._world_pos(c + Vector2(cos(a), sin(a)) * ETER_BODY_R, 0.0)
		sp.pixel_size = maxf(0.0001, h / float(sp.texture.get_height()))
		sp.no_depth_test = false   # 身后那几根被身体挡住, 身前的盖在身上
		sp.render_priority = 0
		sp.modulate.a = clampf(grow * 1.4, 0.0, 0.95)


func _tick_eter_rings(delta: float) -> void:
	var keep: Array = []
	for ring in _eter_rings:
		var me: Dictionary = ring["me"]
		ring["t"] = float(ring["t"]) + delta
		ring["pulse"] = maxf(0.0, float(ring["pulse"]) - delta / 0.35)
		if float(ring["t"]) >= float(ring["life"]) or not me.get("alive", false):
			_free(ring["dome"])
			_free(ring["disc"])
			for f in ring["flames"]:
				_free((f as Dictionary)["node"])
			continue
		_eter_place(ring)
		## 火星: 从携带者身边绕身转圈往上飘(黄金角轮转, 不用随机数)
		ring["ember"] = float(ring["ember"]) + delta
		while float(ring["ember"]) >= 0.09:
			ring["ember"] = float(ring["ember"]) - 0.09
			ring["en"] = int(ring["en"]) + 1
			var ea: float = float(ring["en"]) * 2.39996
			_eter_embers.append({"me": me, "a": ea, "t": 0.0, "node": _ember_node(Vector2(me["pos"]))})
		keep.append(ring)
	_eter_rings = keep
	var ke: Array = []
	for e in _eter_embers:
		var n = e["node"]
		var me2: Dictionary = e["me"]
		if n == null or not is_instance_valid(n) or not me2.get("alive", false):
			_free(n)
			continue
		e["t"] = float(e["t"]) + delta
		var k: float = float(e["t"]) / 0.9
		if k >= 1.0:
			_free(n)
			continue
		var a: float = float(e["a"]) + k * 3.5                      # 绕身转
		var rr: float = 26.0 + 20.0 * k
		(n as Sprite3D).position = battle._world_pos(Vector2(me2["pos"]) + Vector2(cos(a), sin(a)) * rr, 0.2 + 1.8 * k)
		(n as Sprite3D).modulate = Color(1.0, 0.65 + 0.3 * (1.0 - k), 0.25, 1.0 - k)
		ke.append(e)
	_eter_embers = ke


"""
s = s[:a] + NEW + s[b:]
## 清场: 罩 / 地面节点
old_clear = """	for ring in _eter_rings:
		for f in ring["tongues"]:
			_free((f as Dictionary)["node"])
	_eter_rings.clear()
"""
assert s.count(old_clear) == 1
s = s.replace(old_clear, """	for ring in _eter_rings:
		_free(ring["dome"])
		_free(ring["disc"])
		for f in ring["flames"]:
			_free((f as Dictionary)["node"])
	_eter_rings.clear()
""")
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))

## 地面 / 光波素材这一版不用了
patch("tools/assetgen/pack_holy_spear_art.py", [
    ('        "eternal-impact": "center", "eternal-ring-ground": "center", "eternal-pulse": "center"}',
     '        "eternal-impact": "center"}', 1),
    ("    eternal-ring-ground 灼烧圈地面层(循环 12 帧, 俯视): 暗褐焦痕环(压对比) + 焦斑 + 圈内淡热光呼吸 + 圈边琥珀细光\n"
     "    eternal-pulse       每秒跳伤害的光波(8 帧, 俯视): 从中心推到圈边的亮环 + 余晖 + 往外甩的火星\n",
     "    (11-26 深夜用户「相当于携带者周围一个力场一样的东西」⇒ 地面环 / 光波两张作废, 力场改 3D 网格 + 着色器 assets/shaders/eternal_field.gdshader)\n", 1),
    ("    eternal-flame-tongue 圈边火舌(循环 8 帧)", "    eternal-flame-tongue 火舌(循环 8 帧; 力场版贴在携带者身上往上窜)", 1),
])
print("ok")
