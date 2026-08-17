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
# ★★2026-08-17 补【括号必须配对】—— 又是我自己制造的:
#   为了"一行一件事", 我按分号把长句断开, 但【没检查括号深度】⇒ 把「（…；…）」
#   从中间劈成两行, 上一行留个孤零零的「（」, 下一行以「）」开头。
#   实拍才看见:「…最大生命值（+0.60×基础攻击力」后面就没了。
#   ★数值审计接不住: 数字一个没动, 两边照样 ALL OK(与悬空助词那次同一个空档)。
_PAIRS = (('（', '）'), ('(', ')'), ('【', '】'), ('「', '」'))
_unbal = []
_nline_brk = 0
for p in pets:
    rows = [(s.get('name',''), s.get('brief','')) for s in (p.get('skillPool') or [])]
    _pa = p.get('passive')
    if isinstance(_pa, dict): rows.append((_pa.get('name','被动'), _pa.get('desc','')))
    for _nm, _t in rows:
        for _ln in _lines(_t):
            _nline_brk += 1
            if any(_ln.count(_a) != _ln.count(_b) for _a, _b in _PAIRS):
                _unbal.append('%s·%s: %s' % (p['id'], _nm, _ln[:22]))
for e in eq:
    for _ln in _lines(e.get('effectDesc1','')):
        _nline_brk += 1
        if any(_ln.count(_a) != _ln.count(_b) for _a, _b in _PAIRS):
            _unbal.append('%s: %s' % (e['id'], _ln[:22]))
print('  [分母] 括号配对: 扫了 %d 行' % _nline_brk)
chk('★分母: 括号配对真的扫到行了(0 行 = 空检查)', [] if _nline_brk > 100 else ['只扫到 %d 行' % _nline_brk])
chk('★描述每一行的括号都配对 —— 不配对 = 断行时把括号劈开了', sorted(_unbal)[:8])

# ★2026-08-17 补【不许连着两个标点】—— 也是我自己造的:
#   接回被劈开的括号时无条件补了「；」, 而前面已经有「：」⇒「Powerball：；移动速度」。
#   规则化改动最容易在【修复动作本身】上出新问题, 所以修完要复扫。
_DBL = re.compile(r'[：。；，、]；|；[：。；，、]')
_dbl = []
for p in pets:
    rows = [(s.get('name',''), s.get('brief','')) for s in (p.get('skillPool') or [])]
    for s2 in (p.get('skillPool') or []):
        if s2.get('detail'): rows.append((str(s2.get('name',''))+'.detail', s2['detail']))
    _pa = p.get('passive')
    if isinstance(_pa, dict):
        for _k in ('brief','desc','detail'):
            if _pa.get(_k): rows.append(('passive.'+_k, _pa[_k]))
    for _nm, _t in rows:
        for _m in _DBL.finditer(re.sub(r'<[^>]*>', '', str(_t))):
            _dbl.append('%s·%s: %s' % (p['id'], _nm, _m.group(0)))
for e in eq:
    for _m in _DBL.finditer(re.sub(r'<[^>]*>', '', str(e.get('effectDesc1','')))):
        _dbl.append('%s: %s' % (e['id'], _m.group(0)))
chk('★描述里没有连着两个标点(如「：；」) —— 批量断行/接回时最容易补过头', sorted(set(_dbl))[:8])

# ★★2026-08-17 补【行长上限·递归扫全部字段】—— 这条是为了守住一类【空档】而不是一个 bug。
#   由来: 今晚清理描述时我是【按字段名一个个处理】的, 结果两次漏字段:
#     · `passive.brief` —— 而它才是被动在图鉴里【默认显示】的那一份(desc 只在点"详细"时出现)
#     · `volcanoSkills` —— 熔岩龟变身后的技能, 图鉴与选技界面都显示
#   两次都是"我记得列哪些字段"出的错, 而不是规则写错。
#   ⇒ 判据改成【从结果上守】: 递归走整棵 json, 凡是含中文的字符串都算描述,
#     任何一行超过上限就红。**漏掉的字段一定表现为超长行**, 于是不用再靠我记全。
#   上限 130: 当前全局最长 124(修完之后), 而漏字段时是 169 —— 卡在中间。
_CJK = re.compile(r'[一-龥]')
_LIMIT = 130
_long = []
def _walk_text(node, path):
    if isinstance(node, dict):
        for k, v in node.items(): _walk_text(v, path + [str(k)])
    elif isinstance(node, list):
        for i, v in enumerate(node): _walk_text(v, path + ['[%d]' % i])
    elif isinstance(node, str) and len(_CJK.findall(node)) >= 6:
        for ln in re.sub(r'\{[^}]*\}', '#', re.sub(r'<[^>]*>', '', node)).split(chr(10)):
            ln = ln.strip()
            if len(ln) > _LIMIT:
                _long.append('%s: %d 字' % ('.'.join(path), len(ln)))
_walk_text(J('data/pets.json'), [])
print('  [分母] 递归扫 pets.json 全部中文字段, 上限 %d 字' % _LIMIT)
chk('★描述没有超长行(递归扫全部字段 —— 漏处理的字段一定表现为超长行)', sorted(_long)[:6])

# ★★2026-08-17 补【玩家文案里不许出现开发笔记】。
#   实拍发现点「详细」能看到这些(全在 detail 字段里, 一直躺着):
#     ·「小龟抓住目标施展过肩摔(参考英雄联盟瑟提R)：」—— 6 处 LoL 技能出处标注
#     ·「回合制原设计的「释放梭哈后额外给10%最大生命值护盾」【已由用户去掉】：…」
#       —— 写给开发者的设计变更记录, 而读它的正是那个"用户"
#   这类文字对玩家零信息(还假设他玩过别的游戏), 属于用户说的"废话"里最刺眼的一种。
#   ★注意区分: 括号里【夹着真机制】的不能整段删(龙龟Q 那条里有"4秒加速到满速、免疫定身"),
#     只摘掉出处标注。所以这条门禁只认【标注词】本身, 不按括号删。
# ★关键词表【扩过一次】: 第一版只有"参考XX/原设计/…", 结果漏了另一批同类 ——
#   「〖用户 2026-06-30 逐字设计〗」「★2026-07-30 订正: 此前文案写…已按代码真值改正并补全。」
#   都是设计出处与变更记录, 一样印在玩家看的「详细」里。
#   ⇒ 判据加上【日期格式】与【〖〗书名号】这两个形状特征 —— 比继续列词更不容易漏。
_DEVWORD = ('参考英雄联盟', '原设计', '已由用户', '未采用', '回合制', 'PoC', 'TODO',
            '订正', '勘误', '此前文案', '已按代码', '逐字', '〖')
_devnote = []
_TEXT_FILES = ('data/pets.json', 'data/phase2-equipment.json', 'data/equipment.json',
               'data/status.json', 'data/battle-rules.json')
_scanned = 0
for _f in _TEXT_FILES:
    try:
        _raw = io.open(_f, encoding='utf-8').read()
    except Exception:
        # ★不许静默跳过 —— 读不到就是"这一份没被检查", 那才是最该红的情况。
        #   原来这里是 `continue`: 文件没了/改名了, 检查照样全绿。
        _devnote.append('%s 读不到(这一份根本没被检查)' % _f)
        continue
    _scanned += 1
    for _w in _DEVWORD:
        if _w in _raw:
            _devnote.append('%s 出现「%s」' % (_f.split('/')[-1], _w))
    # 形状特征: 玩家文案里不该出现【YYYY-MM-DD 日期】
    if re.search(r'20\d\d-\d\d-\d\d', _raw):
        _devnote.append('%s 出现日期(像变更记录)' % _f.split('/')[-1])
    # ★关键词表【第三次漏同类】: 我先写「参考英雄联盟」, 又漏了「参考虐杀原形」——
    #   出处标注引的是哪个游戏根本不重要, 形状是【"参考" + 作品名】。
    #   ⇒ 判据改成: 玩家文案里【只要出现"参考"】就红。真要写机制不用这两个字。
    if '参考' in _raw:
        _devnote.append('%s 出现「参考」(出处标注)' % _f.split('/')[-1])
# ★★2026-08-17 补【羁绊档位文案 ↔ TYPES 表 对账】。
#   phase2_types.gd 自己写着「效果文本见 TIER_DESCS(那是设计定稿, 属性数值以本表为准)」——
#   一份数据两处写、且明说以其中一处为准 = memory fb-self-claiming-authority-docs-rot 那个形状,
#   迟早漂。玩家在图鉴羁绊页和背包里读的是 TIER_DESCS, 漂了就是骗人。
#   ★判据: 从文案里抠出「每件X额外提供 +N」, 和 TYPES 的 stats 逐档比(百分比档自动换算)。
#   实测当前 34 条全部对得上 —— 这条现在是防漂, 不是修 bug。
_pt = io.open('scripts/gamedata/phase2_types.gd', encoding='utf-8').read()
_types = {}
for _m in re.finditer(r'"([^"]+)":\s*\{"tiers":\s*\[([^\]]+)\],\s*"stats":\s*\[(.*?)\]\}', _pt):
    _vals = []
    for _blk in re.findall(r'\{([^}]*)\}', _m.group(3)):
        _vals.append([float(x) for x in re.findall(r':\s*([0-9.]+)', _blk)])
    _types[_m.group(1)] = _vals
_md = re.search(r'TIER_DESCS\s*:?=\s*\{(.*?)' + chr(10) + r'\}', _pt, re.S)
_syn_bad = []
_syn_n = 0
if _md is None:
    _syn_bad.append('找不到 TIER_DESCS(结构变了, 下面是空检查)')
else:
    _cur = None
    _idx = 0
    for _ln in _md.group(1).split(chr(10)):
        _mk = re.match(r'\s*"([^"]+)":\s*\[', _ln)
        if _mk:
            _cur = _mk.group(1); _idx = 0; continue
        if _cur and '"' in _ln and '每件' in _ln:
            _m2 = re.search(r'每件[^+]*\+\s*([0-9.]+)', _ln)
            if _m2 and _cur in _types and _idx < len(_types[_cur]):
                _syn_n += 1
                _got = float(_m2.group(1))
                _want = _types[_cur][_idx]
                if not any(abs(_got - _w) < 0.01 or abs(_got - _w * 100) < 0.01 for _w in _want):
                    _syn_bad.append('%s 第%d档: 文案 +%g / 表 %s' % (_cur, _idx + 1, _got, _want))
            _idx += 1
print('  [分母] 羁绊档位文案对账 %d 条' % _syn_n)
chk('★分母: 羁绊文案真的抠到了数值(0 条 = 空检查)', [] if _syn_n >= 20 else ['只抠到 %d 条' % _syn_n])
chk('★羁绊档位文案与 TYPES 表一致(文件自己写着"数值以本表为准")', sorted(_syn_bad)[:6])

print('  [分母] 玩家文案文件扫了 %d / %d 份' % (_scanned, len(_TEXT_FILES)))
chk('★分母: 五份玩家文案文件全都读到了(少一份 = 那一份没被检查)',
    [] if _scanned == len(_TEXT_FILES) else ['只扫到 %d 份' % _scanned])
chk('★玩家文案里没有开发笔记(参考XX/原设计/已由用户/回合制…)', sorted(set(_devnote))[:6])

# ★2026-08-17 补【标点用全角 + 不夹英文术语】。
#   实拍扫出来的: status.json 写着「层数随每 tick 衰减 1/3」(tick 是开发术语),
#   p2eq_009 写着「扇形band罩住敌群…对band内每名敌人」, 消耗品里 17 处半角逗号。
#   ★半角标点只在【紧跟中文】时才算错 —— 数字里的逗号/小数点是对的, 不能一刀切。
_punc = []
_ENWORD = ('tick', 'band', 'buff', 'debuff', 'DPS', 'cooldown')
for _f in ('data/pets.json', 'data/phase2-equipment.json', 'data/equipment.json',
           'data/status.json', 'data/battle-rules.json'):
    try:
        _d = J(_f)
    except Exception:
        continue
    def _w2(node, path):
        if isinstance(node, dict):
            for k, v in node.items(): _w2(v, path + [str(k)])
        elif isinstance(node, list):
            for i, v in enumerate(node): _w2(v, path + ['[%d]' % i])
        elif isinstance(node, str) and len(re.findall(r'[一-龥]', node)) >= 4:
            _c = re.sub(r'<[^>]*>', '', node)
            if re.search(r'[一-龥][,;:]', _c):
                _punc.append('%s 半角标点' % _f.split('/')[-1])
            for _w in _ENWORD:
                if re.search(r'(?<![A-Za-z])' + _w + r'(?![A-Za-z])', _c):
                    _punc.append('%s 夹英文「%s」' % (_f.split('/')[-1], _w))
    _w2(_d, [])
chk('★文案标点用全角、不夹英文术语(tick/band/buff…)', sorted(set(_punc))[:6])

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
