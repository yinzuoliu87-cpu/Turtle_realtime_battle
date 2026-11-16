extends RefCounted
## finals_lineup_push.gd —— 周日决赛: 我此刻在打哪一张表、备战窗开没开 + 每轮一次的「没提交」提醒。
##
## 来历(2026-11-15 · 方案书 20261115e): 用户「这个周日这里，这明明手明明在背包里面调了阵容，为什么在比赛里面的阵容
##   不是这个备赛的呢？」—— 原来只有停在对阵图才推、推了不看回包、文案让人以为用的是背包里现在那套。0.23.4 改成全局层
##   在哪一屏都自动推 + 回执。
## ★2026-11-16 再改(方案书 20261116b, 用户「加个按钮，就加在背包里面…加个确定阵容」): **不再自动推**。
##   交阵容只走背包「确定阵容」→ 选龟页决赛模式换技能 →「提交阵容」(scripts/net/finals_confirm.gd, 服务端 finals_confirm_snapshot:
##   什么时候交都算, 每轮锁定前最后一次为准)。这里只剩: 判「我在哪一张、还有没有下一场、备战窗开没开」(FinalsConfirm 也用),
##   以及全局层每拍问一次「这一轮备战开着、背包有没提交的改动 ⇒ 提醒一次」。
##   客户端原来那条推送链(backend.finals_push_snapshot → supabase.finals_update_snapshot → note_result)整条删了;
##   服务端 finals_update_snapshot 留着给 0.23.4 用。

const _SB := preload("res://scripts/net/supabase.gd")


## 我此刻在打的那一张: 冠军杯赛里有我且没收盘 ⇒ 杯; 否则我那一组(与 BracketMapScene._live_dict 同一条规则)。
static func live_of(group: Dictionary, cup: Dictionary) -> Dictionary:
	if int(cup.get("me", -1)) >= 0 and int(cup.get("size", 0)) > 1 and not bool(cup.get("closed", false)):
		return cup
	return group


## 我在这一张里, 而且还有下一场可备战(组里不止一人、没收盘)。纯函数。
static func seated(lv: Dictionary) -> bool:
	return int(lv.get("me", -1)) >= 0 and int(lv.get("size", 0)) > 1 and not bool(lv.get("closed", false))


## 我在这一张里、备战窗开着(窗的判据只在 phase2_config.finals_shop_open 一处)。纯函数。
static func due(lv: Dictionary, now_local: int) -> bool:
	return seated(lv) and _SB.finals_shop_open_of(lv, now_local)


## 全局层每秒一拍。返回要弹的一句(空 = 不弹): 这一轮备战开着、背包有没提交的改动 ⇒ 每轮提醒一次(FinalsConfirm.remind)。
static func tick(group: Dictionary, cup: Dictionary, _now_unix: int) -> String:
	if not seated(live_of(group, cup)):
		return ""
	return FinalsConfirm.remind(group, cup)
