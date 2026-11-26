p = "tests/verify_mask_items.gd"
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = "\t## ── I 135 黄金面具 ──\n"
assert s.count(a) == 1
b = '''\t## ── H2 倒地姿势(11-27): 有阵亡帧条的龟 ⇒ 倒下(阵亡帧正放)→ 趴着(定格 DOWN_F)→ 最后 0.5 秒倒放起身 → 回待机 ──
\t##   渲染层每帧调 AttackRhythm.downed_pose(读 _ven_t0 / _ven_until); 这里 _adv 不跑渲染, 每 0.1 秒直接调一次同一个函数
\tme = _mk("left", ["p2eq_134"], 0.0, 0.0, "basic")
\tfoe = _mk("right")
\t_field([me, foe])
\tme["hp"] = 100.0
\t_s._damage._apply_damage_from(foe, me, 999, Color.WHITE, 0.0, true)
\tvar pf: Array = []
\tvar ptex := ""
\tfor _q in range(26):
\t\tAttackRhythm.downed_pose(_s, me)
\t\tif me.get("_downed_pose", false) and is_instance_valid(me.get("sprite", null)):
\t\t\tpf.append(int(me["sprite"].frame))
\t\t\tvar _ptx = (me.get("anim_sd", {}) as Dictionary).get("tex", null)
\t\t\tptex = (_ptx as Texture2D).resource_path.get_file() if _ptx != null else ""
\t\telse:
\t\t\tpf.append(-1)
\t\t_adv(0.1)
\tvar back := not me.has("_downed_pose") and not bool(me.get("_manual_anim", false)) and str(me.get("anim_action", "x")) == ""
\tvar DF: int = AttackRhythm.DOWN_F
\t_ok("H2 倒地姿势: 阵亡帧条(%s)正放倒下 → 趴着定格第 %d 帧 → 最后 0.5 秒倒放起身 → 2.5 秒整回待机(帧号 %s)" % [ptex, DF, str(pf)],
\t\tptex == "death.png" and int(pf[0]) == 0 and int(pf[5]) == DF and int(pf[12]) == DF and int(pf[19]) == DF
\t\tand int(pf[22]) > 0 and int(pf[22]) < DF and int(pf[24]) <= 2 and int(pf[25]) == -1 and back, "回待机 %s" % str(back))

'''
s = s.replace(a, b + a)
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
