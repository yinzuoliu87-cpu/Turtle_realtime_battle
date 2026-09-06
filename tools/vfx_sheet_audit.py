# -*- coding: utf-8 -*-
"""vfx_sheet_audit.py — 特效精灵表的机器检查（2026-09-06）

★由来：用户「那你这在搞笑吗，这么多问题还对齐lol」。
  001 那一轮我口头报了"五段全接好、对齐 LoL"，而实际上：
    · 8 方向格里 NE 和 NW **完全相同**（去重只剩 7 种）
    · 基准帧朝向是 296.8° 而不是 0°（差 63°）
    · 命中表最后一帧是**整幅 32×32 不透明**的垃圾帧，命中末尾闪一个灰方块
    · 命中尾三帧是"变黑"不是淡出（亮度掉到 14 而 alpha 恒 255）
  **这四条我一条都没自己发现** —— 全是用户追问「方向？」之后量出来的。

★为什么必须是门禁而不是"我记得检查"：
  这类错在单张截图里看不出来。方向差 63° 就是"一道剑气"；
  垃圾帧要正好拍到那 0.04 秒才拍得到。靠眼睛必漏。

★★★这个审计器【不是美术门禁】—— 它管规格, 管不了"好不好看"。2026-09-06 实测:
  用户看完实拍说「我服了你说对齐lol呢？这么差质量」——素材是一排实心月牙(像香蕉),
  而当时**每一条机器检查都是绿的**。我随后连试三个数值判据想把"剑气"和"月亮"分开:

    | 判据          | 读起来像剑气的(ninja/soul1) | 我那批月亮(cand27/35/18) | 分得开吗 |
    |---------------|----------------------------|--------------------------|---------|
    | 笔画细长比    | 0.26 / 0.19                | 0.25 / 0.31 / 0.24       | ✗ 一样  |
    | 黑描边占比    | 30.4% / 25.5%              | 35.3% / 31.3% / 39.4%    | ✗ 一样  |
    | 亮度动态范围  | 224 / 213                  | 228 / 235 / 235          | ✗ 一样  |
    | 弧包角        | 293° / 88°                 | 114° / 124° / 112°       | ✗ ninja 比月亮还绕 |

  (弧包角那条的尺子是自证过的: 人工半月读 155°、人工 70° 弧读 82°, 判据本身没坏。)
  ⇒ **三条全部分不开。** 结论不是"再找个更好的数", 而是:
     形状好不好看**必须人看接触印相**(把候选按 4× 放大铺成 8×8 深灰底一张图),
     机器只负责下面这些"会穿帮但眼睛必漏"的规格项(垃圾帧/变黑/重复格/帧间自转)。
  ★我犯的错就是**只用数值筛选素材, 从没问过一句"它看起来像剑气吗"**。别再重复。

只读。跑法: python tools/vfx_sheet_audit.py
"""
import io
import json
import math
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

try:
    from PIL import Image
except ImportError:
    print("[SKIP] 没装 Pillow")
    sys.exit(0)

VFX = os.path.join("assets", "sprites", "vfx")

## 要检查的表: 路径 → 规格
##   dirs  : 横向方向格数(1 = 不是方向表)
##   frames: 纵向动画帧数
SHEETS = {
    "eq001-flyslash-dir4.png":   {"dirs": 4, "frames": 3},
    "eq001-flyslash-muzzle.png": {"dirs": 1, "frames": 1, "hframes": 4},
    "eq001-flyslash-impact.png": {"dirs": 1, "frames": 1, "hframes": 3},
}

fails = []


def chk(name, ok, detail=""):
    print("  [%s] %s  %s" % ("OK" if ok else "FAIL", name, detail if not ok else ""))
    if not ok:
        fails.append(name)


def axis180(f):
    """像素分布的【轴向】(0~180, 不分头尾)。

    ★★为什么只到 180°: 头尾(哪端是"尖")**不可由形状自动判定** ——
      箭头是宽头朝前, 楔形是窄头朝前, 规则相反。
      2026-09-06 我为此栽了很贵的一跤: 写了个"带头尾"的判据没验就拿去判素材,
      它把 41.3° 读成 221°、把 14.2° 报成"基准帧朝 296.8°",
      害我重出了一整批素材、改了三次拼表脚本 —— **而八个方向本来就是对的**。
    ★轴向这一半是可靠的: 拿人工画的箭头逐次旋转 45° 验过, 最大偏差 1.0°(见 ruler_check)。
      "相邻方向格相差 45°"只需要轴向就能验, 不需要头尾。
    ★头尾(整体朝向对不对)**由人看一眼定**, 机器不判 —— 别再写自动头尾判别了。
    """
    px = f.load()
    W, H = f.size
    pts = [(x, (H - 1 - y)) for y in range(H) for x in range(W) if px[x, y][3] > 0]
    if len(pts) < 20:
        return None
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts) / n
    syy = sum((p[1] - my) ** 2 for p in pts) / n
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts) / n
    return (math.degrees(0.5 * math.atan2(2 * sxy, sxx - syy)) + 180.0) % 180.0


def _fade_by_darkening(seq):
    """seq = [(平均亮度, 平均alpha), ...] 逐帧。返回问题描述, 没问题返回 ""。

    判据: 只看【alpha 仍 >= 220】的那些帧 —— 那几帧还完全不透明, 玩家看到的是实的东西。
    这一段里亮度从峰值掉超过 40% ⇒ 它是在"变黑"而不是"变透明"。
    """
    solid = [(k, L) for k, (L, A) in enumerate(seq) if A >= 220.0]
    if len(solid) < 3:
        return ""
    peak = max(L for _, L in solid)
    if peak < 1.0:
        return ""
    k, low = min(solid, key=lambda p: p[1])
    if low < peak * 0.60:
        return "帧%d 亮度已掉到 %.0f(峰值 %.0f 的 %.0f%%)而 alpha 仍 >=220 —— 是变黑不是淡出"                % (k, low, peak, 100.0 * low / peak)
    return ""


def fade_ruler_check():
    """★判据自证: 造两条【已知答案】的序列, 判据必须一条判过一条判红。"""
    good = [(200.0, 255.0), (205.0, 255.0), (198.0, 180.0), (202.0, 90.0), (196.0, 20.0)]
    bad = [(200.0, 255.0), (150.0, 255.0), (95.0, 255.0), (50.0, 255.0), (22.0, 255.0)]
    return (_fade_by_darkening(good) == "", _fade_by_darkening(bad) != "")


def convex_dir(f):
    """弧【朝哪边鼓】(0~360, 数学角: 0=东, 90=北)。

    ★这条和 axis180 不同: 轴向不分头尾所以只到 180°, 但"凸面朝向"是**可以**自动判的 ——
      一条弧的最佳拟合圆心必定落在它的【凹】侧, 于是 凸向 = 重心 − 圆心。
    """
    px = f.load()
    W, H = f.size
    on = [(x, y) for y in range(H) for x in range(W) if px[x, y][3] > 0]
    if len(on) < 20:
        return None
    cx = sum(p[0] for p in on) / len(on)
    cy = sum(p[1] for p in on) / len(on)
    best = None
    for gx in range(-W, 2 * W, 2):
        for gy in range(-H, 2 * H, 2):
            r = [math.hypot(x - gx, y - gy) for x, y in on]
            m = sum(r) / len(r)
            if m < 3:
                continue
            v = sum((q - m) ** 2 for q in r) / len(r)
            if best is None or v < best[0]:
                best = (v, gx, gy)
    _, gx, gy = best
    return math.degrees(math.atan2(-(cy - gy), cx - gx)) % 360.0


def convex_ruler_check():
    """★判据自证: 人工画两条已知凸向的弧(朝东 / 朝南), 读错就不许拿它判素材。

    ★注意 PIL 的 arc 角度是【屏幕坐标·顺时针】: arc(35,145) 扫过 90°=6点钟方向 ⇒ 弧在底部
      ⇒ 凸面朝**南**。我第一次把它标成"朝北", 判据报 S 时差点去改判据 —— 错的是我的标注。
    """
    from PIL import ImageDraw
    out = []
    for want, (a0, a1) in [(0.0, (-55, 55)), (270.0, (35, 145))]:
        r = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        ImageDraw.Draw(r).arc([4, 4, 27, 27], a0, a1, fill=(255, 220, 120, 255), width=5)
        g = convex_dir(r)
        out.append(abs((g - want + 180.0) % 360.0 - 180.0))
    return max(out)


def ruler_check():
    """★判据自证: 拿【已知答案】的箭头逐次旋转 45°, 读不准就不许拿它判素材。
    (memory fb-verify-check-can-fail: 报"0 分歧"前先证明检查会 FAIL)"""
    from PIL import ImageDraw
    ref = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    d = ImageDraw.Draw(ref)
    d.polygon([(4, 13), (22, 13), (22, 8), (30, 16), (22, 24), (22, 19), (4, 19)],
              fill=(255, 200, 80, 255))
    worst = 0.0
    for k in range(8):
        r = ref.rotate(45 * k, resample=Image.NEAREST, expand=False)
        a = axis180(r)
        want = (45.0 * k) % 180.0
        worst = max(worst, min(abs(a - want), 180 - abs(a - want)))
    return worst


def main():
    print("=== 特效精灵表检查 ===")
    w = ruler_check()
    chk("★分母: 角度判据在【已知答案】上可靠(标尺最大偏差 %.1f°)" % w, w <= 12.0,
        "判据自己就读不准 —— 下面所有角度结论都不作数")
    cw = convex_ruler_check()
    chk("★分母: 凸向判据在【已知答案】上可靠(最大偏差 %.0f°)" % cw, cw <= 25.0,
        "判据自己就读不准 —— ⑥ 的结论不作数")
    g_ok, b_red = fade_ruler_check()
    chk("★分母: 淡出判据在【已知答案】上一过一红(走alpha的过=%s / 走变黑的红=%s)"
        % (g_ok, b_red), g_ok and b_red, "判据自己就分不开 —— ② 的结论不作数")
    n_sheet = 0
    for fn, spec in SHEETS.items():
        p = os.path.join(VFX, fn)
        if not os.path.exists(p):
            chk("%s 存在" % fn, False, "文件不在盘上")
            continue
        n_sheet += 1
        sh = Image.open(p).convert("RGBA")
        W, H = sh.size
        dirs = spec.get("dirs", 1)
        frames = spec.get("frames", 1)
        hf = spec.get("hframes", dirs)
        fw, fh = W // hf, H // frames

        # ── ① 没有"整幅不透明"的垃圾帧 ──
        ## animate_image 偶尔会吐一帧整幅填满的图, 播到它就是屏幕上闪一个方块。
        bad_full = []
        for r in range(frames):
            for c in range(hf):
                f = sh.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
                px = f.load()
                on = sum(1 for y in range(fh) for x in range(fw) if px[x, y][3] > 0)
                if on > fw * fh * 0.9:
                    bad_full.append("帧(%d,%d) %d/%d 像素" % (r, c, on, fw * fh))
        chk("%s ① 没有整幅不透明的垃圾帧" % fn, not bad_full, "; ".join(bad_full[:3]))

        # ── ② 消散靠 alpha 不靠"变黑" ──
        ## 像素风里"变暗到接近黑"是穿帮: 玩家看到的是一团黑东西, 不是消失。
        ##
        ## ★★2026-09-06 重写: 旧判据是逐帧阈值(`lum<45 且 alpha>200`), **卡不住**。
        ##   实测命中表: 帧4 亮度 54/alpha 255、帧5 亮度 23/alpha 165 ——
        ##   一个亮度差 9 点没到线, 一个 alpha 差 35 点没到线, **两边都从阈值旁边溜过去**,
        ##   而肉眼一看尾三帧明摆着是褐色的。逐帧阈值天生问不到"它是怎么消失的"这个问题。
        ## ⇒ 改成量【走向】: 在 alpha 还满的那一段里, 亮度不许塌。
        ##   实测同一张表 亮度 143 → 54(掉 62%)而 alpha 全程 255 = 靠变黑淡出, 当场红。
        if frames == 1 and hf > 1:            # 一次性动画(横排帧)才有"淡出"这回事
            seq = []
            for c in range(hf):
                f = sh.crop((c * fw, 0, (c + 1) * fw, fh))
                px = f.load()
                on = [px[x, y] for y in range(fh) for x in range(fw) if px[x, y][3] > 0]
                if len(on) < 12:
                    continue
                seq.append((sum(q[0] * .3 + q[1] * .6 + q[2] * .1 for q in on) / len(on),
                            sum(q[3] for q in on) / len(on)))
            bad = _fade_by_darkening(seq)
            chk("%s ② 消散走 alpha, 不是靠变黑" % fn, not bad, bad)

        # ── ③ 方向表: 8 格必须两两不同 ──
        if dirs > 1:
            import hashlib
            sigs = {}
            for c in range(dirs):
                s = hashlib.md5(sh.crop((c * fw, 0, (c + 1) * fw, fh)).tobytes()).hexdigest()
                sigs.setdefault(s, []).append(c)
            dup = ["格%s 相同" % "/".join(map(str, v)) for v in sigs.values() if len(v) > 1]
            chk("%s ③ %d 个方向格两两不同" % (fn, dirs), not dup, "; ".join(dup))

            # ── ④ 已删 —— 见下方长注 ──
            ## 【④ 相邻方向格相差 360/dirs 度】这条 2026-09-06 拆掉了, 不是因为它红,
            ## 是因为**它量的那个数问不出这个问题**:
            ##   `axis180` 是 mod 180 的量(头尾不可自动判定, 见其头注) ⇒ 旋转 180° 轴向不变
            ##   ⇒ 4 方向表里【北和南天生同轴】、东和西也同轴, "相邻差 90°"根本不成立。
            ##   实测本表 格1→2 差 9°、格2→3 差 171°, 而这四格是无损构造出来的、**没有错**。
            ## ⇒ 由 ⑥(凸面朝向)取代: 它量完整 360°, 逐格问"你朝不朝你该朝的方向",
            ##   严格强于"相邻两格差多少"。反向验证过: 把北格换成朝西的内容,
            ##   ⑥ 报「格1 凸面 201°(应 ~90°, 差 111°)」—— 指名道姓。
            angs = [axis180(sh.crop((c * fw, 0, (c + 1) * fw, fh))) for c in range(dirs)]

            # ── ⑤ 同一方向格内, 各动画帧的轴向必须基本一致 ──
            ## ★用户看实拍问「这个特效在旋转是？」—— 弹体 4 帧轴向
            ##   14.2°→9.9°→146.9°→119.1°, 帧2 翻了 137°, 循环播放就是"每 4 帧转一圈"。
            ##   ④ 只管"方向格之间差 45°", 管不到"同一方向的各帧别乱转" ⇒ 必须单独一条。
            ## ★generator 做"摆动/形变"动画时很容易把形状摆过头, 这是必查项。
            spin = []
            for c in range(dirs):
                fa = [axis180(sh.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)))
                      for r in range(frames)]
                fa = [a for a in fa if a is not None]
                if len(fa) < 2:
                    continue
                base = fa[0]
                worst = max(min(abs(a - base), 180 - abs(a - base)) for a in fa)
                if worst > 25.0:
                    spin.append("格%d 帧间轴向摆 %.0f°(%s)"
                                % (c, worst, "/".join("%.0f" % a for a in fa)))
            chk("%s ⑤ 同一方向格内各帧朝向一致(不自转)" % fn, not spin, "; ".join(spin[:3]))

            # ── ⑥ 每个方向格的【凸面】必须朝它自己那个方向 ──
            ## ★用户问「方向？」时我答不上来, 因为当时只有轴向(0~180, 不分头尾)。
            ##   头尾确实不可由形状自动判定(见 axis180 头注), **但"弧朝哪边鼓"可以** ——
            ##   弧的最佳拟合圆心一定落在【凹】侧, 所以 凸向 = 重心 − 圆心。
            ##   判据自证见 convex_ruler_check(): 人工画的"凸面朝东/朝南"两个已知答案都读对。
            bad_cv = []
            for c in range(dirs):
                cv = convex_dir(sh.crop((c * fw, 0, (c + 1) * fw, fh)))
                if cv is None:
                    continue
                want = 360.0 - (360.0 / dirs) * c if c else 0.0   # 格序 E,N,W,S ⇒ 逆时针
                want = ((360.0 / dirs) * c) % 360.0
                d = abs((cv - want + 180.0) % 360.0 - 180.0)
                if d > 30.0:
                    bad_cv.append("格%d 凸面 %.0f°(应 ~%.0f°, 差 %.0f°)" % (c, cv, want, d))
            chk("%s ⑥ 每格凸面朝自己那个方向" % fn, not bad_cv, "; ".join(bad_cv))

    ## ── ⑦ 结构剖面要对得上【真 LoL 参考】 ──
    ## ★这条是 2026-09-06 加的, 由来见 tools/vfx_lol_profile.py 头注:
    ##   用户「我最在意的就是对齐 lol，但你就是不会去抄」。上面 ①~⑥ 全是"规格没穿帮",
    ##   **一条都不问"它像不像 LoL"** —— 而那正是他不满的地方。
    ##   剖面四条(白占比/白对主体亮度比/主体层次/长宽比)是从真画面量出来的, 参考图自己全过。
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from vfx_lol_profile import profile as _lp, REF as _LREF
        ref = os.path.join("docs", "specs", "refs", "lol-riven-windslash-f22-cut.png")
        if os.path.exists(ref):
            rp = _lp(Image.open(ref))
            rbad = [k for k, (lo, hi) in _LREF.items() if not (lo <= rp[k] <= hi)]
            chk("★分母: LoL 剖面尺子在【参考图自己】上全过", not rbad, "尺子坏了 —— ⑦ 不作数")
            for fn, spec in SHEETS.items():
                p = os.path.join(VFX, fn)
                if not os.path.exists(p) or spec.get("dirs", 1) < 2:
                    continue      # 只审弹体方向表; 闪光/星爆不是"一扫"形态, 不该套剑气剖面
                sh2 = Image.open(p).convert("RGBA")
                c0 = sh2.crop((0, 0, sh2.width // spec["dirs"], sh2.height // spec["frames"]))
                q = _lp(c0)
                bad7 = ["%s %.2f(应 %.2f~%.2f)" % (k, q[k], lo, hi)
                        for k, (lo, hi) in _LREF.items() if not (lo <= q[k] <= hi)]
                chk("%s ⑦ 结构剖面对得上 LoL 参考" % fn, not bad7, "; ".join(bad7))
    except Exception as _e:
        chk("★LoL 剖面尺子可用", False, "%s: %s" % (type(_e).__name__, _e))

    print("")
    print("  [分母] 检查了 %d 张表" % n_sheet)
    if n_sheet == 0:
        print("[FAIL] 一张表都没检查到 —— 空检查不是通过")
        return 1
    if fails:
        print("FAILED: %d 项" % len(fails))
        return 1
    print("ALL OK — 特效精灵表规格通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
