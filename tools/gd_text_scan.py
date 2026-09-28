# -*- coding: utf-8 -*-
"""gd_text_scan.py — 从 `.gd` 源码里抽出【玩家会读到的中文字符串】。

不是审计器, 是**共享抽取器**。两个审计器都从这里取料:
  · `codex_text_lint.py`  —— 判「开发备注混进玩家文案」(洞①)
  · `text_golden.py`      —— 存 .gd 侧屏幕文案快照(洞②)

★★为什么必须是**一份**抽取器:
  memory [[fb-hand-rolled-copies-drift]] —— 两边各写一遍正则, 抄一次就永远落后。
  谁改了取料口径, 两个审计器同时跟着变。

════════════════════════════════════════════════════════════════════════
 ★口径是量出来的, 不是拍的 (2026-09-28)
════════════════════════════════════════════════════════════════════════
最初的方案是「只收赋给 `.text` / `.tooltip_text` 的字面量」。**实测那个口径抓 0 条**:

  文案体检点名的 7 处开发备注, 只有 1 处是 `btn.tooltip_text = "..."` 的形状,
  另外 6 处分别是
    · `_make_skill_corner("开发中", …)`        —— 传给构造函数的参数
    · `PHASE_PENDING_NOTE := { … : "玩法开发中 · 暂按积分赛规则" }` —— const 字典的值
    · `return str(PHASE_PENDING_NOTE.get(phase, "玩法开发中 …"))`   —— 取值的兜底参数
    · `sub = "玩法开发中, 暂按积分赛规则"`      —— 局部变量, 几层之后才进 Label
  ⇒ 「只看赋值语句」这个口径, **正是这三个洞的同一个形状**: 判据没错, 范围不含。
    按它做出来的门禁会是一条**新的空检查**(实测分母 208 条 / 命中 0)。

所以口径改成:**源码里每一条含中文的字符串字面量**(注释与调试通道除外)。
实测分母 scripts/scenes 877 条 · scripts 全域 1488 条, 6 处点名的存量一条不漏。

不收的两类, 各有理由:
  ① **注释** —— 开发备注写在注释里是正当的, 那是给人看的
  ② **调试通道** —— `print` / `push_error` / `push_warning` / `assert` 的参数
     玩家看不到; 里面出现「待定」「开发中」是正常的
     (⚠ 跳过的条数会被打印出来, 涨了看得见 —— 不是无声的口子)

已知不完备(写在这儿是为了下一个人不会以为它全覆盖):
  · 字符串拼接/`%` 格式化的结果只能看到各自的片段
  · `tr("...")` 之类的间接层没有(本仓目前没有 i18n 层)
  · 三引号多行串整块跳过(本仓里只有 shader 代码, 无中文)
  · 中文的**字典键**也会被收进来(本仓极少; 快照里看得见, 不会静默)
"""
import io
import os
import re

BS = chr(92)
NL = chr(10)

## 含中文 = 候选玩家文案。日文假名/韩文本仓没有, 不收。
CJK = re.compile("[" + chr(0x4E00) + "-" + chr(0x9FFF) + "]")

## 一条 GDScript 双引号串(支持 \" 转义)。单引号本仓不用(style_lint 焊死过双引号习惯)。
STR = re.compile('"(?:[^"' + BS + BS + ']|' + BS + BS + '.)*"')

## 调试通道: 这一行里出现它 ⇒ 这一行的串都不算玩家文案。
##   判据故意落在【整行】而不是精确的参数范围: 宁可少收一点, 也不要把 print 里的
##   开发字眼算成 bug —— 那会让这条门禁变成噪音, 而噪音门禁等于没门禁。
##   ⚠ 前置的点**必须允许**: 本仓写的是 `battle.push_warning("[训龟大师] 立绘未就绪…")`
##     (主场景自己包了一层)。第一版用 `(?<![A-Za-z0-9_.])` 把带点的形式排除掉了,
##     于是那条日志被算成"玩家文案"—— 排除一个字符就漏一整类。
DEBUG_CH = re.compile(
    r"(?<![A-Za-z0-9_])(print|printerr|prints|print_debug|printraw|print_rich"
    r"|push_error|push_warning|assert)\s*\(")

## 明确的"屏幕文案落点" —— 收到的串会打上这个 sink 标签, 快照里分两档看。
SINK_ASSIGN = re.compile(r"\.(text|tooltip_text|placeholder_text|hint_tooltip)\s*=")
SINK_CALL = re.compile(r"(?<![A-Za-z0-9_])(add_text|append_text|set_text|set_tooltip)\s*\(")

## 行内豁免: `# devnote-ok: 原因`。**必须写原因**, 原因会被打印出来, 数量涨了看得见。
##   (照 `zero_caller_audit.py` 的 `# zero-caller-ok:` 同一条规矩 —— 无声豁免等于没有规则。)
##   本仓真实需要它的形状: `BracketMapScene` 的「待定」是**对阵表里那一格还没定下来**
##   的玩家文案(TBD), 不是开发备注; 「左队/右队」是伤害统计面板的真实列名。
EXEMPT_RE = re.compile(r"#\s*devnote-ok:\s*(.+)")


def strip_comment(line):
    """去掉行尾注释, 但**不碰字符串里的 `#`**。

    ★不能简单 `line.split('#')[0]` —— 文案里到处是 `#ffd93d` 颜色码
      (`"[color=#8fa6bb]%d费%s[/color]"`), 一刀切会把半句话当成注释切掉,
      于是那条串再也匹配不上 ⇒ 静默漏掉。
    """
    out = []
    in_s = False
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if in_s:
            out.append(c)
            if c == BS:
                i += 1
                if i < n:
                    out.append(line[i])
                    i += 1
                continue
            if c == '"':
                in_s = False
            i += 1
            continue
        if c == '"':
            in_s = True
            out.append(c)
            i += 1
            continue
        if c == "#":
            break
        out.append(c)
        i += 1
    return "".join(out)


def gd_files(roots):
    """roots 里的每个 .gd(root 可以是目录也可以是单个文件)。"""
    out = []
    for r in roots:
        r = r.replace(BS, "/")
        if os.path.isfile(r):
            if r.endswith(".gd"):
                out.append(r)
            continue
        for dp, _d, fs in os.walk(r):
            for f in fs:
                if f.endswith(".gd"):
                    out.append(os.path.join(dp, f).replace(os.sep, "/"))
    return sorted(set(out))


def scan(roots):
    """→ (rows, stats)

    rows: [(relpath, lineno, sink, text, exempt_reason)]
          sink ∈ text/tooltip_text/placeholder_text/hint_tooltip/add_text/…
                 /"lit"(含中文但落点不明)
          exempt_reason: `# devnote-ok: 原因` 里的原因, 没写豁免就是 ""
    stats: {"files": n, "lits": n, "skipped_debug": n, "skipped_block": n}
    """
    rows = []
    st = {"files": 0, "lits": 0, "skipped_debug": 0, "skipped_block": 0}
    for p in gd_files(roots):
        st["files"] += 1
        src = io.open(p, encoding="utf-8", errors="replace").read()
        lines = src.split(NL)
        in_block = False
        for i, raw in enumerate(lines):
            ## `"""..."""` 整块跳过(本仓里只有 shader 代码)
            tq = raw.count('"""')
            if in_block:
                st["skipped_block"] += 1
                if tq % 2 == 1:
                    in_block = False
                continue
            if tq % 2 == 1:
                in_block = True
                st["skipped_block"] += 1
                continue
            code = strip_comment(raw)
            if '"' not in code:
                continue
            is_dbg = DEBUG_CH.search(code) is not None
            m_as = SINK_ASSIGN.search(code)
            m_cl = SINK_CALL.search(code)
            if m_as is not None:
                sink = m_as.group(1)
            elif m_cl is not None:
                sink = m_cl.group(1)
            else:
                sink = "lit"
            ## 豁免写在本行行尾, 或紧挨着的上一行(长串只好写上一行)
            mex = EXEMPT_RE.search(raw)
            if mex is None and i > 0:
                mex = EXEMPT_RE.search(lines[i - 1])
            why = mex.group(1).strip() if mex is not None else ""
            for m in STR.finditer(code):
                s = m.group(0)[1:-1]
                if not CJK.search(s):
                    continue
                if is_dbg:
                    st["skipped_debug"] += 1
                    continue
                st["lits"] += 1
                rows.append((p, i + 1, sink, s, why))
    return rows, st
