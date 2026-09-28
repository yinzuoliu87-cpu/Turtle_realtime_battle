# -*- coding: utf-8 -*-
"""九宫格**静默降级**审计 —— 「套了皮, 但其实没套上」(2026-09-28)

════════════════════════════════════════════════════════════════════════
 ★由来: 一个真 bug, 门禁 398/398 全绿时它还活着
════════════════════════════════════════════════════════════════════════
`scripts/util/ui_skin.gd::nine_if_big()` 有个尺寸门槛:

    :42   const MIN_FRAME_PX := 40.0
    :47   if w < MIN_FRAME_PX or h < MIN_FRAME_PX:
    :48       return fallback              ← **悄悄**退回调用方给的 StyleBoxFlat

而 `StyleBoxFlat + 圆角/描边` 正是 `verify_ui_consistency` 定义的**网页盒**。
⇒ 调用方**以为自己套了金属框**, 实际画出来的是网页盒, **没有任何报错**。

实例(2026-09-27 修掉的那个): 图鉴形态切换钮 `196×34` 走
`_add_rect(..., stroke_w=2.0)`, 而 `_add_rect` 内部就是 `nine_if_big(w, h, "panel-frame.png", 20, sb)`
—— `34 < 40` ⇒ 退回 StyleBoxFlat(四边 2px 描边 + 底 a=0.92) = 网页盒。
**它一直没被数到**: 那颗钮只在双形态龟(双头/熔岩)身上画, 而 `verify_ui_consistency`
量图鉴时**只量列表第一条** ⇒ 棘轮基线 `Codex web≤0` 一直绿着。

⇒ 一处一处靠肉眼撞见是打地鼠。这个审计器把**会落进降级分支的调用点**扫出来。

════════════════════════════════════════════════════════════════════════
 ★降级/挑错皮的**确切条件**(逐条读 ui_skin.gd 得出, 不是凭印象)
════════════════════════════════════════════════════════════════════════
【A】`nine_if_big` 尺寸门槛                     ui_skin.gd:42 / :47-48
     `w < MIN_FRAME_PX or h < MIN_FRAME_PX` ⇒ return fallback。
     间接路径: `CodexScene._add_rect(cx, cy, w, h, color, a, stroke, stroke_w, …)`
     —— 只在 `stroke != "" and stroke_w >= 1.0` 时才走 `nine_if_big(w, h, "panel-frame.png", 20, sb)`
     (CodexScene.gd:845-846)。无描边的(分隔线 h=1 / 实心色块)**按设计**不套框, 不算命中。

【B】贴图不在 ⇒ 静默退回                        ui_skin.gd:66-67 / :111-114
     `ResourceLoader.exists(p)` 为假就 return fallback。
     ★`exists()` 对**没有 `.import` 的 PNG 返回 false 且不报错**(ui_skin.gd:26 自己写着)
     ⇒ 判据要同时查 `.png` **和** `.png.import`, 只查 png 会漏。
     `button()` 更狠: 两张都不在就 `return`(:114) —— 按钮**一点没动** = Godot 默认皮,
     而 `button()` 本来就是为了消灭默认皮而写的(:95-98)。

【C】边距之和 ≥ 目标尺寸 ⇒ 中段是负的、框直接画不出来   ui_skin.gd:28-30(铁律③)
     `2*margin >= minf(w, h)`。头注点名栽过两次(头像框 64→56、资源条 24→14)。
     ⚠ `_add_rect` 走 margin=20 ⇒ 它的"安全区"其实是 `> 40`, 而门槛 A 是 `>= 40`,
     **`w` 或 `h` 恰好 40 的那一档: 过了 A, 却在 C 上中段 = 0。**

【D】`UISkin.button` 按尺寸挑皮                  ui_skin.gd:107-110 / :121
     `big = minf(w,h) >= 56.0 and w*h >= 5000.0`; big ⇒ `menu/frame-rect.png`(margin 27),
     否则 `chip-frame.png`(源图 **48×24**, margin 7)。
     ★:101-104 记着这条判据的**由来**: 原来一律用 chip-frame, 120×81 的返回键
     "把它拉了 **2.5~3.4 倍** ⇒ 金属细节全被拉平, 看起来就是一块灰板"。
     ⇒ **不 big 却远大于源图**的按钮就是那个形状 —— 判据阈值 `STRETCH_BAR` 直接
     取自这段头注的 2.5(不是我拍的), 见下方常量处的说明。
     ★`w`/`h` 取 `maxf(b.size, b.custom_minimum_size)`(:107-108), 所以判据两个都要看。

【F】`nine_if_big` 中段拉伸过头                  ui_skin.gd:54-61
     `nine()` 的 `tile` 默认 false = STRETCH; 而 `nine_if_big` **根本没有 tile 参数**
     ⇒ 经它走的框一律拉伸。头注实测: 64×64 的 `portrait-frame` 用在 200×200 上,
     中段 5.25 倍 ⇒ 铆钉拉成细线、"实拍只剩四个孤立金角块"。
     同一把尺子(STRETCH_BAR), 量**控件尺寸 ÷ 源图尺寸**。

【E】**尺寸不是字面量 ⇒ 静态判不了**  ← 这条判据的**已知失明**, 必须打印条数
     `host._sp(766)`(缩放函数) / `card_w = (DETAIL_W - 2*start_x - …) / n`(跑时才知道)
     这一类**解析不出来**。它们**不是"没问题"**, 是"这条判据看不见"。
     ⇒ 单独成类、打印条数; 想覆盖它们只能靠运行期实拍(`verify_ui_consistency` 那一路)。

════════════════════════════════════════════════════════════════════════
 ★尺寸怎么解析出来的(以及为什么必须做局部变量解析)
════════════════════════════════════════════════════════════════════════
那个真 bug 的写法是:

    var btn_w = 196.0
    var btn_h = 34.0
    host._add_rect(btn_x, btn_y, btn_w, btn_h, bg_hex, 0.92, border_hex, 2.0, 1.0)

⇒ **只认字面量的扫描器抓不到它**(参数是 `btn_w`/`btn_h`)。所以解析器做三层:
  ① 数字字面量与它们的四则运算
  ② 同文件的 `const NAME := <数>`(以及跨文件**全仓唯一**的同名 const —— `host.DETAIL_W`
     这一类; 同名 const 取值不唯一就当解析不出, 宁可进 E 类也不猜)
  ③ **所在函数内、调用点之前**的 `var name = <数>` / `name = <数>`
     —— 同一个名字被赋过两个不同的值就作废(算 E 类), 不挑一个信。
只要出现函数调用(`_sp(`/`maxf(`/`clampf(`)就直接作废。**方向是保守的: 会漏报, 不会假报。**

════════════════════════════════════════════════════════════════════════
 ★门槛从 ui_skin.gd **读出来**, 不抄
════════════════════════════════════════════════════════════════════════
memory [[fb-hand-rolled-copies-drift]]:「手抄的副本必然落后」。
`MIN_FRAME_PX` / `big` 的 56 与 5000 / big 那档的 margin=27 / chip-frame 的 margin 默认值
全部**正则从 ui_skin.gd 抓**; 抓不到就 **FAIL**(而不是退回我写死的默认值 —— 那正好
是"静默降级"本身的形状)。

════════════════════════════════════════════════════════════════════════
 ★台账: 脚本自己生成, 只减不增
════════════════════════════════════════════════════════════════════════
`tools/_nine_downgrade_ledger.json` 由 `--update` 写, **不要手改**。
★台账的键**不含行号** —— 8 个 agent 正在改 `scripts/`, 行号每分钟都在漂;
  键用 `文件|类|调用|尺寸`, 行号只在报告里打。
每条存量必须在 `WHY` 里有**理由**, 没理由当场红(memory: 不写理由的白名单和放宽判据是一回事)。

跑法:
  python tools/nine_downgrade_audit.py            # 对账(进门禁)
  python tools/nine_downgrade_audit.py --update    # 按当前实测重写台账
  python tools/nine_downgrade_audit.py --file <p>  # 只看一个文件(反向验证用)
  git show HEAD~3:scripts/scenes/codex/detail_views.gd > /tmp/x.gd \
      && python tools/nine_downgrade_audit.py --blob /tmp/x.gd=scripts/scenes/codex/detail_views.gd
      # ↑ 反向验证: 拿**真实的历史违规**喂进来, 确认判据会红(不用动工作树)
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gd_text_scan as _G                       # noqa: E402  共享的"去行尾注释但不碰字符串"实现

NL = chr(10)
BS = chr(92)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(ROOT, "tools", "_nine_downgrade_ledger.json")
SKIN = "scripts/util/ui_skin.gd"
SCAN_DIRS = ["scripts", "autoload"]
SPRITE_DIR = "assets/sprites"

## ★这把尺子**不是我拍的**: ui_skin.gd:101-104 的头注写着 chip-frame(48×24) 被
##   120×81 的返回键 "拉了 2.5~3.4 倍 ⇒ 金属细节全被拉平, 看起来就是一块灰板"。
##   2.5 就是那段实拍里**最小的那个倍数** —— 取它当下限, 比它小的没有实拍证据说糊。
##   (memory [[fb-my-thresholds-degrade-good-assets]]: 我拍的阈值会把好素材改坏
##    ⇒ 只用仓库自己量过的数。)
STRETCH_BAR = 2.5

## 源图尺寸从 PNG 头读, 不写死(换素材了判据要跟着变)。
_PNG_CACHE = {}


# ══════════════════════════════════════════════════════════════════════
#  白名单/理由 —— 每条存量必须有一条, 没有就红
# ══════════════════════════════════════════════════════════════════════
## 键 = 台账键(`文件|类|调用|尺寸`)。**不含行号**, 见头注。
WHY = {
    ## ── A 类(尺寸门槛降级) ──────────────────────────────────────────
    "scripts/scenes/ShopScene.gd|A|nine_if_big|36x36":
        "【刻意】商店卡片上的迷你装备格 36px。ui_skin.gd:35-41 记着 2026-08-18 的实拍退回 ——"
        "套上 57×57 槽框后四角铆钉吃掉大半格子, 更要命的是**费用色从「整块实心」退化成"
        "「一圈细边」, 而那块实心色本身就是信息**。ShopScene.gd 那一段注释(「走 nine_if_big 让"
        "尺寸哪天变大时自动升级, 而不是我在这里替未来拍一个死结论」)说得就是这件事: "
        "**这里传 nine_if_big 是为了拿到那个自动降级**, 不是失误。"
        "⚠ 但**降到的那块 StyleBoxFlat 本身是个网页盒**: :569 `set_border_width_all(1)`(四边)"
        " + `bg_color.a = 0.03` < 0.95, 正好命中 verify_ui_consistency:653-655 的判据, "
        "而 Shop 的基线是 `web: 0`(:127)。它现在绿着**只因为**「空装备槽」这一支在门禁那个"
        "商店状态下不渲染(货架单位都带装备) —— 与 196×34 同一种盲区。"
        "⇒ 真解是让 fallback 别长成网页盒(去掉四边描边, 或把底做成不透明), **不是**把框套回来。",
    "scripts/scenes/codex/detail_views.gd|A|_add_rect|100x34":
        "[待修] **真 bug, 与 2026-09-27 修掉的 196×34 形态钮一模一样的形状。**"
        "技能详情页那颗「← 返回」钮 100×34 走 `_add_rect(…, stroke='#58d3ff', stroke_w=1)`,"
        "而 `_add_rect` 内部是 `nine_if_big(w, h, 'panel-frame.png', 20, sb)` ⇒ 34 < 40 ⇒"
        "静默退回 StyleBoxFlat(1px 描边 + 底 a=0.9) = `verify_ui_consistency` 定义的网页盒。"
        "它藏在**点开某个技能之后**那一层, 而 verify_ui_consistency 量图鉴只量列表第一条"
        "⇒ 从来没被数到。修法照隔壁 :624 的 `_plaque()`(chip-frame 边带 4px, 34 高装得下)。"
        "★这条**不是白名单**: 它在 DEBT 里, 每跑一次都会大声打出来。",

    ## ── C 类(边距×2 ≥ 尺寸) ────────────────────────────────────────
    ## (当前无存量。⚠ `_add_rect` 走 margin=20 ⇒ 它的安全区是 **> 40**, 而门槛 A 是 **>= 40**:
    ##  `w` 或 `h` 恰好 40 的那一档会过了 A 却在 C 上中段 = 0。有了就必须逐条写理由。)

    ## ── D 类(button 挑错皮: 不 big ⇒ 48×24 的 chip-frame 被拉平) ────
    ## ★这一族**同一个根因**: `big` 要求短边 ≥56, 而 `frame-rect` 的边带 27×2 = 54 ——
    ##   也就是说 56 这道线就是为了"边带装得进去"划的。于是**所有 30~52 高的宽扁按钮**
    ##   两头都落空: chip-frame 太小(拉 2.5~9.2 倍), frame-rect 装不进去。
    ##   ⇒ 这是**素材缺口**(缺一张宽扁签牌), 不是调用方写错了。逐条记账、不许再长。
    "scripts/scenes/InventoryScene.gd|D|button|120x40 battlehud/chip-frame.png(48x24)":
        "背包「知道了」×2(阵容帮助框 / 装备详情框) 120×40, 拉 2.50×1.67 —— **正好踩在"
        "ui_skin.gd:103 记的下限 2.5 上**, 而那段实拍说糊是 120×**81**(竖着 3.4 倍)。"
        "主菜单 :1637 的注释也明说「120×40 短边 <56 ⇒ 用 chip-frame, 正是给这个尺寸画的那张」"
        "⇒ 作者拍过板。记账是为了别让**更宽更扁的**混进来, 不是要改这两颗。",
    "scripts/scenes/InventoryScene.gd|D|button|170x38 battlehud/chip-frame.png(48x24)":
        "背包底部操作条「卖出 +N」/ 糖罐「砸开」170×38, 拉 3.54×1.58。38 高连 40 都没到,"
        "换不了 frame-rect(边带 54)。素材缺口那一族, 见上面这段总说明。",
    "scripts/scenes/MainMenuScene.gd|D|button|120x40 battlehud/chip-frame.png(48x24)":
        "主菜单「开打」120×40, 拉 2.50×1.67。MainMenuScene.gd:1635-1639 的注释就是为它写的"
        "(从 Bootstrap 圆角 primary 换成金属签牌), 并**明确选了** chip-frame。作者拍过板。",
    "scripts/scenes/SettingsScene.gd|D|button|150x30 battlehud/chip-frame.png(48x24)":
        "设置屏里的小操作钮 150×30, 拉 3.12×1.25。**30 高**是这一族里最扁的 ——"
        "竖向只有 1.25 倍(几乎不拉), 糊在横向。素材缺口那一族。",
    "scripts/scenes/SettingsScene.gd|D|button|210x52 battlehud/chip-frame.png(48x24)":
        "「清空存档」确认框的 先不清 / 确定 两颗 210×52, 拉 4.38×2.17。"
        "**52 只差 4px 就够 big** —— 但 frame-rect 边带 27×2=54 > 52, 真换过去中段是负的"
        "(那就是 C 类)。⇒ 只能等宽扁签牌素材, 不是改个阈值能解决的。",
    "scripts/scenes/SettingsScene.gd|D|button|230x50 battlehud/chip-frame.png(48x24)":
        "设置屏三选一的选项钮 230×50, 拉 4.79×2.08。同上: 50 < 54, frame-rect 装不进。",
    "scripts/scenes/SettingsScene.gd|D|button|240x48 battlehud/chip-frame.png(48x24)":
        "设置屏「先不选」240×48, 拉 5.00×2.00。注释(:301)说明它是**为了过 81 触摸线**"
        "才从 160×40 拉成 240×48 的 —— 热区判据把它推宽, 反而把贴图拉得更扁。"
        "两条判据方向相反, 真解还是宽扁签牌素材。",
    "scripts/scenes/SettingsScene.gd|D|button|440x46 battlehud/chip-frame.png(48x24)":
        "登录/绑邮箱流程的整行钮 ×3(发验证码 / 确定 / 关闭) 440×46, **拉 9.17×1.92 ——"
        "这一族里最糟的一个**。:544 的注释说宽 440 是为了过热区判据。"
        "⇒ 这三颗是最该优先补素材的(而且它们在**关不掉的登录墙**那一屏上, 每个新玩家必见)。",
    "scripts/scenes/inventory/candy_jar.gd|D|button|120x44 battlehud/chip-frame.png(48x24)":
        "糖罐「收下」120×44, 拉 2.50×1.83。和背包那两颗「知道了」同一个尺寸族, 见上。",
    "scripts/scenes/inventory/synergy_panel.gd|D|button|120x40 battlehud/chip-frame.png(48x24)":
        "羁绊面板「知道了」120×40, 拉 2.50×1.67。同一族; :375 的注释还专门警告过"
        "「必须在 size 之后调」(那条就是 G 类), 顺序是对的。",

    ## ── F 类(nine_if_big 中段拉伸过头) ─────────────────────────────
    "scripts/scenes/CodexScene.gd|F|nine_if_big|170x56 battlehud/chip-frame.png(48x24)":
        "图鉴顶部分类页签 170×56, 中段拉 3.54×2.33。chip-frame 就是**给签牌画的**"
        "(源图 48×24 = 2:1 扁签), 170×56 是 3.0:1 —— **同一个长宽比方向**, 拉的是中段"
        "那条平直金属带而不是花纹; 边带 7px 在 56 高里占 25%, 四角原样。"
        "与战斗面板的签牌是同一张、同一用法。",

    ## ── G 类(button() 调在设尺寸之前) ──────────────────────────────
    "scripts/scenes/battle/dmg_stats_panel.gd|G|button|34x26":
        "[待修] **顺序反了**: `UISkin.button(close, …)` 在前, `close.custom_minimum_size ="
        " Vector2(34, 26)` 在后 ⇒ 调用那一刻 `b.size` 与 `b.custom_minimum_size` 都是 0,"
        "`big` 恒 false。今天结果碰巧一样(34×26 本来也不 big), 所以**是埋着的**: 谁把这颗 ×"
        "改大一点就静默挑错皮。同一个文件的 synergy_panel.gd:375 / candy_jar.gd:104 都写着"
        "「⚠ 必须在 size 之后调」—— 规矩有, 这一处漏了。修法: 把 :381 那行挪到 button() 之前。"
        "★这条**不是白名单**: 它在 DEBT 里, 每跑一次都会大声打出来。",
}


## ══════════════════════════════════════════════════════════════════════
##  DEBT —— 「已确认是 bug、还没修」。**不是白名单**
## ══════════════════════════════════════════════════════════════════════
## ★memory [[fb-gate-can-pin-the-bug-in-place]]: 把一个真 bug 写进白名单, 门禁就替它站岗了。
##   所以这里分两本账:
##     `WHY` 里普通的那些 = 查过、**确实该这样**(小件刻意直角 / 素材缺口 / 作者拍过板);
##     `DEBT` 里的这些   = **真 bug**, 只是我(工具侧)不许改 `scripts/`。
##   DEBT 的条目**每跑一次都会大声打印**(即使全绿), 并且棘轮照样盯着它不许长。
DEBT = {
    "scripts/scenes/codex/detail_views.gd|A|_add_rect|100x34",
    "scripts/scenes/battle/dmg_stats_panel.gd|G|button|34x26",
}


# ══════════════════════════════════════════════════════════════════════
#  ui_skin.gd 的门槛: 读出来, 不抄
# ══════════════════════════════════════════════════════════════════════
def read_thresholds(txt):
    """从 ui_skin.gd 源码里抓出降级/挑皮的全部门槛。抓不到 → None(调用方 FAIL)。"""
    t = {}
    m = re.search(r"const\s+MIN_FRAME_PX\s*:?=\s*([0-9.]+)", txt)
    if m:
        t["min_frame"] = float(m.group(1))
    ## `var big: bool = minf(w, h) >= 56.0 and w * h >= 5000.0`
    m = re.search(r"big\s*:\s*bool\s*=\s*minf\(\s*w\s*,\s*h\s*\)\s*>=\s*([0-9.]+)"
                  r"\s*and\s*w\s*\*\s*h\s*>=\s*([0-9.]+)", txt)
    if m:
        t["big_min"] = float(m.group(1))
        t["big_area"] = float(m.group(2))
    ## big 那一档的贴图与 margin
    m = re.search(r'tex\s*:?=\s*\(\s*"res://assets/sprites/([^"]+)"\s*if\s+big\s+else\s+'
                  r'TEX_DIR\s*\+\s*"([^"]+)"\s*\)', txt)
    if m:
        t["big_tex"] = m.group(1)
        t["small_tex"] = m.group(2)
    m = re.search(r"if\s+big\s*:" + NL + r"\s*margin\s*=\s*([0-9]+)", txt)
    if m:
        t["big_margin"] = int(m.group(1))
    m = re.search(r"static\s+func\s+button\s*\([^)]*margin\s*:\s*int\s*=\s*([0-9]+)", txt)
    if m:
        t["btn_margin"] = int(m.group(1))
    ## `nine_if_big` 内部固定挂哪张图? 它是参数, 不固定 —— 但降级分支必须长成 A 类那样
    if not re.search(r"if\s+w\s*<\s*MIN_FRAME_PX\s+or\s+h\s*<\s*MIN_FRAME_PX\s*:\s*" + NL
                     + r"\s*return\s+fallback", txt):
        t["min_frame_branch"] = False
    else:
        t["min_frame_branch"] = True
    need = ["min_frame", "big_min", "big_area", "big_tex", "small_tex", "big_margin", "btn_margin"]
    if any(k not in t for k in need) or not t["min_frame_branch"]:
        return None, [k for k in need if k not in t] + ([] if t.get("min_frame_branch") else ["降级分支形状"])
    return t, []


# ══════════════════════════════════════════════════════════════════════
#  源码扫描: 把可能跨行的调用整条抓出来
# ══════════════════════════════════════════════════════════════════════
CALL_RE = re.compile(r"(?<![A-Za-z0-9_])(?:UISkin\s*\.\s*)?"
                     r"(nine_if_big|nine|button|slot|_add_rect)\s*\(")
DEF_RE = re.compile(r"^\s*(?:static\s+)?func\s+")
FUNC_HEAD = re.compile(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
NUMSAFE = re.compile(r"^[0-9.+\-*/() ]+$")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*")
CONST_RE = re.compile(r"^const\s+([A-Z_][A-Z0-9_]*)\s*(?::\s*[A-Za-z0-9_]+\s*)?:?=\s*(.+?)\s*$")
ASSIGN_RE = re.compile(r"^\s*(?:var\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z0-9_]+\s*)?"
                       r":?=\s*(.+?)\s*$")


def strip_all(txt):
    """逐行去行尾注释(保留行数与行号)。用 gd_text_scan 的实现: 不能碰 `"#ffd93d"`。"""
    return NL.join(_G.strip_comment(l) for l in txt.split(NL))


def split_args(s):
    """顶层逗号切参。跳字符串、括号/方括号/花括号。"""
    out = []
    buf = []
    d = 0
    in_s = False
    q = ""
    i = 0
    while i < len(s):
        c = s[i]
        if in_s:
            buf.append(c)
            if c == BS:
                i += 1
                if i < len(s):
                    buf.append(s[i])
                    i += 1
                continue
            if c == q:
                in_s = False
            i += 1
            continue
        if c in "\"'":
            in_s = True
            q = c
            buf.append(c)
            i += 1
            continue
        if c in "([{":
            d += 1
        elif c in ")]}":
            d -= 1
        if c == "," and d == 0:
            out.append("".join(buf).strip())
            buf = []
            i += 1
            continue
        buf.append(c)
        i += 1
    tail = "".join(buf).strip()
    if tail or out:
        out.append(tail)
    return out


def grab_call(txt, open_paren):
    """从 `(` 的下标开始, 平衡到闭括号(可跨行), 返回 (内部串, 闭括号下标)。"""
    d = 0
    in_s = False
    q = ""
    i = open_paren
    while i < len(txt):
        c = txt[i]
        if in_s:
            if c == BS:
                i += 2
                continue
            if c == q:
                in_s = False
            i += 1
            continue
        if c in "\"'":
            in_s = True
            q = c
            i += 1
            continue
        if c == "(":
            d += 1
        elif c == ")":
            d -= 1
            if d == 0:
                return txt[open_paren + 1:i], i
        i += 1
    return None, -1


def collect_consts(txt):
    """同文件的 `const NAME := <expr>` → {name: float}(能算出数的那些)。"""
    raw = {}
    for ln in txt.split(NL):
        m = CONST_RE.match(ln)
        if m:
            raw[m.group(1)] = m.group(2)
    out = {}
    for _ in range(4):
        for k, v in raw.items():
            if k in out:
                continue
            f = _num(v, out, {})
            if f is not None:
                out[k] = f
    return out


def _tern_split(e):
    """`a if cond else b` 在**顶层**切开 → (a, b); 不是三元就 None。

    ★为什么非要处理三元: 图鉴被动条写的是 `var pbar_sw: float = 2.0 if … else 1.0`,
      卡片描边写的是 `2.5 if (is_default and not is_locked) else 2.0`。
      只认字面量的话这两处全掉进 E 类(已知失明), 而它们其实**两支都判得了**。
    """
    depth = 0
    in_s = False
    q = ""
    ifp = -1
    elsep = -1
    i = 0
    while i < len(e):
        c = e[i]
        if in_s:
            if c == BS:
                i += 2
                continue
            if c == q:
                in_s = False
            i += 1
            continue
        if c in "\"'":
            in_s = True
            q = c
            i += 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if depth == 0:
            if e.startswith(" if ", i) and ifp < 0:
                ifp = i
            elif e.startswith(" else ", i):
                elsep = i
        i += 1
    if ifp < 0 or elsep < 0 or elsep < ifp:
        return None
    return e[:ifp].strip(), e[elsep + 6:].strip()


def _num_all(expr, consts, loc):
    """表达式的**全部可能取值**(三元就两支都给)。任一支解析不出 → None。"""
    e = (expr or "").strip()
    v = _num_plain(e, consts, loc)
    if v is not None:
        return [v]
    t = _tern_split(e)
    if t is None:
        return None
    a = _num_all(t[0], consts, loc)
    b = _num_all(t[1], consts, loc)
    if a is None or b is None:
        return None
    return a + b


def _num(expr, consts, loc):
    """把表达式解析成**唯一**的 float; 解析不出(或三元两支不等)返回 None。
    **宁可 None 也不猜** —— None 会进 E 类(已知失明), 猜错会造假报。"""
    vs = _num_all(expr, consts, loc)
    if not vs:
        return None
    return vs[0] if max(vs) - min(vs) <= 1e-9 else None


def _num_plain(expr, consts, loc):
    """不含三元的表达式 → float。"""
    e = (expr or "").strip()
    if e == "":
        return None
    for _ in range(8):
        if NUMSAFE.match(e):
            break
        ids = sorted(set(IDENT.findall(e)), key=len, reverse=True)
        if not ids:
            return None
        moved = False
        for name in ids:
            base = name.split(".")[-1]
            val = loc.get(name, loc.get(base, consts.get(base)))
            if val is None:
                return None
            e = re.sub(r"(?<![A-Za-z0-9_.])" + re.escape(name) + r"(?![A-Za-z0-9_])",
                       "(" + repr(float(val)) + ")", e)
            moved = True
        if not moved:
            return None
    if not NUMSAFE.match(e):
        return None
    try:
        v = eval(e, {"__builtins__": {}}, {})       # noqa: S307  已按 NUMSAFE 白名单过滤
    except Exception:
        return None
    return float(v) if isinstance(v, (int, float)) else None


def func_span(lines, lineno):
    """`lineno`(1-based)所在函数的 [起, 止) 行区间(0-based)。找不到就整文件。"""
    i = lineno - 1
    start = 0
    for j in range(min(i, len(lines) - 1), -1, -1):
        if FUNC_HEAD.match(lines[j]):
            start = j
            break
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if FUNC_HEAD.match(lines[j]):
            end = j
            break
    return start, end


def locals_before(lines, lineno, consts):
    """所在函数内、调用点**之前**的 `var x = <数>` / `x = <数>`。
    同名赋过两个不同的值 ⇒ 作废(不挑一个信)。"""
    start, _end = func_span(lines, lineno)
    seen = {}
    bad = set()
    ## `expr`: 名字 → 它的右式**原文**。给 `_num_all_x` 用 —— `var pbar_sw := 2.0 if … else 1.0`
    ## 算不出唯一值(所以进不了 `seen`), 但**两支都判得了**, 别浪费。
    expr = {}
    n_asg = {}
    for j in range(start, lineno - 1):
        m = ASSIGN_RE.match(lines[j])
        if not m:
            continue
        nm, rhs = m.group(1), m.group(2)
        if rhs.endswith(BS) or "==" in lines[j].split("=")[0]:
            continue
        n_asg[nm] = n_asg.get(nm, 0) + 1
        expr[nm] = rhs
        f = _num(rhs, consts, seen)
        if f is None:
            bad.add(nm)
            continue
        if nm in seen and abs(seen[nm] - f) > 1e-9:
            bad.add(nm)
        seen[nm] = f
    for nm in bad:
        seen.pop(nm, None)
    ## 赋过两次以上的名字**不给** expr(不挑一支信)
    return seen, {k: v for k, v in expr.items() if n_asg.get(k, 0) == 1}


def _num_all_x(expr, consts, loc, loc_expr, depth=0):
    """`_num_all` + **展开一层局部名**。`stroke_w=pbar_sw` 那种写法靠它才判得了。"""
    vs = _num_all(expr, consts, loc)
    if vs is not None:
        return vs
    e = (expr or "").strip()
    if depth < 3 and re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", e) and e in loc_expr:
        return _num_all_x(loc_expr[e], consts, loc, loc_expr, depth + 1)
    return None


def node_size(lines, lineno, argname, consts):
    """`UISkin.button(b, …)` 的 b 有多大? 照 ui_skin.gd:107-108 取
    `maxf(b.size, b.custom_minimum_size)` 两者的**大**。找不到 → None。
    先在所在函数里找, 再退到整文件(成员按钮 `_email_send_btn` 那一类)。"""
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", argname or ""):
        return None
    pat = re.compile(r"(?<![A-Za-z0-9_])" + re.escape(argname)
                     + r"\s*\.\s*(size|custom_minimum_size)\s*=\s*Vector2\s*\(([^)]*)\)")
    best = [None, None]
    at = []                              # 设尺寸的行号(判"设在调用之后"用)
    start, end = func_span(lines, lineno)
    ## ★整文件兜底**只给成员字段**(`_email_send_btn` 那一类)。
    ##   局部名(`ok` / `b` / `close`)在别的函数里也叫这个名字 ⇒ 跨函数取尺寸会**认错人**,
    ##   那就成了假报。宁可让它进 E 类(已知失明)。
    scopes = [(start, end)]
    if argname.startswith("_"):
        scopes.append((0, len(lines)))
    for scope in scopes:
        loc, _le = locals_before(lines, min(scope[1], len(lines)), consts)
        for j in range(scope[0], scope[1]):
            for m in pat.finditer(lines[j]):
                a = split_args(m.group(2))
                if len(a) != 2:
                    continue
                w = _num(a[0], consts, loc)
                h = _num(a[1], consts, loc)
                if w is None or h is None:
                    continue
                best[0] = w if best[0] is None else max(best[0], w)
                best[1] = h if best[1] is None else max(best[1], h)
                at.append(j + 1)
        if best[0] is not None and best[1] is not None:
            return (best[0], best[1], at)
    return None


def png_size(rel):
    """`assets/sprites/<rel>` 的 (w, h); 读不到 → None。"""
    if rel in _PNG_CACHE:
        return _PNG_CACHE[rel]
    p = os.path.join(ROOT, SPRITE_DIR, rel)
    out = None
    try:
        with open(p, "rb") as f:
            d = f.read(32)
        if d[:8] == b"\x89PNG\r\n\x1a\n" and d[12:16] == b"IHDR":
            out = (int.from_bytes(d[16:20], "big"), int.from_bytes(d[20:24], "big"))
    except Exception:
        out = None
    _PNG_CACHE[rel] = out
    return out


def tex_rel(name):
    """`nine()` 的名字 → assets/sprites 下的相对路径(ui_skin.gd:65 的规则)。"""
    return name if "/" in name else ("battlehud/" + name)


def lit_str(a):
    """参数是字符串字面量就返回它的内容, 否则 None。"""
    a = (a or "").strip()
    if len(a) >= 2 and a[0] == a[-1] and a[0] in "\"'":
        return a[1:-1]
    return None


# ══════════════════════════════════════════════════════════════════════
#  逐文件判定
# ══════════════════════════════════════════════════════════════════════
def audit_file(rel, raw, th, gconsts, out):
    """out: 累加 dict(见 main 的初始化)。"""
    txt = strip_all(raw)
    lines = txt.split(NL)
    ## 行首偏移 → 行号
    offs = []
    o = 0
    for l in lines:
        offs.append(o)
        o += len(l) + 1

    def line_of(pos):
        lo, hi = 0, len(offs) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if offs[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    consts = dict(gconsts)
    consts.update(collect_consts(txt))

    for m in CALL_RE.finditer(txt):
        kind = m.group(1)
        ln = line_of(m.start())
        if DEF_RE.match(lines[ln - 1]):
            continue                                    # 定义行本身
        body, close = grab_call(txt, m.end() - 1)
        if body is None:
            continue
        args = split_args(body)
        out["sites"] += 1
        out["by_kind"][kind] = out["by_kind"].get(kind, 0) + 1
        loc, loc_expr = locals_before(lines, ln, consts)
        where = "%s:%d" % (rel, ln)

        ## ── 转发点: `_add_rect` 自己内部那句 `nine_if_big(w, h, …)` ──────
        ## 它的 w/h **就是 `_add_rect` 的形参**, 由每个调用方决定 ⇒ 已经在调用方那侧判过了。
        ## 把它算进 E 类("尺寸不是字面量")会**虚报失明**, 单独记一格。
        fstart, _fend = func_span(lines, ln)
        fh = FUNC_HEAD.match(lines[fstart])
        if kind == "nine_if_big" and fh and fh.group(1) == "_add_rect":
            out["forwarded"] += 1
            out["fwd_rows"].append("%s  `_add_rect` 自己的漏斗(w/h 是形参 ⇒ 已在每个"
                                   "调用方那一侧判过)" % where)
            continue

        ## ── 贴图存在性(B 类): 凡参数里有贴图名字面量的都查 ────────────
        tname = None
        if kind == "nine" and len(args) >= 1:
            tname = lit_str(args[0])
        elif kind == "nine_if_big" and len(args) >= 3:
            tname = lit_str(args[2])
        elif kind == "slot":
            tname = "slot-frame.png"                    # ui_skin.gd:83 写死
        elif kind == "button":
            tname = None                                # 两张都查, 见下
        if tname is not None:
            out["tex_checked"] += 1
            r = tex_rel(tname)
            png = os.path.join(ROOT, SPRITE_DIR, r)
            if not os.path.exists(png):
                out["hits"].append(("B", rel, ln, kind, "%s 不存在" % r, where))
            elif not os.path.exists(png + ".import"):
                out["hits"].append(("B", rel, ln, kind,
                                    "%s 有 png 没 .import ⇒ ResourceLoader.exists() 返回 false" % r,
                                    where))
        if kind == "button":
            for t in (th["big_tex"], "battlehud/" + th["small_tex"]):
                out["tex_checked"] += 1
                png = os.path.join(ROOT, SPRITE_DIR, t)
                if not os.path.exists(png) or not os.path.exists(png + ".import"):
                    out["hits"].append(("B", rel, ln, kind,
                                        "%s 缺 png/.import ⇒ button() 会 return, 按钮保持"
                                        "Godot 默认皮" % t, where))

        ## ── 尺寸解析 ────────────────────────────────────────────────
        w = h = None
        margin = None
        tex = tname
        if kind == "nine_if_big":
            if len(args) >= 5:
                w = _num(args[0], consts, loc)
                h = _num(args[1], consts, loc)
                margin = _num(args[3], consts, loc)
        elif kind == "_add_rect":
            ## (cx, cy, w, h, color, a, stroke="", stroke_w=0.0, stroke_a=1.0)
            if len(args) >= 6:
                w = _num(args[2], consts, loc)
                h = _num(args[3], consts, loc)
                stroke = args[6] if len(args) >= 7 else '""'
                sws = _num_all_x(args[7], consts, loc, loc_expr) if len(args) >= 8 else [0.0]
                if lit_str(stroke) == "" or (len(args) < 7):
                    out["by_design"] += 1                # 无描边: 分隔线/实心块, 按设计不套框
                    continue
                if sws is None or (min(sws) < 1.0 <= max(sws)):
                    ## stroke_w 判不了 ⇒ 判不出它到底有没有走 nine_if_big。**算 E 类失明**,
                    ## 不许当成"没问题"(那正是这条判据要避免的假绿)。
                    out["unresolved"] += 1
                    out["unres_rows"].append("%s  _add_rect stroke_w 判不了(%s) ⇒ 判不出有没有走"
                                             " nine_if_big"
                                             % (where, (args[7] if len(args) >= 8 else "?")[:40]))
                    continue
                if max(sws) < 1.0:
                    out["by_design"] += 1
                    continue
                margin = 20.0                            # CodexScene.gd:846 写死
                tex = "panel-frame.png"
        elif kind == "button":
            sz = node_size(lines, ln, args[0] if args else "", consts)
            if sz is None:
                out["unresolved"] += 1
                out["unres_rows"].append("%s  button(%s) 的控件尺寸找不到字面量"
                                         % (where, (args[0] if args else "?")[:30]))
                continue
            w, h, at_lines = sz
            out["resolved"] += 1
            ## ── G: 尺寸**设在 button() 之后** ⇒ 它读到的是 0 ────────────
            ## ui_skin.gd:106-108 自己写着「要读 `b.size`, 而 `custom_minimum_size` 常常才是
            ## 调用方设的值 —— 两个取大」; 而 synergy_panel.gd:375 / candy_jar.gd:104 的注释
            ## 都在警告「**必须在 size 之后调**, size 还是 0 会挑错」。
            ## ⇒ 顺序反了就是 `big=false` 恒成立: 多大的按钮都挂 48×24 的 chip-frame,
            ##   **而且一声不响**(这正是这条判据要抓的那个形状)。
            if at_lines and min(at_lines) > ln:
                would = (min(w, h) >= th["big_min"] and w * h >= th["big_area"])
                out["hits"].append(("G", rel, ln, kind,
                                    "%gx%g 的尺寸设在第 %s 行 = **button() 之后** ⇒ 调用时读到"
                                    " 0x0, big 恒 false。%s"
                                    % (w, h, min(at_lines),
                                       "这颗按钮按真尺寸**本该** big ⇒ 现在挂错皮了(实害)"
                                       if would else
                                       "这颗按钮按真尺寸也不 big ⇒ 今天结果碰巧一样, 是**埋着的**:"
                                       "谁把它改大就静默挑错皮"), where))
                continue
            big = (min(w, h) >= th["big_min"] and w * h >= th["big_area"])
            tx = th["big_tex"] if big else ("battlehud/" + th["small_tex"])
            margin = float(th["big_margin"] if big else th["btn_margin"])
            src = png_size(tx)
            ## C: 边距×2 ≥ 控件短边
            if 2.0 * margin >= min(w, h):
                out["hits"].append(("C", rel, ln, kind,
                                    "%gx%g, margin %g ⇒ 2*margin=%g ≥ 短边 %g, 中段是负的"
                                    % (w, h, margin, 2 * margin, min(w, h)), where))
            ## D: 不 big 却远大于 chip-frame 源图 ⇒ 拉平成灰板
            if not big and src:
                rw, rh = w / src[0], h / src[1]
                if max(rw, rh) >= STRETCH_BAR:
                    out["hits"].append(("D", rel, ln, kind,
                                        "%gx%g 判为 not big(短边 %g<%g 或 面积 %g<%g) ⇒ 挂 %s"
                                        "(%dx%d), 拉 %.2fx%.2f 倍"
                                        % (w, h, min(w, h), th["big_min"], w * h, th["big_area"],
                                           tx, src[0], src[1], rw, rh), where))
            continue

        if kind in ("nine", "slot"):
            ## 没有尺寸参数 ⇒ 这条判据看不见它有多大(只查了贴图存在性与源图 margin)
            src = png_size(tex_rel(tname)) if tname else None
            mg = _num(args[1], consts, loc) if (kind == "nine" and len(args) >= 2) else 12.0
            if src and mg is not None and 2.0 * mg >= min(src):
                out["hits"].append(("C", rel, ln, kind,
                                    "margin %g ⇒ 2*margin=%g ≥ 源图短边 %d, 九宫格区在源图里重叠"
                                    % (mg, 2 * mg, min(src)), where))
            out["nosize"] += 1
            continue

        if w is None or h is None:
            out["unresolved"] += 1
            src_a = args[0] if kind == "nine_if_big" else (args[2] if len(args) > 2 else "?")
            src_b = args[1] if kind == "nine_if_big" else (args[3] if len(args) > 3 else "?")
            out["unres_rows"].append("%s  %s(w=%s, h=%s) 尺寸不是字面量"
                                     % (where, kind, src_a.strip()[:36], src_b.strip()[:36]))
            continue
        out["resolved"] += 1

        ## ── A: MIN_FRAME_PX 门槛 ───────────────────────────────────
        if w < th["min_frame"] or h < th["min_frame"]:
            out["hits"].append(("A", rel, ln, kind,
                                "%gx%g, 短边 %g < MIN_FRAME_PX(%g) ⇒ 静默退回 StyleBoxFlat"
                                % (w, h, min(w, h), th["min_frame"]), where))
            continue                                     # 已降级, C/F 不再叠报
        ## ── C: 边距×2 ≥ 短边 ──────────────────────────────────────
        if margin is not None and 2.0 * margin >= min(w, h):
            out["hits"].append(("C", rel, ln, kind,
                                "%gx%g, margin %g ⇒ 2*margin=%g ≥ 短边 %g, 中段是负的、框画不出来"
                                % (w, h, margin, 2 * margin, min(w, h)), where))
        ## ── F: 中段拉伸过头(nine_if_big 没有 tile 参数, 一律 STRETCH) ─
        src = png_size(tex_rel(tex)) if tex else None
        if src:
            rw, rh = w / src[0], h / src[1]
            if max(rw, rh) >= STRETCH_BAR:
                out["hits"].append(("F", rel, ln, kind,
                                    "%gx%g 挂 %s(%dx%d), 中段拉 %.2fx%.2f 倍(≥%.1f)"
                                    % (w, h, tex_rel(tex), src[0], src[1], rw, rh, STRETCH_BAR),
                                    where))


def ledger_key(cls, rel, kind, detail):
    """**不含行号**的稳定键(8 个 agent 正在改 scripts/, 行号每分钟都在漂)。"""
    m = re.match(r"^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)", detail)
    if m:
        sz = "%gx%g" % (float(m.group(1)), float(m.group(2)))
    else:
        sz = detail.split(",")[0][:48]
    tx = re.search(r"([A-Za-z0-9_\-/]+\.png)\((\d+)x(\d+)\)", detail)
    if tx and cls in ("D", "F"):
        sz += " %s(%sx%s)" % (tx.group(1), tx.group(2), tx.group(3))
    return "%s|%s|%s|%s" % (rel, cls, kind, sz)


def gd_files(dirs):
    out = []
    for d in dirs:
        base = os.path.join(ROOT, d)
        if not os.path.isdir(base):
            continue
        for dp, _dd, fs in os.walk(base):
            for f in fs:
                if f.endswith(".gd"):
                    p = os.path.join(dp, f).replace(BS, "/")
                    out.append(p[len(ROOT.replace(BS, "/")) + 1:])
    return sorted(out)


CLS_NAME = {
    "A": "A 尺寸门槛降级(nine_if_big → StyleBoxFlat)",
    "B": "B 贴图不在/无 .import ⇒ 静默退回",
    "C": "C 边距×2 ≥ 尺寸 ⇒ 中段是负的",
    "D": "D button 挑错皮(不 big 却远大于 chip-frame)",
    "F": "F 中段拉伸过头(nine_if_big 一律 STRETCH)",
    "G": "G UISkin.button() 调在设尺寸之前 ⇒ 读到 0x0, 永远挑小签",
}


def main():
    upd = "--update" in sys.argv
    only = None
    for a in sys.argv[1:]:
        if a.startswith("--file="):
            only = a.split("=", 1)[1].replace(BS, "/")
    ## `--skin=<路径>`: 拿**改过门槛的 ui_skin.gd 副本**跑。
    ## ★它存在的理由只有一个: 反向验证时**不许动工作树**(8 个 agent 正在改 `scripts/`)。
    ##   有了它, "把 MIN_FRAME_PX 调到 60, 看判据会不会多抓" 这种变异实验可以在 /c/tmp 里做。
    skin_rel = SKIN
    for a in sys.argv[1:]:
        if a.startswith("--skin="):
            skin_rel = a.split("=", 1)[1]
    blobs = []
    for a in sys.argv[1:]:
        if a.startswith("--blob="):
            p, _s, asrel = a.split("=", 1)[1].partition("=")
            blobs.append((p, asrel or p))

    print("=== 九宫格静默降级审计(「套了皮, 但其实没套上」· 台账只减不增) ===")

    skin_p = skin_rel if os.path.isabs(skin_rel) else os.path.join(ROOT, skin_rel)
    if not os.path.exists(skin_p):
        print("  [FAIL] 找不到 %s —— 门槛没处读, 这是空检查不是通过" % skin_rel)
        return 1
    skin_txt = strip_all(io.open(skin_p, encoding="utf-8", errors="replace", newline="").read()
                         .replace("\r\n", NL).replace("\r", NL))
    th, missing = read_thresholds(skin_txt)
    if th is None:
        print("  [FAIL] 从 %s 抓不到门槛: %s" % (skin_rel, ", ".join(missing)))
        print("         ★门槛必须**从 ui_skin.gd 读出来**(memory 手抄的副本必然落后)。")
        print("         那边的写法变了就来这里把正则改对 —— 退回写死的默认值本身就是"
              "「静默降级」那个形状。")
        return 1
    print("  [门槛·读自 %s] MIN_FRAME_PX=%g · big: 短边≥%g 且 面积≥%g · big 挂 %s(margin %d)"
          " · 否则 %s(margin %d) · 拉伸尺子 STRETCH_BAR=%.1f(取自 ui_skin.gd:101-104 实拍)"
          % (skin_rel, th["min_frame"], th["big_min"], th["big_area"], th["big_tex"],
             th["big_margin"], th["small_tex"], th["btn_margin"], STRETCH_BAR))

    files = gd_files(SCAN_DIRS)
    ## 全仓 const 表: 同名取值唯一才用(不唯一就让它进 E 类, 宁可漏不猜)
    seen_const = {}
    for rel in files:
        t = strip_all(io.open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace",
                              newline="").read().replace("\r\n", NL).replace("\r", NL))
        for k, v in collect_consts(t).items():
            seen_const.setdefault(k, set()).add(round(v, 6))
    gconsts = {k: list(v)[0] for k, v in seen_const.items() if len(v) == 1}

    out = {"sites": 0, "resolved": 0, "unresolved": 0, "by_design": 0, "nosize": 0,
           "tex_checked": 0, "forwarded": 0, "by_kind": {}, "hits": [], "unres_rows": [],
           "fwd_rows": []}

    if blobs:
        pairs = []
        for p, asrel in blobs:
            pairs.append((asrel, io.open(p, encoding="utf-8", errors="replace",
                                         newline="").read()))
        print("  [反向验证模式] 只扫 %d 个外部 blob: %s"
              % (len(pairs), ", ".join(a for a, _ in pairs)))
    else:
        pairs = []
        for rel in files:
            if only and rel != only:
                continue
            pairs.append((rel, io.open(os.path.join(ROOT, rel), encoding="utf-8",
                                       errors="replace", newline="").read()))

    for rel, raw in pairs:
        audit_file(rel, raw.replace("\r\n", NL).replace("\r", NL), th, gconsts, out)

    n_files = len(pairs)
    print("  [分母] 扫 %d 个 .gd · 调用点 %d 处(%s)"
          % (n_files, out["sites"],
             " / ".join("%s %d" % (k, v) for k, v in sorted(out["by_kind"].items()))))
    print("  [分母] 解析出尺寸 %d 处 · **解析不出 %d 处** · 按设计不套框(无描边分隔线/实心块)"
          " %d 处 · 无尺寸参数(nine/slot, **量不到控件多大** ⇒ F 与控件侧 C 对它失明)"
          " %d 处 · 形参转发点 %d 处"
          % (out["resolved"], out["unresolved"], out["by_design"], out["nosize"],
             out["forwarded"]))
    if out["sites"] != (out["resolved"] + out["unresolved"] + out["by_design"]
                        + out["nosize"] + out["forwarded"]):
        print("  [FAIL] 分母对不上: %d 个调用点 ≠ %d+%d+%d+%d+%d —— 有调用点被静默丢了"
              % (out["sites"], out["resolved"], out["unresolved"], out["by_design"],
                 out["nosize"], out["forwarded"]))
        return 1
    print("  [分母] 查了贴图存在性(png + .import) %d 次 · 全仓唯一 const %d 个"
          % (out["tex_checked"], len(gconsts)))
    print("  [分母] WHY 写了理由的 %d 条(其中 DEBT「已确认是 bug」%d 条)"
          % (len(WHY), len(DEBT)))
    if not DEBT.issubset(set(WHY)):
        print("  [FAIL] DEBT 里有条目没在 WHY 里写理由: %s"
              % ", ".join(sorted(DEBT - set(WHY))))
        return 1

    if not blobs and not only:
        if n_files < 50 or out["sites"] < 40:
            print("  [FAIL] 只扫到 %d 个 .gd / %d 个调用点 —— 收集失效了, 这是空检查不是通过"
                  % (n_files, out["sites"]))
            return 1
        if out["resolved"] < 10:
            print("  [FAIL] 只解析出 %d 处尺寸(<10) —— 尺寸解析器坏了, 判据成了空壳"
                  % out["resolved"])
            return 1

    ## ── E 类: 已知失明, 必须打印 ─────────────────────────────────────
    print("")
    print("  【E·已知失明】尺寸不是字面量、静态判不了: **%d 处**(这不是「没问题」)"
          % out["unresolved"])
    for r in out["unres_rows"]:
        print("      %s" % r)
    print("      ↑ 这些只能靠运行期实拍核(verify_ui_consistency 那一路), 静态侧看不见。")
    for r in out["fwd_rows"]:
        print("      [转发点·不算失明] %s" % r)

    ## ── 命中 ────────────────────────────────────────────────────────
    rows = {}
    for cls, rel, ln, kind, detail, where in out["hits"]:
        k = ledger_key(cls, rel, kind, detail)
        rows.setdefault(k, []).append((cls, where, detail))
    print("")
    print("  【命中】%d 处 / %d 个台账键" % (len(out["hits"]), len(rows)))
    for cls in "ABCDFG":
        got = [(k, v) for k, v in sorted(rows.items()) if v[0][0] == cls]
        if not got:
            continue
        print("   ── %s: %d 键" % (CLS_NAME[cls], len(got)))
        for k, v in got:
            print("      %s  %s" % (v[0][1], v[0][2]))
            if len(v) > 1:
                print("         (同键 %d 处: %s)" % (len(v), ", ".join(x[1] for x in v[1:])))

    if blobs or only:
        print("")
        print("  [单文件/blob 模式] 不对台账, 只打命中(反向验证用)。命中 %d 处"
              % len(out["hits"]))
        return 1 if out["hits"] else 0

    ## ── 台账对账 ────────────────────────────────────────────────────
    ledger = {}
    if os.path.exists(LEDGER):
        try:
            ledger = json.load(io.open(LEDGER, encoding="utf-8"))
        except Exception:
            ledger = {}
    known = ledger.get("known", {})

    if upd:
        io.open(LEDGER, "w", encoding="utf-8", newline=NL).write(json.dumps(
            {"_why": "由 `python tools/nine_downgrade_audit.py --update` 生成, 不要手改。"
                     "`known` = 【会落进 ui_skin.gd 降级/挑错皮分支】的存量, 键 = "
                     "`文件|类|调用|尺寸`(**故意不含行号**: 行号每天都在漂)。只减不增; "
                     "每条都必须在脚本的 WHY 里有一条理由。"
                     "`blind_e` = 尺寸不是字面量、这条判据看不见的条数(已知失明, 只记不判)。",
             "known": {k: len(v) for k, v in sorted(rows.items())},
             "blind_e": out["unresolved"]},
            ensure_ascii=False, indent=1) + NL)
        print("")
        print("  [台账已重写] %s (%d 键 / %d 处 · E 类失明 %d 处)"
              % (LEDGER, len(rows), len(out["hits"]), out["unresolved"]))
        return 0

    bad = []
    for k in sorted(set(list(rows.keys()) + list(known.keys()))):
        got = len(rows.get(k, []))
        cap = int(known.get(k, 0))
        if got > cap:
            cls = (rows[k][0][0] if k in rows else "?")
            bad.append("[FAIL] %s\n"
                       "       %s 处 > 台账 %d 处 —— **新增了一个**。%s\n"
                       "       ⇒ 要么把尺寸/贴图改到不降级(那颗 196×34 的形态钮就是改挂"
                       "边带 4px 的 chip-frame),\n"
                       "         要么在 tools/nine_downgrade_audit.py 的 WHY 里写明**为什么"
                       "这一处必须降级**。\n"
                       "       首处: %s  %s"
                       % (k, got, cap, CLS_NAME.get(cls, cls), rows[k][0][1], rows[k][0][2]))
        elif got < cap:
            bad.append("[FAIL] %s: 现在只剩 %d 处(台账写着 %d) —— 修好了就 `--update` 把"
                       "数字改小, 棘轮只减不增。" % (k, got, cap))
    no_why = [k for k in sorted(rows) if k not in WHY]
    for k in no_why:
        bad.append("[FAIL] %s 没在 WHY 里写理由 —— 不写理由的白名单和放宽判据是一回事。\n"
                   "       首处: %s  %s" % (k, rows[k][0][1], rows[k][0][2]))

    print("")
    if bad:
        for b in bad:
            print(b)
        print("")
        print("  ★这条判据抓的是「**调用方以为自己套了金属框, 实际画出来是网页盒**」那个形状:")
        print("    `nine_if_big` 短边 <%g 就 `return fallback`, 一声不响。" % th["min_frame"])
        print("    实例(已修): 图鉴形态切换钮 196×34 —— 只有双形态龟才画, 而"
              "`verify_ui_consistency`")
        print("    量图鉴时只量列表第一条 ⇒ 那个网页盒从来没被数到过。")
        print("")
        print("  ★如果你刚**改了某个控件的尺寸**(台账键里带尺寸), 会同时看到一条「新增」+ 一条")
        print("    「只剩」—— 那是同一处换了键。确认新尺寸没落进降级分支后跑")
        print("    `python tools/nine_downgrade_audit.py --update` 重记台账; 落进了就先修。")
        print("")
        print("  ★D 类是这几类里**最软的一条**: 尺子 STRETCH_BAR=2.5 取自 ui_skin.gd:103 自己"
              "记的实拍下限(那次是 120×81 = 2.5~3.4 倍)。")
        print("    根因是**素材缺口**(缺一张宽扁签牌): `big` 的 56 那道线就是为了让"
              " frame-rect 的 27×2=54 边带装得进去,")
        print("    于是 30~52 高的宽扁按钮两头落空。新加一颗常规 120×40 的钮也会撞它 ——"
              "那时**写一行 WHY 就行**, 别为了过门禁去改素材或改阈值。")
        print("FAILED: %d 条" % len(bad))
        return 1
    for k in sorted(rows):
        if k in DEBT:
            continue
        print("  [存量·查过确实该这样] %s" % k)
        print("        %s" % WHY[k][:180])
    ## ★DEBT 每跑一次都大声打(即使全绿) —— 白名单会替 bug 站岗, 这一本不许静音。
    debt_here = [k for k in sorted(rows) if k in DEBT]
    if debt_here:
        print("")
        print("  ★★【待修·已确认是 bug, 只是没修】%d 条 —— 这不是白名单, 是欠债:"
              % len(debt_here))
        for k in debt_here:
            print("     ● %s   (%s)" % (k, ", ".join(x[1] for x in rows[k])))
            print("       %s" % WHY[k])
    print("")
    print("ALL OK — 没有新增的「静默降级/挑错皮」调用点"
          "(存量 %d 键 / %d 处, 其中待修 %d 条 · E 类失明 %d 处, 都见上)"
          % (len(rows), len(out["hits"]), len(debt_here), out["unresolved"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
