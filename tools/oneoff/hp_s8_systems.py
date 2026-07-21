# -*- coding: utf-8 -*-
"""S8: 系统机制 §1-§10 同步到云端。
本地新增 §7决胜/§8硬控/§9巡检, 且原「§7 REVIEW_DEMO」重编号为 §10 →
先把云端那个旧 §7 改名成 §10(保住同一元素, 不产生孤儿), 再全量 upsert。"""
import sys, io, re, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP

DOC = io.open('docs/design/实时版-系统机制权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_s8_report.txt', 'w', encoding='utf-8')
def log(*a):
    OUT.write(' '.join(str(x) for x in a) + '\n')

hp = HP()
ROOT = 556
SYS = hp.upsert(ROOT, "⚙️ 系统机制 · 实时版",
                "实时版系统/流程机制权威 (配套28龟技能数据). 每条=真实行为+数值+出处. 本地源 docs/design/实时版-系统机制权威.md", 13)
log("系统文件夹 SYS =", SYS)

# ① 先处理重编号: 云端旧「§7 REVIEW_DEMO / 出包（铁律）」→ 改名为 §10
old = hp.find_child(SYS, "§7 REVIEW_DEMO / 出包（铁律）")
if old:
    hp.rename(old["designElementId"], "§10 REVIEW_DEMO / 出包（铁律）")
    log("重编号: 旧§7(%d) → §10 (保住同一元素, 内容随后 upsert 更新)" % old["designElementId"])
    hp._children.pop(SYS, None)   # 清缓存, 让后面按新名字找得到
else:
    log("重编号: 云端无旧§7 (可能已改过)")

# ② 全量 upsert §1-§10
parts = re.split(r'\n(?=## §)', DOC)
n = 0
for p in parts:
    m = re.match(r'## (§\d+ .+)', p.strip())
    if not m:
        continue
    name = m.group(1).strip()
    body = p.strip()
    if len(body) > 8000:
        body = body[:7950] + "\n…(超长截断, 全文见本地)"
    eid = hp.upsert(SYS, name, body, 10)
    n += 1
    log("  %-46s -> %d (%d字)" % (name, eid, len(body)))

log("\n本轮 upsert %d 个" % n)
hp._children.pop(SYS, None)
kids = hp.children(SYS)
log("回读 SYS.children = %d" % len(kids))
for k in sorted(kids.keys()):
    log("   ", k)
OUT.close()
print("done")
