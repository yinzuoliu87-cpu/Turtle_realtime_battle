extends Node

## verify_palette.gd — 语义色单一事实源 (2026-07-22)
##
## 此前同一个语义色散在三张互不相干的表里, 物理红有两个值(#ff6b6b 与 #ff4444)。
## 用户 2026-07-22 拍板全统一成 #ff4444, 并建 UIPalette 作为唯一来源。
##
## 本门禁守三件事:
##   ① 三个消费方【运行时取到的颜色】真的一致 —— 比 Color 值, 不比源码字符串
##   ② visual_constants 保留字面量(它的契约是与 Phaser PoC 1:1), 但值必须与色表相同;
##      将来谁改漂了当场红。这是"不重构也能防漂"的办法
##   ③ 消费方源码里不许再出现被并掉的旧色值字面量

const UIPalette = preload("res://scripts/engine/ui_palette.gd")
const DMG_PANEL := preload("res://scripts/scenes/dmg_stats_panel.gd")
const SKILL_TEXT_SRC := "res://scripts/engine/skill_text.gd"
const DMG_PANEL_SRC := "res://scripts/scenes/dmg_stats_panel.gd"

# 被并掉的旧值 —— 消费方源码里再出现就是有人绕过色表
const RETIRED := ["#ff6b6b"]

var _fail := 0


func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	var phys := Color(UIPalette.PHYS)
	var magic := Color(UIPalette.MAGIC)
	var true_c := Color(UIPalette.TRUE_DMG)

	# ── ① 三个消费方运行时取到的颜色一致 ──
	var vh: Dictionary = SkillText.VAL_HEX
	print("  [分母] SkillText.VAL_HEX 共 %d 项" % vh.size())
	_ok("VAL_HEX 非空(N=0 是空检查不是通过)", vh.size() > 0)
	_ok("★文案·物理红 = 色表", Color(str(vh.get("val-normal", ""))).is_equal_approx(phys),
		"文案 %s / 色表 %s" % [str(vh.get("val-normal", "")), UIPalette.PHYS])
	_ok("★文案·攻击力与暴击也用同一个红(原来这三项各写各的)",
		str(vh.get("val-atk", "")) == UIPalette.PHYS and str(vh.get("val-crit", "")) == UIPalette.PHYS,
		"val-atk=%s val-crit=%s" % [str(vh.get("val-atk", "")), str(vh.get("val-crit", ""))])
	_ok("★文案·魔法蓝 = 色表", Color(str(vh.get("val-magic", ""))).is_equal_approx(magic))

	var cp: Color = DMG_PANEL.COL_PHY
	_ok("★统计面板·物理红 = 色表(忽略 alpha)",
		is_equal_approx(cp.r, phys.r) and is_equal_approx(cp.g, phys.g) and is_equal_approx(cp.b, phys.b),
		"面板 (%.3f,%.3f,%.3f) / 色表 (%.3f,%.3f,%.3f)" % [cp.r, cp.g, cp.b, phys.r, phys.g, phys.b])
	_ok("统计面板色块仍是半透明(alpha 不该被色表统一掉)", cp.a < 1.0, "alpha=%.2f" % cp.a)

	# ── ② 飘字表保留字面量, 但值必须与色表一致 ──
	var fs: Dictionary = VisualConstants.FLOAT_STYLE
	print("  [分母] VisualConstants.FLOAT_STYLE 共 %d 项" % fs.size())
	_ok("FLOAT_STYLE 非空", fs.size() > 0)
	var checks := [["phys-dmg", phys, "物理"], ["magic-dmg", magic, "魔法"], ["true-dmg", true_c, "真实"]]
	for row in checks:
		var key: String = row[0]
		var want: Color = row[1]
		var label: String = row[2]
		var got := str((fs.get(key, {}) as Dictionary).get("color", ""))
		_ok("★飘字·%s = 色表(它保留字面量, 靠这条防漂)" % label,
			got != "" and Color(got).is_equal_approx(want),
			"飘字 %s / 色表 %s" % [got, want.to_html(false)])

	# ── ③ 消费方源码里不许再出现被并掉的旧色值 ──
	for path in [SKILL_TEXT_SRC, DMG_PANEL_SRC]:
		var src := FileAccess.get_file_as_string(path)
		_ok("读得到 %s" % path.get_file(), src != "")
		# ★必须先剥注释 —— 否则本次改动里"原为 #ff6b6b"这句说明就会把自己判红
		#   (2026-07-22 实测踩到; 同类坑在 verify_cyber_hijack 上踩过两次)
		var code := _code_only(src)
		for old in RETIRED:
			_ok("%s 的【代码】里没有残留旧色值 %s" % [path.get_file(), old],
				not code.contains(old), "还写着 %s = 绕过了色表" % old)
		# 反向自检: 注释被剥掉了, 但代码主体不能被剥没
		_ok("%s 剥注释后仍有实质代码(否则上一条是空检查)" % path.get_file(),
			code.contains("const"), "剥完只剩 %d 字符" % code.length())

	print("ALL PASS — 语义色单一事实源(文案/飘字/统计面板三处一致)" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## 剥注释 —— 不能按第一个 # 截断: 满文件的 "#ff4444" 会被误伤 → 要判引号状态
func _strip_comment(line: String) -> String:
	var in_q := false
	var q := ""
	for i in line.length():
		var ch := line[i]
		if in_q:
			if ch == q and (i == 0 or line[i - 1] != "\\"):
				in_q = false
		elif ch == "\"" or ch == "'":
			in_q = true
			q = ch
		elif ch == "#":
			return line.substr(0, i)
	return line


func _code_only(block: String) -> String:
	var out := ""
	for l in block.split("
"):
		out += _strip_comment(str(l)) + "
"
	return out
