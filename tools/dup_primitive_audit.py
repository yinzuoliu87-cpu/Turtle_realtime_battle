# -*- coding: utf-8 -*-
"""dup_primitive_audit.py — 同一个「共享原语」的实现被**复制到多个文件**里各存一份。

═══════════════════════════════════════════════════════════════════════════
 ★由来(2026-09-29): 8 份 `_tri` / 6 份 `_flat` / 5 份 `RING_LON`
═══════════════════════════════════════════════════════════════════════════
程序化贴地环的三段几何在 `scripts/scenes/battle/*_vfx.gd` 里**各手写一份**:

  · 顶点色三角形  `_tri`      —— 7 份, 加 synergy_vfx 改名成 `_tri3` 的第 8 份
  · 贴地环顶点    `_flat`     —— 3 份, 加改名成 `_flat_vert` 的 3 份, 共 6 份
  · 经向分段      `RING_LON`  —— 5 份

命中本仓两条血债 memory:
  · [[fb-hand-rolled-copies-drift]]  抄一次就永远落后 —— 改一处, 另外七处不跟。
  · [[fb-refactor-creates-the-drift-it-removes]]  抽到共享文件却忘了让原处去读它,
    于是"抽取"本身**制造了**它要消除的漂移。

已抽到 `scripts/util/vfx_geom.gd`(`VfxGeom.tri` / `VfxGeom.flat` / `VfxGeom.RING_LON`)。
这个审计器不负责抽, 负责**不让它长回来**。

═══════════════════════════════════════════════════════════════════════════
 ★判据为什么按 **body 哈希** 而不是按函数名(改名会把副本藏起来)
═══════════════════════════════════════════════════════════════════════════
按名字找 `_tri` 只有 7 份; 按 body 找是 **8 份** —— synergy_vfx 里那份叫 `_tri3`。
`_flat` 同理: 3 份 `_flat` + 3 份 `_flat_vert`。
⇒ 哈希时**把签名行里的函数名抠掉**, 只留参数表 + 函数体, 改名躲不掉。

═══════════════════════════════════════════════════════════════════════════
 ★判据为什么只看 `static func`(先写宽后收窄的记录, 别再放宽)
═══════════════════════════════════════════════════════════════════════════
第一版不分静态与否, 全仓扫出 31 组跨文件同 body, **绝大多数是假阳**:
  `_init` **85 份**(本仓 `RefCounted` + 构造注入的拆分模板, CLAUDE.md §5 写着照抄)、
  `_has_world` 16 份、`on_magic_hurt` / `on_mana_full` / `on_hit` / `on_damaged`
  各 4~6 份(装备效果的**接口钩子**, 每个类必须自己实现一份, 那是多态不是复制)。
收窄成 `static func` 之后: 分母 785 个静态函数, 跨文件同 body **只剩 6 组 / 13 份多余**,
而 `_tri` + `_flat` 两族就占了 10 份 —— 判据刚好卡住那个形状。
  ⇒ 道理: `static` = 不碰实例状态的纯 helper, **天生就该只有一份**;
    实例方法跨文件同 body 通常是"每个类各实现一次接口", 那是对的。

═══════════════════════════════════════════════════════════════════════════
 ★为什么"纯转发"不算副本(第一版把自己的正确修法判红了)
═══════════════════════════════════════════════════════════════════════════
`_flat` 的 6 份 body **一模一样**, 但语义并不相同 —— 它们各自解析自己文件的
`GROUND_Y`, 而全仓 13 个 `GROUND_Y` 有 **4 个取值**(0.03 / 0.055 / 0.06 / 0.07,
各件特效的离地高度本来就不一样)。所以 `VfxGeom.flat()` 收了个 `gy` 参数,
6 个消费方各留**一行适配器**把自己的 `GROUND_Y` 绑上去。
这 6 行适配器**又是彼此逐字相同的** —— 但里面没有任何被复制的逻辑, 逻辑只有一份。
⇒ body 是单条 `return Xxx.yyy(...)` 的**纯转发**一律豁免。
  这与 `twin_const_audit.py` 里那条同源(「一侧写成 `别的类名.同名常量` = 正是我们要的
  修法, 不能报成分歧 —— 第一版就把自己的正确修法判红了」)。

用法:
    python tools/dup_primitive_audit.py            # 只读判定(进门禁)
    python tools/dup_primitive_audit.py --update    # 打印可粘贴的新台账(不自动写)
"""
import hashlib
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCAN_DIRS = ["scripts"]

## 共享原语的所在。这个文件自己当然可以定义它们。
OWNER = "scripts/util/vfx_geom.gd"

FUNC = re.compile(rb"^[ \t]*(static[ \t]+)?func[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(")
CONST_ANY = re.compile(
    rb"^[ \t]*const[ \t]+([A-Z][A-Z0-9_]{2,})[ \t]*(?::=|:[ \t]*\w+[ \t]*=|=)", re.M)
## 纯转发: body 只有一条 `return Xxx.yyy(...)` / `Xxx.yyy(...)`(Xxx 是大写开头的外部类名)
FORWARD = re.compile(r"^[ \t]*(?:return[ \t]+)?[A-Z][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\(")
## ★适配器**必须把自己的 `GROUND_Y` 传下去**, 不许写成字面量。
##   这个洞是反向验证时露出来的: `return VfxGeom.flat(r, th, a, 0.06)` 也是"纯转发",
##   判据会放它过 —— 而 potion 的离地高度是 **0.055**, 写 0.06 就是画面回归,
##   正是"顺手把 GROUND_Y 一起搬走"那个 bug 的等价形态。
##   (memory [[fb-judge-must-fit-the-shape]]: 判据宽一格就放过真 bug。)
FORWARD_GY = re.compile(r"VfxGeom\.flat\([^()]*,[ \t]*GROUND_Y[ \t]*\)")

## ══════════════════════════════════════════════════════════════════════
##  台账①: 跨文件同 body 的 static func。`"名字@行数": 允许的文件数`
##  **只减不增** —— 少了打 `[已清]` 不判红, 多了/新出现当场红。
##  ★这张表是 `--update` 从真扫描生成的, 不是手抄(memory [[fb-hand-rolled-copies-drift]])。
##  存量这 6 份都不是本次要修的东西, 各自有各自的判断要做, 先钉住现状不让它长:
##    · `_set_a` / `_holdfade` / `_mat`  —— 演出材质/淡出的小 helper, 两两成对
##    · `glow`/`gold_glow`, `_hash`/`_hh`, `guard_open`/`step_response`,
##      `crown_height`/`reap_hop`, `_is_mobile`/`is_mobile` —— 改名藏起来的副本
## ══════════════════════════════════════════════════════════════════════
## ★存量 7 组**全部落在 `scripts/scenes/battle/*_vfx.gd`** 里(记台账时逐组核过文件清单,
##   确认没有把当时并行的别人未提交的改动记成存量 —— `_ledger_guard` 提醒的正是这一下)。
DUP_LEDGER = {
    "_set_a@9": 2,                     # blade_eq_vfx / golden_shot_vfx
    "_holdfade@6": 2,                  # holy_shield_vfx / incense_vfx
    "_mat@13": 2,                      # potion_eq_vfx / venom_drone_vfx
    "guard_open,step_response@6": 2,   # blade_eq_vfx / bow_eq_vfx      (改名藏起来的)
    "crown_height,reap_hop@4": 2,      # food_eq_vfx / synergy_vfx      (改名藏起来的)
    "glow,gold_glow@3": 2,             # golden_shot_vfx / gun_eq_vfx   (改名藏起来的)
    "_hash,_hh@3": 2,                   # mana_beam_vfx / spirit_eq_vfx  (改名藏起来的)
}
## ⚠ 曾经这里还有一条 `"_is_mobile,is_mobile@3": 2`
##   (RealtimeBattle3DScene `_is_mobile` / safe_area `is_mobile`)。**那是我写错的**:
##   建台账时我用的探针把**整条签名行**都抠掉了(只留函数体), 于是参数表不同的两个函数
##   也被归成一组; 而审计器只抠**函数名**、保留参数表 —— 它俩签名不同, 本来就不是一组。
##   ⇒ 删掉它不是"去重了一处", 是**台账当初记错了**。台账也是手抄的副本, 一样会漂。

## ══════════════════════════════════════════════════════════════════════
##  台账②: 已经归 `VfxGeom` 的名字, 别处**一个都不许再定义**(硬 0, 不是棘轮)。
##  ★`_flat` / `_flat_vert` 例外: 允许**纯转发**的那一行适配器(要绑自己的 GROUND_Y),
##    body 只要不是纯转发就是副本回来了。
##  ★`_tri` 连同名都不许 —— relic_eq_vfx 里原来有个**同名不同物**的 `_tri`
##    (签名 Vector3 而非 Array, 算的是面法线不是顶点色), 已改名 `_tri_normal`。
##    两个 `_tri` 各干一件事本身就是地雷, 所以这里连名字一起焊死。
## ══════════════════════════════════════════════════════════════════════
OWNED_FUNCS_NO_REDEF = ["_tri", "_tri3"]
OWNED_FUNCS_FORWARD_ONLY = ["_flat", "_flat_vert"]
OWNED_CONSTS = ["RING_LON"]


def iter_gd():
    for d in SCAN_DIRS:
        for dp, _dn, names in os.walk(os.path.join(ROOT, d)):
            for nm in names:
                if nm.endswith(".gd"):
                    p = os.path.join(dp, nm)
                    yield os.path.relpath(p, ROOT).replace("\\", "/"), p


def funcs_of(path):
    """→ [(name, is_static, line, body_bytes)]。按字节读, 行尾原样保留。"""
    raw = io.open(path, "rb").read()
    lines = raw.splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        m = FUNC.match(lines[i])
        if not m:
            i += 1
            continue
        chunk = [lines[i]]
        j = i + 1
        while j < len(lines):
            s = lines[j].rstrip(b"\r\n")
            if s == b"" or re.match(rb"^[ \t]", lines[j]):
                chunk.append(lines[j])
                j += 1
                continue
            break
        while chunk and chunk[-1].rstrip(b"\r\n") == b"":
            chunk.pop()
        out.append((m.group(2).decode(), m.group(1) is not None, i + 1, b"".join(chunk)))
        i = j
    return out


def body_only(body):
    """去掉签名行里的函数名 ⇒ 改名藏不住副本。行尾统一成 LF(本仓行尾是混的)。"""
    norm = body.replace(b"\r\n", b"\n")
    nl = norm.split(b"\n")
    sig = re.sub(rb"func[ \t]+[A-Za-z_][A-Za-z0-9_]*", b"func <NAME>", nl[0], count=1)
    return b"\n".join([sig] + nl[1:]), norm


def is_forward(body):
    """body(不含签名行)只有一条 `Xxx.yyy(...)` ⇒ 纯转发, 不是副本。"""
    norm = body.replace(b"\r\n", b"\n").decode("utf-8", "replace")
    rest = [l for l in norm.split("\n")[1:]
            if l.strip() and not l.strip().startswith("#")]
    return len(rest) == 1 and FORWARD.match(rest[0]) is not None


def main():
    do_update = "--update" in sys.argv

    nfiles = 0
    nstatic = 0
    nconst = 0
    groups = {}          # key -> [(rel, name, line)]
    owned_func_defs = {}  # name -> [(rel, line, forward?)]
    owned_const_defs = {}  # name -> [(rel, line)]

    for rel, full in iter_gd():
        nfiles += 1
        raw = io.open(full, "rb").read()
        for m in CONST_ANY.finditer(raw):
            nconst += 1
            nm = m.group(1).decode()
            if nm in OWNED_CONSTS:
                ln = raw[:m.start()].count(b"\n") + 1
                owned_const_defs.setdefault(nm, []).append((rel, ln))
        for name, is_static, line, body in funcs_of(full):
            if name in OWNED_FUNCS_NO_REDEF or name in OWNED_FUNCS_FORWARD_ONLY:
                owned_func_defs.setdefault(name, []).append(
                    (rel, line, is_forward(body),
                     body.replace(b"\r\n", b"\n").decode("utf-8", "replace")))
            if not is_static:
                continue
            nstatic += 1
            if is_forward(body):
                continue                      # 纯转发不算副本(见文件头)
            key, norm = body_only(body)
            groups.setdefault(hashlib.md5(key).hexdigest(),
                              {"n": norm.count(b"\n") + 1, "hits": []})["hits"].append(
                                  (rel, name, line))

    print("=== 共享原语重复定义审计 ===")
    print("  [分母] 扫描 %d 个 .gd · %d 个 static func · %d 条 const 定义"
          % (nfiles, nstatic, nconst))

    ## ── 空检查哨兵: 收集失效时必须红, 不能读成"没有重复" ──
    ##   (本仓老规矩: 判 0 之前先打分母 —— memory [[fb-redirect-order-fake-green]];
    ##    glow_ball_audit 就因为漏了这一条, 拷到别处跑时 96 处白球变成 ALL OK。)
    if nfiles < 50 or nstatic < 200:
        print("")
        print("  [FAIL] 只扫到 %d 个 .gd / %d 个 static func —— 收集失效了(cwd 不对?), "
              "这是空检查不是通过。" % (nfiles, nstatic))
        return 1

    ## ── 判据①: 跨文件同 body 的 static func(棘轮) ──
    found = {}
    for g in groups.values():
        hits = g["hits"]
        files = sorted({r for r, _n, _l in hits})
        if len(files) < 2:
            continue
        names = sorted({n for _r, n, _l in hits})
        found["%s@%d" % (",".join(names), g["n"])] = (files, hits)

    print("  [分母] 跨文件同 body 的 static func 组: %d 组 / 多余副本 %d 份 · "
          "台账登记 %d 组" % (len(found), sum(len(v[0]) - 1 for v in found.values()),
                             len(DUP_LEDGER)))

    bad = []
    cleared = []
    for key in sorted(set(list(found.keys()) + list(DUP_LEDGER.keys()))):
        got = len(found[key][0]) if key in found else 0
        cap = DUP_LEDGER.get(key, 0)
        if got > cap:
            hits = found[key][1]
            loc = "\n".join("           %s  %s L%d" % (r, n, l) for r, n, l in hits)
            bad.append(
                "[FAIL] `%s` 的同一份实现出现在 %d 个文件(台账允许 %d):\n%s\n"
                "       ⇒ 抽到一处共享位置(纯数据/常量 → scripts/gamedata/,\n"
                "         通用工具 → scripts/util/, 见 CLAUDE.md §5), **并且把原处都改成读它**。\n"
                "         只抽不改原处 = 抽取本身制造了它要消除的漂移\n"
                "         (memory [[fb-refactor-creates-the-drift-it-removes]])。"
                % (key, got, cap, loc))
        elif got < cap:
            ## ★"变少了"是这条判据的目的, 不判红 —— 与 glow_ball / write_orphan
            ##   / nine_downgrade 统一口径(本仓 2026-09-28 把这一族的 got<cap 全改成不红,
            ##   因为它曾**真的拦住过一次正当的删除**)。
            cleared.append("  [已清] `%s` 只剩 %d 个文件(台账写着 %d) —— 不判红; "
                           "把 DUP_LEDGER 改成 %d(或删掉这一行)。" % (key, got, cap, got))

    ## ── 判据②: VfxGeom 拥有的名字不许在别处重新定义 ──
    print("  [分母] 受管名字: func %s(禁重定义) / %s(仅许纯转发) / const %s"
          % (OWNED_FUNCS_NO_REDEF, OWNED_FUNCS_FORWARD_ONLY, OWNED_CONSTS))
    n_fwd = 0
    for nm in OWNED_FUNCS_NO_REDEF:
        for rel, ln, _fwd, _bt in owned_func_defs.get(nm, []):
            if rel == OWNER:
                continue
            bad.append("[FAIL] %s L%d 又定义了 `%s` —— 这个原语已归 `VfxGeom.tri()`。\n"
                       "       同名不同物也不行: relic_eq_vfx 曾有个算面法线的 `_tri`,\n"
                       "       和顶点色那个**签名与 body 都不同** ⇒ 已改名 `_tri_normal`。"
                       % (rel, ln, nm))
    for nm in OWNED_FUNCS_FORWARD_ONLY:
        for rel, ln, fwd, body_txt in owned_func_defs.get(nm, []):
            if rel == OWNER:
                continue
            if not fwd:
                bad.append("[FAIL] %s L%d 的 `%s` 不是纯转发 —— 副本回来了。\n"
                           "       这里只许留**一行**把自己的 GROUND_Y 绑上去的适配器:\n"
                           "           return VfxGeom.flat(r, th, a, GROUND_Y)"
                           % (rel, ln, nm))
                continue
            ## 是转发, 但传下去的必须是**本文件的 GROUND_Y**, 不是字面量
            if FORWARD_GY.search(body_txt) is None:
                bad.append("[FAIL] %s L%d 的 `%s` 转发了, 但最后一个实参不是 `GROUND_Y`:\n"
                           "           %s\n"
                           "       适配器的**唯一职责**就是把本文件的离地高度绑上去。写成字面量 =\n"
                           "       把 GROUND_Y 又抄了一份, 而各件特效的取值本来就不同\n"
                           "       (potion 是 0.055 / venom_drone 是 0.07 / axe_ember 是 0.03)。"
                           % (rel, ln, nm, body_txt.strip().splitlines()[-1].strip()))
                continue
            n_fwd += 1
    for nm in OWNED_CONSTS:
        for rel, ln in owned_const_defs.get(nm, []):
            if rel == OWNER:
                continue
            bad.append("[FAIL] %s L%d 又定义了 `const %s` —— 已归 `VfxGeom.RING_LON`。\n"
                       "       若这一处真需要**别的**分段数, 那它就不是同一个量: 换个名字\n"
                       "       (spirit_eq_vfx 的环面经向就是这么留下的 —— `RING_TORUS_LON := 40`,\n"
                       "        它与 `RING_TUBE` 成对, 和贴地平环不是一回事)。" % (rel, ln, nm))

    ## ★分母哨兵: 适配器一个都没找到 ⇒ 判据②的"仅许纯转发"那一支**根本没被走到**,
    ##   那是空检查(memory [[fb-gate-subject-never-constructed]]: 每条断言配一条分母断言)。
    if n_fwd == 0:
        bad.append("[FAIL] 全仓 0 个 `_flat`/`_flat_vert` 适配器 —— "
                   "「仅许纯转发」这一支没有被测对象, 是空检查不是通过。")
    else:
        print("  [分母] GROUND_Y 绑定适配器(纯转发, 豁免): %d 个" % n_fwd)

    print("")
    for c in cleared:
        print(c)
    if cleared:
        print("")

    if do_update:
        from _ledger_guard import warn_if_dirty
        warn_if_dirty(SCAN_DIRS, ROOT)
        print("  ── 可粘贴的新 DUP_LEDGER ──")
        print("DUP_LEDGER = {")
        for key in sorted(found, key=lambda k: -len(found[k][0])):
            print('    "%s": %d,' % (key, len(found[key][0])))
        print("}")
        print("")

    if bad:
        for b in bad:
            print(b)
        print("FAILED: %d 处" % len(bad))
        return 1
    print("  [台账] 存量 %d 组跨文件同 body 的 static helper 待各自判断(只减不增)"
          % len(found))
    print("ALL OK — 共享原语没有新的重复定义")
    return 0


if __name__ == "__main__":
    sys.exit(main())
