# -*- coding: utf-8 -*-
"""tween_capture_audit.py — 演出 tween 的 lambda 捕获了【可能被释放的节点】

════════════════════════════════════════════════════════════════════════
 ★为什么非有这条门禁不可(2026-09-25 v0.19.443 的 CI 红)
════════════════════════════════════════════════════════════════════════
`verify_equip_batch_20260801` 在 CI 上 **`rc=0`、125 条断言全过**，却被判 FAIL ——
判红的是 `run-tests.sh` 致命报错正则里的 `Lambda capture`，3 条
`Lambda capture at index 0 was freed. Passed "null" instead.`

★★**在 lambda 里写 `is_instance_valid(spr)` 挡不住它**：
  Godot 在**调用之前**就发现捕获的 Object 没了，先打那条错、再把 null 传进来。
  ⇒ 守卫只能防崩溃，防不住日志里那条错，而那条错会把门禁弄红。

★本地高帧率复现不出来（连跑 3 次全 0），`--max-fps 15` 两跑其一出现 ——
  所以它表现为「CI 偶发红、换着测试挂」，每次都要重查一遍。

════════════════════════════════════════════════════════════════════════
 两种修法（都验证过）
════════════════════════════════════════════════════════════════════════
① `tw.bind_node(节点)` —— 绑定节点被释放时 tween **自动 kill**，回调不再被调。
   一行，不用动 lambda 体。**节点没了那段演出本来就该停**的场合用这个。
② 捕获 `weakref(节点)`，lambda 里 `get_ref()` 取 —— WeakRef 是 RefCounted，
   **永不"被释放"**。那段演出**必须继续跑**的场合用这个
   （例：`hookbomb_system._convulse` 每帧压住 `_kill` 的死亡淡出、让尸体留在场上）。
   ⚠ `weakref()` 返回 Variant ⇒ 必须写 `var w: WeakRef = weakref(x)`，
     用 `:=` 会触发「从 Variant 推断类型」，而本仓把那条警告当错误。

════════════════════════════════════════════════════════════════════════
 判据
════════════════════════════════════════════════════════════════════════
一条 tween 链（从 `_reg_tween()` / `create_tween()` 起，到下一个 tween 或下一个
`func ` 为止）同时满足：
  · 链里有 `func(` —— 也就是挂了 lambda 回调
  · lambda 体里出现 `is_instance_valid(X)`，而 X **不是**这条链里声明的名字
    （lambda 形参 / 块内 `for X in` 的循环变量 / 块内 `var X` 都不算捕获）
    ⇒ X 是**捕获进来的对象**，而且作者自己知道它会消失（所以才写了守卫）
  · 链里**没有** `bind_node(` / `weakref(` / `get_ref()`
⇒ 记一处风险。

★为什么拿 `is_instance_valid` 当线索而不是"捕获了节点类型的变量"：
  GDScript 是鸭子类型，静态判不出一个 `var x = ...` 是不是 Node。
  而**作者写了 `is_instance_valid` 这件事本身**就是「这东西会消失」的自证 ——
  用它当线索，既不会把纯值捕获误报进来，也不会漏掉真正危险的那些。

⚠ **已知不准的地方(2026-09-25 踩过)**: 40 行窗口会把**嵌套**的 tween 链
  (外层 lambda 里又建了一条 tween)的捕获算到外层头上。`elite_system` 那处就是:
  内层 `gt` 动的是 `gh`, 而窗口里更下面另一个 lambda 的 `for bl3 in blades` 被算成了捕获
  ⇒ 我照它插了 `gt.bind_node(bl3)` ⇒ `Identifier "bl3" not declared` ⇒ **门禁 FAIL x253**。
  ⇒ 照这个清单动手时**必须逐处读代码确认被绑的是哪个节点**, 不许机械套。

★★台账口径 **只减不增**（照 `glow_ball` / `asset_orphan`）：
  存量 94 处是 2026-09-25 量出来的；新增一处直接红，减少了就更新 BASELINE。
  不这么做的话它会一边修一边长回来。

跑法:
    python tools/tween_capture_audit.py            # 报表 + 判红
    python tools/tween_capture_audit.py --list     # 逐处列出来(修的时候用)
"""
import collections
import glob
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ★存量台账。只减不增 —— 修完一批就把这个数调下来。
# →3 次历史: 94(初量) → 47(机械安全那批)。剩下 47 处要逐个判 ——
#   其中 3 处捕获的是 `battle`(场景本身), **给它 bind_node 是错的**;
#   14 处捕获两三个节点(bind_node 只能绑一个);
#   其余的链子末尾不是 `queue_free` 那个节点 ⇒ 提前 kill 可能丢掉后续动作,
#   要改用 weakref。
#
# ★★2026-10-04 47 → 31(逐处读完那一轮)。拆成三笔, 别把"尺子修好了"算成"bug 修好了":
#   ① 尺子自己的 bug: `local_names` 里 `for X in` / `var X` 那两条正则的 `\b` 早就被写成了
#      **退格字符 0x08**(heredoc 吃掉了反斜杠, 同 memory fb-heredoc-backslash-n-corrupts-json),
#      于是 09-25 加的"块内 var/for 不算捕获"从来没生效过 ⇒ 47 里有 14 处是 lambda 体里
#      `var n = instance_from_id(...)` / `for x in arr` 这种**局部变量**被当成了捕获。
#      14 处逐处核过: 名字都只在 lambda 体内声明(或是数组元素), 没有一处是被捕获的外层节点。
#   ② 真修 2 处(都用 weakref, 结算行一个字没动), 门禁 tests/verify_tween_capture_lane:
#      - chest_system 财宝风暴逐跳回调捕获底盘 disc —— 顿帧期间 tween 照走、延时队列不走
#        ⇒ 累计顿帧 > 0.6 秒最后一跳就晚于底盘释放(变异实测 4 条报错)。
#      - equip_system 千刃风暴「剑长出来」tween 捕获剑 —— 时停前建的 tween 被定格,
#        携带者协程照走把剑飞完释放 ⇒ 解冻后每步一条(变异实测 131 条)。
#        (这一处原来被台账记成「battle」—— 是窗口里协程的 is_instance_valid(battle), 真正的捕获
#         spr0 没有 is_instance_valid, 尺子看不见它; 修它顺带让那条误记消失。)
#   ③ 剩下 31 处逐条判为无害, 理由写在下面 HARMLESS 里(按 文件 + 捕获名 记, 不按行号 —— 行号会漂)。
#      ★换路**不是**这一类的触发条件: `_dl_clear_units` 把在途 sim tween 全部 kill 并移出
#        `_sim_tweens` 之后才扫 `_world`(门禁①守着, 变异两行都删 ⇒ 上千条报错)。
#      真正的触发条件只有「两条时钟错开」: 顿帧(tween 走、延时/协程不走)与时停(定格的 tween 不走、
#      携带者的协程/延时照走)。判无害 = 两种错开下捕获物都不会先于回调被释放。
BASELINE = 31   # 2026-09-25: 94 → 47 · 2026-10-04: 47 → 31(尺子修 14 + 真修 2)

# ★每一处剩下的风险都要有一句**为什么无害**。键 = (文件, 被捕获的名字逗号串), 值 = (处数, 理由)。
#   新冒出来一处没登记 → 红; 登记了但代码里没这处了(修掉了/改名了) → 也红, 逼着把台账跟着降。
#   「本链」= 释放该节点的 queue_free 就在这条 tween 链(或它自己回调里新建的链)末尾 ⇒ 回调必然先于释放。
HARMLESS = {
    ("scripts/scenes/MatchmakingScene.gd", "_dots_lbl"):
        (1, "成员变量不是捕获(lambda 捕获的是 self); tween 建在本场景上, 场景释放 tween 跟着死"),
    ("scripts/scenes/RealtimeBattle3DScene.gd", "ball, core, glow"):
        (1, "气波: 三个节点都只由本链末尾回调释放; sim tween 换路即 kill"),
    ("scripts/scenes/ShopScene.gd", "tr"):
        (1, "tr.create_tween() 绑在 tr 自己身上, tr 释放 tween 自动 kill"),
    ("scripts/scenes/TeamSelectScene.gd", "tr"):
        (1, "同上: tween 建在 tr 自己身上"),
    ("scripts/scenes/battle/battle_vfx.gd", "spr"):
        (1, "破蛋: spr 是蛋单位自己的立绘, 只在换路 _dl_clear_units 里释放, 而那里先 kill tween"),
    ("scripts/scenes/battle/synergy_vfx.gd", "blade"):
        (1, "处决铡刀: blade 只由捕获它的那个延时回调自己释放; 铡刀下落那条只是 tween_property"),
    ("scripts/scenes/team_select/pet_grid.gd", "card"):
        (1, "窗口误记: 捕获 card 的是 mouse_exited 信号 lambda, 信号连在 card 自己身上; tween 也建在 card 上"),
    ("scripts/systems/equip/equip_system.gd", "battle, slr"):
        (1, "千刃风暴地缝: slr 由 _close_slits 释放, 它在 tween(0.4s)之后 ≥0.87s 才开始且自己的 _wait_sim 不带主人"
            " ⇒ 顿帧(tween 更快)/时停(它也停)都追不上; battle 是成员, 窗口误记"),
    ("scripts/systems/skills/candy_system.gd", "hammer"):
        (1, "糖果锤: hammer 只由本链回调里新建的链释放"),
    ("scripts/systems/skills/chest_system.gd", "disc, disc2"):
        (1, "风暴驱动 tween: 两张底盘只由本链末尾回调里新建的链释放(逐跳回调那处已改 weakref)"),
    ("scripts/systems/skills/cyber_system.gd", "orb, spr3"):
        (1, "浮游炮齐射: orb 本链释放; spr3(炮)由 2.4s 的延时回调释放 —— 只有顿帧能让两者错开,"
            " 而顿帧只会让本 tween 更早跑完; 时停里施法者已死, 延时与 tween 一起定格"),
    ("scripts/systems/skills/elite_system.gd", "tsp"):
        (1, "吞噬: tsp 是目标单位立绘(只在换路释放); 卷须 tends 是数组元素不是捕获"),
    ("scripts/systems/skills/elite_system.gd", "fs2"):
        (1, "空中巨拳: fs2 只由本链回调里新建的链释放"),
    ("scripts/systems/skills/headless_system.gd", "cone, scythe"):
        (1, "镰刀横扫: scythe 本链末尾释放, cone 由本链回调里新建的链释放"),
    ("scripts/systems/skills/headless_system.gd", "cone"):
        (1, "同一条链(窗口从刀光 et 起算的重复计数)"),
    ("scripts/systems/skills/lava_system.gd", "battle, wave"):
        (1, "岩浆浪: 捕获的是 wref(=wall), 本链末尾释放; wave/battle 是窗口里 lambda 外的 is_instance_valid, 误记"),
    ("scripts/systems/skills/pirate_system.gd", "ball"):
        (1, "炮弹: ball 只由本链末尾回调释放"),
    ("scripts/systems/skills/pirate_system.gd", "ship"):
        (1, "演出船俯冲: ship(_perf_ship)全仓只在本链的 on_impact 回调里释放"),
    ("scripts/systems/skills/rocket_system.gd", "smref"):
        (1, "烟柱: 本链末尾释放"),
    ("scripts/systems/skills/star_system.gd", "wisp"):
        (1, "奇点烟圈: 本链末尾释放"),
    ("scripts/systems/skills/star_system.gd", "core"):
        (3, "奇点核心: core/halo 只由 do_burst 里三条互斥分支(cf/cd/eat)之一释放, 全在 master 链之后"),
    ("scripts/systems/skills/star_system.gd", "swirl"):
        (2, "换位螺旋: 由本链回调里新建的 st2 释放"),
    ("scripts/systems/skills/star_system.gd", "rc, rh"):
        (1, "星波: 两道环由本链回调里新建的链释放"),
    ("scripts/systems/skills/star_system.gd", "rc"):
        (1, "同一条星波链(窗口重复计数)"),
    ("scripts/systems/skills/star_system.gd", "pillar"):
        (1, "天崩光柱: 只由捕获它的 comet 延时回调自己释放; 另一条只是 tween_property"),
    ("scripts/systems/skills/star_system.gd", "head"):
        (1, "彗星头: 本链末尾释放"),
    ("scripts/systems/skills/star_system.gd", "head, ring1"):
        (1, "彗星撞击回调: head 本链, ring1/ring2 由本回调里新建的链释放"),
    ("scripts/systems/trainer/trainer_system.gd", "pot"):
        (1, "怒火药水: 本链末尾回调释放"),
}

TWEEN_START = ("_reg_tween()", "create_tween()")
FIXED_MARKS = ("bind_node(", "weakref(", "get_ref()")


def local_names(block):
    """这条链里**不是捕获**的名字: lambda 形参 + 块内 `for X in` 的循环变量 + 块内 `var X`。

    ★★2026-09-25 第一版只排除了 `func(...)` 形参, 漏了 `for X in` —— 于是
      `elite_system` 里 lambda 体内 `for bl3 in blades:` 的 `bl3` 被当成"捕获的节点",
      我照着它在 lambda **外面**插了 `gt.bind_node(bl3)` ⇒ `Parse Error:
      Identifier "bl3" not declared in the current scope` ⇒ **整套门禁 FAIL x253**。
      (那一版还让台账多算了几处, 所以数也是错的。)
    """
    out = set()
    for m in re.finditer(r"func\(([^)]*)\)", block):
        for part in m.group(1).split(","):
            name = part.split(":")[0].strip()
            if name:
                out.add(name)
    out |= set(re.findall(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b", block))
    out |= set(re.findall(r"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)", block))
    return out


def scan_file(path):
    src = io.open(path, encoding="utf-8", newline="").read()
    lines = src.split("\n")
    risky, fixed = [], 0
    for i, line in enumerate(lines):
        if not any(t in line for t in TWEEN_START):
            continue
        block = "\n".join(lines[i:i + 40])
        # 链在下一个 tween 起点 / 下一个 func 定义处截断
        cut = len(line)
        for stop in TWEEN_START + ("\nfunc ",):
            k = block.find(stop, cut)
            if k > 0:
                block = block[:k]
        if "func(" not in block:
            continue
        params = local_names(block)
        caps = sorted(set(re.findall(r"is_instance_valid\(([A-Za-z_][A-Za-z0-9_]*)\)", block)) - params)
        if not caps:
            continue
        if any(m in block for m in FIXED_MARKS):
            fixed += 1
        else:
            risky.append((i + 1, caps))
    return risky, fixed


def main():
    show = "--list" in sys.argv
    files = sorted(glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True))
    per = collections.OrderedDict()
    n_risky = n_fixed = 0
    for f in files:
        risky, fixed = scan_file(f)
        n_fixed += fixed
        if risky:
            rel = os.path.relpath(f, ROOT).replace("\\", "/")
            per[rel] = risky
            n_risky += len(risky)

    print("=== 演出 tween 的 lambda 捕获了可能被释放的节点 ===")
    print("  ★分母: 扫了 %d 个 .gd" % len(files))
    print("  已修(链里有 bind_node / weakref / get_ref): %d 处" % n_fixed)
    print("  ★风险: **%d 处** / %d 个文件   (台账 %d, 只减不增)"
          % (n_risky, len(per), BASELINE))
    print("")
    print("  最多的十个文件:")
    for rel, lst in sorted(per.items(), key=lambda kv: -len(kv[1]))[:10]:
        print("    %-52s %d 处" % (rel.replace("scripts/", ""), len(lst)))
    if show:
        print("")
        print("  逐处(行号 = 那条 tween 链的起点; 括号里是被捕获的名字):")
        for rel, lst in per.items():
            print("    %s" % rel)
            for ln, caps in lst:
                why = HARMLESS.get((rel, ", ".join(caps)), (0, "★未登记理由"))[1]
                print("      :%-5d  %-22s %s" % (ln, ", ".join(caps), why))

    ## 每一处都要有登记的理由, 且登记的处数与实际相符(多了/少了/没这处了都红)
    seen = collections.Counter()
    for rel, lst in per.items():
        for _ln, caps in lst:
            seen[(rel, ", ".join(caps))] += 1
    bad = []
    for key, n in sorted(seen.items()):
        want = HARMLESS.get(key, (0, ""))[0]
        if want != n:
            bad.append("%s [%s]: 实际 %d 处, HARMLESS 登记 %d 处" % (key[0], key[1], n, want))
    for key, (want, _why) in sorted(HARMLESS.items()):
        if key not in seen:
            bad.append("%s [%s]: HARMLESS 登记了 %d 处, 代码里已没有 —— 删掉这条" % (key[0], key[1], want))
    print("")
    print("  ★分母: HARMLESS 登记 %d 条键 / %d 处; 实际 %d 条键 / %d 处"
          % (len(HARMLESS), sum(v[0] for v in HARMLESS.values()), len(seen), sum(seen.values())))
    if bad:
        print("[FAIL] 台账理由与代码对不上 %d 条:" % len(bad))
        for b in bad:
            print("       " + b)
        print("       新增的风险先按本文件头注修; 确实无害才在 HARMLESS 里写一句**为什么**。")
        return 1

    print("")
    if n_risky > BASELINE:
        print("[FAIL] 风险处数 %d > 台账 %d —— **新增了**。" % (n_risky, BASELINE))
        print("       两种修法见本文件头注: `tw.bind_node(节点)`(那段该停) 或")
        print("       捕获 `weakref`(那段必须继续跑)。")
        print("       ⚠ 在 lambda 里加 `is_instance_valid` **不算修** —— 它挡不住那条错。")
        return 1
    if n_risky < BASELINE:
        print("[FAIL] 风险处数 %d < 台账 %d —— 修好了就把 BASELINE 调成 %d(台账要跟着降)。"
              % (n_risky, BASELINE, n_risky))
        return 1
    print("ALL OK — 风险处数 = 台账 %d(只减不增)" % BASELINE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
