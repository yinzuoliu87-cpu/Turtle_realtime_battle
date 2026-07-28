# -*- coding: utf-8 -*-
"""S17: 第三轮技能平衡 (2026-07-28)。只推内容真变了的 9 只龟。
★幂等: 按 "龟 · NN ·" 前缀定位既有云端元素做 PATCH, 找不到报错不新建。"""
import sys, io, os, re
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from hacknplan_sync import HP
DOC = io.open('docs/design/28龟技能设计-权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_s17_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')
CHANGED = ['5. 天使龟', '6. 寒冰龟', '9. 幽灵龟', '11. 财神龟', '12. 骰子龟',
           '14. 赌神龟', '18. 线条龟', '20. 凤凰龟', '22. 赛博龟']
secs = {}
for p in re.split(r'\n(?=## )', DOC):
    m = re.match(r'## (.+)', p.strip())
    if m: secs[m.group(1).strip()] = p.strip()
hp = HP(); kids = hp.children(556)
done = miss = 0
for pref in CHANGED:
    body = None
    for k, v in secs.items():
        if k.startswith(pref): body = v; break
    if body is None: log('X 本地无此章节:', pref); miss += 1; continue
    num = pref.split('.')[0].zfill(2)
    tgt = None
    for cname, el in kids.items():
        if cname.startswith("龟 · %s ·" % num): tgt = (cname, el); break
    if tgt is None: log('X 云端无对应元素(不新建):', pref); miss += 1; continue
    cname, el = tgt
    if len(body) > 8000: body = body[:7950] + "\n…(超长截断, 全文见本地)"
    hp._req("/designelements/%d" % el["designElementId"], {"name": cname, "description": body}, method="PATCH")
    log('OK %-14s -> [%d] (%d字)' % (pref, el["designElementId"], len(body)))
    done += 1
log('\n更新 %d, 失败 %d' % (done, miss))
OUT.close(); print('done')
