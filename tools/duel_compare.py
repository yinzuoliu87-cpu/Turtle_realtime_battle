# -*- coding: utf-8 -*-
"""两轮胜率对照 + 逐技能诊断 (2026-07-29 固化)。

由来: 第三/四轮我在对话里手搓了两遍同样的 python —— 每次都要重写"按龟聚合、
      算变化、分强弱档、找放不出来的技能"。固化成脚本, 下一轮直接跑。

用法:
    python tools/duel_compare.py --old tools/duel3 --new tools/duel4
    python tools/duel_compare.py --new tools/duel4              # 只看单轮
    python tools/duel_compare.py --old tools/duel3 --new tools/duel4 --focus lightning,fortune

它答三个问题:
  ① 每只龟这轮 vs 上轮多少 (按龟聚合 = 该龟全部技能合并)
  ② 平衡整体好了还是坏了 (平均偏离 50% / 极差 / 强弱龟只数)
  ③ 弱龟是"放不出来"还是"能放但打不动" —— 两种病要两种药,
     第三轮财神就是加强了"每次多强"而它根本放不到(梭哈340龟能·释放1.65次/场)
"""
import io, sys, os, csv, glob, argparse, collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

CN = {'basic': '普通龟', 'ninja': '忍者', 'ghost': '幽灵', 'cyber': '赛博', 'candy': '糖果',
      'headless': '无头', 'phoenix': '凤凰', 'pirate': '海盗', 'diamond': '钻石', 'gambler': '赌神',
      'space': '太空', 'stone': '石头', 'hiding': '缩头', 'shell': '贝壳', 'angel': '天使',
      'hunter': '猎人', 'bamboo': '竹子', 'lava': '熔岩', 'rainbow': '彩虹', 'bubble': '泡泡',
      'chest': '宝箱', 'crystal': '水晶', 'dice': '骰子', 'line': '线条', 'ice': '寒冰',
      'two_head': '双头', 'fortune': '财神', 'lightning': '闪电'}

STRONG, WEAK = 65.0, 35.0


def load(d):
    """→ (按龟: {id: (胜,场)}, 按技能: {(id,技名): (胜,场,释放数)})"""
    tw, tn = collections.Counter(), collections.Counter()
    sw, sn, sc = collections.Counter(), collections.Counter(), collections.Counter()
    files = sorted(glob.glob(os.path.join(d, 'duel-*.csv')))
    if not files:
        print('[FAIL] %s 下没有 duel-*.csv' % d)
        sys.exit(1)
    n_rows = 0
    for f in files:
        for r in csv.DictReader(io.open(f, encoding='utf-8')):
            n_rows += 1
            for side, t, s, rel in (('L', r['左龟'], r['左技能'], r['左释放']),
                                    ('R', r['右龟'], r['右技能'], r['右释放'])):
                tn[t] += 1
                sn[(t, s)] += 1
                sc[(t, s)] += int(rel)
                if r['胜方'] == side:
                    tw[t] += 1
                    sw[(t, s)] += 1
    return ({k: (tw[k], tn[k]) for k in tn},
            {k: (sw[k], sn[k], sc[k]) for k in sn}, n_rows, len(files))


def pct(w_n):
    w, n = w_n[0], w_n[1]
    return 100.0 * w / n if n else float('nan')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--new', required=True)
    ap.add_argument('--old', default=None)
    ap.add_argument('--focus', default='', help='逗号分隔的龟 id, 额外打逐技能明细')
    a = ap.parse_args()

    nt, ns, nrows, nfiles = load(a.new)
    ot, os_, orows, ofiles = (None, None, 0, 0)
    if a.old:
        ot, os_, orows, ofiles = load(a.old)

    print('=== 胜率对照 ===')
    print('  新: %s  %d 场 / %d 分片' % (a.new, nrows, nfiles))
    if a.old:
        print('  旧: %s  %d 场 / %d 分片' % (a.old, orows, ofiles))
        if nrows != orows:
            print('  ⚠ 两轮场次不同 (%d vs %d) —— 对比要打折看' % (nrows, orows))
    print('')

    # ── ① 按龟聚合 ──
    rows = sorted(nt.items(), key=lambda kv: -pct(kv[1]))
    print('  %-2s %-6s %8s%s %s' % ('#', '龟', '本轮', ('  %8s %8s' % ('上轮', '变化')) if a.old else '', '档'))
    for i, (k, v) in enumerate(rows, 1):
        p = pct(v)
        tag = ' ★强' if p >= STRONG else (' ▼弱' if p <= WEAK else '')
        if a.old and k in ot:
            o = pct(ot[k])
            print('  %-2d %-6s %7.1f%%  %7.1f%% %+7.1f %s' % (i, CN.get(k, k), p, o, p - o, tag))
        else:
            print('  %-2d %-6s %7.1f%% %s' % (i, CN.get(k, k), p, tag))

    # ── ② 整体 ──
    def stats(tbl):
        vs = [pct(v) for v in tbl.values()]
        return (sum(abs(v - 50) for v in vs) / len(vs), min(vs), max(vs),
                sum(1 for v in vs if v >= STRONG), sum(1 for v in vs if v <= WEAK))
    nd, nlo, nhi, nst, nwk = stats(nt)
    print('')
    print('  ── 整体 ──')
    if a.old:
        od, olo, ohi, ost, owk = stats(ot)
        print('  平均偏离 50%%:  %.1fpp → %.1fpp  (%+.1f, 越小越平衡)' % (od, nd, nd - od))
        print('  极差:          %.1f%%~%.1f%%  →  %.1f%%~%.1f%%' % (olo, ohi, nlo, nhi))
        print('  ≥%.0f%% 强龟:     %d → %d 只' % (STRONG, ost, nst))
        print('  ≤%.0f%% 弱龟:     %d → %d 只' % (WEAK, owk, nwk))
    else:
        print('  平均偏离 50%%: %.1fpp | 极差 %.1f%%~%.1f%% | 强龟 %d 只 / 弱龟 %d 只'
              % (nd, nlo, nhi, nst, nwk))

    # ── ③ 弱龟诊断: 放不出来 vs 打不动 ──
    casts = [v[2] / v[1] for v in ns.values() if v[1]]
    med = sorted(casts)[len(casts) // 2]
    print('')
    print('  ── 弱龟诊断 (全表技能释放/场 中位数 %.2f) ──' % med)
    print('  两种病要两种药: "放不出来"加数值没用(得降价/降门槛), "打不动"才该加数值')
    weak = [k for k, v in nt.items() if pct(v) <= WEAK]
    for t in sorted(weak, key=lambda t: pct(nt[t])):
        print('  %s %.1f%%' % (CN.get(t, t), pct(nt[t])))
        for k in sorted([k for k in ns if k[0] == t], key=lambda k: -pct(ns[k])):
            w, n, c = ns[k]
            wr, cp = 100.0 * w / n, c / n
            dx = '★放不出来(释放 %.0f%% 中位数)' % (100 * cp / med) if cp < med * 0.65 else (
                 '能放但打不动' if wr < 30 else '')
            print('     %-10s %5.1f%%  释放 %.2f/场  %s' % (k[1], wr, cp, dx))

    # ── ④ focus: 指定龟的逐技能明细(含与上轮对比) ──
    foc = [x.strip() for x in a.focus.split(',') if x.strip()]
    if foc:
        print('')
        print('  ── 指定龟逐技能 ──')
        for t in foc:
            if t not in nt:
                print('  (无此龟: %s)' % t); continue
            head = '  %s %.1f%%' % (CN.get(t, t), pct(nt[t]))
            if a.old and t in ot:
                head += '  (上轮 %.1f%%, %+.1f)' % (pct(ot[t]), pct(nt[t]) - pct(ot[t]))
            print(head)
            for k in sorted([k for k in ns if k[0] == t], key=lambda k: -pct(ns[k])):
                w, n, c = ns[k]
                line = '     %-10s %5.1f%%  释放 %.2f/场' % (k[1], 100.0 * w / n, c / n)
                if a.old and os_ and k in os_:
                    ow, on, oc = os_[k]
                    line += '   (上轮 %.1f%% / %.2f次, %+.1fpp)' % (
                        100.0 * ow / on, oc / on, 100.0 * w / n - 100.0 * ow / on)
                print(line)

    # ── ⑤ 分母自检 ──
    print('')
    print('  ── 分母 ──')
    per = collections.Counter(v[1] for v in ns.values())
    print('  组合数 %d (应 84) | 每组合场次分布 %s | 总场次 %d (应 3486)'
          % (len(ns), dict(per), nrows))
    zero = [k for k, v in ns.items() if v[2] == 0]
    print('  技能释放恒为 0 的组合: %d 个 %s' % (len(zero), zero[:5] if zero else ''))
    ok = (len(ns) == 84 and nrows == 3486 and not zero)
    print('  %s' % ('★四条判据全过' if ok else '★有判据没过 —— 上面的表要打问号'))


if __name__ == '__main__':
    main()
