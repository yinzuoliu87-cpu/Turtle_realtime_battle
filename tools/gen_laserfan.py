# -*- coding: utf-8 -*-
"""gen_laserfan.py — 010「激光长刃」的四件素材: 预警扇形 / 斩击 / 竖劈行波条 / 图标。

跑法(两步, 与 006/007/008/009 同一条流水):
  python tools/gen_laserfan.py --out C:/tmp/lf_tel   --mode tel   --dirs 16 --frames 1 --px 224
  python tools/pixelize_sheet.py C:/tmp/lf_tel   --dirs 16 --frames 1 --cell 224 --art-h 224 \
      --palette laser -o assets/sprites/vfx/eq010-tel.png

★★这一版是**照着现状实拍 100 帧逐帧重写的**(见 docs/studies/20260910-010激光长刃现状逐帧.md)。
  旧四张素材(dungeon-laser-blade / laser-slash-anim / laser-cleave-anim / laser-wave)
  **一张都不是像素画**: 21296 / 595 / 2623 / 2762 色, 半透像素 39951 / 7919 / 3148 / 2461。

★旧演出逐帧看出来的六条真毛病(每条都对应下面一处):
  1. **零预兆** —— 帧 0-3 全黑, 帧 4 直接满屏红。009 已经定死「预警范围 == 伤害范围」。
     ⇒ 本版新增 `--mode tel`: 填满整个 120° 扇形的半调网点 + 三条边界亮轮廓。
  2. **像素密度随射程漂** —— `pixel_size = rng×WS/53`, 近战 3★ 0.204、赛博龟 3★ **0.408 m/px**
     (009 月之刃是 0.105)。⇒ 本版 `R_TEX = 108`(旧 53), 一律细一倍。
  3. **后两帧几乎看不见** —— 纹理第 4 帧平均 alpha 只有 **56/255**、最大 **73/255**,
     黑地上读成暗棕爪痕。⇒ 本版消散靠**碎开**(格子开洞), 颜色始终满亮(009 同一条)。
  4. **不是从一边扫到另一边就算数, 还得盖满** —— 009 那一轮的原话:
     「更亮的线根本比预警区小太多啊, 预警是告诉玩家要实际产生伤害的地区啊」。
     ⇒ 斩击每帧在它**扫到的角度上径向盖满 0..R**, 五帧并集铺满整片扇形。
  5. **自由角旋转** —— `spr.rotation = Vector3(0.0, -base_ang, 0.0)` 是连续角,
     贴地精灵被任意角重采样, 像素网格当场碎。⇒ 16 向烤进素材, 运行时 `rotation=0` 只选帧。
  6. **气波画得比判定窄 22%** —— `_on_line` 的 80 是**半宽**(判定 160 码宽), 而贴图 3.0m=125 码。
     ⇒ 本版 `--mode bar`: 条宽由 `LASER_CHOP_HALF_W` 一个常量同时喂绘制与判定。

★画布口径(与 009 不同, 这里说清楚为什么):
  009 的带是**离原点很远的一段环**, 所以它把画布平移到带心去取景(`dir × 650`), 省掉整个圆盘。
  010 的扇形**顶点就在携带者脚下**, 平移省不出东西; 而扇形绕顶点转到任意方向时,
  16 个方向的并集正好是**整张圆盘** ⇒ 顶点放格心、格边 = 2R + 余量, 是唯一不需要按方向记偏移的取景。
  ⇒ 格 224 / `R_TEX = 108` / 顶点在 (112,112)。运行时 `position = 顶点`, **没有任何锚点偏移**。
  表 = `224×16 × 224×5` = **3584 × 1120**(两边都 ≤ 4096, 老 iOS 贴图边长下限)。

★为什么不做到全档 0.10 米/像素: 赛博龟(`atk_range=450`)3★ 半径 900 码,
  要 0.10 得 `R_TEX=216` ⇒ 格 440、表 7040×2200 = 62 MB, 且超 4096。
  本版赛博龟档是 **0.200**(旧 0.408), 常见档(≤450 码) **≤0.100**。这条缺口在方案书里显式记账。

★抖动(dither)必须按【最终像素】算, 不能按超采样像素算 —— 与 009 同一条:
  `pixelize_sheet` 用 BOX(面积平均)缩小, 超采样分辨率上的点画会被平均成一片均匀灰。
  ⇒ 本文件所有点画都用 `x // SS, y // SS` 定位, 让整个 SS×SS 块同开同关。
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

## ── 与 EquipSystem 常量同口径 ──
HALF_DEG = 60.0                 # LASER_ARC_DEG / 2
R_TEX = 108.0                   # 扇形半径在最终纹理里的像素数(必须与 LASER_R_TEX 一致)
CELL = 224                      # 最终格边长; 顶点在格心 ⇒ 半格 112 > R_TEX 108, 留 4px 余量
VIEW = (CELL * 0.5) / R_TEX     # 画布半宽(占 R 的比例) = 1.037
SS = 6                          # 超采样倍数

## 竖劈冲击波: 世界尺寸**固定**(与射程无关) ⇒ 密度恒定。
## ★★这是**一道会动的波**, 不是一排铺好的条(用户 2026-09-10:
##   「我实际的效果就是波在移动, 碰到人造成伤害, 你这样没有遵从装备效果啊」)。
##   上一版我把它做成沿路径铺 N 条、逐条点亮 —— 几何对了(每条正是 160 码判定带),
##   但那不是「波在移动」, 是把效果换个说法重新编码了一遍。演出必须**就是**那个效果。
BAR_HW_TEX = 19.0               # 波前半宽在纹理里的像素数(= LASER_CHOP_HALF_W 码)
BAR_CELL = 48                   # 半格 24 > 1.14×19, 转到任意方向都装得下
BAR_VIEW = (BAR_CELL * 0.5) / BAR_HW_TEX
WAVE_BOW = 0.34                 # 波前外凸(占半宽的比例) —— 弧形, 中间比两端靠前
WAVE_TRAIL = 0.30               # 拖尾长度(占半宽的比例)

## laser 板(与 tools/pixelize_sheet.py 的 PALETTES["laser"] 一致, 索引 0 最亮)
P = [
    (252, 246, 244),   # 0 白热刃芯
    (255, 196, 186),   # 1 热白
    (255, 160, 140),   # 2 热橙红
    (245, 105,  92),   # 3 主激光红
    (196,  52,  52),   # 4 暗红
    (140,  32,  38),   # 5 近黑红
]

## Bayer 4x4 有序抖动矩阵(阈值 0..15)。哈希读成噪点/磨砂, 有序抖动读成网点/半调。
BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def clamp01(x):
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def _frac(x):
    """确定性伪随机 0..1 —— 同一个 x 永远给同一个值(可复现, 不用 random)。"""
    v = math.sin(x * 12.9898) * 43758.5453
    return v - math.floor(v)


## ─────────────────────────────────────────────────────────────
## 斩击 slash —— 一刀从扇形的一端扫到另一端
## ─────────────────────────────────────────────────────────────
def _shade_slash(r, a, half, t, pxq):
    """斩击 = 一刀从 -60° 扫到 +60°, **扫过之处径向盖满 0..R**。

    ★这是 009 那一轮定死的两条(用户三句话逼出来的), 010 原样继承:
      ①「更亮的线你这没有从一边到另一边的感觉啊」⇒ 领先边逐帧单调推进, 不是原地张开。
      ②「更亮的线根本比预警区小太多啊」⇒ 扫过的每一处**径向盖满**, 不许只画一条细的。
    ★消散靠**碎开**不靠变暗: 旧素材第 4 帧平均 alpha 56/255, 黑地上读成暗棕爪痕。
      本版颜色始终满亮, 用格子开洞让它"用完"。
    """
    qx, qy = pxq
    ## 领先边(刀刃当前所在的角度): 从 -half 扫到 +half。
    ## ★0.10 预偏移: 直接从 t=0 起扫的话第 0 帧刀刃正好落在起点、一点面积都没有(009 实测过)。
    sweep = min(1.0, (0.10 + t) / 0.62)
    lead = -half + 2.0 * half * sweep
    if a > lead:
        return None                                  # 还没扫到这里
    d = (lead - a) / (2.0 * half)                    # 距领先边多远(0=刀刃上)
    ## ── 径向: 盖满 0..R, 只用亮度分层, 不留空 ──
    ## 近顶点略暗(那里是刀根)、中段最亮、贴外弧略收 —— 但都不为 0。
    rad = 1.0 - 0.34 * (2.0 * r - 1.0) ** 2
    ## ── 角向: 领先边最亮, 往后衰减到没有 ──
    ## ★不许留亮度地板: 009 第一版留了 0.30 的地板 ⇒ 整片全亮 ⇒ 实拍是一块实心板。
    trail = (1.0 - d) ** 2.0
    v = rad * trail
    blade = d < 0.045                                # 刀刃本身: 领先边前 4.5% 压成最亮
    ## ── 碎开: 后 42% 按【角度 x 径向】二维格子开洞 ──
    ## ★格子要方, 不能拍脑袋: 角向 N_a 份在 r=0.66 处每格弧长 = 0.66*(2*half)/N_a,
    ##   径向 N_r 份每格 = 1.0/N_r。要方 ⇒ N_r ≈ N_a / (0.66*2*half) = N_a/1.382。
    ##   取 N_a = 18 ⇒ N_r = 13。(009 第一版用 19x4 拉成 2 倍高的长条, 实拍碎成横向条纹。)
    if t > 0.58:
        k = (t - 0.58) / 0.42
        ca = math.floor(a * 8.6 + _frac(math.floor(r * 13.0) * 5.3) * 2.0)
        cu = math.floor(r * 13.0)
        if _frac(ca * 1.0 + cu * 7.31) < k * 0.88:
            return None
        if _frac(ca * 2.7 + cu * 3.19) < k * 0.34:
            return None
    th = float(BAYER4[qy & 3][qx & 3]) / 16.0
    if blade:
        return P[0]                                  # 刀刃: 一条硬亮边, 不参与抖动
    ## ★色阶用**有序抖动量化**, 不用固定阈值阶梯 —— 固定阈值实拍是一圈圈同心色带(等高线)。
    lv = v * 5.4 + th
    bi = int(math.floor(lv))
    if bi <= 0:
        return None
    return P[max(0, 5 - bi)]


## ─────────────────────────────────────────────────────────────
## 竖劈冲击波 wave —— **一道会动的弧形波前**, 世界尺寸固定
## ─────────────────────────────────────────────────────────────
def _shade_wave(u, v, t, pxq, nframes):
    """u = 沿推进方向(半宽为 1 的口径), v = 横向 -1..1(= 判定的 ±LASER_CHOP_HALF_W)。

    ★形状: 中间外凸的弧(WAVE_BOW), 领先边烫白, 往后按距离衰减成拖尾 —— 这才读作「波」。
    ★两端**硬切**在 |v| = 1: 那是判定边界本身, 软掉等于告诉玩家"这里大概打得到"。
    ★消散靠**碎开**不靠变暗(旧版 laser-wave 末帧压暗成褐色, 黑地上读成脏影)。
    """
    qx, qy = pxq
    th = float(BAYER4[qy & 3][qx & 3]) / 16.0
    av = abs(v)
    if av > 1.0:
        return None
    uf = WAVE_BOW * (1.0 - v * v)            # 波前那条弧
    d = uf - u                               # >0 = 在波前后面(拖尾侧)
    if d < -0.02:
        return None                          # 波前之前什么都没有
    f = int(round(t * (nframes - 1)))
    trail = WAVE_TRAIL * (0.45 if f == 0 else (1.0 if f < 3 else 0.75))
    if d > trail:
        return None
    k = clamp01(d / max(1e-6, trail))        # 0 = 贴着波前, 1 = 拖尾末端
    if f == 3:                               # 碎裂: 横向开洞, 颜色仍满亮
        cg = math.floor((v + 1.0) * 13.0)
        ce = math.floor(k * 3.0)
        if _frac(cg * 3.77 + ce * 9.13 + 0.31) < 0.58:
            return None
        return P[2] if k < 0.5 else P[3]
    if k < 0.16:
        return P[0]                          # 白热波前(领先那一条)
    lv = (1.0 - k) * 4.6 + th
    bi = int(math.floor(lv))
    if bi <= 0:
        return None
    return P[max(0, 5 - bi)]


## ─────────────────────────────────────────────────────────────
## 竖劈落刃 chop —— 携带者头上落下的那一刀(公告板, 单方向)
## ─────────────────────────────────────────────────────────────
def _shade_chop(x01, y01, t, pxq, nframes):
    """旧版这一段用户认可(斜刃下落 → 劈地红爆), 所以形状原样保留, 只换成像素画。
    ★但落点从**目标身上**改到**携带者身上** —— 旧版把刀画在目标头上、伤害却靠波飞 0.30 秒
      才到, 玩家看到的「劈」和真正掉血的「波」不是同一件事。
      竖劈是携带者劈出来的, 波才是打人的那一下。
    """
    qx, qy = pxq
    th = float(BAYER4[qy & 3][qx & 3]) / 16.0
    f = int(round(t * (nframes - 1)))
    if f <= 2:
        ## 刃: 从右上斜着压下来, 每帧更低。
        ## ★★两个数是**算出来的不是拍的**(第一版两条都错, 渲出来一眼就看见):
        ##   ① 刀尖的终点必须**正好落在劈地红爆的中心**(0.42, 0.80) —— 第一版刀尖停在 y=0.52,
        ##      而红爆画在 y=0.80, 刀根本没碰到地就炸了。
        ##   ② 起始帧整把刀要在格子里 —— 第一版刀根伸到 y=-0.36, 第 0 帧被切掉大半。
        ##   ⇒ 刀尖 (0.62,0.34) → (0.42,0.80); 刃长 0.34 ⇒ 起始帧刀根 (0.754,0.028) 仍在格内。
        drop = [0.00, 0.50, 1.00][f]
        bx, by = 0.62 - drop * 0.20, 0.34 + drop * 0.46
        dx, dy = x01 - bx, y01 - by
        along = (dx * -0.3987 + dy * 0.9170)         # 沿下落方向(左下); <0 = 刀尖之后的刃身
        perp = abs(-dx * 0.9170 + dy * -0.3987)
        blen = 0.34
        if -blen < along < 0.04:
            s01 = (-along) / blen
            w = 0.046 * (1.0 - s01) ** 0.5
            if perp < w:
                return P[0] if perp < w * 0.40 else (P[2] if perp < w * 0.75 else P[3])
            if perp < w * 1.8 and (1.0 - (perp - w) / max(1e-6, w * 0.8)) > 0.34 + th * 0.6:
                return P[4]
        return None
    ## 后两帧: 劈地红爆 —— 地面一道横向裂光, 中间白热
    cy = 0.80
    dy2 = abs(y01 - cy)
    halfw = [0.0, 0.0, 0.0, 0.40, 0.52][f]
    dxc = abs(x01 - 0.42)   # 与刀尖终点同一个 x
    if dxc > halfw:
        return None
    prof = 1.0 - (dxc / halfw) ** 2
    thick = 0.055 * prof
    if dy2 > thick:
        return None
    if f == 4:                                # 末帧碎开, 不压暗
        if _frac(math.floor(x01 * 34.0) * 5.7 + math.floor(y01 * 34.0) * 2.3) < 0.55:
            return None
    e = 1.0 - dy2 / max(1e-6, thick)
    lv = e * prof * 4.8 + th
    bi = int(math.floor(lv))
    if bi <= 0:
        return None
    return P[max(0, 5 - bi)]


def render_cell(mode, d_ang, f, nframes, px):
    """渲一格(某方向某帧)的大图, 返回 RGBA Image。"""
    n = px * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    t = f / float(max(1, nframes - 1))
    ca, sa = math.cos(d_ang), math.sin(d_ang)
    if mode == "wave":
        for y in range(n):
            # 画布 y 向下, 场地 y 向下(与 ARENA 同口径) ⇒ 不翻转
            fy = (y + 0.5) / n * 2.0 * BAR_VIEW - BAR_VIEW
            qy = y // SS
            for x in range(n):
                fx = (x + 0.5) / n * 2.0 * BAR_VIEW - BAR_VIEW
                u = fx * ca + fy * sa                # 沿推进方向
                v = -fx * sa + fy * ca               # 横向(= 判定的 ±HALF_W)
                col = _shade_wave(u, v, t, (x // SS, qy), nframes)
                if col is not None:
                    ld[x, y] = col + (255,)
        return img
    if mode == "chop":
        for y in range(n):
            qy = y // SS
            for x in range(n):
                col = _shade_chop((x + 0.5) / n, (y + 0.5) / n, t, (x // SS, qy), nframes)
                if col is not None:
                    ld[x, y] = col + (255,)
        return img
    half = math.radians(HALF_DEG)
    shade = _shade_slash
    for y in range(n):
        fy = (y + 0.5) / n * 2.0 * VIEW - VIEW
        qy = y // SS
        for x in range(n):
            fx = (x + 0.5) / n * 2.0 * VIEW - VIEW
            r = math.hypot(fx, fy)
            ## ★严格卡在扇形内: **画出来的范围必须 == 打得到的范围**(009 那条老账)。
            if r > 1.0:
                continue
            a = math.atan2(fy, fx) - d_ang
            while a > math.pi:
                a -= 2.0 * math.pi
            while a < -math.pi:
                a += 2.0 * math.pi
            if abs(a) > half:
                continue
            col = shade(r, a, half, t, (x // SS, qy))
            if col is not None:
                ld[x, y] = col + (255,)
    return img


## ─────────────────────────────────────────────────────────────
## 图标 —— 32×32 红色能量长刃(旧图标是 600×600 / 21296 色的 AI 渲染图)
## ─────────────────────────────────────────────────────────────
def render_icon(px):
    """32x32 激光长刃图标。用户 2026-09-09 点名「换」。

    ★与 009 弯刀的区别是**直**: 010 叫「长刃」, 刃身是一条直的能量束。
      性格全靠轮廓给 —— 32x32 上加细节只会变噪点(memory: 尺寸小到某个程度加细节只会变噪点)。
      只保留四段: 白热刃芯 / 红热刃身 / 护手 / 柄。
    ★刃芯必须是**一条**(1~2 px), 不是整片白 —— 激光的读法就是"细白芯 + 红晕",
      整片白会读成一块金属板(009 图标第一版踩过"压白芯成灰板")。
    """
    n = px * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ld = img.load()
    ## 刃: 从左下 (0.22,0.80) 到右上 (0.86,0.15) 的一条直束
    A = (0.22, 0.80)
    B = (0.86, 0.15)
    dx, dy = B[0] - A[0], B[1] - A[1]
    blen = math.hypot(dx, dy)
    ux, uy = dx / blen, dy / blen
    for y in range(n):
        v = (y + 0.5) / n
        qy = y // SS
        for x in range(n):
            u = (x + 0.5) / n
            rx, ry = u - A[0], v - A[1]
            s = (rx * ux + ry * uy) / blen           # 0=柄端 1=刃尖
            perp = abs(-rx * uy + ry * ux)
            th = float(BAYER4[(x // SS) & 3][qy & 3]) / 16.0
            col = None
            ## 刃身: 根部宽 → 刃尖收成 0(不收尖会留一个圆帽, 009 图标踩过)
            ## ★★第一版 w=0.052、core=w*0.30 ⇒ 32px 上刃芯半宽只有 0.5px,
            ##    斜着走的一条线上**时有时无**, 渲出来是一条断断续续的白点; 而 glow 铺到 2.1w
            ##    又把两侧糊成毛边 ⇒ 整体读成"一根毛毛的红棍"不是"一束激光"。
            ##    ⇒ 刃加宽到 0.068、刃芯占 0.42(≥1px 连续), 红晕收到 1.5w 并且**只在外侧半格**。
            w = 0.068 * (1.0 - s) ** 0.55
            if 0.0 <= s <= 1.0:
                if s > 0.185 and perp < w:
                    col = P[0] if perp < w * 0.42 else (P[2] if perp < w * 0.74 else P[3])
                ## ★★护手/柄一律用**矩形**判据, 不用 (s, perp) 的菱形带。
                ##    第一版写成 `0.11 < s <= 0.20 and perp < 0.132` 再按 perp 分三档,
                ##    在 32px 上渲出来是一摊散点(逐像素打表看过: 22~26 行全是零散的 4/5),
                ##    读成"刀根炸了一朵火花"而不是"护手"。护手是**硬件**, 要有直边。
                ## 护手: 垂直刃身的一段短横。
                ## ★★再窄一点就活不下来: 斜 45° 的细长矩形经过 SS=6 超采样 + BOX 缩小 + 重索引,
                ##    **1px 级的多色分层会被打成散点**(逐像素打表看过两版)。
                ##    ⇒ 只留【一个实心色 + 一圈描边】, 且厚度给到 2px 以上。像素画里
                ##    小尺寸靠**实心块**活, 不靠层次(memory: 尺寸小到某个程度加细节只会变噪点)。
                elif 0.105 < s <= 0.178 and perp < 0.150:
                    col = P[5] if perp > 0.118 else P[4]
                ## 柄
                elif 0.032 < s <= 0.105 and perp < 0.050:
                    col = P[5]
                ## 柄头
                elif s <= 0.032 and perp < 0.078:
                    col = P[4]
            ## 刃身外的红晕: 一格宽的抖动halo, 让它读成"发光"而不是"贴纸"
            if col is None and 0.22 < s <= 1.0 and perp < w * 1.5:
                glow = 1.0 - (perp - w) / max(1e-6, w * 0.5)
                if glow > 0.34 + th * 0.62:
                    col = P[4]
            if col is not None:
                ld[x, y] = col + (255,)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="大图输出目录(d{i}_f{j}.png)")
    ap.add_argument("--mode", choices=["slash", "wave", "chop", "icon"], required=True)
    ap.add_argument("--dirs", type=int, default=16)
    ap.add_argument("--frames", type=int, default=1)
    ap.add_argument("--px", type=int, default=CELL,
                    help="**最终**格边长; 实际渲 px*SS 再交给 pixelize_sheet")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    n = 0
    if a.mode == "icon":
        render_icon(a.px).save(os.path.join(a.out, "d0_f0.png"))
        n = 1
        print("  icon: 渲了 1 张大图 (%dpx)" % (a.px * SS))
    else:
        for d in range(a.dirs):
            d_ang = math.tau * d / float(a.dirs)
            for f in range(a.frames):
                render_cell(a.mode, d_ang, f, a.frames, a.px).save(
                    os.path.join(a.out, "d%d_f%d.png" % (d, f)))
                n += 1
        print("  %s: 渲了 %d 张大图 (%d 向 x %d 帧, 每张 %dpx)"
              % (a.mode, n, a.dirs, a.frames, a.px * SS))
    if n == 0:
        print("[FAIL] 一张都没渲 —— 空目录不是通过")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
