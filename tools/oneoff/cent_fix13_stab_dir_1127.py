"""cent_fix13_stab_dir_1127.py —— 普攻冲击罩朝敌人 + 二档沿穿刺线延伸(用户 11-27「方向朝哪儿呢？你应该朝着敌人啊…二档…还有延伸距离…冲击波你得想办法延伸」)
  方向 = 矛尖 → 目标(地面方向); 距离 = 矛尖到目标 + (2 档起 LINE_LEN 260 码, 否则 0.6 米); 速度固定 CENT_SHOCK_SPD ⇒ 路越长飞得越久
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
rel = "scripts/scenes/battle/spear_eq_vfx.gd"
p = os.path.join(ROOT, rel)
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
def rep(a, b):
    global s
    assert s.count(a) == 1, (a[:70], s.count(a)); s = s.replace(a, b)
rep('''	## 沿画面上矛指的方向冲(立绘是朝镜头的板, 矛在画面里永远水平 ⇒ 镜头的左右轴压到地面上); 原来朝目标冲, 目标斜着时罩子离开矛头
	var cx := Vector3(cb.x.x, 0.0, cb.x.z).normalized() if Vector3(cb.x.x, 0.0, cb.x.z).length() > 0.01 else Vector3.RIGHT
	var d3: Vector3 = cx * (1.0 if fr else -1.0)
	if tg.is_empty():
		return
	tip += d3 * 0.25   # 尖端略超出矛尖: 矛头罩在里面
''', '''	if tg.is_empty():
		return
	## 朝敌人冲(11-27 用户「方向朝哪儿呢？你应该朝着敌人啊」): 地面方向 = 矛尖 → 目标; 二档起沿穿刺线再延 LINE_LEN(与结算同一条线)
	var tgp: Vector3 = battle._world_pos(Vector2(tg["pos"]), tip.y)
	var fl := Vector3(tgp.x - tip.x, 0.0, tgp.z - tip.z)
	var d3: Vector3 = fl.normalized() if fl.length() > 0.05 else Vector3(1.0 if fr else -1.0, 0.0, 0.0)
	var tier: int = int(u.get("_cent_tier", 1))
	var dist: float = fl.length() + (SpearSynergySystem.LINE_LEN * float(battle.WS) if tier >= 2 else 0.6)
	tip += d3 * 0.25   # 尖端略超出矛尖: 矛头罩在里面
''')
rep('''	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": CENT_SHOCK_SEC, "p0": tip, "d3": d3, "dist": CENT_SHOCK_DIST})
''', '''	_stabs.append({"parts": parts, "bills": bills, "ring": ring, "t": 0.0, "life": maxf(CENT_SHOCK_SEC, dist / CENT_SHOCK_SPD), "p0": tip, "d3": d3, "dist": dist})
''')
rep("const CENT_SHOCK_DIST := 2.0\n", "const CENT_SHOCK_DIST := 2.0\nconst CENT_SHOCK_SPD := 16.0   # 冲击罩飞行速度(米/秒): 二档整条线(目标 + 260 码)约 0.6 秒\n")
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
