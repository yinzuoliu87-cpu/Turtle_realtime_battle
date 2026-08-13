# -*- coding: utf-8 -*-
"""变异探针 —— 机械地回答「我们的门禁到底守得住哪些声明」。

★为什么要它(2026-08-13 用户:「前面方案书都不能说收尾, 很严重问题」):
  一天之内同一个形状出现四次 —— 门禁全绿, 但它证明的是**我的实现**而不是**用户的需求**:
    · v0.19.141 凤凰: 断言 `_phx_onhit_n`(我自己插的标记) ⇒ 竹制弓箭其实一次没触发
    · v0.19.144 凤凰: 我"修"出了 11 件装备双倍触发, 门禁照样绿
    · 法器主动门禁第一版: 判据被"双方在互相普攻"喂饱, 把主动改成 `pass` 照样全绿
    · 008 珊瑚刺: 我读了调用点的**过期注释**当事实
  ⇒ 「已完成」现在是**自己宣称**的, 不是**被证明**的。这个工具把它变成可测量的。

做法: 逐个把产品函数的函数体换成 `pass`, 跑门禁, 看有没有红。
  · 红了  ⇒ 这个函数**有人守**
  · 没红 ⇒ 它是**裸奔**的: 谁把它删了 / 改坏了都没人知道

★安全纪律(我 2026-08-05 真的忘过一次还原, 几小时后三条门禁红看着像回归):
  ① 每次变异前 `git diff --quiet` 必须干净, 否则**直接退出**(不在脏工作区上跑)
  ② 每次跑完立刻还原并**再验一次** `git diff --quiet`; 不干净就**中止全部**并大声报警
  ③ 只改一个文件的一个函数, 不做批量

用法:
  python tools/mutation_probe.py --list                    # 只列出候选函数, 不动代码
  python tools/mutation_probe.py --file scripts/... --n 20 # 跑前 20 个
  python tools/mutation_probe.py --resume                  # 接着上次的进度
结果累加进 tools/mutation_report.json(断点续跑, 这机器随时可能蓝屏)。
"""
import io
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPORT = os.path.join(ROOT, 'tools', 'mutation_report.json')
GODOT = os.environ.get('GODOT', r'C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe')

# 只探这些目录 —— 装备/技能/羁绊是"玩家能感知的效果"所在, 也是方案书声明的落点。
TARGET_DIRS = ['scripts/systems', 'scripts/scenes/battle']

# 不探的: 构造/析构/纯 getter/演出。它们被打瘸也不该让数值门禁红。
SKIP_RE = re.compile(r'^(_init|_ready|_process|_notification|_to_string)$')


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, cwd=ROOT, capture_output=True, text=True,
                          encoding='utf-8', errors='replace', **kw)


def clean_tree():
    return sh('git diff --quiet').returncode == 0


def funcs_of(path):
    """列出 (函数名, 起始行, 结束行) —— 结束行 = 下一个顶格 func 之前。"""
    lines = io.open(os.path.join(ROOT, path), encoding='utf-8', errors='replace').readlines()
    heads = []
    for i, ln in enumerate(lines):
        m = re.match(r'^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', ln)
        if m:
            heads.append((m.group(1), i))
    out = []
    for k, (name, i) in enumerate(heads):
        j = heads[k + 1][1] if k + 1 < len(heads) else len(lines)
        if SKIP_RE.match(name):
            continue
        if j - i < 4:                      # 太短的多半是转发/getter, 打瘸没意义
            continue
        out.append((name, i, j))
    return lines, out


def mutate(path, i, j, lines):
    """把 [i, j) 这个函数的**函数体**换成 pass, 保留签名(否则调用方编译就炸, 那不是"门禁抓到")。"""
    head = lines[i]
    body = ['\tpass\n']
    return lines[:i + 1] + body + lines[j:], head.strip()


def run_gates(only=None):
    """跑门禁。只跑自证测试(不跑冒烟), 判据与 run-tests.sh 一致: 要有 ALL PASS 且无 FAIL。"""
    r = sh('bash sweep.sh' if only is None else 'bash sweep.sh %s' % only)
    txt = (r.stdout or '') + (r.stderr or '')
    red = ('[FAIL]' in txt) or ('FAIL x' in txt) or (r.returncode != 0)
    return red, txt


def main():
    if not clean_tree():
        print('★工作区不干净 —— 拒绝在脏工作区上做变异(会把你未提交的改动搅进去)。')
        print('   先 git status 看一眼, commit 或 stash 之后再跑。')
        return 2

    rep = {}
    if os.path.exists(REPORT):
        rep = json.load(io.open(REPORT, encoding='utf-8'))

    only_file = None
    limit = 9999
    args = sys.argv[1:]
    if '--file' in args:
        only_file = args[args.index('--file') + 1]
    if '--n' in args:
        limit = int(args[args.index('--n') + 1])

    targets = []
    for d in TARGET_DIRS:
        for dp, _, fs in os.walk(os.path.join(ROOT, d)):
            for fn in fs:
                if not fn.endswith('.gd'):
                    continue
                rel = os.path.relpath(os.path.join(dp, fn), ROOT).replace('\\', '/')
                if only_file and rel != only_file:
                    continue
                targets.append(rel)
    targets.sort()

    if '--list' in args:
        tot = 0
        for p in targets:
            _, fs = funcs_of(p)
            tot += len(fs)
            print('%-58s %d 个函数' % (p, len(fs)))
        print('')
        print('合计 %d 个文件 / %d 个候选函数' % (len(targets), tot))
        print('已探过 %d 个' % len(rep))
        return 0

    n = 0
    for p in targets:
        lines, fs = funcs_of(p)
        for (name, i, j) in fs:
            key = '%s::%s' % (p, name)
            if key in rep:
                continue
            if n >= limit:
                break
            n += 1
            src = os.path.join(ROOT, p)
            orig = ''.join(lines)
            new, head = mutate(p, i, j, lines)
            io.open(src, 'w', encoding='utf-8', newline='\n').write(''.join(new))
            red, _txt = run_gates()
            io.open(src, 'w', encoding='utf-8', newline='\n').write(orig)
            if not clean_tree():
                print('!!! 还原失败, 立即中止 —— 手动 git diff 检查 %s' % p)
                return 3
            rep[key] = {'guarded': bool(red), 'sig': head}
            print('%-4s %s' % ('守住' if red else '★裸奔', key))
            json.dump(rep, io.open(REPORT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

    naked = [k for k, v in rep.items() if not v['guarded']]
    print('')
    print('分母: 已探 %d 个函数; 其中【打瘸了也没人红】的 %d 个' % (len(rep), len(naked)))
    for k in naked[:40]:
        print('  ★', k)
    return 0


if __name__ == '__main__':
    sys.exit(main())
