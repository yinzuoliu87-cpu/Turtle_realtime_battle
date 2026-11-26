class_name OtherworldSystem
extends RefCounted
## otherworld_system.gd —— 136 千面【里世界】(2026-11-26 · 方案书 docs/plans/20261125c-面具羁绊.md §3)
##
## 用户 11-25 夜 / 11-26:「开打第 8 秒随机拽取对面一个人进入一个新里世界…偷取属性」「决斗改为十二秒…从场上消失到另外一个里世界…
##   地图上需要有个按钮，可以调整观众的视角，从主地图切换到里世界」「同时拥有多个千面要拽人的时候，我们只开一个里世界…所有被牵连到的人都会到里世界来」
##   「里世界里面…只存在一方的队伍，另一方被打死完了之后，他们就会回到这个主世界」「偷的属性…在你进入里世界的时候开偷，然后一直持续到这个战场结束」
##
## ── 做法 ──────────────────────────────────────────────────────
## 里世界是一个「相位」, 不是另一块地: 被拽进去的单位原地挂 `_ow = true`, 位置不动。
##   · 敌我原语 `battle._is_hostile` 先过 `separated(a, b)` ⇒ 主世界与里世界互相不当敌人:
##     选目标、范围伤害(_enemies_of)、嘲讽全都自动隔开(全工程敌我判断只有这一个入口, 见 battle_targeting §HOSTILE)。
##   · 画面: 主世界视角下里世界的人隐去; 切到里世界视角只看得见里世界的人(battle_render 读 `battle._ow_view`)。
##   · 结束(12 秒到 / 一方在里世界里全灭): 所有人原地回到主世界, `_ow` 清掉。
## 偷属性: 每个千面携带者从它拽进来的那一个身上, 每秒偷 3/5/10% 攻击力、护甲、魔抗(按对方当前底数), 直接改两边的
##   base_atk / base_def / base_mr ⇒ 一直留到这个战场结束(换路整体重建单位字典, 自然清零)。
const OW_AT := 8.0
const OW_SEC := 12.0
const OW_STEAL := [0.03, 0.05, 0.10]
## 里世界那块地: 跟主岛一样大(技能射程 / 走位空间都不变), 往远处挪 OW_SHIFT 像素(镜头切过去才看得见)
const OW_SHIFT := Vector2(0.0, 2600.0)

var battle
var _carriers: Array = []     # {u, si, used}
var active := false
var t0 := 0.0
var members: Array = []       # 单位字典(is_same 比较, 不当键)
var pairs: Array = []         # {thief, victim, si, acc}
## 门禁量
var stat := {"pull": 0, "open": 0, "close": 0, "steal_ticks": 0}
var last_close_reason := ""


func _init(b) -> void:
	battle = b


## a 与 b 一个在里世界、一个在主世界 ⇒ 互相看不见
static func separated(a, b) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	return bool((a as Dictionary).get("_ow", false)) != bool((b as Dictionary).get("_ow", false))


func add_carrier(u: Dictionary, si: int) -> void:
	_carriers.append({"u": u, "si": si, "used": false})


func _in(u: Dictionary) -> bool:
	for m in members:
		if is_same(m, u):
			return true
	return false


func _enter(u: Dictionary) -> void:
	if _in(u):
		return
	u["_ow"] = true
	u["_ow_pos0"] = Vector2(u["pos"])
	u["pos"] = Vector2(u["pos"]) + OW_SHIFT   # 整体平移到里世界那块地(相对站位不变)
	u["_nav_path"] = PackedVector2Array()
	members.append(u)


func _leave(u: Dictionary) -> void:
	u["_ow"] = false
	if u.has("_ow_pos0"):
		u["pos"] = ArenaShape.clamp_in(Vector2(u["_ow_pos0"]), battle.ARENA)   # 回到进去之前的位置
		u.erase("_ow_pos0")
	u["_nav_path"] = PackedVector2Array()


static func ow_rect_of(arena: Rect2) -> Rect2:
	return Rect2(arena.position + OW_SHIFT, arena.size)


func _victim_for(c: Dictionary):
	var pool: Array = []
	for o in battle._units:
		if not (o is Dictionary) or not o.get("alive", false) or bool(o.get("_ow", false)):
			continue
		## 按阵营挑, 不走 _is_hostile: 携带者自己可能已被对面的千面拽进里世界, 那时 _is_hostile 会把主世界的人全隔开
		if str(battle._tamed_side(o)) == str(battle._tamed_side(c)) or bool(o.get("hijacked", false)) 				or bool(o.get("_isEgg", false)) or battle._is_untouchable(o) or o.get("_egg_fence", false):
			continue
		pool.append(o)
	if pool.is_empty():
		return null
	return pool[battle._battle_rng.randi() % pool.size()]


## 切换世界后, 指着另一个世界的目标一律放掉(下一帧重新索敌)
func _drop_cross_targets() -> void:
	for u in battle._units:
		if not (u is Dictionary):
			continue
		var t = u.get("target", null)
		if t is Dictionary and separated(u, t):
			u["target"] = null
		var tb = u.get("taunt_by", null)
		if tb is Dictionary and separated(u, tb):
			u["taunt_by"] = null
			u["taunt_until"] = 0.0


func tick(delta: float) -> void:
	var t := float(battle._t)
	var el: float = t - float(battle._sd_t0)
	for c in _carriers:
		var cu: Dictionary = c["u"]
		if bool(c["used"]) or not cu.get("alive", false) or el < OW_AT:
			continue
		c["used"] = true
		var v = _victim_for(cu)
		if not (v is Dictionary):
			continue
		if not active:
			active = true
			t0 = t
			ArenaShape.ow_rect = ow_rect_of(battle.ARENA)
			stat["open"] += 1
			if battle.get("_equip_sys") != null:
				battle._equip_sys._mask_sys._fx("ow_open", [])
		_enter(cu)
		_enter(v)
		pairs.append({"thief": cu, "victim": v, "si": int(c["si"]), "acc": 0.0})
		stat["pull"] += 1
		_drop_cross_targets()
		battle._equip_sys._mask_sys._fx("ow_pull", [cu, v])
	if not active:
		return
	for P in pairs:
		var th: Dictionary = P["thief"]
		var vi: Dictionary = P["victim"]
		if not th.get("alive", false) or not vi.get("alive", false) or not bool(th.get("_ow", false)) or not bool(vi.get("_ow", false)):
			continue
		P["acc"] = float(P["acc"]) + delta
		while float(P["acc"]) >= 1.0:
			P["acc"] = float(P["acc"]) - 1.0
			_steal(th, vi, float(OW_STEAL[int(P["si"])]))
	## 结束: 12 秒到 / 里世界里只剩一方
	var sides := {}
	for m in members:
		if m.get("alive", false):
			sides[str(battle._tamed_side(m))] = true
	if t - t0 >= OW_SEC:
		close("time")
	elif sides.size() < 2:
		close("wipe")


func _steal(th: Dictionary, vi: Dictionary, pct: float) -> void:
	stat["steal_ticks"] += 1
	for f in ["base_atk", "base_def", "base_mr"]:
		var amt: float = maxf(0.0, float(vi.get(f, 0.0))) * pct
		vi[f] = float(vi.get(f, 0.0)) - amt
		th[f] = float(th.get(f, 0.0)) + amt
	battle._recalc_stats(vi)
	battle._recalc_stats(th)
	battle._equip_sys._mask_sys._fx("ow_steal", [th, vi])


func close(reason: String) -> void:
	if not active:
		return
	active = false
	last_close_reason = reason
	stat["close"] += 1
	for m in members:
		if m is Dictionary:
			_leave(m)
	members.clear()
	pairs.clear()
	ArenaShape.ow_rect = Rect2()
	_drop_cross_targets()
	battle._equip_sys._mask_sys._fx("ow_close", [reason])


func clear_all() -> void:
	for m in members:
		if m is Dictionary:
			_leave(m)
	members.clear()
	pairs.clear()
	_carriers.clear()
	active = false
	ArenaShape.ow_rect = Rect2()
