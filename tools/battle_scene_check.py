# -*- coding: utf-8 -*-
"""战场画面的**实拍**门禁 (2026-10-02 建)。

`tools/battle_scene_audit.py` 量得很细, 但它要**手工喂一张图** ——
于是方案书 `20260918-战斗场景美术重做.md` / `20260918b-战斗场景整体重做.md` 里
那几条验收项长年写着「**已达标但无门禁**」。没人跑的量尺 = 画面可以静默退回去,
而本仓已经吃过这一类的亏(memory `fb-zero-caller-is-a-whole-class`)。

这个脚本把「拍 + 量 + 判」接成一条, 进 `run-tests.sh`。

★拍摄口径钉死在下面的 SHOT 里, **不许随手改**: 同一场战斗
  540x960 量出 13.58% / 1280x720 量出 18.74% / 1920x1080 量出 18.40%
  —— 换分辨率就不是同一件事了(台账 `tests/golden/battle_scene_debt.txt` 里有这张表)。

★★本条是【本地专属审计】: 它开真窗口截图(--position 5000,5000 把窗口丢到屏幕外),
  无显示设备的机器(GitHub runner)跑不了, 会干净跳过并返回 0。
  这件事本身由 `tools/ci_deps_audit.py` 的 LOCAL_ONLY 名单守着 ——
  它会**真把本脚本跑一遍**(强制无显示设备), 确认确实干净跳过, 所以这条登记不会是假的。

跑法:
    python tools/battle_scene_check.py
"""
import os
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))

GODOT = os.environ.get("GODOT", "C:/Users/Louis/Desktop/Godot_v4.6.3-stable_win64.exe")
OUT = os.path.join(os.environ.get("TEMP", "/tmp"), "turtle_battle_scene_check.png")

## ★拍摄口径 —— 改这里之前先读台账里那张「换分辨率就不是同一件事」的表。
SHOT_RES = "1280x720"
SHOT_SEC = "4"        # SELFSHOT: 等 4 秒真实时间, 让战斗跑起来(单位已经在打了)
SHOT_FRAMES = "900"   # --quit-after 是【帧】不是毫秒; 600 帧不够(拍不到), 900 够

SKIP_MARK = "本条为【本地专属审计】: 它开真窗口截图, 无显示设备的机器跑不了"


def _no_display():
    ## ★强制开关给 ci_deps_audit 用 —— 它要在有显示设备的本机上验「跳过这条路真的走得通」。
    if os.environ.get("TURTLE_FORCE_NO_DISPLAY") == "1":
        return True
    if os.name == "nt":
        return False
    return not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))


def shoot():
    if os.path.exists(OUT):
        os.remove(OUT)
    env = dict(os.environ)
    env.update({
        "SHIP": "1",            # 关 demo 劫持, 否则假人永不死(CLAUDE.md §4)
        "QUIET": "1",           # ★开窗口也必须静音 —— 用户 2026-10-01 点名的那条
        "SELFSHOT": SHOT_SEC,
        "SHOT_OUT": OUT.replace("\\", "/"),
    })
    subprocess.run(
        [GODOT, "--audio-driver", "Dummy", "--path", ROOT,
         "--resolution", SHOT_RES, "--position", "5000,5000",
         "res://scenes/RealtimeBattle3D.tscn", "--quit-after", SHOT_FRAMES],
        env=env, capture_output=True, timeout=180)
    return os.path.exists(OUT)


def main():
    if _no_display():
        print("  [SKIP] " + SKIP_MARK)
        return 0

    if not os.path.exists(GODOT):
        print("  [FAIL] 找不到 Godot: %s (用 GODOT=... 指过来)" % GODOT)
        return 1

    if not shoot():
        ## ★这条不许降级成 SKIP: 拍不到就是没验, 不是"通过"。
        print("  [FAIL] 一张都没拍到 —— 战斗场景没跑起来 (期望 %s)" % OUT)
        return 1

    import battle_scene_audit as A
    a = A.audit(OUT)
    if a is None:
        print("  [FAIL] 量不出来(图读不了?)")
        return 1

    rules = A.verdict(a)
    print("  [分母] 实拍 %dx%d → 场地区 %dx%d · 采样 %d 点 · 判据 %d 条"
          % (a["size"][0], a["size"][1], a["crop"][0], a["crop"][1], a["samples"], len(rules)))
    if len(rules) < 5:
        print("  [FAIL] 判据只有 %d 条 —— 少于 5 条说明有判据没跑(空检查)" % len(rules))
        return 1

    bad = 0
    for name, ok, got in rules:
        print("  [%s] %-30s 实测 %s" % ("PASS" if ok else "FAIL", name, got))
        if not ok:
            bad += 1
    print("")
    if bad:
        print("FAILED: %d 条" % bad)
        return 1
    print("ALL OK — 战场画面实拍(%d 条全达标)" % len(rules))
    return 0


# ★ __main__ 守卫: 别的脚本要 import 本文件复用它的判据函数(不另抄一份口径);
#   没有守卫时 import 会当场跑完审计并 sys.exit, **把调用方静默掐死**。
if __name__ == "__main__":
    sys.exit(main())
