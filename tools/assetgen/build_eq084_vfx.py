# -*- coding: utf-8 -*-
"""手半剑 084 三张特效素材的**构建脚本**(2026-08-29)。

素材 = PixelLab 生成的原始帧 → 本脚本按【用户参考图的形态指标】加工。
判据在 `tools/vfx_ref_match.py`, 改完这里必须跑那个, ALL OK 才算数。

★为什么留这个脚本而不是只留 PNG:
  素材是**推导出来的**不是画出来的 —— 参数(收尖包络/刀锋层厚/丝的周期占空比/
  量化档数)全在这里。以后要调"再收尖一点""丝再密一点", 改参数重跑, 不用重新生成。
  只留 PNG 的话, 下一个人只能重新描一遍。

★三条加工分别对应用户参考图的哪一点:
  ① 斩击弧  —— 厚身急剧收成针尖(sin² 包络砍外侧) + 最外 12% 提成白热刀锋
  ② 剑气波  —— 整片打散成细丝(周期 7px / 占空 45% ⇒ 55% 是黑缝 ⇒ 通透),
                 每行末端随机缩短 ⇒ 前缘散成须; 亮度/色相/饱和度**量化**成有限色板
                 (不量化会造出 419 个色, 那不是像素画)
  ③ 命中爆点 —— 补橙色火星碎屑

★`random.seed` 固定: 每次跑出同一结果。不播种的话"改好了"可能只是这次运气。

原始帧: C:/tmp/v2/{s,w}0..8.png + burst.png (PixelLab 产出, 未入库)
跑法: python tools/assetgen/build_eq084_vfx.py && python tools/vfx_ref_match.py
"""
import sys, colorsys, math, random
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from PIL import Image

WAVE_STRANDS = 27   # 扇面里画几根丝(34 根时填充 33%, 略超丝丝分开的 30% 上限)
ROW_PERIOD = 3.0    # 丝 + 缝 在 y 方向的周期(px)
ROW_DUTY = 0.58     # 丝的基准疏密(门限, 会被噪声上下推 ±0.26)。0.50 时填充只有 16%, 差一点

def HOT_ROW(y, k):
    """这一行是不是【白热丝】。约每 6 根丝里有 1 根 —— 参考里白热是少数亮丝。"""
    return ((y * 7 + k * 3) % 17) < 3


random.seed(4084)   # ★播种: 每次跑出同一结果, 不然"改好了"可能只是这次运气


def load_frames(prefix, n):
    return [Image.open('C:/tmp/v2/%s%d.png' % (prefix, i)).convert('RGBA') for i in range(n)]


def save_sheet(frames, out):
    w, h = frames[0].size
    sh = Image.new('RGBA', (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sh.paste(f, (i * w, 0))
    sh.save(out)
    return sh.size


# ══ ① 斩击弧: 加白热刀锋 + 收尖 ══
#   参考: 厚身急剧收成针尖 + 白热刀锋与高饱和身强反差
def fix_slash(im, k, n):
    px = im.load(); W, H = im.size
    # 每列的不透明范围 → 求"外缘"(最外那一层就是刀锋)
    for x in range(W):
        ys = [y for y in range(H) if px[x, y][3] > 40]
        if not ys:
            continue
        y0, y1 = ys[0], ys[-1]
        th = y1 - y0 + 1
        # ★两端收尖: 按沿弧长的位置砍掉外侧, 越靠两端砍得越狠
        fu = x / float(W - 1)
        env = math.sin(math.pi * max(0.0, min(1.0, fu)))
        keep = max(1, int(th * (0.25 + 0.75 * env * env)))
        cut = th - keep
        for y in range(y0, y0 + cut // 2):
            r, g, b, a = px[x, y]; px[x, y] = (r, g, b, 0)
        for y in range(y1 - (cut - cut // 2) + 1, y1 + 1):
            r, g, b, a = px[x, y]; px[x, y] = (r, g, b, 0)
        # ★白热刀锋: 收尖之后, 最外 EDGE 层提到近白
        ys2 = [y for y in range(H) if px[x, y][3] > 40]
        if not ys2:
            continue
        e0, e1 = ys2[0], ys2[-1]
        th2 = e1 - e0 + 1
        edge = max(1, int(th2 * 0.12))
        for y in list(range(e0, e0 + edge)) + list(range(e1 - edge + 1, e1 + 1)):
            r, g, b, a = px[x, y]
            if a < 40:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            nr, ng, nb = colorsys.hsv_to_rgb(h, 0.10, min(1.0, max(v, 0.93)))
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return im


# ══ ② 剑气波: 打散成细丝 ══
#   参考: 整片由分开的细丝组成、丝间有黑缝、完全通透、前缘散成须
def fix_wave(im, k, n):
    """★★第三版画法: **沿辐射方向画有厚度的曲线丝**, 不再逐行处理。

    前两版都栽在同一个地方 —— 我按【行】加工:
      · v1 沿 x 每 7px 切一刀 ⇒ 点阵, 实拍像**纱窗**
      · v2 整行画/整行空     ⇒ 1px 直线, 实拍像**扫描线**
    逐行处理**只能**产出水平的、1 像素高的东西, 而参考里的丝是
    **有厚度(2~4px)、从扇心向外辐射、带弧度**的。做法本身错了, 调参数救不了。

    现在: 拿原始帧的不透明区域当**边界模板**, 在里面画 N 根丝 ——
    每根从后缘某点出发, 沿辐射方向走, 带一点弧度, 粗细 2~4px, 长短分层。
    """
    src = im.load()
    W, H = im.size
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    po = out.load()

    # 模板: 哪些像素属于这片扇面(以及那里原本的颜色)
    def inside(x, y):
        return 0 <= x < W and 0 <= y < H and src[x, y][3] > 40

    # 扇心 = 不透明区域的**左中**(波从左边发出、向右推)
    ys = [y for y in range(H) if any(inside(x, y) for x in range(W))]
    if not ys:
        return out
    cy = (ys[0] + ys[-1]) * 0.5
    xs = [x for x in range(W) if any(inside(x, y) for y in range(H))]
    cx = xs[0]

    for si in range(WAVE_STRANDS):
        # 出发点在后缘上下散开
        t = si / float(WAVE_STRANDS - 1)
        y0 = cy + (t - 0.5) * (ys[-1] - ys[0]) * 1.02
        # 每根丝: 粗细 / 长度 / 弧度 都分层(长短悬殊 ⇒ 前缘散成须)
        thick = random.choice([2, 2, 3, 3, 4])
        if random.random() < 0.32:
            L = (xs[-1] - xs[0]) * (0.30 + 0.25 * random.random())   # 短碎须
        else:
            L = (xs[-1] - xs[0]) * (0.72 + 0.28 * random.random())   # 长丝
        x_start = xs[0] + (xs[-1] - xs[0]) * 0.05 * random.random()
        curve = (random.random() - 0.5) * 0.55                      # 弧度
        hot = (si % 6 == k % 6)                                     # 约 1/6 是白热丝
        steps = int(L)
        for i2 in range(steps):
            f = i2 / float(max(1, steps - 1))
            x = int(x_start + f * L)
            # 弧度: 越往外偏得越多(丝是张开的) + 沿程轻微摆动
            y = y0 + curve * (f * f) * (ys[-1] - ys[0]) * 0.45 \
                + math.sin(f * 6.0 + si * 0.9 + k * 0.6) * 1.6
            for dy in range(-(thick // 2), thick - thick // 2):
                xx, yy = x, int(y) + dy
                if not inside(xx, yy):
                    continue
                r, g, b, a = src[xx, yy]
                h, sat, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
                # 丝的芯亮、边暗(厚度方向) + 沿程首尾略暗
                core = 1.0 - abs(dy / max(1.0, thick * 0.5))
                tail = math.sin(math.pi * min(1.0, max(0.0, f))) ** 0.35
                vv = min(1.0, max(0.25, v) * (0.55 + 0.5 * core) * tail)
                vv = round(vv * 4.0) / 4.0                          # ★量化 ⇒ 有限色板
                if hot and core > 0.45:
                    nr, ng, nb = colorsys.hsv_to_rgb(h, 0.10, min(1.0, max(vv, 0.95)))
                else:
                    nr, ng, nb = colorsys.hsv_to_rgb(round(h * 12.0) / 12.0,
                        round(max(sat, 0.55) * 4.0) / 4.0, vv)
                po[xx, yy] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
    return out


# ══ ③ 命中爆点: 补橙色火星 ══
def fix_burst(im):
    px = im.load(); W, H = im.size
    cx, cy = W * 0.5, H * 0.5
    n = 0
    for i in range(46):
        a = random.random() * math.tau
        d = W * (0.30 + 0.22 * random.random())
        bx, by = int(cx + math.cos(a) * d), int(cy + math.sin(a) * d)
        sz = 1 + (i % 3)
        for dx in range(-sz, sz + 1):
            for dy in range(-sz, sz + 1):
                x, y = bx + dx, by + dy
                if not (0 <= x < W and 0 <= y < H):
                    continue
                if dx * dx + dy * dy > sz * sz:
                    continue
                v = 0.75 + 0.25 * random.random()
                nr, ng, nb = colorsys.hsv_to_rgb(0.07, 0.90, v)   # 橙
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), 255)
                n += 1
    return im, n


fs = load_frames('s', 9)
fs = [fix_slash(f.copy(), i, 9) for i, f in enumerate(fs)]
print('  斩击弧 %dx%d' % save_sheet(fs, 'assets/sprites/vfx/eq084-slash.png'))

fw = load_frames('w', 9)
fw = [fix_wave(f, i, 9) for i, f in enumerate(fw)]
print('  剑气波 %dx%d' % save_sheet(fw, 'assets/sprites/vfx/eq084-wave.png'))

fb = Image.open('C:/tmp/v2/burst.png').convert('RGBA')
fb, nsp = fix_burst(fb)
fb.save('assets/sprites/vfx/eq084-burst.png')
print('  命中爆点 补了 %d px 橙色火星' % nsp)
