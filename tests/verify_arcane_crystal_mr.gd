extends Node
## verify_arcane_crystal_mr.gd — 法器(088/089/090)打水晶龟必须吃到「水晶共鸣 -20%」
##
## 由来(2026-08-20): eq_arcane_batch 里的 `_magic_after_mr` 自己抄了一遍魔法结算公式,
## 注释还写着"与 _resolve_dmg 魔法分支逐字一致" —— **假的**: 主场景那边还有一行
## `if magic and tgt.id == "crystal": base *= 0.8`, 这份没有
## ⇒ 法器打水晶龟的魔法段是应有伤害的 **125%(÷0.8)**。
##
## ★判据不比公式、不数标记 —— **拿同一份 raw 喂两条路, 断言结果一模一样**。
##   这样以后主场景再加任何一条魔法修正, 这里都自动跟上(比"抄一遍公式再对比"强)。

var _n := 0
var _fail := 0


func _ok(t: String, c: bool, ex: String = "") -> void:
	_n += 1
	if not c:
		_fail += 1
	print("  [%s] %s  %s" % ["PASS" if c else "FAIL", t, ex])


func _ready() -> void:
	await get_tree().process_frame
	var scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(scn)
	await get_tree().process_frame
	print("=== 法器魔法结算 ↔ 主场景单一源 ===")

	var arc = scn._equip_sys._arcane_sys
	_ok("★分母: 法器系统在场", arc != null)
	if arc == null:
		_done(scn)
		return

	# 干净合成单位: 不用随机 spawn 的真单位(CI 会因队伍未播种 RNG 偶发红)
	## ★暴击必须钉成 0: `_resolve_dmg` 会掷 `_battle_rng.randf() < crit` —— 不钉的话这条测试
	##   会偶发红(memory: 拿随机数测精确数值 = CI 偶发红, 用干净合成单位隔离)。
	## ★crit/crit_dmg 是它**必读**的键, 缺了会中途报错返回 null(实测两条路都印 0, 而末尾是 maxi(1,...) 不可能为 0)。
	var src := {"id": "basic", "crit": 0.0, "crit_dmg": 1.5,
		"magic_pen": 0.0, "magic_pen_pct": 0.0, "damage_amp": 0.0}
	var crystal := {"id": "crystal", "mr": 20.0, "def": 10.0, "damage_reduction": 0.0}
	var normal := {"id": "basic", "mr": 20.0, "def": 10.0, "damage_reduction": 0.0}

	for raw in [100.0, 250.0, 777.0]:
		var a: int = arc._magic_after_mr(src, raw, crystal)
		var b: int = scn._resolve_dmg(src, raw, crystal, true)
		_ok("★raw=%.0f 打水晶龟: 法器 == 主场景" % raw, a == b, "法器 %d / 主场景 %d" % [a, b])

	# ★反面: 水晶龟确实比普通龟少吃 20% —— 否则上面那条就算两边一致也可能是"两边都没减"
	var c1: int = arc._magic_after_mr(src, 1000.0, crystal)
	var n1: int = arc._magic_after_mr(src, 1000.0, normal)
	_ok("★反面: 打水晶龟明显少于打普通龟(共鸣真的生效)", c1 < n1,
		"水晶 %d < 普通 %d" % [c1, n1])
	_ok("★反面: 比值 ≈ 0.8(不是随便小一点)",
		absf(float(c1) / maxf(1.0, float(n1)) - 0.8) < 0.02,
		"实测 %.3f" % (float(c1) / maxf(1.0, float(n1))))

	print("%d passed, %d failed" % [_n - _fail, _fail])
	print("ALL PASS — 法器魔法结算走单一源" if _fail == 0 else "FAIL")
	_done(scn)


func _done(scn) -> void:
	if is_instance_valid(scn):
		scn.queue_free()
	get_tree().quit(0 if _fail == 0 else 1)
