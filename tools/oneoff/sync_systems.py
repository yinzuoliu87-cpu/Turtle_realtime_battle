# -*- coding: utf-8 -*-
"""把 docs/design/实时版-系统机制权威.md 的 §1-§7 同步到 HacknPlan GDM (556 下新建系统文件夹)。
幂等: upsert 按 name 查找。输出写文件(控制台 GBK 崩 emoji)。"""
import sys, io, re, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP

DOC = io.open('docs/design/实时版-系统机制权威.md', encoding='utf-8').read()
OUT = io.open('tools/sync_systems_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

hp = HP()
ROOT = 556
# 系统文件夹 (13=Folder)
SYS = hp.upsert(ROOT, "⚙️ 系统机制 · 实时版",
                "实时版系统/流程机制权威 (配套28龟技能数据). 每条=真实行为+数值+出处. 本地源 docs/design/实时版-系统机制权威.md", 13)
log("系统文件夹 SYS =", SYS)

# 按 "## §N ..." 切段
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
    eid = hp.upsert(SYS, name, body, 10)  # 10=Mechanic
    n += 1
    log("  ", name, "->", eid, "(%d 字)" % len(body))

log("完成: %d 个系统机制元素挂在 SYS(%d) 下" % (n, SYS))
# 回读校验: 从 tree 查 SYS 的真实子元素
kids = hp.children(SYS)
log("回读 SYS.children =", len(kids), "→", sorted(kids.keys()))
OUT.close()
print("done, report -> tools/sync_systems_report.txt")
