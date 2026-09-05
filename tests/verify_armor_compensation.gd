extends Node
## verify_armor_compensation.gd — 「真物理改造」的三处补偿系数不许只改一半 (2026-08-29)
##
## ══════════════════════════════════════════════════════════════════════
##  由来
## ══════════════════════════════════════════════════════════════════════
## 用户 2026-08-29 把口径讲清了：
##   「你选物理，就是在说这一发应该被护甲挡、被虚化躲」——
##   写"物理"不是描述它长什么样，是**指定它该被什么克制**。
##   "红字 + 不吃护甲" = 它已经是真实伤害了，只是画成红的。
##
## 本轮把三处从"不吃抗性的定额伤害"改成真吃抗性，并**按实测护甲分布补偿系数**，
## 使【平均强度不变】而【护甲从此能挡它】。
##
## ★补偿倍率是量出来的不是拍的：`tests/_probe_armor_dist.gd` 挂在产品自己的伤害管线上，
##   记下一场真实对局里**每一次挨打时目标此刻的护甲**（387 次）：
##     护甲 p10=10 · p25=10 · 中位=14 · p75=34 · p90=52 · 最大=85
##     （建表值只有 9~21 —— 局内被装备/岩层/铁壁/护盾 buff 抬上去了，所以必须量运行时）
##   逐次算倍率再平均 ⇒ 物理 0.6685 / 魔法 0.6745。
##   ★是"逐次算再平均"不是"拿中位护甲算一次" —— 倍率对护甲是凸函数，
##     代入中位数 14 给出 0.741，真平均是 0.669，差 7 个百分点。
##
## ══════════════════════════════════════════════════════════════════════
##  这条门禁守什么（不是"数我自己插的标记"）
## ══════════════════════════════════════════════════════════════════════
## 判据 = **产品里那几个常量的当前值** × 实测平均倍率 ≈ **改造之前的旧值**。
## 也就是说它守的是一条设计口径：「这三处改成吃抗性之后，平均强度不许变」。
## 谁把系数改回去、或者只改一半（比如把 `_phys_after_armor` 撤了却留着 ×1.5 的系数，
## 那会变成 1.5 倍白给），这条立刻红。
##
## ⚠ 这条**不**替代 `verify_dmg_type_sentinel` 的 ①d ——
##   那条守"真的走了抗性公式"，这条守"走了之后系数配套改了"。两条缺一不可：
##   只有 ①d ⇒ 有人改成吃护甲但不补系数 = 悄悄削弱 33%；
##   只有本条 ⇒ 有人留着系数把抗性撤掉 = 悄悄增强 50%。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_armor_compensation.tscn

const ShellSystem := preload("res://scripts/systems/skills/shell_system.gd")
const HookBombSystem := preload("res://scripts/systems/equip/hookbomb_system.gd")
const BasicConsts := preload("res://scripts/gamedata/basic_consts.gd")

## ★实测值（tests/_probe_armor_dist.gd，387 次真实挨打）。改这两个数 = 重新量过。
const ARMOR_AVG_MULT := 0.6685      # 物理：一发伤害平均会被护甲砍到原来的多少
const MAGIC_AVG_MULT := 0.6745      # 魔法：同上，按魔抗
## 允许的偏差：系数要凑成好记的整数（0.598 → 0.60），不可能精确等于。
## ±8% 足够容纳这种取整，又拦得住"忘了补"（那是 ‑33%）与"补两次"（+50%）。
const TOL := 0.08

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


## 现值 × 平均倍率 ≈ 旧值？
func _comp(label: String, now: float, old: float, mult: float) -> void:
	var eff: float = now * mult
	var rel: float = absf(eff - old) / maxf(0.000001, old)
	_ok("%s: 现值 %.4f × 平均倍率 %.4f = %.4f  ≈ 旧值 %.4f (偏差 %.1f%%)"
			% [label, now, mult, eff, old, rel * 100.0],
		rel <= TOL,
		"" if rel <= TOL else "★偏差超过 %.0f%% —— 要么系数没补, 要么补过头" % (TOL * 100.0))


func _ready() -> void:
	print("=== 真物理改造·补偿系数对账 ===")

	# ── 分母：三处常量都真的读到了(读不到会让下面全是拿 0 比 0 的假 PASS) ──
	_ok("★分母: 三处常量都取到且非零",
		ShellSystem.RELEASE_DMG_PCT > 0.0
			and BasicConsts.HEADLESS_BITE_MAXHP > 0.0
			and (HookBombSystem.BOMB_DPS_PCT as Array).size() == 3
			and (HookBombSystem.BLAST_FLAT as Array).size() == 3
			and HookBombSystem.BLAST_MAXHP_PCT > 0.0,
		"冲击波 %.2f / 撕咬 %.3f / 钩弹 %s / 聚爆 %s + %.2f"
			% [ShellSystem.RELEASE_DMG_PCT, BasicConsts.HEADLESS_BITE_MAXHP,
				str(HookBombSystem.BOMB_DPS_PCT), str(HookBombSystem.BLAST_FLAT),
				HookBombSystem.BLAST_MAXHP_PCT])
	_ok("★分母: 平均倍率在合理区间(0.4~0.9) —— 写成 1.0 会让所有对账恒真",
		ARMOR_AVG_MULT > 0.4 and ARMOR_AVG_MULT < 0.9
			and MAGIC_AVG_MULT > 0.4 and MAGIC_AVG_MULT < 0.9)

	# ── ① 龟壳被动·冲击波：储能 × 40% → 60% ──
	_comp("①冲击波 RELEASE_DMG_PCT", ShellSystem.RELEASE_DMG_PCT, 0.40, ARMOR_AVG_MULT)

	# ── ② 无头龟撕咬第二段：3% → 4.5% 目标最大生命【魔法】 ──
	_comp("②撕咬 HEADLESS_BITE_MAXHP", BasicConsts.HEADLESS_BITE_MAXHP, 0.03, MAGIC_AVG_MULT)

	# ── ③ 靶向器 p2eq_055：两段 ──
	var old_dps := [0.02, 0.04, 0.04]
	for i in range(3):
		_comp("③钩弹每秒 BOMB_DPS_PCT[%d]" % i,
			float((HookBombSystem.BOMB_DPS_PCT as Array)[i]), float(old_dps[i]), ARMOR_AVG_MULT)
	## ══════════════════════════════════════════════════════════════
	##  ★★★③b 聚爆两段：补偿口径 2026-09-06 被**用户主动削弱**覆盖了
	## ══════════════════════════════════════════════════════════════
	## 原来这里是 `_comp(..., old_flat=[200,400,500], 0.10)`，守的是
	## 「改成吃护甲之后**平均强度不许变**」——那条口径的前提是"这次只改伤害类型、不改强度"。
	##
	## 2026-09-06 用户：「病毒箭头爆炸伤害削弱为120/250/400+目标10%最大生命值」
	## ⇒ 这是**主动改强度**，那个锚（改造前的定额）不再是"应该保持的值"，
	##   继续拿它对账只会永远红。**但也不能改成拿新值反推 —— 那就成恒真式了。**
	##
	## ⇒ 判据换成两条仍然有意义的：
	##   ③b-1 这两个数 == **用户 2026-09-06 拍板的那几个**（谁再动谁红，走正常改数流程）
	##   ③b-2 **算出实际到手**并打印（面板 × 平均护甲倍率）——
	##        因为它们仍走 `_phys_after_armor`（由下面 ④ 守），面板 ≠ 玩家看到的掉血。
	##        留这个数是为了下次有人调它时**知道自己在调什么**。
	##
	## ★`BOMB_DPS_PCT`（附身 DoT）这次**没动** ⇒ 它上面那三条补偿对账**原样保留**，
	##   那条口径对它仍然成立。别顺手一起改。
	const USER_FLAT_20260906 := [120.0, 250.0, 400.0]
	const USER_PCT_20260906 := 0.10
	for i in range(3):
		var cur: float = float((HookBombSystem.BLAST_FLAT as Array)[i])
		_ok("③b-1 聚爆定额 BLAST_FLAT[%d] == 用户 2026-09-06 拍板的 %.0f（实际到手约 %.1f = 面板 × %.4f）"
				% [i, USER_FLAT_20260906[i], cur * ARMOR_AVG_MULT, ARMOR_AVG_MULT],
			is_equal_approx(cur, USER_FLAT_20260906[i]),
			"现值 %.1f ≠ %.1f —— 改数要连同本断言一起改" % [cur, USER_FLAT_20260906[i]])
	_ok("③b-1 聚爆 BLAST_MAXHP_PCT == 用户 2026-09-06 拍板的 %.0f%%（实际到手约 %.2f%%）"
			% [USER_PCT_20260906 * 100.0, HookBombSystem.BLAST_MAXHP_PCT * ARMOR_AVG_MULT * 100.0],
		is_equal_approx(HookBombSystem.BLAST_MAXHP_PCT, USER_PCT_20260906),
		"现值 %.4f ≠ %.4f" % [HookBombSystem.BLAST_MAXHP_PCT, USER_PCT_20260906])
	## ★分母：证明上面那两条不是拿常量比自己 —— 面板值必须真的**不等于**实际到手值，
	##   否则说明 ARMOR_AVG_MULT 被写成了 1.0，整条对账退化成恒真。
	_ok("③b-2 ★分母: 面板值 ≠ 实际到手（护甲倍率没被写成 1.0）",
		not is_equal_approx(float((HookBombSystem.BLAST_FLAT as Array)[0]),
			float((HookBombSystem.BLAST_FLAT as Array)[0]) * ARMOR_AVG_MULT),
		"两者相等 ⇒ ARMOR_AVG_MULT 失效，上面的『实际到手』全是假数")

	# ── ④ 系数配套的另一半：那三处【真的】还在走抗性公式 ──
	## ★只对账系数守不住"有人把 `_phys_after_armor` 撤了但留着 ×1.5" —— 那是白给 50%。
	##   源码扫描在这里是够的：判的是"这一行还在不在", 不是"运行时行为对不对"
	##   (运行时那半由 verify_dmg_type_sentinel ①d 守, 两条分工写在文件头注)。
	var shell_src := FileAccess.get_file_as_string("res://scripts/systems/skills/shell_system.gd")
	var hook_src := FileAccess.get_file_as_string("res://scripts/systems/equip/hookbomb_system.gd")
	var god_src := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	_ok("★分母: 三个源码文件都读到了(空串会让下面全是假 FAIL)",
		shell_src.length() > 1000 and hook_src.length() > 1000 and god_src.length() > 1000,
		"%d / %d / %d 字符" % [shell_src.length(), hook_src.length(), god_src.length()])
	_ok("★④ 冲击波仍走 _phys_after_armor", shell_src.contains("_phys_after_armor(u, float(dmg), e)"))
	_ok("★④ 钩索炸弹两段仍走 _phys_after_armor",
		hook_src.count("_phys_after_armor(") >= 2,
		"命中 %d 处" % hook_src.count("_phys_after_armor("))
	_ok("★④ 无头龟撕咬第二段仍走 _dot_after_resist",
		god_src.contains("_dot_after_resist(tgt, float(tgt[\"maxHp\"]) * BasicConsts.HEADLESS_BITE_MAXHP, true, u)"))

	print("")
	print("  (共 %d 条断言)" % _n)
	if _n < 15:
		print("  [FAIL] ★分母: 断言只有 %d 条(<15) —— 有用例没跑到" % _n)
		_fail += 1
	print("ALL PASS — 真物理改造补偿对账" if _fail == 0 else "FAIL x%d — 真物理改造补偿对账" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
