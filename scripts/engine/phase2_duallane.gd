extends RefCounted

## Phase2DualLane — 双路龟蛋战斗 流程逻辑 (壳, 纯函数, 可单测)
##
## 用 preload 引 (不用 class_name):
##   const DualLane = preload("res://scripts/engine/phase2_duallane.gd")
##
## 现状(壳): 分路/路序/胜负判定的【纯逻辑】已搭并可测。还缺(下一步, 多需 UI/战斗渲染):
##   - 分路暗选 UI (玩家把 6 龟拖到上/下路; 这里先 auto_split 均分占位)
##   - 龟蛋基地的【渲染 + 受击】(蛋作为攻击目标, HP 跨路累计)
##   - 终极战场 final 的演出 + 永恒 buff 叠加 (见 phase2_config G 段)
##   - BattleScene 在 mode=="duallane" 时按 current_lane 取 3 龟开打 (已加 guarded 钩子)

const P2 := preload("res://scripts/engine/phase2_config.gd")


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


## 整局最终胜者: 优先 final, 否则两路全胜方. 无平局(NO_DRAW) → 调用方在 final 强制分出.
static func overall_winner(lane_results: Dictionary) -> String:
	var fin := final_winner(lane_results)
	if fin != "":
		return fin
	return match_winner(lane_results)
