# -*- coding: utf-8 -*-
"""rng_discipline —— 随机源纪律门禁(保护确定性工作不被悄悄回退)。

Phase1 花了大力气把战斗 sim 的随机全路由到单一受控源 `_battle_rng`(种子化→可复现),
这是 verify_battle_determinism 得以成立的根。但只要有人后面手一滑写一个【裸的全局 randf()/randi()】
到 sim 路径里, 确定性就【悄悄】破了——而它未必被 2 单位确定性测试的场景触发(那测试打近战、不游走),
于是门禁绿着、determinism 却已经漏。这正是"不强制就回退"。

规范: **不许裸全局 RNG。视觉抖动走 `_juice_rng`, 战斗 sim 走 `_battle_rng`(种子化)。**
本工具把当前裸调用数【冻结】成棘轮(只减不增):
  · 新增裸 randf/randi/... → 红。逼你用命名 rng(改一个字: `randf(`→`_juice_rng.randf(`)。
  · 把存量路由掉、数字变小 → 改 rng_budget.json 里的值(改小才过)= 还债账。

存量 336 处多为视觉抖动(idle bob 相位 / 飘字偏移 / 粒子位置), 冻结不动无害;
真正的价值是【挡住新的 sim 裸随机】。进 run-tests.sh 门禁(成功打印 ALL OK)。
"""
import io, sys, os, re, json
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

CFG = json.load(io.open('tools/rng_budget.json', encoding='utf-8'))
CAP = int(CFG['max_bare_rng'])
ROOTS = CFG.get('scan_roots', ['scripts', 'autoload'])

# 裸全局 RNG = randf(|randi(|randf_range(|randi_range(|randfn( 前面【没有】'.' 或标识符字符
# (命名接收者 `_battle_rng.randf()` 的 'randf' 前面是 '.', 被这条负向前瞻排除)
BARE = re.compile(r'(?<![\.\w])(randf|randi|randf_range|randi_range|randfn)\s*\(')
## ★★2026-10-02 补: 上面那条正则有个**整类盲区** —— 它只认"裸函数名", 而
##   `Array.shuffle()` / `Array.pick_random()` 是**方法调用**, 前面必然带个点,
##   正好被 `(?<![\.\w])` 这个 lookbehind 排除掉。
##   实测代价: `shell_system.gd:335` 的 `pool.shuffle()` 决定龟壳从 76 个可抄技能里
##   抄哪两个 = **直接改结果**, 而它走的是**引擎全局 RNG**。三道防线全看不见它
##   (本工具的正则不认 / tween 台账无关 / `shell` 在任何确定性门禁里都不在场)。
## ⇒ 这两个单列一条, 因为它们【没有受控版本】: `RandomNumberGenerator` 没有 shuffle,
##   要确定性就得自己写 Fisher-Yates 并喂 `_battle_rng`(shell_system 现在就是这么做的)。
ENGINE_RNG_METHOD = re.compile(r'\.(shuffle|pick_random)\s*\(')

files = []
for base in ROOTS:
    if not os.path.isdir(base):
        continue
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.endswith('.gd'):
                files.append(os.path.join(dp, f).replace(os.sep, '/'))
files.sort()

per_file = {}
total = 0
for p in files:
    c = 0
    for l in io.open(p, encoding='utf-8'):
        code = l.split('#', 1)[0]   # 注释里的不算
        c += len(BARE.findall(code))
    if c:
        per_file[p] = c; total += c

## ★引擎 RNG 的【方法形态】—— 硬零, 不进上面那个棘轮。
##   理由: 它们没有受控版本(RandomNumberGenerator 没有 shuffle/pick_random),
##   所以"还几处"这种渐进口径不适用 —— 出现一处就是一处确定性漏洞。
em = []
for p in files:
    for i, l in enumerate(io.open(p, encoding='utf-8'), 1):
        code = l.split('#', 1)[0]
        if ENGINE_RNG_METHOD.search(code):
            em.append('%s:%d  %s' % (p, i, code.strip()[:72]))

print('=== 随机源纪律 (裸全局 randf/randi 冻结 ≤%d · 只减不增) ===' % CAP)
print('  裸调用现 %d 处 (上限 %d)' % (total, CAP))
for p in sorted(per_file, key=lambda k: -per_file[k]):
    print('  %5d  %s' % (per_file[p], p))

print('  [分母] 扫 %d 个战斗链路 .gd 找 .shuffle(/.pick_random( —— 命中 %d 处' % (len(files), len(em)))
if em:
    for x in em:
        print('  [FAIL] 引擎 RNG 方法: ' + x)
    print('         (它们走【引擎全局 RNG】, 改结果就是确定性漏洞。')
    print('          没有受控版本 ⇒ 自己写 Fisher-Yates 喂 `_battle_rng`, 见 shell_system.gd)')
    print('FAILED: 引擎 RNG 方法 %d 处' % len(em))
    sys.exit(1)

if total > CAP:
    print('  [FAIL] 裸全局 RNG 增加了 (%d > %d)。新随机请走命名源: 视觉→_juice_rng.  sim→_battle_rng(种子化)。' % (total, CAP))
    print('FAILED: 随机源纪律回退')
    sys.exit(1)
if total < CAP:
    print('  ✅ 已还 %d 处(请把 rng_budget.json 的 %d 改到 %d)' % (CAP - total, CAP, total))
print('ALL OK — 随机源纪律达标(无新增裸随机·确定性受保护)')
sys.exit(0)
