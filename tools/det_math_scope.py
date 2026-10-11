# -*- coding: utf-8 -*-
"""det_math_scope —— 「sim 路径」文件清单(det_math_rewrite.py 与 det_math_lint.py 共用这一份, 不许抄第二份)。

sim 文件 = 战斗模拟会走到的代码: 主场景 + battle/ 下非纯 UI 的 + systems/(除音频/回放网络)+ combat/ + gamedata/
          + util/arena_shape.gd(每步钳位置)。整份文件一律不许裸调跨平台不一致的数学。
演出文件 = *_vfx.gd 等 —— 大部分是画面, 但**里面也住着 sim 逻辑**(bow_eq_vfx 用 _battle_rng.randfn 定落点、
          spirit_eq_vfx 的 parasol_heal 直接回血)。⇒ 演出文件按**函数**判: 函数体里碰了 sim 标记
          (SIM_MARK)的, 整个函数不许裸调; 其余函数是纯画面, 放行。
"""
import os
import re
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

## 纯 UI / 开发工具 / 纯画面: 按函数判(见 SIM_MARK)
RENDER = re.compile(r'(_vfx\.gd$|/battle_hud\.gd$|/battle_render\.gd$|/battle_vfx\.gd$|/info_panel\.gd$|/inspect_card\.gd$'
                    r'|/settle_screen\.gd$|/replay_controls\.gd$|/review_console\.gd$|/dmg_stats_panel\.gd$|/battle_vfx_lab\.gd$'
                    r'|/arena_outer\.gd$|/map_field\.gd$|/topbar_status\.gd$|/sword_3d\.gd$|/battle_world_builder\.gd$'
                    r'|/equip/hp_lines\.gd$)')
## 整个不算(网络/音频/回放校验: 不算战斗数值)
SKIP = re.compile(r'(/systems/audio/|/systems/replay/|/systems/sim/sim_driver\.gd$|/systems/sim/sim_shot\.gd$'
                  r'|/gamedata/(vfxlab_cases|skill_icons|axe_art|glossary|menu_arena_layout|bracket_layout|arena_theme)\.gd$)')

## 演出文件里, 函数体出现这些 ⇒ 这个函数在改 sim 状态 / 取 sim 随机, 按 sim 函数判
SIM_MARK = re.compile(r'_battle_rng|_apply_damage|\bbattle\._kill\(|\b_kill\(|\b_heal\(|battle\._heal|'
                      r'\["(hp|pos|shield|energy|alive)"\]\s*([-+*/]?=)(?!=)')


def _all():
    pats = ['scripts/scenes/RealtimeBattle3DScene.gd', 'scripts/scenes/battle/*.gd', 'scripts/systems/**/*.gd',
            'scripts/combat/*.gd', 'scripts/gamedata/*.gd', 'scripts/util/arena_shape.gd']
    out = []
    for p in pats:
        for f in glob.glob(os.path.join(ROOT, p), recursive=True):
            r = os.path.relpath(f, ROOT).replace('\\', '/')
            if SKIP.search('/' + r):
                continue
            out.append(r)
    return sorted(set(out))


def sim_files():
    """整份按 sim 判的文件。"""
    return [f for f in _all() if not RENDER.search('/' + f)]


def render_files():
    """按函数判的演出文件。"""
    return [f for f in _all() if RENDER.search('/' + f)]


# ─────────────── 接收者类型(只有 Vector2 / RandomNumberGenerator 要改走 DetMath) ───────────────
## 同名方法在 Vector3 / Color / String 上也有(.length() / .lerp() / .normalized() …), 那些是 3D 演出 / 文本,
## 不进 sim, 不改。判法是启发式, 但**改写工具与门禁用同一个函数** ⇒ 两边口径一致;
## 判成「其它」的每一处都列在 `det_math_lint.py --list-other` 里可逐条复查。
_V3 = re.compile(r'Vector3|Basis|Transform3D|Quaternion|\bColor\b|(?<!ARENA)\.position\b|^position\b|global_position|_world_pos'
                 r'|\.origin\b|_cam\b|cam_p|to_cam|\bbasis\b|unproject|TENT_')
_SIM_WRITE = re.compile(r'\["(pos|hp|shield|energy|alive)"\]\s*([-+*/]?=)(?!=)|_apply_damage|_heal\(')
_STRISH = re.compile(r'^"|^\'|\bstr\(|nickname|to_lower|_nk\(|"%|TAG_ALPHABET|ROW_PREFIX')
_SIMPLE_TYPES = {'Vector2': 'v2', 'Vector2i': 'other', 'Vector3': 'other', 'Color': 'other', 'String': 'other',
                 'StringName': 'other', 'Quaternion': 'other', 'Basis': 'other', 'RandomNumberGenerator': 'v2'}


def _decl_kind(lines, ln, name, depth=0):
    pat = re.compile(r'^(?:var|const)\s+' + re.escape(name) + r'\s*(?::\s*(\w+))?\s*(?::?=\s*(.*))?$')
    ppat = re.compile(r'[(,]\s*' + re.escape(name) + r'\s*:\s*(\w+)')
    for j in range(ln - 1, max(-1, ln - 600), -1):
        l = lines[j].split('#')[0]
        st = l.strip()
        m = pat.search(st)
        if m:
            if m.group(1):
                return _SIMPLE_TYPES.get(m.group(1), 'v2')
            rhs = m.group(2) or ''
            if _V3.search(rhs) or _STRISH.search(rhs):
                return 'other'
            if depth < 2 and re.match(r'^\(?[A-Za-z_]\w*\s*[-+]', rhs.strip()):
                ## var up := (tip - grip) —— 顺着右边的名字再查一层
                for nm in re.findall(r'(?<![.\w])[A-Za-z_]\w*', rhs):
                    if nm != name and _decl_kind(lines, j, nm, depth + 1) == 'other':
                        return 'other'
            return 'v2'
        if st.startswith(('func ', 'static func ')):
            m2 = ppat.search(st)
            if m2:
                return _SIMPLE_TYPES.get(m2.group(1), 'v2')
            if not l.startswith('\t'):
                return 'v2'
    return 'v2'


def first_arg(code, pos):
    """code[pos] 是方法调用的 '(' 之后一位, 返回第一个实参文本(顶层逗号/右括号为止)。"""
    depth = 0
    i = pos
    while i < len(code):
        c = code[i]
        if c in '([':
            depth += 1
        elif c in ')]':
            if depth == 0:
                break
            depth -= 1
        elif c == ',' and depth == 0:
            break
        i += 1
    return code[pos:i].strip()


def recv_kind(lines, ln, recv, arg=''):
    """'v2' = 当 Vector2 处理(要走 DetMath); 'other' = Vector3/Color/String 等(不进 sim)。ln 从 0 起。
    接收者判不出来时再看第一个实参(a.lerp(b, t) / a.dot(b) 里 b 是 3D 的, a 也是)。"""
    k = _recv_kind1(lines, ln, recv)
    line = lines[ln] if 0 <= ln < len(lines) else ''
    ## ★这一行在写 sim 状态 ⇒ 一律当 Vector2(宁可多改一处, 不许把 sim 漏成「3D 放行」)。
    ##   真是 3D 字面量(Vector3(/Color()的, 引擎会在解析期报类型错, 不会静默。
    if _SIM_WRITE.search(line[:line.find('#')] if '#' in line else line) and not re.match(r'^(Vector3|Color)\(', recv):
        return 'v2'
    if k == 'v2' and arg and not re.match(r'^[-0-9.]', arg):
        if _V3.search(arg) or _STRISH.search(arg):
            return 'other'
        m = re.match(r'^\(*([A-Za-z_]\w*)\s*(\)|$)', arg)
        if m and _decl_kind(lines, ln, m.group(1)) == 'other':
            return 'other'
    if k == 'v2' and re.search(r'\.(position|global_position|scale)\s*=', line):
        return 'other'
    return k


def _recv_kind1(lines, ln, recv):
    if _V3.search(recv) or _STRISH.search(recv):
        return 'other'
    if '["pos"]' in recv or recv.startswith('Vector2(') or 'as Vector2)' in recv:
        return 'v2'
    m = re.match(r'^\(*([A-Za-z_]\w*)', recv)
    if not m:
        return 'v2'
    name = m.group(1)
    if name in ('self', 'battle', 'b', 'u', 'o', 'e', 't', 'a') and '.' in recv:
        return 'v2'
    k = _decl_kind(lines, ln, name)
    if k == 'v2' and recv.startswith('(') and re.search(r'\b(\w+)\b', recv[1:]):
        ## (a - b) 这种: 里面任何一个名字是 3D 的就算 3D
        for nm in re.findall(r'[A-Za-z_]\w*', recv):
            if nm != name and _decl_kind(lines, ln, nm) == 'other':
                return 'other'
    return k


def func_ranges(lines):
    """[(起, 止)) 每个顶层函数(含 static)的行区间(lines 不带行尾)。"""
    starts = [i for i, l in enumerate(lines) if re.match(r'^(static\s+)?func\s', l)]
    out = []
    for k, s in enumerate(starts):
        e = starts[k + 1] if k + 1 < len(starts) else len(lines)
        out.append((s, e))
    return out


def sim_func_lines(lines, code_end):
    """演出文件里「碰了 sim 状态」的函数覆盖的行号集合(0 起)。"""
    keep = set()
    for s, e in func_ranges(lines):
        body = '\n'.join(x[:code_end(x)] for x in lines[s:e])
        if SIM_MARK.search(body):
            keep.update(range(s, e))
    return keep


def triple_string_lines(lines):
    """落在 \"\"\" 多行字符串里的行(0 起; 含开闭那两行) —— 着色器源码住在这里, 不是 GDScript。"""
    out = set()
    inside = False
    for i, l in enumerate(lines):
        n = l.count('"""')
        if inside or n:
            out.add(i)
        if n % 2 == 1:
            inside = not inside
    return out
