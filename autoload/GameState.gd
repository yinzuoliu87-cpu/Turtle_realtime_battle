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
## 对手(ghost快照)的技能选择 {pet_id → idx}; 匹配到ghost时战斗场景填, 敌侧_resolve_chosen_index读(用户2026-07-15: ghost带技能配置); 不落盘
var foe_loadouts: Dictionary = {}
## 最近匹配过的对手ghost_id(保留3个·防连续遇到同一快照·用户2026-07-15真机纠错); 不落盘
var recent_ghost_ids: Array = []

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
var dual_active: bool = false   # 双路对局激活: 开始战斗置true → 战斗场走双路spawn(分路/小将/蛋/半场流程), 非教程/调试
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
var bgm_volume: float = 0.45                           # 设置: BGM 音量
var sfx_volume: float = 0.8                            # 设置: SFX 音量
var fullscreen: bool = false                           # 设置: 全屏 (原来切了不存, 重启回窗口)
var perf_lite: bool = false                            # 设置: 低画质模式 (原来是死按钮, 只改自己的 label)

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
var chest_treasure_value: float = 0.0                 # 宝箱藏宝图·财宝值(随一大轮累积·用户2026-07-16)
var chest_treasures_won: Array = []                   # 宝箱藏宝图·本大轮已开战利品id(常驻整轮·最多5件)
var season_leaders: Array = []                        # 本赛季锁定的 3 统领 id (整轮不可换)
var persistent_bench: Array = []                      # 持久背包 [{id,star}] (装备永不丢; build 源, 取代局内临时 bench_inventory)
var persistent_equipped: Dictionary = {}             # 持久 build {pet_key → [{id,star}]} (build 源, 取代局内临时 equipped_p2)
# ─── 糖果龟·糖果罐 局外赛季被动 (封板L390-403: 选糖果龟当统领才有·大轮1颗·赢+1输+4封顶30·打碎按档领奖·碎即消失) ───
var candy_jar_count: int = 0                          # 糖果罐计数 0-30 (赢+1/输+4·逆风快攒翻盘)
var candy_jar_broken: bool = false                    # 本赛季糖果罐已打碎领奖 (一大轮1颗)
var candy_temp_levels: Dictionary = {}               # 临时等级器已用 {pet_id: +级数} (本大轮永久·切轮重置)
var gambler_wheel_stacks: Dictionary = {}            # 赌神·命运之轮抽花色跨场累积 {"spade"/"heart"/"diamond"/"club": 抽中次数} (本大轮永久·切轮重置·方案B·用户2026-07-09)
var lane_loadout: Dictionary = {}                    # (旧, 弃用) 阵容格子; 双路改用 dual_lineup
# 双路布阵: 上/下战场各3单位(3统领+3小将分3+3). unit = {"kind":"leader","id":X} 或 {"kind":"minion","role":"front"/"back"}
# front小将=近战挥砍×1.4 / back小将=远程射击×1.5; 某路0统领→首个小将自动精英(spawn时判). 位置=场内自由放置(此处只定分路+小将类型)
var dual_lineup: Dictionary = {}

## 双路布阵默认: 3统领(slot 0/1/2)+3小将分上/下. top=统领0,1+前排小将; bottom=统领2+前排小将+后排小将.
##   统领 unit 带 slot(0=统领1/1=统领2/2=统领3, 稳定身份) + id(=season_leaders[slot], 大轮未选统领时=""占位)。
##   id="" → 背包渲染成「统领N ?」占位; 玩家可拖问号↔小将排上下战场; 选龟按序填 season_leaders 后 slot→真龟(阵型保留)。
func default_dual_lineup() -> Dictionary:
	var lead: Array = season_leaders.duplicate() if season_leaders is Array else []
	var id0: String = str(lead[0]) if lead.size() > 0 else ""
	var id1: String = str(lead[1]) if lead.size() > 1 else ""
	var id2: String = str(lead[2]) if lead.size() > 2 else ""
	return {
		"top": [{"kind": "leader", "id": id0, "slot": 0}, {"kind": "leader", "id": id1, "slot": 1}, {"kind": "minion", "role": "front"}],
		"bottom": [{"kind": "leader", "id": id2, "slot": 2}, {"kind": "minion", "role": "front"}, {"kind": "minion", "role": "back"}],
	}

## 取双路布阵. 结构合法(3统领·slot 0/1/2齐全)→ 按 season_leaders[slot] 填/占位 id(保留玩家排的阵型); 否则重置默认.
func get_dual_lineup() -> Dictionary:
	if _dl_structure_ok(dual_lineup):
		_resolve_leader_slots(dual_lineup)
		return dual_lineup
	dual_lineup = default_dual_lineup()
	return dual_lineup

## 结构合法: top/bottom 都在 + 恰好3统领 + slot 覆盖 0/1/2. (旧存档统领无slot → false → 重置一次默认)
func _dl_structure_ok(dl) -> bool:
	if not (dl is Dictionary and dl.has("top") and dl.has("bottom")):
		return false
	if not (dl["top"] is Array and dl["bottom"] is Array):
		return false
	var slots := {}
	var lead_n := 0
	for lane in ["top", "bottom"]:
		for u in dl[lane]:
			if u is Dictionary and str(u.get("kind", "")) == "leader":
				lead_n += 1
				var s := int(u.get("slot", -99))
				if s >= 0 and s <= 2:
					slots[s] = true
	return lead_n == 3 and slots.size() == 3

## 按 slot 把统领 id 填成 season_leaders[slot] (无/越界→""占位). 每次取阵都跑, 幂等.
func _resolve_leader_slots(dl: Dictionary) -> void:
	var lead: Array = season_leaders if season_leaders is Array else []
	for lane in ["top", "bottom"]:
		for u in dl[lane]:
			if u is Dictionary and str(u.get("kind", "")) == "leader":
				var s := int(u.get("slot", -1))
				u["id"] = str(lead[s]) if (s >= 0 and s < lead.size()) else ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		test_mode = true   # headless(测试/仿真/导出) → 绝不写盘, 保护玩家存档
	_load()
	if fullscreen and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)   # 开机恢复全屏(设置持久化)
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




# ─── 持久化 ──────────────────────────────────────────────────





## 宠物等级 (1:1 PoC pet-level.ts getPetLevel/setPetLevel): 默认1, clamp 1-10, set 后存档
func get_pet_level(pet_id: String) -> int:
	return int(pet_levels.get(pet_id, 1))


func set_pet_level(pet_id: String, level: int) -> void:
	pet_levels[pet_id] = clampi(level, 1, 10)
	save()


## ★存档保护: 置 true 后 save() 空转。
## 【headless 下自动开启】—— 自动化测试/仿真会大量改 GameState 状态并触发 save(),
## 曾把玩家的 user://savegame.json 整个覆盖(2026-07-10 实际发生过: 币/背包/统领/糖果罐全被测试值写入)。
## 真实玩家永远不会以 headless 跑游戏, 所以这个判定是安全的; tests/ 也会显式再设一次。
var test_mode: bool = false

func save() -> void:
	if test_mode:
		return
	var data := {
		"best_dungeon_stage": best_dungeon_stage,
		"coins": coins,
		"battles_won": battles_won,
		"battles_total": battles_total,
		"inventory": inventory,
		"match_history": match_history,
		"pet_levels": pet_levels,
		"bgm_volume": bgm_volume,
		"sfx_volume": sfx_volume,
		"fullscreen": fullscreen,
		"perf_lite": perf_lite,
		"meta_deepsea_coins": meta_deepsea_coins,
		"season_id": season_id,
		"season_start_ts": season_start_ts,
		"hearts": hearts,
		"season_total_battles": season_total_battles,
		"season_eggs_killed": season_eggs_killed,
		"season_wins": season_wins,
		"season_level": season_level,
		"season_xp": season_xp,
		"chest_treasure_value": chest_treasure_value,
		"chest_treasures_won": chest_treasures_won,
		"season_leaders": season_leaders,
		"loadouts": loadouts,                 # 大轮内各龟 3选1 技能选择, 随赛季持久(跨场景/重启不丢)
		"persistent_bench": persistent_bench,
		"persistent_equipped": persistent_equipped,
		"candy_jar_count": candy_jar_count,
		"candy_jar_broken": candy_jar_broken,
		"candy_temp_levels": candy_temp_levels,
		"gambler_wheel_stacks": gambler_wheel_stacks,
		"lane_loadout": lane_loadout,
		"dual_lineup": dual_lineup,
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
	bgm_volume = data.get("bgm_volume", 0.45)
	sfx_volume = data.get("sfx_volume", 0.8)
	fullscreen = bool(data.get("fullscreen", false))
	perf_lite = bool(data.get("perf_lite", false))
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
	chest_treasure_value = float(data.get("chest_treasure_value", 0.0))
	chest_treasures_won = data.get("chest_treasures_won", [])
	season_leaders = data.get("season_leaders", [])
	loadouts = {}                                     # JSON 数字回来是 float → 强转回 int(与 _toggle_skill 写入一致); 缺键=旧档默认空
	var _lo_raw = data.get("loadouts", {})
	if _lo_raw is Dictionary:
		for _lk in _lo_raw:
			var _lv = _lo_raw[_lk]
			loadouts[str(_lk)] = int(_lv) if (_lv is int or _lv is float) else _lv
	persistent_bench = data.get("persistent_bench", [])
	for _bi in range(persistent_bench.size()):        # 迁移: 老存档把临时等级器存成裸String → 转成字典(否则 auto_merge_all/_equip_cell 崩)
		if persistent_bench[_bi] is String and str(persistent_bench[_bi]) == TEMP_LEVELER_ID:
			persistent_bench[_bi] = TEMP_LEVELER_ITEM.duplicate()
	persistent_equipped = data.get("persistent_equipped", {})
	candy_jar_count = int(data.get("candy_jar_count", 0))
	candy_jar_broken = bool(data.get("candy_jar_broken", false))
	candy_temp_levels = data.get("candy_temp_levels", {})
	gambler_wheel_stacks = data.get("gambler_wheel_stacks", {})
	lane_loadout = data.get("lane_loadout", {})
	dual_lineup = data.get("dual_lineup", {})
	# 装备库: Array[String] (Variant default → assign 后再强转)
	var inv_raw: Array = data.get("inventory", [])
	inventory = []
	for x in inv_raw:
		if x is String:
			inventory.append(x)


## 重置所有进度。**不清设置项**(bgm/sfx 音量 · fullscreen · perf_lite) — 那是偏好不是进度。
## ⚠ 破坏性: 调用方必须先做二次确认 (SettingsScene 已加确认弹窗)。
func reset_save() -> void:
	best_dungeon_stage = 0
	coins = 0
	battles_won = 0
	battles_total = 0
	inventory = []
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
	candy_jar_count = 0
	candy_jar_broken = false
	candy_temp_levels = {}
	gambler_wheel_stacks = {}
	lane_loadout = {}
	dual_lineup = {}
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

# ══════ 糖果罐 局外赛季被动 API (封板L390-403·糖果龟当统领才有·打碎按当前计数领档奖) ══════
## 档位奖励规格(封板表): coins=深海币[lo,hi] / cost=装备费档 / star=装备星 / leveler=临时等级器概率
## 临时等级器(糖果罐奖励): 消耗品条目, 用在龟/小将身上→该大轮等级永久+1. kind="item" 使其绕开装备逻辑。
const TEMP_LEVELER_ID := "temp_leveler"
const TEMP_LEVELER_ITEM := {"id": "temp_leveler", "star": 0, "kind": "item"}

## 背包项是不是装备(非消耗品)? 3合1/装备渲染只认这个。
static func is_equip_item(it) -> bool:
	return it is Dictionary and str(it.get("kind", "equip")) != "item"

const _CANDY_JAR_TIERS := [
	{"coins": [8, 12],    "cost": [1, 2], "star": 1, "leveler": 0.0},    # 档1 计数0-5
	{"coins": [15, 22],   "cost": [2, 3], "star": 1, "leveler": 0.0},    # 档2 6-11
	{"coins": [25, 35],   "cost": [3],    "star": 2, "leveler": 0.0},    # 档3 12-17
	{"coins": [45, 55],   "cost": [4],    "star": 2, "leveler": 0.25},   # 档4 18-23
	{"coins": [65, 80],   "cost": [5],    "star": 2, "leveler": 0.50},   # 档5 24-29
	{"coins": [120, 120], "cost": [5],    "star": 2, "leveler": 1.0},    # 档6封顶 30
]

## 有糖果罐? = 本赛季锁定统领含糖果龟 且 未碎 (罐随统领锁定而有; 大轮1颗)
func has_candy_jar() -> bool:
	return (season_leaders is Array) and ("candy" in season_leaders) and not candy_jar_broken

## 战斗结算调: 赢+1 / 输+4 (逆风快攒翻盘) · 封顶30 (仅有罐且未碎时计). 自存.
func candy_jar_add(n: int) -> void:
	if not has_candy_jar():
		return
	candy_jar_count = clampi(candy_jar_count + n, 0, 30)
	save()

## 当前计数 → 档位 1-6 (封板计数区间)
func candy_jar_tier() -> int:
	var c := candy_jar_count
	if c >= 30: return 6
	if c >= 24: return 5
	if c >= 18: return 4
	if c >= 12: return 3
	if c >= 6:  return 2
	return 1

## 打碎糖果罐: 按当前档领奖(深海币+装备进背包+可能临时等级器)·碎即消失. 返回奖励摘要; 无罐→{}.
func break_candy_jar() -> Dictionary:
	if not has_candy_jar():
		return {}
	var tier: int = candy_jar_tier()
	var spec: Dictionary = _CANDY_JAR_TIERS[tier - 1]
	var got_coins: int = randi_range(int(spec["coins"][0]), int(spec["coins"][1]))   # 深海币档内随机
	meta_deepsea_coins += got_coins
	var eq_id: String = _candy_jar_pick_equip(spec["cost"])   # 装备按档费抽1 → 进持久背包(指定星)
	var star: int = int(spec["star"])
	if eq_id != "":
		persistent_bench.append({"id": eq_id, "star": star})
	var got_leveler: bool = false   # 临时等级器按档概率给1个(字符串消耗品进背包)
	if float(spec["leveler"]) > 0.0 and randf() < float(spec["leveler"]):
		persistent_bench.append(TEMP_LEVELER_ITEM.duplicate())   # 消耗品(非装备): kind="item" → 不参与3合1/不当装备渲染
		got_leveler = true
	candy_jar_broken = true
	save()
	return {"tier": tier, "coins": got_coins, "equip": eq_id, "star": star, "leveler": got_leveler}

func _candy_jar_pick_equip(costs: Array) -> String:   # 从 DataRegistry.phase2_equipment 按 cost 抽1
	var pool: Array = []
	for eq in DataRegistry.phase2_equipment:
		if int(eq.get("cost", 0)) in costs:
			pool.append(str(eq.get("id", "")))
	if pool.is_empty(): return ""
	return str(pool[randi() % pool.size()])

## 临时等级器: 用在1只龟/小将 → 本大轮该单位永久+1级(切轮重置). 自存.
func apply_temp_leveler(pet_id: String) -> void:
	candy_temp_levels[pet_id] = int(candy_temp_levels.get(pet_id, 0)) + 1
	save()

## 某单位本大轮临时等级加成 (已接战斗: RealtimeBattle3DScene._make_unit 的 _lvl += temp_level_bonus(id) → 主属性+5%/级)
func temp_level_bonus(pet_id: String) -> int:
	return int(candy_temp_levels.get(pet_id, 0))

## 临时等级器用在【小将】身上: 小将无 pet_id(阵容里只有 kind/role) → 直接把 temp_lv 记在该格子的字典上,
## 随格子一起换位/持久(dual_lineup 已存档). 战斗 _spawn_lane_side 读它加到该小将等级上。
func apply_temp_leveler_minion(lane: String, idx: int) -> bool:
	var dl: Dictionary = get_dual_lineup()
	if not dl.has(lane): return false
	var arr: Array = dl[lane]
	if idx < 0 or idx >= arr.size() or not (arr[idx] is Dictionary): return false
	var u: Dictionary = arr[idx]
	if str(u.get("kind", "")) != "minion": return false
	u["temp_lv"] = int(u.get("temp_lv", 0)) + 1
	save()
	return true

## 从背包移除第一个临时等级器. 成功→true.
func consume_temp_leveler(bench_idx: int) -> bool:
	if bench_idx < 0 or bench_idx >= persistent_bench.size(): return false
	var it = persistent_bench[bench_idx]
	if not (it is Dictionary) or str(it.get("id", "")) != TEMP_LEVELER_ID: return false
	persistent_bench.remove_at(bench_idx)
	save()
	return true

## 某档的奖励预览文本 (UI 用; 不消耗)
func candy_jar_tier_preview(tier: int) -> String:
	if tier < 1 or tier > _CANDY_JAR_TIERS.size(): return ""
	var sp: Dictionary = _CANDY_JAR_TIERS[tier - 1]
	var c: Array = sp["coins"]
	var cost: Array = sp["cost"]
	var lv: float = float(sp["leveler"])
	var costs := []
	for x in cost: costs.append("%d费" % int(x))
	var t := "深海币 %d~%d ｜ %s装备×1 (%d★)" % [int(c[0]), int(c[1]), "/".join(costs), int(sp["star"])]
	if lv > 0.0: t += " ｜ 临时等级器 %d%%" % int(lv * 100.0)
	return t

## 买经验: 4 深海币 = 4 XP (设计§五). 满级/币不足 → false.
func buy_season_xp() -> bool:
	if meta_deepsea_coins < _P2.BUY_XP_COST or season_level >= _P2.MAX_LEVEL:
		return false
	meta_deepsea_coins -= _P2.BUY_XP_COST
	add_season_xp(_P2.BUY_XP_AMOUNT)
	save()
	return true

## 自动 3 合 1 (背包 + 龟身装备一起算, 用户 2026-07-01): 同 id+star 满 3 → 升 1 星, 反复到无可合 (满3星止). 不自存. 买/装/卸后自动调.
## 合出的高星: 若被合的3件里有装在龟身 → 放回那只龟(保持装备; 先移后加故槽位天然安全); 否则回背包. 纯背包合成(优先从背包移)行为与旧版一致.
func auto_merge_all() -> void:
	var changed := true
	while changed:
		changed = false
		var counts := {}
		for it in persistent_bench:
			if not is_equip_item(it): continue          # 消耗品(临时等级器)不参与3合1
			var k := "%s|%d" % [str(it.get("id", "")), int(it.get("star", 1))]
			counts[k] = int(counts.get(k, 0)) + 1
		for pet in persistent_equipped.keys():
			for eit in persistent_equipped[pet]:
				var ke := "%s|%d" % [str(eit.get("id", "")), int(eit.get("star", 1))]
				counts[ke] = int(counts.get(ke, 0)) + 1
		# ★小将(dual_lineup)装的也进合成池(用户2026-07-18「买两件也不合成」根因: 龟身1星在小将上→auto_merge_all原来只扫背包+统领·漏小将→凑不齐3件; 商店"已有N"却算了小将→显示3却不合=矛盾)
		if dual_lineup is Dictionary:
			for lane in ["top", "bottom"]:
				for mu in (dual_lineup.get(lane, []) as Array):
					if mu is Dictionary and (mu as Dictionary).get("equips") is Array:
						for meit in ((mu as Dictionary)["equips"] as Array):
							if meit is Dictionary:
								var km := "%s|%d" % [str(meit.get("id", "")), int(meit.get("star", 1))]
								counts[km] = int(counts.get(km, 0)) + 1
		for k in counts.keys():
			if int(counts[k]) < 3:
				continue
			var parts := str(k).split("|")
			var iid := str(parts[0])
			var star := int(parts[1])
			if star >= 3:
				continue
			var removed := 0
			var host_pet := ""                            # 有统领件被合 → 记第一只龟(升星件放回它)
			var host_lane := ""                           # 或有小将件被合 → 记第一只小将(升星件放回它)
			var host_idx := -1
			var bi := 0                                     # 先从背包移(纯背包合成行为不变)
			while bi < persistent_bench.size() and removed < 3:
				if not is_equip_item(persistent_bench[bi]):
					bi += 1; continue                       # 跳过消耗品
				var bit: Dictionary = persistent_bench[bi]
				if str(bit.get("id", "")) == iid and int(bit.get("star", 1)) == star:
					persistent_bench.remove_at(bi); removed += 1
				else:
					bi += 1
			if removed < 3:                                 # 不够再从统领龟身移
				for pet2 in persistent_equipped.keys():
					var eqs: Array = persistent_equipped[pet2]
					var ei := 0
					while ei < eqs.size() and removed < 3:
						var eit2: Dictionary = eqs[ei]
						if str(eit2.get("id", "")) == iid and int(eit2.get("star", 1)) == star:
							eqs.remove_at(ei); removed += 1
							if host_pet == "": host_pet = str(pet2)
						else:
							ei += 1
					persistent_equipped[pet2] = eqs
					if removed >= 3:
						break
			if removed < 3 and dual_lineup is Dictionary:   # 还不够再从小将(dual_lineup)移
				for lane2 in ["top", "bottom"]:
					var arr2: Array = dual_lineup.get(lane2, [])
					for midx in range(arr2.size()):
						if removed >= 3: break
						var mu2 = arr2[midx]
						if not (mu2 is Dictionary) or not ((mu2 as Dictionary).get("equips") is Array): continue
						var meqs: Array = (mu2 as Dictionary)["equips"]
						var mei := 0
						while mei < meqs.size() and removed < 3:
							var mit = meqs[mei]
							if mit is Dictionary and str(mit.get("id", "")) == iid and int(mit.get("star", 1)) == star:
								meqs.remove_at(mei); removed += 1
								if host_pet == "" and host_lane == "": host_lane = lane2; host_idx = midx
							else:
								mei += 1
						(mu2 as Dictionary)["equips"] = meqs
					if removed >= 3: break
			if host_pet != "":                              # 升星件优先装回统领
				persistent_equipped[host_pet].append({"id": iid, "star": star + 1})
			elif host_lane != "" and host_idx >= 0:         # 否则装回小将
				var hu: Dictionary = (dual_lineup[host_lane] as Array)[host_idx]
				var heq: Array = hu.get("equips", []) if hu.get("equips") is Array else []
				heq.append({"id": iid, "star": star + 1})
				hu["equips"] = heq
			else:
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
	loadouts = {}                     # 新大轮阵容清空 → 技能 3选1 选择也清空(锁定阵容一起重来)
	chest_treasure_value = 0.0        # 藏宝图财宝值/战利品随大轮重置(用户2026-07-16)
	chest_treasures_won = []
	persistent_bench = []
	persistent_equipped = {}
	candy_jar_count = 0
	candy_jar_broken = false
	candy_temp_levels = {}
	gambler_wheel_stacks = {}
	lane_loadout = {}
	dual_lineup = {}
