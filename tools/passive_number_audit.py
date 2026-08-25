# -*- coding: utf-8 -*-
"""被动文案里的系数 ↔ 它自己那只龟的代码 (2026-08-17 新增)。

★为什么要单独一个审计器: `pet_number_audit` 与 `tri_audit` **都只遍历 `skillPool`**,
  28 只龟的**被动数值从来没有被任何审计对过代码** —— 这是一整块没人守的地。

★为什么需要: `pet_number_audit` / `tri_audit` **都只遍历 `skillPool`** ——
  28 只龟的**被动数值从来没有被任何审计对过代码**。
  (`brief_detail_audit` 只保证 passive.brief ↔ passive.desc 内部一致,
   两边一起写错它照样绿。)

★判据范围要窄才有意义: 全仓搜 "2.5" 会命中几百处, 等于没查。
  本项目约定每只龟的实现在 `scripts/systems/skills/<id>_system.gd`
  ⇒ 只在**这只龟自己的系统文件 + 主场景里带它名字的段**里找。
  找不到系统文件的龟, 明确记成"无法对账"而不是当成通过(空检查最会骗人)。
"""
import io, sys, json, re, os, glob
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
NL = chr(10)

pets = json.load(io.open('data/pets.json', encoding='utf-8'))
pets = pets if isinstance(pets, list) else pets['pets']
PH = re.compile(r'\{([A-Za-z]):([^}]*)\}')
NUM = re.compile(r'\d+(?:\.\d+)?')
## 占位符里的 `类名.常量名` —— 这类是【引用】不是【手写】, 判据不同(见下面的注释)。
CONST_REF = re.compile(r'[A-Z][A-Za-z0-9_]*\.[A-Z][A-Z0-9_]{2,}')

ALL_CODE = [io.open(f, encoding='utf-8', errors='replace').read()
            for f in (['scripts/scenes/RealtimeBattle3DScene.gd']
                      + sorted(glob.glob('scripts/scenes/battle/*.gd'))
                      + sorted(glob.glob('scripts/systems/**/*.gd', recursive=True)))]

## 全仓源码(给常量引用判据用): 常量可能声明在任何一个文件里。
ALL_SRC = NL.join(ALL_CODE) + NL + NL.join(
    io.open(g, encoding='utf-8', errors='replace').read()
    for g in sorted(glob.glob('scripts/gamedata/*.gd')) + sorted(glob.glob('scripts/util/*.gd')))

resolved = miss_file = 0
bad = []
for p in pets:
    pid = str(p.get('id', ''))
    pa = p.get('passive')
    if not isinstance(pa, dict):
        continue
    txt = ' '.join(str(pa.get(k, '')) for k in ('brief', 'desc', 'detail'))
    coefs = []
    refs = []
    for _t, expr in PH.findall(txt):
        ## ★★2026-08-25: 本审计器原来只数【手写系数】, 而文案根除正在把它们一个个
        ##   换成 `类名.常量名` 引用 —— 分母因此**会一路萎缩到 0**, 到时候这条门禁
        ##   就是空转(它自己的分母断言先响了: 12 → 11)。
        ##   常量引用不是"少了一次对账", 而是**更强的对账**: 它直接指着代码里的那个数,
        ##   还有 text_const_orphan_audit 保证那个常量真的有产品代码在读。
        ##   ⇒ 把它一并计入分母, 判据是"这个常量解析得出数值"。
        for r in CONST_REF.findall(expr):
            refs.append(r)
        for n in NUM.findall(CONST_REF.sub(' ', expr)):
            if n not in ('0', '1'):        # 0/1 太常见, 对不出信息
                coefs.append(n)
    if not coefs and not refs:
        continue
    # 判据范围: ①这只龟的系统文件(有就用) ②全仓里【提到它 id 或它被动中文名】的行。
    #   ②是为了够到没有独立系统文件的龟 —— 实测小龟的 `_BASIC_RARITY_BONUS` 注释写着
    #   「小龟不屈」、星际龟的上限写在 `STAR_FULL_PCT`。只用①的话这两只根本没被对账,
    #   而"无法对账"被当成通过就是空检查。
    pname = str(pa.get('name', ''))
    hay = ''
    f = 'scripts/systems/skills/%s_system.gd' % pid
    if os.path.exists(f):
        hay += io.open(f, encoding='utf-8').read() + NL
    for g in ALL_CODE:
        for l in g.split(NL):
            if ('_%s_' % pid) in l or ('"%s"' % pid) in l or (pname and pname in l):
                hay += l + NL
    if len(hay.strip()) < 40:
        miss_file += 1
        print('  [无法对账] %-10s 找不到任何提到它的代码行' % pid)
        continue
    ## 常量引用: 判据是"解析得出数值"(解析不出来 → 渲染时会原样吐出 `{C:...}` 给玩家看)。
    for r in sorted(set(refs)):
        resolved += 1
        cls, _dot, cname = r.partition('.')
        if not re.search(r'^\s*const\s+' + re.escape(cname) + r'\s*:?=', ALL_SRC, re.M):
            bad.append('%s·%s: 文案引用的常量 %s 在全仓找不到 const 声明' % (pid, str(pa.get('name', '')), r))
    for n in sorted(set(coefs)):
        resolved += 1
        if n in hay:
            continue
        # 0.25 也可能写成 25 / 0.250 / 1.0-0.75 这类等价形态, 放宽一档再试
        alt = [n.rstrip('0').rstrip('.'), n + '0', str(float(n)), str(float(n) * 100).rstrip('0').rstrip('.')]
        if any(a and a in hay for a in alt):
            continue
        bad.append('%s·%s: 文案系数 %s 在 %s 里找不到' % (pid, str(pa.get('name', '')), n, os.path.basename(f)))

print(NL + '  [分母] 被动系数对账: 比到 %d 个 · 无法对账的龟 %d 只' % (resolved, miss_file))
_fail = 0
## ★阈值随分母口径一起提: 只数手写系数时分母是 11 且一路在掉(根除的方向就是把它清零),
##   把常量引用计入之后是 154 且**只会涨**。留 120 的余量给某只龟的被动改写。
if resolved < 120:
    print('  [FAIL] ★分母: 只比到 %d 个系数(<120) —— 空检查, 不是通过' % resolved)
    _fail += 1
if miss_file > 0:
    print('  [FAIL] ★有 %d 只龟无法对账 —— "对不上代码"和"没去对"是两回事' % miss_file)
    _fail += 1
if bad:
    print('  [FAIL] ★被动文案系数与代码对不上:')
    for b in bad:
        print('         ' + b)
    _fail += 1
else:
    print('  [ OK ] ★被动文案里的系数都能在它自己那只龟的代码里找到')
print('ALL OK — 被动数值对账' if _fail == 0 else 'FAILED: %d 项' % _fail)
sys.exit(1 if _fail else 0)
