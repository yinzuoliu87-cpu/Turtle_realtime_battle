# -*- coding: utf-8 -*-
"""零调用者审计 —— 「写进去了没人读」的通用探测器 (2026-09-01)

════════════════════════════════════════════════════════════════════════
 ★由来
════════════════════════════════════════════════════════════════════════
2026-09-01 我给四个最终造物写完全部行为、门禁 64 条全绿、11 个变异全红，
然后用户说「你先继续找漏洞」。一扫才发现：

    undead_on_death / seraph_boomerang_settle / holo_aura_tick / ember_light_cast
    —— 产品代码里**一个调用者都没有**

也就是说四个造物的主动**一个都放不出来**、亡灵之斧**死了不会重生**。
而门禁全绿，因为门禁**直接调那些函数**，从没证明"游戏里真的会走到"。

这是一整类错，不是一次意外。同族记录：
  · memory [[fb-verify-must-run-the-real-path]]：我"目视确认新实现"看的是零调用者的死函数
  · memory [[fb-write-without-reader-and-fake-gates]]：一天三次"生产侧写了消费侧没读"
  · memory [[fb-gate-must-measure-requirement-not-my-hook]]：断言自己插的标记 = 插一行数一行必绿

★仓库里已有的 `deadcode_audit.py` **抓不到这一类** —— 它只看 `_do_skill` 的 match 分支
  能不能被技能池分派到，管不到"新写的类里有没有人调它的方法"。

════════════════════════════════════════════════════════════════════════
 ★判据（两次修正才对，留档免得再走弯路）
════════════════════════════════════════════════════════════════════════
第一版：只数**别的文件**里的调用 ⇒ 误报 4 个（它们是被同文件的分派器调的）。
        判据太窄 = 造假 bug。
现在：  函数「活」= 全仓（**含本文件**，但不含定义行）至少有一个调用点。
        再单独报一列"外部入口"，方便看这个模块是从哪儿被驱动的。

★留了 `# zero-caller-ok: 原因` 的豁免注释 —— 但**必须写原因**，且会被打印出来，
  数量涨了看得见。（不写原因不给过：无声豁免等于没有规则。）

════════════════════════════════════════════════════════════════════════
 ★★★已知盲区：同名方法互相掩护（2026-09-05 量的，别以为这条门禁是全覆盖的）
════════════════════════════════════════════════════════════════════════
主判据是「名字 `\bfn\b` 在全仓出现过就算有人调」。**同一个名字被多个类定义时，
它们互相掩护**：只要任意一个被调过，全部定义处都算活的。

实测（受检目录 106 文件 / 1658 个函数名）：
  · **44 个名字**被 ≥2 个文件定义，共 **246 个定义处**
  · `clear_all` 16 处 · `tick` 36 处 · `on_hit` 11 处 · `_ring_mesh` 5 处 …

这不是假想。**`IncenseStoneSystem.clear_all()` 就是这么漏过去的** ——
它写着完整的换路撤场（写回存档 → `_revoke()` → 复位加载闸 → 清香台），
**全仓零调用者**，而这条门禁一直报绿，因为另外 15 个 `clear_all` 有人调。
（那一条实测**无功能后果**，见它自己的 `zero-caller-ok` 注释。）

⇒ 下面加了**第二道网**（`same_name_dead`）：对同名方法的**每个定义处**单独判 ——
   ① 同文件内有裸调 `fn(`，或 ② 全仓/tests 有限定调用 `X.fn(`；两者皆无 = 死。
   实测它在 246 个定义处里恰好抓到 **1 个真死函数**（`potion_eq_vfx._ring_mesh`，
   2026-08-11 用户批"程序生成的圆环"后换了真瓶子立绘，函数留着 23 行没人调），
   **零误报**，所以直接当红灯用，不留台账。

★第二道网**仍不完备**：它的 ② 是「全仓任何地方有 `X.fn(`」，
  所以 `clear_all` 这种"有别的持有者在调"的情况照样漏。要真收口得做
  class → 持有字段 的类型映射，而那条路实测会漏四类
  （`:=` 声明 / preload 别名 / 跨文件赋值 / 只看 `clear_all` 不看 `clear`），
  成本远大于收益。**写在这里是为了下一个人不会以为这条门禁已经全覆盖。**
"""
import io
import json
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

## 受检目录：**行为代码**。纯数据表（gamedata）与场景脚本另论 ——
## 数据表里的常量本来就可能只被文案引用，误报会把这条门禁变成噪音。
ROOTS = ["scripts/systems", "scripts/scenes/battle"]
## 引擎回调 / 生命周期：Godot 自己调，永远看不到调用点。
ENGINE = {
    "_init", "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_draw", "_notification", "_enter_tree", "_exit_tree", "_to_string", "_get",
    "_set", "_get_property_list", "_gui_input", "_unhandled_key_input",
}
EXEMPT_RE = re.compile(r"#\s*zero-caller-ok:\s*(.+)")
## 存量欠债台账 —— 见 main() 里那段注释
LEDGER = os.path.join("tools", "zero_caller_debt.json")


def gd_files(roots):
    out = []
    for r in roots:
        for dirpath, _dirs, files in os.walk(r):
            for f in files:
                if f.endswith(".gd"):
                    out.append(os.path.join(dirpath, f).replace(os.sep, "/"))
    return sorted(out)


def main():
    files = gd_files(ROOTS)
    if not files:
        print("[FAIL] 一个 .gd 都没扫到 —— 目录写错了, 这是空检查不是通过")
        return 1
    ## 全仓源码（含 autoload 与 scripts 全部，调用可能来自任何地方）
    allsrc = {}
    for dirpath, _d, fs in os.walk("scripts"):
        for f in fs:
            if f.endswith(".gd"):
                p = os.path.join(dirpath, f).replace(os.sep, "/")
                allsrc[p] = io.open(p, encoding="utf-8", errors="replace").read()
    for f in os.listdir("autoload"):
        if f.endswith(".gd"):
            p = "autoload/" + f
            allsrc[p] = io.open(p, encoding="utf-8", errors="replace").read()
    ## ★门禁探针也算"有人读"——但**分开算**。
    ##   仓库里有一大批只给门禁用的读数函数(sentinel_* / b81_guarding / height_profile_of …),
    ##   它们**故意**只被 tests/ 调用: 产品不需要它们, 门禁需要它们把内部状态读出来。
    ##   不算进来会误报 40 多个 ⇒ 这条门禁立刻变成噪音, 而噪音门禁等于没门禁。
    testsrc = {}
    if os.path.isdir("tests"):
        for f in os.listdir("tests"):
            if f.endswith(".gd"):
                p = "tests/" + f
                testsrc[p] = io.open(p, encoding="utf-8", errors="replace").read()

    n_fun = 0
    dead = []
    exempt = []
    probes = []
    for path in files:
        src = allsrc.get(path, "")
        if not src:
            continue
        lines = src.split("\n")
        for i, ln in enumerate(lines):
            m = re.match(r"^func\s+([A-Za-z_][A-Za-z0-9_]*)", ln)
            if not m:
                continue
            fn = m.group(1)
            if fn in ENGINE:
                continue
            n_fun += 1
            ## 豁免注释：允许写在 func 行本身，或它上面那一行
            ex = EXEMPT_RE.search(ln) or (EXEMPT_RE.search(lines[i - 1]) if i > 0 else None)
            if ex:
                exempt.append("%s:%s  (%s)" % (os.path.basename(path), fn, ex.group(1).strip()[:50]))
                continue
            ## ★数**名字的出现**而不是 `name(` —— 见头注「判据」那一段:
            ##   `.bind()` 引用式调用(tween_callback(_xxx.bind(...))) 名字后面没有括号,
            ##   只数 `name(` 会把 17 个活函数判成死的(2026-09-01 实测)。
            pat = re.compile(r"\b" + re.escape(fn) + r"\b")
            defpat = re.compile(r"^func\s+" + re.escape(fn) + r"\b.*$", re.M)
            hits = 0
            for p2, s2 in allsrc.items():
                body = defpat.sub("", s2) if p2 == path else s2
                hits += len(pat.findall(body))
            if hits == 0:
                ## 产品里没人调 —— 再看门禁里有没有
                thits = 0
                for _p3, s3 in testsrc.items():
                    thits += len(pat.findall(s3))
                if thits > 0:
                    probes.append("%s:%s" % (os.path.basename(path), fn))
                else:
                    dead.append("%s:%d  %s" % (path, i + 1, fn))

    ## ══════════════════════════════════════════════════════════════
    ##  第二道网：同名方法互相掩护（见文件头「已知盲区」）
    ## ══════════════════════════════════════════════════════════════
    ## 主判据按名字数，同名方法只要有一个被调，全部定义处都算活的。
    ## 这里对**每个定义处**单独判：① 同文件内有裸调 `fn(`，或
    ## ② 全仓/tests 有限定调用 `X.fn(`；两者皆无 = 死。
    defs_by_name = {}
    for path in files:
        src = allsrc.get(path, "")
        for i, ln in enumerate(src.split("\n")):
            m = re.match(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)", ln)
            if not m or m.group(1) in ENGINE:
                continue
            ex = EXEMPT_RE.search(ln)
            if ex:
                continue
            defs_by_name.setdefault(m.group(1), []).append((path, i + 1))
    multi = {k: v for k, v in defs_by_name.items() if len(v) >= 2}
    whole = "\n".join(allsrc.values())
    wtests = "\n".join(testsrc.values())
    same_name_dead = []
    n_multi_sites = 0
    for fn, sites in multi.items():
        qual = re.compile(r"[A-Za-z_0-9\]\"]\." + re.escape(fn) + r"\s*\(")
        bare = re.compile(r"(?<![\w\.])" + re.escape(fn) + r"\s*\(")
        has_qual = bool(qual.search(whole)) or bool(qual.search(wtests))
        for p, ln in sites:
            n_multi_sites += 1
            body = re.sub(r"^(?:static\s+)?func\s+" + re.escape(fn) + r"\b.*$", "",
                          allsrc[p], flags=re.M)
            if not bare.search(body) and not has_qual:
                same_name_dead.append("%s:%d  %s" % (p, ln, fn))

    print("  [分母] 扫描 %d 个文件 · %d 个函数 (受检目录: %s)"
          % (len(files), n_fun, " ".join(ROOTS)))
    print("  [分母] 第二道网: %d 个名字被 ≥2 文件定义 · 共 %d 个定义处"
          % (len(multi), n_multi_sites))
    if len(multi) < 10 or n_multi_sites < 50:
        print("")
        print("[FAIL] 同名方法只找到 %d 个名字 / %d 个定义处 —— 分母过小, 第二道网是空检查"
              % (len(multi), n_multi_sites))
        return 1
    if exempt:
        print("  [豁免] %d 个（每个都写了原因）:" % len(exempt))
        for e in exempt[:10]:
            print("     " + e)
    if probes:
        print("  [门禁探针] %d 个只被 tests/ 调用(这是**故意的**: 产品不需要, 门禁要读内部状态)"
              % len(probes))
    if n_fun < 200:
        print("")
        print("[FAIL] 只扫到 %d 个函数(<200) —— 分母过小, 这是空检查不是通过" % n_fun)
        return 1
    ## ★★台账: 存量欠债**只减不增**(照 arch_budget 的老规矩)。
    ##   实测存量 10 个, 全是别人早年留下的; 一刀切要求清零 = 这条门禁第一天就红,
    ##   而第一天就红的门禁只会被 `|| true` 掉。新增的必须当场红, 存量慢慢还。
    ledger = {}
    if os.path.exists(LEDGER):
        try:
            ledger = json.load(io.open(LEDGER, encoding="utf-8"))
        except Exception:
            ledger = {}
    known = set(ledger.get("known", []))
    fresh = [d for d in dead if d.split("  ")[-1] not in known]
    if os.environ.get("ZERO_CALLER_UPDATE") == "1":
        io.open(LEDGER, "w", encoding="utf-8").write(json.dumps(
            {"known": sorted(d.split("  ")[-1] for d in dead)},
            ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (%d 个存量)" % (LEDGER, len(dead)))
        return 0
    if dead and not fresh:
        print("")
        print("  [存量] %d 个在台账里(只减不增; 新增的会当场红)" % len(dead))
    dead = fresh
    if dead:
        print("")
        print("[FAIL] **新增**了写了却没有任何人调的函数 %d 个:" % len(dead))
        for d in dead:
            print("   " + d)
        print("")
        print("  （四个最终造物的主动就是这么漏掉的：函数写好、门禁全绿、游戏里放不出来。")
        print("    确实不该有调用者的，加注释 `# zero-caller-ok: 原因`，原因会被打印出来。）")
        return 1
    ## 第二道网**不留台账**（实测存量为 0，零误报）—— 新增当场红。
    if same_name_dead:
        print("")
        print("[FAIL] **同名掩护**下的死函数 %d 个（主判据按名字数，抓不到这一类）:"
              % len(same_name_dead))
        for d in same_name_dead:
            print("   " + d)
        print("")
        print("  （同一个名字被多个类定义时会互相掩护：只要任意一个被调过，主判据就全部报绿。")
        print("    这一列是对**每个定义处**单独判的 —— 同文件裸调 或 任意处 `X.fn(` 限定调用，")
        print("    两者皆无。确实不该有调用者的，加 `# zero-caller-ok: 原因`。）")
        return 1

    print("")
    print("ALL OK — 没有「写了没人读」的函数")
    return 0


if __name__ == "__main__":
    sys.exit(main())
