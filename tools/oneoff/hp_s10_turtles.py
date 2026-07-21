# -*- coding: utf-8 -*-
"""S10: 把上次同步后【内容真的变了】的 6 只龟推上云 + 小将三节(hp_minion_sync 负责)。

只动变了的, 不重刷 28 只 —— 云端 28 只的命名是 S1-S4 当时定的
(「龟 · 05 · 天使龟（angel）👼🐢」), 用新写的切分器全量重刷容易把格式弄拧。
按云端现有元素名匹配, 找不到就报错不新建(防止造出重复条目)。
"""
import sys, io, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP

DOC = io.open('docs/design/28龟技能设计-权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_s10_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

CHANGED = ['5. 天使龟', '11. 财神龟', '25. 星际龟', '26. 缩头龟', '27. 无头龟', '28. 龟壳龟']

secs = {}
for p in re.split(r'\n(?=## )', DOC):
    m = re.match(r'## (.+)', p.strip())
    if m: secs[m.group(1).strip()] = p.strip()

hp = HP()
kids = hp.children(556)
log("556 下现有 %d 个元素" % len(kids))

done = miss = 0
for pref in CHANGED:
    body = None
    for k, v in secs.items():
        if k.startswith(pref): body = v; local_name = k; break
    if body is None:
        log("✗ 本地找不到章节:", pref); miss += 1; continue
    num = pref.split('.')[0].zfill(2)
    # 云端命名: 「龟 · NN · ...」
    target = None
    for cname, el in kids.items():
        if cname.startswith("龟 · %s ·" % num): target = (cname, el); break
    if target is None:
        log("✗ 云端找不到对应元素(不新建, 防重复):", pref); miss += 1; continue
    cname, el = target
    if len(body) > 8000: body = body[:7950] + "\n…(超长截断, 全文见本地)"
    hp._req("/designelements/%d" % el["designElementId"],
            {"name": cname, "description": body}, method="PATCH")
    log("✓ %-28s → 云端 [%d] %s (%d字)" % (local_name[:28], el["designElementId"], cname, len(body)))
    done += 1

log("\n更新 %d 只, 失败 %d" % (done, miss))
OUT.close(); print("done")
