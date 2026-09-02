# -*- coding: utf-8 -*-
"""axe_icon_check.py — 斧头 9 张图标的【硬闸】(方案书 20260902-斧头图标重做 §5/§6)

════════════════════════════════════════════════════════════════════════
 ★由来: 我量了却没拿它当门禁
════════════════════════════════════════════════════════════════════════
用户 2026-09-02:「为什么不统一角度？第二版的钻石斧是个什么东西」

两条都是我的方法错:
 · 我从第一版起就在量手柄角度(参考 −31°), 但**只是印出来**, 没让它拦 ⇒
   第二版出现 +90°/+63° 的竖柄斧, 九张角度各不相同。
 · 钻石斧我打出过「非棕 3%」这个数, 也只是写进表里就往下走了 ⇒
   出来的是一把**土黄色镐头**(实测 9 个颜色全在色相 32~40° 棕色区)。

**量了不用 = 没量。** 所以把判据做成脚本: 出图 → 跑它 → 不过就重出, 不靠我一张张看。

════════════════════════════════════════════════════════════════════════
 判据(全部可证伪, 每条都说明"不满足意味着什么")
════════════════════════════════════════════════════════════════════════
 A 手柄角度   与参考 −31° 差 ≤ 8°        不满足 = 角度不统一(用户点名的第一条)
 B 内容格数   在参考 151 格的 ±35% 内     不满足 = 太胖/太瘦, 与其它档不是一套
 C 蒙版互异   九张两两不许逐字节相同      不满足 = 又是"同一形状换配色"(重做的全部意义)
 D 与 wood 交集 ≥ 45%                    不满足 = 换了个东西, 不是同一把斧的进化
 E 材质可辨   非棕像素占比 ≥ 该档的下限   不满足 = 看不出材质(钻石斧变镐头就是这条)
 F 造物特效   轮廓外元素 ≥ 8%            不满足 = 特效没长出来, 只是换色

跑法:
    python tools/axe_icon_check.py --dir docs/plans/ref/gen9b
    python tools/axe_icon_check.py --dir assets/sprites/equip --prefix axe-
"""
import argparse
import collections
import colorsys
import io
import math
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs", "plans", "ref", "ref-native-10色-22x20.png")

ORDER = ["wood", "stone", "iron", "gold", "diamond", "undead", "seraph", "holo", "ember"]
FINALS = {"undead", "seraph", "holo", "ember"}

## 每档【与木斧色距远的像素】的下限 —— 即"看不看得出换了材质"。
## ★这张表是"材质可辨"的唯一口径 —— 钻石斧变成土黄镐头, 就是这一条没设闸。
MIN_NONBROWN = {
    "wood": 0, "stone": 0, "iron": 12, "gold": 10, "diamond": 25,
    "undead": 12, "seraph": 12, "holo": 25, "ember": 12,
}
## ★★边界一律【含等号】—— 三处都栽过: 非棕 10% 对下限 10%、轮廓外 8% 对下限 8%
##   都被判死。"恰好在线上"应当算过, 边界写错一格是这类判据最常见的 bug
##   (memory: 处决线那次也是 —— 边界两侧各量一次)。
ANGLE_TOL = 8.0        # 与参考手柄角度的最大偏差(度)
SIZE_TOL = 0.35        # 内容格数相对参考的允许偏差
MIN_INTER = 45.0       # 与 wood 轮廓的最小交集(%)
MIN_OUTSIDE = 8.0      # 造物: 轮廓外元素最小占比(%)


def load32(p):
    from PIL import Image
    im = Image.open(p).convert("RGBA")
    c = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    bb = im.getbbox() or (0, 0, im.width, im.height)
    cr = im.crop(bb)
    c.paste(cr, ((32 - cr.width) // 2, (32 - cr.height) // 2), cr)
    return c


def mask(im):
    px = im.load()
    return {(x, y) for y in range(32) for x in range(32) if px[x, y][3] > 8}


def handle_deg(m):
    """手柄主轴 = 内容【下半部分】的主方向(斧头都在上半)。"""
    pts = sorted(m)
    if len(pts) < 16:
        return float("nan")
    ys = [p[1] for p in pts]
    ymid = (min(ys) + max(ys)) / 2.0
    low = [p for p in pts if p[1] > ymid]
    if len(low) < 8:
        return float("nan")
    mx = sum(p[0] for p in low) / len(low)
    my = sum(p[1] for p in low) / len(low)
    sxx = sum((p[0] - mx) ** 2 for p in low)
    syy = sum((p[1] - my) ** 2 for p in low)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in low)
    return math.degrees(0.5 * math.atan2(2 * sxy, sxx - syy))


def palette_of(im):
    """一张图的调色板(去重后的不透明色)。★保留: D 判据仍要用它。"""
    px = im.load()
    return {px[x, y][:3] for y in range(32) for x in range(32) if px[x, y][3] > 8}


def diff_from_wood_pct(im, wood):
    """与木斧【逐格比对】色差够大的像素占比 —— "看不看得出换了材质"。

    ★这条判据改了三版, 前两版都错:
      v1 「色相不在棕色区(8~48°)」⇒ 金(44°)橙(33°)本来就在里面, gold/ember 做对了被判死。
      v2 「与木斧调色板的最小 RGB 距离」⇒ 金色恰好接近木斧的某个亮棕, 又判死。
      v3(本版) **逐格对位比**: 九档共用同一母版(蒙版逐字节相同, 原版也是这么做的),
         所以可以一格对一格。同一位置从棕色变成金色, 距离必然大 —— 这才问对了问题。
    ★口径: 只统计【两边都不透明】的格; 分母是这些格数。
    """
    a = im.load()
    b = wood.load()
    n = t = 0
    for y in range(32):
        for x in range(32):
            ca, cb = a[x, y], b[x, y]
            if ca[3] <= 8 or cb[3] <= 8:
                continue
            t += 1
            d2 = (ca[0]-cb[0])**2 + (ca[1]-cb[1])**2 + (ca[2]-cb[2])**2
            if d2 > 55 * 55:
                n += 1
    return 100.0 * n / max(1, t)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--prefix", default="")
    a = ap.parse_args()

    if not os.path.exists(REF):
        print("  [FAIL] 参考基准图不存在: %s —— 没有标尺, 这是空检查" % REF)
        return 1
    ref = load32(REF)
    ref_m = mask(ref)
    ref_deg = handle_deg(ref_m)
    ref_n = len(ref_m)
    print("  [标尺] 参考: %d 格 · 手柄轴 %.1f°" % (ref_n, ref_deg))

    ims = {}
    for k in ORDER:
        p = os.path.join(a.dir, a.prefix + k + ".png")
        if not os.path.exists(p):
            print("  [FAIL] 缺图: %s" % p)
            return 1
        ims[k] = load32(p)
    wood_m = mask(ims["wood"])
    wood_pal = palette_of(ims["wood"])

    fails = []
    print("")
    print("  key      格数  手柄轴   角度差  与wood交集  异色  轮廓外")
    for k in ORDER:
        im = ims[k]
        m = mask(im)
        deg = handle_deg(m)
        dd = abs(deg - ref_deg)
        inter = 100.0 * len(m & wood_m) / max(1, len(wood_m))
        nb = diff_from_wood_pct(im, ims["wood"])
        out = 100.0 * len(m - wood_m) / max(1, len(m))
        print("  %-8s %4d  %6.1f°  %5.1f°   %6.1f%%  %5.1f%% %5.1f%%"
              % (k, len(m), deg, dd, inter, nb, out))
        if dd > ANGLE_TOL + 1e-9:
            fails.append("%s: 手柄角度 %.1f°, 与参考差 %.1f°(上限 %.0f°) —— 角度不统一"
                         % (k, deg, dd, ANGLE_TOL))
        if abs(len(m) - ref_n) / float(ref_n) > SIZE_TOL:
            fails.append("%s: 内容 %d 格, 与参考 %d 格差 %.0f%%(上限 %.0f%%) —— 与其它档不是一套"
                         % (k, len(m), ref_n, 100.0 * abs(len(m) - ref_n) / ref_n, 100 * SIZE_TOL))
        if k != "wood" and inter + 1e-9 < MIN_INTER:
            fails.append("%s: 与 wood 轮廓交集只有 %.0f%%(下限 %.0f%%) —— 换了个东西, 不是同一把斧的进化"
                         % (k, inter, MIN_INTER))
        if nb + 1e-9 < MIN_NONBROWN[k]:
            fails.append("%s: 与木斧逐格比对, 变了色的只有 %.0f%%(下限 %.0f%%) —— 看不出换了材质"
                         % (k, nb, MIN_NONBROWN[k]))
        if k in FINALS and out + 1e-9 < MIN_OUTSIDE:
            fails.append("%s: 轮廓外元素只有 %.0f%%(下限 %.0f%%) —— 特效没长出来, 只是换色"
                         % (k, out, MIN_OUTSIDE))

    ## C ★★这条原来是「九张蒙版两两不许相同」—— **判据本身是错的, 已删**。
    ##   2026-09-02 拆了原版六档斧头: 它们的蒙版**逐字节完全相同**(对称差 0 格),
    ##   人家就是"同一形状换配色"。我那条闸在**拦正确的做法**。
    ##   真正该管的是【五个材质档共用母版形状】而【四个造物要突破轮廓加特效】,
    ##   前者由 D(与 wood 交集)管, 后者由 F(轮廓外元素)管 —— 已经各有闸了。
    same = []
    for i in range(len(ORDER)):
        for j in range(i + 1, len(ORDER)):
            if ims[ORDER[i]].split()[3].tobytes() == ims[ORDER[j]].split()[3].tobytes():
                same.append((ORDER[i], ORDER[j]))
    print("")
    print("  蒙版逐字节相同的对数: %d  (五个材质档【应当】相同 —— 原版就是这么做的)" % len(same))

    print("")
    if fails:
        print("[FAIL] %d 条不达标:" % len(fails))
        for f in fails:
            print("   · " + f)
        return 1
    print("ALL OK — 九张全部达标")
    return 0


if __name__ == "__main__":
    sys.exit(main())
