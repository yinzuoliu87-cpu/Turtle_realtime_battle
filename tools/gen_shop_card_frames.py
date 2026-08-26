# -*- coding: utf-8 -*-
"""按费用档重上色生成商店卡框 card-frame-t1..t5.png。

由来: 用户 2026-07-29「框框的颜色不变吗，不是 5 档吗」→ 生成了 5 张按亮度重上色的框。
★但当时那段脚本**从没提交** —— `ShopScene.gd` 的注释写着「tools 里那段」, 而 tools 里没有。
  于是想调一档颜色就得从头猜算法。这次把它固化下来。

算法(照 ShopScene 注释复现): 拿中性框 `card-frame-n.png`, 按每个像素的**亮度**在
  暗端 = 目标色 × DARK
  亮端 = 目标色 向白 lerp LIGHT
之间插值; alpha 原样保留、形状逐像素一致。

★算法是不是复现对了, 有【客观判据】: 拿现有调色板重新生成 t2~t5,
  必须与盘上已有的文件**逐像素一致**。对不上就是我猜错了, 不许硬着头皮往下走。
  (verify 子命令干的就是这件事。)

用法:
  python tools/gen_shop_card_frames.py verify     # 只对账, 不写文件
  python tools/gen_shop_card_frames.py write      # 按 PALETTE 重新生成 5 张
"""
import io
import os
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

from PIL import Image

BASE = 'assets/sprites/shop/card-frame-n.png'
OUT = 'assets/sprites/shop/card-frame-t%d.png'

DARK = 0.20      # 暗端: 目标色 × 0.20
LIGHT = 0.15     # 亮端: 目标色 向白 15%

## 五档源色。
## ★1 费(2026-08-26, 用户拍板方案 A): `#9aa6b4` → `#a9a9a9`。
##   原因: `#9aa6b4` = (154,166,180) **蓝通道最高**, 是【蓝灰】——
##   和 3 费蓝 `#60a5fa` = (96,165,250) 同一个色相家族, 只差饱和度。
##   实测源色差只有 129(五档里最近的一对), 重上色又压到 61 ——
##   压暗把绝对色差砍掉一半以上, 所以名字看得清、框看不清。
##   换成**真中性灰**后色相不再和蓝撞。
## ⚠ 只改**框**的源色; 名字颜色仍走 `ShopScene._cost_color()` 的 `#9aa6b4` 不动 ——
##   那个值用户 2026-07-29 定过, 还推敲过在卡底 #11202e 上的对比度 6.68。
PALETTE = {
    1: '#a9a9a9',   # 灰(中性·2026-08-26 由 #9aa6b4 蓝灰改来)
    2: '#4ade80',   # 绿
    3: '#60a5fa',   # 蓝
    4: '#c084fc',   # 紫
    5: '#fbbf24',   # 金
}
## 复现对账用的【历史】调色板 —— 5 张现有文件就是拿它生成的。
LEGACY = dict(PALETTE)
LEGACY[1] = '#9aa6b4'


def hex2rgb(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def luma(r, g, b):
    """Rec.709 亮度(0~1)。

    ★不是 Rec.601。我第一版按 601 写, 复现出来差 5000 多像素、最大偏差 97 ——
      对现有 5 张做逐通道最小二乘, 601 的最大残差 9.34 / mean 6.11 / maxch 34.32,
      而 **709 只有 0.59**(≈只剩取整误差)。是量出来的, 不是挑的。
    """
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


def recolor(base, rgb):
    """按亮度把中性框重上色。返回新 Image。

    ★关键的一步是【按底框自己的亮度上限归一】, 我第一版漏了它:
      底框最亮处的 709 亮度只有 0.516(它本来就是张暗色金属框), 直接拿 lum∈[0,1]
      去插值等于**永远够不到亮端** ⇒ 整张偏暗、颜色也偏。
      回归反推出的归一上限 0.5185 与实测的 0.5163 对得上, 这才是原作者的做法。
    """
    out = Image.new('RGBA', base.size)
    src = base.load()
    dst = out.load()
    dark = tuple(c * DARK for c in rgb)
    light = tuple(c + (255 - c) * LIGHT for c in rgb)
    lmax = 0.0
    for y in range(base.height):
        for x in range(base.width):
            r, g, b, a = src[x, y]
            if a >= 128:
                lmax = max(lmax, luma(r, g, b))
    lmax = max(lmax, 1e-6)
    for y in range(base.height):
        for x in range(base.width):
            r, g, b, a = src[x, y]
            ## ★★全透明像素**也要照跑公式**, 不能特判成 (0,0,0,0)。
            ##   PNG 在 alpha=0 的像素底下**照样存着 RGB**, 原作者是对整张图无差别上色的
            ##   (实测 t3 的透明像素是 (19,33,50,0), 正好等于 #60a5fa 的暗端 (19.2,33,50))。
            ##   我第一版把它们清零 ⇒ 3134 个透明像素全部对不上, `verify` 报"最大偏差 53",
            ##   而那 53 完全来自看不见的像素 —— 差点让我以为算法还没复现对。
            k = min(luma(r, g, b) / lmax, 1.0)
            dst[x, y] = (
                int(round(dark[0] + (light[0] - dark[0]) * k)),
                int(round(dark[1] + (light[1] - dark[1]) * k)),
                int(round(dark[2] + (light[2] - dark[2]) * k)),
                a,
            )
    return out


def diff_px(a, b):
    """两张图不一致的像素数 + 最大单通道偏差。"""
    pa, pb = a.load(), b.load()
    n = 0
    worst = 0
    for y in range(a.height):
        for x in range(a.width):
            ca, cb = pa[x, y], pb[x, y]
            if ca != cb:
                n += 1
                worst = max(worst, max(abs(u - v) for u, v in zip(ca, cb)))
    return n, worst


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'verify'
    if not os.path.exists(BASE):
        print('缺中性底框 %s' % BASE)
        return 1
    base = Image.open(BASE).convert('RGBA')

    if mode == 'verify':
        ## ★算法复现对账: 用【历史】调色板重生成, 必须与盘上文件逐像素一致。
        ##   1 费那张是刚换过色的, 拿历史色对它 ⇒ 也应当一致(证明只有源色变了、算法没变)。
        bad = 0
        for k in sorted(LEGACY):
            p = OUT % k
            if not os.path.exists(p):
                print('  [FAIL] 缺 %s' % p)
                bad += 1
                continue
            cur = Image.open(p).convert('RGBA')
            for name, pal in (('当前', PALETTE), ('历史', LEGACY)):
                got = recolor(base, hex2rgb(pal[k]))
                n, worst = diff_px(got, cur)
                ## ★允许 ≤1 的偏差, 但**不是随手放宽**: 实测偏差分布是 {0: 319, 1: 1731},
                ##   **偏差 >1 的像素 0 个** —— 差的全是取整(原作者用的取整方式与 round 差半个)。
                ##   判据仍然很紧: 换个色、换个亮度权重、漏掉归一, 偏差立刻上到 38~97。
                if worst <= 1:
                    print('  [ OK ] t%d 与【%s调色板 %s】一致(%d 个像素差 1, 无一超过 1)'
                          % (k, name, pal[k], n))
                    break
            else:
                n, worst = diff_px(recolor(base, hex2rgb(PALETTE[k])), cur)
                print('  [FAIL] t%d 两套调色板都对不上(差 %d 像素, 最大偏差 %d)' % (k, n, worst))
                bad += 1
        print('')
        if bad:
            print('FAILED: %d 张对不上 —— 算法复现错了或文件被手改过' % bad)
            return 1
        print('ALL OK — 生成算法可复现')
        return 0

    if mode != 'write':
        print('用法: gen_shop_card_frames.py verify|write')
        return 1

    ## 只重生成【指定的档】, 默认全部。
    ## ★为什么支持指定: 现有 t2~t5 与本脚本的输出有 ±1 的取整抖动(见 verify 的说明),
    ##   没改色的档全部重写 = 白白改动 4 个二进制文件, diff 里看不出哪个是真改动。
    which = [int(a) for a in sys.argv[2:] if a.isdigit()] or sorted(PALETTE)
    for k in which:
        img = recolor(base, hex2rgb(PALETTE[k]))
        img.save(OUT % k)
        print('  已写 %s  ← %s' % (OUT % k, PALETTE[k]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
