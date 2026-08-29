# -*- coding: utf-8 -*-
"""拆帧 / 合帧 —— 让特效 sheet 能拿去 Aseprite 一帧一帧改 (2026-08-29)。

★由来: 用户要用 Aseprite 逐帧改十字斩的素材。仓库里存的是**横排 sheet**
  (9 帧 × 128px 拼成 1152×128), 直接改整条容易错位; 拆成 f0..f8 单帧最好改,
  Aseprite 的「Open File Sequence」会自动把 f0..f8 认成一段动画。

跑法:
    python tools/assetgen/vfx_edit.py list              # 有哪些能改
    python tools/assetgen/vfx_edit.py out eq084-chop    # sheet → edit/eq084-chop/f0.png..
    python tools/assetgen/vfx_edit.py in  eq084-chop    # 单帧 → sheet, 并**重量几何**

★★`in` 那一步会把改完的素材**重新量一遍**, 并和代码里的常量对照:
  · 落地点 CHOP_PIVOT      —— 改了刀尖位置, 游戏里就会钉错地方
  · 刀身偏向 CHOP_MASS_DX  —— 它决定"朝左劈还是朝右劈"的镜像条件, 符号反了整刀就背对目标
  · 圆心/张角(横斩那张)     —— 张角必须等于判定锥, 否则"看到多宽 ≠ 打到多宽"
  数值漂了会**大声报出来**, 不会默默让游戏用错的常量跑。

★也可以完全不用本工具: Aseprite 能直接开 sheet ——
    File → Open `assets/sprites/vfx/eq084-chop.png`
    Sprite → Import Sprite Sheet → Type: Horizontal, Size 128×128
  改完 File → Export Sprite Sheet 存回同一个文件即可。
  但那样就**没有上面那一步几何复核**, 常量漂了没人知道。

★改完记得让 Godot 重新导入: `godot --headless --path . --import`
  (本工具的 `in` 会自动跑, 除非加 --no-import)
"""
import io
import math
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

VFX = "assets/sprites/vfx"
## ★用户 2026-08-29:「把素材搞文件夹放我桌面上, 我一个个打开修完全部保存后就定稿,
##   从我桌面上移除」。所以工作区就在桌面, 收回后直接删掉。
DESK = os.path.join(os.path.expanduser("~"), "Desktop", "084素材_改这里")
EDIT = DESK

## 一次摆上桌面的整套(084 十字斩)。
BATCH_084 = ["eq084-chop", "eq084-slash-wide", "eq084-wave", "eq084-burst", "eq084-beam"]
GODOT = os.environ.get("GODOT", "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe")

## 每张图“该量什么” —— 量法与 blade_eq_vfx.gd 里的常量一一对应。
SPEC = {
    "eq084-chop": {"kind": "contact", "const": {
        "CHOP_PIVOT": (0.468, 0.893), "CHOP_MASS_DX": -0.095}},
    "eq084-slash-wide": {"kind": "fan", "pivot": (0.664, 0.728), "want_span": 120.0},
    "eq084-slash-narrow": {"kind": "contact", "const": {}},
    "eq084-slash": {"kind": "fan", "pivot": (0.664, 0.728), "want_span": 116.0},
    "eq084-wave": {"kind": "plain"},
    "eq084-burst": {"kind": "plain"},
    ## ★激光束的单帧是 **6:1 的长条**, 不是正方形。
    ##   按正方形切会把 6 帧切成 36 块碎片(实测踩过)。
    "eq084-beam": {"kind": "plain", "aspect": 6.0},
}


def frames_of(im, name=None):
    """横排 sheet → 帧列表。默认帧宽 = 图高(正方形帧),
    SPEC 里标了 aspect 的按那个宽高比切。"""
    h = im.height
    fw = int(round(h * float(SPEC.get(name, {}).get("aspect", 1.0)))) if name else h
    if fw <= 0 or im.width % fw != 0:
        return [im]
    return [im.crop((fw * k, 0, fw * (k + 1), h)) for k in range(im.width // fw)]


def cmd_list():
    print("  可编辑的特效(横排 sheet):")
    for fn in sorted(os.listdir(VFX)):
        if not fn.endswith(".png"):
            continue
        p = os.path.join(VFX, fn)
        try:
            im = Image.open(p)
        except Exception:
            continue
        if im.width > im.height and im.width % im.height == 0:
            name = fn[:-4]
            tag = "  ← 有几何复核" if name in SPEC and SPEC[name]["kind"] != "plain" else ""
            print("    %-26s %d 帧 × %dpx%s" % (name, im.width // im.height, im.height, tag))
    return 0


def cmd_out(name):
    src = os.path.join(VFX, name + ".png")
    if not os.path.exists(src):
        print("  [FAIL] 没有 %s" % src)
        return 1
    im = Image.open(src).convert("RGBA")
    fs = frames_of(im, name)
    d = os.path.join(EDIT, name)
    os.makedirs(d, exist_ok=True)
    for i, f in enumerate(fs):
        f.save(os.path.join(d, "f%d.png" % i))
    print("  拆出 %d 帧 → %s" % (len(fs), os.path.abspath(d)))
    print("")
    print("  Aseprite: File → Open File Sequence, 选中 f0.png ~ f%d.png" % (len(fs) - 1))
    print("            (它会认成一段动画; 改完把每帧存回原文件名)")
    print("  改完跑:   python tools/assetgen/vfx_edit.py in %s" % name)
    return 0


def _measure(name, fs):
    """按 SPEC 重量几何。返回 (行, 警告列表)。"""
    sp = SPEC.get(name, {"kind": "plain"})
    out, warn = [], []
    if sp["kind"] == "contact":
        cs, dx = [], []
        for f in fs:
            px = f.load()
            W, H = f.size
            pts = [(x, y) for y in range(H) for x in range(W) if px[x, y][3] > 40]
            if len(pts) < 80:
                continue
            ymax = max(p[1] for p in pts)
            lo = [p[0] for p in pts if p[1] >= ymax - 2]
            cx = sum(lo) / float(len(lo)) / W
            mx = sum(p[0] for p in pts) / float(len(pts)) / W
            cs.append((cx, ymax / float(H)))
            dx.append(mx - cx)
        if not cs:
            warn.append("%s 一帧有效内容都没有(N=0 是空检查)" % name)
            return out, warn
        px_ = sum(c[0] for c in cs) / len(cs)
        py_ = sum(c[1] for c in cs) / len(cs)
        mdx = sum(dx) / len(dx)
        drift_x = max(c[0] for c in cs) - min(c[0] for c in cs)
        drift_y = max(c[1] for c in cs) - min(c[1] for c in cs)
        out.append("落地点 (%.3f, %.3f) · 逐帧漂移 x %.3f / y %.3f · 刀身偏向 %+.3f"
                   % (px_, py_, drift_x, drift_y, mdx))
        if drift_y > 0.04:
            warn.append("%s 落地点【纵向在漂】%.3f > 0.04 —— 刀会在地上滑" % (name, drift_y))
        want = sp.get("const", {})
        if "CHOP_PIVOT" in want:
            wx, wy = want["CHOP_PIVOT"]
            if abs(px_ - wx) > 0.03 or abs(py_ - wy) > 0.03:
                warn.append("%s 落地点变了: (%.3f,%.3f) ≠ 代码里的 CHOP_PIVOT (%.3f,%.3f)"
                            " —— 改 blade_eq_vfx.gd 的 CHOP_PIVOT" % (name, px_, py_, wx, wy))
        if "CHOP_MASS_DX" in want:
            w = want["CHOP_MASS_DX"]
            if (mdx < 0) != (w < 0):
                warn.append("%s 刀身偏向【换边了】: %+.3f vs 代码 %+.3f —— 镜像条件会反,"
                            " 整刀会背对目标。改 CHOP_MASS_DX" % (name, mdx, w))
            elif abs(mdx - w) > 0.05:
                warn.append("%s 刀身偏向变了: %+.3f ≠ 代码 %+.3f —— 建议同步 CHOP_MASS_DX"
                            % (name, mdx, w))
    elif sp["kind"] == "fan":
        gxn, gyn = sp["pivot"]
        spans = []
        for f in fs:
            px = f.load()
            W, H = f.size
            gx, gy = gxn * W, gyn * H
            a = sorted(math.degrees(math.atan2(y - gy, x - gx))
                       for y in range(H) for x in range(W) if px[x, y][3] > 40)
            if len(a) < 200:
                continue
            N = len(a)
            best = None
            for i in range(N):
                j = (i + N - 1) % N
                w = a[j] - a[i] if j > i else a[j] + 360.0 - a[i]
                if best is None or w < best:
                    best = w
            spans.append(best)
        if not spans:
            warn.append("%s 一帧有效内容都没有(N=0 是空检查)" % name)
            return out, warn
        got = sum(spans) / len(spans)
        out.append("绕圆心 (%.3f,%.3f) 的张角 %.0f°(期望 %.0f°) · 量了 %d 帧"
                   % (gxn, gyn, got, sp["want_span"], len(spans)))
        if abs(got - sp["want_span"]) > 10.0:
            warn.append("%s 张角 %.0f° ≠ %.0f° —— 演出承诺的和打得到的不一样"
                        % (name, got, sp["want_span"]))
    return out, warn


def cmd_in(name, do_import=True):
    d = os.path.join(EDIT, name)
    if not os.path.isdir(d):
        print("  [FAIL] 没有 %s —— 先跑 out" % d)
        return 1
    ## ★★把目录里所有 f<数字>.png 全收起来排序 —— **不能**从 f0 数到第一个缺失就停。
    ##   用户 2026-08-29 删了多余帧, 删的是中间的 f6 ⇒ "数到缺失就停" 会静默丢掉 f7 f8,
    ##   只收 6 帧还一声不吧。缺口要**显式报出来**, 不允许静默截断。
    import re as _re
    idx = []
    for fn in os.listdir(d):
        m = _re.match(r"^f(\d+)\.png$", fn)
        if m:
            idx.append(int(m.group(1)))
    idx.sort()
    if idx:
        gaps = [k for k in range(idx[0], idx[-1] + 1) if k not in idx]
        if gaps:
            print("  [注意] 帧号中间有缺口: 缺 %s —— 按**剩下的顺序**拼回(帧数 %d⇒%d)"
                  % (",".join("f%d" % g for g in gaps), idx[-1] + 1, len(idx)))
    fs = [Image.open(os.path.join(d, "f%d.png" % i)).convert("RGBA") for i in idx]
    if not fs:
        print("  [FAIL] %s 里一张 f*.png 都没有" % d)
        return 1
    sz = set(f.size for f in fs)
    if len(sz) != 1:
        print("  [FAIL] 各帧尺寸不一致: %s —— Aseprite 导出时别改画布" % sorted(sz))
        return 1
    w, h = fs[0].size
    sh = Image.new("RGBA", (w * len(fs), h), (0, 0, 0, 0))
    for k, f in enumerate(fs):
        sh.paste(f, (k * w, 0))
    dst = os.path.join(VFX, name + ".png")
    sh.save(dst)
    print("  合回 %d 帧 → %s (%dx%d)" % (len(fs), dst, sh.width, sh.height))

    lines, warn = _measure(name, fs)
    for L in lines:
        print("  [几何] " + L)
    for W in warn:
        print("  [注意] " + W)

    if do_import:
        print("  Godot 重新导入…")
        subprocess.run([GODOT, "--headless", "--path", ".", "--import"],
                       capture_output=True, timeout=600)
        print("  导入完成")
    if warn:
        print("")
        print("FAILED: %d 条几何对不上 —— 代码常量要跟着改, 否则游戏用的是旧数" % len(warn))
        return 1
    print("")
    print("ALL OK — 已合回并重新导入, 几何与代码常量一致")
    return 0


def cmd_desk():
    """把整套 084 素材拆到桌面一个文件夹里。"""
    os.makedirs(DESK, exist_ok=True)
    n = 0
    for name in BATCH_084:
        src = os.path.join(VFX, name + ".png")
        if not os.path.exists(src):
            print("  [跳过] 没有 %s" % src)
            continue
        im = Image.open(src).convert("RGBA")
        fs = frames_of(im, name)
        d = os.path.join(DESK, name)
        os.makedirs(d, exist_ok=True)
        for i, f in enumerate(fs):
            f.save(os.path.join(d, "f%d.png" % i))
        print("  %-22s %d 帧" % (name, len(fs)))
        n += len(fs)
    _tips = [
        "十字斩素材 —— 用 Aseprite 逐帧改",
        "",
        "每个子文件夹 = 一张特效, 里面 f0.png f1.png ... 是它的逐帧。",
        "",
        "  eq084-chop        竖斩(新月形刀光, 从左上劈到地面)",
        "  eq084-slash-wide  横斩(扇形, 铺在地面上, 张角就是 120度 判定锥)",
        "  eq084-wave        剑气波",
        "  eq084-burst       命中爆点",
        "  eq084-beam        普攻红色激光束",
        "",
        "Aseprite: File → Open File Sequence, 选中 f0.png 到最后一张 → 它会认成一段动画。",
        "改完存回原文件名(别改画布尺寸, 别改帧数)。",
        "",
        "全部改完后告诉我, 我跑:",
        "    python tools/assetgen/vfx_edit.py done",
        "它会合回 sheet、重量几何(落地点/刀身偏向/张角)、重新导入 Godot,",
        "然后把这个文件夹从桌面删掉。",
        "",
        "⚠ 改完之后不要再跑 build_eq084_vfx.py —— 那个是从原始帧重新生成的,",
        "  会把你手改的盖掉。",
    ]
    ## ★用 chr(10) 拼行 —— heredoc 里的反斜杠 n 会变真换行把字符串撑断
    ##   (memory fb-heredoc-backslash-n-corrupts-json, 写本文件时又踩了一次)
    io.open(os.path.join(DESK, "说明.txt"), "w", encoding="utf-8").write(
        chr(10).join(_tips) + chr(10))
    print("")
    print("  → %s" % DESK)
    print("  共 %d 帧。改完告诉我, 我跑 `vfx_edit.py done` 收回并删掉桌面那个文件夹。" % n)
    return 0


def cmd_done():
    """收回整套 + 重量几何 + 重新导入 + 删掉桌面文件夹。"""
    if not os.path.isdir(DESK):
        print("  [FAIL] 桌面上没有 %s" % DESK)
        return 1
    bad = 0
    done = []
    for name in BATCH_084:
        if not os.path.isdir(os.path.join(DESK, name)):
            continue
        print("▶ %s" % name)
        if cmd_in(name, do_import=False) != 0:
            bad += 1
        done.append(name)
    if not done:
        print("  [FAIL] 一个子文件夹都没找到(N=0 是空检查不是通过)")
        return 1
    print("")
    print("  Godot 重新导入…")
    subprocess.run([GODOT, "--headless", "--path", ".", "--import"],
                   capture_output=True, timeout=600)
    if bad:
        print("")
        print("FAILED: %d 张几何对不上 —— **桌面文件夹先不删**, 修完再跑一次" % bad)
        return 1
    import shutil
    shutil.rmtree(DESK, ignore_errors=True)
    print("  已从桌面移除 %s" % DESK)
    print("")
    print("ALL OK — %d 张已定稿并导入" % len(done))
    return 0


def main():
    a = sys.argv[1:]
    if not a or a[0] not in ("list", "out", "in", "desk", "done"):
        print(__doc__)
        return 2
    if a[0] == "list":
        return cmd_list()
    if a[0] == "desk":
        return cmd_desk()
    if a[0] == "done":
        return cmd_done()
    if len(a) < 2:
        print("  用法: vfx_edit.py %s <名字>" % a[0])
        return 2
    if a[0] == "out":
        return cmd_out(a[1])
    return cmd_in(a[1], "--no-import" not in a)


if __name__ == "__main__":
    sys.exit(main())
