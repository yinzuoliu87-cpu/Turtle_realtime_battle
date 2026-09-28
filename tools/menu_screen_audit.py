# -*- coding: utf-8 -*-
"""menu_screen_audit.py — 量一张【菜单类屏幕】的版式指标, 并与参考图分布比。

═══════════════════════════════════════════════════════════════════════════
★这份脚本存在的理由(2026-09-27 用户原话):

    「主菜单那次是取了 30 款同类好游戏 140 张截图、量出阈值才做对了吗?
      **也没做对啊, 质量不高啊?**」

用户是对的, 而我之前答错了。那 140 张截图量的是**战斗场景**(`tools/battle_scene_audit.py`),
**菜单类屏幕(主菜单/图鉴/排行榜/商店/背包)从来没有被任何参考量过**。
「我照流程做了」不是证据 —— 这个文件就是去把**缺的那把尺子**补上。

★★但请先读文件末尾的 `LIMITS`。这把尺子**不发合格证**。
  上一轮我拿「0 个圆角盒」当"全清了"报给用户, 用户当场说「一点也看不出来游戏的味道」。
  **阈值全在区间内 ≠ 做得好**, 理由写在 `LIMITS` 里, 报结论前必须连那段一起报。
═══════════════════════════════════════════════════════════════════════════

用法
────
    python tools/menu_screen_audit.py measure <图.png> [...]     # 逐张打指标
    python tools/menu_screen_audit.py refs   <参考根目录>         # 量参考集 → refs.json + thresholds.md
    python tools/menu_screen_audit.py diff   <参考根目录>         # 我们 vs 参考中位数, 按差距排序
    python tools/menu_screen_audit.py selftest                   # ★证明它会 FAIL(反向验证)

参考根目录的样子(本轮实际用的是 C:/tmp/uiref, **不进仓库**, 只是外部素材):
    <root>/mainmenu/*.jpg  codex/  leaderboard/  shop/  inventory/   ← 参考图
    <root>/ours/{mainmenu,codex,leaderboard,shop,inventory}.png      ← 我们自己的实拍
    <root>/sources.txt                                               ← 每张图的来源与游戏名

我们自己那五张怎么来(照抄仓库里**现成的** `tests/_shot_scene.gd`, 没造新轮子):

    NO_SAVE=1 APPDATA=<每屏一份私有目录> \
    SHOT_SCENE=res://scenes/Leaderboard.tscn SHOT_SETUP=res://tests/_setup_lb_rows.gd \
    SHOT_OUT=C:/tmp/uiref/ours/leaderboard.png SHOT_WAIT=460 \
    <godot> --audio-driver Dummy --path . res://tests/_shot_scene.tscn \
            --resolution 1280x720 --position 5000,5000

  ★`NO_SAVE=1` 不是可选的 —— 截图台**必须真渲染**所以不是 headless,
    而 GameState 的第一道闸只认 headless ⇒ 不给它就**写玩家真存档**
    (见 docs/plans/20260919-每个交互点实拍巡检.md 的 A 条)。
  ★**不能加 `--headless`**: 无头是 dummy renderer, 截出来是空图**而且不报错**。
  ★每屏一份独立 APPDATA —— 同 CLAUDE.md §2 那条「测试之间靠文件互相串味」。

═══ 口径: 为什么不缩放 ═══
参考图多是 1920×1080, 我们是 1280×720。**一律按原分辨率量**, 不 resize:
  · resize 到同一高度必然引入重采样 ⇒ 给参考图**凭空加上抗锯齿**,
    而 `aa_ratio`(字是不是像素字)正是靠抗锯齿判的 ⇒ 尺子会把参考组一律判成"糊的",
    我们反而"更像素" —— **方向刚好反了**。
  · 所以凡是跟尺寸挂钩的量, 要么换算成「等效 720p 像素」(`*720/H`),
    要么本来就是比例(边带宽 ÷ 控件高)。后者正是需求里要的口径。
"""
import io
import json
import os
import sys
from collections import Counter

try:
    import numpy as np
    from scipy import ndimage
    from PIL import Image
except ImportError:  # pragma: no cover
    print("需要 numpy / scipy / pillow:  pip install numpy scipy pillow")
    sys.exit(2)

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

CLASSES = ["mainmenu", "codex", "leaderboard", "shop", "inventory"]
CLASS_CN = {"mainmenu": "主菜单", "codex": "图鉴", "leaderboard": "排行榜",
            "shop": "商店", "inventory": "背包"}

# ── 指标登记表: 键 → (中文名, 单位, 方向说明) ────────────────────────────
# 「方向说明」只描述这条量的是什么, **不含"越大越好"** —— 好坏由人看图判, 不由这里判。
METRICS = [
    ("round_panel_pct", "圆角面板占比", "%", "被判定为圆角矩形的面板 ÷ 全部面板"),
    ("radius_p50", "圆角半径中位", "px@720", "只统计 r>0 的面板; 没有圆角面板时为 None"),
    ("framed_panel_pct", "带边框面板占比", "%", "≥3 条边有明显边带的面板"),
    ("band_ratio_p50", "边带宽 ÷ 控件高", "", "9-slice 像素边框的粗细, 中位"),
    ("band_colors_p50", "边带内颜色数", "色", "1≈发丝线; ≥3≈有厚度的像素边框"),
    ("text_area_pct", "文字占面积比", "%", "文字行外接框总面积 ÷ 全屏"),
    ("font_tiers", "字号档数", "档", "一屏用了几档字号(行高直方图的峰数)"),
    ("line_h_p50", "正文行高中位", "px@720", ""),
    ("aa_ratio", "字的抗锯齿率", "", "0≈像素字; 高≈平滑矢量字"),
    ("eff_colors", "有效色数", "色", "5bit 量化后占面积≥0.05% 的颜色数"),
    ("sat_p50", "饱和度中位", "", ""),
    ("sat_hi_pct", "高饱和像素占比", "%", "S>0.5 的像素"),
    ("deadflat_pct", "死平填充占比", "%", "5×5 内明度极差≤2 的像素 —— 网页味的主形状"),
    ("panel_count", "面板数", "个", "面积≥0.2% 且填充率≥0.55 的纯色块"),
    ("col_shared", "对齐列数", "列", "被≥3 行共用的左边界 x —— 表格结构"),
    ("col_cover_pct", "落在对齐列上的行占比", "%", ""),
    ("hrule_count", "全宽细分隔线条数", "条", "跨≥35% 宽、厚≤3px 的横线"),
    ("icon_like", "图标状元件数", "个", "彩色小块(≥5 色、有饱和度)"),
    ("icon_per_run", "图标 ÷ 文字行", "", "图标化程度; 0=纯文字标签"),
]
METRIC_KEYS = [m[0] for m in METRICS]


# ══════════════════════════════════════════════════════════════════════
# 基础量
# ══════════════════════════════════════════════════════════════════════
def load(path):
    """读图。只在超大图(H≥2160)上做**整数倍**面积降采样, 避免非整数倍重采样糊边。"""
    im = Image.open(path).convert("RGB")
    W, H = im.size
    if H >= 2160:
        k = H // 1080
        im = im.resize((W // k, H // k), Image.BOX)
    return np.asarray(im, dtype=np.float32)


def luma(a):
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def saturation(a):
    mx = a.max(axis=2)
    mn = a.min(axis=2)
    return np.where(mx <= 0, 0.0, (mx - mn) / np.maximum(mx, 1e-6))


## ── 背景/前景分离 ────────────────────────────────────────────────────
## ★为什么必须有这一步(2026-09-27 实地打脸):
##   另一个 agent 把【设置屏】整屏重做(音量条从网页 range 长相换成九宫格金属槽、
##   两个 CSS 对话框换成像素面板), 拿这把尺子量 before/after ——
##   **「死平填充」79.4% → 78.1%, 基本不动**。查出来的原因:
##   尺子把**平铺背景上的装饰纹样数成了 273 条「文字行」** ⇒ 前景怎么改, 分母都被背景压住。
##   本仓所有菜单屏铺的是同一张花砖底, 它在任何屏上都贡献几乎一样的一大堆边与行。
##
## 判据: 背景是【把局部均色跟四边取样的基色比得上、且连到屏幕边缘】的那一片。
##   · 用**局部均色**(9px 盒滤波)而不是原像素 —— 花砖上的纹样是低反差的,
##     均色仍然等于底色, 于是纹样跟着底一起被划进背景; 而面板的均色是另一种颜色。
##   · 要求**连到屏幕边缘** —— 控件内部偶然撞上底色的小块不会被误划。
## 参数由五张实拍标定(把控件外接框量出来当真值): blur=9 / tol=12 时
##   排行榜 50.7%(真值≈54) · 图鉴 21.5%(≈18) · 主菜单 49.3%(≈45)。
##   tol=8 会漏掉一半背景, tol≥22 会把暗色面板整个吞掉(图鉴 50.5% vs 真值 18)。
BG_BLUR, BG_TOL = 9, 12.0


def background_mask(img, panel_boxes=()):
    """回 (bg 布尔掩码, 背景基色)。检测不到就回全 False —— 那时所有量退化成整屏口径。"""
    H, W = img.shape[:2]
    base = np.stack([ndimage.uniform_filter(img[..., c], BG_BLUR) for c in range(3)], axis=2)
    strip = np.concatenate([base[:6].reshape(-1, 3), base[-6:].reshape(-1, 3),
                            base[:, :6].reshape(-1, 3), base[:, -6:].reshape(-1, 3)])
    ref = np.median(strip, axis=0)
    m = np.abs(base - ref).max(axis=2) < BG_TOL
    lab, k = ndimage.label(m)
    if k == 0:
        return np.zeros((H, W), bool), ref
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    if not border:
        return np.zeros((H, W), bool), ref
    bg = np.isin(lab, list(border))
    # 保险: 已经认出来的面板一律算前景, 哪怕它的底色跟背景撞了
    for p in panel_boxes:
        bg[p["y0"]:p["y1"] + 1, p["x0"]:p["x1"] + 1] = False
    return bg, ref


def qkey(a, bits=4):
    """量化成一个整数键。bits=4 → 每通道 16 级(面板/边带用); bits=5 → 32 级(调色板用)。"""
    sh = 8 - bits
    q = (a.astype(np.uint8) >> sh).astype(np.int32)
    n = 1 << bits
    return q[..., 0] * n * n + q[..., 1] * n + q[..., 2]


# ══════════════════════════════════════════════════════════════════════
# ① 面板: 圆角半径 / 边框边带
# ══════════════════════════════════════════════════════════════════════
## 圆角矩形: 圆心在 (r,r) 半径 r。对角线上的点 (t,t) 到圆心距 √2(r−t), 进入图形要 ≤ r
## ⇒ t = r(1 − 1/√2) = 0.2929r ⇒ **r = 3.4142·t**, t 是沿对角线走过的【格数】。
## ★这里错过一次: 先按"欧氏距离"写成 2.4142·t —— 但循环里数的是**下标**不是距离,
##   差了一个 √2。合成图真值 r=28, 错的系数量出 19.3, 对的量出 27.3。
##   **常数必须拿已知答案的图标定, 不能靠推导直接信。**
CORNER_K = 3.4142
ROUND_MIN = 10.0     # 判"圆角"的下限(px@720)。见 LIMITS: 比这更小的圆角这把尺子分不出直角。


def _corner_radius(sub):
    """沿四个角的对角线走, 回 r(px, 原分辨率)。

    ★不拿 bbox 的极值角当起点 —— 区域边界是**毛的**(噪点/抖动让最上面那行出现在某个
      奇怪的 x 上), 于是直角也能走出 2~3 格, 量出 r≈8 的假圆角。
      改成拿【中间 50% 的边界中位数】当矩形的四条边, 毛刺就进不来。
    """
    bh, bw = sub.shape
    if bh < 6 or bw < 6:
        return 0.0
    cols = np.arange(int(bw * 0.25), int(bw * 0.75) + 1)
    rows = np.arange(int(bh * 0.25), int(bh * 0.75) + 1)
    if cols.size < 2 or rows.size < 2:
        return 0.0

    def first_true(arr2d, axis):
        any_ = arr2d.any(axis=axis)
        idx = arr2d.argmax(axis=axis).astype(np.float64)
        idx[~any_] = np.nan
        return idx

    top = first_true(sub[:, cols], 0)
    bot = (bh - 1) - first_true(sub[::-1, :][:, cols], 0)
    lft = first_true(sub[rows, :], 1)
    rgt = (bw - 1) - first_true(sub[rows, :][:, ::-1], 1)
    with np.errstate(invalid="ignore"):
        y_t, y_b = np.nanmedian(top), np.nanmedian(bot)
        x_l, x_r = np.nanmedian(lft), np.nanmedian(rgt)
    if not np.isfinite([y_t, y_b, x_l, x_r]).all():
        return 0.0
    y_t, y_b, x_l, x_r = int(y_t), int(y_b), int(x_l), int(x_r)
    lim = max(1, min(y_b - y_t, x_r - x_l) // 2)
    ds = []
    for cy, cx, sy, sx in ((y_t, x_l, 1, 1), (y_t, x_r, 1, -1),
                           (y_b, x_l, -1, 1), (y_b, x_r, -1, -1)):
        d = lim
        for i in range(lim):
            yy, xx = cy + sy * i, cx + sx * i
            if 0 <= yy < bh and 0 <= xx < bw and sub[yy, xx]:
                d = i
                break
        ds.append(d)
    ds.sort()
    return CORNER_K * 0.5 * (ds[1] + ds[2])   # 中间两角, 抗"一个角被别的东西压住"


def _band(img, q, mask, y0, y1, x0, x1, inner_key):
    """从面板边界**向外**走, 数出边带(9-slice 框)的宽度与带内颜色数。

    判据: 一直走到颜色稳定成"外部背景色"(取 24px 处那一格)为止。
    走满 24px 还不稳定 ⇒ 判为 0(说不清, 不硬猜)。
    """
    H, W = q.shape
    MAXB = 24
    widths, cols = [], set()
    probes = [
        (range(x0 - 1, max(-1, x0 - 1 - MAXB), -1), (y0 + y1) // 2, "h"),
        (range(x1 + 1, min(W, x1 + 1 + MAXB)), (y0 + y1) // 2, "h"),
        (range(y0 - 1, max(-1, y0 - 1 - MAXB), -1), (x0 + x1) // 2, "v"),
        (range(y1 + 1, min(H, y1 + 1 + MAXB)), (x0 + x1) // 2, "v"),
    ]
    for rng, fixed, axis in probes:
        seq, kseq = [], []
        for p in rng:
            if axis == "h":
                if not (0 <= p < W):
                    break
                seq.append(img[fixed, p]); kseq.append(q[fixed, p])
            else:
                if not (0 <= p < H):
                    break
                seq.append(img[p, fixed]); kseq.append(q[p, fixed])
        if len(seq) < 6:
            continue
        ## ★停止条件用【颜色距离】不是"量化桶完全相等"。
        ##   桶相等那一版在**渐变背景**上几乎永远不成立 ⇒ 一路走到 24px 才碰巧撞上同一个桶,
        ##   于是 25px 高的一行量出 10px"边带"(band/h=0.40), 把背景渐变算成了边框。
        outer = np.asarray(seq[-1], np.float32)
        b = 0
        for v in seq:
            if float(np.abs(np.asarray(v, np.float32) - outer).max()) <= 12.0:
                break
            b += 1
        if b >= len(seq):            # 一路到底都没稳定 ⇒ 说不清, 这条边不算数
            continue
        widths.append(b)
        for v in kseq[:b]:
            cols.add(int(v))
    if not widths:
        return 0.0, 0, 0
    widths.sort()
    return (float(np.median(widths)), len(cols),
            sum(1 for w in widths if w >= 2))


def panels(img, lum, q4):
    """找面板候选。

    ★不按"同一个量化色"切 —— 那条路我先试过, 当场坏在一个真实形状上:
      `#F8F9FB` 的页面底色和 `#FFFFFF` 的卡片在 4bit 量化下**是同一个桶**,
      于是底色和三张卡连成一整块 → 被"整屏背景"规则滤掉 → 一个面板都找不到。
      (合成图真值是 3 张圆角卡, 尺子报 0 个 —— 靠 `selftest` 当场照出来的。)

    ⇒ 改成按**强边界**切: `~edge` 的连通域。两块颜色相近的区域之间照样有边界,
      而区域内部的轻微抖动/噪点(极差≤6)不会把它切碎 —— 像素风的面板填充正是这种。
      代价写在这里: **重纹理/插画填充的面板会被切碎因而数不到**,
      所以 `panel_count` 低有两种可能(真没有面板 / 面板太花), 不能只看它下结论。
    """
    H, W = lum.shape
    area_min = int(0.002 * H * W)
    ## ★先过一道 3×3 中值再求极差。中值是**保边**的: 它压掉面板填充里的抖动/噪点,
    ##   而不削弱真边界。实测(两张合成图): 像素面板内部极差 8.0 → 3.0,
    ##   而"浅灰底 vs 白卡"那条只有 5.8 的弱边界仍然是 6.07 ⇒ 阈值 4.5 能把两者分开。
    ##   不过这一道, 像素风面板会被自己的噪点切碎 ⇒ 一个面板都找不到。
    sm = ndimage.median_filter(lum, size=3)
    rng3 = ndimage.maximum_filter(sm, size=3) - ndimage.minimum_filter(sm, size=3)
    edge = rng3 > 4.5
    lab, k = ndimage.label(~edge)
    out = []
    if k == 0:
        return out
    objs = ndimage.find_objects(lab)
    sizes = ndimage.sum(np.ones_like(lum), lab, range(1, k + 1))
    for i, sl in enumerate(objs):
        a = sizes[i]
        if a < area_min:
            continue
        ys, xs = sl
        y0, y1, x0, x1 = ys.start, ys.stop - 1, xs.start, xs.stop - 1
        bh, bw = y1 - y0 + 1, x1 - x0 + 1
        if bw < 40 or bh < 20:
            continue
        if bw > 0.95 * W and bh > 0.95 * H:     # 整屏背景不是面板
            continue
        if a / float(bh * bw) < 0.55:
            continue
        sub = (lab[sl] == (i + 1))
        r = _corner_radius(sub)
        key = int(np.bincount(q4[sl][sub].ravel()).argmax())
        bwid, bcol, bsides = _band(img, q4, sub, y0, y1, x0, x1, key)
        out.append({"y0": y0, "y1": y1, "x0": x0, "x1": x1,
                    "bh": bh, "bw": bw, "r": r * 720.0 / H,
                    "band": bwid, "band_ratio": bwid / float(bh),
                    "band_colors": bcol, "band_sides": bsides})
    # 去重: 同一块面板可能被相邻量化色各认领一次
    out.sort(key=lambda p: -p["bh"] * p["bw"])
    keep = []
    for p in out:
        dup = False
        for k2 in keep:
            ox = max(0, min(p["x1"], k2["x1"]) - max(p["x0"], k2["x0"]))
            oy = max(0, min(p["y1"], k2["y1"]) - max(p["y0"], k2["y0"]))
            if ox * oy > 0.6 * min(p["bh"] * p["bw"], k2["bh"] * k2["bw"]):
                dup = True
                break
        if not dup:
            keep.append(p)
    return keep


# ══════════════════════════════════════════════════════════════════════
# ② 文字 / 图标 / 表格结构
# ══════════════════════════════════════════════════════════════════════
def ink_and_text(img, lum):
    """不做 OCR。用「局部明度反差」抠出笔画, 再把**同一行的字横向粘起来**成文字行。

    横向膨胀那一下是关键: 单个汉字/字母是一堆碎块, 粘起来才量得到"行高"与"左边界",
    而行高直方图的峰数就是**字号档数**、左边界就是**表格列**。
    """
    H, W = lum.shape
    bg = ndimage.uniform_filter(lum, size=21)
    d = lum - bg
    ink = np.abs(d) > 26.0

    n_edge = int((ink & (~ndimage.binary_erosion(ink))).sum())

    # --- 文字行 ---
    k = max(3, int(round(6 * H / 720.0)))
    merged = ndimage.binary_dilation(ink, structure=np.ones((1, k), bool))
    lab, n = ndimage.label(merged)
    runs = []
    if n:
        for i, sl in enumerate(ndimage.find_objects(lab)):
            ys, xs = sl
            bh = ys.stop - ys.start
            bw = xs.stop - xs.start
            hh = bh * 720.0 / H
            if not (5.0 <= hh <= 64.0):
                continue
            if bw < 8 or bw > 0.92 * W:
                continue
            if bh * bw > 0.04 * H * W:
                continue
            runs.append({"y0": ys.start, "x0": xs.start, "h": bh, "w": bw, "hh": hh})

    # --- 抗锯齿率: 文字行里有多少像素卡在【纸色与墨色中间】 ---
    # ★第一版写成「笔画外圈有没有过渡像素」, 两张已知答案的图量出 1.01 与 0.99 ——
    #   **分不开**。原因是"背景"用的是 21px 局部均值, 而字间空隙在那个尺度上也算反差,
    #   于是空隙自己被算成了笔画, 边与晕一样多、比值恒等于 1。
    #   改成量**灰阶层数**: 像素字只有纸/墨两级, 中间带按定义是空的;
    #   平滑矢量字的每条笔画边都要靠中间灰来过渡。与背景模型无关。
    mids = []
    for r in runs:
        patch = lum[r["y0"]:r["y0"] + r["h"], r["x0"]:r["x0"] + r["w"]]
        if patch.size < 60:
            continue
        lo, hi = np.percentile(patch, 5), np.percentile(patch, 95)
        if hi - lo < 30.0:                       # 反差太小, 说不清, 不算进去
            continue
        a_, b_ = lo + 0.25 * (hi - lo), lo + 0.75 * (hi - lo)
        mids.append(float(((patch > a_) & (patch < b_)).mean()))
    aa = float(np.median(mids)) if len(mids) >= 8 else None
    return ink, runs, aa, n_edge


def font_tiers(runs, H):
    """行高直方图的峰数 = 字号档数。2px 一格(换算到 720p), 相邻格合并, 只数够分量的峰。"""
    if len(runs) < 6:
        return None, None
    hs = sorted(r["hh"] for r in runs)
    med = hs[len(hs) // 2]
    bins = Counter(int(h // 2) for h in hs)
    thr = max(3, 0.06 * len(hs))
    peaks, prev = 0, -9
    for b in sorted(bins):
        if bins[b] < thr:
            continue
        if b - prev > 1:            # 相邻格算同一档
            peaks += 1
        prev = b
    return peaks, med


def tabular(runs, W):
    """表格结构: 有多少个左边界 x 被 ≥3 行共用。网页味的「列标题 + 列对齐」就落在这里。"""
    if len(runs) < 4:
        return 0, 0.0
    step = max(4, int(round(8 * W / 1280.0)))
    c = Counter(r["x0"] // step for r in runs)
    shared = [x for x, n in c.items() if n >= 3]
    cover = sum(c[x] for x in shared) / float(len(runs))
    return len(shared), 100.0 * cover


def hrules(lum):
    """全宽细分隔线: 横向一长段明度几乎不变, 而上下两侧明显不同。"""
    H, W = lum.shape
    same = np.abs(np.diff(lum, axis=1)) < 3.0          # (H, W-1)
    up = np.abs(lum[2:-2] - lum[:-4]) > 12.0           # (H-4, W)
    dn = np.abs(lum[2:-2] - lum[4:]) > 12.0
    cand = same[2:-2] & up[:, :-1] & dn[:, :-1]        # (H-4, W-1)
    need = int(0.35 * W)
    # 每行最长连续 True 段 —— 逐像素 Python 循环要 90 万次, 这里按列累加向量化算。
    acc = np.zeros(cand.shape[0], np.int32)
    best = np.zeros(cand.shape[0], np.int32)
    for x in range(cand.shape[1]):
        col = cand[:, x]
        acc = np.where(col, acc + 1, 0)
        best = np.maximum(best, acc)
    rows = np.nonzero(best >= need)[0].tolist()
    merged, prev = 0, -9
    for y in rows:
        if y - prev > 3:
            merged += 1
        prev = y
    return merged


def icons(img, lum, q4, ink):
    """图标状元件: 有厚度、有颜色、**不是**一串笔画的小块。

    ★不能用 `ink` 来找它。`ink` 是「跟 21px 局部均值比反差大」, 而一枚 18px 的亮图标
      **自己就把那 21px 的局部均值抬上去了** ⇒ 它整块都不算 ink, 一个都数不到
      (合成图里真值 27 枚, 尺子报 0 —— 靠 `selftest` 照出来的)。
      同一个坑也吃过一次: 粗笔画的字会让 `aa_ratio` 大于 1。**21px 的背景模型只对细笔画成立。**

    ⇒ 改成按「够亮 + 够饱和」的连通块找, 与背景模型无关。
    ⚠ 口径要说清楚: 它数的是**彩色小块**, 立绘/头像/贴图碎片同样会被数进去,
      所以它量的是「这一屏有多少图形化元件」, **不是**「有多少枚设计过的图标」。
    """
    H, W = lum.shape
    sat = saturation(img)
    colorful = (sat > 0.35) & (lum > 60.0)
    colorful = ndimage.binary_closing(colorful, structure=np.ones((3, 3), bool))
    lab, n = ndimage.label(colorful)
    if n == 0:
        return 0
    cnt = 0
    for i, sl in enumerate(ndimage.find_objects(lab)):
        ys, xs = sl
        bh, bw = ys.stop - ys.start, xs.stop - xs.start
        hh, ww = bh * 720.0 / H, bw * 720.0 / H
        if not (10 <= hh <= 80 and 10 <= ww <= 80):
            continue
        if not (0.45 <= bw / float(bh) <= 2.2):
            continue
        sub = (lab[sl] == (i + 1))
        if sub.sum() / float(bh * bw) < 0.25:
            continue
        if np.unique(q4[sl][sub]).size < 4:
            continue
        cnt += 1
    return cnt


# ══════════════════════════════════════════════════════════════════════
# 主量法
# ══════════════════════════════════════════════════════════════════════
def measure(path):
    img = load(path)
    H, W = img.shape[:2]
    lum = luma(img)
    q4 = qkey(img, 4)
    q5 = qkey(img, 5)
    sat = saturation(img)

    ps = panels(img, lum, q4)
    r_all = [p["r"] for p in ps]
    r_pos = sorted(x for x in r_all if x >= ROUND_MIN)
    framed = [p for p in ps if p["band_sides"] >= 3]
    bands = sorted(p["band_ratio"] for p in framed)
    bcols = sorted(p["band_colors"] for p in framed)

    ink, runs, aa, n_edge = ink_and_text(img, lum)
    tiers, lh = font_tiers(runs, H)
    cshared, ccover = tabular(runs, W)
    txt_area = sum(r["h"] * r["w"] for r in runs) / float(H * W)

    # 死平填充: 5×5 邻域明度极差 ≤2
    mx = ndimage.maximum_filter(lum, size=5)
    mn = ndimage.minimum_filter(lum, size=5)
    deadflat = float(((mx - mn) <= 2.0).mean())

    ic = icons(img, lum, q4, ink)
    vals, cts = np.unique(q5, return_counts=True)
    eff = int((cts >= 0.0005 * H * W).sum())

    def med(a):
        return float(np.median(a)) if len(a) else None

    return {
        "file": os.path.basename(path), "size": [W, H],
        "panel_count": len(ps),
        "round_panel_pct": (100.0 * len(r_pos) / len(ps)) if ps else None,
        "radius_p50": med(r_pos),
        "framed_panel_pct": (100.0 * len(framed) / len(ps)) if ps else None,
        "band_ratio_p50": med(bands),
        "band_colors_p50": med(bcols),
        "text_area_pct": 100.0 * txt_area,
        "font_tiers": tiers,
        "line_h_p50": lh,
        "aa_ratio": aa,
        "eff_colors": eff,
        "sat_p50": float(np.median(sat)),
        "sat_hi_pct": 100.0 * float((sat > 0.5).mean()),
        "deadflat_pct": 100.0 * deadflat,
        "col_shared": cshared,
        "col_cover_pct": ccover,
        "hrule_count": hrules(lum),
        "icon_like": ic,
        "icon_per_run": (ic / float(len(runs))) if runs else None,
        "_n_text_runs": len(runs), "_n_ink_edge": n_edge,
    }


# ══════════════════════════════════════════════════════════════════════
# 参考集 / 差值表
# ══════════════════════════════════════════════════════════════════════
def _q(vals, p):
    v = sorted(x for x in vals if x is not None)
    if not v:
        return None
    return float(np.percentile(v, p))


def scan_refs(root, workers=8):
    from concurrent.futures import ProcessPoolExecutor
    jobs, meta = [], []
    for c in CLASSES:
        d = os.path.join(root, c)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if fn.lower().endswith((".jpg", ".jpeg", ".png")):
                jobs.append(os.path.join(d, fn))
                meta.append(c)
    out = {c: [] for c in CLASSES}
    with ProcessPoolExecutor(max_workers=workers) as ex:
        for c, r in zip(meta, ex.map(measure, jobs, chunksize=2)):
            out[c].append(r)
    return out


def dist_table(rows):
    """一组图 → 每个指标的 n / p10 / p50 / p90。

    ★`n` 不是装饰: 它是**分母**。n 小到个位数的指标, 那一行的"中位数"说明不了任何事,
      报的时候必须连 n 一起报(CLAUDE.md:「打印分母 —— N=0 是空检查不是通过」)。
    """
    t = {}
    for k in METRIC_KEYS:
        vals = [r.get(k) for r in rows]
        vals = [v for v in vals if v is not None]
        t[k] = {"n": len(vals), "p10": _q(vals, 10), "p50": _q(vals, 50),
                "p90": _q(vals, 90)}
    return t


def fmt(v, k=""):
    if v is None:
        return "—"
    if k in ("panel_count", "font_tiers", "eff_colors", "col_shared",
             "hrule_count", "icon_like"):
        return "%.0f" % v
    if abs(v) >= 100:
        return "%.0f" % v
    return "%.2f" % v


# ══════════════════════════════════════════════════════════════════════
# ★反向验证: 证明这把尺子会 FAIL
# ══════════════════════════════════════════════════════════════════════
def _synth(kind, W=1280, H=720):
    """合成两张【已知答案】的图: 一张刻意的网页味, 一张刻意的像素游戏味。

    CLAUDE.md:「报『做完了/没问题』之前, 先证明检查本身会 FAIL」。
    一把量不出这两张差别的尺子, 拿去量真图得到的任何数字都不算数。
    """
    a = np.zeros((H, W, 3), np.uint8)

    def glyphs(y, xa, xb, core, aa_col):
        """画一行"字": 2px 宽的竖笔画, 每 6px 一根。
        ★不能画成一整条 14px 厚的实心杠 —— `aa_ratio` 拿 21px 均值当背景模型,
          笔画一厚, 杠的内部自己就成了背景 ⇒ 只有边缘算笔画, 比值直接大于 1,
          尺子会把"没有抗锯齿"的那张判成抗锯齿更重。真实字的笔画是细的。"""
        for x in range(xa, xb - 2, 6):
            if aa_col is not None:                        # 抗锯齿: 笔画两侧一圈过渡色
                a[y - 1:y + 13, x - 1:x + 3] = aa_col
            a[y:y + 12, x:x + 2] = core

    if kind == "web":
        a[:, :] = (248, 249, 251)                        # 死平浅灰底
        for i in range(3):                               # 三张大圆角白卡
            x0, y0 = 80 + i * 380, 140
            x1, y1 = x0 + 330, y0 + 400
            r = 28
            yy, xx = np.mgrid[y0:y1, x0:x1]
            m = np.ones((y1 - y0, x1 - x0), bool)
            for cy, cx in ((y0 + r, x0 + r), (y0 + r, x1 - r),
                           (y1 - r, x0 + r), (y1 - r, x1 - r)):
                near = ((yy - cy) ** 2 + (xx - cx) ** 2 > r * r)
                q = (np.abs(yy - cy) < r) & (np.abs(xx - cx) < r)
                m &= ~(near & q)
            a[y0:y1, x0:x1][m] = (255, 255, 255)
            for j in range(9):
                glyphs(y0 + 40 + j * 38, x0 + 24, x1 - 24, (60, 62, 68), (158, 160, 166))
    else:
        rng = np.random.default_rng(7)
        base = np.array((26, 38, 54), np.int16)
        a[:, :] = np.clip(base + rng.integers(-5, 6, (H, W, 1)), 0, 255).astype(np.uint8)
        for i in range(3):                               # 三块直角 + 厚像素边框的木牌
            x0, y0 = 80 + i * 380, 140
            x1, y1 = x0 + 330, y0 + 400
            a[y0 - 8:y1 + 8, x0 - 8:x1 + 8] = (92, 60, 30)
            a[y0 - 5:y1 + 5, x0 - 5:x1 + 5] = (168, 118, 58)
            a[y0 - 2:y1 + 2, x0 - 2:x1 + 2] = (58, 36, 18)
            inner = np.clip(np.array((44, 30, 20), np.int16)
                            + rng.integers(-4, 5, (y1 - y0, x1 - x0, 1)), 0, 255)
            a[y0:y1, x0:x1] = inner.astype(np.uint8)
            for j in range(9):                           # 硬边像素字, 无过渡色
                ty = y0 + 40 + j * 38
                glyphs(ty, x0 + 48, x1 - 24, (236, 226, 190), None)
                # 行首一枚 18×18 的多色小图标(≥5 色才算图标, 单色块不算)
                pal = [(220, 60, 60), (250, 140, 40), (250, 220, 90),
                       (70, 200, 120), (60, 150, 240), (255, 255, 255)]
                for u in range(6):
                    a[ty - 2 + u * 3:ty + 1 + u * 3, x0 + 20:x0 + 38] = pal[u]
    return a


def selftest():
    import tempfile
    ok = True
    paths = {}
    for k in ("web", "pixel"):
        p = os.path.join(tempfile.gettempdir(), "_menu_audit_%s.png" % k)
        Image.fromarray(_synth(k)).save(p)
        paths[k] = p
    w, x = measure(paths["web"]), measure(paths["pixel"])
    # ★每条都是【已知答案】的方向。方向反了 = 尺子坏了, 不是被测图坏了。
    checks = [
        ("网页图有圆角面板 / 像素图没有",
         (w["round_panel_pct"] or 0) > 50 and (x["round_panel_pct"] or 0) < 20,
         "web=%s pixel=%s" % (fmt(w["round_panel_pct"]), fmt(x["round_panel_pct"]))),
        ("像素图有边框 / 网页图没有",
         (x["framed_panel_pct"] or 0) > 50 and (w["framed_panel_pct"] or 0) < 50,
         "web=%s pixel=%s" % (fmt(w["framed_panel_pct"]), fmt(x["framed_panel_pct"]))),
        ("网页图死平填充远高于像素图",
         w["deadflat_pct"] > x["deadflat_pct"] * 3,
         "web=%.1f%% pixel=%.1f%%" % (w["deadflat_pct"], x["deadflat_pct"])),
        # ★要的不是"大一点", 是**拉开数量级** —— 两个值挨在 1.01 / 0.99 的那一版
        #   6 条判据也是全 PASS 的, 而它其实什么都没量到。**判据必须卡住那个形状。**
        ("网页图抗锯齿率 ≥ 像素图的 3 倍",
         (w["aa_ratio"] or 0) >= 3.0 * (x["aa_ratio"] or 0) + 0.05,
         "web=%s pixel=%s" % (fmt(w["aa_ratio"]), fmt(x["aa_ratio"]))),
        ("圆角半径量得准(合成图真值 28px, 容差 ±4)",
         w["radius_p50"] is not None and abs(w["radius_p50"] - 28.0) <= 4.0,
         "web=%s (真值 28)" % fmt(w["radius_p50"])),
        ("像素图数得出图标 / 网页图数不出",
         x["icon_like"] >= 9 and w["icon_like"] <= 2,
         "web=%d pixel=%d" % (w["icon_like"], x["icon_like"])),
        ("两张都量到了文字行(分母不为 0)",
         w["_n_text_runs"] >= 20 and x["_n_text_runs"] >= 20,
         "web=%d pixel=%d" % (w["_n_text_runs"], x["_n_text_runs"])),
    ]
    print("== 反向验证: 拿两张【已知答案】的合成图证明尺子会 FAIL ==\n")
    for name, good, got in checks:
        print("  [%s] %-34s %s" % ("PASS" if good else "FAIL", name, got))
        ok &= bool(good)
    print("\n%s" % ("全部方向正确 —— 这把尺子确实在量它声称的东西。"
                    if ok else "★有方向不对 —— 尺子坏了, 它量出的任何数字都不算数。"))
    return 0 if ok else 1


# ══════════════════════════════════════════════════════════════════════
LIMITS = u"""
★★这把尺子量不到什么 —— 报结论必须连这段一起报

它**量得到**的只有【可数的形状】:
  圆角半径 / 边带宽度与颜色数 / 文字面积与字号档数 / 抗锯齿率 / 颜色数与饱和度 /
  死平填充比 / 列对齐与分隔线 / 图标状元件个数。
这些全是「像不像网页排版」的**代理量**, 不是「好不好看」。

它**量不到**(而这些恰恰是用户在意的):
  ① 好不好看 / 有没有"游戏味" —— 用户 2026-09-27 原话「一点也看不出来游戏的味道」。
     指标全落在参考区间里的屏, 照样可以是丑的。
  ② 美术素材本身的质量 —— 边框是精致的木雕还是我随手画的棕色方框, 这里一模一样。
  ③ 版式的意图 —— 哪个元素该最显眼、视线走哪条路, 一条都量不到。
  ④ 文字语言 —— 「暂无数据」还是「还没人上榜」, 像素级一样。
     而「文字语言也是」是用户点名的三件事之一。
  ⑤ 动效/手感 —— 全是静态单帧。
  ⑥ 一致性 —— 每屏单独量, 量不到"五屏像不像一家出的"。

★为什么「阈值都在区间内」≠ 做得好:
  · 参考中位数是 **60~75 款不同风格游戏拍平出来的**。谁都不长成那个中位数,
    往中位数靠 = 往"平均脸"靠, 那正好是"AI 味"的定义。
  · 这些量互相之间可以**用错误的方式满足**: 把所有圆角改成直角、边框描一圈灰线,
    指标立刻进区间, 而屏幕可以更难看。上一轮我就是拿「0 圆角盒」报的"全清了"。
  · 区间是 p10~p90, 按定义就有 20% 的**好参考**落在区间外。踩线不等于错。

⇒ 正确用法只有一个: **当探照灯用, 不当合格证用。**
  指标差得最远的那几条 → 值得去看那一屏到底怎么回事;
  指标都在区间内 → 什么都没证明, 该截图给人看。
"""


def cmd_refs(root):
    res = scan_refs(root)
    io.open(os.path.join(root, "refs.json"), "w", encoding="utf-8", newline="").write(
        json.dumps(res, ensure_ascii=False))
    lines = [u"# 菜单类屏幕 · 参考图阈值表", u"",
             u"由 `tools/menu_screen_audit.py refs` 生成, **不要手抄到别处**"
             u"(手抄的副本必然落后)。", u"",
             u"来源与每张图的游戏名见同目录 `sources.txt`。", u""]
    for c in CLASSES:
        rows = res.get(c) or []
        if not rows:
            continue
        t = dist_table(rows)
        lines += [u"## %s (`%s`) — %d 张" % (CLASS_CN[c], c, len(rows)), u"",
                  u"| 指标 | 单位 | n | p10 | **p50** | p90 |",
                  u"|---|---|---:|---:|---:|---:|"]
        for k, cn, unit, _note in METRICS:
            d = t[k]
            lines.append(u"| %s | %s | %d | %s | **%s** | %s |" % (
                cn, unit, d["n"], fmt(d["p10"], k), fmt(d["p50"], k), fmt(d["p90"], k)))
        lines.append(u"")
    lines += [u"## 这把尺子量不到什么", u"", u"```", LIMITS.strip(), u"```", u""]
    p = os.path.join(root, "thresholds.md")
    io.open(p, "w", encoding="utf-8", newline="").write(u"\n".join(lines))
    print(u"参考 %d 张 → %s" % (sum(len(v) for v in res.values()), p))
    return 0


def cmd_diff(root):
    rp = os.path.join(root, "refs.json")
    if not os.path.exists(rp):
        print("先跑 `refs` 生成 refs.json"); return 2
    res = json.load(io.open(rp, encoding="utf-8"))
    rows = []
    for c in CLASSES:
        ours_p = os.path.join(root, "ours", c + ".png")
        ref = res.get(c) or []
        if not (os.path.exists(ours_p) and ref):
            continue
        t = dist_table(ref)
        o = measure(ours_p)
        for k, cn, unit, _n in METRICS:
            d, mine = t[k], o.get(k)
            if d["p50"] is None or mine is None or d["n"] < 8:
                continue
            lo, hi = d["p10"], d["p90"]
            span = max(1e-6, (hi - lo))
            # ★用【参考自己的 p10~p90 跨度】当尺子单位 —— 不同指标量纲差几个数量级,
            #   直接比绝对差会让"颜色数"永远排第一。
            z = (mine - d["p50"]) / span
            inside = (lo - 1e-9) <= mine <= (hi + 1e-9)
            rows.append((abs(z), c, cn, unit, mine, d, z, inside, k))
    rows.sort(reverse=True)
    print(u"== 我们 vs 参考中位数 (按「差了几个参考跨度」排序) ==\n")
    print(u"  %-6s %-16s %10s %10s %14s %7s %s" % (
        u"屏", u"指标", u"我们", u"参考p50", u"参考p10~p90", u"差", u"在区间内"))
    for _a, c, cn, unit, mine, d, z, inside, k in rows:
        print(u"  %-6s %-16s %10s %10s %14s %+7.1f  %s" % (
            CLASS_CN[c], cn, fmt(mine, k), fmt(d["p50"], k),
            u"%s~%s" % (fmt(d["p10"], k), fmt(d["p90"], k)), z,
            u"是" if inside else u"★否"))
    print(LIMITS)
    return 0


def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    cmd = sys.argv[1]
    if cmd == "selftest":
        return selftest()
    if cmd == "refs":
        return cmd_refs(sys.argv[2])
    if cmd == "diff":
        return cmd_diff(sys.argv[2])
    if cmd == "measure":
        for p in sys.argv[2:]:
            a = measure(p)
            print(u"== %s  %dx%d ==" % (a["file"], a["size"][0], a["size"][1]))
            for k, cn, unit, note in METRICS:
                print(u"  %-16s %10s %-7s %s" % (cn, fmt(a.get(k), k), unit, note))
            print(u"  (分母: 文字行 %d 条 / 笔画边 %d px)"
                  % (a["_n_text_runs"], a["_n_ink_edge"]))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
