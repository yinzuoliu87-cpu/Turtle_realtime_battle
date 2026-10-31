class_name ChampionFx
extends Control
## champion_fx.gd —— 冠军收盘的像素特效层: 背光(转动的光束)/ 蓄力汇聚火花 / 像素彩带 / 落地扬尘。
## ★一律硬边方块(2px 网格), 不用软粒子 —— 与对阵图那套像素美术一个手感(研究笔记「像素风翻译」:
##   彩带 = 像素纸屑、白闪 = 全屏白 2 帧再淡出、光点 = 2×2 发光像素)。
## ★确定性: 粒子用自带种子的 RNG, 只由 `step(dt)` 推进(演出层每帧喂它), 同样的输入画出同样的帧。

const CONFETTI_COLS := [Color("#f4c552"), Color("#ffe9a8"), Color("#e2484e"), Color("#4cc9f0"),
	Color("#7ee08a"), Color("#f6ecd9"), Color("#c77dff")]
const GRID := 2.0
const UI := preload("res://scripts/scenes/bracket/champion_ui.gd")

var rays_center := Vector2.ZERO
var rays_radius := 420.0
var rays_alpha := 0.0          # 0 = 不画
var rays_rot := 0.0
var rays_speed := 0.35         # 弧度 / 秒
var rays_col := Color("#ffd772")

var rng := RandomNumberGenerator.new()
var parts: Array = []          # {p: Vector2, v: Vector2, c: Color, w, h, spin, ph, life, kind}
var rain_rate := 0.0           # 每秒从顶上撒几片(0 = 不撒)
var _rain_acc := 0.0
var t := 0.0


func _init() -> void:
	rng.seed = 20261101
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "ChampionFx"


func live_count() -> int:
	return parts.size()


## 蓄力: n 颗火花从一圈外沿往 c 汇聚, dur 秒到。
func converge(c: Vector2, n: int, dur: float, radius: float = 300.0) -> void:
	for i in range(n):
		var a := rng.randf() * TAU
		var r := radius * (0.7 + rng.randf() * 0.5)
		var start := c + Vector2(cos(a), sin(a)) * r
		parts.append({"kind": "spark", "p": start, "from": start, "to": c, "age": -rng.randf() * dur * 0.35,
			"dur": dur * (0.55 + rng.randf() * 0.3), "c": CONFETTI_COLS[i % 2], "w": 4.0, "h": 4.0})


## 彩带一炮: 从 c 往上 / 往两边炸开, 再飘落。
func burst(c: Vector2, n: int, power: float = 520.0) -> void:
	for i in range(n):
		var a := -PI * 0.5 + (rng.randf() - 0.5) * PI * 1.25
		var sp := power * (0.45 + rng.randf() * 0.75)
		_add_paper(c + Vector2((rng.randf() - 0.5) * 40.0, 0), Vector2(cos(a), sin(a)) * sp)


## 落地扬尘: 往两侧贴地散开的灰点。
func dust(c: Vector2, n: int, width: float = 120.0) -> void:
	for i in range(n):
		var dir := -1.0 if i % 2 == 0 else 1.0
		parts.append({"kind": "dust", "p": c + Vector2(dir * rng.randf() * width * 0.3, -rng.randf() * 6.0),
			"v": Vector2(dir * (60.0 + rng.randf() * 140.0), -20.0 - rng.randf() * 50.0),
			"age": 0.0, "dur": 0.45 + rng.randf() * 0.3, "c": Color("#c9b79a"), "w": 4.0, "h": 4.0})


func _add_paper(p: Vector2, v: Vector2) -> void:
	var c: Color = CONFETTI_COLS[rng.randi() % CONFETTI_COLS.size()]
	var long := rng.randf() < 0.5
	parts.append({"kind": "paper", "p": p, "v": v, "c": c, "w": 6.0 if long else 4.0, "h": 3.0 if long else 4.0,
		"spin": 4.0 + rng.randf() * 8.0, "ph": rng.randf() * TAU, "age": 0.0, "dur": 5.0 + rng.randf() * 2.0,
		"sway": 18.0 + rng.randf() * 26.0})


func step(dt: float) -> void:
	t += dt
	rays_rot = fmod(rays_rot + rays_speed * dt, TAU)
	if rain_rate > 0.0:
		_rain_acc += rain_rate * dt
		while _rain_acc >= 1.0:
			_rain_acc -= 1.0
			_add_paper(Vector2(rng.randf() * size.x, -10.0), Vector2((rng.randf() - 0.5) * 40.0, 60.0 + rng.randf() * 60.0))
	var keep: Array = []
	for q in parts:
		q["age"] = float(q["age"]) + dt
		var age: float = q["age"]
		match str(q["kind"]):
			"spark":
				if age >= 0.0:
					var k := UI.ease_in(age / float(q["dur"]))
					q["p"] = (q["from"] as Vector2).lerp(q["to"], k)
			"paper":
				var v: Vector2 = q["v"]
				v.y = minf(v.y + 900.0 * dt, 150.0)          # 纸片: 先被抛起, 很快到终速飘落
				v.x *= pow(0.25, dt)
				q["v"] = v
				q["p"] = (q["p"] as Vector2) + v * dt + Vector2(sin(age * 3.0 + float(q["ph"])) * float(q["sway"]) * dt, 0.0)
			"dust":
				var v2: Vector2 = q["v"]
				v2 *= pow(0.05, dt)
				q["v"] = v2
				q["p"] = (q["p"] as Vector2) + v2 * dt
		if age < float(q["dur"]) and (q["p"] as Vector2).y < size.y + 20.0:
			keep.append(q)
	parts = keep
	queue_redraw()


func _snap(p: Vector2) -> Vector2:
	return Vector2(floorf(p.x / GRID) * GRID, floorf(p.y / GRID) * GRID)


func _draw() -> void:
	if rays_alpha > 0.01:
		_draw_rays()
	for q in parts:
		var age: float = q["age"]
		if age < 0.0:
			continue
		var c: Color = q["c"]
		var p := _snap(q["p"])
		match str(q["kind"]):
			"spark":
				var k: float = age / float(q["dur"])
				c.a = clampf(k * 3.0, 0.0, 1.0)
				draw_rect(Rect2(p, Vector2(4, 4)), c)
				var back := _snap((q["p"] as Vector2).lerp(q["from"], 0.08))
				draw_rect(Rect2(back, Vector2(2, 2)), Color(c, c.a * 0.6))
			"paper":
				var fl := absf(cos(age * float(q["spin"]) + float(q["ph"])))      # 翻面: 宽度随转角变
				var w := maxf(GRID, roundf(float(q["w"]) * fl / GRID) * GRID)
				var fade := 1.0 - UI.seg(age, float(q["dur"]) - 0.6, float(q["dur"]))
				var cc := c.darkened(0.35) if fl < 0.4 else c
				cc.a = fade
				draw_rect(Rect2(p, Vector2(w, float(q["h"]))), cc)
			"dust":
				c.a = 1.0 - age / float(q["dur"])
				draw_rect(Rect2(p, Vector2(4, 4)), c)


## 背光: 12 道硬边扇形光束绕中心转(像素风的「光柱」), 外圈一道淡光环。
func _draw_rays() -> void:
	var n := 12
	var c := rays_center
	for i in range(n):
		var a0 := rays_rot + float(i) * TAU / float(n)
		var half := TAU / float(n) * 0.22
		var col := Color(rays_col, rays_alpha * (0.34 if i % 2 == 0 else 0.20))
		var pts := PackedVector2Array([c,
			c + Vector2(cos(a0 - half), sin(a0 - half)) * rays_radius,
			c + Vector2(cos(a0 + half), sin(a0 + half)) * rays_radius])
		draw_colored_polygon(pts, col)
	## 中心一团暖光(三层同心圆叠出阶梯亮度, 不做软渐变)
	for k in range(3):
		draw_circle(c, rays_radius * (0.17 - float(k) * 0.045), Color(rays_col, rays_alpha * 0.11))
