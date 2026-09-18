# -*- coding: utf-8 -*-
"""★草稿★ 恒真常量分支审计 —— 「有调用者却永远到不了」的第三道网 (2026-09-18 起草)

⚠ 这是**草稿**, 放在 scratchpad 里。定案后的落点是 `tools/zero_caller_audit.py` 的
   第三道网(和第一/二道网同文件、同一个 rc), 或独立成 tools/const_branch_audit.py。
   两种都行, 判据不变。

════════════════════════════════════════════════════════════════════════
 ★由来 (R11 · 2026-09-18)
════════════════════════════════════════════════════════════════════════
`battle_world_builder._build_ground()` 里:

    if battle.MAP_V2 or OS.has_environment("TILEMAP") or OS.has_environment("MAPEDIT"):
        _build_tilemap_ground(); return
    <后面 19 行旧地面分支>            ← 永远执行不到

`MAP_V2` 是 `const MAP_V2 := true`, **编译期恒真** ⇒ 那个 `return` 把同函数后续
整段吞掉。牵连出来的 `_make_ground_material`(71 行 shader)/`_build_arena_ring`/
`VfxTex._make_arena_ring_texture`/`ARENA_RING_*` 全是死的。

★`zero_caller_audit` 的两道网**都抓不到**: 它们问的是「有没有调用者」,
  而上面每一个**都有调用者** —— 整条链是在顶上被一个恒真常量剪断的。
  这是「写了没人读」的**新形状**: 不是没人调, 是那个调用点自己到不了。

★旁证(当时被误判了): `tests/shot_skill_ring_phases.gd:15` 写着
  「⚠ 实测记录: BLACKMAP=1 【没有】把地图变黑(它管的是环境背景那一层)」——
  那正是 `_build_ground()` 第 504 行「地面纯黑」分支到不了的表现,
  当时被解释成「它管的是环境背景那一层」就停止追查了。**这条门禁会直接指着行号说话。**

════════════════════════════════════════════════════════════════════════
 ★判据 —— 四个条件全中才报红 (刚好卡住这一个形状, 不许放宽)
════════════════════════════════════════════════════════════════════════
  ① 条件里引用了某个 `const X := true` / `:= false`(含 `obj.X` 的限定写法)
  ② 该条件**因此编译期恒真**  (`CONST_TRUE or 任意` 恒真 · `not CONST_FALSE` 恒真)
  ③ 分支体的**最后一条顶层语句是 `return`**
  ④ 这个 `if` 之后(跳过 elif/else 链), 同一函数里**还有真代码**

  ①②③④ ⇒ ④ 那段代码永远执行不到 = 报红。

★为什么一条都不能松 —— 全仓只有 6 个 `const := true/false`, 其中 **5 个是刻意留的
  A/B 开关**(`tentacle_vfx.gd` 注释明写「旧的运动学路径保留在 SIM_ON=false 分支里,
  只为出问题时能一键对照」)。**把这 5 个报红 = 判据形状错了, 要收窄, 不是加白名单。**
  实测这 5 个各自为什么不中(逐条量过, 别再重查):

    NO_DRAW               只出现在注释里, 连 if 都没有            → ① 不中
    REVIEW_DEMO_DEFAULT   `return REVIEW_DEMO_DEFAULT and ...`   → 是 return 不是 if, ① 不中
    REVIEW_DUMMY_KILLABLE `if not battle.X:` 体是两行赋值         → ③ 不中(不以 return 收尾)
    REVIEW_DUMMY_ATTACKS  同上                                    → ③ 不中
    SIM_ON                `if SIM_ON == false and ...: continue`  → ③ 不中(continue 不是 return)
                          `if SIM_ON:` 体是一行赋值               → ③ 不中
                          `if SIM_ON and 运行期条件:`             → ② 不中(不恒定)

  另外 `MAP_V2` 在 `_build_camera` 里还有一处 `if battle.MAP_V2 or ...:`(行 370),
  那处体内是两行赋值、不 return ⇒ ③ 不中, **不报**。它确实没吞掉任何东西, 报它就是假 bug。

★恒**假**分支(`if CONST_FALSE and ...:`)**不在本网的射程里**: 恒假分支吞不掉后面的代码,
  它的毛病是「体本身是死的」, 而那正是 A/B 开关**故意**的样子(SIM_ON == false 那条)。
  本脚本会把恒假分支的条数打进分母(看得见), 但不红。要管那一类得另立判据。

════════════════════════════════════════════════════════════════════════
 ★自检 (--selftest) —— 「一条都没红」不是运气好, 可能是判据是假的
════════════════════════════════════════════════════════════════════════
  · 阳性夹具(照抄 MAP_V2 的形状)必须被抓到;
  · 阴性夹具(照抄 SIM_ON / REVIEW_DUMMY_* 的 A/B 形状)必须**一条都不报**。
  两边都过才允许继续扫仓库。自检失败直接 rc=1。

 ★反向验证钩子: 环境变量 `CONSTBRANCH_RELAX` 可以把某一条判据故意拆掉,
   用来证明每一条都**在承重**(拆掉后结果必须变)。取值:
     return      —— 不要求③(分支体以 return 收尾)
     after       —— 不要求④(后面还有代码)
     constref    —— 不要求①(条件里真的引用了那个常量)
     value       —— 把常量值全当成 true(故意读错值)
   ⚠ 这几个只给反向验证用, 正式跑门禁时**不许设**。脚本会在输出里大声标出来。

 ★★实测结果(2026-09-18, 别再重跑一遍):
   · RELAX=return   ⇒ **自检当场红**(阴性夹具多报 SIM_ON 那处) —— 判据③承重, 且自检能发现它被拆
   · RELAX=after    ⇒ **自检当场红**(阴性夹具多报"恒真+return 但后面没代码"那处) —— 判据④承重
   · RELAX=constref ⇒ 自检过、仓库结果不变(仍 1 处)。**这一条在本仓实测【不承重】** ——
                      因为不引用常量的条件一律折不成常量。留着是防将来有人写 `if true:`,
                      **不许把它当成"验过了"的证据**。
   · RELAX=value    ⇒ 仓库结果不变(仍 1 处), 但分母变了(恒真 4→3 / 恒假 2→3)。
                      ⇒ **光看 rc 看不出常量值读错**, 分母那两行才看得出来 —— 所以分母必须打。
   另有 7 条在**副本**上做的定点变异(scratchpad/r11/反向验证.py), 全部符合预期:
     ①MAP_V2 值读成 false ⇒ 0 处  ②套上删除补丁 ⇒ 0 处  ③留着 if 但后面无代码 ⇒ 0 处
     ④把 return 拿掉 ⇒ 0 处       ⑤注入一处新违规 ⇒ 当场红(2 处)
     ⑥注入"return 嵌在里层 if"的近似形状 ⇒ 不报  ⑦常量表清空 ⇒ 0 处
   ⚠ 变异 ⑦ 第一版写成 `consts or CONSTS`, **空字典是 falsy** ⇒ 喂进去的还是全表、报 1 处,
     我差点判成"判据有问题"。变异脚本自己失败 = 假证据(memory fb-mutation-script-failure-is-a-red)。
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOTS = ["scripts", "autoload"]

# `const NAME := true` / `const NAME: bool = false` 两种写法都认
CONST_DECL = re.compile(
    r"^[\t ]*const[\t ]+([A-Za-z_][A-Za-z0-9_]*)[\t ]*"
    r"(?::=|:[\t ]*bool[\t ]*=)[\t ]*(true|false)[\t ]*(?:#.*)?$"
)
IF_LINE = re.compile(r"^([\t ]*)if[\t ]+(.*)$")

RELAX = os.environ.get("CONSTBRANCH_RELAX", "").strip()


# ─────────────────────────────────────────────────────────────────────
#  小词法: 去注释 / 顶层切分 —— 都要**跳过字符串里的字符**
# ─────────────────────────────────────────────────────────────────────
def strip_comment(line):
    """去掉行尾 `#` 注释。★字符串里的 `#` 不算(颜色字面量 "#1a2340" 满仓都是)。"""
    out = []
    q = None
    i = 0
    while i < len(line):
        ch = line[i]
        if q:
            if ch == "\\":
                out.append(ch)
                if i + 1 < len(line):
                    out.append(line[i + 1])
                    i += 2
                    continue
            elif ch == q:
                q = None
            out.append(ch)
        else:
            if ch in "\"'":
                q = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out)


def split_top(text, sep):
    """按 sep 切分, 但只在括号深度 0 且不在字符串里的位置切。sep 形如 ' or '。"""
    parts = []
    depth = 0
    q = None
    last = 0
    i = 0
    n = len(sep)
    while i < len(text):
        ch = text[i]
        if q:
            if ch == "\\":
                i += 2
                continue
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "\"'":
            q = ch
            i += 1
            continue
        if ch in "([{":
            depth += 1
            i += 1
            continue
        if ch in ")]}":
            depth -= 1
            i += 1
            continue
        if depth == 0 and text.startswith(sep, i):
            parts.append(text[last:i])
            i += n
            last = i
            continue
        i += 1
    parts.append(text[last:])
    return parts


def first_top_colon(text):
    """返回第一个「顶层、不在字符串里」的 `:` 的下标; 没有返回 -1。
    ★if 语句的块冒号就是它 —— 字典字面量/类型标注的冒号都在括号里或在冒号之后。"""
    depth = 0
    q = None
    i = 0
    while i < len(text):
        ch = text[i]
        if q:
            if ch == "\\":
                i += 2
                continue
            if ch == q:
                q = None
            i += 1
            continue
        if ch in "\"'":
            q = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == ":" and depth == 0:
            return i
        i += 1
    return -1


def unwrap_parens(t):
    t = t.strip()
    while t.startswith("(") and t.endswith(")"):
        depth = 0
        ok = True
        for k, ch in enumerate(t):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and k != len(t) - 1:
                    ok = False
                    break
        if not ok:
            break
        t = t[1:-1].strip()
    return t


REF_RE = re.compile(r"^(?:[A-Za-z_][A-Za-z0-9_]*\.)?([A-Za-z_][A-Za-z0-9_]*)$")


def atom_value(term, consts, seen):
    """单个原子项的编译期值: True / False / None(运行期决定)。
    认得 `X` · `obj.X` · `not X` · `X == true` · `X != false` 这几种写法。"""
    t = unwrap_parens(term)
    neg = False
    while t.startswith("not ") or t.startswith("!"):
        neg = not neg
        t = t[4:].strip() if t.startswith("not ") else t[1:].strip()
        t = unwrap_parens(t)
    lit = None
    m = re.match(r"^(.+?)[\t ]*(==|!=)[\t ]*(true|false)$", t)
    if m:
        t = unwrap_parens(m.group(1))
        lit = (m.group(3) == "true") if m.group(2) == "==" else (m.group(3) != "true")
    m2 = REF_RE.match(t)
    if not m2 or m2.group(1) not in consts:
        return None
    seen.add(m2.group(1))
    val = consts[m2.group(1)]
    if RELAX == "value":
        val = True                       # 反向验证: 故意把常量值全读成 true
    if lit is not None:
        val = (val == lit)
    return (not val) if neg else val


def eval_cond(cond, consts, seen):
    """整条条件的编译期值。只做 or/and 两层折叠 —— 够用, 且不会把运行期项算成常量。"""
    vals = []
    for o in split_top(cond, " or "):
        avals = [atom_value(a, consts, seen) for a in split_top(o, " and ")]
        if any(v is False for v in avals):
            vals.append(False)
        elif avals and all(v is True for v in avals):
            vals.append(True)
        else:
            vals.append(None)
    if any(v is True for v in vals):
        return True
    if vals and all(v is False for v in vals):
        return False
    return None


def ind_len(line):
    n = 0
    for ch in line:
        if ch in "\t ":
            n += 1
        else:
            break
    return n


def is_blankish(line):
    s = strip_comment(line).strip()
    return s == ""


def ends_with_return(block, base_ind):
    """分支体的**最后一条顶层语句**是不是 `return`。
    ★必须是**顶层**(缩进 == 分支体基准缩进) —— 嵌在里层 if 里的 return 是条件性的,
      吞不掉后面的代码, 算进来就是宽一格造假 bug。"""
    last = None
    for ln in block:
        if is_blankish(ln):
            continue
        last = ln
    if last is None:
        return False
    if ind_len(last) != base_ind:
        return False
    code = strip_comment(last).strip()
    segs = [s.strip() for s in split_top(code, ";")]
    segs = [s for s in segs if s]
    if not segs:
        return False
    return re.match(r"^return\b", segs[-1]) is not None or segs[-1] == "return"


def scan_file(path, consts):
    """返回 (hits, n_if, n_const_true, n_const_false)。"""
    src = io.open(path, encoding="utf-8", errors="replace", newline="").read()
    lines = src.replace("\r\n", "\n").split("\n")
    hits = []
    n_if = n_true = n_false = 0
    for i, raw in enumerate(lines):
        m = IF_LINE.match(raw)
        if not m:
            continue
        n_if += 1
        if_ind = len(m.group(1))
        code = strip_comment(raw)
        ci = first_top_colon(code)
        if ci < 0:
            continue                      # 跨行条件等 —— 本网不处理
        cond = code[code.index("if") + 2:ci].strip()
        inline = code[ci + 1:].strip()
        seen = set()
        val = eval_cond(cond, consts, seen)
        if not seen and RELAX != "constref":
            continue                      # ① 条件里没有引用已知常量
        if val is False:
            n_false += 1
            continue                      # 恒假分支不在本网射程(见文件头)
        if val is not True:
            continue
        n_true += 1
        # ── 分支体 ────────────────────────────────────────────────
        if inline:
            block = [("\t" * (if_ind + 1)) + inline]
            base = if_ind + 1
            end = i                       # 单行体, 块到本行为止
        else:
            j = i + 1
            block = []
            while j < len(lines):
                ln = lines[j]
                if is_blankish(ln):
                    block.append(ln)
                    j += 1
                    continue
                if ind_len(ln) <= if_ind:
                    break
                block.append(ln)
                j += 1
            end = j - 1
            base = None
            for ln in block:
                if not is_blankish(ln):
                    base = ind_len(ln)
                    break
            if base is None:
                continue
        ok_ret = ends_with_return(block, base)
        if RELAX != "return" and not ok_ret:
            continue                      # ③
        # ── 跳过 elif / else 链 ───────────────────────────────────
        k = end + 1
        while k < len(lines):
            while k < len(lines) and is_blankish(lines[k]):
                k += 1
            if k >= len(lines):
                break
            ln = lines[k]
            s = strip_comment(ln).strip()
            if ind_len(ln) == if_ind and (s.startswith("elif ") or s.startswith("else:")
                                          or s == "else:"):
                k += 1
                while k < len(lines) and (is_blankish(lines[k]) or ind_len(lines[k]) > if_ind):
                    k += 1
                continue
            break
        # ── ④ 同一函数里, 这个 if 之后还有真代码 ──────────────────
        after = None
        while k < len(lines):
            ln = lines[k]
            if is_blankish(ln):
                k += 1
                continue
            if ind_len(ln) == 0:
                break                     # 缩进回到 0 列 = 函数结束了
            if ind_len(ln) >= if_ind:
                after = (k + 1, strip_comment(ln).strip())
            break
        if RELAX != "after" and after is None:
            continue
        hits.append({
            "file": path, "line": i + 1, "cond": cond,
            "consts": sorted(seen),
            "ret": ok_ret,
            "after": after, "dead_from": (end + 2),
        })
    return hits, n_if, n_true, n_false


# ─────────────────────────────────────────────────────────────────────
#  自检夹具 —— 先证明「它会红」和「它不会乱红」, 再去扫仓库
# ─────────────────────────────────────────────────────────────────────
POS_FIXTURE = """extends Node
const MAP_V2 := true
func _build_ground() -> void:
\tif battle.MAP_V2 or OS.has_environment("TILEMAP"):    # 恒真
\t\t_build_tilemap_ground(); return
\tvar mi = MeshInstance3D.new()
\tmi.name = "Ground"
\tbattle._world.add_child(mi)
"""

NEG_FIXTURE = """extends Node
const SIM_ON := true
const REVIEW_DUMMY_ATTACKS := true
const REVIEW_DEMO_DEFAULT := false
func _review_demo() -> bool:
\treturn REVIEW_DEMO_DEFAULT and OS.is_debug_build()
func _tick() -> void:
\tfor t in list:
\t\tif SIM_ON == false and int(t["state"]) == 0:
\t\t\tcontinue
\t\t_rebuild(t)
func _rebuild(t) -> void:
\tif SIM_ON:
\t\tsimpts = _sim_chain(t)
\tvar stool := SurfaceTool.new()
\tif SIM_ON and simpts.size() == 9:
\t\treturn
\tstool.begin(0)
func _spawn() -> void:
\tif not REVIEW_DUMMY_ATTACKS:
\t\tru["no_basic"] = true
\t\tru["no_move"] = true
\tru["active_skills"] = []
func _tail_ok() -> void:
\tif SIM_ON:
\t\t_do(); return
"""


def selftest(tmpdir):
    ## ★夹具写系统临时目录, 绝不落进仓库(门禁跑时改仓库=整轮作废)。
    ##   自己建的自己删 —— 门禁一天跑很多轮, 不清理就攒一地 constbranch_* 空目录。
    import tempfile, shutil, atexit
    owned = tmpdir is None
    d = tmpdir or tempfile.mkdtemp(prefix="constbranch_")
    if owned:
        atexit.register(lambda: shutil.rmtree(d, ignore_errors=True))
    pp = os.path.join(d, "_pos.gd")
    np_ = os.path.join(d, "_neg.gd")
    io.open(pp, "w", encoding="utf-8", newline="").write(POS_FIXTURE)
    io.open(np_, "w", encoding="utf-8", newline="").write(NEG_FIXTURE)
    consts = {"MAP_V2": True, "SIM_ON": True, "REVIEW_DUMMY_ATTACKS": True,
              "REVIEW_DEMO_DEFAULT": False}
    ph, _, _, _ = scan_file(pp, consts)
    nh, _, _, _ = scan_file(np_, consts)
    ok = True
    if len(ph) != 1:
        print("[FAIL] 自检: 阳性夹具(MAP_V2 形状)应抓到 1 处, 实得 %d" % len(ph))
        ok = False
    if nh:
        print("[FAIL] 自检: 阴性夹具(A/B 开关形状)应 0 处, 实得 %d —— %s"
              % (len(nh), nh))
        ok = False
    ## ★阴性夹具最后那个 `_tail_ok` 是【恒真 + return 但后面没代码】——
    ##   它证明判据④在承重: 少了④它会被当成红, 而它其实什么都没吞。
    print("  [自检] 阳性 %d/1 · 阴性 %d/0 → %s" % (len(ph), len(nh), "OK" if ok else "FAIL"))
    return ok


def main():
    if RELAX:
        print("  ⚠⚠ CONSTBRANCH_RELAX=%s —— 判据被故意拆掉一条, 这是**反向验证模式**,"
              " 结果不作数" % RELAX)
    if not selftest(None):
        return 1
    files = []
    for r in ROOTS:
        if not os.path.isdir(r):
            continue
        for dp, _d, fs in os.walk(r):
            for f in fs:
                if f.endswith(".gd"):
                    files.append(os.path.join(dp, f).replace(os.sep, "/"))
    files.sort()
    if not files:
        print("[FAIL] 一个 .gd 都没扫到 —— 目录写错了, 这是空检查不是通过")
        return 1
    # ── 收全仓的 const bool ───────────────────────────────────────
    consts = {}
    decl_at = {}
    for p in files:
        src = io.open(p, encoding="utf-8", errors="replace", newline="").read()
        for i, ln in enumerate(src.replace("\r\n", "\n").split("\n")):
            m = CONST_DECL.match(ln)
            if m:
                consts[m.group(1)] = (m.group(2) == "true")
                decl_at[m.group(1)] = "%s:%d" % (p, i + 1)
    hits = []
    n_if = n_true = n_false = 0
    for p in files:
        h, a, b, c = scan_file(p, consts)
        hits += h
        n_if += a
        n_true += b
        n_false += c
    print("  [分母] 扫描 %d 个 .gd (根: %s)" % (len(files), " ".join(ROOTS)))
    print("  [分母] 找到 %d 个 `const X := true/false`:" % len(consts))
    for k in sorted(consts):
        print("           %-24s = %-5s  %s" % (k, str(consts[k]).lower(), decl_at[k]))
    print("  [分母] 扫过 %d 条 if · 其中因常量【恒真】%d 条 · 【恒假】%d 条(恒假不在本网射程)"
          % (n_if, n_true, n_false))
    if len(consts) < 3 or n_if < 500:
        print("")
        print("[FAIL] 分母过小(const %d / if %d) —— 这是空检查不是通过" % (len(consts), n_if))
        return 1
    if hits:
        print("")
        print("[FAIL] 恒真常量分支把同函数后续代码吞成死代码 —— %d 处:" % len(hits))
        for h in hits:
            print("   %s:%d" % (h["file"], h["line"]))
            print("       条件  : if %s:" % h["cond"][:96])
            print("       恒真因: %s (const)" % ", ".join(h["consts"]))
            print("       分支体 以 return 收尾 ⇒ 第 %d 行起【永远执行不到】:" % h["dead_from"])
            print("           %d: %s" % (h["after"][0], h["after"][1][:96]))
        print("")
        print("  （zero_caller 的两道网抓不到这一类: 那下面每个函数**都有调用者**,")
        print("    只是整条链在顶上被一个恒真常量剪断了。")
        print("    修法二选一: ①删掉到不了的那段(推荐) ②把常量换成运行期开关。")
        print("    确实是刻意留的 A/B 对照, 那它就不该以 return 收尾 —— 改成 if/else。）")
        return 1
    print("")
    print("ALL OK — 没有被恒真常量吞掉的代码段")
    return 0


if __name__ == "__main__":
    sys.exit(main())
