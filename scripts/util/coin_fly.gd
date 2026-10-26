extends Control
class_name CoinFly
## 深海币入账动画(2026-10-26 · 方案书 docs/plans/20261026b-周六流程.md §4 F)。
##
## 用户 10-26「获得深海币有动画吗，看看商业游戏」。节奏照 Royal Match 回主界面那一段逐帧量的
##   (docs/studies/20261026-深海币入账动画逐帧.md):
##   ① 原地亮出「+N」和一小堆币(弹一下)  ② 停 HOLD_SEC 让人看清拿了多少
##   ③ 币一枚一枚弹起、走弧线飞向钱包(间隔 GAP_SEC, 每枚 FLY_SEC)
##   ④ 每到一枚, 钱包数字整步跳一次 + 图标弹一下(1.0 → 1.2 → 1.0)并闪白
##   ⑤ 数字滚动总长不随金额拉长: 最多 MAX_COINS 枚, 每枚分摊整数、最后一枚补齐余数(`split`)
##
## ★只管【显示】: 真余额在数据层早已入账(结算 / 补发当场就加进 `meta_deepsea_coins`), 这里只让钱包数字从旧值走到新值。
##   ⇒ 点任意处 = 剩下的币瞬间到达、数字跳到终值(`finish`); 不吞点击(底下的按钮照常能点)。
## ★「上次给玩家看过的余额」记在 `seen` —— 钱包每次出现时问 `gain_since_seen(真值)`, 多出来的那一截就是要飞的。
##   进程刚起(seen < 0)不算收入: 开机那一刻的余额没有「旧值」可言。

const COIN_TEX := preload("res://assets/sprites/menu/ic-deepsea.png")
const NODE_NAME := "CoinFly"
const MAX_COINS := 10          # 枚数上限(Royal Match +302 也是 10 枚)
const HOLD_SEC := 0.5          # 「+N」与币堆亮出来之后停多久
const GAP_SEC := 0.1           # 相邻两枚起飞间隔
const FLY_SEC := 0.45          # 每枚从起点到钱包
const COIN_PX := 34.0          # 飞行中的币(源图 64, 最近邻缩; 30 实拍在手机比例下偏小)
const PUNCH := 1.2             # 图标弹一下的峰值
## 翻面: x 方向离散的 4 档宽度(像素风不做平滑旋转), 每档停 FLIP_STEP 秒。
const FLIP_SCALES := [1.0, 0.55, 0.15, 0.55]
const FLIP_STEP := 0.06

static var seen: int = -1

var done := false
var shown := 0                 # 钱包此刻显示的数
var _final := 0
var _label: Label = null
var _icon: Control = null
var _coins: Array = []         # [TextureRect]
var _amt_label: Label = null
var _portions: Array = []
var _landed := 0
var _t := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _paths: Array = []         # 每枚: [起点, 控制点, 终点]

signal finished


## 本次钱包出现时, 比上次多了多少(负数 / 第一次 ⇒ 0)。调完 `seen` 就记成真值。
static func gain_since_seen(real: int) -> int:
	if seen < 0:
		seen = real
		return 0
	var g: int = real - seen
	seen = real
	return maxi(0, g)


## 金额拆成每枚的份额: 枚数 = min(金额, MAX_COINS), 平分取整, 余数落在最后一枚。
static func split(amount: int, max_coins: int = MAX_COINS) -> Array:
	if amount <= 0:
		return []
	var n: int = mini(amount, max_coins)
	var base: int = amount / n
	var out: Array = []
	for i in range(n):
		out.append(base)
	out[n - 1] = int(out[n - 1]) + amount - base * n
	return out


## 开一段入账动画。host = 挂在谁下面(场景根); from = 币堆中心(画布坐标);
## label / icon = 钱包的数字与图标(动画期间本函数改 label.text); start = 钱包现在显示的数; amount = 要飞进去多少。
## amount <= 0 ⇒ 什么都不建, 返回 null。
static func play(host: Node, from: Vector2, label: Label, icon: Control, start: int, amount: int) -> CoinFly:
	if amount <= 0 or host == null or label == null:
		return null
	var cf := CoinFly.new()
	cf.name = NODE_NAME
	cf._from = from
	cf._label = label
	cf._icon = icon
	cf.shown = start
	cf._final = start + amount
	cf._portions = split(amount)
	host.add_child(cf)
	cf._build(amount)
	return cf


func _build(amount: int) -> void:
	top_level = true
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_label.text = str(shown)
	_to = _icon.get_global_rect().get_center() if _icon != null and is_instance_valid(_icon) else _label.get_global_rect().get_center()
	## 币堆: 中心一圈错开摆, 后摆的压在先摆的上面。
	var n: int = _portions.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261026 + amount   # 同一笔钱每次长得一样(截图可复现); 不碰全局随机
	for i in range(n):
		var c := TextureRect.new()
		c.texture = COIN_TEX
		c.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		c.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(COIN_PX, COIN_PX)
		c.pivot_offset = c.size / 2.0
		var ang: float = TAU * float(i) / float(maxi(1, n)) + rng.randf_range(-0.3, 0.3)
		var rad: float = 0.0 if i == 0 else rng.randf_range(10.0, 22.0)
		var p: Vector2 = _from + Vector2(cos(ang), sin(ang) * 0.6) * rad + Vector2(0.0, 18.0)
		c.position = p - c.size / 2.0
		c.scale = Vector2.ZERO
		add_child(c)
		_coins.append(c)
		## 弧线: 先往上弹(控制点在两端连线中点的上方), 左右各抖 ±20。
		var mid: Vector2 = (p + _to) / 2.0
		var ctrl: Vector2 = Vector2(mid.x + rng.randf_range(-20.0, 20.0), minf(p.y, _to.y) - 90.0 - rng.randf_range(0.0, 40.0))
		_paths.append([p, ctrl, _to + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))])
	_amt_label = Label.new()
	_amt_label.name = "CoinFlyAmount"
	_amt_label.text = "+%d" % amount
	_amt_label.add_theme_font_size_override("font_size", 44)
	_amt_label.add_theme_color_override("font_color", Color("#ffd93d"))
	_amt_label.add_theme_color_override("font_outline_color", Color("#1a0e05"))
	_amt_label.add_theme_constant_override("outline_size", 8)
	_amt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_amt_label.size = Vector2(240.0, 60.0)
	_amt_label.position = _from - Vector2(120.0, 66.0)
	_amt_label.pivot_offset = _amt_label.size / 2.0
	_amt_label.scale = Vector2(0.4, 0.4)
	_amt_label.modulate.a = 0.0
	add_child(_amt_label)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_amt_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_amt_label, "modulate:a", 1.0, 0.15)
	for i in range(_coins.size()):
		tw.tween_property(_coins[i], "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.02 * i)


## 一帧推进。★自己数时间(不用每枚一条 tween): 「点一下全部到达」只要把时钟拨到头, 不必挨个杀 tween。
func _process(delta: float) -> void:
	if done:
		return
	_t += delta
	var t0: float = HOLD_SEC + 0.25
	for i in range(_coins.size()):
		var c: TextureRect = _coins[i]
		if c == null or not is_instance_valid(c) or not c.visible:
			continue
		var k: float = (_t - t0 - GAP_SEC * i) / FLY_SEC
		if k <= 0.0:
			continue
		if k >= 1.0:
			c.visible = false
			_land(i)
			continue
		var e: float = 0.35 * k + 0.65 * k * k   # 带一点初速弹起, 越飞越快扑进钱包(单调, 不回退)
		var pth: Array = _paths[i]
		var a: Vector2 = pth[0]
		var b: Vector2 = pth[1]
		var d: Vector2 = pth[2]
		var pos: Vector2 = a.lerp(b, e).lerp(b.lerp(d, e), e)
		c.position = pos - c.size / 2.0
		var step: int = int((_t - t0 - GAP_SEC * i) / FLIP_STEP) % FLIP_SCALES.size()
		var sc: float = lerpf(1.0, 0.7, k)
		c.scale = Vector2(float(FLIP_SCALES[step]) * sc, sc)
	if _amt_label != null and _landed > 0:
		_amt_label.modulate.a = 1.0 - float(_landed) / float(maxi(1, _coins.size()))
	if _landed >= _coins.size():
		_end()


## 第 i 枚到了: 数字整步跳 + 图标弹一下闪白。
func _land(i: int) -> void:
	_landed += 1
	shown += int(_portions[i])
	if i == _portions.size() - 1 or _landed >= _portions.size():
		shown = _final
	if _label != null and is_instance_valid(_label):
		_label.text = str(shown)
	if _icon != null and is_instance_valid(_icon):
		_icon.pivot_offset = _icon.size / 2.0
		_icon.scale = Vector2(PUNCH, PUNCH)
		_icon.modulate = Color(2.2, 2.2, 2.2, 1.0)
		var tw := _icon.create_tween().set_parallel(true)
		tw.tween_property(_icon, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_icon, "modulate", Color.WHITE, 0.14)


## 点任意处 ⇒ 剩下的瞬间到达。★不吞事件: 底下的按钮照常收到这一下。
func _input(e: InputEvent) -> void:
	if done:
		return
	if (e is InputEventMouseButton and (e as InputEventMouseButton).pressed) or (e is InputEventScreenTouch and (e as InputEventScreenTouch).pressed):
		finish()


## 立刻收尾: 数字到终值, 币全收掉。
func finish() -> void:
	if done:
		return
	_end()


func _end() -> void:
	done = true
	shown = _final
	if _label != null and is_instance_valid(_label):
		_label.text = str(_final)
	if _icon != null and is_instance_valid(_icon):
		_icon.scale = Vector2.ONE
		_icon.modulate = Color.WHITE
	finished.emit()
	queue_free()
