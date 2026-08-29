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
    "eq084-slash.png": {
        "label": "斩击弧",
        "taper_max": 0.16,          # 厚身→针尖
        "fill_max": 0.34,           # 大量留空
        "hot_min": 0.06, "hot_max": 0.30,   # 白热刀锋要有, 但不能糊成一片白
        "strands_min": 2,           # 一笔里多缕重叠
    },
    "eq084-wave.png": {
        "label": "剑气波",
        "taper_max": 0.85,          # 波是扇面, 不要求收尖(但前缘不能是最厚处 → 见 front_max)
        "fill_max": 0.30,           # ★最关键: 丝丝分开、完全通透
        "hot_min": 0.03, "hot_max": 0.25,
        "strands_min": 6,           # ★由大量分开的细丝组成
        "front_max": 0.75,          # 末端厚度 / 最厚处 —— 前缘不许是实心板
        "thick_min": 2.0,           # ★丝要有厚度 —— 逐行处理只能出 1px 横线
        "fill_min": 0.18,           # ★不许太稀 —— 参考整体仍是一片, 只是丝间有缝
        "gap_cv_min": 0.45,         # ★丝的【间距】也要参差 —— 等距 = 扫描线
        "cv_min": 0.55,             # ★段长要参差 —— 等长点阵看着像纱窗
        "seg_mu_min": 9.0,          # ★丝要沿流向连续, 不是被剁成一截截
    },
    "eq084-beam.png": {
        "label": "激光束",
        # 参考 = 云顶 S4 速射火炮 + 用户发的四张实拍图: **一条细的亮电弧线**
        "taper_max": 0.95,          # 束是通长的, 不要求收尖
        "fill_max": 0.85,
        "hot_min": 0.06, "hot_max": 0.32,   # ★白热芯要有(实拍第一版整条暗红, 读成一条暗线)
        "strands_min": 1,
        "bright_min": 0.55,         # ★中位亮度 —— 激光是发光体, 不能是暗线
    },
    "eq084-burst.png": {
        "label": "命中爆点",
        "taper_max": 0.30,          # 角状棱刺
        "fill_max": 0.40,
        "hot_min": 0.05, "hot_max": 0.35,
        "strands_min": 2,
        "warm_min": 0.01,           # 橙色火星碎屑
    },
}


def mid_frame(im):
    """横排 sheet 取中间一帧; 单帧原样返回。"""
    if im.width > im.height and im.width % im.height == 0:
        n = im.width // im.height
        k = n // 2
        return im.crop((im.height * k, 0, im.height * (k + 1), im.height))
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
    pal = set()
    soft_a = 0
    for x in range(W):
        for y in range(H):
            r, g, bl, al = px[x, y]
            if al == 0:
                continue
            pal.add((r >> 3, g >> 3, bl >> 3))     # 量化到 5bit/通道再数
            if 40 < al < 215:
                soft_a += 1

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
        "bright": bright,
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
        print("  %-12s 收尖 %.2f · 填充 %.0f%% · 白热 %.0f%% · 丝股 %d · 前缘 %.2f · 暖屑 %.1f%% · 色数 %d · 软边 %.0f%% · 段长 %.1f±cv%.2f · 缝cv%.2f · 丝厚%.1f"
              % (spec["label"], pr["taper"], 100 * pr["fill"], 100 * pr["hot"],
                 pr["strands"], pr["front"], 100 * pr["warm"], pr["pal"], 100 * pr["soft"], pr["seg_mu"], pr["seg_cv"], pr["gap_cv"], pr["thick"]))
        if pr["taper"] > spec["taper_max"]:
            fails.append("%s 收尖不够: %.2f > %.2f(参考是厚身急剧收成针尖)"
                         % (spec["label"], pr["taper"], spec["taper_max"]))
        if pr["fill"] > spec["fill_max"]:
            fails.append("%s 太实心: 填充 %.0f%% > %.0f%%(参考是丝丝分开、大量留空)"
                         % (spec["label"], 100 * pr["fill"], 100 * spec["fill_max"]))
        if pr["hot"] < spec["hot_min"]:
            fails.append("%s 没有白热刀锋: %.0f%% < %.0f%%(参考是白热核心与高饱和身强反差)"
                         % (spec["label"], 100 * pr["hot"], 100 * spec["hot_min"]))
        if pr["hot"] > spec["hot_max"]:
            fails.append("%s 白热糊成一片: %.0f%% > %.0f%%"
                         % (spec["label"], 100 * pr["hot"], 100 * spec["hot_max"]))
        if pr["strands"] < spec["strands_min"]:
            fails.append("%s 丝股不够: %d < %d(参考是一笔里多缕重叠 / 大量分开的细丝)"
                         % (spec["label"], pr["strands"], spec["strands_min"]))
        if "front_max" in spec and pr["front"] > spec["front_max"]:
            fails.append("%s 前缘是实心板: 末端/最厚 %.2f > %.2f(参考是散成须)"
                         % (spec["label"], pr["front"], spec["front_max"]))
        # ★像素风: 全仓通用判据(不分张)
        if pr["pal"] > PAL_MAX:
            fails.append("%s 不像素风: 色数 %d > %d(像素画是有限色板, 不是连续渐变)"
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
        if "bright_min" in spec and pr["bright"] < spec["bright_min"]:
            fails.append("%s 太暗(读成一条暗线): 中位亮度 %.2f < %.2f(激光是发光体)"
                         % (spec["label"], pr["bright"], spec["bright_min"]))
        if "warm_min" in spec and pr["warm"] < spec["warm_min"]:
            fails.append("%s 没有橙色火星: %.1f%% < %.1f%%"
                         % (spec["label"], 100 * pr["warm"], 100 * spec["warm_min"]))

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
