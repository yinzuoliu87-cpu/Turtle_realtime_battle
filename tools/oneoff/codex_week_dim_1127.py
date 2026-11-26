"""codex_week_dim_1127.py —— 图鉴: 本周商店不出的装备 / 不在本周的大羁绊 ⇒ 行压暗 + 名字后注「本周不出」(方案书 20261124d; 用户 11-27「直接做就好了呀」)
商店本来就只出本周的件(货架上看不到别的), 所以「哪些本周有」只在图鉴里讲; 判据与商店掷货同一个函数 WeeklySynergy.pool_ok。
一次性; 原行尾二进制读写。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:70], s.count(a))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok", rel)


patch("scripts/scenes/codex/list_builder.gd", [
("""func _add_simple_row(label: String, label_color: String, stroke: Color, icon_path: String,
		idx: int, icon_native: bool = false) -> void:
	var col = stroke; col.a = 0.7""",
"""## `off_week` = 本周商店不出(11-27): 整行压暗 + 名字后注「本周不出」; 仍然点得开看说明。
func _add_simple_row(label: String, label_color: String, stroke: Color, icon_path: String,
		idx: int, icon_native: bool = false, off_week: bool = false) -> void:
	var col = stroke; col.a = 0.7"""),
("""	lbl.add_theme_color_override("font_color", Color(label_color))
	p.add_child(lbl)
	host._connect_row(p, idx, col)""",
"""	lbl.add_theme_color_override("font_color", Color(label_color))
	p.add_child(lbl)
	if off_week:
		lbl.text = label + "  " + Lang.t("· 本周不出")
		p.modulate = Color(1.0, 1.0, 1.0, 0.42)
	host._connect_row(p, idx, col)


## 这一件这周商店出不出(与掷货同一个判据; 没有周 / 演示 ⇒ 都出)。羁绊赠送(费用 0)不上商店, 不标。
static func off_week_eq(eq: Dictionary) -> bool:
	if int(eq.get("cost", 0)) <= 0 or GameState == null:
		return false
	return not WeeklySynergy.pool_ok(str(eq.get("id", "")), int(GameState.week_anchor_ts), EconLedger.POOL_VER)


## 这个大羁绊在不在本周 10 个里(小木斧 / 香火这类不轮换的类型 ⇒ 不标)。
static func off_week_syn(t: String) -> bool:
	if GameState == null or not WeeklySynergy.ALL.has(t):
		return false
	return not WeeklySynergy.of_week(int(GameState.week_anchor_ts)).has(t)"""),
("""			_add_simple_row(rname, "#ffffff", Color(stroke), ipath, host._items.size() - 1)""",
"""			_add_simple_row(rname, "#ffffff", Color(stroke), ipath, host._items.size() - 1, false, off_week_eq(eq))"""),
])

patch("scripts/scenes/CodexScene.gd", [
("""				_codex_list._add_simple_row(sname, col, Color(col), _type_icon(sname),
					_items.size() - 1, true)""",
"""				_codex_list._add_simple_row(sname, col, Color(col), _type_icon(sname),
					_items.size() - 1, true, _codex_list.off_week_syn(sname))   # 不在本周 10 个里 ⇒ 压暗 + 「本周不出」(11-27)"""),
])

p = os.path.join(ROOT, "locale", "en.po")
raw = open(p, "rb").read()
nl = b"\r\n" if b"\r\n" in raw else b"\n"
if "· 本周不出".encode("utf-8") not in raw:
    add = ('msgid "· 本周不出"\nmsgstr "· Not this week"\n').encode("utf-8").replace(b"\n", nl)
    open(p, "wb").write(raw.rstrip() + nl + nl + add)
    print("en.po +1")
