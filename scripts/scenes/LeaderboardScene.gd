extends Control

const TopBar = preload("res://scripts/util/top_bar.gd")
var _top_bar = null

## LeaderboardScene — V2 排行榜 (阶段5 MVP, 设计§五/§十三).
## ★★A8(2026-09-19) 排序键换成**字典序「胜场 → 余命 → 横扫」**(原来只按击杀龟蛋数降序)。
##   文案与表头一起改 —— 判据/文案/代码三者必须同时改, 否则榜上排的和标题写的不是一回事。
## MVP: 本地 ghost 池各阵容的 season_wins/hearts/season_sweeps + 自己, 排序展示. 真后端复算防作弊=上线版.
##
## ═══ 2026-08-19 实拍复看(1560×720 真渲染截图)修掉的四件事 ═══
## ① 整屏还是「深色圆角矩形 + 2px 细边」—— 背包/图鉴/选龟早就换成金属九宫格了, 只剩这屏没跟上。
## ② **榜上找不到自己**: `Backend.leaderboard()` 把自己混进去按蛋数降序切前 30 条,
##    而本屏只画得下 13 行 —— 蛋数并列 0 的时候自己排在哪儿全看排序稳定性, 实拍那张
##    13 行里**一个「◀ 你」都没有**。排行榜看不到自己 = 这屏白开。⇒ 自己那行【钉住】。
## ③ 最后一行**压在金属边带上**: 原来 `y > 540` 才 break, 末行标签 532+28=560 = 面板高度,
##    正好压满下边框(金属框实测边带 13px, 比原来的 2px 细边更吃亏)。⇒ 行数按内容区算出来。
## ④ 返回键 120×44 = **24pt**, 低于 44pt 触控下限(视口 720 ↔ 390pt ⇒ 44pt = 81px);
##    而且是 Godot 默认皮。⇒ UISkin.button + 81 高。
##
## ═══ 2026-09-28 从「后台管理表格」改成「游戏排行榜」═══
## 用户:「图鉴, 排行榜什么我一点也看不出来游戏的味道, 全是 ai 味和网页味, 文字语言也是」。
## 实拍那张上整屏就是**一条金色长条 + 一行字**。逐条对着改(详见下面 RANK_X 一段):
## ① 表头行「排名 | 玩家 | 胜·余命·横扫」拆掉, 标题改「🏆 本周排行」(那一步先做的)。
## ② 名次从纯文本「#1」改成**金/银/铜的九宫格签牌**(颜色 + 边框, 不是 emoji 堆砌);
##    第 4 名起只剩一个暗号码 —— 领奖台和看台一眼分得开。
## ③ 自己那行 = 整行金签牌底 + 名字后面一枚「你」金签, 不再是名字里拼一串 "  ◀ 你"。
## ④ 成绩从拼接串「0胜 · ♥8 · 0横扫」改成**三格「图标 + 数字」**, 该量是 0 就把图标压暗。
## ⑤ **空席**: 全新档的榜本来就只有自己一行(产品行为, 不是 bug), 而只画一行看着像坏掉的界面
##    ⇒ 剩下的名次照画, 名次/牌位在、名字与成绩位是破折号。**不补零**(补零 = 造假对手)。
## ═══ 2026-10-19 全部名次(用户「开放所有排名」, 方案书 docs/plans/20261019-排行榜开放全部名次.md) ═══
## 原来只画 11 行(前 9 名 + ⋯ + 我)、服务端只回前 30 名。现在: 滚动列表一路翻到最后一名(按页取, 只建露出来的行),
## 「我」钉在列表下沿, 顶栏「我的位置」把列表滚到我那一段。门禁 tests/verify_leaderboard_all_ranks.gd。
##
## 判据同一轮搬家: `tests/verify_leaderboard_header.gd` 原来量表头, 表头没了之后那两条
## 分母当场红 —— 产品对了判据还在量旧样子。已改成**在数据行上**量同一件事。
##
## ═══ 2026-10-23 重做: 游戏质感(用户「排行榜需要大型重做」, 多选题只选了「看着像网页，没有游戏味」) ═══
## 方案书 docs/plans/20261023-排行榜重做.md(§5 已拍板: 三列不动 / 不加页签 / 不加个人卡 / 不做历史榜)。
## 对着改前实拍(docs/plans/img-20261023-排行榜重做/)逐条改:
##   ① 760 宽的一条居中窄栏, 宽屏两边各空 400 —— 这就是网页「定宽正文栏」的长相。⇒ 面板吃满设计框(1180 宽)。
##   ② 每行 = 一条细边 + 一行 18 号字, 读起来是表格。⇒ 每个人一张**行卡**(新画的像素九宫格: 粗描边 + 斜面 + 四角铆钉),
##      卡与卡之间留缝 —— 照荒野乱斗 / 部落冲突的榜: 一行 = 一个游戏里的条目, 不是表格里的一格。
##   ③ 没有头像。⇒ 名字前一枚头像 = 这个人的第一只统领(服务端每行下发 `lead`; 本机那一路取快照 leaders[0])。
##      没有 `lead`(老服务端 / 老快照) ⇒ 槽里写名字首字, 不编一只龟(与对阵图没头像数据时同一个做法)。
##   ④ 成绩数字和名字一样大。⇒ 三个成绩 30 号像素字 + 描边, 摆在行卡右段一块压暗的「成绩槽」里, 右对齐到列名。
##   ⑤ 人少时整屏「—」占位。⇒ 列表只画真实的人, 一行占位都不画(全新档的榜就是只有自己一张卡)。
##   ⑥ 前三名 = 金 / 银 / 铜的八角奖牌(新画) + 整张行卡染同色; 自己 = 整张行卡染亮橙金(全屏最亮的一张) + 「你」签。
## 三列的字(剩余生命 / 胜场 / 总场次)、排序、全部名次、钉住我、我的位置、本机记录、举报拉黑 —— 一样没动。

const W := 1280.0
## ★面板吃满设计框(两边各留 50)。原来 760 宽居中 ⇒ 19.5:9 的手机上内容只占屏宽一半。
const PANEL_W := 1180.0
## 内边距要 > panel-frame 贴图**实测边带 13px**(不是九宫格配置的 20 —— 那是"从哪切开",
## 不是"画了多宽的边"; verify_ui_consistency 的 `_band_of` 就是这么量的)。
const PAD := 22.0
## 一行的步距 = 行卡高 + 卡缝。行卡 52 高: 头像 40 + 上下各 6(行卡贴图边带实测 5px, 头像不压边)。
const ROW_H := 58.0
const CARD_GAP := 6.0
const CARD_H := ROW_H - CARD_GAP
## 行卡左右沿(相对面板): 比内容区各宽 6, 仍在面板金属边带(13px)以内。
const CARD_X := PAD - 6.0
const CARD_W := PANEL_W - CARD_X * 2.0
## 表头一行(规模数 / 本地记录 / 三个列名)。
const HEAD_Y := PAD - 4.0
const HEAD_H := 28.0
## 行卡与新画的两张素材(都是中灰, 靠 modulate 染色: 普通 / 金 / 银 / 铜 / 自己)。
const ROW_TEX := "leaderboard/lb-row.png"
const ROW_TEX_MARGIN := 10
const MEDAL_TEX := "leaderboard/lb-medal.png"
## 剩余生命的心形(2026-10-24 用户「画吧」), 见 `_hearts_cell`。
const HEART_TEX := "res://assets/sprites/leaderboard/lb-heart.png"
const HEART_EMPTY_TEX := "res://assets/sprites/leaderboard/lb-heart-empty.png"
const HEART_W := 18.0
const HEART_H := 16.0
const HEART_GAP := 4.0

## ═══ 全部名次 (2026-10-19 · 用户「排行榜你学一下其他游戏的，开放所有排名」) ═══
## 参考(docs/plans/ref/20261019-排行榜参考/, 逐张看过): 荒野乱斗 / 使命召唤手游 / Flash Party 三款同一个结构 ——
##   ① 名次列表**整条可滚动**, 一屏只露一段, 往下拖能一直拖到最后一名;
##   ② **自己那一行钉在列表下沿**, 与列表隔开、整行高亮, 滚到哪儿它都在; 没上榜时名次位写「—」(CoD「NOT ON LEADERBOARD」);
##   ③ Golf Clash: 列表直接滚到自己所在那一段, 自己那行在列表里同样高亮。
## ⇒ 列表 = ScrollContainer, 一屏 VIS_ROWS 行; 下沿钉一行「我」; 顶栏一枚「我的位置」把列表滚到我附近。
## ★只建**看得见的那几行**(按滚动位置现建现拆): 全部名次可能上千行, 一次全建出来是上千个节点。
## ★服务端那一路按页取(`SupabaseNet.fetch_week_leaderboard_page_async`, 一页 WEEK_LB_PAGE 名), 滚到哪页取哪页。
## ★2026-10-23 行卡加高(40 → 58, 放得下头像与大号数字) ⇒ 一屏 10 行 → 8 行, 面板高度仍在设计框里。
const VIS_ROWS := 8
## 列表与钉住那一行之间的空隙(中间一条分隔线)。
const PIN_GAP := 14.0
## 列表(滚动区)的上沿与高度。
const LIST_Y := HEAD_Y + HEAD_H + 10.0
const LIST_H := float(VIS_ROWS) * ROW_H
## 钉住那一行的上沿。
const PIN_Y := LIST_Y + LIST_H + PIN_GAP
## ★面板高度是【按内容反算】的: 表头 + 8 行 + 空隙 + 钉住一张行卡 + 下内边距。
const PANEL_H := PIN_Y + CARD_H + PAD - 4.0
## 顶栏那枚「我的位置」(名词, 不口语化)。
const JUMP_TEXT := "我的位置"
const PANEL_X := (W - PANEL_W) / 2.0
const PANEL_Y := 92.0
const Backend = preload("res://scripts/net/backend.gd")
const MatchCard := preload("res://scripts/scenes/record/match_card.gd")

## ═══ 一行的版面 (2026-09-28, 用户「一点也看不出来游戏的味道, 全是 ai 味和网页味」) ═══
##
## 改之前一行是 **三个纯文字格**: 「#7」「名字  ◀ 你」「0胜 · ♥8 · 0横扫」。
## 那是**后台管理表格**的三件套: 纯文本序号 / 纯文本标记 / 把三个量拼成一个字符串。
## 游戏的榜靠三样东西说话, 下面每一条都对着其中一样:
##   ① 名次**牌位**: 前三名是金/银/铜的九宫格金属签牌(颜色 + 边框), 第 4 名起只剩一个暗号码
##      ⇒ "谁在领奖台上"不用读数字就看得出。(不堆 emoji —— 那只是把网页味换成表情味。)
##   ② 「你」是一枚**金签牌**贴在自己名字后面 + 整行金色签牌底, 不是文字里的 "◀ 你"。
##   ③ 成绩三个量各自**一个图标一个数字**, 不再拼成一条串; 该量是 0 就把图标压暗
##      ⇒ "还没有"是看出来的。
##
## 全部横坐标按行卡 [CARD_X, CARD_X+CARD_W] = [16, 1164] **反算**(2026-10-23 重排), 不是拍脑袋:
##   名次 38..74 │ 头像 88..128 │ 名字 142..692 │ 成绩槽 696..1154(三列右沿 806 / 974 / 1142)
const RANK_X := PAD + 16.0
## ★名次格 = 奖牌 36×36(原图 ×1, 不拉伸像素画)。**两边都 < 40** 是有讲究的 —— `verify_ui_consistency`
##   把"住在 <40px 小盒子里的字"当角标放过(那条判据的原话见它的 `_badge`)。牌子再大一格,
##   牌里的名次数字就会被当成"文字压边带"报上来, 而实拍它稳稳在牌中间。
##   第 4 名起的号码也居中在这 36 宽里(三位数刚好; 四位数两边各溢出几像素, 落在行卡空白里)。
const RANK_W := 36.0
const RANK_H := 36.0
## 头像(第一只统领): 40 方, 竖直居中在行卡里。
const AV_X := RANK_X + RANK_W + 14.0
const AV_PX := 40.0
const NAME_X := AV_X + AV_PX + 14.0
const NAME_FS := 22
## 「你」签牌: 36×26, 同样 < 40(理由同上)。自己那行的名字列要先给它让出 48px,
## 否则长昵称的字块会和签牌叠在一起(全屏"两段文字压在一起"那条判据是**全局清零**的)。
const YOU_W := 36.0
const YOU_H := 26.0
const YOU_GAP := 12.0
## 玩家 ID(`#XXXXXX`)那一小格。★只在**重名**的行上出现(2026-10-04 · 名字允许重复,
##   同名的两个人靠它分开); 不重名的行一个字都不多。字小一号、走名次那个灰。
const TAG_W := 96.0
const TAG_FS := 15
## 这一榜里重名的名字(`_P2.names_needing_tag` 算的) —— `_draw_row` 读它决定要不要摆 ID。
var _dup_names: Dictionary = {}
## 成绩三列: 每列宽 140, 列距 28 ⇒ 列右沿 806 / 974 / 1142(行卡内沿再留 12)。数字与列名都**右对齐到列右沿**。
const COL_W := 140.0
const STAT_CELL := 168.0
const STAT_X0 := CARD_X + CARD_W - 22.0 - COL_W - 2.0 * STAT_CELL
## 成绩槽(行卡右段压暗的那一块)原来从第一列左沿往右 30 起(那时第一列是一个右对齐的数字), 到行卡内沿止。
## 名字列止于成绩槽左沿。
## ★2026-10-24 剩余生命画成一排心(比一个数字宽得多) ⇒ 槽的左沿改成「整排心左边再留 8」, 心整排落在槽里
##   (实拍: 原来的 +30 让第一颗心一半露在槽外)。名字列随之窄 26px。
const HEARTS_ROW_W := HEART_W * _P2C.HEARTS_MAX + HEART_GAP * (_P2C.HEARTS_MAX - 1)
const SLOT_X := STAT_X0 + COL_W - HEARTS_ROW_W - 8.0
const NAME_W := SLOT_X - 4.0 - NAME_X
## 成绩数字: 30 号像素字 + 4px 暗描边(与周六赛况板的战绩数字同一种写法)。
const STAT_FS := 30
const STAT_OUTLINE := 4
## 表头左段「本周共 N 人上榜」的宽(17 号字 9 个字位 ≈ 150, 留余量)。
const CAP_W := 180.0

## ═══ 三个成绩列 (2026-10-06 · 用户「积分赛写上名字，剩余生命，胜场，总场次啊 ，都给我做」) ═══
## 列名就是用户那句话里的词, 一个字不改; 照 使命召唤手游 / 英雄联盟手游 排行榜:
##   **表头写纯文字列名, 行里只放数字**(格里不画图标 —— 用户「排行榜里的奖杯是？」)。
##   ★例外(2026-10-24 用户「画吧」): 「剩余生命」一列画成一排心形(`_hearts_cell`), 另外两列仍是数字。
## ★顺序 = 用户说的顺序: 剩余生命 | 胜场 | 总场次。
## ★排序**不变**: 胜场 → 剩余生命 → 横扫。横扫不上屏, 但同胜同命时仍由它定先后(服务端 SQL 与本机 cmp 同一套)。
## ★`battles` < 0 = 这一行的来源没带总场次(v1 服务端 / 老快照) ⇒ 画「—」, 不编 0。
const COL_HEADS := ["剩余生命", "胜场", "总场次"]
const COL_KEYS := ["hearts", "wins", "battles"]

## ═══ 一周四种榜 (2026-10-06 · 同一句「都给我做」) ═══
##   周一(休赛)   上周终榜      —— 请求**上周**的周锚点; 名字旁挂 冠军/亚军/四强/进决赛日
##   周二~周五    本周排行      —— 实时积分赛榜
##   周六(闯关)   积分赛终榜    —— 积分赛已收盘、榜冻结; 胜场 ≥ PROMOTE_WINS 的挂「已晋级」; 顶栏右侧「全场赛况」
##   周日(决赛)   积分赛终榜    —— 同上; 顶栏右侧「查看对阵图」; 某一组决赛打完(closed)后组里的人换挂 冠军/亚军/四强
## ★「冻结」不靠客户端拦: 只有积分赛那一支会写 `ghosts`(RealtimeBattle3DScene 结算里 upload_ghost
##   只在积分赛分支), 周五 23:00 收盘之后本周的 `ghosts` 就不再长了。
## ★头衔从哪来: 服务端 `standings.title` 至今**没人写**(恒空, v2 SQL 照样下发它, 将来写入端落地即生效);
##   冠军/亚军/四强/进决赛日 = 客户端从 `finals_week_view(那一周)` 现算 —— 座次推导只在 `bracket.gd` 一份,
##   与主菜单发头衔(`BracketMapScene.record_progress_from` → `Bracket.my_progress`)同一套。
## ★日子只从 `phase2_config.now_utc()` 读**一次**(时间穿越 / 门禁钉钟都走它), 不读系统钟。
const DAY_TITLE := {
	"rest": "上周终榜",
	"ranked": "本周排行",
	"gauntlet": "积分赛终榜",
	"finals": "积分赛终榜",
}
const MARK_PROMOTED := "已晋级"
const MARK_W := 96.0
const MARK_FS := 16
const COL_TITLE := "#ffd97a"
const COL_PROMOTED := "#8fd99c"
const WEEK_SEC := 7 * 86400
## 顶栏右侧那个入口: 与主菜单赛程卡上那扇门**同一个目标场景**(常量取自 MainMenuScene, 不另抄)。
const BRACKET_LINE := "查看对阵图"
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _BR := preload("res://scripts/gamedata/bracket.gd")
const _MM := preload("res://scripts/scenes/MainMenuScene.gd")
## 举报 / 拉黑(2026-10-20 · App Store 审核指南 1.2): 点别人的名字 ⇒ 玩家菜单; 被拉黑的人显示默认昵称。
const _PM := preload("res://scripts/scenes/social/player_menu.gd")
const _BL := preload("res://scripts/util/blocklist.gd")
const _RPT := preload("res://scripts/net/report_net.gd")

## 金/银/铜奖牌。`modulate_color` 是**乘**在 lb-medal.png 上的(中灰八角牌: 实测牌面 (196,196,200)、
## 外圈亮边 (250,250,250) / 暗边 (120,120,124)) ⇒ 乘出来就是金 / 银 / 铜三块牌, 不是 emoji。
const MEDAL_PLATE := [
	Color(1.16, 0.88, 0.30),      # 金
	Color(0.88, 0.94, 1.06),      # 银
	Color(1.04, 0.64, 0.36),      # 铜
]
## 前三名整张行卡的染色(行卡贴图底色中灰 (118,122,134); 比自己那张暗, 只当"领奖台的台阶")。
const MEDAL_BAND := [
	Color(1.02, 0.78, 0.26),
	Color(0.56, 0.62, 0.76),
	Color(0.92, 0.56, 0.32),
]
## 奖牌里的名次数字: 白字 + 牌色的深描边(亮牌面上白字要靠描边才读得出)。
const MEDAL_NUM_OUTLINE := ["#5a3a06", "#2e3644", "#4e260e"]
## 面板(装行卡的槽)的染色: 比原来(0.74/0.94/1.14)压暗一档 —— 槽要比卡暗, 卡才浮得起来。
const PANEL_TINT := Color(0.58, 0.74, 0.96, 1.0)
## 普通行卡: 深蓝石板色, 与面板同一个色系(面板芯 (40,41,66) × 面板染色)。
const ROW_BAND := Color(0.34, 0.40, 0.58)
## 自己那张: 全屏最亮的一张(亮橙金, 照荒野乱斗自己那行的橙底; 和 MEDAL_BAND 三条都不一样 —— 门禁就是这么判"你看得出来"的)。
const SELF_BAND := Color(1.42, 0.94, 0.36)
const SELF_TAG := Color(1.34, 1.14, 0.56)
const COL_SELF := "#fff3d0"
const COL_ROW := "#eef4fa"
const COL_DIM := "#6f8092"
const COL_RANK := "#9fb2c4"
## 成绩槽: 行卡右段压暗的那一块(上沿一道暗线 + 下沿一道亮线 = 往里凹的像素斜面)。
const SLOT_FILL := Color(0.0, 0.0, 0.0, 0.26)
const SLOT_TOP := Color(0.0, 0.0, 0.0, 0.34)
const SLOT_LIP := Color(1.0, 1.0, 1.0, 0.08)
## 字的暗描边(行卡染亮橙金时白字要靠它压住)。
const COL_INK := Color(0.04, 0.05, 0.08, 0.85)

## ═══ 底部那一行提示 (2026-09-28: 「连不上」不许说成「你打得少」) ═══
##
## ★★★原来只有一句: 「（榜上暂时只有你 —— 打完一场, 对手就会上来）」。
##   探针 `tests/_probe_lb_reach.gd` 实测: 池子 396 条 / 榜上 rows = **1**,
##   而池子里唯一能带来别人的两条路(`apply_pull_response` / `ingest_remote`)
##   **纯网络**。⇒ **断网时打一万场也不会有对手上来**, 那句话把网络失败
##   归因到了玩家的场次上。这是说谎级, 不是措辞问题。
##
## ★四句各对一档(档的定义与理由见 `Backend.REACH_*`), **互斥**:
##   · OK      问到过 ⇒ 原话一个字不改, 这时它是真的
##   · FAIL    问过没问到 ⇒ 照 `BracketMapScene.gd:523` 的样式说「连不上服务器 · …」
##   · UNKNOWN 还没问 ⇒ 不许说"连不上"(那是把没发生的故障说成发生了), 只说还没读到
##   · OFF     没配后端 ⇒ **一句承诺都不给, 也不挂"离线"角标**
##     (`SettingsScene.gd:103` / `remote_pool.gd:182`: 常驻的"离线"标记是反的 ——
##      它等于告诉玩家"你是残缺状态, 去修"。所以这一档只陈述事实, 不解释原因。)
const HINT_ONLY_YOU_OK := "（暂无其他玩家 · 对战后更新）"
const HINT_ONLY_YOU_FAIL := "（无法连接服务器）"
const HINT_ONLY_YOU_UNKNOWN := "（暂无对手数据）"
const HINT_ONLY_YOU_OFF := "（暂无其他玩家）"

## ═══ 数据从哪来 (2026-10-06 · 60 人实操严重项 A2) ═══
##
## ★★原来**只有**本机那一路: `Backend.leaderboard(本机快照池)`。新玩家只拉过场次 N / N+1 的快照,
##   榜上每个人都冻在「1 胜 · 6 命」—— 实操截图前 9 行全是 1 胜, 而那几个号几小时前已经打到 9-6 / 10-6。
##   那是「我碰巧拉到过的那一份」, 不是排行榜。
## ⇒ 先问服务端 `week_leaderboard`(`SupabaseNet.fetch_week_leaderboard_async`)。
##   只有**问不到**(没配后端 / 断网 / 超时 / 服务端还没部署)才退回本机那一路,
##   而且退回时屏上**明写「本机记录」** —— 不许把过期的本机数据当成实时榜摆出来。
const SRC_SERVER := "server"
const SRC_LOCAL := "local"
const SRC_LOADING := "loading"
const FALLBACK_MARK := "本地记录 · 非实时排名"
const LOADING_TEXT := "正在读取本周排行…"
const SB := preload("res://scripts/net/supabase.gd")
## 当前画的是哪一路 / 哪几行(门禁读它当分母; 屏幕上的字才是判据)。
var source: String = ""
var shown_rows: Array = []
## 这一屏开着时是周几的哪一档(`phase2_config.PHASE_*`), 以及榜对应的那一周的周锚点。
var day_phase: String = ""
var board_week_ts: int = 0
## 顶栏右侧那个入口(周六/周日才有), 门禁读它。
var entry_btn: Button = null
## 顶栏全部入口(周一两枚: 周六赛况 / 周日对阵图), 门禁读它。
var entry_btns: Array = []
## account_id → {"id": 头衔 id, "closed": 那一组打完没有}(决赛日那一周的 finals_week_view 现算)。
var _fin_titles: Dictionary = {}
var _last_total: int = -1
## 每次重画都整块换掉的那一层(表面板 + 分隔线 + 顶栏不动)。
var _panel: Panel = null
var _body: Control = null
## ── 全部名次那一套(门禁读这些当分母; 屏幕上的字才是判据) ──
## 顶栏「我的位置」。
var jump_btn: Button = null
## 滚动区 / 滚动区里那条撑高的长条 / 钉住「我」那一行。
var _scroll: ScrollContainer = null
var _list: Control = null
var _pin: Control = null
## 列表一共多少行(= 能翻到的名次数)。服务端那一路 = 全榜人数; 退回旧函数时 = 拿到的行数。
var list_len: int = 0
## 名次 → 那一行的数据(服务端按页陆续补进来; 本机那一路一次全有)。
var _by_rank: Dictionary = {}
## 「我」那一行(名次 < 1 = 本周榜上没有我)。
var me_row: Dictionary = {}
## 正在取 / 取失败的页(页号 = (名次-1) / WEEK_LB_PAGE)。取失败的不自动重试(断网时不刷请求)。
var _pending: Dictionary = {}
var _failed: Dictionary = {}
## 新函数没部署(404) ⇒ 退回旧函数, 只能翻到它给的那些名次, 不再按页取。
var _legacy: bool = false
## 现在建着的行: 名次 → 节点。
var _row_nodes: Dictionary = {}
## 本屏发出去的页请求(offset 列表, 门禁分母)。
var page_offsets: Array = []

func _ready() -> void:
	_bg()

	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   规则来自 599 张/146 个触屏游戏枢纽页的逐张实测, 见 top_bar.gd 头注。
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	## ★「现在」只读这一次(全局时间缝: 门禁钉钟 / 开发包穿越 / 服务器偏移都在它里面)。
	var now: int = int(_P2C.now_utc())
	day_phase = _P2C.phase_at_utc(now)
	board_week_ts = board_week(now)
	## ★「我的位置」排第一枚(最左), 周六/周日的入口排在它右边(那颗仍是最后一枚, 见下面 entry_btn)。
	var acts: Array = [[JUMP_TEXT, jump_to_me]]
	var ents := day_entries(day_phase)
	for ent in ents:
		acts.append([str(ent["text"]), _open_gauntlet_board if str(ent["scene"]) == _MM.GAUNTLET_BOARD_SCENE
			else _open_bracket_map])
	_top_bar = TopBar.new(self, {
		## ★★2026-09-27 标题里**不写排序规则**。「排行榜 · 胜场 → 余命 → 横扫」是**规格书**
		##   的写法(把内部比较器写在标题上), 用户 2026-09-27:「我一点也看不出来游戏的味道」。
		##   排序规则该由榜自己的样子表达(名次牌 + 数字), 不是标题里念一遍。
		"title": board_title(day_phase),
		"palette": TopBar.DEEP,
		"width": W,
		"safe_left": _sm.x,
		"safe_right": _sm.z,
		"on_back": func(): SceneNav.go(get_tree(), "res://scenes/MainMenu.tscn"),
		"actions": acts,
	})
	if _top_bar.action_btns.size() > 0:
		jump_btn = _top_bar.action_btns[0] as Button
		jump_btn.name = "LbJumpMe"
	## 入口按钮 = 「我的位置」之后那几枚, 顺序同 day_entries。entry_btn = 最后一枚(周六/周日只有一枚)。
	entry_btns.clear()
	for ei in range(ents.size()):
		if ei + 1 < _top_bar.action_btns.size():
			var eb := _top_bar.action_btns[ei + 1] as Button
			eb.name = "LbDayEntry" if ei == ents.size() - 1 else "LbDayEntry%d" % ei
			entry_btns.append(eb)
	if not entry_btns.is_empty():
		entry_btn = entry_btns[entry_btns.size() - 1]

	# 表面板 —— 金属九宫格(和背包/图鉴/战绩同一张 panel-frame)。冷蓝调走 modulate(`PANEL_TINT`),
	# ★ modulate 别超 1.3: 过了会把框芯冲亮、金属细节糊平(实拍确认过)。
	var panel := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.12, 0.18, 0.9); psb.border_color = Color("#2e4a5e")
	psb.set_border_width_all(2); psb.set_corner_radius_all(12)
	var ptex := UISkin.nine("panel-frame.png", 20, psb)
	var well: ColorRect = null
	if ptex is StyleBoxTexture:
		(ptex as StyleBoxTexture).modulate_color = PANEL_TINT
		## ★芯子不画, 改铺一块平色(2026-10-23 实拍): panel-frame 原图芯子里有一粒暗斑 + 几块做旧亮斑,
		##   原来 760 宽拉 2 倍还看不太出; 面板拉到 1180 宽之后那粒斑被拉成一团污渍, 人少时就摆在空列表正中间。
		##   边框(九宫格的四边四角)照旧, 只换芯子 —— 颜色 = 原图芯子 (40,41,66) × 面板染色。
		(ptex as StyleBoxTexture).draw_center = false
		well = ColorRect.new()
		well.name = "LbWell"
		well.color = Color(40.0 / 255.0 * PANEL_TINT.r, 41.0 / 255.0 * PANEL_TINT.g, 66.0 / 255.0 * PANEL_TINT.b, 1.0)
		well.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well.position = Vector2(20.0, 20.0)
		well.size = Vector2(PANEL_W - 40.0, PANEL_H - 40.0)
	panel.add_theme_stylebox_override("panel", ptex)
	panel.position = Vector2(PANEL_X, PANEL_Y); panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(panel)
	if well != null:
		panel.add_child(well)
	_panel = panel

	# 表头 + 一条分隔线(原来表头和第一行只隔 38px 且没有任何分界, 整块读起来是一堵字墙)
	## ★表头说的量必须就是行里画的那三个量 —— A8 改排序那轮改了标题、改了行文案、
	##   改了比较器, **漏了这一行**, 于是表头写着「击杀蛋数」而数据是「x胜 · ♥y · z横扫」。
	##   实拍巡检(2026-09-19)当场看见的, 而排序那条门禁一条都没红 —— 它只测函数不测 UI。
	##   已补 `tests/verify_leaderboard_header.gd`: 表头↔行文案逐项对账。
	## ★★去掉**表头行**。「排名 | 玩家 | 胜·余命·横扫」是数据表/后台界面的标志 ——
	##   游戏的榜靠名次牌与数字本身说话, 不靠一行字段名。
	##   (数字的含义已经写在每一行里: 图标 + 数字, 不会看不懂。)
	var sep := ColorRect.new()
	sep.color = Color(0.35, 0.55, 0.70, 0.45)
	sep.position = Vector2(PAD, LIST_Y - 6.0); sep.size = Vector2(PANEL_W - PAD * 2.0, 2)
	panel.add_child(sep)

	## ★先问服务端; 连节点都没建(没配后端)⇒ 当场画本机那一路(带「本机记录」)。
	if not _ask_server():
		_render(_local_rows(), SRC_LOCAL, -1)
	# ★UI 双端适配(用户2026-08-01「有些画面都没有居中」): 把内容装进 1280×720 设计框并居中于真实视口。
	#   本屏原先直接按设计坐标画在视口(0,0) → 21:9 上内容整体坐在左边 200px(审计器实测)。
	#   ★必须放在 _ready 最后 —— UIFrame 收编的是【已经建出来的】子节点。
	#   (异步晚建的节点由 UIFrame._process 的孤儿收编兜住; 回包后重画的那一层挂在已收编的面板下。)
	UIFrame.attach(self)


## 榜对应哪一周(周锚点)。周一(休赛)看**上周**, 其余六天看本周。
## ★与上传那一侧同一个口径: 上传用 `GameState.week_anchor_ts`, 它由 `ensure_season` 从同一个
##   `week_anchor_utc(now_utc())` 滚出来; 这里直接从「现在」算, 不依赖本屏打开前有没有滚过轮。
static func board_week(now: int) -> int:
	var a: int = _P2C.week_anchor_utc(now)
	return a - WEEK_SEC if _P2C.phase_at_utc(now) == _P2C.PHASE_REST else a


## 顶栏标题。不认识的阶段按积分赛日。
static func board_title(phase: String) -> String:
	return str(DAY_TITLE.get(phase, DAY_TITLE[_P2C.PHASE_RANKED]))


## 顶栏右侧入口: 周六 → 全场赛况(GauntletBoard) / 周日 → 查看对阵图(BracketMap) / 其余 → 无。
## ★目标场景与文字都取主菜单那两扇门的常量 —— 同一个入口不许有两份地址。
static func day_entry(phase: String) -> Dictionary:
	var es := day_entries(phase)
	return es[0] if not es.is_empty() else {}


## 顶栏右侧全部入口(从左到右)。
## ★★2026-10-19 用户「周六 / 周日赛况保留到周一」: 周一(休赛)两扇门都给 —— 「周六赛况」→ GauntletBoard、
##   「周日对阵图」→ BracketMap(看的是上周那一场; 与主菜单周一那两扇门同名同目标)。
##   ⚠ 主线已有 `Phase2Config.weekend_view_week(now_utc)`(周一 = 上周周号), 本工作区基于更早的提交没有它,
##   这里按「周一 = PHASE_REST」判; 合并时由主会话对接到 weekend_view_week。
const MON_GAUNTLET_LINE := "周六赛况"
const MON_BRACKET_LINE := "周日对阵图"

static func day_entries(phase: String) -> Array:
	if phase == _P2C.PHASE_GAUNTLET:
		return [{"text": _MM.GAUNTLET_BOARD_LINE, "scene": _MM.GAUNTLET_BOARD_SCENE}]
	if phase == _P2C.PHASE_FINALS:
		return [{"text": BRACKET_LINE, "scene": _MM.BRACKET_SCENE}]
	if phase == _P2C.PHASE_REST:
		return [{"text": MON_GAUNTLET_LINE, "scene": _MM.GAUNTLET_BOARD_SCENE},
			{"text": MON_BRACKET_LINE, "scene": _MM.BRACKET_SCENE}]
	return []


## 具名方法(门禁量 `pressed.get_connections()` 能看到方法名)。走主菜单同一条路径规则 `res://scenes/<X>.tscn`。
func _open_gauntlet_board() -> void:
	_go(_MM.GAUNTLET_BOARD_SCENE)


func _open_bracket_map() -> void:
	_go(_MM.BRACKET_SCENE)


func _go(scene: String) -> void:
	var path := "res://scenes/%s.tscn" % scene
	if not ResourceLoader.exists(path):
		push_error("[LB] 目标场景不存在: " + path)
		return
	SceneNav.go(get_tree(), path)


## 名字旁边挂什么(纯函数, 四天全可穷举)。返回显示文字, "" = 不挂。
##   `srv_title` = 服务端 standings.title(现在恒空; 有就以它为准)
##   `fin` = 这个人在那一周决赛里的 {"id": TITLE_*, "closed": 那一组打完没有}, 不在决赛里 = {}
static func row_mark(phase: String, srv_title: String, fin: Dictionary) -> String:
	if srv_title != "":
		return str(_P2C.TITLE_LABEL.get(srv_title, srv_title))
	var fid := str(fin.get("id", ""))
	match phase:
		_P2C.PHASE_REST:
			return str(_P2C.TITLE_LABEL.get(fid, "")) if fid != "" else ""
		_P2C.PHASE_FINALS:
			if bool(fin.get("closed", false)) and fid in [_P2C.TITLE_CHAMPION,
					_P2C.TITLE_RUNNER_UP, _P2C.TITLE_SEMIFINAL, _P2C.TITLE_GROUP_CHAMPION]:
				return str(_P2C.TITLE_LABEL[fid])
			return ""
		## ★★周六周日不挂「已晋级」(用户 2026-10-10「行」): 这块榜上它指「晋级了闯关赛」, 而同一天赛况板上的「已晋级」
		##   指「晋级了周日」⇒ 闯关赛 0-3 出局的人在这里照样挂着「已晋级」, 读起来像进了周日。
		_P2C.PHASE_GAUNTLET:
			return ""
	return ""


## `finals_week_view` 的组(`SupabaseNet.parse_finals_week` 的 buckets) + 冠军杯赛那一张(`cup`)
##   → account_id → {"id", "closed"}。
## ★推导走 `Bracket.my_progress` / `semifinal_reached` —— 与主菜单给自己发头衔的那条链同一套
##   (`GameState.sync_titles`): 小组赛赢下 = 组冠军(1 人组也算, 不设门槛); 冠军 / 亚军 / 四强从冠军杯赛来;
##   冠军杯赛只有 1 人 ⇒ 他是冠军, 没有亚军 / 四强。
static func finals_titles(buckets: Array, cup: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var cn := int(cup.get("size", 0))
	var caccs: Array = cup.get("accs", []) if cup.get("accs", []) is Array else []
	for b in buckets:
		if not (b is Dictionary):
			continue
		var bd: Dictionary = b
		var n := int(bd.get("size", 0))
		var accs: Array = bd.get("accs", []) if bd.get("accs", []) is Array else []
		var done: Dictionary = bd.get("done", {}) if bd.get("done", {}) is Dictionary else {}
		if n < 1:
			continue
		var gc := _BR.champion_seed(n, done)
		for sd in range(mini(n, accs.size())):
			var acc := str(accs[sd])
			if acc == "":
				continue
			var tid := _P2C.TITLE_GROUP_CHAMPION if sd == gc else _P2C.TITLE_FINALS_DAY
			out[acc] = {"id": tid, "closed": bool(bd.get("closed", false))}
	## 冠军杯赛 1 人表: 他直接是冠军。
	if cn == 1 and not caccs.is_empty() and str(caccs[0]) != "":
		out[str(caccs[0])] = {"id": _P2C.TITLE_CHAMPION, "closed": bool(cup.get("closed", false))}
	## 冠军杯赛(两人及以上): 冠军 / 亚军 / 四强盖过小组赛那一档(组冠军)。
	if cn >= 2:
		var cdone: Dictionary = cup.get("done", {}) if cup.get("done", {}) is Dictionary else {}
		var ctotal: int = _BR.rounds_for(cn)
		for sd in range(mini(cn, caccs.size())):
			var acc := str(caccs[sd])
			if acc == "":
				continue
			var pr: Dictionary = _BR.my_progress(sd, cn, cdone)
			var tid := ""
			if bool(pr.get("champion", false)):
				tid = _P2C.TITLE_CHAMPION
			elif bool(pr.get("runner_up", false)):
				tid = _P2C.TITLE_RUNNER_UP
			elif _BR.semifinal_reached(int(pr.get("deepest", 0)), ctotal):
				tid = _P2C.TITLE_SEMIFINAL
			if tid != "":
				out[acc] = {"id": tid, "closed": bool(cup.get("closed", false))}
	return out


## 发请求; 返回 false = 一个请求都没发(没配后端), 调用方当场画本机那一路。
## ★先画「正在读取」再发: 回包可能**同步**回来(门禁的假传输、令牌已在手时),
##   反过来的话「正在读取」会把刚画好的服务端榜盖掉。
## ★周一/周日顺带问那一周的决赛(头衔用)。头衔晚到就把同一份榜重画一遍; 问不到就不挂头衔。
## ★★请求**推迟一帧**发(2026-10-06 截图时查实): 从主菜单 `change_scene_to_file` 进来时, 本屏的 `_ready`
##   跑在 root 正在挂子节点的那一刻, `SupabaseNet._spawn()` 往 root 上挂请求节点会报
##   「Parent node is busy setting up children」—— 节点不在树里, 超时计时器起不来、HTTPRequest 也发不出去。
##   (门禁里本屏是挂在测试节点下的, 碰不到这个时刻; 只有当主场景跑才看得见。)
func _ask_server() -> bool:
	if not SB.enabled():
		return false
	_render([], SRC_LOADING, -1)
	call_deferred("_fetch_now")
	return true


func _fetch_now() -> void:
	if not is_inside_tree():
		return
	if day_phase == _P2C.PHASE_REST or day_phase == _P2C.PHASE_FINALS:
		SB.fetch_finals_week_cb(board_week_ts, _on_finals_week)
	## ★先问按页取的新函数(第 1 页); 它没部署(404)再退回旧函数; 都问不到才退回本机。
	if not _request_page(0, true):
		_render(_local_rows(), SRC_LOCAL, -1)


## 发一页请求(第 page 页 = 名次 page*WEEK_LB_PAGE+1 起)。`first` = 开屏那一页, 回包决定走哪一路。
## ★`_pending` 在发之前记: 门禁的假传输会**同步**回包, 记在后面就会把刚回来的那页永远标成「正在取」。
func _request_page(page: int, first: bool = false) -> bool:
	var off: int = page * SB.WEEK_LB_PAGE
	_pending[page] = true
	var sent: bool = SB.fetch_week_leaderboard_page_async(board_week_ts, off, SB.WEEK_LB_PAGE,
		func(res: Dictionary) -> void: _on_server_page(res, page, first))
	if sent:
		page_offsets.append(off)
	else:
		_pending.erase(page)
	return sent


func _on_server_page(res: Dictionary, page: int, first: bool) -> void:
	if not is_inside_tree():
		return
	_pending.erase(page)
	var ok: bool = str(res.get("err", "?")) == "" and res.get("rows", null) is Array
	if first:
		if ok:
			var tot: int = int(res.get("total", 0))
			_render(res["rows"] as Array, SRC_SERVER, tot, _me_of(res), tot)
			return
		## 新函数没部署(老服务端) ⇒ 退回旧函数: 前 WEEK_LB_LEGACY_LIMIT 名 + 我。
		if str(res.get("err", "")) == "unavailable":
			print("[LB] 按页取的函数没部署(404) ⇒ 退回旧函数 week_leaderboard")
			_legacy = true
			if SB.fetch_week_leaderboard_async(board_week_ts, SB.WEEK_LB_LEGACY_LIMIT, _on_server_lb):
				return
		print("[LB] 服务端榜没拿到(%s) ⇒ 退回本机记录" % str(res.get("err", res.get("reason", "?"))))
		_render(_local_rows(), SRC_LOCAL, -1)
		return
	if source != SRC_SERVER:
		return
	if not ok:
		## ★不自动重试: 断网时每滚一下就重发一遍, 只会把请求刷爆。这几行保持「只有名次」的待取样子。
		_failed[page] = true
		print("[LB] 第 %d 页没拿到(%s)" % [page + 1, str(res.get("err", "?"))])
		return
	for r in (res["rows"] as Array):
		var rk := int((r as Dictionary).get("rank", 0))
		if rk >= 1:
			_by_rank[rk] = r
	_recount_dups()
	_rebuild_rows()


## 旧函数那一路(新函数没部署时)。只给前 N 名 ⇒ 列表只到连续拿到的那一名, 「共 X 人上榜」照旧写全榜人数。
func _on_server_lb(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	if str(res.get("err", "?")) == "" and res.get("rows", null) is Array:
		var rows: Array = res["rows"]
		_render(rows, SRC_SERVER, int(res.get("total", 0)), _me_of(res), _contiguous(rows))
		return
	print("[LB] 服务端榜没拿到(%s) ⇒ 退回本机记录" % str(res.get("err", res.get("reason", "?"))))
	_render(_local_rows(), SRC_LOCAL, -1)


## rows 里从第 1 名起连续有几名(旧函数把「我」也可能塞在 rows 末尾, 那一行不算进列表长度)。
static func _contiguous(rows: Array) -> int:
	var have: Dictionary = {}
	for r in rows:
		have[int((r as Dictionary).get("rank", 0))] = true
	var k := 0
	while have.has(k + 1):
		k += 1
	return k


func _on_finals_week(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (res.get("buckets", null) is Array):
		print("[LB] 决赛头衔没拿到(%s) ⇒ 不挂头衔" % str(res.get("reason", "?")))
		return
	_fin_titles = finals_titles(res["buckets"] as Array,
		res.get("cup", {}) if res.get("cup", {}) is Dictionary else {})
	if source == SRC_SERVER or source == SRC_LOCAL:
		_rebuild_rows()


## 本机那一路(原来唯一的一路)。名次 = 全量下标 + 1。
func _local_rows() -> Array:
	var pool := Backend.load_pool()
	## ★limit 必须给【全量】(原来是 30) —— `Backend.leaderboard()` 是**排完序再切**的,
	##   开局大家**胜场**并列 0 时自己经常落在第 30 名开外, **在本屏拿到 rows 之前就已经被切没了**,
	##   于是下面的"钉住自己"根本无从谈起(第一版实拍复看: 榜上仍旧一个「◀ 你」都没有)。
	##   拿全量在这里自己切, 名次 = 全量下标 + 1, 才是真名次。
	## ★"我"那一行用玩家昵称(没设就是兜底短码) —— 与别人那几行同一个来源。
	var rows: Array = Backend.leaderboard(pool, Backend.player_display_name(), int(GameState.season_wins),
		int(GameState.hearts), int(GameState.season_sweeps), 1 << 30)
	## 自己那行的总场次(`leaderboard()` 只认别人的快照字段, 自己的从存档补)。
	## ★2026-10-11 全项目通读 B4: 周一看的是**上周**的榜, 而存档已滚到本周(清零) ⇒ 与服务端那一路同一口径,
	##   自己那一行不许拿本周成绩冒充上周 —— 一律 -1(画「—」)。门禁 verify_leaderboard_monday_local。
	var last_week: bool = day_phase == _P2C.PHASE_REST
	for r in rows:
		if bool((r as Dictionary).get("is_self", false)):
			(r as Dictionary)["battles"] = -1 if last_week else int(GameState.season_total_battles)
			## 头像 = 我现在这支阵容的第一只统领(别人那几行取各自快照的 leaders[0], 见 `Backend.leaderboard`)。
			(r as Dictionary)["lead"] = my_lead()
			if last_week:
				(r as Dictionary)["wins"] = -1
				(r as Dictionary)["hearts"] = -1
				(r as Dictionary)["sweeps"] = 0
	return rows


## 服务端回包里的「我」: `me` 优先, 其次 rows 里标了 is_self 的那行。
## ★本周一份都没传过(服务端榜上没有我)⇒ 仍然钉一行自己, 名次画「—」(不编一个名次)。
func _me_of(res: Dictionary) -> Dictionary:
	var me: Dictionary = res.get("me", {}) if res.get("me", {}) is Dictionary else {}
	if not me.is_empty():
		return me
	for r in (res.get("rows", []) as Array):
		if bool((r as Dictionary).get("is_self", false)):
			return r
	## ★周一看的是**上周**的榜: 存档里的成绩已经滚到本周了, 不许拿来冒充上周。
	var last_week: bool = day_phase == _P2C.PHASE_REST
	return {"rank": 0, "name": Backend.player_display_name(),
		"wins": -1 if last_week else int(GameState.season_wins),
		"hearts": -1 if last_week else int(GameState.hearts),
		"sweeps": 0 if last_week else int(GameState.season_sweeps),
		"battles": -1 if last_week else int(GameState.season_total_battles),
		"is_self": true, "tag": Backend.my_tag(), "lead": my_lead()}


## 我的头像 id = 本周阵容的第一只统领(与上传快照时 `profile.avatar` 同一个来源: `GameState.season_leaders[0]`)。
## 还没选阵容 ⇒ ""(槽里写名字首字)。
static func my_lead() -> String:
	var ls = GameState.season_leaders if GameState != null else []
	return str((ls as Array)[0]) if ls is Array and not (ls as Array).is_empty() else ""


## 这一行的名次: 服务端那一路带 `rank`(全榜真名次), 本机那一路就是下标 + 1。
static func _rank_of(r: Dictionary, idx: int) -> int:
	return int(r.get("rank", idx + 1))


## 整块重画(表面板/分隔线/顶栏不动)。
##   `total` = 上榜人数(<0 ⇒ 用 rows.size()); `me` = 钉住的「我」(空 ⇒ 从 rows 里找 is_self);
##   `n_list` = 列表能翻到第几名(<0 ⇒ rows.size())。
func _render(rows: Array, src: String, total: int, me: Dictionary = {}, n_list: int = -1) -> void:
	_BL.mask(rows)
	_BL.mask(me)
	source = src
	shown_rows = rows
	_last_total = total
	_last_me = me
	_last_n_list = n_list
	_by_rank.clear()
	_row_nodes.clear()
	_scroll = null
	_list = null
	_pin = null
	if _body != null:
		_panel.remove_child(_body)
		_body.queue_free()
	_body = Control.new()
	_body.name = "LbBody"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.position = Vector2.ZERO
	_body.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_child(_body)
	var panel: Control = _body
	var n_on_board: int = total if total >= 0 else rows.size()

	## 表头拆掉之后分隔线上面空出 46px。**不再摆一行字段名**(那正是要去掉的东西),
	## 改摆一句说人话的规模数 —— 顺带把"榜上只有我一个"这件事直接说出来。
	## ★表头这一条从左到右三段, **各占各的横向区间, 互不重叠**:
	##   规模数 [28, 28+CAP_W) │ 「本机记录」[28+CAP_W, STAT_X0-12) │ 三个列名 [STAT_X0, 末列右沿]
	##   (2026-10-06 之前「本机记录」占右半边 [380, 732], 正好压在列名上 ⇒ verify_ui_consistency 报字叠字。)
	var cap_line := Label.new()
	cap_line.name = "LbCapLine"
	cap_line.text = LOADING_TEXT if src == SRC_LOADING else (("上周共 %d 人上榜" if day_phase == _P2C.PHASE_REST
		else "本周共 %d 人上榜") % n_on_board)
	cap_line.add_theme_font_size_override("font_size", 17)
	cap_line.add_theme_color_override("font_color", Color("#c9b58a"))
	cap_line.position = Vector2(PAD + 6.0, HEAD_Y)
	cap_line.size = Vector2(CAP_W, HEAD_H)
	cap_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(cap_line)
	## 列名(照 使命召唤手游 / 英雄联盟手游: 表头纯文字, 与下面的数字**右沿对齐**)。
	if src != SRC_LOADING:
		for ci in range(COL_HEADS.size()):
			var ch := Label.new()
			ch.name = "LbColHead%d" % ci
			ch.text = str(COL_HEADS[ci])
			ch.add_theme_font_size_override("font_size", 16)
			ch.add_theme_color_override("font_color", Color("#9fb2c4"))
			ch.position = Vector2(STAT_X0 + float(ci) * STAT_CELL, HEAD_Y)
			ch.size = Vector2(COL_W, HEAD_H)
			ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			panel.add_child(ch)
	if src == SRC_LOCAL:
		var mark := Label.new()
		mark.name = "LbSourceMark"
		mark.text = FALLBACK_MARK
		mark.add_theme_font_size_override("font_size", 15)
		mark.add_theme_color_override("font_color", Color("#d9a95a"))
		var mx: float = PAD + 6.0 + CAP_W
		mark.position = Vector2(mx, HEAD_Y)
		mark.size = Vector2(STAT_X0 - 12.0 - mx, HEAD_H)
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.add_child(mark)
	if src == SRC_LOADING:
		list_len = 0
		me_row = {}
		_update_jump()
		return

	for i in range(rows.size()):
		var rk: int = _rank_of(rows[i] as Dictionary, i)
		if rk >= 1:
			_by_rank[rk] = rows[i]
	list_len = n_list if n_list >= 0 else rows.size()
	me_row = me
	if me_row.is_empty():
		for i2 in range(rows.size()):
			if bool((rows[i2] as Dictionary).get("is_self", false)):
				me_row = (rows[i2] as Dictionary).duplicate()
				me_row["rank"] = _rank_of(rows[i2] as Dictionary, i2)
				break
	if me_row.is_empty():
		me_row = _me_of({})
	_recount_dups()
	print("[LB] src=%s rows=%d total=%d list=%d me=%d" % [src, rows.size(), n_on_board, list_len,
		int(me_row.get("rank", 0))])   # 分母: 0 行 = 空检查

	## ── 名次列表(滚动区) ──
	## ★滚动条不画(SHOW_NEVER, 照参考三款): 手指拖、滚轮滚照常; 一条竖滚动条会压在成绩列的右沿上。
	_scroll = ScrollContainer.new()
	_scroll.name = "LbScroll"
	_scroll.position = Vector2(0.0, LIST_Y)
	_scroll.size = Vector2(PANEL_W, LIST_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.clip_contents = true
	panel.add_child(_scroll)
	_list = Control.new()
	_list.name = "LbList"
	_list.mouse_filter = Control.MOUSE_FILTER_PASS
	## ★2026-10-23 列表只有真实的人那么长(原来不满一屏时按一屏撑、补「—」空席)。
	_list.custom_minimum_size = Vector2(PANEL_W, float(list_len) * ROW_H)
	_scroll.add_child(_list)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)

	## ── 钉住「我」那一行(列表下沿, 中间一条分隔线) ──
	var psep := ColorRect.new()
	psep.name = "LbPinSep"
	psep.color = Color(0.35, 0.55, 0.70, 0.45)
	psep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	psep.position = Vector2(PAD, LIST_Y + LIST_H + PIN_GAP * 0.5 - 1.0)
	psep.size = Vector2(PANEL_W - PAD * 2.0, 2)
	panel.add_child(psep)
	_pin = Control.new()
	_pin.name = "LbPin"
	_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin.position = Vector2(0.0, PIN_Y)
	_pin.size = Vector2(PANEL_W, CARD_H)
	panel.add_child(_pin)

	# 提示行 —— 三种态各说各的话(原来只有"池子只有我一个"那一种才出提示)。
	## ★「上传阵容」是**接口词**(那是 `upload_ghost` 在做的事, 不是玩家在做的事) ——
	##   用户 2026-09-28 点的就是这个:「文字语言也是」。玩家侧只看得见"打了一场"。
	## ★服务端那一路: 问到了就是 REACH_OK(「打完一场对手就会上来」此时是真的)。
	## ★2026-10-23 它只在榜上 ≤1 人时出现 ⇒ 列表那时只有一张卡, 提示就摆在那张卡下面(列表区里), 不再单占面板底部一条。
	var hint := Label.new()
	hint.name = "LbHint"
	hint.text = hint_text(n_on_board,
		Backend.REACH_OK if src == SRC_SERVER else Backend.pool_reach())
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color("#8292a4"))
	hint.position = Vector2(PAD, LIST_Y + float(list_len) * ROW_H + 18.0)
	hint.size = Vector2(PANEL_W - PAD * 2.0, HEAD_H)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if hint.text != "":
		panel.add_child(hint)
	else:
		hint.free()

	_rebuild_rows()
	_update_jump()


## 重名按**全部已拿到的行 + 我**判(不按画出来的那几行) —— 第 3 名和第 40 名同名, 第 3 名照样该带号。
func _recount_dups() -> void:
	var names: Array = []
	for rk in _by_rank.keys():
		var r: Dictionary = _by_rank[rk]
		if bool(r.get("is_self", false)):
			continue
		names.append(str(r.get("name", "")))
	names.append(str(me_row.get("name", "")))
	_dup_names = Backend._P2.names_needing_tag(names)


func _on_scrolled(_v: float) -> void:
	_refresh_window()


## 滚动区现在露出来的是第几行到第几行(下标, 含两端)。列表空着 ⇒ (0, -1), 一行都不建。
## ★2026-10-23 只数真实的人(原来按 max(人数, 一屏) 数, 不满一屏的那几格画成「—」空席)。
func _window() -> Vector2i:
	var n: int = list_len
	var s: float = float(_scroll.scroll_vertical) if _scroll != null else 0.0
	var first: int = clampi(floori(s / ROW_H), 0, maxi(n - 1, 0))
	var last: int = mini(n, ceili((s + LIST_H) / ROW_H)) - 1
	return Vector2i(first, last)


## 只建露出来的那几行: 滚出去的拆掉、滚进来的现建; 没拿到的那页顺手去取(往下多预取一屏)。
func _refresh_window() -> void:
	if _list == null or not is_instance_valid(_list):
		return
	var w := _window()
	for rk in _row_nodes.keys():
		var i: int = int(rk) - 1
		if i < w.x or i > w.y:
			_drop_row(_row_nodes[rk])
			_row_nodes.erase(rk)
	for i in range(w.x, w.y + 1):
		if not _row_nodes.has(i + 1):
			_row_nodes[i + 1] = _build_row(i + 1)
	if source != SRC_SERVER or _legacy:
		return
	var want: Array = []
	for rk2 in range(w.x + 1, mini(list_len, w.y + 1 + VIS_ROWS) + 1):
		if _by_rank.has(rk2):
			continue
		var pg: int = floori(float(rk2 - 1) / float(SB.WEEK_LB_PAGE))
		if not _pending.has(pg) and not _failed.has(pg) and not want.has(pg):
			want.append(pg)
	for pg2 in want:
		_request_page(int(pg2))


func _drop_row(nd) -> void:
	if is_instance_valid(nd) and nd is Node:
		(nd as Node).get_parent().remove_child(nd)
		(nd as Node).queue_free()


## 整份行重建(新的一页到了 / 头衔到了): 列表里露出来的行 + 钉住那一行。
func _rebuild_rows() -> void:
	if _list == null or not is_instance_valid(_list):
		return
	for rk in _row_nodes.keys():
		_drop_row(_row_nodes[rk])
	_row_nodes.clear()
	if _pin != null and is_instance_valid(_pin):
		for ch in _pin.get_children():
			_drop_row(ch)
		var mrk: int = int(me_row.get("rank", 0))
		_draw_row(_pin, maxi(mrk - 1, 0), me_row)
		_ignore_mouse(_pin)
	_refresh_window()


## 列表里的一行(名次 rk ≤ 榜上人数)。拿到了画整张行卡; 还没拿到(那一页在路上 / 没取到)只画一张压暗的空卡 +
## 名次号(不编名字、不编成绩)。★没有「名次超出人数」那一支了(2026-10-23: 不画空席)。
func _build_row(rk: int) -> Control:
	var row := Control.new()
	row.name = "LbRow_%d" % rk
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(0.0, float(rk - 1) * ROW_H)
	row.size = Vector2(PANEL_W, ROW_H)
	_list.add_child(row)
	if _by_rank.has(rk):
		_draw_row(row, rk - 1, _by_rank[rk] as Dictionary)
	else:
		var band := _row_band(row, ROW_BAND)
		band.modulate.a = 0.45
		var n := _cell(row, str(rk), RANK_X, RANK_W, 20, Color(COL_RANK), HORIZONTAL_ALIGNMENT_CENTER)
		n.modulate.a = 0.42
	_ignore_mouse(row)
	return row


## 行里的签牌/行卡默认会吞掉触摸 ⇒ 手指按在行上拖不动列表。一律放行给滚动区。
## ★★按钮除外(2026-10-23 查实的老 bug): 点别人名字弹「举报 / 拉黑」的那颗热区(`player_menu.hotspot`, 它自己设好了
##   MOUSE_FILTER_PASS = 收得到点击、也不挡拖动)原来也被这里一并改成 IGNORE ⇒ **真机上点名字什么都不会发生**,
##   而门禁 verify_report_block 直接 `pressed.emit()` 绕过了鼠标层, 一直是绿的。
func _ignore_mouse(n: Node) -> void:
	if n is BaseButton:
		return
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in n.get_children():
		_ignore_mouse(ch)


## 顶栏「我的位置」: 把列表滚到我所在那一段(我在第 JUMP_ABOVE+1 行)。榜上没有我 / 我在拿不到的名次 ⇒ 按钮置灰。
const JUMP_ABOVE := 4

func jump_to_me() -> void:
	var rk: int = int(me_row.get("rank", 0))
	if _scroll == null or rk < 1 or rk > list_len:
		return
	var max_s: float = maxf(0.0, float(maxi(list_len, VIS_ROWS) - VIS_ROWS) * ROW_H)
	var target: int = int(clampf(float(rk - 1 - JUMP_ABOVE) * ROW_H, 0.0, max_s))
	_scroll.scroll_vertical = target
	## ★列表刚换过长度、滚动区还没重新排版时, 上一句会被旧的上限夹住 ⇒ 下一帧再设一次。
	if _scroll.scroll_vertical != target:
		_scroll.set_deferred("scroll_vertical", target)
	_refresh_window()


func _update_jump() -> void:
	if jump_btn == null or not is_instance_valid(jump_btn):
		return
	var rk: int = int(me_row.get("rank", 0))
	var can: bool = rk >= 1 and rk <= list_len
	jump_btn.disabled = not can
	jump_btn.modulate = Color(1, 1, 1, 1.0 if can else 0.45)


## 背景 = 主菜单那张平铺底(深绿 #1a3a2a + menu-bg-tile + 暗渐变遮罩)。
##
## ★这不是"给新内容挑素材", 是**补上一处漏做的统一**: 主菜单/图鉴/战绩/设置四屏早就是这张底了,
##   只有本屏还是一块纯 #0a1622 —— 实拍看就是"一片空的深色屏"。
##   (素材铁律说的是"新内容一律新素材"; 这里连新内容都不是, 就是同一层壳没铺全。)
func _bg() -> void:
	var base := ColorRect.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.color = Color(0.102, 0.227, 0.165)
	add_child(base)
	if ResourceLoader.exists("res://assets/sprites/menu/menu-bg-tile.png"):
		var tile := TextureRect.new()
		tile.texture = PreloadCache.menu_bg_tile_tex()   # 复用缓存 512² 纹理(resize 只做一次)
		tile.stretch_mode = TextureRect.STRETCH_TILE
		tile.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vp := get_viewport_rect().size
		tile.size = Vector2(vp.x + 512, vp.y + 512)
		tile.position = Vector2(-512, -512)
		add_child(tile)
		var drift := TweenKit.loop_on(tile)
		drift.tween_property(tile, "position", Vector2(0, 0), 25.0).from(Vector2(-512, -512)).set_trans(Tween.TRANS_LINEAR)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(0.031, 0.047, 0.078, 0.20),
		Color(0.031, 0.047, 0.078, 0.32),
		Color(0.031, 0.047, 0.078, 0.46),
	])
	var gt := GradientTexture2D.new()
	gt.gradient = grad; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gt.width = 8; gt.height = 128
	var ov := TextureRect.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.texture = gt
	ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ov.stretch_mode = TextureRect.STRETCH_SCALE
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)


## 底部提示行说哪一句 —— 纯函数, 四档全可穷举。
##
## ★做成 `static` + 纯函数而不是埋在 `_ready` 里的 if/elif: 门禁要能**逐档**验它。
##   埋在 `_ready` 里的话只验得到"这次真实环境落到的那一档"(而门禁环境恒是 OFF),
##   另外三句从来没被任何判据看过 —— 那正是上一版那句假话活下来的方式。
##   真屏幕上画的就是它的返回值(`_ready` 里只有这一处给 hint 赋值), 所以验它 = 验屏幕。
## ★2026-10-06 榜上有人时不再按自己的战绩说话 ⇒ self_found / self_wins 两个参数没人读了, 一并删掉(死参数门禁)。
static func hint_text(rows_n: int, reach: String) -> String:
	## 榜上不止你一个 ⇒ 与"问没问到"无关, 照旧按自己的战绩说。
	## ★2026-10-06 用户「每场打完自动上榜？何意味啊」: 榜上有人时不再挂底注(参考的手游排行榜都没有页脚说明)。
	if rows_n > 1:
		return ""
	match reach:
		Backend.REACH_OK:
			return HINT_ONLY_YOU_OK
		Backend.REACH_FAIL:
			return HINT_ONLY_YOU_FAIL
		Backend.REACH_UNKNOWN:
			return HINT_ONLY_YOU_UNKNOWN
	return HINT_ONLY_YOU_OFF


## 一张行卡: 底卡(九宫格, 按身份染色) + 名次(奖牌 / 号码) + 头像 + 名字(+「你」签 / 玩家 ID / 头衔) + 成绩槽里三个大号数字。
## ★行里每一格都直接挂在行节点下, x 用本屏自己的列常量(门禁按 `NAME_X` / `RANK_X` / `STAT_X0` 认列, 不另抄坐标)。
func _draw_row(parent: Control, idx: int, r: Dictionary) -> void:
	## ★名次读行自己带的(服务端那一路是全榜真名次, 「我」可能是第 20 名接在第 11 行)。
	var rank: int = _rank_of(r, idx)
	var is_self: bool = bool(r.get("is_self", false))
	var wins: int = int(r.get("wins", 0))
	## ★★★领奖台只发给**有战绩的人**(2026-09-28)。
	##   实拍全新档那张: `#1 龟主-0000 ◀ 你 0胜 · ♥8 · 0横扫` —— 一个字都没打过的人
	##   被画成**金牌第一名**。名次数字本身没说谎(排序下他确实是第 1 行, 因为就他一个),
	##   说谎的是**金/银/铜那块牌**: 牌位的含义是"这人赢到了这个位置"。
	##   ⇒ 判据是「这一行有没有战绩」= `wins > 0`, 不是"排第几"。
	##   0 胜的那行仍然画得见(自己那张行卡的亮橙金 + 「你」签一个都没动 ——
	##   「榜上必须找得到自己」是 2026-08-19 钉死的另一条需求), 只是**不上领奖台**。
	var podium: bool = rank >= 1 and rank <= 3 and wins > 0
	if is_self:
		_row_band(parent, SELF_BAND)
	elif podium:
		_row_band(parent, MEDAL_BAND[rank - 1])
	else:
		_row_band(parent, ROW_BAND)
	_stat_slot(parent)
	_rank_badge(parent, rank, podium, is_self)
	_avatar(parent, r)
	## 自己那行要先给「你」签牌让出位置 —— 名字字块和签牌叠在一起会踩全局的"两段文字压在一起"。
	var nw: float = (NAME_W - YOU_W - YOU_GAP) if is_self else NAME_W
	var tag_s := str(r.get("tag", ""))
	var show_tag: bool = tag_s != "" and _dup_names.has(str(r.get("name", "?")))
	if show_tag:
		nw -= TAG_W
	## 名字旁的头衔 / 「已晋级」(四天各挂各的, 见 `row_mark`)。名字列先给它让出位置。
	var mark_s := row_mark(day_phase, str(r.get("title", "")),
		_fin_titles.get(str(r.get("account_id", "")), {}) as Dictionary)
	if mark_s != "":
		nw -= MARK_W
	var nm := _cell(parent, str(r.get("name", "?")), NAME_X, nw, NAME_FS,
		Color(COL_SELF if is_self else COL_ROW), HORIZONTAL_ALIGNMENT_LEFT)
	_ink(nm, 3)
	## 点别人的头像或名字 ⇒ 「举报 / 拉黑」(热区盖住头像 + 名字那一段, 整张卡高 —— 手指好点)。
	if not is_self:
		_PM.hotspot(parent, Rect2(AV_X, 0.0, SLOT_X - 4.0 - AV_X, CARD_H),
			{"name": _BL.raw_name(r), "tag": tag_s, "ctx": _RPT.CTX_LEADERBOARD,
				"account": str(r.get("account_id", ""))}, _rerender)   # 账号: 菜单里「加好友」直接申请, 不必按 ID 查人
	## ghost 名来自玩家自定义 profile, 长度不受控 —— 截断加省略号, 别让它糊到成绩槽上。
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if is_self:
		_you_tag(parent, nm)
	## 紧跟在名字(自己那行是「你」签)后面依次摆: 玩家 ID → 头衔。
	var tx: float = NAME_X + _text_w(nm) + 10.0 + ((YOU_W + YOU_GAP) if is_self else 0.0)
	if show_tag:
		var tl := _cell(parent, tag_s, tx, TAG_W, TAG_FS, Color(COL_RANK), HORIZONTAL_ALIGNMENT_LEFT)
		tl.name = "RowTag"
		_ink(tl, 2)
		tx += _text_w(tl) + 10.0
	if mark_s != "":
		var ml := _cell(parent, mark_s, tx, MARK_W, MARK_FS,
			Color(COL_PROMOTED if mark_s == MARK_PROMOTED else COL_TITLE), HORIZONTAL_ALIGNMENT_LEFT)
		ml.name = "RowMark_%d" % idx   # 带下标: 同一父节点下重名会被引擎改成 @Label@N
		_ink(ml, 3)
	for ci in range(COL_KEYS.size()):
		var k := str(COL_KEYS[ci])
		var dv: int = -1 if k == "battles" else 0
		_stat_cell(parent, ci, int(r.get(k, dv)), is_self)


## 拉黑 / 移出之后原地重画(同一份行, 名字由 `_BL.mask` 换 / 换回)。
var _last_me: Dictionary = {}
var _last_n_list: int = -1


func _rerender() -> void:
	if is_inside_tree():
		_render(shown_rows, source, _last_total, _last_me, _last_n_list)


## 整张行卡的底(新画的像素九宫格 lb-row.png: 粗描边 + 上亮下暗的斜面 + 四角铆钉; 中灰, 按身份染色)。
## 兜底(贴图缺失时才会用上): **直角 + 不描边** —— 圆角 / 四边细边正是"网页盒"的长相, 全屏一致性门禁对本屏卡的是 0。
func _row_band(parent: Control, tint: Color) -> Panel:
	var band := Panel.new()
	band.name = "RowCard"
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(tint.r * 0.30, tint.g * 0.30, tint.b * 0.30, 1.0)
	var tex := UISkin.nine(ROW_TEX, ROW_TEX_MARGIN, fb)
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = Color(tint.r, tint.g, tint.b, 1.0)
	band.add_theme_stylebox_override("panel", tex)
	band.position = Vector2(CARD_X, 0.0)
	band.size = Vector2(CARD_W, CARD_H)
	parent.add_child(band)
	return band


## 成绩槽: 行卡右段压暗的一块, 上沿一道暗线、下沿一道亮线(往里凹的像素斜面)。三个大号数字住在槽里。
## ★纯色块(ColorRect), 不是 StyleBox —— 不描边不圆角, 不落进"网页盒"。
func _stat_slot(parent: Control) -> void:
	var x0: float = SLOT_X
	var x1: float = CARD_X + CARD_W - 10.0
	var y0: float = 8.0
	var y1: float = CARD_H - 8.0
	for spec in [[SLOT_FILL, y0, y1 - y0], [SLOT_TOP, y0, 2.0], [SLOT_LIP, y1 - 2.0, 2.0]]:
		var c := ColorRect.new()
		c.color = spec[0]
		c.position = Vector2(x0, float(spec[1]))
		c.size = Vector2(x1 - x0, float(spec[2]))
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(c)


## 名次: 前三名是金/银/铜八角奖牌(lb-medal.png 染色), 第 4 名起只剩一个号码(领奖台与看台的差别)。
## `podium` = 这一行**配得上牌位**吗(见 `_draw_row` 里 `podium` 那段: 0 胜不上领奖台)。
##   前三名而不配牌位时走的就是第 4 名起那条路 —— 一个号码, 不是"没有名次"。
func _rank_badge(parent: Control, rank: int, podium: bool, is_self: bool = false) -> void:
	if rank > 3 or rank < 1 or not podium:
		## 名次 < 1 = 服务端榜上还没有我(本周一份都没传过) ⇒ 画「—」, 不编一个名次。
		## 自己那张卡是亮橙金底, 灰蓝号码在上面读不出 ⇒ 用自己那行的字色。
		var n := _cell(parent, str(rank) if rank >= 1 else "—", RANK_X, RANK_W, 22 if rank < 1000 else 18,
			Color(COL_SELF if is_self else COL_RANK), HORIZONTAL_ALIGNMENT_CENTER)
		_ink(n, 3)
		return
	var plate := Panel.new()
	plate.name = "RankMedal"
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.10, 0.12, 0.16, 1.0)      # 直角不描边, 理由同 _row_band
	var tex := UISkin.nine(MEDAL_TEX, 0, fb)
	var c: Color = MEDAL_PLATE[rank - 1]
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = Color(c.r, c.g, c.b, 1.0)
	plate.add_theme_stylebox_override("panel", tex)
	## ★牌子的 x 就是 `RANK_X`(门禁按它认"这是名次牌"), 大小 = 奖牌原图 ×1(36, 不拉伸像素画); 竖直居中在行卡里。
	plate.position = Vector2(RANK_X, (CARD_H - RANK_H) * 0.5)
	plate.size = Vector2(RANK_W, RANK_H)
	parent.add_child(plate)
	## ★号码住在**牌子里**(而不是摆在牌子旁边): 牌子 36×36 两边都 <40,
	##   一致性门禁按"角标"放过它 —— 见 RANK_W 的注释。
	var l := Label.new()
	l.text = str(rank)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color("#ffffff"))
	l.add_theme_color_override("font_outline_color", Color(MEDAL_NUM_OUTLINE[rank - 1]))
	l.add_theme_constant_override("outline_size", 5)
	l.position = Vector2.ZERO
	l.size = Vector2(RANK_W, RANK_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	plate.add_child(l)


## 头像 = 这个人的第一只统领(`lead`)。与周六赛况板 / 对阵图同一个头像件(`MatchCard.avatar`)。
## 没有 `lead`(老服务端没下发 / 老快照没带) ⇒ 槽里写名字首字, 不编一只龟(对阵图同一个做法);
##   名字首字是数字 / 符号时连字都不写(空槽) —— 一个孤零零的数字会被读成名次。
func _avatar(parent: Control, r: Dictionary) -> void:
	var pid := str(r.get("lead", ""))
	var nm := str(r.get("name", ""))
	var letter := nm.substr(0, 1).to_upper() if nm != "" else ""
	if letter != "" and (letter.is_valid_int() or (letter.to_upper() == letter.to_lower() and letter.unicode_at(0) < 0x2E80)):
		letter = ""
	var av := MatchCard.avatar(pid, AV_PX, false, false, letter)
	av.name = "RowAvatar"
	av.position = Vector2(AV_X, (CARD_H - AV_PX) * 0.5)
	parent.add_child(av)


## 名字那一格里字真正占了多宽(截断了就是格宽)。「你」签 / 玩家 ID / 头衔都按它往后摆 ——
## 摆死一个 x 会在短名字后留一大段空, 在长名字上又叠上去。
func _text_w(nm: Label) -> float:
	var tw: float = nm.size.x
	var f: Font = nm.get_theme_font("font")
	if f != null:
		tw = minf(tw, f.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			nm.get_theme_font_size("font_size")).x)
	return tw


## 「你」金签牌, 贴在自己名字**后面**。
func _you_tag(parent: Control, nm: Label) -> void:
	var tw: float = _text_w(nm)
	var tag := Panel.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.16, 0.13, 0.05, 1.0)      # 直角不描边, 理由同 _row_band
	var tex := UISkin.nine("chip-frame.png", 7, fb)
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = Color(SELF_TAG.r, SELF_TAG.g, SELF_TAG.b, 1.0)
	tag.add_theme_stylebox_override("panel", tex)
	tag.position = Vector2(NAME_X + tw + 10.0, (CARD_H - YOU_H) * 0.5)
	tag.size = Vector2(YOU_W, YOU_H)
	parent.add_child(tag)
	var l := Label.new()
	l.text = "你"
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(COL_SELF))
	l.position = Vector2.ZERO
	l.size = Vector2(YOU_W, YOU_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_child(l)


## 成绩一格 = 一个**纯数字**(30 号像素字 + 暗描边), 右对齐到列右沿(与表头列名同一条右沿)。`i` = COL_HEADS 的下标。
## ★2026-10-06 用户「排行榜里的奖杯是？」: 格里不画图标(照 使命召唤手游 / 英雄联盟手游, 列名写在表头)。
## ★★2026-10-24 用户「画吧」(问的是「剩余生命要不要画成心形」) ⇒ **只有「剩余生命」这一列**改画心形(`_hearts_cell`);
##   胜场 / 总场次照旧是纯数字, 别的图标照旧不进成绩格。
## `v < 0` = 这一项没有数据(老快照没带总场次 / 周一上周榜上没有我) ⇒ 「—」, 不编 0。
func _stat_cell(parent: Control, i: int, v: int, is_self: bool) -> void:
	var cx: float = STAT_X0 + float(i) * STAT_CELL
	if str(COL_KEYS[i]) == "hearts":
		_hearts_cell(parent, cx, v)
		return
	var col: String = COL_DIM if v <= 0 else (COL_SELF if is_self else COL_ROW)
	var l := _cell(parent, str(v) if v >= 0 else "—", cx, COL_W, STAT_FS,
		Color(col), HORIZONTAL_ALIGNMENT_RIGHT)
	l.name = "RowStat%d_%d" % [i, int(parent.position.y)]
	_ink(l, STAT_OUTLINE)


## 剩余生命 = 一排 HEARTS_MAX 颗心: 还在的命是红心(左起), 丢掉的是暗色空槽; 整排右对齐到列右沿(与表头列名同一条右沿)。
## 心形 18×16 = 9×8 美术像素 ×2(与行卡 / 奖牌同一个口径), `tools/build_lb_heart.py` 生成; 不拉伸、最近邻。
## ★不收点击: 整行点名字弹玩家菜单, 心不能挡热区。`hearts` 元数据 = 画了几颗红心(门禁读它, 不读贴图名猜)。
func _hearts_cell(parent: Control, cx: float, v: int) -> void:
	var n: int = int(_P2C.HEARTS_MAX)
	var lit: int = clampi(v, 0, n)
	var w: float = HEARTS_ROW_W
	var box := Control.new()
	box.name = "RowHearts_%d" % int(parent.position.y)
	box.set_meta("hearts", lit)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(cx + COL_W - w, (CARD_H - HEART_H) * 0.5)
	box.size = Vector2(w, HEART_H)
	parent.add_child(box)
	var full: Texture2D = load(HEART_TEX)
	var empty: Texture2D = load(HEART_EMPTY_TEX)
	for k in range(n):
		var t := TextureRect.new()
		t.name = "Heart%d" % k
		t.texture = full if k < lit else empty
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.position = Vector2(float(k) * (HEART_W + HEART_GAP), 0.0)
		t.size = Vector2(HEART_W, HEART_H)
		box.add_child(t)


## 行内一格文字(统一行高 = 行卡高、竖直居中 —— 手写一遍就会漂)。
func _cell(parent: Control, s: String, x: float, w: float, fs: int,
		col: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.position = Vector2(x, 0.0)
	l.size = Vector2(w, CARD_H)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


## 字的暗描边(行卡染亮橙金 / 金 / 铜时, 浅色字要靠它才压得住底)。
func _ink(l: Label, px: int) -> void:
	l.add_theme_color_override("font_outline_color", COL_INK)
	l.add_theme_constant_override("outline_size", px)
