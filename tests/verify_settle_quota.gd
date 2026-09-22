extends Node
## verify_settle_quota.gd — A5 的另一半：**结算屏真的把本周配额画出来了**
##
## ★★由来(2026-09-18): 方案书 A5 写的是「主菜单**与结算屏**读数」,
##   落地时只做了主菜单(`MainMenuScene` 的状态行, 由 `verify_mainmenu_layout` ⑦ 守着)。
##   查实 `grep -rn "ranked_used" scripts/scenes/battle/` **零命中** —— 结算屏这半从来没做。
##   ★更糟: 我回填方案书时把「与结算屏」那半句**一起改没了**, 等于用回填动作
##   把未完成的那一半**从账上抹掉** —— 比不回填更危险。
##
## ★判据落在【产品渲染出来的文本】上, 不落在"我喂进去的字段":
##   喂的是**真 GameState**(产品自己读的那个), 断言的是 `_build_reward_chips`
##   真的生成了一块写着「本周场次 / N / 配额」的 chip。
## ★另一半判据同样重要: 换成闯关赛阶段, 这块 chip **必须消失** ——
##   闯关/决赛日的场次不吃这个配额(见 GameState.ranked_used 注释), 那时显示会误导。
##   没有这一条, 「无条件永远显示」也能让上面那条绿。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_settle_quota.tscn --quit-after 600

const HUD := preload("res://scripts/scenes/battle/battle_hud.gd")
const P2C := preload("res://scripts/gamedata/phase2_config.gd")

var _ok := 0
var _fail := 0
var _bak := {}

func _chk(name: String, cond: bool, extra: String = "") -> void:
	if cond:
		_ok += 1
		print("  [PASS] %s%s" % [name, ("  " + extra) if extra != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [name, ("  " + extra) if extra != "" else ""])

## 最小替身 battle：只提供 `_build_reward_chips` 读的那三个字段。
## ★这三个**与被测的事无关**(它们决定"要不要画结算屏"), 喂它们不构成恒真式；
##   被测的那两个量(`week_phase` / `ranked_used`)来自**真 GameState**。
class FakeBattle extends RefCounted:
	var _had_season := true
	var _last_reward := 12
	var _last_was_exhibition := false

## 把 chip 树里所有 Label 的文本拼起来 —— 判据落在**渲染后文本**,
## 不落在"items 数组里有没有那一项"(后者是我塞进去的中间变量)。
func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += str((n as Label).text) + "|"
	for c in n.get_children():
		s += _all_text(c)
	return s

func _ready() -> void:
	await get_tree().process_frame
	print("── A5 另一半: 结算屏配额读数 ──")
	var gs = GameState
	for k in ["week_phase", "ranked_used", "season_wins", "hearts", "season_level"]:
		_bak[k] = gs.get(k)

	var quota: int = int(P2C.RANKED_QUOTA)
	_chk("★分母: 配额常量取得到且 > 0", quota > 0, "RANKED_QUOTA=%d" % quota)

	var hud = HUD.new(FakeBattle.new())

	## ① 积分赛阶段 ⇒ 该出现「本周场次 N / 配额」
	gs.week_phase = "ranked"
	gs.ranked_used = 7
	var c1 = hud._build_reward_chips(gs)
	_chk("① ★分母: 结算屏 chip 真的建出来了(不是 null)", c1 != null)
	if c1 == null:
		_restore(); _done(); return
	var t1 := _all_text(c1)
	_chk("① ★出现「本周场次」这块", t1.contains("本周场次"), t1.substr(0, 90))
	_chk("① ★数值是真读的 ranked_used 与 RANKED_QUOTA(不是写死)",
		t1.contains("7 / %d" % quota), "找 7 / %d" % quota)

	## ①b 换一个 ranked_used 再读一次 —— 挡住"写死 7"这种改法
	gs.ranked_used = 19
	var c1b = hud._build_reward_chips(gs)
	var t1b := _all_text(c1b) if c1b != null else ""
	_chk("①b ★改成 19 之后读数跟着变(挡住写死)", t1b.contains("19 / %d" % quota))

	## ② 「显示不显示」跟着**这一场吃不吃配额**走 —— 与结算记账同一个判据。
	##
	## ★★2026-09-22 换判据。原来这一条是「闯关赛阶段**不显示**这块」,
	##   忠实于方案书 A3(闯关赛不吃积分赛配额) —— 但闯关赛/决赛日的**玩法一行都没写**,
	##   那几天配额照扣 ⇒ 原判据把「**扣了却不显示**」钉在了原地
	##   (memory `fb-gate-can-pin-the-bug-in-place`, 这是同一条判据的第四份副本)。
	## ★「没有这一条, 无条件永远显示也能让①绿」这个用意**保住了**:
	##   下面的表里 `ranked·表演赛` 那一行就是 must-not-show 的对照组。
	for case2 in [["gauntlet", false], ["finals", false], ["rest", false], ["ranked", true]]:
		gs.week_phase = str(case2[0])
		(hud.battle as FakeBattle)._last_was_exhibition = bool(case2[1])
		var c2 = hud._build_reward_chips(gs)
		var t2 := _all_text(c2) if c2 != null else ""
		## 表演赛没有 stake, 一律不显示; 其余看这一场吃不吃配额
		var want2: bool = (not bool(case2[1])) and P2C.phase_uses_ranked_quota(str(case2[0]))
		var tag2: String = str(case2[0]) + (" · 表演赛" if bool(case2[1]) else "")
		_chk("② ★分母(%s): chip 真建出来了(不是 null/空)" % tag2, t2 != "", t2.substr(0, 60))
		_chk("② %s → 「本周场次」%s" % [tag2, "显示" if want2 else "不显示"],
			t2.contains("本周场次") == want2, t2.substr(0, 90))
	(hud.battle as FakeBattle)._last_was_exhibition = false

	_restore()
	_chk("★收尾: GameState 已还原成跑之前的样子",
		str(gs.week_phase) == str(_bak["week_phase"]) and int(gs.ranked_used) == int(_bak["ranked_used"]),
		"week_phase=%s ranked_used=%d" % [str(gs.week_phase), int(gs.ranked_used)])
	_done()

## ★调试台/门禁写 GameState 会落盘污染玩家存档(本项目栽过) ⇒ 跑完必须还原。
func _restore() -> void:
	for k in _bak:
		GameState.set(k, _bak[k])

func _done() -> void:
	print("")
	if _fail == 0:
		print("ALL PASS — 结算屏配额读数 (%d/%d)" % [_ok, _ok])
	else:
		print("FAILED %d 条 (通过 %d)" % [_fail, _ok])
	get_tree().quit(1 if _fail > 0 else 0)
