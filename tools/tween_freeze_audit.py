# -*- coding: utf-8 -*-
"""tween_freeze_audit.py — 战斗世界侧的 tween 必须走 `_reg_tween()`，否则时停冻不住它。

★★为什么有这个东西（用户 2026-09-14）：
  「这个装备我看有很多有问题的地方，**很多特效没有冻结**」——说的是 059 沙漏的时停。

  他是对的，而且能量出来。探针实测（`tests/verify_timestop_freeze.gd` 那套采样）：
  时停期间 `battle._world` 里 **56 个 Node3D 照常在动**，位移量和时停前一模一样
  （背景鱼群 Δpos 1.4112 → 1.4188、气泡 1.1063 → 1.1122）。

  根因不是"漏了某一处"，是**战斗世界侧有 23 处直接 `create_tween()`**：
  它们从来没进过 `battle._sim_tweens` ⇒ `_ts_begin_freeze()` 遍历那个数组时根本找不到它们。

  `RealtimeBattle3DScene.gd` 第 48 行的注释**早就写着**
  「VFX工具(277) 散在 8 处, 且依赖 _reg_tween 的时停契约(**漏注册=时停静默失效**)」——
  契约在，但**没有任何东西守着它**，于是一年里慢慢漏了 23 处。
  memory `fb-weld-visual-lessons-into-gate`：**memory 靠我想起来，门禁自己会红。**

★判据：战斗侧源码里每出现一次裸 `create_tween()`，都必须在下面的白名单里，
  且每个文件的条数**只减不增**。新写的一处没登记 ⇒ 当场红。

★为什么是白名单而不是"一律禁止"：有三类**本来就不该冻**的：
  ① 时停自己的演出（反色闪 / 扩散 / 停摆钟 / 时之主金辉光）——冻了就什么都看不见；
  ② UI 层（飘字 / 血条 / 结算面板 / 换路流程）——时停期间只有携带者能动，
     它打出的伤害数字该正常飞；灰世界叠加层本来就压在 UI 层之下（`layer = 5`）；
  ③ `_reg_tween()` 自己的实现。
  判据必须刚好卡住"**世界里的演出**不许绕开"这个形状（memory `fb-judge-must-fit-the-shape`）。
"""
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 扫这些地方 —— 它们的演出都活在 `battle._world` 里，时停必须管得着
SCAN_DIRS = [
    os.path.join("scripts", "scenes", "battle"),
    os.path.join("scripts", "systems"),
]
SCAN_FILES = [os.path.join("scripts", "scenes", "RealtimeBattle3DScene.gd")]

# ── 台账：文件 → (允许条数, 为什么它不该冻) ──
# ★只减不增。修掉一处就把数字改小；想加一处必须在这里写清楚**为什么它不该被时停冻住**。
ALLOW = {
    "scripts/scenes/RealtimeBattle3DScene.gd": (
        1, "`_reg_tween()` 自己的实现（第 2359 行），就是那个注册口本身"),
    "scripts/systems/equip/timestop_system.gd": (
        # 10 → 9 (v0.19.381): 时之主那颗白球换成时之砂后不再需要脉动 tween，
        #   帧号由 `_ts_tick_visual` 按真实时间推。棘轮只减不增，所以这里跟着改小。
        9, "时停【自己】的演出：反色闪 / 压暗扩散 / 停摆钟 / 蓄力沙漏。"
            "冻了就等于时停没有画面"),
    "scripts/scenes/battle/battle_hud.gd": (
        4, "UI 层（HUD 面板动效），不在 `_world` 里"),
    "scripts/scenes/battle/battle_vfx.gd": (
        3, "飘字（伤害/治疗数字，CanvasLayer）。时停期间只有携带者能动，"
           "它打出的数字该正常飞；灰世界叠加层本来就压在 UI 之下（`layer = 5`）"),
    "scripts/scenes/battle/dual_lane_flow.gd": (
        4, "双路换路流程的转场 UI，不在 `_world` 里"),
}

CALL = re.compile(r"(?<!_reg_tween\(\)\.)\bcreate_tween\s*\(\s*\)")


def strip_comment(line):
    """把行内注释去掉（只讨论代码里真的调用）。字符串里出现 `#` 的情况本仓没有。"""
    i = line.find("#")
    return line if i < 0 else line[:i]


def scan():
    hits = {}
    files = []
    for d in SCAN_DIRS:
        for dirpath, _dirs, names in os.walk(os.path.join(ROOT, d)):
            for n in names:
                if n.endswith(".gd"):
                    files.append(os.path.join(dirpath, n))
    for f in SCAN_FILES:
        files.append(os.path.join(ROOT, f))

    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        with open(path, encoding="utf-8", newline="") as fh:
            for i, line in enumerate(fh.read().split("\n"), 1):
                code = strip_comment(line)
                if "_reg_tween" in code:
                    continue
                if CALL.search(code):
                    hits.setdefault(rel, []).append((i, line.strip()[:100]))
    return hits, len(files)


def main():
    hits, nfiles = scan()
    print("=== 战斗侧 tween 冻结契约（裸 create_tween() 必须登记）===")
    print("  [分母] 扫描 %d 个 .gd（battle 场景层 + systems + 主场景）" % nfiles)
    print("  [分母] 台账登记 %d 个文件、共 %d 条豁免"
          % (len(ALLOW), sum(v[0] for v in ALLOW.values())))

    bad = []
    for rel, rows in sorted(hits.items()):
        cap, why = ALLOW.get(rel, (0, ""))
        if len(rows) > cap:
            bad.append("[FAIL] %s: 裸 create_tween() %d 处 > 台账允许 %d 处\n"
                       "       新增的这些没走 `_reg_tween()` ⇒ 时停期间它们不会被冻住。\n"
                       "       行号: %s\n"
                       "       要么改成 `battle._reg_tween()`（世界里的演出都该这样），\n"
                       "       要么在 tools/tween_freeze_audit.py 的 ALLOW 里说明为什么它不该冻。"
                       % (rel, len(rows), cap, [r[0] for r in rows]))
        elif len(rows) < cap:
            bad.append("[FAIL] %s: 裸 create_tween() 只剩 %d 处（台账写着 %d）——\n"
                       "       修好了就把台账改小，棘轮只减不增。" % (rel, len(rows), cap))
        else:
            print("  [OK] %-52s %d 处 · %s" % (rel, len(rows), why))

    for rel in ALLOW:
        if rel not in hits and ALLOW[rel][0] > 0:
            bad.append("[FAIL] %s: 台账写着 %d 处豁免，实际一处都没有（文件没了/已清零）——把它从 ALLOW 删掉"
                       % (rel, ALLOW[rel][0]))

    print("")
    if bad:
        for b in bad:
            print(b)
        print("FAILED: %d 处违规" % len(bad))
        return 1
    print("ALL OK — 战斗世界侧的演出 tween 全部走 `_reg_tween()`（时停能冻得住）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
