# -*- coding: utf-8 -*-
"""det_math_lint —— sim 路径上不许绕过 DetMath 裸调「跨平台不逐位一致」的数学(进 run-tests 门禁, 成功打印 ALL OK)。

由来(2026-10-10): iPad(ARM64)真人录的 8 场在 Windows(x86-64)上重放, 第 180~600 步就分叉。
  反汇编 ios.zip 里的 libgodot.a: Vector2.length/distance_to/normalized/dot/cross/rotated/lerp/…、
  全局 lerpf/smoothstep/lerp_angle、RandomPCG::random(randf_range)、randfn —— iOS 版全都编成了 FMA(fmadd),
  x86-64 版不是。sin/cos/atan2/pow/exp/log 则是各家 libm 各算各的。
  ⇒ 这些全改走 `scripts/util/det_math.gd`(只用 + - * / sqrt, GDScript VM 逐条舍入, 各平台逐位一致)。
  方案书: docs/plans/20261010-跨平台浮点确定性.md

判什么:
  ① sim 文件(det_math_scope.sim_files): 整份文件里不许出现裸调用。
  ② 演出文件(det_math_scope.render_files): 只判「函数体碰了 sim 标记」的函数(SIM_MARK: _battle_rng /
     _apply_damage / _kill / _heal / 写 hp·pos·shield·energy·alive)。
  Vector3 / Color / String 上的同名方法不算(det_math_scope.recv_kind 判, 与改写工具同一个函数)。
  ★硬零, 不设棘轮: 出现一处就是一处跨设备分叉源。

自检(每次都跑): 往一段合成代码里放已知的裸调用, 判据必须全部抓到 —— 抓不到就是判据瞎了, 直接红。

用法: python tools/det_math_lint.py [--list-other]
"""
import io
import os
import re
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from det_math_scope import sim_files, render_files, recv_kind, first_arg, sim_func_lines, triple_string_lines, ROOT  # noqa: E402
from det_math_rewrite import METHODS, FUNCS, code_end, in_string, receiver_start  # noqa: E402
from det_math_tweens import find as find_tweens  # noqa: E402

RE_METH = re.compile(r'\.(' + '|'.join(METHODS) + r')\(')
RE_FUNC = re.compile(r'(?<![\w.])(' + '|'.join(FUNCS) + r')\(')
## 引擎里其它会融合的入口(sim 上用到过的): Geometry2D 的几何查询、NavigationServer2D 的寻路查询(走 DetNav)
RE_OTHER = re.compile(r'\bGeometry2D\.|NavigationServer2D\.map_get_(?:path|closest_point)\b')


def scan_lines(lines, idxs, path, out, other):
    shader = triple_string_lines(lines)
    for i in idxs:
        if i in shader:
            continue
        l = lines[i]
        if l.lstrip().startswith('#'):
            continue
        code = l[:code_end(l)]
        for m in RE_FUNC.finditer(code):
            if in_string(code, m.start()):
                continue
            if re.search(r'func\s+$', code[:m.start()]):
                continue
            out.append((path, i + 1, m.group(1) + '()', l.strip()))
        for m in RE_METH.finditer(code):
            if in_string(code, m.start()) or code[max(0, m.start() - 7):m.start()] == 'DetMath':
                continue
            name = m.group(1)
            st = receiver_start(code, m.start())
            recv = code[st:m.start()] if st >= 0 else '??'
            if name not in ('randf_range', 'randfn') and recv_kind(lines, i, recv, first_arg(code, m.end())) != 'v2':
                other.append((path, i + 1, '.' + name, recv))
                continue
            out.append((path, i + 1, '.' + name + '()', l.strip()))
        for m in RE_OTHER.finditer(code):
            if not in_string(code, m.start()):
                out.append((path, i + 1, m.group(0).rstrip('.'), l.strip()))


def lint_text(path, text, is_sim):
    lines = [x.rstrip('\r\n') for x in text.splitlines()]
    out, other = [], []
    if is_sim:
        scan_lines(lines, range(len(lines)), path, out, other)
        return out, other, len(lines)
    keep = sorted(sim_func_lines(lines, code_end))
    scan_lines(lines, keep, path, out, other)
    return out, other, len(keep)


def selftest():
    sim_src = ('func f(u, t, rng):\n'
               '\tvar d := u["pos"].distance_to(t["pos"])\n'
               '\tvar a := sin(0.3) + atan2(1.0, 2.0)\n'
               '\tvar v: Vector2 = (u["pos"] - t["pos"]).normalized()\n'
               '\tvar r := rng.randf_range(0.0, 1.0)\n'
               '\tvar q := Geometry2D.get_closest_point_to_segment(v, v, v)\n'
               '\tvar ok := DetMath.dist(u["pos"], t["pos"]) + DetMath.dsin(0.3)\n'
               '\tvar s3 := Vector3(1, 0, 0).normalized()\n'
               '\tvar pp := NavigationServer2D.map_get_path(m, v, v, true)\n')
    out, other, _ = lint_text('<self>', sim_src, True)
    want = {'.distance_to()', 'sin()', 'atan2()', '.normalized()', '.randf_range()', 'Geometry2D', 'NavigationServer2D.map_get_path'}
    got = {o[2] for o in out}
    rnd_src = ('func pretty(x):\n\treturn sin(x)\n'
               'func hurt(u):\n\tu["hp"] -= 1.0\n\treturn cos(1.0)\n')
    out2, _, _ = lint_text('<self>', rnd_src, False)
    tw_src = ('func k(uu, a, b):\n\tvar t = create_tween()\n'
              '\tt.tween_method(func(q: float) -> void:\n\t\tuu["pos"] = DetMath.vlerp(a, b, q)\n'
              '\t, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD)\n'
              '\tt.tween_method(func(p): uu["pos"] = p, a, b, 0.2)\n'
              '\tt.tween_method(func(q: float): uu["pos"] = DetMath.vlerp(a, b, DetMath.tween_ease(q, 1, 0)), 0.0, 1.0, 0.2)\n'
              '\tt.tween_method(func(v: float): node.scale = Vector3.ONE * v, 0.0, 1.0, 0.2).set_trans(Tween.TRANS_BACK)\n')
    tw_bad, tw_n = find_tweens(tw_src)
    ok = (got == want and len(out) == 7 and len(other) == 1 and len(out2) == 1 and out2[0][2] == 'cos()'
          and tw_n == 3 and len(tw_bad) == 2)
    return ok, 'sim 抓到 %s(应 %d 处·实 %d) / 3D 放行 %d / 演出抓到 %s / 补间: 写 sim %d 个(应 3)、违规 %d 个(应 2)' % (
        sorted(got), 7, len(out), len(other), [o[2] for o in out2], tw_n, len(tw_bad))


def main():
    bad = []
    other = []
    fails = []
    ok, det = selftest()
    print('[自检] 判据抓得到已知的裸调用: %s —— %s' % ('PASS' if ok else 'FAIL', det))
    if not ok:
        fails.append('自检')
    sim = sim_files()
    rnd = render_files()
    n_sim_lines = 0
    n_rnd_lines = 0
    for p in sim:
        o, ot, n = lint_text(p, io.open(os.path.join(ROOT, p), encoding='utf-8').read(), True)
        bad += o
        other += ot
        n_sim_lines += n
    for p in rnd:
        o, ot, n = lint_text(p, io.open(os.path.join(ROOT, p), encoding='utf-8').read(), False)
        bad += o
        other += ot
        n_rnd_lines += n
    ## 补间: 写 sim 状态的 tween_method 必须线性 float 0→1(缓动走 DetMath.tween_ease)
    tw_bad_all = []
    tw_total = 0
    for p in sim:
        tb, tn = find_tweens(io.open(os.path.join(ROOT, p), encoding='utf-8').read())
        tw_total += tn
        tw_bad_all += [(p,) + x for x in tb]
    print('[补间] 写 sim 状态的 tween_method %d 个, 违规 %d 个' % (tw_total, len(tw_bad_all)))
    if tw_total < 10:
        fails.append('补间分母过小')
    for x in tw_bad_all:
        print('  ✗ %s:%d 写 sim 的补间走了引擎插值: %s —— 改成 float 0→1 线性 + DetMath.tween_ease\n      %s' % x)
    if tw_bad_all:
        fails.append('写 sim 的非线性补间 %d 个' % len(tw_bad_all))
    det_calls = 0
    for p in sim + rnd:
        det_calls += io.open(os.path.join(ROOT, p), encoding='utf-8').read().count('DetMath.')
    print('[分母] sim 文件 %d 个(%d 行) · 演出文件 %d 个(其中碰 sim 状态的函数共 %d 行) · DetMath 调用 %d 处'
          % (len(sim), n_sim_lines, len(rnd), n_rnd_lines, det_calls))
    if len(sim) < 60 or det_calls < 500 or n_rnd_lines < 100:
        fails.append('分母过小(范围被改窄了?)')
        print('  ✗ 分母过小: sim 文件应 ≥60、DetMath 调用应 ≥500、演出里的 sim 函数应 ≥100 行')
    if '--list-other' in sys.argv:
        for o in other:
            print('  [非 Vector2 · 放行] %s:%d %s 接收者 %s' % o)
    print('[放行] 判成 Vector3/Color/String 的同名方法 %d 处(--list-other 逐条列出)' % len(other))
    for b in bad:
        print('  ✗ %s:%d 裸调 %s —— 改走 DetMath(scripts/util/det_math.gd)\n      %s' % b)
    if bad:
        fails.append('裸调用 %d 处' % len(bad))
    if fails:
        print('FAIL det_math_lint: ' + ' / '.join(fails))
        sys.exit(1)
    print('ALL OK — sim 路径上 0 处绕过 DetMath 的跨平台不一致数学')


if __name__ == '__main__':
    main()
