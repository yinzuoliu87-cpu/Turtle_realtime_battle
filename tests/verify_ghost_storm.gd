extends Node
## 幽灵龟两技(用户 2026-11-08):
##   「如果目标已经有诅咒，则造成百分之三百攻击力的真实伤害。并且…在原有诅咒基础上，就增加四秒诅咒」(灵魂风暴)
##   「冥魂突袭的那个数值本来是一百五十的攻击力，改为百分之二百五十的攻击力」(幽冥突袭)
## 期望值写需求字面值, 不引用 GhostSystem 常量(引用常量 = 常量改错了门禁跟着错)。
## 真场景 + 干净目标(双抗 0、无盾、无减伤), 直接调结算函数(不等演出 tween, CLAUDE.md §4.5)。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const WANT_CURSED_TRUE := 3.0      # 已诅咒: ×攻击力真实伤害
const WANT_CURSE_ADD := 4.0        # 两支都加 4 秒诅咒(已有的在剩余时间上加)
const WANT_PHANTOM := 2.5          # 幽冥突袭 ×攻击力魔法

var _fail := 0


func _chk(name: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", name, ("  " + detail) if detail != "" else ""])
	if not ok:
		_fail += 1


func _curse_left(s, u: Dictionary) -> float:
	for d in u.get("dots", []):
		if str(d.get("tag", "")) == "curse":
			return float(d.get("until", 0.0)) - float(s._t)
	return 0.0


func _clean(s, id: String, side: String, pos: Vector2) -> Dictionary:
	var u: Dictionary = s._spawn._make_unit(id, side, pos, {})
	u["maxHp"] = 100000.0; u["hp"] = 100000.0
	u["def"] = 0.0; u["mr"] = 0.0; u["base_def"] = 0.0; u["base_mr"] = 0.0
	u["shield"] = 0.0; u["flat_dr"] = 0.0; u["damage_reduction"] = 0.0
	u["crit"] = 0.0; u["dodge_bonus"] = 0.0
	s._units.append(u)
	return u


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true
	print("=== 幽灵龟·灵魂风暴 / 幽冥突袭(用户 11-08) ===")
	var s = RB.new()
	add_child(s)
	for _i in range(8):
		await get_tree().process_frame
	var g: Dictionary = _clean(s, "ghost", "left", Vector2(400, 400))
	## 技能结算里加增益会触发重算属性(幽冥突袭带自身闪避) ⇒ 攻击力要从基础攻击力设, 再重算一次
	g["base_atk"] = 100.0
	s._recalc_stats(g)
	var atk: float = float(g["atk"])
	_chk("分母: 幽灵龟攻击力 = 100(从基础攻击力算出)", absf(atk - 100.0) < 0.01, "%.2f" % atk)

	## ① 目标没有诅咒 ⇒ 上 4 秒诅咒(原行为, 不能被这次改坏)
	var t1: Dictionary = _clean(s, "stone", "right", Vector2(600, 400))
	s._ghost_sys._sk_ghost_soulstorm(g, t1)
	var left1: float = _curse_left(s, t1)
	print("  ① 无诅咒目标: 诅咒剩 %.2f 秒(需求 %.0f)" % [left1, WANT_CURSE_ADD])
	_chk("① 无诅咒 ⇒ 上 4 秒诅咒", absf(left1 - WANT_CURSE_ADD) < 0.01)

	## ② 目标已有诅咒(剩 3 秒) ⇒ 300% 攻击力真实伤害 + 诅咒剩余时间再加 4 秒
	var t2: Dictionary = _clean(s, "stone", "right", Vector2(600, 500))
	s._damage._add_curse(t2, 3.0, g)
	var before: float = _curse_left(s, t2)
	var hp0: float = float(t2["hp"])
	s._ghost_sys._sk_ghost_soulstorm(g, t2)
	var lost: float = hp0 - float(t2["hp"])
	var after: float = _curse_left(s, t2)
	print("  ② 已诅咒目标: 掉血 %.0f(需求 %.0f = %.0f%% × 攻击力 %.0f) · 诅咒 %.2f → %.2f 秒(需求 +%.0f)" % [
		lost, atk * WANT_CURSED_TRUE, WANT_CURSED_TRUE * 100.0, atk, before, after, WANT_CURSE_ADD])
	_chk("② 分母: 出手前目标确实带着诅咒", before > 2.9)
	_chk("② 已诅咒 ⇒ 300% 攻击力真实伤害", absf(lost - atk * WANT_CURSED_TRUE) <= 1.0, "%.0f" % lost)
	_chk("② 已诅咒 ⇒ 诅咒在剩余时间上再加 4 秒", absf(after - (before + WANT_CURSE_ADD)) < 0.01, "%.2f → %.2f" % [before, after])

	## ③ 幽冥突袭: 250% 攻击力魔法(目标魔抗 0 ⇒ 掉血 = 2.5 × 攻击力)
	var t3: Dictionary = _clean(s, "stone", "right", Vector2(600, 600))
	var hp3: float = float(t3["hp"])
	s._ghost_sys._ghost_phantom_hit(g, t3)
	var lost3: float = hp3 - float(t3["hp"])
	print("  ③ 幽冥突袭: 掉血 %.0f(需求 %.0f)" % [lost3, atk * WANT_PHANTOM])
	_chk("③ 幽冥突袭 250% 攻击力魔法伤害", absf(lost3 - atk * WANT_PHANTOM) <= 1.0, "%.0f" % lost3)

	s.queue_free()
	await get_tree().process_frame
	print("")
	print("ALL PASS — 幽灵龟两技(11-08)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
