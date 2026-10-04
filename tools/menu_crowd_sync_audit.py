# -*- coding: utf-8 -*-
"""menu_crowd_sync_audit.py — 主菜单群像背景 menu-bg-crowd.png 必须就是生成器现在吐出来的那张

由来（2026-10-04 欠账盘点 R3）：`tools/build_menu_crowd_bg.py` 从 28 只龟的第 0 帧合成主菜单背景。
它存在的全部理由写在它自己头注里 ——「加龟 / 换立绘 / 调纵深参数时重跑一次就同步，手工拼的图在下一只
龟进来时就烂了」。**但没有任何东西守着"重跑一次"这一步**：加了第 29 只龟、改了某只立绘、调了
LAYERS/DIM 参数而忘了重跑，背景就静静地落后，门禁全绿。

★判据：在内存里用生成器**自己的函数**重新合成一遍（不写盘、不碰 assets/），与仓库里那张逐像素比。
  · 本机实测（Pillow 12.1.1）逐像素 **完全相同**（0 个像素不同）。
  · CI 装的是不钉版本的 Pillow ⇒ 重采样(LANCZOS)的末位舍入可能随版本差 1~2 级。为了不让它变成
    "换个 Pillow 版本就红"的假红，判据收在「差异 > 6 级的像素占比 ≤ 0.5%」——
    真正的漂移（换一只龟 / 改一个亮度参数）动的是成片像素、几十级，量级差三个数量级（反向验证见下）。
  · 反向验证（2026-10-04）：把 `DIM_OVERALL` 0.54→0.60 ⇒ 当场红；还原后逐字节一致。

跑法: python tools/menu_crowd_sync_audit.py
"""
import os
import sys

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

import build_menu_crowd_bg as gen   # noqa: E402

LEVEL = 6          # 单通道差 > 这个才算"不同"(吸收重采样末位舍入)
MAX_FRAC = 0.005   # 不同像素占比上限


def main():
    bad = []
    pets, broken = gen.first_frames()
    print("=== 主菜单群像背景 ↔ 生成器同步 ===")
    print("  [分母] 生成器切出 %d 只龟 / 异常 %d" % (len(pets), len(broken)))
    if len(pets) < 28 or broken:
        bad.append("[FAIL] 分母: 只切出 %d 只(异常 %s) —— 生成器本身就跑不通, 下面的比对没有意义"
                   % (len(pets), broken))
    canvas, placed = gen.compose(pets)
    want = gen.finish(canvas, gen.DIM_OVERALL, gen.LEFT_DIM, gen.VIGNETTE, gen.DESAT).convert("RGB")
    if len(placed) != len(pets):
        bad.append("[FAIL] 排布 %d 只 ≠ 切出 %d 只(LAYERS 名额与龟数对不上 —— 加了龟没扩名额)"
                   % (len(placed), len(pets)))
    if not os.path.exists(gen.OUT_PNG):
        bad.append("[FAIL] 仓库里没有 %s" % os.path.relpath(gen.OUT_PNG, ROOT))
    else:
        have = Image.open(gen.OUT_PNG).convert("RGB")
        if have.size != want.size:
            bad.append("[FAIL] 尺寸不同: 仓库 %s / 生成器 %s" % (have.size, want.size))
        else:
            n = want.size[0] * want.size[1]
            d = ImageChops.difference(have, want)
            # 每像素取三通道最大差
            r, g, b = d.split()
            mx = ImageChops.lighter(ImageChops.lighter(r, g), b)
            hist = mx.histogram()
            exact = hist[0]
            over = sum(hist[LEVEL + 1:])
            frac = over / float(n)
            print("  [分母] 比了 %d 个像素: 完全相同 %d / 差 > %d 级的 %d (%.3f%%, 上限 %.1f%%)"
                  % (n, exact, LEVEL, over, frac * 100.0, MAX_FRAC * 100.0))
            if frac > MAX_FRAC:
                bad.append("[FAIL] menu-bg-crowd.png 与生成器现在吐出的图不一致(%.2f%% 像素差 > %d 级)。\n"
                           "       加了龟 / 换了立绘 / 调了参数却没重跑: python tools/build_menu_crowd_bg.py\n"
                           "       然后 <godot> --headless --path . --import" % (frac * 100.0, LEVEL))
    print("")
    if bad:
        for x in bad:
            print(x)
        print("FAILED: %d 处" % len(bad))
        return 1
    print("ALL OK — 主菜单群像背景就是生成器现在的产物")
    return 0


if __name__ == "__main__":
    sys.exit(main())
