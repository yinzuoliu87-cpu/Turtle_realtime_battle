# -*- coding: utf-8 -*-
"""提交前守卫: 工作区里有没有【看着像反向验证残留】的改动 (2026-08-28)。

★由来(一晚踩两次):
  做反向验证要"改坏产品代码 → 确认门禁会红 → 还原"。还原那步失手过两次:
  · `BEAR_RESIST 70→20` —— 当场用 `git diff` 抓到了
  · `CONCH_COST_MIN 4→3` —— **漏了, 几小时后由 5 条不相干的测试红出来**
    (2 个装备平衡测试 + 2 个文案金样本 —— 因为那个常量会通过占位符进玩家文案),
    我一度以为是自己改白名单碰坏的, 查了半天才发现是老残留。

★判据: 只看【单行常量数值被改】这种形状 —— 那正是反向验证最常用的手法,
  而正常开发很少只改一个 const 的数字却不动任何别的东西。
  报的是**疑点不是错误**: 真要改常量, 加 `--ack` 或在提交信息里说明即可。

★为什么不做成"工作区必须干净": 本仓库**不 push 是铁律**, 未提交状态常在且值钱
  (memory [[fb-never-git-checkout-to-cleanup]])。一刀切会天天误报然后被无视。

跑法: python tools/worktree_clean_check.py
"""
import io
import os
import re
import subprocess
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

## 只盯这些目录 —— 产品代码。tests/ 与 tools/ 的常量改动多半是正常开发。
WATCH = ('scripts/', 'autoload/', 'data/', 'server/')

## 形如 `const NAME := 数值` 或 `NAME = 数值` 的单行数值改动。
CONST_LINE = re.compile(r'^[+-]\s*(?:const\s+)?([A-Z][A-Z0-9_]{2,})\s*:?=\s*(-?[\d.]+)')


def main():
    try:
        r = subprocess.run(['git', 'diff', '-U0'], capture_output=True, text=True,
                           encoding='utf-8', errors='replace', timeout=120)
    except Exception as e:
        print('  [FAIL] 跑不了 git diff: %s' % e)
        return 1
    if r.returncode != 0:
        print('  [FAIL] git diff 失败')
        return 1

    cur = None
    pairs = {}          # (file, CONST) -> [旧值, 新值]
    n_files = 0
    for ln in (r.stdout or '').split(chr(10)):
        if ln.startswith('+++ b/'):
            cur = ln[6:]
            n_files += 1
            continue
        if cur is None or not cur.startswith(WATCH):
            continue
        m = CONST_LINE.match(ln)
        if not m:
            continue
        key = (cur, m.group(1))
        pairs.setdefault(key, [None, None])
        pairs[key][0 if ln[0] == '-' else 1] = m.group(2)

    ## 一改一(有旧有新)才算"数值被换掉" —— 纯新增常量不算。
    hits = [(f, k, v[0], v[1]) for (f, k), v in sorted(pairs.items())
            if v[0] is not None and v[1] is not None and v[0] != v[1]]

    print('  [分母] 扫了 %d 个改动文件 · 命中【单行常量数值被改】%d 处' % (n_files, len(hits)))
    if not hits:
        print('')
        print('ALL OK — 工作区没有像反向验证残留的改动')
        return 0

    ack = '--ack' in sys.argv
    for f, k, a, b in hits:
        print('  [%s] %s: %s  %s → %s' % ('注意' if ack else 'FAIL', f, k, a, b))
    print('')
    if ack:
        print('ALL OK — 已用 --ack 确认这些是有意的改动')
        return 0
    print('FAILED: %d 处常量数值被改 —— 确认是有意的就加 --ack 再跑' % len(hits))
    print('  (反向验证做完请务必还原; 只有一处是真改动时, --ack 一下即可)')
    return 1


if __name__ == '__main__':
    sys.exit(main())
