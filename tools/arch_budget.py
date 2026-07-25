# -*- coding: utf-8 -*-
"""arch_budget —— 架构预算门禁(强制·大厂"不许出现上帝对象"这条规范做成机器判)。

规范本身不值钱, 写在文档里没人自觉遵守 —— 25k 行的 RealtimeBattle3DScene.gd 一路长到今天
就是因为"单文件别变上帝对象"从来没被强制过。本工具把它变成【会红的门禁】:

  1. 新文件硬上限 max_file_lines: 任何【不在欠债台账里】的文件超了 → 红(挡住新的上帝对象诞生)。
  2. 历史欠债棘轮 ratchet: 存量超标文件冻结在【当前行数】, 只能【减】不能【增】——
     · 文件长了(哪怕 +1 行) → 红。逼你"想往里加代码? 先拆出去"。
     · 拆小了 → 手动把 arch_budget.json 里的数字改到新值(改小才过) = 欠债台账, 单调下降、可审计。
  3. 单函数硬上限 max_func_lines: 同理, 超长函数也是债, 新的不许生、旧的登记进 ratchet 只减不增。

★这才是"一劳永逸": 债只会减不会增, 决定权从"人的自觉"变成"门禁的红灯"。
配置见 tools/arch_budget.json。进 run-tests.sh 门禁(成功打印 ALL OK)。
"""
import io, sys, os, re, json
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

CFG = json.load(io.open('tools/arch_budget.json', encoding='utf-8'))
MAX_FILE = int(CFG['max_file_lines'])
MAX_FUNC = int(CFG['max_func_lines'])
FILE_DEBT = CFG.get('file_ratchet', {})      # path -> 冻结行数(只减不增)
FUNC_DEBT = CFG.get('func_ratchet', {})      # "path::func" -> 冻结函数行数(只减不增)
ROOTS = CFG.get('scan_roots', ['scripts', 'autoload'])

fail = [0]
def bad(msg):
    fail[0] += 1
    print('  [FAIL] ' + msg)

def count_lines(p):
    return sum(1 for _ in io.open(p, encoding='utf-8'))

def _indent(l):
    return len(l[:len(l) - len(l.lstrip())].expandtabs(4))

def func_spans(p):
    """真·函数体长度: 从 func 头到【缩进退回到 <= 函数头缩进】的第一条实语句为止。
    不把两个函数【之间】的 const/var/注释块算进函数体(那是旧逻辑的错, 会把 4 行函数算成 491 行)。"""
    lines = io.open(p, encoding='utf-8').read().splitlines()
    out = []
    i, n = 0, len(lines)
    while i < n:
        m = re.match(r'(\s*)func\s+([A-Za-z0-9_]+)', lines[i])
        if not m:
            i += 1; continue
        ind = len(m.group(1).expandtabs(4)); name = m.group(2)
        j = i + 1
        while j < n:
            s = lines[j].strip()
            if s == '' or s.startswith('#'):
                j += 1; continue
            if _indent(lines[j]) <= ind:
                break
            j += 1
        out.append((name, j - i))
        i = j
    return out

# ── 收集所有 .gd ──
allfiles = []
for base in ROOTS:
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.endswith('.gd'):
                allfiles.append(os.path.join(dp, f).replace('\\', '/'))
allfiles.sort()

print('=== 架构预算 (单文件≤%d行 · 单函数≤%d行 · 欠债只减不增) ===' % (MAX_FILE, MAX_FUNC))
print('  扫描 %d 个 .gd · 共 %d 行' % (len(allfiles), sum(count_lines(p) for p in allfiles)))

# ── 1) 文件行数 ──
print('--- 文件行数 ---')
for p in allfiles:
    n = count_lines(p)
    if p in FILE_DEBT:
        cap = int(FILE_DEBT[p])
        if n > cap:
            bad('欠债增长: %s 现 %d 行 > 台账冻结的 %d 行。往上帝文件里加代码=违规,先拆出去; 真拆小了把 arch_budget.json 改到新值。' % (p, n, cap))
        else:
            slack = cap - n
            tag = '✅已还 %d 行(请把台账 %d→%d)' % (slack, cap, n) if slack > 0 else '冻结'
            print('  [债务] %-46s %6d 行 (上限 %d·%s)' % (p, n, cap, tag))
    elif n > MAX_FILE:
        bad('新上帝对象: %s = %d 行 > 上限 %d。请拆分; 确需保留须评审后登记进 file_ratchet。' % (p, n, MAX_FILE))
if not any(p in FILE_DEBT or count_lines(p) > MAX_FILE for p in allfiles):
    print('  (无超标文件)')

# ── 2) 函数行数 ──
print('--- 函数行数 ---')
func_hits = 0
for p in allfiles:
    for name, ln in func_spans(p):
        key = '%s::%s' % (p, name)
        if key in FUNC_DEBT:
            cap = int(FUNC_DEBT[key])
            if ln > cap:
                bad('超长函数欠债增长: %s 现 %d 行 > 台账 %d。' % (key, ln, cap))
            else:
                func_hits += 1
        elif ln > MAX_FUNC:
            bad('新超长函数: %s = %d 行 > 上限 %d。请拆; 确需保留登记进 func_ratchet。' % (key, ln, MAX_FUNC))
print('  登记在册的超长函数债: %d 个(均未增长)' % func_hits)

if fail[0] == 0:
    print('ALL OK — 架构预算达标(无新上帝对象·欠债未增长)')
    sys.exit(0)
else:
    print('FAILED: %d 处架构预算违规' % fail[0])
    sys.exit(1)
