# -*- coding: utf-8 -*-
"""menu_arena_sync_audit.py — 主菜单擂台背景的烘焙产物必须就是生成器现在吐出来的那一套

由来（2026-10-05）：主菜单背景换成「擂台 + 看台」，由 `tools/build_menu_arena_bg.py` 把
`assets/sprites/menu/arena/src/` 里 PixelLab 新生成的原件分层烘进 `baked/`，排布写进
`scripts/gamedata/menu_arena_layout.gd`（生成文件）。同群像墙那条（`menu_crowd_sync_audit`）一样：
**没有任何东西守着"改了生成器/换了原件要重跑"这一步** —— 调了一个站位、换了一张观众图却忘了重烘，
游戏里静静地还是旧的，门禁全绿。

★判据：把生成器**原样**跑一遍到临时目录（不碰仓库），再与仓库里的那一套比：
  ① 排布常量文件逐字节相同（它是生成器写的纯文本，没有任何舍入可吸收）
  ② baked/ 下的 png **一张不多一张不少**，且逐张逐像素比（RGBA）
     —— 本机 Pillow 下应当 0 像素不同；为不让「CI 换了 Pillow 版本」变成假红，
        收在「单通道差 > 6 级的像素占比 ≤ 0.5%」（与群像那条同一把尺子）。
  ③ R8 两个钉死的取舍没被改：DESAT == 0.50 / LEFT_DIM == 0.24。
     （2026-10-05 精修只动了左侧那段坡的长度，两个钉死值不许动 —— 想动先回方案书 R8 问用户。）
★反向验证（2026-10-05）：把生成器的 `ATK_X` +1、`DESAT` 改 0.55 ⇒ 当场红 2 处
  （① 排布常量不同 —— 角斗龟的图是裁到包围盒存的, 挪 1 格图本身不变、变的是偏移;
    ③ R8 钉死值被改 —— desat 0.05 的差在多数像素上 ≤ 6 级, 光靠 ② 的像素尺子拦不住, 所以单列 ③）。
  还原后 ALL OK。

跑法: python tools/menu_arena_sync_audit.py
"""
import os
import sys
import tempfile

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

try:
    from PIL import Image, ImageChops
except ImportError:
    print("[FAIL] 需要 Pillow (CI 在 tests.yml 里装)")
    sys.exit(1)

import build_menu_arena_bg as gen   # noqa: E402

LEVEL = 6
MAX_FRAC = 0.005


def _diff_frac(a, b):
    d = ImageChops.difference(a, b)
    mx = d.split()[0]
    for ch in d.split()[1:]:
        mx = ImageChops.lighter(mx, ch)
    hist = mx.histogram()
    n = a.size[0] * a.size[1]
    return sum(hist[LEVEL + 1:]) / float(n)


def main():
    bad = []
    print("=== 主菜单擂台背景 ↔ 生成器同步 ===")
    repo_out, repo_gd = gen.OUT, gen.LAYOUT_GD
    with tempfile.TemporaryDirectory() as td:
        gen.OUT = os.path.join(td, "baked")
        gen.LAYOUT_GD = os.path.join(td, "layout.gd")
        try:
            lay, counts = gen.build()
        finally:
            tmp_out, tmp_gd = gen.OUT, gen.LAYOUT_GD
            gen.OUT, gen.LAYOUT_GD = repo_out, repo_gd
        print("  [分母] 生成器: " + "  ".join("%s %s" % kv for kv in counts.items()))
        want_png = sorted(f for f in os.listdir(tmp_out) if f.endswith(".png"))
        have_png = sorted(f for f in os.listdir(repo_out) if f.endswith(".png")) if os.path.isdir(repo_out) else []
        print("  [分母] 生成器吐出 %d 张 / 仓库里 %d 张" % (len(want_png), len(have_png)))
        if len(want_png) < 20:
            bad.append("[FAIL] 分母: 生成器只吐出 %d 张 —— 它本身就跑不通, 下面的比对没有意义" % len(want_png))
        # ① 排布常量
        want_gd = open(tmp_gd, "rb").read()
        have_gd = open(repo_gd, "rb").read() if os.path.exists(repo_gd) else b""
        if want_gd != have_gd:
            bad.append("[FAIL] %s 与生成器现在写出的不一致(%d vs %d 字节)" % (
                os.path.relpath(repo_gd, ROOT), len(have_gd), len(want_gd)))
        # ② 逐张
        if set(want_png) != set(have_png):
            bad.append("[FAIL] baked/ 张数对不上: 多出 %s / 缺 %s" % (
                sorted(set(have_png) - set(want_png))[:5], sorted(set(want_png) - set(have_png))[:5]))
        n_cmp = 0
        for f in sorted(set(want_png) & set(have_png)):
            a = Image.open(os.path.join(tmp_out, f)).convert("RGBA")
            b = Image.open(os.path.join(repo_out, f)).convert("RGBA")
            n_cmp += 1
            if a.size != b.size:
                bad.append("[FAIL] %s 尺寸不同: 仓库 %s / 生成器 %s" % (f, b.size, a.size))
                continue
            fr = _diff_frac(a, b)
            if fr > MAX_FRAC:
                bad.append("[FAIL] %s 与生成器现在吐出的不一致(%.2f%% 像素差 > %d 级)" % (f, fr * 100.0, LEVEL))
        print("  [分母] 逐像素比了 %d 张" % n_cmp)
    # ③ R8 钉死的两个数
    print("  [R8] DESAT=%.2f LEFT_DIM=%.2f" % (gen.DESAT, gen.LEFT_DIM))
    if abs(gen.DESAT - 0.50) > 1e-9 or abs(gen.LEFT_DIM - 0.24) > 1e-9:
        bad.append("[FAIL] R8 钉死的取舍被改了(desat 0.50 / 左侧压暗 0.24) —— 想改先回方案书 R8 问用户")
    print("")
    if bad:
        for x in bad:
            print(x)
        print("       改了生成器/换了原件却没重烘: python tools/build_menu_arena_bg.py, 然后 <godot> --headless --path . --import")
        print("FAILED: %d 处" % len(bad))
        return 1
    print("ALL OK — 主菜单擂台背景就是生成器现在的产物")
    return 0


if __name__ == "__main__":
    sys.exit(main())
