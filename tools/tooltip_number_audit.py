# -*- coding: utf-8 -*-
"""装备文案数值 ↔ 代码 交叉核查(只读)。2026-07-19 建。

【查什么】effectDesc1 里的 a/b/c 三元组(=1★/2★/3★) 能否在代码里找到对应的三元数组字面量。
【怎么比】解析成 float 再比 —— 不是字符串比。否则 0.50 匹配不上 50%、0.10 匹配不上 10%。
          同时试 原值 / ÷100(文案写百分数·代码存小数) / ×100 三种口径。
【就近约束】光"全代码里存在这个数组"太松(可能是别件装备的巧合)。所以还要求命中位置落在
          该装备 id 字面量附近 ±2500 字符内; 落不进去的单列为【远处命中】人工复核。
          实现写在具名函数里(函数体不含 id 字符串)的会自然落到这一档 —— 已核实的进白名单。

★这【不是】龟的检查: 龟没有星级 → detail 里根本没有三元组 → 拿这套查龟会得到
  "0 个三元组、0 条不符"的【空结论】。龟的文案核对是人工逐条做的, 见
  docs/design/文案核对清单-20260719.md; 龟这边可自动查的是 energyCost(见 verify_codex_text.gd)。
"""
import io, sys, json, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# 已人工核实过的【远处命中】: 实现在具名函数里, 函数体不含 id 字面量。
# 格式 (id, 三元组) -> 核实结论(哪个函数)。新增项必须先人工看代码再往这里加。
VERIFIED_FAR = {
    # ★信号放大器038 效果重做(用户 2026-07-30, A 方案): 数值全在
    #   scripts/systems/equip/signal_wave_system.gd 的常量区(单独成文件 —— 上帝文件卡在
    #   arch_budget 8600), 离 "p2eq_038" 锚点远但【人工核过】。
    ('p2eq_038', '1/2/5'):       'AMP_PER_STACK 每层增伤 [0.01,0.02,0.05]',
    ('p2eq_038', '125/250/500'): 'WAVE_DMG 弧形波魔法伤害 [125,250,500]',
    ('p2eq_038', '5/7/10'):      'MR_PEN 每次释放的魔抗穿透 [5,7,10]',
    # ★复活海螺033 小虫带装(用户 2026-07-30): 星级数组 [1,2,3] 在 _conch_grant_equips 里,
    #   离 "p2eq_033" 锚点较远但【人工核过】—— 小虫带的 3 件装备按携带者星级取 1/2/3 星。
    ('p2eq_033', '1/2/3'): '_conch_grant_equips 小虫带装星级 [1,2,3]',
    # ★荆棘海胆015 效果重做(用户 2026-07-30): 三个数组在 equip_system.gd 常量区,
    #   离 "p2eq_015" 锚点较远但【人工核过】—— 累计阈值→护盾→强化下一击流血。
    ('p2eq_015', '300/270/230'): 'THORN_THRESHOLD 反伤累计阈值 [300,270,230]',
    ('p2eq_015', '50/70/200'):   'THORN_SHIELD 触发时给自己的护盾 [50,70,200]',
    ('p2eq_015', '30/50/90'):    'THORN_BLEED 强化那一击的流血层数 [30,50,90]',
    ('p2eq_032', '3/5/8'):      '_eq_summon_skeleton 骷髅攻击 [3,5,8]',
    ('p2eq_032', '8/13/20'):    'sk["boom_pct_true"]=[0.08,0.13,0.20] 死亡爆炸%最大生命真伤',
    ('p2eq_058', '500/1000/1800'): '_eq_summon_turret 炮台生命(不乘HP_MULT·文案也没写×成长)',
    ('p2eq_058', '20/30/45'):   '_eq_summon_turret 炮台攻击',
    ('p2eq_058', '70/85/100'):  '_tick_eq_turret 携带者存活时炮台双抗',
    ('p2eq_058', '2/2/3'):      '_turret_on_shot 每次普攻永久+护穿',
    ('p2eq_058', '20/30/40'):   '_tick_eq_turret 携带者400码内攻速加成',
    # ── 2026-07-23 拆回合制 P2RT 后新增(逐条核实数值在实时对应装备的效果函数里·见工具 verify_far) ──
    ('p2eq_007', '0.5/0.8/1.1'): '_eq_broadsword 锈蚀阔剑 [0.5,0.8,1.1]',
    ('p2eq_007', '20/35/60'):    '_eq_broadsword 锈蚀阔剑 [20,35,60]',
    ('p2eq_007', '50/75/100'):   '_eq_broadsword 锈蚀阔剑 [0.5,0.75,1.0]×100',
    ('p2eq_008', '8/12/18'):     '_step_projectiles 珊瑚刺%maxHP [0.08,0.12,0.18]',
    ('p2eq_008', '1/1.2/1.5'):   '_step_projectiles 珊瑚刺 [1.0,1.2,1.5]',
    ('p2eq_009', '0.5/0.7/0.9'): '_eq_wide_blade 宽刃弯刀 [0.5,0.7,0.9]',
    ('p2eq_009', '2/2.5/3'):     '_eq_wide_blade 宽刃弯刀 [2.0,2.5,3.0]',
    ('p2eq_009', '30/45/60'):    '_eq_wide_blade 宽刃弯刀 [30,45,60]',
    ('p2eq_022', '40/60/100'):   '_fuel_bottle_hit 余烬燃油瓶 [40,60,100]',
    ('p2eq_022', '10/15/20'):    '_fuel_bottle_hit 余烬燃油瓶 [0.10,0.15,0.20]',
    ('p2eq_022', '20/35/60'):    '_fuel_bottle_hit 余烬燃油瓶 [20,35,60]',
    # 龙蛋削弱二(用户 2026-07-29): 伤害与治疗合并成同一组 [45,80,120]、系数拍平成 1×ATK(不再是三元组)、
    # 灼烧 [30,45,70]→[20,35,50]。旧的四条白名单已删(留着会被 [STALE] 标出来)。
    ('p2eq_024', '45/80/120'):   '_dragon_hit_enemy 魔法伤 / _dragon_heal_ally 回血, 同为 [45,80,120] + 1×ATK',
    ('p2eq_024', '20/35/50'):    '_dragon_hit_enemy 龙蛋灼烧层(固定层数) [20,35,50]',
    ('p2eq_043', '60/110/200'):  '_eq_water_wave 海浪护符 [60,110,200]',
    ('p2eq_043', '2/3/5'):       '_eq_water_wave 海浪护符 [2,3,5]',
    ('p2eq_043', '40/95/120'):   '_eq_water_wave 海浪护符 [40,95,120]',
    ('p2eq_057', '2/3/7'):       '_eq_sniper 狙击长管 [2,3,7]',
    # ── 2026-07-25 装备效果抽到 equip/equip_system.gd(装备与技能分开)后, id 分派与效果数组分居两文件
    #    (或效果在留守主场景的 _ice_throw_go/_fuel_bottle_hit/_tick_laser 里)→ 字符距离超 WIN=远处命中。
    #    纯搬迁·数值一个没改(移动前均在册通过)·逐条核对数组仍在对应装备的效果码里。 ──
    ('p2eq_006', '0.8/1.3/4.0'):  '_eq_sword_storm 千刃风暴(reorg远)',
    ('p2eq_006', '70/100/400'):   '_eq_sword_storm 千刃风暴(reorg远)',
    ('p2eq_010', '35/80/100'):    '激光长刃 _tick_laser/_eq_laser_* (reorg远)',
    ('p2eq_010', '0.6/1.0/8.0'):  '_eq_laser_chop/sweep 激光 [0.6,1.0,8.0](equip_system:968)',
    ('p2eq_010', '15/32/200'):    '_eq_laser_chop/sweep 激光 [15,32,200](equip_system:968)',
    ('p2eq_028', '40/60/100'):    '_ice_throw_go 冰霜冻露瓶 [40,60,100](留守主场景·reorg远)',
    ('p2eq_029', '100/160/250'):  '冰封水母 p2eq_029 case(reorg远)',
    ('p2eq_030', '30/35/40'):     '迷你水晶球A p2eq_030(reorg远)',
    ('p2eq_029', '1/1.8/2.5'):    '冰封水母 p2eq_029 冰效果[1.0,1.8,2.5](随_ice_搬到ice_system·reorg远·数值未改)',
    ('p2eq_029', '25/40/60'):     '冰封水母 p2eq_029 冰效果[25,40,60](随_ice_搬到ice_system·reorg远·数值未改)',
    # ── 2026-08-01 装备批次13条(用户): 逐条核实数值在对应效果码里 ──
    ('p2eq_031', '60/130/250'):  '_crystal_sweep_step 迷你水晶球B 伤害 [60,130,250](crystal_system.gd·reorg远)',
    ('p2eq_032', '16/31/55'):    '_eq_summon_skeleton 骷髅最大生命 [16.0,31.0,55.0](equip_system.gd·id 在 stats_apply 侧→远)',
    ('p2eq_032', '13/17/23'):    '_eq_summon_skeleton 骷髅存活时长 [13.0,17.0,23.0]',
    ('p2eq_055', '1/1/2'):       'HookBombSystem.BOMB_COUNT [1,1,2] 挂弹敌人数(独立文件→远)',
    ('p2eq_055', '1/2/2'):       'HookBombSystem.BOMB_DPS_PCT [0.01,0.02,0.02] 每秒%maxHp',
    ('p2eq_055', '200/400/500'): 'HookBombSystem.BLAST_FLAT [200.0,400.0,500.0] 聚爆固定段',
}
WIN = 2500

eq = json.load(io.open('data/phase2-equipment.json', encoding='utf-8'))
eq = eq if isinstance(eq, list) else eq.get('equipment', eq.get('items'))
code = io.open('scripts/scenes/RealtimeBattle3DScene.gd', encoding='utf-8').read() \
     + '\n@@@\n' + io.open('scripts/gamedata/equip_stats.gd', encoding='utf-8').read()
# 2026-07-25: 主战斗文件拆分后, 效果数组可能搬到 scripts/systems/*.gd(如沙漏 5/10/30 → timestop_system.gd)。
#   把 systems/ 全体一并纳入对账源, 否则拆一个效果出去就误报"代码里找不到对应数组"。
import glob as _glob
for _sysf in sorted(_glob.glob('scripts/systems/**/*.gd', recursive=True)):
    code += '\n@@@\n' + io.open(_sysf, encoding='utf-8').read()
# 2026-07-26: 核心引擎拆分把弹道/伤害等抽到 scripts/scenes/battle_*.gd(如珊瑚刺 8/12/18 → battle_ballistics.gd)。
#   这些也含装备【效果】数值 → 一并纳入对账源, 否则拆一刀就误报"代码里找不到"(刀6 CI 门禁曾因此红)。
for _bf in sorted(_glob.glob('scripts/scenes/battle/*.gd')):
    code += '\n@@@\n' + io.open(_bf, encoding='utf-8').read()
# 2026-07-23: 装备【效果】数值只在 RealtimeBattle3DScene(实时实装)对账; equip_stats 只有属性STATS(无[N,N,N]效果三元组)。
# 原来还读回合制 phase2_equip_runtime.gd 的效果数组 —— 那是死代码, 让文案能匹配到游戏不用的旧数值(分歧源), 已去掉。

NUM = r'-?\d+(?:\.\d+)?'
ARRS = [(m.start(), tuple(float(g) for g in m.groups()))
        for m in re.finditer(r'\[\s*(%s)\s*,\s*(%s)\s*,\s*(%s)\s*\]' % (NUM, NUM, NUM), code)]

# ── id → 效果函数 锚点 (2026-07-23 拆掉回合制 P2RT 后新增) ──
# 回合制 P2RT 把 "p2eq_NNN" 和它的效果数组写在一起(近), 实时版则是: id 在 match 分派表里、
# 数值在几十行外的 _eq_<名> 函数体内(远)。只锚 id 字符串会把这些逐星数组误判成"远处命中"。
# 于是把每件装备【分派到的效果函数定义处】也当作它的锚点 → 数值就落在 WIN 内。
_ID2FN = {}
# 2026-07-25: 装备效果抽到 EquipSystem 后, 分派可能写成 "p2eq_NNN": _equip_sys._eq_xxx( →
#   跳过 <名>_sys. 前缀, 锚到真正的效果函数名(否则锚到 _equip_sys → 数值当"远处命中"误报)。
for _m in re.finditer(r'"(p2eq_\d+)"\s*:\s*(?:_\w+_sys\.)?(_\w+)\s*\(', code):
    _ID2FN.setdefault(_m.group(1), set()).add(_m.group(2))
_FNDEF = {}
for _m in re.finditer(r'\bfunc\s+(_\w+)\s*\(', code):
    _FNDEF[_m.group(1)] = _m.start()

def close(a, b):
    return abs(a - b) <= max(1e-6, abs(b) * 1e-6)

none, far, stale = [], [], []
total = 0
for e in eq:
    eid = e['id']
    anchors = [m.start() for m in re.finditer(re.escape('"%s"' % eid), code)]
    for _fn in _ID2FN.get(eid, ()):        # 该装备分派到的效果函数定义处也算锚点
        if _fn in _FNDEF:
            anchors.append(_FNDEF[_fn])
    trips = set(re.findall(r'(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)/(\d+(?:\.\d+)?)', str(e.get('effectDesc1', ''))))
    for t in trips:
        total += 1
        key = (eid, '/'.join(t))
        vals = [float(x) for x in t]
        hit_glob = hit_near = False
        for k in (1.0, 0.01, 100.0):
            sc = [v * k for v in vals]
            for pos, ct in ARRS:
                if all(close(s, c) for s, c in zip(sc, ct)):
                    hit_glob = True
                    if any(abs(pos - a) <= WIN for a in anchors):
                        hit_near = True
        row = (eid, str(e.get('name', ''))[:11], '/'.join(t))
        if not hit_glob:
            none.append(row)
        elif not hit_near and key not in VERIFIED_FAR:
            far.append(row)
    # 白名单里指向本装备、但文案已不再出现的条目 = 过期白名单
    for (weid, wt) in VERIFIED_FAR:
        if weid == eid and tuple(wt.split('/')) not in trips:
            stale.append((weid, wt))

print('装备文案三元组 %d 个 · 代码三元数组 %d 个 · 已核实远处命中白名单 %d 条'
      % (total, len(ARRS), len(VERIFIED_FAR)))
bad = 0
if none:
    bad += len(none); print('\n[FAIL] 代码里完全找不到对应数组: %d' % len(none))
    for m in none: print('   %-10s %-12s %s' % m)
if far:
    bad += len(far); print('\n[CHECK] 远处命中·不在白名单(人工核代码后再加白名单): %d' % len(far))
    for m in far: print('   %-10s %-12s %s' % m)
if stale:
    bad += len(stale); print('\n[STALE] 白名单条目在文案里已不存在(文案改过?请复核并清理): %d' % len(stale))
    for m in stale: print('   %-10s %s' % m)
print('\n' + ('ALL OK — 装备文案三元组与代码一致' if bad == 0 else 'NEEDS REVIEW: %d' % bad))
sys.exit(1 if bad else 0)
