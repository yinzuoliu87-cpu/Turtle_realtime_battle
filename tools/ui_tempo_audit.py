# -*- coding: utf-8 -*-
"""UI 动效节拍纪律 —— 2026-10-02 建。

由来: 用户 2026-09-30「我需要你**一帧帧看**」, 并给了一段 84 秒真机录屏。
我当时只做了**事件定位**(哪一秒发生了什么), **动效时长一直没量** ——
而且这件事我在回复里说了三遍「还欠动效毫秒数」, 然后再没做
(memory `fb-read-both-sides-of-the-conversation`)。

2026-10-02 补量: 2480 帧全抽(`-fps_mode passthrough`, 容器帧数对得上)、逐帧差分、
门槛取差分分布的 90 分位(2.99, 中位 0.14)、连续段容忍 3 帧静止, 得 50 段动效。
★参考的节拍只有**三档**:
    转场 ~300ms(整屏换, 峰值差分 47~63) · 点击/状态反馈 135~240ms · 大段演出 1.0~1.7s

★★而我们这边 **UI 侧 169 处 tween 用了 45 种不同时长**(30ms ~ 2900ms) —— 每个动画各拍一个数。
与当初「同一个语义色散在三张互不相干的表里」是同一个病 ⇒ 照 `UIPalette` 的先例收成一张表
(`T_TAP/T_BASE/T_TRANS/T_SLOW/T_SET`), 并用本审计器做**只减不增**的棘轮。

⚠ 本审计器**不要求一次改完 169 处** —— 那是机械活, 分批做。它守的是:
   ① 裸数字的**种类数**只减不增(别再新增第 46 种)
   ② 裸数字的**处数**只减不增
   ③ 分母: 真的扫到了 tween(扫到 0 个就是正则烂了, 下面全是空检查)
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

LEDGER = 'tests/golden/ui_tempo_debt.txt'
# ★只管 UI 场景, 不管战斗特效 —— 特效时长是美术参数, 另有 vfx_discipline 管。
SCAN_DIR = 'scripts/scenes'
SKIP_DIR = 'battle'
# ★★2026-10-02 换掉了原来那条正则 —— 它是个**假解析器**:
#      r'tween_(?:property|interval)\([^)]*?,\s*([0-9]*\.?[0-9]+)\s*\)'
#   `[^)]*?` 非贪婪 ⇒ 遇到**嵌套调用**就停在内层的右括号上, 于是两头都错:
#     · 虚报 21 处: `tween_property(spr,"scale",Vector3(0.3,0.3,0.3),0.46)` 数成了时长 0.3
#     · 漏报 65 处: `tween_interval(1.4)` 没有逗号, 一次都没被数到
#   而**棘轮把虚报的 159 焊成了基线** —— 判据本身错了, 棘轮只会把错数字守得更牢。
#   现在改成括号配平的真解析: 取 tween 调用的【最后一个顶层参数】, 它是裸数字才算时长。
CALL = re.compile(r'tween_(?:property|interval)\(')
_NUM_ONLY = re.compile(r'^[0-9]*\.?[0-9]+$')


def tween_durations(src):
	"""逐个 yield (起, 止, 值) —— src 里每个 tween_property/interval 的时长参数。

	★这是本审计器与批量改造脚本【共用的唯一口径】。想换写法的脚本 import 这个函数,
	  不许自己再抄一条正则(memory `fb-hand-rolled-copies-drift`: 抄一次永远落后)。
	"""
	for m in CALL.finditer(src):
		i = m.end() - 1               # 指向 '('
		depth = 0
		quote = None
		args = []
		cur = []
		j = i
		while j < len(src):
			c = src[j]
			if quote is not None:
				if ord(c) == 92:	# 反斜杠转义 —— 不写字面量(heredoc 会把它折叠)
					cur.append(c)
					j += 2
					continue
				if c == quote:
					quote = None
				cur.append(c)
				j += 1
				continue
			if c == '"' or ord(c) == 39:	# 单/双引号 —— 同上, 不写转义字面量
				quote = c
				cur.append(c)
				j += 1
				continue
			if c == '(':
				depth += 1
				if depth > 1:
					cur.append(c)
				j += 1
				continue
			if c == ')':
				depth -= 1
				if depth == 0:
					args.append(''.join(cur))
					break
				cur.append(c)
				j += 1
				continue
			if c == ',' and depth == 1:
				args.append(''.join(cur))
				cur = []
				j += 1
				continue
			cur.append(c)
			j += 1
		if depth != 0 or not args:
			continue                  # 括号没配平(多半是跨行/截断) —— 不猜
		last = args[-1]
		if not _NUM_ONLY.match(last.strip()):
			continue
		# 末参在原串里的精确位置: j 指向调用的右括号, 末参紧贴在它前面
		end = j - (len(last) - len(last.rstrip()))
		start = end - len(last.strip())
		yield start, end, float(last.strip())

fails = []


def chk(name, bad):
    if bad:
        fails.append('%s: %s' % (name, bad if isinstance(bad, str) else ' / '.join(map(str, bad[:6]))))
        print('  [FAIL] %s' % name)
    else:
        print('  [ OK ] %s' % name)


def read_ledger():
    if not os.path.exists(LEDGER):
        return None
    out = {}
    for line in io.open(LEDGER, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        k, _, v = line.partition('\t')
        out[k.strip()] = int(v.strip())
    return out


def main():
    vals = {}
    n_hit = 0
    n_file = 0
    for dp, _dd, fs in os.walk(SCAN_DIR):
        if SKIP_DIR in dp.replace('\\', '/').split('/'):
            continue
        for f in fs:
            if not f.endswith('.gd'):
                continue
            n_file += 1
            s = io.open(os.path.join(dp, f), encoding='utf-8', errors='replace').read()
            for _a, _b, v in tween_durations(s):
                if not (0.01 <= v <= 3.0):
                    continue      # 超出这个区间的多半不是时长(是坐标/比例)
                n_hit += 1
                vals.setdefault(round(v, 3), 0)
                vals[round(v, 3)] += 1

    print('  [分母] 扫 %d 个非战斗场景 .gd · 命中 tween 时长 %d 处 · %d 种取值'
          % (n_file, n_hit, len(vals)))
    chk('★分母: 真的扫到 tween(扫到 0 处则下面全是空检查)',
        [] if n_hit >= 60 else ['只有 %d 处' % n_hit])
    if n_hit < 60:
        print('FAILED: %d 处' % len(fails))
        sys.exit(1)

    led = read_ledger()
    cur = {'裸时长·种类数': len(vals), '裸时长·处数': n_hit}
    if led is None:
        print('  [分母] 台账不存在, 本次测得:')
        for k in sorted(cur):
            print('      %s\t%d' % (k, cur[k]))
        chk('★台账在位(%s)' % LEDGER, '不存在 —— 先生成再提交')
    else:
        worse = []
        shrunk = []
        for k in sorted(cur):
            base = led.get(k)
            flag = '?' if base is None else ('↓' if cur[k] < base else ('=' if cur[k] == base else '↑'))
            print('  [分母] %-14s 现在 %4d / 台账 %s  %s' % (k, cur[k], str(base), flag))
            if base is None:
                worse.append('%s 没登记进台账' % k)
            elif cur[k] > base:
                worse.append('%s 从 %d 涨到 %d' % (k, base, cur[k]))
            elif cur[k] < base:
                shrunk.append(k)
        chk('★只减不增(别再新增第 %d 种时长)' % (len(vals) + 1), worse)
        if shrunk:
            chk('★减下去了就把台账改小(留着的空额迟早被人用掉): %s' % ' '.join(shrunk),
                ['%s 台账还写着 %d, 实测已经 %d' % (k, led[k], cur[k]) for k in shrunk])

    # 最常见的几个值 —— 给下一批改造指路(改众数收益最大)
    top = sorted(vals.items(), key=lambda kv: -kv[1])[:6]
    print('  [分母] 出现最多的时长: %s'
          % ' · '.join('%.0fms×%d' % (v * 1000, n) for v, n in top))

    print('')
    if fails:
        for f in fails:
            print('  %s' % f)
        print('FAILED: %d 处' % len(fails))
        sys.exit(1)
    print('ALL OK — UI 动效节拍(裸时长只减不增)')


# ★加 __main__ 守卫: 批量改造脚本要 import tween_durations 复用口径,
#   不加守卫的话 import 当场跑完审计并 sys.exit, 把调用方掐死。
if __name__ == '__main__':
	main()
