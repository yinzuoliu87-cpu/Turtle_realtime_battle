# -*- coding: utf-8 -*-
"""pixel_art_audit.py — 素材到底是不是【真像素画】。

★由来(2026-09-06)：审 003 锋利鲨齿时，图标在 10 倍放大下是糊的。量出来
  **469×531 / 28,176 色 / 3,795 个半透明边缘像素** —— 它是一张全彩绘图被缩进图标框，
  不是像素画。而 001/002 是 32×32 / 24~33 色 / 零半透。
  扫全仓后发现 **96 件装备图标里 50 件不合格**，最夸张的 1254×1254 / 114,858 色。

★为什么这条重要（用户 2026-09-06 反复说「我们是像素风」）：
  同一个画面里混着全彩绘图和像素画，**再好的特效也贴不上去**。
  这不是"某件做得差"，是风格不统一。

★三条判据（都可量，不靠眼睛）：
  ① 尺寸 ≤ MAX_PX —— 像素画在原分辨率下作画；上千像素的图必然是绘图缩下来的
  ② 色数 ≤ MAX_COLORS —— 成熟像素项目锁 16~48 色一套主板
  ③ 半透明边缘 == 0 —— 像素画是硬边；半透边缘 = 抗锯齿 = 绘图工具的产物

★台账制(照 arch_budget 的老规矩)：存量记在 tools/pixel_art_debt.json，**只减不增**。
  新增不合格的当场红；已有的慢慢还。没有台账的话这条门禁永远红，等于没有。

只读(除非 --update)。跑法:
  python tools/pixel_art_audit.py
  python tools/pixel_art_audit.py --update   # 重写台账(只在真的还债之后跑)
"""
import argparse
import io
import json
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

MAX_PX = 64          # 单边像素上限
MAX_COLORS = 64      # 不透明像素的不同颜色数上限
DEBT_FILE = os.path.join("tools", "pixel_art_debt.json")
EQUIP_JSON = os.path.join("data", "phase2-equipment.json")


def profile(path):
    """→ (宽, 高, 色数, 半透边缘像素数)"""
    im = Image.open(path).convert("RGBA")
    px = im.load()
    cols = set()
    semi = 0
    for y in range(im.height):
        for x in range(im.width):
            a = px[x, y][3]
            if a > 16:
                cols.add(px[x, y][:3])
            if 16 < a < 245:
                semi += 1
    return im.width, im.height, len(cols), semi


def verdict(w, h, ncol, semi):
    """不合格的理由列表；空 = 合格。"""
    bad = []
    if max(w, h) > MAX_PX:
        bad.append("尺寸 %dx%d > %d" % (w, h, MAX_PX))
    if ncol > MAX_COLORS:
        bad.append("%d 色 > %d" % (ncol, MAX_COLORS))
    if semi > 0:
        bad.append("半透边缘 %d px(抗锯齿)" % semi)
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--update", action="store_true", help="重写台账(只在真的还债之后跑)")
    a = ap.parse_args()

    if not os.path.exists(EQUIP_JSON):
        print("[FAIL] 找不到 %s" % EQUIP_JSON)
        return 1
    items = json.load(io.open(EQUIP_JSON, encoding="utf-8"))
    base = {}
    if os.path.exists(DEBT_FILE):
        try:
            base = json.load(io.open(DEBT_FILE, encoding="utf-8"))
        except Exception:
            base = {}
    known = set(base.get("bad_ids", []))

    cur_bad = {}
    n_checked = 0
    for it in items:
        img = it.get("img", "")
        p = os.path.join("assets", "sprites", img.replace("/", os.sep))
        if not img or not os.path.exists(p):
            print("  [FAIL] %s 图标文件不在: %s" % (it.get("id"), img))
            return 1
        n_checked += 1
        w, h, ncol, semi = profile(p)
        bad = verdict(w, h, ncol, semi)
        if bad:
            cur_bad[it.get("id")] = "%s ── %s" % (it.get("name", ""), "; ".join(bad))

    ## ★分母: 没检查到东西就是空检查, 不是通过
    print("  [分母] 检查了 %d 件装备图标 (判据: ≤%dpx · ≤%d 色 · 零半透边缘)"
          % (n_checked, MAX_PX, MAX_COLORS))
    if n_checked == 0:
        print("[FAIL] 一件都没检查到")
        return 1

    if a.update:
        io.open(DEBT_FILE, "w", encoding="utf-8").write(
            json.dumps({"_note": "不是真像素画的装备图标·只减不增。判据见 tools/pixel_art_audit.py",
                        "bad_ids": sorted(cur_bad)}, ensure_ascii=False, indent=2))
        print("  [台账已重写] %s (%d 件欠债)" % (DEBT_FILE, len(cur_bad)))
        return 0

    grew = sorted(set(cur_bad) - known)
    fixed = sorted(known - set(cur_bad))
    print("  台账欠债 %d 件 · 本次实测不合格 %d 件" % (len(known), len(cur_bad)))
    if fixed:
        print("  ✅ 已还债 %d 件: %s" % (len(fixed), ", ".join(fixed)))
    if grew:
        print("[FAIL] 新增 %d 件不是像素画的图标 —— 只减不增:" % len(grew))
        for i in grew:
            print("       %s %s" % (i, cur_bad[i]))
        print("       ⇒ 新图标必须做成 ≤%dpx · ≤%d 色 · 硬边(零半透)。"
              "走 tools/pixelize_sheet.py 的锁定调色板。" % (MAX_PX, MAX_COLORS))
        return 1
    if fixed:
        print("       ⇒ 记得跑 --update 把台账降下来。")
    print("ALL OK — 没有新增的非像素画图标")
    return 0


if __name__ == "__main__":
    sys.exit(main())
