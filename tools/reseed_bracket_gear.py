# -*- coding: utf-8 -*-
"""按用户 2026-07-21 的云顶式强度梯队, 重排 ghost_seed.json 各档的装备配置。

【为什么要重排】
  ①档0 应该是"所有玩家第一大轮第一把"→ 不该有装备; 而且代码
    equip_slots_for_battles(1) == 0 本来就规定 0 槽 —— 旧数据发了 3 件, 违反自家规则。
  ②档7/档8 旧数据各 15 件, 但槽位上限是 4槽×3龟 = 12 件 —— 也超了。
  ③各档之间的强度梯度不按梯队走(旧档8 全 5费3星, 而用户明确说 5费3星"几乎不存在")。

【强度换算】用户给的公式: 强度 ≈ M费基础值 × 1.8^(N-1) × 技能系数(低费技能弱→系数低)
【槽位上限】代码权威 backend.battles_for_bracket + phase2_config.equip_slots_for_battles

只改 equipped / minions[*].equips, 不动阵容/等级/其它字段。原文件自动备份。
"""
import io
import json
import random
import shutil

SRC = 'data/ghost_seed.json'
BAK = 'data/ghost_seed.json.bak-gear'
EQ = 'data/phase2-equipment.json'

# ── 代码权威: 档 → 场次 → 每龟槽位 ──
BRACKET_BATTLES = {0: 1, 1: 3, 2: 5, 3: 8, 4: 14, 5: 20, 6: 30, 7: 40, 8: 45}


def slots_for_battles(t):
    if t <= 1:
        return 0
    if t <= 3:
        return 1
    if t <= 5:
        return 2
    if t <= 8:
        return 3
    return 4


# ── 各档的装备配比(费, 星, 权重) —— 按用户梯队设计 ──
# 梯队参考: 1费1星 < 2费1星 < 1费2星 < 3费1星 < 2费2星 < 4费1星/1费3星
#          < 3费2星 < 5费1星 < 2费3星 < 4费2星 < 3费3星 < 5费2星 < 4费3星 < 5费3星(几乎不存在)
TIER_MIX = {
    0: [],                                             # 无装备(第一大轮第一把)
    1: [(1, 1, 80), (2, 1, 20)],                       # 梯队#1-2 刚起步
    2: [(2, 1, 45), (1, 2, 30), (3, 1, 25)],           # 梯队#2-4
    3: [(3, 1, 35), (2, 2, 35), (1, 3, 15), (4, 1, 15)],   # 梯队#4-6
    4: [(4, 1, 25), (2, 2, 25), (3, 2, 35), (1, 3, 15)],   # 梯队#5-8 过渡到中期核心
    5: [(3, 2, 45), (5, 1, 25), (2, 3, 30)],           # 梯队#7-10 中期核心
    6: [(4, 2, 50), (3, 2, 30), (5, 1, 20)],           # 梯队#10 为主
    7: [(4, 2, 35), (3, 3, 35), (5, 2, 30)],           # 梯队#11-13 终局前段
    8: [(4, 3, 45), (5, 2, 40), (3, 3, 12), (5, 3, 3)],    # 梯队#13-14 主; 5费3星仅 3% (用户: 几乎不存在)
}

K = {1: 0.85, 2: 0.90, 3: 1.00, 4: 1.15, 5: 1.30}


def strength(m, n):
    return m * (1.8 ** (n - 1)) * K[m]


def main():
    shutil.copyfile(SRC, BAK)
    data = json.load(io.open(SRC, encoding='utf-8'))
    eqs = json.load(io.open(EQ, encoding='utf-8'))
    eqs = eqs if isinstance(eqs, list) else eqs.get('equipment', eqs.get('items'))
    by_cost = {}
    for e in eqs:
        by_cost.setdefault(int(e.get('cost', 1)), []).append(str(e['id']))

    rng = random.Random(20260721)     # 确定性: 同样输入永远同样输出, 便于复核
    report = []

    for bk in sorted(data['brackets'].keys(), key=int):
        b = int(bk)
        cap_per_pet = slots_for_battles(BRACKET_BATTLES.get(b, 45))
        mix = TIER_MIX.get(b, [])
        teams = data['brackets'][bk]
        tot_items = 0
        tot_str = 0.0

        for team in teams:
            leaders = team.get('leaders', [])
            equipped = {}
            for pid in leaders:
                items = []
                for _ in range(cap_per_pet):
                    if not mix:
                        break
                    cost, star = pick(rng, mix)
                    pool = by_cost.get(cost) or by_cost.get(1) or []
                    if not pool:
                        continue
                    items.append({'id': rng.choice(pool), 'star': star})
                    tot_items += 1
                    tot_str += strength(cost, star)
                if items:
                    equipped[pid] = items
            team['equipped'] = equipped

            # 小将: 镜像本档档次, 件数取队长的一半(向下取整), 上限 3
            mn = team.get('minions') or {}
            for lane in mn:
                for slot in mn[lane]:
                    n = 0 if not mix else min(3, max(0, cap_per_pet - 1))
                    ml = []
                    for _ in range(n):
                        cost, star = pick(rng, mix)
                        pool = by_cost.get(cost) or by_cost.get(1) or []
                        if pool:
                            ml.append({'id': rng.choice(pool), 'star': star})
                    slot['equips'] = ml

        avg = (tot_str / tot_items) if tot_items else 0.0
        report.append((b, len(teams), cap_per_pet, cap_per_pet * 3, tot_items, avg))

    io.open(SRC, 'w', encoding='utf-8').write(
        json.dumps(data, ensure_ascii=False, indent=1))

    print('备份 -> %s' % BAK)
    print('档 | 队数 | 槽/龟 | 队长件数上限 | 实发件数 | 单件均强度')
    prev = 0.0
    for b, nt, cap, capall, items, avg in report:
        arrow = ''
        if prev > 0 and avg > 0:
            arrow = '  (×%.2f)' % (avg / prev)
        print('  %d | %2d | %d | %2d | %4d | %6.2f%s' % (b, nt, cap, capall, items, avg, arrow))
        if avg > 0:
            prev = avg


def pick(rng, mix):
    tot = sum(w for _, _, w in mix)
    r = rng.uniform(0, tot)
    acc = 0.0
    for cost, star, w in mix:
        acc += w
        if r <= acc:
            return cost, star
    return mix[-1][0], mix[-1][1]


main()
