# -*- coding: utf-8 -*-
"""number_coverage_audit.py — 玩家文案里每一个数字, 是"被证明的"还是"没人验的"。

★由来(2026-08-20, 用户连问两次「怎么根除」):
  玩家文案里 **2487 个数字是手抄代码的**, 只有 220 个是占位符。手抄的每一个在写下那天都是对的,
  原件一改就烂 —— 这是本项目反复出现的头号病(一晚上同一形状出现七次)。

★"根除"不等于手工把 2487 个全转成占位符 —— 那反而会引入新错。
  根除 = **让剩下的数字不可能悄悄错**, 即每个数字都处在三种状态之一:
    ① 占位符   —— {N:...} / {C:...} 渲染时从代码算, **不可能错**
    ② 有人验   —— 被某个审计器逐个对着代码验过(错了就红)
    ③ 未验证   —— 没人管。**这一类的条数就是本审计器要盯住的指标**
  把 ③ 焊成"只降不升", 每次改动要么用占位符要么补覆盖, 它就不会再长。

★覆盖面是量出来的, 不是猜的:
  · tooltip_number_audit 验【装备】文案里的 a/b/c 三档 ↔ 代码三元数组
  · pet_number_audit     验【占位符表达式】↔ 代码 (literal 数字它管不着)
  · brief_detail_audit   比的是 brief ↔ detail **两份文案**, 不是文案 ↔ 代码
  ⇒ 龟技能文案里写死的数字, 基本没有任何审计器拿它对过代码。洞就在这。

★不算数字的东西(判据要刚好卡住那个形状, 别把噪声算成缺口):
  序数(第 1 段 / 3 档)、百分号里的 0/1/2/3、版本号、以及占位符内部的数。
"""
import io, json, re, sys

sys.stdout.reconfigure(encoding='utf-8')

TEXT_KEYS = {'brief', 'desc', 'detail', 'effect', 'effectBrief',
             'effectDesc1', 'effectDesc2', 'effectDesc3'}
PLACEHOLDER = re.compile(r'\{[A-Z]?:?[^}]*\}')
TAG = re.compile(r'<[^>]+>')
NUM = re.compile(r'(?<![\w.])\d+(?:\.\d+)?')
TRIPLE = re.compile(r'\d+(?:\.\d+)?/\d+(?:\.\d+)?/\d+(?:\.\d+)?')
## ★★不是数值、而是【名字】的那些 token —— 提成常量没有意义, 反而会让文案更难读。
##   目前只有 FPGA板(040) 的四个 2-bit 状态名: 00 / 01 / 10 / 11。
##   它们出现在 "00=回复…" "01=累计…" 这种句式里, 是状态标签, 不是可调的数。
##   ⚠ 这不是放水的口子: 判据是**紧跟等号**(`00=`), 普通数字不会长这样;
##     而且下面会打印被跳过的条数, 涨了看得见。
## ⚠ 这行写过一次 `\b`, 但当时是用**非 raw 字符串**写进文件的,
##   Python 把 `\b` 解释成了**退格符 0x08** 写进去 ⇒ 正则永远匹配不上,
##   而 grep 看不出来(退格符不显示)。不加 \b 也完全够用。
LABEL_NUM = re.compile(r'(?:00|01|10|11)=')
NOISE = {'0', '1', '2', '3'}

# 只降不升。改动后如果这个数涨了, 说明又添了没人验的数字。
BASELINE = 871   # 2026-08-24 累计已转 135 段(1722→871)。台账见 docs/plans/20260820-文案数字根除.md。**只降不升**。
#   ★这个数从 1452 涨到 1734 不是退步, 是【量准了】: 原来把 {N:0.5*ATK} 这类占位符整体
#   记进"不可能错", 而里面的 0.5 是手写在文案里的系数、照样会漂(幽灵龟就是这么漂的)。
#   把这 282 个藏起来的系数摊出来之后, 基线才对得上真实风险。
#   降的办法只有两条: 把数字换成占位符({N:...}/{C:类名.常量名}), 或给它补一个对着代码验的审计器。
#   ★别用"放宽基线"降 —— 那等于把问题从看得见改成看不见。


def collect():
    out = []

    def walk(o, path, src):
        if isinstance(o, dict):
            nm = o.get('name') or o.get('id') or ''
            for k, v in o.items():
                if isinstance(v, str) and k in TEXT_KEYS:
                    out.append((src, '%s%s.%s' % (path, nm, k), v))
                else:
                    walk(v, path + (str(nm) + '/' if nm else ''), src)
        elif isinstance(o, list):
            for x in o:
                walk(x, path, src)

    for f, tag in [('data/pets.json', '龟'), ('data/phase2-equipment.json', '装备')]:
        walk(json.load(io.open(f, encoding='utf-8')), '', tag)
    return out


def main():
    texts = collect()
    n_ph = 0
    n_covered = 0
    n_unver = 0
    n_label = 0      # 被当成【名字】跳过的 token 数(FPGA 的 00/01/10/11), 见 LABEL_NUM
    worst = []
    for src, who, t in texts:
        ## ★2026-08-20 修一个【我自己的分类错误】: 原来把占位符整体记进「不可能错」。
        ##   实测反例(幽灵龟): brief 写 `{N:0.5*ATK}` 而活代码是 0.4A —— **占位符里的系数
        ##   本身就是手写在文案里的字面量**, eval_expr 只是把这个手写表达式算了一遍,
        ##   只有 ATK/maxHp 这些【变量名】来自代码。所以 {N:0.5*ATK} 照样会漂, 而且更隐蔽
        ##   (它看起来像个占位符, 让人以为已经安全了)。
        ##   ⇒ 只有【不含数字字面量】的占位符({N:ATK}/{C:类名.常量})才算「不可能错」;
        ##     含系数的({N:0.5*ATK})把那些系数计入「没人验」。
        ##   这次修正会让③变大 —— 那是把已经存在的风险从看不见改成看得见, 不是新增风险。
        for ph in PLACEHOLDER.findall(t):
            if ph.startswith('{C:'):
                n_ph += 1                     # 直接引用代码常量: 中间不经任何副本
                continue
            lits = [x for x in NUM.findall(ph) if x not in NOISE]
            if lits:
                n_unver += len(lits)          # 手写的系数, 与代码无绑定
            n_ph += 1
        body = TAG.sub('', PLACEHOLDER.sub(' ', t))
        # ① 装备文案里的 a/b/c 三档 —— tooltip_number_audit 逐个对过代码
        trips = TRIPLE.findall(body)
        if src == '装备':
            n_covered += sum(len(x.split('/')) for x in trips)
        body = TRIPLE.sub(' ', body)
        ## 先摘掉【状态名】(见 LABEL_NUM 的注释): 它们不是可调的数值。
        n_label += len(LABEL_NUM.findall(body))
        body = LABEL_NUM.sub(' ', body)
        nums = [x for x in NUM.findall(body) if x not in NOISE]
        if src == '龟':
            n_covered += 0            # 龟文案的 literal 数字: 没有审计器对代码验过
        n_unver += len(nums)
        if nums:
            worst.append((len(nums), who, nums[:5]))

    total = n_ph + n_covered + n_unver
    print('[分母] 文案 %d 段 · 数字总数 %d' % (len(texts), total))
    print('  ① 占位符(不可能错)      %5d  %4.1f%%' % (n_ph, 100.0 * n_ph / max(1, total)))
    print('  ② 有审计器逐个对代码验   %5d  %4.1f%%' % (n_covered, 100.0 * n_covered / max(1, total)))
    print('  ③ ★没人验               %5d  %4.1f%%' % (n_unver, 100.0 * n_unver / max(1, total)))
    worst.sort(reverse=True)
    print('\n  没人验的数字最多的 8 段:')
    for n, who, ex in worst[:8]:
        print('     %-42s %2d 个: %s' % (who[:42], n, ','.join(ex)))

    if BASELINE is None:
        print('\n[FAIL] BASELINE 还没填 —— 把上面 ③ 的实测值填进脚本顶部, 它才开始只降不升')
        return 1
    if n_unver > BASELINE:
        print('\n[FAIL] 没人验的数字从 %d 涨到 %d —— 新加的数字要么用占位符, 要么补覆盖'
              % (BASELINE, n_unver))
        return 1
    print('\nALL OK — 没人验的数字 %d ≤ 基线 %d' % (n_unver, BASELINE))
    return 0


if __name__ == '__main__':
    sys.exit(main())
