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
BASELINE = 47   # 2026-09-25: 94 → 47(机械安全的那批: 单捕获 + 链末尾就 queue_free 它)

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
    out |= set(re.findall(r"for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in", block))
    out |= set(re.findall(r"var\s+([A-Za-z_][A-Za-z0-9_]*)", block))
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
                print("      :%-5d  %s" % (ln, ", ".join(caps)))

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
