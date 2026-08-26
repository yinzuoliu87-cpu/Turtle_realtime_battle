extends Node
## verify_pk_bar_continuity.gd — PK 条在【三种事件】下比例连续 (2026-08-25)
##
## 补 `docs/plans/20260730d-装备平衡7项+局内5条反馈.md` 的 2-c —— 那条自标「❌ 缺门禁」,
## 而且方案书自己写明了**为什么难**:
##
##   「实现在位，但三种事件零断言；且现有门禁**抓不住回退** ——
##     合成单位全未驯服 → `_eff_side` 退化成 `side`，把分母改回去照样全绿」
##
## ★所以本文件的第一条就是【分母断言】: 场上必须真的有一只 `_eff_side != side` 的龟。
##   没有它, 分子按 `_eff_side` / 分母按 `side` 这个**故意的不对称**根本表现不出来,
##   整份测试就是空检查 —— 这正是上一版门禁的死法。
##
## ── 三个跳变源(用户 2026-07-30:「怎么有时候莫名增加或减少」) ──
##   ① 驯服归顺: 那只龟的血从敌方分子搬到我方分子
##      · 修之前分子分母都用 `_eff_side` ⇒ 整只龟从敌方消失又整只出现在我方,
##        实测敌方 0.630 → 1.000(+0.370) / 我方 0.993 → 0.811(−0.182), 两条同时硬跳,
##        **方向还是反的**(我方多了个帮手, 条子反而被那只残血龟稀释掉下来)。
##      · 修之后: 只搬分子、**分母不动** ⇒ 我方涨 / 敌方跌, 方向对, 幅度 = 那只龟的血占比。
##   ② 口哨临时血: 同时抬这只龟【原方】的分母与分子 ⇒ 幅度小(方案书实测 +0.023)。
##   ③ 驯服重生回血: 分子涨、分母不动。
##
## ★判据落在【产品自己算出来的 `_pk_target_l/r`】与 `_pk_sum` 的分子分母上,
##   不是我自己另算一份公式(那会变成"拿代码跟我抄的副本比")。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_pk_bar_continuity.tscn

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _n := 0
var _fail := 0
var _s = null
var _h = null


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 干净合成单位 —— 把血量压成好算的整数, 免得随机 spawn 的属性把"幅度"这条判据搅浑。
func _mk(side: String, dx: float, hp: float) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit("green", side, c + Vector2(dx, 0))
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["alive"] = true
	u.erase("tamed_side")
	return u


func _targets() -> Vector2:
	_h._pk_refresh()
	return Vector2(_h._pk_target_l, _h._pk_target_r)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	print("=== PK 条: 三种事件下比例连续 ===")
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(30):
		await get_tree().process_frame
	_s._edit_mode = false
	_h = _s._hud
	_ok("★分母: HUD 与 PK 条都在", _h != null and _h._pk_bar != null)
	if _h == null:
		_done()
		return

	# 我方两只各 1000, 敌方两只各 1000 —— 双方分母都是 2000, 满血时两条都是 1.0
	var a1 := _mk("left", -200.0, 1000.0)
	var a2 := _mk("left", -260.0, 1000.0)
	var e1 := _mk("right", 200.0, 1000.0)
	var e2 := _mk("right", 260.0, 1000.0)
	_s._units.clear()
	_s._units.append_array([a1, a2, e1, e2])

	var t0 := _targets()
	var sum_l0: Vector2 = _h._pk_sum("left")
	var sum_r0: Vector2 = _h._pk_sum("right")
	_ok("★分母: 开场双方分母都是 2000(合成单位真的被 _pk_counts 计进去了)",
		is_equal_approx(sum_l0.y, 2000.0) and is_equal_approx(sum_r0.y, 2000.0),
		"左分母 %.0f 右分母 %.0f" % [sum_l0.y, sum_r0.y])
	_ok("★分母: 满血时两条都是 1.0", absf(t0.x - 1.0) < 0.001 and absf(t0.y - 1.0) < 0.001,
		"L=%.3f R=%.3f" % [t0.x, t0.y])
	## ★★这条是整份测试成立的前提: 此刻【没有】任何龟归顺,
	##   所以 `_eff_side` 与 `side` 完全一致 —— 下面必须先把这个条件破掉。
	var any_tamed := false
	for u in _s._units:
		if _s._eff_side(u) != str(u.get("side", "")):
			any_tamed = true
	_ok("★分母: 此刻场上【没有】归顺的龟(基线干净)", not any_tamed)

	## ★★把我方打到半血再做后面三节 —— `_pk_target = clampf(cur/mx, 0, 1)` 是**钳到 1.0** 的,
	##   我方满血时归顺者的血加进去也顶在 1.0, "涨"这条判据永远逼不出来。
	##   (第一版就栽在这: ①③ 的"我方条涨"报红, 而那不是产品的错、是我的用例摆错了。)
	a1["hp"] = 500.0
	a2["hp"] = 500.0
	_ok("★分母: 我方先打到半血(留出上涨空间, 否则 clamp 到 1.0 什么都看不出来)",
		absf(_targets().x - 0.5) < 0.001, "L=%.3f" % _targets().x)

	_t_defect(a1, e1, sum_l0, sum_r0, t0)
	_t_temp_hp()
	_t_revive_heal()
	_done()


func _done() -> void:
	if _s != null:
		_s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 12:
		print("  [FAIL] ★分母: 断言只有 %d 条(<12) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — PK 条三事件连续" if _fail == 0 else "FAIL x%d — PK 条三事件连续" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ─────────────────────────────────────────────────────────────
# ① 驯服归顺 —— 血搬边、分母不动
# ─────────────────────────────────────────────────────────────
func _t_defect(_a1: Dictionary, e1: Dictionary, sum_l0: Vector2, sum_r0: Vector2,
		t0: Vector2) -> void:
	print("── ① 驯服归顺 ──")
	e1["hp"] = 600.0                       # 残血归顺: 幅度好算, 也正是当年"方向反了"的那个场景
	var t_pre := _targets()
	e1["tamed_side"] = "left"              # ★真正把 _eff_side 改掉(产品字段, 不是我插的标记)
	_ok("★① 分母断言: 这只龟【真的归顺了】(_eff_side %s ≠ 原阵营 %s)"
			% [_s._eff_side(e1), str(e1.get("side", ""))],
		_s._eff_side(e1) != str(e1.get("side", "")))

	var t1 := _targets()
	var sum_l1: Vector2 = _h._pk_sum("left")
	var sum_r1: Vector2 = _h._pk_sum("right")

	## ★★核心: 分母【一动都不能动】。修之前分子分母都按 _eff_side ⇒ 整只龟连血带底
	##   从敌方搬到我方, 两条同时硬跳。这条就是守那次修复的。
	_ok("★★① 我方分母不动(%.0f → %.0f)" % [sum_l0.y, sum_l1.y],
		is_equal_approx(sum_l0.y, sum_l1.y))
	_ok("★★① 敌方分母不动(%.0f → %.0f)" % [sum_r0.y, sum_r1.y],
		is_equal_approx(sum_r0.y, sum_r1.y))

	## 方向: 我方多了个帮手就该涨、敌方少了个人就该跌。修之前**方向是反的**。
	_ok("★① 我方条【涨】(%.3f → %.3f)" % [t_pre.x, t1.x], t1.x > t_pre.x + 0.001)
	_ok("★① 敌方条【跌】(%.3f → %.3f)" % [t_pre.y, t1.y], t1.y < t_pre.y - 0.001)

	## 幅度: 正好等于那只龟的血 ÷ 分母 —— 不是"随便跳一下"。
	var want_up: float = 600.0 / sum_l1.y
	_ok("① 我方涨幅 = 那只龟的血 ÷ 分母 = %.3f" % want_up,
		absf((t1.x - t_pre.x) - want_up) < 0.005,
		"实得 %.3f" % (t1.x - t_pre.x))
	var want_dn: float = 600.0 / sum_r1.y
	_ok("① 敌方跌幅 = 同一只龟的血 ÷ 敌方分母 = %.3f" % want_dn,
		absf((t_pre.y - t1.y) - want_dn) < 0.005,
		"实得 %.3f" % (t_pre.y - t1.y))
	## 复位, 不污染后面两节(血量保持半血, 后面还要留上涨空间)
	e1.erase("tamed_side")
	e1["hp"] = 1000.0


# ─────────────────────────────────────────────────────────────
# ② 口哨临时血 —— 分子分母同抬, 幅度必须小
# ─────────────────────────────────────────────────────────────
func _t_temp_hp() -> void:
	print("── ② 临时血 ──")
	var t_pre := _targets()
	var mx_pre: float = _h._pk_sum("left").y
	for u in _s._units:                    # 给我方第一只加 700 临时血(maxHp 与 hp 同抬)
		if str(u.get("side", "")) == "left":
			u["maxHp"] = float(u["maxHp"]) + 700.0
			u["hp"] = float(u["hp"]) + 700.0
			break
	var t1 := _targets()
	var mx1: float = _h._pk_sum("left").y
	_ok("★② 分母【跟着抬】了 700(%.0f → %.0f) —— 这正是幅度小的原因"
			% [mx_pre, mx1], is_equal_approx(mx1 - mx_pre, 700.0))
	## ★★判据不能写成"幅度 < 某个绝对值" —— 第一版就这么写, 结果在【半血】场景下报红,
	##   而那不是产品错: 给半血单位加 700 **满值**临时血, 比例本来就该涨一截
	##   (新加的血是满的、原有的是半的)。方案书量到的 +0.023 是**满血**场景。
	## ⇒ 判据换成【反事实对比】: "分母也跟着抬"到底把幅度压下去了多少。
	##   只抬分子(旧行为) 会跳 (cur+700)/mx; 分子分母同抬(现行为) 是 (cur+700)/(mx+700)。
	##   后者必须**明显小于**前者 —— 这才是"分母跟着抬"这件事的可观测后果。
	var cur_pre: float = _h._pk_sum("left").x - 700.0
	var only_num: float = clampf((cur_pre + 700.0) / mx_pre, 0.0, 1.0)   # 反事实: 只抬分子
	var jump_now: float = absf(t1.x - t_pre.x)
	var jump_bad: float = absf(only_num - t_pre.x)
	_ok("★★② 分母同抬把跳幅压下来了: 实际 +%.3f ≪ 只抬分子会跳的 +%.3f"
			% [jump_now, jump_bad], jump_now < jump_bad - 0.05,
		"实际 %.3f / 反事实 %.3f" % [jump_now, jump_bad])


# ─────────────────────────────────────────────────────────────
# ③ 驯服重生回血 —— 分子涨、双方分母都不动
# ─────────────────────────────────────────────────────────────
func _t_revive_heal() -> void:
	print("── ③ 归顺者重生回血 ──")
	var victim = null
	for u in _s._units:
		if str(u.get("side", "")) == "right":
			victim = u
			break
	## 我方仍需留出上涨空间(同上, clamp 到 1.0)
	for u in _s._units:
		if str(u.get("side", "")) == "left":
			u["hp"] = float(u["maxHp"]) * 0.4
	victim["tamed_side"] = "left"           # 归顺
	victim["hp"] = 100.0                    # 濒死
	var t_pre := _targets()
	var ly0: float = _h._pk_sum("left").y
	var ry0: float = _h._pk_sum("right").y
	_ok("★③ 分母断言: 这只龟真的归顺了", _s._eff_side(victim) != str(victim.get("side", "")))

	victim["hp"] = float(victim["maxHp"]) * 0.30   # 重生回 30%
	var t1 := _targets()
	_ok("★③ 我方条【涨】(重生的血算进我方分子) %.3f → %.3f" % [t_pre.x, t1.x],
		t1.x > t_pre.x + 0.001)
	_ok("★★③ 双方分母都没动(左 %.0f / 右 %.0f)" % [ly0, ry0],
		is_equal_approx(_h._pk_sum("left").y, ly0)
			and is_equal_approx(_h._pk_sum("right").y, ry0))
	_ok("★③ 敌方条【不受影响】(它的血早就不在敌方分子里了) %.3f → %.3f" % [t_pre.y, t1.y],
		absf(t1.y - t_pre.y) < 0.001)
