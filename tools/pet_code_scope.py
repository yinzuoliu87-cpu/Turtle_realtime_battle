# -*- coding: utf-8 -*-
"""龟技能【代码事实源】共享模块 (2026-07-30)。

★为什么存在 —— 用户 2026-07-30:「有些细节不应该让玩家看到的，但你在看技能时
  应该以代码的实际效果来向我汇报，这怎么办」。他点到了根本: 这是【两件事】——

  | | 事实源 | 用途 |
  |---|---|---|
  | 玩家看到的文案 (pets.json brief/detail) | 设计决定, 有些效果【故意不写】 | 游戏内展示 |
  | 做平衡分析 / 向用户汇报 | **必须是代码** | 判强度、定数值 |

  我这一路的错就是拿 tooltip 当事实源汇报: 无头·灵魂打击文案写 0.9A+20%当前生命,
  代码是 0.5A+10%(差一倍, 类型也错), 而且文案完全没提镰刀横扫的 5 秒诅咒 + 锁龟能。
  魔法石那次也是(文案 2%, 代码已是 2.1~3.0%)。

  所以: 分析技能【先跑 pet_effect_dump.py, 不读 tooltip】。

被两个工具共用(单一实现, 免得两份会漂):
  · tools/pet_effect_dump.py   —— 打印某技能的代码真实效果(给人看)
  · tools/pet_number_audit.py  —— 双向对账(进门禁)

★局限(必须知道, 别当成"抽全了"):
  · 只跟到调用链 depth=2, 且只跟【同文件】的 _xxx 函数
  · 通过 _pending_shots / tween callback 的【延时回调】跟不进去(如水晶刺)
  · 逐帧状态机跟不进去(如稳定骰子的 _dice_dash_tick)
  · 只认写死的字面量与同文件 const; 跨文件常量、运行时算出来的值抽不到
  抽不到的东西【不代表不存在】—— 那正是白名单要人工核的部分。
"""
import io, os, re

BS = chr(92)


def load_src(base='scripts'):
    """全部 .gd 源码 {路径: 内容}。"""
    src = {}
    for root, dirs, files in os.walk(base):
        for fn in files:
            if fn.endswith('.gd'):
                p = (root + '/' + fn).replace(BS, '/')
                src[p] = io.open(p, encoding='utf-8', errors='ignore').read()
    return src


def dispatch_map(src):
    """技能 type → 实现函数名。从主文件的 match 分派表抓。
    ★普攻(basic/physical/iceSpike…)不在这张表里 —— 它们走 BASIC_ATK 表, 需另走一条链。"""
    rb = src.get('scripts/scenes/RealtimeBattle3DScene.gd', '')
    return {m.group(1): m.group(2)
            for m in re.finditer(r'"([a-zA-Z]+)":\s*(?:_[a-z_0-9]+\.)?(_sk_[a-z_0-9]+)', rb)}


## 训龟大师技能 → 实现入口函数(2026-07-30 需求3「训龟大师的每一个技能效果和特效需要审核一边」)。
##
## ★为什么要手写这张表, 不像龟那样从 match 分派表自动抓 ——
##   大师的分派是 trainer_system._cast_active 里的 match, 但六个主动【分散在两个文件】:
##   hook/hunt_order/tame 在 trainer_system.gd, fury_potion/whistle/glacier 在主文件
##   (battle._cast_*)。func_scope 只跟【同文件】的 _xxx 子函数, 跨文件跟不进去,
##   所以入口必须显式指定, 才不会把三个漏成"效果 0 条"。
##
## ★魔法石是【被动】不是主动: 它不进 _cast_active, 走的是普攻路径
##   (trainer_system._tick_trainer_attacks 里判 _tr_passive == "magic_stone")。
##
## ★值是【一条函数链】而不是单个入口。为什么(探针实测出来的, 不是设计洁癖):
##   六个主动里有三个的入口是主文件里的【薄包装】—— 例如 _cast_glacier 只往
##   _glacier_zones 塞一个区域字典就返回了, 真正的"-40%移速 / 受伤+20%"在
##   trainer_system._tick_glaciers 里逐帧施加。func_scope 只跟【同文件】子函数,
##   所以只给入口的话这三个技能会显示"效果 0 条" —— 我第一版正是这样, 七个技能
##   抽出来一共 0 条效果, 看着像"大师没有任何效果"。
##   链里每一环都由 verify_trainer_audit 断言【函数真的存在】, 改名/搬家会红。
TRAINER_SKILLS = {
    # 被动: 普攻钩里判 _tr_passive → 石头弹道(battle_ballistics) → 到点 _trainer_magicstone_onhit 结算
    'magic_stone': ['_tick_trainer_attacks', '_fire_trainer_rock', '_trainer_magicstone_onhit'],
    # 钩锁: 入口→到达回调 _hook_grab(眩晕/易伤) + 逐帧 _tick_hooks(一段段拽)
    'hook':        ['_cast_hook', '_hook_grab', '_tick_hooks'],
    # 怒火药水: 入口(主文件·薄包装) → 落地回调施三 buff(trainer_system)
    'fury_potion': ['_cast_fury_potion', '_fury_apply_buffs'],
    # 口哨: 入口三选一 → 临时血 / 灵体气波 / 狂暴
    # 口哨②气波 2026-07-30 改真 skillshot: 入口只定方向+召小龟+登记飞行 →
    #   _tick_wave_flights 每帧推进+碰撞 → _wave_apply 命中才结算(削甲/真伤/击飞)
    'whistle':     ['_cast_whistle', '_whistle_temphp', '_apply_temp_maxhp',
                    '_whistle_spirit_wave', '_tick_wave_flights', '_wave_apply',
                    '_whistle_berserk', '_whistle_berserk_on'],
    # 冰川: 入口只登记区域 → 效果全在逐帧 _tick_glaciers
    'glacier':     ['_cast_glacier', '_tick_glaciers'],
    # 猎龟令: 入口只发锁头弹道 → 到达回调 _hunt_mark 打标记 → 逐帧 _hunt_taunt_tick 刷嘲讽
    'hunt_order':  ['_cast_hunt_order', '_hunt_mark', '_tick_hunt_taunt'],
    # 驯服: 入口发弹道 → _tame_mark 打标记 → 死亡时改判归顺 → 逐帧 _tick_tame_decay 掉血
    'tame':        ['_cast_tame', '_tame_mark', '_tick_tame_decay'],
}

TRAINER_CN = {
    'magic_stone': '魔法石(被动)', 'hook': '钩锁', 'fury_potion': '怒火药水',
    'whistle': '口哨', 'glacier': '冰川', 'hunt_order': '猎龟令', 'tame': '驯服',
}


def _one_body(s, fname):
    m = re.search(r'^func ' + re.escape(fname) + r'\(', s, re.M)
    if not m:
        return None
    nxt = re.search(r'^func ', s[m.end():], re.M)
    return s[m.start(): m.end() + (nxt.start() if nxt else len(s) - m.end())]


def func_scope(src, fname, depth=2):
    """→ (文件路径, [(函数名, 函数体), ...], {常量名: 值})

    搜索域 = 入口函数 + 它(递归 depth 层)调用的【同文件】函数。
    ★为什么要跟子函数: 伤害普遍不在入口函数里 —— 冰霜 0.18 在 _ice_frost_tick,
      水晶刺 1.5 在 _crystal_spike_line。第一版只读入口, 15 处报错全是误报。
    """
    for p, s in src.items():
        body = _one_body(s, fname)
        if body is None:
            continue
        consts = {cm.group(1): cm.group(2)
                  for cm in re.finditer(r'^const ([A-Z][A-Z0-9_]*)\s*:?=\s*([\d.]+)', s, re.M)}
        bodies = [(fname, body)]
        seen = {fname}
        frontier = [body]
        for _ in range(depth):
            nxt = []
            for b in frontier:
                for callee in sorted(set(re.findall(
                        r'(?<![A-Za-z0-9_])(_[a-z][a-z0-9_]*)\s*[\(.]', b))):
                    if callee in seen:
                        continue
                    sub = _one_body(s, callee)
                    if sub is None:
                        continue
                    seen.add(callee)
                    bodies.append((callee, sub))
                    nxt.append(sub)
            frontier = nxt
        return p, bodies, consts
    return None, None, None


def expand_consts(text, consts):
    """把同文件具名常量替换成数值 —— 冰封写的是 FREEZE_DMG 不是 2.5。"""
    for k, v in consts.items():
        text = text.replace(k, v)
    return text


def battle_consts(src):
    """主战斗文件里的数值常量表。给下面 expand_cross 用。"""
    rb = src.get('scripts/scenes/RealtimeBattle3DScene.gd', '')
    return {m.group(1): m.group(2)
            for m in re.finditer(r'^const ([A-Z][A-Z0-9_]*)\s*:?=\s*([\d.]+)', rb, re.M)}


def expand_cross(text, bc):
    """把 `battle.CONST` 形式的【跨文件】常量替换成数值。

    ★2026-07-30 加这个的原因(探针实测, 不是猜的): 训龟大师 7 技的 dump 一开始
      【七个全是"效果 0 条"】。探针打出 _hook_grab 的函数体, 看到的是
        battle._damage._stun(target, battle.HOOK_STUN, "hook")
      —— 数值是 battle.HOOK_STUN, 常量定义在主文件, 而 trainer_system.gd 自己
      【一个 const 都没有】, 所以 expand_consts(只展开同文件)什么也换不掉,
      EFFECT_RULES 里要求数字字面量的规则就全部落空。
      这正是本模块注释里写着的"跨文件常量抽不到"那条局限, 现在补掉。

    ★只替换带 `battle.` 前缀的形式, 不做裸名替换 —— 裸名替换会把主文件的常量
      名字硬塞进各龟系统文件的文本里, 可能误改到同名的局部标识符。
    """
    for k, v in bc.items():
        text = text.replace('battle.' + k, v)
    return text


## 代码效果 → 人话。每条 = (正则, 格式化函数, 效果类别)
## 类别用于「代码→文案」对账: 文案里必须出现该类别的任一关键词, 或登记进 HIDDEN。
EFFECT_RULES = [
    (r'_atk_dmg\([^,]+,\s*([\d.]+)[^)]*\)',
     lambda m: '伤害 %s×攻击力' % m.group(1), 'dmg'),
    (r'_apply_damage_from\([^,]+,\s*[^,]+,\s*int\(([^)]*maxHp[^)]*)\)',
     lambda m: '伤害 按最大生命: %s' % m.group(1).strip(), 'dmg'),
    (r'_apply_damage_from\([^,]+,\s*[^,]+,\s*int\(([^)]*\["hp"\][^)]*)\)',
     lambda m: '伤害 按当前生命: %s' % m.group(1).strip(), 'dmg'),
    (r'_add_curse\([^,]+,\s*([\d.]+)',
     lambda m: '诅咒 %s 秒 (每秒 5%% 目标最大生命真伤·无视双抗)' % m.group(1), 'curse'),
    (r'_apply_dot_stacks\([^,]+,\s*"([a-z]+)",\s*([^,]+),',
     lambda m: 'DoT %s %s 层' % (m.group(1), m.group(2).strip()), 'dot'),
    (r'_stun\(([^,]+),\s*([\d.]+)',
     lambda m: '眩晕/定身 %s 秒  ← 对象 %s' % (m.group(2), m.group(1).strip()), 'stun'),
    # ★距离为 0 的不算击退 —— 那是"轻击飞"的实现方式(_knockback(u,t,0.0,vy,..)),
    #   双头·融合 和 星际·扭曲空间 都是这么写的。第一版把它们报成"文案没写击退"= 误报。
    (r'_knockback\([^,]+,\s*[^,]+,\s*((?!0\.0)[\d.]+)',
     lambda m: '击退 %s' % m.group(1), 'knock'),
    (r'_knock_up\([^,]+,\s*[^,]+,\s*([\d.]+)',
     lambda m: '击飞 vy=%s' % m.group(1), 'knockup'),
    (r'_grant_shield\(([^,]+),\s*([^,]+?)(?:,\s*([\d.]+))?\)',
     lambda m: '护盾 %s%s' % (m.group(2).strip(),
                             (' 持续 %s 秒' % m.group(3)) if m.group(3) else ' (不限时)'), 'shield'),
    (r'_heal\(([^,]+),\s*([^,)]+)',
     lambda m: '回复 %s' % m.group(2).strip(), 'heal'),
    (r'energy_lock_until"\]\s*=\s*[^+]*\+\s*([\d.]+)',
     lambda m: '锁龟能 %s 秒 (期间不充能)' % m.group(1), 'elock'),
    (r'cc_immune_until"\]\s*=\s*[^+]*\+\s*([\d.]+)',
     lambda m: '免疫控制 %s 秒' % m.group(1), 'ccimm'),
    # ★倍率 >1 是【加速】(凤凰强化涅槃 ×1.5 / 熔岩爆发 ×1.3), <1 才是减速。
    #   第一版一律归成 'slow' 去查"减速"关键词 → 两处误报。
    (r'spd_move_mult"\]\s*=\s*(0\.[\d]+)',
     lambda m: '移速 ×%s (减速)' % m.group(1), 'slow'),
    (r'spd_move_mult"\]\s*=\s*(1\.[\d]+)',
     lambda m: '移速 ×%s (加速)' % m.group(1), 'haste'),
    (r'_buff\([^,]+,\s*"([a-z_]+)",\s*(-?[\d.]+),\s*(true|false),\s*([\d.]+)',
     lambda m: 'buff %s %s%s 持续 %s 秒' % (
         m.group(1), m.group(2),
         '(百分比)' if m.group(3) == 'true' else '(定值)', m.group(4)), 'buff'),
    (r'_add_stack\([^,]+,\s*"([a-z]+)",\s*([\d]+),\s*([\d]+)',
     lambda m: '叠层 %s +%s (上限 %s)' % (m.group(1), m.group(2), m.group(3)), 'stack'),
    # ── 以下是【训龟大师】那套写法(2026-07-30 需求3 加的) ───────────────────────
    # ★大师的效果基本【不走 _stun/_buff 这些函数】, 而是直接写单位字段, 数值再由
    #   _mitigate_incoming / 移动结算 那边读。所以龟那套规则一条都对不上 ——
    #   第一版七技抽出来一共 0 条效果, 看着像"大师没有任何效果"。
    (r'haste_mult"\]\s*=\s*([\d.]+)',
     lambda m: '攻速 ×%s' % m.group(1), 'aspd'),
    (r'move_buff_mult"\]\s*=\s*([\d.]+)',
     lambda m: '移速 ×%s' % m.group(1), 'haste'),
    (r'echarge_mult"\]\s*=\s*([\d.]+)',
     lambda m: '龟能充能 ×%s' % m.group(1), 'echarge'),
    (r'slow_mag"\]\s*=\s*([\d.]+)',
     lambda m: '减速至 ×%s' % m.group(1), 'slow'),
    # 易伤: 只写"到什么时候", 倍率是另一个常量(HOOK_VULN/HUNT_VULN/…), 在 _mitigate_incoming 读。
    # 所以这里只报"有易伤", 具体倍率靠人工/verify_trainer_desc 核 —— 不假装抽到了倍率。
    (r'([a-z_]*)vuln_until"\]\s*=',
     lambda m: '易伤(受伤加成·倍率在 _mitigate_incoming 里读)', 'vuln'),
    (r'hunt_until"\]\s*=\s*[^+]*\+\s*([\d.]+)',
     lambda m: '猎龟令标记 %s 秒' % m.group(1), 'mark'),
    (r'tame_pending"\]\s*=\s*true',
     lambda m: '驯服标记(死亡时改判归顺而非真死)', 'tame'),
]

## 效果类别 → 文案里应出现的任一关键词
CATEGORY_WORDS = {
    'curse': ['诅咒'],
    'dot':   ['灼烧', '中毒', '流血', '层'],
    # ★"束缚""不能攻击或移动"都是眩晕/定身的同义表达 —— 泡泡束缚与缩头就是这么写的,
    #   第一版没收这两个词 → 误报成"文案没写眩晕"。
    'stun':  ['眩晕', '定身', '石化', '冰封', '僵直', '不可移动', '束缚', '不能攻击或移动', '不能移动'],
    # ★关键词表要收【文案实际的说法】, 不是我以为的说法(2026-07-30 逐条对完 14 处误报才校准):
    #   · 文案普遍把 _knockback 写成"击飞"而不是"击退"(石头磐石之躯/竹刺阵)
    #   · 写"移动速度"而不是"移速"(竹击/强化涅槃/熔岩爆发)
    #   · 写"龟能才重新开始充能"而不是"不充能"(石头嘲讽)
    #   收窄关键词 = 制造假警报, 而假警报多了这审计器就废了。
    'haste': ['移速', '移动速度', '加速', '疾行'],
    'knock': ['击退', '推开', '弹开', '击飞', '推'],
    'knockup': ['击飞', '挑空', '浮空', '滞空', '卷入', '吸引'],
    'shield': ['护盾', '盾'],
    'heal':  ['回复', '治疗', '回血', '吸血', '偷取'],
    'elock': ['锁龟能', '龟能锁', '锁定龟能', '不充能', '龟能锁定', '重新开始充能', '重新充能'],
    'ccimm': ['免疫控制', '免控', '霸体'],
    'slow':  ['减速', '移速', '移动速度'],
    'stack': ['层', '印记', '标记'],
    # ── 训龟大师那几类(2026-07-30) ──
    'aspd':    ['攻速', '攻击速度'],
    'echarge': ['龟能充能', '充能', '龟能'],
    'vuln':    ['受伤', '易伤', '承受', '受到伤害'],
    'mark':    ['锁定', '标记', '猎'],
    'tame':    ['归顺', '驯服', '重生', '不真死'],
}


def effects_of(src, fname, depth=2):
    """→ [(函数名, 人话, 类别), ...] 去重后的效果清单。"""
    path, bodies, consts = func_scope(src, fname, depth)
    if bodies is None:
        return None, []
    bc = battle_consts(src)
    out = []
    seen = set()
    for fn, body in bodies:
        t = expand_consts(expand_cross(body, bc), consts)
        for pat, fmt, cat in EFFECT_RULES:
            for m in re.finditer(pat, t):
                try:
                    line = fmt(m)
                except Exception:
                    continue
                key = (line, cat)
                if key in seen:
                    continue
                seen.add(key)
                out.append((fn, line, cat))
    return path, out
