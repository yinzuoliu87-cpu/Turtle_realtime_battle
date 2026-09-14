# -*- coding: utf-8 -*-
"""059 沙漏【时间停止释放瞬间】的能量场 8 帧 (2026-09-14)。

★★为什么要有它 —— 它是来【替换一颗放大的白球】的:
  原来释放那一下只有 `_ts_shock_ring()`: 一颗 `VfxTex._make_fire_glow_tex()` 从 60 码
  放大到 900 码。那正是本仓点名过的禁区形状(「无含义圆环与白球」)。

★用户 2026-09-14 把重点说死了:
  「9 秒只是剧里面对技能夸张的说法, **真正要看的是喊出时间暂停时整个画面的变化,
    整个能量场是怎么弄的, 这是关键啊**, 画面变灰后就没什么好看的因为是全对话了」
  ⇒ 参考的价值全在**释放那一瞬**, 不在定格之后。

★参考逐帧(docs/studies/20260914g-059时停能量场逐帧.md):
  原片 10fps 抽帧在那一瞬只有 5 帧 —— **密度不够**, 重抽成 30fps 才看清结构。
  量出来三条(以最亮 2% 像素的质心为心, 打 10 圈径向剖面 + 24 扇角向分布):

    ① **是环不是球**: 早期剖面 189/160/127/132/134/**158**/144/121/104/98
       —— 亮核 → 第 2 圈掉到谷底 127 → 第 5 圈**回升到 158**。中间那个谷是关键。
    ② **向外扩张 + 中心掏空**: 晚期剖面 76/63/77/101/115/155/188/**192**/161/153
       —— 峰值从第 0 圈搬到第 7 圈, 核心从 189 掉到 76。
    ③ **角向不均匀**: 24 扇的变异系数 **0.15 → 0.23**, 最亮扇约是最暗扇的 1.9~2.2 倍。
       这一条把它和「无含义闭合圆环」区分开 —— 均匀闭合环的变异系数会接近 0。
       物理读法: 那是羽状放射丝, 不是一个规则的圈。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = 1.775 码。
  cell 64×64 ⇒ 按 114 码摆(64 × 1.775 = 113.6), 游戏里再按整数倍放大到判定尺寸。
"""
import os
import math
import sys

from PIL import Image

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

CELL = 64
FRAMES = 8
CX = CY = CELL / 2.0 - 0.5
RMAX = CELL * 0.5

## 参考量出来的两条径向包络(10 圈, 已归一化到 0~1)。逐帧在两者之间插值 ——
## **表驱动, 不手调系数**(memory [[fb-match-reference-by-measured-curve]])。
EARLY = [189, 160, 127, 132, 134, 158, 144, 121, 104, 98]
LATE = [76, 63, 77, 101, 115, 155, 188, 192, 161, 153]
_m = float(max(max(EARLY), max(LATE)))
EARLY = [v / _m for v in EARLY]
LATE = [v / _m for v in LATE]

## 色阶: 白热核心 → 青绿中段 → 紫色外缘(参考里就是这个走向: 内白、中泛绿、外圈发紫)
C_HOT = (255, 248, 232, 245)
C_MID = (176, 226, 214, 225)
C_COOL = (150, 118, 208, 205)
C_DARK = (86, 60, 126, 165)

## 羽状放射丝: 13 条(质数, 不与 24 扇的统计格对齐 ⇒ 不会量出假的规则性)。
## ★第一版 FIL_GAIN=0.62 + 纯 `cos(a*N)` ⇒ 渲出来是**一朵条纹雏菊**, 三条数字全达标而形状是错的
##   (memory [[fb-my-thresholds-degrade-good-assets]] 同族: 量过了不等于对, 必须渲出来自己看)。
##   ⇒ 三处一起改: ①增益砍到 0.30(丝是**调制**不是主体) ②角度随半径扭转 = **真的螺旋**
##   ③每条丝的振幅用确定性杂色分层, 不是 13 条一模一样的辐条。
FILAMENTS = 13
FIL_GAIN = 0.34
SWIRL = 2.6            # 螺旋量: 角度随归一化半径扭转多少弧度 —— 参考里那圈是【卷】进去的
## ★★全局偏心。**这才是参考那 0.15~0.23 角向变异系数的来源** —— 不是丝。
##   我先以为是丝, 把增益从 0.30 一路试到 0.56 全都量不出来, 才想明白:
##   **一条螺旋在任何半径上都扫过所有扇区**, 角向差异被它自己抹平了。
##   参考里那个场本来就是**偏的**(亮弧压在一侧, 施法者的身体挡掉另一侧) ⇒ 偏心才是那个量的来源。
##   顺带: 偏心也让它不是"一个规则的圆", 正好避开被点名过的禁区形状。
LOPSIDE = 0.44        # 偏心强度(0=完全对称)
LOPSIDE_DIR = 2.3     # 亮弧压在哪个方向(弧度)
CLR = (0, 0, 0, 0)


def _lerp_prof(t):
    return [EARLY[i] + (LATE[i] - EARLY[i]) * t for i in range(10)]


def _radial(prof, rn):
    """rn: 0~1 的归一化半径 ⇒ 在 10 圈包络上线性插值。"""
    x = min(9.999, max(0.0, rn * 10.0))
    i = int(x)
    f = x - i
    b = prof[min(9, i + 1)]
    return prof[i] + (b - prof[i]) * f


def _draw(im, fi):
    ox = fi * CELL
    t = fi / float(FRAMES - 1)
    prof = _lerp_prof(t)
    ## 整体随帧向外推: 早期只占 60% 画布, 末帧铺满 ⇒ 读得出"在扩张"
    scale = 0.60 + 0.40 * t
    for y in range(CELL):
        for x in range(CELL):
            dx = x - CX
            dy = (y - CY) / 0.78          # 俯视角: 圆压成椭圆
            r = math.hypot(dx, dy)
            rn = r / (RMAX * scale)
            if rn > 1.0:
                continue
            v = _radial(prof, rn)
            ## 羽状丝: **螺旋**角向调制 —— 角度随半径扭转(SWIRL), 所以丝是卷的不是直的。
            ## 每条丝的振幅按 `(k*7 mod 13)/12` 确定性分层 ⇒ 13 条粗细不一, 不是规则辐条。
            a = math.atan2(dy, dx) + t * 0.55 + SWIRL * rn
            k = int((a / (2.0 * math.pi) * FILAMENTS) % FILAMENTS)
            amp = 0.45 + 0.55 * (((k * 7) % FILAMENTS) / float(FILAMENTS - 1))
            fil = 0.5 + 0.5 * math.cos(a * FILAMENTS)
            v *= (1.0 - FIL_GAIN) + FIL_GAIN * (fil * amp * 2.0)
            ## 全局偏心: 亮弧压在 LOPSIDE_DIR 一侧(与半径无关 ⇒ 螺旋抹不平它)
            a0 = math.atan2(dy, dx)
            v *= (1.0 - LOPSIDE) + LOPSIDE * (0.5 + 0.5 * math.cos(a0 - LOPSIDE_DIR))
            if v < 0.30:
                continue
            c = C_HOT if v > 0.86 else (C_MID if v > 0.62 else (C_COOL if v > 0.42 else C_DARK))
            im.putpixel((ox + x, y), c)


def main():
    im = Image.new("RGBA", (CELL * FRAMES, CELL), CLR)
    for f in range(FRAMES):
        _draw(im, f)
    path = os.path.join(OUT, "ts-vortex.png")
    im.save(path)

    # ── 自检: 烘完回量, 和参考的三条对账 ──
    px = im.load()
    print("写出 %s  %dx%d  %d 帧, cell %d" % (path, im.width, im.height, FRAMES, CELL))
    cols = set()
    peaks = []
    cvs = []
    for f in range(FRAMES):
        # 径向 10 圈
        acc = [0.0] * 10
        cnt = [0] * 10
        sect = [0.0] * 24
        scnt = [0] * 24
        for y in range(CELL):
            for x in range(CELL):
                c = px[f * CELL + x, y]
                if c[3] == 0:
                    continue
                cols.add(c)
                lum = c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114
                dx = x - CX
                dy = (y - CY) / 0.78
                r = math.hypot(dx, dy)
                k = min(9, int(r / RMAX * 10.0))
                acc[k] += lum
                cnt[k] += 1
                s = int((math.atan2(dy, dx) + math.pi) / (math.pi / 12.0)) % 24
                sect[s] += lum
                scnt[s] += 1
        prof = [acc[i] / cnt[i] if cnt[i] else 0.0 for i in range(10)]
        pk = max(range(10), key=lambda i: prof[i])
        peaks.append(pk)
        sv = [sect[i] / scnt[i] for i in range(24) if scnt[i]]
        mean = sum(sv) / max(1, len(sv))
        var = sum((v - mean) ** 2 for v in sv) / max(1, len(sv))
        cv = (var ** 0.5) / max(1.0, mean)
        cvs.append(cv)
        print("  f%d 峰值在第 %d 圈 · 角向变异系数 %.2f · 剖面 %s"
              % (f, pk, cv, " ".join("%3.0f" % v for v in prof)))
    print("  色数 %d" % len(cols))

    ## ★★参考对账三条(判据落在**量出来的形状**, 不是"我觉得像")
    print("  ★① 峰值圈逐帧外移: %s" % peaks)
    assert peaks[-1] > peaks[0], "峰值没有外移 ⇒ 没有『扩张+中心掏空』, 那就还是一颗球"
    print("  ★② 角向变异系数 %.2f~%.2f (参考 0.15~0.23; 均匀闭合环会接近 0)"
          % (min(cvs), max(cvs)))
    assert min(cvs) > 0.10, "角向太均匀 ⇒ 读成一个规则圆环, 正是被点名过的禁区形状"
    ## ③ 早期必须有"核亮-中暗-外回亮"那个谷。
    ##   ★分母用【本帧实际占据的最大半径】, 不用整张 cell —— f0 只铺 60%,
    ##     拿整张当分母会把包络的后半段切进空白格, 谷就被抹平了(第一版就是这么误红的)。
    f0acc = [0.0] * 10
    f0cnt = [0] * 10
    rocc = 0.0
    for y in range(CELL):
        for x in range(CELL):
            if px[x, y][3] == 0:
                continue
            rocc = max(rocc, math.hypot(x - CX, (y - CY) / 0.78))
    for y in range(CELL):
        for x in range(CELL):
            c = px[x, y]
            if c[3] == 0:
                continue
            lum = c[0] * 0.299 + c[1] * 0.587 + c[2] * 0.114
            r = math.hypot(x - CX, (y - CY) / 0.78)
            k = min(9, int(r / max(1.0, rocc) * 10.0))
            f0acc[k] += lum
            f0cnt[k] += 1
    p0 = [f0acc[i] / f0cnt[i] if f0cnt[i] else 0.0 for i in range(10)]
    dip = min(range(1, 6), key=lambda i: p0[i])
    rise = max(p0[dip + 1:]) if dip < 9 else 0.0
    print("  *3 f0 剖面(占据半径 %.1f texel 为分母) %s -> 谷在第 %d 圈 %.0f, 谷后回升到 %.0f"
          % (rocc, " ".join("%3.0f" % v for v in p0), dip, p0[dip], rise))
    assert rise > p0[dip] + 3.0, "没有『核亮-中暗-外回亮』那个谷 ⇒ 它是实心球不是环"


if __name__ == "__main__":
    main()
