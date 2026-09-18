# -*- coding: utf-8 -*-
"""plan_stale_audit.py — 方案书里标着「❌ 还没做」的项，**做完了就得当场红**。

★★为什么有这个东西（用户 2026-09-18）：
  「你这方案书有问题吧，很多都做过了你标记未做？」

  实情比这更糟，两个方向都有：
    · 做过了却标未做 —— `20260916b-A阶段离线周赛骨架.md` 标着 0 勾 / 12 未勾全 ❌，
      而 A1~A5 早在 2026-09-17 就随三个提交落地了，账挂了一天多。
    · 没做完却标成做完 —— 我当天回填时把 A4 打成 [x]（实际只做 2/3，
      「封盘不让开打」那道闸根本不存在），A5 打成 [x]（结算屏那半没做，
      而且**回填时把原文「与结算屏」那半句一起改没了**）。

★为什么 `plans_lint` 守不住：它的第 ④ 条只验「未勾项有没有带分类标记」，
  **不验那个标记是不是真的** ⇒ 一条 ❌ 可以在事情做完之后继续挂着而门禁永远绿。

★为什么不去自动证明「做完了」：`plans_lint` 文件头已经记过那条路**试过并失败**——
  「按关键词去 tests/ 找证据…实测不可靠，把有覆盖的报成没有，
    拿它当门禁只会天天误报然后被白名单掏空」。

⇒ **换形状不是放松**：把不可靠的「证明做完了」，反过来做成可靠的「证明标记过期了」。
  条目自己点名一个**「它做完了就会存在」的东西**；那个东西一旦真的存在，这条 ❌ 就当场红。
  判据不再需要猜"算不算做完"，只需要问"这个文件/符号在不在" —— 这是确定的。

★判据（两条）：
  A. 每条 `- [ ] ❌` 必须在**本条目块内**带一行 `★done-when: <kind>:<value>`。
     存量 21 条没带 ⇒ 记台账（只减不增，照 arch_budget/zero_caller 的老规矩）。
  B. 带了标签的条目，**如果那个东西已经存在 ⇒ 当场红**（标记过期了）。
     ★这条**不留台账**：立规矩时存量为 0，之后新增的都是真过期。

  kind 支持三种（都只问"在不在"，不问"对不对"）：
    file:<repo 相对路径>        文件存在 ⇒ 过期
    gate:<测试名>               tests/<测试名>.gd 存在 ⇒ 过期
    grep:<目录>:<正则>          在该目录的 .gd 里搜到 ⇒ 过期

★为什么 kind 要限定这三种：它们都是**机器能确定回答**的。
  「功能是否正确」不能当判据 —— 那正是上一次自动查证失败的地方。

跑法：
  python tools/plan_stale_audit.py
  PLAN_STALE_UPDATE=1 python tools/plan_stale_audit.py   # 重写台账（还债后用）
"""
import hashlib
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
PLANS = os.path.join(ROOT, "docs", "plans")
LEDGER = os.path.join(ROOT, "tools", "plan_stale_debt.json")

## ★盯 ❌ 与 ⏳ 两种：❌="真没做"、⏳="登记了还没做"，**两种都会过期**。
##   只盯 ❌ 会漏掉大头 —— 实测 ⏳ 有 87 条是 ❌(21 条)的 4 倍,
##   而当天被用户抓到的两条(A4 只做 2/3、A5 只做一半)正好都是 ⏳。
##   🔲(待用户拍板) 与 ❓(未决问题) **不在射程**：它们等的是人不是代码。
ITEM = re.compile(r"^- \[ \]\s*[❌⏳]")
ANY_ITEM = re.compile(r"^\s*- \[[ x]\]")
TAG = re.compile(r"★done-when:\s*([A-Za-z]+):(.+?)\s*$")

## 扫哪些目录找 symbol —— 只看**产品代码**。
## ★不包含 docs/：方案书里写着这个名字不代表代码里有，那正是本门禁要防的病。
CODE_DIRS = ["scripts", "autoload"]


def gd_files(dirs):
    out = []
    for d in dirs:
        p = os.path.join(ROOT, d)
        for root, _dirs, files in os.walk(p):
            for f in files:
                if f.endswith(".gd"):
                    out.append(os.path.join(root, f))
    return out


_SRC_CACHE = {}


def src_of(dirname):
    """某目录下所有 .gd 的合并文本（缓存）。"""
    if dirname in _SRC_CACHE:
        return _SRC_CACHE[dirname]
    blob = []
    base = os.path.join(ROOT, dirname)
    if os.path.isdir(base):
        for root, _dirs, files in os.walk(base):
            for f in sorted(files):
                if f.endswith(".gd"):
                    try:
                        blob.append(io.open(os.path.join(root, f), encoding="utf-8",
                                            errors="replace", newline="").read())
                    except Exception:
                        pass
    s = chr(10).join(blob)
    _SRC_CACHE[dirname] = s
    return s


def artifact_exists(kind, value):
    """那个「做完就会存在的东西」在不在。返回 (在不在, 说明)。"""
    kind = kind.strip().lower()
    value = value.strip().strip("`")
    if kind == "file":
        p = os.path.join(ROOT, value.replace("/", os.sep))
        return os.path.exists(p), value
    if kind == "gate":
        p = os.path.join(ROOT, "tests", value + ".gd")
        return os.path.exists(p), "tests/%s.gd" % value
    if kind == "grep":
        parts = value.split(":", 1)
        if len(parts) != 2:
            return None, "grep 值要写成 <目录>:<正则>，实得 %r" % value
        d, pat = parts[0].strip(), parts[1].strip()
        try:
            rx = re.compile(pat)
        except re.error as e:
            return None, "正则编译失败: %s" % e
        return bool(rx.search(src_of(d))), "%s 里搜 /%s/" % (d, pat)
    return None, "不认识的 kind: %r（只支持 file/gate/grep）" % kind


def blocks(path):
    """把一份方案书切成 [(起始行号, 首行, 整块文本)]，块 = 一条 `- [ ]/[x]` 到下一条之前。"""
    lines = io.open(path, encoding="utf-8", errors="replace", newline="").read().split(chr(10))
    idx = [i for i, ln in enumerate(lines) if ANY_ITEM.match(ln)]
    out = []
    for n, i in enumerate(idx):
        j = idx[n + 1] if n + 1 < len(idx) else len(lines)
        out.append((i + 1, lines[i], chr(10).join(lines[i:j])))
    return out


def main():
    if not os.path.isdir(PLANS):
        print("[FAIL] 找不到 %s —— 目录写错了，这是空检查不是通过" % PLANS)
        return 1
    files = sorted(f for f in os.listdir(PLANS) if f.endswith(".md"))
    if not files:
        print("[FAIL] 一份方案书都没扫到 —— 空检查")
        return 1

    untagged, stale, badtag = [], [], []
    n_x = 0
    for f in files:
        for lineno, head, block in blocks(os.path.join(PLANS, f)):
            if not ITEM.match(head):
                continue
            n_x += 1
            m = None
            for ln in block.split(chr(10)):
                mm = TAG.search(ln)
                if mm:
                    m = mm
                    break
            ## ★★台账的键不能用行号 —— 2026-09-19 当场栽了:
            ##   我只是在某个条目里加了 4 行说明, **下面所有条目的行号全变**,
            ##   于是 3 条存量被报成"新增" ⇒ 这种误报正是会让门禁被 `|| true` 掉的东西。
            ##   改成【条目首行文本的哈希】: 行号怎么挪都认得出, 只有条目本身被改写才算新的。
            ##   (归一化掉首尾空白与标记后的差异, 免得改一个标点就当新条目。)
            norm = " ".join(head.strip().split())
            key = "%s#%s" % (f, hashlib.sha1(norm.encode("utf-8")).hexdigest()[:10])
            if m is None:
                untagged.append((key, head.strip()[:78]))
                continue
            ok, why = artifact_exists(m.group(1), m.group(2))
            if ok is None:
                badtag.append((key, why, head.strip()[:60]))
            elif ok:
                stale.append((key, why, head.strip()[:60]))

    print("  [分母] 扫 %d 份方案书 · 找到 %d 条 `- [ ] ❌/⏳`" % (len(files), n_x))
    print("  [分母] 其中带 ★done-when 标签的 %d 条 · 没带的 %d 条"
          % (n_x - len(untagged), len(untagged)))
    if n_x == 0:
        print("[FAIL] 一条 ❌/⏳ 都没扫到 —— 正则写错了，这是空检查不是通过")
        return 1

    ## ── B 条：标记过期（不留台账，立规矩时存量为 0）──
    if badtag:
        print("")
        print("[FAIL] ★done-when 标签写错 %d 条:" % len(badtag))
        for k, why, head in badtag:
            print("   %s  %s" % (k, why))
            print("       %s" % head)
        print("")
        print("  （kind 只支持 file:<路径> / gate:<测试名> / grep:<目录>:<正则>）")
        return 1
    if stale:
        print("")
        print("[FAIL] ★**标记过期** %d 条 —— 它点名的东西已经存在了，说明事情做完了，"
              "这条 ❌/⏳ 该改成 [x] 或写清还差什么:" % len(stale))
        for k, why, head in stale:
            print("   %s" % k)
            print("       %s" % head)
            print("       ⇒ 已存在: %s" % why)
        print("")
        print("  （这条门禁的全部意义就在这里：不去猜「算不算做完」，只问「这个东西在不在」。")
        print("    用户 2026-09-18：「你这方案书有问题吧，很多都做过了你标记未做？」）")
        return 1

    ## ── A 条：没带标签的记台账，只减不增 ──
    ledger = {}
    if os.path.exists(LEDGER):
        try:
            ledger = json.load(io.open(LEDGER, encoding="utf-8"))
        except Exception:
            ledger = {}
    known = set(ledger.get("known", []))
    cur = set(k for k, _h in untagged)
    fresh = sorted(cur - known)

    if os.environ.get("PLAN_STALE_UPDATE") == "1":
        io.open(LEDGER, "w", encoding="utf-8").write(json.dumps(
            {"known": sorted(cur)}, ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (%d 条存量)"
              % (os.path.relpath(LEDGER, ROOT), len(cur)))
        return 0

    if fresh:
        print("")
        print("[FAIL] **新增**了没写 ★done-when 的 ❌/⏳ 条目 %d 条:" % len(fresh))
        for k in fresh:
            print("   %s" % k)
        print("")
        print("  （标 ❌/⏳ 就要点名一个「它做完了就会存在」的东西，格式:")
        print("     ★done-when: gate:verify_xxx      —— tests/verify_xxx.gd 出现就红")
        print("     ★done-when: file:path/to/x.gd    —— 该文件出现就红")
        print("     ★done-when: grep:scripts/scenes/battle:ranked_used  —— 搜到就红")
        print("    不写就等于给自己留一条【永远不会被发现已经过期】的账。）")
        return 1

    paid = sorted(known - cur)
    if paid:
        print("")
        print("[FAIL] 台账**只减不增**，但有 %d 条已经不在了却还挂在台账上（还了债要销账）:" % len(paid))
        for k in paid:
            print("   %s" % k)
        print("")
        print("  跑 `PLAN_STALE_UPDATE=1 python tools/plan_stale_audit.py` 重写台账。")
        return 1

    if cur:
        print("  [存量] %d 条在台账里(只减不增；新增的会当场红)" % len(cur))
    print("")
    print("ALL OK — 没有过期的 ❌/⏳ 标记")
    return 0


if __name__ == "__main__":
    sys.exit(main())
