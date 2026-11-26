"""cent_fix18_stab_orient_1127.py —— 普攻冲击罩朝向压平(11-27 自查一档录像: 目标在右下方近处时罩子朝镜头钻, 看着像往上冒的火柱、前沿亮环变成正对镜头的圆)
  路线不变(矛尖 → 目标, 二档再延伸); 只有罩子 / 前沿环 / 火花 / 出手环的朝向去掉 75% 的「朝镜头 / 背镜头」分量 ⇒ 画面上跟矛一样基本横着指;
  目标几乎正对镜头方向时退回按本体朝向横指。突刺气劲本来就按屏幕投影画, 不动。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
p = os.path.join(ROOT, "scripts/scenes/battle/spear_eq_vfx.gd")
raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
s = raw.decode("utf-8").replace("\r\n", "\n")
i = s.index("func _cent_impact_dome(")
j = s.index("\nfunc ", i + 10)
body = s[i:j]
a = "\ttip += d3 * 0.25   # 尖端略超出矛尖: 矛头罩在里面\n\tvar yaw: float = Cent3dVfx.yaw_of(Vector2(d3.x, d3.z))\n"
assert body.count(a) == 1
body = body.replace(a, "\ttip += d3 * 0.25   # 尖端略超出矛尖: 矛头罩在里面\n"
    "\t## 朝向压平: 去掉 75% 朝镜头 / 背镜头的分量(画面上的矛永远横着刺), 路线仍是 d3\n"
    "\tvar camf := Vector3(cb.z.x, 0.0, cb.z.z).normalized() if Vector3(cb.z.x, 0.0, cb.z.z).length() > 0.01 else Vector3.BACK\n"
    "\tvar d3v: Vector3 = d3 - camf * d3.dot(camf) * 0.75\n"
    "\td3v = d3v.normalized() if d3v.length() > 0.2 else Vector3(cb.x.x, 0.0, cb.x.z).normalized() * (1.0 if fr else -1.0)\n"
    "\tvar yaw: float = Cent3dVfx.yaw_of(Vector2(d3v.x, d3v.z))\n")
a = "\tvar yaw2: float = Cent3dVfx.yaw_of(Vector2(d3.x, d3.z))\n"
assert body.count(a) == 1
body = body.replace(a, "\tvar yaw2: float = yaw\n")
s = s[:i] + body + s[j:]
open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
print("ok")
