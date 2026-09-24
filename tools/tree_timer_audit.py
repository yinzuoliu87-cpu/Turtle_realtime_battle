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

⚠⚠ 本审计器**只守树级计时器这一条路**。同一条报错还有**另一个更大的来源没被守**:
    `tween_callback(func(): ... )` 里捕获了节点 —— tween 还在, 而被捕获的节点先被
    `queue_free` 掉了, 引擎绑捕获时照样喷这条。

    2026-09-24 数过: 全仓 `tween_callback(func` 共 85 处, 其中 **57 处**闭包体里写着
    `is_instance_valid(x)` 兜底 —— 那句话本身就是「我知道这个节点可能先没」的自白,
    而且**它挡不住报错**(报错在绑定捕获那一刻, 函数体根本没执行; 它只挡住了崩溃)。

    同一天 CI 上 `verify_equip_batch_20260801` 冒了 2 条这个报错, 本地
    满速 3 次 / `--max-fps 15` 3 次 / 8 路并发 16 次, 共 22 次**一次都没复现**,
    因此**没有动那 57 处** —— 复现不出来就大改 57 处, 是拿规模赌运气。
    已先做两件能确定的事: ①补上「拆成两行」的形状(当场抓出 RealtimeBattle3DScene:948)
    ②让 CI 失败时把 `.gate-fail-<测试名>.log` 一起推到 ci-logs 分支
    (原来注解里那句「完整日志已留在…」指的文件从没上来过) ⇒ **下次再红就能定位到具体是哪一个**。

    要守这一类的话, 正确的修法不是加判空, 是**让闭包根本不捕获节点**:
    捕获 `n.get_instance_id()`(一个 int, 永远不会"被 freed"), 回调里再
    `instance_from_id(...)` 取回来。
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

ROOTS = ['scripts', 'autoload']
PAT = re.compile(r'get_tree\(\)\.create_timer\([^)]*\)\.timeout\.connect\(')
## ★★2026-09-24 补的缺口: 上面那条只认**一行写完**的形状。拆成两行照样是野捕获，
##   而它一直看不见 —— `RealtimeBattle3DScene.gd:947` 就是这么躲过去的：
##       var _t2 := get_tree().create_timer(1.6)
##       _t2.timeout.connect(func() -> void: ...)
##   ⇒ 先找「把树级计时器存进变量」的行，再往后看几行有没有 `<那个变量>.timeout.connect(`。
##   `await get_tree().create_timer(x).timeout` 不会被误报 —— 它压根没有 `.connect(`。
VAR_PAT = re.compile(r'(?:var\s+)?(\w+)\s*:?=\s*[\w.]*get_tree\(\)\.create_timer\(')
LOOKAHEAD = 8   # 存进变量 → 拿它接闭包，中间隔几行还算同一处


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
                lines = io.open(p, encoding='utf-8').read().split('\n')
                for i, line in enumerate(lines):
                    if PAT.search(line):
                        bad.append((p, i + 1, line.strip()[:88]))
                        continue
                    m = VAR_PAT.search(line)
                    if m is None:
                        continue
                    ## 存进了变量 ⇒ 往后看几行，有没有拿它接闭包
                    hook = re.compile(r'\b' + re.escape(m.group(1)) + r'\.timeout\.connect\(')
                    for k in range(i + 1, min(i + 1 + LOOKAHEAD, len(lines))):
                        if hook.search(lines[k]):
                            bad.append((p, k + 1, '(拆成两行) ' + line.strip()[:38]
                                        + ' … ' + lines[k].strip()[:42]))
                            break
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
