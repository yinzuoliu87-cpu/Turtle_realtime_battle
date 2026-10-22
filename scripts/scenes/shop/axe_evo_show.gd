extends RefCounted
## 小木斧进化演出(方案书 docs/plans/20261022-小木斧进化演出.md · 用户 2026-10-22「小木斧需要设计进化动画吧」)。
##
## 三处共用这一个:
##   · 商店里买小木斧当场进化 —— 买完当场播
##   · 结算(+15) / 战斗击杀(+5)造成的进化 —— 记在 `GameState.axe_evo_pending`, 进背包补放(用户 10-22「补到进背包时吧」)
##   · 四选一选定最终造物 —— 点下就播(加长版)
##
## ★节奏照参考实测(docs/plans/ref/20261022-进化动画参考/分析.md, 9 款游戏逐帧量的):
##   旧形态原色 → 变白剪影 → 新旧白剪影交替、越换越快(宝可梦第 3 世代的做法, 压到 0.8 秒)
##   → 新档位颜色的闪光盖住换图 → 1 帧硬切成新形态原色 + 一圈方块粒子 → 名字晚 0.3 秒出。
##   · 换图是硬切, 不做新旧交叉淡化(9 款里 6 款如此); 像素图只平移不缩放不旋转(像素游戏 3/5 款)。
##   · 普通进化总长 ≈2.4 秒(样本中位数 1.33 秒到揭晓); 最终造物一大轮只有一次, 拉长到 ≈3.9 秒。
##   · **不能跳过**(用户 2026-10-22「点一下就跳过？不行」): 播完自己收起, 有多段就一段接一段播。
## ★闪光 / 粒子全是程序画的纯色块 —— 不借别的装备的特效图(素材不复用)。
##   颜色从九个形态自己的待机帧里量出主色再提亮(见 TINT)。
## ★整段时间轴是纯函数 `state_at(t)`, 一条 tween_method 只负责把时间喂给 `_apply(t)` ——
##   门禁直接按时间点查状态, 不靠等动画真的跑完(无头 CI 上动画推进不稳, CLAUDE.md §3.5)。
## ★挂在宿主下的 CanvasLayer 上(盖住整屏、不被 UIFrame 收编), 门禁 / 测试模式瞬播。
const AE := preload("res://scripts/gamedata/axe_evolution.gd")
const AxeArtRef := preload("res://scripts/gamedata/axe_art.gd")

const NODE_NAME := "AxeEvoShow"
## 宿主的 `_rebuild()` 清子节点时跳过这一组(商店买完、四选一点完都会立刻重建整页)。
const GROUP := "axe_evo_show"
const LAYER := 60

## 九个形态第 0 帧不透明像素的并集是 (44,19)-(79,73), 外扩一圈。九张共用同一裁切 ⇒ 硬切时斧头不跳位。
const CROP := Rect2(40, 16, 44, 60)
const SCALE := 5.0        # 整数倍 + 最近邻, 像素边不糊(4 倍时实拍斧头压不住身后货架)

const T_DIM := 0.12       # 压暗
const T_OLD := 0.15       # 旧形态原色
const T_SIL := 0.12       # 旧形态变白剪影
## 白剪影每次停留多久(从新形态开始, 新旧交替)。奇数个 ⇒ 最后一下停在新形态上。
const SWAP := [0.12, 0.12, 0.09, 0.09, 0.07, 0.07, 0.05, 0.05, 0.04, 0.04, 0.033]
const SWAP_FINAL := [0.2, 0.2, 0.16, 0.16, 0.12, 0.12, 0.09, 0.09, 0.07, 0.07, 0.05, 0.05, 0.04, 0.04, 0.033]
const T_FLASH_UP := 0.05
const T_FLASH_DOWN := 0.25
const FLASH_PEAK := 0.85
const T_NAME_DELAY := 0.3
const T_NAME_IN := 0.15
const T_HOLD := 1.0       # 揭晓后停多久
const T_HOLD_FINAL := 1.8
const T_OUT := 0.2

const BURST_N := 24
const BURST_PX := 10.0    # 一个粒子 = 2 个贴图像素 × SCALE
const T_BURST := 0.45
const BURST_R0 := 90.0
const BURST_R1 := 260.0

## 九个形态的主色(第 0 帧不透明像素里量出来的主色再提亮)。
const TINT := {
	"wood": Color("#c08a4a"), "stone": Color("#b4aea2"), "iron": Color("#c8d0dc"),
	"gold": Color("#ffd23c"), "diamond": Color("#4ff0dc"),
	"undead": Color("#6cff58"), "seraph": Color("#fff2c8"), "holo": Color("#7ad8ff"), "ember": Color("#ffa040"),
}

const SIL_SHADER := """shader_type canvas_item;
uniform float white = 0.0;
void fragment() {
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), white);
}
"""

var host: Node
var _layer: CanvasLayer = null
var _queue: Array = []
var _done: Callable = Callable()
var played: int = 0       # 观测量: 一共开播了几段(门禁分母)
var force_anim := false   # 门禁量时间轴时用: 测试模式下也按真时长播

var _root: Control = null
var _axe: TextureRect = null
var _flash: ColorRect = null
var _name: Label = null
var _sub: Label = null
var _parts: Array = []
var _mat: ShaderMaterial = null
var _old_tex: Texture2D = null
var _new_tex: Texture2D = null
var _new_frames: Array = []
var _old_key := ""
var _new_key := ""
var _final := false
var _center := Vector2.ZERO
var _tw: Tween = null


func _init(h: Node) -> void:
	host = h


func busy() -> bool:
	return _layer != null and is_instance_valid(_layer)


## steps: [{"from": 档位下标, "to": 档位下标}] 或 [{"final": 造物 key}]; 一段一段播, 播完调 done。
func play(steps: Array, done: Callable = Callable()) -> void:
	for s in steps:
		if s is Dictionary:
			_queue.append(s)
	if done.is_valid():
		_done = done
	if not busy():
		_next()


func _next() -> void:
	if _queue.is_empty():
		var d := _done
		_done = Callable()
		if d.is_valid():
			d.call()
		return
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		_queue.clear()
		return
	_show(_queue.pop_front())


## ── 时间轴(纯函数) ─────────────────────────────────────────────

static func swaps(final: bool) -> Array:
	return SWAP_FINAL if final else SWAP


## 换图(闪光峰值)那一刻。
static func t_cut(final: bool) -> float:
	var t := T_DIM + T_OLD + T_SIL
	for d in swaps(final):
		t += float(d)
	return t


static func total(final: bool) -> float:
	return t_cut(final) + (T_HOLD_FINAL if final else T_HOLD) + T_OUT


## t 时刻画面上是什么: form = "old"/"new" · white = 剪影(0/1) · flash = 闪光不透明度 ·
## name_a = 名字不透明度 · alpha = 整层不透明度 · burst = 粒子进度(-1 = 还没炸) · idle = 新形态待机帧号。
static func state_at(t: float, final: bool) -> Dictionary:
	var cut := t_cut(final)
	var st := {"form": "old", "white": 0.0, "flash": 0.0, "name_a": 0.0, "alpha": 1.0, "burst": -1.0, "idle": 0, "swap_i": -1}
	st["alpha"] = clampf(t / T_DIM, 0.0, 1.0)
	var end_t := total(final)
	if t > end_t - T_OUT:
		st["alpha"] = clampf((end_t - t) / T_OUT, 0.0, 1.0)
	if t < cut:
		var t0 := T_DIM + T_OLD
		if t >= t0:
			st["white"] = 1.0
		var ts := t0 + T_SIL
		if t >= ts:
			var acc := ts
			var arr := swaps(final)
			for i in range(arr.size()):
				acc += float(arr[i])
				if t < acc:
					st["swap_i"] = i
					st["form"] = "new" if i % 2 == 0 else "old"
					break
		if t >= cut - T_FLASH_UP:
			st["flash"] = FLASH_PEAK * (t - (cut - T_FLASH_UP)) / T_FLASH_UP
		return st
	st["form"] = "new"
	var u := t - cut
	st["flash"] = FLASH_PEAK * clampf(1.0 - u / T_FLASH_DOWN, 0.0, 1.0)
	st["burst"] = clampf(u / T_BURST, 0.0, 1.0)
	st["name_a"] = clampf((u - T_NAME_DELAY) / T_NAME_IN, 0.0, 1.0)
	st["idle"] = int(u * float(AxeArtRef.FPS["idle"])) % 8
	return st


## ── 画面 ─────────────────────────────────────────────────────

func _frame_tex(key: String, frame: int) -> Texture2D:
	var path := "res://assets/sprites/vfx/eq096-axe-%s-idle.png" % key
	if not ResourceLoader.exists(path):
		return null
	var at := AtlasTexture.new()
	at.atlas = load(path)
	at.region = Rect2(CROP.position.x + float(frame * AxeArtRef.CELL), CROP.position.y, CROP.size.x, CROP.size.y)
	return at


func _show(step: Dictionary) -> void:
	played += 1
	var final_key := str(step.get("final", ""))
	_final = final_key != ""
	var from_i: int = int(step.get("from", AE.STAGES.size() - 1 if _final else 0))
	var to_i: int = int(step.get("to", from_i))
	_old_key = str(AE.display(from_i, "")["key"])
	var disp: Dictionary = AE.display(to_i, final_key)
	_new_key = str(disp["key"])
	_old_tex = _frame_tex(_old_key, 0)
	_new_frames = []
	for f in range(8):
		var ft := _frame_tex(_new_key, f)
		if ft != null:
			_new_frames.append(ft)
	_new_tex = _new_frames[0] if not _new_frames.is_empty() else null
	var tint: Color = TINT.get(_new_key, Color.WHITE)

	_layer = CanvasLayer.new()
	_layer.name = NODE_NAME
	_layer.layer = LAYER
	_layer.add_to_group(GROUP)
	host.add_child(_layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # 盖住底下的点击(播的时候不能买、不能点别的); 点了也不跳过
	_layer.add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.9)   # 0.78 实拍时身后货架的辣椒 / 斧头还在抢眼
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var vs: Vector2 = host.get_viewport().get_visible_rect().size
	var asz := CROP.size * SCALE
	_axe = TextureRect.new(); _axe.name = "Axe"
	_axe.texture = _old_tex
	_axe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_axe.stretch_mode = TextureRect.STRETCH_SCALE
	_axe.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_axe.size = asz
	_axe.position = Vector2(roundf((vs.x - asz.x) * 0.5), roundf(vs.y * 0.44 - asz.y * 0.5))
	_axe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new(); sh.code = SIL_SHADER
	_mat = ShaderMaterial.new(); _mat.shader = sh
	_axe.material = _mat
	_root.add_child(_axe)
	_center = _axe.position + asz * 0.5

	_parts = []
	for i in range(BURST_N):
		var p := ColorRect.new()
		p.size = Vector2(BURST_PX, BURST_PX)
		p.color = tint if i % 2 == 0 else tint.lerp(Color.WHITE, 0.6)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.visible = false
		_root.add_child(p)
		_parts.append(p)

	_name = Label.new(); _name.name = "FormName"
	_name.text = str(disp["name"])
	_name.add_theme_font_size_override("font_size", 40)
	_name.add_theme_color_override("font_color", Color("#ffd93d"))
	_name.add_theme_color_override("font_outline_color", Color("#1a0e05")); _name.add_theme_constant_override("outline_size", 8)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.size = Vector2(vs.x, 56); _name.position = Vector2(0, _axe.position.y + asz.y + 10.0)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_name)
	_sub = Label.new(); _sub.name = "SubLine"
	_sub.text = "最终造物" if _final else "售价 %d 费" % int(disp["cost"])
	_sub.add_theme_font_size_override("font_size", 24)
	_sub.add_theme_color_override("font_color", Color("#e8dcc4"))
	_sub.add_theme_color_override("font_outline_color", Color("#1a0e05")); _sub.add_theme_constant_override("outline_size", 5)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.size = Vector2(vs.x, 34); _sub.position = Vector2(0, _name.position.y + 56.0)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sub)

	_flash = ColorRect.new(); _flash.name = "Flash"
	_flash.color = tint.lerp(Color.WHITE, 0.55)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	if _instant():
		_apply(t_cut(_final) + T_NAME_DELAY + T_NAME_IN)   # 停在揭晓后的画面, 下一帧收起
		_close.call_deferred()
		return
	_apply(0.0)
	_tw = _root.create_tween()
	_tw.tween_method(_apply, 0.0, total(_final), total(_final))
	_tw.tween_callback(_close)


## 把 t 时刻的状态画上去。
func _apply(t: float) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var st := state_at(t, _final)
	_root.modulate.a = float(st["alpha"])
	if str(st["form"]) == "new":
		## 揭晓之后放新形态的待机动画; 揭晓之前(剪影交替)只用第 0 帧
		_axe.texture = _new_frames[int(st["idle"])] if float(st["burst"]) >= 0.0 and _new_frames.size() == 8 else _new_tex
	else:
		_axe.texture = _old_tex
	_mat.set_shader_parameter("white", float(st["white"]))
	_flash.color.a = float(st["flash"])
	_name.modulate.a = float(st["name_a"])
	_sub.modulate.a = float(st["name_a"])
	var b: float = float(st["burst"])
	for i in range(_parts.size()):
		var p: ColorRect = _parts[i]
		if b < 0.0 or b >= 1.0:
			p.visible = false
			continue
		p.visible = true
		var ang := TAU * float(i) / float(_parts.size()) + 0.17 * float(i % 3)
		var r := lerpf(BURST_R0, BURST_R1 * (0.75 + 0.25 * float(i % 4) / 3.0), 1.0 - pow(1.0 - b, 3.0))
		p.position = (_center + Vector2(cos(ang), sin(ang)) * r - p.size * 0.5).round()
		p.modulate.a = 1.0 - b


## 现在画面上是哪个形态 / 是不是剪影(门禁读)。
func shown_key() -> String:
	if _axe == null or not is_instance_valid(_axe):
		return ""
	var at := _axe.texture as AtlasTexture
	if at == null or at.atlas == null:
		return ""
	return at.atlas.resource_path.get_file().trim_prefix("eq096-axe-").trim_suffix("-idle.png")


func shown_white() -> float:
	return float(_mat.get_shader_parameter("white")) if _mat != null else 0.0


func _close() -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = null
	if _layer != null and is_instance_valid(_layer):
		var p := _layer.get_parent()
		if p != null:
			p.remove_child(_layer)
		_layer.queue_free()
	_layer = null
	_root = null
	_parts = []
	_next()


## 门禁 / 测试模式: 不等动画(否则每个经过商店 / 背包的门禁都要多等几秒、模拟号也被挡住)。
func _instant() -> bool:
	if force_anim:
		return false
	var gs = host.get_node_or_null("/root/GameState") if host != null else null
	return gs != null and bool(gs.get("test_mode"))
