# -*- coding: utf-8 -*-
"""vfxlab_show.py — 开一个给用户看的 VFXLAB 窗口, **并自动截屏核实画面里真是那件东西**。

    python tools/vfxlab_show.py p2eq_021 [--wait 9] [--shots 3]

════════════════════════════════════════════════════════════════════════
 ★为什么有这个东西 (用户 2026-09-12)
════════════════════════════════════════════════════════════════════════
「**停，你知道你在看什么吗，又在浪费时间吗，你对着主菜单背景在看什么**」

他是对的。我开了 021 的 HOLD 窗口就叫他看, 而那个窗口里**战斗已经打完了** ——
021 的台子 `attacker: true` 且只有 2 个敌人, 携带者把它们杀光 ⇒ 战斗判定结束
⇒ 场景掉回**主菜单**。他盯着主菜单背景, 我在旁边讲「看那道绿色绑定光束」。

**根因不是那个 bug, 是我从来没核实过窗口里在放什么。**
(memory `fb-gate-subject-never-constructed`: 判据没错, 被测对象根本不在场;
 以及 `fb-wake-by-background-task-not-schedulewakeup`: 没核实就用确定口气汇报 = 欺骗。)

⇒ 两条一起修:
  ① 结构上: `VFXLAB_HOLD` 时假人锁成不死, 战斗不可能结束(见 battle_vfx_lab 同名注释)
  ② 流程上: **本脚本** —— 开窗 → 等落位 → 连拍窗口区域 → 存盘让我自己先看过,
     并机检两条硬指标(画面不是静止的 / 不是满屏 UI), 才允许报「窗口好了」

★截屏必须 DPI 感知(memory `fb-screenshot-must-be-dpi-aware`): 不加 SetProcessDPIAware
  只截得到左上 2/3, 右半屏全丢, 我曾因此把弹窗误判成"页面被挡住"。
★窗口必须 Start-Process 起(memory `fb-vfxlab-window-must-be-muted`):
  Bash 后台起的会跟着 shell 被收掉; 且必须 `--audio-driver Dummy` 静音。
"""
import argparse
import ctypes
import os
import subprocess
import sys
import time

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = r"C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe"
OUT_DIR = os.path.join(ROOT, "_show")


class RECT(ctypes.Structure):
    _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                ("right", ctypes.c_long), ("bottom", ctypes.c_long)]


def window_rect(pid):
    """拿这个进程的主窗口矩形(虚拟桌面绝对坐标)。"""
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def cb(hwnd, _lp):
        p = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            r = RECT()
            user32.GetWindowRect(hwnd, ctypes.byref(r))
            if (r.right - r.left) > 200 and (r.bottom - r.top) > 200:
                found.append((r.left, r.top, r.right, r.bottom))
        return True

    user32.EnumWindows(cb, 0)
    return found[0] if found else None


def grab(box):
    ## ★DPI 感知: 不加这一句只截得到左上 2/3
    ctypes.windll.user32.SetProcessDPIAware()
    from PIL import ImageGrab
    return ImageGrab.grab(bbox=box, all_screens=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case")
    ap.add_argument("--wait", type=float, default=9.0, help="开窗后等几秒再拍(等战斗跑起来)")
    ap.add_argument("--shots", type=int, default=3, help="连拍几张(用来证明画面在动)")
    ap.add_argument("--gap", type=float, default=1.6)
    a = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)

    env = dict(os.environ)
    env.update({"VFXLAB": "1", "VFXLAB_CASE": a.case, "VFXLAB_HOLD": "1", "VFXLAB_GLOW": "1"})
    ## ★DETACHED: 不跟着这个 shell 被收掉
    DETACHED = 0x00000008 | 0x00000200
    p = subprocess.Popen([GODOT, "--path", ROOT, "--audio-driver", "Dummy",
                          "res://scenes/RealtimeBattle3D.tscn"],
                         cwd=ROOT, env=env, creationflags=DETACHED)
    print("PID=%d  case=%s" % (p.pid, a.case))
    time.sleep(a.wait)
    if p.poll() is not None:
        print("[FAIL] ★进程已退出 —— 窗口根本没起来")
        return 1
    box = window_rect(p.pid)
    if box is None:
        print("[FAIL] ★找不到这个进程的可见窗口")
        return 1
    print("窗口 %s  (%dx%d)" % (box, box[2] - box[0], box[3] - box[1]))

    import numpy as np
    frames = []
    for i in range(a.shots):
        im = grab(box)
        f = os.path.join(OUT_DIR, "%s_%d.png" % (a.case, i))
        im.save(f)
        frames.append(np.asarray(im.convert("RGB"), dtype=np.int16))
        print("  拍到 %s" % f)
        if i < a.shots - 1:
            time.sleep(a.gap)

    ## ── 机检两条硬指标(它们只是兜底; 最后一定要我自己看那几张图) ──
    ok = True
    diff = int(np.count_nonzero(np.any(frames[-1] != frames[0], axis=2)))
    tot = frames[0].shape[0] * frames[0].shape[1]
    print("")
    print("  [分母] 窗口 %d 像素" % tot)
    print("  ① 画面在动: 首末两张有 %d px 不同 (%.2f%%)" % (diff, 100.0 * diff / tot))
    if diff < tot * 0.002:
        print("  [FAIL] ★画面几乎静止 —— 可能是主菜单/结算屏, 不是在跑的战斗")
        ok = False
    ## 主菜单是**亮底满屏 UI**, 台子是**黑场 + 几只龟** ⇒ 用暗像素占比分开
    dark = int(np.count_nonzero(frames[-1].sum(axis=2) < 120))
    print("  ② 暗像素占比 %.1f%% (台子黑场应 > 70%%; 主菜单满屏 UI 远低于此)"
          % (100.0 * dark / tot))
    if dark < tot * 0.70:
        print("  [FAIL] ★暗像素太少 —— 画面里多半是 UI(主菜单/结算屏), 不是黑场台子")
        ok = False
    print("")
    print("窗口可看" if ok else "[FAIL] ★别报给用户 —— 先弄清楚窗口里在放什么")
    print("★机检只是兜底: 报给用户之前**必须自己打开那几张图看一眼**。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
