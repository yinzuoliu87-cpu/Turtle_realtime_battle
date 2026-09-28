# -*- coding: utf-8 -*-
"""写入孤儿审计 —— 「**有读者, 却没有任何人给它写过真值**」(2026-09-28, 洞⑤)

════════════════════════════════════════════════════════════════════════
 ★由来: 一个真 bug, 人工 grep 才抓到, 现存审计器一个都看不见
════════════════════════════════════════════════════════════════════════
`autoload/GameState.gd` 的 `battle_seed`:

    :170  var battle_seed: int = 0          ← 声明
    :216  battle_seed = 0                   ← 重置
    :522  if battle_seed != 0:              ← 读(双路商店 rng 播种)
    backend.gd:886  int(GameState.battle_seed)  ← 读(决赛结果上报的 p_seed)

**全仓零处写非 0 值。** 后果两条:
  · `:522` 那条 if **恒假** ⇒ 那一支是死代码
  · 决赛结果的 `p_seed` **恒为 0** ⇒ 服务端拿不到种子、**复算不出任何一场**
而代码注释还把 0 解释成「没设 `TURTLE_SEED` 就是 0」—— 那个解释是错的,
真相是**没人写它**。(memory [[fb-read-a-field-nobody-writes]] 同族)

★为什么现有审计器全看不见(实测的分母, 不是推的):
  · `zero_caller_audit`    管「**写了没人读**」—— 正好是这个的**反面**
  · `const_branch_audit`   只扫 `const X := true/false`(分母: 8 个 const / 8211 条 if),
                           **看不见「一个 var 恒为 0」**
  · `text_const_orphan`    管文案常量, 无关

════════════════════════════════════════════════════════════════════════
 ★判据要**刚好卡住那个形状**
════════════════════════════════════════════════════════════════════════
判「孤儿」= ① 产品代码里有人**读**它  且 ② 产品代码里**一次非默认值写入都没有**。

哪些写入**算**真写入(这些都是合法写入点, 不许报成孤儿):
  · `x = <任何非默认字面量/表达式>`     —— 包括 `x = int(data.get("x", 0))`
    ⇒ **存档还原**(`_apply_save_dict` 那一类)天然算合法写入点, 不用另开例外
  · `x += 1` / `x -= 1` / `x *= …`      —— 复合赋值
  · `obj.x = …`                          —— 跨对象写

哪些**不算**真写入:
  · 声明行本身(`var x: int = 0`)
  · **重置回默认值**(`x = 0` / `= false` / `= ""` / `= []` / `= {}` / `= null`,
    以及等于它声明时那个默认字面量) —— `battle_seed` 全仓就只有这一类

★★判据故意**只看名字不看主主**(不做 class→字段 的归属分析):
  同名的局部变量被赋值会让一个真孤儿**被掩护**(漏报), 但**不会**造出假报 ——
  方向是保守的。写在这里是为了下一个人不会以为它全覆盖。

════════════════════════════════════════════════════════════════════════
 ★白名单 / 台账(与另外四个洞同一条纪律)
════════════════════════════════════════════════════════════════════════
· `WHY`(本文件里, **每条必须带理由**): 测试缝那一类 —— 产品只读、**只有 tests/ 写**
  (`pool_override` / `now_override_ts` / `_transport_for_test`)。那是**设计如此**:
  产品不该写它, 门禁要注入它。**不写理由的白名单和放宽判据是一回事。**
· 台账 `tools/_write_orphan_ledger.json` —— **脚本自己生成**(`--update`), 只减不增。

跑法:
  python tools/write_orphan_audit.py            # 对账(进门禁)
  python tools/write_orphan_audit.py --update   # 按当前实测重写台账
"""
import io
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gd_text_scan as _G                       # noqa: E402  共享的去行尾注释实现

NL = chr(10)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "tools", "_write_orphan_ledger.json")

## 在哪儿找**成员字段的声明**
DECL_DIRS = ["autoload", "scripts"]
## 产品代码(算"读"和"写"都在这里面)
PROD_DIRS = ["autoload", "scripts"]
TEST_DIRS = ["tests"]

## 顶格(或 `static`/`@export` 打头)的成员声明。缩进的 `var` 是局部变量, 不收。
DECL = re.compile(
    r"^(?:@export(?:_[a-z_]+)?(?:\([^)]*\))?\s+)?(static\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*(?::\s*[A-Za-z0-9_\[\], .]+)?\s*(?::?=\s*(.+?))?\s*$")
WORD = re.compile(r"\w+")
## 默认值(重置回它不算"写了真值")
DEFAULTS = {"0", "0.0", "false", '""', "[]", "{}", "null", "-1", "Vector2.ZERO",
            "Vector3.ZERO", "Color()", "PackedStringArray()", "&''", '&""'}

## ══════════════════════════════════════════════════════════════════════
##  ★★判据收窄到**恰好** `battle_seed` 那个形状(第一版太宽, 报了 217 个)
## ══════════════════════════════════════════════════════════════════════
## 第一版只要求"没有非默认赋值", 于是把两大类正常字段全报了进来:
##   ① **声明处就初始化成真值**的: `var _ballistics := BattleBallistics.new(self)`
##      —— 它的"写"就在声明行, 一辈子不用再赋值。这是**正常**字段, 不是孤儿。
##   ② **容器/对象, 靠方法改内容**的: `var _bolt_q := []` + `_bolt_q.append(...)`,
##      `var _units := {}` + `_units[k] = v` —— 赋值语句永远不出现, 但它天天被写。
##      (`_aim.x = …` 这种**成员再赋值**也一样, 我的正则看不见 ⇒ 会造假报。)
## ⇒ 只收**标量且声明时就是默认值**的字段: 那才是「读它的 if 恒假」那个形状。
##   `battle_seed` 正是 `var battle_seed: int = 0`。
## ⚠ 收窄**不是**放宽判据: 上面两类根本不是这条判据要抓的东西, 报了它们
##   只会让 217 条噪音把唯一那条真的埋掉(而噪音门禁等于没门禁)。
##   ①②那两类各自该由别的判据管(①是"声明即初始化", 本来就对; ②要做容器写入分析)。
SCALAR_DEFAULTS = {"0", "0.0", "false", '""', "-1", "null", ""}
## 这些类型的字段即使默认值是标量, 也可能靠 `.x = …` 成员赋值来写 ⇒ 不收
SKIP_TYPE = re.compile(r":\s*(Vector[234]i?|Color|Rect2i?|Transform[23]D|Quaternion|Basis)")

## ══════════════════════════════════════════════════════════════════════
##  白名单 —— 每条必须带理由
## ══════════════════════════════════════════════════════════════════════
## 【测试缝】: 产品**只读**、**只有 tests/ 写** —— 那是设计如此(产品不该写它, 门禁要注入它)。
## 逐条都去看过声明处的头注, 不是按名字猜的。
WHY = {
    "NO_PRESENT": "对照实验快路径(dual_lane_flow.gd:19 头注:「只给离线统计用; 正式对局绝不会设它」)",
    "NO_TRAINER": "对照实验开关(RealtimeBattle3DScene.gd:650:「true 则不生成训龟大师」, 胜率测试用)",
    "now_override_ts": "phase2_config 的纯静态**时间缝** —— 门禁要把「现在」钉在某一刻",
    "clock_override_ts": "主菜单侧的同一条时间缝(截图台/门禁用)",
    "lockout_now_override": "选阵容屏的封盘时刻注入(同上, 门禁要钉住「现在」)",
    "strip_now_override": "主菜单赛程条的时刻注入(截图台/门禁用)",
    "strip_finals_live_override": "把决赛日**手动**按成「没上线」(截图台/调试用)",
    "acct_override": "设置屏账号态注入 —— 登录墙那一屏只有靠它才建得出来(verify_ui_consistency 在用)",
}


def gd_files(dirs):
    out = []
    for d in dirs:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dp, _dd, fs in os.walk(base):
            for f in fs:
                if f.endswith(".gd"):
                    p = os.path.join(dp, f).replace("\\", "/")
                    out.append(p[len(ROOT.replace("\\", "/")) + 1:])
    return sorted(out)


def read_nocmt(rel):
    """去掉行尾注释的源码(注释里的 `x = 1` 不是写入点)。"""
    src = io.open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
    return NL.join(_G.strip_comment(l) for l in src.split(NL))


def write_re(name):
    """`name` 的**赋值**写入点。排掉 `==` / `!=` / `<=` / `>=` / `:=`(声明)。"""
    n = re.escape(name)
    return re.compile(r"(?<![=!<>])\b" + n + r"\s*(?:=(?!=)|\+=|-=|\*=|/=|\|=|&=)")


def main():
    upd = "--update" in sys.argv
    prod = {p: read_nocmt(p) for p in gd_files(PROD_DIRS)}
    tests = {p: read_nocmt(p) for p in gd_files(TEST_DIRS)}
    if len(prod) < 50:
        print("  [FAIL] 只扫到 %d 个产品 .gd —— 目录写错了, 这是空检查不是通过" % len(prod))
        return 1

    ## ── 收声明 ─────────────────────────────────────────────────────
    decls = {}          # name → [(rel, line, static?, default)]
    n_decl = 0
    for rel in gd_files(DECL_DIRS):
        for i, ln in enumerate(prod.get(rel, "").split(NL)):
            m = DECL.match(ln)
            if not m:
                continue
            n_decl += 1
            decls.setdefault(m.group(2), []).append(
                (rel, i + 1, bool(m.group(1)), (m.group(3) or "").strip()))

    ## ── 逐字段数读/写 ─────────────────────────────────────────────
    prod_tok = {}
    for s in prod.values():
        for t in WORD.findall(s):
            prod_tok[t] = prod_tok.get(t, 0) + 1
    test_tok = {}
    for s in tests.values():
        for t in WORD.findall(s):
            test_tok[t] = test_tok.get(t, 0) + 1

    orphans = []        # 真孤儿: 有读者, 产品侧零真写入, tests 也没写
    seams = []          # 测试缝: 产品侧零真写入, 但 tests/ 写了
    n_scope = 0
    for name, sites in sorted(decls.items()):
        if len(name) < 3:
            continue                 # 太短的名字(i/x/dt)同名碰撞太多, 量不准
        ## ★收窄: 所有声明处都必须是「标量 + 默认值」(见 SCALAR_DEFAULTS 那段长注释)
        if not all((d or "").strip() in SCALAR_DEFAULTS for (_r, _l, _st, d) in sites):
            continue
        if any(SKIP_TYPE.search(decl_line) for decl_line in
               [prod.get(r, "").split(NL)[l - 1] if l - 1 < len(prod.get(r, "").split(NL)) else ""
                for (r, l, _st, _d) in sites]):
            continue
        n_scope += 1
        wre = write_re(name)
        real_w = 0
        reset_w = 0
        where = []
        for rel, s in prod.items():
            for i, ln in enumerate(s.split(NL)):
                if not wre.search(ln):
                    continue
                if DECL.match(ln):
                    continue                     # 声明行本身
                rhs = ln.split("=", 1)[1].strip() if "=" in ln else ""
                dflt = ""
                for (r2, _l2, _st, d2) in sites:
                    if r2 == rel or True:
                        dflt = d2 or dflt
                if rhs in DEFAULTS or (dflt and rhs == dflt):
                    reset_w += 1
                    continue
                real_w += 1
                where.append("%s:%d" % (rel, i + 1))
        if real_w > 0:
            continue
        ## 读者 = 产品侧总出现次数 − 声明处 − 重置写
        readers = prod_tok.get(name, 0) - len(sites) - reset_w
        if readers <= 0:
            continue                 # 没人读 = 另一类问题(死字段), 不是这条判据要抓的
        t_w = 0
        for _r3, s3 in tests.items():
            t_w += len(wre.findall(s3))
        row = "%s  (%s:%d) 读 %d 处 · 产品侧真写入 0 · 重置写 %d 处%s" % (
            name, sites[0][0], sites[0][1], readers, reset_w,
            " · tests 写 %d 处" % t_w if t_w else "")
        (seams if t_w > 0 else orphans).append((name, row))

    print("  [分母] 产品 .gd %d 个 · tests .gd %d 个 · 成员字段声明 %d 条"
          % (len(prod), len(tests), n_decl))
    print("  [分母] 其中【标量 + 声明时就是默认值】(= `battle_seed` 那个形状)的字段名 %d 个"
          % n_scope)
    print("  [分母] 判为【有读者但产品侧零真写入】的: 孤儿 %d 个 · 测试缝 %d 个"
          % (len(orphans), len(seams)))
    if n_decl < 200:
        print("  [FAIL] 只收到 %d 条成员声明(<200) —— 收集失效了, 这是空检查不是通过" % n_decl)
        return 1

    ledger = {}
    if os.path.exists(LEDGER):
        try:
            ledger = json.load(io.open(LEDGER, encoding="utf-8"))
        except Exception:
            ledger = {}
    known = set(ledger.get("known", []))
    known_seam = set(ledger.get("seams", []))

    if upd:
        io.open(LEDGER, "w", encoding="utf-8", newline=NL).write(json.dumps(
            {"_why": "由 `python tools/write_orphan_audit.py --update` 生成, 不要手改。"
                     "`known` = 【有读者但没人写真值】的存量(只减不增); "
                     "`seams` = 产品只读、只有 tests/ 写的测试缝存量。",
             "known": sorted(n for n, _r in orphans),
             "seams": sorted(n for n, _r in seams),
             "where": {n: r for n, r in sorted(orphans + seams)}},
            ensure_ascii=False, indent=1) + NL)
        print("  [台账已重写] %s (孤儿 %d · 测试缝 %d)" % (LEDGER, len(orphans), len(seams)))
        return 0

    if seams:
        print("  [测试缝] %d 个(产品只读 · 只有 tests/ 写):" % len(seams))
        for n, r in seams:
            print("     %s%s" % (r, ("  —— " + WHY[n]) if n in WHY else "  ⚠理由未登记"))
    if orphans:
        print("  [存量/命中] %d 个:" % len(orphans))
        for n, r in orphans:
            print("     %s%s" % (r, ("  —— " + WHY[n]) if n in WHY else ""))
    fresh = [(n, r) for n, r in orphans if n not in known and n not in WHY]
    fresh_seam = [(n, r) for n, r in seams if n not in known_seam and n not in WHY]
    cleared = [n for n in known if n not in [x for x, _ in orphans]]
    for n in sorted(cleared):
        print("  [已清] %s 现在有人写真值了 —— `--update` 把它从台账里删掉" % n)
    if fresh or fresh_seam:
        print("")
        for n, r in fresh:
            print("  [FAIL] 新的写入孤儿: %s" % r)
        for n, r in fresh_seam:
            print("  [FAIL] 新的测试缝没写理由: %s" % r)
        print("")
        print("  ★这条判据抓的是 `battle_seed` 那个形状: 读它的 if **恒假**、上报的")
        print("    `p_seed` **恒为 0**, 而注释把 0 解释成「没设环境变量」—— 解释是错的,")
        print("    真相是**没人写它**。⇒ 要么把真值写进去, 要么删掉读它的那一支;")
        print("    确实是测试缝(产品只读/门禁注入) ⇒ 往 WHY 里写一条**带理由**的。")
        print("FAIL x%d" % (len(fresh) + len(fresh_seam)))
        return 1
    print("ALL OK — 没有新增的「有读者却没人写真值」的字段")
    return 0


if __name__ == "__main__":
    sys.exit(main())
