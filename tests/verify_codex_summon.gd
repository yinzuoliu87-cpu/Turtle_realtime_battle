extends Node
## verify_codex_summon.gd — 图鉴「角色」栏召唤物 / 战场单位页(SummonCodex)的门禁(2026-11-27 · 方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md §6)。
##
## 守四件事(少一件就会放过一种错法):
##   ① 收全: 全仓每一个 `_spawn_summon(` 调用点的种类名都在登记表里(SummonCodex.id_of_kind) —— 新加召唤物不登记当场红。
##      分母 = 扫到几个调用点 / 几种种类; 非字面量种类(亡者之书 kind 变量、暗影忍者三元式)各有单独断言。
##   ② 页面齐: 每个条目每一列 info 都有名字 / 头像 / 立绘 / 7 行属性; 攻击 / 技能 / 被动全都有图标且图标文件在盘上;
##      文案渲染完不剩 {C: {N: {M: %s 这类没展开的占位(11-27 出过 %s 原样上屏)。
##   ③ 数字 = 战斗常量: 左栏生命值逐列等于各系统常量, 且这些常量真的被召唤那一行用到(扫源码里的召唤行)
##      —— 页面读常量、战斗却还写着字面量, 两边各管各就是 minion_codex 那种「手抄必漂」。
##   ④ 文案换写法: 召唤它的装备 / 羁绊文案里不再引用召唤物的生命 / 攻击 / 护甲常量(用户 11-27「羁绊里的召唤去描述可以换种方式」),
##      且【名字】经 SummonCodex.linkify 变成能点的链接。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/verify_codex_summon.tscn --quit-after 600

const Phase2Types := preload("res://scripts/gamedata/phase2_types.gd")
const SCAN_ROOT := "res://scripts"
const CALL := "_spawn_summon("
const MIN_CALL_SITES := 20   # 11-27 实测 25 个调用点; 写下限, 新加召唤物不该让这条红(该让 ① 的登记那条红)

## ③ 左栏生命值 = 哪条常量(按列取), 以及召唤那一行在源码里用的是不是它
const HP_SRC := {
	"turret": ["EquipSystem", "TURRET_HP", "res://scripts/systems/equip/eq_summons.gd", "EquipSystem.TURRET_HP[si]"],
	"skeleton": ["EqSummons", "SKEL_HP", "res://scripts/systems/equip/eq_summons.gd", "SKEL_HP[si]"],
	"worm": ["EquipSystem", "WORM_HP", "res://scripts/systems/equip/equip_system.gd", "float(WORM_ATK[si])"],
	"bear": ["EquipTickSystem", "BEAR_HP", "res://scripts/scenes/RealtimeBattle3DScene.gd", "EquipTickSystem.BEAR_HP[si]"],
	"pistol": ["EqGunBatch", "PISTOL_HP", "res://scripts/systems/equip/eq_gun_batch.gd", "float(PISTOL_HP[si])"],
	"medtower": ["EqGunBatch", "TOWER_HP", "res://scripts/systems/equip/eq_gun_batch.gd", "float(TOWER_HP[si])"],
	"cannon": ["EqBombBatch", "CANNON_HP", "res://scripts/systems/equip/eq_bomb_batch.gd", "float(CANNON_HP[si])"],
	"remote_bomb": ["EqBombBatch", "REMOTE_HP", "res://scripts/systems/equip/eq_bomb_batch.gd", "float(REMOTE_HP[si])"],
	"katana": ["EqBombBatch", "KATANA_HP", "res://scripts/systems/equip/eq_bomb_batch.gd", "float(KATANA_HP[si])"],
	"shadow_ninja": ["EqDaggerBatch", "NINJA_HP", "res://scripts/systems/equip/eq_dagger_batch.gd", "float(NINJA_HP[si])"],
	"skel_warrior": ["EqMagicBatch", "SKW_HP", "res://scripts/systems/equip/eq_magic_batch.gd", "hp = SKW_HP[si]"],
	"skel_mage": ["EqMagicBatch", "SKM_HP", "res://scripts/systems/equip/eq_magic_batch.gd", "hp = SKM_HP[si]"],
	"skel_priest": ["EqMagicBatch", "SKP_HP", "res://scripts/systems/equip/eq_magic_batch.gd", "hp = SKP_HP[si]"],
	"mask_lion": ["EqMaskBatch", "LION_HP", "res://scripts/systems/equip/eq_mask_batch.gd", "float(LION_HP[si])"],
	"centurion": ["SpearSynergySystem", "HP", "res://scripts/systems/equip/spear_synergy_system.gd", "float(HP[ti])"],
}

## ④ 召唤它的文案 → 该出现的链接; 以及这些文案里不许再引用的召唤物属性常量
const COPY_LINKS := {
	"p2eq_032": ["skeleton"], "p2eq_033": ["worm"], "p2eq_034": ["bear"], "p2eq_058": ["turret"], "p2eq_072": ["cakebox"],
	"p2eq_077": ["pistol"], "p2eq_079": ["medtower"], "p2eq_096": ["axe"], "p2eq_105": ["cannon"], "p2eq_106": ["remote_bomb"],
	"p2eq_107": ["katana"], "p2eq_115": ["shadow_ninja"], "p2eq_123": ["skel_warrior", "skel_mage", "skel_priest"], "p2eq_130": ["mask_lion"],
}
const FORBIDDEN_CONSTS := ["TURRET_HP", "TURRET_ATK", "TURRET_RES", "WORM_HP", "WORM_ATK", "BEAR_HP", "BEAR_ATK", "BEAR_RESIST",
	"CANNON_HP", "CANNON_ATK", "REMOTE_HP", "REMOTE_RES", "KATANA_HP", "KATANA_ATK", "NINJA_HP", "NINJA_ATK", "NINJA_RES",
	"LION_HP", "LION_ATK", "LION_RES", "SKW_HP", "SKW_ATK", "SKM_HP", "SKM_ATK", "SKP_HP", "SKP_ATK", "PISTOL_HP", "PISTOL_ATK",
	"TOWER_HP", "TOWER_ATK", "SKEL_HP", "SKEL_ATK", "MINION_HP_BASE", "MINION_ATK_BASE", "WRAITH_INHERIT", "SpearSynergySystem.HP[",
	"SpearSynergySystem.ATK[", "SpearSynergySystem.RES["]

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	print("=== 图鉴「角色」栏召唤物页 ===")
	_seg1_coverage()
	_seg2_pages()
	_seg3_numbers()
	_seg4_copy()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 图鉴召唤物页收全、数字读常量、文案已换写法" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


# ── ① 收全 ──
func _files(root: String) -> Array:
	var out: Array = []
	var st: Array = [root]
	while not st.is_empty():
		var d: String = str(st.pop_back())
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		while true:
			var f := da.get_next()
			if f == "":
				break
			if f.begins_with("."):
				continue
			var p: String = d.path_join(f)
			if da.current_is_dir():
				st.append(p)
			elif f.ends_with(".gd"):
				out.append(p)
		da.list_dir_end()
	out.sort()
	return out


func _seg1_coverage() -> void:
	print("— ① 全仓 _spawn_summon 调用点的种类都在登记表里")
	var kinds := {}
	var sites := 0
	var dynamic: Array = []
	var re_kind := RegEx.create_from_string("\"([a-z_]+)\"")
	for p in _files(SCAN_ROOT):
		var src := FileAccess.get_file_as_string(p)
		var from := 0
		while true:
			var i := src.find(CALL, from)
			if i < 0:
				break
			from = i + CALL.length()
			var line_start := src.rfind("\n", i) + 1
			var line := src.substr(line_start, src.find("\n", i) - line_start)
			if line.strip_edges().begins_with("#") or line.contains("func _spawn_summon") or line.contains("`_spawn_summon("):
				continue
			sites += 1
			## 第二个参数: 从第一个逗号到下一个顶层逗号
			var a := src.find(",", from)
			var depth := 0
			var j := a + 1
			while j < src.length():
				var c := src[j]
				if c == "(" or c == "[" or c == "{":
					depth += 1
				elif c == ")" or c == "]" or c == "}":
					depth -= 1
				elif c == "," and depth == 0:
					break
				j += 1
			var arg := src.substr(a + 1, j - a - 1).strip_edges()
			var lits := re_kind.search_all(arg)
			if lits.is_empty():
				dynamic.append("%s: %s" % [p.get_file(), arg])
			for m in lits:
				kinds[m.get_string(1)] = p.get_file()
	_ok("调用点分母 ≥ %d" % MIN_CALL_SITES, sites >= MIN_CALL_SITES, "扫到 %d 个调用点、%d 种字面量种类" % [sites, kinds.size()])
	## 非字面量种类: 只认亡者之书的 kind 变量(取值 = EqMagicBatch.SKEL_KINDS), 名单外的当场红
	for d in dynamic:
		_ok("非字面量种类在白名单: %s" % d, str(d).begins_with("eq_magic_batch.gd: kind"))
	for k in EqMagicBatch.SKEL_KINDS:
		kinds[str(k)] = "eq_magic_batch.gd(SKEL_KINDS)"
	for k in kinds.keys():
		var id: String = SummonCodex.id_of_kind(str(k))
		_ok("种类 %s 有图鉴页" % k, id != "", "→ %s(%s)" % [id, kinds[k]])


# ── ② 页面齐 ──
func _seg2_pages() -> void:
	print("— ② 每页每列: 名字 / 头像 / 立绘 / 7 行属性 / 图标在盘上 / 文案占位全展开")
	var ids: Array = SummonCodex.all_ids()
	_ok("条目分母", ids.size() >= 25, "%d 条" % ids.size())
	var pages := 0
	var icons := 0
	for id in ids:
		var nc: int = maxi(1, SummonCodex.cols(str(id)).size())
		for ci in range(nc):
			var si: Dictionary = SummonCodex.info(str(id), ci)
			pages += 1
			var tag := "%s 第 %d 列" % [id, ci]
			if si.is_empty():
				_ok(tag + " 有数据", false)
				continue
			var bad: PackedStringArray = []
			if str(si.get("name", "")) == "":
				bad.append("无名字")
			if not ResourceLoader.exists(str(si.get("avatar", ""))):
				bad.append("头像不在: " + str(si.get("avatar", "")))
			var por: Dictionary = si.get("portrait", {})
			if not ResourceLoader.exists("res://assets/sprites/" + str(por.get("img", ""))):
				bad.append("立绘不在: " + str(por.get("img", "")))
			if (si.get("stats", []) as Array).size() != 7:
				bad.append("属性行数 %d" % (si.get("stats", []) as Array).size())
			var abil: Array = []
			if not (si.get("basic", {}) as Dictionary).is_empty():
				abil.append(si["basic"])
			if not (si.get("skill", {}) as Dictionary).is_empty():
				abil.append(si["skill"])
			abil.append_array(si.get("passives", []))
			if abil.is_empty():
				bad.append("没有任何攻击 / 技能 / 被动")
			var ctx := {"atk": 100.0, "maxHp": 1000.0, "lv": 1}
			for ab in abil:
				icons += 1
				var ic := "res://assets/sprites/" + str((ab as Dictionary).get("icon", ""))
				if str((ab as Dictionary).get("icon", "")) == "" or not ResourceLoader.exists(ic):
					bad.append("「%s」没图标(%s)" % [str(ab["name"]), ic])
				var txt: String = SkillText.render_bbcode_formula(str(ab["desc"]), ctx, {})
				for tok in ["{C:", "{N:", "{M:", "%s", "%d"]:
					if txt.contains(tok):
						bad.append("「%s」渲染后剩 %s" % [str(ab["name"]), tok])
			_ok(tag, bad.is_empty(), "; ".join(bad))
	_ok("分母: 页 × 列", pages >= 40, "%d 页次、%d 个攻击 / 技能 / 被动" % [pages, icons])


# ── ③ 数字 = 战斗常量 ──
func _seg3_numbers() -> void:
	print("— ③ 左栏生命值逐列 = 战斗常量, 且召唤行真的用它")
	for id in HP_SRC.keys():
		var spec: Array = HP_SRC[id]
		var cls_path := ""
		for c in ProjectSettings.get_global_class_list():
			if str(c.get("class", "")) == str(spec[0]):
				cls_path = str(c.get("path", ""))
		var consts: Dictionary = (load(cls_path) as Script).get_script_constant_map() if cls_path != "" else {}
		var arr = consts.get(str(spec[1]), null)
		if not (arr is Array):
			_ok("%s: %s.%s 是数组" % [id, spec[0], spec[1]], false)
			continue
		var bad: PackedStringArray = []
		for ci in range(SummonCodex.cols(str(id)).size()):
			var si: Dictionary = SummonCodex.info(str(id), ci)
			var hp_disp := ""
			for st in si.get("stats", []):
				if str(st["key"]) == "hp":
					hp_disp = str(st["disp"])
			if hp_disp != str(int(roundf(float(arr[ci])))):
				bad.append("第 %d 列 %s ≠ %s" % [ci, hp_disp, str(arr[ci])])
		_ok("%s 生命值 = %s.%s" % [id, spec[0], spec[1]], bad.is_empty(), "; ".join(bad))
		var src := FileAccess.get_file_as_string(str(spec[2]))
		_ok("%s 召唤行用的是常量(%s)" % [id, spec[3]], src.contains(str(spec[3])), str(spec[2]).get_file())


# ── ④ 文案换写法 + 名字链接 ──
func _seg4_copy() -> void:
	print("— ④ 召唤它的文案不再写召唤物属性, 【名字】能点")
	var texts := 0
	for eid in COPY_LINKS.keys():
		var e: Dictionary = DataRegistry.phase2_equipment_by_id.get(str(eid), {})
		var raw := ""
		for f in ["effectDesc1", "effectDesc2", "effectDesc3", "effectBrief"]:
			raw += str(e.get(f, "")) + "\n"
		texts += 1
		var hit: PackedStringArray = []
		for c in FORBIDDEN_CONSTS:
			if raw.contains(c):
				hit.append(c)
		_ok("%s 文案不引用召唤物属性常量" % eid, hit.is_empty(), ", ".join(hit))
		var bb: String = SummonCodex.linkify(SkillText.equip_full_bb(e, 20))
		for sid in COPY_LINKS[eid]:
			_ok("%s 文案里【%s】是链接" % [eid, SummonCodex.info(str(sid), 0)["name"]], bb.contains("[url=summon:%s]" % sid))
	for tname in ["长矛", "灵物"]:
		var all := ""
		var tb: Dictionary = Phase2Types.TIER_TABLE.get(tname, {})
		for ln in tb.get("lines", []):
			all += str(ln) + "\n"
		for r in tb.get("rows", []):
			all += str(r) + "\n"
		for d in Phase2Types.TIER_DESCS.get(tname, []):
			all += str(d) + "\n"
		texts += 1
		var hit2: PackedStringArray = []
		for c in FORBIDDEN_CONSTS:
			if all.contains(c):
				hit2.append(c)
		_ok("%s 羁绊文案不引用召唤物属性常量" % tname, hit2.is_empty(), ", ".join(hit2))
	var syn_bb: String = SummonCodex.linkify(CodexSynergyView.line_bb(SkillText.render_consts(str((Phase2Types.TIER_TABLE["长矛"]["lines"] as Array)[1]))))
	_ok("长矛羁绊里【百夫长】是链接", syn_bb.contains("[url=summon:centurion]"))
	_ok("文案分母", texts >= 16, "%d 段" % texts)
	## 链接点下去真能找到条目(商店小卡 spec 非空)
	for sid in ["centurion", "turret", "skel_mage"]:
		_ok("商店小卡 %s 能开" % sid, not SummonCodex.card_spec(sid).is_empty())
