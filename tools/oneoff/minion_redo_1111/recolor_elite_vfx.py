# -*- coding: utf-8 -*-
"""精英小将特效配色: 黑红 → 紫(11-11 深渊精英换成深蓝 + 紫光, 旧的黑红雾 / 地刺环 / 冲击环 / 刀光还是旧红紫精英的色)。
只改特效 Color(r, g, b, a) 字面量里偏红的那些(r 明显大于 g、b), 伤害数字 Color("#...") 不动; 不碰机制。
换法: 红 ×0.7、绿 ×0.6、蓝 = max(蓝, 红 × 1.1)(偏亮的提亮系数 > 1 的照样处理)。CRLF 二进制读写。"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
P = os.path.join(ROOT, "scripts", "systems", "skills", "elite_system.gd")
b = open(P, "rb").read()
s = b.decode("utf-8")
PAT = re.compile(r"Color\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)")
n = 0


def fix(m):
	global n
	r, g, bb, a = (float(m.group(i)) for i in range(1, 5))
	if not (r > g * 1.6 and r > bb * 1.6 and r > 0.08):
		return m.group(0)
	n += 1
	nr, ng, nb = r * 0.7, g * 0.6, max(bb, r * 1.1)
	return "Color(%s, %s, %s, %s)" % (round(nr, 3), round(ng, 3), round(nb, 3), m.group(4))


s2 = PAT.sub(fix, s)
## 地刺提亮: 偏紫(原 1.25 / 1.1 / 1.1 是给黑红刺提亮)
s2 = s2.replace("spk.modulate = Color(1.25, 1.1, 1.1, 1.0)", "spk.modulate = Color(1.05, 0.9, 1.35, 1.0)")
open(P, "wb").write(s2.encode("utf-8"))
print("换了 %d 处偏红特效色 → 紫" % n)
