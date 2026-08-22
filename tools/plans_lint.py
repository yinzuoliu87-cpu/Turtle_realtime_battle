# -*- coding: utf-8 -*-
import sys
## ★Windows 控制台默认 GBK, 打印 emoji/生僻字会**直接抛 UnicodeEncodeError**,
##   于是门禁不是"报出问题"而是**崩在打印那一行** —— 我 2026-08-22 往方案书状态里写了个 🟢
##   就把这条门禁弄崩了, 而崩溃的报错和"真有问题"长得完全不一样, 极易误判。
##   同仓库其它审计器(await_guard_audit 等)早就这么处理了, 这份漏了。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
"""方案书生命周期门禁 —— 每个需求都要走完「方案 → 执行 → 测试 → 验收 → 标记完成」。

用户 2026-08-13:「我们现在这个项目需要正式化, 那每个需求都有产生方案, 执行, 测试和验收,
标记已完成整个的流程」。

★为什么要焊成门禁而不是写进规范文档: 实测 44 份方案书里, **只有 2 份**有状态行、
  **只有 5 份**有实施回填 —— 制度写在 README 里没人执行, 和没有制度是一样的。
  同一手法在 `docs_authority_lint.py`(单一事实源纪律)上已经用过一次。

规则(只管【新写的】方案书, 见 SINCE):
  ① 抬头必须有一行 `状态：<允许值之一>`
  ② 状态是「已完成」的, 必须有【实施回填】一节, 且不能只剩占位符
  ③ 七节骨架(需求原文/调查/出入/方案/风险/验收/决策)缺一节就红 —— 格式见 plans/README.md
★为什么设 SINCE: 44 份历史方案书是在这条制度之前写的, 一次性补全既不现实也没价值
  (它们的价值在当时的决策记录, 不在格式)。新账不欠、旧账不追。
"""
import io
import os
import re
import sys

PLANS = 'docs/plans'
SINCE = '20260812'          # 这一天起的新方案书按新制度验(用户定制度的日子)
STATUS_OK = ['草稿', '已拍板', '实施中', '已完成', '已作废']
SECTIONS = ['需求原文', '调查', '出入', '方案', '已知风险', '验收', '决策记录']

fails = []
checked = 0


def check(path, name):
    global checked
    s = io.open(path, encoding='utf-8').read()
    checked += 1
    m = re.search(r'状态[:：]\s*\**([^\*\n（(]+)', s)
    if not m:
        fails.append('%s: 抬头缺【状态：】行(允许值 %s)' % (name, '/'.join(STATUS_OK)))
        return
    st = m.group(1).strip()
    if st not in STATUS_OK:
        fails.append('%s: 状态「%s」不在允许值里 %s' % (name, st, '/'.join(STATUS_OK)))
    miss = [k for k in SECTIONS if k not in s]
    if miss:
        fails.append('%s: 缺骨架小节 %s' % (name, miss))
    if st == '已完成':
        if '实施回填' not in s:
            fails.append('%s: 标了【已完成】却没有「实施回填」一节' % name)
        elif re.search(r'实施回填[^\n]*\n+\s*（(?:逐条)?补', s):
            fails.append('%s: 「实施回填」还是占位符, 没有真内容' % name)


def main():
    if not os.path.isdir(PLANS):
        print('缺 %s' % PLANS)
        return 1
    files = sorted(f for f in os.listdir(PLANS) if f.endswith('.md') and f != 'README.md')
    new = [f for f in files if f[:8].isdigit() and f[:8] >= SINCE]
    print('方案书 %d 份; 按新制度验的(%s 起) %d 份' % (len(files), SINCE, len(new)))
    for f in new:
        check(os.path.join(PLANS, f), f)
    print('  [分母] 实际检查 %d 份' % checked)
    if checked == 0:
        print('  [ OK ] 暂无新制度下的方案书')
        return 0
    for x in fails:
        print('  [FAIL] ' + x)
    if fails:
        print('')
        print('FAILED: %d 处' % len(fails))
        return 1
    print('')
    print('ALL OK — 方案书生命周期完整(状态/骨架/回填)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
