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

## ══════════════════════════════════════════════════════════════════════
##  素材文件本身在哪(给存在性哨兵用) —— 与 ROOT 分开**是有理由的, 而且必须接上线**
## ══════════════════════════════════════════════════════════════════════
## 反向验证时 ROOT 会被指到临时的历史树(`git archive <提交> | tar -x -C /tmp/shadow`),
## 而那棵树里可能**只导了 `scripts/`** —— `assets/` 有 136MB, 没人会为了验一条判据全导。
## ⇒ 素材"在不在磁盘上"必须能单独指到真仓库。
##
## ★★2026-09-28 实测: 这里原来写的就是 `ASSET_ROOT = ROOT` —— 上面那段理由写得好好的,
##   **而拆分根本没接线**(memory [[fb-refactor-creates-the-drift-it-removes]]:
##   抽常量要连「改代码去读它」那一步一起做, 只改名字＝白改)。
##   后果: 只导 `scripts/` 的影子树一跑, 511 个引用点全部"磁盘上不存在"
##   ⇒ 撞上 `missing` 哨兵、报 `[FAIL] 解析错了` —— 而**解析一点没错**,
##   是素材不在那棵树里。判据把**错因**摔在人脸上, 比不报更坏。
##
## 优先级: `--asset-root=<路径>` > 环境变量 `ASSET_ROOT` > ROOT 自己。
## 三者都找不到 `assets/sprites/` 时**不报 FAIL**, 而是把哨兵**明确关掉并大声说**
## (见 main() 里那段) —— 关掉一条哨兵要有人看见, 静默降级正是本仓最恨的形状。
ASSET_ROOT = os.environ.get("ASSET_ROOT") or ROOT
for _a in sys.argv[1:]:
    if _a.startswith("--asset-root="):
        ASSET_ROOT = _a.split("=", 1)[1]
ASSETS_PRESENT = os.path.isdir(os.path.join(ASSET_ROOT, "assets", "sprites"))

LEDGER = os.path.join(ROOT, "tools", "_asset_borrow_ledger.json")
## 洞④ 第二道网的存量台账(跨语义)。**脚本生成**, 不手写。
LEDGER_X = os.path.join(ROOT, "tools", "_asset_crossscreen_ledger.json")

SCAN_DIRS = ["scripts", "scenes", "autoload", "resources"]
SCAN_EXTS = (".gd", ".tscn", ".tres")
## ① 整串 `res://assets/sprites/<任意子目录>/<文件>`
DIRECT = re.compile(r"res://assets/sprites/([A-Za-z0-9_/\-]+\.(?:png|svg|webp))")
## ② 前缀变量: `sic := "res://assets/sprites/stats/"` —— 之后 `sic + "aspd-icon.png"`
PREFIX = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)\s*:?=\s*"res://assets/sprites/([A-Za-z0-9_/\-]*/)"')
## ══════════════════════════════════════════════════════════════════════
##  一条中文标签 —— 给"**这一屏把它叫什么**"当证据(⑥ 2026-09-28 补)
## ══════════════════════════════════════════════════════════════════════
## ★这不是判据, 是**复核料**: 判据只负责把跨屏的挑出来, "是不是同一个含义"
##   要有人看一眼。看的就是这两条标签 ⇒ **标签空掉 = 那一眼没料可看**。
##
## ★★原来只在【同行 + 上下各 2 行】里找**字符串字面量**里的中文, 实测抓不到:
##   排行榜那处引用在 `const STAT_ICONS := [...]` 数组里(LeaderboardScene.gd:93),
##   而「横扫」写在数组**上方 5 行的 `##` 注释**里 ⇒ 两个原因同时踩到:
##     ① 窗口只有 ±2 行, 差了 3 行;
##     ② 那是注释, 而老代码对 j != i 的行做 `split("#")[0]` ⇒ `##` 开头的行被切成空串。
##   于是那条 FAIL 印出来是「Leaderboard 处叫「?」」—— 命中是对的, **证据是残的**,
##   而且 `⚠语义可能不同` 那条提示(靠两边标签比字)也因此**永远不会对它触发**。
##
## ⇒ 四级回落, 一定给出点东西(kind 记下来源, 打印时标明, 别让注释冒充屏幕文案):
##     串   同行的字符串字面量            —— 最强: 它极可能就是这一处的屏幕文案
##     近串 上下 6 行内的字符串字面量
##     注释 上下 8 行内 `#`/`##` 注释里的中文 —— 本仓的"这一格叫什么"大半写在注释里
##     源码 该行源码本身(去掉缩进)        —— 最后兜底, 至少让人知道该去看哪一行
##   ⚠ `⚠语义可能不同` 只在两边都拿到【串/近串/注释】时才算 —— 拿"源码"去比字
##     纯属噪音(变量名、路径、括号都会撞), 会把复核提示变成狼来了。
CJK_CH = "[" + chr(0x4E00) + "-" + chr(0x9FFF) + "]"
## 字符串字面量里的中文
CJK = re.compile('"([^"]*' + CJK_CH + '[^"]*)"')
## 注释里的中文: 取 `#` 之后那一段里连着的中文/标点
CJK_CMT = re.compile("#+\\s*(.*?" + CJK_CH + ".*)$")
## 纯装饰的注释行(═──★ 那种横幅), 抓到它当标签等于没抓到
CMT_NOISE = re.compile("^[\\s=\\-─═★☆·◆●○□■|/\\\\+*#]+$")


def _strip_cmt(ln):
    """去掉行尾注释, 但**不切颜色码**(`#ffd93d` 满仓都是, 一刀切会吃掉半句话)。"""
    out = []
    q = ""
    i = 0
    while i < len(ln):
        c = ln[i]
        if q:
            if c == q:
                q = ""
            out.append(c)
        elif c in "\"'":
            q = c
            out.append(c)
        elif c == "#":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


## 本文件内 `var xxx := "中文…"` / `xxx = "中文…"` —— 标签由**变量**带过来的那一类
VAR_LABEL = re.compile(
    r'^\s*(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*\w+\s*)?:?=\s*"([^"]*'
    + CJK_CH + r'[^"]*)"')
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def var_labels(lines):
    """→ {变量名: 它被赋的第一条中文串}。给 near_label 的【变量】那一级用。"""
    out = {}
    for ln in lines:
        m = VAR_LABEL.match(ln)
        if m and m.group(1) not in out:
            out[m.group(1)] = m.group(2)
    return out


def near_label(lines, i, asset="", vlab=None):
    """→ (标签, 来源) · 来源 ∈ 串/点名/变量/近串/注释/源码。**保证非空**。

    `asset` = 这一处引用的素材相对路径, 用来找**点名它的那条注释**(见 ② 的理由)。
    `vlab`  = var_labels(lines) 的结果(按文件算一次, 别每行重算)。
    """
    ## ① 同行的字符串字面量(不去注释: 同行注释里的话往往正是这一处的说明)
    m = CJK.search(lines[i])
    if m:
        return m.group(1)[:16], "串"
    ## ② 【点名】±12 行内**提到这张图文件名**的注释 —— 比"最近的注释"强得多。
    ##    ★这不是我编的启发式, 是本仓**实际的写法**: 图标为什么选这张, 都写成
    ##      一张清单钉在 `const` 上方, 每行点名文件:
    ##        `##   横扫 \`stats/aspd-icon.png\` —— 交叉双刀。⚠ 它在战斗信息面板里是"攻速"`
    ##    ★为什么必须先于"最近的注释": aspd-icon 那处引用在 `const STAT_ICONS := [` 数组里,
    ##      按距离找会先撞到数组**下方** 3 行的另一段注释(「金/银/铜。modulate_color 是…」)
    ##      —— 那段讲的是签牌配色, **跟这张图一点关系没有**, 拿它当"排行榜把它叫什么"
    ##      的证据等于给复核的人指错地方(比印「?」更坏: 「?」至少不骗人)。
    ##      点名那条在 i-5, 距离更远而**内容是对的**。⇒ 相关性优先于距离。
    base = asset.split("/")[-1] if asset else ""
    if base:
        for d in range(0, 13):
            for j in ((i - d, i + d) if d else (i,)):
                if not (0 <= j < len(lines)):
                    continue
                if base not in lines[j]:
                    continue
                mm = CJK_CMT.search(lines[j])
                if mm and not CMT_NOISE.match(mm.group(1)):
                    ## ★把**路径本身**从标签里剔掉, 只留"这一格叫什么":
                    ##   `横扫 \`stats/aspd-icon.png\` —— 交叉双刀` → `横扫 —— 交叉双刀`。
                    ##   两个理由: ① 印出来是给人看"叫什么", 路径已经在后面的 (文件:行) 里了;
                    ##   ② 下游 `⚠语义可能不同` 是**比两边标签有没有共同字**, 路径里的
                    ##      拉丁字母/斜杠/点会**假装两边有共同字**, 把那条提示搅成噪音。
                    txt = re.sub(r"`[^`]*`", "", mm.group(1))
                    txt = txt.replace(base, "").strip(" \t-—·:：,，。")
                    if txt and re.search(CJK_CH, txt):
                        return txt[:24], "点名"
    ## ③ 【变量】同行上出现的标识符, 若它在本文件里被赋过一条中文串, 就用那条。
    ##    ★实测(⑥ 收尾时抓到): `[sic + "def-icon.png", def_txt, W]` —— 标签藏在
    ##      24 行之上的 `var def_txt: String = "护甲 %d" % def_now`。
    ##      窗口再宽也不该靠"离得近"去猜它, 而**按名字查**是确定的。
    ##      不做这一步时 `近串` 会抓到下一行的 `"魔抗 %d"` ⇒ 印出「def-icon 在战斗里叫魔抗」,
    ##      **看着像一个真的图标错配**, 而实际只是取料取歪了(假线索比没线索更费人)。
    if vlab:
        for mv in IDENT.finditer(_strip_cmt(lines[i])):
            v = vlab.get(mv.group(0))
            if v:
                return v[:16], "变量"
    ## ② 上下 6 行内的字符串字面量(由近到远)
    for d in range(1, 7):
        for j in (i + d, i - d):
            if 0 <= j < len(lines):
                m = CJK.search(_strip_cmt(lines[j]))
                if m:
                    return m.group(1)[:16], "近串"
    ## ③ 上下 8 行内注释里的中文(由近到远; 本仓「这一格叫什么」大半写在注释里)
    for d in range(0, 9):
        for j in ((i - d, i + d) if d else (i,)):
            if not (0 <= j < len(lines)):
                continue
            m = CJK_CMT.search(lines[j])
            if m and not CMT_NOISE.match(m.group(1)):
                return m.group(1).strip()[:24], "注释"
    ## ④ 兜底: 该行源码本身 —— 至少说清该去看哪一行
    return (lines[i].strip()[:32] or "(空行?)"), "源码"

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
    ## ★2026-09-29 登录屏照参考重做时加的两条。用户原话「你自己学其他游戏，把登录做好」。
    ##   参考量出来的事实: Arknights / Free Fire / Disney Mirrorverse / Hungry Shark 的账号控件
    ##   **直接浮在游戏自己的美术上**, 而我们那一屏原本是一块深蓝面板压在共用平铺花砖上,
    ##   **一只龟、一个擂台都看不见**。
    ##   ★★**措词 2026-09-29 改过一次**(同一天拆墙): 原文写的是「登录墙是玩家
    ##   见到这个游戏的**第一屏**」—— 墙拆了之后那句话不成立了: 第一屏是主菜单,
    ##   那一屏只在玩家点了主菜单那句「进度没备份」之后才出现。
    ##   ⇒ 理由本身**没变**: 那一屏仍然盖满全屏、仍然是「这个游戏的底 + 它叫什么」;
    ##   变的只是它不再是开局必经。理由写错和不写理由一样糟, 所以跟着改。
    ##   ⚠ 铁律是「新内容一律新素材」—— 这两条走的是判据自己给的 (b) 出口:
    ##   **两屏把它当同一个含义用**。不是拿别件的图顶替一件没画的东西。
    "menu/menu-bg-crowd.png":
        "菜单屏的**背景底**(28 只龟的群像)。主菜单与**绑定屏**(盖满全屏的那一屏, 2026-09-29 之前叫登录墙)"
        "是同一个含义: 这个游戏的底。"
        "与上面 menu-bg-tile.png 同理 —— 换的是哪张底, 不是换了语义。",
    "menu/menu-title.png":
        "**这个游戏自己的标题图**(斗龟场)。主菜单与**绑定屏**指的是同一件事: 游戏叫什么。"
        "参考里每一屏登录/标题屏都印着自己的标, 换一张反而是错的。",
    "menu/menu-bg-tile.png":
        "全屏共用的背景平铺底(persistent_bg 那一层)。8 个屏是同一个含义: 底。",
    "bg/select-bg.png":
        "选阵容的背景图。两处一个是 preload_cache(预热, 不是第二个语义)、一个是场景自己。",
    "menu/btn-frame.png":
        "按钮框皮。主菜单与设置屏用的是**同一种按钮**, 框就该是同一张(换皮不换义)。",
    "menu/frame-rect.png":
        "方框皮。两处一个是主菜单、一个是 util/ui_skin(全屏共享皮的注册处)。",
    "battlehud/insp-slot.png":
        "检视面板那一套新画的槽框(2026-10-06)。面板里的技能/装备槽、头像框、左侧小卡的图标框是**同一个部件**, 只是建在三个文件里(面板/HUD/小卡)。",
    "battlehud/chip-frame.png":
        "芯片框皮。两处一个是战斗信息面板、一个是 util/ui_skin(全屏共享皮的注册处)。",
    "battlehud/bar-frame.png":
        "条状框皮。战斗血条 / 设置滑条 / 商店条 都是「一条横槽」这同一个形状。",
    "menu/ic-deepsea.png":
        "深海币**货币图标**。主菜单/背包/商店三屏说的是同一种钱。",
    "ui/coin.png":
        "龟币**货币图标**。战斗掉币与主菜单钱包是同一种钱。",
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

## ══════════════════════════════════════════════════════════════════════
##  【类型图标 12 张】—— 2026-09-28, 一条理由覆盖一族(核对过出处才写)
## ══════════════════════════════════════════════════════════════════════
## 事实(逐条查过, 不是按名字猜的):
##   · `CodexScene.TYPE_STYLE`(CodexScene.gd:91+)  —— 图鉴羁绊页的颜色 + 图标
##   · `Phase2Types.TYPE_ICON`(phase2_types.gd:86+) —— 经 `icon_of()`/`icon_bb()` 给
##     羁绊**行名与弹框标题**用(phase2_types.gd:182 / :190)
##   · `tests/verify_no_emoji_icons.gd:509` 自己写着「★★**第二张**类型图标表
##     `Phase2Types.TYPE_ICON` —— 同样三条」⇒ **两张表是有意的**, 而且两张都进了门禁;
##     `type_tables_audit` 也已把两张表的键集与"值指向盘上的 tags/*.png"一起焊住。
## ⇒ 同一张图在两处说的是**同一件事**: 「这件装备是什么类型」。两个消费层(图鉴页 /
##   羁绊面板)共用一张类型图标, 正是"换皮不换义", 与 `menu/btn-frame.png` 同一档。
## ⚠ 我**没有**替"要不要两张表"拍板 —— 那是产品结构问题(平行表天生会漂), 已交主会话。
##   这里只认领"同一个含义"这一件事; 哪天并成一张表, 这 12 条会被 `[已清]` 报出来。
for _t in ("sword", "gadget", "food", "shield", "potion", "gun", "bow",
           "staff", "spirit", "incense", "relic", "axe"):
    CROSS_OK["tags/tag-%s.png" % _t] = (
        "装备**类型图标**。图鉴羁绊页(CodexScene.TYPE_STYLE)与羁绊行名/弹框标题"
        "(Phase2Types.TYPE_ICON)说的是同一件事: 这件装备属于哪个类型。"
        "两张表是有意的(verify_no_emoji_icons.gd:509 明写「第二张类型图标表」, 两张都进门禁)。")


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
    ## `unchecked` = 因为 ASSET_ROOT 下没有 assets/sprites 而**没能查存在性**的引用点数。
    ## 它与 `missing` 是两件事: missing = 查过且不在(解析错了, 真该红);
    ## unchecked = 根本没得查(影子树只导了 scripts/) ⇒ 不红, 但要大声报。
    st = {"files": 0, "refs": 0, "missing": [], "unchecked": 0, "lab_kind": {}}
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
                vlab = var_labels(lines)          # 标签由变量带过来的那一类, 按文件算一次
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
                        if not ASSETS_PRESENT:
                            st["unchecked"] += 1
                        elif not os.path.exists(os.path.join(ASSET_ROOT, "assets", "sprites",
                                                             a.replace("/", os.sep))):
                            st["missing"].append("%s:%d → %s" % (rel, i + 1, a))
                    ## 附近的中文标签(五级回落, 保证非空 —— 见 near_label 的长注释)。
                    ## ★逐**素材**算, 不是逐行算: 同一行/同一个数组里有好几张图时,
                    ##   「点名」那一级要认的是**这一张**的名字(STAT_ICONS 里三张图
                    ##   各有自己那行注释: 胜场/余命/横扫)。按行算会让三张共用一个标签。
                    for a in found:
                        lab, kind = near_label(lines, i, a, vlab)
                        st["lab_kind"][kind] = st["lab_kind"].get(kind, 0) + 1
                        by_file[a].add(rel)
                        by_screen[a][sc].append(("%s:%d" % (rel, i + 1), lab, kind))
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
    ## 标签来源分布(复核料的质量): 「源码」那一档是**没抓到真标签**的兜底,
    ## 它涨了就说明 near_label 的窗口又跟不上代码写法了 ⇒ 打出来才看得见。
    print("  [分母] 附近中文标签的来源: %s"
          % (" · ".join("%s %d" % (k, v) for k, v in sorted(st["lab_kind"].items()))
             or "(无)"))
    ## ★★存在性哨兵在不在岗 —— **关掉要有人看见**(静默降级正是本仓最恨的形状)。
    if not ASSETS_PRESENT:
        print("  [哨兵关闭] ASSET_ROOT=%s 下没有 `assets/sprites/` ⇒ **没查素材存在性**"
              "(本轮 %d 个引用点未查)。" % (ASSET_ROOT, st["unchecked"]))
        print("             这通常是反向验证的影子树只导了 `scripts/`。要让哨兵上岗:")
        print("             `--asset-root=<真仓库路径>` 或 `ASSET_ROOT=<真仓库路径>`。")
        print("             ⚠ 哨兵关着时本轮结论**只对跨语义那道网有效** —— 前缀变量"
              "解析错会让两处引用对不上号而静默报绿, 而那正是这条哨兵防的。")
    else:
        print("  [分母] 查了素材存在性 %d 个引用点(ASSET_ROOT=%s) · 不存在 %d 个"
              % (st["refs"], ASSET_ROOT, len(st["missing"])))
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
        ## ★★见 tools/_ledger_guard.py: 2026-09-28 实测, 照 `[已清]` 的提示直接 --update
        ##   会把**别的 agent 未提交的改动**记成存量。这条路上最贵的一次手滑是
        ##   12 条新的跨语义(`tags/tag-*.png` 第二张表)被写进台账当存量 ⇒ 从此不再红。
        import _ledger_guard
        _ledger_guard.warn_if_dirty(SCAN_DIRS, ROOT)
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
        ## ★只拿【串/近串/注释】比字 —— 「源码」那一档是兜底(变量名/路径/括号),
        ##   拿它比会把复核提示变成狼来了(见 near_label 的长注释)。
        labs = [l for s in cross[k] for (_w, l, kd) in cross[k][s] if l and kd != "源码"]
        warn = ""
        if len(cross[k]) == 2 and len(labs) >= 2:
            a, b = labs[0], labs[-1]
            if a and b and not (set(a) & set(b)):
                warn = "  ⚠语义可能不同(两屏的标签一个字都不重合) —— 复核提示, 不是判决"
        print("     %-34s %-28s %s%s"
              % (k, "/".join(sorted(cross[k])), CROSS_OK[k][:46], warn))
        ## ★★⚠ 一响就把**两屏各叫什么**摆出来。
        ##   原来只说"一个字都不重合"却不印是哪两个词 ⇒ 复核的人还得自己去翻两个文件,
        ##   于是这条提示实际没人会去跟 —— 那和没有提示一样(⑥ 的整个要点就是"有料可看")。
        if warn:
            for s in sorted(cross[k]):
                w0, l0, kd0 = cross[k][s][0]
                print("        └ %-22s 叫「%s」[%s]  %s" % (s, l0, kd0, w0))
    for k in sorted(curx):
        if k in CROSS_OK:
            continue
        if k in oldx:
            print("  [存量·跨语义] %s  %s(台账里, 欠一条理由)"
                  % (k, "/".join(sorted(cross[k]))))
            continue
        ev = []
        for s in sorted(cross[k]):
            w, l, kd = cross[k][s][0]
            ## 来源标出来: 「注释」不是屏幕文案, 别让它冒充; 「源码」是没抓到的兜底。
            ev.append("%s 处叫「%s」[%s](%s)" % (s, l or "?", kd, w))
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
