class_name EquipTickSystem
extends RefCounted
## 装备周期效果tick系统
## 类内名不变;外部名加 battle.

## ★★2026-08-22 文案根除: 034/036 的标量原来散在本文件与主场景里。
## 【034 玩偶小熊】
## 大熊熊掌的【命中时刻】: 整套挥击 0.07×7 秒的 45% 处(挥击接触帧, 不是攻击一开始)。
## ★抽成常量不是为了文案, 是**门禁要拿它推 sim** —— 推少了量到 0 会被误判成「伤害没落」。
const BEAR_PAW_HIT_AT := 0.07 * 7.0 * 0.45
const DOLL_IV := 4.0            # 每几秒派一只小熊
const DOLL_CHARGE_SEC := 1.2    # 大熊层满后, 携带者蓄力几秒才召大熊
const BEAR_ASPD := 0.7          # 大熊攻速(次/秒) ⇒ atk_interval = 1/它
const BEAR_RANGE := 70.0        # 大熊射程(码·近战)
## 大熊立绘的世界高度 = TARGET_BODY_H(2.0m) × BEAR_COL_SIZE / 56。
## ★★2026-09-13 从 48 提到 88。实拍量过: 48 那版大熊只有 **36 屏幕像素高, 比基础龟(~42px)还矮** ——
##   一件 5 费装备攒一整局才召出来的、15000 血 2000 攻的「**大**熊」, 读起来比小龟还小。
##   88 ⇒ 3.14 m ≈ 1.57 个龟高, 场上最大的那个。
## ★`col_size` 只喂 `spr.pixel_size`(纯立绘缩放), **不碰碰撞也不碰任何数值** —— 全仓只有两处读它。
const BEAR_COL_SIZE := 88.0
const BEAR_RESIST := 70.0       # 大熊护甲与魔抗(各·用户 2026-07-30: 20 → 70)
const BEAR_PAW_STACKS := 2      # 熊掌累积几层后, 下一击改成冲击波
const BEAR_WAVE_COEF := 1.5     # 冲击波 ×ATK 物理
const BEAR_WAVE_RANGE := 600.0  # 冲击波那一击射程临时扩到(码)
const BEAR_WAVE_KNOCK_SEC := 0.8  # 冲击波击飞滞空(秒)
const BEAR_WAVE_PULL := 70.0    # 冲击波把命中者拉回身前(码)
## 【036 温泉蛋】孵化进度的五个来源 + 满进度阈值 + 每级成长
## 【014 深海堡垒甲】受击叠硬化, 满层后周期性汲取全体敌。
const FORTRESS_CAP := 25       # 硬化层上限(013 是 20, 见 equip_stats_apply)
const FORTRESS_IV := 8.0       # 满层后每几秒汲取一次
const FORTRESS_HEAL_LOST := 0.05   # 每汲取 1 名敌人, 额外回复自身【已损】生命 ×
const EGG_FULL := 100.0         # 进度满多少 → +1 临时等级
const EGG_PER_CYCLE := 5.0      # 每周期 +
## 那个"周期"= 全局装备周期 RealtimeBattle3DScene.EQ_TICK(2.5 秒), 温泉蛋不另设间隔,
## 所以这里【不存副本】—— 存了就会和 EQ_TICK 各走各的。
const EGG_ON_FOE_DEATH := 10.0  # 敌方死亡 +
const EGG_ON_ALLY_DEATH := 15.0 # 己方死亡 +
const EGG_DMG_RATIO := 0.1      # 造成/承受伤害 × 此比例计入进度
const EGG_LV_GROWTH := 0.05     # 每级 + 基础属性(线性, 非复利)
## 每级 + 攻速。★原来这个 0.02 **连常量都没有**, 直接写死在两处公式里 ——
##   文案只写了 `{C:EquipTickSystem.EGG_LV_GROWTH%}` 那一档, 这一档是"写了代码没写文案"的哑数。
##   抽出来至少让它可被搜到、可被门禁量到(数值一个没动)。
const EGG_LV_ASPD := 0.02

var battle

func _init(b) -> void:
	battle = b

# 数据驱动基础技能: 按 spec 算物/魔/真伤(含加成项)分段打出 + 附带/特殊机制 (1:1 原始 skillPool[0])
func _tick_doll(u: Dictionary, delta: float) -> void:   # 玩偶小熊: 每4s派小熊+攒层; 满层→蓄力→召大熊(不与末只小熊同帧)
	var es: Dictionary = u.get("eq_state", {})
	if not es.has("p2eq_034"): return
	var stt: Dictionary = es["p2eq_034"]
	if bool(stt.get("bear_done", false)) or bool(stt.get("bear_charging", false)): return
	var si: int = int(stt.get("doll_si", 0))
	var _iv: float = 1.0 if OS.has_environment("EQDEMO_FAST") else DOLL_IV   # FAST=快速看波
	stt["doll_t"] = float(stt.get("doll_t", 0.0)) + delta
	if float(stt["doll_t"]) < _iv: return
	stt["doll_t"] = 0.0
	var mt = battle._targeting._nearest_enemy(u)
	if mt == null: return
	var bdm: int = battle._resolve_dmg(u, u["atk"] * [1.0, 2.0, 5.0][si] + [100.0, 210.0, 1000.0][si], mt, false)
	battle._summon_walking_bear(u, mt, bdm)
	stt["bear_layers"] = int(stt.get("bear_layers", 0)) + 1
	var _cap: int = 1 if OS.has_environment("EQDEMO_FAST") else [5, 3, 1][si]
	if int(stt["bear_layers"]) >= _cap:
		stt["bear_charging"] = true
		battle._big_bear_charge_and_spawn(u, si)

func _tick_bear_anim(u: Dictionary, delta: float) -> void:   # 大熊状态机: 移动→走路循环 / 停下→顿住 / 拍击→熊爪 / 冲击波→举手砸地
	var spr = u.get("sprite", null)
	if not is_instance_valid(spr): return
	var ne = battle._targeting._nearest_enemy(u)                     # 朝向最近敌(熊默认朝左→敌在右则flip朝右; 迟滞防抖)
	if ne != null and absf(float(ne["pos"].x) - float(u["pos"].x)) > 40.0:
		spr.flip_h = float(ne["pos"].x) > float(u["pos"].x)
	u["bear_anim_t"] = float(u.get("bear_anim_t", 0.0)) + delta
	var anim = str(u.get("bear_anim", "walk"))
	var voff = Vector3.ZERO
	var ldir: Vector3 = u.get("_bear_ldir", Vector3.ZERO)
	if anim == "attack" or anim == "slam":
		if str(u.get("_bear_sheet", "")) != anim:
			battle._set_bear_sheet(spr, anim); u["_bear_sheet"] = anim; u["bear_anim_t"] = 0.0
		var per: float = 0.07 if anim == "attack" else 0.085
		var total: float = per * float(maxi(1, int(spr.hframes)))
		var prog: float = clampf(float(u["bear_anim_t"]) / maxf(0.01, total), 0.0, 1.0)
		var f: int = int(float(u["bear_anim_t"]) / per)
		# ★★2026-08-07 修: 这里原来只按 `spr.hframes` 判越界, 但引擎校验的是
		#   **hframes × vframes**, 而 `_set_bear_sheet` 换 texture 与写 hframes 之间有一帧窗口
		#   ⇒ 那一帧拿到的是【新表的 hframes + 旧表的贴图】, 于是刷
		#   `ERROR: Index p_frame = 17 is out of bounds (vframes*hframes = 7)`。
		#   与忍者冲刺那处(2026-08-07 同日修)是同一族: **表换了、取帧的代码没跟**。
		#   ⇒ 一律按【贴图当下的真实总帧数】钳制, 表以后再换也不会越界。
		var _bmax: int = maxi(0, int(spr.hframes) * int(spr.vframes) - 1)
		if f > _bmax:
			if u.get("_slam_manual", false):
				spr.frame = _bmax   # 手控砸地: 定住末帧(等波传完, 不回走路循环=修漂移)
			else:
				u["bear_anim"] = "walk"          # 播完回走路/待机
		else:
			spr.frame = mini(f, _bmax)
		if anim == "attack":
			voff = ldir * (sin(prog * PI) * 0.55)          # 前扑扑击(前冲再回)
			voff.y += sin(prog * PI) * 0.14                # 略抬(挥爪)
		# slam 的位移由 _bear_shockwave 手控(_slam_manual), 这里只推进帧
	else:   # walk / idle: 移动→循环走路, 停下→站立顿住(frame0)
		if str(u.get("_bear_sheet", "")) != "walk":
			battle._set_bear_sheet(spr, "walk"); u["_bear_sheet"] = "walk"
		var pv: Vector2 = u.get("_bear_pp", u["pos"])
		var moving: bool = (u["pos"] - pv).length() > 0.6
		u["_bear_pp"] = u["pos"]
		if moving:
			spr.frame = int(float(u["bear_anim_t"]) * 9.0) % maxi(1, int(spr.hframes))
		else:
			spr.frame = 0
	if not u.get("_slam_manual", false):   # 砸地手控voff期间不覆盖
		u["_bear_voff"] = voff

func _tick_fortress(u: Dictionary, delta: float) -> void:   # 深海堡垒甲p2eq_014: 硬化满25层(harden_cap·见 equip_stats_apply)后每8秒汲取全体敌(魔伤0.8/1/2.5×(护甲+魔抗))+每敌回血 50/100/250+已损5%; 满层瞬间立即首次; 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_014": continue
		var stt: Dictionary = u["eq_state"].get("p2eq_014", {})
		if int(stt.get("harden_stacks", 0)) < int(stt.get("harden_cap", FORTRESS_CAP)):
			e["fortress_t"] = FORTRESS_IV   # 未叠满→预置一整个周期(叠满瞬间立即首次汲取)
			continue
		e["fortress_t"] = float(e.get("fortress_t", 0.0)) + delta
		if float(e["fortress_t"]) < FORTRESS_IV: continue
		e["fortress_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		# ★用户 2026-07-30 削弱: 汲取倍率 0.9/1.6/3.0 → 0.8/1/2.5;
		#   每汲取一个敌人回血 60/110/250 + 已损6% → 50/100/250 + 已损5%。
		#   (三星回复 250 是用户 2026-07-31 亲口确认的 —— 他原话写的是"25", 我判断是笔误并问了他。)
		# ★数组【就近声明】而不是提到文件顶部 —— tooltip_number_audit 要求文案里的
		#   "0.8/1/2.5" 这类三元组能在【装备 id 锚点附近】找到同样的数组; 放文件顶部会判"太远"。
		#   (这也和本文件其它效果的写法一致, 见铁壁盾的 [100.0, 250.0, 400.0]。)
		var k2: float = [0.8, 1.0, 2.5][si]                    # 用户2026-07-30 削弱: 0.9/1.6/3.0 →
		var heal_flat: float = [50.0, 100.0, 250.0][si]        # 用户2026-07-30 削弱: 60/110/250 →
		for o in battle._targeting._enemies_of(u):
			# ★★汲取【排除训龟大师与屏障里的龟蛋】(用户 2026-07-30)。
			#   大师是"场外监视者"(不计团灭·见 _dl_side_alive), 拿它当汲取目标既能白嫖回血、
			#   又会把伤害打在一个本不该参战的单位上; 蛋在屏障里更不该被隔空汲。
			if o.get("is_trainer", false):
				continue
			if o.get("_isEgg", false) or o.get("_eggImmune", false):
				continue
			## ★★014 的汲取不再用 `_bolt_line`(直线光束) —— 用户 2026-09-12:
			##   「为什么又用什么长方形来敷衍」。他定的是四拍:
			##   绿色粒子从目标抽出 → 空中飘舞 → 飞到携带者 → 携带者绿色粒子爆发。
			##   `_bolt_line` 留给真正是「一道光束」的地方(闪电链/凤凰喷火)。
			battle._vfx.drain_stream(o["pos"], u["pos"])
			battle._damage._apply_damage_from(u, o, battle._resolve_dmg(u, k2 * (u["def"] + u["mr"]), o, true), Color("#bfe9ff"), 0.0, false, true)   # 真·魔法伤害(走魔抗); 原 raw=true 是白字真伤·与文案"魔法伤害"不符(用户2026-07-19指出)
			battle._damage._heal(u, heal_flat + maxf(0.0, u["maxHp"] - u["hp"]) * FORTRESS_HEAL_LOST)   # 已损生命 6% → 5%

func _tick_ironwall(u: Dictionary, delta: float) -> void:   # 铁壁盾p2eq_016: 每5秒放一个总护盾池(100/250/400 + 携带者8%最大生命)由全队(含自己)均分(用户2026-07-19; 原每人固定15/20/25); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_016": continue
		e["ironwall_t"] = float(e.get("ironwall_t", 0.0)) + delta
		if float(e["ironwall_t"]) < IRONWALL_IV: continue
		e["ironwall_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var mates: Array = battle._targeting._allies_share_pool(u)   # ★均分排除大师+龟蛋(都不占盾份额·稀释)·用户2026-07-23 点4 / 2026-08-01
		if mates.is_empty(): continue
		var pool: float = [100.0, 250.0, 400.0][si] + u["maxHp"] * IRONWALL_MAXHP_PCT   # 总池: 固定 + 携带者最大生命×
		var each: float = pool / float(mates.size())                      # 全队(含自己·除大师/龟蛋)均分
		for o in mates:
			battle._damage._grant_shield(o, each, BattleDamage.COMMON_SHIELD_SEC)   # 通用护盾=4秒(文案没写时长); 周期 IRONWALL_IV=5s 大于它 ⇒ 每轮中间有 1 秒空窗


## 【017 不沉之锚】回血攒充能 → 充能期加攻速 → 普攻消耗充能击飞。
const ANCHOR_ASPD := 1.00      # 持有充能期间普攻攻速 +(真值在 battle_damage.anchor_aspd)
## 那一击的眩晕走【通用 CTRL_SEC】(RealtimeBattle3DScene), 这里不存副本。
## 【021 守护贝母】持续连全队最高攻友军, 周期性重连并给双方一串永久加成。
## 【周期件的触发间隔(秒)】★2026-08-25 文案根除: 这些原来全是各自 `_tick_*` 函数体里的
##   裸字面量, 而 json 的 effectDesc1 / effectBrief 又各手写了一遍 —— 同一个数存三份。
##   现在代码是唯一的那一份, 两处文案都用 `{C:EquipTickSystem.XXX_IV}` 指过来。
const RUST_IV := 3.0            # 001 木制长剑: 每几秒甩一道飞斩剑气
const RUST_RANGE := 2000.0      # 001 剑气射程(码)·2000 = 全场覆盖(用户 2026-07-19 近战→远程)
const JELLY_MAXHP_PCT := 0.04   # 012 海藻: 护盾 = 固定值 + 自身最大生命 ×
const IRONWALL_MAXHP_PCT := 0.08  # 016 铁壁盾: 护盾总池 = 固定值 + 携带者最大生命 ×
const SWORD_STORM_IV := 7.0     # 006 千刃风暴: 每几秒召一排剑穿过全体敌人
const BROADSWORD_IV := 6.0      # 007 锈蚀阔剑: 每几秒挥一道剑气墙
const CORAL_IV := 9.0           # 008 双穿珊瑚刺: 每几秒射一根尖刺(用户 2026-07-19: 6 → 9)
const JELLY_IV := 4.0           # 012 海藻: 每几秒给自己套一次护盾
const IRONWALL_IV := 5.0        # 016 铁壁盾: 每几秒产生一份由全队分摊的护盾
const SHELL_IV := 8.0           # 018 守护贝壳: 每几秒自回一次
const ANEMONE_IV := 7.0         # 019 海葵药膏: 每几秒治自己与最残友军
const DUMBBELL_IV := 8.0        # 020 哑铃: 每几秒锻炼 + 投掷(用户 2026-07-19: 10 → 8)
## ★★【游戏钟延时队列】—— 全装备共用的原语。
##   由来: `tween_interval` + `tween_callback` 做延时投递, 而 **tween 走未钳制的真实 delta,
##   无头下推不动**(CLAUDE.md §3.5)。024 龙蛋、025 雷鸣贝壳、026 雷电法杖**连着三件**都栽在这上面
##   ⇒ 这是一整类, 所以做成共享原语而不是每件各造一个队列
##   (memory [[fb-fix-the-shared-primitive-not-one-instance]])。
##   用法: `battle._equip_tick_sys.schedule(0.4, some_callable)`
const BOLT_GAP := 0.3             # 025 道间错峰(秒·游戏钟)
const BOLT_HIT_DELAY := 0.25      # 025 伤害落在闪电动画中段(秒·游戏钟)
var _bolt_q: Array = []

const THUNDER_IV := 4.0         # 025 雷鸣贝壳: 每几秒降一次雷
const GEAR_IV := 6.0            # 035 黄铜齿轮: 每几秒进一次深海币
const BARNACLE_IV := 5.0        # 每几秒重连一次并给 buff
const BARNACLE_ENERGY := 10.0   # 每次给自己和该友军的龟能
const BARNACLE_ASPD := 0.10     # 每次给自己和该友军的攻速 +(永久本场·可叠)
const ANCHOR_IV := 0.25                # 不沉之锚回血节拍(秒) —— 用户 2026-08-01「恢复触发改为每0.25秒去回复生命值」
const ANCHOR_ACC_PER_CHARGE := 250.0   # 累积治疗满这么多 → +1 沉锚充能(用户2026-07-19: 100→250)

## 不沉之锚 p2eq_017: 治疗【生命百分比最低的友军(含自己)】0.1/0.2/3% 携带者maxHp(用户 2026-08-12 削弱, 原 1/2/15%); 累积治疗满250→+1充能。
## ★★2026-08-01 把触发从【每次受伤】改成【每 0.25 秒】(用户点名)。
##   原来挂在 on-hurt 上 → 回血量与"挨了几下"绑定: 被一群小兵点死的场面奶得飞快,
##   被一发大招秒的场面一次都没回 —— 同一件装备在两种局里完全是两个东西。
##   ★只按【实际回进去的血】攒充能(满血空奶不攒·用户2026-07-19) —— 改成定时后这条更要紧,
##   否则全队满血时每 0.25 秒都白攒一次, 充能会自己涨满。
func _tick_anchor(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	if not u.get("alive", false): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_017": continue
		e["anchor_t"] = float(e.get("anchor_t", 0.0)) + delta
		if float(e["anchor_t"]) < ANCHOR_IV: continue
		e["anchor_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_017", {})
		## 用户 2026-08-12 削弱:「巨沉之锚的每 0.25 回血削弱为 0.1/0.2/3% 最大生命值」
		## (原 1/2/15%)。★注意这条回血还兼着充能来源(累积治疗满 250 → +1 沉锚充能),
		##   所以削回血 = 连带把沉锚充能的攒速一起削了, 不是只削治疗量。
		var heal_amt: float = u["maxHp"] * [0.001, 0.002, 0.03][si]
		var low = null
		var lv := INF
		for o in battle._targeting._allies_of(u):
			if not o.get("alive", false): continue
			var p: float = CombatMath.hp_frac(o["hp"], o["maxHp"])
			if p < lv: lv = p; low = o
		if low == null: continue
		var done: float = battle._damage._heal(low, heal_amt)
		var acc: float = float(stt.get("anchor_accum", 0.0)) + done
		while acc >= ANCHOR_ACC_PER_CHARGE:
			acc -= ANCHOR_ACC_PER_CHARGE
			stt["anchor_charges"] = int(stt.get("anchor_charges", 0)) + 1
		stt["anchor_accum"] = acc
		u["eq_state"]["p2eq_017"] = stt


const HOTSPRING_IV := 1.0    # 温泉蛋回血节拍(秒) —— 用户 2026-08-01「携带者每秒回复 5/7/10 生命值」
## 温泉蛋每秒回血 = 定额 + 百分比×最大生命 (用户 2026-08-31:
##   「温泉蛋的生命恢复改为每秒回复 2/5/10+0.3/0.8/1.2%最大生命值」, 原为纯定额 5/7/10)。
## ★★两个常量放【一处】—— `heal_ps` 有两个写入点(equip_stats_apply 正常路径 +
##   本文件 tick 里的兜底现算), 各写一份数就必然漂; 现在两处都引这里。
const HOTSPRING_FLAT := [2.0, 5.0, 10.0]        # 定额
const HOTSPRING_PCT := [0.003, 0.008, 0.012]    # ×最大生命

## 温泉蛋 p2eq_036: 携带者每秒回血 5/7/10(用户 2026-08-01 新效果)。
## ★只回【携带者自己】—— 用户同批的 11b「温泉蛋也是(排龟蛋和大师)」指的是它【孵满时的全队均摊护盾】,
##   不是这条回血(见 docs/plans/20260801-装备批次13条.md §4·C, 已按代码事实落实)。
## ★每秒回血【不】攒孵化进度: 孵化只吃"造成/承受伤害/敌我死亡", 让站桩回血也攒进度等于自己给自己充能。
func _tick_hotspring(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	if not u.get("alive", false): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_036": continue
		e["hotspring_t"] = float(e.get("hotspring_t", 0.0)) + delta
		if float(e["hotspring_t"]) < HOTSPRING_IV: continue
		e["hotspring_t"] = 0.0
		var stt: Dictionary = u["eq_state"].get("p2eq_036", {})
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var ps: float = float(stt.get("heal_ps", 0.0))
		if ps <= 0.0:
			# 缺省兜底: 老存档/合成单位没走 apply → 按星级现算, 免得这条效果静默不生效
			ps = HOTSPRING_FLAT[si]
		## ★百分比那一半【只能在这里算】—— 它跟着当前最大生命走(装备/羁绊会改 maxHp),
		##   而 `heal_ps` 是登场时算一次的定额。放进 heal_ps 会把它冻在开局那个血量上。
		ps += float(u.get("maxHp", 0.0)) * HOTSPRING_PCT[si]
		battle._damage._heal(u, ps)


## 靶向器 p2eq_055: 携带者【首次】累计造成 TRIGGER_DMG(400) 伤害 → 向最近 1/1/2 名敌人挂钩索炸弹。
## ★用现成的 `_st_dealt`(伤害统计面板的累计造成量, battle_damage.gd 两条路径都在记) 当计数器,
##   不另起一个自己的累加器 —— 多一个累加器就多一处会和面板对不上的地方, 且新累加器必须两条
##   伤害路径都挂钩(CLAUDE.md §3.3), 漏一条就变成"某些伤害不算数"。
func _tick_targeter(u: Dictionary, _delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	if not u.get("alive", false): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_055": continue
		# ★★"每件独立": 触发标记存在【装备条目 e】上, 不是 u["eq_state"]["p2eq_055"]。
		#   后者是按【装备 id】的槽 —— 带两件靶向器时两件共用一个标记, 第一件放完置 true,
		#   第二件永远被跳过 = 第二件完全不生效(探针实测: 带两件的挂弹数与带一件一样都是 1)。
		#   项目里多件装备一律"每件独立"(铁壁盾 e["ironwall_t"] / 激光 e["laser_t"] / 沉锚 e["anchor_t"])。
		if bool(e.get("hb_fired", false)): continue             # "首次" —— 每件一局一次
		if int(u.get("_st_dealt", 0)) < battle._hookbomb_sys.TRIGGER_DMG: continue
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var tg: Array = battle._hookbomb_sys._hb_targets(u, battle._hookbomb_sys.BOMB_COUNT[si])
		if tg.is_empty(): continue                              # 没有合法目标 → 不标 fired, 下帧再试
		e["hb_fired"] = true
		for o in tg:
			battle._hookbomb_sys._hb_attach(u, o, si)

func _tick_thunder(u: Dictionary, delta: float) -> void:
	## (延时队列的排空已移到 tick_delayed —— 那条无条件每帧调)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_025": continue
		e["thunder_t"] = float(e.get("thunder_t", 0.0)) + delta
		if float(e["thunder_t"]) < THUNDER_IV: continue
		e["thunder_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		## ★★2026-09-13: 道间错峰原来是 `tween_interval` —— tween 走**未钳制的真实 delta**,
		##   无头下推不动(CLAUDE.md §3.5) ⇒ ★2/★3 的第 2、3 道雷可能**根本不落**。
		##   改挂进游戏钟队列 `_bolt_q`。
		## 分派链: 这里排队 → `_drain_bolts()` → `_tick_thunder_bolt(u)`(它自己挑目标) → `_tick_thunder_hit`
		##          → 再排一项 → `_tick_thunder_hit(u, o)`【1×ATK 真实伤害】。
		## ★★注释里**不许出现选靶关键词**: `text_claim_audit` 把注释也当证据 ——
		##   我第一版在这里写了「随..机」两个字, 结果把选靶改成固定选第一个**审计照样绿**
		##   (反向验证当场抓到)。证据只能由**代码**提供。
		## ★写清这条链: `text_claim_audit` 跟调用图收证据, 中间隔着通用队列时
		##   名字不会出现在函数体里, 证据链会断(它当场把选靶那条报成对不上)。
		for d in range([1, 2, 3][si]):                # 道间错峰
			_bolt_q.append({"at": battle._t + float(d) * BOLT_GAP, "u": u,
				"kind": "bolt", "o": null})

# 029 冰封水母(布隆大招式): 每12秒→自身上盾→砸地→朝最近敌生成冰道(500x90)→命中魔法伤+击飞0.6s+冰封2.5s
## ★029 冰封水母的「每 12 秒」驱动 `_tick_ice_fissure` 已整体删除(2026-08-12):
##   法器的主动只能由法力条满触发(用户定的规则), 那个计时器是第二个触发口。
##   效果本体 `EquipSystem._eq_ice_fissure` 还在, 现在只由 fire_equip_effect 调。

func _tick_gear(u: Dictionary, delta: float) -> void:   # 黄铜齿轮035(用户2026-07-18改: 随时间铸币·每6秒左队携带者直接+1/2/3深海币+飘字·跟死亡无关·原"攒齿轮层战斗结束折币"改掉)
	if u.get("equips", []).is_empty(): return
	if str(u.get("side", "")) != "left": return   # 深海币=玩家侧meta货币, 只玩家(左队)携带者产币
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_035": continue
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_035", {})
		stt["gear_t"] = float(stt.get("gear_t", 0.0)) + delta
		if float(stt["gear_t"]) >= GEAR_IV:
			stt["gear_t"] = float(stt["gear_t"]) - GEAR_IV   # ★读常量不写死(原来是 6.0, 与 GEAR_IV 两份)
			var coins: int = [1, 2, 3][si]
			var gs = battle.get_node_or_null("/root/GameState")
			if gs != null and gs.get("meta_deepsea_coins") != null:
				gs.set("meta_deepsea_coins", int(gs.get("meta_deepsea_coins")) + coins)
			battle._vfx._float_text(u["pos"], "+%d💠" % coins, Color("#5fd0e0"))   # 可见反馈(用户: 之前无反馈以为没生效)
			battle._vfx.coin_pop(u, coins)   # 头顶旋转金币(用户2026-09-13: 「做一个头顶获得金币旋转的特效」)
			stt["coins_made"] = int(stt.get("coins_made", 0)) + coins   # 头像装备格徽章显示本局累计产币(用户2026-07-19)
		u["eq_state"]["p2eq_035"] = stt

func _tick_shell(u: Dictionary, delta: float) -> void:   # 守护贝壳p2eq_018: 每8秒自回(30/45/60+5/9/15%maxHP)生命(受治疗增幅); 每件独立(用户2026-07-02, 原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_018": continue
		e["shell_t"] = float(e.get("shell_t", 0.0)) + delta
		if float(e["shell_t"]) < SHELL_IV: continue
		e["shell_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		battle._damage._heal(u, [30, 45, 60][si] + u["maxHp"] * [0.05, 0.09, 0.15][si])
		battle._shell_sys._shell_guard_fx(u)   # 半壳合拢护罩演出(用户2026-07-19)

func _tick_anemone(u: Dictionary, delta: float) -> void:   # 海葵药膏p2eq_019: 每7秒奶自己+最低血友军(30/45/60+12/14/18%目标已损血)×海葵增幅; 累计200/180/150治疗+1海葵层(治疗&盾强度+8/9/10%/层); 每件独立(用户2026-07-02,原2.5s)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_019": continue
		e["anemone_t"] = float(e.get("anemone_t", 0.0)) + delta
		if float(e["anemone_t"]) < ANEMONE_IV: continue
		e["anemone_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get("p2eq_019", {})
		# 海葵层的+治疗/护盾强度已经在获得层时真的加进 u.heal_amp/shield_amp (见下), battle._damage._heal 会自己乘, 这里不能再乘一遍
		var h1: float = [30, 45, 60][si] + (u["maxHp"] - u["hp"]) * [0.12, 0.14, 0.18][si]
		var prov19: float = battle._damage._heal(u, h1)                     # 按【实际】回血计数(同017口径·用户2026-07-19)
		## ★★2026-09-12 用户看 019 的窗口后定的:「应该要身上冒绿光和绿粒子，但不要复用」。
		##   被否的是原来那圈「脚下淡绿地环 + 一个飘字」—— 治疗这个动作画面上读不出来。
		##   ⇒ 被治的那只身上冒一束绿光(加色, 从脚下升起裹住它) + 几粒圆药滴往上飘。
		##   素材是**新烤的**(heal-plume / heal-drop), 没复用 014 汲取那颗四芒星:
		##     抽取是「夺」⇒ 尖的正绿; 治疗是「给」⇒ 圆的薄荷青。形状与色相都拉开。
		##   ★范围**只有 019**: 我一度挂在 `battle_damage._heal_flush()`(全仓 80 个治疗点的
		##     中央收口), 被用户当场否 —— 「我只让你对019做」。别再往外推。
		battle._vfx.heal_burst(u)
		var low = battle._lowest_hp_pct_ally(u)                     # 文案是"生命百分比最低"
		if low != null and not is_same(low, u):              # is_same: 单位字典深比较有卡死风险(同053)
			var h2: float = [30, 45, 60][si] + (low["maxHp"] - low["hp"]) * [0.12, 0.14, 0.18][si]
			prov19 += battle._damage._heal(low, h2)
			battle._vfx.heal_burst(low)   # 被奶的友军身上同样冒 —— 「谁治了谁」要看得出来
		stt["anemone_heal"] = float(stt.get("anemone_heal", 0.0)) + prov19
		var thr19: float = [200.0, 180.0, 150.0][si]
		while float(stt["anemone_heal"]) >= thr19:
			stt["anemone_heal"] = float(stt["anemone_heal"]) - thr19
			stt["anemone_layers"] = int(stt.get("anemone_layers", 0)) + 1
			var inc19: float = [0.08, 0.09, 0.10][si]
			u["heal_amp"] = float(u.get("heal_amp", 0.0)) + inc19       # 海葵层原来只放大019自己的回血, 文案说的"治疗与护盾强度"根本没生效 → 真的加进全局(用户2026-07-19)
			u["shield_amp"] = float(u.get("shield_amp", 0.0)) + inc19   # 一局内累计不封顶, 单位每场重建 eq_state/heal_amp → 天然重置
			battle._skill_ring(u["pos"], Color(0.55, 0.9, 0.7, 0.5), 44.0)
		u["eq_state"]["p2eq_019"] = stt

func _tick_dumbbell(u: Dictionary, delta: float) -> void:   # 哑铃p2eq_020: 每8秒一套(原地锻炼锁攻锁充能→+锻炼层→蓄力掷哑铃击退); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_020": continue
		e["dumbbell_t"] = float(e.get("dumbbell_t", 0.0)) + delta
		if float(e["dumbbell_t"]) < DUMBBELL_IV: continue   # 每10秒→每8秒(用户2026-07-19)
		e["dumbbell_t"] = 0.0
		if u.get("_slam", false): continue   # 正在别的channel中→跳过本次
		battle._equip_sys._eq_dumbbell_routine(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

# 027 电棍: 每3s就绪→下次普攻消耗1层(附魔法伤+眩晕); 就绪时身上冒电光
func _tick_baton(u: Dictionary, delta: float) -> void:
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_027": continue
		var bst: Dictionary = u["eq_state"].get("p2eq_027", {})
		if int(bst.get("baton_charges", 0)) <= 0:
			bst["baton_ready"] = false; u["eq_state"]["p2eq_027"] = bst; continue
		if not bst.get("baton_ready", false):
			bst["baton_cd"] = float(bst.get("baton_cd", 0.0)) + delta
			if float(bst["baton_cd"]) >= 3.0:
				bst["baton_ready"] = true
		else:
			bst["baton_spark_t"] = float(bst.get("baton_spark_t", 0.0)) + delta
			if float(bst["baton_spark_t"]) >= 0.16:
				bst["baton_spark_t"] = 0.0
				battle._vfx.baton_spark(u)
		u["eq_state"]["p2eq_027"] = bst

func _tick_barnacle(u: Dictionary, delta: float) -> void:   # 守护贝母p2eq_021: 持续绿色绑定线连全队最高攻友军; 每5秒重连并为自己+该友军 +10龟能+10%攻速(叠加/本场/每场重置); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_021": continue
		var stt: Dictionary = u["eq_state"].get("p2eq_021", {})
		e["barnacle_t"] = float(e.get("barnacle_t", 0.0)) + delta
		if stt.get("link_target", null) == null or float(e["barnacle_t"]) >= BARNACLE_IV:   # 首次立即连 + 每5秒重连+给buff
			if float(e["barnacle_t"]) >= BARNACLE_IV: e["barnacle_t"] = 0.0
			var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
			var prev = stt.get("link_target", null)   # 重连前清上个连接对象的伤害转移标记
			if prev is Dictionary: prev.erase("dmg_redirect_to")
			var best = null; var ba = -1.0
			for o in battle._targeting._allies_of(u):
				if is_same(o, u): continue   # is_same: 单位字典深比较有卡死风险(同053)
				if float(o["atk"]) > ba: ba = float(o["atk"]); best = o
			stt["link_target"] = best
			u["eq_state"]["p2eq_021"] = stt
			var benef: Array = [u]
			if best != null: benef.append(best)
			for o in benef:
				if battle._has_energy_system(o): battle._equip_sys._eq_grant_energy(o, BARNACLE_ENERGY)   # +10龟能(减冷却)
				o["aspd_perm"] = float(o.get("aspd_perm", 1.0)) + BARNACLE_ASPD   # +10%攻速(永久本场,叠加)
				battle._skill_ring(o["pos"], Color(0.55, 1.0, 0.78, 0.5), 44.0)
			if best != null:   # 连接友军: 盾 + 伤害转移(25/40/60%受伤转给携带者); 不净化(用户)
				battle._damage._grant_shield(best, [60.0, 110.0, 180.0][si], BattleDamage.COMMON_SHIELD_SEC)   # 用户2026-07-19: 40/60/90→60/110/180; 通用护盾=4秒
				best["dmg_redirect_to"] = {"carrier": u, "pct": [0.25, 0.40, 0.60][si], "until": battle._t + 5.5}
		battle._update_barnacle_line(u, stt.get("link_target", null))   # 每帧: 持续绿色绑定线(跟随移动/能量脉动)
		break   # 只处理一件(共享绑定线)

func _tick_jelly(u: Dictionary, delta: float) -> void:   # 海藻p2eq_012: 每4s自护盾(用户2026-07-02, 原走2.5s周期); 每件独立计时
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_012": continue
		e["jelly_t"] = float(e.get("jelly_t", 0.0)) + delta
		if float(e["jelly_t"]) < JELLY_IV: continue
		e["jelly_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		battle._vfx.kelp_burst(u)   # ★来源标识: 脚下长一丛海藻(通用六棱护罩由 _grant_shield 另罩一层)
		battle._damage._grant_shield(u, [40.0, 60.0, 90.0][si] + u["maxHp"] * JELLY_MAXHP_PCT, BattleDamage.COMMON_SHIELD_SEC)   # 用户2026-07-19: 30/40/55 → 40/60/90 + 4%最大生命; 通用护盾=4秒(恰好接上下一轮 JELLY_IV=4s·不断层也不无限叠)

func _tick_rustblade(u: Dictionary, delta: float) -> void:   # 木制长剑p2eq_001: 每3s就绪, 射程2000(全场)内最近敌即甩飞斩剑气; 每件独立(多件各自触发)
	if u.get("equips", []).is_empty(): return
	var t = null; var got = false; var rng: float = RUST_RANGE   # 全场覆盖(用户2026-07-19: 近战→远程「裂空飞斩」)
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_001": continue
		e["rust_t"] = float(e.get("rust_t", 0.0)) + delta   # 计时存装备条目→每副本独立就绪
		if float(e["rust_t"]) < RUST_IV: continue           # 该件未就绪(每3s就绪一次)
		if not got:                                          # 目标懒求(多件共用同一最近敌)
			t = battle._targeting._nearest_enemy(u); got = true
		if t == null or (t["pos"] - u["pos"]).length() > rng: continue   # 射程内无敌→保持就绪等待
		e["rust_t"] = 0.0
		var si: int = battle._equip_sys._eq_si(int(e.get("star", 1)))
		var dmg01: int = battle._resolve_dmg(u, u["atk"] * [0.6, 0.75, 1.0][si] + [40.0, 60.0, 100.0][si] * u["crit"], t, false)
		battle._ballistics.fire_flyslash(u, t, dmg01, Color("#ffd27a"))   # 剑气飞到目标才结算伤(命中判定在_projectiles arrival)


func _tick_coral(u: Dictionary, delta: float) -> void:   # 双穿珊瑚刺p2eq_008: 每9秒对最远敌射珊瑚尖刺(用户2026-07-19: 6→9); 命中才结算; 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_008": continue
		e["coral_t"] = float(e.get("coral_t", 0.0)) + delta
		if float(e["coral_t"]) < CORAL_IV: continue
		var far = null; var fd = -1.0
		for o in battle._targeting._pick_enemies_of(u):   # ★单体定向(挑最远一个)必须走 battle._targeting._pick_enemies_of: 排除训龟大师(场外监视者·永远最远)+不可选中; 见 §PICK-TARGET 铁律。原用 battle._targeting._enemies_of → 珊瑚刺永远锁大师(用户2026-07-24)
			var dd2: float = (o["pos"] - u["pos"]).length_squared()
			if dd2 > fd: fd = dd2; far = o
		if far == null: continue
		e["coral_t"] = 0.0
		battle._ballistics._fire_coral_spike(u, far, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_broadsword(u: Dictionary, delta: float) -> void:   # 锈蚀阔剑p2eq_007: 每6秒触发(用户); 每件独立
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_007": continue
		e["bsw_t"] = float(e.get("bsw_t", 0.0)) + delta
		if float(e["bsw_t"]) < BROADSWORD_IV: continue
		if battle._targeting._nearest_enemy(u) == null: continue
		e["bsw_t"] = 0.0
		battle._equip_sys._eq_broadsword(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_sword_storm(u: Dictionary, delta: float) -> void:   # 千刃风暴p2eq_006: 每7秒触发; 每件独立计时
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_006": continue
		e["storm_t"] = float(e.get("storm_t", 0.0)) + delta
		if float(e["storm_t"]) < SWORD_STORM_IV: continue
		if battle._targeting._nearest_enemy(u) == null: continue
		e["storm_t"] = 0.0
		battle._equip_sys._eq_sword_storm(u, battle._equip_sys._eq_si(int(e.get("star", 1))))

func _tick_laser(u: Dictionary, delta: float) -> void:   # 激光长刃p2eq_010: 独立计时器(按携带者攻速)每次扇形斩(用户)
	if u.get("equips", []).is_empty(): return
	for e in u["equips"]:
		if str(e["id"]) != "p2eq_010": continue
		e["laser_t"] = float(e.get("laser_t", 0.0)) + delta
		if float(e["laser_t"]) < maxf(0.3, float(u.get("atk_interval", 1.0))): continue
		var t = battle._targeting._nearest_enemy(u)
		if t == null: continue
		e["laser_t"] = 0.0
		battle._equip_sys._eq_laser_sweep(u, t, battle._equip_sys._eq_si(int(e.get("star", 1))))

# ============================================================================
#  温泉蛋 036 的孵化进度与临时等级 —— 2026-08-01 从 RealtimeBattle3DScene 搬来。
#  搬家理由: arch_budget 焊死了上帝文件的行数(欠债只减不增), 而这两个函数本就是【装备逻辑】,
#  住在主场景里只是历史遗留。调用方改成 battle._equip_tick_sys._egg_*。
# ============================================================================
## 跨路重放温泉蛋已获得的临时等级(用户2026-08-01「重置问题同竹枝弓箭」)。
## 新单位的属性是干净的基线, 所以直接拿它当 ref 连加 n 级 —— 与 _egg_add_progress 里逐级加同一套公式。
## ★不复用 _egg_add_progress: 那条要吃"孵化进度"且会重复触发满级护盾(incub_given 虽拦着, 但依赖它就脆)。
func _egg_replay_levels(u: Dictionary, n: int) -> void:
	if n <= 0 or not u.get("alive", false):
		return
	var stt: Dictionary = u["eq_state"].get("p2eq_036", {})
	if not stt.has("ref_atk"):
		stt["ref_atk"] = u["base_atk"]; stt["ref_def"] = u["base_def"]; stt["ref_mr"] = u["base_mr"]
		stt["ref_hp"] = u["maxHp"]; stt["ref_iv"] = float(u.get("atk_interval", 1.0))
	u["base_atk"] += float(stt["ref_atk"]) * EGG_LV_GROWTH * float(n)
	u["base_def"] += float(stt["ref_def"]) * EGG_LV_GROWTH * float(n)
	u["base_mr"] += float(stt["ref_mr"]) * EGG_LV_GROWTH * float(n)
	var hpg: float = float(stt["ref_hp"]) * EGG_LV_GROWTH * float(n)   # ★原来写死 0.05
	u["maxHp"] += hpg; u["hp"] += hpg
	u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + EGG_LV_ASPD * float(n)))
	stt["egg_levels"] = n
	u["eq_state"]["p2eq_036"] = stt
	battle._recalc_stats(u)


func _egg_add_progress(u: Dictionary, amt: float) -> void:   # 温泉蛋(036): 累积孵化进度→每100+1临时等级(线性+5%基础+攻速2%/级,同统领,上限3/4/5随星级)→孵满全队均摊护盾一次
	if amt <= 0.0 or not u.get("has_egg", false) or not u.get("alive", false): return
	var stt: Dictionary = u["eq_state"].get("p2eq_036", {})
	# 等级上限随星级 3/4/5(用户2026-08-01); 缺省 3 = 老存档/未走 apply 的合成单位仍按原行为
	var cap: int = int(stt.get("egg_cap", 3))
	stt["incub"] = float(stt.get("incub", 0.0)) + amt
	while float(stt["incub"]) >= EGG_FULL and int(stt.get("egg_levels", 0)) < cap:
		stt["incub"] = float(stt["incub"]) - EGG_FULL
		if not stt.has("ref_atk"):   # 首次升级锁基准 → 线性+5%/级(同统领 1+0.05×级, 非复利)
			stt["ref_atk"] = u["base_atk"]; stt["ref_def"] = u["base_def"]; stt["ref_mr"] = u["base_mr"]
			stt["ref_hp"] = u["maxHp"]; stt["ref_iv"] = float(u.get("atk_interval", 1.0))
		stt["egg_levels"] = int(stt.get("egg_levels", 0)) + 1
		var el: int = int(stt["egg_levels"])
		u["base_atk"] += float(stt["ref_atk"]) * EGG_LV_GROWTH          # 线性+5%基础属性/级
		u["base_def"] += float(stt["ref_def"]) * EGG_LV_GROWTH
		u["base_mr"] += float(stt["ref_mr"]) * EGG_LV_GROWTH
		var hpg: float = float(stt["ref_hp"]) * EGG_LV_GROWTH; u["maxHp"] += hpg; u["hp"] += hpg   # ★同上, 原来写死 0.05
		u["atk_interval"] = maxf(0.1, float(stt["ref_iv"]) / (1.0 + EGG_LV_ASPD * float(el)))   # 攻速/级(同统领)
		battle._recalc_stats(u)
		battle._egg_level_up_vfx(u, int(u.get("level", 1)) + el)      # 升级特效(金光柱+LV UP)
		if int(stt["egg_levels"]) >= cap and not bool(stt.get("incub_given", false)):
			stt["incub_given"] = true
			var allies: Array = battle._targeting._allies_share_pool(u)   # ★均分排除大师+龟蛋·用户2026-07-23 点4 / 2026-08-01
			var per: float = float(stt.get("incub_shield", 300.0)) / maxf(1.0, float(allies.size()))
			for o in allies: battle._damage._grant_shield(o, per)
			battle._particle_burst(u["pos"])
	if int(stt.get("egg_levels", 0)) >= cap: stt["incub"] = minf(float(stt["incub"]), EGG_FULL)   # ★原来写死 100.0
	u["eq_state"]["p2eq_036"] = stt

## ── 025 雷鸣贝壳: 从主文件搬来(CLAUDE.md §5「装备效果去 scripts/systems/equip/」) ──
## ★两层延时原来都是 tween; 现在都挂 `_bolt_q`, 由 `_drain_bolts()` 按 `battle._t` 结算。
func _tick_thunder_bolt(u: Dictionary) -> void:
	if not u.get("alive", false): return
	var es = battle._targeting._pick_enemies_of(u)   # battle 无类型 ⇒ := 推不出来
	if es.is_empty(): return
	var o = es[battle._battle_rng.randi() % es.size()]
	battle._lightning_sys._lightning_strike(o["pos"], Color("#8fd4ff"), 4.6)   # 大雷(中心≈2.2=飘字高度)
	## ★伤害落在闪电动画中段 —— 同样改游戏钟队列, 不用 tween。
	_bolt_q.append({"at": battle._t + BOLT_HIT_DELAY, "u": u,
		"kind": "hit", "o": o})

func _tick_thunder_hit(u: Dictionary, o: Dictionary) -> void:
	if not (u.get("alive", false) and o.get("alive", false)): return
	battle._damage._apply_damage_from(u, o, int(u["atk"]), Color("#cfefff"), 0.0, true, true)   # 1×ATK真实伤害(白字,飘在2.2=雷中间)


## 排队到点的雷 —— 由 `_tick_thunder` 每帧调(它本来就每帧被调)。
func _drain_bolts() -> void:
	if _bolt_q.is_empty():
		return
	var i: int = _bolt_q.size() - 1
	while i >= 0:
		var it: Dictionary = _bolt_q[i]
		if battle._t < float(it["at"]):
			i -= 1; continue
		_bolt_q.remove_at(i)
		## 通用项: 直接存了一个 Callable
		if it.has("fn"):
			var fn: Callable = it["fn"]
			if fn.is_valid():
				fn.call()
			i -= 1
			continue
		if str(it["kind"]) == "bolt":
			_tick_thunder_bolt(it["u"])
		else:
			_tick_thunder_hit(it["u"], it["o"])
		i -= 1


## ★共享原语: 延时 `delay` 秒(**游戏钟**)后调 `fn` —— 代替 `tween_interval`+`tween_callback`。
## 排进来的项由 `_drain_bolts()` 每帧按 `battle._t` 结算。
func schedule(delay: float, fn: Callable) -> void:
	_bolt_q.append({"at": battle._t + maxf(0.0, delay), "fn": fn})


## ★★共享延时队列的【唯一入口】—— 由主场景 `_sim_step` 的 tick 群**无条件**每帧调。
##   原来 drain 挂在 `_tick_thunder` 里, 而那整块被 `if not u.equips.is_empty()` 门住
##   ⇒ **没人带装备就永远不排空**(026 门禁当场抓到: 队列剩 6 项)。
##   一个队列一个入口, 谁排进来都一定会被结算。
func tick_delayed(_dt: float) -> void:
	_drain_bolts()
	_tick_bear_waves(_dt)   # 034 大熊冲击波: 波前推进+命中结算(同一条游戏钟, 不再走 process delta)
	_tick_pulls(_dt)        # 击飞态平滑拉回(同上, 原来也挂在 process delta 上)

## 大熊熊掌挥击接触那一瞬: 此刻才结算伤害 + 跳数字 + 金爪痕。
## ★★2026-09-13 从主文件搬过来, 同时把延时从 tween 换成共享原语 `schedule`:
##   原来是 `_reg_tween().tween_interval(0.315)` + `tween_callback` —— tween 走**未钳制的
##   真实 delta, 无头下推不动**(CLAUDE.md §3.5) ⇒ **大熊的普攻一下都不结算**。
##   而大熊是 034 的主要输出(★3 攻击力 2000), 等于这件 5 费装备召出来的东西在打空气。
##   与 024/025/026/028/029 同一条病, 走同一个原语。命中时刻一个数没动。
## ★函数名带 `_tick_` 前缀: `text_claim_audit` 靠前缀才跟得到函数体(026 那轮的教训)。
func _tick_bear_paw_hit(u: Dictionary, tgt) -> void:
	if not u.get("alive", false) or tgt == null or not tgt.get("alive", false):
		return
	battle._do_basic(u, tgt, {"phys": 1.0, "hits": 1})  # 熊掌: 1×ATK 物理
	if u.get("melee", false):
		battle._on_basic_hit(u, tgt)
	battle._bear_claw_fx(tgt["pos"])                    # 金爪三痕+尘


# ════════════════════════════════════════════════════════════════════════════
#  034 大熊【冲击波】—— 波前推进 + 命中结算, 全程走【游戏钟】
# ════════════════════════════════════════════════════════════════════════════
## ★★2026-09-13 重做(用户:「这个大熊冲击波的特效不好, 你得重做」)。
##   同时收掉一条早就登记在案的缺陷: 原来整条波(前摇/砸地/推进/**命中结算**)都挂在
##   `await get_tree().process_frame` + `get_process_delta_time()` 上 —— 那是**未钳制的
##   真实帧 delta**, 与战斗钟 `_t`(钳制到 0.1/帧)是两条钟。两条钟必然丢事件:
##   慢机器/无头下波已经推完了而游戏时间才走了一点点, 命中窗口整个错位。
##   ⇒ 推进与结算搬到本函数, 由 `tick_delayed` 每个 sim step 无条件调一次;
##     大熊自己的起身/砸地姿势留在主场景(纯观感, 那条留 tween/process 是对的)。
const BEAR_WAVE_SPEED := 500.0       # 波速(码/秒) —— 用户当初点名"慢点", 数值原样不动
const BEAR_WAVE_HALF := 85.0         # 判定半宽(码), 也是破土铺开的半宽
const BEAR_WAVE_SEG := 46.0          # 每推进多少码, 在波前那一线上点一排破土
const BEAR_WAVE_PER_SEG := 3         # 每一排点几处(横跨 ±85 码)

var _bear_waves: Array = []


## 起一条波。`origin/dir` 由主场景砸地那一刻给出; 伤害也在那时算好(避免中途 ATK 变了)。
func bear_wave_start(src: Dictionary, origin: Vector2, dir: Vector2, dmg: int) -> void:
	_bear_waves.append({
		"src": src, "origin": origin, "dir": dir, "perp": dir.orthogonal(), "dmg": dmg,
		"traveled": 0.0, "seg": 0.0, "n_seg": 0, "hit": [],
	})


## 每个 sim step 推一格。★dt 是**钳制后**的战斗 delta, 与伤害判定用的是同一条钟。
## ★★演出与判定是**同一个波前**: 破土点在 `origin + dir*traveled` 那一线上冒,
##   伤害也判在 `proj <= traveled`。不是"演出一套、结算另一套"(那是 026 那条病)。
func _tick_bear_waves(dt: float) -> void:
	if _bear_waves.is_empty():
		return
	for i in range(_bear_waves.size() - 1, -1, -1):
		var w: Dictionary = _bear_waves[i]
		var origin: Vector2 = w["origin"]
		var dir: Vector2 = w["dir"]
		var perp: Vector2 = w["perp"]
		var src: Dictionary = w["src"]
		w["traveled"] = float(w["traveled"]) + BEAR_WAVE_SPEED * dt
		var trav: float = float(w["traveled"])
		## ① 演出: 波前每走过 BEAR_WAVE_SEG 码, 在那一线上点一排破土(一段一段地突起)
		while float(w["seg"]) + BEAR_WAVE_SEG <= minf(trav, BEAR_WAVE_RANGE):
			w["seg"] = float(w["seg"]) + BEAR_WAVE_SEG
			var n: int = int(w["n_seg"]); w["n_seg"] = n + 1
			## ★★演出的**外缘**要正好落在判定边上, 不能超出去(用户 2026-09-13 点名"尤其是宽度")。
			##   探针实测过: 判定半宽 85 码(偏 84 挨打 / 偏 88 没事), 而破土中心原来铺到 ±103,
			##   加上精灵自己半宽 39 码 ⇒ 视觉外缘 ±142 码 = **比判定宽 67%**。
			##   ⇒ 中心只铺到 `半宽 − 精灵半宽`, 抖动也钳在里面; 纵向只往后抖不往前抖。
			var inset: float = battle._vfx.QUAKE_ERUPT_YARDS * 0.5
			var span: float = maxf(0.0, BEAR_WAVE_HALF - inset)
			for k in range(BEAR_WAVE_PER_SEG):
				var off: float = lerpf(-span, span, float(k) / float(BEAR_WAVE_PER_SEG - 1))
				off = clampf(off + (6.0 if n % 2 else -6.0), -span, span)   # 两排错开半格, 但不许溢出
				var lead: float = float((n + k) % 3) * -7.0                  # 只往后抖: 前缘不许越过判定
				battle._vfx.bear_quake_erupt(origin + dir * (float(w["seg"]) + lead) + perp * off)
		## ② 结算: 波前扫到谁就结算谁(每个敌人只一次)
		for o in battle._targeting._enemies_of(src):
			if battle._arr_has_unit(w["hit"], o) or not o.get("alive", false):
				continue
			var proj: float = ((o["pos"] as Vector2) - origin).dot(dir)
			if proj < -40.0 or proj > trav + 30.0 or proj > BEAR_WAVE_RANGE + 30.0:
				continue
			if not battle._on_line(origin, dir, o["pos"], BEAR_WAVE_HALF):
				continue
			(w["hit"] as Array).append(o)
			battle._damage._apply_damage_from(src, o, int(w["dmg"]), Color("#ffd27a"), 0.0, false, true)
			battle._damage._knockback(src, o, 0.0, 1.5, 0.0)     # 击飞 ~0.8s(vy×1.5), 横推交给 pull_airborne
			pull_airborne(o, origin, BEAR_WAVE_PULL, 0.45)
			battle._vfx._hit_spark(o)
			## ★命中点**不**再另炸一处破土: 挨打的人可能正站在判定边上, 而一处破土自带
			##   ±39 码的精灵半宽 ⇒ 那一下会把视觉外缘推到 123 码, 又比判定宽了。
			##   命中反馈交给 `_hit_spark` + 伤害飘字, 破土只用来画【波本身】。
		## ③ 大熊从砸地的下沉姿势起身复位(0.3 秒) —— 也走游戏钟
		if src.get("alive", false):
			src["_bear_voff"] = Vector3(0.0, lerpf(-0.22, 0.0,
				clampf(trav / (BEAR_WAVE_SPEED * 0.3), 0.0, 1.0)), 0.0)
		if trav < BEAR_WAVE_RANGE:
			continue
		src["_slam_manual"] = false
		src["no_move"] = false
		src["_bear_voff"] = Vector3.ZERO
		_bear_waves.remove_at(i)


## 击飞态平滑拉向 `origin` —— 走【游戏钟】。
## ★★2026-09-13 从主场景 `_pull_airborne` 搬过来。原来那份是
##   `await get_tree().process_frame` + `get_process_delta_time()` 的协程, 而它的**退出条件**
##   `o["airborne"]` 是**游戏钟**上过期的 ⇒ 又是两条钟: sim 推得快一点, airborne 先过期,
##   协程醒过来时条件已经不成立 ⇒ **一格都没拉**(034 新补的第 ⑥ 节当场抓到: x 700 → 700)。
##   唯一调用者就是大熊冲击波, 所以整只搬走而不是在原地补丁。
var _pulls: Array = []


func pull_airborne(o: Dictionary, origin: Vector2, dist: float, dur: float) -> void:
	if not o.get("alive", false):
		return
	var to_o: Vector2 = origin - (o["pos"] as Vector2)
	var d0: float = to_o.length()
	if d0 < 1.0:
		return
	var pull: float = minf(dist, maxf(0.0, d0 - 24.0))   # 别拉进熊身(留 24px)
	if pull <= 0.5:
		return
	var start: Vector2 = o["pos"]
	_pulls.append({"u": o, "start": start, "target": start + (to_o / d0) * pull,
				   "t": 0.0, "dur": maxf(0.01, dur)})


func _tick_pulls(dt: float) -> void:
	if _pulls.is_empty():
		return
	for i in range(_pulls.size() - 1, -1, -1):
		var q: Dictionary = _pulls[i]
		var o: Dictionary = q["u"]
		q["t"] = float(q["t"]) + dt
		var k: float = clampf(float(q["t"]) / float(q["dur"]), 0.0, 1.0)
		if not o.get("alive", false) or not bool(o.get("airborne", false)) or k >= 1.0:
			if o.get("alive", false) and bool(o.get("airborne", false)):
				o["pos"] = q["target"]
			_pulls.remove_at(i)
			continue
		o["pos"] = (q["start"] as Vector2).lerp(q["target"] as Vector2, 1.0 - (1.0 - k) * (1.0 - k))
