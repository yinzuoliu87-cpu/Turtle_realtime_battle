# -*- coding: utf-8 -*-
"""S15: 移速定位化 (2026-07-28)。
推两样:
  ① §0.5 定位表 —— 新章节, 用 upsert 按 name 幂等建/更 (556 下)
  ② 全 28 只龟 —— 属性表行的移速/攻速都变了, 所以不是"只推变的11只", 是全推
★幂等: upsert 按 name 查找, 存在则 PATCH; 龟按 "龟 · NN ·" 前缀定位既有元素, 找不到报错不新建。
"""
import sys, io, os, re
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from hacknplan_sync import HP

DOC = io.open('docs/design/28龟技能设计-权威.md', encoding='utf-8').read()
OUT = io.open('tools/hp_s15_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')

secs = {}
for p in re.split(r'\n(?=## )', DOC):
    m = re.match(r'## (.+)', p.strip())
    if m: secs[m.group(1).strip()] = p.strip()

hp = HP()
kids = hp.children(556)
done = miss = 0

# ① §0.5 定位表 (新章节)
role_sec = None
for k, v in secs.items():
    if k.startswith('0.5 定位表'): role_sec = v; break
if role_sec is None:
    log('X 本地找不到 §0.5 定位表'); miss += 1
else:
    body = role_sec if len(role_sec) <= 8000 else role_sec[:7950] + "\n…(超长截断, 全文见本地)"
    eid = hp.upsert(556, "§0.5 定位表 (移速/攻速单一事实源)", body, 10)   # 10=Mechanic; upsert 返回 int
    log('OK §0.5 定位表 -> [%d] (%d字)' % (eid, len(body)))
    done += 1

# ② 全 28 只龟
for k in sorted(secs.keys()):
    m = re.match(r'(\d+)\.\s', k)
    if not m: continue
    num = m.group(1).zfill(2)
    if not (1 <= int(num) <= 28): continue
    tgt = None
    for cname, el in kids.items():
        if cname.startswith("龟 · %s ·" % num): tgt = (cname, el); break
    if tgt is None:
        log('X 云端无对应元素(不新建): %s' % k); miss += 1; continue
    cname, el = tgt
    body = secs[k]
    if len(body) > 8000: body = body[:7950] + "\n…(超长截断, 全文见本地)"
    hp._req("/designelements/%d" % el["designElementId"],
            {"name": cname, "description": body}, method="PATCH")
    log('OK %-26s -> [%d] (%d字)' % (k[:26], el["designElementId"], len(body)))
    done += 1

log('\n更新 %d, 失败 %d' % (done, miss))
OUT.close()
print('done')
