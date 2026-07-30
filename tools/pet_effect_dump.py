# -*- coding: utf-8 -*-
"""龟技能【代码真实效果清单】(2026-07-30)。

★用途: 做平衡分析 / 向用户汇报技能效果时【跑这个, 不读 tooltip】。

  由来 (用户 2026-07-30):「有些细节不应该让玩家看到的, 但你在看技能时应该以代码的
  实际效果来向我汇报, 这怎么办」。玩家文案是【设计决定】(有些效果故意不写),
  而分析强度必须看代码。两者混用就会出现:
    · 无头·灵魂打击 —— 我按文案报「0.9A + 20%当前生命」, 代码是 0.5A + 10%(差一倍),
      而且文案完全没提镰刀横扫的【5 秒诅咒 + 锁龟能】
    · 训龟大师·魔法石 —— 文案 2%, 代码已是 (2+0.1×大轮等级)%

跑法:
    python tools/pet_effect_dump.py                      # 全 28 龟
    python tools/pet_effect_dump.py ice                  # 单只龟
    python tools/pet_effect_dump.py headless:灵魂打击      # 单个技能
    python tools/pet_effect_dump.py --diff               # 只列【代码有但文案没写】的

输出里 ⚠ 标记的 = 该效果在玩家文案里【找不到对应关键词】。
  它可能是"忘了写"(该补), 也可能是"故意不给玩家看"(实现细节)——
  分辨依据见 pet_number_audit.py 的 HIDDEN 登记表。

★局限见 pet_code_scope.py 的模块注释 —— 延时回调/逐帧状态机跟不进去。
  所以"这里没列出来"不等于"代码里没有"。
"""
import io, os, sys, json, re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pet_code_scope as S

OUT = io.TextIOWrapper(open(sys.stdout.fileno(), 'wb', closefd=False), encoding='utf-8')


def P(x=''):
    OUT.write(str(x) + '\n')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    only_diff = '--diff' in sys.argv

    d = json.load(io.open('data/pets.json', encoding='utf-8'))
    arr = d if isinstance(d, list) else next(v for v in d.values() if isinstance(v, list))
    pets = {str(x.get('id', '')): x for x in arr}
    src = S.load_src()
    disp = S.dispatch_map(src)

    # 解析目标
    targets = []
    if not args:
        for pid, p in pets.items():
            for s in p.get('skillPool', []):
                targets.append((pid, str(s.get('name', ''))))
    else:
        for a in args:
            if ':' in a:
                pid, nm = a.split(':', 1)
                targets.append((pid, nm))
            else:
                for s in pets.get(a, {}).get('skillPool', []):
                    targets.append((a, str(s.get('name', ''))))

    n_eff = n_warn = n_skip = 0
    for pid, nm in targets:
        p = pets.get(pid)
        if p is None:
            P('  (无此龟: %s)' % pid)
            continue
        hit = [x for x in p.get('skillPool', []) if str(x.get('name', '')) == nm]
        if not hit:
            P('  (%s 没有技能 %s)' % (pid, nm))
            continue
        s = hit[0]
        ty = str(s.get('type', ''))
        fname = disp.get(ty)
        text = str(s.get('brief', '')) + ' ' + str(s.get('detail', ''))
        if fname is None:
            n_skip += 1
            if not only_diff:
                P('══ %s · %s   (type=%s → 未在 _sk_* 分派表里·多为普攻走 BASIC_ATK)'
                  % (p.get('name'), nm, ty))
                P('')
            continue
        path, effs = S.effects_of(src, fname)
        rows = []
        for fn, line, cat in effs:
            words = S.CATEGORY_WORDS.get(cat)
            shown = True if words is None else any(w in text for w in words)
            if not shown:
                n_warn += 1
            n_eff += 1
            rows.append((fn, line, shown))
        if only_diff:
            rows = [r for r in rows if not r[2]]
            if not rows:
                continue
        P('══ %s · %s   (%s → %s)' % (p.get('name'), nm, ty, fname))
        P('   实现: %s' % path)
        cur = None
        for fn, line, shown in rows:
            if fn != cur:
                P('   ── %s()' % fn)
                cur = fn
            P('      %s %s' % ('  ' if shown else '⚠ ', line))
        P('')

    P('── 合计: 效果 %d 条 · 其中文案未提 %d 条 · 跳过(普攻等未映射) %d 个技能'
      % (n_eff, n_warn, n_skip))
    P('   ⚠ = 玩家文案里找不到对应关键词。是"该补"还是"故意隐藏", 见'
      ' pet_number_audit.py 的 HIDDEN 表。')
    OUT.flush()


if __name__ == '__main__':
    main()
