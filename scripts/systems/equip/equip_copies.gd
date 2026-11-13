class_name EquipCopies
extends RefCounted
## 同名装备带多件「各自生效」的份号上下文(2026-11-13 用户「两件相同装备…各自生效各自的效果…统计那肯定是分开」)。
## 方案书 docs/plans/20261113-同名装备多件各自生效.md。
## ★EquipSystem 里有同名转发(`battle._equip_sys.key_of` / `ck_set` / `each_copy` …), 调用方不用改。
##
## 份号: 同一只龟身上同名装备按装备栏顺序编号, 第 1 件 = 原 id, 第 2 件起 =「id#2」「id#3」(EquipCk.ck_name)。
## 用法:
##   · 逐件循环: 循环前 save(), 每件开头 set_e(u, e), 循环后 restore(快照)。
##   · 效果代码取状态 / 记账一律 key_of(u, "p2eq_xxx"): 只在「同一只龟 + 同一种装备」时换成当前这一件的份号, 其余原样 ⇒ 单件逐字不变。
##   · 在途效果(箭雨 / 碑 / 召唤物…)入表时记下 key_of 的结果, 结算时 enter(u, ck) … leave(返回值)。
##   · 批系统每帧推进: each_copy(u, iid, fn) —— 每一份各跑一次 fn(星级下标), 份号 / 统计 / 龟身字段都切好。

var battle
var _u = null
var _k: String = ""


func _init(b) -> void:
	battle = b


func save() -> Array:
	return [_u, _k]


func restore(p: Array) -> void:
	_u = p[0]
	_k = str(p[1])


func set_e(u, e) -> String:
	_u = u
	_k = EquipCk.ck_of(u, e) if u is Dictionary else ""
	return _k


func enter(u, ck: String) -> Array:
	var p: Array = [_u, _k, battle._equip_sys.tally.push(u, ck)]
	_u = u
	_k = ck
	return p


func leave(p: Array) -> void:
	_u = p[0]
	_k = str(p[1])
	battle._equip_sys.tally.pop(p[2])


func key_of(u, iid: String) -> String:
	if _k != "" and is_same(u, _u) and EquipCk.base_id(_k) == iid:
		return _k
	return iid


## 当前份号上下文正是 (u, iid) 的某一件 ⇒ 那一件的星级下标(0~2); 否则 -1(调用方按原口径取)。
func copy_si(u, iid: String) -> int:
	if _k == "" or not is_same(u, _u) or EquipCk.base_id(_k) != iid:
		return -1
	for c in EquipCk.copies(u, iid):
		if str(c[0]) == _k:
			return int(c[1]) - 1
	return -1


## 某件装备按份逐个跑 fn(si)。单件 = 跑一次、与原来逐字相同。返回跑了几份。
func each_copy(u: Dictionary, iid: String, fn: Callable) -> int:
	var n := 0
	for c in EquipCk.copies(u, iid):
		var sv: Array = uf_in(u, str(c[0]))
		var cp: Array = enter(u, str(c[0]))
		fn.call(int(c[1]) - 1)
		leave(cp)
		uf_out(u, sv)
		n += 1
	return n


## ── 龟身字段换装 ── 批系统把某件装备的状态写在龟身上(字段前缀见 UF)的, 第 2 件起在调用期间换成这一件自己的一套
##   (存 eq_state[ck]["_uf"]), 调完换回第一件的。第 1 件 / 没登记的件: 什么都不做。
const UF := {"p2eq_078": ["_g078"], "p2eq_081": ["_b81"], "p2eq_082": ["_b82"], "p2eq_083": ["_b83"],
	## 084 手半剑: 形态 / 自然射程影子 / 原技能表 / 十字斩锁定两件共用(改形态的件, 技能只能有一个); 星级与「给过多少」各件一份 ⇒ 数值加成各给各的
	"p2eq_084": ["_b84_si", "_b84_hp_given", "_b84_atk_given", "_b84_ls_given", "_b84_amp_given", "_b84_dr_given", "_b84_conv", "_b84_mult"],
	"p2eq_085": ["_piezo"], "p2eq_086": ["_sext"], "p2eq_087": ["_dive"], "p2eq_091": ["_scute"],
	"p2eq_060": ["_parasol"], "p2eq_064": ["_bladder"]}


func uf_in(u: Dictionary, ck: String) -> Array:
	var base: String = EquipCk.base_id(ck)
	if base == ck or not UF.has(base) or not (u.get("eq_state", null) is Dictionary):
		return []
	var pre: Array = UF[base]
	var saved: Dictionary = {}
	for k in u.keys():
		for p in pre:
			if str(k).begins_with(p):
				saved[k] = u[k]
				break
	for k in saved:
		u.erase(k)
	var mine: Dictionary = ((u["eq_state"] as Dictionary).get(ck, {}) as Dictionary).get("_uf", {})
	for k in mine:
		u[k] = mine[k]
	return [ck, pre, saved]


func uf_out(u: Dictionary, sv: Array) -> void:
	if sv.is_empty():
		return
	var pre: Array = sv[1]
	var mine: Dictionary = {}
	for k in u.keys():
		for p in pre:
			if str(k).begins_with(p):
				mine[k] = u[k]
				break
	for k in mine:
		u.erase(k)
	for k in (sv[2] as Dictionary):
		u[k] = sv[2][k]
	var st: Dictionary = (u["eq_state"] as Dictionary).get(sv[0], {})
	st["_uf"] = mine
	u["eq_state"][sv[0]] = st
