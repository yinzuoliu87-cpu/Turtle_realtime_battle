"""revive_lock_1127.py —— 复活 2.5 秒里不移动、不行动、不转身(用户 11-27「复活的话，为什么角色还可以移动？复活角色不是不移动了吗？」)
① battle_damage.revive_begin: 定身(channel)对所有复活都上(原来只在 protect 分支里 ⇒ 驯服重生漏了, 复活期间照走照打)
② 主文件 _tick_unit: 朝向跟战斗目标那一行在「定身 return」之前 ⇒ 定身中也会转身; 复活窗口(_revive_until)内锁朝向
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:60])
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/battle/battle_damage.gd", [(
    "\t\tu[\"untargetable_until\"] = maxf(float(u.get(\"untargetable_until\", 0.0)), t + REVIVE_SEC)\n\t\tchannel(u, REVIVE_SEC)\n",
    "\t\tu[\"untargetable_until\"] = maxf(float(u.get(\"untargetable_until\", 0.0)), t + REVIVE_SEC)\n"
    "\tchannel(u, REVIVE_SEC)   # 复活期间不移动不行动: 所有复活都上(11-27 用户「复活角色不是不移动了吗」; 原来只在 protect 里 ⇒ 驯服重生漏了)\n")])

patch("scripts/scenes/RealtimeBattle3DScene.gd", [(
    "and not bool(u.get(\"_face_lock\", false)):   # _face_lock:",
    "and not bool(u.get(\"_face_lock\", false)) and _t >= float(u.get(\"_revive_until\", -1.0)):   # 复活倒地 2.5 秒不转身(11-27) · _face_lock:")])
print("ok")
