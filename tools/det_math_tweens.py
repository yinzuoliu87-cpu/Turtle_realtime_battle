# -*- coding: utf-8 -*-
"""det_math_tweens —— 找出「补间(tween_method)的插值结果写进 sim 状态」的调用(det_math_lint 的一部分)。

为什么: Tween 的缓动方程(Quad/Sine/Cubic/Back/…)与 Vector2 等非 float 的插值(Animation::interpolate_variant)
  在 iOS 版引擎里同样被编成了 FMA(反汇编 libgodot.a 实测); 只有 **TRANS_LINEAR 的 float 补间**
  (`Linear::in` = c*t/d + b, 先除后加, 不可能融合)是各平台逐位一致的。
  ⇒ 写 sim 状态的补间: 一律 float 0→1、线性, 缓动在回调里用 DetMath.ease(q, trans, ease) 自己算。

判法: 一个 tween_method(...) 调用(含多行 lambda), 回调体里出现对字典字段的写入 `x["字段"] = / += / -=`,
  就当它写 sim 状态。对这样的调用要求:
  ① 链上没有非线性的 `.set_trans(`(set_ease 不管: Linear 方程不看 ease)
  ② 起止值是数字字面量(不是 Vector2 / 变量 —— 非 float 的插值走 Animation::interpolate_variant, 融合)
  ③ 它所在的 tween 变量在前后 80 行内没有整条 `变量.set_trans(非线性)`(整条 tween 的默认缓动)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from det_math_rewrite import code_end  # noqa: E402

DICT_WRITE = re.compile(r'\w+\s*\[\s*"[A-Za-z_0-9]+"\s*\]\s*([-+*/]?=)(?!=)')


def _call_span(text, start):
    """text[start] 是 'tween_method(' 的 '(' 位置之后; 返回调用结束(配对右括号)的下标。"""
    depth = 1
    i = start
    q = None
    while i < len(text):
        c = text[i]
        if q:
            if c == '\\':
                i += 2
                continue
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        elif c == '#':
            j = text.find('\n', i)
            i = j if j >= 0 else len(text)
            continue
        elif c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _split_top(args):
    out, depth, cur, q = [], 0, '', None
    for c in args:
        if q:
            cur += c
            if c == q:
                q = None
            continue
        if c in '"\'':
            q = c
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += c
    out.append(cur)
    return [x.strip() for x in out]


def find(text):
    """返回 [(行号, 违规说明, 摘要)] 与 写 sim 的补间总数。"""
    bad = []
    n_sim = 0
    for m in re.finditer(r'\.tween_method\(', text):
        line_start = text.rfind('\n', 0, m.start()) + 1
        if text[line_start:m.start()].lstrip().startswith('#'):
            continue
        end = _call_span(text, m.end())
        if end < 0:
            continue
        body = text[m.end():end]
        ## 去掉注释再判写入
        body_nc = '\n'.join(l[:code_end(l)] for l in body.split('\n'))
        if not DICT_WRITE.search(body_nc):
            continue
        n_sim += 1
        ln = text.count('\n', 0, m.start()) + 1
        args = _split_top(body_nc)
        why = []
        if len(args) >= 3:
            for a in args[1:3]:
                if not re.fullmatch(r'-?\d+(\.\d+)?', a):
                    why.append('起止值不是数字字面量(%s)' % a)
        ## 链: 调用之后同一表达式里的 .set_trans / .set_ease
        tail = text[end + 1:text.find('\n', end + 1) if text.find('\n', end + 1) >= 0 else len(text)]
        ## 只看 set_trans: 线性补间的 set_ease 不改结果(Linear 方程不看 ease)
        for mm in re.finditer(r'\.set_trans\(([^)]*)\)', tail):
            if 'TRANS_LINEAR' not in mm.group(1):
                why.append('链上有 .set_trans(%s)' % mm.group(1))
        mv = re.search(r'(\w+)\s*$', text[line_start:m.start()])
        if mv:
            win = text[max(0, m.start() - 6000):end + 6000]
            for mm in re.finditer(r'\b' + re.escape(mv.group(1)) + r'\.set_trans\(([^)]*)\)', win):
                if 'TRANS_LINEAR' not in mm.group(1):
                    why.append('整条 tween %s.set_trans(%s)' % (mv.group(1), mm.group(1)))
        if why:
            bad.append((ln, '; '.join(why), text[m.start():m.start() + 90].replace('\n', ' ')))
    return bad, n_sim


if __name__ == '__main__':
    from det_math_scope import sim_files, ROOT
    tot = 0
    for p in sim_files():
        t = open(os.path.join(ROOT, p), encoding='utf-8').read()
        b, n = find(t)
        tot += n
        for x in b:
            print('%s:%d  %s\n      %s' % (p, x[0], x[1], x[2]))
    print('写 sim 状态的补间', tot)
