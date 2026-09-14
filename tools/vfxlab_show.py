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
import io
import re
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


def raise_window(pid):
    """把窗口抬到最上层 —— **不抬就会截到盖在它上面的别的窗口**。

    ★2026-09-12 实拍抓到: 022 那次截出来整幅是 **VS Code**, 游戏窗口被压在下面,
      只露出左上角一条标题栏。两条机检还全绿(见下面 ② 的注释)。
    ★`SetForegroundWindow` 在这里**没用**: Windows 的前台锁不让后台进程抢焦点,
      调了返回 false、窗口纹丝不动。有效的是 `SetWindowPos(HWND_TOPMOST)`。
    """
    user32 = ctypes.windll.user32
    found = []

    @ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)
    def cb(hwnd, _lp):
        p = ctypes.c_ulong()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(p))
        if p.value == pid and user32.IsWindowVisible(hwnd):
            found.append(hwnd)
        return True

    user32.EnumWindows(cb, 0)
    for h in found:
        ## HWND_TOPMOST = -1; SWP_NOSIZE|SWP_NOMOVE|SWP_SHOWWINDOW = 0x0001|0x0002|0x0040
        user32.SetWindowPos(ctypes.c_void_p(h), ctypes.c_void_p(-1), 0, 0, 0, 0, 0x0043)
    return len(found)


def grab(box):
    ## ★DPI 感知: 不加这一句只截得到左上 2/3
    ctypes.windll.user32.SetProcessDPIAware()
    from PIL import ImageGrab
    return ImageGrab.grab(bbox=box, all_screens=True)


def _case_flag(case_id, flag):
    """从**真的那张表**里读 case 的一个 bool 字段(不维护第二份名单)。

    只给自检用: `realmap` 台子不是黑场, 拿黑场阈值判它会每次误红。
    """
    src = os.path.join(ROOT, "scripts", "gamedata", "vfxlab_cases.gd")
    txt = io.open(src, encoding="utf-8", newline="").read()
    blocks = re.split(r'^"([^"]+)":\s*\{', txt, flags=re.M)
    for i in range(1, len(blocks) - 1, 2):
        body = blocks[i + 1]
        hit = blocks[i] == case_id or re.search(r'"eq":\s*"%s"' % re.escape(case_id), body)
        if hit:
            return re.search(r'"%s":\s*true' % re.escape(flag), body) is not None
    return False


def _check_case(case_id):
    """case 登记过没有? 没登记就给出最可能的正确键名。

    判据落在**真的那张表**(scripts/gamedata/vfxlab_cases.gd)上, 不维护第二份名单 ——
    维护第二份名单就是"手抄的副本必然落后"(memory [[fb-hand-rolled-copies-drift]])。
    """
    src = os.path.join(ROOT, "scripts", "gamedata", "vfxlab_cases.gd")
    txt = io.open(src, encoding="utf-8", newline="").read()
    keys = re.findall(r'^"([^"]+)":\s*\{', txt, re.M)
    if case_id in keys:
        return True, ""
    ## 同一件装备常常登记在别的键下(法器组是 staff_xxx) —— 按 `"eq": "<id>"` 反查。
    alt = []
    blocks = re.split(r'^"([^"]+)":\s*\{', txt, flags=re.M)
    for i in range(1, len(blocks) - 1, 2):
        k = blocks[i]
        body = blocks[i + 1]
        m = re.search(r'"eq":\s*"([^"]+)"', body)
        if m and m.group(1) == case_id:
            alt.append(k)
    if alt:
        return False, " 这件装备登记在: %s —— 用那个键名。" % ", ".join(alt)
    return False, " 已登记的键共 %d 个; `VFXLAB_CASE=list` 可以打印全部。" % len(keys)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case")
    ap.add_argument("--wait", type=float, default=9.0, help="开窗后等几秒再拍(等战斗跑起来)")
    ap.add_argument("--shots", type=int, default=3, help="连拍几张(用来证明画面在动)")
    ap.add_argument("--gap", type=float, default=1.6)
    a = ap.parse_args()
    os.makedirs(OUT_DIR, exist_ok=True)

    ## ★★开窗前先查这个 case **登记过没有** (2026-09-14 加)。
    ##   由来: 用户看 043 的窗口 ——「你这个展示的什么」。我传的是 `p2eq_043`,
    ##   而 043 是法器, 台子键名是 `staff_043`。`VfxLabCases.get_case()` 对
    ##   **未登记的 id 是回落到 DEFAULT 的**(它自己注释就写着"只是配得不准"),
    ##   于是建了个缺省场: 一只龟、镜头怼脸、法力没灌 ⇒ 浪墙根本不会发生。
    ##   下面那两条机检(画面在动 / 是黑场)**全绿** —— 它们管的是"截没截对窗口",
    ##   管不了"台子是不是那件"(memory [[fb-gate-subject-never-constructed]]:
    ##   判据没错, 被测对象根本不在场)。
    ok_id, hint = _check_case(a.case)
    if not ok_id:
        print("[FAIL] ★case `%s` **没有登记** —— 开出来会是回落的缺省场, 不是这件东西。%s"
              % (a.case, hint))
        return 1

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
    nraise = raise_window(p.pid)
    print("  置顶了 %d 个窗口(不置顶会截到盖在上面的别的窗口)" % nraise)
    time.sleep(1.2)

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
    ## ★这一条**单独用会被骗**: 截到 VS Code 时它也在动(我自己的对话在刷新),
    ##   实测 1.71% 照样过。所以它必须和 ② 一起看 —— ② 才管「截的是不是游戏」。
    ## ★★判据换过一次, 原因写清楚: 第一版判的是「亮度 < 70 的像素占比 > 70%」,
    ##   而 **VS Code 的深色主题是 #1f1f1f(亮度 31)**, 一样满足 —— 实测:
    ##       被 VS Code 挡住那张  亮度<70 占 96.0%   ← 第一版判它「通过」
    ##       真·台子那张          亮度<70 占 95.2%
    ##   **两边都是 95%, 这条等于没判。** 换成**近纯黑(亮度 ≤10)**才分得开:
    ##       被 VS Code 挡住      近纯黑 19.4%
    ##       真·台子(有火)        近纯黑 93.1%
    ##       真·台子(火熄灭)      近纯黑 93.7%
    ##   阈值 70% 两边留着极大余量。台子是真·黑场(0,0,0), 任何 IDE/浏览器的
    ##   「深色主题」都到不了纯黑 —— 这才是能把「截错窗口」判红的那个量。
    ## ★★量的必须是**亮度**, 不是「三通道都 ≤10」—— 台子背景是 (2,4,11):
    ##   亮度 3.8(合格) 但**最大通道 11**(不合格) ⇒ 写成 max(axis=2) 的那一版
    ##   把真台子判成 0.4%, 当场误红。标定用哪个量, 实现就得用哪个量
    ##   (memory [[fb-verify-check-can-fail]]: 新尺子先拿已知答案的样本量一遍)。
    _lum = (frames[-1][..., 0] * 299 + frames[-1][..., 1] * 587
            + frames[-1][..., 2] * 114) // 1000
    black = int(np.count_nonzero(_lum <= 10))
    ## ★`realmap: true` 的台子**本来就不是黑场**(它要看的就是世界本身, 比如 059 时停:
    ##   全场定格 —— 黑场里连世界都没有)。拿黑场阈值去判它 = 每次都喊狼来了,
    ##   而"狼来了"喊多了就等于没有这条自检(memory [[fb-judge-must-fit-the-shape]]:
    ##   判据要刚好卡住那个形状)。⇒ realmap 台子改判"别的窗口盖上来"这个真问题:
    ##   游戏窗口是深色的, 而盖上来的编辑器/浏览器要亮得多。
    _realmap = _case_flag(a.case, "realmap")
    if _realmap:
        _mean = float(_lum.mean())
        print("  ② `realmap` 台子(真实地图·本来就不是黑场): 近纯黑 %.1f%% · 平均亮度 %.1f"
              % (100.0 * black / tot, _mean))
        if _mean > 110.0:
            print("  [FAIL] ★画面太亮 —— 多半截到了**盖在游戏上面的别的窗口**"
                  "(游戏是深色海底图, 平均亮度实测 40~70)")
            ok = False
    else:
        print("  ② 近纯黑(亮度≤10)占比 %.1f%% (台子黑场 >90%%; VS Code 深色主题只有 ~19%%)"
              % (100.0 * black / tot))
        if black < tot * 0.70:
            print("  [FAIL] ★不是黑场台子 —— 多半截到了**盖在游戏上面的别的窗口**,"
                  " 或者掉回了主菜单/结算屏")
            ok = False
    print("")
    print("窗口可看" if ok else "[FAIL] ★别报给用户 —— 先弄清楚窗口里在放什么")
    print("★机检只是兜底: 报给用户之前**必须自己打开那几张图看一眼**。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
