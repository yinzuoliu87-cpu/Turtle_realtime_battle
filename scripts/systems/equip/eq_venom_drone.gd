class_name VenomDroneSystem
extends RefCounted
## eq_venom_drone.gd — 092【剧毒飞行物】(遗物·2 费) 的效果本体
## 方案书 docs/plans/20260805-装备逐件重做.md §0.5 ★092 / 实装契约 20260805-实装契约.md E 路
##
## ══════════════════════════════════════════════════════════════════════
##  ★规格(用户原话, 一字未改)
## ══════════════════════════════════════════════════════════════════════
## > 提供 50/70/100 生命值和 10/22/40 魔抗。
## > 携带者召唤一个剧毒飞行物, 不可选中, 在携带者阵亡后飞行物也阵亡。
## > 飞行物会缓慢的飞行, 朝着随机目标飞, 飞过目标到达它的对面落点后朝下一个目标飞,
## > 同样是飞过目标到对面落点, 如此重复。
## > 飞行物会在路径上每 0.25 秒留下持续 4 秒的毒雾, 毒雾会每 0.25 秒给触碰到的敌方单位
## > 施加 2/3/5 层中毒层数, 还会每 0.25 秒施加一层剧毒缓速效果, 每个单位身上最多 20 层剧毒缓速,
## > 一层剧毒缓速会减少目标 2% 移速和 1% 魔抗, 如果目标在 1.5 秒内没有被施加剧毒缓速,
## > 则每 0.25 秒失去一层剧毒缓速。
##
## 用户已知它放 2 费偏强, 仍然选了 2 费。**上面那段是 2026-08-05 的原话逐字引用, 不改它。**
##
## ⚠★★但【现行值不等于上面的引文】—— 用户 2026-08-13 又加强过三处, 以常量为准, 别照引文改代码:
##   · 中毒层数  2/3/5 → **3/5/8**   (`POISON_STACKS`)
##   · 毒雾寿命  4 秒  → **6 秒**    (`FOG_LIFE`)
##   · 过冲距离  260 码 → **160 码** (`OVERSHOOT`)
##   其余(0.25 秒节拍 / 20 层上限 / 每层 2% 移速 1% 魔抗 / 1.5 秒宽限)与引文一致。
##
## ══════════════════════════════════════════════════════════════════════
##  ★四个必须写清楚的实现判断(规格没写死的地方, 我怎么定的 + 为什么)
## ══════════════════════════════════════════════════════════════════════
## ① **"毒雾每 0.25 秒施加"是【毒雾场】按 0.25 秒节拍施加一次, 不是【每一团】各施加一次。**
##    飞行物每 0.25 秒扔一团、每团活 FOG_LIFE(6) 秒 ⇒ 场上常驻 24 团, 而它飞得慢 ⇒ 相邻团大面积重叠,
##    一只站在尾迹里的敌人同时被五六团盖住。若按"每团各算一次", 一个节拍就能叠满 20 层剧毒缓速,
##    **20 层上限与"1.5 秒不刷新才掉层"这两条规则会同时失去意义** —— 规格白写了两条。
##    ⇒ 只有"整片毒雾场每 0.25 秒结算一次"才让这两条规则都有用。这是规格自洽性给的答案。
##    ★但**不同携带者的毒雾场各算各的**(两只龟各带一件 = 各结算一次), 那是装备实例语义。
##
## ② **飞行物不是 `battle._units` 里的单位。** 规格要它"不可选中" ——
##    做成真单位再打不可选中标记, 要额外应付: 团灭判定(留一个活的飞行物会卡住换路窗口)、
##    分离/寻路/血条/伤害统计/召唤物特殊 tick。做成纯逻辑+演出体则"不可选中"是**结构性成立**的,
##    不是靠一个可能被别处忽略的 flag。规格的两条可观测要求(不可选中 / 随携带者阵亡)都满足。
##
## ③ **携带者阵亡 ⇒ 飞行物立刻消失, 但【已经留下的毒雾照常活满 FOG_LIFE(6) 秒】。**
##    规格只说"飞行物也阵亡", 没说毒雾。毒雾是已经落地的东西, 让它按自己的寿命散掉更自然,
##    也避免"最后一击把整片场地瞬间清空"的突兀。★这要求毒雾的推进【不依赖携带者】——
##    所以本系统的 `tick` 挂在每帧都会跑的 `RelicSynergySystem.tick` 上, 不是挂在携带者的
##    `_tick_eq_intervals` 上(那条路携带者一死就再也不跑, 毒雾会永远定格在原地)。
##
## ④ **剧毒缓速的 −2% 移速走 `move_perm` 通道, 不走两条减速通道。**
##    契约 §4 警告减速有两条并行通道: `slow_until`/`slow_mag` 与 `spd_move_mult`+`spd_dbf_until`,
##    **两条都是单槽**(RealtimeBattle3DScene.gd:2394 各取一个字段) ⇒ 剧毒缓速一旦占了槽,
##    冰冻/岩浆/冰川那些减速就会互相覆盖, 谁后写谁赢。而剧毒缓速是**长期渐变的叠层**,
##    占着单槽等于把别人的减速吞掉。
##    `move_perm` 是**乘法永久通道**(equip_stats_apply.gd:131 唯一写入点, spawn 期写一次、
##    之后全场不变) ⇒ 我可以精确记住"没有剧毒缓速时它是多少"再整体重写, 不漂移、不打架。
##    ★−1% 魔抗走 `buffs` 的 `mr` 百分比区(`_recalc_stats` 的唯一写入点), 同理不去各处伤害公式里乘。
##
## ══════════════════════════════════════════════════════════════════════
##  ★地雷对照(CLAUDE.md)
## ══════════════════════════════════════════════════════════════════════
## · §3.2 **不拿单位字典当 Dictionary 的键**: 毒雾按【整数 did】分组, 不按 owner 字典分组;
##   一切单位比较走 `is_same`。
## · §3.4 `_t` 跨路累加永不重置: 本系统所有计时全用**自己累加的 delta**(`_beat` / `d["leg_t"]` /
##   `f["t"]` / `_vslow_idle`), 一个都没读 `battle._t` 当起点。
## · 契约 §5.6 **随机必须走已播种的 RNG**: 选目标走 `battle._battle_rng`(`rng_discipline` 会抓裸 randf)。
## · 换路: `RelicSynergySystem.clear()`(dual_lane_flow.gd:467 的真入口)会调本系统 `clear_all()`。

const VFX := preload("res://scripts/scenes/battle/venom_drone_vfx.gd")

## ★装备 id 与逐星数值【就近声明】—— tooltip_number_audit 要求文案里的 "a/b/c"
##   能在该装备 id 字面量附近(±2500 字符)找到同样的三元数组。
const IID := "p2eq_092"
## 毒雾每次结算施加的中毒层数(逐星)
const POISON_STACKS := [3, 5, 8]   # 用户 2026-08-13 加强(原 2/3/5)

## 一切节拍都是 0.25 秒(规格): 留毒雾 / 毒雾结算 / 剧毒缓速掉层
const BEAT := 0.25
## 毒雾寿命(秒) —— 本应与 VFX 的 FOG_LIFE 同值, 此处故意写死字面量(门禁要能验两侧一致)。
## ⚠★★**当前两侧不一致**: `scripts/scenes/battle/venom_drone_vfx.gd` 的 `FOG_LIFE` 还是 **4.0**,
##   2026-08-13 只把这一侧加强到 6.0。后果(读代码得出, 不是推测): `_in_any_fog()` 走
##   `VFX.fog_radius(t)`, 而那边 `t >= FOG_LIFE(4.0)` 直接返回 0 ⇒ 每团毒雾**只上 4 秒的毒**,
##   却在本文件 `_fogs` 里留到 6 秒 —— 最后 2 秒是空转的死团(也不画边缘)。修它要动 scenes/ 侧。
const FOG_LIFE := 6.0   # 毒雾停留(秒) —— 用户 2026-08-13 加强(原 4.0)
## 剧毒缓速: 上限 / 每层减移速 / 每层减魔抗 / 多久不刷新开始掉层
const VSLOW_CAP := 20
const VSLOW_MOVE_PER := 0.02
const VSLOW_MR_PER := 0.01
const VSLOW_GRACE := 1.5

## "飞过目标到达它的对面落点": 落点在目标【身后】这么远(码)。
## ★龟的分离半径 SEP_RADIUS=92、近战射程 70 ⇒ 现行 160 码 ≈ 1.7 个身位,
##   足够读出"它是穿过去的"而不是"贴着目标停下"。(初版取 260 码 ≈ 三个身位, 2026-08-13 收短。)
const OVERSHOOT := 160.0   # 过冲(码) —— 用户 2026-08-13 收短(原 260): 飞过头太远会让航线常从旁人头顶穿过
## 到落点多近算到达(码)
const ARRIVE_R := 40.0
## 一段航程的兜底超时(秒)。★Dubins 载具有最小转弯半径 —— 落点若正好落进转弯圆内,
##   数学上会绕着它转圈永远到不了。这条是那个退化情形的唯一出口, 不是"随便加的保险"。
const LEG_TIMEOUT := 8.0
## 落点/飞行物被钳进战场内缩这么多(码), 免得贴着边界打转
const ARENA_PAD := 40.0

var battle

## 活着的飞行物。每个: owner(携带者字典)/si/did/pos/hd/dest/leg_t/fog_acc/node
var _drones: Array = []
## 活着的毒雾。每个: did(哪只飞行物留的)/owner/si/t/pos/node
var _fogs: Array = []
## 建出来的脚环节点(记账用, 撤场一次性拔掉)
var _rings: Array = []

var _vfx
var _beat := 0.0
## 节拍序号 —— 用它给"这一拍被毒雾碰到过"打标记, **不拿单位字典当键**(§3.2)
var _beat_n := 0
var _next_did := 0


func _init(b) -> void:
	battle = b
	_vfx = VFX.new(b)


# ══════════════════════════════════════════════════════════════════
#  §纯函数 —— 门禁直接调, 不建节点、不等演出
# ══════════════════════════════════════════════════════════════════

## "飞过目标到达它的对面落点": 沿【来向】延长过目标 OVERSHOOT 码。
## ★纯几何, 门禁验终点而不是等飞行物飞到(CLAUDE.md §3.5 的 `_pirate_grapple_dest` 同款做法)。
static func overshoot_dest(from: Vector2, tgt: Vector2) -> Vector2:
	var dir: Vector2 = tgt - from
	if dir.length() < 1.0:
		dir = Vector2.RIGHT          # 退化: 已经贴在目标身上 → 随便挑一个方向穿出去
	return tgt + dir.normalized() * OVERSHOOT


## n 层剧毒缓速的移速倍率
static func vslow_move_mult(n: int) -> float:
	return 1.0 - VSLOW_MOVE_PER * float(clampi(n, 0, VSLOW_CAP))


## ★这里原有 `static func vslow_mr_mult(n)` (返回 1.0 - VSLOW_MR_PER*n)。删了:
##   ① 全仓零调用者(`.vslow_mr_mult(` / `"vslow_mr_mult"` / 裸名都是 0, 含 tests/)。
##   ② 它编码的是【乘算】口径, 而实装走的是 `_set_vslow` 里的 buffs 百分比区
##      (`{"stat":"mr", "amount": -VSLOW_MR_PER*nn, "pct": true}`) —— 加算。两者在有别的
##      百分比魔抗 buff 时结果不同, 留着就是一份会误导人的第二口径。
##   移速那半边保留 `vslow_move_mult`, 因为 `_set_vslow` 真的调它。


## 这只身上现有多少层剧毒缓速
static func vslow_stacks(u: Dictionary) -> int:
	return int(u.get("_vslow_n", 0))


# ══════════════════════════════════════════════════════════════════
#  §每帧驱动
# ══════════════════════════════════════════════════════════════════

## sim 是不是真的在跑。★`RelicSynergySystem.tick` 在 `_sim_step` 里是**无条件**调的
##   (RealtimeBattle3DScene.gd:2135, 在 frozen/时停/摆位 的分支之外), 所以这里要自己判 ——
##   不判的话摆位阶段飞行物就已经在场上飞、在给还没开打的敌人上毒了。
func sim_running() -> bool:
	if battle == null:
		return false
	if bool(battle._over) or bool(battle._edit_mode):
		return false
	if str(battle._dl_state) == "place":
		return false
	if battle._dl_sys != null and battle._dl_sys._dl_is_present():
		return false
	return true


## 每帧。★接线点: `RelicSynergySystem.tick()`(遗物羁绊的每帧入口, `_sim_step` 里无条件调)。
##   为什么不是携带者的 `_tick_eq_intervals`: 见文件头判断 ③ —— 携带者一死那条路就不跑了,
##   而毒雾必须继续活满 FOG_LIFE(6) 秒。
func tick(delta: float) -> void:
	if not sim_running():
		return
	var dt: float = maxf(delta, 0.0)
	if dt <= 0.0:
		return
	_tick_drones(dt)
	_tick_fogs(dt)
	_beat += dt
	while _beat >= BEAT:
		_beat -= BEAT
		_on_beat()
	_tick_rings()


## 飞行物: 转向(Dubins 惯性) → 前进 → 每 0.25 秒在路径上留一团毒雾。
func _tick_drones(dt: float) -> void:
	var keep: Array = []
	for d in _drones:
		var o = d["owner"]
		# 规格: 携带者阵亡 → 飞行物也阵亡(每帧判, 不等 0.25 秒的重扫)
		if not (o is Dictionary) or not (o as Dictionary).get("alive", false):
			_free_drone(d)
			continue
		d["leg_t"] = float(d["leg_t"]) + dt
		var pos: Vector2 = d["pos"]
		## 目标还活着 ⇒ 每帧按它【当前】位置重算落点(整段实时跟随); 死了/没有就沿用上次的。
		var _tg = d.get("tgt", null)
		if _tg is Dictionary and (_tg as Dictionary).get("alive", false):
			d["tgt_pos"] = (_tg as Dictionary)["pos"]
			d["dest"] = _clamp_arena(overshoot_dest(
				d.get("leg_p0", pos) as Vector2, (_tg as Dictionary)["pos"] as Vector2))
		var dest: Vector2 = d["dest"]
		if pos.distance_to(dest) <= ARRIVE_R or float(d["leg_t"]) >= LEG_TIMEOUT:
			_new_leg(d)
			dest = d["dest"]
		var want: float = (dest - pos).angle()
		d["hd"] = VFX.steer(float(d["hd"]), want, dt)
		var hd: float = d["hd"]
		pos += Vector2(cos(hd), sin(hd)) * VFX.DRONE_SPEED * dt
		d["pos"] = _clamp_arena(pos)
		d["age"] = float(d["age"]) + dt
		d["fog_acc"] = float(d["fog_acc"]) + dt
		while float(d["fog_acc"]) >= BEAT:
			d["fog_acc"] = float(d["fog_acc"]) - BEAT
			_drop_fog(d)
		_vfx.apply_drone(d["node"], d["pos"], float(d["hd"]), float(d["age"]))
		keep.append(d)
	_drones = keep


## 毒雾: 推进寿命 + 到期收干净。★推进【不依赖携带者是否活着】(判断 ③)。
func _tick_fogs(dt: float) -> void:
	var keep: Array = []
	for f in _fogs:
		f["t"] = float(f["t"]) + dt
		if float(f["t"]) >= FOG_LIFE:
			var n = f.get("node", null)
			if is_instance_valid(n):
				n.queue_free()
			continue
		_vfx.apply_fog(f.get("node", null), float(f["t"]))
		keep.append(f)
	_fogs = keep


## 脚环: 每帧跟位置(网格只在层数变化时重建, 见 VenomDroneVfx.apply_ring)。
func _tick_rings() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var n: int = int(u.get("_vslow_n", 0))
		var r = u.get("_vslow_ring", null)
		if n <= 0 or not u.get("alive", false):
			if is_instance_valid(r):
				r.queue_free()
				_erase_node(r)
			if u.has("_vslow_ring"):
				u.erase("_vslow_ring")
			continue
		if not is_instance_valid(r):
			r = _vfx.make_ring()
			if r == null:
				continue
			u["_vslow_ring"] = r
			_rings.append(r)
		_vfx.apply_ring(r, u["pos"], n)


# ══════════════════════════════════════════════════════════════════
#  §0.25 秒节拍
# ══════════════════════════════════════════════════════════════════

## 一拍做三件事, **顺序不能换**:
##   ① 重扫携带者(补建/撤走飞行物)
##   ② 毒雾场结算(中毒层 + 剧毒缓速 +1, 并给这一拍碰到的单位打上标记)
##   ③ 没被碰到的单位累计"空闲时长", 满 1.5 秒开始每拍掉一层
## ②③ 反过来的话, 这一拍刚被上毒的单位会先被判成"空闲"。
func _on_beat() -> void:
	_beat_n += 1
	_rescan_carriers()
	_apply_fog_field()
	_decay_vslow()


## 按【携带者】重扫: 该有几只飞行物就有几只(同一只龟带两件 = 两只)。
func _rescan_carriers() -> void:
	var keep: Array = []
	for d in _drones:
		var o = d["owner"]
		var live: bool = (o is Dictionary) and (o as Dictionary).get("alive", false)
		if live and battle._arr_has_unit(battle._units, o) and _count_item(o) > 0:
			keep.append(d)
		else:
			_free_drone(d)
	_drones = keep
	for u in battle._units:
		if not (u is Dictionary) or not u.get("alive", false):
			continue
		var want: int = _count_item(u)
		if want <= 0:
			continue
		var have := 0
		for d in _drones:
			if is_same(d["owner"], u):
				have += 1
		while have < want:
			_spawn_drone(u, _star_of(u))
			have += 1


## 毒雾场结算: **按 did 分组**(每只飞行物的毒雾算一片场), 每片场对每个敌人每拍施加一次。
## ★不拿 owner 字典当键(§3.2) —— did 是整数。
func _apply_fog_field() -> void:
	if _fogs.is_empty():
		return
	var groups: Dictionary = {}
	for f in _fogs:
		var did: int = int(f["did"])
		if not groups.has(did):
			groups[did] = []
		(groups[did] as Array).append(f)
	for did in groups.keys():
		var arr: Array = groups[did]
		var head: Dictionary = arr[0]
		var owner = head["owner"]
		if not (owner is Dictionary):
			continue
		var si: int = int(head["si"])
		var stacks: int = POISON_STACKS[clampi(si, 0, 2)]
		# ★AOE 语义走 _enemies_of 不走 _pick_enemies_of: 毒雾是"范围扫到谁算谁"
		#   (battle_targeting.gd §PICK-TARGET 的用法铁律: 定向选靶才用 _pick_)。
		for e in battle._targeting._enemies_of(owner):
			if not _in_any_fog(arr, e["pos"]):
				continue
			battle._damage._apply_dot_stacks(e, "poison", stacks, owner)
			add_vslow(e, 1)


## 这一拍没被任何毒雾碰到的: 空闲累计 +0.25 秒; 满 1.5 秒后**每拍掉一层**。
## ★"1.5 秒"用**拍数**累加而不是拿 `battle._t` 相减: 0.25 是二进制精确值, 6 拍 = 1.5 精确,
##   拿浮点时刻相减会在边界上摇摆(第 6 拍到底掉不掉层要看运气)。
func _decay_vslow() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var n: int = int(u.get("_vslow_n", 0))
		if n <= 0:
			continue
		if int(u.get("_vslow_touch", -1)) == _beat_n:
			continue
		var idle: float = float(u.get("_vslow_idle", 0.0)) + BEAT
		u["_vslow_idle"] = idle
		if idle < VSLOW_GRACE:
			continue
		_set_vslow(u, n - 1)


# ══════════════════════════════════════════════════════════════════
#  §剧毒缓速
# ══════════════════════════════════════════════════════════════════

## 给这只加 n 层剧毒缓速(封顶 20), 并刷新"最近一次被施加"的时刻。
func add_vslow(u: Dictionary, n: int) -> void:
	if not u.get("alive", false) or n <= 0:
		return
	u["_vslow_touch"] = _beat_n
	u["_vslow_idle"] = 0.0
	_set_vslow(u, int(u.get("_vslow_n", 0)) + n)


## 把层数写成真实属性变化。移速走 move_perm(乘法永久通道), 魔抗走 buffs 的百分比区。
## ★`_vslow_mp0` 记的是"没有剧毒缓速时的 move_perm" —— 每次都从它重算, 不做增量,
##   所以反复加减层数不会有浮点漂移(增量式那种写法叠 200 次就飘了)。
func _set_vslow(u: Dictionary, n: int) -> void:
	var nn: int = clampi(n, 0, VSLOW_CAP)
	if not u.has("_vslow_mp0"):
		u["_vslow_mp0"] = float(u.get("move_perm", 1.0))
	var base: float = float(u["_vslow_mp0"])
	if nn <= 0:
		u["_vslow_n"] = 0
		u["move_perm"] = base
		u.erase("_vslow_mp0")
		u.erase("_vslow_idle")
	else:
		u["_vslow_n"] = nn
		u["move_perm"] = base * vslow_move_mult(nn)
	# 魔抗: 只留一条本效果自己的百分比 buff, 每次重写(不 append 第二条)
	var kept: Array = []
	for b in u.get("buffs", []):
		if not bool((b as Dictionary).get("_vslow", false)):
			kept.append(b)
	if nn > 0:
		kept.append({
			"stat": "mr", "amount": -VSLOW_MR_PER * float(nn), "pct": true,
			# ★不设自然到期: 掉层完全由上面的 1.5 秒规则管。给一个远期 until 只是为了
			#   不被 `_tick_unit` 的 buff 过期清理顺手删掉(那里判的是 `_t < b.until`)。
			"until": float(battle._t) + 86400.0, "_vslow": true,
		})
	u["buffs"] = kept
	battle._recalc_stats(u)


# ══════════════════════════════════════════════════════════════════
#  §飞行物生老病死
# ══════════════════════════════════════════════════════════════════

func _spawn_drone(u: Dictionary, star: int) -> void:
	var d := {
		"owner": u,
		"si": clampi(star, 1, 3) - 1,
		"did": _next_did,
		"pos": _clamp_arena(u["pos"]),
		"hd": 0.0,
		"dest": _clamp_arena(u["pos"]),
		"leg_t": 0.0,
		"fog_acc": 0.0,
		"age": 0.0,
		"legs": 0,
		"node": _vfx.make_drone(),
	}
	_next_did += 1
	_new_leg(d)
	d["hd"] = (Vector2(d["dest"]) - Vector2(d["pos"])).angle()
	_drones.append(d)


## 选下一段航程: **随机目标** → 落点 = 穿过它落到对面。
## ★随机必须走已播种的 `battle._battle_rng`(契约 §5.6; 裸 randi 会被 rng_discipline 判红,
##   也会让 verify_battle_determinism 的同种子指纹对不上)。
## ★选靶走 `_pick_enemies_of`: 这是"挑一个目标瞄准", battle_targeting.gd §PICK-TARGET
##   的用法铁律要求走它(排除训龟大师 / 不可选中 / 未破围栏的蛋)。
func _new_leg(d: Dictionary) -> void:
	d["leg_t"] = 0.0
	var owner = d["owner"]
	var cands: Array = []
	if owner is Dictionary:
		cands = battle._targeting._pick_enemies_of(owner)
	if cands.is_empty():
		# 没有可选目标 → 朝战场中心巡航(仍然会留毒雾, 但不会卡住)
		d["dest"] = battle.ARENA.position + battle.ARENA.size * 0.5
		return
	var t: Dictionary = cands[battle._battle_rng.randi() % cands.size()]
	d["tgt_pos"] = t["pos"]
	## ★★整段【持续跟着目标】重算落点(用户 2026-08-13:「人家都往别的地方走了,
	##   飞行物却飞到别的地方」)。原来只在起段那一刻快照一次目标位置, 中途目标走开
	##   就一路飞向空地 —— 这也是"看起来在冲大师/蛋"的来源之一(航线从他们头顶穿过)。
	##   ⚠ 存的是目标【单位字典的引用】; 比较一律 `is_same`, 绝不拿它当 key(CLAUDE.md §3.2)。
	d["tgt"] = t
	## ★过冲相对【起段位置】算, 不是相对当前位置 —— 相对当前算的话落点会随飞行一直往后退,
	##   永远到不了、也就永远不换段。
	d["leg_p0"] = Vector2(d["pos"])
	d["dest"] = _clamp_arena(overshoot_dest(d["leg_p0"], t["pos"]))
	d["legs"] = int(d.get("legs", 0)) + 1


func _drop_fog(d: Dictionary) -> void:
	var f := {
		"did": int(d["did"]),
		"owner": d["owner"],
		"si": int(d["si"]),
		"t": 0.0,
		"pos": Vector2(d["pos"]),
		"node": _vfx.make_fog(d["pos"]),
	}
	_fogs.append(f)


func _free_drone(d: Dictionary) -> void:
	var n = d.get("node", null)
	if is_instance_valid(n):
		n.queue_free()
	d["node"] = null


# ══════════════════════════════════════════════════════════════════
#  §撤场
# ══════════════════════════════════════════════════════════════════

## 换路 / 清场。接线点: `RelicSynergySystem.clear()`(dual_lane_flow.gd:467 的换路真入口)。
## 返回真的 free 掉几个节点(门禁用它当分母)。
##
## ★三样都要清 —— 飞行物 + 毒雾 + 所有单位身上的剧毒缓速层。
##   只清前两样的话, 单位身上的 move_perm/mr buff 会带进下一路(这一路的敌人已经换了一批,
##   但**同一批单位字典在决胜局是会被沿用的**), 那正是本项目栽过的"写了没人清"。
func clear_all() -> int:
	var freed := 0
	for d in _drones:
		if is_instance_valid(d.get("node", null)):
			d["node"].queue_free(); freed += 1
	_drones.clear()
	for f in _fogs:
		if is_instance_valid(f.get("node", null)):
			f["node"].queue_free(); freed += 1
	_fogs.clear()
	for r in _rings:
		if is_instance_valid(r):
			r.queue_free(); freed += 1
	_rings.clear()
	for u in battle._units:
		if u is Dictionary and int((u as Dictionary).get("_vslow_n", 0)) > 0:
			_set_vslow(u, 0)
		if u is Dictionary:
			(u as Dictionary).erase("_vslow_ring")
			(u as Dictionary).erase("_vslow_idle")
			(u as Dictionary).erase("_vslow_touch")
	_beat = 0.0
	return freed


# ══════════════════════════════════════════════════════════════════
#  §小工具
# ══════════════════════════════════════════════════════════════════

func _count_item(u: Dictionary) -> int:
	var n := 0
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == IID:
			n += 1
	return n


func _star_of(u: Dictionary) -> int:
	var s := 1
	for e in u.get("equips", []):
		if e is Dictionary and str((e as Dictionary).get("id", "")) == IID:
			s = maxi(s, int((e as Dictionary).get("star", 1)))
	return s


## 这个点在不在这一片场的任意一团毒雾里。半径用 `VenomDroneVfx.fog_radius(t)` ——
## **与渲染用的是同一条浓度等值线**(见 vfx 文件头的"尺子必须匹配被测概念")。
func _in_any_fog(arr: Array, p: Vector2) -> bool:
	for f in arr:
		var r: float = VFX.fog_radius(float(f["t"]))
		if r > 0.0 and (Vector2(f["pos"]) - p).length() <= r:
			return true
	return false


func _clamp_arena(p: Vector2) -> Vector2:
	var r: Rect2 = battle.ARENA
	return Vector2(
		clampf(p.x, r.position.x + ARENA_PAD, r.end.x - ARENA_PAD),
		clampf(p.y, r.position.y + ARENA_PAD, r.end.y - ARENA_PAD))


func _erase_node(n) -> void:
	for i in range(_rings.size()):
		if is_same(_rings[i], n):
			_rings.remove_at(i)
			return
