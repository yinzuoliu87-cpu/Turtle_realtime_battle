class_name CodexSummonPage
extends RefCounted
## 图鉴「角色」栏 · 召唤物 / 战场单位详情页(2026-11-27 · 方案书 docs/plans/20261127d-图鉴角色栏收全部单位.md)。
## 版式与龟页 / 小将页同一套(复用 detail_views 的 _left_header / _stat_rows / _render_right): 左栏立绘 + 名字 + 签牌 + 属性方块,
##   右栏 被动条 → 普攻条 → 技能卡。召唤物多一样: 属性跟着长矛件数 / 装备星级变 ⇒ 右栏最上面一排选择牌(管整页: 左栏属性与右栏技能
##   都跟着变), 点了整页重画。初版放在左栏属性下面, 要往下滚才看得到(11-27 截图自查)。
## 数据全在 SummonCodex(读战斗代码常量)。

var host
var _sel := {}   # 条目 id → 选中的第几列(换条目回到第 0 列由 CodexScene 切条目时不清, 保留玩家上次看的那一档)

const SEL_W := 64.0
const SEL_H := 36.0
const SEL_HIT_H := 48.0
const SEL_ROW_GAP := 6.0


func _init(h) -> void:
	host = h


func show(id: String) -> void:
	var dv = host._codex_detail
	host._clear_detail()
	var ci: int = int(_sel.get(id, 0))
	var si: Dictionary = SummonCodex.info(id, ci)
	if si.is_empty():
		return
	dv._rerender = show.bind(id)
	host._add_pet_portrait(95, float(si.get("portrait_cy", 100.0)), si["portrait"], float(si.get("portrait_box", 160.0)))
	## 签牌只写一块「召唤物」(用户 11-27「不要提这个近战坦克、不可编入、糖果龟，反而这里写一个召唤物就可以了」);
	##   战场单位(龟蛋 / 训龟大师, source 为空)不挂签牌(用户 11-27「每路一颗和战场单位还有不可编入这三个东西干啥呢」)。
	var chips: Array = []
	if not (si.get("source", {}) as Dictionary).is_empty():
		chips.append({"kind": "tag", "text": Lang.t("召唤物"), "color": "#58d3ff"})
	dv._left_header(str(si["name"]), chips)
	var y: float = dv._stat_rows(si["stats"]) + 14.0
	dv._col_divider(y)
	_render_right_side(id, si, ci)


func _render_right_side(id: String, si: Dictionary, ci: int) -> void:
	var dv = host._codex_detail
	var right_top: float = 16.0
	if not (si.get("cols", []) as Array).is_empty():
		right_top = _selector(id, si, ci, 16.0) + 8.0
	var ctx: Dictionary = {"atk": float(_stat(si, "atk")), "maxHp": float(_stat(si, "hp")), "hp": float(_stat(si, "hp")),
		"def": float(_stat(si, "def")), "mr": float(_stat(si, "mr")), "lv": 1, "crit": 0.0}
	dv._render_right(_as_pet(id, si), ctx, right_top)


static func _stat(si: Dictionary, key: String) -> String:
	for st in si.get("stats", []):
		if str(st["key"]) == key:
			return str(st["disp"])
	return "0"


## 选择牌(右栏最上面): 小标题(长矛件数 / 装备星级 / 进化形态…) + 一排签牌, 当前那一列金色; 放不下换行(小木斧 9 种形态 / 训龟大师 7 个技能)。
## 返回占到的底边。
func _selector(id: String, si: Dictionary, ci: int, y: float) -> float:
	var dv = host._codex_detail
	var x0: float = dv.RCOL_X
	var x_max: float = x0 + dv._rw()
	var cy: float = y + SEL_HIT_H / 2.0
	var ttl: Label = host._add_text(x0, cy, str(si.get("col_title", "")), 16, "#c8d4e0", 0.0, 0.5, true)
	var tw: float = ttl.get_combined_minimum_size().x + 14.0 if ttl != null else 90.0
	var cols: Array = si.get("cols", [])
	var x: float = x0 + tw
	for k in range(cols.size()):
		var txt: String = str(cols[k])
		var w: float = maxf(SEL_W, float(txt.length()) * 18.0 + 16.0)
		if x + w > x_max and x > x0 + tw:
			x = x0 + tw
			cy += SEL_HIT_H + SEL_ROW_GAP
		var on: bool = k == ci
		var col: String = "#ffd93d" if on else "#5f7186"
		var p: Panel = dv._plaque(x, cy - SEL_H / 2.0, w, SEL_H, col)
		p.name = "SummonCol%d" % k
		dv._chip_text(x + 6.0, cy - 12.0, w - 12.0, 24.0, txt, 18, col)
		var hit := Control.new()
		hit.name = "SummonColHit%d" % k
		hit.position = Vector2(x - 4.0, cy - SEL_HIT_H / 2.0)
		hit.size = Vector2(w + 8.0, SEL_HIT_H)
		var k_ref: int = k
		dv._tap_hit(hit, func() -> void: set_col(id, k_ref))
		host.detail.add_child(hit)
		x += w + 8.0
	return cy + SEL_HIT_H / 2.0


## 换列并重画(点签牌 / 门禁 / 截图共用)。
func set_col(id: String, k: int) -> void:
	_sel[id] = k
	host._codex_skill_detail = {}
	host._codex_passive_view = false
	show(id)


## SummonCodex 的一页 → 龟页右栏认得的形状(同 detail_views._minion_pet): 普攻条 / 技能卡 / 被动条。
static func _as_pet(id: String, si: Dictionary) -> Dictionary:
	var pool: Array = []
	var b: Dictionary = si.get("basic", {})
	if not b.is_empty():
		pool.append({"name": str(b["name"]), "brief": str(b["desc"]), "detail": str(b["desc"]), "desc": str(b["desc"]), "_role": "basic",
			"icon": str(b.get("icon", ""))})
	var sk: Dictionary = si.get("skill", {})
	if not sk.is_empty():
		var e := {"name": str(sk["name"]), "brief": str(sk["desc"]), "detail": str(sk["desc"]), "desc": str(sk["desc"]),
			"_role": "active", "_energy": int(sk.get("energy", 0)), "icon": str(sk.get("icon", ""))}
		## 训龟大师的技能按冷却放、不吃龟能: 签牌只写「主动」(冷却秒数技能说明里已经写了, 签牌再写一遍就重复了)
		if sk.has("cd"):
			e["_cd"] = 0.0
		pool.append(e)
	var plist: Array = []
	for pv in si.get("passives", []):
		plist.append({"name": str(pv["name"]), "brief": str(pv["desc"]), "detail": str(pv["desc"]), "desc": str(pv["desc"]),
			"icon": str(pv.get("icon", ""))})
	return {"id": "__summon_%s" % id, "_summon": id, "name": str(si["name"]), "skillPool": pool,
		"passive": plist[0] if not plist.is_empty() else {}, "passives": plist}
