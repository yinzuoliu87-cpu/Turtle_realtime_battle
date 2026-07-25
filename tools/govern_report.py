# -*- coding: utf-8 -*-
"""govern_report —— 规范化健康仪表盘(只读·一眼看全)。

大厂有"工程健康看板"。本工具把散在各门禁里的状态汇成一屏: 装了哪些强制规范、
上帝文件欠了多少债、离目标还有多远、裸随机冻结情况。让"项目在被管理"这件事【可见】,
而不是散在一堆 python 里各说各的。

只读·不改任何东西·不进门禁(它是给人看的报告, 不是判定)。跑: python tools/govern_report.py
"""
import io, sys, os, re, json
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

def J(p):
    return json.load(io.open(p, encoding='utf-8'))

def count_lines(p):
    return sum(1 for _ in io.open(p, encoding='utf-8'))

ab = J('tools/arch_budget.json')
rb = J('tools/rng_budget.json')
ROOTS = ab.get('scan_roots', ['scripts', 'autoload'])

files = []
for base in ROOTS:
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.endswith('.gd'):
                files.append(os.path.join(dp, f).replace(os.sep, '/'))
total_lines = sum(count_lines(p) for p in files)

print('╔══════════════════════════════════════════════════════════════╗')
print('║           斗龟场·实时版 — 规范化健康仪表盘                    ║')
print('╚══════════════════════════════════════════════════════════════╝')

print('\n【强制门禁】(违反即红·bash run-tests.sh)')
gates = [
    ('arch_budget',    '不许上帝对象·单文件≤%d/单函数≤%d·棘轮' % (ab['max_file_lines'], ab['max_func_lines'])),
    ('style_lint',     '全 tab / snake_case / PascalCase 焊死'),
    ('rng_discipline', '裸全局随机冻结·护确定性不回退'),
    ('verify_version', '版本号四处一致 + 游戏内不写死'),
    ('data_integrity / tri_audit', '数据单一事实源·三方对账'),
    ('tooltip/brief_detail_audit', '文案数值 ↔ 代码'),
    ('verify_*_determinism', '同种子逐字节可复现 + 帧率无关'),
    ('workflow_lint', 'CI 工作流 YAML 可解析'),
]
for n, d in gates:
    print('  ✅ %-28s %s' % (n, d))

print('\n【架构债 · 棘轮台账(只减不增)】')
god_cap = None
for p, cap in ab.get('file_ratchet', {}).items():
    now = count_lines(p) if os.path.exists(p) else 0
    god_cap = (p, now, cap)
    tgt = ab['max_file_lines']
    debt = max(0, now - tgt)
    bar_full = 40
    paid = tgt
    frac = min(1.0, paid / float(now)) if now else 1.0
    filled = int(frac * bar_full)
    bar = '█' * filled + '░' * (bar_full - filled)
    status = '冻结·未增长 ✅' if now <= cap else '⚠ 已增长(门禁会红)'
    print('  %s' % p)
    print('    现 %d 行 / 冻结上限 %d (%s)' % (now, cap, status))
    print('    目标 %d 行 → 还欠 %d 行待拆  [%s] %.0f%%' % (tgt, debt, bar, frac * 100))
for k, cap in ab.get('func_ratchet', {}).items():
    print('  超长函数债: %s ≤ %d 行(冻结)' % (k.split('::')[-1], cap))

print('\n【随机源纪律】')
BARE = re.compile(r'(?<![\.\w])(randf|randi|randf_range|randi_range|randfn)\s*\(')
bare = 0
for p in files:
    for l in io.open(p, encoding='utf-8'):
        bare += len(BARE.findall(l.split('#', 1)[0]))
print('  裸全局随机 %d 处 / 冻结 %d (%s)' % (bare, rb['max_bare_rng'],
      '未增长 ✅' if bare <= rb['max_bare_rng'] else '⚠ 增长'))

print('\n【总量】')
print('  %d 个 .gd · 共 %d 行' % (len(files), total_lines))
if god_cap:
    p, now, cap = god_cap
    print('  最大单文件占全项目 %.0f%% (%s)' % (100.0 * now / total_lines, p.split('/')[-1]))
print('\n规范全文: docs/工程规范.md   拆分路线: docs/design/主文件拆分方案-20260719.md')
