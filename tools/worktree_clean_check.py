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


## 把一个 hunk 里的 -/+ 配对, 找"新行是旧行前缀"的。
def _flush_trunc(cur, minus, plus, out):
    if cur is None or not cur.startswith(WATCH):
        return
    for a in minus:
        sa = a.strip()
        ## ★只看【代码行】。注释行天天在改, 把它们算进来就是满屏误报,
        ##   而满屏误报的门禁等于没有门禁(本文件头注里已经记过一次)。
        if len(sa) < 12 or sa.startswith('#'):
            continue
        for b in plus:
            sb = b.strip()
            if sb.startswith('#'):
                continue
            ## 新行严格短于旧行、且是它的前缀 ⇒ 尾巴被砍了
            if sb and sb != sa and sa.startswith(sb) and len(sa) - len(sb) >= 4:
                out.append((cur, a, b))
                break


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
    trunc = []          # 【被截短的表达式】: 新行是旧行的前缀
    hunk_minus = []
    hunk_plus = []
    n_files = 0
    for ln in (r.stdout or '').split(chr(10)):
        if ln.startswith('+++ b/'):
            cur = ln[6:]
            n_files += 1
            continue
        if cur is None or not cur.startswith(WATCH):
            continue
        ## ══ 第二只眼: 【表达式尾巴被砍掉】════════════════════
        ##
        ## ★★ 2026-08-29 又漏一次, 而且上面那只眼看不见:
        ##   反向验证把
        ##       u["_b84_lock_until"] = battle._t + CROSS_T3 + BladeEqVfx.SLASH_LIFE
        ##   改成了
        ##       u["_b84_lock_until"] = battle._t + CROSS_T3
        ##   还原失手后, 它**不是单行常量改数值**, 于是滑过去了 ——
        ##   直到全套门禁报三条红才发现。我那轮只跑了 `git diff --numstat`
        ##   看行数、没看内容。
        ##
        ## ★形状: 新行是旧行的**前缀**(末尾被砍掉一段)。
        ##   这正是"去掉一项看门禁会不会红"最常用的手法,
        ##   而正常开发很少只把一行的尾巴砍掉而完全不动别处。
        if ln.startswith('@@'):
            _flush_trunc(cur, hunk_minus, hunk_plus, trunc)
            hunk_minus = []
            hunk_plus = []
        elif ln.startswith('-') and not ln.startswith('---'):
            hunk_minus.append(ln[1:])
        elif ln.startswith('+') and not ln.startswith('+++'):
            hunk_plus.append(ln[1:])
        m = CONST_LINE.match(ln)
        if not m:
            continue
        key = (cur, m.group(1))
        pairs.setdefault(key, [None, None])
        pairs[key][0 if ln[0] == '-' else 1] = m.group(2)

    _flush_trunc(cur, hunk_minus, hunk_plus, trunc)

    ## 一改一(有旧有新)才算"数值被换掉" —— 纯新增常量不算。
    hits = [(f, k, v[0], v[1]) for (f, k), v in sorted(pairs.items())
            if v[0] is not None and v[1] is not None and v[0] != v[1]]

    print('  [分母] 扫了 %d 个改动文件 · 命中【单行常量数值被改】%d 处 · 【表达式尾巴被砍】%d 处'
          % (n_files, len(hits), len(trunc)))
    for f, a, b in trunc:
        print('  [FAIL] %s 有一行的**尾巴被砍掉**(像反向验证没还原):' % f)
        print('         旧: %s' % a.strip()[:100])
        print('         新: %s' % b.strip()[:100])
    if trunc and '--ack' not in sys.argv:
        print('')
        print('FAILED: %d 处表达式被砍短 —— 确认是有意的就加 --ack' % len(trunc))
        return 1
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
