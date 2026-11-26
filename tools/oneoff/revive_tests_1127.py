"""revive_tests_1127.py —— 复活改成 2.5 秒分 5 段回血(用户 11-27)后, 五条测试跟着改判据。一次性; 原行尾二进制读写。"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        n = s.count(a)
        if n != 1:
            sys.exit("%s: 命中 %d 次: %r" % (rel, n, a[:90]))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok", rel)


patch("tests/verify_mask_items.gd", [
("""		_m.tick(step)
		for u in units:
			_m.tick_unit(u, step)
		_s._ballistics._step_flights(step)""",
"""		_m.tick(step)
		_s._damage.revive_tick()
		for u in units:
			_m.tick_unit(u, step)
		_s._ballistics._step_flights(step)"""),
("""	var down_untg: bool = _s._is_untargetable(me)
	_adv(1.25)
	var mid := float(me["hp"])
	_adv(1.3)
	var up := float(me["hp"])
	_s._damage._apply_damage_from(foe, me, 999999, Color.WHITE, 0.0, true)
	_ok("H 致命一击不死、倒地不可选中 · 1.25 秒时 %.0f(涨到一半) · 2.5 秒后 %.0f = 30%% · 第二次致命照死" % [mid, up],
		down_alive and down_untg and mid > 600.0 and mid < 900.0 and absf(up - float(me["maxHp"]) * 0.3) < 1.0 and not bool(me.get("alive", true)),
		"活 %s · 不可选 %s" % [str(down_alive), str(down_untg)])""",
"""	var down_untg: bool = _s._is_untargetable(me)
	var heal0 := float(me.get("_st_heal", 0.0))
	## 11-27 用户「在两点五秒内血量是逐渐涨的…要有加的数字…你可以断断的加血」⇒ 每 0.5 秒一段、共 5 段, 每段走回血(统计 + 绿字)
	var hs: Array = []
	for _q in range(5):
		_adv(0.25)
		hs.append(float(me["hp"]))   # 段中间: 还没到下一段
		_adv(0.25)
		hs.append(float(me["hp"]))   # 段末: 刚补完这一段
	var to := float(me["maxHp"]) * 0.3
	var stepped := true
	for q in range(5):
		if absf(float(hs[q * 2 + 1]) - to * float(q + 1) / 5.0) > 1.0:
			stepped = false
		if q > 0 and absf(float(hs[q * 2]) - float(hs[q * 2 - 1])) > 0.01:
			stepped = false   # 段与段之间不涨(是一段一段加, 不是每帧涨)
	var up := float(me["hp"])
	var healed := float(me.get("_st_heal", 0.0)) - heal0
	_s._damage._apply_damage_from(foe, me, 999999, Color.WHITE, 0.0, true)
	_ok("H 致命一击不死、倒地不可选中 · 2.5 秒分 5 段涨到 30%% (%s) · 记进回血统计 %.0f · 第二次致命照死" % [str(hs), healed],
		down_alive and down_untg and stepped and absf(up - to) < 1.0 and absf(healed - (to - 1.0)) < 2.0 and not bool(me.get("alive", true)),
		"活 %s · 不可选 %s" % [str(down_alive), str(down_untg)])"""),
])

patch("tests/verify_chip_items.gd", [
("""		_c.tick(step)
		_s._equip_sys._mask_sys.tick(step)""",
"""		_c.tick(step)
		_s._equip_sys._mask_sys.tick(step)
		_s._damage.revive_tick()"""),
])

patch("tests/verify_lethal_hook_heal.gd", [
("""	s._damage._apply_damage_from(atk2, vic2, 200, Color.WHITE)
	var pct := float(vic2["hp"]) / float(vic2["maxHp"])""",
"""	s._damage._apply_damage_from(atk2, vic2, 200, Color.WHITE)
	for _i in range(52):   # 11-27: 复活 = 2.5 秒倒地分 5 段回到 25%(用户「在两点五秒内血量是逐渐涨的」)
		s._t += 0.05
		s._damage.revive_tick()
	var pct := float(vic2["hp"]) / float(vic2["maxHp"])"""),
("""		vic2.get("alive", false) and pct > 0.15)""",
"""		vic2.get("alive", false) and absf(pct - AngelSystem.REVIVE_HP_PCT) < 0.01)"""),
])

patch("tests/verify_tame_defection.gd", [
("""	_ok("③ 复活血量 = 30% 最大生命(需求字面值)",
		absf(float(victim.get("hp", 0)) / maxf(1.0, float(victim.get("maxHp", 1))) - 0.30) < 0.02,
		"%.1f%%" % (100.0 * float(victim.get("hp", 0)) / maxf(1.0, float(victim.get("maxHp", 1)))))""",
"""	for _i in range(52):   # 11-27: 复活 = 2.5 秒分 5 段回到 30%(用户「在两点五秒内血量是逐渐涨的」; 演出期无敌, 只推复活回血)
		s._t += 0.05
		s._damage.revive_tick()
	_ok("③ 复活血量 = 30% 最大生命(需求字面值, 2.5 秒分段回满)",
		absf(float(victim.get("hp", 0)) / maxf(1.0, float(victim.get("maxHp", 1))) - 0.30) < 0.02,
		"%.1f%%" % (100.0 * float(victim.get("hp", 0)) / maxf(1.0, float(victim.get("maxHp", 1)))))"""),
])

patch("tests/verify_trainer_hunt_tame.gd", [
("""	s._kill(f2)                                            # 走真实死亡路径
	var alive_after: bool = bool(f2.get("alive", false))
	var hp_frac: float = float(f2["hp"]) / mx""",
"""	s._kill(f2)                                            # 走真实死亡路径
	var alive_after: bool = bool(f2.get("alive", false))
	for _i in range(52):   # 11-27: 复活 = 2.5 秒分 5 段回到 30%(用户「在两点五秒内血量是逐渐涨的」)
		s._t += 0.05
		s._damage.revive_tick()
	var hp_frac: float = float(f2["hp"]) / mx"""),
])
