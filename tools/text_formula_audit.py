# -*- coding: utf-8 -*-
"""文案里【写的百分比】↔【同一句那个占位符公式算出来的系数】。

═══ 为什么要有这个(2026-08-19) ═══
用户: 「我怀疑的是你学习的描述还不够? 还是你项目里的技能都完全不了解?」——
我逐只读代码复核, 第一批(小龟/石头龟)就抓到两个真 bug, 而且**全套 212 项门禁全绿**:

  ① 石头龟·岩石护盾: 文字写「100%×攻击力 + 6%×最大生命值」(和代码一致),
     可占位符还是 `{S:0.2*ATK+HP*0.05}` —— **文字是新的、公式是旧的**,
     玩家看到的数字停在改版前(代码注释里就写着"用户2026-07-11: 0.2A+5%→1A+6%")。
  ② 海盗龟·朗姆酒 detail: 说「护甲与魔抗各 15%×攻击力」却配 `{D:ATK*0.65}`;
     代码是 护甲 0.15A+0.5A=0.65A、魔抗 0.15A —— brief 写对了, detail 错了。

**这是"文案对不上"的第三种形状: 文案自己内部就对不上**(文字 vs 它自己的公式)。
前面两条审计器都看不见它: `pet_number_audit` 比的是"文案数字 ↔ 代码", 而这里
文字和公式各自都能在代码里找到出处, 只是**配错了对**。

★判据边界(四类误报已排, 每类都栽过):
  a) 公式本身是【百分比单位】—— 石头龟反伤 `{N:5+DEF+MR*0.5}%`
  b) 取整误差 —— 忍者 `0.6667*ATK*3` = 2.0001 vs 文字 200%
  c) 每段 vs 合计 —— 冰晶护体"每段 40%"配的是 `0.4*ATK*3`(总量)
  d) 文字后面还跟着乘数 —— 电龟「100%×攻击力 × 1.5 = {T:ATK*1.5}」

跑法: python tools/text_formula_audit.py
"""
import io, json, re, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

NL = chr(10)
d = json.load(io.open('data/pets.json', encoding='utf-8'))
pets = d if isinstance(d, list) else d['pets']
# 「N%×攻击力」但后面不再接「×最大生命值」这种乘积
PCT = re.compile(r'(\d+(?:\.\d+)?)%\s*[×x]\s*(攻击力|最大生命值|护甲|魔抗)(?!\s*[×x])')
PH = re.compile(r'\{[A-Z]:([^}]+)\}')
KEY = {'攻击力': 'ATK', '最大生命值': 'HP', '护甲': 'DEF', '魔抗': 'MR'}


def coef(expr, var):
    """把表达式当线性式, 取 var 的系数: var=1 其余=0 算一次。算不动就返回 None。"""
    names = set(re.findall(r'[A-Za-z_][A-Za-z_0-9]*', expr))
    env = {n: 0.0 for n in names}
    if var not in env:
        return None
    env[var] = 1.0
    try:
        return round(float(eval(expr, {'__builtins__': {}}, env)), 4)
    except Exception:
        return None


bad = []
n = 0
for x in pets:
    items = []
    pa = x.get('passive')
    if isinstance(pa, dict):
        items.append(('被动', pa))
    for s in (x.get('skillPool') or []):
        items.append((str(s.get('name')), s))
    for nm, obj in items:
        for k in ('brief', 'desc', 'detail'):
            t = str(obj.get(k, '') or '')
            if not t:
                continue
            for line in re.split(r'[\n。]', t):
                phs = PH.findall(line)
                plain = re.sub(r'<[^>]*>', '', line)
                pcts = PCT.findall(plain)
                if not phs or not pcts:
                    continue
                n += 1
                for val, kind in pcts:
                    var = KEY[kind]
                    want = round(float(val) / 100.0, 4)
                    got = [c for c in (coef(e, var) for e in phs) if c is not None]
                    # ⚠ 三类误报要排掉, 否则判据在报自己看不懂的东西:
                    #   a) 公式本身就是【百分比单位】(后面紧跟 %) —— 石头龟反伤 5+DEF+MR*0.5 %
                    #   b) 取整误差 —— 忍者 0.6667*ATK*3 = 2.0001 vs 文字 200%
                    #   c) 每段 vs 合计 —— 冰晶护体"每段 40%"配的是 0.4*ATK*3(总量)
                    pct_unit = ('}%' in line) or ('} %' in line)
                    seg = any(w in plain for w in ('每段', '每次', '每跳', '共', '合计', '段'))
                    #   d) 文字后面还跟着乘数 —— 电龟「100%×攻击力 × 1.5 = {T:ATK*1.5}」
                    #      我的正则只读到前半截, 拿 100% 去比 1.5 自然对不上。
                    if re.search(re.escape(val) + r'%\s*[×x]\s*' + kind + r'\s*(\([^)]*\))?\s*[×x]', plain):
                        continue
                    near = any(abs(g - want) <= 0.01 for g in got)
                    if got and not near and not pct_unit and not seg:
                        bad.append((str(x.get('id')), nm, k, '文字 %s%%×%s' % (val, kind),
                                    '公式 %s' % ' | '.join(phs), got))
print('★分母: 比到 %d 句(同时含"百分比文字"和"占位符公式") —— 0 句 = 空检查' % n)
print('文字 ↔ 公式 对不上: %d 处' % len(bad))
for b in bad:
    print('   %-9s %-10s %-6s %-20s %-32s 公式算出=%s' % b)
if n < 100:
    print('★分母太小, 判据可能失效了')
    sys.exit(1)
if bad:
    sys.exit(1)
print('ALL OK — 文案文字 ↔ 它自己的占位符公式')
