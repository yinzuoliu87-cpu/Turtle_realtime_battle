extends RefCounted

## Phase2DualLane — 双路龟蛋战斗 流程逻辑 (壳, 纯函数, 可单测)
##
## 用 preload 引 (不用 class_name):
##   const DualLane = preload("res://scripts/gamedata/phase2_duallane.gd")
##
## 现状(壳): 分路/路序/胜负判定的【纯逻辑】已搭并可测。还缺(下一步, 多需 UI/战斗渲染):
##   - 分路暗选 UI (玩家把 6 龟拖到上/下路; 这里先 auto_split 均分占位)
##   - 龟蛋基地的【渲染 + 受击】(蛋作为攻击目标, HP 跨路累计)
##   - 终极战场 final 的演出 + 永恒 buff 叠加 (见 phase2_config G 段)
##   - BattleScene 在 mode=="duallane" 时按 current_lane 取 3 龟开打 (已加 guarded 钩子)



## 自动分路 (壳): ids → {top:[...], bottom:[...]}, 奇偶均分.
## 上线版玩家会【暗选】分路 (分路即分死), 这里先均分占位.
static func auto_split(ids: Array) -> Dictionary:
	var top: Array = []
	var bot: Array = []
	for i in range(ids.size()):
		if i % 2 == 0:
			top.append(ids[i])
		else:
			bot.append(ids[i])
	return {"top": top, "bottom": bot}


## 路序: top → bottom → final → done.
static func next_lane(lane: String) -> String:
	match lane:
		"top": return "bottom"
		"bottom": return "final"
		"final": return "done"
	return "done"


## 两路是否都打完 (有记录).
static func lanes_done(lane_results: Dictionary) -> bool:
	return str(lane_results.get("top", "")) != "" and str(lane_results.get("bottom", "")) != ""


## 是否需要终极战场 final: 两路都打完且 1-1 平分.
static func needs_final(lane_results: Dictionary) -> bool:
	if not lanes_done(lane_results):
		return false
	return str(lane_results["top"]) != str(lane_results["bottom"])


## 比赛胜者 ("left"/"right"/"" ). 两路同一方全胜→该方; 1-1→""(需 final); 没打完→"".
static func match_winner(lane_results: Dictionary) -> String:
	if not lanes_done(lane_results):
		return ""
	var t := str(lane_results["top"])
	var b := str(lane_results["bottom"])
	return t if t == b else ""


## 终极战场胜者: final 一场定. 没 final 记录→"".
static func final_winner(lane_results: Dictionary) -> String:
	return str(lane_results.get("final", ""))


## 比分里败方赢了几路(2026-10-12 周日对阵图比分): 两路同一方全胜 ⇒ 2:0 ⇒ 0; 1-1 打了终极 ⇒ 2:1 ⇒ 1;
##   没打完 / 判负收尾(lane_results 空)/ 1-1 而终极没结果 ⇒ -1(不报)。
static func loser_lanes(lane_results: Dictionary) -> int:
	if not lanes_done(lane_results):
		return -1
	if needs_final(lane_results):
		return 1 if final_winner(lane_results) != "" else -1
	return 0 if match_winner(lane_results) != "" else -1


## ★比分代码(2026-10-18 用户「一路碎蛋不就是1：0」): 服务端 `finals_results.loser_lanes` 存的就是它。
##   0 = 2:0 / 1 = 2:1(原义「败方赢了几路」, 胜方默认 2 路)。
##   碎蛋 = 整场当场结束(用户 2026-07-12), 胜方不一定拿满 2 路 ⇒ 另给两个码:
##   SCORE_1_0 = 上路就碎蛋 1:0 / SCORE_1_1 = 1:1 时下路碎蛋 1:1。
##   ★取负数: v0.19.570 及更早的客户端只画 ≥0 的比分 ⇒ 老包看到这两个码是「不画」, 不会画出个假的 2:x。
const SCORE_1_0 := -10
const SCORE_1_1 := -11


## 比分代码; -1 = 不报。`egg_hp` = 结算那一刻的双方蛋血(GameState.egg_hp)。
##   ★碎蛋判据用败方蛋血归零, 不用「只记了一路」: 下路判负收尾后 lane_results 也只剩上路一条, 形状与上路碎蛋相同。
static func score_code(lane_results: Dictionary, egg_hp: Dictionary) -> int:
	var w := overall_winner(lane_results)
	## 恰好一方蛋血为 0 才算碎蛋(双方都是 0 = 蛋血还没初始化, 不是碎蛋)
	var l_broke: bool = float(egg_hp.get("left", 1.0)) <= 0.0
	var r_broke: bool = float(egg_hp.get("right", 1.0)) <= 0.0
	var broke := ""
	if l_broke != r_broke:
		broke = "left" if l_broke else "right"
	if broke == "" or w != "":
		return loser_lanes(lane_results)
	## 碎蛋提前结束: 胜方 = 碎了对面蛋的那一方(碎蛋那一路已记在 lane_results 里)
	var win_side := "right" if broke == "left" else "left"
	var wl := 0
	var ll := 0
	for k in lane_results:
		if str(lane_results[k]) == win_side:
			wl += 1
		else:
			ll += 1
	if wl == 1 and ll == 0:
		return SCORE_1_0
	if wl == 1 and ll == 1:
		return SCORE_1_1
	return -1


## 比分代码 → [胜方路数, 败方路数]; 不认识的码 → []。
static func score_pair(code: int) -> Array:
	match code:
		0: return [2, 0]
		1: return [2, 1]
		SCORE_1_0: return [1, 0]
		SCORE_1_1: return [1, 1]
	return []


## 整局最终胜者: 优先 final, 否则两路全胜方. 无平局(NO_DRAW) → 调用方在 final 强制分出.
static func overall_winner(lane_results: Dictionary) -> String:
	var fin := final_winner(lane_results)
	if fin != "":
		return fin
	return match_winner(lane_results)
