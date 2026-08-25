extends Node2D
## 公式占位符 `{N:...}` 里能不能引用【代码常量】—— 引擎内实测。
##
## 由来(2026-08-25): 量清楚"没人验的数字"里有 289 个藏在占位符**内部**
## (`{N:0.9*ATK}` 里的那个 0.9), 占 60%。它和外面的裸数字是同一个毛病:
## 跟代码没有绑定, 代码改了它照样显示旧数, 只是藏在公式里更不容易发现。
##
## ⇒ `SkillText.eval_expr` 加了预处理: 求值前把 `类名.常量名` 换成数值。
##   这条测试守住这个能力 —— 它坏了, 289 个数会**静默**退回"手写"状态。

const SkillText := preload("res://scripts/util/skill_text.gd")

var _n := 0
var _bad := 0


func _chk(name: String, ok: bool, extra: String = "") -> void:
	_n += 1
	if ok:
		print("  [ OK ] %s" % name)
	else:
		_bad += 1
		print("  [FAIL] %s %s" % [name, extra])


func _ready() -> void:
	print("=== 公式占位符引用代码常量 ===")

	var vars := {"ATK": 100, "DEF": 50, "MR": 20, "HP": 1000}

	## ① 基本能力: 单个常量参与运算
	var v1 = SkillText.eval_expr("StoneSystem.HIT_ATK_COEF*ATK", vars)
	_chk("① 单常量: HIT_ATK_COEF(0.7) × ATK(100) = 70", int(v1) == 70, "实得 %s" % str(v1))

	## ② 多个常量 + 多个变量混算(石头打击的真公式)
	var v2 = SkillText.eval_expr(
		"StoneSystem.HIT_ATK_COEF*ATK+StoneSystem.HIT_DEF_COEF*DEF+StoneSystem.HIT_MR_COEF*MR", vars)
	var want2: int = int(round(StoneSystem.HIT_ATK_COEF * 100 + StoneSystem.HIT_DEF_COEF * 50
		+ StoneSystem.HIT_MR_COEF * 20))
	_chk("② 多常量混算 = %d" % want2, int(v2) == want2, "实得 %s" % str(v2))

	## ③ ★★真正的价值: 它**跟着代码常量走**, 不是把数字抄了一遍。
	##   拿两个不同的常量比 —— 如果预处理没生效, 两次会得到同一个(错的)结果。
	var a = SkillText.eval_expr("StoneSystem.HIT_ATK_COEF*ATK", vars)   # 0.7
	var b = SkillText.eval_expr("StoneSystem.HIT_DEF_COEF*ATK", vars)   # 1.5
	_chk("③ 不同常量给出不同结果(证明真的读了常量, 不是碰巧)",
		int(a) != int(b) and int(a) == int(round(StoneSystem.HIT_ATK_COEF * 100.0))
			and int(b) == int(round(StoneSystem.HIT_DEF_COEF * 100.0)),
		"a=%s b=%s" % [str(a), str(b)])

	## ④ ★解析不出来时**不许静默兜底**: 必须原样返回, 好让渲染门禁报红。
	##   (宁可当场红, 也不要在图鉴里显示一个错数)
	var v4 = SkillText.eval_expr("NoSuchSystem.NO_SUCH_CONST*ATK", vars)
	_chk("④ 未知常量 → 原样返回(不静默出错数)",
		str(v4).find("NoSuchSystem") >= 0, "实得 %s" % str(v4))

	## ⑤ 不含常量的老公式必须照旧(回归守卫)
	var v5 = SkillText.eval_expr("0.9*ATK", vars)
	_chk("⑤ 老公式 0.9*ATK 照旧 = 90", int(v5) == 90, "实得 %s" % str(v5))

	print("  分母: 断言 %d 条" % _n)
	if _n < 5:
		print("  [FAIL] 断言条数不对(%d) —— 有用例没跑到" % _n)
		_bad += 1
	print("")
	if _bad == 0:
		print("ALL PASS — 公式占位符引用代码常量")
	else:
		print("FAIL x%d — 公式占位符引用代码常量" % _bad)
	get_tree().quit()
