# -*- coding: utf-8 -*-
"""T2 数据完整性校验(只读): json 交叉引用 / 资源路径 / 孤儿字段 / id 有效性。
可反复跑, 作为常驻自检工具。"""
import io, sys, os, json, re, collections
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def J(p):
    return json.load(io.open(p, encoding='utf-8'))

fail = [0]
def chk(name, bad, detail=''):
    if bad: fail[0] += 1; print('  [FAIL] %s  %s%s' % (name, bad if not isinstance(bad,list) else bad[:6], (' '+detail) if detail else ''))
    else: print('  [ OK ] %s' % name)

pets = J('data/pets.json'); pets = pets if isinstance(pets, list) else pets['pets']
eq   = J('data/phase2-equipment.json'); eq = eq if isinstance(eq, list) else eq.get('equipment', eq.get('items'))
types= J('data/p2eq-types.json')
picons = J('data/passive-icons.json'); status = J('data/status.json'); rules = J('data/battle-rules.json')
cons = J('data/equipment.json'); cons = cons if isinstance(cons,list) else cons.get('equipment',cons.get('items'))
src = io.open('scripts/scenes/RealtimeBattle3DScene.gd', encoding='utf-8').read()
sken = io.open('scripts/systems/skill_energy.gd', encoding='utf-8').read()

print('=== 数量 ===')
print('  龟 %d · 装备 %d · 消耗品 %d · 状态 %d · 规则 %d · 被动图标 %d' % (len(pets),len(eq),len(cons),len(status),len(rules),len(picons)))

print('\n=== 资源路径存在性 ===')
chk('装备 img 全部存在', [e['id'] for e in eq if not os.path.exists('assets/sprites/'+str(e.get('img','')))])
chk('龟 img 全部存在', [p['id'] for p in pets if not os.path.exists('assets/sprites/'+str(p.get('img','')))])
chk('被动图标文件存在', [k for k,v in picons.items() if str(v).endswith('.png') and not os.path.exists('assets/sprites/'+str(v))])

print('\n=== 交叉引用 ===')
eqids = {e['id'] for e in eq}
chk('p2eq-types 键 == 装备id', sorted(set(types)^eqids))
TYPESET = {'剑','奇械','食物','盾','药水','枪','弓箭','法器','灵物','遗物'}
chk('p2eq-types 的值恰好落在这 10 个类型里(学派已删·护符/饰品已解散)', sorted(set(types.values()) - TYPESET))
chk('10 个类型每个都至少有 1 件装备(分母, 防打错字造出空类型)', sorted(TYPESET - set(types.values())))
ptypes = {str(p.get('passive',{}).get('type','')) for p in pets}
chk('每只龟的被动都有图标', sorted(ptypes - set(picons)))
chk('被动图标无孤儿键', sorted(set(picons) - ptypes))
chk('消耗品全是 category=consumable', [c['id'] for c in cons if c.get('category')!='consumable'])

print('\n=== 技能 / 龟能 ===')
stypes=set()
for p in pets:
    for i,s in enumerate(p.get('skillPool') or []):
        if i>0: stypes.add(str(s.get('type')))   # idx0=普攻不入龟能表
conf=[]
for p in pets:
    for s in (p.get('skillPool') or []):
        t=str(s.get('type')); ec=s.get('energyCost')
        if ec is None: continue
        m=re.search(r'"%s"\s*:\s*([0-9.]+)'%re.escape(t), sken)
        if m and abs(float(m.group(1))-float(ec))>0.01: conf.append('%s: pets=%s 表=%s'%(t,ec,m.group(1)))
chk('pets.energyCost 与 skill_energy 无冲突', conf)
missing=[t for t in stypes if ('"%s"'%t) not in sken]
chk('主动技都在龟能表里', sorted(missing))

print('\n=== 文案完整性 ===')
chk('装备 effectDesc1 非空', [e['id'] for e in eq if not str(e.get('effectDesc1','')).strip()])
chk('龟 passive.desc 非空', [p['id'] for p in pets if not str(p.get('passive',{}).get('desc','')).strip()])
badspan=[]
for p in pets:
    for s in (p.get('skillPool') or []):
        for k in ('brief','detail'):
            t=str(s.get(k,''))
            if t.count('<span')!=t.count('</span>'): badspan.append('%s.%s.%s'%(p['id'],s.get('type'),k))
chk('span 标签配对', badspan)
ph=[]
for e in eq:
    for m in re.finditer(r'\{[A-Za-z]:[^}]*\}', str(e.get('effectDesc1',''))):
        pass
chk('装备文案无未闭合占位符', [e['id'] for e in eq if str(e.get('effectDesc1','')).count('{')!=str(e.get('effectDesc1','')).count('}')])


print('')
print('=== 自称"由 json 直接生成"的表, 是不是真的还一致 ===')
# 由来 (2026-07-29): docs/design/装备逐件审查进度.md 开头写着「本表由 phase2-equipment.json
#   直接生成, 是当前权威状态」, 但仓库里【根本没有生成它的脚本】—— 生成过一次就再没重跑。
#   龙蛋削弱后那一行还挂着旧数值(攻30/55/300 / 1500伤害 / 30/45/70层灼烧), 而它自称权威 ——
#   这比一份老老实实标"历史文档"的文件危险得多: 它在【主动声称自己是对的】。
#   焊进门禁: 59 行随便哪行漂了都红, 不用再靠人想起来去看。
REV = 'docs/design/装备逐件审查进度.md'
try:
    revtxt = io.open(REV, encoding='utf-8').read()
except Exception:
    revtxt = ''
if not revtxt:
    chk('装备评审表读得到(读不到 = 下面是空检查)', ['缺 ' + REV])
else:
    rows = {}
    for L in revtxt.split(chr(10)):
        if '| p2eq_' not in L:
            continue
        for c in [x.strip() for x in L.split('|')]:
            if c.startswith('p2eq_'):
                rows[c] = L
                break
    drift = []
    for e in eq:
        L = rows.get(e['id'])
        if L is None:
            drift.append('%s 不在评审表里' % e['id'])
            continue
        for field, label in (('baseStats1', '属性'), ('effectDesc1', '效果')):
            v = str(e.get(field, '')).strip()
            if v and v not in L:
                drift.append('%s %s 与 json 不一致' % (e['id'], label))
    print('  [分母] 评审表 %d 行 / json %d 件' % (len(rows), len(eq)))
    chk('★装备评审表与 phase2-equipment.json 一致(它自称"当前权威状态")', sorted(drift)[:8])

print('\n%s' % ('ALL OK — 数据完整性' if fail[0]==0 else 'FAILED: %d 项' % fail[0]))
sys.exit(1 if fail[0] else 0)
