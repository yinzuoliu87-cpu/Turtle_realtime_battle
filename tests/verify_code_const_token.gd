extends Node
## verify_code_const_token.gd — {C:类名.常量名} 占位符
##
## 由来(2026-08-20, 用户「怎么根除」): 玩家文案里 **2487 个数字是手抄代码的**, 只有 220 个是占位符。
## 手抄的每一个在写下那天都是对的, 原件一改就烂 —— 这是本项目反复出现的头号病。
## 已有的 {N:1.5*ATK} 只能算单位属性和本条技能自己的 json 字段, 而 json 字段本身又是代码常量的手抄
## (实测已有 10 条对不上)。{C:...} 补上"文案直接引用代码常量"这一环, 中间不经任何副本。

const ST := preload("res://scripts/util/skill_text.gd")

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	print("=== {C:类名.常量名} ===")
	# ① 取标量: 毒雾寿命(逻辑侧唯一的那一份)
	var fog := ST.const_of("VenomDroneSystem.FOG_LIFE")
	_ok("① 取得到标量常量", fog == "6", "FOG_LIFE → %s" % fog)
	# ★分母: 它必须真的等于代码里那个值, 不是碰巧
	_ok("★分母: 与代码常量本体一致", float(fog) == VenomDroneSystem.FOG_LIFE,
		"渲染 %s / 代码 %.1f" % [fog, VenomDroneSystem.FOG_LIFE])

	# ② 数组按三档惯例渲染
	var st := ST.const_of("VenomDroneSystem.POISON_STACKS")
	_ok("② 数组渲染成三档 a/b/c", st == "3/5/8", "POISON_STACKS → %s" % st)

	# ③ 整数不拖 .0
	_ok("③ 6.0 渲染成 6 不是 6.0", not fog.contains("."), fog)

	# ④ ★取不到时原样吐回, **不静默变成 0** —— 静默归零是最难查的一类错
	_ok("④ 类名不存在 → 原样吐回", ST.const_of("NoSuchClass.X") == "{C:NoSuchClass.X}",
		ST.const_of("NoSuchClass.X"))
	_ok("④ 常量不存在 → 原样吐回",
		ST.const_of("VenomDroneSystem.NO_SUCH") == "{C:VenomDroneSystem.NO_SUCH}",
		ST.const_of("VenomDroneSystem.NO_SUCH"))

	# ⑤ 走真渲染管线(不是只测解析函数)
	var out := ST.render_plain("毒雾持续 {C:VenomDroneSystem.FOG_LIFE} 秒", {}, {})
	_ok("⑤ 真渲染管线里展开", out == "毒雾持续 6 秒", out)
	var out2 := ST.render_plain("每 0.25 秒叠 {C:VenomDroneSystem.POISON_STACKS} 层", {}, {})
	_ok("⑤ 三档在真管线里", out2 == "每 0.25 秒叠 3/5/8 层", out2)

	# ⑥ ★反面: 改了代码常量, 渲染结果必须跟着变 —— 这是本机制存在的全部理由
	#    (不能改真常量, 所以拿另一个已知常量做对照: 两个不同常量必须渲染出不同的值)
	var a := ST.const_of("VenomDroneSystem.FOG_LIFE")
	var b := ST.const_of("VenomDroneSystem.OVERSHOOT")
	_ok("⑥ 不同常量渲染出不同值(不是写死的)", a != b, "%s vs %s" % [a, b])

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 代码常量占位符" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
