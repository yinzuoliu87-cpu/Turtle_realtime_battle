# -*- coding: utf-8 -*-
"""龟技能文案数值 ↔ 代码 对账 (2026-07-30)。

★为什么必须有这个 —— 用户 2026-07-30:「不只是无头龟有这问题啊，所有龟、装备、
  训龟大师技能都有问题怎么办呢」。他是对的, 而且我之前报"文案全绿"是误导:

  | 域          | 原有门禁                | 实际覆盖 |
  |-------------|------------------------|---------|
  | 装备        | tooltip_number_audit   | 只查 a/b/c 三元组(星级档); 单值错抓不到 |
  | 训龟大师     | verify_trainer_desc    | 23 个【手工列举】的片段, 新数值不自动纳入 |
  | 龟技能      | 【无】                  | ← 洞在这里 |

  实证: 无头·灵魂打击 文案写「0.9×攻击力 物理 + 20%目标当前生命值」,
  代码是「0.5A 魔法 + 10%当前生命」—— 伤害差一倍、类型也错, 而且文案完全没提
  第 3 段的镰刀横扫(击退300码 + 5秒诅咒)。四轮门禁全绿都没发现。

★判据: 文案里的 {N:x*ATK} / {M:...} / {T:...} / {H:...} / {S:...} / {D:...} 占位符
  是【机器可读】的 —— 取出系数, 到该技能的实现函数体里找。找不到就报。

★这是"存在性"检查不是"语义"检查: 只保证"文案宣称的系数在代码里出现过"。
  它抓不到"系数用在了错的地方", 但足以抓住无头那类"数值根本不是这个数"。

★白名单机制: 有些系数确实在别处(共享常量/别的文件/演出参数)。
  人工核过就登记进 VERIFIED, 附上核对结论 —— 与 tooltip_number_audit 同套路。

跑法: python tools/pet_number_audit.py
"""
import io, sys, os, json, re, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pet_code_scope as S
import derived_consts

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

BS = chr(92)
PH = re.compile(r'\{([A-Z]):([^}]+)\}')
PURE = re.compile(r'^([\d.]+)\*ATK$')

# 人工核实过的例外: (龟id, 技能名, 系数) → 核对结论。
# ★写进来的必须【真的核过】—— 白名单是"我看过了, 是对的", 不是"报错太烦关掉它"。
VERIFIED = {
    ('dice', '稳定骰子', '0.9'):
        '核过(2026-07-30): 在 _dice_dash_tick 里 —— 那是【逐帧驱动的状态机】,'
        ' 不在入口函数的调用链上, 所以本审计器跟不进去。'
        ' dice_system.gd:70 `0.9 * pow(0.9, seg)` 与文案「首段 90%×攻击力, 之后每段递减 10%」一致。',
    ('crystal', '水晶壁垒', '1.5'):
        '核过(2026-07-30): 在 _crystal_spike_line 里(水晶刺真伤), 那是通过 _pending_shots'
        ' 的【延时回调】调的, 调用链跟不进去。crystal_system.gd:351'
        ' `uu["atk"] * 1.5` 与文案「命中敌人受到 150%×攻击力 真实伤害」一致。',
}


## ══ 「故意不给玩家看」登记表 ══
##
## 由来 (用户 2026-07-30):「有些细节不应该让玩家看到的, 但你在看技能时应该以代码的
##   实际效果来向我汇报, 这怎么办」。答案是把两件事分开:
##     · 玩家文案 = 设计决定, 有些效果【故意不写】(写进 tooltip 只会让人困惑)
##     · 我做分析 = 一律跑 tools/pet_effect_dump.py 看代码真实效果, 不读 tooltip
##
## 所以本表的判据是: 代码里的每个效果, 要么【写进玩家文案】, 要么【登记在这里 + 写明理由】。
##   忘写 → 红。故意隐藏 → 登记一次不再报。
## ★这张表本身就是一份「哪些细节对玩家隐藏了」的清单 —— 它有独立价值, 不只是消警告。
HIDDEN = {
    ('basic', '龟派气波', 'stun'):
        '对【自己】定身 0.6 秒, 是掌心聚气动画期间的实现细节(_stun(u, 0.6, ...))。'
        ' 写进 tooltip 只会让玩家以为自己会被眩晕。',
    ('space', '星波', 'elock'):   # ★龟 id 是 space 不是 star(名字叫星际龟, 容易写错)
        '施法期锁龟能 2.6 秒, 代码注释原话「施法锁龟能·爆发/拽完提前恢复·兜底防永锁」——'
        ' 是施法过程的实现细节, 不是设计给玩家算的代价。',
    ('space', '扭曲空间', 'elock'):
        '同上: 施法期锁, 爆发完提前恢复。',
}


def load_src():
    src = {}
    for base in ('scripts',):
        for root, dirs, files in os.walk(base):
            for fn in files:
                if fn.endswith('.gd'):
                    p = (root + '/' + fn).replace(BS, '/')
                    src[p] = io.open(p, encoding='utf-8', errors='ignore').read()
    return src


def _one_body(s, fname):
    m = re.search(r'^func ' + re.escape(fname) + r'\(', s, re.M)
    if not m:
        return None
    nxt = re.search(r'^func ', s[m.end():], re.M)
    end = m.end() + (nxt.start() if nxt else len(s) - m.end())
    return s[m.start():end]


def func_body(src, fname, depth=2):
    """取 fname 的【搜索域】= 它自己的函数体 + 它(递归)调用的同文件函数体。

    ★为什么要跟进子函数(2026-07-30 修): 第一版只读入口函数, 结果 15 处全是误报 ——
      伤害普遍写在子函数里(冰霜 0.18 在 _ice_frost_tick / 水晶刺 1.5 在 _crystal_spike_line /
      碎晶在 _pending_shots 的 lambda 里)。噪声大的审计器等于没有(会被当狼来了忽略)。
    """
    for p, s in src.items():
        body = _one_body(s, fname)
        if body is None:
            continue
        scope = body
        seen = {fname}
        frontier = [body]
        for _ in range(depth):
            nxt = []
            for b in frontier:
                for callee in set(re.findall(r'(?<![A-Za-z0-9_])(_[a-z][a-z0-9_]*)\s*[\(.]', b)):
                    if callee in seen:
                        continue
                    sub = _one_body(s, callee)
                    if sub is None:
                        continue
                    seen.add(callee)
                    scope += chr(10) + sub
                    nxt.append(sub)
            frontier = nxt
        # ★展开同文件的具名常量: 冰封写的是 FREEZE_DMG 不是 2.5
        # ★★2026-08-22 接 derived_consts: 只认「const X := 纯数字」会把**推导式**常量
        #   (BURN_SLOW_MULT := 1.0 - BURN_SLOW_PCT) 留成常量名 ⇒ 这里读成 ×1.0,
        #   把「减速 20%」报成了「加速」(本审计器实测报过这一条)。推导是正确设计,
        #   为了迁就工具而在代码里再手写一个 0.8 才是我在根除的那类病。
        cmap = derived_consts.derive(s, derived_consts.numeric_consts(s))
        for _nm in sorted(cmap.keys(), key=len, reverse=True):   # 长名先替, 免得 A 吃掉 AB 的前缀
            scope = scope.replace(_nm, cmap[_nm])
        return p, scope
    return None, None


def main():
    d = json.load(io.open('data/pets.json', encoding='utf-8'))
    pets = d if isinstance(d, list) else next(v for v in d.values() if isinstance(v, list))
    src = load_src()
    rb = src.get('scripts/scenes/RealtimeBattle3DScene.gd', '')

    # 技能 type → 实现函数名 (从主文件的 match 分派表里抓)
    dispatch = {}
    for m in re.finditer(r'"([a-zA-Z]+)":\s*(?:_[a-z_0-9]+\.)?(_sk_[a-z_0-9]+)', rb):
        dispatch[m.group(1)] = m.group(2)

    n_ph = n_ok = n_bad = n_skip = 0
    bad = []
    nomap = collections.Counter()
    for p in pets:
        pid = str(p.get('id', ''))
        for s in p.get('skillPool', []):
            ty = str(s.get('type', ''))
            nm = str(s.get('name', ''))
            text = str(s.get('brief', '')) + ' ' + str(s.get('detail', ''))
            coefs = set()
            for m in PH.finditer(text):
                mm = PURE.match(m.group(2).strip())
                if mm:
                    coefs.add(mm.group(1))
            if not coefs:
                continue
            fname = dispatch.get(ty)
            if fname is None:
                nomap[ty] += 1
                n_skip += len(coefs)
                continue
            path, body = func_body(src, fname)
            if body is None:
                nomap[ty] += 1
                n_skip += len(coefs)
                continue
            for c in sorted(coefs):
                n_ph += 1
                if (pid, nm, c) in VERIFIED:
                    n_ok += 1
                    continue
                # 系数在函数体里出现即算对上 (0.9 / 0.90 / .9 都认)
                num = c.rstrip('0').rstrip('.') if '.' in c else c
                pat = r'(?<![\d.])' + re.escape(num) + r'0*(?![\d])'
                if re.search(pat, body):
                    n_ok += 1
                else:
                    n_bad += 1
                    bad.append((pid, nm, c, fname, path))

    print('=== ① 文案宣称的数值 → 代码里有没有 ===')
    print('  可对账占位符 %d 个 · 对上 %d · 对不上 %d · 跳过(无法映射) %d'
          % (n_ph, n_ok, n_bad, n_skip))
    if nomap:
        print('  未能映射到 _sk_* 的 type(多为普攻, 走 BASIC_ATK 表): %d 种'
              % len(nomap))
    print('')
    if bad:
        print('[CHECK] 文案宣称的系数在实现函数里找不到: %d 处' % len(bad))
        print('        (人工核过后, 要么改文案/代码, 要么登记进 VERIFIED 并写结论)')
        for pid, nm, c, fn, path in bad:
            print('   %-10s %-12s 系数 %-6s  ← %s()  %s'
                  % (pid, nm, c, fn, path.replace('scripts/', '')))
        print('')
        print('NEEDS REVIEW: %d' % len(bad))
        sys.exit(1)
    # ══ ② 反向: 代码有的效果, 文案有没有提 ══
    #    ★这一节抓的是【漏写】, 与①的【写错】互补。
    #    实证: 无头·灵魂打击 代码里有镰刀横扫的 5 秒诅咒 + 全程锁龟能, 文案一个字没写 ——
    #    ①那一节永远抓不到这种(文案里根本没有这个数, 自然"没有对不上")。
    print('')
    print('=== ② 代码有的效果 → 文案有没有提 ===')
    n_eff = n_miss = 0
    miss = []
    for p in pets:
        pid = str(p.get('id', ''))
        for sk in p.get('skillPool', []):
            fname = dispatch.get(str(sk.get('type', '')))
            if fname is None:
                continue
            nm = str(sk.get('name', ''))
            text = str(sk.get('brief', '')) + ' ' + str(sk.get('detail', ''))
            _, effs = S.effects_of(src, fname)
            for _fn, line, cat in effs:
                words = S.CATEGORY_WORDS.get(cat)
                if words is None:
                    continue
                n_eff += 1
                if any(w in text for w in words):
                    continue
                if (pid, nm, cat) in HIDDEN:
                    continue          # 故意不给玩家看(登记过, 附理由)
                # ★共用实现函数的技能: 一个效果可能属于【兄弟技能】而不是这一个。
                #   实证: 熔岩·地裂 与 岩浆涌动 都分派到 _sk_lava_cast —— 岩浆涌动的护盾
                #   被算到地裂头上了。只要同一函数下【任一】兄弟技能的文案提了, 就不算漏。
                sibs = [x for x in p.get('skillPool', [])
                        if dispatch.get(str(x.get('type', ''))) == fname]
                if len(sibs) > 1:
                    alltext = ' '.join(str(x.get('brief', '')) + str(x.get('detail', ''))
                                       for x in sibs)
                    if any(w in alltext for w in words):
                        continue
                n_miss += 1
                miss.append((pid, nm, cat, line))
    print('  可对账效果 %d 条 · 文案未提且未登记 %d 条 · 已登记「故意隐藏」%d 条'
          % (n_eff, n_miss, len(HIDDEN)))
    if miss:
        print('')
        print('[CHECK] 代码有这些效果, 但玩家文案没写、也没登记进 HIDDEN: %d 处' % len(miss))
        print('        → 要么补进文案, 要么登记进 HIDDEN 并写明为什么不给玩家看')
        for pid, nm, cat, line in miss:
            print('   %-10s %-12s [%-7s] %s' % (pid, nm, cat, line))
        print('')
        print('NEEDS REVIEW: %d' % len(miss))
        sys.exit(1)
    print('')
    print('ALL OK — 龟技能文案与代码【双向】一致(①数值没写错 ②效果没漏写)')


if __name__ == '__main__':
    main()
