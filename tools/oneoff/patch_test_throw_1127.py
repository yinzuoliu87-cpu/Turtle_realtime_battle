p = "tests/verify_spear_synergy.gd"
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = "\t\t_s._ballistics._step_flights(step)\n\t\tt += step\n"
assert s.count(a) == 1
s = s.replace(a, "\t\t_s._ballistics._step_flights(step)\n\t\t_s._ballistics._step_pending_shots(step)   # 11-27 掷矛改成延时起手(回待机再掷)\n\t\tt += step\n")
i = s.index("\tfor _i in range(3):\n\t\t_s._basic_attack(c, near)\n\tvar far_before := float(far[\"hp\"])\n")
j = s.index("\"掷 %s · 出手时 %.0f · 飞到后 %.0f\" % [str(thrown), same_frame, far_before - float(far[\"hp\"])])\n", i)
j = s.index("\n", j) + 1
new = '''\t## 11-27 用户「普攻回到 idle，然后再在 idle 这上面去投掷…投掷的时候不普攻…完成投掷动作再普攻」:
\t##   第 3 下刺完 ⇒ 定身到掷完; THROW_LEAD 后起手, 再过 THROW_RELEASE 出手(这次掷矛占用第 4 下那一拍)
\tvar far_before := float(far["hp"])
\tvar th0: int = int(_p.stat["throw"])
\tfor _i in range(3):
\t\t_s._basic_attack(c, near)
\tvar SP = _p.get_script()
\tvar not_yet: bool = int(_p.stat["throw"]) == th0
\tvar locked: bool = float(c.get("channel_until", 0.0)) >= float(_s._t) + SP.THROW_LEAD + SP.THROW_ANIM - 0.01
\t_adv(SP.THROW_LEAD + SP.THROW_RELEASE + 0.05)
\tvar thrown: bool = int(_p.stat["throw"]) == th0 + 1
\tvar in_flight: float = far_before - float(far["hp"])
\t_adv(1.5)
\t_ok("D 四档掷矛: 第 3 下刺完不当场扔、定身到掷完(不出普攻) · 回待机后起手、出手才发飞矛 · 飞到最远的敌人才结算",
\t\tnot_yet and locked and thrown and in_flight == 0.0 and far_before - float(far["hp"]) > 0.0,
\t\t"刺完时没扔 %s · 定身 %s · 出手 %s · 在路上时伤害 %.0f · 飞到后 %.0f" % [str(not_yet), str(locked), str(thrown), in_flight, far_before - float(far["hp"])])
\tvar th1: int = int(_p.stat["throw"])
\t_s._basic_attack(c, near)
\t_ok("D 掷矛占用第 4 下那一拍: 之后下一记是普通的刺", int(_p.stat["throw"]) == th1, str(int(_p.stat["throw"]) - th1))
'''
s = s[:i] + new + s[j:]
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
