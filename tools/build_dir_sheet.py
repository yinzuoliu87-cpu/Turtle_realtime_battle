# -*- coding: utf-8 -*-
"""build_dir_sheet.py — 把一组动画帧拼成【方向表】。

★★2026-09-06 从 build_dir8_sheet.py 改成 4 方向。这不是省事, 是把设计改对了 ——
  三条实测证据：

  ① **8 格里只有 1 格被用过。** 探针量飞行全程 `di` 恒为 0(目标就在正东)。
     另外 7 格是纯负债：出过的每一个素材缺陷都长在它们身上
     (NE 与 NW 完全相同 / 基准帧整体偏 63° / 格内 4 帧轴向摆 75°)。
  ② **像素只对 90° 旋转和水平镜像无损**, 45° 一定重采样出锯齿。
     ⇒ 8 方向必须有【两张】基准帧(0° 一张 + 45° 一张)。
  ③ **第二张基准帧拿不到。** 试过两条路都失败:
     · 重新生成"横向弧" → 64 张全是直的胶囊/子弹, 不是弧, 和斜向那张不是同一个形状语言;
     · `edit_image` 让它转 45° → 轴向 48.9° vs 原 49.3°, **根本没转**, 只是重画了一张相似的。

  ⇒ 4 方向: E 由基准帧水平镜像(使凸面朝前), N/W/S 由 E 经 90° 旋转/镜像推出。**全程无损。**
     斜向飞行就近取这 4 格 —— 2D 像素游戏本来就是这么做的。

表布局: 横 4 格 = 方向(E, N, W, S), 纵 N 格 = 动画帧。

跑法:
  python tools/build_dir_sheet.py <帧0.png> <帧1.png> ... -o out.png
"""
import argparse
import hashlib
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image

DIRS = 4   # E, N, W, S


## 基准帧凸面朝向 → 先把它转成"凸面朝东"要做的无损变换。
## ★别写死。第一批基准帧凸面朝西, 第二批(照 LoL 剖面重做的宽弧)凸面【朝南】(白边在底),
##   沿用写死的那版会让整表转 90° —— 门禁 ⑥「每格凸面朝自己那个方向」正好抓它。
_TO_EAST = {
    "E": None,
    "W": Image.FLIP_LEFT_RIGHT,
    "S": Image.ROTATE_90,      # PIL 的 ROTATE_90 是逆时针: 底部内容转到右边
    "N": Image.ROTATE_270,
}


def make_dirs(base, base_convex="E"):
    """基准帧 → 四个方向。**只用镜像和 90° 旋转, 对像素无损。**"""
    t = _TO_EAST[base_convex]
    e = base if t is None else base.transpose(t)       # 凸面朝右 = 向东飞
    n = e.transpose(Image.ROTATE_90)                   # 右→上
    w = e.transpose(Image.FLIP_LEFT_RIGHT)             # 凸面朝左 = 向西
    s = e.transpose(Image.ROTATE_270)                  # 右→下
    return [e, n, w, s]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("frames", nargs="+")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--base-convex", default="E", choices=list(_TO_EAST),
                    help="基准帧的凸面朝哪(白边/外缘那一侧)。写错的话整表会转 90°, 门禁⑥会红")
    a = ap.parse_args()

    ims = [Image.open(f).convert("RGBA") for f in a.frames]
    ## ★宽本体必须先【垫成方格】再推方向: 90° 旋转会把 64×24 变成 24×64,
    ##   不垫的话四个格尺寸对不上, 拼出来的表没法当 hframes/vframes 用。
    ##   (垫完像素口径就不能再由格高算了 —— 见 battle_ballistics 的 FLYSLASH_ART_PX 长注。)
    if ims and ims[0].width != ims[0].height:
        S = max(ims[0].width, ims[0].height)
        pad = []
        for im in ims:
            sq = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            sq.paste(im, ((S - im.width) // 2, (S - im.height) // 2))
            pad.append(sq)
        print("  本体 %dx%d → 垫成 %dx%d 方格(为了 90° 旋转)" % (ims[0].width, ims[0].height, S, S))
        ims = pad
    if not ims:
        print("[FAIL] 一帧都没收到 —— 空表不是通过")
        return 1
    W, H = ims[0].size
    for f, im in zip(a.frames, ims):
        if im.size != (W, H):
            print("[FAIL] %s 尺寸 %s ≠ 首帧 %s" % (f, im.size, (W, H)))
            return 1

    sheet = Image.new("RGBA", (W * DIRS, H * len(ims)), (0, 0, 0, 0))
    for r, im in enumerate(ims):
        for c, cell in enumerate(make_dirs(im, a.base_convex)):
            sheet.paste(cell, (c * W, r * H))
    sheet.save(a.out)

    ## ★装表前先自证: 同一行的 4 个方向格必须两两不同。
    ##   历史上 NE 和 NW 拼出来完全一样(去重只剩 7 种), 而肉眼在缩略图里看不出来。
    sigs = {}
    for c in range(DIRS):
        k = hashlib.md5(sheet.crop((c * W, 0, (c + 1) * W, H)).tobytes()).hexdigest()
        sigs.setdefault(k, []).append(c)
    dup = [v for v in sigs.values() if len(v) > 1]
    print("  %s  %dx%d  = %d 方向 × %d 帧" % (a.out, sheet.width, sheet.height, DIRS, len(ims)))
    if dup:
        print("[FAIL] 方向格重复: %s" % dup)
        return 1
    print("  [OK] %d 个方向格两两不同(分母 %d)" % (DIRS, DIRS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
