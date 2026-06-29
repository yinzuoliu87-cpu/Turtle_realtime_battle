extends Node

## GameState — 跨场景状态 (Autoload 单例)

const SAVE_PATH := "user://savegame.json"

# ─── 当前对局 ────────────────────────────────────────────────
var left_team: Array[String] = []
var right_team: Array[String] = []
# 站位 slotKey ("front-0".."back-2"), 与 *_team 平行. 玩家 TeamSelect 摆放结果; 空=用默认前排
var left_slots: Array[String] = []
var right_slots: Array[String] = []
## 玩家每只龟的 5选3 技能选择 {pet_id → [idx,...]}; TeamSelect 写, BattleScene 读 (空=用 defaultSkills)
var loadouts: Dictionary = {}

## "single"  — 自定义单局, 战斗结束回选龟
## "dungeon" — 闯关模式, 战斗结束按胜负进下一关 / 回主菜单
var mode: String = "single"

## 新手教程标记 (1:1 PoC scene data tutorial:true) — 与 mode 正交; mode 仍是玩家可控模式(single)。
##   BattleScene._ready 读取后立即清空 (一次性消费, 不污染下一局)。
var tutorial: bool = false

## 本局战斗规则 (规则之日) — 7 项之一 (烈焰/雷暴/铁壁/狂暴/装备/下雨/正常) 或 "" = 无规则.
## TeamSelect 选规则后写入, BattleScene._ready 读取后清空 (PoC scene.start data.rule 等价).
var battle_rule: String = ""

## 上一场战斗结果 (BattleScene._show_result 写, BattleEndScene 读) — 跨场景传 playerStats 等
var last_battle_result: Dictionary = {}

# ─── 局内经济 (用户 v0.9.9; 不持久化, 每场战斗重置) ─────────────
## 玩家(左队)局内商店钱包 — 1:1 PoC this.coins: 每场重置成 0 (dungeon 跨关携带), 不落盘。
## (持久 meta 累计走下方 coins; 二者分离, 对齐 PoC this.coins ↔ localStorage petState.coins。)
var battle_coins: int = 0
## 野生敌方 AI 钱包 (像玩家一样攒币, 深海/Boss/测试模式恒 0).
var enemy_coins: int = 0
## dungeon 跨关结余: 上关胜利时存本关 battle_coins, 下关 reset 时注入 (1:1 PoC _carryCoins, 纯内存)。
var dungeon_carry_coins: int = 0

# ─── 二阶段 双路龟蛋战斗 (V3.2, 壳, 不持久化, 每局重置) ─────────
## 分路: 玩家把 6 龟暗选分到上/下路 (分路即分死). {"top":[pet_id...], "bottom":[...]}
var lane_assign: Dictionary = {"top": [], "bottom": []}
var enemy_lane_assign: Dictionary = {"top": [], "bottom": []}
## 当前打到哪一路 ("top"→"bottom"→"final" 终极战场)
var current_lane: String = "top"
## 龟蛋基地 HP {"left": int, "right": int} — egg_hp(均等级) 初始化
var egg_hp: Dictionary = {"left": 0, "right": 0}
var egg_hp_max: Dictionary = {"left": 0, "right": 0}
## 攻蛋伤害跨场累计 (上路没打死蛋, 下路接着扣) — 已含在 egg_hp 里, 这里留路输赢记录
var lane_results: Dictionary = {}   # {"top": "left"/"right"/"egg", ...} 哪方赢了该路
## 备战席库存 (装备 id+星级) [{id, star}...], 容量 BENCH_CAP
var bench_inventory: Array = []
## 敌方 AI 专属备战席 (与玩家 bench_inventory 隔离; 装不下的件留这里, 下回合开槽再装).
##   ai_dual_shop 临时把它换进 bench_inventory 跑玩家管线再换回 → 复用 buy/equip/merge 又不污染玩家席。
var ai_bench_inventory: Array = []
## 玩家每龟身上装备 {pet_id → [{id, star}...]}; right 队的键带 "right::" 前缀(p2eq_key)与玩家隔离。
var equipped_p2: Dictionary = {}
var last_merges: Array = []   # try_merge_all 最近一次合成详情(UI 飘字读)
## 跨路幸存者 (待命回复后, 终极战场带血汇合用) {"left":[{id,hp,maxHp,level}...], "right":[...]}.
## 每路打完 snapshot 存活统领(已回复30%已损), 累计; 终极战场从此重建带血.
var dual_survivors: Dictionary = {"left": [], "right": []}
## 整局累计开店次数 (跨上/下/终极) — 商店费用概率档位由它推进 (Phase2Config.stage_for_shop_visit)
var dual_shop_visits: int = 0
## 局内等级 (TFT风, 1-10, 每局重置): 绑龟蛋HP + 商店概率档 + 小将等级. 见 docs/design/PHASE2-LEVEL-DESIGN.md.
var dual_level: Dictionary = {"left": 1, "right": 1}
var dual_avg_level: Dictionary = {"left": 1, "right": 1}   # 选龟时队伍平均等级(固定不随局内升级涨); 深海小将等级用此
var dual_xp: Dictionary = {"left": 0, "right": 0}
## 整局首回合已发被动XP? (TFT风: 第1回合在 Lv1 开打, 被动XP从第2回合起累计 → 不在玩家行动前就跳到 Lv2).
##   每路是独立 BattleScene(turn 各自从1起), 故此旗标必须按【整局】计(reset_dual_lane 重置), 不能按 turn==1.
var dual_passive_xp_started: bool = false
var dual_coins: Dictionary = {"left": 0, "right": 0}   # 双路局内币 (跨上/下/终极持续, 区别于按场重置的 battle_coins)
## PvP 控制方 (见 docs/design/PHASE2-PVP-DESIGN.md): 每方 local/ai/remote. 单机=left本地打右AI.
var side_controllers: Dictionary = {"left": "local", "right": "ai"}
## 战斗随机种子 (权威定+下发; 收口战斗内随机→可复现/回放). 0=未设(用系统随机).
var battle_seed: int = 0

const _DualLane := preload("res://scripts/engine/phase2_duallane.gd")
const _P2 := preload("res://scripts/engine/phase2_config.gd")
const _Equip := preload("res://scripts/engine/phase2_equip.gd")
## 匹配到的对手资料 (野生=模拟真人 / 在线=真人) {name, avatar(pet_id), id}. 匹配动画写, 双路读显.
var dual_opponent: Dictionary = {}
## 新商店货架 (当前掷出的装备, 买掉的位置=null). 局内等级决定费用概率档.
var dual_shop_offer: Array = []
var dual_shop_locked: bool = false   # TFT 式锁店: true → 每回合免费换货跳过(锁住看中的货架)
var dual_shop_refresh_n: Dictionary = {"left": 0, "right": 0}   # 同回合手动刷新次数 → 刷新费递增(每大回合 grant_dual_round 重置归0)
var _dual_shop_rng := RandomNumberGenerator.new()

## 双路状态重置 (开新局调).
var dual_ghost: Dictionary = {}   # 本局对手快照 (后端 find_opponent 给; 局内临时, reset_dual_lane 清). 空 = 现场随机老路 (兜底)
func reset_dual_lane() -> void:
	lane_assign = {"top": [], "bottom": []}
	enemy_lane_assign = {"top": [], "bottom": []}
	current_lane = "top"
	egg_hp = {"left": 0, "right": 0}
	egg_hp_max = {"left": 0, "right": 0}
	lane_results = {}
	bench_inventory = []
	ai_bench_inventory = []
	equipped_p2 = {}
	dual_shop_visits = 0
	dual_level = {"left": 1, "right": 1}
	dual_avg_level = {"left": 1, "right": 1}
	dual_xp = {"left": 0, "right": 0}
	dual_passive_xp_started = false
	dual_coins = {"left": 0, "right": 0}
	dual_survivors = {"left": [], "right": []}
	dual_shop_offer = []
	dual_ghost = {}
	dual_shop_locked = false
	side_controllers = {"left": "local", "right": "ai"}
	battle_seed = 0

## 一组龟 id 的平均等级 (四舍五入, 至少1). 双路小将等级 / 起始局内等级 / 龟蛋HP 用 (= 选龟平均等级).
func team_avg_level(ids: Array) -> int:
	if ids.is_empty():
		return 1
	var s := 0
	for id in ids:
		s += get_pet_level(str(id))
	return maxi(1, int(round(float(s) / float(ids.size()))))


## 开局布置双路 (壳): 6 龟均分上/下路 + 按均等级初始化龟蛋 HP.
## 上线版玩家会暗选分路, 这里 auto_split 占位; player_avg_lv/enemy_avg_lv 给龟蛋 HP 公式.
func setup_dual_lane(player_ids: Array, enemy_ids: Array, start_level: int = 1) -> void:
	reset_dual_lane()
	mode = "duallane"
	lane_assign = _DualLane.auto_split(player_ids)
	enemy_lane_assign = _DualLane.auto_split(enemy_ids)
	# 龟蛋HP 由局内等级定 (TFT风); 开局等级 start_level (默认1→1050).
	dual_level = {"left": start_level, "right": start_level}
	dual_avg_level = {"left": start_level, "right": start_level}   # 修(审计A4#2): 原漏设 → 冒烟/测试路径小将恒Lv1
	var hp: int = _P2.egg_hp(start_level)
	egg_hp = {"left": hp, "right": hp}
	egg_hp_max = {"left": hp, "right": hp}
	current_lane = "top"

## 加 XP, 自动连续升级; 每升一级强化龟蛋(用户定: max+50且current+50, 累计伤害保留). 返回升的级数.
func add_xp(side: String, n: int) -> int:
	if n <= 0 or int(dual_level.get(side, 1)) >= _P2.MAX_LEVEL:
		return 0
	dual_xp[side] = int(dual_xp.get(side, 0)) + n
	var gained := 0
	while int(dual_level[side]) < _P2.MAX_LEVEL and int(dual_xp[side]) >= _P2.xp_to_next(int(dual_level[side])):
		dual_xp[side] = int(dual_xp[side]) - _P2.xp_to_next(int(dual_level[side]))
		dual_level[side] = int(dual_level[side]) + 1
		_reinforce_egg(side)
		gained += 1
	if int(dual_level[side]) >= _P2.MAX_LEVEL:
		dual_xp[side] = 0
	return gained

## 升级强化龟蛋: max 升到新等级对应值, current 同步 +delta (补蛋血), 累计伤害(current<max部分)保留.
func _reinforce_egg(side: String) -> void:
	# 修(审计A4#1): 蛋max基线=队伍均级(dual_avg_level), 每局内升1级再叠1档。原直接用 dual_level(从1起)
	#   → 均级>1时升到2级算出的 new_max < egg_hp(均级) = 蛋max缩水。现 max 取不降 + delta 夹0。
	var eff_lv: int = int(dual_avg_level.get(side, 1)) + maxi(0, int(dual_level.get(side, 1)) - 1)
	var new_max: int = maxi(_P2.egg_hp(eff_lv), int(egg_hp_max.get(side, 0)))   # 不降
	var delta: int = maxi(0, new_max - int(egg_hp_max.get(side, new_max)))
	egg_hp_max[side] = new_max
	egg_hp[side] = mini(new_max, int(egg_hp.get(side, 0)) + delta)

## 买经验 (花局内币). 成功返回 true.
func buy_xp(side: String) -> bool:
	if int(dual_coins.get(side, 0)) < _P2.BUY_XP_COST or int(dual_level.get(side, 1)) >= _P2.MAX_LEVEL:
		return false
	dual_coins[side] = int(dual_coins[side]) - _P2.BUY_XP_COST
	add_xp(side, _P2.BUY_XP_AMOUNT)
	return true

## 每大回合双路结算: 双方各 +被动XP (战斗循环每回合调).
## TFT 风: 整局【第1回合】在 Lv1 开打, 被动XP从第2回合起累计 — 否则第1回合行动前就 +PASSIVE_XP 跳 Lv2
##   (xp_to_next(1)=2=PASSIVE_XP → 首回合即升级), 用户报"一开始就是2级=搞错了"。
## V2 阶段1: 局内每回合 +币/利息 已删 (经济挪局外背包商店). dual_coins 字段保留、产出口断 → 余额恒0、读点安全置灰。
func grant_dual_round() -> void:
	var grant_xp: bool = dual_passive_xp_started   # 首回合(旗标false)不发被动XP → 留在 Lv1
	dual_passive_xp_started = true
	for s in ["left", "right"]:
		if grant_xp:
			add_xp(s, _P2.PASSIVE_XP)   # V2-TODO 阶段2: "每回合+2" 改 "每场+2"(局外结算触发)

# ─── 新商店 (局内等级→费用概率档, 局内币购买; 替代老战中商店) ───
## 掷新货架 (按 side 的局内等级费用概率). battle_seed≠0 时可复现(PvP一致).
func roll_shop_offer(side: String = "left") -> void:
	if battle_seed != 0:
		_dual_shop_rng.seed = battle_seed + dual_shop_visits
	else:
		_dual_shop_rng.randomize()
	var lvl: int = int(dual_level.get(side, 1))
	dual_shop_offer = _Equip.roll_shop(DataRegistry.phase2_equipment, lvl, _P2.SMALL_SHOP_SLOTS, _dual_shop_rng)
	dual_shop_visits += 1

## 买货架第 idx 件 → 进备战席(bench_inventory, {id,star:1}), 扣局内币. 成功 true.
func buy_shop_item(idx: int, side: String = "left") -> bool:
	if idx < 0 or idx >= dual_shop_offer.size():
		return false
	var it = dual_shop_offer[idx]
	if not (it is Dictionary):
		return false
	var cost: int = int(it.get("cost", 1))
	if int(dual_coins.get(side, 0)) < cost:
		return false
	var item_id := str(it.get("id", ""))
	# 备战席满 (BENCH_CAP) 默认 block; 但若【买进这张会立刻凑成三合一】(本 side 龟身+席已有 ≥2 件同 id+1星 →
	#   第3张合1, 净占用 -1 → 买完反而少占一格), 则放行 (1:1 云顶: 满席仍能买能合的牌)。
	if bench_inventory.size() >= _P2.BENCH_CAP and not _buy_would_merge(item_id, 1, side):
		return false
	dual_coins[side] = int(dual_coins[side]) - cost
	bench_inventory.append({"id": item_id, "star": 1})
	# 三合一升星: 战中由 BattleScene._battle_merge_p2eq(扫龟身_p2_equips+备战席,可见) 处理;
	#   持久流(大地图)由 equip_to_turtle/unequip 的 try_merge_all 处理。此处只入席。
	dual_shop_offer[idx] = null
	return true

## 满席凑合一预判: 买入一张 (id, star) 后是否会立刻触发三合一 (= 本 side 已有 ≥2 件同 id+同星 → 第3张合1).
##   数【备战席 + 本 side 龟身 equipped_p2 (left=裸键 / right="right::"前缀键)】里同 id+star 的件数, ≥(MERGE_COUNT-1)=2 即放行。
##   满星件不可再合 → 不放行 (避免满席买进无法合成的满星件溢出)。
func _buy_would_merge(item_id: String, star: int, side: String) -> bool:
	if star >= _Equip.MAX_STAR:
		return false
	var have := 0
	for b in bench_inventory:
		if b is Dictionary and str(b.get("id", "")) == item_id and int(b.get("star", 1)) == star:
			have += 1
	var _is_right := (side == "right")
	for pet in equipped_p2:
		if str(pet).begins_with(_P2EQ_RIGHT_PREFIX) != _is_right:
			continue   # 只数本 side 的龟身件 (命名空间隔离, 同 try_merge_all)
		for it in equipped_p2[pet]:
			if it is Dictionary and str(it.get("id", "")) == item_id and int(it.get("star", 1)) == star:
				have += 1
	return have >= _Equip.MERGE_COUNT - 1

## 备战席第 idx 件【出售】退币 (仅玩家用; AI 不出售). 售价 = 该装备 cost × 星级 (1星=cost / 2星=2×cost / 3星=3×cost,
##   ≈ 凑成该星所付总买价的折算: 2星耗3件买价但只退2×, 略低于买价, 贴合云顶"卖略亏"). 退到 dual_coins[side]. 成功 true.
##   消耗品/单体buff(字符串 bench 项, 如口哨/糖果罐) 没有 cost 概念 → 不可售, 返回 false。
func sell_bench_item(idx: int, side: String = "left") -> bool:
	if idx < 0 or idx >= bench_inventory.size():
		return false
	var b = bench_inventory[idx]
	if not (b is Dictionary):
		return false   # phase1 字符串项 (口哨/糖果罐/消耗品) 不可售
	dual_coins[side] = int(dual_coins.get(side, 0)) + sell_value(str(b.get("id", "")), int(b.get("star", 1)))
	bench_inventory.remove_at(idx)
	return true

## 装备出售价 = floor(cost × star × 0.8) (cost 取 phase2 装备定义; 缺失则按 1; 至少退 1).
##   ×0.8 = 云顶式"卖略亏": 单件买立刻卖也有 ~20% 损耗 (旧 cost×star = 全额退/零损耗, 已废). 集中一处便于调平衡.
func sell_value(item_id: String, star: int) -> int:
	var def: Dictionary = DataRegistry.phase2_equipment_by_id.get(item_id, {})
	var cost: int = int(def.get("cost", 1)) if def is Dictionary else 1
	return maxi(1, int(floor(maxi(1, cost) * maxi(1, star) * 0.8)))

## 三合一升星 (TFT风自动合成): 备战席里 3 件同id同星 → 合成 1 件高一星, 反复直到无可合.
##   3件1星→1件2星; 再3件2星→1件3星(满星). 返回合成发生的次数.
func try_merge_bench() -> int:
	var merges := 0
	var changed := true
	while changed:
		changed = false
		var groups: Dictionary = {}   # "id|star" → [备战席索引...]
		for i in range(bench_inventory.size()):
			var b: Dictionary = bench_inventory[i]
			var k := "%s|%d" % [str(b.get("id", "")), int(b.get("star", 1))]
			if not groups.has(k):
				groups[k] = []
			(groups[k] as Array).append(i)
		for k in groups:
			var idxs: Array = groups[k]
			var star: int = int(str(k).split("|")[1])
			if idxs.size() >= 3 and star < _Equip.MAX_STAR:
				var item_id: String = str(k).split("|")[0]
				var rm: Array = [int(idxs[0]), int(idxs[1]), int(idxs[2])]
				rm.sort(); rm.reverse()   # 降序删, 防索引错位
				for ri in rm:
					bench_inventory.remove_at(ri)
				bench_inventory.append({"id": item_id, "star": star + 1})
				merges += 1
				changed = true
				break   # 备战席变了, 重新统计
	return merges

## 跨域 TFT 3合1: 扫【备战席 bench_inventory + 所有龟身 equipped_p2】, 同 id 同星 ≥3 → 合成 1 件高一星,
##   优先装回参与的龟(超槽退回席), 否则留席。反复直到无可合。返回 [{id, star, pet}...] 合成详情(pet=""=留席)。
##   用户场景: 龟身1件短刃 + 席2件同款 → 合成1件二星短刃装回那只龟。
func try_merge_all(side: String = "left") -> Array:
	var results: Array = []
	var safety: int = 0
	# side 命名空间隔离 (2026-06-24): 只在【本 side 的龟身键】+ 备战席里合成, 不混另一队的件。
	#   left → 只取裸键(非 "right::" 前缀); right → 只取 "right::" 前缀键。另一队的键原样保留不动。
	var _is_right := (side == "right")
	var _other_kept: Dictionary = {}   # 另一队的 equipped_p2 子集, 合成后原样并回
	while safety < 64:
		safety += 1
		# 扁平化【本 side 龟身 + 备战席】的件(保留来源 pet 键, ""=备战席)
		var flat: Array = []
		_other_kept = {}
		for b in bench_inventory:
			if b is Dictionary:
				flat.append({"id": str(b.get("id", "")), "star": int(b.get("star", 1)), "pet": ""})
		for pet in equipped_p2:
			var _pet_is_right := str(pet).begins_with(_P2EQ_RIGHT_PREFIX)
			if _pet_is_right != _is_right:
				_other_kept[pet] = equipped_p2[pet]   # 不是本 side → 保留原样, 不参与合成
				continue
			for it in equipped_p2[pet]:
				if it is Dictionary:
					flat.append({"id": str(it.get("id", "")), "star": int(it.get("star", 1)), "pet": str(pet)})
		# 按 id|star 分组, 找一组 ≥3 (star<MAX)
		var groups: Dictionary = {}
		for fi in range(flat.size()):
			var it: Dictionary = flat[fi]
			if int(it["star"]) >= _Equip.MAX_STAR:
				continue
			var k: String = "%s|%d" % [str(it["id"]), int(it["star"])]
			if not groups.has(k):
				groups[k] = []
			(groups[k] as Array).append(fi)
		var pick: Array = []
		var m_id: String = ""
		var m_star: int = 0
		for k in groups:
			if (groups[k] as Array).size() >= 3:
				pick = (groups[k] as Array).slice(0, 3)
				m_id = str(k).split("|")[0]
				m_star = int(str(k).split("|")[1])
				break
		if pick.is_empty():
			break
		# 结果归属: 3件里优先一个有 pet 的(装回那只龟)
		var dest_pet: String = ""
		for mi in pick:
			if str(flat[mi]["pet"]) != "":
				dest_pet = str(flat[mi]["pet"])
				break
		# 重建 bench + equipped(排除被合的3件) + 加合成件
		var rm: Dictionary = {}
		for mi in pick:
			rm[mi] = true
		var nb: Array = []
		var ne: Dictionary = {}
		for fi in range(flat.size()):
			if rm.has(fi):
				continue
			var it: Dictionary = flat[fi]
			if str(it["pet"]) == "":
				nb.append({"id": str(it["id"]), "star": int(it["star"])})
			else:
				if not ne.has(it["pet"]):
					ne[it["pet"]] = []
				(ne[it["pet"]] as Array).append({"id": str(it["id"]), "star": int(it["star"])})
		var merged: Dictionary = {"id": m_id, "star": m_star + 1}
		var placed: String = ""
		if dest_pet != "":
			var cap: int = _P2.equip_slots_for_level(int(dual_level.get(side, 1)))
			if not ne.has(dest_pet):
				ne[dest_pet] = []
			if (ne[dest_pet] as Array).size() < cap:
				(ne[dest_pet] as Array).append(merged)
				placed = dest_pet
			else:
				nb.append(merged)
		else:
			nb.append(merged)
		# 另一队的龟身键原样并回 (本次合成只动本 side, 不丢另一队装备)
		for k in _other_kept:
			ne[k] = _other_kept[k]
		bench_inventory = nb
		equipped_p2 = ne
		results.append({"id": m_id, "star": m_star + 1, "pet": placed})
	last_merges = results
	return results

## equipped_p2 的 side 命名空间键 (防左右队同名龟串装, 2026-06-24):
##   left(玩家) 用裸 pet_id 不变 → 全部既有玩家路径(BattleScene读/snapshot回写/test)零改动;
##   right(AI) 用 "right::"+pet_id 隔离 → AI 写自己空间, 不污染玩家 equipped_p2["basic"] 等。
const _P2EQ_RIGHT_PREFIX := "right::"
static func p2eq_key(side: String, pet_id: String) -> String:
	return (_P2EQ_RIGHT_PREFIX + pet_id) if side == "right" else pet_id

## 把备战席第 bench_idx 件装到某龟 (pet_id). 龟槽上限 = 随局内等级开放(1-5, equip_slots_for_level). 成功 true.
func equip_to_turtle(bench_idx: int, pet_id: String, side: String = "left") -> bool:
	if bench_idx < 0 or bench_idx >= bench_inventory.size():
		return false
	var key := p2eq_key(side, pet_id)
	if not equipped_p2.has(key):
		equipped_p2[key] = []
	if (equipped_p2[key] as Array).size() >= _P2.equip_slots_for_level(int(dual_level.get(side, 1))):
		return false
	(equipped_p2[key] as Array).append(bench_inventory[bench_idx])
	bench_inventory.remove_at(bench_idx)
	try_merge_all(side)   # 装备后跨域三合一
	return true

## 把某龟第 slot_idx 件卸回备战席. 成功 true.
func unequip_from_turtle(pet_id: String, slot_idx: int) -> bool:
	if not equipped_p2.has(pet_id):
		return false
	var arr: Array = equipped_p2[pet_id]
	if slot_idx < 0 or slot_idx >= arr.size() or bench_inventory.size() >= _P2.BENCH_CAP:
		return false
	bench_inventory.append(arr[slot_idx])
	arr.remove_at(slot_idx)
	try_merge_all()   # 卸下后跨域三合一
	return true

## 敌方AI购物 (right): 全复用玩家管线 (buy_xp / buy_shop_item / equip_to_turtle+try_merge_all).
##   ① 盈余高于装备预算且未满级 → 买经验升级开槽 (槽跟上玩家)。
##   ② 掷货 → 每件买得起的 → buy_shop_item 进【AI 专属席】→ equip_to_turtle 装到有空槽的敌方龟(自带三合一升星)。
##   ③ 装不下的件留 AI 席, 下回合开槽再装 (不再 break 整轮丢弃)。
##   side 命名空间 (p2eq_key): 龟身键带 "right::" 前缀, 与玩家 equipped_p2["basic"] 等隔离, 不串装。
##   返回本次新装到龟身的件数 (用于测试/调试)。
func ai_dual_shop() -> int:
	var side := "right"
	# 预算守卫: 没币直接返回
	if int(dual_coins.get(side, 0)) <= 0:
		return 0
	var turtles: Array = []
	for k in ["top", "bottom"]:
		for t in enemy_lane_assign.get(k, []):
			turtles.append(str(t))
	if turtles.is_empty():
		return 0

	# ① 买经验升级 (留够 AI_GEAR_RESERVE 装备预算后, 盈余拿去升级开槽; 每次调用最多买几次, 跟玩家逐回合节奏)
	var xp_buys := 0
	while xp_buys < _P2.AI_MAX_XP_BUYS_PER_VISIT \
			and int(dual_level.get(side, 1)) < _P2.MAX_LEVEL \
			and int(dual_coins.get(side, 0)) >= _P2.AI_GEAR_RESERVE + _P2.BUY_XP_COST:
		if not buy_xp(side):
			break
		xp_buys += 1

	var lvl: int = int(dual_level.get(side, 1))
	var cap: int = _P2.equip_slots_for_level(lvl)

	# ② 掷货 (AI 自己的货架 RNG; 不碰玩家 dual_shop_offer — 临时换进, 跑完换回)
	if battle_seed != 0:
		_dual_shop_rng.seed = battle_seed + dual_shop_visits + 7777
	else:
		_dual_shop_rng.randomize()
	var offer: Array = _Equip.roll_shop(DataRegistry.phase2_equipment, lvl, _P2.SMALL_SHOP_SLOTS, _dual_shop_rng)

	# 临时把【玩家货架/玩家席】换成【AI 货架/AI 席】→ 跑真玩家管线 → 再换回, 零污染玩家状态。
	var saved_offer: Array = dual_shop_offer
	var saved_bench: Array = bench_inventory
	dual_shop_offer = offer
	bench_inventory = ai_bench_inventory

	var bought := 0
	for idx in range(dual_shop_offer.size()):
		# 席已超 CAP (上回合留下的件 + 本轮买进, 各龟满装不掉) → 停止再买, 别让 AI 席无限涨/浪费币。
		#   (玩家路买后必 _battle_merge_p2eq/try_merge_bench 合掉, AI 路同理在本轮末补合, 但若合不掉就别再加件。)
		if bench_inventory.size() >= _P2.BENCH_CAP:
			break
		var it = dual_shop_offer[idx]
		if not (it is Dictionary):
			continue
		var cost: int = int(it.get("cost", 1))
		if int(dual_coins.get(side, 0)) < cost:
			continue
		# 买进 AI 席 (走玩家管线; 席满则跳过, 不丢币)
		if not buy_shop_item(idx, side):
			continue
		var bench_idx: int = bench_inventory.size() - 1   # 刚 append 的那件
		# 找一个有空槽的敌方龟装上 (random 顺序无所谓, 取第一个有空位的)
		var target := ""
		for t in turtles:
			var tkey := p2eq_key(side, str(t))
			if (equipped_p2.get(tkey, []) as Array).size() < cap:
				target = str(t)
				break
		if target != "":
			if equip_to_turtle(bench_idx, target, side):   # 自带 try_merge_all 三合一升星
				bought += 1
		# 装不下 (各龟满): 件留 AI 席, 下回合开槽再装 (不 break, 继续买别的填席)

	# 本轮买完: 席内同款三合一升星 (1:1 玩家买后 _battle_merge_p2eq/try_merge_bench)。
	#   各龟满 → equip_to_turtle 没触发 try_merge_all → 散件堆 AI 席; 这里席内自合, 防 ai_bench_inventory 稳定停在 >CAP。
	try_merge_bench()

	# 换回玩家状态; AI 席持久化 (留下的件下回合还在)
	ai_bench_inventory = bench_inventory
	bench_inventory = saved_bench
	dual_shop_offer = saved_offer
	return bought

## 刷新货架 (花刷新费). 成功 true.
##   刷新费恒为 shop_refresh_cost(0) (=flat 2, STEP=0 不递增); 单一来源.
##   旧 dual_shop_refresh_n 累加已失效 (STEP=0 → n 不影响费用), 删除以免误导.
func refresh_shop(side: String = "left") -> bool:
	var cost: int = _P2.shop_refresh_cost(0)
	if int(dual_coins.get(side, 0)) < cost:
		return false
	dual_coins[side] = int(dual_coins[side]) - cost
	roll_shop_offer(side)
	return true

## 记录某路胜者 ("left"/"right"), 推进到下一路.
func record_lane_result(winner: String) -> void:
	lane_results[current_lane] = winner
	current_lane = _DualLane.next_lane(current_lane)

## 是否需要终极战场 (两路 1-1).
func dual_lane_needs_final() -> bool:
	return _DualLane.needs_final(lane_results)

## 整局最终胜者 ("left"/"right"/""); "" = 还没分出 (需打下一路 / final).
func dual_lane_winner() -> String:
	return _DualLane.overall_winner(lane_results)

## 整局是否已分胜负: 谁的龟蛋被摧毁谁败 (胜负只看蛋, 不看赢几路). "" = 未分.
func dual_match_over() -> String:
	var l_dead: bool = int(egg_hp_max.get("left", 0)) > 0 and not egg_alive("left")
	var r_dead: bool = int(egg_hp_max.get("right", 0)) > 0 and not egg_alive("right")
	if l_dead and r_dead:
		return "left"   # 双蛋同灭(真平局, 终极双方团灭罕见) → 归玩家 (原顺查左先=恒判右赢=偏袒敌方)
	if l_dead:
		return "right"
	if r_dead:
		return "left"
	return ""

## 上下两路是否都打完.
func dual_lanes_done() -> bool:
	return _DualLane.lanes_done(lane_results)

## 快照某场存活统领(非小将/召唤/蛋) → 待命回复30%已损 → 累计进 dual_survivors (终极带血汇合).
func snapshot_lane_survivors(fighters: Array) -> void:
	for f in fighters:
		if f.get("_isMinion", false) or f.get("_isEgg", false) or f.get("_isSummon", false):
			continue
		if not f.get("alive", false):
			continue
		var s := str(f.get("side", ""))
		if s != "left" and s != "right":
			continue
		var hp: int = int(f.get("hp", 0))
		var maxhp: int = int(f.get("maxHp", 0))
		var recovered: int = mini(maxhp, hp + int(round((maxhp - hp) * _P2.STANDBY_RECOVER_PCT)))
		# 回写战中(拖装/合星)对装备的最终改动 → 持久存储, 跨路保留 (仅我方;
		#   否则下路/终极从 equipped_p2 重建会丢战中装的, 且该件已从备战席删=彻底丢失。审计 2026-06-23)
		if s == "left" and f.has("_p2_equips"):
			equipped_p2[str(f.get("id", ""))] = (f["_p2_equips"] as Array).duplicate(true)
		(dual_survivors[s] as Array).append({
			"id": str(f.get("id", "")), "hp": recovered, "maxHp": maxhp,
			"level": int(f.get("_level", 1)),
		})

## 攻蛋: 对某方龟蛋累计伤害 (amount 为最终值, 调用方按场景先算好×5; 跨上/下/终极累计).
## 返回是否摧毁 (HP 归零). §4 伤害跨战场累计保留.
func damage_egg(side: String, amount: int) -> bool:
	var cur: int = maxi(0, int(egg_hp.get(side, 0)) - maxi(0, amount))
	egg_hp[side] = cur
	return cur <= 0

func egg_alive(side: String) -> bool:
	return int(egg_hp.get(side, 0)) > 0

## 龟蛋血量比例 (HUD 用) 0..1.
func egg_frac(side: String) -> float:
	var mx: int = int(egg_hp_max.get(side, 0))
	return clampf(float(egg_hp.get(side, 0)) / float(mx), 0.0, 1.0) if mx > 0 else 0.0

## 双路对局快照 (PvP 权威同步 / 断线重连用) — 可 JSON 序列化的对局态.
## (单位逐龟 state 不在此, 由战斗层另行同步; 这里是对局框架态.)
func dual_lane_snapshot() -> Dictionary:
	return {
		"lane_assign": lane_assign.duplicate(true),
		"enemy_lane_assign": enemy_lane_assign.duplicate(true),
		"current_lane": current_lane,
		"egg_hp": egg_hp.duplicate(true),
		"egg_hp_max": egg_hp_max.duplicate(true),
		"lane_results": lane_results.duplicate(true),
		"dual_shop_visits": dual_shop_visits,
		"dual_level": dual_level.duplicate(true),
		"dual_xp": dual_xp.duplicate(true),
		"dual_passive_xp_started": dual_passive_xp_started,
		"dual_coins": dual_coins.duplicate(true),
		"side_controllers": side_controllers.duplicate(true),
		"battle_seed": battle_seed,
	}

## 应用对局快照 (权威下发 → 本端覆盖). 重连续战用.
func apply_dual_lane_snapshot(snap: Dictionary) -> void:
	mode = "duallane"
	lane_assign = (snap.get("lane_assign", {}) as Dictionary).duplicate(true)
	enemy_lane_assign = (snap.get("enemy_lane_assign", {}) as Dictionary).duplicate(true)
	current_lane = str(snap.get("current_lane", "top"))
	egg_hp = (snap.get("egg_hp", {}) as Dictionary).duplicate(true)
	egg_hp_max = (snap.get("egg_hp_max", {}) as Dictionary).duplicate(true)
	lane_results = (snap.get("lane_results", {}) as Dictionary).duplicate(true)
	dual_shop_visits = int(snap.get("dual_shop_visits", 0))
	dual_level = (snap.get("dual_level", {"left": 1, "right": 1}) as Dictionary).duplicate(true)
	dual_xp = (snap.get("dual_xp", {"left": 0, "right": 0}) as Dictionary).duplicate(true)
	dual_passive_xp_started = bool(snap.get("dual_passive_xp_started", true))   # 重连默认已开始(不再误跳首回合)
	dual_coins = (snap.get("dual_coins", {"left": 0, "right": 0}) as Dictionary).duplicate(true)
	side_controllers = (snap.get("side_controllers", {"left": "local", "right": "ai"}) as Dictionary).duplicate(true)
	battle_seed = int(snap.get("battle_seed", 0))

# ─── 闯关进度 (单次冒险, 不持久化, 失败重置) ───────────────────
var dungeon_stage: int = 1                           # 当前第几关 (1-5)
var dungeon_carry_hp: Dictionary = {}                 # {pet_id → remaining_hp}, 跨关继承
var dungeon_carry_equips: Dictionary = {}             # {pet_id → [eq_id...]} 跨关携带身上已装装备 (1:1 PoC snapshot.equipIds, 修"装备每关全丢")
var dungeon_carry_bench: Array = []                   # 跨关携带装备席库存 (1:1 PoC benchInventoryIds)
## 本关玩家(左队)阵亡龟 id 列表 — 下一关 70% HP 复活 (1:1 PoC BattleScene.ts:1498-1503 wasDead → maxHp*0.7).
## snapshot_left_hp 在深海胜利 _show_result 时填充; 与 dungeon_carry_hp 同生命周期 (开新 run/换关清算).
var dungeon_dead_ids: Array[String] = []
var dungeon_bonuses: Array = []                       # 闯关累积加成 TeamBonus[]{kind,value,equipId} (奖励/事件)
var dungeon_rule: String = ""                         # 闯关整局规则 (stage1 抽一条非正常, 全程沿用 — 1:1 PoC DungeonScene.ts:85-90)

# ─── 持久化数据 (写入 user://savegame.json) ────────────────────
var best_dungeon_stage: int = 0                       # 史上最远到第几关
var coins: int = 0                                    # 龟币累计
var battles_won: int = 0
var battles_total: int = 0
var inventory: Array[String] = []                     # 收集到的装备 id 列表 (跨场景持久)
var match_history: Array = []                          # 对局记录 [{result,lineup,mode,turn}], 最新在前封顶 50
var pet_levels: Dictionary = {}                        # 宠物等级 {petId: 1-10} (1:1 PoC petState.levels; 只调试面板改, 默认1)
var achievements_unlocked: Array = []                 # 已解锁成就 id
## 成就累计统计 (1:1 PoC achievement-tracker.ts AchStats). 持久化, AchievementTracker 读写.
## 字段: battles/wins/crits/totalDmg/totalEquipsBought/totalCoinsEarned(int)
##       petsUsed/rulesSeen ({id→true} set 模拟), bestDungeon(int).
var ach_stats: Dictionary = {}
var bgm_volume: float = 0.45                           # 设置: BGM 音量
var sfx_volume: float = 0.8                            # 设置: SFX 音量

# ─── V2 异步PvP 生命赛季 持久字段 (写入 savegame.json; 见 docs/specs/V2-阶段2) ───
var meta_deepsea_coins: int = 0                       # 局外深海币 (独立钱包; 区别于 coins/battle_coins/dual_coins)
var season_id: int = 1                                # 第几大轮赛季 (5天一轮, 切轮全重置)
var season_start_ts: int = 0                          # 本赛季开始 unix 时间戳 (0=未初始化; 满 SEASON_DURATION_SEC 后过期滚下一赛季)
var hearts: int = 8                                   # 命数 (8起, 输-1, 0=淘汰; 玩法在阶段4)
var season_total_battles: int = 0                     # 本赛季总战斗数 → 决定装备槽 0/1/2/3/4
var season_eggs_killed: int = 0                       # 本赛季击杀龟蛋数 (排行榜口径)
var season_wins: int = 0                              # 本赛季胜场数 (实时战斗赢一场+1; 排行指标候选)
var season_level: int = 1                             # 大轮等级 1-10 (每场+2经验累积, 可买经验; 驱动商店出货档 + 装备槽; 用户 2026-06-27)
var debug_level: int = 0                              # 调试器: >0 强制全体战斗单位等级(测试用, 正式版用外部快照); 0=用真实等级
var season_xp: int = 0                                # 大轮等级当前经验 (满 xp_to_next(level) 升级)
var season_leaders: Array = []                        # 本赛季锁定的 3 统领 id (整轮不可换)
var persistent_bench: Array = []                      # 持久背包 [{id,star}] (装备永不丢; build 源, 取代局内临时 bench_inventory)
var persistent_equipped: Dictionary = {}             # 持久 build {pet_key → [{id,star}]} (build 源, 取代局内临时 equipped_p2)
var lane_loadout: Dictionary = {}                    # 出战阵容: 分路+小将占位+各持有者装备 (小将载体阶段3补全)


func _ready() -> void:
	_load()
	ensure_season()   # V2: 初始化/滚动赛季 (阶段4)
	# 把存档音量同步给 Audio autoload
	if Engine.has_singleton("Audio") or get_node_or_null("/root/Audio"):
		Audio.bgm_volume = bgm_volume
		Audio.sfx_volume = sfx_volume


## 全局全屏切换: F11 / Alt+Enter. (画面靠 stretch=canvas_items + aspect=keep 等比放大到任意分辨率/4K.)
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		var w := get_window()
		var is_fs: bool = w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		w.mode = Window.MODE_WINDOWED if is_fs else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()


# ─── 局内经济 (用户 v0.9.9 — 1:1 PoC BattleScene 经济) ──────────

## 野生敌方模式判定 (1:1 PoC isWildEnemyMode: 'pve'||'custom').
## 野生 = 玩家打随机野生龟的对局; 深海/Boss/测试 不给敌方 AI 钱 (aiGainCoins 守卫).
## Godot: single/custom/pve = 野生自定义局; dungeon 非 boss 关也是随机野生龟; boss/boss-pick/test 排除.
func is_wild_enemy_mode() -> bool:
	if mode in ["single", "custom", "pve"]:
		return true
	if mode == "dungeon" and not is_dungeon_boss_stage():
		return true
	return false


## 局内经济重置 (BattleScene 开局调) — 1:1 PoC :653 this.coins = _carryCoins.
## 玩家钱包归 0 (dungeon stage>1 注入跨关结余); 敌方钱包清零. 持久 meta coins 不动.
func reset_battle_economy() -> void:
	battle_coins = dungeon_carry_coins if (mode == "dungeon" and dungeon_stage > 1) else 0
	enemy_coins = 0


## 利息 (1:1 PoC: 每持有 5 币得 1, 上限 10/回合, TFT 风, floor).
func _interest(bank: int) -> int:
	return mini(10, int(floor(bank / 5.0)))


## 每回合开始经济结算 (1:1 PoC BattleScene:7795-7802).
## 先按"加 10 之前"的存款结息 (TFT 顺序), 再 +10. 玩家 coins / 野生敌方 enemy_coins 各自结算.
## 返回 {player_gain, player_interest, coins} 供 BattleScene 打日志/刷新币显示. BattleScene 在回合开始调用.
func on_battle_turn_economy() -> Dictionary:
	var p_interest: int = _interest(battle_coins)
	battle_coins += 10 + p_interest
	# 野生敌方 AI 同步收币 (深海/Boss 不给 → ai_gain_coins 守卫)
	ai_gain_coins(10 + _interest(enemy_coins))
	return {"player_gain": 10 + p_interest, "player_interest": p_interest, "coins": battle_coins}


## 野生敌方 AI 收币 (1:1 PoC aiGainCoins; 非野生模式 / amount<=0 → no-op).
func ai_gain_coins(amount: int) -> void:
	if not is_wild_enemy_mode() or amount <= 0:
		return
	enemy_coins += amount


## 财富羁绊 _synergyWealthCoinPerTurn / 招财 fortuneGold+2 每回合发币 (1:1 PoC BattleScene:5289-5308).
## 玩家方 (left) 进 battle_coins 钱包; 野生敌方 (right) 进 enemy_coins. side: "left"/"right".
## (PoC 把 wealthCoin 加到 this.coins/aiGainCoins, 不是 fortune 技能资源 _goldCoins.)
func grant_wealth_coin(side: String, amount: int) -> void:
	if amount <= 0:
		return
	if side == "left":
		battle_coins += amount
	else:
		ai_gain_coins(amount)


## 记一场对局 (BattleEnd 调) — 最新在前, 封顶 50
func record_match(result: String, lineup: Array, mode_str: String, turn_num: int) -> void:
	match_history.insert(0, {"result": result, "lineup": lineup, "mode": mode_str, "turn": turn_num})
	if match_history.size() > 50:
		match_history.resize(50)
	save()


# ─── 当前对局 ────────────────────────────────────────────────

func has_team() -> bool:
	return left_team.size() == 3 and right_team.size() == 3


func clear_team() -> void:
	left_team = []
	right_team = []
	left_slots = []


# ─── 闯关 ────────────────────────────────────────────────────

func start_dungeon() -> void:
	mode = "dungeon"
	dungeon_stage = 1
	dungeon_carry_hp = {}
	dungeon_dead_ids = []
	dungeon_bonuses = []
	dungeon_carry_coins = 0   # 新 run 清零 (1:1 PoC stage1 _carryCoins=0)
	dungeon_carry_equips = {}; dungeon_carry_bench = []
	# 整局规则: 抽一条非「正常对局」, 全程沿用 (1:1 PoC DungeonScene.ts:85-90)
	var pool: Array = []
	for r in DataRegistry.battle_rules:
		if r is Dictionary and r.get("id", "") != "normal":
			pool.append(str(r.get("name", "")))
	dungeon_rule = pool[randi() % pool.size()] if not pool.is_empty() else ""


func advance_stage() -> void:
	# 1:1 PoC: 本关胜利结余 → 下关 _carryCoins (advance 在赢一关后调, battle_coins 尚未被下场 reset)
	dungeon_carry_coins = battle_coins
	dungeon_stage += 1


## 进下一关前给 right_team 随机抽 3 龟 (排除玩家阵容). 从 BattleScene 移来, 供 BattleEnd 路由用.
func setup_next_dungeon_stage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pool: Array = []
	for pet in DataRegistry.all_pets:
		var pid: String = pet["id"]
		if not (pid in left_team):
			pool.append(pid)
	pool.shuffle()
	var count: int = 1 if is_dungeon_boss_stage() else 3   # BOSS 关 1 只强敌, 否则 3
	var new_right: Array[String] = []
	for i in range(count):
		new_right.append(pool[i % pool.size()])
	right_team = new_right


func reset_dungeon() -> void:
	mode = "single"
	dungeon_stage = 1
	dungeon_carry_hp = {}
	dungeon_dead_ids = []
	dungeon_bonuses = []
	dungeon_carry_coins = 0
	dungeon_rule = ""
	dungeon_carry_equips = {}; dungeon_carry_bench = []


func is_dungeon_boss_stage() -> bool:
	return dungeon_stage == 5


## 战斗结束后调, 记录左方龟跨关 HP 状态 (1:1 PoC BattleScene.ts:1480-1513 playerHpSnapshot).
##   存活龟 → dungeon_carry_hp (但 _build_teams 实际回满血, 与 PoC:1505-1507 / JS dungeon.js:191 一致);
##   阵亡龟(alive==false 或 hp==0) → dungeon_dead_ids, 下一关 70% HP 复活 (PoC:1498-1503 wasDead).
func snapshot_left_hp(fighters: Array) -> void:
	dungeon_carry_hp = {}
	dungeon_dead_ids = []
	dungeon_carry_equips = {}
	for f in fighters:
		if f.get("side", "") != "left":
			continue
		# 召唤物/中立不计入玩家阵容继承
		if f.get("_isSummon", false) or f.get("_isNeutral", false):
			continue
		var dead: bool = not bool(f.get("alive", false)) or int(f.get("hp", 0)) == 0
		if dead:
			dungeon_dead_ids.append(f["id"])
		else:
			dungeon_carry_hp[f["id"]] = f["hp"]
		# 跨关携带身上已装装备 (死活都带, 死龟下关 70% 复活仍带装备) — 1:1 PoC snapshot.equipIds(:8672)
		var eqs: Array = f.get("_equipped_ids", [])
		if not eqs.is_empty():
			dungeon_carry_equips[f["id"]] = eqs.duplicate()


# ─── 持久化 ──────────────────────────────────────────────────

func record_battle_win() -> void:
	battles_won += 1
	battles_total += 1
	coins += 20    # 每场胜利 +20 龟币
	if mode == "dungeon" and dungeon_stage > best_dungeon_stage:
		best_dungeon_stage = dungeon_stage
	save()


func record_battle_loss() -> void:
	battles_total += 1
	save()


## 宠物等级 (1:1 PoC pet-level.ts getPetLevel/setPetLevel): 默认1, clamp 1-10, set 后存档
func get_pet_level(pet_id: String) -> int:
	return int(pet_levels.get(pet_id, 1))


func set_pet_level(pet_id: String, level: int) -> void:
	pet_levels[pet_id] = clampi(level, 1, 10)
	save()


func save() -> void:
	var data := {
		"best_dungeon_stage": best_dungeon_stage,
		"coins": coins,
		"battles_won": battles_won,
		"battles_total": battles_total,
		"inventory": inventory,
		"match_history": match_history,
		"pet_levels": pet_levels,
		"achievements_unlocked": achievements_unlocked,
		"ach_stats": ach_stats,
		"bgm_volume": bgm_volume,
		"sfx_volume": sfx_volume,
		"meta_deepsea_coins": meta_deepsea_coins,
		"season_id": season_id,
		"season_start_ts": season_start_ts,
		"hearts": hearts,
		"season_total_battles": season_total_battles,
		"season_eggs_killed": season_eggs_killed,
		"season_wins": season_wins,
		"season_level": season_level,
		"season_xp": season_xp,
		"season_leaders": season_leaders,
		"persistent_bench": persistent_bench,
		"persistent_equipped": persistent_equipped,
		"lane_loadout": lane_loadout,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[GameState] save 失败: cannot open " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	best_dungeon_stage = data.get("best_dungeon_stage", 0)
	coins = data.get("coins", 0)
	battles_won = data.get("battles_won", 0)
	battles_total = data.get("battles_total", 0)
	match_history = data.get("match_history", [])
	pet_levels = data.get("pet_levels", {})
	achievements_unlocked = data.get("achievements_unlocked", [])
	ach_stats = data.get("ach_stats", {})
	bgm_volume = data.get("bgm_volume", 0.45)
	sfx_volume = data.get("sfx_volume", 0.8)
	# V2 赛季持久字段
	meta_deepsea_coins = int(data.get("meta_deepsea_coins", 0))
	season_id = int(data.get("season_id", 1))
	season_start_ts = int(data.get("season_start_ts", 0))
	hearts = int(data.get("hearts", 8))
	season_total_battles = int(data.get("season_total_battles", 0))
	season_eggs_killed = int(data.get("season_eggs_killed", 0))
	season_wins = int(data.get("season_wins", 0))
	season_level = int(data.get("season_level", 1))
	season_xp = int(data.get("season_xp", 0))
	season_leaders = data.get("season_leaders", [])
	persistent_bench = data.get("persistent_bench", [])
	persistent_equipped = data.get("persistent_equipped", {})
	lane_loadout = data.get("lane_loadout", {})
	# 装备库: Array[String] (Variant default → assign 后再强转)
	var inv_raw: Array = data.get("inventory", [])
	inventory = []
	for x in inv_raw:
		if x is String:
			inventory.append(x)


func reset_save() -> void:
	best_dungeon_stage = 0
	coins = 0
	battles_won = 0
	battles_total = 0
	inventory = []
	# 1:1 PoC resetAchievements(): 清空解锁 + 累计统计
	achievements_unlocked = []
	ach_stats = {}
	match_history = []
	# V2 赛季持久字段重置 (注: pet_levels 龟自身等级来自养龟站, 不在此清)
	meta_deepsea_coins = 0
	season_id = 1
	season_start_ts = 0
	hearts = 8
	season_total_battles = 0
	season_eggs_killed = 0
	season_wins = 0
	season_level = 1
	season_xp = 0
	season_leaders = []
	persistent_bench = []
	persistent_equipped = {}
	lane_loadout = {}
	save()


# ─── V2 赛季 / 命 逻辑 (阶段4核心) ───────────────────────────
## 启动时确保赛季已初始化: season_start_ts=0 → 设当前; 已过 5 天 → 滚下一赛季.
func ensure_season() -> void:
	if season_start_ts == 0:
		season_start_ts = int(Time.get_unix_time_from_system())
		save()
	elif is_season_expired():
		start_new_season()
		save()

## 本赛季是否已过 SEASON_DURATION_SEC (倒计时归0). 未初始化(0)算未过期.
func is_season_expired() -> bool:
	if season_start_ts == 0:
		return false
	return int(Time.get_unix_time_from_system()) - season_start_ts >= _P2.SEASON_DURATION_SEC

## 0 命 = 淘汰出局 (开放无限表演赛, 玩法在后续).
func is_eliminated() -> bool:
	return hearts <= 0

## 输一场 → 失一颗心 (clamp ≥0). 返回是否就此淘汰. (不自存; 调用方负责 save)
func lose_heart() -> bool:
	hearts = maxi(0, hearts - 1)
	return hearts <= 0

## 大轮等级 +XP (每场+2; 满 xp_to_next 升级, 封顶 MAX_LEVEL). 不自存, 调用方 save.
func add_season_xp(amt: int) -> void:
	season_xp += amt
	while season_level < _P2.MAX_LEVEL and season_xp >= _P2.xp_to_next(season_level):
		season_xp -= _P2.xp_to_next(season_level)
		season_level += 1

## 买经验: 4 深海币 = 4 XP (设计§五). 满级/币不足 → false.
func buy_season_xp() -> bool:
	if meta_deepsea_coins < _P2.BUY_XP_COST or season_level >= _P2.MAX_LEVEL:
		return false
	meta_deepsea_coins -= _P2.BUY_XP_COST
	add_season_xp(_P2.BUY_XP_AMOUNT)
	save()
	return true

## 自动 3 合 1 (持久背包内): 同 id+star 满 3 → 升 1 星, 反复到无可合 (满3星止). 不自存. 买/卸后自动调.
func auto_merge_bench() -> void:
	var changed := true
	while changed:
		changed = false
		var counts := {}
		for it in persistent_bench:
			var k := "%s|%d" % [str(it.get("id", "")), int(it.get("star", 1))]
			counts[k] = int(counts.get(k, 0)) + 1
		for k in counts.keys():
			if int(counts[k]) < 3:
				continue
			var parts := str(k).split("|")
			var iid := str(parts[0])
			var star := int(parts[1])
			if star >= 3:
				continue
			var removed := 0
			var i := 0
			while i < persistent_bench.size() and removed < 3:
				var it: Dictionary = persistent_bench[i]
				if str(it.get("id", "")) == iid and int(it.get("star", 1)) == star:
					persistent_bench.remove_at(i); removed += 1
				else:
					i += 1
			persistent_bench.append({"id": iid, "star": star + 1})
			changed = true
			break

## 开新一大轮赛季: 命/币/局内等级/总战斗数/蛋数/背包build 全重置 (设计§五). pet_levels(养龟站)不动.
func start_new_season() -> void:   # 不自存; 调用方(ensure_season/调试快进)负责 save
	season_id += 1
	season_start_ts = int(Time.get_unix_time_from_system())
	hearts = 8
	season_total_battles = 0
	season_eggs_killed = 0
	season_wins = 0
	season_level = 1
	season_xp = 0
	meta_deepsea_coins = 0
	season_leaders = []
	persistent_bench = []
	persistent_equipped = {}
	lane_loadout = {}
