class_name InvOps
extends RefCounted
## 背包·装备/卸下/卖出 —— 界面那一半(提示 / 选中态 / 存盘 / 重画)。
## ★记账那一半(改背包 / 身上 / 深海币 / 卡池)在 `scripts/gamedata/econ_inv.gd`, 一律经 `GameState.econ({...})` 走记账口
##   (方案书 docs/plans/20261106-装备与深海币服务器记账.md S2): 服务器按流水重放才对得上。这里不许再直接改那些字段
##   (门禁 tools/econ_writer_audit.py)。
## 类内名不变;外部名加 battle.

const EconInv := preload("res://scripts/gamedata/econ_inv.gd")

var host

func _init(b) -> void:
	host = b

func _unequip_at(pet_id: String, cell_idx: int) -> void:
	if not bool(GameState.econ({"op": "unequip", "pid": pet_id, "cell": cell_idx}).get("ok", false)):
		return
	GameState.save()
	host._rebuild()

## 卸下小将第 cell_idx 件装备 → 回背包.
func _unequip_minion_at(lane: String, idx: int, cell_idx: int) -> void:
	if not bool(GameState.econ({"op": "unequip", "lane": lane, "idx": idx, "cell": cell_idx}).get("ok", false)):
		return
	GameState.save()
	host._rebuild()

## 该路首个小将 idx (0统领路首小将=精英)
func _equip_to(pet_id: String, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		host._sel_bench = -1; host._rebuild(); return
	if EconInv.is_leveler(GameState, bench_idx):   # 临时等级器 → 该龟本大轮永久+1级
		var rl: Dictionary = GameState.econ({"op": "leveler", "pid": pet_id, "bench": bench_idx})
		host._sel_bench = -1
		if bool(rl.get("ok", false)):
			host._toast("%s 本大轮等级 +1（当前 +%d）" % [pet_id, GameState.temp_level_bonus(pet_id)])
		host._rebuild(); return
	## ★羁绊赠送件不占容量也不被「已装满」拦; 两种「装不了」(单只 / 全队)分开告诉玩家 —— 判据在 EconInv.equip。
	var r: Dictionary = GameState.econ({"op": "equip", "pid": pet_id, "bench": bench_idx})
	host._sel_bench = -1
	if not _toast_refusal(r):
		GameState.save()
	host._rebuild()

## 小将装备(实时新增): 存 dual_lineup[lane][idx].equips (id共享__minion__进不了persistent_equipped). 战斗端 _spawn_lane_side 读 .equips→_dl_equips 注入.
func _equip_minion(lane: String, idx: int, bench_idx: int) -> void:
	var bench: Array = GameState.persistent_bench
	if bench_idx < 0 or bench_idx >= bench.size():
		host._sel_bench = -1; host._rebuild(); return
	if EconInv.is_leveler(GameState, bench_idx):   # 临时等级器 → 该小将本大轮永久+1级
		if bool(GameState.econ({"op": "leveler", "lane": lane, "idx": idx, "bench": bench_idx}).get("ok", false)):
			host._toast("临时等级器 → 小将(%s路第%d格) 本大轮 +1 级" % [lane, idx + 1])
		host._sel_bench = -1
		host._rebuild(); return
	# 小将与统领【同一套容量规则】(用户 2026-07-27:「单只统领或小将的上限固定为3」)
	var r: Dictionary = GameState.econ({"op": "equip", "lane": lane, "idx": idx, "bench": bench_idx})
	host._sel_bench = -1
	if not _toast_refusal(r) and bool(r.get("ok", false)):
		GameState.save()
	host._rebuild()

## 装不上的两种原因各一句(返回 true = 弹了提示)。
func _toast_refusal(r: Dictionary) -> bool:
	match str(r.get("reason", "")):
		"full":
			host._toast("装备栏已满（%d 件）" % host.P2.UNIT_EQUIP_CAP)
			return true
		"team_full":
			host._toast("全队装备已达上限 %d/%d" % [GameState.team_equipped_count(), GameState.team_equip_cap()])
			return true
	return false

## 一件装备从一只单位直接挪到另一只(拖拽「换人」, 2026-10-22)。判据与理由见 EconInv.move。
func _move_worn(src_lane: String, src_idx: int, cell_idx: int, dst_lane: String, dst_idx: int) -> void:
	var r: Dictionary = GameState.econ({"op": "move", "sl": src_lane, "si": src_idx, "cell": cell_idx,
		"dl": dst_lane, "di": dst_idx})
	if not _toast_refusal(r) and bool(r.get("ok", false)):
		GameState.save()
	host._rebuild()


## 卖价(屏上「卖出 +N」与真价同源: EconInv.sell_value → Phase2Config.sell_value)。
func _sell_value(item: Dictionary) -> int:
	return EconInv.sell_value(item)

func _sell_selected() -> void:
	if host._sel_bench < 0 or host._sel_bench >= GameState.persistent_bench.size():
		return
	## ★羁绊赠送件(圣光护盾)【不能卖】—— 拦截写在 EconInv.sell 里加币之前(界面这里只出那句话)。
	var r: Dictionary = GameState.econ({"op": "sell", "bench": host._sel_bench})
	host._sel_bench = -1
	if str(r.get("reason", "")) == "grant":
		host._toast("羁绊赠送装备不可出售")
		host._rebuild()
		return
	if bool(r.get("ok", false)):
		GameState.save()
	host._rebuild()

# ============================================================================
#  糖果罐（糖果龟被动 · 局外经济行 · 用户2026-07-07设计）
#  · 大轮开始时若锁定统领含糖果龟 → 拥有 1 个糖果罐
#  · 赢一局计数 +1 / 输一局 +4（逆风快攒）· 封顶 30
#  · 随时可打碎领奖: 计数越高档位越高(6档) → 深海币 + 装备(按档费/星) + 临时等级器(按档概率)
#  · 打碎后本大轮消失
#  逻辑全在 GameState: has_candy_jar / candy_jar_count / candy_jar_tier / break_candy_jar
# ============================================================================
