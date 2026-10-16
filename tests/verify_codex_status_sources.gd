extends Node
## verify_codex_status_sources.gd — 图鉴状态页「来源」与代码对账(2026-10-10)
##
## 由来: 图鉴体检(2026-10-10) —— 25 个状态页只有一行「效果」, 4 页写「数值由来源决定」却不点名来源。
##   来源表 scripts/scenes/codex/status_sources.gd 是手写的, 所以必须有一道会红的对账:
##
##   ① 认领真实: 每条来源钉的「文件:函数(:分支)」存在, 且里面真有施加该状态的代码;
##   ② 归属真实: 那段代码确实属于所写的龟 / 装备 / 小将 / 羁绊(技能派发表 / 分支名 / 指定正则);
##      技能 type 在那只龟身上查得到, 装备 / 羁绊 / 小将 id 在数据里查得到;
##   ③ 无遗漏: 全仓扫描每一处施加状态的代码(按状态各一组写法), 每一处要么被某条来源认领,
##      要么在本文件 IGNORE 里写明为什么不算(通用入口 / 自身施法定身 / 训龟大师 …);
##      IGNORE 里的条目也必须还对得上一处真实代码(过期的忽略 = 红);
##   ④ 数值真实: 来源格上的 {C:类.常量} 必须是那段代码里真在用的常量(或其一跳推导),
##      裸数字必须是那段代码里的字面量(允许 ×100 与 1−x 换算), 渲染后不许残留 {C: / {R:;
##   ⑤ 活页面: 走真入口 _switch_tab("status") → _select(i) 渲染 25 页, 每页来源格数 == 表里条数且 ≥1,
##      全页不含「数值由来源决定」, 详情框满高; 点来源格真的跳到那只龟 / 那件装备 / 那个羁绊。

const CODEX_SCN := preload("res://scenes/Codex.tscn")
const StatusSources := preload("res://scripts/scenes/codex/status_sources.gd")
const StatusPage := preload("res://scripts/scenes/codex/status_page.gd")
const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")

## 状态 → 施加它的代码写法(与 status_sources.gd 的 "re" 二选一命中即可)。
const SIG := {
	"stun": ["\\b_stun\\(", "\"stun_until\"\\]\\s*=\\s*maxf", "\\b_freeze\\(", "\\b_fire_ice_shard\\("],
	"fear": ["\"fear_until\"\\]\\s*="],
	"airborne": ["\\b_knock_up\\(", "\"airborne\"\\]\\s*=\\s*true", "\\b_knockback\\("],
	"taunt": ["\\b_taunt\\(", "\"taunt_until\"\\]\\s*=\\s*(battle\\.)?_t\\s*\\+"],
	"burn": ["_apply_dot_stacks\\([^,]+,\\s*\"burn\"", "\\b_spawn_fireball\\("],
	"poison": ["_apply_dot_stacks\\([^,]+,\\s*\"poison\""],
	"bleed": ["_apply_dot_stacks\\([^,]+,\\s*\"bleed\"", "_spawn_eq_bolt\\(.*\\b(true|false),\\s*(?!0\\b)[^,)\\s]"],
	"curse": ["\\b_add_curse\\("],
	"shield": ["\\b_grant_shield\\("],
	"magic-shield": ["\"magic_shield\"\\]\\s*=\\s*float\\(u\\.get\\(\"magic_shield\"[^)]*\\)\\)\\s*\\+"],
	"dodge": ["_buff\\([^,]+,\\s*\"dodge\"", "\"dodge\"\\]\\s*=\\s*float\\(u\\.get\\(\"dodge\"", "\"selfDodge\"\\s*:"],
	"stealth": ["\"phase_until\"\\]\\s*="],
	"untargetable": ["\"untargetable_until\"\\]\\s*=\\s*(maxf|(battle\\.)?_t\\s*\\+)"],
	"reflect": ["\"reflect\"\\]\\s*=\\s*float\\(u\\.get\\(\"reflect\"", "REFLECT_BASE \\+"],
	"cyber-charge": ["\"cyber_ai_charge\"\\]\\s*=\\s*(CyberSystem\\.AI_START_CHARGE|int\\(u\\.get\\(\"cyber_ai_charge\"[^)]*\\)\\)\\s*\\+)"],
	"chilled": ["\"spd_dbf_until\"\\]\\s*=\\s*(battle\\.)?_t\\s*\\+", "\\bapply_chill\\("],
	"slow": ["\"slow_until\"\\]\\s*=\\s*(maxf|(battle\\.)?_t\\s*\\+)"],
	"heal-reduce": ["\"heal_reduce_until\"\\]\\s*=", "\"healCut\"\\s*:"],
	"energy-lock": ["\"energy_lock_until\"\\]\\s*=\\s*(maxf|(battle\\.)?_t\\s*\\+)"],
	"true-fire": ["\"true_fire_until\"\\]\\s*="],
	"corrode": ["\"corrode_stacks\"\\]\\s*=\\s*mini"],
	"ink": ["_add_stack\\([^,]+,\\s*\"ink\""],
	"crystal-mark": ["_add_stack\\([^,]+,\\s*\"crystal\""],
	"shock-mark": ["_add_stack\\([^,]+,\\s*\"electric\""],
	"hunt-mark": ["\"hunt_mark_until\"\\]\\s*="],
}

## 扫到但【不算来源】的施加点。键 = "状态|文件:函数#分支"。每条写原因。
const IGNORE := {
	# —— 通用入口 / 通道本身(真正的来源是调用它的地方, 那些已逐个认领) ——
	"stun|scenes/battle/battle_damage.gd:_stun#": "眩晕的通用入口",
	"stun|scenes/RealtimeBattle3DScene.gd:_freeze#": "冻结 = 通用眩晕入口加特效",
	"stun|scenes/battle/battle_ballistics.gd:_step_projectiles#": "冰锥弹道命中的冻结通道; 来源是发射方(_fire_ice_shard 调用点)",
	"airborne|scenes/battle/battle_damage.gd:_knockback#": "击飞的通用入口",
	"airborne|scenes/RealtimeBattle3DScene.gd:_knock_up#": "击飞的通用入口",
	"taunt|scenes/RealtimeBattle3DScene.gd:_taunt#": "嘲讽的通用入口",
	"burn|scenes/battle/battle_ballistics.gd:_step_projectiles#": "火球弹道的灼烧通道; 来源是 _spawn_fireball 调用点",
	"bleed|scenes/battle/battle_ballistics.gd:_step_projectiles#": "装备弹道的流血通道; 来源是 _spawn_eq_bolt 带流血的调用点",
	"heal-reduce|scenes/RealtimeBattle3DScene.gd:_apply_skill_extras#": "技能附带减益的通用入口; 来源是传 healCut 的调用点",
	"dodge|scenes/RealtimeBattle3DScene.gd:_sk_dmg#": "技能给施法者闪避的通用入口; 来源是传 selfDodge 的调用点",
	"ink|scenes/RealtimeBattle3DScene.gd:_add_stack#": "连笔同步: 一方获得墨迹时另一方同步, 不是新来源",
	# —— 当前没有任何调用方会走到的分支(写法在, 但没有技能 / 装备传入) ——
	"stun|scenes/RealtimeBattle3DScene.gd:_apply_rider#": "技能 rider 通道, 当前没有技能传 stun",
	"burn|scenes/RealtimeBattle3DScene.gd:_apply_rider#": "技能 rider 通道, 当前没有技能传 burn",
	"slow|scenes/RealtimeBattle3DScene.gd:_apply_rider#": "技能 rider 通道, 当前没有技能传 slow",
	"curse|scenes/RealtimeBattle3DScene.gd:_apply_rider#": "技能 rider 通道, 当前没有技能传 curse",
	"shock-mark|scenes/RealtimeBattle3DScene.gd:_sk_dmg_wave#": "技能 elec 参数通道, 当前没有技能传 elec",
	"untargetable|systems/equip/equip_system.gd:_eq_ink_sac#": "免死墨囊通道: 当前没有装备写 _ink_sac(原 063 已改成别的效果)",
	# —— 施法者自己的施法定身 / 演出, 不是对敌控制 ——
	"stun|systems/skills/headless_system.gd:_sk_headless_fear#": "恐吓 = 带「恐惧」标记的眩晕, 列在恐惧页",
	"airborne|systems/equip/eq_arcane_batch.gd:_pestle_leap#": "镇海杵: 携带者自己起跳",
	"chilled|scenes/battle/battle_damage.gd:apply_chill#": "冰寒的唯一写入口本身, 来源按调用方登记",
	# —— 不在图鉴里的单位 ——
	"stun|systems/trainer/trainer_system.gd:_hook_grab#": "训龟大师(周末 Boss), 不在图鉴",
	"slow|systems/trainer/trainer_system.gd:_tick_glaciers#": "训龟大师, 不在图鉴",
	"taunt|systems/trainer/trainer_system.gd:_tick_hunt_taunt#": "训龟大师, 不在图鉴",
	"untargetable|systems/trainer/trainer_system.gd:_tame_try_revive#": "训龟大师, 不在图鉴",
	"airborne|systems/trainer/trainer_system.gd:_wave_apply#": "训龟大师, 不在图鉴",
	# —— 属性表派生(StatusSources.derived 直接读属性表) ——
	"reflect|systems/equip/equip_stats_apply.gd:apply_stat_dict#": "装备 reflectPct 属性: 来源从 EquipStats.STATS 现算",
	"dodge|systems/equip/equip_stats_apply.gd:apply_stat_dict#": "装备 dodgePct 属性: 来源从 EquipStats.STATS 现算",
	"dodge|systems/equip/synergy_system.gd:_add#": "羁绊 dodgePct 属性: 来源从 Phase2Types.TYPES 现算",
	# —— 字符串 / 调试 ——
	"stun|gamedata/vfxlab_cases.gd:<top>#p2eq_090_wave": "特效实验台说明文字里提到 _stun(), 不是代码",
}

var _n := 0
var _fail := 0
var _files := {}        # rel → PackedStringArray(行)
var _funcs := {}        # "rel:fn" → [start, end)  (start = func 行)
var _by_name := {}      # fn 名 → Array["rel:fn"]
var _const_def := {}    # 常量名 → 定义行
var _armset := {}
var _re_cache := {}


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
		print("  [FAIL] " + name + ("  " + detail if detail != "" else ""))


func _re(p: String) -> RegEx:
	if not _re_cache.has(p):
		var r := RegEx.new()
		if r.compile(p) != OK:
			push_error("bad regex " + p)
		_re_cache[p] = r
	return _re_cache[p]


func _ready() -> void:
	print("=== verify_codex_status_sources ===")
	_load_sources()
	_build_armset()
	print("  扫描: %d 个 .gd / %d 个函数" % [_files.size(), _funcs.size()])
	_ok("分母: 扫到的 .gd ≥ 150", _files.size() >= 150, str(_files.size()))
	var hits := _scan_hits()
	print("  施加点(去重后的 状态|文件:函数#分支): %d" % hits.size())
	_ok("分母: 施加点 ≥ 150", hits.size() >= 150, str(hits.size()))
	_check_entries()
	_check_completeness(hits)
	_check_derived()
	await _check_live_pages()
	print("  断言 %d 条, 失败 %d 条" % [_n, _fail])
	if _fail == 0:
		print("ALL PASS — 图鉴状态页来源与代码对账")
	else:
		print("FAILED: %d" % _fail)
	get_tree().quit()


# ───────────────────────── 源码载入 ─────────────────────────
func _load_sources() -> void:
	for root in ["res://scripts", "res://autoload"]:
		_walk(root)
	var fre := _re("^(static\\s+)?func\\s+(\\w+)")
	var cre := _re("^\\s*const\\s+([A-Z_0-9]+)\\s*(:=|=|:)")
	for rel in _files.keys():
		var lines: PackedStringArray = _files[rel]
		var cur := "<top>"
		var start := 0
		for i in range(lines.size()):
			var m := fre.search(lines[i])
			if m != null:
				_close_fn(rel, cur, start, i)
				cur = m.get_string(2)
				start = i
			var cm := cre.search(lines[i])
			if cm != null:
				_const_def[cm.get_string(1)] = lines[i]
		_close_fn(rel, cur, start, lines.size())


func _close_fn(rel: String, fn: String, s: int, e: int) -> void:
	var key := rel + ":" + fn
	if _funcs.has(key):
		return   # 同名函数取第一份(<top> 只取文件头那段)
	_funcs[key] = [s, e]
	if not _by_name.has(fn):
		_by_name[fn] = []
	(_by_name[fn] as Array).append(key)


func _walk(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_walk(dir + "/" + sub)
	for f in d.get_files():
		if f.ends_with(".gd"):
			var path := dir + "/" + f
			var rel := path.trim_prefix("res://scripts/").trim_prefix("res://")
			_files[rel] = FileAccess.get_file_as_string(path).replace("\r", "").split("\n")


func _build_armset() -> void:
	for p in DataRegistry.all_pets:
		_armset[str(p.get("id", ""))] = true
		for key in p.keys():
			var v = p[key]
			if v is Array:
				for s in v:
					if s is Dictionary and (s as Dictionary).has("type"):
						_armset[str(s["type"])] = true
		var pas = p.get("passive", {})
		if pas is Dictionary and (pas as Dictionary).has("type"):
			_armset[str(pas["type"])] = true
	for t in MinionCodex.TYPE_TO_KIND.keys():
		_armset[str(t)] = true


## 去掉行尾注释(# 前面不是引号 —— "#ff0000" 这种颜色串不算注释)。
func _code(line: String) -> String:
	var s := line.strip_edges()
	if s.begins_with("#"):
		return ""
	var i := 0
	while true:
		i = line.find("#", i)
		if i < 0:
			return line
		if i > 0 and line[i - 1] == "\"":
			i += 1
			continue
		return line.substr(0, i)
	return line


func _indent(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == "\t":
		n += 1
	return n


func _arm_of(lines: PackedStringArray, i: int, fstart: int) -> String:
	var own := _re("^\\s*\"([A-Za-z0-9_]+)\"\\s*:").search(lines[i])
	if own != null and _is_arm(own.get_string(1)):
		return own.get_string(1)
	var ind := _indent(lines[i])
	for j in range(i - 1, fstart, -1):
		var lj := lines[j]
		if lj.strip_edges() == "" or lj.strip_edges().begins_with("#"):
			continue
		var ij := _indent(lj)
		if ij >= ind:
			continue
		ind = ij
		var cands: Array = []
		var m := _re("^\\s*\"([A-Za-z0-9_]+)\"\\s*:").search(lj)
		if m != null:
			cands.append(m.get_string(1))
		else:
			for mm in _re("==\\s*\"([A-Za-z0-9_]+)\"").search_all(lj):
				cands.append(mm.get_string(1))
		for c in cands:
			if _is_arm(str(c)):
				return str(c)
	return ""


func _is_arm(s: String) -> bool:
	return _armset.has(s) or s.begins_with("p2eq_")


# ───────────────────────── 扫描施加点 ─────────────────────────
func _scan_hits() -> Dictionary:
	var out := {}
	for key in _funcs.keys():
		var rel: String = key.split(":")[0]
		var fn: String = key.substr(rel.length() + 1)
		var rng: Array = _funcs[key]
		var lines: PackedStringArray = _files[rel]
		var s0: int = rng[0] + (0 if fn == "<top>" else 1)
		for i in range(s0, rng[1]):
			var c := _code(lines[i])
			if c.strip_edges() == "":
				continue
			for st in SIG.keys():
				for p in SIG[st]:
					if _re(p).search(c) != null:
						var hk := "%s|%s#%s" % [st, key, _arm_of(lines, i, rng[0])]
						if not out.has(hk):
							out[hk] = "%s:%d" % [rel, i + 1]
						break
	return out


## 来源钉的那一段代码: 整个函数, 或函数里 arm 分支那一段。
func _unit_text(at: String, arm: String) -> String:
	if not _funcs.has(at):
		return ""
	var rel: String = at.split(":")[0]
	var rng: Array = _funcs[at]
	var lines: PackedStringArray = _files[rel]
	if arm == "":
		var buf: PackedStringArray = []
		for i in range(rng[0], rng[1]):
			buf.append(_code(lines[i]))
		return "\n".join(buf)
	var out: PackedStringArray = []
	var i: int = rng[0] + 1
	while i < rng[1]:
		var l := lines[i]
		var is_arm := _re("^\\s*\"" + arm + "\"\\s*:").search(l) != null or l.contains("== \"" + arm + "\"")
		if is_arm:
			var ind := _indent(l)
			out.append(_code(l))
			var j := i + 1
			while j < rng[1]:
				var lj := lines[j]
				if lj.strip_edges() != "" and not lj.strip_edges().begins_with("#") and _indent(lj) <= ind:
					break
				out.append(_code(lj))
				j += 1
			i = j
			continue
		i += 1
	return "\n".join(out)


func _fn_body(key: String) -> String:
	return _unit_text(key, "")


## from 的函数体里点名了 target(深度 ≤ 3, 按函数名跨文件找) —— 「这段代码由这个技能触发」的证据。
func _reaches(from_fn: String, target_fn: String, depth: int = 3) -> bool:
	if from_fn == target_fn:
		return true
	var frontier: Array = [from_fn]
	var seen := {from_fn: true}
	for _d in range(depth):
		var nxt: Array = []
		for f in frontier:
			for key in _by_name.get(f, []):
				var body := _fn_body(str(key))
				if _re("\\b" + target_fn + "\\b").search(body) != null:
					return true
				for m in _re("\\b(_?[a-z][a-z0-9_]*)\\(").search_all(body):
					var nm := m.get_string(1)
					if _by_name.has(nm) and not seen.has(nm):
						seen[nm] = true
						nxt.append(nm)
				for m in _re("\\b(_?[a-z][a-z0-9_]*)\\.bind\\(").search_all(body):
					var nm2 := m.get_string(1)
					if _by_name.has(nm2) and not seen.has(nm2):
						seen[nm2] = true
						nxt.append(nm2)
		frontier = nxt
	return false


## 技能 type → 主场景派发表那一行点名的 _sk_* 函数(一行可能有两个, 如梭哈首发 / 变身后)。
func _dispatch_fns(sk: String) -> Array:
	var main: PackedStringArray = _files.get("scenes/RealtimeBattle3DScene.gd", PackedStringArray())
	var r := _re("^\\s*\"" + sk + "\"\\s*:\\s*(.*)$")
	var out: Array = []
	for l in main:
		var m := r.search(l)
		if m == null:
			continue
		for c in _re("\\b(_sk_[a-z0-9_]+)\\(").search_all(m.get_string(1)):
			out.append(c.get_string(1))
	return out


# ───────────────────────── ①②④ 逐条来源 ─────────────────────────
func _check_entries() -> void:
	var n_entries := 0
	var n_vals := 0
	for st in StatusSources.SRC.keys():
		_ok("来源表的状态 id 在 status.json 里: " + st, _status_ids().has(st))
		for e in StatusSources.SRC[st]:
			n_entries += 1
			var tag := "%s ← %s %s %s" % [st, str(e.get("k")), str(e.get("id")), str(e.get("sk", ""))]
			var at := str(e.get("at", ""))
			var arm := str(e.get("arm", ""))
			_ok("① 函数存在: " + tag + " @ " + at, _funcs.has(at))
			var unit := _unit_text(at, arm)
			_ok("① 分支存在: " + tag + " #" + arm, unit.strip_edges() != "")
			var pats: Array = [str(e["re"])] if e.has("re") else SIG.get(st, [])
			var applied := false
			for p in pats:
				if _re(str(p)).search(unit) != null:
					applied = true
			_ok("① 真的施加了「%s」: %s @ %s#%s" % [st, tag, at, arm], applied)
			_ok("② 归属: " + tag + " @ " + at, _owned(e, at, arm, unit), _owner_hint(e))
			_ok("② 数据里查得到: " + tag, _exists(e))
			if str(e.get("v", "")) != "":
				n_vals += 1
				_check_value(st, e, unit, tag)
	print("  来源条目 %d 条, 带数值 %d 条" % [n_entries, n_vals])
	_ok("分母: 来源条目 ≥ 150", n_entries >= 150, str(n_entries))
	_ok("分母: 带数值的来源 ≥ 40", n_vals >= 40, str(n_vals))


func _status_ids() -> Dictionary:
	var d := {}
	for s in DataRegistry.status_defs:
		d[str(s.get("id", ""))] = true
	return d


func _link_ok(e: Dictionary, at: String) -> bool:
	if not e.has("link"):
		return false
	var lf := str(e.get("lf", at.split(":")[0]))
	var txt := "\n".join(_files.get(lf, PackedStringArray()))
	var r := RegEx.new()
	r.compile("(?m)" + str(e["link"]))
	return r.search(txt) != null


func _owned(e: Dictionary, at: String, arm: String, unit: String) -> bool:
	var k := str(e.get("k", ""))
	var id := str(e.get("id", ""))
	var sk := str(e.get("sk", ""))
	var fn := at.substr(at.find(":") + 1)
	if e.has("link"):
		return _link_ok(e, at)
	if arm != "" and (arm == id or arm == sk):
		return true
	match k:
		"pet", "minion":
			if sk == "":
				return false
			for d in _dispatch_fns(sk):
				if _reaches(str(d), fn):
					return true
			return false
		"eq":
			if unit.contains("\"" + id + "\""):
				return true
			## 点名这件装备 id 的函数(派发分支 / 状态读写)在 2 跳内调到了它
			for key in _funcs.keys():
				var kname: String = str(key).substr(str(key).find(":") + 1)
				if kname == "<top>":
					continue
				if _fn_body(str(key)).contains("\"" + id + "\"") and _reaches(kname, fn, 2):
					return true
			## 退一步: 文件本身就是这件装备的专属文件(全文件只点名这一件 id)才算。
			##   equip_system.gd 这种装着几十件的大文件不许靠「文件里出现过」蒙混, 必须给 arm / link。
			var ftxt := "\n".join(_files.get(at.split(":")[0], PackedStringArray()))
			var ids := {}
			for m in _re("p2eq_\\d{3}").search_all(ftxt):
				ids[m.get_string()] = true
			return ids.size() == 1 and ids.has(id)
		"syn":
			return "\n".join(_files.get(at.split(":")[0], PackedStringArray())).contains(id)
	return false


func _owner_hint(e: Dictionary) -> String:
	var sk := str(e.get("sk", ""))
	return "派发=" + str(_dispatch_fns(sk)) if sk != "" else ""


func _exists(e: Dictionary) -> bool:
	var id := str(e.get("id", ""))
	match str(e.get("k", "")):
		"pet":
			var pet: Dictionary = DataRegistry.pet_by_id.get(id, {})
			return not pet.is_empty() and (str(e.get("sk", "")) == "" or not StatusPage.skill_of(pet, str(e["sk"])).is_empty())
		"eq":
			return DataRegistry.phase2_equipment_by_id.has(id)
		"minion":
			var ok := MinionCodex.MINION_INFO.has(id)
			if str(e.get("sk", "")) != "":
				ok = ok and str(MinionCodex.TYPE_TO_KIND.get(str(e["sk"]), "")) == id
			if str(e.get("pv", "")) != "":
				var pvs: Array = (MinionCodex.MINION_INFO.get(id, {}) as Dictionary).get("passives", [])
				ok = ok and pvs.any(func(x): return str(x.get("name", "")) == str(e["pv"]))
			return ok
		"syn":
			return Phase2Types.TYPES.has(id)
	return false


func _check_value(st: String, e: Dictionary, unit: String, tag: String) -> void:
	var v := str(e["v"])
	var shown := StatusSources.render_value(v)
	_ok("④ 数值渲染无残留占位: " + tag, not shown.contains("{C:") and not shown.contains("{R:"), shown)
	## 常量: 名字必须出现在这段代码里, 或是这段代码里某个常量的一跳推导
	var idents := {}
	for m in _re("\\b([A-Z][A-Z0-9_]{2,})\\b").search_all(unit):
		idents[m.get_string(1)] = true
	for name in idents.keys():
		var dl := str(_const_def.get(name, ""))
		for m2 in _re("\\b([A-Z][A-Z0-9_]{2,})\\b").search_all(dl):
			idents[m2.get_string(1)] = true
	for m in _re("[{][CR]:[A-Za-z0-9_]+\\.([A-Z0-9_]+)%?[}]").search_all(v):
		_ok("④ 常量 %s 真在这段代码里用: %s" % [m.get_string(1), tag], idents.has(m.get_string(1)))
	## 裸数字: 必须是这段代码里的字面量(或 ×100 / 1−x 换算)
	var nums: Array = []
	for m in _re("(?<![A-Za-z_0-9.])(\\d+\\.\\d+|\\d+)(?![A-Za-z_0-9])").search_all(unit):
		nums.append(float(m.get_string(1)))
	var bare := _re("[{][^}]*[}]").sub(v, "", true)
	for m in _re("(\\d+(?:\\.\\d+)?)").search_all(bare):
		var x := float(m.get_string(1))
		var found := false
		for y in nums:
			if absf(y - x) < 1e-6 or absf(y * 100.0 - x) < 1e-4 or absf((1.0 - y) * 100.0 - x) < 1e-4:
				found = true
				break
		_ok("④ 裸数字 %s 是这段代码里的字面量: %s" % [m.get_string(1), tag], found)


# ───────────────────────── ③ 无遗漏 ─────────────────────────
func _check_completeness(hits: Dictionary) -> void:
	var claimed := {}
	for st in StatusSources.SRC.keys():
		for e in StatusSources.SRC[st]:
			claimed["%s|%s#%s" % [st, str(e.get("at", "")), str(e.get("arm", ""))]] = true
	var unclaimed := 0
	for hk in hits.keys():
		if claimed.has(hk) or IGNORE.has(hk):
			continue
		unclaimed += 1
		_ok("③ 施加点没有被任何来源认领(加进 status_sources.gd 或写明原因进 IGNORE): " + str(hk), false, str(hits[hk]))
	for ik in IGNORE.keys():
		_ok("③ IGNORE 条目仍对得上一处真实代码: " + str(ik), hits.has(ik))
	for ck in claimed.keys():
		_ok("③ 来源认领的位置确实是一处施加点: " + str(ck), hits.has(ck) or _claimed_by_custom_re(ck))
	print("  未认领施加点 %d 处; 忽略 %d 处" % [unclaimed, IGNORE.size()])


## 带 "re" 的来源(施加写法不是标准形状)不一定落在 SIG 扫描里, 由 ① 单独证明。
func _claimed_by_custom_re(ck: String) -> bool:
	for st in StatusSources.SRC.keys():
		for e in StatusSources.SRC[st]:
			if "%s|%s#%s" % [st, str(e.get("at", "")), str(e.get("arm", ""))] == ck and e.has("re"):
				return true
	return false


func _check_derived() -> void:
	var n_r := 0
	var n_d := 0
	for eid in _equip_stats_table().keys():
		for t in _equip_stats_table()[eid]:
			if t is Dictionary and (t as Dictionary).has("reflectPct"):
				n_r += 1; break
		for t in _equip_stats_table()[eid]:
			if t is Dictionary and (t as Dictionary).has("dodgePct"):
				n_d += 1; break
	var dr := StatusSources.derived("reflect").filter(func(x): return str(x["k"]) == "eq").size()
	var dd := StatusSources.derived("dodge").filter(func(x): return str(x["k"]) == "eq").size()
	_ok("属性派生: 反伤装备条数 == 属性表里带 reflectPct 的装备数(%d)" % n_r, dr == n_r and n_r > 0, str(dr))
	_ok("属性派生: 闪避装备条数 == 属性表里带 dodgePct 的装备数(%d)" % n_d, dd == n_d and n_d > 0, str(dd))
	var syn_d := StatusSources.derived("dodge").filter(func(x): return str(x["k"]) == "syn").size()
	_ok("属性派生: 闪避羁绊(灵物)在列", syn_d >= 1, str(syn_d))


func _equip_stats_table() -> Dictionary:
	return (load("res://scripts/gamedata/equip_stats.gd") as Script).get_script_constant_map()["STATS"]


# ───────────────────────── ⑤ 活页面 ─────────────────────────
func _texts(n: Node, out: PackedStringArray) -> void:
	if n is Label:
		out.append((n as Label).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	for c in n.get_children():
		_texts(c, out)


func _tiles(n: Node, out: Array) -> void:
	if n.has_meta("status_src"):
		out.append(n)
	for c in n.get_children():
		_tiles(c, out)


func _check_live_pages() -> void:
	var c = CODEX_SCN.instantiate()
	add_child(c)
	for _i in range(4):
		await get_tree().process_frame
	c.call("_switch_tab", "status")
	await get_tree().process_frame
	var items: Array = c.get("_items")
	_ok("⑤ 分母: 状态页签 25 条", items.size() == DataRegistry.status_defs.size() and items.size() >= 25, str(items.size()))
	var pages := 0
	for i in range(items.size()):
		c.call("_select", i)
		for _j in range(3):
			await get_tree().process_frame
		var sid := str((items[i] as Dictionary).get("id", ""))
		var det: Node = c.get("detail")
		var txt: PackedStringArray = []
		_texts(det, txt)
		var all := "\n".join(txt)
		var tiles: Array = []
		_tiles(det, tiles)
		var want: int = StatusSources.sources_of(sid).size()
		_ok("⑤ %s: 至少 1 个来源" % sid, want >= 1)
		_ok("⑤ %s: 来源格数 == 来源条数(%d)" % [sid, want], tiles.size() == want, str(tiles.size()))
		_ok("⑤ %s: 页面不含「数值由来源决定」" % sid, not all.contains("由来源决定"))
		_ok("⑤ %s: 页面不含未渲染占位" % sid, not all.contains("{C:") and not all.contains("{R:"))
		var frame: Control = c.get("detail_frame")
		_ok("⑤ %s: 详情框满高(不露背景)" % sid, absf(frame.size.y - float(c.DETAIL_MAX_H)) < 1.0, str(frame.size.y))
		pages += 1
	_ok("⑤ 分母: 渲染了全部状态页", pages == items.size(), str(pages))
	## 点来源格 → 跳转: 每种来源各点一格(龟 / 小将 / 装备 / 羁绊)
	var kinds := {"pet": ["stun", "pets"], "minion": ["stun", "pets"], "eq": ["burn", "equips"], "syn": ["shield", "synergies"]}
	for k in kinds.keys():
		var sid: String = kinds[k][0]
		c.call("_switch_tab", "status")
		await get_tree().process_frame
		var its: Array = c.get("_items")
		for i in range(its.size()):
			if str((its[i] as Dictionary).get("id", "")) == sid:
				c.call("_select", i)
		for _j in range(2):
			await get_tree().process_frame
		var tiles: Array = []
		_tiles(c.get("detail"), tiles)
		var tile: Control = null
		for t in tiles:
			if str((t.get_meta("status_src") as Dictionary).get("k", "")) == k:
				tile = t
				break
		_ok("⑤ 跳转: %s 页有一格 %s 来源" % [sid, k], tile != null)
		if tile == null:
			continue
		var e: Dictionary = tile.get_meta("status_src")
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.global_position = Vector2(100, 100)
		tile.gui_input.emit(press)
		var rel := press.duplicate()
		rel.pressed = false
		tile.gui_input.emit(rel)
		for _j in range(4):
			await get_tree().process_frame
		var cur: Dictionary = (c.get("_items") as Array)[int(c.get("_sel_idx"))]
		var landed := str(c.get("current_tab")) == str(kinds[k][1])
		match k:
			"pet", "eq": landed = landed and str(cur.get("id", "")) == str(e["id"])
			"minion": landed = landed and str(cur.get("_minion", "")) == str(e["id"])
			"syn": landed = landed and str(cur.get("_type", "")) == str(e["id"])
		_ok("⑤ 跳转: 点 %s「%s」落到它的图鉴页" % [k, str(e["id"])], landed, "%s %s" % [str(c.get("current_tab")), str(cur)])
	c.queue_free()
