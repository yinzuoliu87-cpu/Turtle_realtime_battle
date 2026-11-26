"""cent_fix2_1127.py —— 百夫长第二轮(用户 11-27):
  「为什么是浮空的？」⇒ 打包脚底对齐 186 → 191(帧底; 已在 pack 脚本里改, 本脚本不重复)
  「投掷动画…肯定是不合格的」⇒ 掷矛换成 throw2(16 帧: 举矛 → 矛后拉 → 第 9 帧整个人前冲、手臂甩出、矛离手 → 前倾随势 → 掏出新矛站直);
      帧条取 1..16(去掉 0 = 站姿), @16 = 1.0 秒, 出手帧 = 下标 7(0.44 秒); 结算 THROW_ANIM 0.58 → 1.0、THROW_RELEASE 0.17 → 0.44
      飞矛从手里出去 —— 出手前那几帧手里拿着矛, 出手后空手(帧里画的就是这样)
  「落地那个圈太小了…整个岛…大一点啊」⇒ 预警标记圈直径 4 → 9 米
  「身后拖一道金色和红缨色的下坠光尾」⇒ 下落时本体头顶上方挂 spear-cent-trail(特效工作台自写图层: 白金芯 + 红缨色外缘 + 速度线 + 火星, 6 帧循环),
      跟着本体一起往下砸, 落地那一刻消失
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
        assert s.count(a) == 1, (rel, a[:70])
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("tools/assetgen/pack_spear_chip_art.py", [
    ('    "eq-centurion-throw":  ("throw",         [3, 4, 5, 6, 7, 8, 0]),                   # 从举矛过肩截起: 出手在下标 2(引擎里飞矛动作一开始就发)\n',
     '    "eq-centurion-throw":  ("throw2",        list(range(1, 17))),                      # 11-27 用户「投掷动画…不合格」重出: 举矛后拉 → 下标 7 整个人前冲甩出、矛离手 → 前倾随势 → 掏新矛站直(16 帧 @16 = 1 秒)\n'),
    ('            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False), ("centurion-drop-marker", "spear-cent-marker", False)]:\n',
     '            ("centurion-aegis-open+centurion-aegis-loop", "spear-cent-aegis", False), ("centurion-drop-marker", "spear-cent-marker", False),\n'
     '            ("centurion-fall-trail", "spear-cent-trail", False)]:\n'),
])

patch("scripts/systems/equip/spear_synergy_system.gd", [
    ("const THROW_ANIM := 0.58\nconst THROW_RELEASE := 0.17\n",
     "const THROW_ANIM := 1.0      # 11-27 重出的掷矛动作 16 帧 @16\nconst THROW_RELEASE := 0.44   # 出手帧 = 第 8 帧(下标 7)\n"),
])

patch("scripts/scenes/battle/spear_eq_vfx.gd", [
    ("const CENT_MARKER_M := 4.0      # 预警标记圈直径(米)\n",
     "const CENT_MARKER_M := 9.0      # 预警标记圈直径(米; 4 时用户 11-27「落地那个圈太小了…大一点啊」)\nconst CENT_TRAIL_M := 7.0       # 下坠光尾长(米)\n"),
    ("\t_cent_play(u, \"throw\", 12.0)\n",
     "\t_cent_play(u, \"throw\", 16.0)   # 16 帧 = 1 秒, 出手帧下标 7(结算 THROW_RELEASE 同一刻)\n"),
    ('\t_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec), "mk": mk, "sp": sp, "planted": false, "ghost": 0.0})\n',
     '\tvar tr := _strip(V + "spear-cent-trail.png", 6, battle._world_pos(Vector2(p["pos"]), CENT_DROP_H), CENT_TRAIL_M, 16.0, true, sec, false, null, 0.0)\n'
     '\tif tr != null:\n'
     '\t\ttr.visible = false   # 开始砸下那一刻才亮(下面 tick 里跟着本体)\n'
     '\t_lands.append({"u": p, "t": 0.0, "sec": maxf(0.1, sec), "mk": mk, "sp": sp, "tr": tr, "planted": false, "ghost": 0.0})\n'),
    ('\t\t\tu["_slam_voff"] = Vector3(0.0, CENT_DROP_H * (1.0 - k * k), 0.0)   # 加速砸下(落地那一刻由 cent_impact 归零)\n',
     '\t\t\tu["_slam_voff"] = Vector3(0.0, CENT_DROP_H * (1.0 - k * k), 0.0)   # 加速砸下(落地那一刻由 cent_impact 归零)\n'
     '\t\t\tvar tr = l.get("tr")\n'
     '\t\t\tif tr != null and is_instance_valid(tr):   # 下坠光尾: 挂在本体头顶上方, 跟着往下砸\n'
     '\t\t\t\t(tr as Sprite3D).visible = k < 1.0\n'
     '\t\t\t\t(tr as Sprite3D).position = battle._world_pos(Vector2(u["pos"]), CENT_DROP_H * (1.0 - k * k) + 1.6)\n'),
])
print("ok")
