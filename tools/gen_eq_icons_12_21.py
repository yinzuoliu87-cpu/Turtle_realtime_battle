# -*- coding: utf-8 -*-
"""gen_eq_icons_12_21.py —— 装备 012~021 十件的 32×32 像素图标。

跑法(每件两步, 与 006~011 同一条流水):
  python tools/gen_eq_icons_12_21.py --out C:/tmp/ic012 --id 12 --px 32
  python tools/pixelize_sheet.py C:/tmp/ic012 --dirs 1 --frames 1 --cell 32 --art-h 32 \
      --palette rust -o assets/sprites/equip/eq012-icon.png

★为什么要重画这十张(2026-09-11 逐张量出来的, 不是印象):

  | id  | 现役图标                | 尺寸    | 色数  | 半透  |
  |-----|------------------------|--------|------|------|
  | 012 | turtle-jelly.png       | 64×64  |   63 |    0 |
  | 013 | urchin-shield.png      | 64×64  |   98 |  139 |
  | 014 | fortress-armor.png     | 64×64  |   59 |   43 |
  | 015 | dungeon-urchin.png     |501×498 |22450 |11940 |
  | 016 | equip-shield-icon.png  |475×475 |11604 | 5081 |
  | 017 | anchor-shield.png      | 64×64  |   44 |    5 |
  | 018 | dungeon-shell.png      |513×487 |38953 | 5496 |
  | 019 | dungeon-anemone.png    |503×496 |46049 | 7799 |
  | 020 | dungeon-dumbbell.png   |712×712 |13202 |30361 |
  | 021 | pearl-guard.png        | 64×64  |   86 |   30 |

  判据沿用 010/011:**色数 ≤ 8 且半透 = 0**, 十件全部不达标;
  其中 5 件是 500~712 像素的 AI 渲染图 —— 正是用户说的「拿图片贴图敷衍我」。
  用户 2026-08-07 定的图标尺寸是 **32×32**。

★形状怎么定的: 每件按**装备文案里的那个东西**画, 不按"好看"画。
  轮廓一律留 1px 暗描边(板子最后一档), 内部 2~3 档明度 —— 32×32 上靠**实心块**活,
  不靠层次(memory: 尺寸小到某个程度加细节只会变噪点)。
"""
import argparse
import math
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

SS = 6   # 超采样倍数

## 每件用哪块板(与 pixelize_sheet.PALETTES 的键一致)
PAL_OF = {
    12: "kelp",    # 海藻: 橄榄绿带状叶片(与 019 的薄荷青 jade 拉开)
    13: "coral",   # 炙烤海胆: 烤过的暖橙红
    14: "steel",   # 深海堡垒甲: 蓝灰重甲
    15: "venom",   # 荆棘海胆: 深紫长刺
    16: "crack",   # 铁壁盾: 更暗的铁色, 与 014 的钢蓝拉开
    17: "steel",   # 不沉之锚: 铁锚
    18: "coral",   # 守护贝壳: 粉白扇贝
    19: "jade",    # 海葵药膏: 绿药膏罐
    20: "crack",   # 哑铃: 黑铁
    21: "steel",   # 守护贝母: 珠母贝 + 白珍珠
}
NAME_OF = {
    12: "海藻", 13: "炙烤海胆", 14: "深海堡垒甲", 15: "荆棘海胆", 16: "铁壁盾",
    17: "不沉之锚", 18: "守护贝壳", 19: "海葵药膏", 20: "哑铃", 21: "守护贝母",
}

## 板索引: 0 最亮 … 末档最暗(描边)。六色板用 0..5, ring/四色板不在这里用。
HI, LT, MD, DK, DP, OL = 0, 1, 2, 3, 4, 5


def _ring_band(u, v, r0, r1):
    d = math.hypot(u, v)
    return r0 <= d <= r1


# ── 012 海藻: 三片带状叶片从底部长上来 ───────────────────
## ★ 2026-09-11 重画: 原来是「龟苓膏块」的圆角方块果冻。用户拍板改名【海藻】
##   (「名称也不好，改为海藻，重做图标」) ⇒ 图标换成海藻本体。
## 形状与战斗里的 `kelp-frond.png` 同一套参数(正弦中线 + 根宽尖窄 + 左上受光),
## 图标与实战演出才是同一件东西 —— 不是两张长得不一样的绿东西。
IC12_BLADES = [
    ## (根部 x, 波长, 振幅, 根部半宽, 相位, 向外张开)
    ## ★第一版 hw=0.19~0.30 且三片都从中间起 ⇒ 渲出来是一个填满格子的绿色 X,
    ##   像仙人掌/字母, 不像海藻。改成: 窄叶 + 三个分开的根 + 向上开扇 ⇒ 叶与叶之间有缝,
    ##   轮廓才读得出来(32×32 上靠**缝**分形, 不靠细节)。
    (-0.30, 1.55, 0.17, 0.165, 0.00, -0.26),
    ( 0.00, 1.95, 0.13, 0.145, 1.20,  0.02),
    ( 0.30, 1.55, 0.17, 0.160, 2.40,  0.26),
]


def ic12(u, v):
    ## 底部的固着器(holdfast): 海藻抓石头的那一团 —— 没它三片叶就是“悬在空中”
    if v > 0.56:
        hf = 0.52 * max(0.0, 1.0 - (v - 0.56) / 0.34) ** 0.5   # max(): v>0.90 时底数转负 ⇒ 幂运算出复数
        if abs(u) <= hf:
            return OL if (abs(u) > hf - 0.10 or v > 0.84) else DK
    t = (0.86 - v) / 1.62                   # 尖停在 v=-0.76 而不是顶到格边(否则尖是平的)                      # v: -1(顶) → +1(底); t: 0=根 1=尖
    if t < 0.0 or t > 1.0:
        return None
    best = None
    for (x0, wl, amp, hw, ph, fan) in IC12_BLADES:
        cx = x0 + amp * math.sin(t * math.tau / wl + ph) + fan * (t ** 1.35)
        w = hw * (1.0 - t) ** 0.30 + 0.018
        sgn = (u - cx) / w
        if abs(sgn) > 1.0:
            continue
        if best is None or abs(sgn) < abs(best):
            best = sgn
    if best is None:
        return None
    if abs(best) > 0.62:
        return OL                               # 描边(32×32 上要粗一点才抠得出轮廓)
    if -0.58 < best < -0.24 and 0.18 < t < 0.84:
        return HI                               # 受光边的细高光(光从左上)
    if best < 0.02:
        return LT
    if best < 0.36:
        return MD
    return DK


# ── 013 炙烤海胆: 短刺球 + 焦痕 ────────────────────────────────────────
def ic13(u, v):
    d = math.hypot(u, v)
    a = math.atan2(v, u)
    ## 12 根短刺: 刺长随角度周期变化
    spike = 0.62 + 0.22 * max(0.0, math.cos(12.0 * a)) ** 3
    if d > spike:
        return None
    if d > 0.60:
        return DK if d > spike - 0.06 else MD    # 刺
    if d > 0.54:
        return OL                                 # 球体描边
    ## 球体: 左上受光
    sh = (u * 0.7 + v * 0.7)
    if sh < -0.34:
        return HI
    if sh < -0.05:
        return LT
    if sh < 0.30:
        return MD
    return DP


# ── 014 深海堡垒甲: 胸甲(梯形 + 双肩 + 中脊) ──────────────────────────
def ic14(u, v):
    ## 主体梯形: 上宽下窄
    halfw = 0.72 - 0.30 * (v + 0.9) / 1.8
    body = (-0.86 <= v <= 0.86) and abs(u) <= halfw
    ## 肩甲: 上方两块
    pauld = (v < -0.42) and (0.40 < abs(u) < 0.92) and (abs(v + 0.66) < 0.26)
    if not (body or pauld):
        return None
    if pauld:
        return OL if (abs(u) > 0.86 or abs(v + 0.66) > 0.21) else DK
    if abs(u) > halfw - 0.09 or v > 0.78 or v < -0.80:
        return OL                       # 描边
    if abs(u) < 0.10:
        return HI if v < 0.30 else LT   # 中脊高光
    ## 甲片: 三条横带
    band = int((v + 0.86) / 0.42)
    return [LT, MD, DK, DP][min(3, band)]


# ── 015 荆棘海胆: 长刺球 ──────────────────────────────────────────────
def ic15(u, v):
    d = math.hypot(u, v)
    a = math.atan2(v, u)
    spike = 0.44 + 0.52 * max(0.0, math.cos(8.0 * a)) ** 2   # 8 根长刺
    if d > spike:
        return None
    if d > 0.44:
        ## 刺: 尖端亮、根部暗
        t = (d - 0.44) / max(1e-6, spike - 0.44)
        return LT if t > 0.62 else (MD if t > 0.28 else DK)
    if d > 0.38:
        return OL
    sh = (u * 0.7 + v * 0.7)
    if sh < -0.22:
        return LT
    if sh < 0.16:
        return MD
    return DP


# ── 016 铁壁盾: 塔盾 ──────────────────────────────────────────────────
## ★重画过一次。第一版用 crack 板的 MD/DP 当盾面, 渲出来是**一张深色卡片**:
##   32×32 上 (40,46,60) 和 (18,21,30) 挨在一起根本分不出层次, 盾尖也被压没了。
##   ⇒ 盾面上移到 LT/MD 档(亮的那两档), 只用 OL 描边; 盾尖加长并收窄。
def ic16(u, v):
    if v < -0.86 or v > 0.94:
        return None
    if v < 0.16:
        halfw = 0.68
    else:
        halfw = 0.68 * (1.0 - ((v - 0.16) / 0.78) ** 1.4)   # 下半收成尖
    if halfw <= 0.0 or abs(u) > halfw:
        return None
    if abs(u) > halfw - 0.11 or v < -0.78 or v > 0.86:
        return OL                        # 描边
    ## 中央圆凸(盾心)
    dc = math.hypot(u, v + 0.16)
    if dc < 0.24:
        if dc > 0.19:
            return OL
        return HI if math.hypot(u + 0.06, v + 0.22) < 0.11 else LT
    ## 四颗铆钉
    for rx, ry in ((-0.42, -0.56), (0.42, -0.56), (-0.34, 0.30), (0.34, 0.30)):
        if math.hypot(u - rx, v - ry) < 0.085:
            return OL if math.hypot(u - rx, v - ry) > 0.055 else HI
    ## 两条横带把盾面分成三段(读成"铁壁"的层)
    if -0.40 < v < -0.30 or 0.16 < v < 0.26:
        return MD
    return LT



# ── 017 不沉之锚 ──────────────────────────────────────────────────────
def ic17(u, v):
    ## 顶环
    if _ring_band(u, v + 0.70, 0.13, 0.24):
        return OL if _ring_band(u, v + 0.70, 0.21, 0.24) else LT
    ## 竖杆
    if abs(u) < 0.11 and -0.58 < v < 0.64:
        return OL if abs(u) > 0.075 else LT
    ## 横梁
    if abs(v + 0.30) < 0.10 and abs(u) < 0.58:
        return OL if abs(v + 0.30) > 0.065 else MD
    ## 底部弯钩: 一段圆环的下半
    d = math.hypot(u, v - 0.28)
    if 0.44 < d < 0.62 and v > 0.22:
        return OL if (d < 0.48 or d > 0.58) else MD
    ## 两侧尖爪
    if 0.44 < abs(u) < 0.72 and 0.44 < v < 0.68 and abs(u) + v * 0.5 < 1.02:
        return DK
    return None


# ── 018 守护贝壳: 扇贝 ────────────────────────────────────────────────
## ★重画过一次。第一版把铰合点放在 v=-0.42 之外, 扇面被画布**切掉下半**,
##   渲出来是半张放射扇 —— 读成"太阳"不是"扇贝"。
##   ⇒ 铰合点收进画布(v=0.62), 扇面往上开, 顶缘做成扇贝特有的**波浪边**, 两侧加"耳"。
def ic18(u, v):
    hy = 0.62                          # 铰合点 y
    vv = v - hy
    d = math.hypot(u * 1.05, vv)
    if vv > 0.0:
        return None                    # 铰合点以下不画
    a = math.atan2(-vv, u * 1.05)      # 0..pi
    ## 顶缘波浪(扇贝的扇形边)
    edge = 0.90 + 0.055 * math.cos(7.0 * a)
    if d > edge:
        ## 两侧的小"耳"
        if 0.30 < abs(u) < 0.72 and -0.10 < vv < 0.02:
            return OL if abs(vv) > 0.06 else MD
        return None
    if d < 0.13:
        return OL                      # 铰合部
    if d > edge - 0.07:
        return OL                      # 外缘描边
    ## 放射肋 7 条
    rib = math.cos(7.0 * a)
    if rib > 0.62:
        return HI if d < 0.58 else LT
    if rib < -0.62:
        return DP
    return MD if d < 0.66 else DK



# ── 019 海葵药膏: 药膏罐 + 海葵触手 ──────────────────────────────────
## ★重画过一次。第一版罐身是个**纯绿方块**、触手三根粗短像叶子。
##   ⇒ 罐身改成有肩的圆罐(带高光条), 触手改细、加末端小球(海葵的触手是带球的)。
def ic19(u, v):
    ## 触手: 三根细须, 末端一个小球
    if v < -0.16:
        for k, (x0, amp, top) in enumerate(((-0.40, 0.13, -0.80), (-0.02, 0.17, -0.92), (0.38, 0.12, -0.74))):
            xc = x0 + amp * math.sin((v + 0.16) * 6.2)
            if v > top:
                if abs(u - xc) < 0.055:
                    return LT if k == 1 else MD
            if math.hypot(u - (x0 + amp * math.sin((top + 0.16) * 6.2)), v - top) < 0.10:
                return HI if k == 1 else LT      # 末端小球
        return None
    ## 罐口(一圈厚沿)
    if -0.16 <= v < -0.02:
        if abs(u) > 0.58:
            return None
        return OL if (abs(u) > 0.50 or v < -0.13) else DK
    ## 罐身: 有肩的圆罐
    if v > 0.86:
        return None
    halfw = 0.52 + 0.14 * math.sin(math.pi * min(1.0, (v + 0.02) / 0.88))
    if abs(u) > halfw:
        return None
    if abs(u) > halfw - 0.09 or v > 0.79:
        return OL
    if -0.36 < u < -0.18:
        return HI                      # 竖高光条
    if u < 0.06:
        return LT
    if u > 0.30:
        return DP
    return MD



# ── 020 哑铃: 横杆 + 两侧配重片 ──────────────────────────────────────
def ic20(u, v):
    ## 横杆
    if abs(v) < 0.13 and abs(u) < 0.86:
        return OL if abs(v) > 0.085 else LT
    ## 两侧各两片配重
    for xc, hw, hh in ((0.52, 0.13, 0.46), (0.78, 0.10, 0.32)):
        for sgn in (-1.0, 1.0):
            if abs(u - sgn * xc) < hw and abs(v) < hh:
                edge = abs(u - sgn * xc) > hw - 0.035 or abs(v) > hh - 0.06
                if edge:
                    return OL
                return MD if u * sgn < xc else DK
    return None


# ── 021 守护贝母: 张开的双壳 + 珍珠 ──────────────────────────────────
## ★重画过**两次**。
##   第一版: 两片壳的椭圆挨太近, 糊成一个圆盘(读成硬币)。
##   第二版: 拉开了缝, 但两片同色同形 + 中间一条黑横带 ⇒ 读成"带缝的圆盘/眼睛"。
##   ⇒ 第三版三样一起改: ① 两片压得更扁并再拉开 ② 上片亮下片暗(分出前后)
##   ③ 珍珠加大并**压在缝上跨过两片**, 让"张开的贝含着珠"这件事成为主体。
def ic21(u, v):
    GAP = 0.30
    ## 珍珠先判(压在最上层, 跨过缝)
    dp_ = math.hypot(u, v)
    if dp_ < 0.34:
        if dp_ > 0.29:
            return OL
        return HI if math.hypot(u + 0.09, v + 0.09) < 0.16 else LT
    for sgn in (-1.0, 1.0):
        vv = (v - sgn * GAP) / 0.44          # 压扁
        if sgn < 0 and vv > 0.0:
            continue
        if sgn > 0 and vv < 0.0:
            continue
        d = math.hypot(u / 1.00, vv)
        if d > 1.0:
            continue
        if d > 0.88:
            return OL                        # 壳缘描边
        a = abs(math.atan2(vv, u))
        rib = math.cos(5.0 * a)              # 放射肋
        if sgn < 0:                          # 上片: 受光, 亮
            if rib > 0.55:
                return HI if d < 0.55 else LT
            return LT if d < 0.70 else MD
        if rib > 0.55:                       # 下片: 背光, 暗
            return MD
        return DK if d < 0.70 else DP
    return None



REND = {12: ic12, 13: ic13, 14: ic14, 15: ic15, 16: ic16,
        17: ic17, 18: ic18, 19: ic19, 20: ic20, 21: ic21}

## 各板的实际色(与 pixelize_sheet.PALETTES 一致) —— 渲大图时直接用最终色,
## 后面 pixelize_sheet 只做 BOX 缩小 + 硬 alpha + 最近邻重索引(不会串档)。
PALETTES = {
    "gold":  [(245,238,205),(250,208,110),(240,185,80),(195,128,40),(150,85,28),(110,58,18)],
    "blood": [(255,214,208),(255,150,140),(232,70,62),(176,34,34),(110,20,24),(62,12,16)],
    "venom": [(240,236,226),(206,200,214),(176,108,232),(128,60,190),(84,34,130),(46,18,74)],
    "coral": [(250,240,230),(255,198,176),(250,138,106),(206,82,74),(146,48,56),(78,28,38)],
    "rust":  [(238,232,220),(206,186,158),(176,116,62),(132,74,40),(88,48,30),(48,28,22)],
    "crack": [(246,248,252),(200,210,228),(96,108,132),(40,46,60),(18,21,30),(8,9,13)],
    "jade":  [(238,250,240),(184,232,200),(110,200,148),(58,150,104),(32,96,72),(16,54,44)],
    "steel": [(246,248,252),(206,216,232),(168,182,204),(118,132,158),(74,86,110),(38,46,64)],
    ## ★kelp 只有 **5** 档(没有 DP 那一档) —— render() 里的 min(idx, len-1) 会把 OL(5) 夹到 4,
    ##   正好落在描边色上。与战斗里的 kelp-frond.png 逐字同色。
    "kelp":  [(214,240,186),(150,200,110),(92,152,76),(48,104,60),(24,58,40)],
}


def render(eid, px_final):
    n = px_final * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    pal = PALETTES[PAL_OF[eid]]
    fn = REND[eid]
    for y in range(n):
        for x in range(n):
            u = (x + 0.5) / n * 2.0 - 1.0
            v = (y + 0.5) / n * 2.0 - 1.0
            idx = fn(u, v)
            if idx is None:
                continue
            ld[x, y] = pal[min(idx, len(pal) - 1)] + (255,)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--id", type=int, required=True, choices=sorted(REND.keys()))
    ap.add_argument("--px", type=int, default=32)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    render(a.id, a.px).save(os.path.join(a.out, "d0_f0.png"))
    print("  %03d %s: 渲了 1 张大图 (%dpx → 最终 %dpx, 板 %s)"
          % (a.id, NAME_OF[a.id], a.px * SS, a.px, PAL_OF[a.id]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
