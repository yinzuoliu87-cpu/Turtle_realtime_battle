# -*- coding: utf-8 -*-
"""护盾时长审计 —— 「通用护盾 = 4 秒」这条封板规则的棘轮 (2026-09-11)

════════════════════════════════════════════════════════════════════════
 ★由来
════════════════════════════════════════════════════════════════════════
用户 2026-09-11 看 012 演示时问:

    「**而且盾不过期是什么东西，我记得通用护盾是4秒啊，
      特殊护盾有特殊说明啊，这几件不会都是这种问题吧**」

他记得没错。封板规则在 `docs/design/技能改制设计决策.md`(石龟封板补全一节):

    「全局规则: 所有"通用护盾"持续=4秒(嘲讽的"永久护盾"是特例除外)。」

而 2026-08 那一轮**只扫了技能**(bamboo / bubble / diamond 各自存了一份
`*_SHIELD_SEC := 4.0`), 装备层一处都没扫 —— 当场实测 49 个给盾点里
**18 限时 / 31 永久**。

他的指示是「**先只修4件，把这个问题记录下来**」⇒ 012/015/016/021 当场修成 4 秒,
剩下的**登记进这个台账**, 等他拍板逐批还。

════════════════════════════════════════════════════════════════════════
 ★为什么是"台账 + 门禁"而不是"写进路线图"
════════════════════════════════════════════════════════════════════════
memory [[fb-registered-todos-rot]]:「**待用户拍板的登记会烂**」——
这仓库有前科: 4 条登记里 3 条我后来照着念全念错了(决定早就给了没回填)。
文档不会自己红, 台账会。

所以这条门禁做两件事:
  ① **存量冻结**: 台账里的永久给盾点原样放行(它们是历史欠账, 一刀切清零 =
     这条门禁第一天就红, 而第一天就红的门禁只会被 `|| true` 掉);
  ② **新增当场红**: 台账之外再出现"没写时长的 `_grant_shield`" 直接 FAIL。
  ③ **还了债要销账**: 台账里某条已经改成限时了, 也 FAIL —— 逼着把台账改小,
     棘轮才只会往一个方向转。(照 `zero_caller_audit` / `arch_budget` 的老规矩,
     但那两个都只做了 ①②; 这里补上 ③, 否则台账会一直停在历史最大值。)

════════════════════════════════════════════════════════════════════════
 ★判据
════════════════════════════════════════════════════════════════════════
`_grant_shield(u, amt)`            ⇒ 永久(默认 dur=0) —— 要登记
`_grant_shield(u, amt, X)`         ⇒ 有人决定了时长 —— 放行(值对不对由
                                     tests/verify_shield_duration.gd 端到端量)

一起扫 `_holy_convert(` 是因为它是 `_grant_shield` 的**薄包装**(盾羁绊 9 档:
盾类装备给盾/治疗时额外转 20% 圣光盾), 它自己的 dur 参数决定转出来那一份的时长。
只扫 `_grant_shield` 会漏掉"治疗转圣光盾"那条路。

**豁免**写 `# shield-perm-ok: 原因` 在同一行或上一行 —— 必须写原因, 且原因会被
打印出来(无声豁免等于没有规则)。真正该永久的例子: 石龟嘲讽的 1A 盾, 封板文档
里点名写了「嘲讽的"永久护盾"是特例除外」。

★分母: 扫到的给盾点少于 `MIN_SITES` 直接 FAIL —— N 小就是空检查不是通过
  ([[fb-verify-check-can-fail]])。

跑法:
  python tools/shield_duration_audit.py
  SHIELD_PERM_UPDATE=1 python tools/shield_duration_audit.py   # 重写台账(还债/新还完时用)
"""
import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIR = os.path.join(ROOT, "scripts")
LEDGER = os.path.join(ROOT, "tools", "shield_perm_debt.json")

## 给盾入口: `_grant_shield` 本体 + 它的薄包装 `_holy_convert`(盾羁绊 9 档转圣光盾)
GRANT_FNS = ("_grant_shield", "_holy_convert")

## 分母下界。实测 2026-09-11 共 51 处; 掉到 40 以下必然是扫描口径坏了。
MIN_SITES = 40

EXEMPT_RE = re.compile(r"#\s*shield-perm-ok:\s*(.+?)\s*$")
FUNC_RE = re.compile(r"^func\s+([A-Za-z_][A-Za-z0-9_]*)")


def _top_level_commas(arg_text):
    """数实参表里的【顶层】逗号 —— 嵌套的 [40,60,90][si] / Vector2(x,y) 不算。"""
    depth = 0
    n = 0
    for ch in arg_text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            n += 1
    return n


def _args_of(text, open_idx):
    """从 `(` 开始按括号配平取出实参串; 跨行也能取(调用写成多行时)。"""
    depth = 0
    out = []
    for ch in text[open_idx:]:
        if ch == "(":
            depth += 1
            if depth == 1:
                continue
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return "".join(out)
        out.append(ch)
    return None            # 括号没配平(不该发生)


def scan():
    sites = []
    for root, _dirs, files in os.walk(SCAN_DIR):
        for fn in sorted(files):
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(root, fn)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            lines = io.open(path, encoding="utf-8", newline="").read().split(chr(10))
            cur_func = "(顶层)"
            seen_in_func = {}
            for i, line in enumerate(lines):
                m = FUNC_RE.match(line)
                if m:
                    cur_func = m.group(1)
                for fname in GRANT_FNS:
                    j = line.find(fname + "(")
                    if j < 0:
                        continue
                    if line.lstrip().startswith("func ") or line.lstrip().startswith("#"):
                        continue
                    ## 跨行调用: 从本行起把后续行接上再配平
                    blob = chr(10).join(lines[i:i + 6])
                    args = _args_of(blob, blob.find(fname + "(") + len(fname))
                    if args is None:
                        continue
                    timed = _top_level_commas(args) >= 2
                    ex = EXEMPT_RE.search(line) or (
                        EXEMPT_RE.search(lines[i - 1]) if i > 0 else None)
                    key = "%s::%s" % (rel, cur_func)
                    seen_in_func[key] = seen_in_func.get(key, 0) + 1
                    if seen_in_func[key] > 1:
                        key = "%s#%d" % (key, seen_in_func[key])
                    sites.append({
                        "key": key, "rel": rel, "line": i + 1, "timed": timed,
                        "exempt": ex.group(1) if ex else None,
                        "text": line.strip()[:110],
                    })
                    break
    return sites


def main():
    sites = scan()
    total = len(sites)
    timed = [s for s in sites if s["timed"]]
    exempt = [s for s in sites if not s["timed"] and s["exempt"]]
    perm = [s for s in sites if not s["timed"] and not s["exempt"]]

    print("=== 护盾时长审计 (通用护盾 = 4 秒·封板) ===")
    print("  扫到给盾点 %d 个: 限时 %d · 永久 %d · 豁免 %d"
          % (total, len(timed), len(perm), len(exempt)))
    if exempt:
        print("  [豁免] %d 个(每个都写了原因):" % len(exempt))
        for e in exempt:
            print("     %s:%d  %s" % (e["rel"], e["line"], e["exempt"]))

    if total < MIN_SITES:
        print("")
        print("[FAIL] ★分母: 只扫到 %d 个给盾点(<%d) —— 扫描口径坏了, 这是空检查不是通过"
              % (total, MIN_SITES))
        return 1

    ledger = {}
    if os.path.exists(LEDGER):
        try:
            ledger = json.load(io.open(LEDGER, encoding="utf-8"))
        except Exception:
            ledger = {}
    known = set(ledger.get("known", []))

    if os.environ.get("SHIELD_PERM_UPDATE") == "1":
        io.open(LEDGER, "w", encoding="utf-8").write(json.dumps(
            {"_": "永久给盾点存量台账(只减不增)。新增当场红; 还了债要跑 "
                  "SHIELD_PERM_UPDATE=1 重写这里。判据见 tools/shield_duration_audit.py",
             "known": sorted(s["key"] for s in perm)},
            ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (%d 个存量)" % (os.path.relpath(LEDGER, ROOT), len(perm)))
        return 0

    fresh = [s for s in perm if s["key"] not in known]
    stale = sorted(known - set(s["key"] for s in perm))

    if fresh:
        print("")
        print("[FAIL] **新增**了没写时长的给盾点 %d 个(默认 dur=0 = 永久不过期):" % len(fresh))
        for s in fresh:
            print("   %s:%d  %s" % (s["rel"], s["line"], s["text"]))
        print("")
        print("  （封板规则: 通用护盾 4 秒。写 `BattleDamage.COMMON_SHIELD_SEC`;")
        print("    确实该永久的(嘲讽那类)加 `# shield-perm-ok: 原因`, 原因会被打印。）")
        return 1

    if stale:
        print("")
        print("[FAIL] 台账里这 %d 条已经不是永久盾了 —— 还了债要销账(棘轮只能往小转):" % len(stale))
        for k in stale:
            print("   " + k)
        print("")
        print("  跑一次: SHIELD_PERM_UPDATE=1 python tools/shield_duration_audit.py")
        return 1

    if perm:
        print("  [存量] %d 个永久给盾点在台账里(只减不增; 新增的会当场红)" % len(perm))
    print("")
    print("ALL OK — 没有新增的「永久护盾」给盾点")
    return 0


if __name__ == "__main__":
    sys.exit(main())
