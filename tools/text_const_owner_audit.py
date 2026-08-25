# -*- coding: utf-8 -*-
"""文案里引用的常量, 类名必须**属于这个主体** —— 跨主体引用一律报出来。

★为什么必须单独一条(2026-08-25 两次真事故, 两次都是同一个根因):
  批量转引用的写入如果用【全局字符串替换】, 同一个 `{N:0.5*ATK}` 会被替换成
  **第一个提案**里的常量, 而它属于别的龟:
    · 无头龟「万千触须」→ 骰子龟 `DiceSystem.ALLIN_DMG` (1.5 → 0.5)
    · 无头龟「灵魂打击」→ 彩虹龟 `RainbowSystem.REFLECT_COEF` (两者都是 0.5)

  已有门禁**一条都拦不住第二例**:
    · 渲染门禁     —— 它确实渲染得出一个数, 绿。
    · 原文金样本   —— 只说"这行改了", 绿。
    · 值金样本     —— 两个常量【同值】⇒ 多重集没变, 绿。
    · 常量孤儿审计 —— 那个常量确实有产品代码在读(彩虹龟在读), 绿。
    · text_formula_audit —— 只覆盖"同时写了百分比文字"的句子。
  第二例是被 `verify_turtle_balance_r6` 抓到的 —— 它恰好断言了具体常量名。
  ⇒ 归属本身要有一条独立门禁, 不能指望平衡门禁碰巧覆盖到。

★判据: 一段文案引用 `X.CONST`, 则 X 必须是
  ① 这个主体自己的类(龟 → `<id>_system.gd` 的 class_name; 装备 → 实现它的批文件类), 或
  ② 全局共享类(下面 SHARED 白名单, 每条都有理由), 或
  ③ EXEMPT 里逐条写明理由的例外(比如龟技能确实引用了另一只龟的机制)。
"""
import io, json, os, re, sys, glob

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NL = chr(10)

REF = re.compile(r'\{[A-Z][:：][^{}]*?([A-Z][A-Za-z0-9_]*)\.([A-Z][A-Z0-9_]{2,})[^{}]*\}')
TEXT_KEYS = ('brief', 'desc', 'detail', 'effectDesc1', 'effectDesc2', 'effectDesc3', 'effectBrief')

## 全局共享类 —— 任何主体都可以引用, 各有理由。
SHARED = {
    'RealtimeBattle3DScene': '主场景: 全局规则常量(战场尺寸/通用控制时长/召唤物系数)',
    'EquipSystem': '装备总系统: 周期表与跨件常量',
    'EquipTickSystem': '装备每帧系统: 周期件的间隔与层数上限',
    'CombatMath': '通用战斗数学(暴击/减伤公式)',
    'DamageMath': '通用伤害数学',
    'SkillEnergy': '龟能通用规则',
    'BasicConsts': '小龟 = 所有龟的普攻基线, 被别的龟当通用值引用',
    'SynergySystem': '羁绊总表',
    'BattleDamage': '伤害层: 诅咒/流血/中毒这些【跨龟通用的 DoT 规则】住在这里',
    'EquipStatsApply': '装备属性落地层: 各件的初始层数/上限',
}

## 逐条例外: 主体 → {允许的外部类: 理由}。**不写理由不许加。**
## 这些是**真的复用了别人的机制**, 不是接错:
EXEMPT = {
    'p2eq_028': {'IceSystem': '冰霜冻露瓶直接复用寒冰龟的【冰寒】状态与冻露参数'},
    'p2eq_029': {'IceSystem': '寒霜裂地直接复用寒冰龟的【裂地】几何'},
    'p2eq_031': {'CrystalSystem': '环形扫射复用水晶龟的扫射扇面与结晶印记'},
    'p2eq_030': {'CrystalSystem': '贯穿光束复用水晶龟的光束参数'},
    'p2eq_067': {'VenomDroneSystem': '毒药瓶的普攻附毒走毒液无人机那套中毒层数'},
    'p2eq_068': {'PotionEqVfx': '深海气压罐的射束长度/时长由它的演出层定义(几何即规格)'},
    'p2eq_076': {'BowEqVfx': '连发弩机的贯穿衰减【故意】住在演出层: `pierce_mult()` 是'
                             '"伤害与光迹亮度"的同一个事实源(见 bow_eq_vfx.gd §④ 的注释),'
                             '拆开就会出现"光越来越暗但伤害没降"这类两边不一致'},
}


def class_of(path):
    if not os.path.exists(path):
        return None
    m = re.search(r'^class_name\s+(\w+)', io.open(path, encoding='utf-8', errors='replace').read(), re.M)
    return m.group(1) if m else None


def equip_owner_classes():
    """装备 id → 允许的类集合。装备的实现散在多个批文件里, 用 `p2eq_0NN` 出现过的文件反查。"""
    own = {}
    for p in glob.glob(os.path.join(ROOT, 'scripts/systems/**/*.gd'), recursive=True) + \
             glob.glob(os.path.join(ROOT, 'scripts/scenes/battle/*.gd')):
        src = io.open(p, encoding='utf-8', errors='replace').read()
        cls = re.search(r'^class_name\s+(\w+)', src, re.M)
        if not cls:
            continue
        for eid in set(re.findall(r'p2eq_\d{3}', src)):
            own.setdefault(eid, set()).add(cls.group(1))
    ## ★同龟侧那条教训: 光反查 id 会漏 —— `eq_spirit_batch.gd` 里 `p2eq_061` 出现 0 次,
    ##   而它正是 061 的实现。⇒ 再加一条**中文装备名**反查。
    eq = json.load(io.open(os.path.join(ROOT, 'data/phase2-equipment.json'), encoding='utf-8'))
    eq = eq if isinstance(eq, list) else next(v for v in eq.values() if isinstance(v, list))
    srcs = []
    for p in glob.glob(os.path.join(ROOT, 'scripts/systems/**/*.gd'), recursive=True) +              glob.glob(os.path.join(ROOT, 'scripts/scenes/battle/*.gd')):
        t = io.open(p, encoding='utf-8', errors='replace').read()
        c = re.search(r'^class_name\s+(\w+)', t, re.M)
        if c:
            srcs.append((c.group(1), t))
    for item in eq:
        nm = str(item.get('name', ''))
        if len(nm) < 2:
            continue
        for cname, t in srcs:
            if nm in t:
                own.setdefault(str(item.get('id', '')), set()).add(cname)
    return own


def pet_owner_classes(pets):
    """龟 → 允许的类集合。

    ★不能只按 `scripts/systems/skills/<id>_system.gd` 猜文件名 —— **id 与文件名不总一致**:
      星际龟的 id 是 `space`, 实现却在 `star_system.gd`(class StarSystem)。
      按文件名猜会把它 25 处**全部合法的**引用报成"串台"(第一版实测)。
    ★也不能只反查 `"<id>"`: `star_system.gd` 里 `"space"` 出现 **0 次** ——
      那个文件根本不需要写自己的 id。⇒ 再加一条**技能名**反查(中文技能名是强归属信号)。
    """
    own = {}
    sig = {}
    for p in pets:
        pid = str(p.get('id', ''))
        own[pid] = set()
        names = set()
        pa = p.get('passive') or {}
        if pa.get('name'):
            names.add(str(pa['name']))
        for sk in (p.get('skillPool') or []):
            if sk.get('name'):
                names.add(str(sk['name']))
        sig[pid] = names
    for p in glob.glob(os.path.join(ROOT, 'scripts/systems/skills/*.gd')):
        src = io.open(p, encoding='utf-8', errors='replace').read()
        cls = re.search(r'^class_name\s+(\w+)', src, re.M)
        if not cls:
            continue
        base = os.path.basename(p)
        for pid, names in sig.items():
            if (base == '%s_system.gd' % pid or ('"%s"' % pid) in src
                    or sum(1 for nm in names if len(nm) >= 2 and nm in src) >= 2):
                own[pid].add(cls.group(1))
    return own


def main():
    bad, n = [], 0
    eq_own = equip_owner_classes()

    pets = json.load(io.open(os.path.join(ROOT, 'data/pets.json'), encoding='utf-8'))
    pets = pets if isinstance(pets, list) else pets['pets']
    pet_own = pet_owner_classes(pets)
    for p in pets:
        pid = str(p.get('id', ''))
        mine = set(pet_own.get(pid, set()))
        segs = [(('被动.' + k), (p.get('passive') or {}).get(k) or '') for k in TEXT_KEYS]
        for sk in (p.get('skillPool') or []):
            segs += [('%s.%s' % (sk.get('name'), k), sk.get(k) or '') for k in TEXT_KEYS]
        for label, t in segs:
            for m in REF.finditer(str(t)):
                n += 1
                cls = m.group(1)
                if cls in mine or cls in SHARED or cls in EXEMPT.get(pid, {}):
                    continue
                bad.append(('龟', pid, label, cls + '.' + m.group(2), '本龟的类是 %s'
                            % (', '.join(sorted(mine)) or '(它没有独立系统文件)')))

    eq = json.load(io.open(os.path.join(ROOT, 'data/phase2-equipment.json'), encoding='utf-8'))
    eq = eq if isinstance(eq, list) else next(v for v in eq.values() if isinstance(v, list))
    for e in eq:
        eid = str(e.get('id', ''))
        mine = eq_own.get(eid, set())
        for k in TEXT_KEYS:
            t = str(e.get(k) or '')
            for m in REF.finditer(t):
                n += 1
                cls = m.group(1)
                if cls in mine or cls in SHARED or cls in EXEMPT.get(eid, {}):
                    continue
                bad.append(('装备', eid, k, cls + '.' + m.group(2),
                            '实现它的类是 %s' % (', '.join(sorted(mine)) or '(找不到)')))

    print('[分母] 文案里的常量引用 %d 处' % n)
    if n < 200:
        print('[FAIL] ★分母只有 %d —— 空检查不是通过' % n)
        return 1
    if bad:
        print('')
        print('★★ 引用了【不属于这个主体】的类 %d 处 —— 多半是批量替换串了台:' % len(bad))
        for kind, sid, label, ref, why in bad[:40]:
            print('   %-3s %-11s %-22s → %-42s %s' % (kind, sid, label[:22], ref, why))
        if len(bad) > 40:
            print('   ... 另 %d 处' % (len(bad) - 40))
        print('')
        print('[FAIL] 跨主体引用。确实该引用外部类的, 加进 EXEMPT 并写明理由。')
        return 1
    print('')
    print('ALL OK — 文案引用的常量都属于它自己的主体')
    return 0


if __name__ == '__main__':
    sys.exit(main())
