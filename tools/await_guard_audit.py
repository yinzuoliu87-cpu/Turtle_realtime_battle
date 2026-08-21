# -*- coding: utf-8 -*-
"""await 之后必须重新确认 battle 还活着 (只读审计器)

★由来 (2026-08-20, smoke_scenes 间歇红 1/3):
  `SCRIPT ERROR: Invalid call. Nonexistent function 'get_process_delta_time' in base 'previously freed'.`
  投射物协程里 `while ...: await battle.get_tree().process_frame` —— 战斗结束、场景被
  queue_free 之后, 这个协程还会被唤醒一次, 然后拿 **已释放的 battle** 继续用。

★两个反直觉的点 (踩过才知道):
  ① `is_instance_valid(self)` 挡不住 —— self 是 RefCounted 的装备/技能系统, 它活得好好的,
     死的是 battle 那个 Node。挡不住却看着像挡住了。
  ② `battle.is_inside_tree()` 当守卫更糟 —— **守卫本身就是一次对已释放实例的调用**,
     它会先炸。所以 `is_instance_valid(battle)` 必须排在 `and` 链的**第一位**(短路)。

★判据: 任何【循环体里出现 `await battle.` 】的 while/for, 它的循环头必须含
  `is_instance_valid(battle)`。外层循环用**缩进**判定 —— 按"往回数 N 行"找会误报
  (我第一版就把 battle_vfx.gd 一个不相干的 for 抓了进来)。
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOTS = ['scripts', 'autoload']
NEEDLE = 'await battle.'
GUARD = 'is_instance_valid(battle)'
BASELINE = 0            # 只降不升


def indent_of(s):
    return len(s) - len(s.lstrip())


def scan():
    bad = []
    n_await = 0
    n_loop = 0
    for root in ROOTS:
        for dp, _, fs in os.walk(root):
            for f in fs:
                if not f.endswith('.gd'):
                    continue
                p = os.path.join(dp, f).replace(os.sep, '/')
                L = io.open(p, encoding='utf-8').read().split('\n')
                for i, line in enumerate(L):
                    if NEEDLE not in line:
                        continue
                    n_await += 1
                    my = indent_of(line)
                    ## ★★2026-08-21 扩大判据: 原来只查【循环里】的 await。
                    ##   实测冒烟 5 次红 2 次, 两条错都在同一处(第 3 次硬释放之后):
                    ##     · Lambda capture at index 0 was freed
                    ##     · Condition "!is_inside_tree()" is true (get_global_transform)
                    ##   后一条来自 `battle._cam.global_transform` —— **在循环外面**。
                    ##   ⇒ 危险的不是"循环", 是"await 之后还继续用 battle"。判据按这个来。
                    nxt = ""
                    has_more = False
                    for k in range(i + 1, len(L)):
                        t = L[k]
                        if not t.strip():
                            continue
                        ind = indent_of(t)
                        if ind < my:
                            break                    # 出了这个块, 后面不是同一段
                        if t.strip().startswith("#"):
                            continue
                        nxt = t
                        has_more = True
                        break
                    if not has_more:
                        continue                     # await 是这段的最后一句, 回来什么都不做
                    n_loop += 1                      # 分母: 需要守卫的 await 点
                    if GUARD not in nxt:
                        bad.append((p, i + 1, line.strip()[:90]))
    return n_await, n_loop, bad


def main():
    n_await, n_loop, bad = scan()
    print('[分母] `await battle.` 共 %d 处 · 其中【回来还要继续用 battle】的 %d 处' % (n_await, n_loop))
    if n_loop == 0:
        print('[FAIL] 一个需要守卫的 await 都没扫到 —— 这是空检查, 不是通过')
        return 1
    if not bad:
        print('ALL OK — 每个 await battle 的循环都先确认 battle 还活着')
        return 0
    print('[FAIL] %d 处在 await 后继续用 battle, 却没先确认它还活着:' % len(bad))
    for p, ln, st in bad:
        print('   %s:%d  %s' % (p, ln, st))
    print('  修法: 在 `await battle....` 的【下一行】加 `if not is_instance_valid(battle): return`')
    print('        ★写在循环头上不算 —— 循环头在 await 之前求值, 挡不住 await 期间的释放。')
    return 1


if __name__ == '__main__':
    sys.exit(main())
