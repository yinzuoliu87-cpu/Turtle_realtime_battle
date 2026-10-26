extends RefCounted
class_name MenuWeekend
## 主菜单上周末那几件事的调度(2026-10-26 · 方案书 docs/plans/20261026b-周六流程.md §4 A~C / F)。
## 从 MainMenuScene 拆出来(那边有 3000 行上限 `tools/arch_budget.py`): 模板照 dmg_stats_panel.gd —— 构造注入主菜单, 那边只剩几行转调。
##   · 深海币入账动画: 钱包先显示旧值, 菜单落定后飞(scripts/util/coin_fly.gd)
##   · 周末收盘卡: 收盘后第一次进主菜单, 按先后一张张弹(scripts/scenes/week_close_card.gd)
##   · 开始战斗 / 商店被拦: 一张卡说原因, 周末没资格的给「观战」
##   · 周末锁着的模式卡: 第三格写去处, 点卡直达观战
## 用户 10-26:「获得深海币有动画吗，看看商业游戏」「没晋级的你第一次进搞个弹窗？你设计一下，其他你都设计一下」。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")

## 被拦时那张卡的节点名; 正文在 Body0(门禁按名字读屏上那句话)。
const BLOCK_CARD_NAME := "BlockCard"
## 锁着的模式卡第三格
const MODE_WATCH_BOARD := "观看全场赛况 »"
const MODE_WATCH_BRACKET := "观看对阵图 »"
## 等右上角那排滑入落定(`_slide_in` 0.45 秒)再飞, 不然终点还在动。
const SETTLE_SEC := 0.55

var menu                       # MainMenuScene
## 这次进主菜单要飞进钱包的两截(都只管显示, 钱早已在 `meta_deepsea_coins` 里):
##   fly_settle = 上次给玩家看过余额之后新进账的(打完一场 / 糖果罐 …), 菜单落定后从屏幕中央飞;
##   fly_cards  = 这次要弹的收盘卡上的奖励, 点「领取」时从卡上那枚币飞。
var fly_settle := 0
var fly_cards := 0
var queue: Array = []          # 待弹的收盘卡(WeekCloseCard.KIND_*), 按先后


func _init(m) -> void:
	menu = m


## 收盘卡只在玩家真走到的那一屏弹: 门禁 / 冒烟把主菜单挂成子节点时不弹(同首次提示那条); 教程沙盒里不弹。
func cards_enabled() -> bool:
	if menu.get_tree() == null or menu.get_tree().current_scene != menu:
		return false
	return not bool(GameState.get("tutorial_active"))


## 算这次要飞的两截。★在建货币条之前调(钱包要先显示旧值 = 真余额 − withheld())。
func plan(now: int) -> void:
	queue = WeekCloseCard.due(GameState, now) if cards_enabled() else []
	fly_cards = 0
	for k in queue:
		fly_cards += int(WeekCloseCard.spec(str(k), GameState, now).get("coins", 0))
	var gain: int = CoinFly.gain_since_seen(int(GameState.meta_deepsea_coins))
	## 卡上的钱若是这一程里才进账的(同一进程里先看过钱包, 之后才收盘补算), 它已经在 gain 里 ⇒ 不重复扣。
	fly_settle = maxi(0, gain - fly_cards)


func withheld() -> int:
	return fly_settle + fly_cards


## 菜单落定 → 先飞结算那一截 → 再一张张弹收盘卡(每张「领取」各飞一截)→ 都完了出「第一次遇到」提示。
func run() -> void:
	if fly_settle <= 0 and queue.is_empty():
		return
	## ★挂在主菜单身上的 Timer(不是树级计时器): 主菜单先没了它跟着没, 后半截根本不会再跑(tools/tree_timer_audit.py)。
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = SETTLE_SEC
	menu.add_child(t)
	t.start()
	await t.timeout
	t.queue_free()
	if fly_settle > 0:
		var cf := fly(menu.get_viewport_rect().size / 2.0, fly_settle)
		fly_settle = 0
		if cf != null and not queue.is_empty():
			await cf.finished
			if not menu.is_inside_tree():
				return
	next_card()


## 钱包那两个节点(货币条第 0 种 = 深海币)。
func wallet_nodes() -> Array:
	var bar = menu.content_root.get_node_or_null(menu.CURRENCY_BAR_NAME) if menu.content_root != null else null
	if bar == null:
		return [null, null]
	return [bar.get_node_or_null("CurNum0"), bar.get_node_or_null("CurIcon0")]


## 飞一截进钱包: 从 from(画布坐标)飞 amount, 数字从钱包【此刻显示的数】走起。
func fly(from: Vector2, amount: int) -> CoinFly:
	var wn: Array = wallet_nodes()
	var lab: Label = wn[0] as Label
	if lab == null or amount <= 0:
		return null
	var cur: int = int(lab.text) if lab.text.is_valid_int() else int(GameState.meta_deepsea_coins) - amount
	return CoinFly.play(menu, from, lab, wn[1] as Control, cur, amount)


## 弹队列里的下一张收盘卡; 队列空了 ⇒ 出「第一次遇到」那条提示(有卡时被推迟到这里)。
func next_card() -> void:
	if not menu.is_inside_tree():
		return
	if queue.is_empty():
		menu._first_tip(menu._strip_now())
		return
	var kind: String = str(queue.pop_front())
	var now: int = menu._strip_now()
	var d: Dictionary = WeekCloseCard.spec(kind, GameState, now)
	WeekCloseCard.mark_seen(GameState, kind, now)
	GameState.save()
	var coins: int = int(d.get("coins", 0))
	WeekCloseCard.open(menu, d, func(door: String, from_pos: Vector2) -> void:
		fly_cards = maxi(0, fly_cards - coins)
		if _go_door(door):
			return
		## 领取 ⇒ 从卡上那枚币飞进钱包, 飞完再弹下一张; 其它(好的 / 关闭)⇒ 直接下一张。
		## ★卡上的钱不领也照样在账上(收盘补算早已入账): 这里只决定数字怎么走到真值。
		if coins > 0:
			var cf := fly(from_pos if from_pos.x >= 0.0 else menu.get_viewport_rect().size / 2.0, coins)
			if cf != null and not queue.is_empty():
				await cf.finished
		next_card())


## 按去处换场景; 返回 true = 换走了。
func _go_door(door: String) -> bool:
	if door == WeekCloseCard.DOOR_BOARD:
		menu._open_gauntlet_board()
		return true
	if door == WeekCloseCard.DOOR_BRACKET:
		menu._open_bracket_map()
		return true
	return false


## 被拦住时给不给去处、去哪。纯按状态分, 与 `_battle_block_msg` 同一组判据。
func block_door(ts: int) -> Array:
	var ph: String = _P2.phase_at_utc(ts)
	if ph == _P2.PHASE_GAUNTLET and _P2.phase_mode_live(_P2.PHASE_GAUNTLET):
		if not GameState.gauntlet_eligible() or GameState.gauntlet_state() == _P2.GAUNTLET_OUT:
			return [WeekCloseCard.TXT_WATCH, WeekCloseCard.DOOR_BOARD]
		return []
	if ph == _P2.PHASE_FINALS and _P2.phase_mode_live(_P2.PHASE_FINALS):
		if GameState.gauntlet_state() == _P2.GAUNTLET_IN:
			return [WeekCloseCard.TXT_BRACKET, WeekCloseCard.DOOR_BRACKET]
		return [WeekCloseCard.TXT_WATCH, WeekCloseCard.DOOR_BRACKET]
	return []


## 开始战斗 / 商店被拦住时那张卡: 原来是顶部飘 2.6 秒的金字, 没底板、不给去处 ——
##   周末没资格的人读完不知道观战入口在哪(实拍: 藏在「模式卡 → 周赛程页 → 周六格」)。
##   ⇒ 压暗 + 一张卡(与周末收盘卡同一种样子) + 「好的」, 有去处时再给一颗(观战 / 查看对阵图)。
func block_card(msg: String, door: Array) -> void:
	var old: Node = menu.get_node_or_null(BLOCK_CARD_NAME)
	if old != null:
		menu.remove_child(old)   # 先摘下来: 不然新卡同名会被引擎改名, 门禁 / 驱动按名字找不到
		old.queue_free()
	var d := {"node_name": BLOCK_CARD_NAME, "title": "", "body": [msg], "primary": [WeekCloseCard.TXT_OK, WeekCloseCard.DOOR_NONE], "secondary": []}
	if not door.is_empty():
		d["primary"] = door
		d["secondary"] = [WeekCloseCard.TXT_OK, WeekCloseCard.DOOR_NONE]
	WeekCloseCard.open(menu, d, func(dr: String, _from: Vector2) -> void: _go_door(dr))


## 锁着的模式卡点下去去哪: 闯关赛 ⇒ 全场赛况; 决赛日(玩法上线) ⇒ 对阵图; 没锁 / 别的阶段 ⇒ ""(照旧开赛程页)。
func locked_door(now: int) -> String:
	if not menu.mode_card_locked(now):
		return ""
	var ph: String = _P2.phase_at_utc(now)
	if ph == _P2.PHASE_GAUNTLET:
		return menu.WEEK_DOOR_BOARD
	if ph == _P2.PHASE_FINALS and menu._finals_live():
		return menu.WEEK_DOOR_BRACKET
	return ""


## 模式卡被点: 锁着且有去处 ⇒ 直达观战; 否则开本周赛程页。
## ★只在主菜单自己就是 current_scene 时换场景(同登录墙那条): 门禁把主菜单挂成子节点时换场会把宿主整棵树换掉 ⇒ 那时照旧开赛程页。
func on_mode_tap() -> void:
	var door: String = locked_door(menu._strip_now())
	if menu.get_tree() == null or menu.get_tree().current_scene != menu:
		door = ""
	if door == menu.WEEK_DOOR_BOARD:
		menu._open_gauntlet_board()
	elif door == menu.WEEK_DOOR_BRACKET:
		menu._open_bracket_map()
	else:
		menu._open_week_popup()


## ══ 拦截提示的文案(2026-10-26 从 MainMenuScene 搬来; 那边 `_msg_*` 转调这里) ══
## ★★拦截提示的文案放这两个函数里 —— 商店入口与开打入口原来**各写了一份同样的字符串**,
##   改一处漏一处就是「同一个状态两个名字」(memory fb-hand-rolled-copies-drift)。
## ★★2026-09-22: 原文案「等周六闯关赛(开赛观战)」**说的是做不到的事** ——
##   当时闯关赛玩法一行没写(现在 E-A 已落地), 观赛入口更是 F 阶段的事;
##   玩家按字面读会周六打开游戏找闯关赛, 然后发现还是原来那个积分赛。
##   ⇒ 没上线时说**真的会发生的那件事**: 下周一换新的一轮(自然周锚点, UTC 周一 00:00)。
##   玩法上线后自动换回原文案, 不用再记得改这里。
## 这一周后面**还有闯关赛可打吗**? 三个条件缺一不可。
## ★★提示语问的是这个, 不是"开关翻了没有" —— 同样打满配额的两个人,
##   晋级了的那个周六真有东西打, 没晋级的那个要等下周一。跟开关走就会对其中一个说谎。
##
## ★★★2026-09-28 修: 原来第二条问的是 `gauntlet_eligible()`(= `promoted`), 而
##   `promoted` 全仓**只有 `settle_ranked_close()` 一个写入点**, 那个函数开头就
##   「周五 23:00 UTC 之前直接 return」⇒ **周一~周五这一支结构上恒假**。
##   于是 `season_wins=20`(线=5)、配额打满的人, 周一~周五被告知「下周一开新的一轮」——
##   而他周六铁定有 6 场可打。**这个函数自己的头注(上面那两行)写的就是要防这件事,
##   而那件事正发生在它自己身上。**(探针 `tests/_probe_promote_ahead.gd`:
##   「周六闯关赛见」在 `promoted=false` 时七天 0 次出现。)
## ⇒ 收盘前该问的是「**胜场过没过晋级线**」(`GameState.gauntlet_line_reached()`),
##   收盘后 `promoted` 已经是事实 ⇒ 两个**取并集**, 缺一不可:
##     · 只问线 —— 收盘后被清过场次的边角状态会漏(线是 `season_wins`, 不是存档标记);
##     · 只问 `promoted` —— 就是上面那个 bug。
func gauntlet_ahead() -> bool:
	if not _P2.phase_mode_live(_P2.PHASE_GAUNTLET):
		return false                      # 闯关赛玩法还没上线
	if not (GameState.gauntlet_eligible() or GameState.gauntlet_line_reached()):
		return false                      # 收盘算过了没晋级, 而且胜场也没到线
	return _P2.gauntlet_can_play(int(GameState.gauntlet_wins), int(GameState.gauntlet_losses))


## 「周六还有东西打」这半句话怎么说。空串 = 这一周到此为止。
## ★★收盘前后**不是同一句话**, 这一条是诚实度的分界:
##     收盘后 `promoted` 已经算出来了 ⇒ 「你已晋级」是既成事实;
##     收盘前谁也没算过 ⇒ 只能说**已知的那件事**:「胜场过了晋级线」。
##   查实(见 `GameState.gauntlet_line_reached()` 头注三条): 晋级判据里只有胜场、
##   没有名额上限也没有排名截断、`season_wins` 只增不减 ⇒ 过了线就一定会晋级,
##   所以这里敢接「周六闯关赛见」。**将来加了名额/排名线, 要改的是那个函数的头注与这一句。**
## ★2026-10-26 拦截提示全改成完整句子「原因 + 下一次机会在哪」(用户「文案你学习商业游戏的说法」;
##   参考 docs/plans/ref/20261026-周末文案参考.md: 炉石「本次竞技模式即将结束，当前无法入场。」/
##   英雄联盟「这个战队目前没有参加冠军杯赛的资格。」—— 没有一家用「·」串短语)。
##   「下周一重置」→「新一轮积分赛下周二开始」: 周一是休赛日, 下一次能打的是周二。
const MSG_NEXT_WEEK := WeekCloseCard.TXT_NEXT_WEEK

func ahead_tail() -> String:
	if not gauntlet_ahead():
		return ""
	if GameState.gauntlet_eligible():
		return "已晋级闯关赛，周六可继续参赛。"
	return "胜场已达晋级线，可参加周六闯关赛。"


func msg_eliminated() -> String:
	## ⚠ 0 命**不等于**没资格: 5 胜 + 8 负 = 13 场, 完全可能既淘汰又晋级。
	##   原稿的终榜排序是「胜场 > 余命 > 横扫」, 余命只是第二键, 不是门槛。
	var tail: String = ahead_tail()
	if tail != "":
		return "积分赛生命已耗尽。%s" % tail
	return "生命已耗尽，本周无法参加积分赛。闯关赛周六开放观战。%s" % MSG_NEXT_WEEK


func msg_quota_full() -> String:
	var q: int = int(_P2.RANKED_QUOTA)
	var tail: String = ahead_tail()
	if tail != "":
		return "本周积分赛 %d 场已全部完成。%s" % [q, tail]
	return "本周积分赛 %d 场已全部完成，未晋级闯关赛。闯关赛周六开放观战。%s" % [q, MSG_NEXT_WEEK]


## 周六点「开打」被拦住时说什么。返回空串 = 没拦, 可以开。
## ★与 `GameState.gauntlet_can_play()` **共用同一组判据**(`phase2_config.gauntlet_state`),
##   这里只负责把状态翻译成人话 —— 就地再写一遍 `if wins >= 4` 就是同一判据存两份。
##
## ★★★2026-09-28: 这两把锁原来**都不指下一步**, 而同族的每一句都带
##   (「下周一开新的一轮」/「周六闯关赛见」)。周六是这两句唯一的出场日,
##   玩家当天读完就该知道"接下来去哪"：
##     · 没晋级那句里的「积分赛」指周二~周五, **本周已经过去了** ⇒ 必须写清是下周一,
##       而且把门槛写出来(线在 `PROMOTE_WINS`, 不抄数字);
##     · 刚晋级那句只说了"到此为止", **没告诉他明天有决赛日** ⇒ 他周日不来,
##       座位空着、桶还可能卡住。
## `ts` = 调用方手里那一刻(不再自己读钟: 一屏只读一次钟, 见 `_now_ts` 的计数)。
func msg_gauntlet_block(ts: int = 0) -> String:
	if not GameState.gauntlet_eligible():
		## ★2026-10-03 周六实操 S13: 14 胜 / 16 胜的人被告知「打够 11 胜就能来」——
		##   晋级是「胜场过线 **且** 没淘汰」(gauntlet_line_reached), 这句原来不分是哪一条没过。
		if GameState.is_eliminated() and int(GameState.season_wins) >= int(_P2.PROMOTE_WINS):
			return "积分赛生命已耗尽，本周未晋级闯关赛，可观战。%s" % MSG_NEXT_WEEK
		return "闯关赛仅限积分赛 %d 胜晋级的玩家参加。本周未晋级，可观战。%s" % [int(
			_P2.PROMOTE_WINS), MSG_NEXT_WEEK]
	var st: String = GameState.gauntlet_state()
	if st == _P2.GAUNTLET_IN:
		## 明天(周日)几点开打: 按玩家设备时区说(用户 2026-10-26「根据机子的时间去显示正确时间」)。
		return "已晋级决赛日（%s），闯关赛已完成。决赛日%s：%s 开始。" % [_P2.gauntlet_label(
			int(GameState.gauntlet_wins), int(GameState.gauntlet_losses)), _P2.STAGE_GROUP,
			_P2.local_wd_hhmm(_P2.finals_seat_ts(_P2.week_anchor_utc(ts if ts > 0 else menu._now_ts())))]
	if st == _P2.GAUNTLET_OUT:
		return "本周闯关赛已结束（%s）。决赛日开放观战。%s" % [_P2.gauntlet_label(
			int(GameState.gauntlet_wins), int(GameState.gauntlet_losses)), MSG_NEXT_WEEK]
	return ""
