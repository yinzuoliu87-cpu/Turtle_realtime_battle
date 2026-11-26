"""shop_week_strip_1127.py —— 商店顶栏中间一块木牌「本周羁绊」+ 本周 10 个大羁绊的图标(方案书 20261124d; 用户 11-27「直接做就好了呀」)
顶栏中间本来空着(用户 08-15 删了页名, 「中间给你这么空位你在干啥啊」); 木牌与右上角钱袋牌同一张(_plank), 装进 _coin_box ⇒ 4:3 上跟着顶栏走。
图标 32×32 原尺寸、最近邻(像素网格不打烂)。点任意一枚 ⇒ 吐司说出这 10 个的名字。一次性; 原行尾二进制读写。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REL = "scripts/scenes/ShopScene.gd"
p = os.path.join(ROOT, REL)
raw = open(p, "rb").read()
nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")

A = "\t_tut_coin = coin   # 教学高亮\"币\"锚点\n"
assert s.count(A) == 1, s.count(A)
s = s.replace(A, A + "\t_build_week_strip(cpx)   # 本周羁绊(11-27)\n")

B = "## 场景底图(2026-10-21): 原背景去掉货柜与左下半截宝箱、四边外扩"
assert s.count(B) == 1
s = s.replace(B, """## 顶栏中间「本周羁绊」木牌(11-27 · 方案书 20261124d): 商店这周只出这 10 个大羁绊的装备(小木斧 / 香火石不轮换, 不列)。
##   左沿接在左上页签之后(WEEK_X), 右沿离钱袋牌留 16; 图标原尺寸 32、最近邻。点一下 ⇒ 吐司报这 10 个的名字(手机上没有悬停)。
const WEEK_X := 340.0
const WEEK_ICON := 32.0
const WEEK_GAP := 10.0

func _build_week_strip(coin_x: float) -> void:
	var syns: Array = WeeklySynergy.of_week(int(GameState.week_anchor_ts))
	if syns.size() >= WeeklySynergy.ALL.size():
		return   # 没有周(演示 / 冷启动)⇒ 16 个全在, 不挂这块牌子
	var w: float = minf(coin_x - 16.0 - WEEK_X, 150.0 + float(syns.size()) * (WEEK_ICON + WEEK_GAP) + 24.0)
	var plq := _plank(_coin_box, Vector2(WEEK_X, 48.0 - 32.0), Vector2(w, 64.0)); plq.name = "WeekSynPlaque"
	var lbl := Label.new(); lbl.text = Lang.t("本周羁绊")
	lbl.add_theme_font_size_override("font_size", 24); lbl.add_theme_color_override("font_color", Color("#ffe6a8"))
	lbl.add_theme_color_override("font_outline_color", Color("#1a0e05")); lbl.add_theme_constant_override("outline_size", 5)
	lbl.position = Vector2(WEEK_X + 18.0, 48.0 - 20.0); lbl.size = Vector2(120.0, 40.0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_box.add_child(lbl)
	var x: float = WEEK_X + 18.0 + 124.0
	for t in syns:
		var ip: String = Phase2Types.icon_of(str(t))
		if ip == "" or not ResourceLoader.exists(ip):
			continue
		var ic := TextureRect.new(); ic.name = "WeekSyn_" + str(t)
		ic.texture = load(ip); ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.position = Vector2(x, 48.0 - WEEK_ICON * 0.5); ic.size = Vector2(WEEK_ICON, WEEK_ICON)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_coin_box.add_child(ic)
		x += WEEK_ICON + WEEK_GAP
	var names: String = "、".join(PackedStringArray(syns))
	_wire_tap(plq, func() -> void: _toast(Lang.t("本周商店只出这些羁绊的装备：%s") % names))


""" + B)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok", REL)

po = os.path.join(ROOT, "locale", "en.po")
r = open(po, "rb").read()
n2 = b"\r\n" if b"\r\n" in r else b"\n"
add = ""
if "本周羁绊".encode() not in r:
    add += 'msgid "本周羁绊"\nmsgstr "This week"\n\n'
if "本周商店只出这些羁绊的装备：%s".encode() not in r:
    add += 'msgid "本周商店只出这些羁绊的装备：%s"\nmsgstr "This week the shop only sells gear from: %s"\n'
if add:
    open(po, "wb").write(r.rstrip() + n2 + n2 + add.strip("\n").encode("utf-8").replace(b"\n", n2) + n2)
    print("en.po +")
