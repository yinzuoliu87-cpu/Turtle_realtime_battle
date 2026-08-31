# -*- coding: utf-8 -*-
"""axe_palette.py — 小木斧 9 个档位的【调色板替换】(用户 2026-08-31 未决点 ⑪ 选 C)。

★为什么是调色板替换而不是"斧头当独立图层":
  用户要「斧头的颜色要多变，就像不同档位一样」，同时召唤物有 14 个动作。
  · 每档各出一套动画 = 14 × 9 = 126 套, 不现实。
  · 斧头当独立图层靠手部锚点跟随 —— 挥砍时斧头是主体, 锚点跟随极易穿帮。
  ⇒ 只出**一套**素材, 斧刃用一条**专属色阶**, 换档位只换那几个颜色索引。

★这份脚本同时是【门禁】: 直接跑它会核对那条硬约束 ——
  **斧刃的色阶不许和斧柄/身体用色相撞**。撞了就意味着换成金斧时连柄(或龟身)也变金,
  而那种事六期才发现就是全部返工。

用法:
  python tools/axe_palette.py            # 自检: 9 档色阶两两不撞、且都不与柄色相撞
  python tools/axe_palette.py --emit     # 按 9 档生成 assets/sprites/equip/axe-<key>.png
"""
import io, os, sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NL = chr(10)

## 基底素材(PixelLab Pro 64 选 1: 竖柄 + 单侧扇形刃, 刃与柄天然分色)。
BASE = os.path.join(ROOT, 'assets', 'sprites', 'equip', '_axe-base-steel.png')

## ★基底里【斧刃】用到的 9 个颜色, 按明度排序 = 一条 9 级色阶。
##   这是实测出来的, 不是我猜的 —— 见 20260831 方案书三期的回填。
##   ⚠ `(65,43,39)` 看着像灰其实是暖棕(r>g>b), **属于柄不属于刃**, 不在这张表里。
STEEL_RAMP = [(92, 99, 103), (105, 111, 123), (106, 122, 122), (125, 135, 141),
              (132, 142, 152), (135, 149, 154), (152, 163, 171), (171, 184, 191),
              (208, 212, 211)]

## 斧柄/木质部分用到的颜色 —— 换色时**不许碰**, 也不许有任何档位的刃色与它们相撞。
## ★★2026-08-31 追加的结论(做召唤物立绘时量出来的): **按颜色换色靠不住。**
##   召唤物本体(小将)有 **2144 种颜色**(带抗锯齿), 而九档刃色阶共 81 个 RGB ——
##   撞上只是时间问题, 一撞就是"换成金斧连龟身也跟着变金"。
##   ⇒ 正解是**按区域(掩膜)换**: 把"哪些像素属于斧刃"存成一张掩膜, 只重绘掩膜内的像素,
##     本体用什么颜色就完全无关了。下面 `recolor_masked()` 就是这条路;
##     `SHAFT_COLORS` 这条检查**保留**给"装备图标"那张单体素材用(它色数少, 颜色法够用)。
SHAFT_COLORS = {(64, 34, 29), (118, 69, 52), (162, 112, 80), (47, 27, 26), (65, 43, 39)}

## 9 个档位的刃色阶。两端色给出, 中间线性插 —— 保证每档都是 9 级、一一对应(未决点 ⑪ 的第二条约束)。
## 顺序 = AxeEvolution.STAGES + FINALS。
TIERS = [
    ('wood',    '木斧',     (104, 72, 44),  (236, 206, 150)),
    ('stone',   '石斧',     (74, 74, 78),   (186, 186, 190)),
    ('iron',    '铁斧',     (92, 99, 103),  (208, 212, 211)),   # = 基底本身
    ('gold',    '金斧',     (122, 88, 16),  (255, 226, 120)),
    ('diamond', '钻石斧',   (28, 108, 122), (168, 246, 255)),
    ('undead',  '亡灵之斧', (36, 74, 46),   (150, 236, 168)),
    ('seraph',  '炽天使',   (128, 40, 12),  (255, 196, 96)),
    ('holo',    '全息斧',   (36, 60, 130),  (150, 210, 255)),
    ('ember',   '余烬',     (96, 22, 22),   (255, 130, 70)),
]


def ramp(lo, hi, n):
    return [tuple(int(lo[k] + (hi[k] - lo[k]) * i / (n - 1)) for k in range(3)) for i in range(n)]


def tier_ramp(key):
    for k, _name, lo, hi in TIERS:
        if k == key:
            return ramp(lo, hi, len(STEEL_RAMP))
    raise KeyError(key)


def recolor(src_img, key):
    """把基底的刃色阶换成 `key` 这一档的色阶。柄与描边一个像素都不动。"""
    m = dict(zip(sorted(STEEL_RAMP, key=sum), tier_ramp(key)))
    W, H = src_img.size
    px = src_img.load()
    from PIL import Image
    out = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    o = out.load()
    n = 0
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a < 10:
                continue
            c = (r, g, b)
            if c in m:
                o[x, y] = m[c] + (a,)
                n += 1
            else:
                o[x, y] = (r, g, b, a)
    return out, n


def build_mask(img, ramp_colors):
    """哪些像素属于斧刃 —— 返回 {(x,y)} 集合。
    ★只在**单体斧头素材**上建一次(它的刃色就是 STEEL_RAMP 那 9 个), 之后把掩膜存下来,
      贴到召唤物身上时连掩膜一起平移 ⇒ 换档只重绘掩膜内的像素, 与本体颜色无关。"""
    W, H = img.size
    px = img.load()
    want = set(ramp_colors)
    return {(x, y) for y in range(H) for x in range(W)
            if px[x, y][3] >= 10 and px[x, y][:3] in want}


def blade_mask_cc(img, grey_pred=None):
    """从**合成好的立绘**里抠出斧刃 —— 取【最大连通块】, 不是"所有灰像素"。
    ★★为什么必须连通: 2026-08-31 实测, 按"冷灰"选出来的 71 个像素里
      **有 24 个是甲片高光**(x=16/25/39~47/57~60), 只有 47 个在斧刃上。
      我当时还报了一句"掩膜外改动 = 0" —— 那是**恒真式**: 掩膜是我按颜色定义的,
      按定义当然没有东西在它外面。真正该问的是"**斧头以外的地方有没有变**"。
      ⇒ 判据改成量【斧刃连通块的包围盒之外】, 掩膜改成取最大连通块。"""
    W, H = img.size
    px = img.load()
    if grey_pred is None:
        def grey_pred(c):
            r, g, b = c
            return max(r, g, b) >= 70 and abs(r - g) < 18 and abs(g - b) < 18
    grey = {(x, y) for y in range(H) for x in range(W)
            if px[x, y][3] >= 10 and grey_pred(px[x, y][:3])}
    seen, best = set(), set()
    for s0 in grey:
        if s0 in seen:
            continue
        comp, stack = set(), [s0]
        while stack:
            c = stack.pop()
            if c in seen:
                continue
            seen.add(c)
            comp.add(c)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (c[0] + dx, c[1] + dy)
                    if n in grey and n not in seen:
                        stack.append(n)
        if len(comp) > len(best):
            best = comp
    return best


def outside_blade_changed(before, after, mask):
    """换色之后, **斧刃包围盒以外**有多少像素变了。必须是 0。
    ★这条才是真判据 —— "掩膜外有没有变"是恒真的, "斧头外有没有变"才不是。"""
    if not mask:
        return -1
    xs = [p[0] for p in mask]
    ys = [p[1] for p in mask]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    W, H = before.size
    a, b = before.load(), after.load()
    n = 0
    for y in range(H):
        for x in range(W):
            if x0 <= x <= x1 and y0 <= y <= y1:
                continue
            if a[x, y] != b[x, y]:
                n += 1
    return n


def recolor_masked(img, mask, key):
    """按【掩膜】换刃色: 掩膜内的像素按明度映到该档色阶, 掩膜外一个都不碰。
    ★这条不看颜色 ⇒ 本体有多少种颜色、撞不撞都无所谓。"""
    from PIL import Image
    ramp = tier_ramp(key)
    ## ★★映射必须与 `recolor()` **一模一样**(按色阶序位一一对应), 掩膜只负责决定
    ##   "改哪些像素", 不负责"改成什么色"。
    ##   第一版我给掩膜版另写了一套"按明度分桶"的映射 ⇒ 九档结果与颜色版**全部不一致** ——
    ##   掩膜版应当是颜色版的**超集**(多处理了那些被合成/抗锯齿糊掉的像素), 不是另一套算法。
    m = dict(zip(sorted(STEEL_RAMP, key=sum), ramp))
    out = img.copy()
    o = out.load()
    px = img.load()
    n = 0
    for (x, y) in mask:
        r, g, b, a = px[x, y]
        c = (r, g, b)
        if c in m:
            o[x, y] = m[c] + (a,)
        else:
            ## 贴到召唤物身上之后, 边缘会被抗锯齿糊出不在色阶里的颜色 ——
            ## 这些像素按明度就近落到色阶上(颜色版对它们无能为力, 这正是掩膜版的价值)。
            lv = (r * 299 + g * 587 + b * 114) // 1000
            o[x, y] = ramp[min(len(ramp) - 1, lv * len(ramp) // 256)] + (a,)
        n += 1
    return out, n


def main():
    fails = []
    ramps = {k: tier_ramp(k) for k, _n, _l, _h in TIERS}

    ## ① 每档都是 9 级且一一对应
    for k, r in ramps.items():
        if len(r) != len(STEEL_RAMP):
            fails.append('%s 的色阶 %d 级 ≠ 基底的 %d 级' % (k, len(r), len(STEEL_RAMP)))
    print('  [分母] 档位 %d 个 · 每档色阶 %d 级' % (len(TIERS), len(STEEL_RAMP)))

    ## ② ★硬约束: 任何档位的刃色都不许和柄色相撞
    ##    撞了 = 换成那一档时连柄也跟着变色。
    for k, r in ramps.items():
        bad = set(r) & SHAFT_COLORS
        if bad:
            fails.append('%s 的刃色与【柄色】相撞 %d 个: %s' % (k, len(bad), sorted(bad)[:4]))
    print('  [检查] 9 档刃色 ↔ 柄色 相撞: %d 处'
          % sum(len(set(r) & SHAFT_COLORS) for r in ramps.values()))

    ## ③ 档位之间要分得开 —— 两档色阶完全相同 = 玩家看不出进化。
    ##    判据用"最亮那一级的色差", 而不是"有没有交集"(灰阶之间必然有交集)。
    keys = [k for k, _n, _l, _h in TIERS]
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = ramps[keys[i]][-1], ramps[keys[j]][-1]
            if sum(abs(a[t] - b[t]) for t in range(3)) < 40:
                fails.append('%s 与 %s 的最亮级几乎同色(色差 %d < 40)'
                             % (keys[i], keys[j], sum(abs(a[t] - b[t]) for t in range(3))))
    print('  [检查] 档位两两可区分: %d 对' % (len(keys) * (len(keys) - 1) // 2))

    if '--emit' in sys.argv:
        from PIL import Image
        if not os.path.exists(BASE):
            fails.append('基底素材不在: %s' % BASE)
        else:
            src = Image.open(BASE).convert('RGBA')
            for k, name, _l, _h in TIERS:
                img, n = recolor(src, k)
                p = os.path.join(ROOT, 'assets', 'sprites', 'equip', 'axe-%s.png' % k)
                img.save(p)
                print('  生成 %-14s %s (换 %d 像素)' % (k, name, n))

    print('')
    if fails:
        for f in fails:
            print('  [FAIL] ' + f)
        print('FAILED: %d 处' % len(fails))
        return 1
    print('ALL OK — 斧头调色板: 9 档等长 · 不与柄色相撞 · 档位之间分得开')
    return 0


if __name__ == '__main__':
    sys.exit(main())
