# -*- coding: utf-8 -*-
"""S11: 只读回读校验 —— 云端 556 子树 vs 本地事实源。不做任何写操作。"""
import sys, io, os, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hacknplan_sync import HP
OUT = io.open('tools/hp_s11_report.txt', 'w', encoding='utf-8')
def log(*a): OUT.write(' '.join(str(x) for x in a) + '\n')
hp = HP()
fail = [0]
def ok(name, cond, detail=''):
    log(('  [PASS] ' if cond else '  [FAIL] ') + name + (('  ' + detail) if detail else ''))
    if not cond: fail[0] += 1

kids = hp.children(556)
log("=== 556 实时版知识库 子元素 %d 个 ===" % len(kids))
for k in sorted(kids.keys()): log("   ", k)

# ① 系统机制 §1-§10
sysk = hp.children(651)
want = {'§%d'%i for i in range(1, 11)}
got = {re.match(r'(§\d+)', k).group(1) for k in sysk if re.match(r'§\d+', k)}
ok("系统机制 §1-§10 齐全", want <= got, "缺 %s" % (want - got) if want - got else "共%d节" % len(sysk))
ok("系统机制无多余节", len(sysk) == 10, "实际 %d" % len(sysk))

# ② 装备 59 件, 且描述已是评审后版本(抽查关键数值) + 不含废弃字段
eq = json.load(io.open('data/phase2-equipment.json', encoding='utf-8'))
eq = eq if isinstance(eq, list) else eq.get('equipment', [])
ek = hp.children(591)
ok("装备 59 件", len(ek) == len(eq), "云端%d / 本地%d" % (len(ek), len(eq)))
bad_rarity = []
sample_bad = []
for nm, el in ek.items():
    d = hp._req('/designelements/%d' % el['designElementId']).get('description', '')
    if '稀有[' in d: bad_rarity.append(nm)
    m = re.search(r'(p2eq_\d+)', nm)
    if m:
        loc = [x for x in eq if x['id'] == m.group(1)]
        if loc and loc[0].get('effectDesc1', '') and loc[0]['effectDesc1'] not in d:
            sample_bad.append(nm)
ok("装备描述已清除废弃「稀有[..]」字段", not bad_rarity, "残留: %s" % bad_rarity[:3])
ok("59 件效果文案 == 本地 effectDesc1", not sample_bad, "不符: %s" % sample_bad[:5])

# ③ 28 龟齐全 + 小将三节
turtles = [k for k in kids if k.startswith('龟 · ')]
ok("28 龟齐全", len(turtles) == 28, "实际 %d" % len(turtles))
mk = hp.children(659)
ok("小将 3 节", len(mk) == 3, "实际 %d: %s" % (len(mk), sorted(mk.keys())))

log("\n%s" % ("ALL PASS — 云端 == 本地" if fail[0] == 0 else "FAILED: %d" % fail[0]))
OUT.close(); print("done")
