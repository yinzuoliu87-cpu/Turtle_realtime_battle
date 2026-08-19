# -*- coding: utf-8 -*-
"""文案【声称的事】 ↔ 代码【实际做的事】—— 查数值之外的那三类。

═══ 为什么要有这个 ═══
用户 2026-08-19 读一眼就发现:「小龟被动的增伤只适用于普通攻击吗」——
文案写「普攻伤害随稀有度提升」, 而代码那行挂在**伤害总闸**上(普攻/技能/真伤全覆盖),
系数取的还是**目标**的稀有度。**两处都错, 而当时全套 211 项门禁全绿。**

已有的审计器各有各的盲区:
  · `pet_number_audit`  —— 对【数值】和【效果类别覆盖】, 看不见"作用范围"
  · `passive_number_audit` —— 只对被动的系数
  · `tooltip_number_audit` —— 只对装备数值
  ⇒ 「文案说 A, 代码做 B」这一整类, **没有任何一条判据在看**。

═══ 这个工具查三类可机检的"声称" ═══
  ① 触发周期: 文案「每 N 秒」 ↔ 代码里这只龟的计时常量/判断里有没有这个 N
  ② 选靶对象: 文案「最近/最远/随机/全体/生命最低/攻击力最高」 ↔ 代码里的选靶调用
  ③ 作用范围: 文案「普攻/普通攻击」这种限定词 ↔ 实现是不是挂在通用伤害路径上

★判据边界(老实说清楚):
  · 只查【能机检的三类】。像"击飞 0.55 秒滞空"这种演出细节, 机检不了, 仍需人读。
  · 报出来的是**疑点**不是结论 —— 每条都要人复核; 复核过认为没问题的进 ACCEPT 名单,
    连理由一起写在这里, 而不是把判据放宽。
  · 分母会打印: 扫到几只龟、几条文案、几处代码 —— 0 了就是空检查。

跑法: python tools/text_claim_audit.py [--list]
"""
import io
import os
import re
import sys
import json
import glob

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
NL = chr(10)

# ── 选靶词 → 代码里对应的函数名/关键字 ─────────────────────────────────
# ⚠ 第一版按"有具名选靶函数"设计(`_farthest_enemy` 之类) —— **这仓库根本没有这类函数**,
#   grep 出来是空的, 选靶全是内联循环。于是 7 条全是误报(竹击/背刺实测代码注释就写着
#   「钩最远那个」「闪现到最远那只身后」, 文案是对的)。
#   ⇒ 改成两路取证: 标识符**或**同段中文注释里提到这个概念都算数。
#   ★注释是弱证据(它会烂), 所以这里报出来的一律只当【疑点】, 人复核之后进 ACCEPT。
TARGET_WORDS = {
    '最近的敌': ['nearest', 'closest', '最近'],
    '最远的敌': ['farthest', 'far_enemy', '最远'],
    '随机': ['randi', 'pick_random', 'randf', 'shuffle', '随机'],
    '全体敌': ['_all_enemies', '_enemies_of', '_team_of', '全体', '全场'],
    # 手写的最小值循环里没有 lowest 字样(涟漪药剂/狙击长管都是 var lv := INF 比大小),
    # 只按名字找会把它们报成误报。把这个惯用法也算进来。
    '生命百分比最低': ['lowest', 'min_hp', '最低', '最残', 'INF', 'hp_frac'],
    '攻击力最高': ['highest_atk', 'max_atk', '最高'],
}

# 复核过、认为文案没问题的疑点(连理由)。★放这里而不是放宽判据。
ACCEPT = {
    ('basic', '普攻'): '龟盾那半边确实只强化下一次普攻; 增伤那半边已改成「所有伤害」',
    # 下面 5 条 2026-08-19 逐条读代码复核过: **文案是对的**, 报出来是因为被描述的行为
    # 不在"这个技能自己那个函数"里(证据范围的固有边界), 不是文案错。
    ('fortune', '招财进宝', '随机'): '随机在 _chest_sys._chest_pick_equip 里, 不在技能函数内',
    ('rainbow', '反射', '随机'): '「随机敌」属于打包被动【强化棱镜】, 实现在被动 tick 不在本技能',
    ('rainbow', '反射', '每5秒'): '同上, 「每 5 秒抽一色」是强化棱镜被动的节奏',
    ('candy', '糖果炸弹', '全体敌'): '「对全体敌人均摊」是炸弹死亡爆炸, 实现在 spawn/summon 侧',
    ('shell', '复制', '随机'): '代码用 pool.shuffle() 取随机 —— 我的词表当时没收 shuffle',
    # ── 装备(2026-08-19 逐件复核): 都是**证据范围**造成的误报, 文案本身对 ──
    ('p2eq_080', '每1.2秒'): '机炮节拍是 eq_gun_batch.gd 的常量 HELI_FIRE_IV := 1.2, 不在 id 附近',
    ('p2eq_080', '最近的敌'): '直升机走通用召唤 AI 选靶, 不在这件装备的代码里',
    ('p2eq_080', '随机'): '同上; 轰炸航线由通用逻辑挑',
    ('p2eq_033', '最近的敌'): '海螺虫是 _spawn_summon("worm") 通用召唤, 自动打最近敌由召唤 AI 管',
    ('p2eq_033', '随机'): '小虫随机带 3 件装备走 _chest_pick_equip, 不在本件代码里',
    ('p2eq_087', '随机'): '偷训龟大师技能走大师技能池的随机, 不在本件代码里',
    ('p2eq_092', '随机'): '毒蛾飞行物随机选目标由 venom_drone 的飞行逻辑管',
    ('p2eq_094', '最近的敌'): '实测用 _nearest_enemy_from(以碑为原点算最近), 文案对; 误报因为它的实现函数叫 stele_bolt_land, 不符合我 _eq_/_tick_ 的命名假设',
}


def load_pets():
    d = json.load(io.open('data/pets.json', encoding='utf-8'))
    return d if isinstance(d, list) else d['pets']


def strip(t):
    t = re.sub(r'<[^>]*>', '', t)
    t = re.sub(r'\{[A-Za-z]?:?[^}]*\}', ' ', t)
    return t


def skill_code(S, src, sk_type, pid, consts):
    """只取【这个技能自己那个函数】的代码, 不再拿整只龟的代码当证据。

    ★为什么必须收窄(实测教训): 第一版把"提到这只龟 id 的行 ±12 行"全当证据,
      代码池撑到 **200 万字符** —— 反向验证塞一句「每 77 秒」进去, 判据**报 0**,
      因为 "77" 在这么大的池子里随便就能撞上。**分母撑爆 = 空检查。**
      现在改用仓库已有的 `pet_code_scope.dispatch_map` 找到实现函数,
      再用 `func_scope` 取函数体(含它调用的下一层), 证据范围就是它自己。
    """
    fname = S.dispatch_map(src).get(sk_type)
    if not fname:
        return ''
    _path, funcs, _c = S.func_scope(src, fname, depth=2)
    return NL.join(b for _n, b in funcs)


def basic_atk_code(S, src, pid):
    """普攻这条链: `BASIC_ATK` 表里这只龟那一行 + 主场景里它的 `u["id"] == "<pid>"` 分支。

    ★为什么不把 `_basic_attack` / `_do_basic` 整个函数体也算进去:
      那两个函数是**所有龟共用**的, 把它算成证据等于给每只龟都发一张通行证 ——
      判据会被稀释成"什么都能找到"(这正是这条工具前面栽过三次的病)。
    """
    rb = src.get('scripts/scenes/RealtimeBattle3DScene.gd', '')
    row = ''
    m = re.search(r'^\s*"%s":\s*\{[^}]*\}.*$' % re.escape(pid), rb, re.M)
    if m:
        row = m.group(0)
    return row + NL + passive_code(S, src, pid, {})


def passive_code(S, src, pid, consts):
    """被动没有 dispatch —— 取主场景里 `u["id"] == "<pid>"` 那个分支的整段。"""
    lines = src.get('scripts/scenes/RealtimeBattle3DScene.gd', '').split(NL)
    out = []
    i = 0
    while i < len(lines):
        if ('u["id"] == "%s"' % pid) in lines[i] or ("u[\"id\"] == \"%s\"" % pid) in lines[i]:
            base = len(lines[i]) - len(lines[i].lstrip())
            out.append(lines[i])
            j = i + 1
            while j < len(lines):
                ln = lines[j]
                if ln.strip() and (len(ln) - len(ln.lstrip())) <= base and not ln.lstrip().startswith('#'):
                    break
                out.append(ln)
                j += 1
            i = j
        else:
            i += 1
    f = 'scripts/systems/skills/%s_system.gd' % pid
    if f in src:
        out.append(src[f])
    return NL.join(out)


def main():
    pets = load_pets()
    funnel = io.open('scripts/scenes/battle/battle_damage.gd', encoding='utf-8').read()
    funnel_ids = set(re.findall(r'(?:src|u)\.get\("id",\s*""\)\s*==\s*"([a-z_]+)"', funnel))

    import pet_code_scope as S
    src = S.load_src()
    consts = S.battle_consts(src)
    n_pet = n_txt = n_code = 0
    period_bad, target_bad, scope_bad, unmatched = [], [], [], []
    for p in pets:
        pid = str(p.get('id', ''))
        entries = []
        pa = p.get('passive')
        if isinstance(pa, dict):
            entries.append(('被动', pa, passive_code(S, src, pid, consts)))
        for sk in (p.get('skillPool') or []):
            _c = skill_code(S, src, str(sk.get('type', '')), pid, consts)
            if len(_c.strip()) < 40:
                # 普攻不在分派表里(仓库注释早写明), 走 BASIC_ATK 这条链
                _c = basic_atk_code(S, src, pid)
            entries.append((str(sk.get('name', '')), sk, _c))
        if any(len(c.strip()) > 40 for _n, _o, c in entries):
            n_pet += 1
        for nm, obj, code in entries:
            if len(code.strip()) < 40:
                # ★对不到实现 = 这条【查不了】, 必须显式登记。
                #   第一版在这里静默 continue —— 140 条里 29 条被悄悄跳过, 而我只打印
                #   "受检 111 条"。反向验证往被跳过的那条里塞「每 77 秒」, 判据自然报 0,
                #   我差点以为是匹配逻辑坏了。**缺口不登记 = 假绿。**
                unmatched.append((pid, nm, str(obj.get('type', '') or '被动')))
                continue
            n_code += len(code)
            txt = strip(' '.join(str(obj.get(k, '') or '') for k in ('brief', 'desc', 'detail')))
            if not txt.strip():
                continue
            n_txt += 1
            for m in re.finditer(r'每\s*([0-9.]+)\s*秒', txt):
                v = m.group(1)
                # ★必须带数字边界: 子串匹配会让「77」撞上 `0.775`、`#777`, 于是
                #   反向验证塞「每 77 秒」进去判据**报 0** —— 又一个空检查。
                alts = {v, v + '.0', v.rstrip('0').rstrip('.')}
                pat = '|'.join(re.escape(a) for a in alts if a)
                if re.search(r'(?<![0-9.])(?:%s)(?![0-9])' % pat, code) is None                         and (pid, nm, '每%s秒' % v) not in ACCEPT:
                    period_bad.append((pid, nm, '每%s秒' % v))
            for w, keys in TARGET_WORDS.items():
                if w in txt and not any(k in code for k in keys)                         and (pid, nm, w) not in ACCEPT:
                    target_bad.append((pid, nm, w))
            if pid in funnel_ids and ('普攻' in txt or '普通攻击' in txt):
                if (pid, '普攻') not in ACCEPT:
                    scope_bad.append((pid, nm, '说普攻但实现在伤害总闸'))

    # ── 装备 95 件: 同样查【触发周期 / 选靶对象】 ─────────────────────────
    # ★证据 = `scripts/systems/equip/*.gd` 里提到这件 id 的行 ±14 行(那是它的 match 分支)。
    #   不含主场景共享函数 —— 同龟那边的教训: 共享代码算证据 = 给每件发通行证。
    eq_src = {}
    for f in sorted(glob.glob('scripts/systems/equip/*.gd')):
        eq_src[f] = io.open(f, encoding='utf-8', errors='replace').read()
    # 召唤物类装备(复活海螺/旋翼机/毒蛾茧/潜水钟)的行为住在 battle/ 与主场景, 不在 equip/ ——
    # 只扫 equip/ 会把它们全报成"选靶对不上"。把提到这件 id 的其它文件也收进来。
    eq_extra = {}
    for f in (sorted(glob.glob('scripts/scenes/battle/*.gd'))
              + ['scripts/scenes/RealtimeBattle3DScene.gd']):
        eq_extra[f] = io.open(f, encoding='utf-8', errors='replace').read()
    eqd = json.load(io.open('data/phase2-equipment.json', encoding='utf-8'))
    eqarr = eqd if isinstance(eqd, list) else list(eqd.values())[0]
    n_eq = 0
    eq_unmatched = []
    for e in eqarr:
        eid = str(e.get('id', ''))
        buf = ''
        for _f, src_s in list(eq_src.items()) + list(eq_extra.items()):
            lines = src_s.split(NL)
            keep = set()
            for i, ln in enumerate(lines):
                if eid in ln:
                    for j in range(max(0, i - 6), min(len(lines), i + 15)):
                        keep.add(j)
            for j in sorted(keep):
                buf += lines[j] + NL
        # ★装备的实现在【具名函数】里(_eq_fuel_throw / _tick_sword_storm), 函数体不含 id ——
        #   只按 id 抓行只能抓到 match 分派表和注释, 抓不到真正干活的代码 ⇒ 22 条选靶全是误报。
        #   跟着分派/注释里提到的函数名, 把函数体也收进证据。(同龟那边的教训。)
        fns = set(re.findall(r'(_(?:eq|tick)_[a-z0-9_]+)', buf))
        for _f2, src2 in eq_src.items():
            l2 = src2.split(NL)
            for i2, ln2 in enumerate(l2):
                m2 = re.match(r'func (' + '|'.join(re.escape(x) for x in fns) + r')', ln2) if fns else None
                if m2 is None:
                    continue
                j2 = i2 + 1
                while j2 < len(l2) and (l2[j2].strip() == '' or l2[j2].startswith((chr(9), ' '))):
                    buf += l2[j2] + NL
                    j2 += 1
        # 装备周期 tick 的 2.5 秒是主场景常量 EQ_TICK, 不在装备文件里 —— 单独补上这一行
        buf += 'EQ_TICK 2.5' + NL
        txt = strip(str(e.get('effectBrief', '') or '') + ' ' + str(e.get('effectDesc1', '') or ''))
        if len(buf.strip()) < 40:
            eq_unmatched.append((eid, str(e.get('name', '')), '-'))
            continue
        n_eq += 1
        for m in re.finditer(r'每\s*([0-9.]+)\s*秒', txt):
            v = m.group(1)
            alts = {v, v + '.0', v.rstrip('0').rstrip('.')}
            pat = '|'.join(re.escape(a2) for a2 in alts if a2)
            if re.search(r'(?<![0-9.])(?:%s)(?![0-9])' % pat, buf) is None                     and (eid, '每%s秒' % v) not in ACCEPT:
                period_bad.append((eid, str(e.get('name', '')), '每%s秒' % v))
        for w, keys in TARGET_WORDS.items():
            if w in txt and not any(k in buf for k in keys) and (eid, w) not in ACCEPT:
                target_bad.append((eid, str(e.get('name', '')), w))

    print('=== 文案声称 ↔ 代码实际 (数值之外的三类) ===')
    print('★分母: 对到代码的龟 %d 只 · 受检文案 %d 条 · 代码 %d 字符'
          % (n_pet, n_txt, n_code))
    print('★装备: 对到实现 %d 件 · 连不上实现 %d 件' % (n_eq, len(eq_unmatched)))
    for r in (eq_unmatched if '--list' in sys.argv else eq_unmatched[:6]):
        print('       %-11s %s' % (r[0], r[1]))
    print('★缺口: 连不上实现、因而【查不了】的文案 %d 条 —— 这些不是"通过", 是没查'
          % len(unmatched))
    for r in (unmatched if '--list' in sys.argv else unmatched[:8]):
        print('       %-10s %-12s type=%s' % r)
    show = '--list' in sys.argv
    for title, rows in [('① 触发周期对不上', period_bad),
                        ('② 选靶对象对不上', target_bad),
                        ('③ 作用范围说窄了', scope_bad)]:
        print('  %-16s %3d 处' % (title, len(rows)))
        for r in (rows if show else rows[:8]):
            print('       %-10s %-12s %s' % r)
    print('  复核过认为没问题的(附理由) %d 条:' % len(ACCEPT))
    if '--list' in sys.argv:
        for k, why in ACCEPT.items():
            print('       %s —— %s' % ('·'.join(k), why))
    bad = len(period_bad) + len(target_bad) + len(scope_bad)
    if bad:
        print('  ★★有 %d 处【文案声称】对不上【代码实际】, 且未经复核 —— 逐条读代码判,'
              '判完要么改文案, 要么进 ACCEPT 并写清理由(不许放宽判据)。' % bad)
        return 1
    print('  ALL OK — 文案声称 ↔ 代码实际(三类可机检的)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
