class_name EqFoodBatch
extends RefCounted
## eq_food_batch.gd — 食物类新装备【4 件】效果本体(2026-08-05 用户逐件重做·定稿)
##   069 珊瑚糖糕 · 070 压舱咸鱼砖 · 071 炼乳罐 · 072 铁皮蛋糕盒
##
## 规格来源: docs/plans/20260805-装备逐件重做.md **§0.5 已定稿**(用户逐件亲手写并拍板)。
## 接口/分工: docs/plans/20260805-实装契约.md。演出层在 scripts/scenes/battle/food_eq_vfx.gd。
##
## ══════════════════════════════════════════════════════════════════════
##  ★这一批把三件旧效果整条替换掉了(不是叠加) —— 记一笔免得以为漏删:
##    · 069 旧「每 2.5 秒回已损失生命」(_eq_coral_cake)      → 删, 换成三块糖糕
##    · 070 旧「每 2.5 秒永久 +最大生命」(_eq_ration_brick)  → 删, 换成 on-hit + 灰条
##    · 071 旧「受到治疗分给最低血友军」(_kelp_share)         → 删写入, 换成奶油护盾
##    · 072 旧「开战送血 + 全队回已损」(_apply_feast_hp/_eq_feast_pulse) → 删, 换成变身
##  三件的旧【周期节拍登记】也一并从 EQ_IV_BATCH1 里摘掉了。
## ══════════════════════════════════════════════════════════════════════
##
## ── 本文件用到的既有机制(契约 §4「必须复用, 不许另造」) ──────────────
##   · 特殊余额(灰条/奶油盾/终极盾) → `battle._spec`(SpecialBalance), **衰减与吸收不自己实现**
##   · 护盾 `battle._damage._grant_shield` · 治疗 `_heal` · 属性重算 `battle._recalc_stats`
##   · 龟能 `battle._equip_sys._eq_grant_energy`(**没有 u["energy"] 这个字段**)
##   · 嘲讽 `battle._taunt(by, targets, sec)` · 射程 flat `range_add` · 攻速 `aspd_perm`
##
## ── 地雷对照(CLAUDE.md) ─────────────────────────────────────────────
##   §3.1 装备 hp 数值已是最终值, 一处都没乘 HP_MULT
##   §3.2 单位字典不做 key、比较用 `is_same`、存在判断用 `_arr_has_unit`
##   §3.3 两条伤害路径各自扣盾扣血 —— 本文件不改伤害流程, 只发伤害(都走 from_equip=true)
##   §3.4 `_t` 跨路累加永不重置 ⇒ 本批**一处都没有"本路第 N 秒"型计时**:
##        069 的 8 秒攻速窗是【绝对到期时刻】(`_t + 8`, 换路 eq_state 重建 ⇒ 自然作废),
##        072 的法阵周期是【逐帧累加的相对计时】。所以不需要自存 t0, 也就没有那个坑。
##   §3.5 数值不依赖演出 tween: 每个效果都有【同步入口 + 同步证据字段】, 门禁直接调

const KEY_GREY := "p2eq_070_grey"      ## 070 灰色血条(SpecialBalance 的 key)
const KEY_CREAM := "p2eq_071_cream"    ## 071 奶油护盾
const KEY_ULT := "p2eq_072_ult"        ## 072 终极护盾
## 072 【化身蛋糕礼盒】的形态立绘(本件专用新素材, 不复用任何现有图)。
## 铁皮箱体 + 铆钉护角 + 丝带蝴蝶结 —— 要读得出"能挨打的铁盒子"而不是"一块蛋糕"。
const BOX_FORM_TEX := "res://assets/sprites/vfx/eq072-cake-box.png"

var battle
var _eq                                ## EquipSystem(拿 _eq_si / _eq_grant_energy)
var _vfx: FoodEqVfx


func _init(b, eq) -> void:
	battle = b
	_eq = eq
	_vfx = FoodEqVfx.new(b)


func _si(star: int) -> int:
	return clampi(star, 1, 3) - 1


# ══════════════════════════════════════════════════════════════════
#  §每帧总入口 —— 由 EquipSystem._eq_tick 的常驻字段守卫 `_food_eq` 调进来
#    ★守卫是常驻字段而不是遍历 equips: 不带这四件的单位在这条热路径上
#      只多一次 dict.get(同 084 血牙巨剑 `_fang_pct` 的既有做法)。
# ══════════════════════════════════════════════════════════════════

var _vfx_fr: int = -1   ## 演出层是全局的, 而本函数是【每单位】调 → 按帧号去重(同 _sig_tick_fr)


func tick_unit(u: Dictionary, delta: float) -> void:
	var fr: int = Engine.get_process_frames()
	if fr != _vfx_fr:
		_vfx_fr = fr
		_vfx.tick(delta)
	if not u.get("alive", false):
		return
	for e in u.get("equips", []):
		var iid: String = str(e["id"])
		var si: int = _si(int(e.get("star", 1)))
		var stt: Dictionary = u["eq_state"].get(iid, {})
		match iid:
			"p2eq_069": _cake_tick(u, si, stt, delta)
			"p2eq_070": _brick_tick(u, si, stt, delta)
			"p2eq_071": _cream_tick(u, si, stt, delta)
			"p2eq_072": _box_tick(u, si, stt, delta)
		u["eq_state"][iid] = stt


# ══════════════════════════════════════════════════════════════════
#  §069 珊瑚糖糕(食物 · 3 费)
#
#  携带者带 3 块糖糕, 生命【首次】低于 80/55/30% 时各吃一块(每路重置):
#    ① +200/400/600 最大生命 + 30 秒内每秒回 0.6/0.8/1% 最大生命
#    ② +5% 生命偷取(固定值·不随星级) + 10/21/40 攻击力
#    ③ +150/250/400 护盾 + 50 龟能 + 8 秒内 +40/60/80% 攻速
#       + 20 秒内每秒回 1.3/1.6/2% 最大生命
#
#  ★用户 2026-08-05 追加的两条限制, 别漏:
#    · 属性加成【本路永久】(换路重置), 但第三块的攻速**只持续 8 秒**
#      —— 40/60/80% 是全表最高值的 2.67 倍, 常驻会失控, 所以它是"反打窗口"不是常驻。
#    · 两个回血 buff 可以并存(掉血够快会一口气吃完) ⇒ **两条独立的 HoT 通道**,
#      不能用 `_eq_start_hot`(那个"两件同时触发取总量更大的一段", 会把叠加吃掉)。
# ══════════════════════════════════════════════════════════════════

## 三道阈值线(跌破即吃)。★写成三元数组供 tooltip_number_audit 对账文案里的 "80/55/30%"。
const CAKE_LINES := [0.80, 0.55, 0.30]
## 三块糖糕的其余固定值(按星级变的那些是数组, 见下面各分支)。
const CAKE_COUNT := 3           # 带几块(= CAKE_LINES 的长度)
const CAKE_HOT1_SEC := 30.0     # 一号糕的持续回复(秒)
const CAKE_LIFESTEAL := 0.05    # 二号糕的生命偷取(固定值·本路永久)
const CAKE_ENERGY := 50.0       # 三号糕立得龟能
const CAKE_ASPD_SEC := 8.0      # 三号糕的攻速加成只持续这么久(其余属性本路永久)
const CAKE_HOT3_SEC := 20.0     # 三号糕的持续回复(秒)

## ⚠⚠ 诚实记录 —— 这里【没有】用契约 §3 说的那套共用阈值线基建, 说清楚原因与迁移方式:
##   · 我动手实装 069 时, 契约里写的 `battle._equip_sys.hp_line(...)` **还不存在**
##     (`grep -n "func hp_line"` 零命中), 所以三道线是在本文件每帧 tick 里自己判的 ——
##     就是下面 `_cake_tick` 里 `while eaten < 3 and frac < CAKE_LINES[eaten]` 那三行。
##   · 后来主会话把它落地成了 `HpLines`(`scripts/systems/equip/hp_lines.gd`, 挂点 `battle._hpl`,
##     接在 battle_damage 的血量阈值处)。**本件没有迁过去**, 因为迁移要连门禁的驱动方式一起改
##     (现在的 8 条断言是直接改 hp 再 tick, 迁过去要改成走伤害路径), 收尾阶段不做这种改动。
##   · 两者语义等价: ①每块只吃一次 ②"首次" = 每路一次(`eq_state` 换路整体重建 ⇒ 计数归零)
##     ③一次掉穿多条线会按顺序一口气全触发(while 循环 / HpLines 的高到低遍历)。
##   · **一处差异**(诚实列出): 本实现是每帧看血量比例, 所以"最大生命被顶高导致比例跌破"
##     也会触发; HpLines 只在伤害事件后判, 那种情况不触发。对 069 来说前者更贴文案
##     (它自己第一块就会顶高最大生命), 但这是差异不是等价。
##   ★真要迁: 把那三行换成开局注册三条 `battle._hpl.add(u, "p2eq_069_l%d", CAKE_LINES[i], cb)`,
##     回调里仍然 `stt["eaten"] += 1` 并调 `_cake_eat` —— **不要两套并存**。


func _cake_tick(u: Dictionary, si: int, stt: Dictionary, delta: float) -> void:
	# ── 首帧: 头顶挂三块糕(剩几块画几块) ──
	if not stt.has("eaten"):
		stt["eaten"] = 0
		stt["orbit"] = _vfx.cake_orbit_make(u, 3)
	# ── 阈值判定: 每路一次、每块一次。★eq_state 换路重建 ⇒ "首次"天然是"每路首次" ──
	# ★★`frac` 是【进循环前的快照】, 循环里【故意不重算】——
	#   第一块会 +200/400/600 最大生命, 重算的话血量比例立刻被顶回去,
	#   跌到 20% 也只吃得到前两块, 与用户写的"掉血够快会一口气吃完三块"相反。
	#   共用基建 HpLines 的口径也是这一条(它的注释: "一次掉血跌穿多条线时, 三条会按顺序全部触发")。
	var frac: float = float(u["hp"]) / maxf(float(u["maxHp"]), 1.0)
	while int(stt["eaten"]) < 3 and frac < CAKE_LINES[int(stt["eaten"])]:
		var idx: int = int(stt["eaten"])
		stt["eaten"] = idx + 1
		_cake_eat(u, si, stt, idx)
	# ── 两条独立 HoT(可并存) ──
	_cake_hot(u, stt, "hot1", delta)
	_cake_hot(u, stt, "hot3", delta)
	# ── 第三块的 8 秒攻速窗口到期 → 撤回 ──
	if float(stt.get("aspd_add", 0.0)) > 0.0 and battle._t >= float(stt.get("aspd_until", 0.0)):
		u["aspd_perm"] = maxf(0.01, float(u.get("aspd_perm", 1.0)) - float(stt["aspd_add"]))
		stt["aspd_add"] = 0.0
	var orb = stt.get("orbit", null)
	if orb is Dictionary:
		(orb as Dictionary)["left"] = 3 - int(stt["eaten"])
		_vfx.cake_orbit_update(u, orb, delta)


## 吃下第 idx 块(0/1/2)。★**同步入口** —— 门禁直接调它, 不等任何演出。
## (装备 "p2eq_069" —— ★这行 id 是给 tooltip_number_audit 当【就近锚点】的:
##  它要求文案里的 a/b/c 能在该 id 字面量 ±2500 字符内找到同样的三元数组。)
func _cake_eat(u: Dictionary, si: int, stt: Dictionary, idx: int) -> void:
	stt["cake_eaten_n"] = int(stt.get("cake_eaten_n", 0)) + 1   # 同步触发证据(门禁读它)
	match idx:
		0:
			var hp_add: float = [200.0, 400.0, 600.0][si]   # 装备 hp 已是最终值, 不乘 HP_MULT(§3.1)
			u["maxHp"] = float(u["maxHp"]) + hp_add
			u["hp"] = float(u["hp"]) + hp_add
			battle._recalc_stats(u)
			stt["hot1_pct"] = [0.006, 0.008, 0.010][si]     # 每秒回 0.6/0.8/1% 最大生命
			stt["hot1_left"] = CAKE_HOT1_SEC
			stt["hot1_acc"] = 0.0
		1:
			battle._damage._buff(u, "lifesteal", CAKE_LIFESTEAL, false, 99999.0)   # +5% 生命偷取(固定值)
			u["base_atk"] = float(u.get("base_atk", 0.0)) + [10.0, 21.0, 40.0][si]
			battle._recalc_stats(u)
		2:
			battle._damage._grant_shield(u, [150.0, 250.0, 400.0][si])
			_eq._eq_grant_energy(u, CAKE_ENERGY)
			var aspd: float = [0.40, 0.60, 0.80][si]        # +40/60/80% 攻速, ★只持续 8 秒
			u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + aspd
			stt["aspd_add"] = aspd
			stt["aspd_until"] = battle._t + CAKE_ASPD_SEC
			stt["hot3_pct"] = [0.013, 0.016, 0.020][si]     # 每秒回 1.3/1.6/2% 最大生命
			stt["hot3_left"] = CAKE_HOT3_SEC
			stt["hot3_acc"] = 0.0
	_vfx.cake_bite_fx(u, idx)


## 一条带到期时间的【每秒回 X% 最大生命】通道。
## ★按【当前】最大生命算, 不锁速率 —— 文案写的就是"每秒回复 X% 最大生命",
##   而这件的第一块自己就会把最大生命顶高。锁速率反而与文案不符。
func _cake_hot(u: Dictionary, stt: Dictionary, tag: String, delta: float) -> void:
	var left: float = float(stt.get(tag + "_left", 0.0))
	if left <= 0.0:
		return
	var step: float = minf(delta, left)
	stt[tag + "_left"] = left - step
	var acc: float = float(stt.get(tag + "_acc", 0.0)) + step * float(stt.get(tag + "_pct", 0.0)) * float(u["maxHp"])
	# 攒到 ≥1 才发一次, 免得每帧刷零点几的治疗数字
	if acc >= 1.0:
		var give: float = floorf(acc)
		acc -= give
		battle._damage._heal(u, give, true)
		stt[tag + "_healed"] = float(stt.get(tag + "_healed", 0.0)) + give   # 同步证据
	stt[tag + "_acc"] = acc


# ══════════════════════════════════════════════════════════════════
#  §070 压舱咸鱼砖(食物 · 4 费)
#
#  · on-hit: 附带自身 3/4.5/7% 最大生命的【物理】伤害
#  · 并以目标为中心溅射 250 码内的敌人, 各 1/1.5/2% 自身最大生命的【物理】伤害
#  · 被动: 把受到伤害的 30/40/50% 存进【灰色血条】, 每秒把灰条的 5% 转回生命
#  · 额外攻速 = 最大生命 × 0.01(%)  ⇒ 3000 血 = +30%, 10000 血 = +100%
#
#  ★用户 2026-08-05 拍板:「最大, 物理」——
#    ① "血量 × 0.01" 用的是【最大生命】不是当前生命(当前生命会"越残血越慢", 与定位相反)
#    ② on-hit 与溅射都是【物理伤害】(吃护甲)
#
#  ⚠⚠ 已知放大回路(用户知情并选择不加帽): 三段效果**全部按最大生命缩放**,
#     而食物羁绊【成长】让血量没有天花板 ⇒ 血涨 → 打得疼【且】打得快。
#     ⇒ 天花板由食物羁绊决定, 不由这件决定。门禁另建了一条【量级线】盯这件的实际 DPS 倍率。
# ══════════════════════════════════════════════════════════════════

## 灰条把受到伤害的多少存起来
const GREY_STORE := [0.30, 0.40, 0.50]

## ⚠⚠ 诚实记录, 两条与文案字面不完全等价的地方(都是【按契约执行】的结果, 不是我随手定的):
##   ① **灰条【不】挡伤害** —— 这一条已经解决, 不再是差异。
##      `SpecialBalance` 后来加了 `absorb: bool` 选项(special_balance.gd:53/:77, 消费在 :127
##      `if not bool(e.get("absorb", true)): continue`), 本文件两处 grant 都传 `{"absorb": false}`
##      (见 `_grey_store` 与转血那两处) ⇒ 灰条是**纯回收池**, 与文案字面一致。
##      (旧注写"挂上去就会挡伤害 / 得先给 SpecialBalance 加 absorb=false 选项" 已经过时, 已订正。)
##   ② `_st_taken` 记的是【减伤后的名义伤害】, 与"实际掉了多少血"不同 ——
##      被普通护盾/灰条挡掉的那部分【也算】受到伤害, 照样进灰条。
##      这与文案"受到的伤害"是一致的读法, 但和"掉了多少血"不是一回事, 记一笔免得以后当 bug 查。
## 灰条每秒转回生命的比例(固定 5%, 不随星级)
const GREY_CONVERT := 0.05
## 额外攻速系数: 最大生命 × 0.01 得到的是【百分数】⇒ 转成倍率要再 /100
const BRICK_ASPD_PER_HP := 0.0001


func _brick_tick(u: Dictionary, si: int, stt: Dictionary, delta: float) -> void:
	# ── ① 额外攻速 = maxHp × 0.01 % ——【实时】跟着最大生命走 ──
	#    ★用"已给多少"的差量写 aspd_perm: 直接赋值会把别件装备加的攻速抹掉。
	var want: float = float(u["maxHp"]) * BRICK_ASPD_PER_HP
	var given: float = float(stt.get("aspd_given", 0.0))
	if absf(want - given) > 0.0001:
		u["aspd_perm"] = float(u.get("aspd_perm", 1.0)) + (want - given)
		stt["aspd_given"] = want
	# ── ② 受到的伤害按比例存进灰条 ──
	#    ★没有"受到伤害"的中央钩子可挂(那要改 battle_damage 的两条路径, 是主会话的地盘),
	#      所以用 `_st_taken` 做**逐帧差分** —— 它是两条伤害路径都在记的累计承受量
	#      (062 雾行海葵同款做法)。每帧一次 ⇒ 粒度就是一帧, 不会漏也不会重。
	var taken: int = int(u.get("_st_taken", 0))
	if not stt.has("taken_snap"):
		stt["taken_snap"] = taken
	var dtk: int = taken - int(stt["taken_snap"])
	stt["taken_snap"] = taken
	if dtk > 0:
		var store: float = float(dtk) * GREY_STORE[si]
		battle._spec.grant(u, KEY_GREY, store, {"absorb": false})
		stt["grey_stored"] = float(stt.get("grey_stored", 0.0)) + store   # 同步证据
	# ── ③ 每秒把灰条的 5% 转回生命 ──
	stt["grey_t"] = float(stt.get("grey_t", 0.0)) + delta
	while float(stt["grey_t"]) >= 1.0:
		stt["grey_t"] = float(stt["grey_t"]) - 1.0
		_brick_convert(u, stt)
	_vfx.grey_bar_update(u, battle._spec.val(u, KEY_GREY))


## 灰条 → 生命 的一次转化(每秒一次)。★**同步入口**, 门禁直接调。
##
## ★为什么用 clear + 重新 grant 而不是"扣一点":
##   `SpecialBalance` 只有 grant/absorb/clear 三个写口 —— absorb 会按 order 串到别的余额上
##   (同一只龟可能同时带着 071 奶油盾), 那会误伤。clear 走的是 on_break(reason="clear"),
##   而灰条【故意不注册 on_break】⇒ 这条路是静默的, 不会误触发任何"破盾"行为。
func _brick_convert(u: Dictionary, stt: Dictionary) -> void:
	var g: float = battle._spec.val(u, KEY_GREY)
	if g <= 0.01:
		return
	var conv: float = g * GREY_CONVERT
	battle._spec.clear(u, KEY_GREY)
	if g - conv > 0.01:
		battle._spec.grant(u, KEY_GREY, g - conv, {"absorb": false})
	battle._damage._heal(u, conv, true)
	stt["grey_converted"] = float(stt.get("grey_converted", 0.0)) + conv   # 同步证据


## on-hit(由 EquipSystem._eq_on_hit 分派)。★**同步结算**, 不等任何演出。
func _eq_ballast_brick(src: Dictionary, tgt: Dictionary, si: int, basic: bool = false) -> void:
	## ★规格「每次普攻附带」—— 技能/浮游炮不触发(2026-08-11 报修族第 7 件, 补验收时抓到)。
	if not basic:
		return
	if not src.get("alive", false) or not tgt.get("alive", false):
		return
	var mh: float = float(src["maxHp"])
	var main_pct: float = [0.030, 0.045, 0.070][si]     # on-hit: 3/4.5/7% 自身最大生命
	var splash_pct: float = [0.010, 0.015, 0.020][si]   # 溅射: 1/1.5/2% 自身最大生命
	# ★物理伤害 ⇒ _resolve_dmg 的 magic=false(吃护甲); from_equip=true 防回钩 on-hit 自激(契约 §5.7)
	battle._damage._apply_damage_from(src, tgt,
		battle._resolve_dmg(src, mh * main_pct, tgt, false), Color("#ffd9a0"), 0.0, false, true)
	tgt["_brick_hit_n"] = int(tgt.get("_brick_hit_n", 0)) + 1   # 同步触发证据(门禁读它)
	var n := 0
	for o in battle._targeting._enemies_of(src):
		if is_same(o, tgt) or not o.get("alive", false):
			continue
		var d: float = (o["pos"] - tgt["pos"]).length()
		if d > 250.0:
			continue
		## ★伤害跟冲击环走(2026-08-11 用户: 「主要是炸开一道环, 环碰到敌人才跳伤害」):
		##   延时 = 距离 / FoodEqVfx.BRICK_WAVE_SPEED —— 与环的视觉扩张【同一个常量】。
		##   _pending_shots 是 sim 内定时器(CLAUDE.md §3.5: 数值不依赖演出 tween)。
		##   伤害额在调度时快照(on-hit 那一刻的最大生命); 回调重查存活, 环没到人先死不结算。
		var dmg_o: float = battle._resolve_dmg(src, mh * splash_pct, o, false)
		battle._pending_shots.append({"delay": d / FoodEqVfx.BRICK_WAVE_SPEED, "src": src,
			"fn": func() -> void:
				if not src.get("alive", false) or not o.get("alive", false):
					return
				battle._damage._apply_damage_from(src, o, dmg_o, Color("#ffcf88"), 0.0, false, true)
				o["_brick_splash_n"] = int(o.get("_brick_splash_n", 0)) + 1})
		n += 1
	src["_brick_splash_last"] = n
	_vfx.splash_crown(tgt["pos"])
	_vfx.brick_wave(tgt["pos"])


# ══════════════════════════════════════════════════════════════════
#  §071 炼乳罐(食物 · 4 费 · 定位: 辅助)
#
#  · 战斗开始为【所有友军(含携带者自己)】套上其最大生命 10/18/25% 的【奶油护盾】,
#    **永久不衰减**
#  · 奶油护盾被打破时: 对持有者 300 码内的敌人造成 70/100/150 魔法伤害,
#    随后给【持有者】+10 双抗 / +20/30/40% 攻速 / +50 射程, **持续整路**
#  · 携带者每累计损失 50% 最大生命 → 再给全队上一次
#
#  ★用户 2026-08-05 拍板「3 次, 持续每路, 包括」:
#    · 每路共 **3 次** = 开局 1 次 + 携带者累计掉 50% / 掉 100% 各 1 次
#      (用户原话"每路最多触发 2 次…即开局的一次和后续的 2 次"前后矛盾, 提出后明确为 3 次)
#    · 破盾后那三样加成【持续整路】, 换路重置
#    · 「所有友军」**包括携带者自己**
#
#  ★设计上不怕被针对: 盾被打掉不亏反赚(既炸伤敌人又给持有者整路 buff)。
# ══════════════════════════════════════════════════════════════════

## 每路总共给几次(开局 1 + 掉 50% + 掉 100%)
const CREAM_TIMES := 3
## 每累计损失这么多比例的最大生命, 补一次
const CREAM_LOSS_STEP := 0.50


func _cream_tick(u: Dictionary, si: int, stt: Dictionary, delta: float) -> void:
	# ── 开局那一次 ──
	if not bool(stt.get("opened", false)):
		stt["opened"] = true
		stt["given_n"] = 0
		stt["loss_acc"] = 0.0
		_cream_grant_all(u, si, stt)
	# ── 携带者累计损失: 同样用 `_st_taken` 逐帧差分(理由同 070) ──
	var taken: int = int(u.get("_st_taken", 0))
	if not stt.has("taken_snap"):
		stt["taken_snap"] = taken
	var dtk: int = taken - int(stt["taken_snap"])
	stt["taken_snap"] = taken
	if dtk > 0:
		stt["loss_acc"] = float(stt.get("loss_acc", 0.0)) + float(dtk)
		var step: float = float(u["maxHp"]) * CREAM_LOSS_STEP
		while float(stt["loss_acc"]) >= step and int(stt.get("given_n", 0)) < CREAM_TIMES:
			stt["loss_acc"] = float(stt["loss_acc"]) - step
			_cream_grant_all(u, si, stt)
	## ★★壳的呼吸改成【逐个友军】推进(2026-08-11)。
	##   改之前只推 `stt["shell"]` 那一个(建在携带者身上的) ——
	##   现在壳分散在每个拿到盾的友军身上, 不改这里就变成"壳建了但不动"。
	##   ★盾没了(被打破/撚场)就把壳收掉 —— 否则会出现"盾早没了壳还亮着"。
	for o in battle._targeting._allies_of(u, true):
		var cv: float = battle._spec.val(o, KEY_CREAM)
		## ★盾量进血条(2026-08-11 补验收): 奶油盾是 SpecialBalance 余额, 不进 u["shield"] ⇒
		##   血条上原本【没有任何读数】—— 玩家看得见壳、看不见"还剩多少/破没破"。
		##   照 068 法力盾的规矩(特殊护盾给特殊颜色护盾条)每帧喂真实余额, 0 时自动隐藏。
		_vfx.cream_bar_update(o, cv)
		var osh = o.get("_cream_shell", null)
		if not (osh is Dictionary):
			continue
		if not o.get("alive", false) or cv <= 0.0:
			_vfx.cream_shell_free(osh)
			o.erase("_cream_shell")
			continue
		_vfx.cream_shell_update(osh, delta)


## 给【所有友军(含自己)】各上一层奶油护盾。★**同步入口**, 门禁直接调。
## (装备 "p2eq_071" —— tooltip_number_audit 的就近锚点, 同 069 那段注释)
func _cream_grant_all(u: Dictionary, si: int, stt: Dictionary) -> void:
	if int(stt.get("given_n", 0)) >= CREAM_TIMES:
		return
	stt["given_n"] = int(stt.get("given_n", 0)) + 1
	var pct: float = [0.10, 0.18, 0.25][si]   # 最大生命的 10/18/25%
	var n := 0
	for o in battle._targeting._allies_of(u, true):
		if not o.get("alive", false):
			continue
		var amt: float = float(o["maxHp"]) * pct
		# ★永久不衰减 ⇒ decay_sec 缺省 0。破盾回调走 SpecialBalance 的 on_break。
		# ⚠ 同 key 再 grant 会【叠加余额并换掉 on_break】(SpecialBalance 的既有语义) ⇒
		#   两只不同星级的携带者都带 071 时, 破盾时用的是【最后一次 grant 的那个 si】。
		#   这是共用基建的行为, 不在这里另造一套多来源记账 —— 记一笔, 不当 bug 查。
		battle._spec.grant(o, KEY_CREAM, amt, {
			"on_break": func(uu, _k, reason): _cream_on_break(uu, si, str(reason)),
		})
		o["_cream_given"] = float(o.get("_cream_given", 0.0)) + amt   # 同步证据
		## ★★每一个拿到盾的友军都要有壳(2026-08-11 修)。
		##   改之前壳只建一个、而且建在**携带者**身上(下面那行 `cream_shell_make(u)`) ⇒
		##   友军拿到了盾、身上却什么都没有 ⇒ 用户实拍:「全队奶油护盾完全没表达」。
		##   这一类比"颜色不对"严重: **玩家无从得知效果生效了没有**。
		##   ★ `cream_shell_make` 建的是个跟随单位的精灵, 进 `_follow_vfx` ——
		##   而 `_follow_vfx` 换路是会被清的(dual_lane_flow), 所以逐人建不会残留。
		if not (o.get("_cream_shell", null) is Dictionary):
			o["_cream_shell"] = _vfx.cream_shell_make(o)
		n += 1
	stt["cream_targets_last"] = n


## 奶油护盾被打破 → 300 码 AOE + 给【持有者】整路加成。
## ★reason: "damage"(被打光) / "decay"(自然衰减完·本件不衰减所以不会走) / "clear"(撤场·不算破)
## (装备 "p2eq_071" —— tooltip_number_audit 的就近锚点)
func _cream_on_break(holder: Dictionary, si: int, reason: String) -> void:
	if reason == "clear" or not holder.get("alive", false):
		return
	holder["_cream_broke_n"] = int(holder.get("_cream_broke_n", 0)) + 1   # 同步触发证据
	var dmg: float = [70.0, 100.0, 150.0][si]   # 300 码内敌人 70/100/150 魔法伤害
	for o in battle._targeting._enemies_of(holder):
		if not o.get("alive", false):
			continue
		if (o["pos"] - holder["pos"]).length() > 300.0:
			continue
		battle._damage._apply_damage_from(holder, o,
			battle._resolve_dmg(holder, dmg, o, true), Color("#fff0c8"), 0.0, false, true)
	# 三样加成【持续整路】: 双抗写 base_(不是 buff, buff 会到期), 攻速走 aspd_perm, 射程走 range_add
	holder["base_def"] = float(holder.get("base_def", 0.0)) + 10.0
	holder["base_mr"] = float(holder.get("base_mr", 0.0)) + 10.0
	holder["aspd_perm"] = float(holder.get("aspd_perm", 1.0)) + [0.20, 0.30, 0.40][si]
	holder["range_add"] = float(holder.get("range_add", 0.0)) + 50.0
	battle._recalc_stats(holder)
	_vfx.cream_burst(holder["pos"])


# ══════════════════════════════════════════════════════════════════
#  §072 铁皮蛋糕盒(食物 · 5 费 · 定位: 变身型终极坦克)
#
#  · 被动: 获得最大生命 50/80/120% 的【终极护盾】, 永久
#  · 护盾存在时携带者【化身蛋糕礼盒】: 属性照旧, 但射程变近战,
#    普攻与技能替换成礼盒专属
#      礼盒被动: 嘲讽 550 码内所有敌; 每有一个敌人以自己为目标 → **实时** +20/30/60 双抗
#      礼盒普攻: 1 倍攻击力物理伤害
#      礼盒技能: 300 码蛋糕法阵 5 秒, 每秒为其中友军回 50/70/120 生命 + 2/4/6 龟能
#  · 终极护盾被打破 → 携带者出盒参战(**本路不再变回**, 换路重新给盾重新变身)
#  · 携带者阵亡 → 分裂出两个蛋糕礼盒: 20/40/100% 携带者最大生命 · 携带者的攻击力与双抗,
#    **其他都是 0 和默认值**, 同样嘲讽、同样施放礼盒技能
#
#  ★用户看过量级(3★ 总等效血量约 13 万 / 清完约 87 秒)后**明确选择保留**, 这里不做任何收口。
#
#  ★「变身」照项目既有写法(双头龟 two_form / 熔岩 volcano): **同一个单位字典上翻字段**,
#    不另造单位、不另起一套形态机。存原值 → 换字段 → 出盒时还原。
# ══════════════════════════════════════════════════════════════════

## 嘲讽半径(码)。每帧重新施加 ⇒ 走出去就掉, 不是一次性打标
const BOX_TAUNT_PX := 550.0
## 嘲讽刷新时长(秒): 略大于一帧, 保证连续但一停就断
const BOX_TAUNT_SEC := 0.35
## 蛋糕法阵半径(码)与持续(秒)
const BOX_FIELD_PX := 300.0
const BOX_FIELD_SEC := 5.0


func _box_tick(u: Dictionary, si: int, stt: Dictionary, delta: float) -> void:
	# ── 分裂出来的礼盒: 没有护盾、不再分裂, 只吃"嘲讽 + 实时双抗 + 法阵" ──
	if u.get("_cake_is_box", false):
		_box_form_tick(u, si, stt, delta)
		return
	# ── 携带者: 开局一次性给终极护盾并变身(每路一次) ──
	if not bool(stt.get("opened", false)):
		stt["opened"] = true
		var pct: float = [0.50, 0.80, 1.20][si]   # 终极护盾 = 最大生命的 50/80/120%
		battle._spec.grant(u, KEY_ULT, float(u["maxHp"]) * pct, {
			"on_break": func(uu, _k, reason): _box_unbox(uu, str(reason)),
		})
		stt["ult_given"] = float(u["maxHp"]) * pct   # 同步证据
		_box_enter(u, si, stt)
	## ★盾量进血条(2026-08-11 补验收): 终极护盾是 SpecialBalance 余额, 不进 u["shield"] ⇒
	##   血条上原本没有任何读数 —— 玩家只看得到"变成了盒子", 看不到"这层盾还剩多少/快破没"。
	##   照 068 法力盾的规矩(特殊护盾给特殊颜色护盾条)每帧喂真实余额(礼盒粉段), 破盾后自动隐藏。
	## ★2026-08-12 改走 HpBar: 镜像进 `_ultShieldVal`, 由血条自己画(它的 barMax 会撑开)。
	##   原来在 food_eq_vfx 自画一条 ColorRect, 而那套用 maxHp 当分母 ⇒
	##   **满血时段宽恒为 0**, 玩家一次都没看见过(用户实测第 7 条)。
	u["_ultShieldVal"] = battle._spec.val(u, KEY_ULT)
	if u.get("_cake_box", false):
		_box_form_tick(u, si, stt, delta)


## 变身进礼盒: 存原值 → 射程改近战 → 关掉本体普攻/技能(改由礼盒专属接管)。
## ★**同步入口**, 门禁直接调。
func _box_enter(u: Dictionary, si: int, stt: Dictionary) -> void:
	if u.get("_cake_box", false):
		return
	u["_cake_box"] = true
	u["_cake_si"] = si
	# 原值存在单位字典上(不是 eq_state): 出盒还原要在【任何】路径上都拿得到
	u["_cake_o_range"] = float(u.get("atk_range", 70.0))
	u["_cake_o_melee"] = bool(u.get("melee", false))
	u["_cake_o_skills"] = (u.get("active_skills", []) as Array).duplicate()
	u["_cake_o_basic"] = bool(u.get("no_basic", false))
	## ★★真的换立绘(2026-08-11 用户:「换」)。
	##   改之前 `_box_enter` 只改属性(射程/技能/普攻), 视觉上只有一次性的 `box_close_fx`
	##   ⇒ **属性变了、长相还是龟**, 玩家不知道自己已经"化身蛋糕礼盒"。
	##   ★为什么换的是 `idle_sd` 而不是直接设 spr.texture:
	##   `battle_render` 每帧会用 `u["idle_sd"]` 把属性还原到 idle(动作播完就回 idle),
	##   直接改贴图下一帧就被抹掉了 —— 换源头才能持久。
	u["_cake_o_idle_sd"] = u.get("idle_sd", {})
	var _box_tex: Texture2D = load(BOX_FORM_TEX) if ResourceLoader.exists(BOX_FORM_TEX) else null
	if _box_tex != null:
		var _bsd: Dictionary = battle._sprite_dict_from(_box_tex, null, false)
		u["idle_sd"] = _bsd
		battle._set_anim_sheet(u, _bsd, "", true)
	# ★双抗【不存原值】: 礼盒加的那部分单独记在 `_cake_res_given` 里, 出盒时按差量减回去。
	#   存原值再整个写回会把变身期间【别的来源】给的双抗(071 破盾 +10、羁绊…)一并抹掉 ——
	#   那是"手抄快照"的典型翻车形状, 所以这里只动自己加的那一份。
	# 「射程变为近战射程」——★下限钳制: 近战最小攻击射程是 100(MELEE_ATK_RANGE_MIN),
	#   写 70 会让它贴到重叠里去(那个常量就是为此加的)。
	u["atk_range"] = float(battle.MELEE_ATK_RANGE_MIN)
	u["melee"] = true
	# 「普攻和技能将被替换为蛋糕礼盒的专属」——
	#   本项目没有"改写某只龟普攻/技能"的钩子(普攻按 u["id"] 查 BASIC_ATK 表、技能按 active_skills 派),
	#   所以走既有的两个关闸: no_basic 关掉本体普攻、active_skills 清空关掉本体技能,
	#   两者都由本文件的礼盒专属实现接管(_box_basic / _box_field)。
	u["no_basic"] = true
	u["active_skills"] = []
	# 礼盒技能的节奏【沿用携带者自己的技能冷却】—— 不凭空发明一个数(规格里没给这个数)
	var iv := 8.0
	for s in (u["_cake_o_skills"] as Array):
		iv = maxf(iv, float(battle._skill_cd(u, str(s))))
	stt["field_iv"] = iv
	stt["field_t"] = iv * 0.5   # 开局半个周期后放第一次(不在开场瞬间白送)
	_vfx.box_close_fx(u)


## 礼盒形态每帧: 嘲讽 550 码 + 按【当前锁定自己的敌人数】实时给双抗 + 法阵计时。
## (装备 "p2eq_072" —— tooltip_number_audit 的就近锚点)
func _box_form_tick(u: Dictionary, si: int, stt: Dictionary, delta: float) -> void:
	# ── 嘲讽: 每帧重新施加短时长 ⇒ 敌人走出 550 码就自然掉 ──
	var tl: Array = []
	for o in battle._targeting._enemies_of(u):
		if o.get("alive", false) and (o["pos"] - u["pos"]).length() <= BOX_TAUNT_PX:
			tl.append(o)
	if not tl.is_empty():
		battle._taunt(u, tl, BOX_TAUNT_SEC)
	u["_box_taunted_n"] = tl.size()   # 同步证据
	# ── 实时双抗: 数【现在有几个敌人以自己为目标】 ──
	#   ★是"选靶结算之后"的真实结果(`_sep_target` 由 _tick_unit 每帧写), 不是嘲讽施加时算一次:
	#     敌人一切目标, 这里下一帧就掉下来。用户点名要的就是这个"实时"。
	var lockers: int = box_lockers(u)
	var per: float = [20.0, 30.0, 60.0][si]   # 每个锁定自己的敌人 +20/30/60 双抗
	var want: float = per * float(lockers)
	if absf(want - float(u.get("_cake_res_given", 0.0))) > 0.01:
		var d: float = want - float(u.get("_cake_res_given", 0.0))
		u["base_def"] = float(u.get("base_def", 0.0)) + d
		u["base_mr"] = float(u.get("base_mr", 0.0)) + d
		u["_cake_res_given"] = want
		battle._recalc_stats(u)
	_vfx.taunt_ring_update(u, lockers)
	# ── 礼盒专属普攻: 本体普攻已关, 这里按自己的攻击节奏打 1 倍攻击力物理 ──
	_box_basic_tick(u, delta)
	# ── 礼盒专属技能: 蛋糕法阵 ──
	stt["field_t"] = float(stt.get("field_t", 0.0)) + delta
	if float(stt["field_t"]) >= float(stt.get("field_iv", 8.0)):
		stt["field_t"] = 0.0
		_box_field(u, si)
	_box_field_tick(u, si, stt, delta)


## 现在有几个敌人以 u 为目标。★纯查询, 门禁直接调。
func box_lockers(u: Dictionary) -> int:
	var n := 0
	for o in battle._units:
		if not o.get("alive", false) or not battle._is_hostile(o, u):
			continue
		var t = o.get("_sep_target", null)
		if t is Dictionary and is_same(t, u):
			n += 1
	return n


## 礼盒普攻: 造成 1 倍攻击力的【物理】伤害。
## ★走 from_equip=true(契约 §5.7): 它不再回钩 on-hit —— 否则携带者身上别的 on-hit 装备
##   会被礼盒普攻二次点燃, 那是自激的形状。
func _box_basic_tick(u: Dictionary, delta: float) -> void:
	u["_box_cd"] = maxf(0.0, float(u.get("_box_cd", 0.0)) - delta)
	if float(u["_box_cd"]) > 0.0:
		return
	# ★眩晕/击飞期间不出手 —— 本体普攻走的是状态机(那里已经挡了), 礼盒普攻走这里,
	#   不自己挡就成了"被控住照打", 等于给这件装备白送一条免控。
	if battle._t < float(u.get("stun_until", 0.0)) or u.get("airborne", false):
		return
	var tgt = battle._targeting._acquire_target(u)
	if not (tgt is Dictionary) or not (tgt as Dictionary).get("alive", false):
		return
	if ((tgt as Dictionary)["pos"] - u["pos"]).length() > battle._eff_range(u):
		return
	u["_box_cd"] = float(u.get("atk_interval", 1.2)) / maxf(0.1, float(u.get("aspd_perm", 1.0)))
	box_hit(u, tgt)


## 礼盒普攻的结算体。★**同步入口** —— 门禁直接调它量掉血, 不等任何演出(CLAUDE.md §3.5)。
func box_hit(u: Dictionary, tgt: Dictionary) -> void:
	if not u.get("alive", false) or not tgt.get("alive", false):
		return
	battle._damage._apply_damage_from(u, tgt,
		battle._atk_dmg(u, 1.0, tgt), Color("#ffd0dc"), 0.0, false, true)
	tgt["_box_hit_n"] = int(tgt.get("_box_hit_n", 0)) + 1   # 同步触发证据
	battle._vfx._hit_spark(tgt)


## 礼盒技能: 以自己为中心开一个 300 码蛋糕法阵, 持续 5 秒。
## ★跟随携带者(2026-08-11 用户拍板「是要跟随的」): 判定中心 = 每次结算时的当前位置,
##   演出层同帧跟随(cake_field_fx 存 unit 引用) —— 判定与画面永远同一个点。
func _box_field(u: Dictionary, _si: int) -> void:
	u["_box_field_left"] = BOX_FIELD_SEC
	u["_box_field_acc"] = 0.0
	u["_box_field_n"] = int(u.get("_box_field_n", 0)) + 1   # 同步触发证据
	_vfx.cake_field_fx(u, BOX_FIELD_SEC)


func _box_field_tick(u: Dictionary, si: int, _stt: Dictionary, delta: float) -> void:
	var left: float = float(u.get("_box_field_left", 0.0))
	if left <= 0.0:
		return
	u["_box_field_left"] = maxf(0.0, left - delta)
	u["_box_field_acc"] = float(u.get("_box_field_acc", 0.0)) + delta
	while float(u["_box_field_acc"]) >= 1.0:
		u["_box_field_acc"] = float(u["_box_field_acc"]) - 1.0
		box_field_pulse(u, si)


## 法阵的一次每秒结算。★**同步入口**, 门禁直接调。
## (装备 "p2eq_072" —— tooltip_number_audit 的就近锚点)
func box_field_pulse(u: Dictionary, si: int) -> void:
	## ★中心 = 当前位置(跟随, 2026-08-11 用户拍板), 不再读施放时的快照
	var c: Vector2 = u["pos"]
	var heal: float = [50.0, 70.0, 120.0][si]     # 每秒回 50/70/120 生命
	var energy: float = [2.0, 4.0, 6.0][si]       # 每秒给 2/4/6 龟能
	var n := 0
	for o in battle._targeting._allies_of(u, true):
		if not o.get("alive", false) or (o["pos"] - c).length() > BOX_FIELD_PX:
			continue
		battle._damage._heal(o, heal)
		_eq._eq_grant_energy(o, energy)
		## ★滴答读数(2026-08-11 补验收): 台子默认关飘字 ⇒ "每秒回血"原来一点画面证据都没有。
		##   被治到的友军身上升一颗小奶糕 —— 谁在圈里、哪一秒跳了, 一眼可读。
		_vfx.field_heal_fx(o)
		n += 1
	u["_box_field_hits"] = int(u.get("_box_field_hits", 0)) + n   # 同步证据


## 终极护盾被打破 → 出盒参战。★本路不再变回去(每路一次), 换路整体重建 ⇒ 新的一路重新变身。
func _box_unbox(u: Dictionary, reason: String) -> void:
	if reason == "clear" or not u.get("_cake_box", false):
		return
	u["_cake_box"] = false
	u["_cake_unboxed_n"] = int(u.get("_cake_unboxed_n", 0)) + 1   # 同步触发证据
	u["atk_range"] = float(u.get("_cake_o_range", 70.0))
	u["melee"] = bool(u.get("_cake_o_melee", false))
	u["active_skills"] = (u.get("_cake_o_skills", []) as Array).duplicate()
	u["no_basic"] = bool(u.get("_cake_o_basic", false))
	## ★立绘也要换回去 —— 漏了就会"盾早破了人还是个盒子"。
	##   同方向: 换的是 `idle_sd` 本身, 而不是 `spr.texture`(那会被渲染层下一帧抹掉)。
	var _osd = u.get("_cake_o_idle_sd", null)
	if _osd is Dictionary and not (_osd as Dictionary).is_empty():
		u["idle_sd"] = _osd
		battle._set_anim_sheet(u, _osd, "", true)
	u.erase("_cake_o_idle_sd")
	# ★把 skill_cd 清空让它重新懒初始化 —— 变身期间 active_skills 是空的, `_tick_skill_cd`
	#   的懒初始化会把 skill_cd 初始化成【空字典】并从此不再补。不清的话出盒瞬间
	#   `_pick_ready_skill` 会拿到 `cds.get(st, 0.0) == 0.0` ⇒ 每一个技能都"冷却好了" ⇒ 白送一发大招。
	u["skill_cd"] = {}
	# 锁定加成的双抗一并撤掉(它是"礼盒形态"的东西)
	var g: float = float(u.get("_cake_res_given", 0.0))
	if g > 0.0:
		u["base_def"] = maxf(0.0, float(u.get("base_def", 0.0)) - g)
		u["base_mr"] = maxf(0.0, float(u.get("base_mr", 0.0)) - g)
		u["_cake_res_given"] = 0.0
	u["_box_field_left"] = 0.0
	battle._recalc_stats(u)
	_vfx.taunt_ring_free(u)
	_vfx.box_open_fx(u)
	## ★烟雾爆开(2026-08-11 用户点名「护盾被打破变为本体时, 需要做个烟雾爆开特效」):
	##   盒子炸成一团烟、烟散了人站在那儿 —— 形态切换需要一个遮蔽帧, 否则是硬切。
	_vfx.unbox_smoke(u)


## 携带者阵亡 → 分裂出两个蛋糕礼盒(由 EquipSystem._eq_on_death 分派)。
## ★**同步入口** —— 门禁直接调, 建完单位那一行就能断言, 不等弹出演出。
##
## ★「其他都是 0 和默认值」是**逐字段落实**的, 不是复制携带者字典:
##   `_spawn_summon` 造出来的单位本来就是一张干净表(crit/穿透/吸血/增幅全 0),
##   我只往里写用户点名的那三样(生命 / 攻击力 / 双抗)。复制携带者字典会把
##   暴击、吸血、装备、eq_state、召唤物列表一并带过去 —— 那不是用户说的"其他都是 0"。
func _eq_cake_split(u: Dictionary, si: int, star: int) -> void:
	if u.get("_cake_is_box", false) or bool(u.get("_cake_split_done", false)):
		return   # 分裂盒不再分裂(链条终止), 每只携带者也只分裂一次
	u["_cake_split_done"] = true
	var hp_pct: float = [0.20, 0.40, 1.00][si]   # 携带者最大生命的 20/40/100%
	var hp: float = maxf(1.0, float(u["maxHp"]) * hp_pct)
	# ★★"携带者的双抗"要【扣掉礼盒形态自己临时加的那一份】(_cake_res_given)。
	#   携带者可能是【在礼盒形态里】死的(处决 / 墨迹真伤这类绕过余额的路), 那时它的 base_def
	#   里含着最多 +360 的锁定加成。照抄就变成"两个盒子各自先白拿 360 双抗, 然后再各自吃自己的
	#   锁定加成" —— 用户说的是"携带者的双抗", 不是"携带者当时被几个人锁着"。
	var own_def: float = maxf(0.0, float(u.get("base_def", 0.0)) - float(u.get("_cake_res_given", 0.0)))
	var own_mr: float = maxf(0.0, float(u.get("base_mr", 0.0)) - float(u.get("_cake_res_given", 0.0)))
	var made: Array = []
	for k in range(2):
		var b = battle._spawn._spawn_summon(u, "cakebox", hp, float(u.get("atk", 0.0)), {
			"label": "蛋糕礼盒", "spr_id": "", "col_size": 40.0, "hp_w": 28.0,
			"melee": true, "atk_range": float(battle.MELEE_ATK_RANGE_MIN),
			"atk_interval": float(u.get("atk_interval", 1.2)), "move_spd": 0.0, "no_move": true,
		})
		if b == null:
			continue
		b["base_def"] = own_def
		b["base_mr"] = own_mr
		## ★分裂盒也要有立绘(2026-08-11 补验收): _spawn_summon 无 spr_id ⇒ 兜底队色发光球,
		##   花名册打 spr=✗ ——「白球家族」, 玩家看到的是"场上多了两个蓝光点"而不是两个礼盒。
		##   做法同 _box_enter: 换 idle_sd 源头(渲染层每帧从 idle_sd 还原, 改 spr.texture 会被抹掉)。
		##   idle_px 按"64px 盒帧 → 40 码身高"归一(同 _spawn_summon 有立绘分支的公式);
		##   modulate 归白 —— 兜底发光球被染成了队色蓝, 不洗掉的话礼盒是蓝的。
		var _btex: Texture2D = load(BOX_FORM_TEX) if ResourceLoader.exists(BOX_FORM_TEX) else null
		if _btex != null:
			var _bsd2: Dictionary = battle._sprite_dict_from(_btex, null, false)
			b["idle_px"] = float(battle.TARGET_BODY_H) * (40.0 / 56.0) / float(maxi(1, _btex.get_height()))
			b["idle_offy"] = float(_btex.get_height()) * 0.5
			b["idle_sd"] = _bsd2
			battle._set_anim_sheet(b, _bsd2, "", true)
			var _bspr = b.get("sprite", null)
			if is_instance_valid(_bspr):
				_bspr.modulate = Color(1, 1, 1, 1)
		b["equips"] = [{"id": "p2eq_072", "star": star}]   # ★挂条目只为吃到每帧 _eq_tick(不跑属性管线)
		b["eq_state"] = {"p2eq_072": {"opened": true, "field_iv": 8.0, "field_t": 4.0}}
		b["_cake_is_box"] = true
		b["_cake_si"] = si
		b["_food_eq"] = true                              # 常驻守卫: 让 _eq_tick 把它交给本文件
		b["no_basic"] = true                              # 普攻走礼盒专属(本文件 _box_basic_tick)
		b["active_skills"] = []
		battle._recalc_stats(b)
		made.append(b)
		var dir: Vector2 = Vector2(1.0 if k == 0 else -1.0, 0.0)
		_vfx.box_split_hop(u["pos"], dir)
	u["_cake_split_n"] = made.size()   # 同步触发证据(门禁读它)
