# -*- coding: utf-8 -*-
"""素材借用审计 —— 「素材不复用」这条铁律的门禁化 (2026-09-13)。

用户 2026-08-03 定、08-04 重申的铁律: **新内容一律新素材**, 只有背包/商店装备图标可复用。
2026-09-13 用户点名:「你复用素材了, 你凭什么敢?」「你用素材的时候 036,
有没有直接拿旧素材做」—— 说中了: 036 温泉蛋的升级演出里有 5 次 `_gold_chunk_erupt`,
那是 **034 大熊**的 `gold-chunk.png`。

普查之后发现**这是一整类不是一件**: 12 个「名字带主人」的素材被多个系统加载。
⇒ 照 `zero_caller_audit.py` 的老办法办: **存量记台账(只减不增), 新增的当场红**。

判据形状(试了两版):
  · 只数"被几个文件加载" ⇒ 把**同一个系统内部多处调用**也算进来, 全是误报;
    改成数**不同文件**(= 不同系统)。
  · 名字里带 `fx-` / `dust-` / `spark` / `trail` / `glow` / `ring` / `shard` /
    `bubble` / `beam` / `slash` / `hit-` / `impact` / `-icon` 的是**通用基元**,
    多处共用正是它们存在的理由(CLAUDE.md: "vfx 库很全"那条说的是别重复造同一个),
    不进判据。剩下的才是"名字带主人"的。

台账在 `tools/_asset_borrow_ledger.json`。**要减不要加**: 每清掉一条就从台账里删一行。
"""
import collections
import io
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "tools", "_asset_borrow_ledger.json")
PAT = re.compile(r'res://assets/sprites/(?:vfx|equip)/([A-Za-z0-9_\-]+\.png)')
GENERIC = ("fx-", "dust-", "spark", "smoke", "trail", "glow", "ring", "shard",
           "bubble", "beam", "slash", "hit-", "impact", "-icon")


def scan():
    use = collections.defaultdict(set)
    for root, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            p = os.path.join(root, fn).replace("\\", "/")
            rel = p[len(ROOT.replace("\\", "/")) + 1:]
            for ln in io.open(p, encoding="utf-8", errors="replace"):
                for m in PAT.finditer(ln):
                    use[m.group(1)].add(rel)
    out = {}
    for k, v in use.items():
        if len(v) < 2 or any(g in k for g in GENERIC):
            continue
        out[k] = sorted(v)
    return out, len(use)


def main():
    cur, total = scan()
    old = json.load(io.open(LEDGER, encoding="utf-8")) if os.path.exists(LEDGER) else {}
    print("  [分母] 扫到 %d 个素材引用点 · 其中「名字带主人」且跨系统的 %d 个" % (total, len(cur)))
    print("  [台账] %d 条存量(只减不增)" % len(old))
    bad = []
    for k, v in sorted(cur.items()):
        if k not in old:
            bad.append("%s ← %s" % (k, " | ".join(x.split("/")[-1] for x in v)))
        elif sorted(v) != sorted(old[k]):
            extra = [x for x in v if x not in old[k]]
            if extra:
                bad.append("%s 又多了 %s" % (k, " | ".join(x.split("/")[-1] for x in extra)))
    cleared = [k for k in old if k not in cur]
    for k in cleared:
        print("  [已清] %s —— 记得把它从台账里删掉" % k)
    if bad:
        print("")
        for b in bad:
            print("  [FAIL] 新的借用: %s" % b)
        print("")
        print("  ★这条铁律是「新内容一律新素材」。要么给它烘一张自己的,")
        print("    要么(确实是通用基元)把名字改成 fx-/dust-/spark 那一类再进白名单。")
        print("FAIL x%d" % len(bad))
        return 1
    print("ALL OK — 没有新增的素材借用")
    return 0


if __name__ == "__main__":
    sys.exit(main())
