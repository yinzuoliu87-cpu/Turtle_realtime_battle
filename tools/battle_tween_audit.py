# -*- coding: utf-8 -*-
"""battle_tween_audit.py — 战斗路径上的裸 `create_tween()`（不经 `_reg_tween`）棘轮：只减不增

════════════════════════════════════════════════════════════════════════
 为什么有这条（B 阶段确定性加固 · 方案书 20260916c §8.5 第 3 条）
════════════════════════════════════════════════════════════════════════
`_reg_tween()` 建出来的 tween 在 det 模式下被 `pause()`、改由 `_sim_step` 按 SIM_DT
`custom_step` 喂（`RealtimeBattle3DScene._step_sim_tweens`）—— 那是"演出 tween 走 sim 钟"的唯一收口。
**裸 `create_tween()` 不进这个收口**，它永远走引擎的真实（未钳制）delta：
  · 在它的回调里**结算**任何东西（伤害 / 治疗 / 击杀 / 掷骰）⇒ 结算时刻随机器快慢漂 ⇒
    同种子两遍、两台机器得出不同结果（海盗登场轰击就是这样分叉的，§8.2）。
  · 方案书原话：「逐个读过调用点没有一处结算伤害，但**没有门禁守住『以后不会有人在裸 tween 里结算』**」。

★它与 `tools/tween_freeze_audit.py` 的分工（**不是重复**）：
  | | 它守的 | 范围 |
  |---|---|---|
  | tween_freeze | 时停能不能冻住（世界里的演出不许绕开 `_reg_tween`） | battle/ + systems/ + 主场景 |
  | **本工具**   | 确定性：裸 tween 的**数量只减不增** + 它所在的函数**不许结算** | 同上 + `hp_bar.gd`（战斗血条, 不在那份的扫描面里） |
  两份的数要对得上同一批调用点 —— 本工具第 ④ 条拿那份的台账总数对账（差的只能是 hp_bar 那 3 处）。

════════════════════════════════════════════════════════════════════════
 ★★两套独立实现对账（memory `fb-regex-as-parser-fakes-the-baseline`）
════════════════════════════════════════════════════════════════════════
棘轮的基线一旦冻结，基线本身的错就被焊死了。正则当解析器最典型的伪造方式：
  · 注释里写着 `create_tween()`（本仓 20 多处这样的说明文字）⇒ 多数；
  · 字符串里含 `#` ⇒ "去注释"把同一行后面的真调用砍掉 ⇒ 少数。
⇒ 实现 A = 逐行正则（引号感知地去注释）；实现 B = 整文件逐字符词法扫描（字符串 / 三引号 /
  注释是状态机里的状态，标识符是 token）。**两边逐文件、逐行号必须完全一致**，否则当场红 ——
  每次跑都对账，不是冻结那一刻对一次。

跑法:  python tools/battle_tween_audit.py          # 报表 + 判红
       python tools/battle_tween_audit.py --list   # 逐处列出（行号 + 所在函数）
"""
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCAN_DIRS = [
    os.path.join("scripts", "scenes", "battle"),
    os.path.join("scripts", "systems"),
]
SCAN_FILES = [
    os.path.join("scripts", "scenes", "RealtimeBattle3DScene.gd"),
    os.path.join("scripts", "scenes", "hp_bar.gd"),   # 战斗血条(只在战斗里实例化), tween_freeze 不扫它
]

# 注册口本身：它自己当然是"裸" create_tween —— 它就是那个收口。
REGISTRAR = ("scripts/scenes/RealtimeBattle3DScene.gd", "_reg_tween")

# ── 棘轮基线（2026-10-04 冻结，A/B 两套实现对过账）──  文件 → 裸 create_tween 处数
# ★只减不增：修掉一处就把数字改小；数字变大 = 有人新写了一条走真实钟的 tween。
BASELINE = {
    "scripts/scenes/battle/battle_hud.gd": 3,       # HUD 面板动效(UI 层)·2026-10-04 5→3: 结算屏两处随结算屏搬到 settle_screen.gd
    "scripts/scenes/battle/settle_screen.gd": 2,    # 结算屏暗幕淡入 + 胜负大字弹出(UI 层·战斗已结束·理由见 tween_freeze_audit ALLOW)
    "scripts/scenes/battle/battle_vfx.gd": 3,       # 飘字(CanvasLayer)
    "scripts/scenes/battle/dual_lane_flow.gd": 4,   # 换路转场 UI(跨路存活, 不能进 _sim_tweens 被连坐清掉)
    "scripts/scenes/hp_bar.gd": 3,                  # 血条拖尾/横抖/白闪
    "scripts/systems/equip/timestop_system.gd": 5,  # 时停自己的演出(冻了就没画面)
}
BASELINE_TOTAL = 20

# 结算动作：出现在"含裸 tween 的函数"里就红（裸 tween 走真实钟，结算挨着它 = 结算时刻跟着漂的高危形状）。
SETTLE = re.compile(r"\b(_apply_damage_from|_apply_damage|_kill|_heal|_grant_shield|_battle_rng|_sk_dmg\w*)\b")


# ═══════════════════════ 实现 A：逐行正则 ═══════════════════════
CALL_A = re.compile(r"\bcreate_tween\s*\(")
FUNC_A = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")


def _strip_comment_quote_aware(line):
    q = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if q:
            if ch == "\\":
                i += 2
                continue
            if ch == q:
                q = ""
        elif ch in ("\"", "'"):
            q = ch
        elif ch == "#":
            return line[:i]
        i += 1
    return line


def scan_a(text):
    """→ [(行号, 所在函数名)]"""
    out = []
    fn = ""
    in_triple = False
    for ln, raw in enumerate(text.split("\n"), 1):
        line = raw.rstrip("\r")
        # 三引号块(本仓用作块注释/长文案)整段跳过
        if in_triple:
            if '"""' in line:
                in_triple = False
                line = line[line.index('"""') + 3:]
            else:
                continue
        while line.count('"""') % 2 == 1:   # 本行开了一个没关的三引号
            in_triple = True
            line = line[:line.rindex('"""')]
        m = FUNC_A.match(line)
        if m:
            fn = m.group(1)
        code = _strip_comment_quote_aware(line)
        for _ in CALL_A.finditer(code):
            out.append((ln, fn))
    return out


# ═══════════════════════ 实现 B：逐字符词法扫描 ═══════════════════════
def scan_b(text):
    """→ [(行号, 所在函数名)]。状态机: 代码 / 单行字符串 / 三引号字符串 / 注释。"""
    out = []
    i, n, ln = 0, len(text), 1
    fn = ""
    expect_fn_name = False
    toks = []   # 最近几个 token, 只为认 `create_tween` 后面跟 `(`
    while i < n:
        c = text[i]
        if c == "\n":
            ln += 1
            i += 1
            continue
        if c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if text.startswith('"""', i) or text.startswith("'''", i):
            d = text[i:i + 3]
            j = text.find(d, i + 3)
            j = n if j < 0 else j + 3
            ln += text.count("\n", i, j)
            i = j
            continue
        if c in ("\"", "'"):
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            i = j + 1
            continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            word = text[i:j]
            if expect_fn_name:
                fn = word
                expect_fn_name = False
            if word == "func":
                # 有名函数: `func NAME(`; lambda `func(` 不改当前函数
                k = j
                while k < n and text[k] in " \t":
                    k += 1
                expect_fn_name = k < n and (text[k].isalpha() or text[k] == "_")
            if word == "create_tween":
                k = j
                while k < n and text[k] in " \t":
                    k += 1
                if k < n and text[k] == "(":
                    out.append((ln, fn))
            toks.append(word)
            i = j
            continue
        i += 1
    return out


def _files():
    fs = []
    for d in SCAN_DIRS:
        for dirpath, _dirs, names in os.walk(os.path.join(ROOT, d)):
            for nm in names:
                if nm.endswith(".gd"):
                    fs.append(os.path.join(dirpath, nm))
    for f in SCAN_FILES:
        fs.append(os.path.join(ROOT, f))
    return sorted(set(fs))


def _func_bodies(text):
    """函数名 → 函数体文本(去注释)。只给"结算"检查用。"""
    bodies = {}
    cur = None
    buf = []
    for raw in text.split("\n"):
        line = raw.rstrip("\r")
        m = FUNC_A.match(line)
        if m and not line.startswith((" ", "\t")):
            if cur is not None:
                bodies[cur] = "\n".join(buf)
            cur, buf = m.group(1), []
            continue
        if cur is not None:
            buf.append(_strip_comment_quote_aware(line))
    if cur is not None:
        bodies[cur] = "\n".join(buf)
    return bodies


def _tween_freeze_total():
    """拿 tween_freeze_audit 的台账总数(它的 ALLOW 含注册口 1 处)对账。读不到返回 None。"""
    try:
        sys.path.insert(0, os.path.join(ROOT, "tools"))
        import tween_freeze_audit as tfa   # noqa: E402
        return sum(v[0] for v in tfa.ALLOW.values())
    except Exception:
        return None


def main():
    listing = "--list" in sys.argv
    files = _files()
    nlines = 0
    hits_a, hits_b = {}, {}
    settle_bad = []
    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        with open(path, encoding="utf-8", newline="") as fh:
            text = fh.read()
        nlines += text.count("\n") + 1
        a = [h for h in scan_a(text) if (rel, h[1]) != REGISTRAR]
        b = [h for h in scan_b(text) if (rel, h[1]) != REGISTRAR]
        if a:
            hits_a[rel] = a
        if b:
            hits_b[rel] = b
        if a:
            bodies = _func_bodies(text)
            for (ln, fn) in sorted(set(a)):
                m = SETTLE.search(bodies.get(fn, ""))
                if m:
                    settle_bad.append("%s:%d 函数 %s() 里有裸 tween, 同一个函数又调了 `%s`" % (rel, ln, fn, m.group(1)))

    print("=== 战斗路径裸 create_tween() 棘轮（确定性·只减不增）===")
    print("  [分母] 扫描 %d 个 .gd / %d 行（battle/ + systems/ + 主场景 + hp_bar）" % (len(files), nlines))
    tot_a = sum(len(v) for v in hits_a.values())
    tot_b = sum(len(v) for v in hits_b.values())
    print("  [分母] 实现 A(逐行正则) %d 处 / 实现 B(逐字符词法) %d 处 / 基线 %d 处" % (tot_a, tot_b, BASELINE_TOTAL))
    bad = []
    if len(files) < 80 or nlines < 50000:
        bad.append("[FAIL] 分母: 只扫到 %d 个文件 / %d 行 —— 扫描面塌了, 下面全是空检查" % (len(files), nlines))
    if tot_a == 0:
        bad.append("[FAIL] 分母: 一处裸 create_tween 都没找到 —— 要么全修好了(那就把基线清零), 要么扫描器坏了")

    # ① 两套实现逐文件逐行号一致
    for rel in sorted(set(hits_a) | set(hits_b)):
        la = sorted(x[0] for x in hits_a.get(rel, []))
        lb = sorted(x[0] for x in hits_b.get(rel, []))
        if la != lb:
            bad.append("[FAIL] ① 两套实现对不上账: %s  A=%s  B=%s —— 基线不可信, 先查是哪一套在当解析器时出错"
                       % (rel, la, lb))

    # ② 棘轮
    for rel in sorted(set(hits_a) | set(BASELINE)):
        n = len(hits_a.get(rel, []))
        cap = BASELINE.get(rel, 0)
        if n > cap:
            bad.append("[FAIL] ② %s: 裸 create_tween() %d 处 > 基线 %d 处 —— 新增的走真实钟(不进 _sim_tweens),\n"
                       "       det 模式下也不按 sim 步推进。改成 `battle._reg_tween()`; 真要裸的(UI/跨路存活)\n"
                       "       先在 tools/tween_freeze_audit.py 的 ALLOW 写清理由, 再来这里改基线。行号: %s"
                       % (rel, n, cap, [x[0] for x in hits_a.get(rel, [])]))
        elif n < cap:
            bad.append("[FAIL] ② %s: 裸 create_tween() 只剩 %d 处(基线 %d)—— 修好了就把基线改小, 棘轮只减不增"
                       % (rel, n, cap))
        else:
            print("  [OK] ② %-48s %d 处" % (rel, n))
    if sum(BASELINE.values()) != BASELINE_TOTAL:
        bad.append("[FAIL] 基线表合计 %d ≠ BASELINE_TOTAL %d" % (sum(BASELINE.values()), BASELINE_TOTAL))

    # ③ 含裸 tween 的函数不许结算
    if settle_bad:
        for s in settle_bad:
            bad.append("[FAIL] ③ " + s + " —— 裸 tween 走真实钟, 结算挨着它就是海盗登场轰击那个分叉形状(§8.2)")
    else:
        print("  [OK] ③ 含裸 tween 的 %d 个函数里 0 处结算调用(伤害/治疗/击杀/护盾/_battle_rng)"
              % len({(r, h[1]) for r, v in hits_a.items() for h in v}))

    # ④ 与 tween_freeze_audit 的台账对账(那份含注册口 1 处、不含 hp_bar)
    tf = _tween_freeze_total()
    hp = len(hits_a.get("scripts/scenes/hp_bar.gd", []))
    if tf is None:
        bad.append("[FAIL] ④ 读不到 tools/tween_freeze_audit.py 的台账 —— 两份门禁对账断了")
    elif tf - 1 != tot_a - hp:
        bad.append("[FAIL] ④ 与 tween_freeze 台账对不上: 那份 %d 处去掉注册口 1 = %d vs 本工具 %d 处去掉 hp_bar %d = %d"
                   % (tf, tf - 1, tot_a, hp, tot_a - hp))
    else:
        print("  [OK] ④ 与 tween_freeze 台账对账: 那份 %d - 注册口 1 == 本工具 %d - hp_bar %d" % (tf, tot_a, hp))

    if listing:
        for rel in sorted(hits_a):
            for ln, fn in hits_a[rel]:
                print("     %s:%d  %s()" % (rel, ln, fn))

    print("")
    if bad:
        for b in bad:
            print(b)
        print("FAILED: %d 处违规" % len(bad))
        return 1
    print("ALL OK — 战斗路径裸 create_tween() %d 处 == 基线(A/B 两套实现逐行对账一致)" % tot_a)
    return 0


if __name__ == "__main__":
    sys.exit(main())
