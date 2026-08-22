# -*- coding: utf-8 -*-
"""derived_consts.py — 解析 GDScript 里的【推导式常量】。

★★★由来(2026-08-22 · 文案根除分歧工程的配套)

根除分歧的做法是: 把散在代码里的字面量抽成具名常量, 文案用 `{C:类名.常量}` 引用,
改一处两边同时变。做龟壳·暗影时遇到两个必须**推导**的量:

    const BURN_SLOW_MULT := 1.0 - BURN_SLOW_PCT      # 移速乘数由"减速比例"算出
    const BURN_LIFE      := BURN_TICKS * BURN_TICK_SEC  # 总时长由次数×间隔算出

推导是**正确设计** —— 语义值(减速 20%)只存一份, 实现值(移速 ×0.8)算出来。
如果为了迁就工具而在代码里再手写一个 0.8, 那正是我在根除的那类病。

但仓库里几个审计器的常量解析都只认 `const X := <纯数字>`, 遇到推导式就拿到常量名而不是数,
于是:
  · `text_golden` 把 `{C:...BURN_LIFE}` 原样留在快照里(看着像"文案没渲染")
  · `pet_code_scope` 把 `spd_move_mult = BURN_SLOW_MULT` 读成 ×1.0
    ⇒ **把「减速 20%」报成了「加速」**

⇒ 抽成这一份共享实现, 三个工具都用它, 不各写一遍(手抄的副本必然漂)。

安全性: 表达式先过白名单正则(只许字母/数字/下划线/点/四则/括号/空格), 变量必须全部是
**本类已知的数值常量**, eval 的 `__builtins__` 清空。拿不准的一律跳过, 不猜。
"""
import re

CONST_NUM = re.compile(r'^\s*const\s+([A-Z][A-Z0-9_]*)\s*(?::=|=|:\s*\w+\s*=)\s*(-?[\d.]+)\s*(?:#.*)?$', re.M)
CONST_ANY = re.compile(r'^\s*const\s+([A-Z][A-Z0-9_]*)\s*(?::=|=|:\s*\w+\s*=)\s*([^#\n]+?)\s*(?:#.*)?$', re.M)
SAFE_EXPR = re.compile(r'[A-Za-z0-9_.+*/() -]+')
IDENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
# GDScript 的类型包装: float(X) / int(X) —— 对取值没有影响, 剥掉再算
CAST = re.compile(r'\b(?:float|int)\s*\(')


def _fmt(v):
    return str(int(v)) if float(v) == int(v) else str(float(v))


def numeric_consts(src_text):
    """只取 `const X := <纯数字>` 的那些。返回 {名: 字符串数值}。"""
    return {m.group(1): m.group(2) for m in CONST_NUM.finditer(src_text)}


def derive(src_text, base=None):
    """在 base(纯数字常量表)之上补齐**推导式**常量。

    ★多趟直到不再增长 —— 推导可以套推导(A 由 B 算, B 由 C 算)。
      单趟的话顺序一变就漏, 那种漏很隐蔽(工具照常绿, 只是少认一个常量)。
    """
    out = dict(base) if base is not None else numeric_consts(src_text)
    for _ in range(6):                       # 上限防环形引用死循环
        grew = False
        for m in CONST_ANY.finditer(src_text):
            nm, ex = m.group(1), m.group(2).strip()
            if nm in out:
                continue
            ex = CAST.sub('(', ex)
            names = set(IDENT.findall(ex))
            if not names or not names.issubset(set(out.keys())):
                continue
            if not SAFE_EXPR.fullmatch(ex):
                continue
            try:
                env = {k: float(out[k]) for k in names}
            except ValueError:
                continue                     # 数组等非数值常量不参与推导
            try:
                v = eval(ex, {"__builtins__": {}}, env)
            except Exception:
                continue
            if isinstance(v, (int, float)):
                out[nm] = _fmt(v)
                grew = True
        if not grew:
            break
    return out


def selftest():
    """★自证: 不先证明它算得对, 后面三个工具都会跟着错。"""
    src = "\n".join([
        "const A := 10",
        "const B := 0.5",
        "const C := A * B          # 推导",
        "const D := 1.0 - B        # 推导",
        "const E := float(A) * B   # 带 float() 包装",
        "const F := C + D          # 推导套推导",
        "const G := [1, 2, 3]      # 数组: 不该参与",
        "const H := some_func()    # 函数调用: 不该参与",
    ])
    got = derive(src)
    want = {"A": "10", "B": "0.5", "C": "5", "D": "0.5", "E": "5", "F": "5.5"}
    bad = [k for k, v in want.items() if got.get(k) != v]
    extra = [k for k in ("G", "H") if k in got]
    ## ★★负例(2026-08-22 实测踩到): `numeric_consts` 的正则**必须锚行尾**。
    ##   仓库里三个工具各抄了一份 `^const X :?= ([\d.]+)`(没锚 `$`), 遇到
    ##   `const D := 1.0 - B` 就截下开头的 `1.0` 塞进表里; 而 `derive` 会跳过
    ##   "已在表里"的名字 ⇒ 推导式常量永远拿不到真值。
    ##   实测后果: `pet_code_scope` 把「减速 20%」读成「加速 ×1.0」,
    ##   `pet_number_audit` 据此报「代码有效果但文案没写」的假警。
    ##   ⇒ 这条断言就是那个坑本身: D 是推导式, **不许**出现在 numeric_consts 里。
    nc = numeric_consts(src)
    leak = [k for k in ("C", "D", "E", "F") if k in nc]
    ok = not bad and not extra and not leak
    print("  自证 %s  算错的 %s · 不该收却收了的 %s · 被截半截的推导式 %s" % (
        "OK" if ok else "★FAIL", bad or "无", extra or "无", leak or "无"))
    return ok


if __name__ == '__main__':
    import sys
    sys.exit(0 if selftest() else 1)
