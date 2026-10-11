#!/usr/bin/env python3
"""det_math_rewrite.py —— 把 sim 路径上「跨平台不逐位一致」的数学调用改走 DetMath(一次性迁移工具, 可反复跑, 幂等)。

为什么(2026-10-10 跨设备回放分叉, docs/plans/20261010-跨平台浮点确定性.md):
  · 引擎 C++ 里的 Vector2.length / distance_to / normalized / dot / cross / rotated / lerp …、
    以及全局 lerpf / smoothstep / lerp_angle / RandomNumberGenerator.randf_range,
    在 iOS(ARM64·clang 默认 -ffp-contract=on)上被编译成 FMA(fmadd), 在 x86-64 上不是
    ⇒ 同一份输入两边结果差末位(实测 ios.zip 里 libgodot.a 反汇编)。
  · sin/cos/atan2/pow/exp/log 走各平台 libm, IEEE-754 不保证逐位一致。
  GDScript 层的 + - * / sqrt 是 VM 逐条执行(一条一舍入, 不会融合) ⇒ 用它们重写的 DetMath 各平台逐位一致。

用法:
  python tools/det_math_rewrite.py --dry   列出将改的每一处(含接收者表达式)
  python tools/det_math_rewrite.py         就地改写
  python tools/det_math_rewrite.py --check 只数「还剩多少处裸调用」(门禁用的是 tools/det_math_lint.py)
"""
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from det_math_scope import sim_files, render_files, sim_func_lines, triple_string_lines, ROOT, recv_kind, first_arg  # noqa: E402

# 方法: .name( → DetMath.fn(RECV, ...)
METHODS = {
    'length': ('vlen', True),
    'length_squared': ('len2', True),
    'distance_to': ('dist', False),
    'distance_squared_to': ('dist2', False),
    'normalized': ('norm', True),
    'dot': ('dot', False),
    'cross': ('cross', False),
    'angle': ('angle', True),
    'angle_to': ('angle_to', False),
    'rotated': ('rotated', False),
    'lerp': ('vlerp', False),
    'limit_length': ('limit_len', False),
    'move_toward': ('vmove_toward', False),
    'randf_range': ('rrange', False),
    'randfn': ('rnorm', False),
}
# 全局函数: name( → DetMath.fn(
FUNCS = {
    'sin': 'dsin', 'cos': 'dcos', 'tan': 'dtan', 'atan': 'datan', 'atan2': 'datan2',
    'asin': 'dasin', 'acos': 'dacos', 'pow': 'dpow', 'exp': 'dexp', 'log': 'dlog',
    'lerpf': 'flerp', 'lerp_angle': 'lerp_ang', 'smoothstep': 'smooth',
}

IDENT = re.compile(r'[A-Za-z0-9_]')
QUOTES = chr(34) + chr(39)


def code_end(line):
    """注释开始的位置(引号外的 #); 没有就是行长。"""
    q = None
    i = 0
    while i < len(line):
        c = line[i]
        if q:
            if c == '\\':
                i += 2
                continue
            if c == q:
                q = None
        else:
            if c in '"\'':
                q = c
            elif c == '#':
                return i
        i += 1
    return len(line)


def in_string(line, pos):
    q = None
    i = 0
    while i < pos:
        c = line[i]
        if q:
            if c == '\\':
                i += 2
                continue
            if c == q:
                q = None
        elif c in '"\'':
            q = c
        i += 1
    return q is not None


def skip_group_back(s, i):
    """s[i] 是 ) 或 ], 返回与之配对的开括号下标(处理组内字符串)。"""
    close = s[i]
    op = '(' if close == ')' else '['
    depth = 0
    j = i
    while j >= 0:
        c = s[j]
        if c in '"\'':
            # 往回跳过字符串
            k = j - 1
            while k >= 0 and s[k] != c:
                k -= 1
            j = k - 1
            continue
        if c in ')]':
            depth += 1
        elif c in '([':
            depth -= 1
            if depth == 0:
                if c != op:
                    return -1
                return j
        j -= 1
    return -1


def receiver_start(s, dot):
    """s[dot] == '.', 返回接收者表达式起点; -1 = 认不出。
    接收者 = 后缀表达式: 主体(标识符 / 字符串 / 括号) 后跟任意个 .名字 / [..] / (..)。"""
    i = dot - 1
    while True:
        start = i + 1
        while i >= 0 and s[i] in ')]':
            o = skip_group_back(s, i)
            if o < 0:
                return -1
            i = o - 1
            start = o
        if i >= 0 and s[i] in QUOTES and start == i + 1:
            k = i - 1
            while k >= 0 and s[k] != s[i]:
                k -= 1
            if k < 0:
                return -1
            start = k
            i = k - 1
        elif i >= 0 and IDENT.match(s[i]):
            while i >= 0 and IDENT.match(s[i]):
                i -= 1
            start = i + 1
            if s[start].isdigit():
                return -1
        if start > dot - 1:
            return -1
        if i >= 0 and s[i] == '.':
            i -= 1
            continue
        if i >= 0 and s[i] in '$%':
            start = i
        return start


def rewrite_line(line, stats, dry_rows, path, ln, lines=None):
    end = code_end(line)
    code, tail = line[:end], line[end:]
    changed = True
    guard = 0
    while changed and guard < 50:
        changed = False
        guard += 1
        # 方法: 从右往左改, 这样嵌套的接收者也能逐层处理
        hits = []
        for m in re.finditer(r'\.(' + '|'.join(METHODS) + r')\(', code):
            if in_string(code, m.start()):
                continue
            if code[max(0, m.start() - 7):m.start()] == 'DetMath':
                continue
            hits.append(m)
        if hits:
            m = hits[-1]
            name = m.group(1)
            fn, noarg = METHODS[name]
            st = receiver_start(code, m.start())
            if st < 0:
                dry_rows.append((path, ln, name, '??', line.rstrip()))
                stats['unparsed'] = stats.get('unparsed', 0) + 1
                # 打标记避免死循环: 跳过这一处(改成占位再还原)
                code = code[:m.start()] + '\x00' + code[m.start() + 1:]
                changed = True
                continue
            recv = code[st:m.start()]
            after = m.end()
            if name not in ('randf_range', 'randfn') and lines is not None and recv_kind(lines, ln - 1, recv, first_arg(code, after)) != 'v2':
                dry_rows.append((path, ln, name, recv, '[跳过: 非 Vector2]'))
                stats['skip_other'] = stats.get('skip_other', 0) + 1
                code = code[:m.start()] + '\x00' + code[m.start() + 1:]
                changed = True
                continue
            if noarg:
                if code[after:after + 1] != ')':
                    dry_rows.append((path, ln, name, recv + ' (有参数?)', line.rstrip()))
                    code = code[:m.start()] + '\x00' + code[m.start() + 1:]
                    changed = True
                    continue
                new = 'DetMath.%s(%s)' % (fn, recv)
                code = code[:st] + new + code[after + 1:]
            else:
                rest = code[after:]
                sep = '' if rest.startswith(')') else ', '
                new = 'DetMath.%s(%s%s' % (fn, recv, sep)
                code = code[:st] + new + code[after:]
            stats[name] = stats.get(name, 0) + 1
            dry_rows.append((path, ln, name, recv, ''))
            changed = True
            continue
        for m in re.finditer(r'(?<![\w.])(' + '|'.join(FUNCS) + r')\(', code):
            if in_string(code, m.start()):
                continue
            # 跳过 func 定义
            if re.search(r'func\s+$', code[:m.start()]):
                continue
            name = m.group(1)
            code = code[:m.start()] + 'DetMath.' + FUNCS[name] + '(' + code[m.end():]
            stats[name] = stats.get(name, 0) + 1
            dry_rows.append((path, ln, name, '', ''))
            changed = True
            break
    code = code.replace('\x00', '.')
    return code + tail


def main():
    dry = '--dry' in sys.argv
    stats = {}
    rows = []
    files_changed = 0
    sims = set(sim_files())
    for path in sorted(sims) + render_files():
        full = os.path.join(ROOT, path)
        raw = open(full, 'rb').read()
        text = raw.decode('utf-8')
        # 保留每行原行尾(本仓行尾是混的)
        lines = text.splitlines(keepends=True)
        plain = [x.rstrip('\r\n') for x in lines]
        keep = None if path in sims else sim_func_lines(plain, code_end)
        shader = triple_string_lines(plain)
        out = []
        for i, l in enumerate(lines):
            body = l.rstrip('\r\n')
            eol = l[len(body):]
            if body.lstrip().startswith('#') or (keep is not None and i not in keep) or i in shader:
                out.append(l)
                continue
            nb = rewrite_line(body, stats, rows, path, i + 1, plain)
            out.append(nb + eol)
        new = ''.join(out)
        if new != text:
            files_changed += 1
            if not dry:
                open(full, 'wb').write(new.encode('utf-8'))
    if dry:
        for r in rows:
            print('%s:%d  %-18s %s %s' % r)
    print('stats', stats)
    print('files', files_changed, '(dry)' if dry else '(written)')


if __name__ == '__main__':
    main()
