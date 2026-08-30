# -*- coding: utf-8 -*-
"""龟壳「复制」链路的四方一致性审计 (2026-08-28)。

用户 2026-08-28:「我需要根除任何分歧，不允许之后再出任何分歧」。
这条链路上"同一件事记在多个地方"的对账全在这里。

四份事实源:
  A. `data/pets.json` 的 skillPool[].type   —— 玩家真能选到的技能(权威)
  B. `_do_skill` 的 match 块                —— 真能被执行的
  C. `_IMPL_SKILLS`                         —— 声明"已实现"的
  D. `CopyRules.UNCOPYABLE`                 —— 龟壳【不】能抄的(2026-08-29 白名单倒成黑名单)
  E. `battle_spawn` 里小将/精英的 active_skills —— 战斗里真会出现的非龟技

★★判据必须落在【match 块里的 case 标签】, 不能用 `"xxx": _sk_...` 这种正则 ——
  2026-08-28 我就是这么栽的: `fortuneAllIn` 的分派值是个**三元表达式**
  (`(A if cond else B)`), 不以 `_sk_` 开头 ⇒ 正则认不出 ⇒ 报成"声明已实现但没分派"。
  **同一个问题我一晚上判错三次**(先说可抄率 50%、再说 14 个死条目、再说 fortuneAllIn),
  三次全是**拿正则扫源码去猜**。所以这里改成先切出 `_do_skill` 函数体、再取所有 case 标签,
  与"值长什么样"完全无关。

★每一类都打分母 —— N=0 是空检查不是通过。
"""
import io
import json
import os
import re
import sys
from collections import defaultdict

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

RB = 'scripts/scenes/RealtimeBattle3DScene.gd'
RULES = 'scripts/gamedata/copy_rules.gd'
SPAWN = 'scripts/scenes/battle/battle_spawn.gd'
PETS = 'data/pets.json'

## ★普攻位技能【本来就不该】走 `_do_skill` —— 它们是各龟普攻的实现(cd=0/energyCost=0),
##   走普攻分派。放进白名单是错的(永远不会被执行), 但"不在 match 块里"对它们不是问题。
##   判据: pets.json 里 skillPool[0](按约定就是普攻, 28 只无一例外)。
def basic_slot_types(pets):
    out = set()
    for p in pets:
        pool = p.get('skillPool') or []
        if pool and isinstance(pool[0], dict):
            t = str(pool[0].get('type', ''))
            if t:
                out.add(t)
    return out


def const_keys(src, name):
    m = re.search(r'const %s\s*:?=\s*\{(.*?)\n\}' % name, src, re.S)
    if not m:
        m = re.search(r'const %s\s*:?=\s*\{(.*?)\}' % name, src, re.S)
    return set(re.findall(r'"([a-zA-Z]+)"', m.group(1))) if m else set()


def dispatched(src):
    """`_do_skill` 的 match 块里所有 case 标签 —— 与分派值的写法无关。"""
    m = re.search(r'func _do_skill\(.*?\n(?=func )', src, re.S)
    return set(re.findall(r'^\s*"([a-zA-Z]+)":', m.group(0), re.M)) if m else set()


def main():
    for p in (RB, SPAWN, PETS):
        if not os.path.exists(p):
            print('  [FAIL] 缺 %s' % p)
            return 1
    src = io.open(RB, encoding='utf-8').read()
    rules = io.open(RULES, encoding='utf-8').read()
    spawn = io.open(SPAWN, encoding='utf-8').read()
    d = json.loads(io.open(PETS, encoding='utf-8').read())
    pets = d if isinstance(d, list) else d.get('pets', d.get('items', []))

    DISPATCH = dispatched(src)
    IMPL = const_keys(src, '_IMPL_SKILLS')
    ## ★2026-08-29 黑名单模型: 能抄的 = _IMPL 里【不在黑名单】的
    ##   (运行时判据 `CopyRules.can_copy` 就是这两条, 这里逐字照它算)
    BLOCK = set(re.findall(r'^\t"([a-zA-Z]+)":',
        re.search(r'const UNCOPYABLE\s*:?=\s*\{(.*?)\n\}', rules, re.S).group(1), re.M))
    COPYABLE = IMPL - BLOCK
    BASIC = basic_slot_types(pets)
    MINION = set(re.findall(r'active_skills"\]\s*=\s*\["([a-zA-Z]+)"\]', spawn))

    petskill = {}
    for p in pets:
        for sk in (p.get('skillPool') or []):
            t = str(sk.get('type', ''))
            if t:
                petskill[t] = (str(p.get('id')), str(sk.get('name', '')))

    print('  [分母] pets 技能 %d(其中普攻位 %d) · 分派 %d · _IMPL %d · 黑名单 %d · 可抄 %d · 小将技 %d'
          % (len(petskill), len(BASIC), len(DISPATCH), len(IMPL), len(BLOCK), len(COPYABLE), len(MINION)))
    ## 分母守卫: 任何一项解析成 0 = 判据坏了, 不是"没问题"。
    for nm, v in (('分派表', DISPATCH), ('_IMPL', IMPL), ('黑名单', BLOCK), ('可抄集', COPYABLE),
                  ('pets 技能', petskill), ('小将技', MINION), ('普攻位', BASIC)):
        if len(v) == 0:
            print('  [FAIL] ★分母: %s 解析出 0 项 —— 判据坏了(空检查不是通过)' % nm)
            return 1

    fails = []

    # ① 黑名单里指向【根本不存在】的技能 = 挡了个寂寞(打错字/技能改名后没跟)
    for x in sorted(BLOCK - IMPL):
        fails.append('①黑名单 `%s` 在 _IMPL 里根本不存在 —— 挡了个寂寞(打错字? 技能改名了?)' % x)

    # ①b 黑名单每条都要有【探针量到的具体残留】当理由, 不许写"感觉会出问题"
    for x in sorted(BLOCK):
        m = re.search(r'"%s":\s*"([^"]*)"' % re.escape(x), rules)
        why = m.group(1) if m else ''
        if len(why) < 12 or not re.search(r'[a-z_]{4,}', why):
            fails.append('①b黑名单 `%s` 的理由不合格 —— 必须写探针量到的具体字段名, 现在是 %r' % (x, why))

    # ② 战斗里真会出现的小将/精英技, 被黑名单挡了(得有理由)
    for x in sorted(MINION & BLOCK):
        fails.append('②小将/精英技 `%s` 战斗里真会挂, 却在黑名单里' % x)

    # ③ 声明已实现(_IMPL) 但 match 块里没有
    for x in sorted(IMPL - DISPATCH - BASIC):
        fails.append('③`%s` 在 _IMPL 里声明已实现, 但 _do_skill 分派不到' % x)

    # ④ 玩家能选、非普攻位、却既不在分派表也不在 _IMPL —— 选了可能空转
    for x in sorted(set(petskill) - DISPATCH - IMPL - BASIC):
        fails.append('④玩家可选 `%s`(%s·%s) 既没分派也没声明实现 —— 可能空转'
                     % ((x,) + petskill[x]))

    # ⑤ 覆盖率棘轮: 可抄技能数只增不减
    cop = sorted(t for t in petskill if t in COPYABLE)
    base_path = 'tools/copy_chain_baseline.json'
    base = json.loads(io.open(base_path, encoding='utf-8').read()) if os.path.exists(base_path) else None
    print('  [分母] 可抄率 %d/%d = %.0f%%' % (len(cop), len(petskill), 100.0 * len(cop) / len(petskill)))
    if base is not None:
        ## ★★下线要【带理由】才允许 —— 2026-08-30 新增。
        ##   棘轮的本意是"别偷偷把可抄面缩回去", 但有时候下线是【对的】:
        ##   批量台(82 个逐个抄一遍)量出 3 个技能抄了会崩 / 会把龟壳锁死一整场。
        ##   直接改基线 = 无声降标准; 所以改成: 下线必须在 UNCOPYABLE 里
        ##   **带一句写明白的理由**(≥20 字)。该下线的过得去, 偷偷缩水的照样红。
        rules_src = io.open('scripts/gamedata/copy_rules.gd', encoding='utf-8').read()
        why = {}
        for ln in rules_src.split(chr(10)):
            t = ln.strip()
            if not t.startswith('"'):
                continue
            a = t.find('"')
            b = t.find('"', a + 1)
            c = t.find('"', b + 1)
            d = t.rfind('"')
            if a < 0 or b <= a or c <= b or d <= c:
                continue
            why[t[a + 1:b]] = t[c + 1:d]
        lost = sorted(set(base.get('list', [])) - set(cop))
        for x in lost:
            r = why.get(x, '')
            if len(r) < 20:
                fails.append('⑤原本能抄的 `%s` 现在抄不到了, 而 UNCOPYABLE 里没有(或只有一句空话的)'
                             '理由 —— 下线可以, 但必须写清为什么' % x)
            else:
                print('  [已下线·有理由] %-20s %s' % (x, r[:74]))
        ## ★计数那条要【扣掉有理由的下线】—— 否则每次正当下线都得手改基线,
        ##   而手改基线正是"无声降标准"本身。有理由的不算退步, 没理由的照样红。
        ok_lost = 0
        for x in sorted(set(base.get('list', [])) - set(cop)):
            if len(str(why.get(x, ''))) >= 20:
                ok_lost += 1
        if len(cop) < int(base.get('copyable', 0)) - ok_lost:
            fails.append('⑤覆盖率退步: 可抄 %d < 基线 %d - 有理由下线 %d —— 只许增不许减'
                         % (len(cop), int(base['copyable']), ok_lost))

    # ⑥ 逐龟: 整只龟一个都抄不到(只报, 不判红 —— 那是设计问题不是漂移)
    per = defaultdict(lambda: [0, 0])
    for t, (pid, _n) in petskill.items():
        per[pid][1] += 1
        if t in COPYABLE:
            per[pid][0] += 1
    zero = sorted(p for p, (c, _tt) in per.items() if c == 0)
    if zero:
        print('  [注意] 整只龟一个技能都抄不到: %s (共 %d 只)' % (' '.join(zero), len(zero)))

    for x in fails:
        print('  [FAIL] ' + x)
    if fails:
        print('')
        print('FAILED: %d 处 —— 复制链路有分歧' % len(fails))
        return 1
    print('')
    print('ALL OK — 复制链路四方一致')
    return 0


if __name__ == '__main__':
    sys.exit(main())
