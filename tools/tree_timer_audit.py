# -*- coding: utf-8 -*-
"""树级计时器 + 闭包 = 活过场景释放的野捕获 (只读审计器)

★由来 (2026-08-21, 冒烟间歇红):
  `ERROR: Lambda capture at index 0 was freed. Passed "null" instead.`

  `get_tree().create_timer(...)` 造的是 **SceneTreeTimer** —— 它挂在场景树上,
  **本场景被释放了它照样会响**。如果给它接一个闭包, 而闭包捕获了本场景(或场景里的节点),
  响的时候引擎去绑那个已释放的捕获, 就报这条。

★两个反直觉的点 (踩过才知道):
  ① 报错发生在【绑定捕获】那一刻, **函数体根本没执行** ——
     所以写在闭包里的 `is_inside_tree()` / `is_instance_valid()` 一点用都没有。
  ② 闭包**捕获 Node 不安全, 捕获 RefCounted 安全** ——
     Node 被 free 就没了; RefCounted 被 Callable 引用着, 引用不掉到 0 就不会没。

★修法: 换成【挂在自己身上的 Timer 子节点】(`Timer.new()` + `add_child`) ——
  场景没了它跟着没, 根本不会响。或者干脆 `await`(那样至少不会有野捕获)。
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOTS = ['scripts', 'autoload']
PAT = re.compile(r'get_tree\(\)\.create_timer\([^)]*\)\.timeout\.connect\(')


def main():
    bad = []
    n_files = 0
    for root in ROOTS:
        for dp, _, fs in os.walk(root):
            for f in fs:
                if not f.endswith('.gd'):
                    continue
                p = os.path.join(dp, f).replace(os.sep, '/')
                n_files += 1
                for i, line in enumerate(io.open(p, encoding='utf-8').read().split('\n')):
                    if PAT.search(line):
                        bad.append((p, i + 1, line.strip()[:88]))
    print('[分母] 扫了 %d 个 .gd' % n_files)
    if n_files == 0:
        print('[FAIL] 一个文件都没扫到 —— 空检查不是通过')
        return 1
    if not bad:
        print('ALL OK — 没有「树级计时器接闭包」的野捕获')
        return 0
    print('[FAIL] %d 处把闭包接到了【会活过场景释放】的树级计时器上:' % len(bad))
    for p, ln, st in bad:
        print('   %s:%d  %s' % (p, ln, st))
    print('  修法: 换成挂在自己身上的 Timer 子节点(Timer.new() + add_child), 场景没了它跟着没。')
    return 1


if __name__ == '__main__':
    sys.exit(main())
