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
## 判据同一轮搬家: `tests/verify_leaderboard_header.gd` 原来量表头, 表头没了之后那两条
## 分母当场红 —— 产品对了判据还在量旧样子。已改成**在数据行上**量同一件事。

const W := 1280.0
const PANEL_W := 760.0
## 内边距要 > panel-frame 贴图**实测边带 13px**(不是九宫格配置的 20 —— 那是"从哪切开",
## 不是"画了多宽的边"; verify_ui_consistency 的 `_band_of` 就是这么量的)。
const PAD := 22.0
const ROW_H := 40.0
const ROW_TOP := 68.0
## 底部给"提示行"留一行的位置 —— 空数据态/自己 0 蛋时要说人话, 不能只剩一屏 0。
const FOOT_H := 30.0
const ROWS := 11
## ★面板高度是【按内容反算】的, 不是拍脑袋: 表头到首行 68 + 11 行×40 + 提示行 30 + 下内边距。
##   第一版随手写 584, 于是 floor(可用高/行高) 之后余下一条 24px 的空带子夹在末行和提示行之间。
const PANEL_H := ROW_TOP + float(ROWS) * ROW_H + FOOT_H + PAD
const PANEL_X := (W - PANEL_W) / 2.0
const PANEL_Y := 86.0
const Backend = preload("res://scripts/net/backend.gd")

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
## 全部横坐标按内容区 [PAD, PANEL_W-PAD] = [22, 738] **反算**, 不是拍脑袋:
##   名次牌 24..58 │ 名字 74..484 │ 成绩三格 500..734
const RANK_X := PAD + 2.0
## ★34×28: **两边都 < 40** 是有讲究的 —— `verify_ui_consistency` 把"住在 <40px 小盒子里的字"
##   当角标放过(那条判据的原话见它的 `_badge`)。牌子再大一格, 牌里的名次数字就会被
##   当成"文字压边带"报上来, 而实拍它稳稳在牌中间。
const RANK_W := 34.0
const RANK_H := 28.0
const NAME_X := PAD + 52.0
const NAME_W := 410.0
## 「你」签牌: 36×24, 同样 < 40(理由同上)。自己那行的名字列要先给它让出 48px,
## 否则长昵称的字块会和签牌叠在一起(全屏"两段文字压在一起"那条判据是**全局清零**的)。
const YOU_W := 36.0
const YOU_H := 24.0
const YOU_GAP := 12.0
## 玩家 ID(`#XXXXXX`)那一小格。★只在**重名**的行上出现(2026-10-04 · 名字允许重复,
##   同名的两个人靠它分开); 不重名的行一个字都不多。字小一号、走名次那个灰。
const TAG_W := 82.0
const TAG_FS := 14
## 这一榜里重名的名字(`_P2.names_needing_tag` 算的) —— `_draw_row` 读它决定要不要摆 ID。
var _dup_names: Dictionary = {}
## 成绩三列: 每列宽 70, 列距 12 ⇒ 500 / 582 / 664, 末列右沿 734。数字与列名都**右对齐到列右沿**。
const STAT_X0 := PAD + 478.0
const STAT_CELL := 82.0
const COL_W := 70.0
## 表头左段「本周共 N 人上榜」的宽(16 号字 9 个字位 ≈ 140, 留 20 余量)。
const CAP_W := 160.0

## ═══ 三个成绩列 (2026-10-06 · 用户「积分赛写上名字，剩余生命，胜场，总场次啊 ，都给我做」) ═══
## 列名就是用户那句话里的词, 一个字不改; 照 使命召唤手游 / 英雄联盟手游 排行榜:
##   **表头写纯文字列名, 行里只放数字**(格里不画图标 —— 用户「排行榜里的奖杯是？」)。
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
const TITLE_ICON := "🏆 "
const DAY_TITLE := {
	"rest": "上周终榜",
	"ranked": "本周排行",
	"gauntlet": "积分赛终榜",
	"finals": "积分赛终榜",
}
const MARK_PROMOTED := "已晋级"
const MARK_W := 64.0
const MARK_FS := 14
const COL_TITLE := "#f2c766"
const COL_PROMOTED := "#8fd99c"
const WEEK_SEC := 7 * 86400
## 顶栏右侧那个入口: 与主菜单赛程卡上那扇门**同一个目标场景**(常量取自 MainMenuScene, 不另抄)。
const BRACKET_LINE := "查看对阵图"
const _P2C := preload("res://scripts/gamedata/phase2_config.gd")
const _BR := preload("res://scripts/gamedata/bracket.gd")
const _MM := preload("res://scripts/scenes/MainMenuScene.gd")

## 金/银/铜。`modulate_color` 是**乘**在 chip-frame 上的(它是一块暗底 + 一圈银边:
## 实测底 (52,58,69)、边 (158,164,179)) ⇒ 乘出来就是"暗底 + 金/银/铜边框"的签牌,
## 而不是一块纯色圆角 —— 这正是"用颜色与边框"而不是堆 emoji 的做法。
const MEDAL_PLATE := [
	Color(1.50, 1.14, 0.44),      # 金
	Color(1.22, 1.30, 1.44),      # 银
	Color(1.42, 0.88, 0.52),      # 铜
]
## 整行的底签牌(比牌位暗一档, 只当"领奖台的台阶", 不许抢自己那行的亮度)。
const MEDAL_BAND := [
	Color(1.00, 0.82, 0.34),
	Color(0.86, 0.92, 1.04),
	Color(0.98, 0.64, 0.38),
]
const MEDAL_NUM := ["#ffefb0", "#eef5ff", "#ffd2a4"]
## 自己那行: 全屏最亮的一条(和 MEDAL_BAND 三条都不一样 —— 门禁就是这么判"你看得出来"的)。
const SELF_BAND := Color(1.18, 1.02, 0.52)
const SELF_TAG := Color(1.34, 1.14, 0.56)
const COL_SELF := "#ffe9a8"
const COL_ROW := "#dfe9f2"
const COL_DIM := "#5d6e7e"
const COL_RANK := "#7f93a6"

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
## account_id → {"id": 头衔 id, "closed": 那一组打完没有}(决赛日那一周的 finals_week_view 现算)。
var _fin_titles: Dictionary = {}
var _last_total: int = -1
## 每次重画都整块换掉的那一层(表面板 + 分隔线 + 顶栏不动)。
var _panel: Panel = null
var _body: Control = null

func _ready() -> void:
	_bg()

	## ★顶栏走全项目同一个原语 `TopBar`(2026-09-19·用户「做」)。
	##   规则来自 599 张/146 个触屏游戏枢纽页的逐张实测, 见 top_bar.gd 头注。
	var _sm: Vector4 = SafeArea.margins(Vector2(get_viewport().get_visible_rect().size), 18.0)
	## ★「现在」只读这一次(全局时间缝: 门禁钉钟 / 开发包穿越 / 服务器偏移都在它里面)。
	var now: int = int(_P2C.now_utc())
	day_phase = _P2C.phase_at_utc(now)
	board_week_ts = board_week(now)
	var acts: Array = []
	var ent := day_entry(day_phase)
	if not ent.is_empty():
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
		"on_back": func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"),
		"actions": acts,
	})
	if not acts.is_empty() and _top_bar.action_btns.size() > 0:
		entry_btn = _top_bar.action_btns[_top_bar.action_btns.size() - 1] as Button
		entry_btn.name = "LbDayEntry"

	# 表面板 —— 金属九宫格(和背包/图鉴/战绩同一张 panel-frame)。冷蓝调走 modulate,
	# ★ modulate 别超 1.3: 过了会把框芯冲亮、金属细节糊平(实拍确认过)。
	var panel := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.12, 0.18, 0.9); psb.border_color = Color("#2e4a5e")
	psb.set_border_width_all(2); psb.set_corner_radius_all(12)
	var ptex := UISkin.nine("panel-frame.png", 20, psb)
	if ptex is StyleBoxTexture:
		(ptex as StyleBoxTexture).modulate_color = Color(0.74, 0.94, 1.14, 1.0)
	panel.add_theme_stylebox_override("panel", ptex)
	panel.position = Vector2(PANEL_X, PANEL_Y); panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(panel)
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
	sep.color = Color(0.35, 0.55, 0.70, 0.55)
	sep.position = Vector2(PAD, ROW_TOP - 12.0); sep.size = Vector2(PANEL_W - PAD * 2.0, 2)
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
	return TITLE_ICON + str(DAY_TITLE.get(phase, DAY_TITLE[_P2C.PHASE_RANKED]))


## 顶栏右侧入口: 周六 → 全场赛况(GauntletBoard) / 周日 → 查看对阵图(BracketMap) / 其余 → 无。
## ★目标场景与文字都取主菜单那两扇门的常量 —— 同一个入口不许有两份地址。
static func day_entry(phase: String) -> Dictionary:
	if phase == _P2C.PHASE_GAUNTLET:
		return {"text": _MM.GAUNTLET_BOARD_LINE, "scene": _MM.GAUNTLET_BOARD_SCENE}
	if phase == _P2C.PHASE_FINALS:
		return {"text": BRACKET_LINE, "scene": _MM.BRACKET_SCENE}
	return {}


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
	get_tree().change_scene_to_file(path)


## 名字旁边挂什么(纯函数, 四天全可穷举)。返回显示文字, "" = 不挂。
##   `srv_title` = 服务端 standings.title(现在恒空; 有就以它为准)
##   `fin` = 这个人在那一周决赛里的 {"id": TITLE_*, "closed": 那一组打完没有}, 不在决赛里 = {}
static func row_mark(phase: String, wins: int, srv_title: String, fin: Dictionary) -> String:
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
	if not SB.fetch_week_leaderboard_async(board_week_ts, SB.WEEK_LB_LIMIT, _on_server_lb):
		_render(_local_rows(), SRC_LOCAL, -1)


func _on_server_lb(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	if str(res.get("err", "?")) == "" and res.get("rows", null) is Array:
		_render(_server_rows(res), SRC_SERVER, int(res.get("total", 0)))
		return
	print("[LB] 服务端榜没拿到(%s) ⇒ 退回本机记录" % str(res.get("err", res.get("reason", "?"))))
	_render(_local_rows(), SRC_LOCAL, -1)


func _on_finals_week(res: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not (res.get("buckets", null) is Array):
		print("[LB] 决赛头衔没拿到(%s) ⇒ 不挂头衔" % str(res.get("reason", "?")))
		return
	_fin_titles = finals_titles(res["buckets"] as Array,
		res.get("cup", {}) if res.get("cup", {}) is Dictionary else {})
	if source == SRC_SERVER or source == SRC_LOCAL:
		_render(shown_rows, source, _last_total)


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
	for r in rows:
		if bool((r as Dictionary).get("is_self", false)):
			(r as Dictionary)["battles"] = int(GameState.season_total_battles)
	return rows


## 服务端那一路: 前 N 名 + 「我」(不在前 N 名里就接在末尾, 名次是服务端给的全榜真名次)。
## ★本周一份都没传过(服务端榜上没有我)⇒ 仍然钉一行自己, 名次画「—」(不编一个名次)。
func _server_rows(res: Dictionary) -> Array:
	var rows: Array = (res.get("rows", []) as Array).duplicate(true)
	for r in rows:
		if bool((r as Dictionary).get("is_self", false)):
			return rows
	var me: Dictionary = res.get("me", {}) if res.get("me", {}) is Dictionary else {}
	if not me.is_empty():
		rows.append(me)
	else:
		## ★周一看的是**上周**的榜: 存档里的成绩已经滚到本周了, 不许拿来冒充上周 ⇒ 只钉一行空名次。
		var last_week: bool = day_phase == _P2C.PHASE_REST
		rows.append({"rank": 0, "name": Backend.player_display_name(),
			"wins": -1 if last_week else int(GameState.season_wins),
			"hearts": -1 if last_week else int(GameState.hearts),
			"sweeps": 0 if last_week else int(GameState.season_sweeps),
			"battles": -1 if last_week else int(GameState.season_total_battles),
			"is_self": true, "tag": Backend.my_tag()})
	return rows


## 这一行的名次: 服务端那一路带 `rank`(全榜真名次), 本机那一路就是下标 + 1。
static func _rank_of(r: Dictionary, idx: int) -> int:
	return int(r.get("rank", idx + 1))


## 整块重画(表面板/分隔线/顶栏不动)。`total` = 上榜人数(<0 ⇒ 用 rows.size())。
func _render(rows: Array, src: String, total: int) -> void:
	source = src
	shown_rows = rows
	_last_total = total
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
	##   规模数 [28, 28+CAP_W) │ 「本机记录」[28+CAP_W, STAT_X0-12) │ 三个列名 [STAT_X0, 734]
	##   (2026-10-06 之前「本机记录」占右半边 [380, 732], 正好压在列名上 ⇒ verify_ui_consistency 报字叠字。)
	var cap_line := Label.new()
	cap_line.name = "LbCapLine"
	cap_line.text = LOADING_TEXT if src == SRC_LOADING else (("上周共 %d 人上榜" if day_phase == _P2C.PHASE_REST
		else "本周共 %d 人上榜") % n_on_board)
	cap_line.add_theme_font_size_override("font_size", 16)
	cap_line.add_theme_color_override("font_color", Color("#8fa6b8"))
	cap_line.position = Vector2(PAD + 6.0, PAD + 2.0)
	cap_line.size = Vector2(CAP_W, 26.0)
	cap_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(cap_line)
	## 列名(照 使命召唤手游 / 英雄联盟手游: 表头纯文字, 与下面的数字**右沿对齐**)。
	if src != SRC_LOADING:
		for ci in range(COL_HEADS.size()):
			var ch := Label.new()
			ch.name = "LbColHead%d" % ci
			ch.text = str(COL_HEADS[ci])
			ch.add_theme_font_size_override("font_size", 15)
			ch.add_theme_color_override("font_color", Color("#8fa6b8"))
			ch.position = Vector2(STAT_X0 + float(ci) * STAT_CELL, PAD + 2.0)
			ch.size = Vector2(COL_W, 26.0)
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
		mark.position = Vector2(mx, PAD + 2.0)
		mark.size = Vector2(STAT_X0 - 12.0 - mx, 26.0)
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		panel.add_child(mark)
	if src == SRC_LOADING:
		return

	# ★能画几行是【算出来】的, 不是写死的阈值 —— 写死那次末行正好压在金属边带上。
	var body_h: float = PANEL_H - PAD - FOOT_H - ROW_TOP
	var cap: int = maxi(1, int(floor(body_h / ROW_H)))
	print("[LB] src=%s rows=%d total=%d cap=%d body_h=%.0f" % [src, rows.size(), n_on_board, cap, body_h])   # 分母: 0 行 = 空检查
	var self_idx := _self_index(rows)
	var shown := _pick_rows(rows, cap, self_idx)
	## ★重名按**全量** rows 判, 不按画出来的那几行 —— 第 3 名和第 40 名同名, 第 3 名照样该带号。
	var _all_names: Array = []
	for rr in rows:
		_all_names.append(str((rr as Dictionary).get("name", "")))
	_dup_names = Backend._P2.names_needing_tag(_all_names)

	var y := ROW_TOP
	var max_rank := 0
	for item in shown:
		var idx: int = int(item)
		if idx < 0:                     # -1 = 省略号占位(自己被钉到末行时, 中间断开的地方)
			var gap := Label.new(); gap.text = "⋯"
			gap.add_theme_font_size_override("font_size", 18)
			gap.add_theme_color_override("font_color", Color("#4a5a6b"))
			gap.position = Vector2(PAD, y); gap.size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 6.0)
			gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			panel.add_child(gap)
			y += ROW_H
			continue
		_draw_row(panel, y, idx, rows[idx] as Dictionary)
		max_rank = maxi(max_rank, _rank_of(rows[idx] as Dictionary, idx))
		y += ROW_H

	## ★★空席(2026-09-28)。用户那张实拍上整屏就是「一条金色长条 + 一行字」——
	##   那**不是画错了**, 那就是全新档的真榜: `rows.size() == 1`(只有自己)。
	##   一块只画了一行的榜看起来像坏掉的界面。⇒ 剩下的名次照样画出来, 画成**空席**:
	##   名次在、牌位在(前三名的金银铜压暗), 名字位置一道破折号。
	##   一眼能读出"这是一块 11 名的榜, 位置都空着", 而不是"这屏只有一行"。
	##   ⚠ 空席**不带成绩数字** —— 补零会造出"别人 0 胜"的假数据。
	var drawn: int = shown.size()
	var vacant: int = max_rank + 1
	while drawn < cap:
		_draw_vacant(panel, y, vacant)
		y += ROW_H
		drawn += 1
		vacant += 1

	# 底部提示行 —— 三种态各说各的话(原来只有"池子只有我一个"那一种才出提示)。
	## ★「上传阵容」是**接口词**(那是 `upload_ghost` 在做的事, 不是玩家在做的事) ——
	##   用户 2026-09-28 点的就是这个:「文字语言也是」。玩家侧只看得见"打了一场"。
	##   (改这句之前 grep 过 `tests/` `tools/`: 没有任何判据钉这句文案;
	##    `tests/_probe_newuser.gd:100` 里有一份手抄的同串, 那是探针的自印, 不是断言。)
	## ★服务端那一路: 问到了就是 REACH_OK(「打完一场对手就会上来」此时是真的)。
	var hint := Label.new()
	hint.text = hint_text(n_on_board,
		Backend.REACH_OK if src == SRC_SERVER else Backend.pool_reach())
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("#6b7b8c"))
	hint.position = Vector2(PAD, PANEL_H - PAD - FOOT_H + 4.0)
	hint.size = Vector2(PANEL_W - PAD * 2.0, FOOT_H - 6.0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if hint.text != "":
		panel.add_child(hint)
	else:
		hint.free()


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
		var drift := tile.create_tween().set_loops()
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


## 自己在 rows 里的下标(没有 = -1)。
func _self_index(rows: Array) -> int:
	for i in range(rows.size()):
		if bool((rows[i] as Dictionary).get("is_self", false)):
			return i
	return -1


## 挑出要画的行下标; `-1` 表示"这里插一个省略号"。
##
## ★为什么要这一步: 榜单能取 30 条, 面板只画得下 12 行左右。原来是"画到装不下就 break",
##   于是**自己排在第 13 名开外时整屏看不到自己** —— 而**胜场**并列 0 的开局,
##   自己排第几完全看排序稳定性(实拍那张就一个「◀ 你」都没有)。
##   ⇒ 自己不在可见段里就把**末行让给自己**, 中间用 ⋯ 断开(通用榜单做法)。
func _pick_rows(rows: Array, cap: int, self_idx: int) -> Array:
	var out: Array = []
	var n: int = mini(rows.size(), cap)
	if self_idx < 0 or self_idx < cap:
		for i in range(n):
			out.append(i)
		return out
	for i in range(maxi(0, cap - 2)):
		out.append(i)
	out.append(-1)
	out.append(self_idx)
	return out


## 一行: 底签牌 + 名次牌 + 名字(+「你」签) + 三个「图标 数字」。
func _draw_row(parent: Control, y: float, idx: int, r: Dictionary) -> void:
	## ★名次读行自己带的(服务端那一路是全榜真名次, 「我」可能是第 20 名接在第 11 行)。
	var rank: int = _rank_of(r, idx)
	var is_self: bool = bool(r.get("is_self", false))
	var wins: int = int(r.get("wins", 0))
	## ★★★领奖台只发给**有战绩的人**(2026-09-28)。
	##   实拍全新档那张: `#1 龟主-0000 ◀ 你 0胜 · ♥8 · 0横扫` —— 一个字都没打过的人
	##   被画成**金牌第一名**。名次数字本身没说谎(排序下他确实是第 1 行, 因为就他一个),
	##   说谎的是**金/银/铜那块牌**: 牌位的含义是"这人赢到了这个位置"。
	##   ⇒ 判据是「这一行有没有战绩」= `wins > 0`, 不是"排第几"。
	##   0 胜的那行仍然画得见(自己那行的整行金底 + 「你」签一个都没动 ——
	##   「榜上必须找得到自己」是 2026-08-19 钉死的另一条需求), 只是**不上领奖台**。
	##   ⚠ 空席的暗牌位不在此列: 那是"台阶空着", 本来就已经压到 0.42。
	var podium: bool = rank >= 1 and rank <= 3 and wins > 0
	if is_self:
		_row_band(parent, y, SELF_BAND)
	elif podium:
		_row_band(parent, y, MEDAL_BAND[rank - 1])
	elif idx % 2 == 1:
		var zebra := ColorRect.new()   # 斑马纹: 纯色块, 不带边 ⇒ 不是"网页盒"
		zebra.color = Color(1, 1, 1, 0.035)
		zebra.position = Vector2(PAD - 6.0, y - 5.0)
		zebra.size = Vector2(PANEL_W - (PAD - 6.0) * 2.0, ROW_H - 4.0)
		parent.add_child(zebra)
	_rank_badge(parent, y, rank, 1.0, podium)
	## 自己那行要先给「你」签牌让出位置 —— 名字字块和签牌叠在一起会踩全局的"两段文字压在一起"。
	var nw: float = (NAME_W - YOU_W - YOU_GAP) if is_self else NAME_W
	var tag_s := str(r.get("tag", ""))
	var show_tag: bool = tag_s != "" and _dup_names.has(str(r.get("name", "?")))
	if show_tag:
		nw -= TAG_W
	## 名字旁的头衔 / 「已晋级」(四天各挂各的, 见 `row_mark`)。名字列先给它让出位置。
	var mark_s := row_mark(day_phase, wins, str(r.get("title", "")),
		_fin_titles.get(str(r.get("account_id", "")), {}) as Dictionary)
	if mark_s != "":
		nw -= MARK_W
	var nm := _cell(parent, str(r.get("name", "?")), NAME_X, y, nw, 18,
		Color(COL_SELF if is_self else COL_ROW), HORIZONTAL_ALIGNMENT_LEFT)
	## ghost 名来自玩家自定义 profile, 长度不受控 —— 截断加省略号, 别让它糊到成绩列上。
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if is_self:
		_you_tag(parent, nm, y)
	## 紧跟在名字(自己那行是「你」签)后面依次摆: 玩家 ID → 头衔。
	var tx: float = NAME_X + _text_w(nm) + 8.0 + ((YOU_W + YOU_GAP) if is_self else 0.0)
	if show_tag:
		var tl := _cell(parent, tag_s, tx, y + 1.0, TAG_W, TAG_FS, Color(COL_RANK),
			HORIZONTAL_ALIGNMENT_LEFT)
		tl.name = "RowTag"
		tx += _text_w(tl) + 8.0
	if mark_s != "":
		var ml := _cell(parent, mark_s, tx, y + 1.0, MARK_W, MARK_FS,
			Color(COL_PROMOTED if mark_s == MARK_PROMOTED else COL_TITLE), HORIZONTAL_ALIGNMENT_LEFT)
		ml.name = "RowMark_%d" % int(y)   # 带 y: 同一父节点下重名会被引擎改成 @Label@N
	for ci in range(COL_KEYS.size()):
		var k := str(COL_KEYS[ci])
		var dv: int = -1 if k == "battles" else 0
		_stat_cell(parent, y, ci, int(r.get(k, dv)), is_self)


## 空席: 名次 + 牌位(压暗) + 破折号。
## ★**不画成绩数字**(补零就成了"别人 0 胜"的假数据), 三个成绩位画破折号 ——
##   既守住列的节奏(不然整块榜右半边是空的), 又明说"这里没有人"。
## ★也**不画图标**: 图标是"这个量有多少"的标记, 空席上没有量。
func _draw_vacant(parent: Control, y: float, rank: int) -> void:
	## ★空席照旧给牌位(压到 0.42) —— 空席画的是"台阶空着", 没有"谁赢到了这里"的主张。
	_rank_badge(parent, y, rank, 0.42, true)
	var l := _cell(parent, "—", NAME_X, y, NAME_W, 18, Color(COL_DIM), HORIZONTAL_ALIGNMENT_LEFT)
	l.modulate.a = 0.75
	for i in range(COL_HEADS.size()):
		var d := _cell(parent, "—", STAT_X0 + float(i) * STAT_CELL, y,
			COL_W, 18, Color(COL_DIM), HORIZONTAL_ALIGNMENT_RIGHT)
		d.modulate.a = 0.6


## 整行的底签牌(九宫格金属签, 不是圆角色块)。
func _row_band(parent: Control, y: float, tint: Color) -> void:
	var band := Panel.new()
	var fb := StyleBoxFlat.new()
	## 兜底(贴图缺失时才会用上): **直角 + 不描边** —— 圆角/四边细边正是"网页盒"的长相,
	## 全屏一致性门禁对本屏卡的是 0。
	fb.bg_color = Color(0.10, 0.13, 0.17, 0.55)
	var tex := UISkin.nine("chip-frame.png", 7, fb)
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = Color(tint.r, tint.g, tint.b, 1.0)
	band.add_theme_stylebox_override("panel", tex)
	band.position = Vector2(PAD - 6.0, y - 5.0)
	band.size = Vector2(PANEL_W - (PAD - 6.0) * 2.0, ROW_H - 4.0)
	parent.add_child(band)


## 名次: 前三名是金/银/铜签牌, 第 4 名起只剩一个暗号码(领奖台与看台的差别)。
## `k` = 亮度系数, 空席用 0.42 压暗。
## `podium` = 这一行**配得上牌位**吗(见 `_draw_row` 里 `podium` 那段: 0 胜不上领奖台)。
##   前三名而不配牌位时走的就是第 4 名起那条路 —— 一个暗号码, 不是"没有名次"。
func _rank_badge(parent: Control, y: float, rank: int, k: float, podium: bool) -> void:
	if rank > 3 or rank < 1 or not podium:
		## 名次 < 1 = 服务端榜上还没有我(本周一份都没传过) ⇒ 画「—」, 不编一个名次。
		var n := _cell(parent, str(rank) if rank >= 1 else "—", RANK_X, y, RANK_W, 16,
			Color(COL_RANK), HORIZONTAL_ALIGNMENT_CENTER)
		n.modulate.a = k
		return
	var plate := Panel.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.10, 0.12, 0.16, 1.0)      # 直角不描边, 理由同 _row_band
	var tex := UISkin.nine("chip-frame.png", 7, fb)
	var c: Color = MEDAL_PLATE[rank - 1]
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = Color(c.r * k, c.g * k, c.b * k, 1.0)
	plate.add_theme_stylebox_override("panel", tex)
	plate.position = Vector2(RANK_X, y)
	plate.size = Vector2(RANK_W, RANK_H)
	parent.add_child(plate)
	## ★号码住在**牌子里**(而不是摆在牌子旁边): 牌子 34×28 两边都 <40,
	##   一致性门禁按"角标"放过它 —— 见 RANK_W 的注释。
	var l := Label.new()
	l.text = str(rank)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(MEDAL_NUM[rank - 1]))
	l.position = Vector2.ZERO
	l.size = Vector2(RANK_W, RANK_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate.a = k
	plate.add_child(l)


## 「你」金签牌, 贴在自己名字**后面**。位置按字块真实宽度算 —— 摆死一个 x 会在短名字后
## 留一大段空, 在长名字上又叠上去。
## 名字那一格里字真正占了多宽(截断了就是格宽)。
func _text_w(nm: Label) -> float:
	var tw: float = nm.size.x
	var f: Font = nm.get_theme_font("font")
	if f != null:
		tw = minf(tw, f.get_string_size(nm.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			nm.get_theme_font_size("font_size")).x)
	return tw


func _you_tag(parent: Control, nm: Label, y: float) -> void:
	var tw: float = _text_w(nm)
	var tag := Panel.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Color(0.16, 0.13, 0.05, 1.0)      # 直角不描边, 理由同 _row_band
	var tex := UISkin.nine("chip-frame.png", 7, fb)
	if tex is StyleBoxTexture:
		(tex as StyleBoxTexture).modulate_color = Color(SELF_TAG.r, SELF_TAG.g, SELF_TAG.b, 1.0)
	tag.add_theme_stylebox_override("panel", tex)
	tag.position = Vector2(NAME_X + tw + 8.0, y + (ROW_H - 12.0 - YOU_H) / 2.0)
	tag.size = Vector2(YOU_W, YOU_H)
	parent.add_child(tag)
	var l := Label.new()
	l.text = "你"
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(COL_SELF))
	l.position = Vector2.ZERO
	l.size = Vector2(YOU_W, YOU_H)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_child(l)


## 成绩一格 = 一个**纯数字**, 右对齐到列右沿(与表头列名同一条右沿)。`i` = COL_HEADS 的下标。
## ★2026-10-06 用户「排行榜里的奖杯是？」: 格里不画图标(照 使命召唤手游 / 英雄联盟手游, 列名写在表头)。
## `v < 0` = 这一项没有数据(老快照没带总场次 / 周一上周榜上没有我) ⇒ 「—」, 不编 0。
func _stat_cell(parent: Control, y: float, i: int, v: int, is_self: bool) -> void:
	var cx: float = STAT_X0 + float(i) * STAT_CELL
	var col: String = COL_DIM if v <= 0 else (COL_SELF if is_self else COL_ROW)
	var l := _cell(parent, str(v) if v >= 0 else "—", cx, y, COL_W, 18,
		Color(col), HORIZONTAL_ALIGNMENT_RIGHT)
	l.name = "RowStat%d_%d" % [i, int(y)]


## 行内一格文字(统一字号/行高/垂直居中 —— 手写一遍就会漂)。
func _cell(parent: Control, s: String, x: float, y: float, w: float, fs: int,
		col: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.position = Vector2(x, y)
	l.size = Vector2(w, ROW_H - 12.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = align
	parent.add_child(l)
	return l
