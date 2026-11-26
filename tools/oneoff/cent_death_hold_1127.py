"""cent_death_hold_1127.py —— 阵亡淡出前的等待可由单位自己声明(_death_hold, 默认仍是 T_SLOW 0.55 秒, 其它单位不变)
百夫长倒下帧条 12 帧 @12fps = 1 秒(膝盖一软 → 侧身倒地), 原来 0.55 秒就开始淡、0.95 秒淡完 ⇒ 人没倒到地上就没了(11-27 自查录像 27.7 秒只剩影子)。
百夫长声明 1.3 秒 = 倒完再在地上躺 0.3 秒才淡。纯演出(tween), 不碰结算。一次性; 原行尾二进制读写。
"""
import os
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (rel, a[:60])
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))


patch("scripts/scenes/RealtimeBattle3DScene.gd", [(
    "\t\t\tstw.tween_interval(UIPalette.T_SLOW)        # 等 death 帧演完",
    "\t\t\tstw.tween_interval(maxf(UIPalette.T_SLOW, float(u.get(\"_death_hold\", 0.0))))        # _death_hold: 帧条长的单位自己声明(百夫长 1.3 秒, 11-27) · 等 death 帧演完")])
patch("scripts/systems/equip/spear_synergy_system.gd", [(
    "\tp[\"bar_head_h\"] = 4.0",
    "\tp[\"_death_hold\"] = 1.3   # 倒下帧条 1 秒 + 在地上躺 0.3 秒再淡(11-27 自查: 原来没倒完就淡没了)\n\tp[\"bar_head_h\"] = 4.0")])
print("ok")
