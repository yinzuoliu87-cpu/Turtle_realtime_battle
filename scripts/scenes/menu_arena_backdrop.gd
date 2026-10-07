class_name MenuArenaBackdrop
extends Control
## menu_arena_backdrop.gd — 主菜单背景: 擂台 + 看台, 会动 (2026-10-05)。
##
## 由来: 方案书 docs/plans/20260917-主菜单版式重做.md R1(场景 = 擂台 + 看台) /
##   R1-a(不拿 map 件拼) / R1-b(「不能用现有的龟立绘」, 观众也全新画)。
##   素材全是 PixelLab 新生成的, 由 tools/build_menu_arena_bg.py 分层烘好、调好色,
##   排布在 scripts/gamedata/menu_arena_layout.gd(生成文件)。本文件只管【拼起来 + 让它动】。
##
## 会动的东西(都在 `step()` 里, 一条钟):
##   · 看台观众: 每排两组交错, 各按自己的节拍蹦 1 像素(整排一起动像一块板在晃)
##   · 火盆: 4 帧火苗乱序换 + 火光明暗
##   · 顶沿的灯: 3 组各自明暗
##   · 小旗: 着色器按行横摆, 越往下摆幅越大, 摆幅取整到原生像素(不糊)
##   · 两只角斗龟: 架势 → 蓄力 → 突刺/顶盾 → 收回, 一个循环 3.4 秒
##
## 像素口径: 原生 390×180, 按视口高(或宽, 取大的那个)整体放大铺满 —— 与原来那张群像 COVERED 一样居中裁边。
##   1280×720 与 1560×720 下都是 ×4, UI 落在原生坐标上是同一个位置(主角站位就是照这个算的)。

const _L := preload("res://scripts/gamedata/menu_arena_layout.gd")
const NODE_NAME := "ArenaBackdrop"
const FIGHT_CYCLE := 3.4          # 秒: 一次「蓄力 → 出手 → 收回」
const FLAME_FRAME := 0.11         # 秒: 火苗换帧

const _BANNER_SHADER := """
shader_type canvas_item;
uniform float t = 0.0;
uniform float amp = 1.6;          // 最下沿的摆幅(原生像素)
uniform vec2 tex_px = vec2(32.0, 48.0);
void fragment() {
	float k = UV.y * UV.y;        // 顶上挂杆不动, 越往下摆得越开
	float off = floor(sin(t * 2.2 + UV.y * 5.5) * amp * k + 0.5) / tex_px.x;
	COLOR = texture(TEXTURE, UV + vec2(off, 0.0));
}
"""

var _t := 0.0
var _stage: Control = null
var _crowd: Array = []            # [{node, y0, period, duty, phase}]
var _lights: Array = []           # [{node, base, amp, period, phase}]
var _flames: Array = []           # [{node, frames: Array[Texture2D], idx}]
var _glows: Array = []            # [TextureRect]
var _banner: TextureRect = null
var _atk: TextureRect = null
var _def: TextureRect = null
var _atk_tex := {}                # pose -> {tex, x, y}
var _def_tex := {}
var _atk_pose := "stance"
var _def_pose := "guard"
var _tex_paths: Array = []


func _init() -> void:
	name = NODE_NAME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST    # 像素风: 放大不许插值糊掉(子节点继承)
	clip_contents = true


func _ready() -> void:
	_build()
	step(0.0)


## 铺满 `vp`: 等比放大到盖住整个视口, 居中裁边(同 STRETCH_KEEP_ASPECT_COVERED)。
func fit(vp: Vector2) -> void:
	size = vp
	if _stage == null:
		return
	var nat := _native()
	var s: float = maxf(vp.x / nat.x, vp.y / nat.y)
	_stage.scale = Vector2(s, s)
	_stage.position = ((vp - nat * s) / 2.0).round()


func _native() -> Vector2:
	var n: Array = _L.LAYOUT["native"]
	return Vector2(float(n[0]), float(n[1]))


func _process(delta: float) -> void:
	step(minf(delta, 0.1))


## 推进一步。★测试直接调它(给确定的 dt), 不靠等帧 —— 帧率跟机器挂钩, 钟不该。
func step(dt: float) -> void:
	_t += dt
	for c in _crowd:
		var cyc: float = fposmod(_t / float(c["period"]) + float(c["phase"]), 1.0)
		(c["node"] as Control).position.y = float(c["y0"]) - (1.0 if cyc < float(c["duty"]) else 0.0)
	for l in _lights:
		var a: float = float(l["base"]) + float(l["amp"]) * sin(TAU * _t / float(l["period"]) + float(l["phase"]))
		(l["node"] as CanvasItem).modulate.a = clampf(a, 0.0, 1.0)
	var tick := int(floor(_t / FLAME_FRAME))
	for i in range(_flames.size()):
		var f: Dictionary = _flames[i]
		var frames: Array = f["frames"]
		## 乱序但确定: 同一时刻同一帧(测试可复现), 两边火盆不同步
		var idx: int = int(abs(hash(tick * 31 + i * 7))) % frames.size()
		if idx != int(f["idx"]):
			f["idx"] = idx
			var fn: TextureRect = f["node"]
			fn.texture = frames[idx]
			## 每帧烘焙时各自裁到包围盒 ⇒ 偏移各不相同, 换帧要连位置一起换(否则火苗会跳)
			fn.position = f["offs"][idx]
			fn.size = (frames[idx] as Texture2D).get_size()
		if i < _glows.size():
			(_glows[i] as CanvasItem).modulate.a = 0.75 + 0.25 * float((idx * 5 + tick) % 4) / 3.0
	if _banner != null and _banner.material is ShaderMaterial:
		(_banner.material as ShaderMaterial).set_shader_parameter("t", _t)
	_fight_pose(fposmod(_t, FIGHT_CYCLE))


func _fight_pose(c: float) -> void:
	var ap := "stance"
	var dp := "guard"
	var ax := 0.0
	var dx := 0.0
	if c >= 1.7 and c < 2.3:
		ap = "windup"
	elif c >= 2.3 and c < 2.9:
		ap = "thrust"
		dp = "brace"
		ax = 2.0      # 出手往前送两格
		dx = 1.0      # 挨了一下往后退一格
	## 架势时的呼吸: 两只错开半拍上下 1 格
	var ay := -1.0 if (ap == "stance" and fposmod(c, 0.8) < 0.4) else 0.0
	var dy := -1.0 if (dp == "guard" and fposmod(c + 0.4, 0.8) < 0.4) else 0.0
	_set_pose(_atk, _atk_tex, ap, ax, ay)
	_set_pose(_def, _def_tex, dp, dx, dy)
	_atk_pose = ap
	_def_pose = dp


func _set_pose(node: TextureRect, table: Dictionary, pose: String, dx: float, dy: float) -> void:
	if node == null or not table.has(pose):
		return
	var e: Dictionary = table[pose]
	if node.texture != e["tex"]:
		node.texture = e["tex"]
		node.size = (e["tex"] as Texture2D).get_size()
	node.position = Vector2(float(e["x"]) + dx, float(e["y"]) + dy)


func _tex(path: String) -> Texture2D:
	_tex_paths.append(path)
	return load(path) as Texture2D


func _rect(e: Dictionary) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _tex(str(e["tex"]))
	r.position = Vector2(float(e["x"]), float(e["y"]))
	r.size = Vector2(float(e["w"]), float(e["h"]))
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(r)
	return r


func _build() -> void:
	var L: Dictionary = _L.LAYOUT
	_stage = Control.new()
	_stage.name = "Stage"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = _native()
	add_child(_stage)
	_rect(L["base"])
	for e in L["lights"]:
		_lights.append({"node": _rect(e), "base": e["base"], "amp": e["amp"], "period": e["period"], "phase": e["phase"]})
	for e in L["crowd"]:
		_crowd.append({"node": _rect(e), "y0": float(e["y"]), "period": e["period"], "duty": e["duty"], "phase": e["phase"]})
	_banner = _rect(L["banner"])
	_banner.name = "Banner"
	var sh := Shader.new()
	sh.code = _BANNER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex_px", Vector2(float(L["banner"]["w"]), float(L["banner"]["h"])))
	_banner.material = mat
	for side in ["atk", "def"]:
		var table := {}
		for pose in (L["fighters"][side] as Dictionary).keys():
			var e: Dictionary = L["fighters"][side][pose]
			table[pose] = {"tex": _tex(str(e["tex"])), "x": e["x"], "y": e["y"]}
		var node := TextureRect.new()
		node.name = "Fighter_" + side
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(node)
		if side == "atk":
			_atk = node
			_atk_tex = table
		else:
			_def = node
			_def_tex = table
	var glow_tex := _tex("res://assets/sprites/menu/arena/baked/glow.png")
	for i in range((L["flames"] as Array).size()):
		var frames: Array = []
		var first: Dictionary = L["flames"][i][0]
		for e in L["flames"][i]:
			frames.append(_tex(str(e["tex"])))
		var g: Dictionary = L["glows"][i]
		var gr := TextureRect.new()
		gr.texture = glow_tex
		gr.size = glow_tex.get_size()
		gr.position = Vector2(float(g["cx"]), float(g["cy"])) - gr.size / 2.0
		gr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		gr.material = add
		_stage.add_child(gr)
		_glows.append(gr)
		var fr := TextureRect.new()
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(fr)
		var offs: Array = []
		for e in L["flames"][i]:
			offs.append(Vector2(float(e["x"]), float(e["y"])))
		fr.texture = frames[0]
		fr.position = Vector2(float(first["x"]), float(first["y"]))
		fr.size = (frames[0] as Texture2D).get_size()
		_flames.append({"node": fr, "frames": frames, "offs": offs, "idx": 0})
	for e in L["front"]:
		_crowd.append({"node": _rect(e), "y0": float(e["y"]), "period": e["period"], "duty": e["duty"], "phase": e["phase"]})


## ── 给门禁的读数(只读) ──

## 本背景用到的每一张贴图路径。门禁拿它断言「全是 arena/ 下的新素材」(R1-a / R1-b)。
func texture_paths() -> Array:
	return _tex_paths.duplicate()


## 两只角斗龟在【视口坐标】里的框(所有姿势的并集 + 出手位移)。门禁拿它断言没被按钮/赛程条盖住。
func fighter_rects() -> Array:
	var out: Array = []
	if _stage == null:
		return out
	var xf := _stage.get_global_transform()
	for table in [_atk_tex, _def_tex]:
		var u := Rect2()
		var first := true
		for pose in table.keys():
			var e: Dictionary = table[pose]
			var r := Rect2(Vector2(float(e["x"]), float(e["y"])) + Vector2(-1, -1),
				(e["tex"] as Texture2D).get_size() + Vector2(4, 2))
			u = r if first else u.merge(r)
			first = false
		out.append(xf * u)
	return out


## 此刻的动画状态快照。门禁连续推几步看它变没变(「会动」不能只看节点在不在)。
func debug_state() -> Dictionary:
	var crowd_y: Array = []
	for c in _crowd:
		crowd_y.append((c["node"] as Control).position.y - float(c["y0"]))
	var flame_idx: Array = []
	for f in _flames:
		flame_idx.append(int(f["idx"]))
	var light_a: Array = []
	for l in _lights:
		light_a.append((l["node"] as CanvasItem).modulate.a)
	var bt := 0.0
	if _banner != null and _banner.material is ShaderMaterial:
		var v = (_banner.material as ShaderMaterial).get_shader_parameter("t")
		bt = float(v) if v != null else 0.0     # 从没设过是 null; float(null) 会让门禁中途中止

	return {"t": _t, "crowd_y": crowd_y, "flame_idx": flame_idx, "light_a": light_a,
		"banner_t": bt, "atk_pose": _atk_pose, "def_pose": _def_pose,
		"atk_x": _atk.position.x if _atk != null else 0.0}
