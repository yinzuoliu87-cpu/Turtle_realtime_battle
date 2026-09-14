# -*- coding: utf-8 -*-
"""059 沙漏【时停期间】携带者周身的「时之砂」8 帧循环 (2026-09-14)。

★为什么要有这张图 —— 它是来【替换一颗白球】的, 不是新加演出:
  原来 `_ts_caster_glow` 在携带者身上贴一颗 150 码的 `VfxTex._make_fire_glow_tex()` 金球。
  染色法核实(把它的 modulate 改成品红重拍): 那团白【就是它】,
  而它把携带者**整只盖没了** —— 并排图里时停前能看见龟, 时停中只剩一颗白球。

  两条都踩了:
  ① 「无含义白球」是本仓点名过的禁区形状 (memory [[fb-vfx-defect-families]]);
  ② **方向和参考正好相反** —— JoJo 那 149 帧里, 时之主(DIO/承太郎)是定格世界里
     **唯一清晰、唯一正常**的那个, 没有任何光球罩着他
     (逐帧研究 docs/studies/20260914e-059时停参考逐帧.md)。

★为什么是「沙」而不是随便换个形状:
  059 就叫【沙漏】, 而且蓄力那 1 秒已经在放「金沙粒螺旋汇入」(`_ts_charge_vfx`)。
  定格期间让少量沙继续绕着他走 = **同一条因果链的延续**, 不是凭空发明
  (memory [[fb-telegraph-needs-a-cause-not-a-flash]]: 预兆要有因)。
  颗粒稀疏 ⇒ 盖不住龟, 正好是白球的反面。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = 1.775 码。
  cell 36×36 texel ⇒ 按 64 码摆(36 × 1.775 = 63.9), 正好 1:1, 比龟略大一圈。
"""
import os
import math

from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 36
FRAMES = 8
CX = CY = CELL / 2.0 - 0.5

CLR = (0, 0, 0, 0)
## 沙的三档(暗→亮)。与蓄力那段的金沙同色系, 形状是新画的。
SAND_D = (128, 88, 30, 150)    # 背面/远端的沙(暗, 半透 ⇒ 不挡龟)
SAND_M = (206, 158, 62, 195)
SAND_L = (255, 222, 136, 230)  # 正面/近端的沙(亮)

## 14 颗沙: (起始相位, 椭圆半径, 高度, 每帧转多少)。半径/高度/速度都不一样
## ⇒ 读成"一把散着走的沙", 不是"一圈规则的点"(规则的圈 = 被点名过的形状)。
GRAINS = [
    (0.00, 15.5, -2.0, 0.30), (0.52, 13.0,  1.5, 0.26), (1.05, 16.2,  4.0, 0.33),
    (1.57, 11.5, -4.5, 0.24), (2.09, 15.0,  6.5, 0.29), (2.62, 13.8, -1.0, 0.31),
    (3.14, 16.5,  2.5, 0.27), (3.67, 12.2,  5.5, 0.34), (4.19, 15.8, -3.5, 0.25),
    (4.71, 14.0,  7.5, 0.32), (5.24, 16.0,  0.5, 0.28), (5.76, 12.8, -5.5, 0.35),
    (0.79, 16.8,  8.5, 0.23), (2.36, 11.0,  3.0, 0.36),
]
SQUASH = 0.42      # 俯视角下的圆压成椭圆(比 044/045 更扁 —— 这圈沙是"绕着脚踝走"的)


def _px(im, ox, x, y, c):
    xi, yi = int(round(x)), int(round(y))
    if 0 <= xi < CELL and 0 <= yi < CELL:
        im.putpixel((ox + xi, yi), c)


def _draw_frame(im, f):
    ox = f * CELL
    for (a0, r, hy, spd) in GRAINS:
        ang = a0 + f * spd
        x = CX + math.cos(ang) * r
        y = CY + math.sin(ang) * r * SQUASH - hy
        ## 正面(sin > 0, 朝屏幕下方 = 离相机近)亮, 背面暗 ⇒ 读得出它在【绕着转】
        s = math.sin(ang)
        core = SAND_L if s > 0.45 else (SAND_M if s > -0.35 else SAND_D)
        _px(im, ox, x, y, core)
        ## 只有正面那几颗加粗到 2 格 —— 全部加粗就糊成一条带子
        if s > 0.45:
            _px(im, ox, x, y + 1, SAND_M)
        ## 一格短拖尾(朝来的方向), 表示它在动而不是停着
        _px(im, ox, CX + math.cos(ang - spd * 0.9) * r,
            CY + math.sin(ang - spd * 0.9) * r * SQUASH - hy, SAND_D)


def main():
    im = Image.new("RGBA", (CELL * FRAMES, CELL), CLR)
    for f in range(FRAMES):
        _draw_frame(im, f)
    path = os.path.join(OUT, "ts-sand.png")
    im.save(path)

    # ── 自检: 烘完回量 ──
    px = im.load()
    print("写出 %s  %dx%d  %d 帧, cell %d" % (path, im.width, im.height, FRAMES, CELL))
    cols = set()
    covs = []
    centroid_x = []
    for f in range(FRAMES):
        n = 0
        sx = 0.0
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3] == 0:
                    continue
                n += 1
                sx += x
                cols.add(c)
        covs.append(n)
        centroid_x.append(sx / max(1, n))
        print("  f%d 覆盖 %3d px (%.1f%%), 亮度重心 x=%.2f" % (f, n, 100.0 * n / (CELL * CELL),
                                                             sx / max(1, n)))
    print("  色数 %d" % len(cols))

    ## ★★这张图是来【替换一颗盖住龟的白球】的 ⇒ 第一条自检就是「它盖不住龟」。
    ##   044 的气泡是 12~19%、045 的余烬是 4~6%; 沙比两者都稀。
    mx = max(covs)
    print("  ★最高覆盖 %.1f%%(必须 < 8%% —— 它是来替换白球的, 自己再盖住龟就白换了)"
          % (100.0 * mx / (CELL * CELL)))
    assert mx < 0.08 * CELL * CELL, "沙盖得太密, 又变成一团东西糊在龟身上了"

    ## ★第二条: 它必须【在转】—— 重心逐帧摆动, 不是一张贴纸
    span = max(centroid_x) - min(centroid_x)
    print("  ★八帧亮度重心 x 摆动 %.2f texel(必须 > 0.8 —— 不摆就是贴纸不是在绕转)" % span)
    assert span > 0.8, "重心不动 ⇒ 它没有在绕着转"

    ## ★第三条: 色数 —— 像素风, 别糊
    assert len(cols) <= 8, "色数 %d 太多, 像素风要干净" % len(cols)


if __name__ == "__main__":
    main()
