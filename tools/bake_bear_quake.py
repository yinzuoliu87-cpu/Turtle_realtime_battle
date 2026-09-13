# -*- coding: utf-8 -*-
"""034 玩偶小熊·大熊【冲击波】的两张新素材 (2026-09-13)。

用户 2026-09-13:「这个大熊冲击波的特效不好, 你得重做」。
实拍读出来的毛病(逐帧看过 16 帧, 见 docs/studies/20260913r-034大熊冲击波重做.md):
  ① **根本没有波** —— 全程只有 `gold-chunk` 一簇簇随机冒, 横向散布 ±26/±55 码,
     连一条波前都拼不出来, 读成"地上插了一排蜡烛/金条"。
  ② 脚下挂着一个**又细又大的黄色椭圆环**(`_skill_ring`)几秒不散 = 无含义圆环(禁区)。
  ③ 金块**一出生就淡出**, 中段在黑场里读成深褐色柱子(淡出病)。
  ④ 前摇那颗 `VfxTex._make_fire_glow_tex()` 程序光球 —— 同样是禁区那一类。

⇒ 重做成【真的有一条波前】: 一排直立的土石浪(billboard, 不旋转) 沿行进方向推,
  波前自己翻涌(8 帧循环), 碎石只在**波前那一线**上冒(不再全场散点)。

★像素风三条硬约束: 整数倍缩放 / 不许自由旋转 / NEAREST。
  方向**不靠旋转**解决 —— 照 043 浪墙的老办法: 一排直立 billboard 沿 perp 铺开、
  沿 dir 平移, 朝向只用 `flip_h`。裂缝预兆做成**径向对称**的, 对称就不需要旋转。

★尺子: 1 texel = 0.0426 m = 1 屏幕像素(zoom 1.0) = **1.775 码**。
  ⇒ 浪头 44 texel 宽 = 78 码; 30 texel 高 = 53 码(约 2/3 个龟高)。
    伤害判定半宽 85 码 ⇒ 5 片浪头每 40 码铺一片, 正好盖满 ±80 码。
"""
import os, math
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "sprites", "vfx")

# 土石色阶(暗→亮) + 暖金鳞边。金色沿用大熊自己那套暖金(金爪痕/金块同族),
# 但**形状**是新的 —— 铁律管的是"别拿别的图顶替", 不是"不许同色系"。
D = (38, 24, 16, 255)      # 轮廓/根部暗土
M = (96, 62, 34, 255)      # 土体
L = (150, 104, 56, 255)    # 受光面
G = (236, 176, 82, 255)    # 暖金鳞边
W = (255, 232, 168, 255)   # 浪尖高光
DUST = (170, 146, 118, 255)
CLR = (0, 0, 0, 0)



def _px(im, x, y, c):
    if 0 <= x < im.width and 0 <= y < im.height:
        im.putpixel((x, y), c)


# ── 破土隆起(一次性动画) ────────────────────────────────────────────────────
# ★★用户 2026-09-13 第二轮:「不如原版啊, 不是一个墙飞过去啊, 是一段段地突起啊动画」。
#   ⇒ 原版的**概念是对的**(沿途地面一段一段破土隆起), 坏的只是执行:
#     随机散点拼不出线 / 金块淡出病 / 无含义圆环。我上一版换成"一整面墙平移"是把
#     概念也换掉了 —— 概念不许动, 只修执行。
#   ⇒ 这张表是【一次性的破土动画】: 鼓起 → 顶到最高 → 崩解 → 剩一堆碎土。
#     由调用方**沿行进方向一段一段地点**出来, 方向感来自"点的顺序", 不来自平移。
# ★左右对称 ⇒ 不需要 flip、更不需要旋转(像素风不许自由旋转)。
# 逐帧高度包络(相对峰高): 0 起、3 到顶、之后崩塌。不手调 —— 写成显式表, 门禁也读它。
ERUPT_ENV = [0.10, 0.45, 0.82, 1.00, 0.92, 0.62, 0.30, 0.12]
CW, CH, CN = 44, 42, 8     # 破土: 宽 × 高 × 帧数
                           # ★实拍第一版 36×34 只有 0.44 个龟高, 一排里读成「一堆小山包」;
                           #   加到 44×42(78×75 码 ≈ 0.9 个龟高)才像「地被顶穿了」。
GROUND = CH - 1


## ★形状试了三版, 每版都并排渲出来看过:
##   v1 圆顶 ⇒ 读成一只面包; v2 四块竖直土板 ⇒ 读成城市天际线;
##   v3(现) **尖刺**: 中间一根主刺 + 两侧各一根矮刺, 轮廓带锯齿 —— 这才是"地面被顶穿"。
##   教训同 memory[[fb-my-thresholds-degrade-good-assets]]: 形状不对就换形状, 别在错的形状上调系数。
LOBES = [(0.00, 1.00, 1.35), (-0.58, 0.46, 1.15), (0.62, 0.40, 1.10)]   # (中心t, 相对高, 尖锐度)


def _mound_top(x, h):
    """该列土刺的顶 y(越小越高); CH 表示这一列没有土。"""
    t = (x - (CW - 1) / 2.0) / ((CW - 1) / 2.0)      # -1..1
    hh = 0.0
    for c, k, sharp in LOBES:
        half = 0.52 if c == 0.0 else 0.30            # 主刺宽, 侧刺窄
        d = abs(t - c) / half
        if d < 1.0:
            hh = max(hh, h * k * (1.0 - d) ** sharp)
    ## 锯齿: 沿 x 的确定性抖动(±1.6 texel) —— 刺的边缘要毛糙, 光滑=土包
    hh += math.sin(x * 1.9) * 1.1 + math.sin(x * 0.7 + 1.3) * 0.6
    if hh < 0.8:
        return CH
    return int(round(GROUND - hh))


def _slab_seam(_x):
    return False


def bake_crest():
    im = Image.new("RGBA", (CW * CN, CH), CLR)
    peak = CH - 6
    for f in range(CN):
        ox = f * CW
        h = peak * ERUPT_ENV[f]
        if f == 0:                                   # 第 0 帧 = 地面先裂开(不是一块亮板)
            for x in range(4, CW - 4):
                _px(im, ox + x, GROUND, D)
                if (x + 1) % 3 == 0:
                    _px(im, ox + x, GROUND - 1, G if (x + 2) % 6 else W)
            continue
        broken = f >= 4                              # 4 帧起开始崩(顶上掏洞)
        top = [_mound_top(x, h) for x in range(CW)]
        for x in range(CW):
            if top[x] >= CH:
                continue
            for y in range(top[x], CH):
                d = y - top[x]
                if broken and d <= 1 and (x * 3 + f * 5) % 5 == 0:
                    continue                         # 崩解: 顶层掏出缺口(不是整块沉下去)
                if d == 0:
                    c = W if (x + f) % 4 else G
                elif d <= 2:
                    c = G if not broken else L
                elif y >= CH - 2:
                    c = D
                elif (x * 5 + y * 3 + f) % 7 == 0:
                    c = L                            # 土的斑点质感
                else:
                    c = M
                _px(im, ox + x, y, c)
            _px(im, ox + x, top[x] - 1, D)           # 暗描边: 黑场里才有形
            if _slab_seam(x):                        # 板缝: 一道暗线, 四块板才分得开
                for y2 in range(top[x], CH - 1):
                    _px(im, ox + x, y2, D)
        # 地面被顶开的裂口: 丘脚两侧各一小撮翻起来的土
        for sgn in (-1, 1):
            for k in range(3):
                bx = (CW - 1) // 2 + sgn * (int((CW - 1) / 2.0 * 0.72) + k)
                _px(im, ox + bx, GROUND, D)
                if k < 2 and f >= 1:
                    _px(im, ox + bx, GROUND - 1, M)
        # 碎石: 从丘顶往【两侧上方】崩, 逐帧越飞越远越低(抛物线)
        n_rock = 4 if f >= 1 else 0
        for k in range(n_rock):
            sgn = 1 if k % 2 else -1
            age = min(1.0, (f - 1) / 5.0)
            rx = (CW - 1) // 2 + sgn * int(round(3 + k * 1.5 + age * 11))
            ry = int(round(GROUND - h - 3 - math.sin(age * math.pi) * 9 + k))
            w_ = 3 if k % 2 else 2
            for dx in range(w_):
                for dy in range(2):
                    _px(im, ox + rx + dx, ry + dy, L if dy == 0 else M)
            for dx in range(-1, w_ + 1):
                _px(im, ox + rx + dx, ry - 1, D)
                _px(im, ox + rx + dx, ry + 2, D)
        # 浮尘: 崩解之后才有(不是一出生就糊一层)
        if f >= 3:
            for k in range(8):
                dx = 3 + (k * 5 + f * 3) % (CW - 6)
                dy = GROUND - 2 - (k % 5) - int(h * 0.3)
                if 0 <= dy < CH and im.getpixel((ox + dx, dy))[3] == 0:
                    _px(im, ox + dx, dy, DUST)
    p = os.path.join(OUT, "bear-quake-erupt.png")
    im.save(p)
    return p, im


# ── 预兆: 破土小喷 ──────────────────────────────────────────────────────────
# ★为什么不是"地上的裂缝": 裂缝是**有方向的形状**, 贴到任意方向的地面上就得旋转,
#   而像素风不许自由旋转。我先烘了一版径向对称的裂缝想绕开这条 —— 并排渲出来是
#   一只蝙蝠/一团糊(压扁 0.58 之后好几条臂落到同一行)。
# ⇒ 换成**直立的破土小喷**: billboard 本来就永远正对镜头, 一点旋转都不需要,
#   方向感改由【一节一节往外摆的位置与顺序】给 —— 摆到哪、摆几节, 就是波会走多远。
#   这是"预兆自带信息量"那条: 喷的位置数量 = 波的路径与射程。
TW, TH, TN = 14, 16, 5     # 预兆: 宽 × 高 × 帧数


def bake_crack():
    im = Image.new("RGBA", (TW * TN, TH), CLR)
    cx = TW // 2
    for f in range(TN):
        ox = f * TW
        k = f / float(TN - 1)
        # 地面那一撮被顶起来的土(底部两行, 逐帧向两侧摊开)
        half = 1 + int(round(k * 4))
        for x in range(cx - half, cx + half + 1):
            _px(im, ox + x, TH - 1, D)
            if abs(x - cx) <= half - 1:
                _px(im, ox + x, TH - 2, M if abs(x - cx) else L)
        # 往上喷的尘柱: 高度随帧涨, 越往上越细越暗(不做"一出生就淡出")
        col = int(round(2 + k * 8))
        for i in range(col):
            y = TH - 3 - i
            w_ = max(0, 2 - i // 4)
            for dx in range(-w_, w_ + 1):
                if (i * 3 + dx + f) % (2 if i >= 5 else 5) == 0:
                    continue                      # 挖空 ⇒ 尘是松散的不是一根柱子(越高挖得越狠)
                _px(im, ox + cx + dx, y, L if i < 2 else (M if i < 6 else DUST))
        # 崩出去的小石子: 两颗, 往左右上方飞
        for sgn in (-1, 1):
            sx = cx + sgn * (2 + int(round(k * 4)))
            sy = TH - 5 - int(round(math.sin(k * math.pi) * 6))
            _px(im, ox + sx, sy, L)
            _px(im, ox + sx + sgn, sy, M)
            _px(im, ox + sx, sy - 1, D)
        if f >= 2:                                # 根部透出暖光 = 下面正在受力("因")
            _px(im, ox + cx, TH - 2, G)
            _px(im, ox + cx, TH - 3, G if f < 4 else W)
    p = os.path.join(OUT, "bear-quake-tell.png")
    im.save(p)
    return p, im


def report(name, im, nf):
    w = im.width // nf
    print("  %-26s %dx%d = %d 帧 × %dx%d" % (name, im.width, im.height, nf, w, im.height))
    for f in range(nf):
        cell = im.crop((f * w, 0, (f + 1) * w, im.height))
        px = list(cell.getdata())
        op = [p for p in px if p[3] > 0]
        br = [p for p in op if (p[0] + p[1] + p[2]) / 3.0 >= 110]
        print("    f%d 不透明 %4d (%.0f%%)  亮像素/不透明 = %.2f"
              % (f, len(op), 100.0 * len(op) / len(px), (len(br) / len(op)) if op else 0.0))


if __name__ == "__main__":
    p1, i1 = bake_crest(); report("bear-quake-erupt.png", i1, CN)
    p2, i2 = bake_crack(); report("bear-quake-tell.png", i2, TN)
    print("→", p1)
    print("→", p2)
