# -*- coding: utf-8 -*-
"""S13: 补同步 —— S8-S12 之后本地又改了权威文档(58条文案订正+无头龟补实装), 云端已落后。
只推【内容真的变了】的章节, 云端找不到对应元素则报错不新建。"""
import sys, io, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP
DOC = io.open('docs/design/28龟技能设计-权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_s13_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')
CHANGED = ['5. 天使龟', '6. 寒冰龟', '7. 忍者龟', '8. 双头龟', '10. 钻石龟', '27. 无头龟']
secs = {}
for p in re.split(r'\n(?=## )', DOC):
    m = re.match(r'## (.+)', p.strip())
    if m: secs[m.group(1).strip()] = p.strip()
hp = HP()
kids = hp.children(556)
done = miss = 0
for pref in CHANGED:
    body = None; local = None
    for k, v in secs.items():
        if k.startswith(pref): body = v; local = k; break
    if body is None: log('✗ 本地无此章节:', pref); miss += 1; continue
    num = pref.split('.')[0].zfill(2)
    tgt = None
    for cname, el in kids.items():
        if cname.startswith("龟 · %s ·" % num): tgt = (cname, el); break
    if tgt is None: log('✗ 云端无对应元素(不新建):', pref); miss += 1; continue
    cname, el = tgt
    if len(body) > 8000: body = body[:7950] + "\n…(超长截断, 全文见本地)"
    hp._req("/designelements/%d" % el["designElementId"], {"name": cname, "description": body}, method="PATCH")
    log('✓ %-24s → [%d] %s (%d字)' % (local[:24], el["designElementId"], cname, len(body)))
    done += 1
log('\n更新 %d, 失败 %d' % (done, miss))
OUT.close(); print('done')
