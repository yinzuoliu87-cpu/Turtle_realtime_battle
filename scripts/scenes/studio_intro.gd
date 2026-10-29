class_name StudioIntro
extends CanvasLayer
## 工作室开场「灯鱼 Lampfish」(2026-10-29, 方案书 docs/plans/20261029-工作室开场动画.md)。
##
## 冷启动时盖在主菜单最上层播约 2.5 秒, 播完淡出露出已经搭好的主菜单。
## ★为什么是「盖一层」而不是新的 run/main_scene: 主菜单在下面同时搭好(不白等、切场不闪背景瓷砖),
##   run/main_scene 不变 ⇒ 几十个直接起主菜单的门禁、陪练号、实玩驱动一条都不用改。
## ★画面规格按 10 家商业开场逐帧研究定(方案书 §4.1): 纯色底 #0a0e18(= iPhone 启动屏同色) / 单色像素小标志 /
##   0.3 秒内看得清 / 点灯那一下有高峰 + 声音 / 字晚一拍逐个落下 / 停留段不冻结 / 0.3 秒淡出。
## 素材与音效: tools/build_studio_intro.py(确定性, 逐像素画, 0 次生成模型); 时间轴 TIMING 与那边逐项相同(门禁对账)。
##
## 不播: 无头(门禁 / 裁判)、陪练号(SIM_DRIVER=1)、NO_INTRO=1; 同一进程只播一次(回主菜单不重放)。

signal finished

const DIR := "res://assets/sprites/ui/studio_intro/"
const SFX := "res://assets/audio/sfx/studio_intro.wav"
const BG := Color8(10, 14, 24)
const LAYER := 9000
const NODE := "StudioIntro"
const S := 6                 ## 主像素(视口单位)
const SZ := 3                ## 中文副标像素
const SKIP_AFTER := 0.3      ## 开播 0.3 秒后点任意处跳到淡出
## 与 tools/build_studio_intro.py 的 TIMING 逐项相同(秒)。
const TIMING := {
	"spark1": 0.05, "spark2": 0.13, "ignite": 0.22,
	"letters": 0.52, "letter_step": 0.045, "zh": 0.98, "blink": 1.45,
	"fade": 2.2, "end": 2.5,
}
## 字母宽(1 倍像素)与字距: L A M P F I S H。与生成脚本 LETTERS 同形。
const LETTER_W := [6, 6, 8, 6, 6, 2, 6, 6]
const LETTER_GAP := 2
const LANTERN := Vector2i(3, 5)     ## 灯玻璃中心(1 倍像素, 小鱼图内)

## 【门禁注入点】≥0 时无视无头 / 环境判断: 1 = 要播, 0 = 不播。
static var force_override: int = -1
static var played := false

var t := 0.0
var _root: Control = null
var _fish: TextureRect = null
var _ticks: Array = []
var _rings: Array = []
var _rays: TextureRect = null
var _letters: Array = []
var _zh: TextureRect = null
var _tex := {}
var _fish_pos := Vector2.ZERO
var _word_pos := Vector2.ZERO
var _zh_pos := Vector2.ZERO
var _sfx: AudioStreamPlayer = null
var _done := false


static func should_play() -> bool:
	if played:
		return false
	if force_override >= 0:
		return force_override == 1
	if DisplayServer.get_name() == "headless":
		return false
	if OS.get_environment("SIM_DRIVER") == "1" or OS.get_environment("NO_INTRO") == "1":
		return false
	return true


## 主菜单 _ready 第一句调: 该播就在 root 上盖一层(延后一拍挂, root 在场景 _ready 期间不收孩子)。
static func play_once(tree: SceneTree) -> StudioIntro:
	if tree == null or not should_play():
		return null
	played = true
	var it := StudioIntro.new()
	it.name = NODE
	it.layer = LAYER
	Audio.bgm_hold = true
	tree.root.add_child.call_deferred(it)
	return it


func _tx(n: String) -> Texture2D:
	if not _tex.has(n):
		var p := DIR + n + ".png"
		_tex[n] = load(p) as Texture2D if ResourceLoader.exists(p) else null
	return _tex[n]


func _sprite(n: String, k: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _tx(n)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if r.texture != null:
		r.size = r.texture.get_size() * k
	_root.add_child(r)
	return r


func _ready() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_input)
	add_child(_root)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	## 叠放次序: 光线 / 光环 / 光芒 在小鱼底下, 字在最上
	for i in range(2):
		_ticks.append(_sprite("ticks_%d" % i, S))
	for i in range(4):
		_rings.append(_sprite("ring_%d" % i, S))
	_rays = _sprite("rays", S)
	_fish = _sprite("fish_off", S)
	_fish.name = "Fish"
	for i in range(8):
		var l := _sprite("letter_%d" % i, S)
		l.name = "Letter%d" % i
		_letters.append(l)
	_zh = _sprite("zh", SZ)
	_zh.name = "Zh"
	_layout()
	if ResourceLoader.exists(SFX):
		_sfx = AudioStreamPlayer.new()
		_sfx.stream = load(SFX)
		_sfx.volume_db = linear_to_db(maxf(0.0001, Audio.sfx_volume))
		add_child(_sfx)
		_sfx.play()
	_apply()


## 摆位: 小鱼在上、字标、中文副标, 整组竖直居中略偏上(与预览脚本同一套算法)。
func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	var fsz := _fish.size
	var word_w := 0
	for w in LETTER_W:
		word_w += w + LETTER_GAP
	word_w = (word_w - LETTER_GAP) * S
	var lh := (_letters[0] as TextureRect).size.y
	var total := fsz.y + 5 * S + lh + 4 * S + _zh.size.y
	var top := roundf(vs.y * 0.47 - total / 2.0)
	_fish_pos = Vector2(roundf(vs.x / 2.0 - fsz.x / 2.0), top)
	_word_pos = Vector2(roundf(vs.x / 2.0 - word_w / 2.0), top + fsz.y + 5 * S)
	_zh_pos = Vector2(roundf(vs.x / 2.0 - _zh.size.x / 2.0), _word_pos.y + lh + 4 * S)


func _center_on_lantern(r: TextureRect, dy: float) -> void:
	var c := _fish_pos + Vector2(LANTERN.x * S + S / 2.0, LANTERN.y * S + S / 2.0 + dy)
	r.position = (c - r.size / 2.0).round()


## 按 t 把每一层摆到该在的样子(纯函数式: 只看 t, 门禁可以直接跳到任一时刻量)。
func _apply() -> void:
	var tm := TIMING
	var st := "off"
	if (t >= tm["spark1"] and t < tm["spark1"] + 0.035) or (t >= tm["spark2"] and t < tm["spark2"] + 0.035):
		st = "on"
	if t >= tm["ignite"]:
		st = "flash" if t < tm["ignite"] + 0.10 else "on"
	if t >= tm["blink"] and t < tm["blink"] + 0.10:
		st = "blink"
	_fish.texture = _tx("fish_" + st)
	_fish.set_meta("state", st)
	## 惊醒一跳(整格): 点灯后 0.04~0.20 秒跳 2 格再落回; 停留段 1 格轻浮
	var dy := 0.0
	if t >= tm["ignite"] + 0.04 and t < tm["ignite"] + 0.20:
		dy = -roundf(2.0 * sin((t - tm["ignite"] - 0.04) / 0.16 * PI)) * S
	if t >= 1.1:
		dy = -S if sin((t - 1.1) * TAU / 1.2) > 0.3 else 0.0
	_fish.position = _fish_pos + Vector2(0, dy)
	var lit: bool = (st == "on" and t < tm["ignite"]) or t >= tm["ignite"] + 0.10
	for i in range(2):
		var k := _ticks[i] as TextureRect
		k.visible = lit and int(t / 0.14) % 2 == i
		_center_on_lantern(k, dy)
	var e: float = t - tm["ignite"]
	for i in range(4):
		var r := _rings[i] as TextureRect
		r.visible = e >= 0.0 and e < 0.32 and mini(int(e / 0.08), 3) == i
		_center_on_lantern(r, dy)
	_rays.visible = e >= 0.0 and e < 0.10
	_center_on_lantern(_rays, dy)
	var x := _word_pos.x
	for i in range(8):
		var l := _letters[i] as TextureRect
		var t0: float = tm["letters"] + i * tm["letter_step"]
		l.visible = t >= t0
		l.position = Vector2(x, _word_pos.y - (S if t < t0 + 0.05 else 0))
		x += (LETTER_W[i] + LETTER_GAP) * S
	_zh.visible = t >= tm["zh"]
	_zh.position = _zh_pos + Vector2(0, S if t < tm["zh"] + 0.06 else 0)
	var a := 1.0
	if t >= tm["fade"]:
		a = 1.0 - clampf((t - tm["fade"]) / (tm["end"] - tm["fade"]), 0.0, 1.0)
	_root.modulate.a = a


## 门禁 / 跳过用: 推进时间(钳 0.1 秒防卡顿一帧跳过整段)。
func advance(dt: float) -> void:
	if _done:
		return
	t += minf(dt, 0.1)
	_apply()
	## 留 1 微秒浮点余量: 按小步累加时 t 会停在 2.4999999, 差这一点就永远不收尾。
	if t >= float(TIMING["end"]) - 1e-6:
		_finish()


func _process(dt: float) -> void:
	advance(dt)


func skip() -> void:
	if t >= SKIP_AFTER and t < TIMING["fade"]:
		t = TIMING["fade"]
		_apply()


func _on_input(ev: InputEvent) -> void:
	if (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed) or (ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed):
		skip()


func _finish() -> void:
	_done = true
	Audio.release_bgm_hold(0.6)
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	## 半路被拆(换场景 / 退出)也要把背景音乐放开, 不许留静音。
	if not _done:
		Audio.release_bgm_hold(0.3)
