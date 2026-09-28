# -*- coding: utf-8 -*-
"""素材借用审计 —— 「素材不复用」这条铁律的门禁化 (2026-09-13, 2026-09-28 补洞④)。

用户 2026-08-03 定、08-04 重申的铁律: **新内容一律新素材**, 只有背包/商店装备图标可复用。
2026-09-13 用户点名:「你复用素材了, 你凭什么敢?」「你用素材的时候 036,
有没有直接拿旧素材做」—— 说中了: 036 温泉蛋的升级演出里有 5 次 `_gold_chunk_erupt`,
那是 **034 大熊**的 `gold-chunk.png`。

普查之后发现**这是一整类不是一件**: 12 个「名字带主人」的素材被多个系统加载。
⇒ 照 `zero_caller_audit.py` 的老办法办: **存量记台账(只减不增), 新增的当场红**。

════════════════════════════════════════════════════════════════════════
 ★★★洞④ (2026-09-28): 扫描范围只有 `vfx|equip`, 而且对 `-icon` 整类豁免
════════════════════════════════════════════════════════════════════════
原来的正则是 `res://assets/sprites/(?:vfx|equip)/…`, 并且把名字里带 `-icon`
的当「通用基元」放过。**两条口子叠在一起, 把整个 UI 图标层排除在门禁之外**:

  实例: 排行榜「横扫」列借用 `assets/sprites/stats/aspd-icon.png`,
        而那张图在战斗信息面板里是**「攻速」** —— 同一张图两个含义,
        正是这条铁律要防的, 而审计器跑出来 **ALL OK**。
        (`stats/` 不在 `vfx|equip` 里 ⇒ 第一条口子; 就算在, `-icon` ⇒ 第二条。)

⇒ 改了三件事:
  ① 扫描范围: `assets/sprites/**` 全部(含 ui/menu/stats/battlehud/trainer/bg/…),
     文件类型从 `.gd` 扩到 `.tscn` / `.tres`(`select-bg.png` 只在 .tscn 里引用过),
     并解析**前缀变量拼接**(`sic := "res://…/stats/"` + `"aspd-icon.png"` ——
     `aspd-icon` 那一处就是这个形状, 只认 `res://` 整串会漏掉它)。
  ② `-icon` 豁免**删掉**。剩下的通用基元名字规约(`fx-`/`dust-`/`spark`/…)
     **只对 `vfx/` 生效** —— 那条规约的出处是「vfx 库很全, 别重复造同一个」,
     它说的是特效基元, 不是 UI 图标。
  ③ 新增第二道网【**跨语义**】: 判据不再是"按路径/后缀豁免", 而是量真实的事 ——
     **同一张素材被几个语义不同的地方引用**。

════════════════════════════════════════════════════════════════════════
 ★两道网量的是两件不同的事(别把它们合起来)
════════════════════════════════════════════════════════════════════════
(a)【同屏内借别人的图】: 一张「名字带主人」的图被 **≥2 个文件**加载。
    抓的是 `dragon-flame.png` 被龙装备 + 凤凰 + 阴燃三家用 —— 都在战斗屏内,
    跨屏判据看不见它。台账 `tools/_asset_borrow_ledger.json`。

(b)【**跨语义**】: 一张图出现在 **≥2 个屏**上。抓的是 aspd-icon 那个形状。
    战斗侧(主场景 / `scenes/battle/` / `systems/`)**全折成一个 Battle 屏** ——
    不折的话 `candy-burst.png` 会因为"糖果系统 + 战斗主场景"被报成跨屏,
    而那是同一个语义被上帝文件拆分切成了两个文件, 不是两个含义。

════════════════════════════════════════════════════════════════════════
 ★★为什么 (b) 必须是【台账 + 白名单, 每条带理由】而不是纯判据
════════════════════════════════════════════════════════════════════════
**正当复用与违规复用在结构上一模一样**, 判据量不到"语义一不一致":

  · `menu/ic-trophy.png`  主菜单「排行榜」入口 + 排行榜「胜场」列 —— 语义一致, **正当**
  · `stats/aspd-icon.png` 战斗「攻速」       + 排行榜「横扫」列 —— 语义不同, **违规**

两条的形状是同一个(`Battle | Leaderboard`)。⇒ 判据只负责**把跨屏的挑出来**,
"是不是同一个含义"必须有人看一眼并**写下理由**。
**不写理由的白名单和放宽判据是一回事。**

为了让这一眼**有料可看**, 审计器会把每个引用点**附近的中文标签**打出来
(aspd-icon 那次: 战斗侧同行写着「攻速 每秒 %s 下」, 排行榜侧写着「横扫」),
两边标签一个字都不重合的还会标 `⚠语义可能不同` 当复核提示 ——
**那只是提示, 不是判决**(「余命」vs「生命」也不重合, 而它们是同一维)。

跑法:
  python tools/asset_borrow_audit.py            # 对账(进门禁)
  python tools/asset_borrow_audit.py --update    # 两份台账都按当前实测重写
"""
import collections
import io
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
## 素材文件本身在哪(存在性哨兵用)。反向验证时 ROOT 会被指到临时的历史树,
## 而 assets/ 只在真仓库里 ⇒ 分成两个常量。
ASSET_ROOT = ROOT
LEDGER = os.path.join(ROOT, "tools", "_asset_borrow_ledger.json")
## 洞④ 第二道网的存量台账(跨语义)。**脚本生成**, 不手写。
LEDGER_X = os.path.join(ROOT, "tools", "_asset_crossscreen_ledger.json")

SCAN_DIRS = ["scripts", "scenes", "autoload", "resources"]
SCAN_EXTS = (".gd", ".tscn", ".tres")
## ① 整串 `res://assets/sprites/<任意子目录>/<文件>`
DIRECT = re.compile(r"res://assets/sprites/([A-Za-z0-9_/\-]+\.(?:png|svg|webp))")
## ② 前缀变量: `sic := "res://assets/sprites/stats/"` —— 之后 `sic + "aspd-icon.png"`
PREFIX = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*:?=\s*"res://assets/sprites/([A-Za-z0-9_/\-]*/)"')
## 一条中文标签(给"这一屏把它叫什么"当证据)
CJK = re.compile('"([^"]*[' + chr(0x4E00) + '-' + chr(0x9FFF) + '][^"]*)"')

## 通用基元的**名字规约** —— 多处共用正是它们存在的理由。
## ⚠ 只对 `vfx/` 生效(见头注②): 这条规约的出处是「vfx 库很全, 别重复造同一个」。
## ⚠ `-icon` **已从名单里删掉** —— 它把整个 UI 图标层排除在门禁之外, 正是洞④。
GENERIC = ("fx-", "dust-", "spark", "smoke", "trail", "glow", "ring", "shard",
           "bubble", "beam", "slash", "hit-", "impact")

## ══════════════════════════════════════════════════════════════════════
##  【跨语义】白名单 —— 每条**必须**带理由(见头注)
## ══════════════════════════════════════════════════════════════════════
## ★理由要回答的是**同一个问题**: 这两处把它当同一个含义用吗?
##   回答不了就别写, 让它红 —— 红了是"去看一眼", 不是"去改判据"。
## ★★这张表**同时替第一道网 (a) 认领** —— 同一件事在两个列表里各红一次,
##   只会让人去改判据而不是去看事实。所以表里也允许出现"同一屏内两个文件"
##   的正当复用(`stats/crit-dmg-icon.png` 就是: 战斗飘字 ↔ 信息面板同一维)。
CROSS_OK = {
    "menu/menu-bg-tile.png":
        "全屏共用的背景平铺底(persistent_bg 那一层)。8 个屏是同一个含义: 底。",
    "bg/select-bg.png":
        "选阵容的背景图。两处一个是 preload_cache(预热, 不是第二个语义)、一个是场景自己。",
    "menu/btn-frame.png":
        "按钮框皮。主菜单与设置屏用的是**同一种按钮**, 框就该是同一张(换皮不换义)。",
    "menu/frame-rect.png":
        "方框皮。两处一个是主菜单、一个是 util/ui_skin(全屏共享皮的注册处)。",
    "battlehud/chip-frame.png":
        "芯片框皮。两处一个是战斗信息面板、一个是 util/ui_skin(全屏共享皮的注册处)。",
    "battlehud/bar-frame.png":
        "条状框皮。战斗血条 / 设置滑条 / 商店条 都是「一条横槽」这同一个形状。",
    "menu/ic-deepsea.png":
        "深海币**货币图标**。主菜单/背包/商店三屏说的是同一种钱。",
    "ui/coin.png":
        "龟币**货币图标**。战斗掉币与主菜单钱包是同一种钱。",
    "menu/ic-trophy.png":
        "奖杯。主菜单「排行榜」入口与排行榜「胜场」列 —— 用户点名过这是**正当**复用。",
    "stats/hp-icon.png":
        "生命。排行榜「余命」列与选阵容详情的「生命」是同一维(字面不同, 含义同)。",
    ## ★★下面这 4 条是**修好前缀变量解析之后**才露头的(在此之前 `sic + "xxx.png"`
    ##   被解析成 `status/` 那个不存在的目录, 两处引用对不上号 ⇒ 静默报绿)。
    ##   四条都是【战斗信息面板 ↔ 选阵容详情面板】的**同一维属性**同一张图。
    "stats/atk-icon.png":
        "攻击。战斗信息面板「攻击 %d」与选阵容详情「攻击力」是同一维。",
    "stats/def-icon.png":
        "护甲。战斗信息面板「护甲 %d」与选阵容详情「防御力」是同一维。",
    "stats/mr-icon.png":
        "魔抗。两屏都叫魔抗。",
    "stats/crit-dmg-icon.png":
        "暴伤。战斗演出的暴伤飘字(battle_vfx:298)与信息面板「暴伤」那一格(info_panel:540)是同一维。",
    ## ★★2026-09-28 图标接线那一轮新引入的跨屏复用, 理由由那个 agent 给、我逐条复核过。
    ##   ⚠ 他给了三条, 我**只收两条** —— `ui/icon-turtle.png` 有分歧, 留在台账里等裁决:
    ##     图鉴页签「龟」是**导航标签**, 而撮合屏那处是**对手立绘缺图时的兜底**
    ##     (MatchmakingScene.gd:477, 按 4x=128 画在 200 的立绘框里 ⇒ 它在那儿的角色是
    ##      **画面**不是标签)。「都画着一只龟」是**长得像**, 不等于同一个含义:
    ##     缺图该读成「这个对手没有立绘」, 不是读成「龟这一类」。⇒ 宁可少收一条。
    "ui/icon-equip.png":
        "「装备」这个概念本身。图鉴页签「装备」与背包右上角「装备 8/10」说的是同一件事。",
    "ui/icon-lock.png":
        "「锁住了」这个状态。对阵图未开放的节点与背包顶栏「商店还没开」是同一个含义: 这条路现在走不通。",
    "trainer/trainer-girl.png": "训龟师**本人立绘**。战斗里出场的和配置屏里挑的是同一个角色。",
    "trainer/trainer-mage.png": "同上(法师)。",
    "trainer/trainer-villager.png": "同上(村民)。",
    "vfx/hook-skill-icon.png": "训龟师技能图标: 战斗 HUD 上的那个技 = 配置屏里挑的那个技。",
    "vfx/whistle-icon.png": "同上(哨子)。",
    "vfx/fury-potion-icon.png": "同上(狂怒药水)。",
    "vfx/glacier-icon.png": "同上(冰川)。",
    "vfx/hunt-order-icon.png": "同上(狩猎令)。",
    "vfx/magic-stone-icon.png": "同上(魔石)。",
    "vfx/tame-icon.png": "同上(驯服)。",
}


def screen_of(rel):
    """玩家**在哪一屏**看到它。

    ★战斗侧(主场景 / `scenes/battle/` / `systems/`)全折成一个 `Battle` ——
      不折的话上帝文件拆分本身就会造出一堆"跨屏"(糖果系统 + 战斗主场景),
      那是一个语义被切成两个文件, 不是两个含义。
    """
    rel = rel.replace("\\", "/")
    if rel.startswith("scripts/systems/") or rel.startswith("scripts/scenes/battle/") \
            or rel == "scripts/scenes/RealtimeBattle3DScene.gd":
        return "Battle"
    if rel.startswith("scenes/"):
        return os.path.basename(rel).rsplit(".", 1)[0]
    if rel.startswith("scripts/scenes/team_select/"):
        return "TeamSelect"
    m = re.match(r"scripts/scenes/([A-Za-z0-9_]+)Scene\.gd$", rel)
    if m:
        return m.group(1)
    if rel.startswith("scripts/scenes/"):
        return "Scene:" + os.path.basename(rel)[:-3]
    if rel.startswith("autoload/"):
        return "Global"
    if rel.startswith("scripts/util/"):
        return "Util(全屏共享皮)"
    if rel.startswith("scripts/gamedata/"):
        return "Data:" + os.path.basename(rel)[:-3]
    return "Other:" + os.path.basename(rel)


def is_generic(key):
    return key.startswith("vfx/") and any(g in key for g in GENERIC)


def scan():
    """→ (by_file, by_screen, stats)

    by_file[素材] = {引用它的**文件**}                 —— 第一道网 (a)
    by_screen[素材][屏] = [(file:line, 附近的中文标签)] —— 第二道网 (b)

    ★★前缀变量必须按【该行之前最近的一次赋值】解析, **不能按文件内最后一次**。
      实测(洞④ 反向验证当场抓到): `info_panel.gd` 里 `sic` 赋了两次
      (`:496 = .../stats/`、`:968 = .../status/`), last-wins 会把 `:502` 的
      `sic + "aspd-icon.png"` 算成 `status/aspd-icon.png` —— **磁盘上没这个文件** ——
      于是它和排行榜那一处的 `stats/aspd-icon.png` 对不上号,
      **这条判据在它专门要抓的那一件上报绿**。
      ⇒ 下面 `st["missing"]` 是这一类的分母哨兵: 解析出来的路径不存在就当场红。
    """
    by_file = collections.defaultdict(set)
    by_screen = collections.defaultdict(lambda: collections.defaultdict(list))
    st = {"files": 0, "refs": 0, "missing": []}
    for d in SCAN_DIRS:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dp, _dd, fs in os.walk(base):
            for f in fs:
                if not f.endswith(SCAN_EXTS):
                    continue
                p = os.path.join(dp, f).replace("\\", "/")
                rel = p[len(ROOT.replace("\\", "/")) + 1:]
                src = io.open(p, encoding="utf-8", errors="replace").read()
                st["files"] += 1
                ## 前缀变量的**每一次**赋值都记下来(行号 → 目录), 用的时候取最近的那次
                pref = collections.defaultdict(list)
                for m in PREFIX.finditer(src):
                    pref[m.group(1)].append((src.count(chr(10), 0, m.start()), m.group(2)))
                sc = screen_of(rel)
                lines = src.split(chr(10))
                for i, ln in enumerate(lines):
                    found = [m.group(1) for m in DIRECT.finditer(ln)]
                    for v, asg in pref.items():
                        for m2 in re.finditer(
                                re.escape(v) + r'\s*\+\s*"([A-Za-z0-9_\-]+\.(?:png|svg|webp))"', ln):
                            near = [d for (l0, d) in asg if l0 <= i]
                            if not near:
                                continue
                            found.append(near[-1] + m2.group(1))
                    if not found:
                        continue
                    for a in found:
                        if not os.path.exists(os.path.join(ASSET_ROOT, "assets", "sprites",
                                                           a.replace("/", os.sep))):
                            st["missing"].append("%s:%d → %s" % (rel, i + 1, a))
                    ## 附近的中文标签: 同行优先, 再看上下各 2 行
                    lab = ""
                    for j in (i, i + 1, i - 1, i + 2, i - 2):
                        if 0 <= j < len(lines):
                            mm = CJK.search(lines[j].split("#")[0] if j != i else lines[j])
                            if mm:
                                lab = mm.group(1)[:16]
                                break
                    for a in found:
                        by_file[a].add(rel)
                        by_screen[a][sc].append(("%s:%d" % (rel, i + 1), lab))
                        st["refs"] += 1
    return by_file, by_screen, st


def _load(path, key):
    if not os.path.exists(path):
        return {}
    try:
        return json.load(io.open(path, encoding="utf-8")).get(key, {})
    except Exception:
        return {}


def main():
    by_file, by_screen, st = scan()
    upd = "--update" in sys.argv
    print("  [分母] 扫 %d 个文件(.gd/.tscn/.tres) · 素材引用点 %d 个 · 涉及素材 %d 张"
          % (st["files"], st["refs"], len(by_file)))
    if st["refs"] < 200 or len(by_file) < 100:
        print("  [FAIL] 引用点只有 %d / 素材只有 %d —— 扫描失效了, 这是空检查不是通过"
              % (st["refs"], len(by_file)))
        return 1
    ## ★★分母哨兵: 解析出来的素材路径**必须真的存在**。
    ##   解析错了(前缀变量一个文件里赋两次那种)会让两处引用**对不上号** ⇒
    ##   跨语义判据在它专门要抓的那一件上静默报绿。实测踩过一次, 见 scan() 的长注释。
    if st["missing"]:
        print("  [FAIL] 有 %d 个引用点解析出**磁盘上不存在**的素材路径 —— 解析错了,"
              " 而解析错会让两处引用对不上号、判据静默报绿:" % len(st["missing"]))
        for m in st["missing"][:12]:
            print("     " + m)
        return 1

    ## ══════════════════════════════════════════════════════════════
    ##  第一道网 (a): 同屏内一张「名字带主人」的图被 ≥2 个文件加载
    ## ══════════════════════════════════════════════════════════════
    ## ★★**一条理由覆盖两道网**: 已在 `CROSS_OK` 里写过理由的(跨屏但同语义,
    ##   如背景底/货币图标/按钮框皮/训龟师立绘), (a) 也不再重复报一遍 ——
    ##   同一件事在两个列表里各红一次, 只会让人去改判据而不是去看事实。
    ##   ⇒ 扩了扫描范围之后 (a) 从 12 涨到 14(新露头的两张: `battlehud/panel-frame.png`
    ##     与 `skills/lightning-3.png`, 旧的 `vfx|equip` 范围根本看不见它们),
    ##     而不是涨到 34 条全是 UI 皮。
    cur = {}
    for k, v in by_file.items():
        if len(v) < 2 or is_generic(k) or k in CROSS_OK:
            continue
        cur[k] = sorted(v)
    old = _load(LEDGER, "known")
    print("  [分母] (a) 名字带主人且跨文件的 %d 张 · 台账 %d 条(只减不增) · 被 CROSS_OK 理由认领而不重复报的 %d 张"
          % (len(cur), len(old),
             len([k for k, v in by_file.items() if len(v) >= 2 and k in CROSS_OK])))

    ## ══════════════════════════════════════════════════════════════
    ##  第二道网 (b): 【跨语义】—— 同一张图出现在 ≥2 个屏上
    ## ══════════════════════════════════════════════════════════════
    cross = {k: v for k, v in by_screen.items() if len(v) >= 2 and not is_generic(k)}
    curx = {}
    for k in sorted(cross):
        curx[k] = {s: cross[k][s][0][0] for s in sorted(cross[k])}
    oldx = _load(LEDGER_X, "known")
    n_wl = len([k for k in curx if k in CROSS_OK])
    print("  [分母] (b) 跨语义(跨 ≥2 屏)的 %d 张 · 白名单认领 %d 张 · 台账 %d 条"
          % (len(curx), n_wl, len(oldx)))
    print("  [分母] (b) 被 `vfx/` 通用基元名字规约放过的跨屏素材 %d 张"
          % len([k for k, v in by_screen.items() if len(v) >= 2 and is_generic(k)]))

    if upd:
        io.open(LEDGER, "w", encoding="utf-8", newline=chr(10)).write(json.dumps(
            {"_why": "由 `python tools/asset_borrow_audit.py --update` 生成, 不要手改。"
                     "第一道网(同屏内借别人的图)的存量, 只减不增。",
             "known": dict(sorted(cur.items()))}, ensure_ascii=False, indent=1) + chr(10))
        io.open(LEDGER_X, "w", encoding="utf-8", newline=chr(10)).write(json.dumps(
            {"_why": "由 `python tools/asset_borrow_audit.py --update` 生成, 不要手改。"
                     "第二道网【跨语义】里**白名单还没认领**的存量, 只减不增。"
                     "认领的办法是往 CROSS_OK 里写一条**带理由**的。",
             "known": {k: v for k, v in sorted(curx.items()) if k not in CROSS_OK}},
            ensure_ascii=False, indent=1) + chr(10))
        print("  [台账已重写] %s (%d 条) + %s (%d 条)"
              % (LEDGER, len(cur), LEDGER_X,
                 len([k for k in curx if k not in CROSS_OK])))
        return 0

    bad = []
    for k, v in sorted(cur.items()):
        if k not in old:
            bad.append("(a) %s ← %s" % (k, " | ".join(x.split("/")[-1] for x in v)))
        else:
            extra = [x for x in v if x not in old[k]]
            if extra:
                bad.append("(a) %s 又多了 %s" % (k, " | ".join(x.split("/")[-1] for x in extra)))
    for k in [k for k in old if k not in cur]:
        print("  [已清] (a) %s —— 记得 `--update` 把它从台账里删掉" % k)

    ## 白名单逐条打印(带理由) + 复核提示
    print("  [白名单·跨语义] %d 条, 每条带理由:" % n_wl)
    for k in sorted(curx):
        if k not in CROSS_OK:
            continue
        labs = [l for s in cross[k] for (_w, l) in cross[k][s] if l]
        warn = ""
        if len(cross[k]) == 2 and len(labs) >= 2:
            a, b = labs[0], labs[-1]
            if a and b and not (set(a) & set(b)):
                warn = "  ⚠语义可能不同(两屏的标签一个字都不重合) —— 复核提示, 不是判决"
        print("     %-34s %-28s %s%s"
              % (k, "/".join(sorted(cross[k])), CROSS_OK[k][:46], warn))
    for k in sorted(curx):
        if k in CROSS_OK:
            continue
        if k in oldx:
            print("  [存量·跨语义] %s  %s(台账里, 欠一条理由)"
                  % (k, "/".join(sorted(cross[k]))))
            continue
        ev = []
        for s in sorted(cross[k]):
            w, l = cross[k][s][0]
            ev.append("%s 处叫「%s」(%s)" % (s, l or "?", w))
        bad.append("(b) 跨语义: %s  ——  %s" % (k, " ｜ ".join(ev)))
    ## 白名单里已经不存在的条目也要报 —— 否则它会永远留在这儿当"看着很周全"。
    ## ⚠ 判"还在不在"要把**两道网**都算上: 有些条目只被 (a) 用到
    ## (同一屏内两个文件, 如 `stats/crit-dmg-icon.png`), 只看 (b) 会把它误报成已清。
    _claimed_a = set(k for k, v in by_file.items() if len(v) >= 2 and not is_generic(k))
    stale = [k for k in CROSS_OK if k not in curx and k not in _claimed_a]
    for k in stale:
        print("  [已清] (b) 白名单里的 %s 已经不跨屏了 —— 把那条理由删掉" % k)

    if bad:
        print("")
        for b in bad:
            print("  [FAIL] %s" % b)
        print("")
        print("  ★这条铁律是「新内容一律新素材」。(a) 要么给它烘一张自己的, 要么")
        print("    (确实是 vfx 通用基元)把名字改成 fx-/dust-/spark 那一类。")
        print("  ★(b)【跨语义】: 两屏把它当**同一个含义**用 ⇒ 往 CROSS_OK 里写一条**带理由**的;")
        print("    含义不同(排行榜「横扫」借战斗「攻速」那张图) ⇒ 给它自己的图。")
        print("    **不写理由的白名单和放宽判据是一回事。**")
        print("FAIL x%d" % len(bad))
        return 1
    print("ALL OK — 没有新增的素材借用, 也没有未认领的跨语义复用")
    return 0


if __name__ == "__main__":
    sys.exit(main())
