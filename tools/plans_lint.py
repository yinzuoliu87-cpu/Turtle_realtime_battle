# -*- coding: utf-8 -*-
import sys
## ★Windows 控制台默认 GBK, 打印 emoji/生僻字会**直接抛 UnicodeEncodeError**,
##   于是门禁不是"报出问题"而是**崩在打印那一行** —— 我 2026-08-22 往方案书状态里写了个 🟢
##   就把这条门禁弄崩了, 而崩溃的报错和"真有问题"长得完全不一样, 极易误判。
##   同仓库其它审计器(await_guard_audit 等)早就这么处理了, 这份漏了。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
"""方案书生命周期门禁 —— 每个需求都要走完「方案 → 执行 → 测试 → 验收 → 标记完成」。

用户 2026-08-13:「我们现在这个项目需要正式化, 那每个需求都有产生方案, 执行, 测试和验收,
标记已完成整个的流程」。

★为什么要焊成门禁而不是写进规范文档: 实测 44 份方案书里, **只有 2 份**有状态行、
  **只有 5 份**有实施回填 —— 制度写在 README 里没人执行, 和没有制度是一样的。
  同一手法在 `docs_authority_lint.py`(单一事实源纪律)上已经用过一次。

规则(只管【新写的】方案书, 见 SINCE):
  ① 抬头必须有一行 `状态：<允许值之一>`
  ④ **未勾的验收项必须带分类标记**(⏳待人工/🔲待拍板/❌确认缺/❓证据不足) —— 见 CHECKBOX_MARKS 的由来
  ⑤ 条目里点名的 `tests/verify_*.gd` / `tools/*.py` 必须真的存在
  ② 状态是「已完成」的, 必须有【实施回填】一节, 且不能只剩占位符
  ③ 七节骨架(需求原文/调查/出入/方案/风险/验收/决策)缺一节就红 —— 格式见 plans/README.md
★为什么设 SINCE: 44 份历史方案书是在这条制度之前写的, 一次性补全既不现实也没价值
  (它们的价值在当时的决策记录, 不在格式)。新账不欠、旧账不追。
"""
import io
import json
import os
import re
import sys

## ★★2026-08-25 新增第 ④⑤ 条 —— 起因是我把「方案书没勾」当成「事情没做」报给用户,
##   **一晚上连错四次**(088 涨潮碑 / 飞镖攻速 / 灵物触手 / 预警敌我异色),
##   四次都是"做完了、账没回填", 我照着复选框念 = 让用户重新回答他早就答过的问题。
##   这与本项目花一整夜根除的「文案手抄代码数字」是**同一个病**:
##   同一件事记在两个地方, 其中一个不会自动跟着走。
##
## ★判据必须可靠, 不能猜。我试过"按关键词去 tests/ 找证据", **实测不可靠**
##   (它把有覆盖的报成没有), 拿它当门禁只会天天误报然后被白名单掏空。
## ⇒ 改成一条**纯格式**的纪律, 精度 100%:
##     未勾的每一条, 必须带一个说明"为什么还没勾"的标记。
##   这样「做了没回填」与「真没做」就再也混不了 —— 前者根本不该留在未勾里。
CHECKBOX_MARKS = {
    '⏳': '只能人工验 / 待 F5',
    '🔲': '待用户拍板',
    '❌': '确认还缺(真没做)',
    '❓': '证据不足, 不打勾',
}

PLANS = 'docs/plans'
SINCE = '20260812'          # 这一天起的新方案书按新制度验(用户定制度的日子)
STATUS_OK = ['草稿', '已拍板', '实施中', '已完成', '已作废']
SECTIONS = ['需求原文', '调查', '出入', '方案', '已知风险', '验收', '决策记录']

fails = []
checked = 0
boxed = 0
skipped_refs = 0


def check(path, name):
    global checked
    s = io.open(path, encoding='utf-8').read()
    checked += 1
    m = re.search(r'状态[:：]\s*\**([^\*\n（(]+)', s)
    if not m:
        fails.append('%s: 抬头缺【状态：】行(允许值 %s)' % (name, '/'.join(STATUS_OK)))
        return
    st = m.group(1).strip()
    if st not in STATUS_OK:
        fails.append('%s: 状态「%s」不在允许值里 %s' % (name, st, '/'.join(STATUS_OK)))
    miss = [k for k in SECTIONS if k not in s]
    if miss:
        fails.append('%s: 缺骨架小节 %s' % (name, miss))
    if st == '已完成':
        if '实施回填' not in s:
            fails.append('%s: 标了【已完成】却没有「实施回填」一节' % name)
        elif re.search(r'实施回填[^\n]*\n+\s*（(?:逐条)?补', s):
            fails.append('%s: 「实施回填」还是占位符, 没有真内容' % name)


def check_boxes(path, name):
    """④⑤ —— 对**全部**方案书生效(不受 SINCE 限制)。

    ★为什么不跟 ①②③ 一起设 SINCE: 那三条是"七节骨架"格式, 补历史没价值。
      而④⑤ 管的是**账准不准** —— 账烂掉的恰恰是老方案书(我这次连错四次, 四次都在老的里)。
      而且成本为零: 21 条未勾项已经逐条分类完了, 门禁只是把线守住。
    """
    global boxed
    s = io.open(path, encoding='utf-8').read()
    boxed += 1
    mst = re.search(r'状态[:：]\s*\**([^\*\n（(]+)', s)
    st = mst.group(1).strip() if mst else ''

    ## ④ 未勾的验收项必须带分类标记 —— 没标记 = 没人分类过 = 读的人必然误判。
    for ln in s.split(chr(10)):
        m2 = re.match(r'^\s*-\s*\[\s\]\s*(.{0,6})', ln)
        if not m2:
            continue
        if not any(k in m2.group(1) for k in CHECKBOX_MARKS):
            fails.append('%s: 未勾的验收项没带标记(%s 之一) → 「%s」'
                         % (name, '/'.join(CHECKBOX_MARKS), ln.strip()[:60]))
    ## ⑤ 条目里点名的测试/工具文件必须真的在盘上 —— 防"指向已删测试的假账"。
    ##   (同 docs_authority_lint 的「消费链活」判据: 写了引用就得能解析。)
    ## ★正则要认【裸文件名】: 方案书里大量写成 `verify_x.gd:76` 而不带 `tests/` 前缀 ——
    ##   第一版只认带前缀的, 反向验证(把引用改成一个不存在的测试)**没红**, 差点又是一条假门禁。
    ## ★两类【合法的不存在】必须放过, 否则这条规则会把两种正当写法判成烂账:
    ##   ① 方案书**记录"这份门禁被整份删除"**(20260805 §两份门禁整份删除) —— 那是历史记录, 不是烂账;
    ##   ② **草稿**方案书里写的是"将要新增 verify_x.gd" —— 文件本来就还不该存在。
    ##   判据: ①看引用所在行有没有"删"字; ②看方案书状态是不是「草稿」。
    ##   ⚠ 这不是放水的口子 —— 两条都很窄, 且下面会打印被放过的条数, 涨了看得见。
    draft = (st == '草稿')
    for ln in s.split(chr(10)):
        for ref in set(re.findall(r'(tests/verify_[A-Za-z0-9_]+\.gd|verify_[A-Za-z0-9_]+\.gd|tools/[A-Za-z0-9_]+\.py)', ln)):
            cands = [ref, os.path.join('tests', ref)] if not ref.startswith(('tests/', 'tools/')) else [ref]
            if any(os.path.exists(c) for c in cands):
                continue
            if '删' in ln or draft:
                global skipped_refs
                skipped_refs += 1
                continue
            fails.append('%s: 引用了不存在的文件 `%s`(测试被删/改名了, 这条账已经烂了)' % (name, ref))



def check_version_trace():
    """⑥ 版本留痕 —— 发出去的每个版本都得能在某份方案书里找到 (2026-08-30)。

    ★由来: 用户 2026-08-30「我觉得就很奇怪啊, 方案书应该是标准进度啊, 不可以不管啊」。
      当时实测: 08-27 起发出的 17 个版本里, **12 个在全部 50 份方案书里一个字都查不到**。
      方案书事实上已经不是进度了 —— 而没人会发现, 因为原来的 ①~⑤ 全是
      "已写入的内容格式对不对", 没有一条问"**该写的写了没**"。

    判据: 最新的**活跃**方案书(草稿/已拍板/实施中)日期之后,
          CHANGELOG 里的每个版本号必须在**某份**方案书里出现。
    ★为什么是"某份"而不是"那份": 同一段时间可能并行着两件事
      (这四天就是后端上线 + 六件复查), 逼着写进同一份反而造假账。
      规则只守一条线: **不允许派了版本却哪里都没记**。
    """
    if not os.path.exists('CHANGELOG.md'):
        fails.append('版本留痕: 找不到 CHANGELOG.md')
        return
    files = sorted(f for f in os.listdir(PLANS) if f.endswith('.md') and f != 'README.md')
    ## ★★锚点 = 【最新的那份方案书】, 不论状态 —— 2026-08-31 修。
    ##   第一版锚在"最新的**活跃**方案书"上, 结果一把它标成【已完成】,
    ##   锚点就**倒退**到更早的那份, 凭空要求覆盖 25 个老版本。
    ##   语义应该是"自最近一次开工以来派的版本都得有记录", 完工不该让门槛后退。
    dated = [f for f in files if f[:8].isdigit()]
    if not dated:
        print('  [版本留痕] 没有带日期的方案书 —— 跳过')
        return
    newest = max(dated)
    since = '%s-%s-%s' % (newest[:4], newest[4:6], newest[6:8])
    cl = io.open('CHANGELOG.md', encoding='utf-8').read()
    vers = re.findall(r'^## (\d+\.\d+\.\d+[a-z]?) — (\d{4}-\d{2}-\d{2})', cl, re.M)
    want = [v for v, d in vers if d >= since]
    blob = ''.join(io.open(os.path.join(PLANS, f), encoding='utf-8').read() for f in files)
    miss = [v for v in want if v not in blob]
    print('  [版本留痕] 最新方案书 %s(%s 起); 待覆盖版本 %d 个, 缺 %d 个'
          % (newest, since, len(want), len(miss)))
    ## ★分母断言: 一个版本都没扫到 = 正则挂了 / CHANGELOG 改格式了, 不是通过。
    if not want:
        fails.append('版本留痕: %s 起一个版本都没扫到(CHANGELOG 共 %d 个版本行) —— 空检查不是通过'
                     % (since, len(vers)))
        return
    for v in miss:
        fails.append('版本留痕: %s 发出去了, 但全部 %d 份方案书里一个字都没提 —— 方案书不是进度了'
                     % (v, len(files)))



def check_number_source():
    """⑦ 未勾项里的【具体数字】必须注明它从哪个活事实源读出来 (2026-08-30)。

    ★由来: 用户 2026-08-30「究竟还有多少任务没做完」。我照方案书的复选框念了一遍,
      逐条核实后发现 **6 条 ❌ 里 5 条是烂账** —— 其中最典型的一条写着
      「87 个可抄分母 · 现 32 个 37% · 上限 87」, 而实测是 **可抄 83 / 技能 103 / 77%**。
      那三个数是几周前手抄进去的, 从此再没跟着代码走。

    ★这是同一个病今天第三次(前两次: 版本留痕漏 12 个 / 靶向器"要跳数字"其实一直在跳)。
      根子不是"我忘了更新", 是**方案书里存了一份会漂的副本**
      —— 和本仓库花一整夜根除的「文案手抄代码数字」完全同构。

    判据: 未勾的验收项里如果出现【具体数字】(百分比 / N/M / 三位以上整数),
          同一条目里必须出现一个**活事实源**的引用 —— `tools/*.py`、`tests/*.gd`、
          `scripts/**.gd`、或 `.json`。给不出来源的数字 = 一笔将来必烂的账。
    ★不管已勾的: 已勾条目是历史记录, 数字定格在当时是对的。
    """
    import glob as _glob
    files = sorted(f for f in os.listdir(PLANS) if f.endswith('.md') and f != 'README.md')
    n_open = 0
    n_num = 0
    src_re = re.compile(r'(tools/[A-Za-z0-9_]+\.py|tests/[A-Za-z0-9_]+\.gd'
                        r'|[A-Za-z0-9_/]+\.gd|[A-Za-z0-9_/]+\.json)')
    ## ★数字形态必须【刚好卡住会烂的那种】。
    ##   第一版写成"百分比 / N分之M / 三位以上整数", 当场造了两个假 bug:
    ##     · 「2026-08-30」里的 2026 被当成数字(那是日期)
    ##     · 「手半剑 084」里的 084 被当成数字(那是装备号)
    ##   ⇒ 收紧到真正会漂的三类: **百分比 / 比率 N/M / 带量词的计数**,
    ##     外加"现在是/共/合计/总数"后面跟的数(那是明摆着的快照)。
    ##   宽一格造假 bug、窄一格放过真 bug —— 这条宁可窄, 因为误报会把门禁掏空。
    num_re = re.compile(
        r'(\d+\s*%'
        r'|\d+\s*/\s*\d+'
        r'|\d+\s*(?:个|条|处|件|项|次|张|份|只|发|支|套)'
        r'|(?:现在是|现|共|合计|总数|总共)\s*\d{2,})')
    for f in files:
        body = io.open(os.path.join(PLANS, f), encoding='utf-8').read()
        lines = body.split(chr(10))
        for i, ln in enumerate(lines):
            if not re.match(r'^\s*-\s*\[\s\]', ln):
                continue
            n_open += 1
            ## 条目可能跨行(续行缩进) —— 连同后面的缩进续行一起看。
            block = [ln]
            for nxt in lines[i + 1:]:
                if nxt.strip() == '' or re.match(r'^\s*-\s*\[', nxt) or not nxt.startswith(' '):
                    break
                block.append(nxt)
            txt = chr(10).join(block)
            if not num_re.search(txt):
                continue
            n_num += 1
            if not src_re.search(txt):
                fails.append('%s: 未勾项里写了具体数字却没注明活事实源 → 「%s」'
                             ' —— 手抄的数字必然落后, 要么写清从哪个工具/文件读, 要么别写数'
                             % (f, ln.strip()[:70]))
    print('  [数字来源] 未勾项 %d 条, 其中带具体数字 %d 条' % (n_open, n_num))
    ## ★分母: 一条未勾项都没扫到 = 正则挂了 / 方案书改写法了, 不是通过。
    if n_open == 0:
        fails.append('数字来源: 一条未勾项都没扫到 —— 空检查不是通过, 先看复选框写法变了没')


# ════════════════════════════════════════════════════════════════════════
#  ⑦ 打了勾的验收项必须【点名门禁】(2026-09-01)
#
#  ★由来: 用户连问八遍「为什么这些教训明明发生过, 也记录了, 你还是做不到」。
#    我给的第一个答案("memory 不会自己跑")只解释了机制, 没答到点子上。
#    真正的原因是 —— **我按"我干了多少"打勾, 不按"有什么证据"打勾**。
#
#    2026-09-01 的实例: 方案书里写着
#        - [x] 召唤物动画: 待机／走路／攻击／技能释放 四条
#    我打这个勾是因为我生成了四张精灵表, 不是因为我验过它们在场上是对的。
#    而那四张表同时有三个错(朝向反了 / 只有龟一半高 / 六帧只播五帧),
#    全在这个勾底下躺着, 直到用户喊了一声「方向」。
#
#    ⇒ 这条规则守的不是"有没有门禁", 是**我凭什么打那个勾**。
#      打勾就得点名: `verify_xxx` / `tools/xxx.py` / `run-tests`。
#      给不出来的, 只能写成未勾 + ⏳ 标记(那是"我量不到"的诚实写法, 规则④管它)。
#
#  ★为什么是【每份文件各自只减不增】而不是一刀切:
#    实测 22 份方案书 310 条勾里 268 条没点名(86%) —— 一刀切会把整个门禁变成噪音,
#    而噪音门禁等于没门禁。所以照 arch_budget 的老规矩记台账、只减不增。
#    ★★**没在台账里的文件按 0 算** —— 否则新开一份方案书就能无限打空勾,
#      而"新方案书"恰恰是最需要管的地方(今天这次就是)。
# ════════════════════════════════════════════════════════════════════════
GATE_TOKEN = re.compile(r'verify_[A-Za-z0-9_]+|tools/[A-Za-z0-9_]+\.py|run-tests')
DEBT_FILE = os.path.join('tools', 'plans_gate_debt.json')


def _acceptance_lines(lines):
    """只取【验收清单】那一节的行。

    ★判据要刚好卡住那个形状(memory [[fb-judge-must-fit-the-shape]]):
      第一版我扫的是全文的 `- [x]`, 结果把**决策记录**里的勾也算进来了 ——
      「- [x] 未决 ① —— 用户 2026-08-31 定: 两个都收」这种条目本来就不该有门禁,
      判它烂账是**造假 bug**。收窄到验收节: 从含"验收"的标题起, 到下一个同级或更高级标题止。
    """
    out = []
    depth = 0
    on = False
    for ln in lines:
        m = re.match(r'^(#+)\s*(.*)$', ln)
        if m:
            d = len(m.group(1))
            if '验收' in m.group(2):
                on = True
                depth = d
                continue
            if on and d <= depth:
                on = False
        if on:
            out.append(ln)
    return out


def _checked_blocks(lines):
    """产出每个 `- [x]` 条目的【完整文本】(条目行 + 它下面的续行)。

    ★必须带续行: 我写的验收项经常是"结论一行 + 下面缩进几行讲判据",
      而门禁名字往往在续行里。只看条目行会把好账判成烂账(判据窄一格)。
    """
    i = 0
    while i < len(lines):
        if re.match(r'^\s*-\s*\[[xX]\]', lines[i]):
            blk = [lines[i]]
            j = i + 1
            while (j < len(lines) and lines[j].strip()
                   and not re.match(r'^\s*-\s*\[', lines[j])
                   and (lines[j].startswith('  ') or lines[j].startswith('	'))):
                blk.append(lines[j])
                j += 1
            yield lines[i], chr(10).join(blk)
            i = j
        else:
            i += 1


def check_gate_named():
    """⑦ 每份方案书里"没点名门禁的勾"只减不增。"""
    base = {}
    if os.path.exists(DEBT_FILE):
        try:
            base = json.load(io.open(DEBT_FILE, encoding='utf-8'))
        except Exception:
            base = {}
    files = sorted(f for f in os.listdir(PLANS) if f.endswith('.md') and f != 'README.md')
    tot_checked = 0
    tot_bad = 0
    grew = []
    cur = {}
    for f in files:
        lines = _acceptance_lines(
            io.open(os.path.join(PLANS, f), encoding='utf-8').read().split(chr(10)))
        n = 0
        bad = 0
        first_bad = ''
        for head, blk in _checked_blocks(lines):
            n += 1
            if not GATE_TOKEN.search(blk):
                bad += 1
                if not first_bad:
                    first_bad = head.strip()[:70]
        tot_checked += n
        tot_bad += bad
        if bad:
            cur[f] = bad
        allow = int(base.get(f, 0))
        if bad > allow:
            grew.append('%s: 没点名门禁的勾 %d 条 > 台账 %d 条 —— 新打的勾必须写清"哪条门禁证明了它"'
                        '(给不出来就写成未勾 + ⏳)。例: 「%s」' % (f, bad, allow, first_bad))
    print('  [分母] ⑦ 打勾的验收项共 %d 条, 其中没点名门禁的 %d 条(台账 %d 份文件)'
          % (tot_checked, tot_bad, len(base)))
    if tot_checked < 100:
        fails.append('⑦ 分母过小: 只扫到 %d 条验收勾(<100) —— 空检查不是通过' % tot_checked)
    for g in grew:
        fails.append(g)
    if os.environ.get('PLANS_GATE_DEBT_UPDATE') == '1':
        io.open(DEBT_FILE, 'w', encoding='utf-8').write(
            json.dumps(cur, ensure_ascii=False, indent=1, sort_keys=True) + chr(10))
        print('  [台账已重写] %s (%d 份文件)' % (DEBT_FILE, len(cur)))


def main():
    if not os.path.isdir(PLANS):
        print('缺 %s' % PLANS)
        return 1
    files = sorted(f for f in os.listdir(PLANS) if f.endswith('.md') and f != 'README.md')
    new = [f for f in files if f[:8].isdigit() and f[:8] >= SINCE]
    print('方案书 %d 份; 按新制度验的(%s 起) %d 份' % (len(files), SINCE, len(new)))
    for f in new:
        check(os.path.join(PLANS, f), f)
    for f in files:
        check_boxes(os.path.join(PLANS, f), f)
    check_version_trace()
    check_number_source()
    check_gate_named()
    print('  [分母] 骨架检查 %d 份 · 复选框纪律检查 %d 份 (放过的引用: 已删/草稿 %d 处)'
          % (checked, boxed, skipped_refs))
    if boxed < 40:
        print('  [FAIL] ★分母: 复选框只扫到 %d 份(<40) —— 空检查不是通过' % boxed)
        fails.append('复选框扫描分母过小')
    if checked == 0:
        print('  [ OK ] 暂无新制度下的方案书')
        return 0
    for x in fails:
        print('  [FAIL] ' + x)
    if fails:
        print('')
        print('FAILED: %d 处' % len(fails))
        return 1
    print('')
    print('ALL OK — 方案书生命周期完整(状态/骨架/回填)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
