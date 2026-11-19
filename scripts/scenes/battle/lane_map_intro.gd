extends RefCounted
## lane_map_intro.gd — 换路幕布三段演出: 开场「战场地图」/ 对阵 / 一路战果(方案书 docs/plans/20261115d-三路战场地图开场.md)。
##
## 用户 11-15:「你说三路开战这个，这个这种描述其实不符合一种商业游戏啊…上路战场、下路战场、中级战场，
##   是否可以通过一个那个？地图一样的形式去展现出来，就是做多做点动画啥的…你可以设计一下。」
##
## ★只管画面: 幕布什么时候出、什么时候走(5 秒 / 回放只认录像那一下)仍由 dual_lane_flow 管, 这里一行不碰。
## ★幕布上不写「点击继续」(用户 11-15「全程在服务器上运行，那应该没有说用户可以点击的东西」); 点击处理还在 dual_lane_flow(本机跑的教程用)。
## ★动画不用 tween: build 时登记一张「轨道表」, `pose(t)` 按时刻把全部节点摆好(同 finals_vs_intro) ——
##   门禁能摆到任意时刻去量, 无头 CI 不靠 tween 推进(CLAUDE.md §4.5)。t 由幕布下挂的 Clock 按帧累加(回放乘播放倍速)。
## ★动画只动 scale / modulate / position, 不动 visible: 直播一致性门禁按「可见节点」数文本, 两边同一份节点就同一份数。
## ★节点不起名(引用存在字典里): 文本的「锚」= 最近一个有名字的祖先 = PresentPanel(verify_stream_hud_parity 按它比列头)。
##   只有门禁按名字找的几个 Label 起名(LaneSettleResult / LaneSettleRecord / LaneSettleEggs)。

const DUR := 5.0
## 设计画布(按屏幕等比缩放居中; 背景另铺满全屏)
const CW := 1200.0
const TITLE_PX_S := 24
const TITLE_PX_L := 36
const CH := 720.0
const AV := 52.0
## 地图幕顶上留一条: 场地名牌 + 战果幕的比分 / 蛋血两行(不压上路圆章)
const TOPBAND := 64.0

const COL_BLUE := Color("#5b9cf0")
const COL_RED := Color("#ef5b66")
const COL_GOLD := Color("#ffd93d")
const COL_TEXT := Color("#e8f0f6")
const COL_SUB := Color("#9fb3c8")
const COL_WIN := Color("#9ae6b0")
const COL_LOSE := Color("#ff9b9b")

const LANE_ART := {"top": "res://assets/sprites/finals/bt-lane-top.png", "bottom": "res://assets/sprites/finals/bt-lane-bottom.png",
	"final": "res://assets/sprites/finals/bt-lane-final.png"}
const KAIZHAN := "res://assets/sprites/finals/bt-kaizhan.png"
## VS 盾徽: 龟甲纹盾面(用户 11-15「这个盾面一定要说这两种颜色吗？还是说你可以设计一种什么图标呢？」——
##   背景两条斜带已经在说蓝对红, 盾面再分红蓝是重复; 中间这枚是这个游戏自己的标志 ⇒ 琥珀色龟甲, 不偏任何一方)。
##   tools/assetgen/build_vs_crest_shell.py 由决赛日那枚 vs-crest.png 改盾面(铜边 / 铆钉 / 交叉剑原样)。地图上「本路」那枚同一个。
const CREST := "res://assets/sprites/finals/vs-crest-shell.png"
const PHOTO_META := "_lane_map_photo"
## 幕布底板上挂着本实例(dual_lane_flow 换幕时问闪白到哪了, 见 flash_alpha_of)
const INTRO_META := "_lane_map_intro"
const WarTable := preload("res://scripts/scenes/battle/lane_war_table.gd")

const SEA_SHADER := """
shader_type canvas_item;
uniform vec4 c_top : source_color = vec4(0.055, 0.12, 0.20, 1.0);
uniform vec4 c_bot : source_color = vec4(0.02, 0.05, 0.10, 1.0);
uniform vec4 c_grid : source_color = vec4(0.16, 0.28, 0.40, 1.0);
uniform vec4 c_glint : source_color = vec4(0.55, 0.80, 0.92, 1.0);
uniform vec2 rect_size = vec2(1560.0, 720.0);
uniform float px = 3.0;
uniform float cell = 48.0;
uniform float t = 0.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 sp = floor(UV * rect_size / px) * px;
	vec4 col = mix(c_top, c_bot, UV.y);
	vec2 d = UV - 0.5;
	col.rgb *= 1.0 - dot(d, d) * 1.1;
	vec2 g = mod(sp, cell);
	if (g.x < px || g.y < px) { col.rgb = mix(col.rgb, c_grid.rgb, 0.28); }
	vec2 wsz = vec2(42.0, 27.0);
	vec2 wc = floor(sp / wsz);
	float r = h(wc);
	if (r > 0.80) {
		vec2 lp = mod(sp, wsz);
		float ph = fract(t * 0.30 + r * 7.0);
		float drift = floor(ph * 5.0) * px;
		float on = step(ph, 0.75);
		if (lp.y >= 12.0 && lp.y < 12.0 + px && lp.x >= 6.0 + drift && lp.x < 6.0 + drift + 4.0 * px) {
			col.rgb = mix(col.rgb, c_glint.rgb, 0.45 * on);
		}
	}
	// 深浅水斑: 两层低频值噪声, 量化成 4 档(像素画不要平滑渐变), 慢慢漂
	vec2 q = sp / 220.0 + vec2(t * 0.012, t * 0.006);
	vec2 i0 = floor(q);
	vec2 f0 = fract(q);
	f0 = f0 * f0 * (3.0 - 2.0 * f0);
	float n = mix(mix(h(i0), h(i0 + vec2(1.0, 0.0)), f0.x), mix(h(i0 + vec2(0.0, 1.0)), h(i0 + vec2(1.0, 1.0)), f0.x), f0.y);
	float sh = floor(clamp((n - 0.45) * 3.0, 0.0, 1.0) * 3.0) / 3.0;
	col.rgb = mix(col.rgb, col.rgb * 1.55 + vec3(0.0, 0.025, 0.035), sh * 0.55);
	// 雾带: 横向拉长的噪声, 往右慢漂, 只在暗处提一点亮
	vec2 qf = vec2(sp.x / 520.0 - t * 0.02, sp.y / 140.0);
	vec2 i1 = floor(qf);
	vec2 f1 = fract(qf);
	f1 = f1 * f1 * (3.0 - 2.0 * f1);
	float fog = mix(mix(h(i1 + 7.0), h(i1 + vec2(8.0, 7.0)), f1.x), mix(h(i1 + vec2(7.0, 8.0)), h(i1 + vec2(8.0, 8.0)), f1.x), f1.y);
	col.rgb += vec3(0.05, 0.07, 0.09) * floor(clamp((fog - 0.55) * 4.0, 0.0, 1.0) * 2.0) / 2.0;
	COLOR = vec4(col.rgb, 1.0);
}
"""


## 立绘待机换帧: AtlasTexture 的区域固定在第 0 帧, 采样时按 UV 平移到第 N 帧。
## ★顶点色要在 vertex() 里单独取: Godot 4 的 canvas 片段着色器里 COLOR 进来时已经乘过一次贴图色,
##   再乘一次贴图 = 颜色平方 ⇒ 整个人发黑(用户 11-15「这个 PK 界面，这个角色怎么很黑呀」)。
const BODY_SHADER := """
shader_type canvas_item;
uniform vec2 shift = vec2(0.0);
varying vec4 vcol;
void vertex() {
	vcol = COLOR;
}
void fragment() {
	COLOR = texture(TEXTURE, UV + shift) * vcol;
}
"""

static var _body_sh: Shader = null
## 立绘第 0 帧里不透明像素的上 / 下沿(占帧高的比例), 按贴图路径缓存 —— 帧图底下常留透明边, 不量就会「脚踩不到影子」
static var _used_cache: Dictionary = {}
static var _sea_sh: Shader = null

var battle
var flow
var mode := ""
## overview: 即将开打的那一路; preview: 本路; lane_settle: 刚打完的那一路
var lane := "top"
var next_lane := ""
var me_lr := "left"
var t := 0.0
var root: Control = null          # = PresentPanel
var map: Control = null           # 对阵屏的设计画布(1200×720 等比缩放居中)
var vp := Vector2(1560, 720)
var base_s := 1.0
var base_p := Vector2.ZERO
var tracks: Array = []            # [{k, node, t0, dur, ...}]
var sea_mat: ShaderMaterial = null
var zoom: Dictionary = {}         # {"in": [t0, t1](推近那一段, 闪白跟它走), "flash": ColorRect, "flash_in": 对阵幕开头褪白}
var anim_frames: Array = []       # [{node: TextureRect, tex, fw, fh, hf, frames, fps}]
var table = null                  # 桌面作战地图(lane_war_table.gd), 开场 / 战果两幕用
var anchors: Array = []           # 2D 字跟着 3D 点走: [{node, p, off}]
var cam_segs: Array = []          # 镜头分段: [t0, t1, [pos, look], [pos, look]]


func _init(b, f) -> void:
	battle = b
	flow = f


# ══════════════════════════════════════════════════════════════════════
#  入口: dual_lane_flow._dl_build_present_overlay 建好不透明底板 `back` 之后调
# ══════════════════════════════════════════════════════════════════════
func build(back: Control, mode_: String, inset_bottom: float) -> Control:
	mode = mode_
	me_lr = ReplayRecorder.my_side(battle)
	var gs = battle.get_node_or_null("/root/GameState")
	var cur: String = str(gs.current_lane) if gs != null else "top"
	lane = cur if cur in ["top", "bottom", "final"] else "top"
	next_lane = "bottom" if lane == "top" else ("final" if lane == "bottom" else "")
	vp = battle.get_viewport().get_visible_rect().size
	root = Control.new()
	root.name = "PresentPanel"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(root)
	_add_sea()
	map = Control.new()
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.size = Vector2(CW, CH)
	var band: float = 0.0 if mode == "preview" else TOPBAND
	base_s = minf(vp.x / CW, (vp.y - inset_bottom - band) / CH)
	base_p = Vector2((vp.x - CW * base_s) * 0.5, band + (vp.y - inset_bottom - band - CH * base_s) * 0.5)
	root.add_child(map)
	match mode:
		"overview":
			_build_table(false)
		"lane_settle":
			_build_table(true)
		_:
			_build_vs()
	var clk := Clock.new()
	clk.intro = self
	back.add_child(clk)
	back.set_meta(INTRO_META, self)
	pose(0.0)
	return root


## 这块幕布此刻闪白层的不透明度(不是本演出的幕布 / 没有闪白层 = 0)。
## dual_lane_flow 换幕时看它: 旧幕停在闪白上 ⇒ 硬切, 不交叉淡化(见 dual_lane_flow.FLASH_CUT_MIN)。
static func flash_alpha_of(back: Node) -> float:
	if back == null or not is_instance_valid(back) or not back.has_meta(INTRO_META):
		return 0.0
	var it = back.get_meta(INTRO_META)
	if it == null or not (it.zoom as Dictionary).has("flash"):
		return 0.0
	var fl = it.zoom["flash"]
	return (fl as ColorRect).modulate.a if is_instance_valid(fl) else 0.0


func tick(dt: float) -> void:
	var sp := 1.0
	if battle != null and battle._replay != null and battle._replay.is_playing():
		sp = maxf(0.25, float(battle._replay.speed))
	pose(t + dt * sp)


# ══════════════════════════════════════════════════════════════════════
#  背景 / 小部件
# ══════════════════════════════════════════════════════════════════════
func _add_sea() -> void:
	if _sea_sh == null:
		_sea_sh = Shader.new()
		_sea_sh.code = SEA_SHADER
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = _sea_sh
	sea_mat.set_shader_parameter("rect_size", vp)
	bg.material = sea_mat
	root.add_child(bg)


func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _trect(tex: Texture2D, sz: Vector2, parent: Control, center: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size = sz
	tr.pivot_offset = sz * 0.5
	tr.position = center - sz * 0.5
	parent.add_child(tr)
	return tr


func _label(txt: String, fs: int, col: Color, parent: Control, center: Vector2, title: bool = false, nm: String = "") -> Label:
	var l := Label.new()
	if nm != "":
		l.name = nm
	l.text = txt
	if title:
		## 像素标题字只有 12 的倍数是整像素(verify_title_font ③): 两档, 写成常量
		if fs >= TITLE_PX_L:
			UISkin.title_label(l, TITLE_PX_L)
		else:
			UISkin.title_label(l, TITLE_PX_S)
	else:
		l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 1.0))
	l.add_theme_constant_override("outline_size", maxi(4, fs / 5))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := Vector2(maxf(60.0, float(txt.length()) * fs * 1.05 + 24.0), fs * 1.6)
	l.size = sz
	l.pivot_offset = sz * 0.5
	l.position = center - sz * 0.5
	parent.add_child(l)
	return l






## 圆章里的场地照片: 开局第一次建幕布时用一个只渲一次的 SubViewport 共享主世界、按战斗镜头拍一张, 存在战斗场上三章共用。
## 拍不到(无头 / 没镜头)⇒ null, 圆章用纯色兜底。
func photo() -> Texture2D:
	if battle.has_meta(PHOTO_META):
		var v = battle.get_meta(PHOTO_META)
		if is_instance_valid(v) and v is SubViewport:
			return (v as SubViewport).get_texture()
	if DisplayServer.get_name() == "headless":
		return null
	var cam = battle.get("_cam")
	if cam == null or not is_instance_valid(cam) or not (cam as Node).is_inside_tree():
		return null
	var sv := SubViewport.new()
	sv.name = "LaneMapPhoto"
	sv.size = Vector2i(640, 360)
	sv.world_3d = battle.get_viewport().world_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.transparent_bg = false
	var c3 := Camera3D.new()
	c3.projection = (cam as Camera3D).projection
	c3.fov = (cam as Camera3D).fov
	c3.size = (cam as Camera3D).size
	c3.near = (cam as Camera3D).near
	c3.far = (cam as Camera3D).far
	c3.keep_aspect = (cam as Camera3D).keep_aspect
	sv.add_child(c3)
	battle.add_child(sv)
	c3.global_transform = (cam as Camera3D).global_transform
	c3.current = true
	battle.set_meta(PHOTO_META, sv)
	return sv.get_texture()






# ══════════════════════════════════════════════════════════════════════
#  轨道表
# ══════════════════════════════════════════════════════════════════════
func _pop(node: CanvasItem, t0: float, dur: float = 0.34) -> void:
	tracks.append({"k": "pop", "node": node, "t0": t0, "dur": dur})


func _fade(node: CanvasItem, t0: float, dur: float, a0: float = 0.0, a1: float = 1.0) -> void:
	tracks.append({"k": "fade", "node": node, "t0": t0, "dur": dur, "a0": a0, "a1": a1})


func _slide(node: Control, from: Vector2, to: Vector2, t0: float, dur: float, back_ease: bool = true) -> void:
	tracks.append({"k": "slide", "node": node, "from": from, "to": to, "t0": t0, "dur": dur, "back": back_ease})






func _slam(node: Control, t0: float, from_scale: float = 2.6, dur: float = 0.18) -> void:
	tracks.append({"k": "slam", "node": node, "t0": t0, "dur": dur, "s0": from_scale})


## 到点响一声(只响一次; 摆回更早的时刻不重响)。用游戏里现成的公共声(没有为这几拍新做声音, 见方案书 R9)。
## ★裁判机(在录直播)不响: 手机看直播时幕布是自己按事件建的, 这几声由手机自己的这套轨道响; 录进流里就会响两遍。
func _sfx(name: String, t0: float, vol: float = 1.0, pitch: float = 1.0) -> void:
	tracks.append({"k": "sfx", "node": root, "t0": t0, "dur": 0.0, "name": name, "vol": vol, "pitch": pitch, "fired": false})




static func _ease_in_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func pose(tt: float) -> void:
	t = tt
	if sea_mat != null:
		sea_mat.set_shader_parameter("t", t)
	for tr in tracks:
		var node = tr["node"]
		if node == null or not is_instance_valid(node):
			continue
		var x: float = (t - float(tr["t0"])) / maxf(0.001, float(tr.get("dur", 1.0)))
		match str(tr["k"]):
			"pop":
				var k := clampf(x, 0.0, 1.0)
				(node as CanvasItem).modulate.a = clampf(x * 2.5, 0.0, 1.0)
				(node as Control).scale = Vector2.ONE * (ChampionUi.ease_back(k) if k > 0.0 else 0.01)
			"fade":
				(node as CanvasItem).modulate.a = lerpf(float(tr["a0"]), float(tr["a1"]), ChampionUi.ease_out(x))
			"slide":
				var e: float = ChampionUi.ease_back(x) if bool(tr["back"]) else ChampionUi.ease_out(x)
				(node as Control).position = (tr["from"] as Vector2).lerp(tr["to"], e)
				(node as CanvasItem).modulate.a = clampf(x * 3.0, 0.0, 1.0)
			"slam":
				var k3 := clampf(x, 0.0, 1.0)
				(node as CanvasItem).modulate.a = clampf(x * 4.0, 0.0, 1.0)
				(node as Control).scale = Vector2.ONE * lerpf(float(tr["s0"]), 1.0, ChampionUi.ease_out(k3)) if x > 0.0 else Vector2.ONE * float(tr["s0"])
			"sfx":
				if not bool(tr["fired"]) and t >= float(tr["t0"]) and t < float(tr["t0"]) + 0.5:
					tr["fired"] = true
					if StreamRecorder.cur == null:
						var au = battle.get_node_or_null("/root/Audio") if battle != null else null
						if au != null:
							au.play_sfx(str(tr["name"]), float(tr["vol"]), float(tr["pitch"]), 0.0, 0.0)
				elif t >= float(tr["t0"]) + 0.5:
					tr["fired"] = true
			"dust":
				(node as Dust).prog = clampf(x, 0.0, 1.0)
				(node as Dust).queue_redraw()
			"pop3":
				var kp := clampf(x, 0.0, 1.0)
				(node as Node3D).scale = Vector3.ONE * maxf(0.001, ChampionUi.ease_back(kp)) if x > 0.0 else Vector3.ONE * 0.001
			"drop3":
				var spr: Sprite3D = node
				spr.visible = x >= 0.0
				var kd := clampf(x, 0.0, 1.0)
				spr.position = (tr["to"] as Vector3) + Vector3(0, 2.2 * (1.0 - ChampionUi.ease_out(kd)) - (sin(kd * PI) * 0.0), 0)
			"hop3":
				var k3 := _ease_in_out(x)
				var p3: Vector3 = (tr["from"] as Vector3).lerp(tr["to"], k3)
				p3.y += sin(PI * clampf(x, 0.0, 1.0)) * float(tr["h"])
				(node as Sprite3D).position = p3
			"grey3":
				(node as Sprite3D).modulate = Color.WHITE.lerp(Color(0.42, 0.42, 0.48), ChampionUi.ease_out(x))
			"path3":
				(node as ShaderMaterial).set_shader_parameter("prog", clampf(x, 0.0, 1.0))
			"pulse3":
				var w3 := 0.5 + 0.5 * sin((t - float(tr["t0"])) * TAU * 0.9)
				(node as ShaderMaterial).set_shader_parameter("a", 0.0 if t < float(tr["t0"]) else clampf((t - float(tr["t0"])) * 4.0, 0.0, 1.0) * (0.45 + 0.55 * w3))
			"fade3":
				(node as ShaderMaterial).set_shader_parameter("a", float(tr["a1"]) * (ChampionUi.ease_out(x) if float(tr["dur"]) > 0.0 else 1.0))
			"slash3":
				(node as ShaderMaterial).set_shader_parameter("prog", (ChampionUi.ease_out(x) if float(tr["dur"]) > 0.0 else 1.0) if x >= 0.0 or float(tr["dur"]) <= 0.0 else 0.0)
			"dim3":
				(node as ShaderMaterial).set_shader_parameter("dim", 0.42 * (ChampionUi.ease_out(x) if float(tr["dur"]) > 0.0 else 1.0))
			"tint3":
				var tc3: Color = tr["col"]
				(node as ShaderMaterial).set_shader_parameter("tint", Color(tc3.r, tc3.g, tc3.b, 0.30 * (ChampionUi.ease_out(x) if float(tr["dur"]) > 0.0 else 1.0)))
			"lit3":
				var dl: Dictionary = tr["d"]
				var kl := ChampionUi.ease_out(x)
				(dl["top_mat"] as ShaderMaterial).set_shader_parameter("lit", kl)
				## 镜头开始推近(3.7 秒)起光柱淡掉: 贴近看一圈半透明的柱壁像个罐子罩在台子上
				var k_dive: float = 1.0 - clampf((t - 3.7) / 0.5, 0.0, 1.0)
				(dl["pillar_mat"] as ShaderMaterial).set_shader_parameter("a", 0.28 * kl * k_dive * (0.85 + 0.15 * sin(t * 6.0)))
				## 金色光点: 绕台沿一圈、各自错开相位往上升、到顶淡出(按时刻算, 不随机)
				var spk: Array = dl["sparks"]
				var rr: float = float(WarTable.LANE_R["final"])
				for si in spk.size():
					var sp3: Sprite3D = spk[si]
					var ph: float = fposmod((t - float(tr["t0"])) * 0.55 + float(si) / float(spk.size()) * 1.7, 1.0)
					var ang: float = float(si) * 2.39996
					var rad: float = rr * (0.92 + 0.12 * float(si % 3) / 2.0)
					sp3.position = Vector3(cos(ang) * rad, WarTable.TOP_Y + 0.1 + ph * 2.6, sin(ang) * rad)
					sp3.modulate = Color(1, 1, 1, kl * (1.0 - ph) * (0.6 + 0.4 * float(si % 2)))
				(dl["node"] as Node3D).position.y = 0.35 * ChampionUi.ease_back(clampf(x, 0.0, 1.0)) if x > 0.0 else 0.0   # 台子微微升起
				## 外扩光环: 0.6 秒从台沿推到 1.8 倍并淡出
				var kw: float = clampf((t - float(tr["t0"])) / 0.6, 0.0, 1.0)
				(dl["wave"] as Node3D).scale = Vector3.ONE * lerpf(1.0, 1.8, ChampionUi.ease_out(kw))
				(dl["wave_mat"] as ShaderMaterial).set_shader_parameter("a", (1.0 - kw) * 1.2 if x > 0.0 else 0.0)
				(dl["rim_mat"] as StandardMaterial3D).albedo_color = Color(0.86, 0.66, 0.24).lerp(Color(1.0, 0.92, 0.55), kl)
			"bands":
				(node as Bands).prog = ChampionUi.ease_out(x)
				(node as Bands).queue_redraw()
	for af in anim_frames:
		var tr2: TextureRect = af["node"]
		if not is_instance_valid(tr2):
			continue
		var fi: int = int(floor(t * float(af["fps"]))) % maxi(1, int(af["frames"]))
		var hf: int = maxi(1, int(af["hf"]))
		(af["mat"] as ShaderMaterial).set_shader_parameter("shift", Vector2(float(fi % hf) * float(af["fw"]), float(fi / hf) * float(af["fh"])))
	_pose_zoom()
	_pose_table()
	## 屏震(VS 盾徽砸下那一下): 叠在推近之后, 按时刻算(不随机 ⇒ 门禁摆到哪一刻都一样)
	for tr3 in tracks:
		if str(tr3["k"]) == "shake":
			var xs: float = (t - float(tr3["t0"])) / float(tr3["dur"])
			if xs > 0.0 and xs < 1.0:
				var amp: float = 7.0 * (1.0 - xs)
				map.position += Vector2(sin(xs * 47.0) * amp, cos(xs * 39.0) * amp * 0.6)


## 对阵屏的画布摆回基准位置(等比缩放居中) + 闪白层: 地图幕 = 镜头推近末尾闪起来(接对阵屏); 对阵幕 = 开头从白褪掉
func _pose_zoom() -> void:
	if map == null:
		return
	map.scale = Vector2.ONE * base_s
	map.position = base_p
	if zoom.has("flash"):
		var fl: ColorRect = zoom["flash"]
		if is_instance_valid(fl):
			var zi2: Array = zoom.get("in", [99.0, 99.0])
			var a := 0.72 * clampf((t - (float(zi2[1]) - 0.2)) / 0.2, 0.0, 1.0)
			if zoom.has("flash_in"):
				a = maxf(a, 0.72 * (1.0 - clampf(t / 0.25, 0.0, 1.0)))
			fl.modulate.a = a


func _side_specs(ln: String, side_lr: String) -> Array:
	if ln == "final":
		return []
	return flow._dl_lane_specs(ln) if side_lr == "left" else flow._dl_foe_specs(ln)








## 幸存者(此刻场上还活着的): 与 `_dl_snapshot_survivors` 同一个口径(有效阵营 / 非蛋 / 非召唤 / 非训龟大师)
func _alive_specs(side_lr: String) -> Array:
	var out: Array = []
	for u in battle._units:
		if not u.get("alive", false) or battle._eff_side(u) != side_lr:
			continue
		if u.get("_isEgg", false) or u.get("is_summon", false) or u.get("is_trainer", false):
			continue
		if u.get("_isMinion", false):
			out.append({"kind": "minion", "role": str(u.get("minion_role", "front")), "elite": bool(u.get("is_elite", false))})
		else:
			out.append({"kind": "leader", "id": str(u.get("id", ""))})
	return out


func _lane_winner(ln: String) -> String:
	var gs = battle.get_node_or_null("/root/GameState")
	if gs != null and gs.lane_results is Dictionary and (gs.lane_results as Dictionary).has(ln):
		return str(gs.lane_results[ln])
	if mode == "lane_settle" and ln == lane:
		return "right" if str(battle._dl_pending_loser) == "left" else "left"
	return ""




## 闪白层: 地图幕 = 推近末尾闪起来(接对阵屏); 对阵幕 = 开头从白褪掉
func _add_flash(at_start: bool) -> void:
	var fl := ColorRect.new()
	fl.color = Color(1.0, 0.97, 0.88, 1.0)
	fl.set_anchors_preset(Control.PRESET_FULL_RECT)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.modulate.a = 0.72 if at_start else 0.0
	root.add_child(fl)
	zoom["flash"] = fl
	if at_start:
		zoom["flash_in"] = true






# ══════════════════════════════════════════════════════════════════════
#  桌面作战地图(开场 / 一路战果) —— 第三轮(用户 11-15「在一个视角上面看到下面一张地图…把视角往里面挪动」)
# ══════════════════════════════════════════════════════════════════════
## 一只单位的立绘字典(战斗里同一个取法)
func _sd_of(spec) -> Dictionary:
	return _body(spec)


## 2D 字跟着 3D 点走(每帧按镜头投影摆; 点在镜头背后就藏)
func _anchor(node: Control, p: Vector3, off: Vector2 = Vector2.ZERO) -> void:
	anchors.append({"node": node, "p": p, "off": off})


func _cam_seg(t0: float, t1: float, a: Array, b: Array) -> void:
	cam_segs.append([t0, t1, a, b])


func _build_table(settle: bool) -> void:
	var hdr: Dictionary = flow._side_headers()
	var gs = battle.get_node_or_null("/root/GameState")
	var thc := Color(0.17, 0.24, 0.17)
	table = WarTable.new()
	var v: TextureRect = table.build(vp, photo(), thc)
	root.add_child(v)
	root.move_child(v, 1)   # 海图(2D 底)之上、地图画布之下
	var ov: Array = table.overview_cam()
	## ── 左上: 场地名牌 ──
	var th := str(ArenaTheme.cfg_of(ArenaTheme.active).get("label", ""))
	if th != "":
		var plate := PanelContainer.new()
		var psb := StyleBoxFlat.new()
		psb.bg_color = Color(0.04, 0.07, 0.11, 0.92)
		psb.set_border_width_all(2)
		psb.border_color = Color("#c9a24a")
		psb.content_margin_left = 16
		psb.content_margin_right = 16
		psb.content_margin_top = 2
		psb.content_margin_bottom = 2
		plate.add_theme_stylebox_override("panel", psb)
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pl := Label.new()
		pl.text = th
		UISkin.title_label(pl, 24)
		pl.add_theme_color_override("font_color", COL_GOLD)
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(pl)
		root.add_child(plate)
		plate.position = Vector2(18, 12)
		_slide(plate, plate.position - Vector2(200, 0), plate.position, 0.0, 0.4, false)
	## ── 大本营: 名字(我方绿 / 对方红) + 蛋血条 ──
	for side_lr in ["left", "right"]:
		var bp: Vector3 = WarTable.BASE_POS[side_lr]
		var nm := _label(str(hdr["l"] if side_lr == "left" else hdr["r"]), 22, COL_WIN if side_lr == me_lr else COL_LOSE, root, Vector2.ZERO)
		_anchor(nm, bp + Vector3(0, 2.75, 0))
		_fade(nm, 0.35 if not settle else 0.0, 0.25)
		var lv_l: int = maxi(1, int(gs.season_level)) if gs != null and gs.season_level != null else 1
		var mx: float = maxf(1.0, flow.egg_max_for(lv_l if side_lr == "left" else flow._dl_foe_level(lv_l)))
		var raw_hp: float = float((gs.egg_hp as Dictionary).get(side_lr, 0.0)) if gs != null and gs.egg_hp is Dictionary else 0.0
		var cur_hp: float = mx if raw_hp <= 0.0 else minf(mx, raw_hp)   # 开场那一刻还没写蛋血(建场时才写)⇒ 满血
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.02, 0.03, 0.05, 0.9)
		bar_bg.size = Vector2(96, 10)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar_bg)
		var fill := ColorRect.new()
		fill.color = WarTable.COL_BLUE if side_lr == "left" else WarTable.COL_RED
		fill.size = Vector2(92.0 * clampf(cur_hp / mx, 0.0, 1.0), 6)
		fill.position = Vector2(2, 2)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_bg.add_child(fill)
		_anchor(bar_bg, bp + Vector3(0, 0, 1.75))
		_fade(bar_bg, 0.40 if not settle else 0.0, 0.25)
		if not settle:
			tracks.append({"k": "pop3", "node": table.bases[side_lr]["node"], "t0": 0.20, "dur": 0.35})
	## ── 三块战场台 + 路名金字 ──
	var lanes := ["top", "bottom", "final"]
	for i in lanes.size():
		var ln: String = lanes[i]
		if not settle:
			tracks.append({"k": "pop3", "node": table.isl[ln]["node"], "t0": 0.25 + 0.15 * float(i), "dur": 0.4})
			_sfx("ui_click", 0.25 + 0.15 * float(i), 0.8, 0.9 + 0.12 * float(i))
		var la: Texture2D = _tex(str(LANE_ART[ln]))
		if la != null:
			var lsz := Vector2(la.get_width(), la.get_height()) * 1.7
			var lab := _trect(la, lsz, root, Vector2.ZERO)
			_anchor(lab, (WarTable.LANE_POS[ln] as Vector3) + Vector3(0, 0, float(WarTable.LANE_R[ln]) + 0.75))
			if not settle:
				_fade(lab, 0.45 + 0.15 * float(i), 0.3)
		## 已经打完的路(不是这一幕刚打完的那条): 直接是结果态
		var w := _lane_winner(ln)
		if w != "" and not (settle and ln == lane):
			_mark_result3(ln, w, -1.0)
	## ── 路线 ──
	for k in table.paths.size():
		var pth: Dictionary = table.paths[k]
		if settle:
			(pth["mat"] as ShaderMaterial).set_shader_parameter("prog", 1.0)
		else:
			tracks.append({"k": "path3", "node": pth["mat"], "t0": 0.55 + 0.05 * float(k), "dur": 0.6})
	## ── 上 / 下两路: 双方各三只立牌站在台面两侧(三对三) ──
	var kk := 0
	for ln2 in ["top", "bottom"]:
		for side_lr in ["left", "right"]:
			var specs: Array = _side_specs(ln2, side_lr)
			for j in specs.size():
				var pos: Vector3 = WarTable.squad_pos(ln2, side_lr, j, specs.size())
				var st: Dictionary = table.add_standee(_sd_of(specs[j]), ln2, side_lr, pos)
				var done := _lane_winner(ln2) != ""
				if settle:
					if done and ln2 != lane:
						(st["spr"] as Sprite3D).modulate = Color(0.42, 0.42, 0.48)
					elif ln2 == lane:
						tracks.append({"k": "grey3", "node": st["spr"], "t0": 0.8, "dur": 0.4})
				else:
					var t_in: float = (1.05 if ln2 == "top" else 1.45) + 0.06 * float(kk % 6)
					tracks.append({"k": "drop3", "node": st["spr"], "to": pos, "t0": t_in, "dur": 0.32})
					(st["spr"] as Sprite3D).visible = false
				kk += 1
	if not settle:
		_sfx("ui_confirm", 1.45, 0.7)
		_sfx("ui_confirm", 1.85, 0.7, 1.12)
	## ── 终极战场两侧: 开场 = 「？」; 战果幕 = 已过去的幸存者 + 这一路的幸存者走过去 ──
	for side_lr in ["left", "right"]:
		if not settle:
			for q in 2:
				var ph := _qmark()
				root.add_child(ph)
				_anchor(ph, WarTable.squad_pos("final", side_lr, q, 2) + Vector3(0, 0.55, 0))
				_pop(ph, 1.9 + 0.06 * float(q), 0.3)
		else:
			var prev: Array = (gs.dual_survivors.get(side_lr, []) as Array) if gs != null and gs.dual_survivors is Dictionary else []
			var now: Array = _alive_specs(side_lr)
			var tot := prev.size() + now.size()
			for j in prev.size():
				table.add_standee(_sd_of(prev[j]), "final", side_lr, WarTable.squad_pos("final", side_lr, j, tot))
			for j in now.size():
				var to: Vector3 = WarTable.squad_pos("final", side_lr, prev.size() + j, tot)
				var from: Vector3 = WarTable.squad_pos(lane, side_lr, j, maxi(1, now.size()))
				var st2: Dictionary = table.add_standee(_sd_of(now[j]), "final", side_lr, from)
				tracks.append({"k": "hop3", "node": st2["spr"], "from": from, "to": to, "t0": 1.25 + 0.08 * float(j), "dur": 0.75, "h": 0.9})
			if not now.is_empty():
				_sfx("ui_confirm", 1.9, 0.7)
	## ── 镜头 ──
	var focus: String = lane if not settle else next_lane
	if not settle:
		_cam_seg(0.0, 1.4, table.high_cam(), ov)
		var drift: Array = [(ov[0] as Vector3) + Vector3(0, -0.5, -0.6), ov[1]]
		_cam_seg(1.4, 3.7, ov, drift)
		_cam_seg(3.7, 4.45, drift, table.lane_cam(focus, false))
		_cam_seg(4.45, 5.0, table.lane_cam(focus, false), table.lane_cam(focus, true))
	else:
		_cam_seg(0.0, 0.8, table.lane_cam(lane, false), ov)
		_cam_seg(0.8, 3.7, ov, ov)
		if focus != "":
			_cam_seg(3.7, 4.45, ov, table.lane_cam(focus, false))
			_cam_seg(4.45, 5.0, table.lane_cam(focus, false), table.lane_cam(focus, true))
	## ── 本路(开场 = 上路; 战果 = 下一路)金圈呼吸 + 盾徽; 终极战场要开打 ⇒ 光柱亮起 ──
	if settle:
		_settle_marks3()
	if focus != "":
		var t_hi: float = 2.2 if not settle else 2.4
		tracks.append({"k": "pulse3", "node": table.isl[focus]["glow_mat"], "t0": t_hi, "t1": 99.0})
		if focus == "final":
			tracks.append({"k": "lit3", "node": table.isl["final"]["node"], "d": table.isl["final"], "t0": t_hi, "dur": 1.0})
			_sfx("level_up", t_hi, 0.7)
		var crest: Texture2D = _tex(CREST)
		if crest != null:
			var cr := _trect(crest, Vector2(64, 64), root, Vector2.ZERO)
			_anchor(cr, (WarTable.LANE_POS[focus] as Vector3) + Vector3(0, 1.9, 0))
			_slam(cr, t_hi + 0.1, 2.2)
			_sfx("g_shield_gain", t_hi + 0.22, 0.8)
		for ln3 in ["top", "bottom", "final"]:
			if ln3 != focus:
				tracks.append({"k": "dim3", "node": table.isl[ln3]["top_mat"], "t0": t_hi, "dur": 0.4})
		_sfx("match_found", 3.8, 0.75)
		zoom["in"] = [4.45, 5.0]
	_add_flash(false)


func _qmark() -> Control:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.45, 0.52, 0.62, 0.7)
	sb.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size = Vector2(40, 40)
	p.pivot_offset = p.size * 0.5
	var q := Label.new()
	q.text = "?"
	q.add_theme_font_size_override("font_size", 22)
	q.add_theme_color_override("font_color", COL_SUB)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(q)
	return p


## 一路的结果: 看的人输了这一路 ⇒ 台面上「挥」两刀打叉 + 压暗; 赢了 ⇒ 胜方色光圈。t0 < 0 = 直接是结果态(早已打完的那路)。
func _mark_result3(ln: String, win_lr: String, t0: float) -> void:
	var d: Dictionary = table.isl[ln]
	var team: Color = WarTable.COL_BLUE if win_lr == "left" else WarTable.COL_RED
	var lost := win_lr != me_lr
	var t_at: float = maxf(0.0, t0)
	if lost:
		for k in 2:
			tracks.append({"k": "slash3", "node": (d["slash"] as Array)[k], "t0": t_at + 0.17 * float(k), "dur": 0.13 if t0 >= 0.0 else 0.0})
		tracks.append({"k": "dim3", "node": d["top_mat"], "t0": t_at, "dur": 0.3 if t0 >= 0.0 else 0.0})
	else:
		var gm: ShaderMaterial = d["glow_mat"]
		gm.set_shader_parameter("col", team.lerp(Color.WHITE, 0.2))
		tracks.append({"k": "fade3", "node": gm, "t0": t_at, "dur": 0.3 if t0 >= 0.0 else 0.0, "a1": 0.75})
	tracks.append({"k": "tint3", "node": d["top_mat"], "t0": t_at, "dur": 0.35 if t0 >= 0.0 else 0.0, "col": team})


## 一路战果: 结果(打叉 / 光圈) + 印章(按看的人那一侧) + 顶上比分 / 蛋血两行(门禁按名字找这三个 Label)
func _settle_marks3() -> void:
	var win_lr := "right" if str(battle._dl_pending_loser) == "left" else "left"
	_mark_result3(lane, win_lr, 0.8)
	var won := win_lr == me_lr
	var res := _label("本战场胜利" if won else "本战场失败", 36, COL_WIN if won else COL_LOSE, root, Vector2.ZERO, true, "LaneSettleResult")
	res.add_theme_constant_override("outline_size", 10)
	res.rotation = -0.14
	_anchor(res, (WarTable.LANE_POS[lane] as Vector3) + Vector3(0, 1.2, 0))
	_slam(res, 0.95, 2.2, 0.2)
	if won:
		_sfx("reward_normal", 0.85, 0.6)
	else:
		_sfx("g_crit", 0.82, 0.85, 0.8)       # 第一刀
		_sfx("g_crit", 0.99, 0.85, 0.7)       # 第二刀
		_sfx("g_shield_break", 1.05, 0.6)
	var gs = battle.get_node_or_null("/root/GameState")
	## 顶上记分牌: 深色底 + 金边, 垫在比分 / 蛋血两行下面(原来是两行光秃秃的小字)
	var board := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.03, 0.05, 0.09, 0.9)
	bsb.set_border_width_all(2)
	bsb.border_color = Color("#c9a24a")
	bsb.set_corner_radius_all(4)
	board.add_theme_stylebox_override("panel", bsb)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.size = Vector2(minf(560.0, vp.x - 360.0), 64)
	board.position = Vector2((vp.x - board.size.x) * 0.5, 4)
	root.add_child(board)
	_fade(board, 1.1, 0.25)
	var rec := _label(flow._dl_record_line(lane, win_lr), 24, Color("#ffe9a8"), root, Vector2(vp.x * 0.5, 22), true, "LaneSettleRecord")
	_slam(rec, 1.2, 1.5, 0.2)
	_sfx("ui_click", 1.3, 0.8, 1.25)
	if gs != null and gs.egg_hp is Dictionary:
		var foe := ReplayRecorder.foe_side(battle)
		var e := _label("龟蛋生命  我方 %d  ·  对方 %d" % [int(gs.egg_hp.get(me_lr, 0.0)), int(gs.egg_hp.get(foe, 0.0))], 16, Color("#cfe6ff"), root, Vector2(vp.x * 0.5, 50), false, "LaneSettleEggs")
		_fade(e, 1.3, 0.3)


## 每帧: 镜头按段插值 → 立牌待机帧 → 2D 字按投影摆
func _pose_table() -> void:
	if table == null:
		return
	if table.sea_mat != null:
		table.sea_mat.set_shader_parameter("t", t)
	var seg: Array = []
	for s in cam_segs:
		if t >= float(s[0]):
			seg = s
	if not seg.is_empty():
		var k: float = _ease_in_out((t - float(seg[0])) / maxf(0.01, float(seg[1]) - float(seg[0])))
		var a: Array = seg[2]
		var b: Array = seg[3]
		table.set_cam((a[0] as Vector3).lerp(b[0], k), (a[1] as Vector3).lerp(b[1], k))
	for st in table.standees:
		var spr: Sprite3D = st["spr"]
		if int(st["frames"]) > 1 and is_instance_valid(spr):
			spr.frame = int(floor(t * float(st["fps"]))) % mini(int(st["frames"]), spr.hframes * spr.vframes)
	for an in anchors:
		var nd: Control = an["node"]
		if not is_instance_valid(nd):
			continue
		var p3: Vector3 = an["p"]
		if table.is_behind(p3):
			nd.position = Vector2(-9999, -9999)
			continue
		nd.position = table.project(p3) + (an["off"] as Vector2) - nd.size * 0.5


# ══════════════════════════════════════════════════════════════════════
#  对阵(双方全身立绘斜切对峙)
# ══════════════════════════════════════════════════════════════════════
func _body(spec) -> Dictionary:
	var sd: Dictionary = {}
	if spec is Dictionary:
		var sp: Dictionary = spec
		if str(sp.get("kind", "")) == "minion" or sp.has("role"):
			if str(sp.get("role", "")) == "reserve":
				sd = battle._reserve_sys.sprite_dict()
			else:
				sd = battle._hiding_sys._minion_sprite_dict(bool(sp.get("elite", false)), str(sp.get("role", "front")) == "back")
		else:
			## 界面立绘那一套待机(PetUiIdle): pets.json 没登记逐帧待机的龟(变脸龟)由它补一张 8 帧表;
			##   直接读 pets.json 的 img 拿到的是静态图(用户 11-15「这个变脸龟的待机动画是没有用嘛」)
			var pid := str(sp.get("id", ""))
			var pet: Dictionary = battle._data_by_id.get(pid, {})
			var ui: Dictionary = PetUiIdle.of(pet) if not pet.is_empty() else pet
			if not is_same(ui, pet) and ResourceLoader.exists(battle.SPRITE_DIR + str(ui.get("img", ""))):
				sd = battle._sprite_dict_from(load(battle.SPRITE_DIR + str(ui["img"])), ui.get("sprite"), false)
			else:
				sd = battle._resolve_pet_sprite(pid)
	return sd


func _body_rect(spec, h: float, parent: Control) -> TextureRect:
	var sd := _body(spec)
	var tex: Texture2D = sd.get("tex") as Texture2D
	var tr := TextureRect.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size = Vector2(h, h)
	tr.pivot_offset = Vector2(h * 0.5, h)
	if tex != null:
		var hf: int = maxi(1, int(sd.get("hframes", 1)))
		var vf: int = maxi(1, int(sd.get("vframes", 1)))
		var fw: float = float(tex.get_width()) / float(hf)
		var fh: float = float(tex.get_height()) / float(vf)
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(0, 0, fw, fh)
		tr.texture = at
		var sc: float = minf(h / fw, h / fh)
		tr.set_meta("disp_h", fh * sc)
		tr.set_meta("used_y", _used_rows(tex, int(fw), int(fh)))
		if int(sd.get("frames", 1)) > 1:
			if _body_sh == null:
				_body_sh = Shader.new()
				_body_sh.code = BODY_SHADER
			var bm := ShaderMaterial.new()
			bm.shader = _body_sh
			tr.material = bm
			anim_frames.append({"node": tr, "mat": bm, "fw": fw / float(tex.get_width()), "fh": fh / float(tex.get_height()), "hf": hf,
				"frames": int(sd.get("frames", 1)), "fps": float(sd.get("fps", 8.0))})
	parent.add_child(tr)
	return tr


## 第 0 帧不透明区域的上 / 下沿(比例)。量不到(无头 / 压缩贴图取不出像素)⇒ 整帧(0, 1)。
static func _used_rows(tex: Texture2D, fw: int, fh: int) -> Vector2:
	var key := "%s|%d|%d" % [tex.resource_path, fw, fh]
	if _used_cache.has(key):
		return _used_cache[key]
	var out := Vector2(0.0, 1.0)
	var img: Image = tex.get_image()
	if img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var fr: Image = img.get_region(Rect2i(0, 0, mini(fw, img.get_width()), mini(fh, img.get_height())))
		var ur: Rect2i = fr.get_used_rect()
		if ur.size.y > 0:
			out = Vector2(float(ur.position.y) / float(fh), float(ur.end.y) / float(fh))
	_used_cache[key] = out
	return out


func _build_vs() -> void:
	var hdr: Dictionary = flow._side_headers()
	## 底: 本场地照片压暗(没有照片 = 海图)
	var tex: Texture2D = photo()
	if tex != null:
		var bgp := TextureRect.new()
		bgp.texture = tex
		bgp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bgp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bgp.set_anchors_preset(Control.PRESET_FULL_RECT)
		bgp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bgp.modulate = Color(0.42, 0.45, 0.52, 1.0)
		root.add_child(bgp)
		root.move_child(bgp, 1)
	## 左蓝右红两条斜带 + 中缝亮线(在地图画布上画, 跟着等比缩放)
	var bands := Bands.new()
	bands.size = Vector2(CW, CH)
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(bands)
	tracks.append({"k": "bands", "node": bands, "t0": 0.0, "dur": 0.3})
	## 顶上路名金字
	var la: Texture2D = _tex(str(LANE_ART.get(lane, LANE_ART["top"])))
	if la != null:
		var lsz := Vector2(la.get_width(), la.get_height()) * 3.0
		var lt := _trect(la, lsz, map, Vector2(CW * 0.5, 54))
		_slide(lt, lt.position - Vector2(0, 60), lt.position, 0.1, 0.4)
	## 双方立绘
	var specs_l: Array = flow._dl_lane_specs(lane)
	var specs_r: Array = flow._dl_foe_specs(lane)
	var n: int = maxi(specs_l.size(), specs_r.size())
	## 3 只以内一排放大; 4 只一排略小; 再多(终极战场: 两路幸存 + 援军小将, 一侧最多 7 只)分前后两排
	var rows: int = 1 if n <= 4 else 2
	var bh: float = 236.0 if n <= 3 else (196.0 if n <= 4 else 140.0)
	for side_lr in ["left", "right"]:
		var specs: Array = specs_l if side_lr == "left" else specs_r
		var team: Color = COL_BLUE if side_lr == "left" else COL_RED
		## 双方名字放顶上与路名同一行的两侧(放中间会和后排头顶的名牌挤在一起)
		var hd := _label(str(hdr["l"] if side_lr == "left" else hdr["r"]), 24, COL_WIN if side_lr == me_lr else COL_LOSE, map,
			Vector2(CW * (0.17 if side_lr == "left" else 0.83), 54), true)
		_slide(hd, hd.position + Vector2(-140.0 if side_lr == "left" else 140.0, 0), hd.position, 0.3, 0.35, false)
		var cnt := specs.size()
		var per_row: int = int(ceil(float(cnt) / float(rows)))
		## 后排先建(画在下面), 前排后建
		var order: Array = []
		for i in cnt:
			order.append(i)
		if rows > 1:
			order.sort_custom(func(a, b): return (a / per_row) > (b / per_row) or ((a / per_row) == (b / per_row) and a < b))
		for i in order:
			## 斜排: 离中线越远越靠上(与中缝斜线平行); 两排时后排整体往上、往外错半格
			var row: int = i / per_row
			var col: int = i % per_row
			var step: float = minf(170.0, 480.0 / maxf(1.0, float(per_row)))
			var dx: float = 160.0 + float(col) * step + float(row) * step * 0.5
			var x: float = CW * 0.5 + (-dx if side_lr == "left" else dx)
			var y: float = 520.0 - float(col) * 30.0 - float(row) * 165.0
			var shadow := Shadow.new()
			shadow.size = Vector2(bh * 0.55, 18)
			shadow.position = Vector2(x - bh * 0.275, y - 8)
			shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map.add_child(shadow)
			_fade(shadow, 0.25 + 0.08 * float(i), 0.3)
			var body := _body_rect(specs[i], bh, map)
			if side_lr == "right":
				body.flip_h = true
			## 脚踩在基线 y 上: 按帧里不透明像素的下沿对齐(不是帧底), 影子 / 光圈 / 扬尘 / 名牌都跟着基线走
			var dh: float = float(body.get_meta("disp_h", bh))
			var used: Vector2 = body.get_meta("used_y", Vector2(0.0, 1.0))
			var top_off: float = (bh - dh) * 0.5
			var feet_off: float = top_off + used.y * dh
			var head_y: float = y - feet_off + top_off + used.x * dh
			var to := Vector2(x - bh * 0.5, y - feet_off)
			var from := to + Vector2(-520.0 if side_lr == "left" else 520.0, 0)
			_slide(body, from, to, 0.25 + 0.08 * float(i), 0.45)
			## 落地: 滑到位那一刻(缓动过冲回落约在 70%)脚下扬一圈像素尘 + 队伍色光圈亮一下
			var t_land: float = 0.25 + 0.08 * float(i) + 0.45 * 0.7
			var glow := GroundGlow.new()
			glow.col = team
			glow.size = Vector2(bh * 0.7, 26)
			glow.position = Vector2(x - bh * 0.35, y - 13)
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map.add_child(glow)
			map.move_child(glow, map.get_children().find(body))
			_fade(glow, t_land, 0.25)
			var dust := Dust.new()
			dust.size = Vector2(bh * 0.9, 60)
			dust.position = Vector2(x - bh * 0.45, y - 40)
			dust.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map.add_child(dust)
			tracks.append({"k": "dust", "node": dust, "t0": t_land, "dur": 0.5})
			## 脚下名牌: 名字 + Lv + 装备格
			var plate := VBoxContainer.new()
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.add_theme_constant_override("separation", 2)
			plate.alignment = BoxContainer.ALIGNMENT_CENTER
			var nm := Label.new()
			nm.text = flow._dl_spec_name(specs[i])
			nm.add_theme_font_size_override("font_size", 22)
			nm.add_theme_color_override("font_color", COL_TEXT)
			nm.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 1.0))
			nm.add_theme_constant_override("outline_size", 5)
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.add_child(nm)
			## 被训龟大师驯服、改投这一边的龟(终极战场名单里带 tamed_side): 名字下面写一行, 不然看着像「我方的龟站到了对面」
			if specs[i] is Dictionary and str((specs[i] as Dictionary).get("tamed_side", "")) != "":
				var tm := Label.new()
				tm.text = "被驯服"
				tm.add_theme_font_size_override("font_size", 16)
				tm.add_theme_color_override("font_color", Color("#ffb054"))
				tm.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 1.0))
				tm.add_theme_constant_override("outline_size", 4)
				tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
				plate.add_child(tm)
			var eqs: Array = flow._dl_spec_equips(specs[i], side_lr == "left")
			if not eqs.is_empty():
				var er := HBoxContainer.new()
				er.alignment = BoxContainer.ALIGNMENT_CENTER
				er.add_theme_constant_override("separation", 3)
				er.mouse_filter = Control.MOUSE_FILTER_IGNORE
				for e in eqs:
					if e is Dictionary:
						var chip: Control = flow._dl_equip_chip(str(e.get("id", "")), int(e.get("star", 1)))
						chip.custom_minimum_size = Vector2(40, 40)
						er.add_child(chip)
				plate.add_child(er)
			plate.size = Vector2(190, 70)
			## 两排时后排的名牌放头顶上(放脚下会被前排立绘挡住)
			plate.position = Vector2(x - 95, y + 6) if row == 0 else Vector2(x - 95, head_y - 72)
			map.add_child(plate)
			_fade(plate, 0.8 + 0.06 * float(i), 0.3)
	## 中间 VS 盾徽砸下
	var crest: Texture2D = _tex(CREST)
	if crest != null:
		## 盾心落在两条斜带的中缝上(Bands 的中缝: x = 0.56w − 0.12w·y/h)
		var cy_cr := 330.0
		var cr := _trect(crest, Vector2(150, 150), map, Vector2(CW * 0.56 - CW * 0.12 * cy_cr / CH, cy_cr))
		_slam(cr, 0.55, 2.6, 0.18)
		tracks.append({"k": "shake", "node": map, "t0": 0.73, "dur": 0.3})
		_sfx("g_skill_hit", 0.72, 1.0, 0.85)
	_sfx("ui_click", 0.30, 0.6, 1.1)                                     # 斜带扫入
	_add_flash(true)


# ══════════════════════════════════════════════════════════════════════
#  开战横幅(原来是场中一个飘字「开 战」)
# ══════════════════════════════════════════════════════════════════════
static func fight_banner(b, ln: String) -> Control:
	if b == null or b._ui_layer == null:
		return null
	var vp2: Vector2 = b.get_viewport().get_visible_rect().size
	var holder := Control.new()
	holder.name = "FightBanner"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 40
	b._ui_layer.add_child(holder)
	holder.add_to_group(BattleHud.UI_TRANSIENT_GROUP)
	var s: float = minf(vp2.x / CW, vp2.y / CH)
	var bh: float = 150.0 * s
	var cy: float = vp2.y * 0.40
	var band := ColorRect.new()
	band.color = Color(0.03, 0.04, 0.08, 0.82)
	band.size = Vector2(vp2.x, bh)
	band.position = Vector2(0, cy - bh * 0.5)
	band.pivot_offset = Vector2(0, bh * 0.5)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(band)
	for yy in [cy - bh * 0.5, cy + bh * 0.5 - 3.0 * s]:
		var ln2 := ColorRect.new()
		ln2.color = COL_GOLD
		ln2.size = Vector2(vp2.x, maxf(2.0, 3.0 * s))
		ln2.position = Vector2(0, yy)
		ln2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(ln2)
		ln2.position.y = yy - band.position.y
	var kz: Texture2D = load(KAIZHAN) if ResourceLoader.exists(KAIZHAN) else null
	var word := TextureRect.new()
	word.texture = kz
	word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	word.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word.size = Vector2(240, 128) * s
	word.pivot_offset = word.size * 0.5
	word.position = Vector2(vp2.x * 0.5, cy - 14.0 * s) - word.size * 0.5
	holder.add_child(word)
	var la: Texture2D = load(str(LANE_ART.get(ln, ""))) if ResourceLoader.exists(str(LANE_ART.get(ln, ""))) else null
	var sub := TextureRect.new()
	sub.texture = la
	sub.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sub.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sub.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.size = Vector2(132, 40) * s
	sub.position = Vector2(vp2.x * 0.5, cy + 52.0 * s) - sub.size * 0.5
	holder.add_child(sub)
	var clk := BannerClock.new()
	clk.parts = [band, word, sub]
	clk.vw = vp2.x
	holder.add_child(clk)
	clk.pose(0.0)
	return holder


# ══════════════════════════════════════════════════════════════════════
#  小部件类
# ══════════════════════════════════════════════════════════════════════
class Clock extends Node:
	var intro = null

	func _process(d: float) -> void:
		if intro != null:
			intro.tick(d)


class BannerClock extends Node:
	var parts: Array = []
	var vw := 1560.0
	var tt := 0.0
	const DUR := 1.15

	static func _eo(x: float) -> float:
		return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)

	static func _eio(x: float) -> float:
		var u := clampf(x, 0.0, 1.0)
		return u * u * (3.0 - 2.0 * u)

	## 0~0.15 带子从左扫入; 0.08~0.26 大字 1.6 → 1 砸下; 0.22 起路名淡入; 0.9~1.1 整条从右扫出
	func pose(x: float) -> void:
		tt = x
		for p in parts:
			if not is_instance_valid(p):
				return
		var band: Control = parts[0]
		var word: Control = parts[1]
		var sub: Control = parts[2]
		var kin := _eo(tt / 0.15)
		var kout := _eio((tt - 0.9) / 0.2)
		band.scale = Vector2(maxf(0.001, kin * (1.0 - kout)), 1.0)
		band.position.x = vw * kout
		var kw := (tt - 0.08) / 0.18
		word.modulate.a = clampf(kw * 4.0, 0.0, 1.0) * (1.0 - kout)
		word.scale = Vector2.ONE * lerpf(1.6, 1.0, _eo(kw))
		sub.modulate.a = clampf((tt - 0.22) / 0.15, 0.0, 1.0) * (1.0 - kout)

	func _process(d: float) -> void:
		pose(tt + d)
		if tt >= DUR:
			var h := get_parent()
			if h != null and is_instance_valid(h):
				h.queue_free()






## 对阵屏的两条斜带(左蓝右红)+ 中缝亮线。prog: 0 = 都在屏外, 1 = 到位
class Bands extends Control:
	var prog := 0.0

	func _draw() -> void:
		## 设计画布外(iPad 上下、宽屏左右)也要铺满: 多边形往四边各延一个画布; 中缝沿同一条斜线延长
		var w := size.x
		var h := size.y
		var off := (1.0 - prog) * w * 0.6
		var xt := w * 0.68      # 中缝在 y = -h 处的 x(斜率: 每往下一个画布高, 左移 0.12w)
		var xb := w * 0.32      # 中缝在 y = 2h 处的 x
		var l := PackedVector2Array([Vector2(-w, -h), Vector2(xt - off, -h), Vector2(xb - off, 2.0 * h), Vector2(-w, 2.0 * h)])
		var r := PackedVector2Array([Vector2(xt + off, -h), Vector2(w * 2.0, -h), Vector2(w * 2.0, 2.0 * h), Vector2(xb + off, 2.0 * h)])
		draw_colored_polygon(l, Color(0.16, 0.33, 0.66, 0.55))
		draw_colored_polygon(r, Color(0.62, 0.17, 0.22, 0.55))
		if prog > 0.95:
			draw_line(Vector2(xt, -h), Vector2(xb, 2.0 * h), Color(1.0, 0.95, 0.75, 0.9), 4.0)


## 落地扬尘: 一圈像素方块从脚下往两侧、往上散开再落下淡出(prog 0→1)
class Dust extends Control:
	var prog := 0.0

	func _draw() -> void:
		if prog <= 0.0 or prog >= 1.0:
			return
		var c := Vector2(size.x * 0.5, size.y - 6.0)
		for i in 18:
			var side := -1.0 if i % 2 == 0 else 1.0
			var sp := 0.30 + 0.70 * float((i * 37) % 11) / 11.0
			var e := 1.0 - pow(1.0 - prog, 2.0)
			var dx := side * size.x * 0.55 * sp * e
			var dy := -sin(minf(1.0, prog * 1.3) * PI) * (14.0 + 22.0 * float((i * 53) % 7) / 7.0)
			var p := (c + Vector2(dx, dy)).snapped(Vector2(3, 3))
			var sz := 9.0 if i % 4 == 0 else (6.0 if i % 2 == 0 else 3.0)
			var a := 0.9 * (1.0 - prog)
			draw_rect(Rect2(p + Vector2(0, 3), Vector2(sz, sz)), Color(0.10, 0.08, 0.06, a * 0.4))
			draw_rect(Rect2(p, Vector2(sz, sz)), Color(0.90, 0.84, 0.72, a))


## 脚下队伍色光圈(扁椭圆, 三圈由外到内渐实)
class GroundGlow extends Control:
	var col := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		for i in 3:
			var k := 1.0 - float(i) * 0.28
			var r := Rect2(c - Vector2(size.x * 0.5 * k, size.y * 0.5 * k), Vector2(size.x * k, size.y * k))
			draw_rect(r.grow_individual(-r.size.x * 0.12, 0, -r.size.x * 0.12, 0), Color(col.r, col.g, col.b, 0.16 + 0.10 * float(i)))
			draw_rect(Rect2(r.position + Vector2(0, r.size.y * 0.25), Vector2(r.size.x, r.size.y * 0.5)), Color(col.r, col.g, col.b, 0.10 + 0.08 * float(i)))






class Shadow extends Control:
	func _draw() -> void:
		var c := size * 0.5
		for i in 3:
			var k := 1.0 - float(i) * 0.25
			draw_rect(Rect2(c - Vector2(size.x * 0.5 * k, size.y * 0.5 * k * 0.6), Vector2(size.x * k, size.y * k * 0.6)), Color(0, 0, 0, 0.18))
