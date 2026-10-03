# -*- coding: utf-8 -*-
"""主题素材【统一调色】—— 让一组素材看起来是一套，而不是各长各的。

★为什么需要它（2026-10-03，用户：「4版我必须要看到咩咩启示录的质量」）
  咩咩的素材是手绘的，整套共享**一个主色系 + 一种墨线**；而 PixelLab 逐件生成的东西
  各长各的。实测我们第一批 17 件：
      dusk  的色相是 11/19/20/29/33°（暖），**却混着 240° 和 287°**
      shoal 88 / 134 / 340° 三头跑
      storm 119 / 258° 对半劈
      明度中位从 0.12 到 0.79
  ⇒ 「不像一套」不是玄学，是**色相离散 + 明度跨度**两个可量的数。

★做法（照参考的规律，不是我拍的）
  咩咩每张图是「**一个主色系统治全图 + 强饱和只给光源**」(raw_18 BOSS 场最典型：
  整张红橙粉，强饱和只有烛火)。所以：
    ① 把每个像素的色相**往主题色相拉** `pull` 比例 —— 不是全部压成同一个色，留出层次
    ② **放过强饱和的亮像素**（烛火/灯芯/花心这类“光”与点缀），它们是参考里唯一允许跳出色系的东西
    ③ 把明度**压进主题的区间**，整组的明暗跨度才一致

★不做什么
  · 不改形状、不改 alpha —— 这是调色不是重绘
  · 不碰 `assets/sprites/map/` 下的既有素材（只处理 `themes/` 这一层）
  · 原图先存 `.orig.png`，可重跑、可回退（**不靠 git checkout**，见 memory）

用法:
    python tools/theme_palette_harmonize.py            # 全部主题
    python tools/theme_palette_harmonize.py dusk       # 只处理一个
"""
import colorsys
import glob
import os
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # ★本机控制台是 GBK, 中文箭头会炸

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "assets", "sprites", "map", "themes")

# 主题 → (主色相°, 拉拢比例, 明度下限, 明度上限)
# ★色相取自 `scripts/gamedata/arena_theme.gd` 里那一版的地面/地平线色系；
#   明度区间照参考：咩咩单张图的物件明度中位集中在 0.2~0.6，跨度不超过一档。
SPEC = {
    "dusk":  (58.0, 0.55, 0.12, 0.55),   # 暗林: 黄橄榄(Darkwood 实测)
    "reef":  (228.0, 0.55, 0.12, 0.52),
    "shoal": (48.0, 0.58, 0.28, 0.78),
    "storm": (212.0, 0.60, 0.14, 0.56),
}

# 放过“光”：强饱和 + 够亮的像素保留原色相（烛火/灯芯/花心）
ACCENT_S = 0.55
ACCENT_L = 0.52

## ★★★【剪影不进这套处理】2026-10-03 实拍照出来的:
##   前景框边那条草带被这里的明度重映射 `ll = lo + (hi-lo)*ll` **把近黑抬到了下限 0.16**,
##   再被色相拉到 334°(红) ⇒ 画面下沿出现一条**亮红色的带**, 比原来难看得多。
##   剪影的定义就是「接近黑 + 中性」—— 它本来就不该被"拉进主色系"。
##   ⇒ 文件名带这些词的一律跳过; 它们的颜色由引擎侧的 `modulate` 压暗决定。
##   (memory `fb-my-thresholds-degrade-good-assets`: 我拍的阈值会把好素材改坏。)
SKIP_WORDS = ("silhouette", "band", "veil", "leaf", "debris")
## ★debris(地面碎件)也跳过: 被拉成地面同色就**隐身**了 —— 参考里的骨头是浅米白, 就是要跳出来的。
##   2026-10-03 探针: 碎件 260 件全建出来了, 实拍一件都看不见, 原因就是被这里染成了地面色。

## ★★★统一墨线(2026-10-03)。实测第一批 17 件的**描边**:
##   描边明度中位从 **12 到 141**、「近黑描边」占比从 **0% 到 98%** ——
##   花丛 97% / 灯柱 74% 有浓重深描边, 而浮木 / 草丛 / 棕榈 / 贝壳堆**是 0%**。
##   同一画面里混着两种画法, 这是「不像一套」最直接的原因。
##   咩咩的每件东西都是**同一种深色墨线**(逐张看参考可见)。
## ⇒ 每版一种墨色(主色相的极暗版, 不是纯黑 —— 咩咩的墨线是偏暖的深褐/深紫, 不是 #000),
##   把每件物件**最外一圈**不透明像素统一换成它。
INK = {
    "dusk":  (22, 24, 14),     # 暗林: 深橄榄墨
    "reef":  (16, 18, 38),     # 深靛
    "shoal": (58, 40, 26),     # 中深褐(白昼整体亮, 墨线不必压到最黑)
    "storm": (22, 26, 34),     # 冷深灰
}


def _hue_pull(h_deg, target_deg, f):
    """把色相往目标拉 f 比例，走最短弧（别绕一圈）。"""
    d = (target_deg - h_deg + 540.0) % 360.0 - 180.0
    return (h_deg + d * f) % 360.0


def _ink_outline(im, ink):
    """把最外一圈不透明像素(4 邻域里有透明的)换成墨色, alpha 保留。"""
    w, h = im.size
    px = im.load()
    edge = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] <= 40:
                continue
            for a, b in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if not (0 <= a < w and 0 <= b < h) or px[a, b][3] <= 40:
                    edge.append((x, y))
                    break
    for x, y in edge:
        px[x, y] = (ink[0], ink[1], ink[2], px[x, y][3])
    return len(edge)


def harmonize(path, target_h, pull, lo, hi, ink=None):
    orig = path[:-4] + ".orig.png"
    if not os.path.exists(orig):
        Image.open(path).save(orig)          # 第一次先留底，可重跑
    im = Image.open(orig).convert("RGBA")
    w, h = im.size
    px = im.load()
    hs_b, ls_b, hs_a, ls_a = [], [], [], []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= 8:
                continue
            hh, ll, ss = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
            if ss > 0.12:
                hs_b.append(hh * 360.0)
            ls_b.append(ll)
            if not (ss >= ACCENT_S and ll >= ACCENT_L):      # 不是“光”才调
                hh = _hue_pull(hh * 360.0, target_h, pull) / 360.0
                ll = lo + (hi - lo) * ll
            nr, ng, nb = colorsys.hls_to_rgb(hh, min(1.0, max(0.0, ll)), ss)
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
            hh2, ll2, ss2 = colorsys.rgb_to_hls(nr, ng, nb)
            if ss2 > 0.12:
                hs_a.append(hh2 * 360.0)
            ls_a.append(ll2)
    if ink is not None:
        _ink_outline(im, ink)      # ★统一墨线放在调色**之后**: 墨色不该再被拉色相/压明度
    im.save(path)
    def med(v):
        return sorted(v)[len(v) // 2] if v else -1.0
    return (med(hs_b), med(ls_b), med(hs_a), med(ls_a))


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else ""
    if not os.path.isdir(DIR):
        print("  没有 %s —— 还没有主题素材" % DIR)
        return 0
    n = 0
    for th, (target_h, pull, lo, hi) in sorted(SPEC.items()):
        if only and th != only:
            continue
        files = sorted(glob.glob(os.path.join(DIR, th + "_*.png")))
        files = [f for f in files if not f.endswith(".orig.png")]
        skipped = [f for f in files if any(w in os.path.basename(f) for w in SKIP_WORDS)]
        files = [f for f in files if f not in skipped]
        for f in skipped:
            ## 已经处理过的要**还原**(第一次跑把它们改坏了)
            o = f[:-4] + ".orig.png"
            if os.path.exists(o):
                Image.open(o).save(f)
            print("    [跳过·剪影] %s (已从 .orig 还原)" % os.path.basename(f)[:-4])
        if not files:
            continue
        print("── %s（主色相 %.0f° · 拉拢 %.0f%% · 明度 %.2f~%.2f）" % (th, target_h, pull * 100, lo, hi))
        hs = []
        for f in files:
            hb, lb, ha, la = harmonize(f, target_h, pull, lo, hi, INK.get(th))
            hs.append(ha)
            print("    %-26s 色相 %5.0f°→%5.0f°   明度中位 %.2f→%.2f"
                  % (os.path.basename(f)[:-4], hb, ha, lb, la))
            n += 1
        if len(hs) >= 2:
            ## ★色相是**环**, 直线减法会把 334° 和 22° 算成相差 312°(其实只差 48°)。
            ##   用「以主色相为原点的有符号偏差」来量跨度 —— 这才是"散不散"。
            dev = [abs((x - target_h + 540.0) % 360.0 - 180.0) for x in hs]
            print("    [整组] 离主色相最远 %.0f° · 中位 %.0f° (越小越像一套)"
                  % (max(dev), sorted(dev)[len(dev) // 2]))
    print("\n  处理 %d 件（原图留在同名 .orig.png，可重跑/可回退）" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
