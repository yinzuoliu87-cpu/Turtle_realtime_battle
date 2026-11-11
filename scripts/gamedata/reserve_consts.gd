class_name ReserveConsts
extends RefCounted
## 援军小将 —— 终极战场里双方始终各上一只(方案书 docs/plans/20261029-终极战场援军小将.md; 11-11 起不再只在没有幸存时才上,
##   并从这一方背包里未穿戴的装备中随机带一件, 方案书 docs/plans/20261111b-援军小将始终登场并带背包装备.md)。数值单一来源:
##   战斗(battle_spawn._make_unit / reserve_system)与图鉴文案都读这里, 不许各抄一份。
## 用户 2026-10-29 拍板: 1000 血 / 50 攻击 / 15 双抗 / 远程; 「玩家所战斗的每一个场次, 会使他的基础属性提升百分之四」;
##   龟能 135; 敌人前后左右各出现一道气波、四道同时往敌人中间走; 每道 100% 攻击力物理 + 该敌人 10% 最大生命值魔法。

const NAME := "援军小将"
const SKILL := "reserveConverge"
const SKILL_NAME := "四面合围"

const HP := 1000.0
const ATK := 50.0
const DEF := 15.0
const MR := 15.0
## 每打一场基础属性 +4%(线性, 按这一方本周已打场数 season_total_battles)。
const GROWTH_PER_BATTLE := 0.04
const MOVE := 105.0
const ATK_INTERVAL := 0.85
const RANGE := 400.0                ## 远程普攻射程(同远程小将)
const ENERGY := 135.0

const WAVES := 4
## 用户 2026-10-29 看录屏:「这四个波的离角色距离还是有点近，可以远一点，然后移动速度还可以慢一点。还有的话，就这四个波至少是一次就是浮现，
##   一次出现，然后顿一下…就在原地…动态个零点五秒左右，再开始移动」⇒ 半径 260 → 360、出现后原地停 WAVE_HOLD 秒、
##   速度 380 → 210(★旧版标称 380 实际只有 285: 延时队列 0.05 秒一步要 4 个 1/60 秒 sim 步才到点; 现已按 sim 步对齐,
##   标称 = 实际 ⇒ 210 比用户看到的旧速度慢约 1/4)。
const WAVE_RADIUS := 360.0          ## 气波出现在目标前后左右多远
const WAVE_MAX_FLY := 900.0         ## 追踪气波最多飞这么远(追不上就消散)
const WAVE_OVERSHOOT := 60.0        ## (特效用)拖尾 / 预示线的长度参考: 出发半径之外再多画一段
const WAVE_SPEED := 210.0
const WAVE_HOLD := 0.5              ## 四道同时出现后在原地停这么久(弹体照常动、转向跟着目标)再开始追; 停的时候不判命中
const WAVE_HALF_W := 55.0
const WAVE_CATCHUP := 20.0         ## 往回补查(防迎面走来的敌人从两步之间穿过去; 见 battle_ballistics._first_on_segment)
const ATK_COEF := 1.0               ## 物理段: 100% 攻击力
const MAXHP_PCT := 0.10             ## 魔法段: 该敌人 10% 最大生命值(真实 maxHp, 不除 HP_MULT —— CLAUDE.md §3.1)
const CAST_RANGE := 600.0
const CAST_ROOT := 0.5              ## 施法定身


## 场数 ⇒ 属性倍率。1 + 0.04 × 场数: 乘加都是 IEEE-754 逐位一致的运算, 跨平台确定(不用 pow)。
static func growth_mult(battles: int) -> float:
	return 1.0 + GROWTH_PER_BATTLE * float(maxi(0, battles))


## 开战那一刻的底子(与 MinionCodex.base_stats 同形)。
static func base_stats(battles: int) -> Dictionary:
	var m := growth_mult(battles)
	return {"name": NAME, "rarity": "C", "crit": 0.0,
		"hp": HP * m, "atk": ATK * m, "def": DEF * m, "mr": MR * m}


## ── 随身装备(用户 2026-11-11「援护小将始终在终极战场登场，并且他会携带…背我背包里的装备…随便抽取一件…在登场的时候装备只会抽取一件」) ──
## 可抽清单(`GameState.reserve_pool` / 快照 `reserve_pool`)最多收这么多件: 防一条脏快照塞上万件拖慢开局。
const POOL_CAP := 60
## 阵营盐: 同一个对局种子下左右两方各抽各的(不加盐 ⇒ 两边背包一样时永远抽到同一格)。
const PICK_SALT_LEFT := 0x51A7E
const PICK_SALT_RIGHT := 0x2B0C3


## 清洗一份可抽清单: 只留 {id, star}(id 非空; 星级夹 1~3), 保持原顺序, 最多 POOL_CAP 件。
## ★不在这里查 id 存不存在于装备表 —— 调用方(GameState / 快照读出)各自有数据表; 这里只管形状, 纯函数可直接门禁。
static func clean_pool(raw) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for it in (raw as Array):
		if out.size() >= POOL_CAP:
			break
		if not (it is Dictionary):
			continue
		var id := str((it as Dictionary).get("id", ""))
		if id == "":
			continue
		var st = (it as Dictionary).get("star", 1)
		var star: int = clampi(int(st) if (st is int or st is float) else 1, 1, 3)
		out.append({"id": id, "star": star})
	return out


## 登场时从可抽清单里抽**一件**(用户: 「装备只会抽取一件」)。返回 [] 或 [{id, star}](直接当 spec.equips 用)。
## ★纯函数: 独立 PCG, 种子 = 对局种子 ^ 阵营盐 —— **不吃 `_battle_rng`**:
##   ① 对阵预览卡与开场生成各调一次也抽到同一件; ② 不改动战斗随机数序列里任何其他抽签;
##   ③ 录制 / 回放 / 服务器裁判拿同一个种子 ⇒ 同一件(RandomNumberGenerator 是 PCG32, 跨平台逐位一致)。
static func pick_equip(pool: Array, battle_seed: int, side_lr: String) -> Array:
	var p := clean_pool(pool)
	if p.is_empty():
		return []
	var r := RandomNumberGenerator.new()
	r.seed = battle_seed ^ (PICK_SALT_LEFT if side_lr == "left" else PICK_SALT_RIGHT)
	return [(p[r.randi() % p.size()] as Dictionary).duplicate()]
