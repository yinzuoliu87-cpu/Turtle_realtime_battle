# -*- coding: utf-8 -*-
"""glow_ball_audit.py — 「无含义白球」的存量台账：`VfxTex._make_fire_glow_tex()`。

★★为什么有这个东西：
  `_make_fire_glow_tex()` 生成的是一颗**程序化软光球**。用户点名否过这个形状两次
  （memory `fb-vfx-defect-families` 把「无含义圆环与白球」列为禁区形状；
   `fb-fix-the-shared-primitive-not-one-instance`：共享原语被否就换原语，
   而不是给单件开口子）。

  2026-09-14 做 059 沙漏时又撞上两处：
    · 时之主身上罩的那颗金球（染色确认就是它）——换成了 `ts-sand.png`
    · 释放瞬间那颗从 60 码 tween 放大到 900 码的白球——换成了 `ts-vortex.png`
  一处一处替是**打地鼠**：全仓还有 **112 处**。

★这个文件不负责"修"，负责**不让它继续长**：
  存量按文件记账，**只减不增**。替掉一处就把数字改小；新增一处当场红。
  ⇒ 以后谁再想拿白球顶替，提交前就会被挡住，不靠谁记得。

★为什么不直接全仓替：112 处分布在 19 个文件、每一处的语义都不同
  （有的是火花、有的是拖尾、有的是聚能）。**逐处替需要各自的参考与逐帧研究**，
  那是一件一件的活；这里先把口子焊住，避免边替边漏。
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CALL = re.compile(r"VfxTex\._make_fire_glow_tex\s*\(")

## ── 台账：文件 → 允许的调用点数。**只减不增。** ──
## ★这张表是**从真扫描生成**的, 不是手抄 —— 我第一版照着被 `head -12` 截断的清单手写,
##   漏了 13 个文件(dragon/angel/chest/ice/phoenix/smolder/trainer…), 跑起来当场红 25 处。
##   memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后。
LEDGER = {
    "scripts/scenes/RealtimeBattle3DScene.gd": 17,
    "scripts/systems/skills/headless_system.gd": 11,
    "scripts/scenes/battle/gun_eq_vfx.gd": 8,
    "scripts/systems/skills/hiding_system.gd": 8,
    "scripts/systems/skills/shell_system.gd": 7,
    "scripts/systems/skills/lava_system.gd": 5,
    "scripts/systems/skills/rocket_system.gd": 5,
    "scripts/systems/skills/star_system.gd": 5,
    "scripts/systems/skills/crystal_system.gd": 4,
    "scripts/systems/skills/cyber_system.gd": 4,
    "scripts/systems/skills/elite_system.gd": 4,
    "scripts/systems/skills/phoenix_system.gd": 3,
    "scripts/systems/skills/smolder_system.gd": 3,
    "scripts/scenes/battle/blade_eq_vfx.gd": 2,
    "scripts/systems/equip/dragon_system.gd": 2,
    "scripts/systems/skills/chest_system.gd": 2,
    "scripts/systems/skills/ice_system.gd": 2,
    "scripts/scenes/battle/battle_ballistics.gd": 1,
    "scripts/scenes/battle/battle_spawn.gd": 1,
    "scripts/scenes/battle/synergy_vfx.gd": 1,
    "scripts/systems/skills/angel_system.gd": 1,
    "scripts/systems/trainer/trainer_system.gd": 1,
}


def scan():
    hits = {}
    n = 0
    for dirpath, _d, names in os.walk(os.path.join(ROOT, "scripts")):
        for nm in names:
            if not nm.endswith(".gd"):
                continue
            p = os.path.join(dirpath, nm)
            rel = os.path.relpath(p, ROOT).replace("\\", "/")
            txt = io.open(p, encoding="utf-8", newline="").read()
            c = 0
            for line in txt.split("\n"):
                i = line.find("#")
                code = line if i < 0 else line[:i]
                c += len(CALL.findall(code))
            n += 1
            if c:
                hits[rel] = c
    return hits, n


def main():
    hits, nfiles = scan()
    total = sum(hits.values())
    print("=== 无含义白球台账 `VfxTex._make_fire_glow_tex()`(只减不增) ===")
    print("  [分母] 扫描 %d 个 .gd · 实测调用点 %d 处 · 台账登记 %d 处(%d 个文件)"
          % (nfiles, total, sum(LEDGER.values()), len(LEDGER)))
    bad = []
    for rel in sorted(set(list(hits.keys()) + list(LEDGER.keys()))):
        got = hits.get(rel, 0)
        cap = LEDGER.get(rel, 0)
        if got > cap:
            bad.append("[FAIL] %s: 白球 %d 处 > 台账 %d 处 —— **新增了一处**。\n"
                       "       「无含义圆环与白球」是本仓点名过的禁区形状(用户否过两次)。\n"
                       "       要么换成有含义的形状(照参考逐帧量了再烤, 见 059 的 ts-sand / ts-core / ts-aura),\n"
                       "       要么在 tools/glow_ball_audit.py 的 LEDGER 里说明为什么这一处必须是白球。"
                       % (rel, got, cap))
        elif got < cap:
            bad.append("[FAIL] %s: 白球只剩 %d 处(台账写着 %d) —— 修好了就把台账改小, 棘轮只减不增。"
                       % (rel, got, cap))
    ## 台账外的文件只要有一处就是新增
    for rel, got in sorted(hits.items()):
        if rel not in LEDGER:
            bad.append("[FAIL] %s: 白球 %d 处, **不在台账里** —— 新增的当场红。" % (rel, got))
    print("")
    if bad:
        for b in bad:
            print(b)
        print("FAILED: %d 处" % len(bad))
        return 1
    print("  [台账] 存量 %d 处待逐个替换(每一处都要各自的参考与逐帧研究, 不一刀切)" % total)
    print("ALL OK — 白球没有新增")
    return 0


if __name__ == "__main__":
    sys.exit(main())
