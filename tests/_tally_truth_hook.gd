extends EquipTally
## _tally_truth_hook.gd —— 装备统计「逐笔对账」的记账钩(门禁 verify_eq_tally_truth 与探针 _probe_tally_truth / _probe_tally_real 共用)。
##
## 换掉 `battle._equip_sys.tally`: 每一笔伤害 / 治疗 / 护盾进账前抓一次脚本调用栈,
## 按「这一笔是谁的代码打出来的」独立判一个真值, 再记下 EquipTally 实际给了哪件装备多少。
## 真值判法(从结算函数往外走, 第一个命中的帧决定):
##   EQ    = 装备效果文件(scripts/systems/equip/, 不含羁绊 / 记账 / 属性套用)
##   REACT = 先碰到另一层 `_apply_damage_from` / `_apply_damage` / `_post_hit_hooks`
##           ⇒ 这一笔是「上一笔伤害的反应」(吸血、反伤、龟被动、羁绊)
##   SYN   = 羁绊文件
##   DEFER-<发射时的真值> = 弹道落地(发射那一刻同样判一次, 记在弹道字典上)
##   NONE  = 一路走到主循环都没碰到上面任何一种(普攻本体 / 技能本体)
##   DOT   = DoT 一跳(真值看层是谁加的: on_dot_add 那一刻同样判一次)

var events: Array = []          # [{kind, truth, amt, key, credited: {iid|key: amt}, where, stk}]
var direct: Array = []          # credit() 直记(不经 on_damage/on_heal/on_shield)
var dot_adds: Array = []        # [{type, stacks, truth, tgt_id}]
var _cur = null
var _pend_label = null          # 刚发射、还没贴到弹道字典上的真值
var _cur_proj_label := ""       # 正在落地的那发弹道的真值

const DMG_APP := ["_apply_damage_from", "_apply_damage", "_post_hit_hooks"]
const SKIP_FILES := ["equip_tally.gd", "_tally_truth_hook.gd"]


func _frames() -> Array:
	var out: Array = []
	for bt in Engine.capture_script_backtraces():
		for i in range(bt.get_frame_count()):
			out.append([str(bt.get_frame_file(i)), str(bt.get_frame_function(i)), int(bt.get_frame_line(i))])
	return out


static func _base(f: String) -> String:
	return f.get_file()


func _is_eq_file(f: String) -> bool:
	if not f.contains("scripts/systems/equip/"):
		return false
	var b: String = _base(f)
	if b.contains("synergy") or b in ["equip_tally.gd", "equip_stats_apply.gd"]:
		return false
	return true


## 从 start 帧(不含)往外找第一个决定性的帧。
func _classify(fr: Array, start: int, skip_ball: bool = false) -> Array:
	for i in range(start + 1, fr.size()):
		var f: String = fr[i][0]
		var fn: String = fr[i][1]
		if _base(f) in SKIP_FILES:
			continue
		if _is_eq_file(f):
			return ["EQ", "%s:%s:%d" % [_base(f), fn, int(fr[i][2])]]
		if f.contains("scripts/systems/equip/") and _base(f).contains("synergy"):
			return ["SYN", "%s:%s:%d" % [_base(f), fn, int(fr[i][2])]]
		if fn in DMG_APP:
			return ["REACT", "%s:%s:%d" % [_base(f), fn, int(fr[i][2])]]
		if _base(f) == "battle_ballistics.gd" and fn in ["_step_projectiles", "_step_pending_shots"]:
			if skip_ball:
				continue
			return ["DEFER-" + _cur_proj_label, "%s:%s:%d" % [_base(f), fn, int(fr[i][2])]]
		if fn in ["_sim_step", "_tick_unit", "_process"]:
			return ["NONE", "%s:%s" % [_base(f), fn]]
	return ["NONE", "?"]


static func _stk(fr: Array) -> String:
	var parts: Array = []
	for i in range(mini(fr.size(), 14)):
		if _base(fr[i][0]) in SKIP_FILES:
			continue
		parts.append("%s:%s:%d" % [_base(fr[i][0]).get_basename(), fr[i][1], int(fr[i][2])])
	return " < ".join(parts)


## 找到「这一笔的结算函数」那一帧(names 里任一个), 返回下标; 找不到返回 -1。
func _find(fr: Array, names: Array) -> int:
	for i in range(fr.size()):
		if fr[i][1] in names and not (_base(fr[i][0]) in SKIP_FILES):
			return i
	return -1


func _begin(kind: String, amt: float, key: String, truth: Array, tgt, fr: Array) -> void:
	_cur = {"kind": kind, "truth": truth[0], "where": truth[1], "amt": amt, "key": key,
		"credited": {}, "tgt_side": str((tgt as Dictionary).get("side", "")) if tgt is Dictionary else "",
		"tgt_id": str((tgt as Dictionary).get("id", "")) if tgt is Dictionary else "",
		"stk": _stk(fr) if not fr.is_empty() else ""}


func _end() -> void:
	events.append(_cur)
	_cur = null


## ── 发射时刻的真值 ──
func _label_last_proj() -> void:
	if _pend_label == null:
		return
	var ps: Array = battle._projectiles
	if not ps.is_empty() and ps.back() is Dictionary and not (ps.back() as Dictionary).has("_probe_truth"):
		ps.back()["_probe_truth"] = str(_pend_label[0])
		ps.back()["_probe_where"] = str(_pend_label[1])
	_pend_label = null


func capture() -> Array:
	_label_last_proj()
	var fr: Array = _frames()
	var ci: int = _find(fr, ["_push_proj"])
	if ci >= 0:
		_pend_label = _classify(fr, ci, true)
	return super.capture()


func use(tl) -> void:
	_label_last_proj()
	super.use(tl)
	_cur_proj_label = ""
	if tl is Array:
		for p in battle._projectiles:
			if p is Dictionary and is_same((p as Dictionary).get("_tl", null), tl):
				_cur_proj_label = str((p as Dictionary).get("_probe_truth", "?"))
				break


func on_damage(src, u: Dictionary, amt: int, bkt: String) -> void:
	_label_last_proj()
	if amt <= 0:
		super.on_damage(src, u, amt, bkt)
		return
	var key: String = bkt if (bkt == "phy" or bkt == "mag") else "tru"
	var truth: Array
	var fr: Array = []
	if dot_mode and (dot_type != "" or dot_flat != null) and is_same(dot_u, u):
		truth = ["DOT", (dot_type if dot_type != "" else "flat:" + str((dot_flat as Dictionary).get("tag", "")))]
	else:
		fr = _frames()
		## 从【结算这一段的伤害函数】往外走: 额外真伤(金弹/腐蚀/墨迹)由同一段的 _apply_damage_from 里记, 不是「反应」
		var i: int = _find(fr, ["_apply_damage_from", "_apply_damage"])
		truth = _classify(fr, i)
		## 召唤物打的: 召唤物身上的来源标就是真值(探针场上只有装备会召唤物)
		if src is Dictionary and str((src as Dictionary).get("_eq_src", "")) != "":
			truth = ["SUMMON", str(src.get("_eq_src", ""))]
	_begin("dmg", float(amt), key, truth, u, fr)
	super.on_damage(src, u, amt, bkt)
	_end()


func on_heal(u: Dictionary, got: float) -> void:
	_label_last_proj()
	if got <= 0.0:
		super.on_heal(u, got)
		return
	var fr: Array = _frames()
	var truth: Array = _classify(fr, _find(fr, ["_heal"]))
	_begin("heal", got, "heal", truth, u, fr)
	super.on_heal(u, got)
	_end()


func on_shield(u: Dictionary, got: float) -> void:
	_label_last_proj()
	if got <= 0.0:
		super.on_shield(u, got)
		return
	var fr: Array = _frames()
	var i: int = _find(fr, ["_grant_shield", "on_shield"])
	var truth: Array = _classify(fr, i)
	_begin("shield", got, "shield", truth, u, fr)
	super.on_shield(u, got)
	_end()


func on_dot_add(u: Dictionary, type: String, stacks: int, before: int, src) -> void:
	_label_last_proj()
	var fr: Array = _frames()
	var truth: Array = _classify(fr, _find(fr, ["_apply_dot_stacks"]))
	dot_adds.append({"type": type, "stacks": stacks, "truth": truth[0], "where": truth[1], "tgt_id": str(u.get("id", ""))})
	super.on_dot_add(u, type, stacks, before, src)


func _add(owner: Dictionary, iid: String, key: String, amt: float) -> void:
	if iid != "" and amt > 0.0:
		if _cur != null:
			var c: Dictionary = _cur["credited"]
			c[iid + "|" + key] = float(c.get(iid + "|" + key, 0.0)) + amt
		else:
			var fr: Array = _frames()
			var w := "?"
			for f in fr:
				if not (_base(f[0]) in SKIP_FILES):
					w = "%s:%s:%d" % [_base(f[0]), f[1], int(f[2])]
					break
			direct.append({"iid": iid, "key": key, "amt": amt, "where": w})
	super._add(owner, iid, key, amt)
