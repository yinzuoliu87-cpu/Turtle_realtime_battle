# -*- coding: utf-8 -*-
"""手半剑 084 三张特效素材 ↔ 用户参考图的**可量化**对账 (2026-08-29)。

用户 2026-08-29:「你在验证和我给你的参考图做到一模一样加像素风，
                  你做完你自己验证，**没通过就不要停也不要给我看**，
                  我需要你保证不会停，你有没有办法保证」

★保证的办法就是这个脚本: 把"通过"写成**有阈值的数字**, 我循环到它说 ALL OK 才停。
  判据不是我眼看 —— 我这一轮已经眼看着判错过四次(说"白热保留 9~21%",
  还原颜色后实测是 **0%**, 因为我没重新量)。

★阈值的来历(逐条对应用户给的图):
  【斩击图】厚身急剧收成针尖 · 白热刀锋与高饱和身强反差 · 一笔里多缕重叠 · 大量留空
  【剑气波图】整片由**分开的细丝**组成、丝间有黑缝、完全通透 · 前缘散成须(不是实心板)
  【命中图】角状棱刺(不是柔和月牙) · 橙色火星碎屑

⚠ **已知局限, 不隐瞒**: 用户的参考图只在对话里, 我没有文件, 所以阈值是**我读图后
  折算出来的数**, 不是像素级比对。我读错了 = 这个脚本焊住了错的靶子。
  ⇒ 若用户把图存到 `docs/ref/084/` 下, 应改成真正的逐像素/直方图比对。

跑法: python tools/vfx_ref_match.py
"""
import io
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    from PIL import Image
except Exception:
    print("  [FAIL] 需要 Pillow")
    sys.exit(1)

import colorsys
import math

VFX = "assets/sprites/vfx"

# ★像素风的两条通用判据(用户:「和参考做到一模一样**加像素风**」)
PAL_MAX = 96        # 量化到 5bit/通道后的色数上限 —— 像素画是有限色板
SOFT_MAX = 0.14     # alpha 处在 40~215 之间的占比上限 —— 羽化软边不像素

# ── 逐张的判据(全部来自用户参考图) ──────────────────────────────
#   taper     两端厚度 / 最厚处 —— 越小越"收成针尖"
#   fill      不透明像素 / 外接框面积 —— 越小越"通透、留空多"
#   hot       白热像素占比(低饱和 + 高亮) —— 刀锋那一层
#   strands   横向扫描线上"亮-暗-亮"的交替次数中位数 —— 多缕分层 / 丝丝分开的直接量
SPEC = {
    ## ★★2026-08-29 大改一次判据, 记下来免得再犯:
    ##   用户要看素材, 一并排就看出来 —— **PixelLab 原始帧比我加工后的好**:
    ##   斩击的紫色分层刀光被我洗白切碎, 剑波漂亮的辐射细丝被我剁成横向碎条。
    ##   根因是**这几条阈值是我拍脑袋定的, 而且拍错了**:
    ##     · `fill_max 0.30~0.34`(填充率上限) —— 参考里的剑气波本来就是**密集**的
    ##       辐射细丝(丝间只有细黑缝), 填充率本来就高。这条逼着我去削材质。
    ##     · `strands_min 6` —— 细丝一密就会连成片, 扫描线计数天然偏低。
    ##       这条逼着我把丝拉开、拉出黑缝, 结果成了纱窗。
    ##     · `taper_max` / `cv_min` 同理, 都是我按"看着应该这样"折算的数。
    ##   ⇒ **撤掉这几条**。判据错比判据松更危险: 松只是漏, 错是**主动把好的推向坏的**。
    ##
    ##   留下的都是"能指出具体缺陷"的:
    ##     · 白热要有(参考的强反差) · 前缘不许是实心板(那是真缺陷, 屏上读成方块)
    ##     · 像素风两条(有限色板 / 硬边) · 亮度下限(太暗读成一条暗线)
    ##
    ##   ⚠ 真正的解法是**拿用户的参考图做逐像素比对** —— 图只在对话里, 我没有文件。
    ##     用户把它们存到 `docs/ref/084/` 之后就该换成真比对, 而不是我折算的数。
    "eq084-slash.png": {
        "label": "斩击弧",
        "hot_min": 0.04, "hot_max": 0.45,   # 白热刀锋要有, 但不能糊成一片白
    },
    ## ★★撤掉 slab_max: 我把原图最亮的**白芯**当成"过曝白板"压成了一块灰绿死板,
    ##   并排一看明显比原图差。那是波的亮芯, 不是缺陷。今天第三次同一类错误。
    "eq084-wave.png": {
        "label": "剑气波",
        "hot_min": 0.02,
        "bulge_min": 0.045,         # ★前缘必须是【弯的】(用户点名「前部分是弯的」)
        "wedge_max": 0.45,          # ★必须是【扇形】而不是圆坨 —— 尾部要收成尖
        "thick_min": 2.0,           # 丝要有厚度 —— 逐行处理只能出 1px 横线
    },
    "eq084-beam.png": {
        "label": "激光束",
        # 参考 = 云顶 S4 速射火炮 + 用户发的四张实拍图: **一条细的亮电弧线**
        "hot_min": 0.04, "hot_max": 0.40,   # ★白热芯要有(第一版整条暗红, 读成一条暗线)
        "bright_min": 0.55,         # ★中位亮度 —— 激光是发光体, 不能是暗线
    },
    "eq084-burst.png": {
        "label": "命中爆点",
        "hot_min": 0.03, "hot_max": 0.40,
        "warm_min": 0.01,           # 橙色火星碎屑
    },
}


def mid_frame(im):
    """★★2026-08-29 改成【整张 sheet 一起量】, 不再只取中间一帧。

    只量中间一帧会被那一帧的偶然性质带偏 —— 斩击弧的动画是"起手亮 → 中段紫 → 末尾散",
    第 4 帧正好是最暗的一帧, 判据于是报"白热 0%", 而实际上前三帧全是白热刀锋。
    我照着那个假读数把整条弧洗白了一遍, 反而毁了原本对的紫色分层。
    """
    return im


def profile(path):
    im = mid_frame(Image.open(path).convert("RGBA"))
    px = im.load()
    W, H = im.size
    cols = []
    for x in range(W):
        c = 0
        for y in range(H):
            if px[x, y][3] > 40:
                c += 1
        cols.append(c)
    nz = [i for i, c in enumerate(cols) if c > 0]
    if not nz:
        return None
    a, b = nz[0], nz[-1]
    span = b - a + 1
    mx = max(cols) or 1
    q = max(1, int(span * 0.15))
    tip = (sum(cols[a:a + q]) / q + sum(cols[b - q + 1:b + 1]) / q) / 2.0
    front = sum(cols[b - q + 1:b + 1]) / q
    filled = sum(cols)
    fill = filled / float(span * H)

    hot = 0
    warm = 0
    tot = 0
    for x in range(W):
        for y in range(H):
            r, g, bl, al = px[x, y]
            if al < 40:
                continue
            tot += 1
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, bl / 255.0)
            if s < 0.30 and v > 0.80:
                hot += 1
            if 0.03 < h < 0.14 and s > 0.45 and v > 0.55:
                warm += 1

    # ── 像素风指标(用户 2026-08-29:「和我给你的参考图做到一模一样**加像素风**」)──
    #   ① 调色板要收敛(像素画是有限色, 不是连续渐变)
    #   ② alpha 要硬(基本只有全透/全不透, 中间值少 ⇒ 没有羽化软边)
    ## ★★色数要【逐帧】数再取最大, 不能数整张 sheet。
    ##   2026-08-29 我把量法从"中间一帧"改成"整张 sheet"之后, 色数自然从
    ##   ~60 涨到 ~105(九帧的色并集), 而阈值 PAL_MAX 还是按**单帧**定的
    ##   ⇒ PixelLab 原图被判"不像素风"。判据自己造出来的假问题,
    ##   而我上一次就是照着这种假问题把好素材改坏的。
    _nfr = max(1, W // H) if W > H and W % H == 0 else 1
    _fw = W // _nfr
    pal_max_fr = set()
    soft_a = 0
    for k in range(_nfr):
        pal_k = set()
        for x in range(k * _fw, (k + 1) * _fw):
            for y in range(H):
                r, g, bl, al = px[x, y]
                if al == 0:
                    continue
                pal_k.add((r >> 3, g >> 3, bl >> 3))   # 量化到 5bit/通道再数
                if 40 < al < 215:
                    soft_a += 1
        if len(pal_k) > len(pal_max_fr):
            pal_max_fr = pal_k
    pal = pal_max_fr

    # 丝股数: 数"透明→不透明"的上升沿。
    # ★★【两个方向都数、取大的】—— 只沿横向数是**方向相关**的:
    #   丝如果是横着的(剑气波就是), 每行只会数到 1, 判据就把好素材判成"丝股不够"。
    #   我第一版就是这么误判的。丝丝分开这件事与方向无关, 判据也不该相关。
    def _runs_along(horizontal):
        acc = []
        outer = range(0, H, 2) if horizontal else range(0, W, 2)
        inner = range(W) if horizontal else range(H)
        for o in outer:
            cnt = 0
            prev = False
            for i in inner:
                cur = (px[i, o][3] > 40) if horizontal else (px[o, i][3] > 40)
                if cur and not prev:
                    cnt += 1
                prev = cur
            if cnt > 0:
                acc.append(cnt)
        acc.sort()
        return acc[len(acc) // 2] if acc else 0
    strands = max(_runs_along(True), _runs_along(False))

    # ★★"不许太规则": 逐行量【每段连续不透明的长度】, 看它们参不参差。
    #   规则点阵(我第一版沿 x 每 7px 切一刀)也能满足"丝股数"这一条 —— 实拍看着像纱窗。
    #   真的丝是**沿流向连续的长丝**、长短不一 ⇒ 段长的变异系数要够大。
    def _seglens(horizontal):
        acc = []
        outer = range(0, H, 2) if horizontal else range(0, W, 2)
        inner = range(W) if horizontal else range(H)
        for o in outer:
            run = 0
            for i in inner:
                on = (px[i, o][3] > 40) if horizontal else (px[o, i][3] > 40)
                if on:
                    run += 1
                elif run:
                    acc.append(run); run = 0
            if run:
                acc.append(run)
        return acc
    # ★取"沿丝方向"那一侧: 丝是长的, 所以平均段长大的那个方向就是丝的方向
    # ★★"间距也要参差": 等间距的丝 = 扫描线/条码, 实拍一眼就看出来是机器画的。
    #   我第一版丝的间距是固定周期 3px, 段长判据全过, 屏幕上却是一排等距横线。
    #   ⇒ 量【缝隙的长度】分布, 变异系数太小就是等距。
    def _gaplens(horizontal):
        acc = []
        outer = range(0, H, 2) if horizontal else range(0, W, 2)
        inner = range(W) if horizontal else range(H)
        for o in outer:
            run = 0
            started = False
            for i in inner:
                on = (px[i, o][3] > 40) if horizontal else (px[o, i][3] > 40)
                if on:
                    started = True
                    if run:
                        acc.append(run); run = 0
                elif started:
                    run += 1
        return acc
    ga, gb = _gaplens(True), _gaplens(False)
    gaps = ga if len(ga) >= len(gb) else gb
    if gaps:
        gmu = sum(gaps) / float(len(gaps))
        gvar = sum((v - gmu) ** 2 for v in gaps) / float(len(gaps))
        gcv = (gvar ** 0.5) / max(1e-6, gmu)
    else:
        gcv = 0.0

    # ★★"丝要有厚度": 逐行处理只能产出 **1 像素高的直线** —— 屏幕上就是一排横线,
    #   而参考里的丝有 2~4px 厚、沿扇形辐射、带弧度。
    #   ⇒ 量【垂直于丝方向】的平均段长 = 丝的粗细。
    def _mean(a):
        return sum(a) / float(len(a)) if a else 0.0
    _ma, _mb = _mean(_seglens(True)), _mean(_seglens(False))
    # 丝的方向 = 平均段长大的那一侧; 厚度 = 另一侧
    thick = _mb if _ma >= _mb else _ma

    sa, sb = _seglens(True), _seglens(False)
    ma = sum(sa) / float(len(sa)) if sa else 0.0
    mb = sum(sb) / float(len(sb)) if sb else 0.0
    seglens = sa if ma >= mb else sb
    if seglens:
        mu = sum(seglens) / float(len(seglens))
        var = sum((v - mu) ** 2 for v in seglens) / float(len(seglens))
        cv = (var ** 0.5) / max(1e-6, mu)
    else:
        mu, cv = 0.0, 0.0

    # ★★"前缘必须是弯的"(用户 2026-08-29 点名:「剑气…前部分是弯的」)。
    #   量法: 逐行取最右的不透明像素 = 前缘轮廓; 看**中间比上下两端凸出多少**。
    #   直边 ≈ 0, 外凸弧 > 0。我第一版实测只凸 5px(128px 宽的图里约等于直的)。
    ## ★★必须【逐帧】量。横排 sheet 上按整张取"每行最右"只会拿到**最后一帧**的
    ##   轮廓(前面八帧全被遮住) ⇒ 读数没意义。我第一版就是这么写的, 报回 -1%。
    nfr = max(1, W // H) if W > H and W % H == 0 else 1
    fwid = W // nfr
    bl_acc, wd_acc = [], []
    for k in range(nfr):
        x0 = k * fwid
        prof_r, wid = [], []
        for y in range(H):
            xs2 = [x for x in range(x0, x0 + fwid) if px[x, y][3] > 40]
            if xs2:
                prof_r.append(max(xs2) - x0)
        if len(prof_r) < 9:
            continue
        q = max(1, len(prof_r) // 5)
        mid_i = len(prof_r) // 2
        bl_acc.append(sum(prof_r[mid_i - 2:mid_i + 3]) / 5.0
                      - (sum(prof_r[:q]) / q + sum(prof_r[-q:]) / q) / 2.0)
        ## ★“扇形”指标: 后五分之一的高度 / 前五分之一的高度。
        ##   扇面 ≈ 0.2以下(尾部收成尖); 圆坨/矩形 ≈ 1。
        for a, b in ((0, fwid // 5), (fwid - fwid // 5, fwid)):
            ys2 = [y for y in range(H) for x in range(x0 + a, x0 + b) if px[x, y][3] > 40]
            wid.append((max(ys2) - min(ys2)) if len(ys2) > 4 else 0)
        if wid[1] > 4:
            wd_acc.append(wid[0] / float(wid[1]))
    bulge = sum(bl_acc) / len(bl_acc) if bl_acc else 0.0
    wedge = sum(wd_acc) / len(wd_acc) if wd_acc else 1.0

    # ★"过曝白板"指标: 极低饱和 + 极亮 的像素占比。
    #   剑气波第一版右边那块就是它 —— 一整片纯白, 屏上读成一块方板。
    #   这是**能指出具体缺陷**的判据; 而"填充率上限"那种是我拍脑袋的, 已撤。
    slab = 0
    for x in range(W):
        for y in range(H):
            r, g, bl, al = px[x, y]
            if al < 40:
                continue
            h, s2, v2 = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, bl / 255.0)
            if s2 < 0.16 and v2 > 0.90:
                slab += 1

    vlist = []
    for x in range(W):
        for y in range(H):
            r, g, bl, al = px[x, y]
            if al < 40:
                continue
            vlist.append(colorsys.rgb_to_hsv(r / 255.0, g / 255.0, bl / 255.0)[2])
    vlist.sort()
    bright = vlist[len(vlist) // 2] if vlist else 0.0

    return {
        "bright": bright, "slab": slab / float(max(1, tot)),
        "bulge": bulge / float(max(1, H)), "wedge": wedge,
        "span": span, "max": mx, "tip": tip,
        "taper": tip / float(mx), "front": front / float(mx),
        "fill": fill, "hot": hot / float(max(1, tot)),
        "warm": warm / float(max(1, tot)), "strands": strands,
        "pal": len(pal), "soft": soft_a / float(max(1, tot)),
        "seg_mu": mu, "seg_cv": cv, "gap_cv": gcv, "thick": thick,
    }


def main():
    fails = []
    print("  [分母] 逐张量形态 —— 判据来自用户参考图(见文件头注)")
    n_checked = 0
    for fn, spec in SPEC.items():
        p = os.path.join(VFX, fn)
        if not os.path.exists(p):
            fails.append("%s 不存在" % fn)
            continue
        pr = profile(p)
        if pr is None:
            fails.append("%s 整张全透明" % fn)
            continue
        n_checked += 1
        print("  %-12s 收尖 %.2f · 填充 %.0f%% · 白热 %.0f%% · 丝股 %d · 前缘 %.2f · 暖屑 %.1f%% · 色数 %d · 软边 %.0f%% · 段长 %.1f±cv%.2f · 缝cv%.2f · 丝厚%.1f · 白板%.0f%% · 前缘凸%.0f%% · 尾/前%.2f"
              % (spec["label"], pr["taper"], 100 * pr["fill"], 100 * pr["hot"],
                 pr["strands"], pr["front"], 100 * pr["warm"], pr["pal"], 100 * pr["soft"], pr["seg_mu"], pr["seg_cv"], pr["gap_cv"], pr["thick"], 100 * pr["slab"], 100 * pr["bulge"], pr["wedge"]))
        if "taper_max" in spec and pr["taper"] > spec["taper_max"]:
            fails.append("%s 收尖不够: %.2f > %.2f(参考是厚身急剧收成针尖)"
                         % (spec["label"], pr["taper"], spec["taper_max"]))
        if "fill_max" in spec and pr["fill"] > spec["fill_max"]:
            fails.append("%s 太实心: 填充 %.0f%% > %.0f%%(参考是丝丝分开、大量留空)"
                         % (spec["label"], 100 * pr["fill"], 100 * spec["fill_max"]))
        if "hot_min" in spec and pr["hot"] < spec["hot_min"]:
            fails.append("%s 没有白热刀锋: %.0f%% < %.0f%%(参考是白热核心与高饱和身强反差)"
                         % (spec["label"], 100 * pr["hot"], 100 * spec["hot_min"]))
        if "hot_max" in spec and pr["hot"] > spec["hot_max"]:
            fails.append("%s 白热糊成一片: %.0f%% > %.0f%%"
                         % (spec["label"], 100 * pr["hot"], 100 * spec["hot_max"]))
        if "strands_min" in spec and pr["strands"] < spec["strands_min"]:
            fails.append("%s 丝股不够: %d < %d(参考是一笔里多缕重叠 / 大量分开的细丝)"
                         % (spec["label"], pr["strands"], spec["strands_min"]))
        if "front_max" in spec and pr["front"] > spec["front_max"]:
            fails.append("%s 前缘是实心板: 末端/最厚 %.2f > %.2f(参考是散成须)"
                         % (spec["label"], pr["front"], spec["front_max"]))
        # ★像素风: 全仓通用判据(不分张)
        if pr["pal"] > PAL_MAX:
            fails.append("%s 不像素风: 单帧最大色数 %d > %d(像素画是有限色板, 不是连续渐变)"
                         % (spec["label"], pr["pal"], PAL_MAX))
        if pr["soft"] > SOFT_MAX:
            fails.append("%s 不像素风: 软边 %.0f%% > %.0f%%(像素画硬边, alpha 基本只有全透/全不透)"
                         % (spec["label"], 100 * pr["soft"], 100 * SOFT_MAX))
        if "thick_min" in spec and pr["thick"] < spec["thick_min"]:
            fails.append("%s 丝太细(1px 横线): 厚度 %.1f < %.1f px(参考的丝有 2~4px 厚)"
                         % (spec["label"], pr["thick"], spec["thick_min"]))
        if "fill_min" in spec and pr["fill"] < spec["fill_min"]:
            fails.append("%s 太稀(只剩几根线): 填充 %.0f%% < %.0f%%(参考整体仍是一片, 只是丝间有缝)"
                         % (spec["label"], 100 * pr["fill"], 100 * spec["fill_min"]))
        if "gap_cv_min" in spec and pr["gap_cv"] < spec["gap_cv_min"]:
            fails.append("%s 丝的【间距】太均匀(像扫描线): 缝长变异 %.2f < %.2f"
                         % (spec["label"], pr["gap_cv"], spec["gap_cv_min"]))
        if "cv_min" in spec and pr["seg_cv"] < spec["cv_min"]:
            fails.append("%s 太规则(像纱窗): 段长变异系数 %.2f < %.2f(真的丝长短参差, 不是等长点阵)"
                         % (spec["label"], pr["seg_cv"], spec["cv_min"]))
        if "seg_mu_min" in spec and pr["seg_mu"] < spec["seg_mu_min"]:
            fails.append("%s 丝被剁碎了: 平均段长 %.1f < %.1f px(丝应沿流向连续)"
                         % (spec["label"], pr["seg_mu"], spec["seg_mu_min"]))
        if "bulge_min" in spec and pr["bulge"] < spec["bulge_min"]:
            fails.append("%s 前缘是【直的】: 中间只比两端凸出 %.0f%% 图宽 < %.0f%%(参考里前缘是一道外凸的弧)"
                         % (spec["label"], 100 * pr["bulge"], 100 * spec["bulge_min"]))
        if "wedge_max" in spec and pr["wedge"] > spec["wedge_max"]:
            fails.append("%s 不是【扇形】: 尾宽/前宽 %.2f > %.2f(圆坨是 1, 扇面从一点张开应 ≪1)"
                         % (spec["label"], pr["wedge"], spec["wedge_max"]))
        if "slab_max" in spec and pr["slab"] > spec["slab_max"]:
            fails.append("%s 有大片过曝白板: %.0f%% > %.0f%%(屏上读成一块方板)"
                         % (spec["label"], 100 * pr["slab"], 100 * spec["slab_max"]))
        if "bright_min" in spec and pr["bright"] < spec["bright_min"]:
            fails.append("%s 太暗(读成一条暗线): 中位亮度 %.2f < %.2f(激光是发光体)"
                         % (spec["label"], pr["bright"], spec["bright_min"]))
        if "warm_min" in spec and pr["warm"] < spec["warm_min"]:
            fails.append("%s 没有橙色火星: %.1f%% < %.1f%%"
                         % (spec["label"], 100 * pr["warm"], 100 * spec["warm_min"]))

    ## ══ 斩击的【张角 = 判定锥】: 演出即判定 ═════════════════
    ##
    ## ★用户 2026-08-29 在图上标蓝点定下了圆心 = **弧所在圆的圆心**(挥剑的转轴)。
    ##   绕这个点量, 横斩/竖斩两张的张角必须**等于各自的判定锥**(120 / 60)。
    ## ★期望值写死在这里, 不读生成器的常量 —— 否则改生成器时两边一起变, 永远绿。
    ##   (本会话已经因为"判据迭代产品自己的常量"翻过两次。)
    ## ★★两张图的圆心**不在同一个位置** —— 竖斩那张生成时已经旋转+挪到了左下角,
    ##   好让它的直边水平贴地。拿错圆心量出来的张角是别人的(实测会报 90°)。
    ## ★两张都是 120°: 横斩的 120° = 地面判定锥; 竖斩的 120° = 竖直平面里的挥剑弧
    ##   (从举过头顶砍到地面), 不是地面锥 —— 两者本来不是同一个东西。
    ## ★只量横斩那张的张角 —— 它是地面扇形, 张角就是判定锥。
    ## ★竖斩换成了 2026-08-29 **新生成**的 eq084-chop.png: 它是【新月形刀光】,
    ##   没有"从圆心张开多少度"这回事 ⇒ 拿张角去量它是拿错尺子。
    ##   它自己的判据在下面单独一段(落地点稳不稳 + 真的会消散)。
    for fn, want, PIVOT in (("eq084-slash-wide.png", 120.0, (0.664, 0.728)),):
        fp = os.path.join(VFX, fn)
        if not os.path.exists(fp):
            fails.append("%s 不存在" % fn)
            continue
        im = Image.open(fp).convert("RGBA")
        px2 = im.load()
        Hf = im.height
        nf = max(1, im.width // Hf)
        spans = []
        for k in range(nf):
            gx, gy = PIVOT[0] * Hf, PIVOT[1] * Hf
            ## ★角度要用【帧内坐标】算。我第一版直接拿了 sheet 的绝对 x,
            ##   于是第 k 帧的 x 大出一大截, 所有角度全塌到 0 附近 ⇒ 报 26 度。
            a = sorted(math.degrees(math.atan2(y - gy, (x - k * Hf) - gx))
                       for y in range(Hf)
                       for x in range(k * Hf, (k + 1) * Hf)
                       if px2[x, y][3] > 40)
            if len(a) < 200:
                continue
            ## 量【几何全张】(含所有质量的最小弧), 不是 90% 分位 ——
            ## 楞形是被硬裁过的, 全张就该正好等于判定锥。
            N = len(a)
            best = None
            for i in range(N):
                j = (i + N - 1) % N
                w = a[j] - a[i] if j > i else a[j] + 360.0 - a[i]
                if best is None or w < best:
                    best = w
            spans.append(best)
        if not spans:
            fails.append("%s 一帧有效内容都没有(N=0 是空检查)" % fn)
            continue
        got = sum(spans) / len(spans)
        print("  %-26s 绕圆心张角 %.0f 度 (写死期望 %.0f) · 量了 %d 帧"
              % (fn, got, want, len(spans)))
        if abs(got - want) > 10.0:
            fails.append("%s 张角 %.0f 度 ≠ 判定锥 %.0f 度 —— 演出承诺的和打得到的不一样"
                         % (fn, got, want))

    ## ══ 竖斩新素材 eq084-chop.png 的判据 ═════════════════════
    ## ★它是一张【下劈到地】的新月刀光。两条它真正承诺的事:
    ##   ① 落地点逐帧不漂 —— 漂了就是"刀在地上滑"
    ##   ② 真的会消散 —— 末帧实心度必须远小于首帧(否则刀光挂在那不动)
    fp = os.path.join(VFX, "eq084-chop.png")
    if not os.path.exists(fp):
        fails.append("eq084-chop.png 不存在")
    else:
        im = Image.open(fp).convert("RGBA")
        px2 = im.load()
        Hf = im.height
        nf = max(1, im.width // Hf)
        cont = []
        fill = []
        for k in range(nf):
            pts = [(x - k * Hf, y) for y in range(Hf)
                   for x in range(k * Hf, (k + 1) * Hf) if px2[x, y][3] > 40]
            fill.append(len(pts) / float(Hf * Hf))
            if len(pts) < 80:
                continue
            ymax = max(p[1] for p in pts)
            lo = [p[0] for p in pts if p[1] >= ymax - 2]
            cont.append((sum(lo) / float(len(lo)) / Hf, ymax / float(Hf)))
        if len(cont) < 5:
            fails.append("eq084-chop.png 有内容的帧只有 %d(N=0 是空检查)" % len(cont))
        else:
            sx = max(c[0] for c in cont) - min(c[0] for c in cont)
            sy = max(c[1] for c in cont) - min(c[1] for c in cont)
            print("  %-26s 落地点漂移 x %.3f / y %.3f · 实心度 首%.0f%% → 末%.0f%% · 量了 %d 帧"
                  % ("eq084-chop.png", sx, sy, 100 * fill[0], 100 * fill[-1], len(cont)))
            ## ★★只管【纵向】。横向漂移是刀扫过去、拖影往前散 —— 本来就该有。
            ##   用户 2026-08-29 拿 Aseprite 改完说"竖劈就这样", 实测横向 0.204,
            ##   而我原来拍的上限是 0.10 ⇒ 按那个数就得把他定稿的刀改回去。
            ##   阈值错不是"判据太松", 是**主动把好的推向坏的**(memory
            ##   [[fb-my-thresholds-degrade-good-assets]])。横向只留一个兵底(整张滑过去才管)。
            if sy > 0.04:
                fails.append("eq084-chop.png 刀尖【纵向】在漂 y %.3f > 0.04 —— 刀会浮离地面"
                             % sy)
            if sx > 0.45:
                fails.append("eq084-chop.png 刀尖横向滑了半张图 x %.3f > 0.45" % sx)
            if fill[-1] > fill[0] * 0.25:
                fails.append("eq084-chop.png 没消散: 末帧实心度 %.0f%% 不到首帧 %.0f%% 的四分之一"
                             % (100 * fill[-1], 100 * fill[0]))

    print("  [分母] 真的量了 %d 张(N=0 是空检查不是通过)" % n_checked)
    if n_checked < 4:
        fails.append("只量到 %d 张, 应该是 4 张" % n_checked)
    for f in fails:
        print("  [FAIL] " + f)
    if fails:
        print("")
        print("FAILED: %d 条没达到参考" % len(fails))
        return 1
    print("")
    print("ALL OK — 四张素材都达到参考图的形态指标")
    return 0


if __name__ == "__main__":
    sys.exit(main())
