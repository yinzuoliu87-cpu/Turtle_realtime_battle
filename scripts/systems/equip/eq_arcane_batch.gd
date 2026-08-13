class_name EqArcaneBatch
extends RefCounted
## eq_arcane_batch.gd — 法器三件新装备的效果本体
## 088 涨潮碑 · 089 蚀月符纸 · 090 镇海杵
##
## 规格 = `docs/plans/20260805-装备逐件重做.md` §0.5【用户逐件亲手写的定稿】, 一个数都不许改。
## 演出层放 `scripts/scenes/battle/arcane_eq_vfx.gd`(本文件自己 new 出来, 不进共享文件)。
##
## ══════════════════════════════════════════════════════════════════════
##  ★本文件是【本批唯一归你的产品代码】—— 共享文件一律不要动
## ══════════════════════════════════════════════════════════════════════
## 已由主会话预接线、**不要改**:
##   · `scripts/systems/equip/equip_system.gd`      (声明/构造/tick/全部钩子派发)
##   · `scripts/systems/equip/equip_stats_apply.gd` (常驻字段/登场标记)
##   · `scripts/gamedata/equip_stats.gd`            (STATS 三星属性)
##   · `data/phase2-equipment.json`                 (名字/属性镜像/文案)
##   · `scripts/scenes/battle/dual_lane_flow.gd`    (换路调 clear_all)
##   · `scripts/systems/equip/staff_synergy_system.gd` (法力条本体)
## 归你的: **本文件** + `scripts/scenes/battle/arcane_eq_vfx.gd` + `tests/verify_eq_arcane_batch.gd/.tscn`
##
## ══════════════════════════════════════════════════════════════════════
##  ★三条焊死的口径(与批①/批② 同, 逐条对应踩过的坑)
## ══════════════════════════════════════════════════════════════════════
## ① **随机一律走 `battle._battle_rng`**。裸 `randi()`/`randf()` 会破坏确定性 ——
##    `tools/rng_discipline.py` 冻结了裸调用数, `verify_battle_determinism` 同种子比指纹。
##    ⇒ **本文件一次随机都没用**(选靶全走"最近", 伤害不掷暴击) —— 三件是零 RNG 的。
## ② **本文件打出的每一段伤害都 `from_equip = true`** ⇒ 不回钩 on-hit
##    (`battle_damage.gd` 里 `if not from_equip` 才回钩 on-hit / 处决 / 冰封 / 僵硬)。
##    ⚠ 这一条对法器**格外要紧**: `battle_damage.gd:292` 的「造成伤害 ×0.1 涨法力」
##    也在 `if not from_equip` 里 —— 不焊就是「碑打人 → 涨法力 → 立碑 → 再打人」的自激循环。
## ③ **`_t` 跨路累加永不重置**(CLAUDE.md §3.4) ⇒ 所有"持续 N 秒 / 每 N 秒"
##    存**自管累加器**(`el` / `t_left`), 本文件没有一处拿 `_t` 直接和常数比。
##
## ══════════════════════════════════════════════════════════════════════
##  本批的分派落点(主会话已接好)
## ══════════════════════════════════════════════════════════════════════
##   088 → `on_mana_full`(立碑) + `tick`(碑区域每秒结算 + 圈内攻速 + ★碑存在期间锁法力条)
##   089 → `on_mana_full`(贴符纸) + `tick`(符纸每秒掉血削魔抗 / 目标死亡转移剩余时长)
##   090 → `on_mana_full`(跳起猛砸) + `on_basic`(每第三次普攻发浪潮) + `tick`(砸落定时)
## ★法器的触发时机是【法力条满】, 不排 EQ_PERIOD —— `StaffSynergySystem._fire` 走
##   `EquipSystem.fire_equip_effect` 路由到 `on_mana_full`。
##
## ══════════════════════════════════════════════════════════════════════
##  ★★「锁法力条」怎么在【不改 staff_synergy_system.gd】的前提下做到
## ══════════════════════════════════════════════════════════════════════
## 法力条本体在 `StaffSynergySystem.add_mana`(共享文件, 契约禁止我改)。所以走两道:
##   ① **拒发**: `on_mana_full` 一进来先看这件装备的 `mana_locked` —— 锁着就直接 return。
##      这是硬闸: `add_mana` 已经把 `stt["mana"]` 清零才调 `_fire`, 所以拒发之后条也是空的。
##   ② **压零**: 锁期内每帧把 `eq_state[eid]["mana"]` 按回 0 ⇒ 条**真的不增长**(可断言)。
## 只压**这一件**的条, 不动同一只龟身上别的法器(所以没用 `u["_staff_busy"]` ——
## 那个是全单位闸, 会连带把 089/090 的条一起冻住, 规格没这么写)。
## ★同一手法的先例: 068 深海气压罐「法力护盾存在时锁充能条」(eq_potion_batch.gd:_eq_pressure_store)。
##
## ══════════════════════════════════════════════════════════════════════
##  ⚠ 诚实记录: 规格没写死、由我定的地方(选了哪一侧 / 另一侧是什么 / 为什么)
## ══════════════════════════════════════════════════════════════════════
## · **088/089/090 打出的伤害一律【不掷暴击】。** 三处规格写的都是固定数
##   (15/25/40 · 400/700/1000 · 200/300/5000 + 3 ATK), 没提暴击。
##   选"不暴"的另两个理由: ① 与 074 鲸骨胸甲的既有口径一致(固定值段不暴);
##   ② 少掷一次骰 = 少一处影响确定性指纹的地方。**另一侧**是走 `battle._resolve_dmg`
##   让它们照吃暴击率 —— 那会让 090 的 3★ 一发变成 5750→最高 8625, 我不敢替用户加。
## · **088 的碑与携带者【脱钩】**: 携带者中途死了, 碑照样把 5 秒走完。
##   规格说"钉在地上不跟随", 我把"不跟随"读成连生死也不跟随(同 075 箭雨"放出去就脱钩")。
##   **另一侧**是携带者一死碑就散。
## · **088 的圈内攻速走 `aspd_perm` 加算通道**, 不用限时 buff 槽 `spd_aspd_mult` ——
##   后者是全场共用的一个 slot(冰龟减攻速也写它), 写进去会互相覆盖(eq_bow_batch 那条注释)。
##   代价是要自己收回来, 所以 `_stele_aura()` 每帧按"人在不在圈里"重算一次差量。
## · **089 贴给【最近的敌人】。** 规格只说"给一个敌人"。选"最近"是因为**转移**那条
##   规格明写"转移到最近的敌人" —— 施加与转移用同一把尺子才自洽。**另一侧**是随机敌人。
## · **089 的 400/700/1000 按【每秒 1/15】均摊**(15 跳)。规格是"15 秒内共造成 N",
##   与"每秒削减 1 魔抗"同一节拍, 所以取每秒一跳。**另一侧**是一次性打完或按帧连续掉血。
## · **089 的削魔抗走 `_recalc_stats` 的 `mr_shred` 通道**(主会话 2026-08-06 加的共享口子),
##   本文件**不碰** `mr` / `base_mr`, 只累加 `o["mr_shred"]` 再调一次 `battle._recalc_stats(o)`。
##   ⚠ 这里原来是我自己写的一个每帧守卫: 它把 `_recalc_stats` 的 mr 公式**镜像了一份**
##   (只去掉那个 `maxf(0.0, …)` 下钳), 正是 memory [[fb-hand-rolled-copies-drift]]
##   「手抄的副本必然落后」那条坑 —— 别人改了 `_recalc_stats` 的公式, 我那份不会跟。
##   主会话把口子开进共享文件之后, **守卫函数与它的登记表一并删除**(不是留着当备份)。
##   顺带白拿两件事: ① 削穿之后 `mr` 自然为负, `resist_multiplier` 按 `1+|r|/(|r|+40)` 给增伤;
##   ② `mr_shred` 是**单位字段** ⇒ 换路整体重建单位时天然清零 = 用户定的「本路不恢复、换路重置」,
##   我这边不需要任何自管重置。
## · **090 的浪潮把"携带者→第一个目标"算作【第 1 跳】。** 规格"最多跳跃 4/5/8 次" ⇒
##   一次浪潮最多命中 4/5/8 个单位。**另一侧**是首段不计、总命中 5/6/9 个。
## · **090 的携带者一开始就进【已飞过】名单**, 浪潮不会回头打/奶自己。
##   规格说"从携带者发射" ⇒ 他是起点, 起点算飞过。**另一侧**是允许弹回携带者身上治疗。
## · **090 的浪潮【瞬时结算】**(规格原话"如同闪电一样"), 演出是事后画折线。
##   这条同时满足契约 §7:「数值测试不许依赖 tween 跑完」。
## · **090 的起跳→砸落 = 0.6 秒**(规格没给)。起跳直接写击飞物理字段, 由主循环那段
##   `airborne` 积分抛起再落回; 重力按 `g = 4h/T²` 配, 所以**落地与砸落同时**。
## · **090 的"1 秒击飞"靠配重力实现**(`g = 2·vy/T`), 不是靠拉大初速 ——
##   后者会把人抛到 2.75 米高。同 stone_system 里 `knock_g = -36.111` 那一手。
## · **碑/符纸的到期条件是【跳满 AND 时间到】, 不是只看时间。** 每帧 `el += delta` 的浮点残差
##   会让第 5 跳落在 4.99999 秒 —— 只看时间就会在它跳出来之前把碑撤掉(门禁实测: 5 秒的碑只跳 4 次,
##   共 160 伤害而不是 200)。代价是持续时间最多多出 1 帧(≤17 毫秒), 换来"5 秒 = 5 跳 / 15 秒 = 15 跳"
##   是硬事实。**另一侧**是保留"到点就撤"并接受偶尔少跳一次。

var battle
var vfx: ArcaneEqVfx

# ══════════════════════════════════════════════════════════════════
#  §常量 —— 规格里的"秒/码/次", 不是三元数组(三元数组一律就近声明, 契约 §6)
# ══════════════════════════════════════════════════════════════════

## 088: 碑的持续秒数 / 半径(码) / 结算节拍(秒)
const STELE_SEC := 5.0
const STELE_RADIUS := 250.0
const STELE_TICK := 1.0
## 089: 符纸时长(秒) / 结算节拍(秒) / 每跳削掉的魔抗点数
const TALISMAN_SEC := 15.0
const TALISMAN_TICK := 1.0
const TALISMAN_MR_PER_TICK := 1.0
## 090: 猛砸半径(码) / ATK 系数 / 起跳到砸落(秒) / 起跳峰高(米) / 击飞滞空(秒) / 几次普攻一发浪潮
## ★★2026-08-09 1000 → 500(用户拍板)。原因是**读不成一个圈**:
##   战场 `ARENA = Rect2(70, 110, 1596, 728)`, 半径 1000 ⇒ 直径 2000 **比战场长边还长**,
##   预警圈整个落在画面外(实拍确认)。500 ⇒ 直径 1000: 横向放得下(1596),
##   纵向仍超出(728) ⇒ 是一个上下被战场边界切平的圆, 但已经读得出"这是一个范围"。
const PESTLE_RADIUS := 500.0
## 起跳最多把携带者带出去多远(码) —— 用户 2026-08-13:「跳的时候移动的落点为250码内」。
## ★不是"跳到最密的敌群中心": 那可能在 800 码外, 跳过去等于瞬移。
const PESTLE_LEAP_MAX := 250.0
const PESTLE_ATK_SCALE := 3.0
## ★★2026-08-08 用户:「这个起跳不够高, 不够物理, 哪有这么快的跳」。
##   旧版是 h=2.4 米 / T=0.6 秒, **反推出来的重力是 −26.7 m/s² ≈ 2.7 个地球重力**
##   —— 又矮又快, 像被弹簧弹了一下, 不像"跳起来再砸下去"。
##   ⇒ 改成**先定峰高与重力、再推滞空**(物理的因果方向), 而不是先定时间再倒推重力。
const PESTLE_APEX_M := 7.0      ## 峰高(米)。龟高约 2 米 ⇒ 跳三个半身位
const PESTLE_G := 20.0          ## 下坠重力(米/秒²)。地球 9.8; 游戏里惯用约 2 倍让落地有分量
## 滞空 T = 2√(2h/g)。★不写死: 改 h 或 g, T 自动跟着走(门禁验这条关系)
static func pestle_jump_sec() -> float:
	return 2.0 * sqrt(2.0 * PESTLE_APEX_M / PESTLE_G)
const PESTLE_KB_SEC := 1.0
## 砸落的**兜底**上限(秒)。正常路径由真实落地事件结算; 这条只防"永远落不了地"留下孤儿在途条目
## (携带者被别的机制永久滞空 / 状态错乱)。★不是正常触发路径, 正常路径命中它就说明落地事件漏了。
const PESTLE_SLAM_WATCHDOG := 3.0
const PESTLE_EVERY := 3
## 浪潮每一跳飞多久(秒)。★"一簇水跳过去"要看得见飞行过程, 太快就又变成瞬时连线了。
const WAVE_HOP_SEC := 0.26

## 伤害飘字色。★取自演出层 `ArcaneEqVfx.COL_*`(颜色的单一事实源在那边),
##   引用是**单向**的 —— 演出层不反过来引用本文件, 免得两个 class_name 循环依赖。
const COL_TIDE := ArcaneEqVfx.COL_TIDE
const COL_MOON := ArcaneEqVfx.COL_MOON
const COL_SLAM := ArcaneEqVfx.COL_SLAM
const COL_WAVE := ArcaneEqVfx.COL_WAVE

# ══════════════════════════════════════════════════════════════════
#  §状态 —— 全部是【全局表】, 不挂在携带者身上
#    ★存单位字典进 Array 是允许的(禁止的是拿它当 **Dictionary 的键**, CLAUDE.md §3.2);
#      查在不在一律 `battle._arr_has_unit` / `is_same`, 不用 `in` / `.has()`。
# ══════════════════════════════════════════════════════════════════

## 立着的潮汐碑 [{src, si, pos, el, ticks, dmg, shd, aspd}]
var _steles: Array = []
## 贴着的符纸 [{src, si, tgt, el, ticks, per, hops}]
var _talismans: Array = []
## 起跳中还没砸下来的镇海杵 [{u, si, t_left, flat, stun}]
var _slams: Array = []
## 每次起跳的自增编号(见 `air_id`)。
var _pestle_air_seq: int = 0
## 当前吃着 088 圈内攻速的单位(撤场/碑没了要把增量还回去)
var _aura_units: Array = []


func _init(b) -> void:
	battle = b
	vfx = ArcaneEqVfx.new(b)


# ══════════════════════════════════════════════════════════════════
#  §通用小工具
# ══════════════════════════════════════════════════════════════════

## 只做魔抗减免、不掷暴击 —— `battle._phys_after_armor` 的魔法版。
## ★公式与 `_resolve_dmg` 的魔法分支逐字一致(`DamageMath` 那两个静态函数是单一事实源),
##   没有在这里抄第二份减伤曲线。**负魔抗照吃**(resist_multiplier 对负值返回 1+|r|/(|r|+40)),
##   089 削穿之后靠的就是这条。
func _magic_after_mr(u: Dictionary, raw: float, tgt: Dictionary) -> int:
	var resist: float = DamageMath.effective_resist(float(tgt.get("mr", 0.0)),
		float(u.get("magic_pen_pct", 0.0)), float(u.get("magic_pen", 0.0)))
	var d: float = raw * DamageMath.resist_multiplier(resist)
	d *= 1.0 + float(u.get("damage_amp", 0.0))
	d *= 1.0 - float(tgt.get("damage_reduction", 0.0))
	return maxi(1, int(round(d)))


## 锁住【这一件法器】的法力条(见文件头「锁法力条」那节)。
func _mana_lock(u: Dictionary, eid: String) -> void:
	if not (u.get("eq_state", null) is Dictionary):
		return
	var stt: Dictionary = u["eq_state"].get(eid, {})
	stt["mana_locked"] = true
	stt["mana"] = 0.0
	u["eq_state"][eid] = stt


func _mana_unlock(u: Dictionary, eid: String) -> void:
	if not (u.get("eq_state", null) is Dictionary):
		return
	var stt: Dictionary = u["eq_state"].get(eid, {})
	stt["mana_locked"] = false
	u["eq_state"][eid] = stt


func mana_locked(u: Dictionary, eid: String) -> bool:
	if not (u.get("eq_state", null) is Dictionary):
		return false
	return bool((u["eq_state"].get(eid, {}) as Dictionary).get("mana_locked", false))


## 锁期内每帧把条压回 0 —— 「法力不增长」这句话的可断言形式。
func _mana_hold(u: Dictionary, eid: String) -> void:
	if not (u.get("eq_state", null) is Dictionary):
		return
	var stt: Dictionary = u["eq_state"].get(eid, {})
	if bool(stt.get("mana_locked", false)):
		stt["mana"] = 0.0
		u["eq_state"][eid] = stt


## 让 tgt 滞空恰好 sec 秒: 击飞初速由 `_knockback` 给, 这里只配本次击飞的重力
##   —— 滞空 = 2·vy/|g| ⇒ |g| = 2·vy/sec。落地时主循环会 `erase("knock_g")`。
func _knock_for(by: Dictionary, tgt: Dictionary, sec: float) -> void:
	if tgt.get("airborne", false):
		return
	battle._damage._knockback(by, tgt, 0.0, 1.0, 0.6)
	if tgt.get("airborne", false):
		tgt["knock_g"] = -2.0 * float(tgt.get("vy", battle.KNOCK_VY)) / maxf(0.05, sec)


# ══════════════════════════════════════════════════════════════════
#  §钩子
# ══════════════════════════════════════════════════════════════════

## 每帧全局推进: 碑的区域结算 / 符纸 / 在途的猛砸 / 演出
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_tick_steles(delta)
	_tick_talismans(delta)
	_tick_slams(delta)
	if vfx != null:
		vfx.tick(delta)


## 每帧逐单位推进 —— 本批三件都是【全局表】驱动, 这里没有活儿。
## ★不是忘了写: 碑钉在地上、符纸贴在敌人身上、猛砸在半空, 三件都与"逐单位遍历"无关,
##   放进来只会让每只龟每帧白跑一次。
func tick_unit(_u: Dictionary, _delta: float) -> void:
	pass


## 携带者登场 —— 法器三件都没有"登场就生成一个东西"的形态(那是枪 077/079/080)。
func on_spawn(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 携带者普攻发出 —— 090 的被动(每第三次普攻发一片浪潮)。
func on_basic(u: Dictionary, tgt, eid: String, si: int) -> void:
	if eid != "p2eq_090" or not u.get("alive", false):
		return
	_pestle_on_basic(u, tgt, si)


func on_hit(_src: Dictionary, _tgt: Dictionary, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_damaged(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


func on_magic_hurt(_u: Dictionary, _src, _dmg: float, _eid: String, _si: int) -> void:
	pass


## 携带者阵亡 —— 三件都【不】在这里清场:
##   · 088 的碑钉在地上、与携带者脱钩(文件头诚实记录第 2 条);
##   · 089 的符纸贴在敌人身上, 携带者死了符纸照烧完;
##   · 090 若死在半空, 由 `_tick_slams` 丢掉那条在途记录(它每帧都验 alive)。
func on_death(_u: Dictionary, _eid: String, _si: int) -> void:
	pass


## 法器法力条集满 —— 本批的唯一触发口。
## ★第一件事是查锁: 锁期内直接拒发(见文件头「锁法力条」①)。
func on_mana_full(u: Dictionary, eid: String, si: int) -> void:
	if not (u is Dictionary) or not u.get("alive", false):
		return
	if mana_locked(u, eid):
		return
	match eid:
		"p2eq_088":
			_stele_raise(u, si)
		"p2eq_089":
			_talisman_stick(u, si)
		"p2eq_090":
			_pestle_leap(u, si)


## ★换路撤场: 碑/符纸/在途猛砸全清, 圈内攻速增量原样还回去。
## 漏了就会把上一路的碑带进下一路(而且攻速增量永远收不回来 = 每换一路白涨一次)。
func clear_all() -> void:
	for o in _aura_units:
		if o is Dictionary:
			var given: float = float((o as Dictionary).get("_stele_aspd", 0.0))
			if given > 0.0:
				o["aspd_perm"] = maxf(0.01, float(o.get("aspd_perm", 1.0)) - given)
			o["_stele_aspd"] = 0.0
	_aura_units.clear()
	for st in _steles:
		if st is Dictionary and (st as Dictionary).get("src", null) is Dictionary:
			_mana_unlock((st as Dictionary)["src"], "p2eq_088")
	for sl in _slams:
		if sl is Dictionary and (sl as Dictionary).get("u", null) is Dictionary:
			_mana_unlock((sl as Dictionary)["u"], "p2eq_090")
	_steles.clear()
	_talismans.clear()
	_slams.clear()
	if vfx != null:
		vfx.clear()


# ══════════════════════════════════════════════════════════════════
#  §088 涨潮碑 (法器 · 1 费)
#  「法力条集满 → 在自己脚下立一块潮汐碑, 钉在地上不跟随, 持续 5 秒, 半径 250 码。
#    碑内敌人每秒受到 15/25/40 魔法伤害; 碑内友军每秒获得 20/35/55 护盾(可叠加),
#    并获得 10/15/25% 攻速(只在圈内生效)。碑存在期间锁法力条。」
# ══════════════════════════════════════════════════════════════════

## 立碑。★三个逐星数组【就近声明】并快照进碑的记录里 ——
##   这样它们和本件的 `"p2eq_088"` 字面量同处一屏, `tools/tooltip_number_audit.py`
##   的 ±2500 字符窗口锚得到(契约 §6: 提到文件顶部会被判"远处命中"直接红)。
func _stele_raise(u: Dictionary, si: int) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_088", {})
	var dmg_ps: float = [15.0, 25.0, 40.0][si]      # 碑内敌人每秒魔法伤害
	var shd_ps: float = [20.0, 35.0, 55.0][si]      # 碑内友军每秒护盾(可叠加·到期不消失)
	var aspd: float = [0.10, 0.15, 0.25][si]        # 碑内友军攻速加成(离圈即失)
	stt["stele_raised"] = int(stt.get("stele_raised", 0)) + 1   # 同步触发证据(门禁数它, 不等演出)
	u["eq_state"]["p2eq_088"] = stt
	_mana_lock(u, "p2eq_088")                        # ★释放期间锁法力条
	_steles.append({
		"src": u, "si": si, "pos": (u["pos"] as Vector2),
		"el": 0.0, "ticks": 0, "hit": 0, "shd": shd_ps, "dmg": dmg_ps, "aspd": aspd,
	})
	if vfx != null:
		vfx.stele_raise((u["pos"] as Vector2), STELE_RADIUS, STELE_SEC)


## 每帧推进所有碑。★节拍靠"已过秒数 → 应该跳过几次"算, 不是 `acc -= 1.0` 那种自减 ——
##   浮点残差会让第 5 跳落在 4.9999 秒然后多跳一次(5 秒的碑跳 6 次)。
func _tick_steles(delta: float) -> void:
	var cap: int = int(STELE_SEC / STELE_TICK)
	for i in range(_steles.size() - 1, -1, -1):
		var st: Dictionary = _steles[i]
		st["el"] = float(st["el"]) + delta
		var want: int = mini(int(floor(float(st["el"]) / STELE_TICK)), cap)
		while int(st["ticks"]) < want:
			st["ticks"] = int(st["ticks"]) + 1
			_stele_settle(st)
		var src = st.get("src", null)
		## ★到期条件是【跳满 AND 时间到】而不是只看时间 —— 每帧 `el += delta` 的浮点残差
		##   会让第 5 跳落在 4.99999 秒, 只看时间就会在它跳出来之前把碑撤掉(实测: 5 秒的碑只跳 4 次)。
		##   多留的那一帧(≤1 帧)对手感无影响, 但"5 秒 = 5 跳"变成硬事实。
		if int(st["ticks"]) >= cap and float(st["el"]) >= STELE_SEC:
			if src is Dictionary:
				_mana_unlock(src, "p2eq_088")
			_steles.remove_at(i)
		elif src is Dictionary:
			_mana_hold(src, "p2eq_088")               # ★锁期内条压回 0
	_stele_aura()


## 一跳结算: 圈内敌人掉血 + 圈内友军叠盾。
## ★敌人用 `_enemies_of`(**不是** `_pick_enemies_of`): 碑是"按半径扫到谁算谁"的真 AOE,
##   训龟大师照吃 AOE 波及 —— 这是 battle_targeting §PICK-TARGET 写死的语义。
## ★友军用 `_allies_share_pool`: 契约 §4「友军一律排除龟蛋与训龟大师」。
func _stele_settle(st: Dictionary) -> void:
	var src = st.get("src", null)
	if not (src is Dictionary):
		return
	var c: Vector2 = st["pos"]
	var r2: float = STELE_RADIUS * STELE_RADIUS
	for o in battle._targeting._enemies_of(src):
		if not o.get("alive", false):
			continue
		if (o["pos"] as Vector2).distance_squared_to(c) > r2:
			continue
		battle._damage._apply_damage_from(src, o,
			_magic_after_mr(src, float(st["dmg"]), o), COL_TIDE, 0.0, false, true)
		st["hit"] = int(st.get("hit", 0)) + 1
	## ★标一下"这次护盾是哪件装备给的"再清掉 —— `_holy_convert` 读 `battle._cur_eq_item`,
	##   不标的话会拿上一件装备的残留 id 判定(盾羁绊 9 档会白拿一次转化)。
	##   088 是【法器】不是【盾】, 所以标对了反而不会触发转化, 这正是想要的。
	battle._cur_eq_item = "p2eq_088"
	for a in battle._targeting._allies_share_pool(src):
		if not a.get("alive", false):
			continue
		if (a["pos"] as Vector2).distance_squared_to(c) > r2:
			continue
		battle._damage._grant_shield(a, float(st["shd"]))
	battle._cur_eq_item = ""
	var stt: Dictionary = (src as Dictionary)["eq_state"].get("p2eq_088", {})
	stt["stele_ticks"] = int(stt.get("stele_ticks", 0)) + 1   # 同步跳数证据(门禁数它, 不等演出)
	(src as Dictionary)["eq_state"]["p2eq_088"] = stt
	if vfx != null:
		vfx.stele_pulse(c, STELE_RADIUS)


## 圈内攻速: 每帧按"人在不在圈里"重算差量。★这是 buff 而不是一次性给予 ——
##   走出去要立刻没(护盾已给的留着), 所以不能在结算那一跳里发。
##   多块碑重叠取**更高**的那一档(不是相加) —— 同一效果的多来源在本项目一律取高(契约 §4)。
func _stele_aura() -> void:
	if _steles.is_empty() and _aura_units.is_empty():
		return
	var still: Array = []
	for o in battle._units:
		if not (o is Dictionary):
			continue
		var want: float = 0.0
		if o.get("alive", false) and not o.get("is_trainer", false) and not o.get("_isEgg", false):
			for st in _steles:
				var src = (st as Dictionary).get("src", null)
				if not (src is Dictionary):
					continue
				if not (is_same(o, src) or battle._is_ally(src, o)):
					continue
				if (o["pos"] as Vector2).distance_to((st as Dictionary)["pos"] as Vector2) > STELE_RADIUS:
					continue
				want = maxf(want, float((st as Dictionary)["aspd"]))
		var given: float = float(o.get("_stele_aspd", 0.0))
		if absf(want - given) > 1e-9:
			o["aspd_perm"] = maxf(0.01, float(o.get("aspd_perm", 1.0)) + (want - given))
			o["_stele_aspd"] = want
		if want > 0.0:
			still.append(o)
	_aura_units = still


# ══════════════════════════════════════════════════════════════════
#  §089 蚀月符纸 (法器 · 1 费)
#  「法力条集满 → 给一个敌人贴符纸: 15 秒内共造成 400/700/1000 魔法伤害,
#    每秒削减 1 魔抗(本路不恢复)。符纸可叠加。
#    被贴符的敌人死亡时, 带剩余时长的符纸转移到最近的敌人。」
# ══════════════════════════════════════════════════════════════════

## 贴符。目标 = **最近的敌人**(与"转移到最近的敌人"同一把尺子, 见文件头诚实记录)。
## ★选靶走 `_nearest_enemy`(不就地手写): 它把大师/黑洞期/龟蛋围栏三条排除规则收在一处,
##   手抄一份就永远落后一次(memory [[fb-hand-rolled-copies-drift]])。
func _talisman_stick(u: Dictionary, si: int) -> void:
	var tgt = battle._targeting._nearest_enemy(u)
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_089", {})
	var total: float = [400.0, 700.0, 1000.0][si]   # 15 秒内共造成的魔法伤害
	stt["moon_stuck"] = int(stt.get("moon_stuck", 0)) + 1   # 同步触发证据(门禁数它)
	u["eq_state"]["p2eq_089"] = stt
	_talismans.append({
		"src": u, "si": si, "tgt": tgt, "el": 0.0, "ticks": 0, "hops": 0,
		"per": total / TALISMAN_SEC,
	})
	if vfx != null:
		vfx.talisman_stick(tgt, TALISMAN_SEC)


## 每帧推进所有符纸。节拍算法同碑(按"已过秒数"推, 不自减)。
func _tick_talismans(delta: float) -> void:
	var cap: int = int(TALISMAN_SEC / TALISMAN_TICK)
	for i in range(_talismans.size() - 1, -1, -1):
		var tl: Dictionary = _talismans[i]
		if not _talisman_retarget(tl):
			_talismans.remove_at(i)
			continue
		tl["el"] = float(tl["el"]) + delta
		var want: int = mini(int(floor(float(tl["el"]) / TALISMAN_TICK)), cap)
		while int(tl["ticks"]) < want:
			tl["ticks"] = int(tl["ticks"]) + 1
			_talisman_settle(tl)
		## ★同碑: 到期条件是【跳满 AND 时间到】, 浮点残差不许吃掉第 15 跳。
		if int(tl["ticks"]) >= cap and float(tl["el"]) >= TALISMAN_SEC:
			_talismans.remove_at(i)


## 目标死了 → 把符纸转到【最近的敌人】。返回 false = 没人可转, 这张符纸作废。
## ★★**只转剩余时长**(`el` / `ticks` 原样带走) —— 已削的魔抗留在死者身上,
##   新目标从**它自己的**魔抗开始削。用户 2026-08-06 明确拍板过这条。
## ★"最近"是【离死者最近】, 用 `_nearest_enemy_from(src, 死者位置)`:
##   符纸是从尸体上飞出去的, 尺子的原点就该在尸体上, 不在携带者身上。
func _talisman_retarget(tl: Dictionary) -> bool:
	var tgt = tl.get("tgt", null)
	if tgt is Dictionary and (tgt as Dictionary).get("alive", false):
		return true
	var src = tl.get("src", null)
	if not (src is Dictionary) or not (tgt is Dictionary):
		return false
	var from: Vector2 = (tgt as Dictionary)["pos"]
	var nx = battle._targeting._nearest_enemy_from(src, from)
	if not (nx is Dictionary):
		return false
	tl["tgt"] = nx
	tl["hops"] = int(tl.get("hops", 0)) + 1
	if vfx != null:
		vfx.talisman_transfer(from, (nx as Dictionary)["pos"] as Vector2)
		vfx.talisman_stick(nx, maxf(0.0, TALISMAN_SEC - float(tl["el"])))
	return true


## 一跳: 掉血 + 削 1 点魔抗。
func _talisman_settle(tl: Dictionary) -> void:
	var src = tl.get("src", null)
	var tgt = tl.get("tgt", null)
	if not (src is Dictionary) or not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	battle._damage._apply_damage_from(src, tgt,
		_magic_after_mr(src, float(tl["per"]), tgt), COL_MOON, 0.0, false, true)
	_shred_mr(tgt, TALISMAN_MR_PER_TICK)
	var stt: Dictionary = (src as Dictionary)["eq_state"].get("p2eq_089", {})
	stt["moon_ticks"] = int(stt.get("moon_ticks", 0)) + 1   # 同步跳数证据(门禁数它)
	(src as Dictionary)["eq_state"]["p2eq_089"] = stt


## 削魔抗 —— 走 `_recalc_stats` 的 **`mr_shred` 通道**(主会话 2026-08-06 在共享文件里开的口子:
## `u["mr"] = maxf(0.0, base_mr*(1+pct)+flat) - mr_shred`, 即**钳完再减**)。
##
## ★本文件**不写** `mr` 也**不写** `base_mr`, 只累加削减量, 由那个唯一写入点自己算:
##   · 削穿之后 `mr` 自然为负 ⇒ `DamageMath.resist_multiplier` 按 `1+|r|/(|r|+40)` 给增伤(上限 2.0),
##     不必在这边镜像任何公式(镜像过一版, 已删 —— [[fb-hand-rolled-copies-drift]]);
##   · 「钳完再减」意味着**只有显式削减**拿得到负抗性, 百分比 debuff 那类照旧被钳在 0, 行为没变;
##   · `mr_shred` 是**单位字段** ⇒ **换路整体重建单位时自动清零** = 用户定的
##     「削掉的魔抗本路不恢复、换路重置」, 本文件不需要任何自管重置。
func _shred_mr(o: Dictionary, amt: float) -> void:
	o["mr_shred"] = float(o.get("mr_shred", 0.0)) + amt
	battle._recalc_stats(o)


# ══════════════════════════════════════════════════════════════════
#  §090 镇海杵 (法器 · 5 费)
#  主动「法力条集满 → 跳到空中后向整个战场猛砸: 1000 码内敌人受到
#        3 ATK + 200/300/5000 魔法伤害, 2/3/8 秒眩晕 + 1 秒击飞。
#        ★造成伤害后才重新开始记录法力值。」
#  被动「每第三次普攻发射一片浪潮, 从携带者飞向目标后不断跳向最近的、
#        未被本次浪潮飞过的友军或敌军, 最多跳 4/5/8 次;
#        打到敌人 40/70/140 魔法伤害, 打到友军 20/40/80 治疗。」
#  ⚠ 3★ 是全表最大的一次星级跳跃(魔伤 300→5000 · 眩晕 3→8 秒)。
#     用户原话「5000，8秒，就要8」—— 照做, 不许在实施时调低。
# ══════════════════════════════════════════════════════════════════

## 起跳。逐星数组就近声明并快照进在途记录(锚点 = 本函数里的 `"p2eq_090"`)。
func _pestle_leap(u: Dictionary, si: int) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_090", {})
	var flat: float = [200.0, 300.0, 5000.0][si]    # 猛砸的固定魔法伤害段(另加 3 ATK)
	var stun: float = [2.0, 3.0, 8.0][si]           # 猛砸的眩晕秒数
	stt["pestle_leaps"] = int(stt.get("pestle_leaps", 0)) + 1   # 同步触发证据(门禁数它)
	u["eq_state"]["p2eq_090"] = stt
	_mana_lock(u, "p2eq_090")                        # ★砸出伤害之前, 法力条不增长
	## ★`air_id`: 这一跳的专属编号。落地事件只认自己那一跳 —— 携带者在半空被【别人】
	##   击飞再落地时, 不至于被误判成"我砸下来了"(方案书 20260809 风险 4)。
	_pestle_air_seq += 1
	u["_pestle_air_id"] = _pestle_air_seq
	var _p0: Vector2 = Vector2(u["pos"])
	var _dest: Vector2 = pestle_dest(u)
	_slams.append({"u": u, "si": si, "flat": flat, "stun": stun,
		"t_left": pestle_jump_sec(), "air_id": _pestle_air_seq,
		"p0": _p0, "dest": _dest, "t_total": pestle_jump_sec()})
	## 起跳: 直接写击飞物理字段, 由主循环那段 airborne 积分抛起再落回(不用 tween)。
	## 峰高 h 与滞空 T 解耦: vy = 2h/T, g = −4h/T² ⇒ 落地时刻恰好 = T = 砸落时刻。
	if not u.get("airborne", false):
		u["airborne"] = true
		u["vy"] = sqrt(2.0 * PESTLE_G * PESTLE_APEX_M)   # v₀ = √(2gh)
		u["vx"] = 0.0
		u["vz"] = 0.0
		u["knock_g"] = -PESTLE_G                          # 重力是**给定的**, 不是倒推的
	if vfx != null:
		vfx.pestle_leap(u, pestle_jump_sec(), _dest)   # ★预警圈画在【落点】, 不是起跳点


## 这一跳落在哪 —— 敌人最密集处, 但最多离携带者 `PESTLE_LEAP_MAX` 码。
##
## ★密度选点【复用】`BowEqVfx.densest_point`(最大覆盖 → 覆盖集质心, 纯几何零 RNG):
##   075 箭雨与 067 毒药瓶用的就是它。再写一份必然漂(memory [[fb-hand-rolled-copies-drift]])。
## ★用 `_enemies_of`(真 AOE 的名单): 砸落本身是范围结算, 选落点时把训龟大师算进"人堆"
##   是合理的 —— 它站在哪儿确实影响"哪里人多"; 而它照样只吃 AOE 波及, 没有被"锁定"。
## ★没有敌人 ⇒ 原地跳(返回自身位置), 不是跳到 (0,0)。
func pestle_dest(u: Dictionary) -> Vector2:
	var here: Vector2 = Vector2(u["pos"])
	var pts: Array = []
	for o in battle._targeting._enemies_of(u):
		if o is Dictionary and (o as Dictionary).get("alive", false):
			pts.append(Vector2((o as Dictionary)["pos"]))
	if pts.is_empty():
		return here
	var want: Vector2 = BowEqVfx.densest_point(pts, PESTLE_RADIUS)
	var d: Vector2 = want - here
	if d.length() > PESTLE_LEAP_MAX:
		want = here + d.normalized() * PESTLE_LEAP_MAX
	## 钳进战场(别跳到墙外/屏外)
	want.x = clampf(want.x, battle.ARENA.position.x + 40.0, battle.ARENA.end.x - 40.0)
	want.y = clampf(want.y, battle.ARENA.position.y + 40.0, battle.ARENA.end.y - 40.0)
	return want


## 在途猛砸的倒计时。携带者中途死了就丢掉这条(并解锁, 免得留一把锁在尸体上)。
func _tick_slams(delta: float) -> void:
	for i in range(_slams.size() - 1, -1, -1):
		var sl: Dictionary = _slams[i]
		var u = sl.get("u", null)
		if not (u is Dictionary) or not (u as Dictionary).get("alive", false):
			if u is Dictionary:
				_mana_unlock(u, "p2eq_090")
				## ★演出善终、效果作废(用户 2026-08-13):「携带者阵亡, 预警特效还是持续到
				##   正常消失, 只是没有拍地和击飞特效了」。
				##   不孤儿化的话, 预警圈永远等不到落地事件 ⇒ 一直亮到 watchdog(≈7.0 秒),
				##   而这一跳本来只有 1.67 秒 —— 圈会在尸体上多亮 5 秒多。
				if vfx != null:
					vfx.orphan_leap(u)
			_slams.remove_at(i)
			continue
		sl["t_left"] = float(sl["t_left"]) - delta
		## ★横向位移用【显式插值】而不是给 vx/vz 初速: 滞空积分每帧对横速做阻尼(_kdamp),
		##   给初速会落不准; 仓库先例 `_pull_airborne` 的注释就写着"vx/vz 须为 0, 靠此改 pos"。
		var _tt: float = maxf(0.001, float(sl.get("t_total", 1.0)))
		var _q: float = clampf(1.0 - float(sl["t_left"]) / _tt, 0.0, 1.0)
		if sl.has("p0") and sl.has("dest") and (u as Dictionary).get("airborne", false):
			(u as Dictionary)["pos"] = (sl["p0"] as Vector2).lerp(sl["dest"] as Vector2, _q)
		## ★★砸落**不再由倒计时触发** —— 由 `on_unit_landed`(真实落地事件)结算。
		##   历史: 倒计时走 `tick_global` 的 delta, 而跳跃走被顿帧/时停门控的 `_tick_unit`,
		##   两条时钟在顿帧期间分叉 ⇒ 砸落提前(实测结算那一刻龟还在 3.59 米高)。
		##   这里只剩两种收尾:
		##     ① 携带者压根没进滞空态(起跳时已被别人击飞 ⇒ 我们没写物理) ⇒ 到点即结算
		##     ② 兜底: 超时 PESTLE_SLAM_WATCHDOG 还没落地 ⇒ 强制结算, 不留孤儿
		if float(sl["t_left"]) <= 0.0 and not (u as Dictionary).get("airborne", false):
			_slams.remove_at(i)
			pestle_slam(sl)
		elif float(sl["t_left"]) <= -PESTLE_SLAM_WATCHDOG:
			_slams.remove_at(i)
			pestle_slam(sl)
		else:
			_mana_hold(u, "p2eq_090")   # ★还在半空 ⇒ 法力条压回 0(「造成伤害后才重新记录」)


## 【真实落地事件】—— 主循环在 `airborne` true→false 那一帧调。
## ★这是"砸击命中 = 落地那一刻"的**唯一**正常触发路径: 演出与结算读的是同一个物理事件,
##   不存在两个时钟对不上的问题。门禁 ③L2 注入顿帧反证这一点。
func on_unit_landed(u: Dictionary) -> void:
	if _slams.is_empty() or not (u is Dictionary):
		return
	var aid: int = int((u as Dictionary).get("_pestle_air_id", -1))
	for i in range(_slams.size() - 1, -1, -1):
		var sl: Dictionary = _slams[i]
		if not is_same(sl.get("u", null), u):
			continue
		## 只认自己那一跳(见 air_id 的注释)。`air_id` 对不上说明这次落地是别人把它击飞的,
		## 本次猛砸还在自己的行程里 —— 不结算, 继续等。
		if int(sl.get("air_id", -1)) != aid:
			continue
		_slams.remove_at(i)
		pestle_slam(sl)


## 砸落结算。★独立具名函数: 演出末尾调它、门禁也直接调它 ——
##   一个测"数值对不对"的用例不该依赖任何动画 tween 跑完(CLAUDE.md §3.5)。
## ★用 `_enemies_of`(真 AOE, 大师照吃波及)而不是 `_pick_enemies_of`。
func pestle_slam(sl: Dictionary) -> void:
	var u = sl.get("u", null)
	if not (u is Dictionary):
		return
	var c: Vector2 = (u as Dictionary)["pos"]
	var r2: float = PESTLE_RADIUS * PESTLE_RADIUS
	var base: float = float((u as Dictionary).get("atk", 0.0)) * PESTLE_ATK_SCALE + float(sl["flat"])
	var n: int = 0
	for o in battle._targeting._enemies_of(u):
		if not o.get("alive", false):
			continue
		if (o["pos"] as Vector2).distance_squared_to(c) > r2:
			continue
		battle._damage._apply_damage_from(u, o, _magic_after_mr(u, base, o), COL_SLAM, 0.0, false, true)
		battle._damage._stun(o, float(sl["stun"]), "p2eq_090")
		_knock_for(u, o, PESTLE_KB_SEC)
		n += 1
	var stt: Dictionary = (u as Dictionary)["eq_state"].get("p2eq_090", {})
	stt["pestle_slams"] = int(stt.get("pestle_slams", 0)) + 1
	stt["pestle_slam_hit"] = n
	(u as Dictionary)["eq_state"]["p2eq_090"] = stt
	_mana_unlock(u, "p2eq_090")   # ★★造成伤害【之后】才重新开始记录法力值
	if vfx != null:
		vfx.drop_leap(u)              # ★同一事件里收起跳演出 —— 圈不许比人晚落地
		vfx.pestle_slam(c, PESTLE_RADIUS)


## 每次普攻攒一下, 第三下发浪潮。
func _pestle_on_basic(u: Dictionary, tgt, si: int) -> void:
	var stt: Dictionary = u["eq_state"].get("p2eq_090", {})
	var n: int = int(stt.get("pestle_basics", 0)) + 1
	if n < PESTLE_EVERY:
		stt["pestle_basics"] = n
		u["eq_state"]["p2eq_090"] = stt
		return
	stt["pestle_basics"] = 0
	var hops: int = [4, 5, 8][si]                   # 一片浪潮最多跳几次
	var dmg: float = [40.0, 70.0, 140.0][si]        # 打到敌人的魔法伤害
	var heal: float = [20.0, 40.0, 80.0][si]        # 打到友军的治疗
	stt["pestle_waves"] = int(stt.get("pestle_waves", 0)) + 1
	u["eq_state"]["p2eq_090"] = stt
	var got: Array = wave_chain(u, tgt, hops, dmg, heal)
	stt = u["eq_state"].get("p2eq_090", {})
	stt["wave_hits"] = int(got[0])
	stt["wave_dmg_n"] = int(got[1])
	stt["wave_heal_n"] = int(got[2])
	u["eq_state"]["p2eq_090"] = stt


## 浪潮链: 从携带者出发, 第一跳打 `first`(普攻的那个目标), 之后每次跳向
## **离当前落点最近的、本次浪潮还没飞过的**友军或敌军。返回 [总命中, 打敌数, 奶友数]。
##
## ★"未被本次浪潮飞过"按【次施放】各自记 —— `visited` 是本函数的局部 Array,
##   一次浪潮一份。**绝不拿单位字典当 Dictionary 的键**(Godot 递归哈希 + 互引成环 → 卡死,
##   CLAUDE.md §3.2), 判存在一律 `battle._arr_has_unit`, 比较一律 `is_same`。
## ★携带者一开始就在 `visited` 里 —— 他是起点, 浪潮不回头。
## 第 i 跳(0 起)落到目标的时刻(秒)。★演出与结算共用这一个函数 —— 两边各算一份
## 就是"演出到了伤害还没到"的老毛病(CLAUDE.md 里 084 剑波焊 WAVE_SPD 也是为这个)。
static func wave_hop_delay(i: int) -> float:
	return WAVE_HOP_SEC * float(i + 1)


func wave_chain(u: Dictionary, first, hops: int, dmg: float, heal: float) -> Array:
	var visited: Array = [u]
	var path: Array = [(u["pos"] as Vector2)]
	var hit: int = 0
	var nd: int = 0
	var nh: int = 0
	var cur: Vector2 = u["pos"]
	var nxt = null
	if first is Dictionary and (first as Dictionary).get("alive", false) \
			and not battle._arr_has_unit(visited, first):
		nxt = first
	else:
		nxt = _wave_next(u, cur, visited)
	while hit < hops and nxt is Dictionary:
		var o: Dictionary = nxt
		visited.append(o)
		path.append(o["pos"] as Vector2)
		# ★★2026-08-08【时序合一】伤害/治疗**等那一簇水真的跳到**才结算。
		#   用户:「浪潮弹射是一簇水在目标之间跳来跳去, 有高度变化, 并不是闪电连锁」——
		#   既然它是**飞过去**的, 就不该在出手那一帧把整条链全算完(旧版就是那样,
		#   演出还没画完血已经掉光了)。每跳按累计飞行时间延后。
		var tgt_u: Dictionary = o
		var lag: float = wave_hop_delay(hit)
		var to_foe: bool = battle._is_hostile(u, o)
		battle._queue_shots(1, 0.0, func() -> void:
			if not tgt_u.get("alive", false):
				return
			if to_foe:
				battle._damage._apply_damage_from(u, tgt_u, _magic_after_mr(u, dmg, tgt_u),
					COL_WAVE, 0.0, false, true)
			else:
				battle._damage._heal(tgt_u, heal), u, "", Callable(), lag)
		if to_foe:
			nd += 1
		else:
			nh += 1
		hit += 1
		cur = o["pos"]
		nxt = _wave_next(u, cur, visited)
	if vfx != null and path.size() >= 2:
		vfx.wave_path(path)
	return [hit, nd, nh]


## 下一跳: 离 `from` 最近、且不在 `visited` 里的友军或敌军。没有就返回 null。
## ★敌人走 `_pick_enemies_of`(定向选取闸门: 排大师/黑洞期), 友军走 `_allies_share_pool`
##   (契约 §4: 排龟蛋与训龟大师) —— 两张名单都不是就地手写的。
func _wave_next(u: Dictionary, from: Vector2, visited: Array):
	var best = null
	var bd: float = INF
	for pool in [battle._targeting._pick_enemies_of(u), battle._targeting._allies_share_pool(u)]:
		for o in pool:
			if not (o is Dictionary) or not o.get("alive", false):
				continue
			if battle._arr_has_unit(visited, o):
				continue
			var d: float = (o["pos"] as Vector2).distance_squared_to(from)
			if d < bd:
				bd = d
				best = o
	return best
