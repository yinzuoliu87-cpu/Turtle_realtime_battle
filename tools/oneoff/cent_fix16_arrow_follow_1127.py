"""cent_fix16_arrow_follow_1127.py —— 普攻的金色突刺气劲(spear-cent-thrust 帧条)跟着冲击罩走(用户 11-27「还有一个像箭头一样的…让那个东西也跟着罩子方向去走」)
  原来: cent_thrust 里在「百夫长 → 目标」中点原地画一次, 0.3 秒消失, 长度只到第一个目标 ⇒ 和往前冲的罩子分开
  现在: 固定长 CENT_ARROW_M, 箭头尖贴着罩子头部, 每帧跟着罩子(二档跟结算的冲击波波头)往前走, 帧条循环, 罩子散时一起淡掉
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "scripts/scenes/battle/spear_eq_vfx.gd")
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:70], s.count(a)); s = s.replace(a, b)
rep('''	_dir_strip(SV + "spear-cent-thrust.png", 7, mid, dir, ln * float(battle.WS), 24.0, 7.0 / 24.0, CENT_TIP_H)
	_cent_glow_on(u)''', '''	## 金色突刺气劲改由 _cent_impact_dome 建、跟着冲击罩走(11-27 用户「像箭头一样的…也跟着罩子方向去走」); 原来在这里原地画一次
	_cent_glow_on(u)''')
rep('''	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": maxf(CENT_SHOCK_SEC, dist / CENT_SHOCK_SPD), "p0": tip, "d3": d3, "dist": dist,
		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y})
''', '''	var arrow := _dir_strip(SV + "spear-cent-thrust.png", 7, Vector2(u["pos"]), Vector2(d3.x, d3.z), CENT_ARROW_M, 24.0, 0.0, tip.y)
	if arrow != null:
		(_mfx.back() as Dictionary)["loop"] = true   # 帧条循环, 跟罩子同生同灭(_stab_free 删)
		arrow.position = tip - d3 * (CENT_ARROW_M * 0.5 - 0.1)
	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": maxf(CENT_SHOCK_SEC, dist / CENT_SHOCK_SPD), "p0": tip, "d3": d3, "dist": dist,
		"u": u, "front": [fr_dark, fr_hot], "spray": spray, "skid": 0.0, "h": tip.y, "arrow": arrow})
''')
rep('''		var sp0 = st.get("spray")
''', '''		var ar0 = st.get("arrow")   # 突刺气劲: 箭头尖贴着罩子头部往前走
		if ar0 != null and is_instance_valid(ar0):
			(ar0 as Sprite3D).position = pos - d3 * (CENT_ARROW_M * 0.5 - 0.1)
			(ar0 as Sprite3D).modulate = Color(1.0, 1.0, 1.0, fd)
		var sp0 = st.get("spray")
''')
rep('''	for f in st.get("front", []):
		_free(f)
	_stop_ps(st.get("spray"))
''', '''	for f in st.get("front", []):
		_free(f)
	_stop_ps(st.get("spray"))
	_free(st.get("arrow"))
''')
rep('''		for f in st.get("front", []):
			_free(f)
		_free(st.get("spray"))
	_stabs.clear()
''', '''		for f in st.get("front", []):
			_free(f)
		_free(st.get("spray"))
		_free(st.get("arrow"))
	_stabs.clear()
''')
rep("const CENT_SHOCK_SPD := 16.0", "const CENT_ARROW_M := 2.6     # 突刺气劲长(米), 跟着罩子走\nconst CENT_SHOCK_SPD := 16.0")
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
