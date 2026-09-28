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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gd_text_scan as _G          # noqa: E402  共享的"去行尾注释"实现(会跳过字符串里的 #)


def _decomment(src):
    """去掉行尾注释后的源码。

    ★★为什么必须去: 主判据数的是"名字在全仓出现过", 它不区分代码和注释 ⇒
      **一句追忆往事的注释就能让一个死函数永远活着**。
      实证: `RealtimeBattle3DScene.gd:8604 _fill_equip_section()` 零调用点,
      而 `info_panel.gd:226` 有一行注释提到它的名字 ⇒ 扩了 ROOTS 之后**依然报绿**。
      实测去注释后受检全域的死函数 16 → 30, 多出来的 14 个全是真死代码。
    ★不能用 `line.split("#")[0]` —— 本仓文案里到处是 `#ffd93d` 颜色码,
      一刀切会把半句话当注释切掉。`gd_text_scan.strip_comment` 已经处理过字符串。
    """
    return NL.join(_G.strip_comment(l) for l in src.split(NL))

NL = chr(10)

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

## ══════════════════════════════════════════════════════════════════════
##  ★★★洞③(2026-09-28)：ROOTS 原来只有两个目录 —— **那是盲区，不是许可**
## ══════════════════════════════════════════════════════════════════════
## 原来写的是 `["scripts/systems", "scripts/scenes/battle"]`，理由栏写着
## 「纯数据表（gamedata）与场景脚本另论」。**场景脚本正是屏幕代码住的地方**，
## 于是这两类死代码一直没人看得见：
##   · `scripts/scenes/RealtimeBattle3DScene.gd:8606` `_fill_equip_section()`
##     （文案「装备 (%d)」，正是用户点名的括号计数形状）—— **零调用点**
##   · `scripts/gamedata/phase2_config.gd` `now_utc()` 这条新开的时间缝
##     —— 零个**产品**调用者
## 两个都因为「ROOTS 不含那些目录」而报绿。
## ⇒ 扩到 `scripts/` 全部。误报的代价用存量台账 + `# zero-caller-ok:` 吸收，
##   **不靠缩小扫描范围换绿灯**。
## ★★★洞⑤(2026-09-28)：`autoload/` 也从来不判 —— 又一个"盲区不是许可"
## 洞③ 把 ROOTS 从两个子目录扩到了 `scripts`, 但 `autoload/` 仍在**受检集之外**
## (它一直在 `allsrc` 里当"调用方"被搜, 却从不作为"被检对象")。
## 活实例(清死码那轮实测撞到): 删掉 `GameState.ai_dual_shop()` 之后**搁浅了三个函数**
##   —— `buy_xp` / `buy_shop_item` / `equip_to_turtle`(0 产品 / 0 测试调用),
## 而这条判据**一条级联红都没有**。同批还照出既有的 `grant_dual_round`。
## ⇒ 受检集含 `autoload/`。扩出来的存量进台账**带理由**
##   (那三个被 `docs/archive/V2-阶段1-砍局内经济商店-实施规格.md` §3 明确留给阶段2 局外商店)。
ROOTS = ["scripts", "autoload"]
## 引擎回调 / 生命周期：Godot 自己调，永远看不到调用点。
ENGINE = {
    "_init", "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
    "_draw", "_notification", "_enter_tree", "_exit_tree", "_to_string", "_get",
    "_set", "_get_property_list", "_gui_input", "_unhandled_key_input",
    ## ★2026-09-28 补: `Control._make_custom_tooltip` 也是**引擎虚函数**(悬浮提示时
    ##   引擎自己调), 名单里漏了它 ⇒ `rich_tooltip.gd:11` 与 `SkillTipButton.gd:8`
    ##   两处被第三道网报成"同名跨类掩护"嫌疑, 而它们**本来就不该有调用点**。
    ##   (`rich_tooltip.gd:6` 头注自己写着「给格子挂上这个脚本, 覆写 _make_custom_tooltip」。)
    "_make_custom_tooltip", "_can_drop_data", "_drop_data", "_get_drag_data",
    "_has_point", "_structured_text_parser", "_get_minimum_size", "_shortcut_input",
}
EXEMPT_RE = re.compile(r"#\s*zero-caller-ok:\s*(.+)")

## ══════════════════════════════════════════════════════════════════════
##  存量的【理由】—— 台账是脚本生成的, 理由只能住在这儿
## ══════════════════════════════════════════════════════════════════════
## ★为什么不用 `# zero-caller-ok:`: 那条注释要写进**产品源码**, 而"这一批是扩了
##   扫描范围才露头的旧存量"是**审计器这一侧**的事实, 不该往 28 个产品文件里撒注释。
## ★★不写理由的台账 = "看着很周全": 下一个人看到 39 行函数名, 没法分辨哪些是
##   "查过确实该留"、哪些是"没人看过"。⇒ 没理由的会被打成【欠一条理由】并计数,
##   涨了看得见(与 nine_downgrade 的 WHY / codex_text_lint 的 GD_WHY 同一口径)。
## ★每条都去看过出处, 不是按名字猜的。引文都核对过原文。
DEBT_WHY = {
    ## 【V2 阶段1 明确留给阶段2 的商店算法】—— 原文见
    ## docs/archive/V2-阶段1-砍局内经济商店-实施规格.md:17
    ## 「商店算法值钱、留给局外: …/buy_shop_item/…/equip_to_turtle 是纯逻辑无 UI 耦合,
    ##   阶段 2 局外商店直接复用 —— 阶段 1 只删『战斗内呈现 + 调用』, 不删算法」
    "buy_shop_item": "V2阶段1规格:17 明确留给阶段2局外商店复用(只删战斗内调用, 不删算法)",
    "equip_to_turtle": "同上(V2阶段1规格:17 的同一句名单里)",
    ## 同文件 :46「`buy_xp` UI 入口随商店删, 函数留, 阶段 2 局外接钮」
    "buy_xp": "V2阶段1规格:46「UI 入口随商店删, 函数留, 阶段2局外接钮」",
    ## 同文件 :15 把 grant_dual_round 的 XP 段与币段拆开; 清死码那轮核实它是**既有**存量
    "grant_dual_round": "V2阶段1规格:15 的 XP↔币解耦对象; 清死码那轮核实是既有存量, 不是删出来的",
    ## docs/archive/PHASE2-LEVEL-DESIGN.md:17
    ## 「`shop_cost_odds(局内等级)` 直接用, 替掉原 `stage_for_shop_visit(开店次数)`」
    "stage_for_shop_visit": "PHASE2-LEVEL-DESIGN:17 已被 shop_cost_odds(局内等级) 替掉(旧档映射)",
}
## 存量欠债台账 —— 见 main() 里那段注释
LEDGER = os.path.join("tools", "zero_caller_debt.json")
## 第二道网的台账。原来它**没有台账**(注释写着"实测存量为 0, 零误报 ⇒ 直接当红灯用"),
## 而那个 0 是在 `systems + scenes/battle` 那个范围内量的。2026-09-28 扩到 `scripts/`
## 全域之后有了 1 条**真**存量(`RecordScene._stroked_label`, 与设置屏同名同签名的
## 复制粘贴残留) ⇒ 照本仓老规矩: 存量记台账只减不增, 新增当场红。
## **不许**为了让它绿回去而缩小范围或放宽判据。
LEDGER2 = os.path.join("tools", "zero_caller_samename_debt.json")


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

    ## ══════════════════════════════════════════════════════════════
    ##  预分词(见下面主判据里的等价性说明)
    ## ══════════════════════════════════════════════════════════════
    WORD = re.compile(r"\w+")
    ## ★★2026-09-28 洞④: 原来是 `^func\s+` ⇒ **`static func` 整类不可见**。
    ##   活实例: `scripts/gamedata/phase2_config.gd:612 static func stage_for_shop_visit`
    ##   全仓零调用(`docs/archive/PHASE2-LEVEL-DESIGN.md:17` 记着它被
    ##   `shop_cost_odds(局内等级)` 替掉了) —— 而这条判据从来没看见过它。
    ##   第二道网早就写的是 `^(?:static\s+)?func`, 主网漏了 ⇒ 两张网口径不一致。
    FUNCLINE = re.compile(r"(?m)^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\b.*$")
    ## ★分词表一律用**去掉注释**的源码(见 `_decomment` 的长注释)
    nocmt = {k: _decomment(v) for k, v in allsrc.items()}
    nocmt_t = {k: _decomment(v) for k, v in testsrc.items()}
    tok_total = {}
    for _s in nocmt.values():
        for t in WORD.findall(_s):
            tok_total[t] = tok_total.get(t, 0) + 1
    tok_tests = {}
    for _s in nocmt_t.values():
        for t in WORD.findall(_s):
            tok_tests[t] = tok_tests.get(t, 0) + 1
    ## 每个文件里, 它自己的 `^func <名字> …` 行上**那个名字**出现了几次
    own_defline = {}
    for _p, _s in nocmt.items():
        d0 = {}
        for m0 in FUNCLINE.finditer(_s):
            nm0 = m0.group(1)
            d0[nm0] = d0.get(nm0, 0) + len([t for t in WORD.findall(m0.group(0)) if t == nm0])
        own_defline[_p] = d0

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
            m = re.match(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)", ln)
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
            ##
            ## ★★2026-09-28(洞③ 扩 ROOTS 时)把这里从「每个函数 × 每个文件各跑一次
            ##   `\bfn\b` 正则」换成**预先分词后查计数表**。判定**逐字等价**:
            ##   `re.findall(r"\w+", src)` 切出的是**极大字符串**, 而 `\bfn\b`
            ##   命中一次 ⟺ 有一个切片恰好等于 fn(两边的"词"是同一个定义, `\w`
            ##   连中文也算词字符 ⇒ 「汉字foo」两边都不算命中, 一致)。
            ##   `defpat.sub` 那一步 = 只从**本文件**里减掉 `^func fn…` 那些行上
            ##   fn 自己出现的次数 ⇒ 等价于 `tok_total[fn] - own_defline[path][fn]`。
            ##   ⇒ O(函数数 × 文件数) 降到 O(源码总量)。扩了 ROOTS 还更快。
            hits = tok_total.get(fn, 0) - own_defline.get(path, {}).get(fn, 0)
            if hits == 0:
                ## 产品里没人调 —— 再看门禁里有没有
                thits = tok_tests.get(fn, 0)
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
    ## ★同样预扫一遍(判定等价, 只是把「每个定义处重跑一次 re.sub + search」
    ##   换成查表): `QUAL` 收全仓/tests 里所有 `X.fn(` 的名字;
    ##   `BARE` 收每个文件里所有裸调 `fn(` 的名字, 再减掉它自己 `func fn(` 那几行贡献的。
    QUAL = re.compile(r"[A-Za-z_0-9\]\"]\.([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    BARE = re.compile(r"(?<![\w\.])([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    SFUNCLINE = re.compile(r"(?m)^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\b.*$")
    qual_names = set()
    ## ★字符串派发: `has_method("fn")` / `Callable(host, "fn")` / `call("fn")`。
    ##   不收这一支, 5 个屏的 `_tutorial_anchor` 会全被判死 —— 它们是被
    ##   `TutorialGuide.gd:256` 用字符串调到的。
    STRLIT = re.compile(r'"([A-Za-z_][A-Za-z0-9_]*)"')
    str_names = set()
    for _s in list(nocmt.values()) + list(nocmt_t.values()):
        qual_names.update(QUAL.findall(_s))
        str_names.update(STRLIT.findall(_s))
    ## ★同文件里这个名字**作为一个词**出现过就算活(不要求后面跟括号)。
    ##   场景脚本的主力写法是**裸引用**: `back.pressed.connect(_on_back)`、
    ##   `{"on_back": _on_back}`、`_xxx.bind(...)` —— 名字后面都没有括号。
    ##   只数 `fn(` 在 `scenes/` 里会连报 `_on_back` / `_on_resize` 一类, 全是误报。
    bare_in = {}
    for _p, _s in nocmt.items():
        c0 = {}
        for nm0 in WORD.findall(_s):
            c0[nm0] = c0.get(nm0, 0) + 1
        for m0 in SFUNCLINE.finditer(_s):
            for nm1 in WORD.findall(m0.group(0)):
                if nm1 == m0.group(1):
                    c0[nm1] = c0.get(nm1, 0) - 1
        bare_in[_p] = c0
    same_name_dead = []
    n_multi_sites = 0
    for fn, sites in multi.items():
        has_qual = fn in qual_names or fn in str_names
        for p, ln in sites:
            n_multi_sites += 1
            if bare_in.get(p, {}).get(fn, 0) <= 0 and not has_qual:
                same_name_dead.append("%s:%d  %s" % (p, ln, fn))

    ## ══════════════════════════════════════════════════════════════════
    ##  第三道网【同名跨类掩护】—— 洞⑦ (2026-09-28)
    ## ══════════════════════════════════════════════════════════════════
    ## 第二道网的 `has_qual` 是**全仓一个集合**: 只要仓库里任何地方出现过 `X.fn(`,
    ## `fn` 的**每一个**定义处都算活的。⇒ 两个类各有一个同名方法时, 一边被调
    ## 就把另一边**一起掩护掉**。
    ## ★活实例(清死码那轮实测撞到): `RecordScene._mono_font` 零调用却报绿 ——
    ##   因为 `scripts/scenes/codex/list_builder.gd:93` 调的是 `host._mono_font()`,
    ##   而那个 `host` 是 **CodexScene**。同一个名字, 两个类, 一边的调用替另一边站了岗。
    ##
    ## ★★这一网**只报不判红**(存量进台账, 新增也只打印), 理由是它靠"接收者能不能
    ##   绑到这个类"的**推断**, 而推断错的方向是**把活函数说成死的** —— 那比漏报贵。
    ##   ⇒ 先当"嫌疑清单"用, 攒够实测再考虑升级成红灯。**判据的强弱写在这里, 不含糊。**
    ##
    ## 能把一处 `recv.fn(` 绑到定义文件 P 的**强信号**(只认这三种, 不猜):
    ##   ① 调用方文件里出现了 P 的 `class_name`(`var x: CodexScene` / `CodexScene.new(`);
    ##   ② P 是 autoload, 且 `recv` 正好是它的 autoload 名(`GameState.fn(`);
    ##   ③ 调用方文件 F 是被 P 构造的(P 里有 `<F的class_name>.new(`) ⇒ F 里的
    ##      `host`/`owner` 一类注入引用指回 P(本仓 RefCounted + 构造注入的标准写法)。
    CLASSNAME = re.compile(r"(?m)^class_name\s+([A-Za-z_][A-Za-z0-9_]*)")
    cls_of = {}                      # 文件 → class_name
    for _p, _s in nocmt.items():
        _m = CLASSNAME.search(_s)
        if _m:
            cls_of[_p] = _m.group(1)
    auto_of = {}                     # autoload 文件 → 它的全局名(按文件名, 本仓一致)
    for _p in nocmt:
        if _p.startswith("autoload/"):
            auto_of[_p] = os.path.basename(_p)[:-3]
    ## P 构造了谁: P 里有 `Foo.new(` 且 Foo 是某文件的 class_name ⇒ 那个文件被 P 构造
    built_by = {}                    # 被构造的文件 → {构造它的文件}
    cls2file = {v: k for k, v in cls_of.items()}
    for _p, _s in nocmt.items():
        for _m2 in re.finditer(r"\b([A-Z][A-Za-z0-9_]*)\s*\.\s*new\s*\(", _s):
            _f2 = cls2file.get(_m2.group(1))
            if _f2:
                built_by.setdefault(_f2, set()).add(_p)

    ## ★★头两版的强信号只有三条(class_name 提及 / autoload 名 / 构造边单向),
    ##   实测 30 条嫌疑里**大部分是误报** —— 逐条看出来缺的是下面两类接收者, 补上:
    ##   ④【preload 别名】`const _P2 = preload("res://scripts/gamedata/phase2_config.gd")`
    ##      之后 `_P2.display_name(...)`。这是**按文件路径**绑, 是最硬的一种,
    ##      而前三条一条都覆盖不到它 ⇒ `phase2_config`/`phase2_types` 的 `display_name`
    ##      两边都被误报成嫌疑(它们其实都活着: backend.gd:944 / synergy_panel.gd:20)。
    ##   ⑤【字段类型】`var _synergy := SynergySystem.new(self)` / `var _wd: BattleWatchdog`
    ##      之后别处写 `battle._synergy.apply_all()` / `_wd.stop()`。
    ##      ⇒ 按**字段名**查它的类, 再查那个类的文件。这一条覆盖了 `apply_all` /
    ##        `live_count` / `stop` / `tick` / `advance` 那一大批 —— 本仓
    ##        「RefCounted + 构造注入 + host 回调」的主力写法全是这个形状。
    ##   ⚠ 构造边也改成**双向**: 之前只认"P 构造了调用方", 而 `battle._synergy` 是
    ##     反过来的(调用方拿着 P 的实例)。方向搞反 = 整类误报。
    ALIAS = re.compile(r"(?m)^\s*(?:const|var|static\s+var)\s+([A-Za-z_][A-Za-z0-9_]*)"
                       r"\s*(?::\s*[A-Za-z0-9_]+\s*)?:?=\s*preload\s*\(\s*\"(res://[^\"]+\.gd)\"")
    FIELD_NEW = re.compile(r"(?m)^\s*(?:@\w+(?:\([^)]*\))?\s+)?(?:static\s+)?var\s+"
                           r"([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z0-9_]+\s*)?:?=\s*"
                           r"([A-Z][A-Za-z0-9_]*)\s*\.\s*new\s*\(")
    FIELD_TYPED = re.compile(r"(?m)^\s*(?:@\w+(?:\([^)]*\))?\s+)?(?:static\s+)?var\s+"
                             r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Z][A-Za-z0-9_]*)")
    ## ⑥【接收者根本无法静态归属】必须算"绑上了" —— **"查不出来"不等于"是死的"**。
    ##   本仓有一批字段是**故意不写类型**的(条件构造 / 可能是 null):
    ##     `RealtimeBattle3DScene.gd:795  var _wd = null   # BattleWatchdog(STRESS/WATCHDOG 下才建)`
    ##     `eq_potion_batch.gd:46         var _beam_vfx`
    ##   对 `_wd.stop()` / `_beam_vfx.live_count()` 这种接收者, 静态侧**无从判断**它是哪个类。
    ##   头一版把它们算成"绑不上" ⇒ `battle_watchdog::stop` / `mana_beam_vfx::live_count`
    ##   等一批**活函数**被报成嫌疑。而这一网自己写着"推断错的方向是把活函数说成死的,
    ##   比漏报贵" —— 那就必须在这儿让步: 无类型字段一律**放过**, 并把条数打出来当已知失明。
    UNTYPED = re.compile(r"(?m)^\s*(?:@\w+(?:\([^)]*\))?\s+)?(?:static\s+)?var\s+"
                         r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*(?:null|\[\]|\{\})\s*)?$")
    alias_to_file = {}               # 别名 → .gd 文件(按 res:// 路径直接绑)
    field_cls = {}                   # 字段名 → {它可能的 class_name}
    untyped_fields = set()           # 无类型字段名 = 接收者无法静态归属
    for _p, _s in nocmt.items():
        for _m in ALIAS.finditer(_s):
            alias_to_file.setdefault(_m.group(1), set()).add(_m.group(2)[len("res://"):])
        for _rx in (FIELD_NEW, FIELD_TYPED):
            for _m in _rx.finditer(_s):
                field_cls.setdefault(_m.group(1), set()).add(_m.group(2))
        for _m in UNTYPED.finditer(_s):
            untyped_fields.add(_m.group(1))
    ## 有明确类型/构造的同名字段不算"无类型"(同名字段两处一个有类型一个没有时, 信有类型那个)
    untyped_fields -= set(field_cls.keys())

    def tied_to(p, fn):
        """全仓有没有一处 `recv.fn(` 能用**五个强信号**绑到定义文件 `p`?"""
        cn = cls_of.get(p)
        an = auto_of.get(p)
        pat = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*" + re.escape(fn) + r"\s*\(")
        for f, s in list(nocmt.items()) + list(nocmt_t.items()):
            for m3 in pat.finditer(s):
                recv = m3.group(1)
                ## ② autoload: 接收者就是它的全局名
                if an and recv == an:
                    return True
                ## ④ preload 别名 —— 按文件路径绑, 最硬
                if p in alias_to_file.get(recv, set()):
                    return True
                ## ⑤ 字段类型: 接收者是个字段, 它的类就是 P 的 class_name
                if cn and cn in field_cls.get(recv, set()):
                    return True
                ## ⑥ 接收者**根本没法静态归属**就一律放过 —— 这是本网的总纲:
                ##    只有在**每一处**接收者都能被正面解析、而且都解析到**别的类**时,
                ##    才敢说这个定义被掩护了。解析不出来 = 不知道, 而"不知道"必须当活的。
                ##    覆盖两类实测过的写法:
                ##      · 无类型字段  `var _wd = null`(条件构造) / `var _beam_vfx`
                ##      · **局部变量派发** `for sys in 表: sys.on_spawn(u, eid, …)`
                ##        (`equip_stats_apply.gd:64` 就是它 —— 三个 `eq_*_batch.on_spawn`
                ##         头一版全被误报, 而它们天天在跑)
                if recv in untyped_fields:
                    return True
                resolvable = (recv in alias_to_file or recv in field_cls
                              or recv in auto_of.values() or recv in cls2file)
                if not resolvable:
                    return True
                ## ① 调用方明确提到了 P 的 class_name
                if cn and re.search(r"\b" + re.escape(cn) + r"\b", s):
                    return True
                ## ③ 构造边(**双向**): P 构造了调用方, 或调用方持有 P 的实例
                if f in built_by and p in built_by[f]:
                    return True
                if p in built_by and f in built_by[p]:
                    return True
        return False

    masked = []
    for fn, sites in multi.items():
        if fn in str_names:
            continue                 # 字符串派发(`call("fn")`)无法归属, 一律放过
        for p, ln in sites:
            if bare_in.get(p, {}).get(fn, 0) > 0:
                continue             # 本文件里有裸引用 = 活
            if "%s:%d  %s" % (p, ln, fn) in same_name_dead:
                continue             # 第二道网已经报了, 不重复
            if not tied_to(p, fn):
                masked.append("%s:%d  %s" % (p, ln, fn))

    print("  [分母] 扫描 %d 个文件 · %d 个函数 (受检目录: %s)"
          % (len(files), n_fun, " ".join(ROOTS)))
    print("  [分母] 第二道网: %d 个名字被 ≥2 文件定义 · 共 %d 个定义处"
          % (len(multi), n_multi_sites))
    print("  [分母] 第三道网(同名跨类掩护·洞⑦·**只报不判红**): 解析到 class_name %d 个 ·"
          " autoload %d 个 · 构造边 %d 条 ⇒ 嫌疑 %d 处"
          % (len(cls_of), len(auto_of), sum(len(v) for v in built_by.values()), len(masked)))
    if len(multi) < 10 or n_multi_sites < 50:
        print("")
        print("[FAIL] 同名方法只找到 %d 个名字 / %d 个定义处 —— 分母过小, 第二道网是空检查"
              % (len(multi), n_multi_sites))
        return 1
    if exempt:
        print("  [豁免] %d 个（每个都写了原因）:" % len(exempt))
        for e in exempt[:10]:
            print("     " + e)
    ## ══════════════════════════════════════════════════════════════════
    ##  门禁探针也要有台账 —— 洞⑧ (2026-09-28)
    ## ══════════════════════════════════════════════════════════════════
    ## 原来这一栏**只打一个数字 104**, 名单从不列出、也没有台账。后果:
    ##   「**产品函数被测试独占**」与「故意写给门禁的探针」**长得一模一样**,
    ##   而两者的处置完全相反 —— 前者是回归(玩家再也走不到它了), 后者是设计。
    ## ★活实例(修「面板技能数值不跟属性变」时带出来): `info_panel.gd:1691`
    ##   `_panel_skill_entries` —— 产品侧零调用(`chest_system.gd:297` 那处是**注释**),
    ##   全仓只有 `verify_info_panel.gd:116` / `verify_info_panel_live.gd:468,485` /
    ##   `verify_two_level_desc.gd:76,82` 在调。2026-08-16 面板重做后产品走的是
    ##   `_skill_bar_entries` ⇒ 它**已经不是活代码**, 只是被测试吊着命。
    ##   而这条判据只说了"104 个", 于是它混在里面谁也看不见。
    ## ⇒ 记台账: 新进这一栏的**当场打出来**(不判红 —— 正当的重构也会把函数变成
    ##   测试专用, 该由人一句话定"删掉"还是"这是测试专用接口"; 要升成红灯是一行的事)。
    LEDGER3 = os.path.join("tools", "zero_caller_probe_debt.json")
    probe_names = sorted(set(p.split(":")[-1] for p in probes))
    ledger3 = {}
    if os.path.exists(LEDGER3):
        try:
            ledger3 = json.load(io.open(LEDGER3, encoding="utf-8"))
        except Exception:
            ledger3 = {}
    known3 = set(ledger3.get("known", []))
    fresh3 = [n for n in probe_names if n not in known3]
    gone3 = sorted(n for n in known3 if n not in probe_names)
    if probes:
        print("  [门禁探针] %d 个只被 tests/ 调用(这是**故意的**: 产品不需要, 门禁要读内部状态)"
              % len(probes))
        print("             台账 %d 条 · **新进这一栏 %d 个** · 离开 %d 个"
              % (len(known3), len(fresh3), len(gone3)))
        for n in fresh3:
            where = [p for p in probes if p.endswith(":" + n)]
            print("     [新增·只被测试调] %s  (%s)" % (n, where[0] if where else "?"))
        if fresh3:
            print("       ↑ 这**不是**红灯, 是一个要人拍板的岔路: 产品侧已经走不到它了 ⇒")
            print("         要么连测试一起删, 要么明说它是测试专用接口(那就该改名/加注释)。")
            print("         确认后跑 `--update` 记进台账。")
        for n in gone3:
            print("     [已清] %s 不再是「只被测试调」了 —— `--update` 把它从台账里删掉" % n)
    if masked:
        print("")
        print("  【第三道网·嫌疑】同名跨类掩护 %d 处 —— **只报不判红**(推断错的方向是"
              "把活函数说成死的, 比漏报贵):" % len(masked))
        for m in sorted(masked):
            print("     " + m)
        print("     ↑ 判法: 这个名字在 ≥2 个文件里有定义, 而**没有一处 `recv.fn(` 能靠"
              "class_name / autoload 名 / 构造边绑到这一个定义**。")
        print("     实例(已被清死码那轮删掉): `RecordScene._mono_font` —— "
              "`codex/list_builder.gd:93` 的 `host._mono_font()` 里 host 是 CodexScene,")
        print("     第二道网的全仓 `qual_names` 让那次调用**替 RecordScene 站了岗**。")
        print("     ⇒ 逐条去看: 真死就删, 真活就说明接收者是怎么绑上的(多半是我这三个"
              "强信号覆盖不到的写法)。")
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
    ## 第二道网的存量台账(键 = 函数名, 同主台账的理由: 行号天天漂)
    ledger2 = {}
    if os.path.exists(LEDGER2):
        try:
            ledger2 = json.load(io.open(LEDGER2, encoding="utf-8"))
        except Exception:
            ledger2 = {}
    known2 = set(ledger2.get("known", []))
    fresh2 = [d for d in same_name_dead if d.split("  ")[-1] not in known2]
    if os.environ.get("ZERO_CALLER_UPDATE") == "1" or "--update" in sys.argv:
        ## ★★见 tools/_ledger_guard.py: --update 会把此刻的工作区焊进棘轮。
        ##   这本台账尤其危险 —— 它记的是"哪些函数允许没人调",
        ##   把别人删一半的状态记进来 = 一批真死码从此永久合法。
        import _ledger_guard
        _ledger_guard.warn_if_dirty(ROOTS + ["tests"])
        io.open(LEDGER2, "w", encoding="utf-8", newline=NL).write(json.dumps(
            {"_why": "由 `python tools/zero_caller_audit.py --update` 生成, 不要手改。"
                     "第二道网(同名掩护)的存量, 只减不增。",
             "known": sorted(d.split("  ")[-1] for d in same_name_dead),
             "where": {d.split("  ")[-1]: d.split("  ")[0] for d in sorted(same_name_dead)}},
            ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (%d 个存量·第二道网)" % (LEDGER2, len(same_name_dead)))
        ## ★台账的**匹配键仍然是函数名**(不是 file:line): 7 个 agent 同时在改
        ##   scripts/, 按行号记明天就全过期, 而"函数挪了两行"不是这条判据要抓的事。
        ##   `where` 只是**给人看的出处**, 每次 --update 重新生成, 不参与判定。
        io.open(LEDGER, "w", encoding="utf-8", newline=NL).write(json.dumps(
            {"_why": "本文件由 `python tools/zero_caller_audit.py --update` 生成, 不要手改。"
                     "`known` 是匹配键(函数名); `where` 只是出处, 不参与判定。只减不增。",
             "known": sorted(d.split("  ")[-1] for d in dead),
             "where": {d.split("  ")[-1]: d.split("  ")[0] for d in sorted(dead)}},
            ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (%d 个存量)" % (LEDGER, len(dead)))
        ## 门禁探针台账(洞⑧): 记「现在哪些函数只被 tests/ 调」, 新进的当场打出来。
        io.open(LEDGER3, "w", encoding="utf-8", newline=NL).write(json.dumps(
            {"_why": "由 `python tools/zero_caller_audit.py --update` 生成, 不要手改。"
                     "`known` = 当前**只被 tests/ 调用**的函数名。它不是欠债也不是白名单, "
                     "是一张**变动通知表**: 新进这一栏说明那个函数产品侧已经走不到了"
                     "(可能是回归, 也可能是有意的测试专用接口), 要人看一眼。",
             "known": probe_names,
             "where": {p.split(":")[-1]: p for p in sorted(probes)}},
            ensure_ascii=False, indent=1) + NL)
        print("  [台账已重写] %s (%d 个只被测试调)" % (LEDGER3, len(probe_names)))
        return 0
    ## ══════════════════════════════════════════════════════════════════
    ##  台账体检: `[已清]` + 【欠一条理由】—— 2026-09-28 统一约定
    ## ══════════════════════════════════════════════════════════════════
    ## ★由来: 同日 `vfx_discipline_audit` 有一条**已经不成立的台账**挡住了一次正当的
    ##   删除(删 `_signal_pulse` 时它红了, 于是那次删除被还原了)。
    ##   ⇒ 台账不报 `[已清]` 的代价不是"多留一行", 是**它会替缺陷站岗、还会拦住正当改动**。
    ##   本仓的约定统一成: **每本棘轮台账都要报 `[已清]`**(asset_borrow / codex_text_lint
    ##   / write_orphan / 这里都已经有), 并且**每条存量要么有理由, 要么被数成欠债**。
    live_names = set(d.split("  ")[-1] for d in dead)
    cleared = sorted(n for n in known if n not in live_names)
    no_why = sorted(n for n in live_names if n not in DEBT_WHY)
    print("  [台账体检] 主网存量 %d 条 · 其中已清 %d 条 · 写了理由 %d 条 · **欠一条理由 %d 条**"
          % (len(known), len(cleared), len(live_names) - len(no_why), len(no_why)))
    for n in cleared:
        print("  [已清] %s 现在有人调了(或被删了) —— `--update` 把它从台账里删掉" % n)
    if dead and not fresh:
        print("")
        print("  [存量] %d 个在台账里(只减不增; 新增的会当场红):" % len(dead))
        for d in sorted(dead):
            nm = d.split("  ")[-1]
            print("     %s%s" % (d, ("   —— " + DEBT_WHY[nm]) if nm in DEBT_WHY else ""))
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
    ## 第二道网的存量走 LEDGER2（见它的注释）—— 新增当场红。
    if same_name_dead and not fresh2:
        print("")
        print("  [存量·第二道网] %d 个在台账里(只减不增):" % len(same_name_dead))
        for d in sorted(same_name_dead):
            print("     " + d)
    same_name_dead = fresh2
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
