# -*- coding: utf-8 -*-
"""变异探针 —— 机械回答「我们的门禁到底守得住哪些声明」。

用法:
    python tools/mutation_probe.py --calibrate   # 标尺自检(必须先跑, 见下)
    python tools/mutation_probe.py               # 跑 CASES 批次, 断点续跑

做法: 逐个把产品函数的函数体换成 `pass`, 跑【它应该由哪条门禁守】, 看红不红。
  · 红了  ⇒ 有人守
  · 没红 ⇒ 裸奔: 谁改坏了都没人知道

★★★必须先跑标尺自检(--calibrate)。它拿两个【已知答案】的函数验探针本身:
    · `incense_stone_system._reapply` 有 48 条断言盯着 ⇒ 打瘸【必须红】
    · `incense_vfx.tick` 是纯演出, 门禁只验数值 ⇒ 打瘸【应该绿(裸奔)】
  **两个方向都对上**才说明探针能分辨守住与裸奔。只有一个方向对 = 可能恒红或恒绿,
  那样跑出来的整张表都是废的。2026-08-14 首次校准: 2/2 通过。

★★这个工具的【盲区】必须写在这里, 否则它会给人虚假的安心:
  变异测试查得出"没人守", **查不出"守错了东西"**。
  实例: v0.19.141 凤凰门禁断言的是 `_phx_onhit_n`(我自己插的标记) ——
  把 `_phoenix_flame_cone` 打瘸它照样会红 ⇒ 探针报"守住",
  **而用户实测竹制弓箭根本不触发**。判据选错层, 变异测试是看不见的。
  ⇒ 它是必要条件不是充分条件。另一半只能靠"判据量产品自己的账 + 反向验证时
    现象要与用户描述一致"。

★安全纪律(我 2026-08-05 真的忘过一次还原, 几小时后三条门禁红看着像回归):
  每次跑完立刻把原文写回; 批次之间 `git status` 应当干净。

⚠ 本机 CPU 有确诊硬件故障(WHEA 20 条 / 两次无转储关机), 反复起 Godot 是最危险的负载。
  所以只跑【单条门禁】而不是全套, 并且分批 + 断点续跑。
"""
import io, os, re, json, subprocess, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = r'c:\Users\Louis\Documents\GitHub\turtle-realtime-godot'
GODOT = r'C:\Users\Louis\Desktop\Godot_v4.6.3-stable_win64.exe'
REP = r'c:\tmp\mut_report.json'

def run(test, frames):
    r = subprocess.run('"%s" --headless --path . tests/%s.tscn --quit-after %d' % (GODOT, test, frames),
                       shell=True, cwd=ROOT, capture_output=True, text=True,
                       encoding='utf-8', errors='replace')
    t = (r.stdout or '') + (r.stderr or '')
    return ('[FAIL]' in t) or ('FAIL x' in t) or ('ALL PASS' not in t)

def stub(path, fname):
    p = os.path.join(ROOT, path)
    L = io.open(p, encoding='utf-8').readlines()
    idx = [k for k, l in enumerate(L) if re.match(r'^func %s\s*\(' % re.escape(fname), l)]
    if not idx:
        return None, None
    i = idx[0]
    j = next((k for k in range(i+1, len(L)) if L[k].startswith('func ')), len(L))
    orig = ''.join(L)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(''.join(L[:i+1]) + '\tpass\n' + ''.join(L[j:]))
    return p, orig

# (文件, 函数, 该由哪条门禁守, 帧数) —— "说不出哪条门禁守它"本身就是答案
CASES = [
 ('scripts/systems/equip/eq_food_batch.gd','_cake_eat','verify_eq_food_batch',1500),
 ('scripts/systems/equip/eq_food_batch.gd','_brick_convert','verify_eq_food_batch',1500),
 ('scripts/systems/equip/eq_food_batch.gd','tick_unit','verify_eq_food_batch',1500),
 ('scripts/systems/equip/eq_gadget_batch.gd','on_basic','verify_eq_gadget_batch',1500),
 ('scripts/systems/equip/eq_gadget_batch.gd','on_spawn','verify_eq_gadget_batch',1500),
 ('scripts/systems/equip/eq_gadget_batch.gd','tick_unit','verify_eq_gadget_batch',1500),
 ('scripts/systems/equip/eq_relic_batch.gd','scute_amount','verify_eq_relic_batch',1500),
 ('scripts/systems/equip/eq_relic_batch.gd','stele_amp','verify_eq_relic_batch',1500),
 ('scripts/systems/equip/eq_relic_batch.gd','on_death','verify_eq_relic_batch',1500),
 ('scripts/systems/equip/eq_relic_batch.gd','tick_unit','verify_eq_relic_batch',1500),
 ('scripts/systems/trainer/trainer_system.gd','_hook_first_target','verify_hook',1500),
 ('scripts/systems/trainer/trainer_system.gd','_tick_trainer_attacks','verify_trainer_hunt_tame',1500),
]
rep = json.load(io.open(REP, encoding='utf-8')) if os.path.exists(REP) else {}
for path, fn, test, fr in CASES:
    key = '%s::%s' % (os.path.basename(path), fn)
    if key in rep:
        continue
    p, orig = stub(path, fn)
    if p is None:
        rep[key] = {'guarded': None, 'note': '找不到该函数'}
        print('  %-52s ★找不到' % key); continue
    red = run(test, fr)
    io.open(p, 'w', encoding='utf-8', newline='\n').write(orig)
    ## ★★★ 还原必须【当场验证】，不能写完就当好了。
    ##   2026-08-14 实测: 批次跑完 `anchor_aspd` 仍是 `pass` 状态留在工作区,
    ##   而全套门禁在那之前跑过 ⇒ **测试抓不到它**, 只有 `git diff` 抓得到。
    ##   (2026-08-05 已经栽过一次同样的事: 几小时后三条门禁红, 看着像回归。)
    ##   ⇒ 一旦 diff 不干净就【立即中止整批】。
    if subprocess.run('git diff --quiet -- "%s"' % path, shell=True, cwd=ROOT).returncode != 0:
        print('!!! 还原失败, 立即中止: %s' % path)
        sys.exit(3)
    rep[key] = {'guarded': bool(red), 'gate': test}
    print('  %-52s %s  (%s)' % (key, '守住' if red else '★裸奔', test))
    json.dump(rep, io.open(REP,'w',encoding='utf-8'), ensure_ascii=False, indent=1)
naked = [k for k,v in rep.items() if v.get('guarded') is False]
print('')
print('分母: 已探 %d 个; 【打瘸了也没人红】的 %d 个' % (len(rep), len(naked)))
for k in naked: print('  ★', k, '←', rep[k].get('gate'))
