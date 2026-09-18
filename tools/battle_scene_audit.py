# -*- coding: utf-8 -*-
"""battle_scene_audit.py — 量一张【战斗场景实拍图】的画面指标。

由来(2026-09-18): 用户「现在战斗内的背景很烂」。对标 30 款同类型好游戏后定了五条规律
(见 docs/plans/20260918-战斗场景美术重做.md)。这个脚本是那份方案书验收清单的**活事实源** ——
方案书里不许手抄数字(plans_lint 会红: 「手抄的数字必然落后」), 一律指到这里读。

★为什么要量而不是看: memory `fb-my-thresholds-degrade-good-assets` —— 我拍的阈值会把好素材改坏;
  memory `fb-color-criteria-need-clean-background` —— 目测时长/颜色都不算数。
  改完场景必须重跑这个脚本比数字, 不许靠眼睛说"好多了"。

量什么(每条都对应方案书里的一条规律):
  ① 明度分位 + 中间调占比 —— 规律⑤。本项目的病不是"颜色打架"是【明度双峰·中间空】:
     改前实测 p50=50 / p75=135, 中间空了 85; 明度 60~130 的中间调占比≈0。
  ② 四角 vs 中心明度 —— 规律④ 边缘压暗有没有真的生效。
  ③ 主色集中度 —— 前 3 色占多少面积, 太高说明画面被几块大色斑统治。

跑法:
    python tools/battle_scene_audit.py <战场实拍.png> [--json]
    # 实拍怎么来: SHIP=1 SELFSHOT=7 SHOT_OUT=<png> <godot> --path . res://scenes/RealtimeBattle3D.tscn

★★裁剪口径要固定, 否则前后两次量的不是同一块地方:
  默认去掉左右两侧队伍面板(各 185px)与顶部血条(60px), 按 1280×720 的版式定的。
  换分辨率要按比例传 --pad。
"""
import argparse
import json
import os
import sys
from collections import Counter

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("需要 Pillow: pip install pillow")
    sys.exit(2)

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

MID_LO, MID_HI = 60, 130          # "中间调"的定义, 与方案书验收项同一口径


def lum(r, g, b):
    return 0.299 * r + 0.587 * g + 0.114 * b


def audit(path, pad_lr=185, pad_top=60, pad_bot=10, step=2):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    # 按 1280 宽定的 pad, 换分辨率按比例缩
    k = W / 1280.0
    l, t = int(pad_lr * k), int(pad_top * k)
    r, b = W - int(pad_lr * k), H - int(pad_bot * k)
    if r - l < 50 or b - t < 50:
        print("★裁剪后几乎没内容了(%dx%d) —— pad 给大了" % (r - l, b - t))
        return None
    crop = im.crop((l, t, r, b))
    px = crop.load()

    vals, cnt = [], Counter()
    for y in range(0, crop.height, step):
        for x in range(0, crop.width, step):
            c = px[x, y]
            vals.append(lum(*c))
            cnt[(c[0] // 16 * 16, c[1] // 16 * 16, c[2] // 16 * 16)] += 1
    vals.sort()
    n = len(vals)
    if n < 1000:
        print("★采样点只有 %d 个, 太少 —— step 调小或图太小" % n)
        return None

    def q(p):
        return vals[min(n - 1, int(n * p))]

    mid = sum(1 for v in vals if MID_LO <= v <= MID_HI)
    top3 = sum(c for _, c in cnt.most_common(3)) / float(sum(cnt.values()))

    # 四角 vs 中心: 各取 12% 边长的方块
    def block_mean(cx, cy, fr=0.12):
        bw, bh = int(crop.width * fr), int(crop.height * fr)
        x0 = max(0, min(crop.width - bw, int(cx - bw / 2)))
        y0 = max(0, min(crop.height - bh, int(cy - bh / 2)))
        s, m = 0.0, 0
        for yy in range(y0, y0 + bh, 2):
            for xx in range(x0, x0 + bw, 2):
                s += lum(*px[xx, yy]); m += 1
        return s / max(1, m)

    center = block_mean(crop.width / 2, crop.height / 2)
    corners = [block_mean(crop.width * f1, crop.height * f2)
               for f1, f2 in ((0.08, 0.08), (0.92, 0.08), (0.08, 0.92), (0.92, 0.92))]
    corner_mean = sum(corners) / len(corners)

    out = {
        "file": os.path.basename(path),
        "size": [W, H],
        "crop": [crop.width, crop.height],
        "samples": n,
        "p5": round(q(0.05), 1), "p25": round(q(0.25), 1), "p50": round(q(0.50), 1),
        "p75": round(q(0.75), 1), "p95": round(q(0.95), 1),
        # ★这个"空档"就是本项目的病: 一半画面在暗带, 上四分位直接跳到亮带, 中间没东西
        "gap_p50_p75": round(q(0.75) - q(0.50), 1),
        "mid_tone_pct": round(100.0 * mid / n, 1),
        "center_lum": round(center, 1),
        "corner_lum": round(corner_mean, 1),
        "corner_vs_center_pct": round(100.0 * (1.0 - corner_mean / max(1e-6, center)), 1),
        "top3_color_pct": round(100.0 * top3, 1),
        # 有效色数: 16 级量化后【占到 0.1% 面积以上】的颜色数。
        # 只数"出现过"会被单像素噪点灌水, 所以要设面积门槛。
        "eff_colors": sum(1 for _k, v in cnt.items() if v >= n * 0.001),
        "top_colors": ["#%02x%02x%02x" % rgb for rgb, _c in cnt.most_common(6)],
    }
    return out


## ★★阈值是【拿 7 款已知好游戏标定出来的】, 不是我拍的。标定表(2026-09-18 实测):
##
##   参考(同类型好游戏)   暗部<40   中间调   有效色数   局部对比   前3色
##   云顶之弈              4.6%    50.2%     223      1.8      5.8%
##   金铲铲之战           16.6%    42.1%     208      1.7     15.1%
##   荒野乱斗              3.4%    46.1%     106      0.7     39.7%
##   Hades II            47.4%    24.3%     116      1.4     25.2%
##   SuperAutoPets        7.2%    44.5%      88      0.0     31.3%
##   CultOfTheLamb       13.1%    59.7%     174      4.3     10.3%
##   VampireSurvivors      -      41.2%     150      9.0       -
##   ──────────────────────────────────────────────────────────
##   本项目(改前)         39.0%    11.1%      70      1.8     25.5%
##
## ★这张表当场证伪了我凭眼睛列的三条"病"(照抄它们会把好画面改坏):
##   ✗「四角比中心暗≥25%」—— 本项目 56.8% PASS 而云顶只有 13% FAIL。方向是反的:
##      本项目边缘暗不是做了 vignette, 是四角本来就是黑色 void 地块(占 26%), 拿"空"冒充"压暗"。
##   ✗「暗部占比高 = 病」—— Hades II 暗部 47.4%, 比本项目的 39% 还暗, 而它是美术标杆。
##   ✗「局部对比度低 = 地面死平」—— 本项目 1.8, 云顶也是 1.8, SuperAutoPets 是 0.0(扁平色块风)。
##
## ⇒ 八个样本量下来只有两条既有区分度、方向又对, 阈值取【参考组的最低值】:
def verdict(a):
    """按方案书验收清单判。★阈值写在这里是【唯一】一份, 方案书指过来读, 不许两边各存一份。"""
    rules = [
        ("中间调(60~130)占比 ≥ 24%", a["mid_tone_pct"] >= 24.0, "%.1f%%" % a["mid_tone_pct"]),
        ("有效色数 ≥ 88", a["eff_colors"] >= 88, "%d" % a["eff_colors"]),
    ]
    return rules


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--pad", type=int, default=185, help="左右各去掉多少像素(按 1280 宽计)")
    args = ap.parse_args()
    if not os.path.exists(args.image):
        print("★找不到 %s" % args.image)
        return 2
    a = audit(args.image, pad_lr=args.pad)
    if a is None:
        return 2
    if args.json:
        print(json.dumps(a, ensure_ascii=False, indent=2))
        return 0
    print("== %s  %dx%d → 场地区 %dx%d  采样 %d 点 ==" % (
        a["file"], a["size"][0], a["size"][1], a["crop"][0], a["crop"][1], a["samples"]))
    print("明度分位  p5=%.0f  p25=%.0f  p50=%.0f  p75=%.0f  p95=%.0f" % (
        a["p5"], a["p25"], a["p50"], a["p75"], a["p95"]))
    print("主色 top6: %s" % " ".join(a["top_colors"]))
    print("有效色数 %d   前3色占 %.1f%%   四角/中心明度 %.0f/%.0f (差 %.1f%%)" % (
        a["eff_colors"], a["top3_color_pct"], a["corner_lum"], a["center_lum"], a["corner_vs_center_pct"]))
    print("  (上面这行只作参考不判定 —— 四角/前3色/暗部占比都被已知好样本证伪过, 见文件头标定表)")
    print()
    bad = 0
    for name, ok, got in verdict(a):
        print("  [%s] %-28s 实测 %s" % ("PASS" if ok else "FAIL", name, got))
        if not ok:
            bad += 1
    print()
    print("%d/%d 条达标" % (len(verdict(a)) - bad, len(verdict(a))))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
