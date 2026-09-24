extends Node

## GameState — 跨场景状态 (Autoload 单例)

const SAVE_PATH := "user://savegame.json"

# ─── 当前对局 ────────────────────────────────────────────────
var left_team: Array[String] = []
var right_team: Array[String] = []
# 站位 slotKey ("front-0".."back-2"), 与 *_team 平行. 玩家 TeamSelect 摆放结果; 空=用默认前排
var left_slots: Array[String] = []
var right_slots: Array[String] = []
## 玩家每只龟的【3选1】主动技能选择 {pet_id → idx} —— 单个整数(1/2/3)，不是数组。
## TeamSelect 写；战斗端 _resolve_chosen_index 读，缺键→回落 skillPool[1]（旧档数组格式有兼容分支）。
## ★ 2026-07-28 正名：原注释四处全错 —— 5→3、选3→选1、数组→单值、
##   “空=用 defaultSkills”实际是回落 skillPool[1]（与 defaultSkills 无关）。
##   loadouts 是战斗真读的字段，这种注释比没注释更危险。
var loadouts: Dictionary = {}
## 对手(ghost快照)的技能选择 {pet_id → idx}; 匹配到ghost时战斗场景填, 敌侧_resolve_chosen_index读(用户2026-07-15: ghost带技能配置); 不落盘
var foe_loadouts: Dictionary = {}
## 最近匹配过的对手ghost_id(保留3个·防连续遇到同一快照·用户2026-07-15真机纠错); 不落盘
var recent_ghost_ids: Array = []

## 本机的随机安装标识 —— **首次启动生成一次, 之后永不变**(换赛季/清档都保留, 换机器才换)。
##
## ★为什么非有不可(2026-08-27, 接上后端之后暴露的):
##   `ghost_id` 原本是 `g_<赛季>_<三只龟>`, **完全不带"是谁"**。单机本地池里够用
##   (池里只有我自己), 变成共享池之后立刻出两个问题:
##     · **两个玩家用同样三只龟 = 同一个 id** ⇒ 在服务端互相覆盖, 后传的把先传的**抹掉**;
##       而且拉回来时谁也分不清那份是自己的还是撞了 id 的陌生人。
##     · 自己那份从服务器绕一圈回来(带 origin=remote), 会把本地 origin=local 那份顶掉
##       (pool_add 按 ghost_id 去重) ⇒ **打到自己**。
##   ⇒ 把"谁"这一维补进 id。见 `Backend.player_ghost_id`。
##
## ★隐私: 这是【本地生成的随机串】, 不是设备号(IDFV/IDFA), 反查不到人。
##   但方案书原来写"上传内容零个人信息"—— 准确说法现在是"零个人信息 + 一个随机不透明标识"。
var install_uid: String = ""

## ─── D-3 服务端账号(2026-09-21) ─────────────────────────────────────
## ★★这两个字段是**身份**, 不是本轮进度 —— 所以它们走 `install_uid` 那条线:
##   保存 ✓ / 载入 ✓ / **清档保留** / **切大轮不动**。
##   ⚠ 别把它们塞进 `start_new_season()` 里那串归零 —— 那串是「本轮攒了多少」,
##     而账号是「你是谁」。换一轮赛季不换人。
##     (同族教训: `week_anchor_ts` 曾被门禁钉成「切轮后必须 == 0」,
##      而它本该换成新一周的锚点 ⇒ 赛季再也滚不动。见 memory
##      `fb-gate-can-pin-the-bug-in-place` —— 「恒等于零值」的断言要先问这字段本来该干什么。)
## ★`install_uid` 保留但降级: 它是**这台机器**, 只当首次匿名登录的本地凭据, **不做主键**。
##   服务端 `ghosts` 的主键是 `(account_id, season_week, battles)` —— 少了「谁」这一维,
##   两个人会在服务端静默互相覆盖(memory `fb-id-without-owner-dimension`)。
var account_id: String = ""        # Supabase 账号 uuid ("" = 还没登录过 / 后端没配)
## ★★玩家昵称(2026-09-24 · 用户「这个在创建账号应该一起吧」)。
##   在**绑定邮箱**那一屏与邮箱同时填 —— 那是玩家唯一感知得到的「创建账号」时刻。
##   ⚠ 它属于**账号**不属于「这局游戏」: 与 `account_id` / `account_email` 同一条线,
##     大轮切换不清、**清档也不清**。清了的话玩家清一次档就变回兜底短码,
##     而服务器上还是同一个账号 —— 名字对不上。`verify_nickname` 两条分别守着。
var nickname: String = ""
var account_email: String = ""     # 补绑的邮箱 ("" = 匿名账号, 换设备会丢档)
## D-3c 登录续期用的 refresh_token。★**设备本地**: 不上云、清档保留、切轮不动。
##   原来这个值被整个扔掉 ⇒ 重开 App 之后再也拿不到 token(2026-09-21 查实)。
##   服务端每次刷新都会**轮换**它 ⇒ 拿到新的必须立刻写盘(见 SupabaseNet._store_session)。
var auth_refresh: String = ""
## D-8 云存档版本号: 我上次和云端对上的是第几版。★设备本地(不上云), 清档保留。
##   推送时带着它去做「比较并交换」—— 云端版本 ≠ 它 ⇒ 另一台设备动过 ⇒ 冲突, 不覆盖。
##   ★判新旧只看这个号, 不看时间戳: 设备时钟不可信。
var cloud_rev: int = 0


## 取本机安装标识, 没有就现生成一个并落盘。
## ★用 crypto 随机而不是 randi(): 后者受 `TURTLE_SEED` 之类的播种影响,
##   播了种的两台机器会生成**同一个 uid** —— 那就等于没加这一维。
func get_install_uid() -> String:
	if install_uid != "":
		return install_uid
	var c := Crypto.new()
	install_uid = c.generate_random_bytes(6).hex_encode()   # 12 个十六进制字符
	save()
	return install_uid

# 训龟大师 装配(局外持久·用户2026-07-26 更正): 形象 + 【全部技能五选一·单个】。主菜单 TrainerConfig 里配, 战斗读。
# ★设计: {magic_stone(被动), hook, fury_potion, whistle, glacier, hunt_order, tame} 里【只选 1 个】。
# 选被动=没有主动Q; 选主动=没有被动。(2026-07-28 加了 猎龟令/驯服, 五选一 → 七选一)
var trainer_appearance: String = "default"     # 形象 id(对应一张立绘)
var trainer_skill: String = "hook"             # 装配的【唯一】技能 id(被动 magic_stone 或某个主动)

## 派生: 装配的是主动 → 返回该主动 id; 装配的是被动/空 → ""(战斗侧据此知道"没有主动Q")。
func trainer_active_skill() -> String:
	return "" if trainer_skill == "magic_stone" else trainer_skill
## 派生: 装配的是被动 → 返回被动 id; 否则 ""。
func trainer_passive_skill() -> String:
	return "magic_stone" if trainer_skill == "magic_stone" else ""

## "single"  — 自定义单局, 战斗结束回选龟
## "dungeon" — 闯关模式, 战斗结束按胜负进下一关 / 回主菜单
var mode: String = "single"

## 新手教程标记 (1:1 PoC scene data tutorial:true) — 与 mode 正交; mode 仍是玩家可控模式(single)。
##   BattleScene._ready 读取后立即清空 (一次性消费, 不污染下一局)。
var tutorial: bool = false

## ── 新手教程模式 (用户 2026-07-23: 两把战斗+中场商店/图鉴, 沙盒不给奖励) ──
## onboarded: 是否走完过首次教学 → 存档, 只触发一次(删档才再触发)
var onboarded: bool = false
## tutorial_stage: 教学当前阶段(跨场景记住走到哪) —— ""=非教学 / match1 / interlude / match2 / done
var tutorial_stage: String = ""
## tutorial_active: 沙盒开关 —— 为真时不给奖励(不设 season_leaders)、商店免费、固定阵容+弱对手。【不进存档】(运行时态)
var tutorial_active: bool = false
## tutorial_mandatory: 首次强制(无跳过) / ❓重玩(可跳)。【不进存档】
var tutorial_mandatory: bool = false

## 技能说明看【详细】还是【简明】(用户需求1 两级描述)。存这里而不是战斗场的成员变量,
## 是为了跨场景/跨对局记住 —— 玩家对"要不要看公式"的偏好是稳定的, 每局重设很烦。
var skill_text_detail: bool = false

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
## 魔法石攻速叠层的【跨路存档】(用户 2026-07-30 拍板"跨路保留")。
## ★为什么非得存在这里: 换路时 _dl_build_lane_field() 会调 _spawn_trainers() 重建大师,
##   单位字典整个换掉 —— 只在 _dl_start_fight 里"不清零"是没用的, 层数照样归零。
##   双方各存一份: 对面大师也在攒层, 它的层数同样要跟过去。
var dual_ms_stacks: Dictionary = {"left": 0, "right": 0}
## 整局首回合已发被动XP? (TFT风: 第1回合在 Lv1 开打, 被动XP从第2回合起累计 → 不在玩家行动前就跳到 Lv2).
##   每路是独立 BattleScene(turn 各自从1起), 故此旗标必须按【整局】计(reset_dual_lane 重置), 不能按 turn==1.
var dual_passive_xp_started: bool = false
var dual_coins: Dictionary = {"left": 0, "right": 0}   # 双路局内币 (跨上/下/终极持续, 区别于按场重置的 battle_coins)
## PvP 控制方 (见 docs/design/PHASE2-PVP-DESIGN.md): 每方 local/ai/remote. 单机=left本地打右AI.
var side_controllers: Dictionary = {"left": "local", "right": "ai"}
## 战斗随机种子 (权威定+下发; 收口战斗内随机→可复现/回放). 0=未设(用系统随机).
var battle_seed: int = 0

const _DualLane := preload("res://scripts/gamedata/phase2_duallane.gd")
const _P2 := preload("res://scripts/gamedata/phase2_config.gd")
const _Equip := preload("res://scripts/gamedata/phase2_equip.gd")
## 匹配到的对手资料 (野生=模拟真人 / 在线=真人) {name, avatar(pet_id), id}. 匹配动画写, 双路读显.
var dual_opponent: Dictionary = {}
## 新商店货架 (当前掷出的装备, 买掉的位置=null). 局内等级决定费用概率档.
var dual_shop_offer: Array = []
var dual_shop_locked: bool = false   # TFT 式锁店: true → 每回合免费换货跳过(锁住看中的货架)
var dual_shop_refresh_n: Dictionary = {"left": 0, "right": 0}   # ⚠死字段(2026-07-19核实): 无人读写; 且注释描述的两件事都不成立 —— SHOP_REFRESH_STEP=0 刷新费不递增, grant_dual_round 也不重置它。下方 L495 注释说它"已删除"其实没删。
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
	bench_inventory.append(mk_eq(item_id, 1))   # ★装备 dict 一律走 mk_eq(093 的 chg 靠它带)
	# 三合一升星: 战中由 BattleScene._battle_merge_p2eq(扫龟身_p2_equips+备战席,可见) 处理;
	#   持久流(大地图)由 equip_to_turtle/unequip 的 try_merge_all 处理。此处只入席。
	dual_shop_offer[idx] = null
	return true

# ══════════════════════════════════════════════════════════════════════
#  093 香火石: 每件装备实例自己的【香火充能条】—— 全表唯一落进存档的装备实例状态
# ══════════════════════════════════════════════════════════════════════
# 用户 2026-08-06 原话:「充能条是跟着这件香火石走的, 比如跨对局, 上个对局打完是 20/4000,
# 在你背包里就应该是 20/4000, 如果卖掉了就丢失这 20, 如果升星就合并 20 和其他的」。
#
# ★★为什么必须收口成下面两个函数:
#   装备 dict 在本文件里被【重建】的地方有 8 处 —— 买入 / 战中三合一 / try_merge_all 的
#   扁平化·重建·合成件 / 持久流升星 3 处 / 糖果罐奖励。每一处重建都写死 `{"id":…, "star":…}`,
#   **额外字段直接丢**。漏一处 = 充能静默清零, 不报错、不崩、没人会发现。
#   ⇒ 本文件里【不许】再手写 `{"id": …, "star": …}` 造装备, 一律走 `mk_eq`。
#   门禁 tests/verify_incense_stone.gd 把"全链路 chg 不丢"焊死(买→装→攒→升星→存档→读档→卖)。
#
# ★刻痕数【不在这里】: 它是队伍级 + 赛季级的(卖掉一件不减已投的痕), 存 `incense_marks`,
#   随 start_new_season() 清零。充能条是每件自己的, 刻痕池是全队共用的 —— 两者存法不同。
const INCENSE_ID := "p2eq_093"

## 取一件装备的香火充能(不是香火石恒为 0)。
static func eq_chg(it) -> int:
	if not (it is Dictionary):
		return 0
	if str((it as Dictionary).get("id", "")) != INCENSE_ID:
		return 0
	return int((it as Dictionary).get("chg", 0))

## 造一件装备 dict。★本文件里所有"新建/重建装备"都必须经过它。
## 非香火石不写 `chg` 字段 —— 免得给另外 94 件装备的存档凭空加一个永远是 0 的键。
static func mk_eq(id: String, star: int, chg: int = 0) -> Dictionary:
	var d: Dictionary = {"id": id, "star": star}
	if id == INCENSE_ID and chg > 0:
		d["chg"] = chg
	return d


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
				# ★093 香火石: 升星前先把三件的香火充能加起来(用户「升星就合并 20 和其他的」)。
				#   必须在 remove_at 之前取 —— 删完就拿不到了。
				var chg_sum: int = 0
				for ri0 in rm:
					chg_sum += eq_chg(bench_inventory[int(ri0)])
				rm.sort(); rm.reverse()   # 降序删, 防索引错位
				for ri in rm:
					bench_inventory.remove_at(ri)
				bench_inventory.append(mk_eq(item_id, star + 1, chg_sum))
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
				flat.append({"id": str(b.get("id", "")), "star": int(b.get("star", 1)), "pet": "", "chg": eq_chg(b)})
		for pet in equipped_p2:
			var _pet_is_right := str(pet).begins_with(_P2EQ_RIGHT_PREFIX)
			if _pet_is_right != _is_right:
				_other_kept[pet] = equipped_p2[pet]   # 不是本 side → 保留原样, 不参与合成
				continue
			for it in equipped_p2[pet]:
				if it is Dictionary:
					flat.append({"id": str(it.get("id", "")), "star": int(it.get("star", 1)), "pet": str(pet), "chg": eq_chg(it)})
		# 按 id|star 分组, 找一组 ≥3 (star<MAX)
		var groups: Dictionary = {}
		for fi in range(flat.size()):
			var it: Dictionary = flat[fi]
			if int(it["star"]) >= _Equip.MAX_STAR:
				continue
			## ★【不升星】的件直接跳过分组(用户 2026-08-31 小木斧「这个装备不会进行升星」)。
			##   名单在 EquipPool.NO_STAR —— 与"无限张"放同一个文件, 因为它们是同一条被动的两半。
			if _EquipPool.NO_STAR.has(str(it["id"])):
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
				nb.append(mk_eq(str(it["id"]), int(it["star"]), int(it.get("chg", 0))))
			else:
				if not ne.has(it["pet"]):
					ne[it["pet"]] = []
				(ne[it["pet"]] as Array).append(mk_eq(str(it["id"]), int(it["star"]), int(it.get("chg", 0))))
		# ★093: 被合掉的三件的香火充能相加进新件(用户「升星就合并」)
		var m_chg: int = 0
		for mi2 in pick:
			m_chg += int((flat[mi2] as Dictionary).get("chg", 0))
		var merged: Dictionary = mk_eq(m_id, m_star + 1, m_chg)
		var placed: String = ""
		if dest_pet != "":
			var cap: int = _P2.UNIT_EQUIP_CAP   # 2026-07-27 统一规则: 单只上限固定3
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

## 把备战席第 bench_idx 件装到某龟 (pet_id). 单只上限 = _P2.UNIT_EQUIP_CAP(3). 成功 true.
func equip_to_turtle(bench_idx: int, pet_id: String, side: String = "left") -> bool:
	if bench_idx < 0 or bench_idx >= bench_inventory.size():
		return false
	var key := p2eq_key(side, pet_id)
	if not equipped_p2.has(key):
		equipped_p2[key] = []
	if (equipped_p2[key] as Array).size() >= _P2.UNIT_EQUIP_CAP:
		return false
	(equipped_p2[key] as Array).append(bench_inventory[bench_idx])
	bench_inventory.remove_at(bench_idx)
	try_merge_all(side)   # 装备后跨域三合一
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
	var cap: int = _P2.UNIT_EQUIP_CAP   # 2026-07-27 统一规则: 单只上限固定3

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

## 本局我方是不是【横扫】(2-0, 没打终极战场)? —— 终榜排序第三键「胜场 > 余命 > 横扫」。
##
## ★★A3(大轮赛制 v2·2026-09-17)。判据要同时满足两条, 少一条就会误记:
##   ① 两路都有结果 —— **投降局的 `lane_results` 是空字典**(2026-09-17 探针
##      tests/_probe_draw_surrender.gd 实测: 投降后 `{}`、`dual_lane_winner()` 返回 "")。
##      不挡住就会把投降也当成一种"没打终极", 而它压根没打完。
##   ② 两路是【同一方】赢 ⇒ `match_winner` 非空 = 不需要终极战场。
## ★放在这一层而不是主场景: 这里才是持有 `lane_results` 与 `_DualLane` 的地方,
##   在主场景另 preload 一份壳 = 同一判据存两份, 必然落后
##   (memory fb-hand-rolled-copies-drift; 059 沙漏「换路重置该由拥有它的系统负责」同族)。
## 本周期的积分赛配额是不是已经打满? ★★A4(大轮赛制 v2·2026-09-17)。
##
## ★判据放在这一层(数据的主人)而不是主菜单 —— 开局闸与商店锁**两处都要用**,
##   各写一份必然有一处落后(memory fb-hand-rolled-copies-drift)。
## ★用户 2026-09-17 拍板: 配额打满 = **锁开局, 且商店一起锁**
##   (「打满就彻底停下来」; 不做"不计分的练手局" —— U9 已经否掉表演赛, 别换个名字装回来)。
## ⚠ 吃不吃配额的判据在 `_P2.phase_uses_ranked_quota()` —— 与结算记账同一个函数。
##   （闯关赛/决赛日玩法还没上线时它对七天都返回 true, 见那边的长注释。）
##
## ⚠⚠ 这里问的是「**现在**能不能开局 / 开商店」, 而存档里的 `week_phase` 回答的是
##   「**上一场**属于哪个阶段」—— 它写在 TeamSelect 点「开打」那一刻, 之后一直留在存档里。
##   两个不是同一个问题。2026-09-22 查实: 拿存档那个字段当"现在"用, 上周六打过的人
##   在周二开局时会被当成还在闯关赛 ⇒ 配额打满了也放行, 白漏一场。所以这一层**问时钟**。
##   (`now` 只为门禁能喂已知日期; 产品调用一律不传。)
## ─── 闯关赛(周六) ────────────────────────────────────────────
## ⚠ 与 `dungeon_*`(深海闯关, 5 关 PvE 冒险)**毫无关系** —— 同名不同物, 别在这两组字段之间抄代码。
##
## 这一周有没有拿到周六的入场资格。★`promoted` 由 `settle_ranked_close()` 在积分赛收盘后写,
##   判据是硬线 `season_wins >= PROMOTE_WINS_FLOOR`(原稿的「前 30%」要服务端终榜, 还没做)。
func gauntlet_eligible() -> bool:
	return bool(promoted)

## 现在能不能开一局闯关赛。三个条件缺一不可, 每条都有自己的话要对玩家说(见主菜单)。
func gauntlet_can_play(now: int = 0) -> bool:
	var ts: int = now if now > 0 else int(Time.get_unix_time_from_system())
	if _P2.phase_at_utc(ts) != _P2.PHASE_GAUNTLET:
		return false                      # 今天不是周六
	if not gauntlet_eligible():
		return false                      # 这一周没晋级
	return _P2.gauntlet_can_play(int(gauntlet_wins), int(gauntlet_losses))

## 当前战绩状态: running / in / out。★UI 与补发共用这一个答案。
func gauntlet_state() -> String:
	return _P2.gauntlet_state(int(gauntlet_wins), int(gauntlet_losses))

## 打完一场闯关赛 → 记战绩。★只在**周六那一场**调(由结算按阶段分流), 不是每场都调。
func gauntlet_record(won: bool) -> void:
	if won:
		gauntlet_wins = int(gauntlet_wins) + 1
	else:
		gauntlet_losses = int(gauntlet_losses) + 1


## 周六打完一场的**整块记账**, 返回这一场给多少深海币。
## ★★为什么整块在这里而不是在战斗主场景: 积分赛那条公式 `8 + 余命 + 2×已失命 + 胜6`
##   整条都吃 `hearts`, 而周六**没有命这个维度**(原稿: 无命, 公式退化为固定数 8)。
##   两套口径必须**各自成段**, 不能在那条公式里塞 if —— 塞了迟早被人当成同一条一起改坏
##   (同族: CLAUDE.md §3.3「两条独立的伤害路径」)。
## ⚠ **不掉命**、**不吃积分赛配额**、**不记横扫**(横扫只用于积分赛种子排序)。
##   `season_total_battles` 照加 —— 它的含义就是"本大轮打了几场", 周六也是真打了。
func gauntlet_settle(won: bool) -> int:
	season_total_battles += 1
	gauntlet_record(won)
	add_season_xp(int(_P2.GAUNTLET_XP_PER_MATCH))
	axe_on_match_end()                   # 096 小木斧: 打完一整场照常给砍伐经验
	candy_jar_add(1 if won else 4)
	if won:
		season_wins += 1
		season_eggs_killed += 1
	return int(_P2.GAUNTLET_COINS_PER_MATCH)


## 闯关配额补发(只补晋级者)。与积分赛的 `backfill_ranked_quota()` 同构, 返回实际补了几场。
## ★用**另一个**已补计数 `gauntlet_backfill_paid`, 不复用积分赛那个 —— 两笔账混在一个字段里,
##   补过积分赛的人会把闯关的额度吃掉(而且静默)。
func backfill_gauntlet_quota() -> int:
	var owed: int = _P2.gauntlet_backfill_owed(int(gauntlet_wins), int(gauntlet_losses))
	var pay: int = owed - int(gauntlet_backfill_paid)
	if pay <= 0:
		return 0
	## ★钱包是 `meta_deepsea_coins` —— 打一场真给的就是它, 商店花的也是它。
	##   (`coins` 在全仓没有任何消费入口, 补进去等于没发; A7 栽过一次, 别再栽。)
	meta_deepsea_coins += pay * int(_P2.GAUNTLET_BACKFILL_COINS)
	add_season_xp(pay * int(_P2.GAUNTLET_BACKFILL_XP))
	gauntlet_backfill_paid = int(gauntlet_backfill_paid) + pay
	return pay


## 闯关赛收盘(周六 23:00 UTC)之后的惰性补算。返回实际补发场数。
## ★形态与 `settle_ranked_close()` 完全一样(下次打开游戏时补算) —— 离线版没有"收盘"这个事件。
## ★★有效窗口 = 周六 23:00 ~ 周日 23:59(**同一个自然周内**)。理由同积分赛那条:
##   周一换轮会清 `meta_deepsea_coins`, 跨周再补当场作废, 发了等于没发还让账对不上。
##   ⇒ 代价写在明处: **周日一次没开游戏 = 拿不到闯关补发。有意的取舍, 不是漏。**
## ★`now_override` 只给门禁用(同 `settle_ranked_close`): 真实时钟一周只有一天多落在窗口里,
##   不给注入口的话"收盘前不补"与"收盘后补"这两侧永远只能验到一侧。
func settle_gauntlet_close(now_override: int = 0) -> int:
	if week_anchor_ts == 0:
		return 0                                   # 锚点还没初始化, 谈不上收盘
	var now: int = now_override if now_override > 0 else int(Time.get_unix_time_from_system())
	if now < _P2.gauntlet_close_ts(int(week_anchor_ts)):
		return 0                                   # 本周闯关赛还没收盘
	return backfill_gauntlet_quota()


## 发一个头衔。返回 true = **真的加了一条**(已经有了就返回 false, 不重复加)。
## ★去重按 `{id, week}`: 同一周把配额打满两次不该变成两个头衔。
## ★还没上线的档(四强/冠军)在这里就拦掉 —— 与门那一套同一条闸,
##   免得哪天有人先接了调用点、玩法却还没上, 悄悄发出不该有的头衔。
func award_title(tid: String, week: int = 0) -> bool:
	if not _P2.title_earnable(tid):
		return false
	var wk: int = week if week > 0 else int(week_anchor_ts)
	if wk <= 0:
		return false                      # 赛程还没初始化, 这时发了记不清是哪一周
	if _P2.title_has(titles, tid, wk):
		return false
	titles.append(_P2.title_row(tid, wk))
	return true


## 本周该拿的头衔一次性补齐(惰性: 每次结算后调一下就行)。返回新加了几条。
## ★★为什么是"补齐"而不是"在那一刻发": 离线版没有"那一刻"这个事件 ——
##   与补发(`settle_ranked_close`)同一个理由。配额是打满的那一场结束时满的,
##   而晋级是周五收盘后算出来的, 两件事发生在不同时刻, 统一在这里对一次账。
func sync_titles() -> int:
	var got := 0
	if int(ranked_used) >= int(_P2.RANKED_QUOTA):
		if award_title(_P2.TITLE_FULL_QUOTA):
			got += 1
	if bool(promoted):
		if award_title(_P2.TITLE_FINALS_DAY):
			got += 1
	return got


## 打完一场 → 该不该吃掉一格积分赛配额。★与开闸的 `ranked_quota_full()` 共用
##   `_P2.phase_uses_ranked_quota()` 这一个判据。
## ⚠ 入参是【这一场】的阶段(存档里的 `week_phase`, 点「开打」那一刻写的),
##   而 `ranked_quota_full()` 问的是【现在】—— 两者问的本来就是两个问题, 不是抄漏了。
func consume_ranked_quota() -> void:
	if _P2.phase_uses_ranked_quota(str(week_phase)):
		ranked_used += 1


func ranked_quota_full(now: int = 0) -> bool:
	var ts: int = now if now > 0 else int(Time.get_unix_time_from_system())
	if not _P2.phase_uses_ranked_quota(_P2.phase_at_utc(ts)):
		return false                      # 闯关赛/决赛日不吃积分赛配额, 自然谈不上打满
	return int(ranked_used) >= int(_P2.RANKED_QUOTA)


func dual_lane_was_sweep() -> bool:
	if not (lane_results is Dictionary) or (lane_results as Dictionary).is_empty():
		return false
	if not _DualLane.lanes_done(lane_results):
		return false
	return str(_DualLane.match_winner(lane_results)) == "left"

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
## 局外商店货架(V2 ShopScene)。★必须持久化 —— 2026-07-21 前它只是 ShopScene 的局部变量,
## 于是【每次退出重进商店都重新掷货】: 买掉的位子会复活、看中的货被冲掉(用户报的 bug)。
## 存的是 [{"id":..,"star":..} | null], null = 该位已买走。跨场景/重启都保留。
var meta_shop_offer: Array = []
## 掷这批货时的 season_total_battles。打完新的一场(该值变化)才自动换新货架, 否则一直保留。
var meta_shop_battles: int = -1
var season_id: int = 1                                # 第几大轮赛季 (★一个自然周一轮, 切轮全重置)
var season_start_ts: int = 0                          # 本赛季开始 unix 时间戳 = 本周一 00:00 UTC (0=未初始化)
var hearts: int = 8                                   # 命数 (8起, 输-1, 0=淘汰; 玩法在阶段4)
var season_total_battles: int = 0                     # 本赛季总战斗数 → 决定装备槽 0/1/2/3/4
var season_eggs_killed: int = 0                       # 本赛季击杀龟蛋数 (排行榜口径)
var season_wins: int = 0                              # 本赛季胜场数 (实时战斗赢一场+1; 排行指标候选)

## ─── 大轮赛制 v2 · 周赛制 (A2, 2026-09-17) ───────────────────────────
## ★每个字段都要走【五处】: 声明 / 保存 / 载入 / reset_save / start_new_season。
##   漏任何一处都**不会报错**, 只会在切轮或重启后悄悄漂 —— 门禁 verify_week_season 就是守这个。
var ranked_used: int = 0            # 积分赛已用场次 (配额 RANKED_QUOTA; 闯关/决赛日的场次不吃它)
var season_sweeps: int = 0          # 横扫(2-0)数 —— 终榜排序第三键「胜场 > 余命 > 横扫」
var backfill_paid: int = 0          # 补发【已发】场次 (幂等: 只补差额, 重复调用不再给)
## ★闯关赛的补发【另记一笔】—— 与积分赛混在一个字段里, 补过积分赛的人会把闯关额度吃掉(而且静默)。
var gauntlet_backfill_paid: int = 0 # 闯关补发【已发】场次 (同样幂等)
var week_phase: String = ""         # 赛程阶段: "" 未定 / rest / ranked / gauntlet / finals
var week_anchor_ts: int = 0         # 本自然周的锚点 (UTC 周一 00:00 的 unix 秒) —— ★赛季换不换轮**只看它**
var gauntlet_wins: int = 0          # 闯关赛战绩: 胜
var gauntlet_losses: int = 0        # 闯关赛战绩: 负
## ★★头衔(E-B5 · D12 四档): 一条 `{id, week}`。
##   **跨大轮保留、清档也不清** —— 这是玩家唯一的永久资产
##   (先例: `install_uid` / `account_id` 也是"清的是这局游戏, 不是你是谁")。
##   ⚠ 它**不在** `start_new_season()` 与 `reset_save()` 的清除名单里, 这是有意的;
##     `verify_titles` 两条分别守着, 加进任何一处清除名单都会当场红。
var titles: Array = []
var promoted: bool = false          # 是否已晋级(积分赛 → 周六)
## 093 香火石【香火刻痕】的刻痕池 —— 队伍级 + 赛季级(用户 2026-08-06「一大轮重置」,
## 而代码里「一大轮」就是赛季, 见上面 season_id 的注释「一个自然周一轮, 切轮全重置」)。
## ★为什么刻痕存这里、而充能条存在装备实例上(见 mk_eq / eq_chg):
##   用户原话「如果卖掉了就丢失这 20」——**只有那 20 点充能会丢**, 已经投进羁绊的刻痕不退。
##   ⇒ 刻痕是全队共用的一个池(多件香火石各自攒充能、共投这一个池), 与某一件的存亡无关。
## ★上限 300(用户原文)。上限判定在写入侧(IncenseStoneSystem), 这里只负责存。
var incense_marks: int = 0                            # 093 香火石: 本赛季已刻的香火刻痕数 (0~300)
## 093 香火【充能条】(0~4000)。★与刻痕同一个池子: 整条香火挂在羁绊上, 装备只是开关
##   (用户 2026-08-13:「羁绊里有多少刻痕和充能都是重新激活状态…就接着激活啊」)。
##   ★这里【曾经】存在装备实例的 `chg` 字段里 ⇒ 卖掉再买充能归零、刻痕却还在, 两半各走各的。
var incense_charge: int = 0
## 096 小木斧【砍伐经验】—— 照 093 香火石的先例做成**赛季级**(用户 2026-08-31「随大轮重置」;
##   代码里「一大轮」就是赛季, 见上面 season_id 的注释)。
## ★★这里是**两个**字段, 不是一个 —— 未决点 ⑥ 拍板「历史累计」之后必然如此:
##   · `axe_exp_bar`   进度条: 攒到阈值就**清零**(进化), 大轮也清零 → 只有进化判定读它
##   · `axe_exp_total` 历史累计: **只增不减**, 大轮才清零 → 召唤物的血/攻公式读它
##   一次加经验必须**同时写两边**。只验其中一个等于没验(门禁 verify_axe 有专门一条)。
## ★四期才接上"怎么攒"(买+15/打完一场+10/击杀+2); 三期只是让读的一侧有东西可读。
var axe_exp_bar: int = 0
var axe_exp_total: int = 0
var axe_stage: int = 0                                # 档位下标(0=木斧, 见 AxeEvolution.STAGES)
var axe_final: String = ""                            # 最终造物 key(空=还没选; 选完本大轮锁定)
## 本大轮内【斧头羁绊处于激活状态】时打完的局数 → 出货概率的「局数×0.1%」那一项。
## ★不是 season_total_battles: 那是本赛季**所有**场次, 而需求说的是"激活羁绊【后】"的局数
##   (2026-08-31 用户原话「玩家激活斧头羁绊时在这大轮游戏的局数」)。拿总场次当它 = 白送概率。
var axe_syn_matches: int = 0
var season_level: int = 1                             # 大轮等级 1-10 (每场+2经验累积, 可买经验; 驱动商店出货档 + 装备槽; 用户 2026-06-27)
# ★装备私人池 (2026-08-03 批2, 方案书 §4.6·D6/D20~D23): {装备id: 剩余张数}, -1 = 已满3★冻结。
#   在此之前商店是【无限张有放回】—— 想要几件同款就有几件, 3★ 只受钱和运气限制。
#   池只在【买 / 卖 / 满星冻结 / 赛季重置】四个时刻变, 与货架无关(D23: 成交才扣) ——
#   这让存档不必和 meta_shop_offer 成对回滚, 也是选 D23 的第三条理由。
var equip_pool: Dictionary = {}
const _EquipPool := preload("res://scripts/gamedata/equip_pool.gd")
const _P2T := preload("res://scripts/gamedata/phase2_types.gd")   # 类型映射(圣光护盾按盾件数发)
const _AxeEvo := preload("res://scripts/gamedata/axe_evolution.gd")  # 096 小木斧: 档位/阈值/出货概率的唯一事实源
var debug_level: int = 0                              # 调试器: >0 强制全体战斗单位等级(测试用, 正式版用外部快照); 0=用真实等级
var season_xp: int = 0                                # 大轮等级当前经验 (满 xp_to_next(level) 升级)
var chest_treasure_value: float = 0.0                 # 宝箱藏宝图·财宝值(随一大轮累积·用户2026-07-16)
var chest_treasures_won: Array = []                   # 宝箱藏宝图·本大轮已开战利品id(常驻整轮·最多5件)
var season_leaders: Array = []                        # 本赛季锁定的 3 统领 id (整轮不可换)
var persistent_bench: Array = []                      # 持久背包 [{id,star}] (装备永不丢; build 源, 取代局内临时 bench_inventory)
var persistent_equipped: Dictionary = {}             # 持久 build {pet_key → [{id,star}]} (build 源, 取代局内临时 equipped_p2)

# ═══ 装备容量 (统一规则·用户 2026-07-27) ═════════════════════════════
# 单只 ≤ _P2.UNIT_EQUIP_CAP(3) 且 全队 6 只合计 ≤ _P2.team_equip_cap(赛季等级)。完全自由分配。
# 规则定义与来龙去脉见 scripts/gamedata/phase2_config.gd 的「装备容量」段。

# ══════════════════════════════════════════════════════════════════════
#  ★羁绊赠送的装备【不占任何容量】(2026-08-03 · 盾羁绊 3/6 档送「圣光护盾」)
#  · 不占全队 team_equip_cap, 也不占单只 UNIT_EQUIP_CAP
#  · 不进商店、不进私人池(shopAvailable=0)、不参与三合一
#  · 羁绊掉档就【收回】—— 它是羁绊的一部分, 不是你买来的东西
#  ⇒ 所有"数装备件数"的地方都要跳过它, 漏一处就会出现"明明没满却装不上"。
# ══════════════════════════════════════════════════════════════════════
const SYNERGY_GRANT_IDS := ["p2eq_095"]        # 圣光护盾

static func is_synergy_grant(item) -> bool:
	return item is Dictionary and str((item as Dictionary).get("id", "")) in SYNERGY_GRANT_IDS


## 一个装备数组里【占容量】的件数(跳过羁绊赠送的)。
static func _cap_count(arr) -> int:
	if not (arr is Array):
		return 0
	var n := 0
	for it in (arr as Array):
		if not is_synergy_grant(it):
			n += 1
	return n


## 当前阵容统领 id 列表(season_leaders, 空时回退 lastLineup.json)。
## ★单一事实源(2026-08-11): 原本只住在 InventoryScene._lineup_ids, 商店羁绊信息栏也要用
##   ⇒ 提上来共用(memory [[fb-hand-rolled-copies-drift]]: 手抄的副本必然落后)。
func lineup_leader_ids() -> Array:
	if season_leaders is Array and (season_leaders as Array).size() > 0:
		return season_leaders.duplicate()
	if FileAccess.file_exists("user://lastLineup.json"):
		var f := FileAccess.open("user://lastLineup.json", FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and (parsed as Dictionary).has("ids"):
				return (parsed["ids"] as Array).duplicate()
	return []


## 全队(当前统领 + 双路小将)身上的装备清单 —— 【羁绊口径】: 只数已装上的, 替补席不算。
## ★与背包羁绊面板(InvSynergy)/战斗侧(SynergySystem 数 battle._units)同口径;
##   计数去重(calc_active 按 id 去重)发生在 Phase2Types, 这里只负责收集。
## 当前阵容的【羁绊行】—— 商店总览条与出战页 chips 共用这一份。
## 返回 [{"t": 类型名, "n": 件数, "tier": 已激活档位(0=未激活), "need": 距下一档还差几件(-1=已顶档)}]
## 排序: 已激活的在前(档位高的更前), 其次"差得最少"的 —— 玩家最关心"再买一件就升档"。
##
## ★口径与战斗完全一致: 只数【装在身上】的、**按装备 id 去重**(带两件一模一样的剑只算 1)。
##   ⚠ 不数背包 —— "买到 ≠ 装上"(2026-08-12 圣光护盾白送 bug 的同一条教训)。
## ★这段【曾经】只长在 ShopScene 里; 2026-08-12 出战页也要显示羁绊时抽到这里, 而不是
##   照抄一份过去 —— 去重口径/差几件/排序三样都容易抄漂, 两处显示不一致玩家会当成 bug。
func synergy_rows() -> Array:
	var counts: Dictionary = {}
	var seen: Dictionary = {}
	for it in team_p2_equips_for_synergy():
		if not (it is Dictionary):
			continue
		var iid := str((it as Dictionary).get("id", ""))
		if iid == "" or seen.has(iid):
			continue
		seen[iid] = true
		## ★按【全部类型】数: 093 香火石同时算遗物与香火(用户 2026-08-13)
		for t in _P2T.types_of(iid):
			counts[str(t)] = int(counts.get(str(t), 0)) + 1
	var rows: Array = []
	for t2 in counts.keys():
		if not _P2T.TYPES.has(t2):
			continue
		var n: int = int(counts[t2])
		var tiers: Array = (_P2T.TYPES[t2] as Dictionary).get("tiers", [])
		var tier := 0
		var need := -1
		for k in range(tiers.size()):
			if n >= int(tiers[k]):
				tier = k + 1
			elif need < 0:
				need = int(tiers[k]) - n
		rows.append({"t": t2, "n": n, "tier": tier, "need": need,
			"tiers_n": tiers.size()})
	rows.sort_custom(func(a, b):
		if int(a["tier"]) != int(b["tier"]):
			return int(a["tier"]) > int(b["tier"])
		var na: int = int(a["need"]) if int(a["need"]) >= 0 else 99
		var nb: int = int(b["need"]) if int(b["need"]) >= 0 else 99
		return na < nb)
	return rows


func team_p2_equips_for_synergy() -> Array:
	var all_equips: Array = []
	for pid in lineup_leader_ids():
		for it in persistent_equipped.get(str(pid), []):
			all_equips.append(it)
	var dl: Dictionary = get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if u is Dictionary and str((u as Dictionary).get("kind", "")) == "minion" and (u as Dictionary).get("equips", null) is Array:
				for it in (u as Dictionary).get("equips", []):
					all_equips.append(it)
	return all_equips


## 全队(当前 3 统领 + dual_lineup 里的 3 小将)已装备总件数 —— 新规则的分母。
## ★只数【当前阵容上】的: persistent_equipped 里可能残留已不在队的老龟, 那些不占容量。
## ★羁绊赠送的装备不计入(见上)。
func team_equipped_count() -> int:
	var n := 0
	for pid in (season_leaders if season_leaders is Array else []):
		n += _cap_count(persistent_equipped.get(str(pid), []))
	var dl: Dictionary = get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if u is Dictionary and str((u as Dictionary).get("kind", "")) == "minion":
				n += _cap_count((u as Dictionary).get("equips", []))
	return n


## 盾羁绊档位 → 该发几个圣光护盾(3档1个 / 6档2个 / 9档2个)。
## ★数的是【当前阵容全队】的盾件数, 按装备 id 去重(与战斗侧同口径)。
func shield_grant_count() -> int:
	## ★★圣光护盾是【盾羁绊档位】的产物 —— 所以它必须【由档位推导】, 不能另抄一套数盾逻辑。
	##   (2026-08-12 用户:「盾是根据羁绊档位来发放的临时装备, 为啥会没有羁绊而出现圣盾,
	##    这是底层没理解到位啊」——说到根子上了。)
	##   原来这里手写了一份"数盾件数 + 自己的 3/6 阈值 + 自己的去重", 而且把【背包】也算了 ⇒
	##   出现"羁绊档位 0 却送了圣盾"。手抄的副本必然落后(memory fb-hand-rolled-copies-drift):
	##   阈值一改、计数域一改, 两边就分家。
	##   现在只问一句: 盾羁绊现在是第几档? 档位怎么算是 Phase2Types 的事, 这里不重复实现。
	##   逐档赠送数(权威文档 TIER_DESCS["盾"]): 档1 送 1 件 / 档2 再送 1 件(共 2) / 档3 不再增。
	var tier := 0
	for a in _P2T.calc_active([{"_p2_equips": team_p2_equips_for_synergy()}]):
		if not (a is Dictionary):
			continue
		if str((a as Dictionary).get("type", "")) == "盾":
			tier = int((a as Dictionary).get("tier", 0))
	return [0, 1, 2, 2][clampi(tier, 0, 3)]


## 按当前盾羁绊档位【补发 / 收回】圣光护盾。任何会改变盾件数的操作之后都要调。
## ★收回时【装在龟身上的也要拿走】—— 掉档就该消失, 留着等于白嫖一件永久装备。
func sync_synergy_grants() -> void:
	var want: int = shield_grant_count()
	var have: Array = []          # [[容器数组, 下标], …]
	for pid in persistent_equipped.keys():
		var arr: Array = persistent_equipped[pid]
		for i in range(arr.size()):
			if is_synergy_grant(arr[i]):
				have.append([arr, i])
	var dl: Dictionary = get_dual_lineup()
	for lane in ["top", "bottom"]:
		for u in (dl.get(lane, []) as Array):
			if u is Dictionary and (u as Dictionary).get("equips") is Array:
				var ea: Array = (u as Dictionary)["equips"]
				for i in range(ea.size()):
					if is_synergy_grant(ea[i]):
						have.append([ea, i])
	for i in range(persistent_bench.size()):
		if is_synergy_grant(persistent_bench[i]):
			have.append([persistent_bench, i])
	if have.size() == want:
		return
	if have.size() < want:
		for _i in range(want - have.size()):
			persistent_bench.append({"id": "p2eq_095", "star": 1})
	else:
		# 多了就收回。★从后往前删, 否则删了前面的会让后面记录的下标全部错位。
		have.reverse()
		for k in range(have.size() - want):
			var arr2: Array = have[k][0]
			var idx: int = int(have[k][1])
			if idx >= 0 and idx < arr2.size() and is_synergy_grant(arr2[idx]):
				arr2.remove_at(idx)


## 本赛季等级下全队可装总数。
func team_equip_cap() -> int:
	return _P2.team_equip_cap(int(season_level))


## 还能再装吗(只看全队预算; 单只上限由调用方另判)。
func team_has_equip_room() -> bool:
	return team_equipped_count() < team_equip_cap()


## ★老存档迁移(2026-07-27 换装备容量规则): 把超出新上限的装备【彻底删除】。
## ⚠ 破坏性: 用户 2026-07-27 明确「U1要彻底消除」—— 不回背包、不折算深海币, 直接销毁。
##   (初版是"卸回背包一件不丢", 用户改口径为彻底删除。)
## 两步, 都优先保留强的(强度 ≈ 费×星, 与门禁同口径的简化) —— 删的永远是最弱的那些:
##   ① 每只单位裁到 ≤ UNIT_EQUIP_CAP
##   ② 若全队仍超 team_equip_cap, 从最弱的开始删
## 幂等: 已合规的存档跑一遍什么也不动。返回【删除】的件数(0 = 无需迁移)。
func migrate_equip_caps() -> int:
	var moved := 0
	var val := func(it) -> int:
		var e: Dictionary = DataRegistry.phase2_equipment_by_id.get(str((it as Dictionary).get("id", "")), {}) if DataRegistry != null else {}
		return maxi(1, int(e.get("cost", 1))) * maxi(1, int((it as Dictionary).get("star", 1)))

	# ① 单只裁到 3 (保留最强的 3 件)
	for pid in (season_leaders if season_leaders is Array else []):
		var p := str(pid)
		var arr: Array = persistent_equipped.get(p, [])
		if arr.size() > _P2.UNIT_EQUIP_CAP:
			arr.sort_custom(func(a, b): return val.call(a) > val.call(b))
			while arr.size() > _P2.UNIT_EQUIP_CAP:
				arr.pop_back()          # 彻底删除(用户口径), 不回背包
				moved += 1
			persistent_equipped[p] = arr
	var dl: Dictionary = get_dual_lineup()
	for lane in ["top", "bottom"]:
		var lst: Array = dl.get(lane, [])
		for i in range(lst.size()):
			var u: Dictionary = lst[i]
			if str(u.get("kind", "")) != "minion":
				continue
			var me: Array = u.get("equips", []) if u.get("equips", null) is Array else []
			if me.size() > _P2.UNIT_EQUIP_CAP:
				me.sort_custom(func(a, b): return val.call(a) > val.call(b))
				while me.size() > _P2.UNIT_EQUIP_CAP:
					me.pop_back()       # 彻底删除
					moved += 1
				u["equips"] = me
				lst[i] = u
		dl[lane] = lst
	dual_lineup = dl

	# ② 全队超预算 → 从最弱的往回卸
	var guard := 0
	while team_equipped_count() > team_equip_cap() and guard < 64:
		guard += 1
		var worst_v := 1 << 30
		var worst_p := ""
		var worst_lane := ""
		var worst_i := -1
		var worst_ci := -1
		for pid in (season_leaders if season_leaders is Array else []):
			var p := str(pid)
			var arr: Array = persistent_equipped.get(p, [])
			for ci in range(arr.size()):
				if val.call(arr[ci]) < worst_v:
					worst_v = val.call(arr[ci]); worst_p = p; worst_lane = ""; worst_ci = ci
		var dl2: Dictionary = get_dual_lineup()
		for lane in ["top", "bottom"]:
			var lst2: Array = dl2.get(lane, [])
			for i in range(lst2.size()):
				var u2: Dictionary = lst2[i]
				if str(u2.get("kind", "")) != "minion":
					continue
				var me2: Array = u2.get("equips", []) if u2.get("equips", null) is Array else []
				for ci in range(me2.size()):
					if val.call(me2[ci]) < worst_v:
						worst_v = val.call(me2[ci]); worst_p = ""; worst_lane = lane; worst_i = i; worst_ci = ci
		if worst_ci < 0:
			break
		if worst_p != "":
			var a3: Array = persistent_equipped[worst_p]
			a3.remove_at(worst_ci)      # 彻底删除
			persistent_equipped[worst_p] = a3
		else:
			var lst3: Array = dl2.get(worst_lane, [])
			var u3: Dictionary = lst3[worst_i]
			var me3: Array = u3.get("equips", [])
			me3.remove_at(worst_ci)     # 彻底删除
			u3["equips"] = me3; lst3[worst_i] = u3; dl2[worst_lane] = lst3
			dual_lineup = dl2
		moved += 1
	return moved

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
	## ★这一句必须在 `_load()` / `ensure_season()` 之前 —— 2026-09-19 探针实证:
	##   全新空 user:// 下, **场景脚本拿到控制权时 `savegame.json` 已经写出来了**
	##   (`ensure_season()` 滚赛季会 `save()`), 所以任何台子在自己 `_ready` 里置
	##   `test_mode` 都**来不及**, 开机那一刻存档就被改写了。
	apply_save_guard(DisplayServer.get_name() == "headless",
		OS.has_environment(NO_SAVE_ENV),
		cmdline_scene_override(OS.get_cmdline_args(),
			str(ProjectSettings.get_setting("application/run/main_scene", ""))))
	_load()
	if fullscreen and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)   # 开机恢复全屏(设置持久化)
	_pc_window_setup()
	ensure_season()   # V2: 初始化/滚动赛季 (阶段4)
	_start_net_keepalive()
	# 把存档音量同步给 Audio autoload
	if Engine.has_singleton("Audio") or get_node_or_null("/root/Audio"):
		Audio.bgm_volume = bgm_volume
		Audio.sfx_volume = sfx_volume


# ════════════════════════════════════════════════════════════════════════
#  D-8 云存档 (2026-09-21 用户「需要存档同步的」)
# ════════════════════════════════════════════════════════════════════════
## ★★设备本地、**永不进云**的键。
##   · 音量 / 全屏 / 画质 —— 这台设备的偏好, 换到另一台不该跟过去
##   · install_uid —— 这台设备的标识
##   · account_id / account_email / auth_refresh —— **身份只来自登录, 永远不许从存档里读**
##     (否则改一份云存档就能让别的设备「变成」另一个号)
##   · cloud_rev —— 同步元数据, 由服务端回包决定
const DEVICE_LOCAL_KEYS := ["bgm_volume", "sfx_volume", "fullscreen", "perf_lite",
	"install_uid", "account_id", "account_email", "auth_refresh", "cloud_rev"]


## 要上云的那一份: 全部字段减去设备本地键。
func cloud_payload() -> Dictionary:
	var d := _save_dict()
	for k in DEVICE_LOCAL_KEYS:
		d.erase(k)
	return d


## 把云存档应用到本机。★设备本地键**一律用本机现值**, 云端那份里就算带了也不认。
func apply_cloud_payload(p: Dictionary, rev: int) -> void:
	var merged: Dictionary = p.duplicate(true)
	var here := _save_dict()
	for k in DEVICE_LOCAL_KEYS:
		merged[k] = here[k]
	_apply_save_dict(merged)
	cloud_rev = rev
	ensure_season()          # 云端那份可能是上一周的 ⇒ 让赛季逻辑自己滚
	save()


## 把【当前内存里】的存档另存一份, 返回路径("" = 没写)。取回 / 冲突时用云端覆盖之前先调它。
## ★写的是内存里的 `_save_dict()` 而不是复制磁盘文件 —— 两者在大多数时候相同,
##   但「内存里刚改、还没落盘」那一刻只有前者是对的。
## ★test_mode 下不写(门禁 / 调试台不许往 user:// 乱丢文件), 门禁自己临时开闸再量。
func backup_save(tag: String) -> String:
	if test_mode:
		return ""
	var path := "user://savegame.before-%s-%d.json" % [tag, int(Time.get_unix_time_from_system())]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(_save_dict(), "  "))
	f.close()
	return path


## D-3c 登录保活 + D-8 存档同步: 每 20 秒一拍。会话剩不到 5 分钟就续; 存档脏了就推。
## ★为什么挂在这里: 玩家大部分时间在战斗场里, 不在主菜单 —— 挂在哪个场景上
##   都会在离开那个场景时断掉。GameState 是唯一全程活着的节点。
## ★test_mode 下**不跑**: 门禁要自己决定什么时候调 `ensure_signed_in_async`,
##   后台一拍冷不丁 spawn 一个节点会让「数子节点」的判据偶发红。
const _SB_NET := preload("res://scripts/net/supabase.gd")

func _start_net_keepalive() -> void:
	var t := Timer.new()
	t.name = "NetKeepalive"
	t.wait_time = 20.0          # D-8: 存档最多晚 20 秒上云
	t.autostart = true
	t.timeout.connect(_net_tick)
	add_child(t)


func _net_tick() -> void:
	if test_mode:
		return
	_SB_NET.ensure_signed_in_async()
	_SB_NET.maybe_push_save()


## 手机切回前台时立刻续一次 —— 在后台放了一小时回来, token 早过期了,
## 等下一拍(最多 60 秒)才续的话, 这段时间里的上传全会被拒。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and not test_mode:
		_SB_NET.ensure_signed_in_async()
	## D-8: 切后台 / 关窗口时立刻推一次 —— 手机上切到后台之后进程随时会被系统杀掉,
	##   等下一拍(最多 20 秒)可能就没有下一拍了。
	if (what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST) \
			and not test_mode:
		_SB_NET.maybe_push_save(true)


## PC 板窗口行为(用户 2026-08-01:「pc端要随便拉，支持全屏」)。
## 全屏与 F11 早就有(见下方 _unhandled_key_input + 设置页开关), 这里只补【最小窗口尺寸】——
## 少了它, 用户可以把窗口拖到 200×100, 那时 UI 字号小到点不动, 看着像"界面坏了"。
## ★640×360 = 设计尺寸 1280×720 的正好一半, 也是像素画常用的 1/2 整数比。
## ★只在桌面平台设: 手机/网页没有可拖拽窗口, 设了是空操作但会在 headless 下多一次 DisplayServer 调用。
func _pc_window_setup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not (OS.has_feature("pc") or OS.has_feature("windows") or OS.has_feature("macos") or OS.has_feature("linuxbsd")):
		return
	var w := get_window()
	if w != null:
		w.min_size = Vector2i(640, 360)


## 全局全屏切换: F11 / Alt+Enter.
## (画面靠 stretch=canvas_items + aspect=expand: 比 16:9 宽→锁高 720 宽变大; 比 16:9 窄→锁宽 1280 高变大。
##  两种情况内容都【不会被挤扁】, 只是多出空地 —— 多出来的地方由 UIFrame 设计框居中吃掉。
##  ★2026-08-01 修注释: 这里原本写 "aspect=keep", 而项目里早就是 expand —— 差别正是
##  "留黑边等比缩放" vs "视口跟着比例长", 照着旧注释推理会得出完全相反的结论。)
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

## 记一场对局 (BattleEnd 调) — 最新在前, 封顶 50
func record_match(result: String, lineup: Array, mode_str: String, turn_num: int) -> void:
	match_history.insert(0, {"result": result, "lineup": lineup, "mode": mode_str, "turn": turn_num})
	if match_history.size() > 50:
		match_history.resize(50)
	save()


# ─── 当前对局 ────────────────────────────────────────────────

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

## ★★【第二道闸】`NO_SAVE=1`(2026-09-19) —— headless 那道闸**盖不住要渲染的台子**。
##   VFXLAB / 评审台 / 调试场 / 截图台都必须真渲染 ⇒ 都不是 headless ⇒ 上面那句不触发。
##   而 `_ready()` 里 `ensure_season()` 会 `save()`, **开机那一刻就把玩家存档改写了**,
##   台子自己再怎么置 `test_mode` 也晚了(探针 `tests/_probe_save_pollution.gd` 实证:
##   全新空 user:// 下, 场景 `_ready` 时刻 `savegame.json` 已存在 · test_mode=false)。
##   存档目录里那两个 `savegame.json.bak-*-被测试污染` / `-被演示污染` 就是历史账。
##   ⇒ 凡是「要渲染但不是玩家在玩」的进程, 一律带 `NO_SAVE=1`。
const NO_SAVE_ENV := "NO_SAVE"

## 该不该开存档保护。返回 "" = 不开; 返回非空 = 开, 内容是**原因**(给测试与日志看)。
## ★写成【纯函数 + 参数注入】不是直接读环境: 这样门禁能把四种组合逐个喂进来验,
##   而不是"门禁自己喂那个字段再去测它"(恒真式)。真入口在 `_ready()` 里注入真值。
## ★★【第三道闸】命令行给了一个**不是主场景**的场景路径 ⇒ 这是台子/测试, 不是玩家在玩。
##   为什么这个信号可靠: 导出版**禁用了 `disable_path_overrides`**(CLAUDE.md §6) ——
##   打包后给场景路径会直接 Abort ⇒ **真玩家的进程里不可能出现这个参数**。
##   为什么要它而不只靠 `NO_SAVE=1`: 第二道闸得靠我每次记得敲, 而「靠记性」这条防线
##   在本项目已经塌过两次(存档目录里那两个 `.bak-*-被污染`)。这一道**不用任何人记得**。
##   ⚠ 主场景本身不算(编辑器 F5 跑主场景 = 正常试玩, 锁了等于存档永远不落盘)。
static func cmdline_scene_override(args: PackedStringArray, main_scene: String) -> String:
	for a in args:
		var s := str(a)
		if (s.ends_with(".tscn") or s.ends_with(".scn")) and s != main_scene:
			return s
	return ""


static func save_guard_reason(is_headless: bool, has_no_save_env: bool,
		scene_override: String = "") -> String:
	if is_headless:
		return "headless"
	if has_no_save_env:
		return NO_SAVE_ENV
	if scene_override != "":
		return "scene:" + scene_override
	return ""

## 真正置位的那一步。返回原因("" = 没开闸)。
## ★为什么把「判」与「置」分开写成两个可注入的函数: 门禁得能**真走到置值那一步**。
##   只验纯函数的话, 把 `_ready` 里的调用整条删掉门禁照样绿
##   —— 就是本项目记过的「写了没人读」/「判据没错但被测对象不在场」。
func apply_save_guard(is_headless: bool, has_no_save_env: bool,
		scene_override: String = "") -> String:
	var reason := save_guard_reason(is_headless, has_no_save_env, scene_override)
	if reason != "":
		test_mode = true
	return reason

## ★D-8(2026-09-21): 存档的【全部字段】只在这一处列出 ——
##   本机文件(`save()`)与云存档(`cloud_payload()`)都从这里取。
##   各写一份的话, 下一个加字段的人只会加一边, 换设备取回时那个字段就静默丢了。
func _save_dict() -> Dictionary:
	return {
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
		"meta_shop_offer": meta_shop_offer,
		"meta_shop_battles": meta_shop_battles,
		"install_uid": install_uid,      # 本机随机安装标识(见 get_install_uid 的长注释)
		"account_id": account_id,        # D-3 服务端账号(身份, 不随赛季变)
		"account_email": account_email,
		"nickname": nickname,  # 补绑的邮箱("" = 匿名, 换设备丢档)
		"auth_refresh": auth_refresh,    # D-3c 登录续期令牌(设备本地, 不上云)
		"season_id": season_id,
		"season_start_ts": season_start_ts,
		"hearts": hearts,
		"season_total_battles": season_total_battles,
		"season_eggs_killed": season_eggs_killed,
		"season_wins": season_wins,
		"ranked_used": ranked_used,
		"season_sweeps": season_sweeps,
		"backfill_paid": backfill_paid,
		"gauntlet_backfill_paid": gauntlet_backfill_paid,
		"week_phase": week_phase,
		"week_anchor_ts": week_anchor_ts,
		"gauntlet_wins": gauntlet_wins,
		"gauntlet_losses": gauntlet_losses,
		"promoted": promoted,
		"titles": titles,
		"incense_marks": incense_marks,   # 093 香火石: 赛季级刻痕池
		"incense_charge": incense_charge, # 093 香火石: 赛季级充能池(与刻痕同一条线)
		"season_level": season_level,
		"season_xp": season_xp,
		"chest_treasure_value": chest_treasure_value,
		"chest_treasures_won": chest_treasures_won,
		"season_leaders": season_leaders,
		"loadouts": loadouts,                 # 大轮内各龟 3选1 技能选择, 随赛季持久(跨场景/重启不丢)
		"equip_pool": equip_pool,
		"axe_exp_bar": axe_exp_bar, "axe_exp_total": axe_exp_total,
		"axe_stage": axe_stage, "axe_final": axe_final,
		"axe_syn_matches": axe_syn_matches,
		"persistent_bench": persistent_bench,
		"persistent_equipped": persistent_equipped,
		"candy_jar_count": candy_jar_count,
		"candy_jar_broken": candy_jar_broken,
		"candy_temp_levels": candy_temp_levels,
		"gambler_wheel_stacks": gambler_wheel_stacks,
		"lane_loadout": lane_loadout,
		"dual_lineup": dual_lineup,
		"onboarded": onboarded,   # 走完首次教学 → 不再触发
		"trainer_appearance": trainer_appearance,   # 训龟大师装配(局外持久)
		"trainer_skill": trainer_skill,
		"cloud_rev": cloud_rev,          # D-8 云存档版本号(设备本地, 不上云)
	}


func save() -> void:
	if test_mode:
		return
	var data := _save_dict()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[GameState] save 失败: cannot open " + SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_SB_NET.note_save_dirty()          # D-8: 只标脏, 推不推由同步层判断


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
	_apply_save_dict(parsed)


## ★D-8: 把一份存档字典应用到内存。本机开机读档与【云存档取回】共用这一个函数。
func _apply_save_dict(data: Dictionary) -> void:
	onboarded = data.get("onboarded", false)
	trainer_appearance = str(data.get("trainer_appearance", "default"))   # 训龟大师装配(缺键=旧档默认)
	# 迁移: 新键 trainer_skill 优先; 旧档只有 trainer_active → 用它(旧的两槽合成一个·取旧主动)。
	trainer_skill = str(data.get("trainer_skill", data.get("trainer_active", "hook")))
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
	meta_shop_offer = data.get("meta_shop_offer", [])
	meta_shop_battles = int(data.get("meta_shop_battles", -1))
	install_uid = str(data.get("install_uid", ""))
	account_id = str(data.get("account_id", ""))
	account_email = str(data.get("account_email", ""))
	nickname = str(data.get("nickname", ""))
	auth_refresh = str(data.get("auth_refresh", ""))
	cloud_rev = int(data.get("cloud_rev", 0))
	season_id = int(data.get("season_id", 1))
	season_start_ts = int(data.get("season_start_ts", 0))
	hearts = int(data.get("hearts", 8))
	season_total_battles = int(data.get("season_total_battles", 0))
	season_eggs_killed = int(data.get("season_eggs_killed", 0))
	season_wins = int(data.get("season_wins", 0))
	ranked_used = int(data.get("ranked_used", 0))
	season_sweeps = int(data.get("season_sweeps", 0))
	backfill_paid = int(data.get("backfill_paid", 0))
	gauntlet_backfill_paid = int(data.get("gauntlet_backfill_paid", 0))
	week_anchor_ts = int(data.get("week_anchor_ts", 0))
	gauntlet_wins = int(data.get("gauntlet_wins", 0))
	gauntlet_losses = int(data.get("gauntlet_losses", 0))
	week_phase = str(data.get("week_phase", ""))
	promoted = bool(data.get("promoted", false))
	titles = (data.get("titles", []) as Array).duplicate(true)
	incense_marks = int(data.get("incense_marks", 0))   # 093 香火石: 赛季级刻痕池
	incense_charge = int(data.get("incense_charge", 0))
	season_level = int(data.get("season_level", 1))
	# ★老存档没有这个键 → 空字典, 由 ensure_equip_pool() 在下次用到时补满(D12: 不做旧档兜底)。
	equip_pool = data.get("equip_pool", {})
	axe_exp_bar = int(data.get("axe_exp_bar", 0))
	axe_exp_total = int(data.get("axe_exp_total", 0))
	axe_stage = int(data.get("axe_stage", 0))
	axe_final = str(data.get("axe_final", ""))
	axe_syn_matches = int(data.get("axe_syn_matches", 0))
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
	# ★老存档迁移(2026-07-27 换装备容量规则): 超出新上限的装备卸回背包, 一件不删。
	#   必须放在 season_leaders / persistent_* / dual_lineup 都读完之后 —— 它要数当前阵容。
	var _mig := migrate_equip_caps()
	if _mig > 0:
		print("[GameState] 装备容量新规则迁移: ★删除 ", _mig, " 件超额装备(单只≤3 且 全队≤", team_equip_cap(), ")")


## 重置所有进度。**不清设置项**(bgm/sfx 音量 · fullscreen · perf_lite) — 那是偏好不是进度。
## ⚠ 破坏性: 调用方必须先做二次确认 (SettingsScene 已加确认弹窗)。
# ════════════════════════════════════════════════════════════════════════
#  096 小木斧【砍伐经验】—— 四期(2026-09-01)
#
#  ★`axe_exp_bar` / `axe_exp_total` / `axe_stage` 三个字段【只能经 axe_add_exp 改】。
#    它们是"同一次加经验的三个侧面", 分头写就必漂(方案书风险 5)。
#    门禁 verify_axe 有一条扫描: 产品代码里除了本函数, 不许再有第二处 `axe_exp_bar =`。
# ════════════════════════════════════════════════════════════════════════

## 攒 n 点砍伐经验。返回**本次是否发生了进化**(调用方要放演出就看这个返回值)。
func axe_add_exp(n: int) -> bool:
	if n <= 0:
		return false
	## ★需求原文:「在到达钻石斧后玩家攒满了400经验值后选择最终造物后**经验值封顶**」。
	##   选完之后经验不再涨 —— 连历史累计也不涨(它是召唤物血/攻的分母, 再涨就没有上限了)。
	##   ⇒ 这条 2026-09-01 才补上: 反向验证时发现"锁定"那条变异杀不死,
	##   顺着查才发现**封顶压根没实现**(选完还在涨), 是需求缺口不是判据问题。
	if axe_final != "":
		return false
	var r: Dictionary = _AxeEvo.advance(axe_exp_bar, axe_exp_total, axe_stage, n)
	axe_exp_bar = int(r["bar"])
	axe_exp_total = int(r["total"])
	axe_stage = int(r["stage"])
	return bool(r["evolved"])


## 打完一整场对局的记账(未决点 ②: 不论有没有走到决胜)。**战斗侧只调这一个函数** ——
## "+10 经验"与"羁绊局数 +1"是同一件事的两面, 拆到两处调用就会有人只加了一半。
## ★调用点必须在 `_settle_season` 的【有赛季】分支里 —— demo / 新手教程不喂赛季,
##   也就不该白送经验(那两条路上面已经 return 了)。
func axe_on_match_end() -> void:
	axe_add_exp(_AxeEvo.EXP_ON_MATCH)
	if axe_synergy_active():
		axe_syn_matches += 1


## 选定最终造物。返回是否真的选上了。
## ★★**唯一**能写 `axe_final` 与在进化外清 `axe_exp_bar` 的产品入口 ——
##   UI 侧(AxePanel)不许自己动这两个字段。我第一版就是在面板里直接写的,
##   被自己的门禁「scripts/ 下没有文件直接赋值这三个字段」当场抓住。
## 规则: 没攒够 400 不给选 / 已经选过本大轮锁定(未决点 ⑩) / key 必须是四个之一。
## 选上之后进度条清零(它已经花掉了), **历史累计不动**(召唤物的血/攻靠它)。
func axe_pick_final(key: String) -> bool:
	## ★这里原本还有一句 `if axe_final != "": return false` —— **反向验证证明它是死代码**:
	##   把它改成 `if false` 门禁一条都不红, 因为 `final_ready()` 自己第一件事就是查
	##   `final_key == ""`。两道闸查同一件事, 留着只会让人以为"锁定"是靠它守的。
	##   ⇒ 删掉, 锁定这件事**只由 final_ready 一处负责**。
	if not _AxeEvo.final_ready(axe_exp_bar, axe_stage, axe_final):
		return false
	var ok := false
	for f in _AxeEvo.FINALS:
		if str((f as Dictionary)["key"]) == key:
			ok = true
			break
	if not ok:
		return false
	axe_final = key
	axe_exp_bar = 0
	save()
	return true


## 斧头羁绊激活了没有。★口径与羁绊面板【完全一致】—— 直接问 synergy_rows(),
## 不自己再数一遍装备(手抄的副本必然落后; 面板改了去重口径这里会自动跟上)。
func axe_synergy_active() -> bool:
	for row in synergy_rows():
		if row is Dictionary and str((row as Dictionary).get("t", "")) == "斧头" 				and int((row as Dictionary).get("tier", 0)) >= 1:
			return true
	return false


## 已经拥有一把了没有(背包 + 装在身上)。未决点 ⑧「只能拥有一把」的判据。
## ⚠ 与 axe_synergy_active 口径【故意不同】: 那个只数装在身上的(羁绊要装上才算),
##   这个连背包也数 —— 买第二把时"背包里躺着一把"同样算已拥有。
func axe_owned() -> bool:
	for it in persistent_bench:
		if it is Dictionary and str((it as Dictionary).get("id", "")) == "p2eq_096":
			return true
	if persistent_equipped is Dictionary:
		for pid in persistent_equipped:
			for it2 in persistent_equipped[pid]:
				if it2 is Dictionary and str((it2 as Dictionary).get("id", "")) == "p2eq_096":
					return true
	return false


func reset_save() -> void:
	## ★清档【不清 install_uid】—— 它是"这台机器"不是"这局游戏"。
	##   清掉的话, 服务器上你之前传的快照就再也认不出是自己的了 ⇒ 打到自己。
	var _keep_uid := install_uid
	## ★同理保留服务端账号: 清的是「这局游戏」, 不是「你是谁」。
	##   清掉的话玩家下次开游戏会新建一个匿名账号, 而服务器上他原来那份数据
	##   就再也认不回来了(而且旧账号还留在那儿占着 MAU)。
	var _keep_acc := account_id
	var _keep_mail := account_email
	## ★昵称同理: 清的是「这局游戏」, 不是「你是谁」
	var _keep_nick := nickname
	var _keep_refresh := auth_refresh   # D-3c: 清档清的是「这局游戏」不是「这台设备的登录」
	var _keep_rev := cloud_rev
	best_dungeon_stage = 0
	coins = 0
	battles_won = 0
	battles_total = 0
	inventory = []
	match_history = []
	# V2 赛季持久字段重置 (注: pet_levels 龟自身等级来自养龟站, 不在此清)
	meta_deepsea_coins = 0
	meta_shop_offer = []
	meta_shop_battles = -1
	season_id = 1
	season_start_ts = 0
	hearts = 8
	season_total_battles = 0
	season_eggs_killed = 0
	season_wins = 0
	ranked_used = 0  # A2(v2 周赛制): 与上面同一条线, 漏一个就会在切轮后悄悄漂
	season_sweeps = 0
	backfill_paid = 0
	gauntlet_backfill_paid = 0
	week_phase = ""
	week_anchor_ts = 0
	gauntlet_wins = 0
	gauntlet_losses = 0
	promoted = false
	incense_marks = 0                 # 093 香火石: 刻痕随大轮(赛季)清零 —— 用户「一大轮重置」
	incense_charge = 0                # 同上: 充能与刻痕同一条线, 一起重置
	season_level = 1
	season_xp = 0
	season_leaders = []
	persistent_bench = []
	persistent_equipped = {}
	equip_pool = {}                   # 池随之清空, 下次用到时补满(D6: 赛季重置)
	## 096 小木斧: 砍伐经验【随大轮重置】(用户 2026-08-31) —— 进度条与累计值**都**清,
	##   档位退回木斧、最终造物的选择也作废(未决点 ⑩「本大轮锁定」的另一半)。
	axe_exp_bar = 0
	axe_exp_total = 0
	axe_stage = 0
	axe_final = ""
	axe_syn_matches = 0
	candy_jar_count = 0
	candy_jar_broken = false
	candy_temp_levels = {}
	gambler_wheel_stacks = {}
	lane_loadout = {}
	dual_lineup = {}
	trainer_appearance = "default"   # 训龟大师装配回默认(形象/钩锁)
	trainer_skill = "hook"
	## ★这一行【必须在 save() 之前】。它原来在文件下方 —— 被两行注释和空行隔开、
	##   一直"挂"在 `# ─── V2 赛季 ───` 分节线与 `func ensure_season()` 的文档注释中间。
	##   GDScript 不拿注释和空行断缩进, 所以它**语法上仍属于本函数**、也确实能跑;
	##   但只要有人在那两行注释之间插一个函数, 它就会**静默变成别人的函数体**。
	##   (今天它恰好是恒等赋值 —— 本函数从头到尾没清过 `install_uid`, 所以行为无变化;
	##    移它纯粹是把这颗雷挪走。上面那句「清档不清 install_uid」的防御仍然在。)
	install_uid = _keep_uid
	account_id = _keep_acc
	account_email = _keep_mail
	nickname = _keep_nick
	auth_refresh = _keep_refresh
	cloud_rev = _keep_rev
	save()


# ─── V2 赛季 / 命 逻辑 (阶段4核心) ───────────────────────────
## 启动时确保赛季已初始化 / 已跨周则滚下一大轮。**一大轮 = 一个自然周**(UTC 周一 00:00 换周)。
## 三条分支各自有理由, 都写在函数里了 —— 尤其分支②(老存档迁移)不许简化成"当过期处理"。
func ensure_season() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	var anchor: int = _P2.week_anchor_utc(now)
	## ① 全新存档: 落在当前这一周, 不算"滚了一轮"
	if season_start_ts == 0:
		season_start_ts = anchor
		week_anchor_ts = anchor
		save()
		return
	## ② 老存档迁移(5 天档 → 周档): `week_anchor_ts` 是 0 只说明这份档存的时候还没有周锚点,
	##    **不代表该滚轮**。只把锚点补上, 命/币/配额一律不动 ——
	##    真按"已过期"处理的话, 所有老玩家升级到这一版的那一刻会被平白清一次档。
	if week_anchor_ts == 0:
		week_anchor_ts = anchor
		save()
		return
	## ③ 跨周 → 滚下一大轮
	## ★走 `is_season_expired()` 而不是就地再写一遍 `anchor != week_anchor_ts` ——
	##   手抄的副本必然落后(memory `fb-hand-rolled-copies-drift`), 而且就地写的话
	##   `is_season_expired()` 会变成**零调用者的死函数**(`tools/zero_caller_audit.py` 管这个)。
	if is_season_expired():
		start_new_season()
		save()
		return
	## ④ 同一周内 + 积分赛已收盘 → 惰性补算(晋级判定 + 配额补发), 见 `settle_ranked_close()`。
	##   ★放在这里而不是另起一个入口: `ensure_season()` 已经是"每次打开游戏/每场结算都会走一遍"
	##     的那条路, 补算需要的正是这个时机。另起入口就要自己再找一遍调用点, 必然漏。
	##   ★分开判 `promoted` 有没有变: 有资格但已补满时 `paid == 0`, 这时 `promoted` 可能刚
	##     从 false 翻成 true —— 只看 `paid > 0` 会把这次翻转丢掉不存盘。
	var was_promoted: bool = promoted
	var paid: int = settle_ranked_close()
	## ⑤ 同一周内 + 闯关赛已收盘 → 闯关配额补发(E-A6)。★挂在同一条惰性路径上,
	##   理由同④; 两笔账各有自己的已补计数, 不会互相吃额度。
	paid += settle_gauntlet_close()
	## ⑥ 头衔补齐(E-B5)。★挂在同一条惰性路径上, 理由同④ ——
	##   配额是打满那一场结束时满的, 而晋级是周五收盘后算出来的,
	##   两件事发生在不同时刻 ⇒ 统一在这里对一次账。
	var new_titles: int = sync_titles()
	if paid > 0 or promoted != was_promoted or new_titles > 0:
		save()

## 本赛季是否已跨进下一个自然周 (UTC 周一 00:00 换周). 未初始化(锚点=0)算未过期.
## ★★判据是**锚点变了没有**, 不是"过了多少秒" —— 后者(旧的 5 天 `SEASON_DURATION_SEC`)
##   与 `phase_at_utc()` 的星期几判定永远合不上, 见 `phase2_config.gd` 顶部那段长注释。
func is_season_expired() -> bool:
	if week_anchor_ts == 0:
		return false
	return _P2.week_anchor_utc(int(Time.get_unix_time_from_system())) != week_anchor_ts

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

## ══════ A7 配额补发(大轮赛制 v2·2026-09-19) ══════════════════════════
## 触发: 积分赛阶段结束且该玩家**晋级**; 补发场数 = 配额 − 实打场数; 每场补币与经验。
##
## ★★U6 拍板: **只补币与经验, 不补 096 砍伐经验、不补糖果罐**。
##   ⇒ 本函数一个字都不许碰 `axe_exp_bar` / `axe_exp_total` / 糖果罐字段。
##   门禁 `verify_backfill` 有一条专门盯这个 —— 否则将来有人"顺手补上"没人拦。
##
## ★幂等靠 `backfill_paid`(已发场次): **只补差额, 重复调用不再给**。
##   ⇒ 判据不是"调过没有"而是"发出去多少场" —— 这样即使中途崩了重跑也不会双发。
##
## ★地板值在 `phase2_config`(A1 已落地), 这里不抄数:
##   `RANKED_BACKFILL_COINS` / `RANKED_BACKFILL_XP`。
##   注释写着原稿是「固定数 + 满命×A」= 8 + 8×1、**不含胜利奖** —— 是固定地板不是按余命算。
##
## 返回实际补发的场数(0 = 没资格 / 已补满)。★不自存, 调用方负责 save(与本文件其它 API 同口径)。
func backfill_ranked_quota() -> int:
	if not promoted:
		return 0                              # 只补晋级者
	var quota: int = int(_P2.RANKED_QUOTA)
	var owed: int = quota - int(ranked_used)  # 该补几场 = 配额 − 实打
	if owed <= 0:
		return 0
	var pay: int = owed - int(backfill_paid)  # ★只补差额
	if pay <= 0:
		return 0
	## ★★2026-09-20 修: 钱包原来是 `coins`, **错的** ——
	##   打一场真实对局给的是 `gs.meta_deepsea_coins += _last_reward`
	##   (`RealtimeBattle3DScene._settle_season`), 商店 `ShopScene.gd:895` 花的也是它;
	##   `coins`(龟币累计) 在全仓**没有任何消费入口**(只在图鉴调试与主菜单显示) ⇒ 补进去等于没发。
	##   方案书写的是「补发 = 打满配额的最低供给」, 那就必须落在**打一场会给的那个钱包**里。
	## ⚠ 为什么门禁没拦住: `verify_backfill` 当时读的也是 `coins` —— **两边同错所以一直全绿**
	##   (同族 memory `fb-gate-must-measure-requirement-not-my-hook`: 判据要落在产品自己的账上,
	##    而"产品自己的账"指的是**玩家真花得出去的那本**, 不是我随手挑的那个字段)。
	meta_deepsea_coins += pay * int(_P2.RANKED_BACKFILL_COINS)
	add_season_xp(pay * int(_P2.RANKED_BACKFILL_XP))   # ★走现成的升级路径, 不另写一套
	backfill_paid = int(backfill_paid) + pay
	return pay


## 积分赛收盘之后的【惰性补算】: 晋级判定 + 配额补发。返回实际补发的场数。
##
## ★★为什么是「下次打开游戏时补算」而不是「到点触发」(2026-09-20 拍板):
##   离线版**根本没有「收盘」这个事件** —— 没有服务器、没有人在周五 23:00 那一刻被叫醒,
##   任何定时触发都要求游戏当时正开着。而「下次打开时补算」这个形态本文件已经有了
##   (`ensure_season()` 的换轮), 挂上去是**零新增机制**。
##
## ★★有效窗口 = 周五 23:00 ~ 周日 23:59(**同一个自然周内**), 不做跨周补发。
##   理由是硬的: `start_new_season()` 会清 `meta_deepsea_coins`,
##   周一换轮之后再补上一周的币**当场作废** —— 发了等于没发, 还让账对不上。
##   ⇒ 代价写在明处: **整个周末一次没开游戏 = 拿不到补发。这是有意的取舍, 不是漏。**
##   补发的用途本来就是让打不满配额的人在**周六闯关赛**有装备可买, 那正好是这个窗口。
##
## ★`promoted` 离线版**只用硬线**「≥ `PROMOTE_WINS_FLOOR` 胜保送」。
##   原稿的「前 30%」需要一份收盘时刻的**全服终榜**, 离线版没有 ——
##   等真后端上了再把比例线加回来(母方案书 D 阶段)。
## ★`now_override` 只给门禁用(照 `TeamSelectScene.lockout_now_override` 的先例):
##   本函数的行为**整条都挂在"现在几点"上**, 而真实时钟一周只有两天多落在窗口里 ——
##   不给注入口的话, 「收盘前不补」与「收盘后补」这两侧永远只能验到一侧,
##   另一侧是盲区(`verify_close_lockout` 就因为没处理这个每周必红两天)。
##   ⚠ 注入口不能代替真入口: 门禁另有一条**不注入**、走 `ensure_season()` 的判据。
func settle_ranked_close(now_override: int = 0) -> int:
	if week_anchor_ts == 0:
		return 0                                   # 锚点还没初始化, 谈不上收盘
	var now: int = now_override if now_override > 0 else int(Time.get_unix_time_from_system())
	if now < _P2.ranked_close_ts(week_anchor_ts):
		return 0                                   # 本周积分赛还没收盘
	if not promoted:
		promoted = int(season_wins) >= int(_P2.PROMOTE_WINS_FLOOR)
	return backfill_ranked_quota()


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
		persistent_bench.append(mk_eq(eq_id, star))
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
			# ★093 香火石: 被合掉的三件的香火充能要加进升星件(用户 2026-08-06「升星就合并」)。
			#   在【每个 remove 点之前】累加 —— 删完就取不到了。
			var chg_sum: int = 0
			var host_pet := ""                            # 有统领件被合 → 记第一只龟(升星件放回它)
			var host_lane := ""                           # 或有小将件被合 → 记第一只小将(升星件放回它)
			var host_idx := -1
			var bi := 0                                     # 先从背包移(纯背包合成行为不变)
			while bi < persistent_bench.size() and removed < 3:
				if not is_equip_item(persistent_bench[bi]):
					bi += 1; continue                       # 跳过消耗品
				var bit: Dictionary = persistent_bench[bi]
				if str(bit.get("id", "")) == iid and int(bit.get("star", 1)) == star:
					chg_sum += eq_chg(persistent_bench[bi])   # ★093: 删之前先取充能
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
							chg_sum += eq_chg(eqs[ei])   # ★093: 删之前先取充能
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
								chg_sum += eq_chg(meqs[mei])   # ★093: 删之前先取充能
								meqs.remove_at(mei); removed += 1
								if host_pet == "" and host_lane == "": host_lane = lane2; host_idx = midx
							else:
								mei += 1
						(mu2 as Dictionary)["equips"] = meqs
					if removed >= 3: break
			if host_pet != "":                              # 升星件优先装回统领
				persistent_equipped[host_pet].append(mk_eq(iid, star + 1, chg_sum))
			elif host_lane != "" and host_idx >= 0:         # 否则装回小将
				var hu: Dictionary = (dual_lineup[host_lane] as Array)[host_idx]
				var heq: Array = hu.get("equips", []) if hu.get("equips") is Array else []
				heq.append(mk_eq(iid, star + 1, chg_sum))
				hu["equips"] = heq
			else:
				persistent_bench.append(mk_eq(iid, star + 1, chg_sum))
			changed = true
			# ★D21「满 3★ 后剩下的张不再流通」这里【不做任何事】—— 不是漏了。
			#   ShopScene._maxed_item_ids() 早就把 star>=3 的 id 排除出掷货池了, 且它是【库存驱动】:
			#   卖掉 3★ 之后自动不再排除。若在这里再写一个冻结状态, 就会与 D22 的守恒律直接打架
			#   (冻结后卖出退不回张 ⇒ 池子永久少 31 张)。完整推导见 equip_pool.gd 末尾。
			break


# ══════════════════════════════════════════════════════════════════════
#  装备私人池 (2026-08-03 批2 · 方案书 §4.6)
#  ★池只在这四个地方变: 买(pool_take) / 卖(pool_give_back) / 满星冻结(auto_merge_all)
#    / 赛季重置(start_new_season)。★货架不动池(D23: 成交才扣)。
# ══════════════════════════════════════════════════════════════════════

## 池空 → 补满; 池非空 → **补齐后来新加的装备**。
## ★不在 _ready 里初始化, 因为 DataRegistry 的载入顺序不保证;
## 改成"用到时确保", 所有入口(掷货/买/卖)都先调它。
##
## ══════════════════════════════════════════════════════════════════
##  ★★2026-08-10 修: 老存档【一辈子抽不到新装备】
## ══════════════════════════════════════════════════════════════════
## 改之前这里是 `if not equip_pool.is_empty(): return` —— 池子是**当时那张装备表的快照**,
## 之后往 `phase2-equipment.json` 加的件**永远不会进池** ⇒ 商店里一次都不会出现。
##
## 用户 2026-08-10 实机反馈「为啥我手机上没看到新装备啊」。查证:
##   · 包没问题(pck 里 `p2eq_060`/`p2eq_077`/`p2eq_095` 的路径都在, 各 7 处引用)
##   · 抽卡池 `full_pool` 收的是"调用那一刻"的 `DataRegistry.phase2_equipment`
##   · 而 `equip_pool` 进存档(save 的 `equip_pool` 键) ⇒ 存档比装备表旧就永久落后
## ⇒ 只补【池里没有的 id】; **已有的张数一个都不动** —— 动了等于把玩家已经买走/
##   卖掉的记录抹掉(池子记的是"还剩几张", 不是"总共几张")。
##
## ⚠ 与 D12「不做旧档兜底」不冲突: 那条说的是"老存档没有 equip_pool 这个键时不特殊处理"
##   (缺键 → 空字典 → 走上面的补满)。这里治的是**另一种病**: 键在、内容却停在旧表。
##   缺值和陈旧值是两类病 —— 同 data_integrity 那条「空值和错值是两类病」。
func ensure_equip_pool() -> void:
	var full: Dictionary = _EquipPool.full_pool(DataRegistry.phase2_equipment)
	if equip_pool.is_empty():
		equip_pool = full
		return
	for eid in full:
		if not equip_pool.has(eid):
			equip_pool[eid] = full[eid]


## 买走 1 张。返回是否成功 —— 张数不够时【不扣、返回 false】, 调用方要据此拒绝这笔交易。
func pool_take(eid: String, n: int = 1) -> bool:
	ensure_equip_pool()
	return _EquipPool.take(equip_pool, eid, n)


## 卖出退回。★按【份数】退(D22): 1★退1 / 2★退3 / 3★退9 ——
## 守恒律: 买 9 张合出 3★ 再卖掉, 池子必须恰好回到原样。这是门禁最好写的一条断言。
func pool_give_back(eid: String, star: int) -> void:
	ensure_equip_pool()
	_EquipPool.give_back(equip_pool, eid, _EquipPool.shares_of(star))


func pool_left(eid: String) -> int:
	ensure_equip_pool()
	return _EquipPool.left(equip_pool, eid)


## 开新一大轮赛季: 命/币/局内等级/总战斗数/蛋数/背包build 全重置 (设计§五). pet_levels(养龟站)不动.
func start_new_season() -> void:   # 不自存; 调用方(ensure_season/调试快进)负责 save
	season_id += 1
	## ★新赛季从**本周一 00:00** 起算, 不是从"玩家开游戏那一刻"起算 ——
	##   一大轮 = 一个自然周(见 `_P2.week_anchor_utc`)。写成"当前时刻"的话,
	##   周三才开一次游戏就把赛季起点定在周三, 赛程条与倒计时立刻和星期几错位。
	season_start_ts = _P2.week_anchor_utc(int(Time.get_unix_time_from_system()))
	hearts = 8
	meta_shop_offer = []      # 新赛季货架作废(否则会带着上赛季的货开局)
	meta_shop_battles = -1
	season_total_battles = 0
	season_eggs_killed = 0
	season_wins = 0
	ranked_used = 0  # A2(v2 周赛制): 与上面同一条线, 漏一个就会在切轮后悄悄漂
	season_sweeps = 0
	backfill_paid = 0
	gauntlet_backfill_paid = 0
	week_phase = ""
	## ★★不是 0 —— 这个字段就是「本大轮是哪一周」本身。写 0 的话下一次 `ensure_season()`
	##   会把它当成"老存档待迁移"(见那边分支②)而**再也滚不了轮**: 补个锚点就返回,
	##   下周一也不会换。这正是它从 A2 落地起一直是**死字段**的原因 ——
	##   写进存档、读出存档, 但没有任何判定读它。
	week_anchor_ts = _P2.week_anchor_utc(int(Time.get_unix_time_from_system()))
	gauntlet_wins = 0
	gauntlet_losses = 0
	promoted = false
	incense_marks = 0                 # 093 香火石: 刻痕随大轮(赛季)清零 —— 用户「一大轮重置」
	incense_charge = 0                # 同上: 充能与刻痕同一条线, 一起重置
	season_level = 1
	season_xp = 0
	meta_deepsea_coins = 0
	season_leaders = []
	loadouts = {}                     # 新大轮阵容清空 → 技能 3选1 选择也清空(锁定阵容一起重来)
	chest_treasure_value = 0.0        # 藏宝图财宝值/战利品随大轮重置(用户2026-07-16)
	chest_treasures_won = []
	persistent_bench = []
	persistent_equipped = {}
	equip_pool = {}                   # 池随之清空, 下次用到时补满(D6: 赛季重置)
	## 096 小木斧: 砍伐经验【随大轮重置】(用户 2026-08-31) —— 进度条与累计值**都**清,
	##   档位退回木斧、最终造物的选择也作废(未决点 ⑩「本大轮锁定」的另一半)。
	axe_exp_bar = 0
	axe_exp_total = 0
	axe_stage = 0
	axe_final = ""
	axe_syn_matches = 0
	candy_jar_count = 0
	candy_jar_broken = false
	candy_temp_levels = {}
	gambler_wheel_stacks = {}
	lane_loadout = {}
	dual_lineup = {}
