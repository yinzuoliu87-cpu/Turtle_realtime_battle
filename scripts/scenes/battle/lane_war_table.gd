extends RefCounted
## lane_war_table.gd — 三路开场的「桌面作战地图」: 斜上方俯看一张摆在桌上的地图, 镜头飞进某一路战场(2026-11-15 第三轮)。
## 用户 11-15:「在一个视角上面看到下面一张地图吧…三条战线，上路战场、下路战场…我们就把视角往里面挪动…
##   上路战场结束之后，如果你输了，这一个叉就挥掉…如果到终极战场的话，那就中间这个大战场就亮起来…每次登场就是…三只三只，都得明白」
## 方案书 docs/plans/20261115d-三路战场地图开场.md §4.5。调度(什么时候飞、什么时候打叉)在 lane_map_intro.gd 的轨道表里。
##
## ★独立 3D 世界(SubViewport.own_world_3d): 不碰战斗场景的世界, 换路清场 / 直播镜像都与它无关。
## ★画面按半分辨率渲、最近邻放大 ⇒ 3D 也是像素颗粒, 和游戏里其余像素画一致。字(路名 / 名字 / 印章)由 2D 层按投影位置叠在上面, 保持清楚。
## ★不靠 tween: 镜头 / 立牌 / 发光全由调用方按时刻摆(`set_cam` / 各节点属性), 门禁能摆到任意时刻去量。

const LANE_POS := {"top": Vector3(0.0, 0.0, -7.6), "bottom": Vector3(0.0, 0.0, 7.6), "final": Vector3(0.0, 0.0, 0.0)}
const LANE_R := {"top": 2.4, "bottom": 2.4, "final": 3.0}
const BASE_POS := {"left": Vector3(-12.6, 0.0, 0.0), "right": Vector3(12.6, 0.0, 0.0)}
const TOP_Y := 0.31                 # 战场台台面高度(立牌脚踩这一层)
const UNIT_H := 1.3                 # 立牌里角色本体的高度(米)。立牌整张正对镜头(不按竖轴转), 斜俯视下不会被压扁
const FOV := 38.0
const COL_BLUE := Color("#5b9cf0")
const COL_RED := Color("#ef5b66")
const COL_GOLD := Color("#ffd24a")

const SEA_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform float t = 0.0;
varying vec3 wp;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 q) {
	vec2 i = floor(q); vec2 f = fract(q); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = floor(wp.xz / 0.1) * 0.1;
	float d = clamp(length(p / vec2(26.0, 16.0)), 0.0, 1.0);
	vec3 col = mix(vec3(0.07, 0.15, 0.25), vec3(0.02, 0.05, 0.10), d);
	float n = vn(p / 4.5 + vec2(t * 0.03, t * 0.015));
	col = mix(col, col * 1.6 + vec3(0.0, 0.03, 0.04), floor(clamp((n - 0.45) * 3.0, 0.0, 1.0) * 3.0) / 3.0 * 0.5);
	vec2 g = abs(fract(p / 2.0 + 0.5) - 0.5);
	if (min(g.x, g.y) < 0.06) { col = mix(col, vec3(0.18, 0.30, 0.42), 0.30); }
	vec2 wc = floor(p / vec2(1.4, 0.9));
	float r = h(wc);
	if (r > 0.78) {
		vec2 lp = p - wc * vec2(1.4, 0.9);
		float ph = fract(t * 0.3 + r * 7.0);
		float dx = floor(ph * 5.0) * 0.1;
		if (lp.y > 0.4 && lp.y < 0.5 && lp.x > 0.2 + dx && lp.x < 0.6 + dx && ph < 0.75) { col = mix(col, vec3(0.55, 0.80, 0.92), 0.45); }
	}
	ALBEDO = col;
}
"""

## 战场台台面: 本局场地照片按圆裁(像素圆边), 可压暗 / 染队伍色 / 打亮
const TOP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D photo : source_color, filter_nearest;
uniform float has_photo = 0.0;
uniform vec4 base_col : source_color = vec4(0.17, 0.24, 0.17, 1.0);
uniform float dim = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float lit = 0.0;
void fragment() {
	vec2 uv = floor(UV * 160.0) / 160.0 + 0.5 / 160.0;
	if (distance(uv, vec2(0.5)) > 0.5) { discard; }
	vec2 pu = vec2(0.5 + (uv.x - 0.5) * 0.5625, uv.y);
	vec3 c = has_photo > 0.5 ? texture(photo, pu).rgb * 1.3 + 0.03 : base_col.rgb;
	c = mix(c, tint.rgb, tint.a);
	c *= (1.0 - dim);
	c += vec3(1.0, 0.85, 0.4) * lit * 0.25;
	ALBEDO = min(c, vec3(1.0));
}
"""

## 发光环 / 光柱 / 打叉刀痕: 透明叠加, 一个 alpha 参数控制
const GLOW_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 col : source_color = vec4(1.0, 0.8, 0.3, 1.0);
uniform float a = 0.0;
uniform float ring = 1.0;      // 1 = 环(按 UV 到中心距离取一圈); 0 = 光柱(按 UV.y 往上淡)
uniform float inner = 0.42;
void fragment() {
	float m;
	if (ring > 0.5) {
		float d = distance(UV, vec2(0.5));
		m = step(inner, d) * step(d, 0.5);
	} else {
		m = pow(1.0 - UV.y, 1.5);
	}
	ALBEDO = col.rgb * m * a;
}
"""

## 打叉的一刀: 沿长度方向按 prog 显出来, 中间一道白芯
const SLASH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float prog = 0.0;
uniform vec4 col : source_color = vec4(0.92, 0.18, 0.24, 1.0);
void fragment() {
	if (UV.x > prog) { discard; }
	float w = abs(UV.y - 0.5) * 2.0;
	float taper = 1.0 - pow(abs(UV.x - 0.5) * 2.0, 3.0);
	if (w > taper) { discard; }
	vec3 c = w < 0.3 ? vec3(1.0, 0.92, 0.85) : col.rgb;
	ALBEDO = c;
}
"""

var sv: SubViewport = null
var cam: Camera3D = null
var root3: Node3D = null
var view: TextureRect = null
var vp := Vector2(1560, 720)
var isl: Dictionary = {}          # lane → {node, top_mat, rim_mat, glow_mat, pillar_mat, slash: [mats], flag: Sprite3D}
var bases: Dictionary = {}        # side → {node}
var sea_mat: ShaderMaterial = null
var standees: Array = []          # [{spr, lane, side, idx, n, frames, fps}]
var paths: Array = []             # [{mi, mat}]
var _used_cache: Dictionary = {}


static func _sh(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


## 建整张桌面(不含立牌): 返回铺满全屏的那张 TextureRect(由调用方放进幕布)
func build(vp_: Vector2, photo: Texture2D, theme_col: Color) -> TextureRect:
	vp = vp_
	sv = SubViewport.new()
	sv.size = Vector2i(maxi(320, int(vp.x * 0.5)), maxi(180, int(vp.y * 0.5)))
	sv.own_world_3d = true
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.04, 0.08)
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	root3 = Node3D.new()
	sv.add_child(root3)
	cam = Camera3D.new()
	cam.fov = FOV
	cam.near = 0.1
	cam.far = 200.0
	sv.add_child(cam)
	cam.current = true
	## 海面(桌布)
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 60)
	sea.mesh = pm
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = _sh(SEA_SHADER)
	sea.material_override = sea_mat
	root3.add_child(sea)
	## 三块战场台
	for ln in ["top", "bottom", "final"]:
		isl[ln] = _make_island(ln, photo, theme_col)
	## 两个龟蛋大本营
	for side in ["left", "right"]:
		bases[side] = _make_base(side)
	## 路线: 大本营 → 上 / 下两路战场两侧; 两路战场 → 终极战场
	for side in ["left", "right"]:
		var bp: Vector3 = BASE_POS[side]
		var sx: float = -1.0 if side == "left" else 1.0
		var tc: Color = COL_BLUE if side == "left" else COL_RED
		for ln in ["top", "bottom"]:
			var lp: Vector3 = LANE_POS[ln]
			var a := bp + Vector3(-sx * 1.6, 0, -1.2 if ln == "top" else 1.2)
			var b := lp + Vector3(sx * (LANE_R[ln] + 0.5), 0, 0)
			var c := Vector3(a.x * 0.55 + b.x * 0.45, 0, b.z)
			paths.append(_make_path(a, c, b, tc))
	for ln in ["top", "bottom"]:
		var lp2: Vector3 = LANE_POS[ln]
		var dz: float = 1.0 if ln == "top" else -1.0
		var a2 := lp2 + Vector3(0, 0, dz * (LANE_R[ln] + 0.15))
		var b2: Vector3 = LANE_POS["final"] - Vector3(0, 0, dz * (LANE_R["final"] + 0.15))
		paths.append(_make_path(a2, a2.lerp(b2, 0.5), b2, COL_GOLD))
	view = TextureRect.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.add_child(sv)
	view.texture = sv.get_texture()
	return view


func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m


func _glow_mat(col: Color, ring: bool, inner: float = 0.42) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _sh(GLOW_SHADER)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("ring", 1.0 if ring else 0.0)
	m.set_shader_parameter("inner", inner)
	m.set_shader_parameter("a", 0.0)
	return m


func _make_island(ln: String, photo: Texture2D, theme_col: Color) -> Dictionary:
	var r: float = LANE_R[ln]
	var p: Vector3 = LANE_POS[ln]
	var n := Node3D.new()
	n.position = p
	root3.add_child(n)
	## 台身(八棱柱: 像素风下棱角比圆柱好看), 上窄下宽
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r * 1.08
	cm.height = 0.6
	cm.radial_segments = 8
	cm.rings = 1
	body.mesh = cm
	body.position.y = 0.0
	body.material_override = _mat(Color(0.20, 0.22, 0.27))
	n.add_child(body)
	## 台沿(终极战场金, 其余铜)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = r + 0.12
	rm.bottom_radius = r + 0.12
	rm.height = 0.1
	rm.radial_segments = 8
	rim.mesh = rm
	rim.position.y = TOP_Y - 0.06
	var rim_mat := _mat(Color(0.86, 0.66, 0.24) if ln == "final" else Color(0.55, 0.42, 0.30))
	rim.material_override = rim_mat
	n.add_child(rim)
	## 台面: 场地照片
	var top := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(r * 2.0, r * 2.0)
	top.mesh = tm
	top.position.y = TOP_Y + 0.005
	var top_mat := ShaderMaterial.new()
	top_mat.shader = _sh(TOP_SHADER)
	top_mat.set_shader_parameter("has_photo", 1.0 if photo != null else 0.0)
	if photo != null:
		top_mat.set_shader_parameter("photo", photo)
	top_mat.set_shader_parameter("base_col", theme_col)
	top.material_override = top_mat
	n.add_child(top)
	## 本路金圈(呼吸) / 胜方色圈
	var glow := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(r * 2.0 + 1.2, r * 2.0 + 1.2)
	glow.mesh = gm
	glow.position.y = TOP_Y + 0.02
	var glow_mat := _glow_mat(COL_GOLD, true, 0.40)
	glow.material_override = glow_mat
	n.add_child(glow)
	var d := {"node": n, "top_mat": top_mat, "rim_mat": rim_mat, "glow_mat": glow_mat, "slash": [], "flag": null}
	## 终极战场: 光柱(亮起来时用)
	if ln == "final":
		var pil := MeshInstance3D.new()
		var pcm := CylinderMesh.new()
		pcm.top_radius = r * 0.85
		pcm.bottom_radius = r * 0.95
		pcm.height = 3.2
		pcm.cap_top = false
		pcm.cap_bottom = false
		pcm.radial_segments = 16
		pil.mesh = pcm
		pil.position.y = TOP_Y + 1.6
		var pmat := _glow_mat(Color(1.0, 0.86, 0.42), false)
		pil.material_override = pmat
		n.add_child(pil)
		d["pillar_mat"] = pmat
		## 外扩光环(亮起那一下从台沿往外推一圈)
		var wave := MeshInstance3D.new()
		var wm := PlaneMesh.new()
		wm.size = Vector2(r * 2.0, r * 2.0)
		wave.mesh = wm
		wave.position.y = TOP_Y + 0.03
		var wmat := _glow_mat(Color(1.0, 0.9, 0.5), true, 0.44)
		wave.material_override = wmat
		n.add_child(wave)
		d["wave"] = wave
		d["wave_mat"] = wmat
		## 亮起来时从台沿往上升的金色光点(位置由调用方按时刻摆)
		var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 0.93, 0.6, 1.0))
		img.set_pixel(0, 0, Color(0, 0, 0, 0)); img.set_pixel(2, 0, Color(0, 0, 0, 0)); img.set_pixel(0, 2, Color(0, 0, 0, 0)); img.set_pixel(2, 2, Color(0, 0, 0, 0))
		var spk_tex := ImageTexture.create_from_image(img)
		var spk: Array = []
		for i in 18:
			var sp := Sprite3D.new()
			sp.texture = spk_tex
			sp.pixel_size = 0.06
			sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sp.shaded = false
			sp.transparent = true
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
			sp.modulate = Color(1, 1, 1, 0)
			n.add_child(sp)
			spk.append(sp)
		d["sparks"] = spk
	## 打叉的两刀(平躺在台面上, 交叉 ±40°)
	for k in 2:
		var sl := MeshInstance3D.new()
		var sm := PlaneMesh.new()
		sm.size = Vector2(r * 2.3, 0.42)
		sl.mesh = sm
		sl.position.y = TOP_Y + 0.04
		sl.rotation.y = deg_to_rad(40.0 if k == 0 else -40.0)
		var smat := ShaderMaterial.new()
		smat.shader = _sh(SLASH_SHADER)
		smat.set_shader_parameter("prog", 0.0)
		sl.material_override = smat
		n.add_child(sl)
		(d["slash"] as Array).append(smat)
	return d


func _make_base(side: String) -> Dictionary:
	var n := Node3D.new()
	n.position = BASE_POS[side]
	root3.add_child(n)
	var tc: Color = COL_BLUE if side == "left" else COL_RED
	var plat := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.3
	cm.bottom_radius = 1.45
	cm.height = 0.5
	cm.radial_segments = 8
	plat.mesh = cm
	plat.material_override = _mat(Color(0.22, 0.24, 0.29))
	n.add_child(plat)
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.38
	rm.bottom_radius = 1.38
	rm.height = 0.1
	rm.radial_segments = 8
	rim.mesh = rm
	rim.position.y = 0.22
	rim.material_override = _mat(tc.darkened(0.15))
	n.add_child(rim)
	var egg_tex: Texture2D = load("res://assets/sprites/pets/egg.png") if ResourceLoader.exists("res://assets/sprites/pets/egg.png") else null
	var egg := Sprite3D.new()
	if egg_tex != null:
		egg.texture = egg_tex
		egg.hframes = 3
		egg.frame = 0
		egg.pixel_size = 1.9 / float(egg_tex.get_height())
		egg.offset.y = float(egg_tex.get_height()) * 0.5
	egg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	egg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	egg.shaded = false
	egg.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	egg.position.y = 0.25
	n.add_child(egg)
	return {"node": n, "egg": egg}


## 虚线路(平躺在桌面上的一条带子): UV.x 是沿路的参数, 着色器按 prog 画出来、按 UV.x 切成虚线
const PATH_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform float prog = 0.0;
uniform float dashes = 30.0;
void fragment() {
	if (UV.x > prog || fract(UV.x * dashes) > 0.55) { discard; }
	ALBEDO = col.rgb;
}
"""


func _make_path(a: Vector3, c: Vector3, b: Vector3, col: Color) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	var w := 0.12
	var pts: Array = []
	for i in n + 1:
		var u := float(i) / float(n)
		pts.append(a.lerp(c, u).lerp(c.lerp(b, u), u))
	var length := 0.0
	for i in range(1, pts.size()):
		length += (pts[i] as Vector3).distance_to(pts[i - 1])
	for i in n:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[i + 1]
		var dir := (p1 - p0).normalized()
		var side := Vector3(-dir.z, 0, dir.x) * w
		var u0 := float(i) / float(n)
		var u1 := float(i + 1) / float(n)
		var y := 0.03
		var v := [p0 - side + Vector3(0, y, 0), p0 + side + Vector3(0, y, 0), p1 + side + Vector3(0, y, 0), p1 - side + Vector3(0, y, 0)]
		var uv := [Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[k])
			st.add_vertex(v[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = _sh(PATH_SHADER)
	mat.set_shader_parameter("col", col)
	mat.set_shader_parameter("dashes", maxf(6.0, length / 0.45))
	mi.material_override = mat
	root3.add_child(mi)
	return {"mi": mi, "mat": mat}


## 立牌: 一只单位的全身像(待机帧表第 0 帧起), 脚踩台面。sd = 战斗里同一个立绘字典(tex / hframes / vframes / frames / fps)。
func add_standee(sd: Dictionary, lane: String, side: String, pos: Vector3) -> Dictionary:
	var spr := Sprite3D.new()
	var tex: Texture2D = sd.get("tex") as Texture2D
	var frames: int = 1
	var fps: float = 8.0
	if tex != null:
		var hf: int = maxi(1, int(sd.get("hframes", 1)))
		var vf: int = maxi(1, int(sd.get("vframes", 1)))
		spr.texture = tex
		spr.hframes = hf
		spr.vframes = vf
		spr.frame = 0
		frames = maxi(1, int(sd.get("frames", 1)))
		fps = float(sd.get("fps", 8.0))
		var fw: int = int(tex.get_width() / hf)
		var fh: int = int(tex.get_height() / vf)
		var used: Vector2 = _used_rows(tex, fw, fh)
		var content_px: float = maxf(8.0, (used.y - used.x) * float(fh))
		spr.pixel_size = UNIT_H / content_px
		## 脚(不透明像素的下沿)落在原点: 居中时帧中心在原点 ⇒ 往上挪「下沿到中心」那段
		spr.offset.y = used.y * float(fh) - float(fh) * 0.5
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.flip_h = side == "right"
	spr.position = pos
	root3.add_child(spr)
	## 脚下小影子
	var sh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.9, 0.45)
	sh.mesh = pm
	sh.position = Vector3(0, 0.01, 0)
	var sm := _mat(Color(0, 0, 0, 0.45))
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh.material_override = sm
	spr.add_child(sh)
	var d := {"spr": spr, "lane": lane, "side": side, "frames": frames, "fps": fps, "home": pos}
	standees.append(d)
	return d


## 第 0 帧不透明区域的上 / 下沿(比例); 量不到 ⇒ (0, 1)
func _used_rows(tex: Texture2D, fw: int, fh: int) -> Vector2:
	var key := "%s|%d|%d" % [tex.resource_path, fw, fh]
	if _used_cache.has(key):
		return _used_cache[key]
	var out := Vector2(0.0, 1.0)
	var img: Image = tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var ur: Rect2i = img.get_region(Rect2i(0, 0, mini(fw, img.get_width()), mini(fh, img.get_height()))).get_used_rect()
		if ur.size.y > 0:
			out = Vector2(float(ur.position.y) / float(fh), float(ur.end.y) / float(fh))
	_used_cache[key] = out
	return out


## 某一路某一侧第 idx 只的站位(台面上, 左方站左半、右方站右半, 面对面三只一排略错开)
static func squad_pos(lane: String, side: String, idx: int, n: int) -> Vector3:
	var c: Vector3 = LANE_POS[lane]
	var sx: float = -1.0 if side == "left" else 1.0
	if lane != "final" and n <= 3:
		## 三只一组的楔形: 一只顶在前面(靠中线), 两只在后面一前一后错开 —— 斜俯视下三只不互相挡, 一眼数得出「三只」
		var wedge: Array = [Vector2(0.75, 0.15), Vector2(1.55, -0.85), Vector2(1.75, 0.95)]
		var w: Vector2 = wedge[mini(idx, 2)]
		return c + Vector3(sx * w.x, TOP_Y, w.y)
	## 终极战场(两路幸存 + 援军, 一侧最多 7 只): 两排, 每排最多 4 只
	var per_row := 4
	var row := idx / per_row
	var col := idx % per_row
	var rows := int(ceil(float(maxi(1, n)) / float(per_row)))
	var x: float = sx * (0.7 + float(col) * 0.62)
	var z: float = (float(row) - float(rows - 1) * 0.5) * 1.3 + (0.25 if col % 2 == 1 else -0.15)
	return c + Vector3(x, TOP_Y, z)


## 镜头: 位置 + 看向。总览位按屏幕宽高比后退, 保证两端大本营都在画面里(iPad 4:3 要退得更远)。
func set_cam(pos: Vector3, look: Vector3) -> void:
	if cam == null:
		return
	cam.position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)


## 总览位: 俯角约 57°, 距离取「左右装得下两端大本营」与「上下装得下上 / 下两块台子 + 路名」两者里更远的那个
func overview_cam() -> Array:
	var aspect: float = vp.x / maxf(1.0, vp.y)
	var tan_v: float = tan(deg_to_rad(FOV * 0.5))
	var dir := Vector3(0, 16.0, 10.5).normalized()
	var pitch: float = asin(dir.y)
	var half_w := 15.0
	var half_d := 12.6                      # 上路台子后沿 / 盾徽到下路路名前沿的一半(米)
	var dist_w: float = half_w / (tan_v * aspect)
	var dist_h: float = (half_d * sin(pitch) + 1.2) / tan_v
	var dist: float = maxf(dist_w, dist_h)
	var look := Vector3(0, 0, 1.4)
	return [look + dir * dist, look]


func high_cam() -> Array:
	var ov := overview_cam()
	var look: Vector3 = ov[1]
	return [look + Vector3(0, ((ov[0] as Vector3) - look).length() * 1.15, 3.0), look]


## 飞进某一路: 先到台子斜上方(看得见三对三), 再贴近台面(场地照片铺满)
func lane_cam(lane: String, close: bool) -> Array:
	var c: Vector3 = LANE_POS[lane]
	if close:
		return [c + Vector3(0, 3.7, 5.0), c + Vector3(0, TOP_Y + 0.9, 0)]
	return [c + Vector3(0, 6.4, 7.6), c + Vector3(0, TOP_Y + 0.5, 0)]


## 3D 点 → 屏幕坐标(全屏像素)。SubViewport 是半分辨率, 换算回整屏。
func project(p: Vector3) -> Vector2:
	if cam == null or not cam.is_inside_tree():
		return Vector2(-9999, -9999)
	var s: Vector2 = cam.unproject_position(p)
	return s * (vp / Vector2(sv.size))


func is_behind(p: Vector3) -> bool:
	return cam == null or not cam.is_inside_tree() or cam.is_position_behind(p)
