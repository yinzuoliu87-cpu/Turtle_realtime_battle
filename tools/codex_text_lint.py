# -*- coding: utf-8 -*-
"""图鉴文案体检 —— 判据不是我拍脑袋定的, 是从 489 条真实同类游戏文案里量出来的。

═══ 来源(2026-08-18 实抓, 去重后 489 条 / 14 款游戏) ═══
  Super Auto Pets 60 · Slay the Spire 45 · Risk of Rain 2 45 · Binding of Isaac 90
  Darkest Dungeon 30 · Noita 40 · Enter the Gungeon 80 · Dead Cells 70
  云顶之弈(中) · 金铲铲(中) · 明日方舟(中·银灰/陈) 等

═══ 从样本里量出来的共同规律 ═══
  1. **短**: 英文 11~18 词; 中文 明日方舟 15~50 字 / 金铲铲 12~20 字 / 云顶 45~85 字
  2. **不称呼玩家**: SAP / StS / 暗黑地牢 / 明日方舟 **零**第二人称;
     云顶用「携带者」、以撒用「Isaac」—— 都拿一个第三人称的名字顶替"你"
  3. **零评价词**: 14 款里 13 款的机制描述**没有一个**"强力/好用/推荐"
  4. **零教学**: 489 条里只有 **1 条**例外(SAP 蓝莓「Prioritize this for enemy random
     abilities」), 其余**没有一句**告诉玩家什么时候用、怎么配
  5. **数值全给死**: 阿拉伯数字 + %; 没有"少量/大量/略微/显著"这类模糊量词
  6. **条件在前效果在后**: 死亡细胞 73% / 明日方舟 / StS「Whenever…, draw 1 card」
  7. **风味话是【另一个字段】**: 死亡细胞的「One hit and you're dead.」是 flavor 行,
     和机制描述分开; 机制行里不掺形容词

═══ 用户 2026-08-18 的原话 ═══
  「图鉴所有的描述都不应该有 ai 味和教导玩家的味道」
  ⇒ "教导味" = 规律 4 的反面; "ai 味" = 规律 3、5 的反面(空泛吹捧 + 模糊量词)。

═══ ★★ 2026-08-19 的纠正: 我把"短"当成了目标, 砍掉的是机制 ═══
  用户: 「小龟的被动是只有普攻增伤吗, 龟派气波的智能冲刺该怎么说呢,
        你确定把关键信息改掉, **这是你学到的东西吗**」
  实测: 我按 60 字上限收完之后, **83 条简述比它自己的全文少讲了机制** ——
  小龟被动少了「龟盾」那半边、龟派气波少了施法期间三项增益和智能冲刺。
  **参考里那些文案短, 是因为那些游戏的机制本身就短**(SAP「Faint → 给一个随机友军
  +1/+1」一句话就是全部)。我们的技能有三四段机制, 把它砍到一句 = 玩家读不到真相。
  ⇒ **完整性是硬指标, 长度是软指标**: 先保证机制一条不少, 再靠删废字压短。
     长度上限从"违规"降级为"提示"; 新增硬判据【简述不许比全文少讲机制】。

跑法: python tools/codex_text_lint.py [--list]
"""
import io
import sys
import json
import re
import collections

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
import os as _os
sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))   # 让 `import gd_text_scan` 在任何 cwd 下都成
NL = chr(10)

# ── 判据 ────────────────────────────────────────────────────────────────
# 一句"简述"的字数上限。中文同类实测 12~85 字, 取 60 —— 比最宽松的云顶还宽一点,
# 因为我们一件装备常带 1/2/3 星三档数值。超过就是"讲不完的第二件事"。
# 简述字数【提示线】—— 超了只提示不算违规(见上面 2026-08-19 的纠正)。
# 真正的硬线是下面的"漏讲机制"。
BRIEF_MAX = 60

## 【漏讲机制】基线: 简述里没提、而它自己全文里有的效果类别数。
## 只许降不许升。40 是 2026-08-19 把被我砍掉的机制补回去之后的实测值 ——
## 这 40 条是**我改之前就存在的**老缺口(不是这次造成的), 留作下一轮的活。
MISS_MAX = 40
# 【全文档】的上限 —— 龟的 `detail`/`desc` 和装备的 `effectDesc1` 是**同一层东西**:
# 都是"点开看全部"里那份完整机制说明。原来给 detail 定 200、给装备定 400 是两套尺子,
# 那不是标准, 是我随手拍的。统一到 400(实测最长一件装备 329 字, 是真机制不是废话)。
DETAIL_MAX = 400

## 【明确豁免】超过上限但**经过复核认为该留**的全文, 连理由一起登记。
##
## ★为什么用名单而不是把上限调高: 调高上限是"把尺子改到能量过为止", 那不是标准;
##   名单摆在这里, 谁都能看见到底破了几个例、各是什么理由。
DETAIL_ALLOW = {
    ('龟技能', 'pirate/海盗船', 'detail'):
        '召唤物完整属性表(生命/攻击/双抗/攻速/射程)+ 三段行为, 删任何一段都会让玩家算不出账',
    ('龟技能', 'shell/暗影', 'detail'):
        '一个技能同时带主动与被动两套机制(潜影/暗影), 本身就是两条技能的信息量',
}

# 教导句: 直接告诉玩家该怎么打。489 条样本里只出现过 1 次。
# ⚠ 判据太宽第 11 次: 「优先」原本在名单里, 结果逮到的是
#   「护盾优先于生命值消耗」「优先攻击最近的敌人」—— 这是**机制说明**(结算顺序/选靶),
#   不是教玩家怎么打。只留真正带指导口气的组合词。
TEACH = ['建议', '推荐', '适合', '优先考虑', '建议优先', '记得', '注意', '尽量', '最好',
         '可以考虑', '不妨', '试试', '用来对付', '用于应对', '搭配', '配合使用',
         '效果更好', '更划算', '性价比', '值得', '别忘了', '需要注意']
# 评价词: 对自己强度下判断。样本里 13/14 款为零。
# ⚠ 同上: 「相当」逮到的是「相当于攻击力的 200%」(等于, 机制), 「万能」逮到的是
#   技能名【万能牌】。判据要卡住"对自己下评价"这个形状, 不是卡住这两个字。
JUDGE = ['强力', '极强', '很强', '强势', '核心地位', '至关重要', '非常', '极其',
         '相当强', '十分', '显著', '大幅', '极佳', '优秀', '出色', '爆发力', '恐怖',
         '无解', '逆天', '神级', '顶级']
# 模糊量词: 样本里数值一律给死, 没有一个"少量/大量"。
VAGUE = ['少量', '大量', '略微', '稍微', '轻微', '巨额', '海量', '若干', '一定量',
         '一定生命', '一定护盾', '不少', '很多', '极大地', '大幅度', '小幅']
# 第二人称: 样本里要么零, 要么用「携带者」这类第三人称顶替。
YOU = ['你的', '你会', '你能', '你可以', '玩家']
# 风味/吹捧从句: 机制行里不该出现的抒情
# 开发备注混进玩家文案 —— 实测抓到两条(赛博龟「尚未定义消耗方式与收益（待设计）」、
# 黄铜齿轮「（仅玩家/左队）…并飘字」)。这比"ai 味"更糟: 玩家读到的是我的 TODO。
# ★2026-08-19 补一类【改动史】词: 龟壳的被动里白纸黑字写着「强化觉醒已并入本被动」——
#   那是给我自己看的变更记录; 玩家读到只会疑惑「什么是强化觉醒, 我是不是错过了什么」。
#   同族还有 已合并/已移除/原为/现改为 —— 全是「这东西以前不是这样」的口气。
DEVNOTE = ['待设计', '待定', '尚未定义', '后续精修', '暂未', '待补', 'TODO', '飘字',
           '仅玩家', '左队', '右队', '占位', '未实现',
           '已并入', '已合并', '已移除', '已删除', '已改为', '现改为', '原为', '本次调整',
           # ★别的游戏的技能代号: 忍者龟的被动里写着「自动冲刺斩·亚索E式」、
           #   斩击的 detail 里写着「亚索E式自动冲刺斩」。那是我跟自己描述手感用的话,
           #   玩家读到只会莫名其妙 —— 而且把别家 IP 的角色名印在自己的图鉴里也不合适。
           '亚索', '英雄联盟', 'LOL', 'DOTA', '类似原神', 'Q式', 'W式', 'E式', 'R式',
           # ★★2026-09-28 补【在向玩家交代我们的开发状态】这一族。名单原来只有
           #   待设计/待定/尚未定义/未实现/TODO —— 而**一个字都不含这五个词**的
           #   「玩法开发中」「这招还在打磨」「暂按积分赛规则」照样印给玩家。
           # ★实证(同日): 有 agent 把「候选技**开发中**」改成「这招还在**打磨**」。
           #   玩家读到的信息**一个字没变**(都是"我们还没做完"), 而只搜「开发中」的
           #   名单会放它过去。⇒ 收「打磨」不是收一个近义词, 是收同一个**形状**。
           # ⚠ **故意不收「未解锁」**: 它是**陈述规则**(这格现在选不了),
           #   不是开发备注, 而且是 2026-09-28 实拍定下来的角标文案。
           #   收了会把 `skill_picker.gd` 一次打红 7 处全是误报。
           #   判据要卡的形状是「在向玩家交代我们的开发状态」,**不是**「听起来像还没做好」。
           '开发中', '打磨', '暂按', '暂锁', '还没做', '敬请期待', '未开放']
FLAVOR = ['越战越勇', '所向披靡', '势不可挡', '锐不可当', '战意', '热血',
          '令人', '仿佛', '宛如', '犹如']


## ══════════════════════════════════════════════════════════════════════
##  洞 ①：这个脚本一行 `.gd` 都不读 (2026-09-28 补)
## ══════════════════════════════════════════════════════════════════════
## 在此之前 `collect()` 只 `load()` **5 个 json**(pets / phase2-equipment / status /
## battle-rules / p2eq-types)。⇒ **屏幕上的字一条都没被查过**:
##   · `MainMenuScene.gd:1117`  「玩法开发中, 暂按积分赛规则」
##   · `BracketMapScene.gd:555` 「跨组总决赛还没做出来」
## 判据(DEVNOTE)没错, **扫描范围不含出问题的地方** ⇒ 永远绿。
##
## 取料走 `tools/gd_text_scan.py`(共享抽取器, `text_golden.py` 也从它取)——
## memory [[fb-hand-rolled-copies-drift]]: 两边各写一遍正则, 抄一次就永远落后。
GD_ROOTS = ['scripts', 'autoload']

## 【调试通道】的第二类: 整个文件都是 dev-only 工具的数据。
## `print()` 已经在 gd_text_scan 里按行排掉了, 但 VFXLAB 的逐件配置表是
## **一整张表的长注释串**(「★这一件没有任何战斗演出…每 6 秒一次的+3飘字」),
## 玩家永远看不到 —— 它自己头注第 4 行就写着 "dev-only 数据·不进正式对局",
## 全仓只有 `battle_vfx_lab.gd`(VFXLAB=1 才起) 读它。
## ⚠ 这是**按文件**的豁免, 所以必须写理由 + 打印条数, 涨了看得见。
GD_DEVTOOL = {
    'scripts/gamedata/vfxlab_cases.gd':
        'VFXLAB 调试台逐件配置表(头注自述 dev-only·只被 battle_vfx_lab.gd 读·VFXLAB=1 才起)',
}

## 存量台账 —— **脚本自己生成**(`--update`), 不手写死名单。
## 键是 `相对路径|原文`, **不含行号**: 7 个 agent 同时在改 scripts/, 按行号记
## 明天就全过期(而且"某行挪了两行"根本不是这条判据要抓的事)。
## ★换个说法蒙不过去: 键含**原文**, 所以「开发中」改成「打磨」是**新键**, 当场红。
GD_LEDGER = 'tools/_gd_devnote_ledger.json'

## 台账里那几条**为什么留着** —— 不写理由的豁免和放宽判据是一回事。
## (台账本身是脚本生成的; 这张表只给理由, 对不上号也不影响判定。)
## ★★2026-09-28 删掉了一条**已经烂掉**的理由(就是新加的「豁免体检」当场照出来的那条):
##     'BracketMapScene.gd|现在你这一组的冠军就是本周冠军 · 跨组总决赛还没做出来':
##         '「还没做」三个字被 verify_bracket_map.gd:407 钉着当判据…'
##   逐条核实过它**确实**不成立了, 不是"话挪了两行":
##     · `BracketMapScene.gd:627` 头注自述那句话缀的「跨组总决赛还没做出来」**已删**;
##     · `verify_bracket_map.gd:407` 自己写着「原来写的是 `et.find("还没做") >= 0`」
##       —— 那条**要求**开发状态词上屏的断言早改了(现在 :421 是反过来的黑名单)。
##   ⇒ 前提(判据钉着它)没了, 理由就该走。**留着它 = 这张表看着很周全而其实有一条是假的。**
GD_WHY = {
    'scripts/scenes/BracketMapScene.gd|待定':
        '这是**对阵表里那一格还没定下来**的玩家文案(TBD), 不是开发备注',
    'scripts/scenes/battle/battle_hud.gd|左队(友军)':
        '伤害统计面板的**真实列名**(玩家侧就叫左队/右队), 不是开发备注',
    'scripts/scenes/battle/battle_debug_arena.gd|左队(友军)': '调试场(DEBUG_EDIT)自己的标签, 不是玩家屏',
    'scripts/scenes/battle/battle_debug_arena.gd|右队(假人)': '调试场(DEBUG_EDIT)自己的标签, 不是玩家屏',
}


def gd_devnote():
    """→ (hits, stats)。`.gd` 里的开发备注: [(path, line, sink, word, text)]"""
    import gd_text_scan as G
    rows, st = G.scan(GD_ROOTS)
    hits = []
    st['skipped_devtool'] = 0
    ## 逐文件记豁免命中数 —— 给【按文件豁免烂掉了】那条 stale 检查当分母
    ## (文件被改名/删掉/内容清空 ⇒ 这一条豁免还挂着, 而它已经什么都不豁免了)。
    st['devtool_by_file'] = {f: 0 for f in GD_DEVTOOL}
    st['scanned_paths'] = set()
    for path, ln, sink, txt, why in rows:
        st['scanned_paths'].add(path)
        if path in GD_DEVTOOL:
            st['skipped_devtool'] += 1
            st['devtool_by_file'][path] = st['devtool_by_file'].get(path, 0) + 1
            continue
        if why:                      # 行内 `# devnote-ok: 原因`
            continue
        for w in DEVNOTE:
            if w in txt:
                hits.append((path, ln, sink, w, txt))
                break
    return hits, st


def gd_devnote_gate():
    """打分母 + 判台账。→ 退出码贡献(0/1)"""
    import json as _json
    import os as _os
    hits, st = gd_devnote()
    print('')
    print('=== `.gd` 屏幕文案里的开发备注(洞① · 2026-09-28 补上) ===')
    print('  [分母] 扫 %d 个 .gd · 抽出含中文的字符串字面量 %d 条'
          % (st['files'], st['lits']))
    print('         (跳过: 调试通道 print/push_* %d 条 · 三引号块 %d 行 · dev-only 工具表 %d 条)'
          % (st['skipped_debug'], st['skipped_block'], st['skipped_devtool']))
    for f, why in sorted(GD_DEVTOOL.items()):
        print('         [按文件豁免] %s (本轮豁免 %d 条) —— %s'
              % (f, st['devtool_by_file'].get(f, 0), why))
    if st['lits'] < 400:
        print('  [FAIL] 只抽到 %d 条字符串(<400) —— 取料失效了, 这是空检查不是通过' % st['lits'])
        return 1
    ledger = {}
    if _os.path.exists(GD_LEDGER):
        try:
            ledger = _json.load(io.open(GD_LEDGER, encoding='utf-8')).get('known', {})
        except Exception:
            ledger = {}
    cur = {}
    for path, ln, sink, w, txt in hits:
        cur['%s|%s' % (path, txt)] = {'line': ln, 'sink': sink, 'word': w}
    if '--update' in sys.argv:
        io.open(GD_LEDGER, 'w', encoding='utf-8', newline=NL).write(_json.dumps(
            {'_why': '本文件由 `python tools/codex_text_lint.py --update` 生成, 不要手改。'
                     '键 = 相对路径|原文(不含行号: 行号天天漂)。只减不增。',
             'known': dict(sorted(cur.items()))}, ensure_ascii=False, indent=1) + NL)
        print('  [台账已重写] %s (%d 条存量)' % (GD_LEDGER, len(cur)))
        return 0
    fresh = sorted(k for k in cur if k not in ledger)
    cleared = sorted(k for k in ledger if k not in cur)
    print('  [台账] %d 条存量(只减不增) · 本轮量到 %d 条' % (len(ledger), len(cur)))
    for k in sorted(cur):
        why = GD_WHY.get(k, '(理由未登记 —— 欠一条)')
        print('     %s:%-4d [%s] 「%s」 %s' % (k.split('|')[0], cur[k]['line'],
                                              cur[k]['word'], k.split('|', 1)[1][:44], why))
    for k in cleared:
        print('  [已清] %s —— 记得把它从台账里删掉(`--update`)' % k[:90])

    ## ══════════════════════════════════════════════════════════════════
    ##  【豁免自身的 stale 检查】—— 2026-09-28 补(照 asset_borrow 的 `[已清]` 样式)
    ## ══════════════════════════════════════════════════════════════════
    ## ★由来: `asset_borrow_audit` 会主动报「白名单里的 X 已经不跨屏了 —— 把那条理由删掉」,
    ##   而这里**不报** ⇒ 一条**烂掉的理由会一直留着**, 而且它长得跟有效的理由一模一样,
    ##   于是这张表**看着很周全**。memory [[fb-registered-todos-rot]] 那一族:
    ##   登记会烂, 而没有 stale 检查就等于给自己留一条**永远不会被发现已经过期**的账。
    ## ★实证(同日抓到): `GD_WHY` 里
    ##   `BracketMapScene.gd|现在你这一组的冠军就是本周冠军 · 跨组总决赛还没做出来`
    ##   —— 那句话早就改了, 命中里没有它, 而这条理由还挂着。
    ## ★为什么**只报不红**: 与 asset_borrow 同一口径。烂理由是"该去清一下", 不是
    ##   "屏幕上多了一句开发备注"; 拿它去红会让两件事共用一个红灯, 人只会去改判据。
    ##   ⚠ 但**必须打印**, 而且打印的是"删掉它"这个动作, 不是含糊的提示。
    stale_why = sorted(k for k in GD_WHY if k not in cur)
    stale_dev = sorted(f for f in GD_DEVTOOL if st['devtool_by_file'].get(f, 0) == 0)
    print('  [豁免体检] GD_WHY %d 条(其中已烂 %d) · 按文件豁免 %d 条(其中已烂 %d)'
          % (len(GD_WHY), len(stale_why), len(GD_DEVTOOL), len(stale_dev)))
    for k in stale_why:
        print('  [已烂·GD_WHY] %s' % k[:100])
        print('        这条理由对应的原文**已不在命中里**(话改了或删了) ⇒ 把它从 GD_WHY 删掉。')
    for f in stale_dev:
        gone = f not in st['scanned_paths']
        print('  [已烂·按文件豁免] %s —— %s ⇒ 把这条豁免删掉。'
              % (f, '文件已不在扫描范围里(改名/删了?)' if gone else '文件还在, 但本轮一条都没豁免到'))

    if fresh:
        print('')
        for k in fresh:
            print('  [FAIL] 新的开发备注上屏: %s:%d 「%s」 ← %s'
                  % (k.split('|')[0], cur[k]['line'], k.split('|', 1)[1][:60], cur[k]['word']))
        print('')
        print('  ★换个文雅说法不算解决 —— 台账的键含**原文**, 「开发中」→「打磨」是新键。')
        print('    判据卡的形状是「在向玩家交代我们的开发状态」。真是玩家该读的规则')
        print('    (例: 对阵表那格「待定」) ⇒ 在那一行写 `# devnote-ok: 原因`。')
        return 1
    return 0


## ★★已知失明(写在这儿是为了下一个人不会以为它全覆盖):
##   关键词名单**天生绕得过** —— 同义词是无穷的。「开发中→打磨」就是实证,
##   而「这块还在路上」「先这样」「后面会补」一条都拦不住。
##   ⇒ 降低失明的**不是**继续堆词, 而是**洞②的快照门禁**: 它不认识含义,
##     只要玩家看到的字变了就把新旧两版摆出来 ⇒ 改文案的人必须明确确认一次。
##     这两条是一对: 名单负责**当场拦住已知的形状**, 快照负责**让所有改动都露头**。
##
## ★★★「搜关键词」这类判据的失明是**两面**的, 两面都要记住:
##   ① **会漏**: 同义词绕得过(「开发中」→「打磨」→「这块还在路上」, 无穷)
##   ② **会假过**: 字符串在, 而行为是错的。同日实证 —— 商店「已拥有掠光溢出」
##      那个真 bug, 原有的 `_check_owned_shine` **四条判据全是 grep 源码**
##      (`shine.rotation = -0.5` 在不在), 溢出的那几天**一条都没红**。
##   ⇒ **字符串在不在, 和画出来的东西在哪, 是两件事。**
##     凡是「靠我列的名单/搜源码认形状」的判据, 都该先问一句:
##     **有没有一个客观事实可以代替我的名单?** 同日的好样本: 判「这是不是 emoji」
##     不靠眼睛也不靠 Unicode 区块表, 而是**问打包回退链里的三张字体文件谁有这个码点**
##     (只有 NotoEmoji 有 ⇒ 屏幕上就是另一套字画的)。那个 agent 第一版手写区块表,
##     176 次里误判了一大半。
##   本条判据目前**没有**这样的客观替代品(「这句话是不是在交代开发状态」是语义问题),
##   所以它必须和洞②的快照门禁配对使用, 而**不能**单独当成"文案没问题"的证明。


def load(p):
    d = json.load(io.open(p, encoding='utf-8'))
    return d if isinstance(d, list) else list(d.values())[0]


def collect():
    rows = []
    for p in load('data/pets.json'):
        pid = str(p.get('id', ''))
        pa = p.get('passive') or {}
        for k in ('brief', 'desc', 'detail'):
            v = str(pa.get(k, '') or '')
            if v:
                rows.append(['龟被动', pid, k, v])
        for grp in ('skillPool', 'volcanoSkills', 'meleeSkills'):
            for s in (p.get(grp) or []):
                for k in ('brief', 'detail', 'desc'):
                    v = str(s.get(k, '') or '')
                    if v:
                        rows.append(['龟技能', '%s/%s' % (pid, s.get('name', '')), k, v])
    for e in load('data/phase2-equipment.json'):
        for k in ('effectBrief', 'effectDesc1', 'effectDesc3'):
            v = str(e.get(k, '') or '')
            if v:
                rows.append(['装备', '%s/%s' % (e.get('id', ''), e.get('name', '')), k, v])
    for f, tag in [('data/status.json', '状态'), ('data/battle-rules.json', '规则'),
                   ('data/p2eq-types.json', '羁绊')]:
        for e in load(f):
            if not isinstance(e, dict):
                continue
            for k, v in e.items():
                if isinstance(v, str) and len(v) >= 8 and k not in (
                        'id', 'name', 'icon', 'color', 'img', 'emoji'):
                    rows.append([tag, str(e.get('id', e.get('name', ''))), k, v])
    return rows


def plain(t):
    """去掉占位符和标记, 只留玩家真正读到的字。

    ★不去掉的话字数会被 {N:0.6*atk} 这种模板撑大, 量出来的"太长"是假的。
    """
    t = re.sub(r'\{[A-Za-z]:[^}]*\}', '00', t)      # 数值占位符 → 当两个字
    t = re.sub(r'<[^>]+>', '', t)                    # html/bbcode
    return t


def mech_gaps():
    """简述比它自己的全文少讲了哪些机制。

    判据用 `pet_code_scope.CATEGORY_WORDS` —— 那张表是**按代码里真有的效果分类**建的,
    不是我临时想的词。全文里出现某类效果、简述里一个同类词都没有 = 玩家在默认那一屏
    读不到这条机制。
    """
    import pet_code_scope as S
    gaps = []
    for p in load('data/pets.json'):
        items = []
        pa = p.get('passive')
        if isinstance(pa, dict) and pa.get('brief'):
            items.append(('%s·被动' % p.get('name', p.get('id')), pa))
        for g in ('skillPool', 'volcanoSkills', 'meleeSkills'):
            for sk in (p.get(g) or []):
                if sk.get('brief'):
                    items.append(('%s·%s' % (p.get('name', ''), sk.get('name', '')), sk))
        for nm, obj in items:
            b = plain(str(obj.get('brief', '')))
            f = plain(str(obj.get('detail', '') or '') + ' ' + str(obj.get('desc', '') or ''))
            miss = [cat for cat, ws in S.CATEGORY_WORDS.items()
                    if any(w in f for w in ws) and not any(w in b for w in ws)]
            if miss:
                gaps.append((nm, miss))
    return gaps


def main():
    rows = collect()
    hits = collections.defaultdict(list)
    for tag, ident, field, txt in rows:
        p = plain(txt)
        n = len(p)
        is_brief = field in ('brief', 'effectDesc1', 'effectDesc3', 'desc') and tag != '龟被动'
        # ★2026-08-19: 装备补了 `effectBrief`(一句话) 之后, `effectDesc1` 的身份从
        #   "简述"变成了"全文"(点开看全部那一层) ⇒ 它按详情的上限算, 不再按简述。
        #   全文档放到 400: 实测最长一件 329 字, 而这些是真机制说明, 不是废话。
        if field in ('brief', 'effectBrief'):
            cap = BRIEF_MAX
        elif field.startswith('effectDesc'):
            cap = 400
        else:
            cap = DETAIL_MAX
        # 长度只提示不算违规(完整性优先); 真正的硬线是"漏讲机制"。
        if n > cap and (tag, ident, field) not in DETAIL_ALLOW:
            hits['偏长(提示线%d)' % cap].append((tag, ident, field, n, p[:40]))
        for w in TEACH:
            if w in p:
                hits['教导玩家'].append((tag, ident, field, w, p[:40]))
                break
        for w in JUDGE:
            if w in p:
                hits['自夸/评价'].append((tag, ident, field, w, p[:40]))
                break
        for w in VAGUE:
            if w in p:
                hits['模糊量词'].append((tag, ident, field, w, p[:40]))
                break
        for w in YOU:
            if w in p:
                hits['称呼玩家'].append((tag, ident, field, w, p[:40]))
                break
        for w in FLAVOR:
            if w in p:
                hits['抒情/风味混进机制'].append((tag, ident, field, w, p[:40]))
                break
        # ★2026-08-19 排版一致性: 全项目写「6 秒」「20% 生命」都带空格, 但 .detail 字段一直没人扫过,
        #   里面有 128 处「6秒」「固定2层」、120 处「治疗自己10%」。单看一条不算错, 一屏里混着两种写法
        #   就显得没做完 —— 而且中文里数字贴着汉字本来就难断字。
        #   ★判据落在**渲染后的文本**(去掉 span 标签)上, 因为 `加<span>25%</span>` 在源码里看着是分开的。
        import re as _re
        _plain = _re.sub(r'<[^>]+>', '', p)
        _m = _re.search(r'\d(秒|码|层|次|档|件)', _plain)
        if _m:
            hits['数字贴着单位'].append((tag, ident, field, _m.group(0), _plain[:40]))
        _m2 = _re.search(r'[一-龥]\d', _plain)
        if _m2:
            hits['汉字贴着数字'].append((tag, ident, field, _m2.group(0), _plain[:40]))
        for w in DEVNOTE:
            if w in p:
                hits['开发备注混进玩家文案'].append((tag, ident, field, w, p[:40]))
                break
        # ⚠ 判据太宽第 12 次(2026-08-19): 这里原来用正则查"没有类型前缀的占位符",
        #   报出 {crit*100} 说它会漏到文面 —— **错的**。SkillText 的正则第二个分支
        #   `\{([^}]+)\}` 本来就支持裸表达式, 实测把 283 段全渲染一遍, 花括号残留 **0**。
        #   ⇒ 这类事只能量**渲染后的产物**, 光看源串判不出来。真检查搬到 Godot 侧
        #     (tests/verify_codex_desc.gd 的"渲染后不许有花括号")。
        # ★句子没写完: 结尾是逗号/顿号 = 话说了一半(实测凤凰龟·烫伤就是这样)。
        st = p.strip()
        if st and st[-1] in '，、；:：':
            hits['句子没写完'].append((tag, ident, field, st[-1], st[-30:]))
        # ★内部简写漏给玩家: 「1.8A」这种 A 是我们内部代指攻击力的写法, 玩家看不懂。
        #   实测漏了 5 组(小龟被动/糖果锤/糖衣炮弹/雷电龟连锁)。
        m_ab = re.search(r'[0-9.]+[A-Z](?![A-Za-z%])', p)
        if m_ab is not None:
            hits['内部简写漏给玩家'].append((tag, ident, field, m_ab.group(0), p[:40]))

    print('=== 图鉴文案体检(判据取自 489 条真实同类游戏文案) ===')
    print('受检文本 %d 条' % len(rows))
    total = 0
    for k in ['内部简写漏给玩家', '句子没写完', '开发备注混进玩家文案', '教导玩家', '自夸/评价', '模糊量词', '称呼玩家', '抒情/风味混进机制', '数字贴着单位', '汉字贴着数字',
              '偏长(提示线%d)' % BRIEF_MAX, '偏长(提示线%d)' % DETAIL_MAX]:
        v = hits.get(k, [])
        if not k.startswith('偏长'):
            total += len(v)
        print('  %-18s %4d 条' % (k, len(v)))
        for r in v[:6] if '--list' not in sys.argv else v:
            print('       %s %s.%s  「%s」  %s' % (r[0], r[1], r[2], r[3], r[4]))
    gaps = mech_gaps()
    print('  %-18s %4d 条 (上限 %d, 只许降)' % ('★简述漏讲机制', len(gaps), MISS_MAX))
    for nm, miss in gaps[:6]:
        print('       %s 缺: %s' % (nm, ','.join(miss)))
    print('  ── 合计 %d 处 ──' % total)
    if len(gaps) > MISS_MAX:
        print('  ★★漏讲机制超过基线 —— 这是硬线: 简述可以长, 但不许比全文少一条机制。')
        return 1
    if DETAIL_ALLOW:
        print('  明确豁免 %d 条(超上限但复核认为该留):' % len(DETAIL_ALLOW))
        for k, why in DETAIL_ALLOW.items():
            print('       %s %s.%s —— %s' % (k[0], k[1], k[2], why))

    ## 洞①: `.gd` 屏幕文案那一节(在此之前本脚本一行 .gd 都不读)
    gd_rc = gd_devnote_gate()

    # 2026-08-20 补上真正的判定行 + 非零退出码。
    #   在此之前本脚本从不打 ALL OK、恒返回 0, 是个报告工具 —— 而我今晚多次声称把
    #   改动史词 / 别家游戏黑话 / 数字间距「焊进门禁」, 实际 run-tests.sh 里根本没有它,
    #   那些检查一条都没被强制执行过。(memory: 写进去了没人读 + 假门禁)
    if total > 0:
        print(chr(10) + "[FAIL] 图鉴文案体检: 上面 %d 处硬问题" % total)
        return 1
    if gd_rc != 0:
        return gd_rc
    if '--update' in sys.argv:
        print(chr(10) + "已重写 .gd 开发备注台账。")
        return 0
    print(chr(10) + "ALL OK — 图鉴文案体检(无教学味/自夸/开发备注/别家黑话/数字贴字; 漏讲机制未超基线; .gd 屏幕文案无新增开发备注)")
    return 0


if __name__ == '__main__':
    sys.exit(main())
