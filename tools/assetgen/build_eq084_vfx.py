# -*- coding: utf-8 -*-
"""还原成 PixelLab 原始帧, 只修真正的毛病。

★★2026-08-29 用户要看素材, 一并排就看出来了:
  **原始帧比我加工后的好** —— 斩击的紫色分层刀光被我洗白切碎, 剑波漂亮的辐射细丝
  被我剁成横向碎条。我的"改进"把好东西改坏了。

★根因: **判据的阈值是我拍的, 而且拍错了** ——
  `fill_max 0.30~0.34`(填充率上限)逼着我去削材质, 而参考里的剑气波本来就是
  **密集**的辐射细丝(丝间只有细黑缝), 填充率本来就高。
  判据错了 ⇒ 我照着它把对的东西改成了错的。这比"判据太松"更危险:
  松只是漏, 错是**主动把好的推向坏的**。

⇒ 现在: 用原始帧, 只修**唯一真正的毛病** —— 剑波前几帧右边那块过曝白板
  (它是一整片纯白, 屏上读成一块方板)。做法是把那片压暗回细丝的亮度区间,
  **不动细丝结构**。
"""
import sys, colorsys, math


sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from PIL import Image


def sheet(frames, out):
    w, h = frames[0].size
    sh = Image.new('RGBA', (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sh.paste(f, (i * w, 0))
    sh.save(out)
    return sh.size


## ══════════════════════════════════════════════════════════════
##  斩击弧: 原帧 + 【绕圆心的角向重映射】各出一张横斩/竖斩
## ══════════════════════════════════════════════════════════════
## 用户 2026-08-29:「这个还分为横斩和竖斩, 你咋做」——
##   旧做法两段共用同一张、只换个 tint。而素材就 80 度张角(实测 90% 质量),
##   判定锥却是 120 / 60 度 ⇒ 横斩**少画 40 度**、竖斩**多画 20 度**。
##   “演出即判定”在这里两边都不成立。
##
## 做法: 绕**圆心**做角向重映射 θ' = mid + (θ - mid) * (目标张角 / 80)。
##   ★逆向采样(逐个目标像素反算回源像素), 所以**不会打洞** ——
##   正向刷会在拉宽 1.5 倍时留下条状空隙。最近邻采样, 保住像素硬边。
## ★★圆心 = 【弧所在圆的圆心】= 挥剑的转轴, 不是"笔触收束的那一点"。
##   用户 2026-08-29 在图上**亲自标了蓝点与蓝色中心角度线**纠正了我:
##     我拟合的是"所有射线的共同出发点"(左下, 笔触的尾巴);
##     他要的是"这道弧绕着转的圆心"(右下, 在弧的**凹侧**)。
##   物理上他对: 剑绕着人转、弧在半径 R 上 ⇒ 人站在圆心。
##   站在笔触尾巴上是错的。
##
##   实测(以他标的蓝点为圆心、按圆周统计取"含 90% 质量的最小弧", 帧 0~5 一致):
##     · 张角   116 度   ← 几乎正好是横斩的判定锥 120 度, 反过来印证了这个模型
##     · 弧中线 -131 度  ← 他手画的是 -118 度, 差 13 度(手画误差内); 取实测值
##     · r95  0.55 帧宽  ← 弧的外缘到圆心的距离, 缩放时让它落在 SLASH_REACH
##
##   ★注意: 这个圆心是**被形状包着**的(周围 353 度都有像素)。
##     所以量张角不能用百分位(在 ±180 处绕回, 我第一版报 353 度), 要找含 90% 质量的最小弧。
SLASH_PIVOT = (0.664, 0.728)
SLASH_MID_DEG = -131.0
SLASH_ART_DEG = 116.0
WIDE_DEG = 120.0                 # = BladeEqVfx.SLASH_DEG_WIDE
## ★★竖斩那张也是 **120 度**, 不是判定锥的 60 度。
##   用户 2026-08-29:「素材要不得, 得搞 120 度的, 120 扇形的一边得贴地」。
##   因为竖斩的扇面是**竖直平面里的挥剑弧**(从举过头顶砍到地面),
##   不是地面上的扭定锥 —— 两者本来就不是同一个东西。
##   横斩那张才是地面锥(120° = SLASH_DEG_WIDE)。
NARROW_DEG = 120.0

## ★用户 2026-08-29:「横斩素材我希望把 D6 移到第一位, D4 放到第二位」。
##   (他看的是桌面那张逐帧图, 标签“帧0…帧8”的中文在他那边没渲出来、成了方框
##    ⇒ 他读成 D0…D8。所以 D6 = 帧6、D4 = 帧4。)
##   其余帧保持相对顺序往后排。
WIDE_ORDER = [6, 4, 0, 1, 2, 3, 5, 7, 8]


def warp_span(im, target_deg):
    """绕圆心把张角从 SLASH_ART_DEG 重映射到 target_deg。"""
    W, H = im.size
    src = im.load()
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dst = out.load()
    gx, gy = SLASH_PIVOT[0] * W, SLASH_PIVOT[1] * H
    mid = math.radians(SLASH_MID_DEG)
    k = SLASH_ART_DEG / float(target_deg)     # 目标角 → 源角 的缩放
    for y in range(H):
        for x in range(W):
            dx, dy = x - gx, y - gy
            r = math.hypot(dx, dy)
            if r < 0.5:
                dst[x, y] = src[int(gx) % W, int(gy) % H]
                continue
            th = math.atan2(dy, dx)
            d = (th - mid + math.pi) % (2 * math.pi) - math.pi     # 归到 [-pi, pi)
            ## ★★目标楞形之外直接透明。
            ##   不加这道闸会**折叠**: 圆心在形状**内部**(周围 353 度都有像素),
            ##   压缩比 k=116/60≈1.93 时, 远离中线的目标角反算回源角会**绕过一整圈**
            ##   又采到有效质量 ⇒ 在不该有东西的地方画出一堆碎块(实拍已见)。
            ##   顺带这道闸也把"张角 = 目标张角"变成硬的。
            if abs(d) > math.radians(target_deg) * 0.5:
                continue
            sth = mid + d * k
            sx = int(round(gx + r * math.cos(sth)))
            sy = int(round(gy + r * math.sin(sth)))
            if 0 <= sx < W and 0 <= sy < H:
                dst[x, y] = src[sx, sy]
    return out


fs = [Image.open('C:/tmp/v2/s%d.png' % i).convert('RGBA') for i in range(9)]
print('斩击弧 还原原始帧 %dx%d' % sheet(fs, 'assets/sprites/vfx/eq084-slash.png'))
## ★用户 2026-08-30:「横扫特效我希望左右再镜像」。
##   镜像直接焊进**文件**, 不在游戏里用 flip_h ——
##   flip_h 会把平面角 A 的特征挪到 180°-A, 上一轮我就因此让扇面背对目标偏了 82°。
##   焊进文件后只需把圆心 x 和弧中线跟着镜像一次, 游戏侧一行不用改。
print('横斩 %.0f度 · 帧序 %s · 已左右镜像  %dx%d'
      % ((WIDE_DEG, WIDE_ORDER)
         + sheet([warp_span(fs[i], WIDE_DEG).transpose(Image.FLIP_LEFT_RIGHT)
                  for i in WIDE_ORDER],
                 'assets/sprites/vfx/eq084-slash-wide.png')))
## ══ 竖斩: 把【直边】转成水平、圆心挪到左下角 ════════════════
##
## 用户 2026-08-29:「120 扇形的一边得贴地」。
##
## ★不需要重画。实测: 这张 120° 图**本来就有一条够直的边** ——
##   +284° 那侧的半径覆盖率 85~90%(从扇尖一直连到外缘),
##   另一条只有 25~75%(毛边)。所以把那条直边转成水平就行。
## ★而且要把旋转**焊进素材文件本身** —— 这样打开图看到的就是
##   "120° 扇形、下缘贴地", 而不是"要在游戏里转一下才贴地"。
## ★只旋转+平移, **不缩放不拉伸** —— 不把好素材改坏。
CHOP_EDGE_DEG = 284.0            # 那条真直的边(图像系度, 绕 SLASH_PIVOT 量出来的)
CHOP_PIVOT = (0.06, 0.94)        # 转完之后圆心放在哪(左下角), 扇面往右上张


def to_ground(im):
    """绕圆心转到【直边水平指右】, 再把圆心挪到左下角。逆向采样+最近邻。"""
    W, H = im.size
    src = im.load()
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dst = out.load()
    ox, oy = SLASH_PIVOT[0] * W, SLASH_PIVOT[1] * H       # 源图里的圆心
    nx, ny = CHOP_PIVOT[0] * W, CHOP_PIVOT[1] * H         # 目标图里的圆心
    th = math.radians(CHOP_EDGE_DEG)                      # 把 +284° 转到 0° ⇒ 逆变换转回 +284°
    c, s2 = math.cos(th), math.sin(th)
    for y in range(H):
        for x in range(W):
            dx, dy = x - nx, y - ny
            sx = int(round(ox + dx * c - dy * s2))
            sy = int(round(oy + dx * s2 + dy * c))
            if 0 <= sx < W and 0 <= sy < H:
                dst[x, y] = src[sx, sy]
    return out


print('竖斩 %.0f度 · 直边转成水平贴地 · 圆心(%.2f,%.2f)  %dx%d'
      % ((NARROW_DEG, CHOP_PIVOT[0], CHOP_PIVOT[1])
         + sheet([to_ground(warp_span(f, NARROW_DEG)) for f in fs],
                 'assets/sprites/vfx/eq084-slash-narrow.png')))

# ── 剑气波: 把整片辐射条【弯成弧】─────────────────────────
#
# ★用户 2026-08-29:「剑气我让你参考的时候, 命名前部分是弯的」。
#   PixelLab 原图的前缘是一堆**近乎竖直的墙**(实测中间只比两端凸出 5px,
#   128px 宽的图里约等于直边) ⇒ 屏上读成"一堆东西的横截面"。
#
# ★★我第一版的做法错了: 逐行把两端**砍掉**一段来凑弧度 ——
#   实拍一看整个变成了**一颗青球**(两端收进去 26% 图宽之后就是圆)。
#   前缘弯不是"把边碎掉", 是**整片条场本身沿着弧走**。
#
# 做法: 把矩形的条场重映射到一个**环形扇区**上 ——
#   源 x = 深度(0=尾 127=前缘) → 目标的半径 r
#   源 y = 沿边的位置            → 目标的角度 θ
#   于是前缘自然成一道**外凸的弧**、尾部收成凹弧、条子真的从一点辐射出来。
#   逆向采样 + 最近邻 ⇒ 不打洞、保住像素硬边。
#
# ★同时撤掉 fix_slab: 我把原图最亮的**白芯**当成"过曝白板"压成了一块
#   灰绿死板(并排一看很明显比原图差)。那是波的亮芯, 不是缺陷。
#   —— 今天第三次同一类错误: 把自己拍的阈值当缺陷, 然后把好东西改坏。

## 前缘凸出多少 px(弦高=图高时)。20px / 128px 宽 ≈ 16% 图宽, 看得出是弧又不至于成球。
## ══ 剑气波: 照用户参考图量出来的三个数改 ═══════════════
##
## ★参考图 2026-08-30 从会话记录里挖回来了(存在 docs/ref/084/)。
##   同一套尺子量参考 vs 我做的, 差距最大的三项:
##
##     项目          参考A   参考B   我的(旧)
##     前缘外凸      17%     25%     **8%**   ← 弧度只有一半
##     亮度前/后比   2.06    1.29    **1.03** ← 我通体一样亮, 没有"亮芯在前"
##     亮段长        76      96      **33**   ← 丝被切得太碎
##
##   色相都是 0.55(青蓝)、长宽比 1.20 vs 1.26 —— 这两项本来就对。
##   ★最致命的是**亮度比 1.03**: 参考是"前缘白热 → 往后过渡到深蓝紫"的**流体**,
##     我做成了通体均匀的一片 ⇒ 读起来是几何图形不是气浪。
##     加上前缘弧只有参考的一半, 就成了用户说的"跟三角形一样"。
WAVE_BULGE = 46.0          # 前缘弦高(px)。128px 宽 ⇒ 约 20%, 向参考的 17~25% 看齐
WAVE_FRONT_V = 1.00        # 前缘明度乘数(白热)
WAVE_BACK_V = 0.52         # 尾部明度乘数 ⇒ 前/后 ≈ 1.9, 向参考的 1.3~2.1 看齐
WAVE_BACK_HUE = 0.70       # 尾部向深蓝紫偏(参考里后缘是紫的)


def shade_flow(im):
    """沿流向做亮度/色相梯度: 前缘白热 → 尾部深蓝紫。

    ★这是参考图与我的版本差距最大的一项(亮度比 2.06/1.29 vs 我的 1.03)。
    ★只改明度与色相, **不动结构** —— 上一次我去削丝结构, 把好素材改坏了。
    """
    px = im.load()
    W, H = im.size
    xs = [x for y in range(H) for x in range(W) if px[x, y][3] > 40]
    if not xs:
        return im
    x0, x1 = min(xs), max(xs)
    span = max(1, x1 - x0)
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a < 8:
                continue
            t = (x - x0) / float(span)          # 0 = 尾部, 1 = 前缘
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            k = WAVE_BACK_V + (WAVE_FRONT_V - WAVE_BACK_V) * (t ** 1.35)
            h2 = WAVE_BACK_HUE + (h - WAVE_BACK_HUE) * (0.35 + 0.65 * t)
            nr, ng, nb = colorsys.hsv_to_rgb(h2, min(1.0, s * (1.0 - 0.20 * t)), min(1.0, v * k))
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return im


def bend_arc(im):
    """把矩形条场弯成环形扇区, 前缘出一道外凸的弧。"""
    W, H = im.size
    src = im.load()
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dst = out.load()
    B = WAVE_BULGE
    R = (H * H / 4.0 + B * B) / (2.0 * B)      # 弦高 B、弦长 H 对应的圆半径
    cx = (W - 1) - R                           # 圆心: 在前缘后面 R 处
    cy = (H - 1) * 0.5
    for y in range(H):
        for x in range(W):
            dx, dy = x - cx, y - cy
            r = math.hypot(dx, dy)
            sx = int(round(r - R + (W - 1)))
            sy = int(round(cy + math.atan2(dy, dx) * R))
            if 0 <= sx < W and 0 <= sy < H:
                dst[x, y] = src[sx, sy]
    return out


## ══ 剑气波: 已换成【重新生成】的素材 ════════════════════
##
## ★★ 2026-08-30: 用户四次点名要重做气波, 我四次退回去改老图(弯弧/加渐变)。
##   现在用 PixelLab 重新生成的 `eq084-wave.png`(9 帧), 不再从 C:/tmp/v2/w*.png 加工。
##
## ★参考图已存 `docs/ref/084/剑气波-参考A/B.png`(从会话记录里挖回来的)。
##   同一套尺子量出来的三项目标 —— 新素材逐帧都达标:
##     前缘外凸  参考 17~25%   新素材 17~23%
##     亮度前/后  参考 1.29~2.06 新素材 1.86~2.02(前三帧)
##     亮段长    参考 15~31% 宽  新素材 17% 宽
##   ★段长必须**归一到包围宽**再比 —— 参考图 494px 宽、候选 128px 宽,
##     按绝对像素比会把全部候选判死(我第一遍就是这么错的)。
