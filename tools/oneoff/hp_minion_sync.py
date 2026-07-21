# -*- coding: utf-8 -*-
"""补充 HackNPlan: 把 28龟技能设计-权威.md 的 小将 三节
(普通小将两主动技 / 精英小将 / 双路单位规整规则) 同步到实时版KB(556)下
「🦐 小将」文件夹。幂等(按 name upsert)。输出写文件(控制台 GBK 崩 emoji)。
用法: python tools/hp_minion_sync.py   (key 在 ~/.hacknplan_key)"""
import sys, io, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP

DOC = io.open('docs/design/28龟技能设计-权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_minion_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

WANT = ['普通小将主动技', '精英小将 (elite)', '双路对局 · 单位规整规则']
parts = re.split(r'\n(?=#{1,2} )', DOC)   # 遇任意 # / ## 标题即断 → 单位规整不吃附录
secs = []
for p in parts:
    m = re.match(r'#{1,2} (.+)', p.strip())
    if not m:
        continue
    title = m.group(1).strip()
    if any(w in title for w in WANT):
        body = p.strip()
        if len(body) > 8000:
            body = body[:7950] + "\n…(超长截断·全文见本地)"
        secs.append((title, body))
log("匹配 %d 节:" % len(secs), [(s[0][:20], len(s[1])) for s in secs])

hp = HP()
FOLDER = hp.upsert(556, "🦐 小将 (minion) · 补位/两主动技/精英/规整",
    "深海小将权威: 补位规则 + 普通小将两主动技(前排人体浪板 minionBodysurf / "
    "后排追踪火箭筒 minionRocket · 各120龟能射程2000 · 2026-07-18封板) + "
    "精英小将(虐杀原形改造) + 双路单位规整规则. 源 docs/design/28龟技能设计-权威.md.", 13)
log("FOLDER =", FOLDER)
for (title, body) in secs:
    short = title.split('（')[0].split('(')[0].strip()
    if '精英' in title:
        short = '精英小将 (elite·虐杀原形改造)'
    eid = hp.upsert(FOLDER, short, body, 10)  # 10 = Mechanic
    log("  ", short, "->", eid, "(%d字)" % len(body))
OUT.close()
print("done, report -> tools/hp_minion_report.txt")
