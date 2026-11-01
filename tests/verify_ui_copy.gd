extends Node
## verify_ui_copy.gd — 全游戏「玩家看到的字」按商业游戏口吻(方案书 docs/plans/20261101f-全游戏文案按商业口吻.md)
##
## 由来: 用户 2026-11-01:「切记你的所有语句，一定要按照商业游戏的口吻去来，一定要按照规则来，不要乱乱用这种语句。」
##   (此前多次:「不要口语化的我说了多少遍了」「有任何商业游戏这么搞吗」)。规则来源: docs/plans/ref/20261101-决赛日文案参考/对照表.md
##   §8「共同规律」15 条。决赛日那一路由 verify_finals_copy 管; 这一条把同一套判据扩到其余各屏。
##
## ① 判据自检: 改前原句(2026-11-01 走查抓到的)每一句都必须判红, 改后同类句不许误报 —— 判据会 FAIL 的证明。
## ② 走屏: `_ui_copy_screens.gd` 清单里每一屏 × 两种比例(1560×720 手机 / 960×720 iPad), 屏上**看得见的每一句**过禁用模式;
##    版面: 开了 clip_text 的字被截 / 两句字互相压住(按字本身占的范围量, 不按控件框)。
## ③ 源码字面量: `tests/golden/gd_text_snapshot.txt`(text_golden 守着它与源码逐条一致)里玩家文案文件的每一条字面量过同一套
##    禁用模式 —— 只在点了才出的字(提示条 / 弹窗 / 结算副标题)走屏走不到, 这一段兜住。
##    「·」只许出现在登记过的并列名词里(ALLOW_DOT_LIT, 每条写理由): 新写一句带「·」的, 要么改写, 要么来这里登记理由。
##
## 跑法: bash godot-quiet.sh res://tests/verify_ui_copy.tscn --quit-after 20000

const SC := preload("res://tests/_ui_copy_screens.gd")
const TP := preload("res://tests/_finals_text_probe.gd")
const SNAP := "res://tests/golden/gd_text_snapshot.txt"
const SIZES := [["phone", Vector2i(1560, 720)], ["ipad", Vector2i(960, 720)]]

## 禁用模式 [正则, 为什么](对照表 §8 编号)
const BAN := [
	["·", "「·」把状态与说明 / 两件事拼成一行(第 2 条): 一行一件事, 第二件换行、写成整句或「标签：值」"],
	["需通过|请刷新(?!商店)|自动刷新|点开细看|可继续观看|仅可观战|点统领卡查看", "下指令 / 教程腔"],
	["就沿用|不调整就|拿下|输给|去看|打完|省下|照发|看看|还剩|细看|再赢|再输|搞定|咱们|别急|快去|赶紧|哈哈", "口语"],
	["桶|服务端|客户端|后端|缓存|拉取|连线|收盘|待实现|TODO", "内部词 / 开发词"],
	["网络(?!连接后重试)", "网络失败只有一种说法(第 7 条):「无法连接服务器。请检查网络连接后重试。」"],
	["读取中|正在读取", "载入只写「正在载入…」/「载入中」(第 7 条)"],
]

## 屏上「·」只许出现在这些并列名词里(整句匹配)。[正则, 理由]
const ALLOW_DOT := [
	["^(前排|后排|援军|精英) · (近战|远程)$", "小将定位: 两个并列名词(LoL「近战 • 刺客」那种)"],
	["^(近战|远程) · \\S+$", "龟定位: 攻击方式 · 职业, 两个并列名词"],
	["^(被动|攻击|主动) · .+$", "技能类别 · 名字 / 消耗(LoL 技能头「被动 · 名字」)"],
	["^技能 · \\d+ 龟能$", "技能类别 · 消耗"],
	["^\\S+ · (技能|被动|攻击)$", "图鉴状态页来源: 技能名 · 技能类别"],
	["^版本 v\\S+ · 玩家 ID \\S+$", "设置页底栏: 版本与玩家 ID 两个并列字段"],
	["^当前版本 \\S+　·　最低版本 \\S+$", "版本墙: 两个并列字段"],
]

## 源码字面量里允许带「·」的(文件|原文 → 理由)。只认这些; 新加一句带「·」的要在这里写理由。
const ALLOW_DOT_LIT := {
	"scripts/gamedata/minion_codex.gd|前排 · 近战": "小将定位(并列名词)",
	"scripts/gamedata/minion_codex.gd|后排 · 远程": "小将定位(并列名词)",
	"scripts/gamedata/minion_codex.gd|援军 · 远程": "小将定位(并列名词)",
	"scripts/gamedata/minion_codex.gd|精英 · 近战": "小将定位(并列名词)",
	"scripts/scenes/InventoryScene.gd|打碎后随机获得以下奖励之一（每大轮限 1 次）：\\n[ul bullet=·]%s[/ul]": "列表项目符号",
	"scripts/scenes/InventoryScene.gd|· 统领：本大轮出战龟　小将：补位单位\\n· 上路、下路独立作战\\n· 依次点击两个单位，或把一个拖到另一个上：交换位置\\n· 小将卡上【前排 / 后排】：切换近战 / 远程\\n· 右上「站位」：拖动单位设置开战站位\\n· 点击单位：查看属性；点击单位身上的装备：卸下\\n· 选择背包装备后点击单位，或拖动装备到单位：装备\\n· 3 件同名同星装备自动合成升星": "说明面板的项目符号(每行一条)",
	"scripts/scenes/RecordScene.gd|%s · %d 回合": "战绩条目的并列元信息(模式 · 回合数)",
	"scripts/scenes/SettingsScene.gd| · 玩家 ID %s": "设置页底栏: 版本与玩家 ID 两个并列字段",
	"scripts/scenes/TeamSelectScene.gd|测试被动·不屈": "门禁专用的假被动名(只在测试里造)",
	"scripts/scenes/battle/battle_hud.gd|← 手指横滑挑龟(共28只+小将+大师) →   点一格选笔刷 → 点战场连点连摆 · 点已摆的龟→出配置面板": "调试场(开发工具, 正式包不出)",
	"scripts/scenes/battle/battle_hud.gd|点空地=摆(龟/小将) · 点单位=选中配装 · 拖拽=挪位 · 满龟能开→秒放技看效果": "调试场(开发工具, 正式包不出)",
	"scripts/scenes/battle/dual_lane_flow.gd|龟蛋生命  我方 %d  ·  对方 %d": "两个并列读数(我方 / 对方)",
	"scripts/scenes/battle/info_panel.gd|%d层 · %d%%": "层数与数值两个并列读数",
	"scripts/scenes/battle/info_panel.gd|%d层 · %s/%s": "层数与数值两个并列读数",
	"scripts/scenes/battle/info_panel.gd|技能 · %d 龟能": "技能类别 · 消耗",
	"scripts/scenes/battle/info_panel.gd|被动 · ": "技能类别 · 名字",
	"scripts/scenes/codex/detail_views.gd|主动 · 龟能 %d": "技能类别 · 消耗(LoL 技能头写名字 + 消耗)",
	"scripts/scenes/codex/detail_views.gd|攻击 · %s": "技能类别 · 名字",
	"scripts/scenes/codex/detail_views.gd|被动 · %s": "技能类别 · 名字",
	"scripts/scenes/codex/status_page.gd|%s · 技能": "来源: 龟名 · 技能类别",
	"scripts/scenes/codex/status_page.gd|%s · 被动": "来源: 龟名 · 技能类别",
	"scripts/scenes/version_wall.gd|当前版本 %s　·　最低版本 %s": "两个并列字段",
}

## 只在开发包 / 内测包里出现的字(正式包不建这些控件): 整条不扫。文件|原文 → 理由
const DEV_ONLY_LIT := {
	"scripts/gamedata/phase2_config.gd| · 不联网": "开发包时间穿越角标(正式包不出)",
	"scripts/gamedata/phase2_config.gd|%s · 服务端时间 周%s %02d:%02d UTC": "内测服角标(正式包不出)",
	"scripts/gamedata/phase2_config.gd|测试时间 周%s %02d:%02d UTC": "开发包时间穿越角标(正式包不出)",
}

## ③ 不扫的文件: 开发工具 / 内部诊断(玩家看不到) / 技能装备羁绊说明(有自己的 LoL 体例门禁 copy_lol_style_lint, 羁绊档位说明里的「·」
##   由图鉴 synergy_view 拆成一条一行显示) / 决赛日(verify_finals_copy 管)。
const SKIP_FILE := "(shot_diff|debug|vfx_lab|vfxlab|_probe|^tests/|tools/|sim_driver|autopilot|referee/|map_edit|layout_editor|review_|" \
	+ "eqdemo|demo_|time_travel|selfcheck|det_scenarios|copy_rules|arena_theme|remote_pool|error_reporter|replay_recorder|" \
	+ "bracket|finals_|champion|premiere|menu_finals_day|skill_text|phase2_types|equip_tier_labels|glossary|status_sources|" \
	+ "chest_loot|skill_forms|battle_vfx|fortune_system|rainbow_system|trainer_system|incense_stone_system|battle_spawn)"

## ★改前原句(2026-11-01 全游戏走查 + 初筛), 每一句都必须被 BAN 判红
const OLD := ["闯关赛 2-1 · 晋级还需 2 胜 / 剩余 2 负", "4-1 · 已晋级决赛日", "1-3 · 已出局", "已截止 · 停止匹配",
	"生命已耗尽 · 下周二可参加", "积分赛生命耗尽 · 本周无法参加", "本大轮阵容已锁定 · 点统领卡查看详情、更换技能",
	"已截止 · 截止前 5 分钟停止匹配", "可装备 0 件  ·  Lv2 可装备 2 件", "「木剑」已失效 · 请刷新", "已锁定 · 下场战斗后不刷新",
	"深海币不足 · 「木剑」需要 3，还差 1", "购买成功 · 「木剑」已放入背包", "已锁定 · 点击解锁", "选择单位 · 本大轮等级 +1",
	"糖果罐 · 第 3 档奖励", "砍伐经验 80/80 · 可最终进化", "练习赛 · 不计入赛季进度", "小组赛 · 不消耗生命 · 结果于下轮开播时公布",
	"生命已耗尽 · 本大轮已出局", "切磋 · 不计入赛季进度", "忍者龟 · 点开细看", "羁绊已激活 · 点击查看详情",
	"本场由服务器判定 · 退出不影响结果", "上一局判负 · 版本已更新", "备战阶段 · 结束后开赛", "积分赛 · 胜利",
	"火山形态 · 还剩 3.2 秒", "潜伏中 · 不会被选为目标", "技能 · 7 选 1", "已绑定 · lisa@example.com",
	"未绑定邮箱 · 更换设备后无法恢复进度", "2~12 个字 · 显示于排行榜", "已拉黑 · 昵称显示为默认昵称", "本地记录 · 非实时排名",
	"本周闯关赛 · 24 人 · 30 场 · 晋级 5 · 出局 3", "再赢 2 场晋级决赛日", "再输 2 场出局", "网络异常，请稍后再试",
	"无法连接服务器，请检查网络", "提交失败，请检查网络后重试", "删除失败：网络不可用，账号未删除", "正在读取本周排行…",
	"读取中", "每 15 秒自动刷新", "休赛日 · 不开放对战", "处理存档冲突 · 云端同步已暂停"]
## 改后同类句不许误报
const NEW_OK := ["胜场 2/4　负场 1/3", "已晋级决赛日（4-1）", "已出局（1-3）", "已截止", "生命已耗尽，下周二可参加",
	"本大轮阵容已锁定\n点击统领卡可查看详情、更换技能", "已截止：截止前 5 分钟停止匹配", "可装备 0 件（Lv2：2 件）",
	"「木剑」已失效，请刷新商店", "已锁定商品，下场战斗后不刷新", "深海币不足，购买「木剑」还差 1", "购买成功，「木剑」已放入背包",
	"已锁定：下场战斗后不刷新", "选择单位：本大轮等级 +1", "糖果罐第 3 档奖励", "砍伐经验 80/80（可最终进化）",
	"练习赛不计入赛季进度。", "小组赛不消耗生命，结果于下轮开播时公布。", "忍者龟\n点击查看详情", "羁绊已激活\n点击查看详情",
	"版本已更新，上一局判负", "备战阶段结束后开赛", "积分赛：胜利", "火山形态：剩余 3.2 秒", "潜伏中：无法被选为目标",
	"技能（7 选 1）", "已绑定：lisa@example.com", "未绑定邮箱", "2~12 个字，显示于排行榜", "已拉黑，该玩家昵称显示为默认昵称",
	"本周闯关赛进行中。24 人参赛，共 30 场对局，晋级 5 人，出局 3 人。", "再胜 2 场晋级决赛日", "再负 2 场出局",
	"无法连接服务器。请检查网络连接后重试。", "提交失败。请检查网络连接后重试。", "删除失败：无法连接服务器，账号未删除",
	"正在载入…", "载入中", "前排 · 近战", "被动 · 不屈", "主动 · 龟能 80", "版本 v0.22.6 · 玩家 ID #3GJ77N",
	"云端同步已暂停，请处理存档冲突"]

var _n := 0
var _fail := 0
var _bak := {}
var _seen_screens := 0
var _seen_items := 0
var _bad: Dictionary = {}                 # 句子 → 第一次见到的屏
var _lay: Dictionary = {}                 # 版面问题 → 屏


func _ok(nm: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  %s %s%s" % ["[PASS]" if cond else "[FAIL]", nm, ("   " + detail) if detail != "" else ""])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	print("=== 全游戏文案(商业口吻) ===")
	for k in SC.KEYS:
		_bak[k] = GameState.get(k)
	GameState.test_mode = true
	_t_judge_self()
	await _t_screens()
	_t_literals()
	_done()


# ══════════════════════════════ 判据 ══════════════════════════════

## 一句话踩了哪一条禁用模式(""= 干净)。`dot_ok` = 这一句的「·」已登记为并列名词。
static func banned(t: String, dot_ok: bool = false) -> String:
	for b in BAN:
		if dot_ok and str(b[0]) == "·":
			continue
		var re := RegEx.new()
		re.compile(str(b[0]))
		if re.search(t) != null:
			return str(b[1])
	return ""


## 屏上那一句的「·」是不是登记过的并列名词。
static func dot_allowed(t: String) -> bool:
	for a in ALLOW_DOT:
		var re := RegEx.new()
		re.compile(str(a[0]))
		if re.search(t) != null:
			return true
	return false


func _t_judge_self() -> void:
	print("── ① 判据自检(改前原句必须判红, 改后同类句不许误报) ──")
	var miss: Array = []
	for t in OLD:
		if banned(str(t), dot_allowed(str(t))) == "":
			miss.append(t)
	_ok("★改前原句 %d 句全部判红" % OLD.size(), miss.is_empty() and OLD.size() >= 40, str(miss))
	var fp: Array = []
	for t in NEW_OK:
		var why := banned(str(t), dot_allowed(str(t)))
		if why != "":
			fp.append("%s ← %s" % [t, why])
	_ok("改后同类句 %d 句不误报" % NEW_OK.size(), fp.is_empty(), str(fp))


# ══════════════════════════════ ② 走屏 ══════════════════════════════

func _t_screens() -> void:
	## UI_COPY_ONLY=a,b: 只走这几屏(改坏验证时省时间; 门禁本身不设)
	var only := OS.get_environment("UI_COPY_ONLY")
	var want: Array = SC.names() if only == "" else Array(only.split(","))
	print("── ② 走屏: %d 屏 × %d 种比例 ──" % [want.size(), SIZES.size()])
	for sz in SIZES:
		get_window().size = sz[1]
		for _i in range(3):
			await get_tree().process_frame
		for nm in want:
			SC.setup(str(nm))
			var n: Node = SC.make(str(nm))
			add_child(n)
			await SC.settle(1.6)
			await SC.post(str(nm), n)
			## 切页签会重播列表 / 详情滑入(延迟 0.25 + 0.42 秒, 带回弹): 等 0.5 秒量到的是回弹到一半的位置
			await SC.settle(1.2)
			var vp := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
			var items := TP.collect(get_tree().root, vp)
			var tag := "%s/%s" % [nm, sz[0]]
			_seen_screens += 1
			for it in items:
				_seen_items += 1
				var t := str(it["text"])
				var why := banned(t, dot_allowed(t))
				if why != "" and not _bad.has(t):
					_bad[t] = "%s ‹%s› %s" % [tag, str(it["path"]).get_file(), why]
			for li in SC.layout_issues(get_tree().root, items, vp):
				if str(li).begins_with("出屏"):
					continue          # 滚动框里半截露出的行 / 入场滑入中的键: 不当版面错(滚动裁剪由采集器的裁剪框量)
				if not _lay.has(str(li)):
					_lay[str(li)] = tag
			SC.drop(n)
			for _i in range(3):
				await get_tree().process_frame
	SC.teardown()
	_ok("★分母: 走了 %d 屏、%d 句" % [_seen_screens, _seen_items],
		_seen_screens == want.size() * SIZES.size() and want.size() == SC.names().size() and _seen_items >= 30 * _seen_screens / 2)
	var lines: Array = []
	for t in _bad:
		lines.append("「%s」%s" % [str(t).replace("\n", "⏎"), _bad[t]])
	_ok("② 各屏没有一句踩禁用模式", lines.is_empty(), "\n      " + "\n      ".join(PackedStringArray(lines)))
	var ll: Array = []
	for t in _lay:
		ll.append("%s  @%s" % [t, _lay[t]])
	_ok("② 版面: 没有被截的字、没有两句互相压住", ll.is_empty(), "\n      " + "\n      ".join(PackedStringArray(ll)))


# ══════════════════════════════ ③ 源码字面量 ══════════════════════════════

func _t_literals() -> void:
	print("── ③ 源码字面量(%s) ──" % SNAP.get_file())
	var f := FileAccess.open(SNAP, FileAccess.READ)
	_ok("★分母: 快照文件在", f != null)
	if f == null:
		return
	var skip := RegEx.new()
	skip.compile("(?i)" + SKIP_FILE)
	var n_all := 0
	var n_seen := 0
	var n_dot_ok := 0
	var bad: Array = []
	var stale: Array = ALLOW_DOT_LIT.keys().duplicate() + DEV_ONLY_LIT.keys()
	while not f.eof_reached():
		var line := f.get_line()
		var parts := line.split("|", true, 2)
		if parts.size() != 3:
			continue
		n_all += 1
		var path := str(parts[0])
		var txt := str(parts[2])
		var key := "%s|%s" % [path, txt]
		stale.erase(key)
		if skip.search(path) != null or DEV_ONLY_LIT.has(key):
			continue
		n_seen += 1
		var dot_ok := ALLOW_DOT_LIT.has(key)
		if dot_ok:
			n_dot_ok += 1
		var why := banned(txt, dot_ok)
		if why != "":
			bad.append("%s「%s」← %s" % [path, txt.left(60), why])
	_ok("★分母: 快照 %d 条, 扫了玩家文案文件里的 %d 条(登记过的并列「·」%d 条)" % [n_all, n_seen, n_dot_ok],
		n_all >= 2000 and n_seen >= 1000 and n_dot_ok == ALLOW_DOT_LIT.size())
	_ok("③ 玩家文案字面量没有一条踩禁用模式", bad.is_empty(), "\n      " + "\n      ".join(PackedStringArray(bad)))
	_ok("③ 白名单里没有已经不存在的条目(改掉了就从白名单删)", stale.is_empty(), str(stale))


func _done() -> void:
	SC.teardown()
	for k in _bak.keys():
		GameState.set(k, _bak[k])
	print("  (用了 %d 帧)" % Engine.get_process_frames())
	if _fail == 0:
		print("ALL PASS (%d)" % _n)
	else:
		print("FAILED %d / %d" % [_fail, _n])
	get_tree().quit(1 if _fail > 0 else 0)
