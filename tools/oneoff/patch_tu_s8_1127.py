p = "tests/verify_trainer_untouchable.gd"
raw = open(p, "rb").read(); nl = b"\r\n" if b"\r\n" in raw else b"\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
a = '\tvar t_magic := ["p2eq_117", "p2eq_118", "p2eq_119", "p2eq_120", "p2eq_121", "p2eq_122", "p2eq_123", "p2eq_124", "p2eq_125", "p2eq_126"]\n'
assert s.count(a) == 1
b = a + ('\t## 2026-11-27 面具 / 长矛 / 筹码批: 30 件(千面里世界、鬼面潜行、鱼叉拽人、百夫长与骑兵召唤物、黄色筹码免控 …)⇒ 第 8 个场景\n'
	'\tvar t_mask := ["p2eq_127", "p2eq_128", "p2eq_129", "p2eq_130", "p2eq_131", "p2eq_132", "p2eq_133", "p2eq_134", "p2eq_135", "p2eq_136"]\n'
	'\tvar t_spear := ["p2eq_137", "p2eq_138", "p2eq_139", "p2eq_140", "p2eq_141", "p2eq_142", "p2eq_143", "p2eq_144", "p2eq_145", "p2eq_146"]\n'
	'\tvar t_chip := ["p2eq_147", "p2eq_148", "p2eq_149", "p2eq_150", "p2eq_151", "p2eq_152", "p2eq_153", "p2eq_154", "p2eq_155", "p2eq_156"]\n')
s = s.replace(a, b)
c = '\t\t\t"eqL": t_magic + t_bow, "eqR": t_shield + t_food + ["p2eq_024", "p2eq_044", "p2eq_053"]},\n'
assert s.count(c) == 1
d = c + ('\t\t{"tag": "S8 面具(里世界 / 潜行)+长矛(鱼叉 / 百夫长) vs 筹码(免控 / 复活)+药水", "L": g0, "R": g3, "tr_l": "tame", "tr_r": "hook", "ms_l": false,\n'
	'\t\t\t"eqL": t_mask + t_spear, "eqR": t_chip + t_potion},\n')
s = s.replace(c, d)
open(p, "wb").write(s.replace("\n", nl.decode()).encode("utf-8"))
q = "run-tests.sh"
raw = open(q, "rb").read()
o = "verify_trainer_untouchable) echo 30000 ;;   # 2026-11-25 第 6 个场景(匕首) · 第 7 个场景(魔法书)".encode()
assert raw.count(o) == 1
open(q, "wb").write(raw.replace(o, "verify_trainer_untouchable) echo 34000 ;;   # 2026-11-25 第 6 个场景(匕首) · 第 7 个场景(魔法书) · 11-27 第 8 个场景(面具/长矛/筹码)".encode()))
print("ok")
