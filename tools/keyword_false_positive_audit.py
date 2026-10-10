# -*- coding: utf-8 -*-
"""keyword_false_positive_audit.py — 关键词自动上色的【误伤】审计。

★由来(2026-10-10): `SkillText.colorize_keywords` 按 `KEYWORD_RULES` 在中文里**按子串**匹配,
  而中文没有词边界 ⇒ 只是"含有"关键词的别的词也被上色。实抓:
    052 左轮手枪「子弹为 0 **时停**止射击」—— 「时停」被染成控制色, 读起来像这件装备会时停。

★判据(不渲染、不起 Godot, <1 秒):
  ① **规则从 `scripts/util/skill_text.gd` 的 KEYWORD_RULES 现读**(不抄第二份 ——
     memory [[fb-hand-rolled-copies-drift]])。
  ② 玩家文案取料 = 两份 json 里所有过 `render_bbcode` / `equip_*_bb` 的字段
     (调用点: detail_views / skill_picker / detail_panel / battle_render / info_panel /
      ShopScene / InventoryScene / dual_lane_flow —— 取的都是下面 TEXT_KEYS 这几个字段)。
     `{C:类.常量}` 按 text_golden 同一套展开; `{X:expr}` 展开成带色 span(与游戏同形)。
  ③ **逐条复刻 colorize_keywords 的顺序替换**, 再把每个关键词 span
     映回纯文本位置, 判它是不是误伤:
       · 落在下面 COMPOUND 表登记的「别的词」里            ⇒ 误伤
       · 落在**数据里的专名**(装备名/龟名/技能名/被动名)里,
         且这个专名不在 NAME_OK 白名单                       ⇒ 误伤
       · 落在【…】里 ⇒ 有意嵌套(KEYWORD_RULES 头注写明), 单独计数不判红
  ④ 打印每条规则的命中数(真/误/专名内嵌套)当分母; 任何误伤 ⇒ exit 1。

用法:
  python tools/keyword_false_positive_audit.py            # 对账(进门禁)
  python tools/keyword_false_positive_audit.py --dump     # 逐条列出全部命中 + 上下文
"""
import io, json, os, re, sys

sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
os.chdir(ROOT)

import text_golden as TG   # const_map / expand —— 与快照同一套 {C:} 展开口径

SRC = 'scripts/util/skill_text.gd'
## 过 colorize_keywords 的字段(两份 json 都用这一张; 多收无害, 少收就是漏)
TEXT_KEYS = ['brief', 'desc', 'detail', 'effect', 'effectBrief',
             'effectDesc1', 'effectDesc2', 'effectDesc3']

## ══════════════════════════════════════════════════════════════════════
## 【别的词】表 —— 关键词 K 出现在这些串里时, 它其实是另一个词的一部分。
##   格式: (关键词, 含它的那个更长的词)。判据 = 纯文本里这条命中的位置
##   恰好落在那个更长的词里。**只登记实抓到的**, 每条写出处。
##   ★这张表是审计侧的「标准答案」; 产品侧的修法是 KEYWORD_RULES 里那条规则的 lookahead,
##     两处**故意分开**: 规则改松了(比如有人把 `(?!止|<)` 删回 `(?!<)`), 这里照样红。
## ══════════════════════════════════════════════════════════════════════
COMPOUND = [
    ('时停', '时停止'),     # 052 左轮手枪「子弹为 0 时停止射击」—— 是「时 + 停止」
    ('魔法', '魔法波'),     # 双头龟融合技的称呼, 实际打物理/真实伤害(数据里不是 name 字段, 专名扫不到)
    ('魔法', '魔法光线'),   # 水晶球那一道光线的称呼(同上)
]

## 专名里**本来就该读成那个关键词**的 —— 放行。
##   判据: 名字的中心词就是这个关键词, 且这件东西/技能确实就是那个东西
##   (「泡泡护盾」确实给护盾; 「魔法胸甲」是件胸甲, 不造成魔法伤害 ⇒ 不放行)。
NAME_OK = {
    ('圣光护盾', '护盾'),   # 装备名同时就是它给的那层护盾(「获得 55 点圣光护盾」), 与【奶油护盾】同一待遇
}



def parse_gd_string_list(body):
    """把 `[ ["a", "b", "c"], ... ]` 形状的 GDScript 字面量拆成 list[list[str]]。"""
    out = []
    for row in re.finditer(r'\[((?:\s*"(?:[^"\\]|\\.)*"\s*,?)+)\]', body):
        items = re.findall(r'"((?:[^"\\]|\\.)*)"', row.group(1))
        out.append([i.replace('\\"', '"').replace('\\\\', '\\') for i in items])
    return out


def strip_comments(block):
    lines = []
    for ln in block.split('\n'):
        ## 去掉 `#` 起的注释 —— 但字符串里的 # 不算(本表的串里没有 #)
        res, inq, esc = '', False, False
        for ch in ln:
            if esc:
                res += ch; esc = False; continue
            if ch == '\\' and inq:
                res += ch; esc = True; continue
            if ch == '"':
                inq = not inq
            if ch == '#' and not inq:
                break
            res += ch
        lines.append(res)
    return '\n'.join(lines)


def read_const_block(src, name):
    m = re.search(r'(?m)^const\s+' + name + r'\s*:?=\s*\[', src)
    if not m:
        return None
    i = m.end() - 1
    depth, inq, esc = 0, False, False
    for j in range(i, len(src)):
        ch = src[j]
        if esc:
            esc = False; continue
        if ch == '\\' and inq:
            esc = True; continue
        if ch == '"':
            inq = not inq; continue
        if inq:
            continue
        if ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
            if depth == 0:
                return strip_comments(src[i:j + 1])
    return None


def load_rules():
    src = io.open(SRC, encoding='utf-8').read()
    blk = read_const_block(src, 'KEYWORD_RULES')
    return parse_gd_string_list(blk[1:-1]) if blk else []


def collect_texts():
    cmap = TG.const_map()
    rows = []
    names = set()

    def walk(o, path):
        if isinstance(o, dict):
            nm = o.get('name')
            if isinstance(nm, str) and nm.strip():
                names.add(nm.strip())
            tag = str(nm or o.get('id') or '')
            for k in TEXT_KEYS:
                v = o.get(k)
                if isinstance(v, str) and v.strip():
                    rows.append((path + tag + '|' + k, TG.expand(v, cmap)))
            for k, v in o.items():
                if not (isinstance(v, str) and k in TEXT_KEYS):
                    walk(v, path + (tag + '/' if tag else ''))
        elif isinstance(o, list):
            for x in o:
                walk(x, path)

    for f, tag in [('data/pets.json', 'pet:'), ('data/phase2-equipment.json', 'eq:')]:
        walk(json.load(io.open(f, encoding='utf-8')), tag)
    return rows, names


COLOR_CLASS = {'N': 'val-normal', 'P': 'val-pierce', 'S': 'val-shield', 'H': 'val-heal',
               'B': 'val-buff', 'D': 'val-def', 'M': 'val-magic', 'T': 'val-true', 'E': 'val-emph'}
TOKEN = re.compile(r'\{([A-Z]):([^}]+)\}|\{([^}]+)\}')


def expand_tokens(t):
    def rep(m):
        c = m.group(1)
        if c and c in COLOR_CLASS:
            return '<span class="%s">0</span>' % COLOR_CLASS[c]
        return '0'
    return TOKEN.sub(rep, t)


def colorize(text, rules):
    """复刻 SkillText.colorize_keywords: 按表序逐条整段替换(后一条看得见前一条插的 span)。
    span 上多带一个 r="规则序号" —— 以 `">` 结尾, 不改变任何 lookbehind 的判定。"""
    for idx, r in enumerate(rules):
        pat, cls = r[0], r[1]
        rx = re.compile(pat)
        text = rx.sub(lambda m: '<span class="%s" r="%d">%s</span>' % (cls, idx, m.group(0)), text)
    return text


SPAN_OPEN = re.compile(r'<span\b[^>]*>')


def keyword_hits(html):
    """→ (纯文本, [(规则序号, start, end)])。只收带 r= 的(规则产生的) span。"""
    plain = ''
    stack = []
    hits = []
    i = 0
    while i < len(html):
        if html[i] == '<':
            gt = html.find('>', i)
            if gt < 0:
                plain += html[i]; i += 1; continue
            tag = html[i:gt + 1]
            i = gt + 1
            low = tag.lower()
            if low.startswith('<span'):
                m = re.search(r'\br="(\d+)"', tag)
                stack.append((int(m.group(1)) if m else None, len(plain)))
            elif low.startswith('</span'):
                if stack:
                    ri, st = stack.pop()
                    if ri is not None:
                        hits.append((ri, st, len(plain)))
            elif low.startswith('<br'):
                plain += '\n'
            continue
        plain += html[i]
        i += 1
    return plain, hits


def main():
    rules = load_rules()
    rows, names = collect_texts()
    print('[分母] KEYWORD_RULES %d 条(现读 %s) · 文案 %d 段 · 数据专名 %d 个'
          % (len(rules), SRC, len(rows), len(names)))
    if len(rules) < 20 or len(rows) < 200:
        print('[FAIL] 规则或文案收得太少 —— 取料坏了, 这是空检查不是通过')
        return 1
    bracket_idx = [i for i, r in enumerate(rules) if r[0].startswith('【')]
    section_idx = [i for i, r in enumerate(rules) if '主动|被动' in r[0]]
    stat = {i: {'tp': 0, 'fp': 0, 'nest': 0} for i in range(len(rules))}
    fps = []
    dump = '--dump' in sys.argv
    for key, raw in rows:
        html = colorize(expand_tokens(raw), rules)
        plain, hits = keyword_hits(html)
        ## 【…】区间
        brk = [(m.start(), m.end()) for m in re.finditer(r'【[^】]{1,12}】', plain)]
        for ri, s, e in hits:
            word = plain[s:e]
            if ri in bracket_idx or ri in section_idx:
                stat[ri]['tp'] += 1
                continue
            why = None
            for kw, comp in COMPOUND:
                if word != kw:
                    continue
                off = comp.find(kw)
                a = s - off
                if a >= 0 and plain[a:a + len(comp)] == comp:
                    why = '别的词「%s」' % comp
                    break
            if why is None:
                for nm in names:
                    if len(nm) <= len(word) or word not in nm:
                        continue
                    ## 这个名字在纯文本里覆盖了这条命中吗
                    for mm in re.finditer(re.escape(nm), plain):
                        if mm.start() <= s and e <= mm.end():
                            if (nm, word) not in NAME_OK:
                                why = '专名「%s」' % nm
                            break
                    if why:
                        break
            in_brk = any(a <= s and e <= b for a, b in brk)
            if why and in_brk:
                ## 【专名】里的嵌套是有意的(KEYWORD_RULES 头注)
                why = None
            if why:
                stat[ri]['fp'] += 1
                fps.append((key, ri, word, why, plain[max(0, s - 12):e + 12].replace('\n', '⏎')))
            elif in_brk:
                stat[ri]['nest'] += 1
            else:
                stat[ri]['tp'] += 1
            if dump:
                print('  %-4s r%02d %-6s %s  …%s…' % ('FP' if why else ('NEST' if in_brk else 'ok'),
                                                    ri, word, key, plain[max(0, s - 10):e + 10].replace('\n', '⏎')))
    print('')
    print('  规则  命中(真) 误伤 【】内嵌套  pattern')
    tot = {'tp': 0, 'fp': 0, 'nest': 0}
    for i, r in enumerate(rules):
        st = stat[i]
        for k in tot:
            tot[k] += st[k]
        print('  r%02d  %6d  %4d  %6d   %s' % (i, st['tp'], st['fp'], st['nest'], r[0]))
    print('  合计 真 %d · 误伤 %d · 【】内嵌套 %d(有意, 不判红)' % (tot['tp'], tot['fp'], tot['nest']))
    if tot['tp'] < 300:
        print('[FAIL] 真命中只有 %d(<300) —— 复刻的上色管线坏了, 这是空检查' % tot['tp'])
        return 1
    if fps:
        print('')
        print('[FAIL] 关键词误伤 %d 处(关键词只是别的词/专名的一部分, 却被上了色):' % len(fps))
        for key, ri, word, why, ctx in fps:
            print('   r%02d 「%s」 在%s  %s  …%s…' % (ri, word, why, key, ctx))
        print('  修法: 给 skill_text.gd KEYWORD_RULES 里那条规则加 lookahead/lookbehind 排除那个更长的词;'
              ' 专名里本该读成关键词的(如「圣光护盾」给的就是护盾)登记进本文件 NAME_OK。')
        return 1
    print('\nALL OK — %d 段文案里 %d 处关键词上色无误伤' % (len(rows), tot['tp'] + tot['nest']))
    return 0


if __name__ == '__main__':
    sys.exit(main())
