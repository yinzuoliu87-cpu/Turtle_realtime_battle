# -*- coding: utf-8 -*-
"""sweep_check.py —— 量一段挥砍帧是不是「真横扫」(2026-11-25)。

由来: 用户 11-25「你不是量了吗？就看它到底有没有从一边横扫到另外一边啊？那很明显是没有，对吧？」——
  我上一版只看刀尖横坐标「右 → 左 → 右」就说绕身横扫了; 按刀的朝向量, 第 7 → 8 帧一帧翻了 166°(刀是跳过去的, 不是扫过去的),
  拖尾把这个跳变盖住了。
判据(屏幕上看一个在胸口高度水平转圈的刀): 朝向依次 指右 0° → 指镜头(屏幕上朝下, 刀变短) → 指左 180° → 指远处(朝上, 被身体挡) → 指右;
  ① 相邻两帧朝向变化 ≤ 60°(连续转过去, 没有跳); ② 刀尖高度在胸口一带(帧高 112 的 38~72 行); ③ 打印每帧 朝向 / 刀长 / 刀尖。
  python tools/oneoff/sweep_check.py <帧1.png> <帧2.png> ...      (刀身找不到的帧记「看不见」, 跳过它不算跳变)
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assetgen"))
import katana_trail as T  # noqa: E402
from PIL import Image  # noqa: E402

MAX_STEP = 60.0
CHEST = (38, 72)


def main():
    paths = sys.argv[1:]
    segs = []
    for p in paths:
        s = T.blade_seg(T._erase_cyan(Image.open(p).convert("RGBA")))
        segs.append((s[0], s[1]) if s else None)
    bad = 0
    prev = None
    for i, (p, s) in enumerate(zip(paths, segs)):
        name = os.path.basename(p)
        if not s:
            print("%2d %-16s 看不见" % (i, name))
            continue
        tip, hilt = s
        ang = math.degrees(math.atan2(-(tip[1] - hilt[1]), tip[0] - hilt[0]))
        ln = math.hypot(tip[0] - hilt[0], tip[1] - hilt[1])
        step = ""
        if prev is not None:
            d = abs((ang - prev + 180.0) % 360.0 - 180.0)
            step = "转 %3.0f°" % d
            if d > MAX_STEP:
                step += " ✗跳变"
                bad += 1
        chest = "" if CHEST[0] <= tip[1] <= CHEST[1] else " (刀尖不在胸口高度)"
        print("%2d %-16s 朝向 %5.0f° 刀长 %3.0f 刀尖 %-10s %s%s" % (i, name, ang, ln, tip, step, chest))
        prev = ang
    print("跳变 %d 处" % bad + ("  ALL OK" if bad == 0 else ""))


if __name__ == "__main__":
    main()
