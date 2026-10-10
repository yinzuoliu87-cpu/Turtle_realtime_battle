extends Node
## verify_pct_glyph.gd — 自证: 像素字 m6x11 的「%」不再长得像「×」
## 跑法: godot --headless --path . res://tests/verify_pct_glyph.tscn --quit-after 300
##
## 背景(2026-10-10 视觉审计): m6x11 原版「%」只有 x 高(8 行), 两端都是「##..##」, 斜杠 3px 粗,
##   与它自己的「×」(6 行、上下也是「##..##」)几乎同形。游戏字号 13/15px 下「25% 暴击率」读成「25x」,
##   公式「0.2%×攻击力」两个符号挨着完全分不出。全游戏所有百分比(图鉴/商店/战斗 HUD/提示)都受影响。
## 修法: 直接改字体文件 assets/fonts/m6x11.ttf 里 `percent` 这一个字形(唯一中心点——
##   主题回退链、MainMenu/Matchmaking 自建链、战斗飘字直接 load m6x11 全都吃到)。
##   新字形 = 与数字同高(11 行)的 2px 斜杠(取自本字体自己的「/」)+ 两角 2x2 点; advance 仍是 7px。
##
## 判据(按字体文件本身在 16px = 1 字体像素 = 1 屏幕像素 下栅格化):
##   ① 「%」的像素图 == 下面的 EXPECTED(逐像素)
##   ② 「%」墨迹高 == 数字「0」墨迹高, 且 > 「×」墨迹高(x 高的东西才会跟 × 混)
##   ③ 「%」与「×」像素图不同; advance: % / 0-9 / × 与改前一致(不动排版)
##   ④ 主题默认字体 = FontVariation(base=m6x11), 且 m6x11 自己有「%」⇒ 屏幕上的 % 确实由它画
## 反向验证: 把原版 m6x11.ttf 放回去重导入, ①② 红(原版 % 高 8 行 / 与 × 顶行同形)。

const EXPECTED := [
	"##..##",
	"##..##",
	"...###",
	"...##.",
	"..###.",
	"..##..",
	".###..",
	".##...",
	"###...",
	"##..##",
	"##..##",
]
## 改前的 advance(px@16), 不许动
const ADV := {"%": 7, "×": 7, "0": 7, "1": 7, "2": 7, "5": 7, "9": 7, ".": 3}

var _fail := 0
var _pass := 0

func _ok(c: bool, msg: String) -> void:
	if c:
		_pass += 1; print("  [PASS] ", msg)
	else:
		_fail += 1; print("  [FAIL] ", msg)

## 按轮廓做点在多边形内(本字体全是直线段像素方块), 采样每个像素中心。返回 {rows:Array[String], top:int, h:int}
func _raster(ts: TextServer, rid: RID, ch: String) -> Dictionary:
	var size := 16
	var gi := ts.font_get_glyph_index(rid, size, ch.unicode_at(0), 0)
	var d: Dictionary = ts.font_get_glyph_contours(rid, size, gi)
	var pts: PackedVector3Array = d.get("points", PackedVector3Array())
	var ends: PackedInt32Array = d.get("contours", PackedInt32Array())
	var polys: Array = []
	var s := 0
	for e in ends:
		var poly: Array = []
		for i in range(s, e + 1):
			poly.append(Vector2(pts[i].x, pts[i].y))
		polys.append(poly)
		s = e + 1
	var rows: Array = []
	var top := 999
	var bot := -999
	for py in range(-14, 4):
		var r := ""
		for px in range(0, 8):
			var p := Vector2(px + 0.5, py + 0.5)
			var inside := false
			for poly in polys:
				var n: int = poly.size()
				for i in n:
					var a: Vector2 = poly[i]
					var b: Vector2 = poly[(i + 1) % n]
					if (a.y > p.y) != (b.y > p.y) and p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y):
						inside = not inside
			r += "#" if inside else "."
		if r.contains("#"):
			top = mini(top, py); bot = maxi(bot, py)
		rows.append(r)
	var ink: Array = []
	if top <= bot:
		for py in range(top, bot + 1):
			ink.append((rows[py + 14] as String).substr(0, 6))
	return {"rows": ink, "top": top, "h": (bot - top + 1) if top <= bot else 0, "npts": pts.size()}

func _ready() -> void:
	var m6 := load("res://assets/fonts/m6x11.ttf") as FontFile
	_ok(m6 != null, "m6x11 加载")
	if m6 == null:
		get_tree().quit(1); return
	var ts := TextServerManager.get_primary_interface()
	var rid := m6.get_rids()[0] if m6.get_rids().size() > 0 else RID()
	_ok(rid.is_valid(), "m6x11 有字体 RID")

	var pct := _raster(ts, rid, "%")
	var mul := _raster(ts, rid, "×")
	var zero := _raster(ts, rid, "0")
	print("[分母] 轮廓点数 %%=%d ×=%d 0=%d" % [pct.npts, mul.npts, zero.npts])
	_ok(int(pct.npts) > 0 and int(mul.npts) > 0 and int(zero.npts) > 0, "三个字形都取到了轮廓(非空检查)")
	print("  %% 像素图 (高 %d):" % pct.h)
	for r in pct.rows: print("    ", r)

	# ①
	_ok(pct.rows == EXPECTED, "① 「%」像素图 == 设计稿 (11x6)")
	# ②
	_ok(int(pct.h) == int(zero.h), "② 「%%」高 %d == 数字「0」高 %d" % [pct.h, zero.h])
	_ok(int(pct.h) > int(mul.h), "② 「%%」高 %d > 「×」高 %d" % [pct.h, mul.h])
	_ok(int(pct.top) == int(zero.top), "② 「%」与数字顶对齐 (同一基线高度)")
	# ③
	_ok(pct.rows != mul.rows, "③ 「%」与「×」像素图不同")
	for ch in ADV.keys():
		var gi := ts.font_get_glyph_index(rid, 16, (ch as String).unicode_at(0), 0)
		var adv: Vector2 = ts.font_get_glyph_advance(rid, 16, gi)
		_ok(is_equal_approx(adv.x, float(ADV[ch])), "③ advance「%s」= %.1f (期望 %d, 排版不动)" % [ch, adv.x, ADV[ch]])
	# ④
	var th := load("res://assets/themes/default_theme.tres") as Theme
	var fv := th.default_font as FontVariation
	_ok(fv != null and fv.base_font == m6, "④ 主题默认字体 = FontVariation(base=m6x11)")
	_ok(m6.has_char(0x25), "④ m6x11 自带「%」⇒ 回退链第一张就画它, 不会落到 Noto")

	if _fail == 0:
		print("ALL PASS (%d/%d) — 「%%」与「×」在像素字里可分辨" % [_pass, _pass])
	else:
		print("FAILED %d/%d" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)
