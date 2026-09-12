# -*- coding: utf-8 -*-
"""vfx_scan.py — 把一段时间**连续录下来**, 再在整段里找特效出现在哪一刻。

跑法:
  python tools/vfx_scan.py p2eq_014 --from 8 --to 40 --step 0.15 \
      --colors 6ec894,eefaf0,3a9668,b8e8c8
  python tools/vfx_scan.py p2eq_020 --from 8 --to 20 --step 0.12 --auto

════════════════════════════════════════════════════════════════════════
 ★为什么有这个东西 (用户 2026-09-12)
════════════════════════════════════════════════════════════════════════
「**能不能算准时间啊，别天天搞错啊**」
「**要么就直接录制多少秒，然后在整个视频里找**」
「**别一天天地没看到或看错特效啊**」

他说的是实情。同一天我因为**拍点没对上**连栽三次, 每次都先得出错误结论:
  · 013 的刺  —— 拍点没盖住触发, 十帧全空场, 我去查"是不是没触发"
  · 020 的哑铃 —— 拍点到 9.2s 就停, 而投掷在 9.5s, 我去查"是不是没画出来"
  · 014 的汲取 —— 拍点 4 秒一发而线只活 0.27 秒(周期 8 秒), 我判成"没渲染",
                 直到拿红色大块探针才发现它其实一直在画

**根因是同一个: 我在猜特效什么时候出现。** 猜错了就去查一个不存在的 bug。

⇒ 不猜了。这个工具做两件事:
  ① **连续录**: 按固定步长把 [from, to] 整段拍下来(走已有的 `VFXLAB_SHOTS` 环境变量,
     不用改产品代码)
  ② **在整段里找**: 逐帧与**基线帧**做差分, 只数"新出现的、且属于目标配色"的像素,
     把峰值时刻排出来, 并拼一张接触印相

★判据为什么要差分而不是绝对色阈值: memory `fb-color-criteria-need-clean-background`
  —— 地图/龟身本来就有大片同色系像素, 绝对阈值的基线不为零, 量出来是噪声。
  差分只看"这一帧比基线多出来的"。
★`--auto` 不给颜色: 退化成"整帧差分最大的时刻", 适合先粗定位再补颜色。
"""
import argparse
import glob
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe"


def _hex(s):
    s = s.strip().lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))


def run_case(case, shots, glow=True):
    env = dict(os.environ)
    env["VFXLAB"] = "1"
    env["VFXLAB_CASE"] = case
    env["VFXLAB_SHOTS"] = ",".join("%.3f" % t for t in shots)
    if glow:
        env["VFXLAB_GLOW"] = "1"
    for f in glob.glob(os.path.join(ROOT, "_vfxlab_%s_*.png" % case)):
        os.remove(f)
    ## ★★ env=env 一定要传! 第一版漏了这个参数 ⇒ VFXLAB 环境变量没进去,
    ##   跑的是**普通游戏**不是台子 ⇒ 永不退出。我一度以为是扫描慢卡了 30 分钟,
    ##   实际是这一行少了三个字符。(同族: memory fb-gate-subject-never-constructed
    ##   —— 判据没错, 被测对象根本不在场。)
    p = subprocess.run([GODOT, "--path", ROOT, "--audio-driver", "Dummy",
                        "--position", "5000,5000", "res://scenes/RealtimeBattle3D.tscn"],
                       cwd=ROOT, env=env, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=300)
    fs = sorted(glob.glob(os.path.join(ROOT, "_vfxlab_%s_*.png" % case)),
                key=lambda q: int(q.split("_")[-1].split(".")[0]))
    return fs, p.returncode


def scan(files, shots, colors, tol, ui_margin):
    """逐帧与基线做差分, 只数【新出现且属于目标配色】的像素。

    ★★用 numpy 向量化。第一版是纯 Python 三重循环 —— 201 帧 x 100 万像素
      跑了 **30 分钟还没出结果**, 我一度以为是 Godot 卡住了(实测拍 60 帧只要 40 秒,
      慢的从来是扫描这一步)。判据一个字没变, 只是换了算法。
    """
    import numpy as np
    base = np.asarray(Image.open(files[0]).convert("RGB"), dtype=np.int16)
    H, W, _ = base.shape
    x0, x1 = ui_margin[0], W - ui_margin[1]
    y0, y1 = ui_margin[2], H - ui_margin[3]
    b = base[y0:y1, x0:x1, :]
    out = []
    for i, f in enumerate(files):
        a = np.asarray(Image.open(f).convert("RGB"), dtype=np.int16)[y0:y1, x0:x1, :]
        changed = np.any(a != b, axis=2)
        if not colors:
            d = np.abs(a - b).sum(axis=2)
            n = int(np.count_nonzero(changed & (d > 90)))
        else:
            hit = np.zeros(changed.shape, dtype=bool)
            for c in colors:
                cc = np.array(c, dtype=np.int16)
                hit |= np.all(np.abs(a - cc) <= tol, axis=2)
            n = int(np.count_nonzero(changed & hit))
        out.append((n, i, shots[i] if i < len(shots) else -1.0))
    return out


def sheet(files, picks, shots, path, cw=420, ch=170, zoom=2):
    if not picks:
        return
    W, H = Image.open(files[0]).size
    cols = min(2, len(picks))
    rows = (len(picks) + cols - 1) // cols
    o = Image.new("RGB", (cw * zoom * cols + 16, (ch * zoom + 16) * rows + 8), (24, 26, 32))
    d = ImageDraw.Draw(o)
    for k, i in enumerate(picks):
        im = Image.open(files[i]).convert("RGB")
        c = im.crop((W // 2 - cw // 2, H // 2 - ch // 2 - 10,
                     W // 2 + cw // 2, H // 2 + ch // 2 - 10)).resize((cw * zoom, ch * zoom),
                                                                     Image.NEAREST)
        x = 4 + (k % cols) * (cw * zoom + 8)
        y = 4 + (k // cols) * (ch * zoom + 16)
        o.paste(c, (x, y))
        d.text((x + 3, y + ch * zoom + 1), "f%d  t=%.2fs" % (i, shots[i]), fill=(255, 255, 0))
    o.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case")
    ap.add_argument("--from", dest="t0", type=float, required=True)
    ap.add_argument("--to", dest="t1", type=float, required=True)
    ap.add_argument("--step", type=float, default=0.15)
    ap.add_argument("--colors", default="", help="逗号分隔的 hex(不含#); 留空用 --auto")
    ap.add_argument("--auto", action="store_true", help="不给配色: 只找整帧差分最大的时刻")
    ap.add_argument("--tol", type=int, default=16)
    ap.add_argument("--top", type=int, default=4)
    ap.add_argument("--out", default="")
    a = ap.parse_args()

    shots = []
    t = a.t0
    while t <= a.t1 + 1e-6:
        shots.append(round(t, 3))
        t += a.step
    print("录 %d 帧: %.2f~%.2fs 每 %.2fs 一帧" % (len(shots), a.t0, a.t1, a.step))

    files, rc = run_case(a.case, shots)
    print("  实际拍到 %d 帧 (godot rc=%d)" % (len(files), rc))
    if len(files) < 3:
        print("[FAIL] 帧太少 —— 台子可能没跑起来, 或 dur 短于窗口")
        return 1
    if len(files) < len(shots):
        print("  ⚠ 少于请求的 %d 帧: 台子 dur 可能没覆盖到 %.1fs" % (len(shots), a.t1))

    colors = [] if a.auto else [_hex(c) for c in a.colors.split(",") if c.strip()]
    res = scan(files, shots, colors, a.tol, (200, 250, 100, 140))
    hits = [r for r in res if r[0] > 0]
    print("")
    print("  有目标像素的帧: %d / %d" % (len(hits), len(res)))
    if not hits:
        print("[FAIL] ★整段都没找到 —— 要么配色给错了, 要么这一段里它真的没出现")
        print("       (先用 --auto 粗定位: 它会报整帧差分最大的时刻)")
        return 1
    first = min(hits, key=lambda r: r[1])
    print("  **首次出现**: f%d  t=%.2fs  (%d px)" % (first[1], first[2], first[0]))
    res.sort(reverse=True)
    print("  峰值 top%d:" % a.top)
    for n, i, ts in res[:a.top]:
        print("     f%-3d t=%6.2fs  %d px" % (i, ts, n))
    picks = sorted(i for _n, i, _t in res[:a.top])
    out = a.out or os.path.join(ROOT, "_vfxscan_%s.png" % a.case)
    sheet(files, picks, shots, out)
    print("  接触印相 → %s" % out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
