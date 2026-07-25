# -*- coding: utf-8 -*-
"""style_lint —— 代码风格门禁(强制 CLAUDE.md §5 约定)。

§5 说"实测已高度统一(80/80 文件全 tab·1375 函数零例外 snake_case)"—— 但"实测统一"只是
【此刻】的事实, 没有门禁就会漂移。本工具把这些【当前 100% 成立的不变量】焊死成门禁:
一旦有人提交违反(空格缩进 / 驼峰函数名 / 非 PascalCase 的 class_name)就红。

这是最便宜的规范化: 零改动、零欠债, 只是把"碰巧一致"变成"强制一致·永不回退"。
进 run-tests.sh 门禁(成功打印 ALL OK)。
"""
import io, sys, os, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

ROOTS = ['scripts', 'autoload', 'tests']
fail = [0]
def bad(msg):
    fail[0] += 1
    print('  [FAIL] ' + msg)

files = []
for base in ROOTS:
    if not os.path.isdir(base):
        continue
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.endswith('.gd'):
                files.append(os.path.join(dp, f).replace(os.sep, '/'))
files.sort()

print('=== 代码风格 (§5: 全 tab 缩进 · 函数 snake_case · class_name PascalCase) ===')
print('  扫描 %d 个 .gd' % len(files))

# 1) 缩进必须 tab: 代码行不许以空格开头(注释对齐行豁免)
sp = []
for p in files:
    for i, l in enumerate(io.open(p, encoding='utf-8'), 1):
        if l[:1] == ' ' and l.strip() != '' and not l.lstrip().startswith('#'):
            sp.append('%s:%d' % (p, i))
if sp:
    bad('%d 行用空格缩进(§5 全 tab): %s' % (len(sp), sp[:8]))

# 2) 函数名 snake_case(允许前导下划线)
for p in files:
    for i, l in enumerate(io.open(p, encoding='utf-8'), 1):
        m = re.match(r'\s*func\s+([A-Za-z0-9_]+)', l)
        if m and not re.match(r'^_?[a-z][a-z0-9_]*$', m.group(1)):
            bad('非 snake_case 函数名 %s:%d → %s' % (p, i, m.group(1)))

# 3) class_name PascalCase
for p in files:
    for i, l in enumerate(io.open(p, encoding='utf-8'), 1):
        m = re.match(r'\s*class_name\s+([A-Za-z0-9_]+)', l)
        if m and not re.match(r'^[A-Z][A-Za-z0-9]*$', m.group(1)):
            bad('非 PascalCase class_name %s:%d → %s' % (p, i, m.group(1)))

if fail[0] == 0:
    print('ALL OK — 代码风格达标(缩进/命名不变量已焊死)')
    sys.exit(0)
else:
    print('FAILED: %d 处风格违规' % fail[0])
    sys.exit(1)
