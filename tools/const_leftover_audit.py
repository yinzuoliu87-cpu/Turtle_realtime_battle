# -*- coding: utf-8 -*-
"""抽了常量, 但**还有地方留着那个裸数字** —— 多半是"接了一处漏了另一处"。

由来(2026-08-24): `text_const_orphan_audit` 只证明"有人读这个常量", 不证明
"该读的都读了"。一个效果写在三处、只接了一处, 孤儿门禁照样全绿 ——
剩下两处继续用裸字面量, 改常量时它们不跟着动, **分歧就是这么产生的**。

第一版只查常量自己那个文件, 当场抓到 4 处真漏接:
  · 双头灵能冲击: **特效环**用了 STRIKE_BLAST_RADIUS, **伤害判定**还是裸 200.0
    ⇒ 改常量会挪环但不挪伤害范围。
  · 蛋糕蜡烛: 携带者那份接了, **友军那份**没接(连 ×0.5 也是裸的)。
  · 熔岩喷发每命中回血 0.08 / 岩浆池存活 5.0。
之后扩成【全仓】—— 散到主场景 / battle_* 的漏接, 只查同文件一条都抓不到。

## 判据是怎么调出来的(两轮都记着, 别再走一遍)
· 第一版"同文件同值裸数字" ⇒ 215 条, 太宽。
· 加黑名单滤演出行 ⇒ 145 条, **抽样四条全是巧合**
  (_world_pos(0.80) 高度 / _shake(0.06) 震屏 / _knockback 抛物线参数 / range(4) 粒子数)。
· 改成**白名单只认玩法消费点**(SINK) ⇒ 28 条, 其中 4 条是真的。
  ★宽一格造假 bug, 窄一格放过真 bug —— 判据要刚好卡住"这个数被当玩法数值用了"。
· 扩全仓时再加一层【同一主体】: 别的文件里那行, 往回 40 行必须提到这只龟/这类装备,
  否则 4.0 / 0.5 满仓都是, 真的会被淹掉。

这是**嫌疑扫描**不是门禁 —— 报出来的每条都要人看一眼, 不许靠调阈值消掉。

    python tools/const_leftover_audit.py            # 列嫌疑
    python tools/const_leftover_audit.py --verbose  # 连文件行号一起列
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSONS = ['data/pets.json', 'data/phase2-equipment.json']

# 这些值太常见, 同值几乎必然是巧合(颜色分量/一半/归一化)。
COMMON = {'0', '1', '2', '3', '0.0', '1.0', '2.0', '0.5', '100', '100.0', '0.25', '0.1'}

# 一眼就是"演出"的行 —— 这些行里的数字不是玩法数值。
VFXY = re.compile(
    r'Color\(|modulate|tween|\.scale|pixel_size|position|rotation|_vfx|_ring\(|'
    r'randf_range|lerpf?\(|\.alpha|render_priority|no_depth|billboard|'
    r'set_trans|set_ease|_flash\(|emitting|amount|_pop\(|_text\(')

# 玩法数值真正被消费的地方 —— 只有这些行里的同值才值得怀疑。
## ★这条白名单第一版漏了【计时器/阈值比较】, 反向验证当场打脸:
##   把泡泡龟被动周期改回裸 5.0(`if u["_bbtimer"] >= 5.0:`), 扫描**一声不吭** ——
##   因为那行既不调伤害函数也不碰 maxHp。窄一格就放过真 bug。
SINK = re.compile(
    r'_apply_damage_from\(|_apply_damage\(|_atk_dmg\(|_mitigate\(|_buff\(|'
    r'_grant_shield\(|_heal\(|_stun\(|_freeze\(|_add_stack\(|_add_curse\(|'
    r'_grant_energy\(|_t \+ |distance_to\([^)]*\)\s*[<>]|'
    r'\bmaxHp\b|_knock_up\(|_taunt\(|'
    r'\]\s*[<>]=?\s*[0-9]|'          # 状态字段跟数比: u["_bbtimer"] >= 5.0
    r'[<>]=?\s*[0-9.]+\s*:|'         # if ... >= 5.0:
    ## ★2026-09-14 补第三类: **演出侧把"效果半径"换算成世界单位**的那个调用。
    ##   由来: 071 炼乳罐的 `cream_burst()` 里写着 `range_m(300.0)`, 而判定用的是
    ##   `CREAM_BURST_R = 300.0` —— 同一个数两份, 改一个不改另一个就是"环画的范围
    ##   和真打的范围对不上"。这条扫描**一声不吭**, 因为 `range_m(` 既不调伤害函数
    ##   也不碰 maxHp, 落不进上面任何一类。
    ##   `range_m()` 的定义就是「码 → 世界单位」⇒ 出现在它里面的裸字面量**必然**是
    ##   一个玩法半径写了第二遍, 不会有巧合。窄一格就放过真 bug(段头那条教训)。
    r'range_m\(')

## 跨文件嫌疑的白名单: **逐条人工定性过是巧合同值**, 写清那行到底在做什么。
## ★加白名单前必须真的去读那一行 —— 白名单是"我看过了", 不是"我懒得管"。
CROSS_OK = {
    ('BubbleSystem', 'FOAM_STORE_PCT'):
        'RealtimeBattle3DScene:7114 `if bs >= 1.0` 是泡泡值的空值守卫(攒够 1 点才触发), '
        '跟"储存 100%"没关系。',
    ('CrystalSystem', 'SPIKE_SLOW_SEC'):
        'equip_system:1557-1558 是【迷你水晶球装备】自己的 p2crystal 层数上限 3, '
        '跟水晶龟冰刺的减速秒数无关(两套机制同值)。',
    ('CyberSystem', 'MECH_BLAST_CD'):
        'RealtimeBattle3DScene:7040 `_ai_dodge_cd = _t + 2.5` 是通用 AI 闪避冷却, '
        '不是机甲爆的冷却。',
    ('IceSystem', 'TEAM_BURST_RADIUS'):
        'equip_system:176 是某件装备护盾三档 [100,160,250] 里的 250, 数组元素撞值。',
    ('StarSystem', 'BOLT_CURHP'):
        'RealtimeBattle3DScene:4828 `if el < 0.05` 是浮点精度阈值 —— 与 WORM_BOOM_PER_SEC '
        '撞的是同一行(两个常量恰好同值 0.05)。',
    ('StarSystem', 'WORM_BOOM_PER_SEC'):
        'RealtimeBattle3DScene:4828 `if el < 0.05` 是浮点精度阈值, 不是每秒引爆比例。',
}

REF = re.compile(r'\{C:([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)%?\}')

## ══════════════════════════════════════════════════════════════════
##  §RANGE_M —— 独立规则: `range_m(` 里不许有裸字面量 (2026-10-02)
## ══════════════════════════════════════════════════════════════════
## 【为什么要独立成一条】`range_m\(` 2026-09-14 就加进了上面的 SINK 白名单, 方案书
## `20260914c` 也登记着「反向验证: 把 300 硬写回去, 扫描必须报出来」——
## **今天真去反向验证, 它一声不吭。**
##
## 根因不在 SINK, 在它后面那两道: 上面那套扫描只认**文案里 `{C:...}` 引用过的常量**,
## 而且跨文件命中还要过 `related()`(行的上下文必须提到那个常量的主体)。
## 一个画在 vfx 文件里的裸半径, 上下文通常不提 `food_batch`/`BOX` ⇒ **被过滤掉**。
## ⇒ 那条登记写的是"能查出", 实际查不出。补成独立规则。
##
## 【判据形状】`range_m()` 的定义就是「码 → 世界单位」, 出现在它里面的裸字面量
## **要么是玩法半径写了第二遍, 要么是纯演出尺寸** —— 后者必须逐条写明理由,
## 照 CROSS_OK 的成例(白名单是"我看过了", 不是"我懒得管")。
RANGE_M = re.compile(r'range_m\(\s*(-?[0-9]+(?:\.[0-9]+)?)\s*[,)]')
RANGE_M_OK = {
    ('food_eq_vfx.gd', '70.0'):
        '070 压舱咸鱼砖的水花【冠本体】尺寸, 不是玩法半径 —— 玩法的 250 码由 brick_wave '
        '冲击环表达(环恒速扩到 250 码, 碰到谁谁那一刻掉血; 2026-08-11 用户拍板), '
        '而冠只是落点读数。同函数的注释里写着这件事。',
}


def check_range_m(srcs):
    """返回 [(文件名, 行号, 值, 整行)] —— 不在白名单里的裸半径。"""
    bad = []
    n_scan = 0
    for p, s in sorted(srcs.items()):
        base = os.path.basename(p)
        for i, ln in enumerate(s.split('\n'), 1):
            st = ln.strip()
            if st.startswith('#'):
                continue
            code = ln.split('#')[0]
            for m in RANGE_M.finditer(code):
                n_scan += 1
                if (base, m.group(1)) in RANGE_M_OK:
                    continue
                bad.append((base, i, m.group(1), st[:92]))
    return bad, n_scan


def subject_of(fname):
    """常量属于哪个"主体"(哪只龟 / 哪类装备): two_head_system.gd -> two_head。"""
    b = fname[:-3]
    for suf in ('_system', '_batch'):
        if b.endswith(suf):
            b = b[:-len(suf)]
    return b[3:] if b.startswith('eq_') else b


## 主体名太泛的文件: 跨文件相关性建立不起来(它们本来就服务全场), 只查同文件。
VAGUE = {'basic_consts', 'equip', 'equip_tick', 'equip_stats_apply', 'realtimebattle3dscene'}


OWNER_LINE = re.compile(r'\["id"\]\s*==|^func\s|^"[a-z_]+":')


def related(lines, idx, subject, _prefix):
    """跨文件那行是否属于同一主体 —— 看它**在谁的块里**, 不看固定行数窗口。

    ★这里踩过两次:
      ① 拿常量前缀词(SHIELD / STACK / BURST ...)当相关性证据 —— 那些词满仓都是,
         等于没过滤(83 条跨文件嫌疑几乎全是噪声)。
      ② 改成"往回 40 行"窗口 —— 主场景那种上万行的文件里, 窗口照样会蹭到别的龟
         (BubbleSystem.SHIELD_SEC 撞上了一条跟泡泡龟无关的 `distance_to > 4.0`)。
    真正的归属是**控制它的那个分支**: 一路往上找缩进更浅的行, 第一条
    `u["id"] == "x"` / `match` 分支 / `func` 头, 就是它的主人。
    """
    if subject in VAGUE:
        return False
    cur = len(lines[idx]) - len(lines[idx].lstrip())
    k = idx - 1
    while k >= 0 and idx - k < 400:
        ln = lines[k]
        st = ln.strip()
        if st and not st.startswith('#'):
            ind = len(ln) - len(ln.lstrip())
            if ind < cur:
                low = st.lower()
                if OWNER_LINE.search(low):
                    # ★按【词】匹配, 不是子串: subject="ice" 会撞上 d**ice**_system,
                    #   于是骰子的护盾时长被当成冰瓶的周期(2026-08-25 实测假红两条)。
                    return re.search(r"(?<![a-z_])" + re.escape(subject) + r"(?![a-z_])", low) is not None
                cur = ind
        k -= 1
    return False

def walk_gd():
    for base in ('scripts', 'autoload'):
        for dp, _, fns in os.walk(os.path.join(ROOT, base)):
            for fn in fns:
                if fn.endswith('.gd'):
                    yield os.path.join(dp, fn)


def main():
    verbose = '--verbose' in sys.argv
    srcs = {p: io.open(p, encoding='utf-8', errors='replace').read() for p in walk_gd()}
    lines_of = {p: s.split('\n') for p, s in srcs.items()}
    owner = {}
    for p, s in srcs.items():
        m = re.match(r'class_name\s+(\w+)', s)
        if m:
            owner[m.group(1)] = p

    refs = set()
    for jp in JSONS:
        raw = io.open(os.path.join(ROOT, jp), encoding='utf-8').read()
        refs |= set(REF.findall(raw))

    print('=' * 68)
    print('  抽了常量却还有地方留着同值裸数字的【嫌疑】扫描(全仓)')
    print('=' * 68)
    print('  分母: 文案引用 %d 个常量 · 扫 %d 个 .gd' % (len(refs), len(srcs)))

    # ══════════════════════════════════════════════════════════════════
    #  ★★2026-10-01 提速: 把【与常量无关】的那部分从内层循环里提出来, 只做一次
    # ══════════════════════════════════════════════════════════════════
    # 由来: 门禁耗时表摊开 —— 本审计器 **411 秒**, 一个人就是整套门禁的墙钟地板
    #   (测试池 JOBS=8 只要 363 秒, 再加并行也下不去这 411)。CLAUDE.md 上次记的是 145 秒,
    #   两个月涨了 2.8 倍 —— 因为代价是 `受检常量数 × 全仓行数`, 两边都在长。
    #   实测规模: 192 个 .gd / 111,797 行 × 几百个常量 ≈ **四千万次行扫描**,
    #   而每行里那 5 个检查(注释 / const 声明 / 切注释 / VFXY / SINK)**与是哪个常量无关**,
    #   却被原样重复了几百遍。
    #
    # ⇒ 两步:
    #   ① 先过一遍全仓, 把过得了那 5 关的行留下来(`kept`)。
    #   ② 给留下来的行建「数值字面量 → 行」索引。每个常量只去看**真的含它那个数**的行,
    #      而不是全仓每一行。
    # ★判据一个字没动: 留下来的行、以及"值出现在这行"的判法, 与原来逐行跑出来的完全一致
    #   (索引用的就是原来那条 `(?<![\w.])…(?![\w.\d])` 的同一套边界规则)。
    #   验收标准是**输出逐字节相同**, 不是"看起来一样"。
    # ⚠ 负号要**两种都收**(2026-10-01 对账时当场抓到, 差了 1 处):
    #   原版找 `1.0` 时, `-1.0` 里的那个 `1.0` **是算命中的** —— 它的 lookbehind 是
    #   `(?<![\w.])`, 而减号既不是 \w 也不是 `.`, 过得去。
    #   第一版索引写成 `-?[0-9]...`, 把 `-1.0` 整个当一个 token ⇒ 查 `1.0` 就漏了
    #   (FANG_LIFESTEAL 原版 9 处、我这边 8 处, 就是这一条)。
    #   ⇒ 带符号与不带符号**各索引一份**: 这样 `pats` 里无论是 `1.0` 还是 `-5` 都查得到,
    #     而 `x-5` 这种(减号前面是 \w, 原版匹配不到 `-5`)也不会多收 —— 因为 lookbehind
    #     写在可选负号【之前】, 那种位置整体就不成立, 引擎会退到数字本身重试, 与原版一致。
    NUMTOK = re.compile(r'(?<![\w.])(-?)([0-9]+(?:\.[0-9]+)?)(?![\w.\d])')
    CONST_DECL = re.compile(r'const\s')
    kept = {}        # fp2 -> [(i, line, code)]
    index = {}       # 数值字面量 -> [(file_ord, fp2, i)]
    for _ord, (fp2, ls) in enumerate(lines_of.items()):
        rows = []
        for i, line in enumerate(ls):
            st = line.lstrip()
            if st.startswith('#') or CONST_DECL.match(st):
                continue
            code = line.split('#')[0]
            if VFXY.search(code) or not SINK.search(code):
                continue
            rows.append((i, line, code))
            toks = set()
            for sign, num in NUMTOK.findall(code):
                toks.add(num)
                if sign:
                    toks.add(sign + num)
            for tok in toks:
                index.setdefault(tok, []).append((_ord, fp2, i))
        kept[fp2] = {i: (line, code) for i, line, code in rows}
    print('  [分母] 预筛后剩 %d 行可疑(全仓 %d 行) · 索引到 %d 个不同数值'
          % (sum(len(v) for v in kept.values()),
             sum(len(v) for v in lines_of.values()), len(index)))

    ## §RANGE_M 先判 —— 它与常量表无关, 是独立的一条。
    rm_bad, rm_n = check_range_m(srcs)
    print('  [分母] `range_m(<裸字面量>)` 全仓 %d 处 · 白名单 %d 条 · 不在白名单的 %d 处'
          % (rm_n, len(RANGE_M_OK), len(rm_bad)))
    if rm_n == 0:
        print('  [FAIL] §RANGE_M: 一处都没扫到 —— 正则坏了, 这条是空检查')
        rm_bad.append(('—', 0, '—', '扫到 0 处'))
    for b, i, v, ln in rm_bad:
        print('  [FAIL] §RANGE_M %s:%d 裸半径 %s —— %s' % (b, i, v, ln))
        print('         (玩法半径请读判定侧那个常量; 确属纯演出尺寸就写进 RANGE_M_OK 并说明理由)')

    hits = []
    checked = 0
    for cls, const in sorted(refs):
        fp = owner.get(cls)
        if fp is None:
            cand = [p for p in srcs if os.path.basename(p) == cls + '.gd']
            if not cand:
                continue
            fp = cand[0]
        m = re.search(r'^\s*const\s+' + re.escape(const) + r'\s*:?=\s*(-?[0-9]+(?:\.[0-9]+)?)\s*(?:#|$)',
                      srcs[fp], re.M)
        if not m:
            continue          # 非纯数值(数组/推导式)不查
        val = m.group(1)
        if val in COMMON:
            continue
        checked += 1
        pats = {val}
        f = float(val)
        if f == int(f):
            pats.add(str(int(f)))
            pats.add('%.1f' % f)
        subject = subject_of(os.path.basename(fp))
        prefix = const.split('_')[0]

        # 只看**真的含这个数**的行。候选按 (文件顺序, 行号) 排 —— 与原来
        # `for fp2 in lines_of: for i in ls:` 的遍历顺序一致, 输出顺序不变。
        cand_set = set()
        for pt in pats:
            for ent in index.get(pt, ()):
                cand_set.add(ent)
        found = []
        for _ord, fp2, i in sorted(cand_set):
            if fp2 != fp and not related(lines_of[fp2], i, subject, prefix):
                continue
            found.append((os.path.basename(fp2), i + 1, kept[fp2][i][0].strip()[:96]))
        if found:
            hits.append((cls, const, val, os.path.basename(fp), found))

    print('  受检: %d 个纯数值常量(数组/推导式/太常见的值不查)' % checked)
    if checked < 60:
        print('  [FAIL] 受检数太少(%d < 60) —— 扫串了, 不是"干净"' % checked)
        return 1

    if not hits:
        print('  [ OK ] 没有嫌疑')
        print()
        print('ALL OK — 常量残留扫描')
        return 0

    cross = [(c, k, v, fn, [x for x in fd if x[0] != fn])
             for c, k, v, fn, fd in hits if any(x[0] != fn for x in fd)]
    print()
    print('  嫌疑 %d 个常量(其中 %d 个的嫌疑点在【别的文件】):' % (len(hits), len(cross)))
    for cls, const, val, fn, found in hits:
        mark = ' ★跨文件' if any(f != fn for f, _i, _l in found) else ''
        print('   %s.%s = %s  [%s]  %d 处%s' % (cls, const, val, fn, len(found), mark))
        if verbose:
            for fn2, i, ln in found[:4]:
                print('        %-26s %5d | %s' % (fn2, i, ln))

    ## ── 判红只判【跨文件】那批 ────────────────────────────────────────
    ##   为什么只判跨文件: 同文件的巧合太多(不同装备各自的 tick 周期撞值),
    ##   判红会逼着人去调阈值; 而跨文件是**看不见的风险** —— 数量小、稳定,
    ##   每条都能人工定性。同文件的留作提示, 每几批扫一眼。
    bad = [(c, k, v, fn, fd) for c, k, v, fn, fd in cross if (c, k) not in CROSS_OK]
    print()
    if bad:
        for cls, const, val, fn, found in bad:
            print('  [FAIL] %s.%s = %s 在【别的文件】还有同值裸数字:' % (cls, const, val))
            for fn2, i, ln in found[:3]:
                print('           %s:%d | %s' % (fn2, i, ln))
        print()
        print('FAIL x%d — 常量残留扫描(跨文件)' % len(bad))
        return 1
    if rm_bad:
        print()
        print('FAIL x%d — §RANGE_M 裸半径' % len(rm_bad))
        return 1
    if rm_bad:
        print()
        print('FAIL x%d — §RANGE_M 裸半径' % len(rm_bad))
        return 1
    print('  [ OK ] §RANGE_M: range_m() 里没有白名单外的裸半径')
    print('  [ OK ] 跨文件嫌疑 %d 条全部在白名单里(各有定性理由)' % len(cross))
    print('  提示: 同文件嫌疑 %d 条 —— 每几批扫一眼, 别积累' % (len(hits) - len(cross)))
    print()
    print('ALL OK — 常量残留扫描')
    return 0


if __name__ == '__main__':
    sys.exit(main())
