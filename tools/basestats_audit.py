# -*- coding: utf-8 -*-
"""basestats_audit.py — 装备属性展示串 `baseStats1` ↔ 事实源 `EquipStats.STATS`。

★由来(2026-08-20): CLAUDE.md 白纸黑字写着"装备属性的真事实源是 EquipStats.STATS,
  data/phase2-equipment.json 里的 baseStats1 是**它的手写镜像, 仅供展示**"。
  手写镜像 = 必然会漂 —— 而**全项目没有任何东西在对这两者的账**:
  `tooltip_number_audit` 只查 effectDesc1 的**效果**三元组, 它的注释里还专门写着
  "equip_stats 只有属性 STATS(无效果三元组)" ⇒ 属性这条缝谁都没管。
  玩家在商店和图鉴看到的属性行就是这个 baseStats1。

★判据: 把 `+攻5/12/20·暴击10/15/25%` 解析成 (键, 三档值), 与 STATS 的三档逐个比。
★★**必须自报"有多少标签没映射上"** —— 映射表是白名单, 白名单天生会漏,
  漏掉的标签如果被静默跳过, 就会伪装成"全部通过"(今晚已经在别处栽过两次)。
"""
import io, json, re, sys

sys.stdout.reconfigure(encoding='utf-8')

# 展示串里的中文标签 → STATS 键。百分号类在 STATS 里存的是小数还是整数, 见 PCT。
LABEL = {
    '攻': 'atk', '生命': 'hp', '护甲': 'def', '魔抗': 'mr', '暴击': 'crit',
    '暴伤': 'critDmg', '护穿': 'armorPen', '破甲': 'armorPen',
    '魔穿': 'magicPen', '法穿': 'magicPen',
    '攻速': '_aspdPct', '移速': '_mspdPct', '射程': '_rangeAdd',
    '吸血': '_lifestealPct', '龟能': '_maxEnergy', '充能': '_echargePct',
    '盾疗': 'shieldHealPct', '治疗与护盾': 'shieldHealPct',
    '闪避': 'dodgePct', '反伤': 'reflectPct',
    '生命偷取': '_lifestealPct', '龟能充能': '_echargePct', '攻击': 'atk',
    '治疗增幅': 'healAmp', '治疗&盾增': 'shieldAmp', '盾增': 'shieldAmp',
}
# 这些键在 STATS 里以小数存(0.10), 而展示串写百分数(10%)
# ★哪些键在 STATS 里存小数是**量出来的**, 不是猜的: crit 存 0.10 而展示写 10%;
#   dodgePct 却存 15.0(整数百分比) —— 第一版把它算成小数, 报出 3 处「展示=15.0 STATS=15.0」的假分歧。
PCT = {'crit', 'critDmg'}
# 一个标签映到两个键(双抗 = 护甲 + 魔抗)
MULTI = {'双抗': ['def', 'mr'], '护甲&魔抗': ['def', 'mr']}


def code_stats():
    s = io.open('scripts/gamedata/equip_stats.gd', encoding='utf-8').read()
    out = {}
    # 不要求行尾逗号+换行 —— 有条目跨行写, 第一版因此只解析到 55/95,
    # 而"只解析到一半"会安静地变成"只查了一半"。分母断言就是防这个。
    pat = '"(p2eq_\\d{3})"\\s*:\\s*\\[(.*?)\\](?=\\s*[,\\n])'
    for m in re.finditer(pat, s, re.S):
        tiers = re.findall(r'\{([^}]*)\}', m.group(2))
        rows = []
        for t in tiers:
            d = {}
            for k, v in re.findall(r'"(\w+)"\s*:\s*(-?[\d.]+)', t):
                d[k] = float(v)
            rows.append(d)
        if len(rows) == 3:
            out[m.group(1)] = rows
    return out


def main():
    code = code_stats()
    j = json.load(io.open('data/phase2-equipment.json', encoding='utf-8'))
    eq = j.get('equipment') if isinstance(j, dict) else j

    n_item = 0
    n_num = 0
    bad = []
    unmapped = {}
    for it in eq:
        eid = str(it.get('id', ''))
        b = str(it.get('baseStats1', '')).strip()
        if not b or eid not in code:
            continue
        n_item += 1
        for m in re.finditer(r'([\u4e00-\u9fa5&]+)\s*([\d.]+(?:/[\d.]+)*)\s*(%?)', b):
            lab, nums, pct = m.group(1).lstrip('+'), m.group(2), m.group(3)
            keys = MULTI.get(lab) or ([LABEL[lab]] if lab in LABEL else None)
            if keys is None:
                unmapped[lab] = unmapped.get(lab, 0) + 1
                continue
            vals = [float(x) for x in nums.split('/')]
            if len(vals) == 1:              # 射程这类三档同值, 只写一次
                vals = vals * 3
            if len(vals) != 3:
                continue
            for key in keys:
                for i, v in enumerate(vals):
                    n_num += 1
                    cv = code[eid][i].get(key)
                    want = v / 100.0 if key in PCT else v
                    if cv is None:
                        bad.append((eid, it.get('name'), lab, key, i + 1, v, '代码里没这个键'))
                    elif abs(float(cv) - want) > 1e-6:
                        bad.append((eid, it.get('name'), lab, key, i + 1, v, cv))

    print('[分母] 对账 %d 件 · 比了 %d 个数 · STATS 解析到 %d 件' % (n_item, n_num, len(code)))
    if n_item < 50 or n_num < 200:
        print('\n[FAIL] 对账件数/数字太少 —— 解析失效了, 这是空检查不是通过')
        return 1
    if unmapped:
        print('\n[FAIL] 有 %d 个属性标签没映射到 STATS 键(漏掉就等于没查):' % len(unmapped))
        for k, v in sorted(unmapped.items(), key=lambda x: -x[1]):
            print('   「%s」 出现 %d 次' % (k, v))
        return 1
    if bad:
        print('\n[FAIL] 展示串与事实源对不上 %d 处:' % len(bad))
        for eid, nm, lab, key, star, v, cv in bad[:14]:
            print('   %-10s %-8s %s(%s) %d★  展示=%s  STATS=%s' % (eid, nm, lab, key, star, v, cv))
        print('\n  事实源是 EquipStats.STATS(CLAUDE.md §1)。改展示串, 别改代码。')
        return 1
    print('\nALL OK — 装备属性展示串与 EquipStats.STATS 一致')
    return 0


if __name__ == '__main__':
    sys.exit(main())
