# -*- coding: utf-8 -*-
"""事实源纪律门禁(只读)。2026-07-26 建。

【为什么要有】本仓库曾同时有 4 份文件自称"唯一事实源"
(战斗基础-策划焊死.md / 实时版路线图.md / 实时版-路线图与待办.md / 若干带"权威"字样的)。
CLAUDE.md §1 + docs/README.md §1 现在钉死"只有三份权威",且它们的路径被
【活门禁工具】直接消费(tri_audit / hp_staleness_check / codex_audit)当事实源读。

但 README 是"路标",路标会漂:
  · 有人把某份权威改名/移走 → 消费它的工具读到死路径 → N=0 空检查【假绿】
  · 有人明天再塞一份"⭐单一事实源=X" → "4 份自称"的病复发,没人拦
  · README §1 表和真实三份漂移 → 索引本身开始骗人

本脚本把"单一事实源不变量"焊成门禁,四条任一破 = 红:
  ① 三份权威文件在其声明路径上真实存在(移走/改名/删 → 红)
  ② 每份权威的【消费者工具】仍引用它的文件名(工具硬编码路径变死 → 红)
  ③ docs/README.md §1 表列的 .md 恰好是这三份,不多不少(索引漂移 → 红)
  ④ 活树里(排除 archive/ 与这三份)没有任何 .md 在开头自称
     "焊死/单一事实源/唯一事实源"(冒名复发 → 红)

强词只取【焊死/单一事实源/唯一事实源】: 实测这三个词当前零非权威文件命中,
是零误报的触发面。"权威"太松(学派效果-实装规格.md 等正当规格也用),故意不当触发词。
"""
import io, os, re, sys, glob

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

# ── 事实源清单(改权威路径/加权威 → 同步改这里, 这是机器可读的 CLAUDE.md §1) ──
AUTHORITY = {
	'docs/design/28龟技能设计-权威.md': ['tools/hp_staleness_check.py', 'tools/tri_audit.py', 'tools/codex_audit.py'],
	'docs/design/实时版-系统机制权威.md': ['tools/hp_staleness_check.py'],
	'docs/实时版-路线图与待办.md': [],   # 无工具消费, 只被 CLAUDE.md/README 索引
}
README = 'docs/README.md'
STRONG = re.compile(r'焊死|单一事实源|唯一事实源')   # 冒名自称的强词(零误报已校准)
IMPOSTOR_SCAN_LINES = 6

bad = 0
auth_base = set(os.path.basename(p) for p in AUTHORITY)


def fail(msg):
	global bad
	bad += 1
	print('[FAIL] ' + msg)


# ── ① 三份权威真实存在 ──
print('权威事实源 %d 份(判据: CLAUDE.md §1 + README §1 + 工具消费)' % len(AUTHORITY))
if len(AUTHORITY) != 3:
	fail('AUTHORITY 清单不是 3 份 —— 与"只有三份权威"的铁律不符, 空/多都是错')
for p in AUTHORITY:
	if os.path.isfile(p):
		print('  OK  存在  %s' % p)
	else:
		fail('权威文件不存在(被改名/移走/删?): %s —— 消费它的工具会读到死路径' % p)

# ── ② 消费者工具仍引用该权威(文件名出现在工具源码里) ──
n_consumer = 0
for p, consumers in AUTHORITY.items():
	base = os.path.basename(p)
	for c in consumers:
		n_consumer += 1
		if not os.path.isfile(c):
			fail('消费者工具不存在: %s (应消费 %s)' % (c, base))
			continue
		src = io.open(c, encoding='utf-8', errors='replace').read()
		if base in src:
			print('  OK  消费链  %-24s ← %s' % (base, c))
		else:
			fail('消费者 %s 里找不到 %s —— 路径漂移了, 工具正在读别的/死路径(N=0 假绿的源头)' % (c, base))
print('  [分母] 校验消费链 %d 条' % n_consumer)
if n_consumer == 0:
	fail('一条消费链都没校验 —— 空检查不是通过')

# ── ③ README §1 表 = 恰好这三份 ──
if not os.path.isfile(README):
	fail('%s 不存在 —— 事实源索引没了' % README)
else:
	txt = io.open(README, encoding='utf-8').read()
	m = re.search(r'##\s*1\..*?(?=\n##\s*2\.)', txt, re.S)
	if not m:
		fail('%s 里找不到 "## 1." 到 "## 2." 之间的权威表' % README)
	else:
		sec = m.group(0)
		links = re.findall(r'\]\(([^)]+\.md)\)', sec)   # §1 内所有指向 .md 的链接
		listed = set(os.path.basename(u.split('#')[0]) for u in links)
		print('  README §1 列出 .md: %s' % ('、'.join(sorted(listed)) or '(无)'))
		missing = auth_base - listed
		extra = listed - auth_base
		if missing:
			fail('README §1 漏列权威: %s' % '、'.join(sorted(missing)))
		if extra:
			fail('README §1 多列了非权威(第 4 份混进事实源表?): %s' % '、'.join(sorted(extra)))
		if not missing and not extra:
			print('  OK  README §1 = 恰好这三份')

# ── ④ 活树无新冒名 ──
all_md = glob.glob('docs/**/*.md', recursive=True)
skip = set(os.path.normpath(p) for p in AUTHORITY) | {os.path.normpath(README)}
n_scan = 0
for f in all_md:
	nf = os.path.normpath(f)
	if nf in skip:
		continue
	if ('archive' + os.sep) in nf or nf.startswith('archive'):
		continue
	if os.sep + 'archive' + os.sep in nf:
		continue
	n_scan += 1
	head = io.open(f, encoding='utf-8', errors='replace').read().split('\n')[:IMPOSTOR_SCAN_LINES]
	for i, line in enumerate(head, 1):
		if STRONG.search(line):
			fail('冒名事实源 %s:%d 开头自称/声明"单一事实源/焊死": %s' % (f, i, line.strip()[:80]))
			break
print('  [分母] 冒名扫描 %d 篇活树 .md(排除 archive/ 与三权威)' % n_scan)
if n_scan == 0:
	fail('一篇都没扫 —— 空检查不是通过')

# ── ⑤ 路线图的最新条目 == project.godot 的 config/version ──
#
# ★这条 2026-08-04 才补上, 而路线图【从 2026-07-31 起就写着"由本脚本焊死"】——
#   实际本脚本此前只查"在不在位/有没有人读", 根本没查内容新不新。
#   于是同一个病复发了第二次: 路线图停在 v0.17.38, 而实际已经 v0.19.11(漂了 21 个版本),
#   而门禁全绿。**文档声称有个门禁、那个门禁却不存在** —— 正是本脚本要治的病，
#   却发生在本脚本自己身上。现在让那句话变成真的。
#
# 判据: 路线图正文里出现的最大版本号, 必须 == project.godot 的 config/version。
#   取"最大"而不是"第一个" —— 路线图是倒序记账, 但历史条目里也会引用旧版本号。
ROADMAP = 'docs/实时版-路线图与待办.md'
_pg = io.open('project.godot', encoding='utf-8').read()
_m = re.search(r'config/version\s*=\s*"([0-9]+)\.([0-9]+)\.([0-9]+)"', _pg)
if _m is None:
	fail('project.godot 里读不到 config/version —— 这条检查的地基没了')
else:
	cur = tuple(int(x) for x in _m.groups())
	txt = io.open(ROADMAP, encoding='utf-8', errors='replace').read()
	## ★★【不要把章节号当版本号】(2026-09-08 踩过): 我在路线图里引用了 `CLAUDE.md §3.5.1`,
	##   它被当成 v3.5.1 抓走, 而判据取的是**全文最大值**(3 > 0) ⇒ 当场报
	##   "路线图最新版本 v3.5.1 ≠ v0.19.345"。报错文字完全看不出真因, 我查了才明白。
	##   ⇒ 排除 `§`/`章节`/`第` 紧跟着的那种。**只排掉这一种**, 别把判据放松成"取第一个"
	##     —— 取最大值正是为了对付倒序记账里引用旧版本的情况。
	vers = []
	skipped = 0
	for m2 in re.finditer(r'(.{0,2})v?([0-9]+)\.([0-9]+)\.([0-9]+)', txt):
		if '§' in m2.group(1) or '节' in m2.group(1):
			skipped += 1
			continue
		vers.append(tuple(int(x) for x in m2.groups()[1:]))
	print('  [分母] 路线图里解析到 %d 个版本号(跳过 %d 个章节号)' % (len(vers), skipped))
	if not vers:
		fail('路线图里一个版本号都没解析到 —— 空检查不是通过')
	else:
		top = max(vers)
		if top != cur:
			fail('路线图最新版本 v%d.%d.%d ≠ project.godot 的 v%d.%d.%d —— '
				'又漂了。记账跟不上就等于"三份权威"里有一份在骗人。'
				'(若这个数看着像章节号, 见本行上方注释: 路线图里别写 §x.y.z)' % (top + cur))

print()
print('ALL OK — 事实源纪律通过(三权威在位·消费链活·README 无漂移·无冒名·路线图不漂)' if bad == 0 else 'NEEDS FIX: %d 项' % bad)
sys.exit(1 if bad else 0)
