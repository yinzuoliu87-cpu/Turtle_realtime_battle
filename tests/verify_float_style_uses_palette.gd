extends Node
## verify_float_style_uses_palette.gd — 飘字色表必须引用 UIPalette，不许自己抄一份
##
## ══════════════════════════════════════════════════════════════════
##  ★由来：收口做了 2/3，漏的那 1/3 抄了一年半
## ══════════════════════════════════════════════════════════════════
## `UIPalette` 是 2026-07-22 建的语义色单一事实源，它自己的文件头写着要收的是三张表：
##
##   | 表 | 当时 | 2026-09-05 实测 |
##   |---|---|---|
##   | `skill_text.VAL_HEX`      | 要收 | ✅ 已接 `UIPalette.PHYS/MAGIC/TRUE_DMG` |
##   | `dmg_stats_panel.COL_*`   | 要收 | ✅ 已接 `Color(UIPalette.PHYS, 0.6)` |
##   | `visual_constants.FLOAT_STYLE` | 要收 | ❌ **一直写着十六进制字面量** |
##
## 也就是说：**单一事实源建好了，最大的那个消费者没接上去**，自己又抄了一份。
## 同族 memory [[fb-refactor-creates-the-drift-it-removes]]「抽常量漏了改代码那步」、
##           [[fb-hand-rolled-copies-drift]]「手抄的副本必然落后」。
##
## ══════════════════════════════════════════════════════════════════
##  ★★量到的事实：今天 **0 处漂移**
## ══════════════════════════════════════════════════════════════════
## 收口前逐对量过 9 对语义色（PHYS×4 / MAGIC×3 / TRUE_DMG×2），**数值全一致**。
## 所以这不是在修一个看得见的 bug —— 是在**拆掉那个靠手工维持的一致**。
## 用户 2026-09-04：「真实伤害数字是一团乱，**应该统一规则的**」。
##
## ══════════════════════════════════════════════════════════════════
##  ★★★判据必须是**源码级**，不能只比数值
## ══════════════════════════════════════════════════════════════════
## 接上 `UIPalette` 之后，「数值相等」就变成恒真式了（两边本来就是同一个常量）。
## 所以主判据落在**源码里写的是不是 `UIPalette.X`**；数值相等只作为第二道。
## 反向验证：把任一项改回 `"#ff4444"` 字面量 ⇒ ① 当场红。
##
## ★非语义色**保留字面量，不许硬凑**（判据要刚好卡住那个形状）：
##   `pierce-dmg`/`crit-pierce` 白 —— 穿透≠真伤，只是恰好也白
##   `shield-num`/`shield-gain` 白 —— `SHIELD_VALUE` 是 `#58d3ff`（统计面板蓝条），不是这个
##   `crit-label` 金 / `counter-dmg` 黄 / `bubble-*` / `dodge-num` —— 调色板里没有对应语义
const VC := preload("res://scripts/systems/visual_constants.gd")
const UIPalette := preload("res://scripts/util/ui_palette.gd")
const SRC := "res://scripts/systems/visual_constants.gd"

## FLOAT_STYLE 的键 → 它必须引用的 UIPalette 常量名
const MUST_REF := {
	"direct-dmg": "PHYS", "phys-dmg": "PHYS", "crit-dmg": "PHYS", "crit": "PHYS",
	"dot-bleed": "PHYS",
	"magic-dmg": "MAGIC", "crit-magic": "MAGIC", "dot-dmg": "MAGIC", "dot-poison": "MAGIC",
	"true-dmg": "TRUE_DMG", "crit-true": "TRUE_DMG", "dot-curse": "TRUE_DMG",
	"heal-num": "HEAL", "heal": "HEAL",
}

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if c:
		print("  [OK] %s" % t)
	else:
		_fail += 1
		print("  [FAIL] %s  %s" % [t, ex])


func _ready() -> void:
	print("=== 飘字色表 → UIPalette 单一事实源 ===")
	var src: String = FileAccess.get_file_as_string(SRC)
	_ok("★分母①: 读到源码 %d 字节" % src.length(), src.length() > 2000,
		"读不到源码 ⇒ 下面的源码级判据全是空检查")

	var style: Dictionary = VC.FLOAT_STYLE
	_ok("★分母②: FLOAT_STYLE 有 %d 项" % style.size(), style.size() >= 25,
		"表太小 ⇒ 没加载到")

	var pal_val := {
		"PHYS": UIPalette.PHYS, "MAGIC": UIPalette.MAGIC,
		"TRUE_DMG": UIPalette.TRUE_DMG, "HEAL": UIPalette.HEAL,
	}
	for cn in pal_val:
		_ok("★分母③: UIPalette.%s 非空 (=%s)" % [cn, str(pal_val[cn])],
			str(pal_val[cn]).begins_with("#") and str(pal_val[cn]).length() == 7,
			"调色板常量读不出来 ⇒ 下面的比对是拿空串比空串")

	# ── ① 源码级：这些项必须写 `UIPalette.X`，不许是十六进制字面量 ──
	print("── ① 源码里写的是 UIPalette.X 而不是字面量 ──")
	var bad_src: Array = []
	var checked := 0
	for k in MUST_REF:
		var want: String = str(MUST_REF[k])
		# 精确匹配那一行：`"<key>": {"color": UIPalette.<WANT>,`
		var rx := RegEx.new()
		rx.compile("\"" + k.replace("-", "\\-") + "\"\\s*:\\s*\\{\\s*\"color\"\\s*:\\s*([^,]+),")
		var m := rx.search(src)
		if m == null:
			bad_src.append("%s → 源码里找不到这一项（键改名了？）" % k)
			continue
		checked += 1
		var expr: String = m.get_string(1).strip_edges()
		if expr != "UIPalette." + want:
			bad_src.append("%s → 写的是 `%s`，应为 `UIPalette.%s`" % [k, expr, want])
	_ok("★分母④: 源码里定位到 %d/%d 项" % [checked, MUST_REF.size()],
		checked == MUST_REF.size(),
		"有项定位不到 ⇒ 它们没被检查")
	_ok("① %d 个语义色项**全部引用 UIPalette**（没人再抄字面量）" % MUST_REF.size(),
		bad_src.is_empty(),
		"%d 处:\n     %s" % [bad_src.size(), "\n     ".join(bad_src)])

	# ── ② 数值级（第二道；接上之后本该恒真，但键写错/引错常量时它会红）──
	print("── ② 运行时取到的值 == UIPalette ──")
	var bad_val: Array = []
	for k in MUST_REF:
		var got: String = str((style.get(k, {}) as Dictionary).get("color", ""))
		var want2: String = str(pal_val.get(str(MUST_REF[k]), "?"))
		if got.to_lower() != want2.to_lower():
			bad_val.append("%s: %s ≠ UIPalette.%s(%s)" % [k, got, str(MUST_REF[k]), want2])
	_ok("② 14 项运行时取值全部等于对应调色板常量", bad_val.is_empty(),
		"%d 处: %s" % [bad_val.size(), ", ".join(bad_val)])

	# ── ③ 暴击色 == 非暴击同类色（只改字号不改色）──
	#    用户 2026-09-04 点了「真实伤害数字是一团乱」这条线，暴击是同一族，一并焊住。
	print("── ③ 暴击只放大字号，不改颜色 ──")
	var pairs := [["crit-dmg", "direct-dmg"], ["crit-magic", "magic-dmg"], ["crit-true", "true-dmg"]]
	var bad_crit: Array = []
	var sized := 0
	for p in pairs:
		var a: Dictionary = style.get(p[0], {})
		var b: Dictionary = style.get(p[1], {})
		if str(a.get("color", "")) != str(b.get("color", "")):
			bad_crit.append("%s(%s) ≠ %s(%s)" % [p[0], str(a.get("color", "")), p[1], str(b.get("color", ""))])
		if int(a.get("size", 0)) > int(b.get("size", 0)):
			sized += 1
	_ok("③ 三对暴击/非暴击**同色**", bad_crit.is_empty(), ", ".join(bad_crit))
	_ok("★分母⑤: 三对里 %d 对暴击字号确实更大（证明取到的是两个不同条目，不是同一条比自己）" % sized,
		sized == 3, "字号没变大 ⇒ 上面那条可能在拿同一个条目自比")

	# ── ④ 飘字调用点不许手抄十六进制 ──
	## `_float_text` **用传进来的 col，不查 FLOAT_STYLE**（`battle_vfx.gd:271`）——
	## 所以调用点写 `Color("#06d6a0")` 就是**又一份治疗色**，表改了它不跟着改。
	## 收口前 `battle_damage.gd` 有 3 处这样的手抄：闪避 #a0e8ff / 护盾 #ffffff / 治疗 #06d6a0。
	print("── ④ `_float_text` 调用点走色表，不手抄十六进制 ──")
	var dsrc: String = FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	var calls: Array = []
	for l in dsrc.split("\n"):
		var s: String = str(l)
		if s.find("_float_text(") >= 0 and not s.strip_edges().begins_with("#"):
			calls.append(s)
	_ok("★分母⑥: 找到 %d 个 `_float_text` 调用点" % calls.size(), calls.size() >= 8,
		"找不到调用点 ⇒ 下面是空检查")
	# 白名单：表里和调色板里都**没有**对应语义的色，硬凑反而是错（判据要刚好卡住那个形状）
	var lit_ok := ["亡灵!"]
	var bad_lit: Array = []
	for s in calls:
		if s.find("Color(\"#") < 0:
			continue
		var excused := false
		for w in lit_ok:
			if s.find(w) >= 0:
				excused = true
		if not excused:
			bad_lit.append(s.strip_edges().substr(0, 96))
	_ok("④ 除白名单外没有手抄的十六进制（白名单 %d 条，各有理由见文件头）" % lit_ok.size(),
		bad_lit.is_empty(),
		"%d 处:\n     %s" % [bad_lit.size(), "\n     ".join(bad_lit)])
	# ★分母⑦：证明白名单里那条**确实还在**用字面量 —— 否则 ④ 是在放空
	var found_excused := false
	for s in calls:
		if s.find("亡灵!") >= 0 and s.find("Color(\"#") >= 0:
			found_excused = true
	_ok("★分母⑦: 白名单那条确实还写着字面量（证明 ④ 的豁免逻辑真被走到）",
		found_excused, "白名单条目已经不存在了 ⇒ 该把它从白名单删掉")

	print("")
	if _fail == 0:
		print("ALL PASS (%d 条)" % _n)
	else:
		print("FAIL x%d / %d 条" % [_fail, _n])
	get_tree().quit()
