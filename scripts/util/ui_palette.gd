class_name UIPalette
extends RefCounted

## UIPalette — 语义色的单一事实源 (2026-07-22 建)
##
## 【为什么要有】此前同一个语义色散在【三张互不相干的表】里:
##   scripts/util/skill_text.gd  VAL_HEX        (17 项, 给技能/装备文案)
##   scripts/systems/visual_constants.gd FLOAT_STYLE (给战斗飘字)
##   scripts/scenes/dmg_stats_panel.gd   COL_*     (给伤害统计面板)
## 实测物理红有两个值: 文案 #ff6b6b / 飘字与统计面板 #ff4444。
## 用户 2026-07-22 拍板【全统一成 #ff4444】。
##
## 【谁改谁】
##   · skill_text.VAL_HEX / dmg_stats_panel.COL_* → 直接引用本文件, 不再写字面量
##   · visual_constants.FLOAT_STYLE 【保留字面量】—— 那份文件的契约是"与 Phaser PoC 1:1,
##     十六进制 100% 同", 改成引用就破坏了它的可核对性。它用的本来就是 #ff4444, 无需改动;
##     门禁 verify_palette 会断言它与本表一致, 将来谁改漂了当场红。
##
## 【加新色的规矩】只往这里加。往消费方直接写 #xxxxxx 会被门禁扫出来。

# ── 三色伤害 ──
const PHYS := "#ff4444"          # 物理 (用户 2026-07-22: 文案的 #ff6b6b 并入此值)
const MAGIC := "#4dabf7"         # 魔法
const TRUE_DMG := "#ffffff"      # 真实
const PIERCE := "#ffffff"        # 穿透

# ── 增益/防护 ──
const HEAL := "#06d6a0"          # 治疗
const BUFF := "#7dffb3"          # 增益
const DEF := "#ffd93d"           # 防御/护甲(黄)

## 护盾有【两个语义】, 不是冲突, 别合并:
##   SHIELD_VALUE = "护盾量"(统计面板里的蓝条)
##   SHIELD_TEXT  = 文案里提到"护盾"两字的浅色
##   飘字里另有 shield-dmg 灰字 = "打在盾上的伤害", 又是第三个语义(留在 FLOAT_STYLE 里)
const SHIELD_VALUE := "#58d3ff"
const SHIELD_TEXT := "#e0e0e0"


# ── 阵营色 ──
## ★与伤害色是【两个语义】, 别因为色值撞了就合并:
##   SIDE_RIGHT 恰好等于文案旧物理红 #ff6b6b, 但它表示的是"右方阵营", 不是"物理伤害"。
##   2026-07-22 合并色表时, 门禁把它当成"残留旧色值"报了红 —— 正确解法是把阵营色也收进来,
##   而不是放宽那条检查。
const SIDE_LEFT := "#06d6a0"
const SIDE_RIGHT := "#ff6b6b"


# ── 战斗信息面板的字号层级(2026-08-17) ──────────────────────────────────
## ★一档 = 一种角色。实测面板曾有 **6 档**(21/14/12/11/10/9), 而 11 和 12、9 和 10
##   的差别小到看不出 —— 多出来的两档不传达任何信息, 只是让"这行比那行重要"失效。
##   并成 4 档: 标题 / 正文 / 次要 / 角标。`verify_info_panel_fits` 焊死"不超过 5 档"。
##
## ★★这四个数是【唯一出处】。由来: `verify_eq_readouts` ⑦ 量"读数会不会撑爆 88px 的槽",
##   它的探针**自己写死 font_size 11**, 而真实读数是 **9** —— 判据和被判对象两个来源,
##   量了半天量的不是同一个东西。(今晚在充能条分母上刚栽过完全同一个形状。)
##   ⇒ 产品侧和门禁侧都从这里取, 改一个数两边一起动。
const F_TITLE := 21    # 龟名 —— 面板里唯一的标题
const F_BODY := 14     # 属性行 / 更多属性 / 按钮 —— 正文
const F_SUB := 12      # 技能名 / 状态签 / 条上数字 / 资源结论 / 龟能消耗 —— 次要信息
const F_MICRO := 10    # ★星级 / 被动·普攻·技能 角色标 / 槽底局内读数 —— 角标级


## "#rrggbb" → Color; alpha 由调用方给(统计面板的色块要半透明)
static func c(hex: String, alpha: float = 1.0) -> Color:
	var col := Color(hex)
	col.a = alpha
	return col
