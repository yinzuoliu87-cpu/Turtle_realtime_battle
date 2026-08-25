extends Node
## verify_lightning_buff.gd — 闪电龟·第四轮平衡加强 (用户 2026-07-29)
##
## 由来：第三轮胜率闪电 12.9% 全表垫底，三个技能 20.5 / 9.6 / 8.4% 没一个及格。
##   诊断：它是全表唯一普攻系数低于 1.0 的龟(0.6×ATK)，三个技能却全收全表最贵的 120 龟能
##   —— 交了"连锁税"却没拿到连锁回报。
##
## 用户口述的六条 + 我顺带修的一处代码/文案不符：
##   ① 基础生命 +40           901 → 941
##   ② 三技能龟能             120/120/120 → 涌动110 / 雷暴110 / 雷盾90
##   ③ 普攻系数               0.6×ATK → 0.9×ATK（连锁 ×0.6 递减【不动】）
##   ④ 雷暴总伤               2.2×ATK → 3.0×ATK（20 道各 0.15）
##   ⑤ 雷盾反击               0.1×ATK → 0.3×ATK
##   ⑥ 涌动持续               5 秒 → 8 秒
##   ⑦ ★涌动立即伤害 1.23 → 1.5×ATK ——【不是平衡改动, 是修 bug】：
##      1.23 = 0.82 × 1.5, 是被动电击还是 0.82×ATK 的时代留下的常量。2026-07-28 被动
##      已改成 1.0×ATK(_shock_dmg), 这里没跟着改 → 文案承诺 1.5×ATK、实发 1.23×ATK, 少 18%。
##
## ★期望值一律写【用户口述的字面需求值】, 不从代码常量读回来。
##   拿代码跟它自己比是恒真式 —— verify_trainer_magicstone 曾经就是这样, 把常量改坏照样 ALL PASS。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_lightning_buff.tscn

# ── 需求值(改需求才动这里) ──
const WANT_HP := 941
const WANT_ENERGY := {"涌动": 110, "雷暴": 110, "雷盾": 90}
const WANT_ATK_SCALE := 0.9      # 普攻主目标
const WANT_CHAIN_DECAY := 0.6    # 连锁每跳递减(本轮【没动】, 焊住防误改)
const WANT_BARRAGE_TOTAL := 3.0  # 雷暴总伤
const WANT_BARRAGE_BOLTS := 20
const WANT_COUNTER := 0.3        # 雷盾反击
const WANT_SURGE_SEC := 8.0      # 涌动持续
const WANT_SURGE_HIT := 1.5      # 涌动立即伤害

var _fail := 0


func _ready() -> void:
	print("=== 闪电龟·第四轮平衡加强 ===")

	# ── ① 基础生命 ──
	var pets: Array = _load_pets()
	_chk("★分母: pets.json 读到 %d 只龟" % pets.size(), pets.size() >= 28)
	var lg: Dictionary = {}
	for p in pets:
		if str(p.get("id", "")) == "lightning":
			lg = p
	if lg.is_empty():
		print("  [FAIL] ★分母: pets.json 里找不到 lightning"); _fail += 1; _done(); return
	print("  闪电基础: 生命 %d / 攻击 %d / 护甲 %d" % [int(lg["hp"]), int(lg["atk"]), int(lg["def"])])
	_chk("① 基础生命 = %d" % WANT_HP, int(lg["hp"]) == WANT_HP)

	# ── ② 三技能龟能: pets.json 与 skill_energy.gd 【两边都要对】 ──
	#    只查一边会漏 —— 战斗真正读的是 SkillEnergy, pets.json 是展示侧。
	var se := FileAccess.get_file_as_string("res://scripts/systems/skill_energy.gd")
	var se_key := {"涌动": "lightningSurgeBuff", "雷暴": "lightningBarrage", "雷盾": "lightningShield"}
	var pool: Array = lg["skillPool"]
	var seen := 0
	for s in pool:
		var nm := str(s.get("name", ""))
		if not WANT_ENERGY.has(nm):
			continue
		seen += 1
		var want: int = int(WANT_ENERGY[nm])
		print("     ② %s: pets.json = %d" % [nm, int(s.get("energyCost", -1))])
		_chk("② %s pets.json 龟能 = %d" % [nm, want], int(s.get("energyCost", -1)) == want)
		_chk("② %s skill_energy.gd 龟能 = %d" % [nm, want],
			se.contains('"%s": %d.0' % [se_key[nm], want]))
	_chk("② ★分母: 三个技能都扫到了(实到 %d)" % seen, seen == 3)

	# ── ③~⑦ 代码里的系数 ──
	#    源码级断言(与 verify_equip_nerf 同套路): 既查新值在、也查旧值【已消失】。
	#    只查新值不查旧值 → 有第二处漏改的旧代码时看不出来。
	var lsys := FileAccess.get_file_as_string("res://scripts/systems/skills/lightning_system.gd")
	var rb := FileAccess.get_file_as_string("res://scripts/scenes/RealtimeBattle3DScene.gd")
	var dmg := FileAccess.get_file_as_string("res://scripts/scenes/battle/battle_damage.gd")
	_chk("★分母: 三份源码都读到了",
		lsys.length() > 3000 and rb.length() > 100000 and dmg.length() > 3000)

	_chk("③ 普攻主目标 = %.1f×ATK" % WANT_ATK_SCALE,
		## ★比【常量的值】不比源码字面串(2026-08-22 根除已提成 LightningSystem)
		is_equal_approx(LightningSystem.BOLT_ATK_COEF, WANT_ATK_SCALE))
	_chk("③ 普攻旧值 0.6 已消失", not is_equal_approx(LightningSystem.BOLT_ATK_COEF, 0.6))
	_chk("③ 连锁递减仍是 ×%.1f(本轮不动)" % WANT_CHAIN_DECAY,
		is_equal_approx(LightningSystem.CHAIN_DECAY, WANT_CHAIN_DECAY))

	## ★2026-08-25 文案根除: `3.0 / 20.0` 这个算式抽成了两个常量 + 一个推导的每道系数,
	##   源码里已经没有那串字面量 —— 比【常量的值】, 并确认伤害那一行确实在引用推导常量。
	_chk("④ 雷暴 = %.1f×ATK / %d 道" % [WANT_BARRAGE_TOTAL, WANT_BARRAGE_BOLTS],
		is_equal_approx(LightningSystem.BARRAGE_TOTAL, WANT_BARRAGE_TOTAL)
			and LightningSystem.BARRAGE_BOLTS == WANT_BARRAGE_BOLTS
			and rb.contains("_atk_dmg(u, LightningSystem.BARRAGE_BOLT_COEF, e, true)"))
	_chk("④ 雷暴每道 = 总量 ÷ 道数(推导, 不是第二份手写值)",
		is_equal_approx(LightningSystem.BARRAGE_BOLT_COEF,
			WANT_BARRAGE_TOTAL / float(WANT_BARRAGE_BOLTS)))
	_chk("④ 雷暴旧值 2.2 已消失", not is_equal_approx(LightningSystem.BARRAGE_TOTAL, 2.2))

	## ★比【常量的值】不比源码串: 2026-08-24 这个系数抽成了 LightningSystem.SHIELD_RETALIATE,
	##   源码里已经没有 "0.3" 这个字面量了 —— 断言字面量的写法会随着代码变干净而假红。
	_chk("⑤ 雷盾反击 = %.1f×ATK" % WANT_COUNTER,
		is_equal_approx(LightningSystem.SHIELD_RETALIATE, WANT_COUNTER)
			and dmg.contains('LightningSystem.SHIELD_RETALIATE, src, true'))
	_chk("⑤ 雷盾反击旧值 0.1 已消失", not is_equal_approx(LightningSystem.SHIELD_RETALIATE, 0.1))

	## ★2026-08-24 起这些系数抽成了常量, 源码里没有字面量了 —— 比【值】, 并确认代码确实在引用它。
	_chk("⑥ 涌动持续 = %.1f 秒" % WANT_SURGE_SEC,
		is_equal_approx(LightningSystem.SURGE_SEC, WANT_SURGE_SEC)
			and lsys.contains('u["shock_boost_until"] = battle._t + SURGE_SEC'))
	_chk("⑥ 涌动旧值 5 秒已消失", not is_equal_approx(LightningSystem.SURGE_SEC, 5.0))
	_chk("⑥ 涌动光环时长跟到 %.1f 秒(灭了但buff还在=误导)" % WANT_SURGE_SEC,
		lsys.contains("Color(0.3, 0.67, 0.97, 0.5), SURGE_SEC)"))

	## SURGE_HIT_COEF 是推导常量(SHOCK_COEF × (1+SURGE_BOOST)) —— 比它算出来的值。
	_chk("⑦ 涌动立即伤害 = %.1f×ATK(与文案一致)" % WANT_SURGE_HIT,
		is_equal_approx(LightningSystem.SURGE_HIT_COEF, WANT_SURGE_HIT)
			and lsys.contains('int(u["atk"] * SURGE_HIT_COEF)'))
	_chk("⑦ 涌动旧遗留常量 1.23 已消失", not is_equal_approx(LightningSystem.SURGE_HIT_COEF, 1.23))

	# ── ⑧ 文案必须跟着数值走(否则玩家看到的是旧数字) ──
	var pj := FileAccess.get_file_as_string("res://data/pets.json")
	## ★2026-08-25 同上: 普攻公式也换成了常量引用 `{M:LightningSystem.BOLT_ATK_COEF*ATK}`。
	##   判据 = 「常量值对」且「文案确实指着它(或还写着等值的字面量)」——
	##   这样"文案变干净"不会假红, 而"文案指错常量 / 数值漂了"仍然当场红。
	_chk("⑧ 普攻文案 = %.1f×ATK" % WANT_ATK_SCALE,
		is_equal_approx(LightningSystem.BOLT_ATK_COEF, WANT_ATK_SCALE)
			and (pj.contains("{M:LightningSystem.BOLT_ATK_COEF*ATK}")
				or pj.contains("{M:%.1f*ATK}" % WANT_ATK_SCALE)))
	## ★2026-08-25 文案根除: 雷暴不再手写「单道系数 × 道数」——
	##   代码里本来就是 `BARRAGE_TOTAL / BARRAGE_BOLTS`, 文案现在直接引用总量常量。
	##   判据 = 两个常量的值都对 + 文案确实指着总量(或还写着旧的乘积式)。
	_chk("⑧ 雷暴文案 = 合计 %.1f×ATK(%d 道)" % [WANT_BARRAGE_TOTAL, WANT_BARRAGE_BOLTS],
		is_equal_approx(LightningSystem.BARRAGE_TOTAL, WANT_BARRAGE_TOTAL)
			and LightningSystem.BARRAGE_BOLTS == WANT_BARRAGE_BOLTS
			and (pj.contains("{M:LightningSystem.BARRAGE_TOTAL*ATK}")
				or pj.contains("{M:%.2f*ATK*%d}" % [WANT_BARRAGE_TOTAL / WANT_BARRAGE_BOLTS, WANT_BARRAGE_BOLTS])))
	## ★2026-08-25: 公式占位符现在可以引用常量(`{M:LightningSystem.SHIELD_RETALIATE*ATK}`),
	##   grep 字面量 `{M:0.3*ATK}` 会因为"文案变干净了"而假红 —— 认常量引用, 并比它的值。
	_chk("⑧ 雷盾文案 = %.1f×ATK" % WANT_COUNTER,
		is_equal_approx(LightningSystem.SHIELD_RETALIATE, WANT_COUNTER)
			and (pj.contains("{M:LightningSystem.SHIELD_RETALIATE*ATK}")
				or pj.contains("{M:%.1f*ATK}" % WANT_COUNTER)))
	## ★文案里现在是占位符 {C:LightningSystem.SURGE_SEC} —— 要先渲染再比,
	##   直接 grep 原文会因为"代码变干净了"而假红。
	_chk("⑧ 涌动文案 = %d 秒" % int(WANT_SURGE_SEC),
		_has_txt(SkillText.render_consts(pj), "接下来%d秒内被动电击" % int(WANT_SURGE_SEC)))

	# ── ⑨ 换算成人话, 打印出来给人看(数字不打出来就没法复核) ──
	var A: float = float(lg["atk"])
	var chain_total: float = WANT_ATK_SCALE * (1.0 + WANT_CHAIN_DECAY + WANT_CHAIN_DECAY * WANT_CHAIN_DECAY)
	print("")
	print("  ── 换算(攻击力 %.0f) ──" % A)
	print("     普攻主目标 %.1f  |  连锁两跳 %.1f + %.1f  |  三段合计 %.2f×ATK = %.1f" % [
		WANT_ATK_SCALE * A, WANT_ATK_SCALE * WANT_CHAIN_DECAY * A,
		WANT_ATK_SCALE * WANT_CHAIN_DECAY * WANT_CHAIN_DECAY * A, chain_total, chain_total * A])
	print("     雷暴总伤 %.0f (单道 %.1f ×%d, 随机散射→主目标约 1/3 = %.0f)" % [
		WANT_BARRAGE_TOTAL * A, WANT_BARRAGE_TOTAL / WANT_BARRAGE_BOLTS * A,
		WANT_BARRAGE_BOLTS, WANT_BARRAGE_TOTAL * A / 3.0])
	print("     雷盾每段反击 %.1f  |  涌动立即 %.0f + %.0f 秒增伤窗口" % [
		WANT_COUNTER * A, WANT_SURGE_HIT * A, WANT_SURGE_SEC])

	_done()


func _load_pets() -> Array:
	var raw := FileAccess.get_file_as_string("res://data/pets.json")
	var j = JSON.parse_string(raw)
	if j is Array:
		return j
	if j is Dictionary:
		for v in (j as Dictionary).values():
			if v is Array:
				return v
	return []


func _chk(name: String, ok: bool) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		_fail += 1


func _done() -> void:
	if _fail == 0:
		print("ALL PASS — 闪电龟第四轮加强")
		get_tree().quit(0)
	else:
		print("FAIL x%d" % _fail)
		get_tree().quit(1)


## 文案子串比对: 先把**空格全去掉**再比。
## ★2026-08-19 排版统一(数字与汉字之间补空格)一次打断了三条这样的断言。
##   它们真正要守的是"这个数值有没有出现在文案里", **不是"空格打在哪"** ——
##   拿排版当判据, 每次改一次文案排版就要改一遍测试, 而且红了还看不出是真是假。
func _has_txt(hay: String, needle: String) -> bool:
	return hay.replace(" ", "").replace("　", "").contains(needle.replace(" ", ""))
