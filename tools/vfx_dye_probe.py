# -*- coding: utf-8 -*-
"""vfx_dye_probe.py — 【染色法】核实一件装备的特效到底画了什么（只读工具，不进门禁）

═══════════════════════════════════════════════════════════════════
 ★为什么需要这个：2026-08-11 的惨痛教训
═══════════════════════════════════════════════════════════════════
2026-08-10 我照着 VFXLAB 的缩略接触印相写了一张 17 件的「问题清单」。
后来逐条核实，**核实过 8 条错了 6 条**：

  · 060「灰白不是磷光」→ 实测 86% 是明确青蓝，**它本来就对**
  · 065「环几乎看不见」→ 环一直在，且按设计随叠层变亮（280→625 像素）
  · 066「完全没有视觉」→ 有闪光 + 飘字 + 体型二阶欠阻尼过冲
  · 073「白球」        → 62% 是绿的，只是球心被加色混合爆白
  · 063「实心球」      → 它画的是环面
  · 070/075「环超范围」→ 环用的就是伤害判定的同一个常量

060 和 065 的补丁我都写好了，量完直接丢掉 —— **差点改坏两处本来正确的代码**。

后来试过用 A/B 差分（同参数只换装备）代替目视，也不行：
**换了装备龟的攻击节奏就变了** ⇒ 动画相位/位置跟着变 ⇒ 差分把龟自己也算进去。
061 差分报 30568 个像素、裁开一看肉眼几乎什么都没有。
加了 `VFXLAB_STILL=1`（两边都不动不打）降到 9113，**仍未清零**
（剩下的是血条那一行 —— 换装备属性变，血条宽度跟着变）。

⇒ **绝对归属只能靠染色法**：给要查的那一处特效一个画面上**独一无二的颜色**，
  再数那个颜色的像素。这是唯一不受"龟自己也在动"干扰的办法。

═══════════════════════════════════════════════════════════════════
 用法
═══════════════════════════════════════════════════════════════════
  python tools/vfx_dye_probe.py <装备id> <要染色的文件> <要染色的那一行里的颜色表达式>

例：
  python tools/vfx_dye_probe.py p2eq_071 \\
      scripts/scenes/battle/food_eq_vfx.gd \\
      'Color(1.0, 0.96, 0.84, 0.42)'

它会：
  ① 备份那个文件 → 把指定的颜色表达式换成品红 `Color(1.0, 0.0, 1.0, 0.95)`
  ② 跑 VFXLAB 拍这一件
  ③ 数每一帧里的品红像素（个数 / 亮度中位数 / 在 x 上分成几簇）
  ④ **无论成功失败都还原备份**，并核对还原干净（DYE 0 处）

⚠ 两条踩过的坑：
  · 染色要下在**每帧真正写颜色那一行**；下在工厂函数里会被后面的赋值覆盖。
  · 同一个文件里若有多处写同一个颜色，按**行号**染，别整串 replace ——
    本脚本用 `count == 1` 的断言拦住这种情况（宁可报错也不要染错地方）。
"""
import io
import os
import re
import subprocess
import sys
import glob

# ★ Windows 控制台默认 GBK, 不包一层会在 print 中文时直接崩
#   (其余 tools/ 下的脚本都加了这一行, 本文件一开始漏了)
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

GODOT = r"C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe"
DYE = 'Color(1.0, 0.0, 1.0, 0.95)'


def shoot(eq_id, out_prefix):
    env = dict(os.environ)
    env.update({"VFXLAB": "1", "VFXLAB_CASE": eq_id, "VFXLAB_OUT": "res://%s" % out_prefix})
    subprocess.run([GODOT, "--path", ".", "--resolution", "1280x720",
                    "--position", "5000,5000", "--audio-driver", "Dummy",
                    "res://scenes/RealtimeBattle3D.tscn"],
                   env=env, capture_output=True, timeout=300)


def count_dye(prefix):
    from PIL import Image
    rows = []
    fs = sorted(glob.glob(prefix + "*.png"),
                key=lambda x: int(x.rsplit("_", 1)[1].split(".")[0]))
    for f in fs:
        im = Image.open(f).convert("RGB")
        px = im.load()
        W, H = im.size
        pts = [(x, max(px[x, y])) for y in range(H) for x in range(W)
               if px[x, y][0] > 60 and px[x, y][2] > 60
               and px[x, y][1] < max(40, px[x, y][0] // 3)]
        if not pts:
            rows.append((os.path.basename(f), 0, 0, 0))
            continue
        xs = sorted({p[0] for p in pts})
        clusters = 1
        for i in range(1, len(xs)):
            if xs[i] - xs[i - 1] > 40:
                clusters += 1
        br = sorted(p[1] for p in pts)
        rows.append((os.path.basename(f), len(pts), br[len(br) // 2], clusters))
    return rows


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    eq_id, path, expr = sys.argv[1], sys.argv[2], sys.argv[3]
    src = io.open(path, encoding="utf-8", newline="").read()
    if src.count(expr) != 1:
        print("★拒绝染色：`%s` 在 %s 里出现 %d 次（必须恰好 1 次，否则会染错地方）"
              % (expr, path, src.count(expr)))
        return 1
    bak = src
    try:
        io.open(path, "w", encoding="utf-8", newline="").write(
            src.replace(expr, DYE + "   # DYE-PROBE", 1))
        prefix = "_dyeprobe_%s_" % eq_id
        for f in glob.glob(prefix + "*.png"):
            os.remove(f)
        shoot(eq_id, prefix)
        rows = count_dye(prefix)
        print("=== %s 染色实测 ===" % eq_id)
        if not rows:
            print("  (一张图都没拍到 —— 台子配置或 case id 有问题)")
        for name, n, med, cl in rows:
            print("  %-28s 染色像素 %5d  亮度中位数 %3d  分布 %d 处" % (name, n, med, cl))
        tot = sum(r[1] for r in rows)
        print("  合计 %d ⇒ %s" % (tot, "这一处确实画出来了" if tot > 200 else "★几乎没画出来（或没触发）"))
        for f in glob.glob(prefix + "*.png"):
            os.remove(f)
    finally:
        io.open(path, "w", encoding="utf-8", newline="").write(bak)
        left = io.open(path, encoding="utf-8", newline="").read().count("DYE-PROBE")
        print("还原：%s（残留 DYE-PROBE %d 处）" % ("干净" if left == 0 else "★没还原干净！", left))
    return 0


if __name__ == "__main__":
    sys.exit(main())
