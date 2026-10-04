class_name EquipTally
extends RefCounted
## 每件装备的本局统计(用户 2026-10-04 ④「每件装备（大部分）需要加上统计量，比如本局总治疗量，
## 本局总伤害量，到时候每个装备慢慢看要怎么显示统计吧」)。方案书 docs/plans/20261004-五件新需求.md §4.5 / §8 ④。
##
## ★★纯记账 —— 不读任何战斗状态做决定、不碰 RNG、不改任何会影响结算的字段。
##   确定性门禁(verify_determinism_b/cross)与回放(verify_replay_roundtrip)靠这条不变。
##
## ── 数据结构 ──────────────────────────────────────────────────────────────
## 单位身上(与 `_st_dealt` 等同层、同口径: 一路一份, 换路随单位字典一起换新):
##   u["_st_eq"] = { "p2eq_088": {"phy": 120.0, "mag": 0.0, "tru": 30.0, "heal": 0.0, "shield": 400.0}, ... }
##   · 键 = 装备 id(同一携带者带两件同 id 的合并成一行 —— 与 eq_state 按 id 记的口径一致)
##   · 记在【携带者】身上(不是受益者): 一件群奶装备给队友回的血, 记在带它的那只龟的这件装备下
##   · phy/mag/tru = 造成伤害(与 `_st_dealt` 同口径: 减伤后、护盾吸收前)
##   · heal = 实际回血(与 `_st_heal` 同口径: 超出满血不计) / shield = 实际获盾(同 `_st_shield`)
## 结算快照行(`battle._st_row`)里摊平成纯标量键(快照行必须纯标量, verify_misc_guards):
##   "_st_eq|p2eq_088|phy": 120 ...      —— 用 `row_fields()` 写, `from_row()` 读回成上面那种嵌套表
## 合计页(`battle_hud._st_merge_all`)按键逐个累加 —— 与 `_st_dealt` 一样「本局 = 各路之和」。
##
## ── 归因(「是哪件装备打的」) ───────────────────────────────────────────────
## ① 上下文: 装备效果分发处(`_cur_eq_item = iid` 的那几处 + 各批系统自己的入口)调 `push(携带者, iid)`,
##    结束调 `pop()`。期间产生的伤害/治疗/护盾记给这件。
##    ★为什么不直接读 `battle._cur_eq_item`: 它被各处「用完清空」而不是「还原上一个」,
##      嵌套时会把外层抹掉; 改它的语义又会改到盾羁绊 9 档的圣光转化(=改战斗结果)。所以另起一份。
## ② 召唤物: 在装备上下文里召出来的召唤物打上 `_eq_src`/`_eq_owner`, 它之后的所有伤害都记给那件。
## ③ DoT: 层数式 DoT(灼烧/中毒/流血)是一个池子, 按「谁加进来的层」分份额, 每跳按份额分摊;
##    flat DoT(诅咒等)施加时在条目上打标。
## ④ 归因不到装备的(普攻本体、技能本体)不记 —— 用户要的是「装备」的账。
## ⑤ 护栏: 伤害只记给「敌对目标」、治疗/护盾只记给「非敌对目标」—— 上下文里混进别人的反应
##    (例: 对面荆棘反伤没开自己的上下文)时宁可漏记也不记错人。

const KEYS := ["phy", "mag", "tru", "heal", "shield"]
const ROW_PREFIX := "_st_eq|"

var battle
var _owner = null          # 当前上下文的携带者(单位字典; 只做引用, 从不当键、从不 ==)
var _iid: String = ""      # 当前上下文的装备 id
## DoT 结算标记(由 DoT 结算处设、本类用完即清): 只在 `dot_mode` 为真的那一次记账里生效
var dot_mode: bool = false
var dot_type: String = ""
var dot_u = null
var dot_flat = null


func _init(b) -> void:
	battle = b


# ─────────────────────────────── 上下文 ───────────────────────────────

## 进入「某携带者的某件装备」上下文。返回旧上下文, 交给 pop() 还原(可嵌套)。
func push(owner, iid: String) -> Array:
	_flush()
	var prev: Array = [_owner, _iid]
	_owner = owner
	_iid = iid
	return prev


func pop(prev: Array) -> void:
	_flush()
	_owner = prev[0]
	_iid = str(prev[1])


## 直接切到某个捕获下来的上下文(延时队列/弹道落地时用; 不是 [owner, iid] 就切成「无」)。
func use(tl) -> void:
	_flush()
	if tl is Array and (tl as Array).size() == 2:
		_owner = tl[0]
		_iid = str(tl[1])
	else:
		_owner = null
		_iid = ""


## 批系统的每单位 tick 不分件派发(一个系统管好几件) ⇒ 切到「这只龟身上属于该系统的第一件」, 没有就切成「无」。
##   ★已知近似: 同一只龟带同一系统的两件不同装备时, 这一路 tick 的产出全记在先出现的那件上。
const SPIRIT_IDS := ["p2eq_060", "p2eq_061", "p2eq_062", "p2eq_063", "p2eq_064"]
const POTION_IDS := ["p2eq_065", "p2eq_066", "p2eq_067", "p2eq_068"]
const FOOD_IDS := ["p2eq_069", "p2eq_070", "p2eq_071", "p2eq_072"]
func use_first_of(u: Dictionary, ids: Array) -> void:
	for e in u.get("equips", []):
		if e is Dictionary and ids.has(str((e as Dictionary).get("id", ""))):
			use([u, str(e["id"])])
			return
	use(null)


## 批④ 版: 系统 → 它管的装备 id 由 `EquipSystem.B4_OWNER` 路由表决定(不在这里抄一份)。
func use_b4(u: Dictionary, sys) -> void:
	for e in u.get("equips", []):
		if e is Dictionary and battle._equip_sys._b4(str((e as Dictionary).get("id", ""))) == sys:
			use([u, str(e["id"])])
			return
	use(null)


## 当前上下文快照(给要跨 await / 进延时队列的效果捕获, 落地时 use() 或 push(c[0], c[1]))。
func capture() -> Array:
	return [_owner, _iid]


## ★延时队列 `_pending_shots` 没有统一入口(四十多处各自 append 字典), 逐处去改必漏一处。
##   ⇒ 换个方向: 上下文每次【切换之前】, 把队尾还没盖章的条目盖上「切换前那个上下文」——
##   条目总是追加在队尾, 所以没盖章的永远是连续的一段尾巴, 碰到第一个盖过章的就停。
##   落地时 `BattleBallistics._step_pending_shots` 用 use() 切回去。弹道走唯一入口 `_push_proj`, 在那里直接盖。
func _flush() -> void:
	var ps: Array = battle._pending_shots
	var i: int = ps.size() - 1
	while i >= 0:
		var d = ps[i]
		if not (d is Dictionary) or (d as Dictionary).has("_tl"):
			break
		d["_tl"] = [_owner, _iid]
		i -= 1


## 每个 sim 步开头清一次(同 `_cur_eq_item` 的每步重置): 防某条路漏了 pop 把上下文漏进下一步。
func reset() -> void:
	_owner = null
	_iid = ""
	_flush()
	dot_mode = false
	dot_type = ""
	dot_u = null
	dot_flat = null


## 给召唤物/flat DoT 条目打来源标(在装备上下文里创建的才打)。返回原对象, 便于就地包一层。
## who: 召唤者/施加者 —— 只有它就是上下文里的携带者时才打(别人在这一刻召的东西不算这件装备的)。
## ★058 炮台 / 032 骷髅由主场景登场时直调召唤(不在任何装备上下文里) ⇒ 按召唤物种类认领。
const KIND_EQ := {"turret": "p2eq_058", "skeleton": "p2eq_032"}
func tag(d: Dictionary, who = null) -> Dictionary:
	if _iid == "" and who is Dictionary and KIND_EQ.has(str(d.get("summon_kind", ""))):
		d["_eq_src"] = KIND_EQ[str(d["summon_kind"])]
		d["_eq_owner"] = who
		return d
	if who != null and not is_same(who, _owner):
		return d
	if _iid != "" and _owner is Dictionary:
		d["_eq_src"] = _iid
		d["_eq_owner"] = _owner
	return d


## 这一笔该记给谁: [携带者, iid] 或 []。
func _attrib(src) -> Array:
	var ctx_ok: bool = _iid != "" and _owner is Dictionary
	if ctx_ok and (src == null or is_same(src, _owner)):
		return [_owner, _iid]
	if src is Dictionary and str((src as Dictionary).get("_eq_src", "")) != "" and (src as Dictionary).get("_eq_owner", null) is Dictionary:
		return [src["_eq_owner"], str(src["_eq_src"])]
	if ctx_ok and src is Dictionary and is_same((src as Dictionary).get("summon_owner", null), _owner):
		return [_owner, _iid]
	return []


func _add(owner: Dictionary, iid: String, key: String, amt: float) -> void:
	if iid == "" or amt <= 0.0:
		return
	var t: Dictionary = owner.get("_st_eq", {})
	var r: Dictionary = t.get(iid, {})
	r[key] = float(r.get(key, 0.0)) + amt
	t[iid] = r
	owner["_st_eq"] = t


func _hostile(a: Dictionary, b: Dictionary) -> bool:
	return bool(battle._is_hostile(a, b))


# ─────────────────────────────── 记账入口 ───────────────────────────────

## 伤害(两条伤害路共用的 `_record_buckets` / `_record_extra_true` 里调 —— CLAUDE.md §3.3)。
## bkt ∈ phy/mag/tru(其它桶名按真实伤害记, 与 `_st_dealt_by_type` 的 dot 桶同源)。
func on_damage(src, u: Dictionary, amt: int, bkt: String) -> void:
	if amt <= 0:
		return
	var key: String = bkt if (bkt == "phy" or bkt == "mag") else "tru"
	if dot_mode:
		if dot_flat is Dictionary and is_same(dot_u, u):
			var fd: Dictionary = dot_flat
			dot_flat = null
			if str(fd.get("_eq_src", "")) != "" and fd.get("_eq_owner", null) is Dictionary and _hostile(fd["_eq_owner"], u):
				_add(fd["_eq_owner"], str(fd["_eq_src"]), key, float(amt))
			return
		if dot_type != "" and is_same(dot_u, u):
			var ty: String = dot_type
			dot_type = ""
			_dot_share_damage(u, ty, key, float(amt))
			return
	var a: Array = _attrib(src)
	if a.is_empty() or is_same(a[0], u) or not _hostile(a[0], u):
		return
	_add(a[0], str(a[1]), key, float(amt))


## 直接记一笔(调用方自己算好归属与数额时用; 例: 多件持续回复合成一次治疗, 按速率份额拆)。
func credit(owner: Dictionary, iid: String, key: String, amt: float) -> void:
	_add(owner, iid, key, amt)


## 实际回血(`_heal` 末尾调; 只认上下文 —— 治疗没有来源参数)。
func on_heal(u: Dictionary, got: float) -> void:
	if got <= 0.0 or _iid == "" or not (_owner is Dictionary):
		return
	if _hostile(_owner, u):
		return
	_add(_owner, _iid, "heal", got)


## 实际获盾(`_grant_shield` 末尾调)。盾羁绊 9 档圣光转化那一份不记(那是羁绊, 不是这件装备)。
func on_shield(u: Dictionary, got: float) -> void:
	if got <= 0.0 or _iid == "" or not (_owner is Dictionary):
		return
	if _hostile(_owner, u):
		return
	_add(_owner, _iid, "shield", got)


# ─────────────────────────────── 层数 DoT 份额 ───────────────────────────────
## u["_dot_eq"][type] = {"other": float, "list": [[携带者, iid, 份额], ...]}
## 份额与层数同量纲; 每次加层前先把旧份额按「当前层数 / 份额合计」缩放(层数每跳按比例衰减,
## 缩放后旧份额 == 现存层数), 池子空了就清零。

func on_dot_add(u: Dictionary, type: String, stacks: int, before: int, src) -> void:
	if stacks <= 0:
		return
	var all: Dictionary = u.get("_dot_eq", {})
	var p: Dictionary = all.get(type, {"other": 0.0, "list": []})
	var lst: Array = p.get("list", [])
	if before <= 0:
		p["other"] = 0.0
		lst = []
	else:
		var tot: float = float(p.get("other", 0.0))
		for e in lst:
			tot += float(e[2])
		if tot > 0.0:
			var k: float = float(before) / tot
			p["other"] = float(p.get("other", 0.0)) * k
			for e in lst:
				e[2] = float(e[2]) * k
		else:
			p["other"] = float(before)
	var a: Array = _attrib(src)
	if a.is_empty() or not _hostile(a[0], u):
		p["other"] = float(p.get("other", 0.0)) + float(stacks)
	else:
		var hit := false
		for e in lst:
			if is_same(e[0], a[0]) and str(e[1]) == str(a[1]):
				e[2] = float(e[2]) + float(stacks)
				hit = true
				break
		if not hit:
			lst.append([a[0], str(a[1]), float(stacks)])
	p["list"] = lst
	all[type] = p
	u["_dot_eq"] = all


func _dot_share_damage(u: Dictionary, type: String, key: String, amt: float) -> void:
	var p: Dictionary = (u.get("_dot_eq", {}) as Dictionary).get(type, {})
	var lst: Array = p.get("list", [])
	if lst.is_empty():
		return
	var tot: float = float(p.get("other", 0.0))
	for e in lst:
		tot += float(e[2])
	if tot <= 0.0:
		return
	for e in lst:
		if e[0] is Dictionary:
			_add(e[0], str(e[1]), key, amt * float(e[2]) / tot)


# ─────────────────────────────── 结算行 ───────────────────────────────

## 单位或快照行 → 摊平的纯标量键(给 `_st_row` 合并进行里)。对快照行幂等(原样拷回)。
static func row_fields(u: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var t = u.get("_st_eq", null)
	if t is Dictionary:
		for iid in (t as Dictionary).keys():
			var r: Dictionary = (t as Dictionary)[iid]
			for k in KEYS:
				var v: float = float(r.get(k, 0.0))
				if v > 0.0:
					out["%s%s|%s" % [ROW_PREFIX, str(iid), k]] = int(round(v))
	else:
		for k in u.keys():
			if str(k).begins_with(ROW_PREFIX):
				out[k] = int(u[k])
	return out


## 快照行/合计行 → 嵌套表 {iid: {phy, mag, tru, heal, shield}}(以后逐件做显示时读这个)。
static func from_row(row: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in row.keys():
		var ks: String = str(k)
		if not ks.begins_with(ROW_PREFIX):
			continue
		var parts: PackedStringArray = ks.substr(ROW_PREFIX.length()).split("|")
		if parts.size() != 2:
			continue
		var r: Dictionary = out.get(parts[0], {})
		r[parts[1]] = int(r.get(parts[1], 0)) + int(row[k])
		out[parts[0]] = r
	return out
