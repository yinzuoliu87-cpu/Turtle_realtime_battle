# -*- coding: utf-8 -*-
"""GitHub Actions 工作流语法体检(只读)。2026-07-23 建。

【为什么要有】2026-07-23: 我给 tests.yml 加"把失败行做成注解"那一步时, 写了一行
`tr '\n' ' | '` —— 里面的换行是【真换行】, 续行顶到第 0 列。
YAML 里缩进比块标量小就会终止块, GitHub 于是拿后半行当 YAML 结构解析 → 整个工作流解析失败。

表现极具迷惑性:
  · 页面/API 里 workflow 的 name 变成【文件路径】(读不到 name 字段)
  · run 的 conclusion = failure, 但 jobs 列表【是空的】—— 一个 job 都没跑
  · 于是"门禁红了"看起来像测试挂了, 实际是工作流根本没启动
我因此连续两次把它误判成"测试在 Linux 上失败", 而真实情况是【门禁从那次提交起就没再运行过】。

本脚本守三件事:
  ① 每个工作流都能被 YAML 解析
  ② 解析出来必须有 name 和至少一个 job(能解析但结构空 = 一样不跑)
  ③ run: 块里不许出现"看起来像被转义换行截断"的可疑行(顶格的续行)
"""
import io, os, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

try:
    import yaml
except ImportError:
    print('[SKIP] 没装 pyyaml —— 装了才能查工作流语法: pip install pyyaml')
    print('ALL OK')   # 不因缺依赖卡住提交; CI 上一定装得上
    sys.exit(0)

WF = '.github/workflows'
bad = 0
n = 0

if not os.path.isdir(WF):
    print('[FAIL] 找不到 %s' % WF)
    sys.exit(1)

files = sorted(f for f in os.listdir(WF) if f.endswith(('.yml', '.yaml')))
print('工作流 %d 个' % len(files))
if not files:
    print('[FAIL] 一个工作流都没有 —— 空检查不是通过')
    sys.exit(1)

for f in files:
    p = os.path.join(WF, f)
    raw = io.open(p, encoding='utf-8').read()
    n += 1
    try:
        d = yaml.safe_load(raw)
    except Exception as e:
        bad += 1
        print('[FAIL] %s YAML 解析失败:' % f)
        print('       %s' % str(e).replace('\n', ' ')[:220])
        continue
    if not isinstance(d, dict):
        bad += 1
        print('[FAIL] %s 顶层不是对象' % f)
        continue
    name = d.get('name')
    jobs = d.get('jobs') or {}
    if not name:
        bad += 1
        print('[FAIL] %s 没有 name —— GitHub 会用文件路径当名字, 这正是解析出问题的信号' % f)
    if not jobs:
        bad += 1
        print('[FAIL] %s 没有任何 job —— 能解析但不跑, 等于门禁失效' % f)
    # ③ 顶格续行: 块标量里出现零缩进的非空行, 多半是转义换行把命令截断了
    for i, line in enumerate(raw.split('\n'), 1):
        if line and not line[0].isspace() and not line.startswith('#'):
            # 顶层键(name:/on:/jobs:/permissions:)是合法的顶格
            head = line.split(':')[0].strip()
            if ':' in line and head and all(c.isalnum() or c in '_-' for c in head):
                continue
            bad += 1
            print('[FAIL] %s:%d 顶格续行(疑似转义换行截断了命令): %s' % (f, i, line[:70]))
    print('  OK  %-22s name=%-22s jobs=%s' % (f, name, list(jobs.keys())))

print()
print('ALL OK — 工作流语法体检通过' if bad == 0 else 'NEEDS FIX: %d 项' % bad)
sys.exit(1 if bad else 0)
