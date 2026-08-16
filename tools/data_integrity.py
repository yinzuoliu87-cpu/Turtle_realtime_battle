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
# ★只对【上架的件】要求有类型/进评审表 —— 羁绊赠送的装备(shopAvailable=0, 如 p2eq_095 圣光护盾)
#   既不进商店/私人池, 也【故意没有类型】(给它"盾"就会 送盾→盾数+1→档位涨→再送盾 无限循环)。
SHOP_EQ = [e for e in eq if int(e.get('shopAvailable', 0)) == 1]
GRANT_EQ = [e for e in eq if int(e.get('shopAvailable', 0)) != 1]
eqids = {e['id'] for e in SHOP_EQ}
chk('p2eq-types 键 == 装备id', sorted(set(types)^eqids))
TYPESET = {'香火', '剑','奇械','食物','盾','药水','枪','弓箭','法器','灵物','遗物'}
chk('p2eq-types 的值恰好落在这 10 个类型里(学派已删·护符/饰品已解散)', sorted({t for v in types.values() for t in (v if isinstance(v, list) else [v])} - TYPESET))
chk('10 个类型每个都至少有 1 件装备(分母, 防打错字造出空类型)', sorted(TYPESET - {t for v in types.values() for t in (v if isinstance(v, list) else [v])}))
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

# ★★2026-08-16 补: 【句子不许以悬空助词开头】—— 这是我自己刚制造的回归。
#   由来: 图鉴描述里 96% 的技能以龟名开头(「小龟发起一次普攻」)、装备以「携带者」开头,
#   在这一页上再写一遍它叫什么是纯废话 ⇒ 批量删主语。但删得过头了:
#     「天使龟的审判之力。」→「的审判之力。」  「闪电龟之力涌动」→「之力涌动」
#     「财神龟的聚宝盆…」→「的聚宝盆…」      「携带者的伤害处决…」→「的伤害处决…」
#   共 14 条描述变成病句, 直接印在玩家看的图鉴上。
#   ★为什么两个数值审计都没接住: 它们只比【数字】和【效果关键词】,
#     而这是纯语法坏死 —— 一个数字都没动, 两边都报 ALL OK。空档正在这里。
#   判据: 的/之/得/地 这四个结构助词【永远不能起句】(「将/其中/它」能, 不列入)。
#   ⚠ 判据要【刚好卡住病句、不误伤好句】。第一版把「之」一律判死, 结果 2026-08-17
#     把描述按分号断行之后, 「之后每次释放…」当场被判红 —— 而那是完全正常的句首。
#     「之」只有在【不接方位/时间词】时才是残渣(之力涌动 ✗ / 之后 ✓ / 之前 ✓)。
_PARTICLE = ('的', '之', '得', '地')
_ZHI_OK = ('后', '前', '中', '内', '间', '上', '下', '外')
_dangle = []
def _lines(t):
    return [x.strip() for x in re.sub(r'<[^>]*>', '', str(t)).strip().split(chr(10)) if x.strip()]
def _is_dangle(ln):
    if ln[0] not in _PARTICLE:
        return False
    if ln[0] == '之':
        return len(ln) < 2 or ln[1] not in _ZHI_OK
    return True
for p in pets:
    rows = [(s.get('name',''), s.get('brief','')) for s in (p.get('skillPool') or [])]
    _pa = p.get('passive')
    if isinstance(_pa, dict): rows.append((_pa.get('name','被动'), _pa.get('desc','')))
    for _nm, _t in rows:
        for _ln in _lines(_t):
            if _is_dangle(_ln): _dangle.append('%s·%s: %s' % (p['id'], _nm, _ln[:20]))
for e in eq:
    for _ln in _lines(e.get('effectDesc1','')):
        if _is_dangle(_ln): _dangle.append('%s: %s' % (e['id'], _ln[:20]))
print('  [分母] 扫描 %d 龟 + %d 装备的描述行' % (len(pets), len(eq)))
chk('★描述没有以悬空助词(的/之/得/地)起句的病句 —— 删主语删过头的信号', sorted(_dangle)[:8])


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
    for e in SHOP_EQ:          # ★只对账【上架件】: 羁绊赠送的装备不进评审表(它不是装备池的一部分)
        L = rows.get(e['id'])
        if L is None:
            drift.append('%s 不在评审表里' % e['id'])
            continue
        for field, label in (('baseStats1', '属性'), ('effectDesc1', '效果')):
            # ★描述改成"一句一行"后, 表格里换行写作 <br>(markdown 单元格不能跨行)。
            #   比对要按【同一口径归一】, 否则永远对不上 —— 而那是格式差异不是内容漂移。
            v = str(e.get(field, '')).strip().replace(chr(13) + chr(10), chr(10)).replace(chr(10), '<br>')
            if v and v not in L:
                drift.append('%s %s 与 json 不一致' % (e['id'], label))
    print('  [分母] 评审表 %d 行 / 上架 %d 件 (另有 %d 件羁绊赠送, 不进表)' % (len(rows), len(SHOP_EQ), len(GRANT_EQ)))
    chk('★装备评审表与 phase2-equipment.json 一致(它自称"当前权威状态")', sorted(drift)[:8])

# ============================================================
#  ★每件装备都必须有图标(2026-08-10 补)
# ============================================================
# 由来: 用户问「图标全做了吗」—— 查下来 060~095 共 36 件的 img 是空的,
# 从加进游戏那天起就没有图。而背包/商店的画法是
# `if img != "" and 文件存在: 画图` —— 后面没有 else ⇒ 无图就什么都不画:
# 背包大格只剩一行字、龟身上的小格是纯空框、商店卡片也空。
#
# ★为什么之前没接住: 上面那节「资源路径存在性」只查"填了的路径对不对",
#   空字段直接跳过 ⇒ "根本没填"永远不会被发现。
#   空值和错值是两类病, 只查后者等于放过前者。
print('')
print('=== 装备图标覆盖 ===')
_no_img = [e['id'] for e in eq if not str(e.get('img', '') or '').strip()]
_bad_img = [e['id'] for e in eq
            if str(e.get('img', '') or '').strip()
            and not os.path.exists(os.path.join('assets/sprites', str(e['img'])))]
print('  [分母] 装备 %d 件' % len(eq))
chk('★每件装备都配了图标(img 非空) —— 空着就是背包里的空白格', sorted(_no_img)[:12])
chk('★每个图标文件真的在盘上', sorted(_bad_img)[:12])

print('\n%s' % ('ALL OK — 数据完整性' if fail[0]==0 else 'FAILED: %d 项' % fail[0]))
sys.exit(1 if fail[0] else 0)
