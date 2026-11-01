extends RefCounted
## finals_copy.gd —— 决赛日玩家可见文字的写法(2026-11-01 · 方案书 docs/plans/20261101e-决赛日文案与赛前页.md)。
## 用户 2026-11-01:「切记你的所有语句，一定要按照商业游戏的口吻去来，一定要按照规则来，不要乱乱用这种语句。」
## 参考原文与共同规律: docs/plans/ref/20261101-决赛日文案参考/对照表.md。
##
## ★这里只放「同一种东西全决赛日只有一种写法」的那几样(时长 / 时刻 / 轮次名 / 冠军行), 句子本身仍写在各屏:
##   · 时长(倒计时)一律「54 分 09 秒」「1 小时 05 分 09 秒」「9 秒」—— 不写「4:07」「0:54:59」
##     (用户 2026-10-04:「8:43」读着像 8 点 43 分; 原来同一屏上「2:58」「还有 0:54:59」「54 分 59 秒」三种写法并存)。
##   · 时刻一律「18:00」(设备时区, `phase2_config.local_hhmm`)。
##   · 数字与汉字之间留一个空格(全游戏 144 : 8 的现行写法, 不另起一套)。
## ★写法规矩(门禁 verify_finals_copy ② 逐句扫): 一行一件事, 不用「·」把状态与说明 / 两件事串成一行(要两件事就两行);
##   不口语、不拟人、不教程腔; 不对观众下做不到的指令(「需通过…」「请刷新」); 屏上不出现已经过去的预告时刻。

const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _B := preload("res://scripts/gamedata/bracket.gd")


## 时长(倒计时 / 剩余)。负数当 0。
static func dur(sec: int) -> String:
	var s := maxi(0, sec)
	if s >= 86400:
		return "%d 天 %d 小时" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%d 小时 %02d 分 %02d 秒" % [s / 3600, (s % 3600) / 60, s % 60]
	if s >= 60:
		return "%d 分 %02d 秒" % [s / 60, s % 60]
	return "%d 秒" % s


## 时刻(设备时区)。
static func at(ts: int) -> String:
	return _P2.local_hhmm(ts)


## ★轮次名全决赛日只有这一套(Dota 勇士联赛「四分之一决赛 → 半决赛 → 总决赛」、方案书 20261031c P5):
##   决赛 / 半决赛 / 1/4 决赛 / 1/8 决赛 / 1/16 决赛 —— 从决赛往回数, 与有没有轮空无关。
##   原来四处各叫各的: 对阵图「1/4 决赛」、主菜单格子与全局小条「第 1 轮」(6 人有轮空)、晋级路线「8强」「半决」、仪式「第 1 轮」。
static func round_name(n: int, r: int) -> String:
	var total := _B.rounds_for(n)
	if r < 1 or r > total:
		return ""
	var back := total - r
	if back == 0:
		return "决赛"
	if back == 1:
		return "半决赛"
	return "1/%d 决赛" % (1 << back)


## 拼两段: 汉字挨着数字 / 字母的地方补一个空格(「冠军杯赛」+「1/4 决赛」⇒「冠军杯赛 1/4 决赛」; 「你的」+「半决赛」照旧连写)。
##   ★只用在**我们自己的词**之间(轮次名 / 组名 / 赛名), 不用在玩家名字上(名字原样)。
static func join(a: String, b: String) -> String:
	if a == "" or b == "":
		return a + b
	var la := a.unicode_at(a.length() - 1)
	var fb := b.unicode_at(0)
	if (_cjk(la) and _alnum(fb)) or (_alnum(la) and _cjk(fb)):
		return a + " " + b
	return a + b


static func _cjk(c: int) -> bool:
	return c >= 0x4e00 and c <= 0x9fff


static func _alnum(c: int) -> bool:
	return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)


## 「标签：值」(全角冒号; 商业游戏「参赛人数：24」「冠军奖励：…」那一种)。
static func kv(label: String, value: String) -> String:
	return "%s：%s" % [label, value]


## 名字 + 玩家 ID(「小辉同学 #T000」; 没有 ID 只写名字)。
static func who(name: String, tag: String) -> String:
	return name if tag == "" else "%s %s" % [name, tag]
