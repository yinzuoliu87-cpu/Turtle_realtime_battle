"""gold_mask_persist_1127.py —— 135 黄金面具层数跨对局保留、只记在这一件上(方案书 20261125c §5; 用户 11-27「直接做就好了呀」)
客户端 / 裁判这一半(服务器那一半是迁移 20261127b_gold_mask_stacks):
  背包件字典 135 带 gm_stk(层数); 合成三件相加(用户 11-26「合成…层数是保留下来的」); 经济资产比对不含 gm_stk(同 093 的 chg: 战斗挣的进度, 不是买卖);
  裁判结果单 gold_new / gold_new_b = {"<龟 id>|<份号>": 新涨层数}; 客户端回包解析 + RefereeWatch.apply_gold 写回那一件; 裁判按 key.a_gold / b_gold 封顶。
一次性; 原行尾二进制读写, 每处替换恰好命中一次。
"""
import os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def patch(rel, pairs):
    p = os.path.join(ROOT, rel)
    raw = open(p, "rb").read()
    nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b, *n in pairs:
        k = n[0] if n else 1
        if s.count(a) != k:
            sys.exit("%s: 命中 %d 次(要 %d): %r" % (rel, s.count(a), k, a[:90]))
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
    print("ok", rel)


patch("autoload/GameState.gd", [
("""static func mk_eq(id: String, star: int, chg: int = 0) -> Dictionary:
	var d: Dictionary = {"id": id, "star": star}
	if id == INCENSE_ID and chg > 0:
		d["chg"] = chg
	return d""",
"""static func mk_eq(id: String, star: int, chg: int = 0, gm: int = 0) -> Dictionary:
	var d: Dictionary = {"id": id, "star": star}
	if id == INCENSE_ID and chg > 0:
		d["chg"] = chg
	if id == GOLD_MASK_ID and gm > 0:
		d["gm_stk"] = gm   # 135 黄金面具层数(跨对局保留、只记在这一件上; 11-27)
	return d


## 135 黄金面具: 这一件攒下的层数(非黄金面具恒为 0)。合成时三件相加(用户 11-26「合成…层数是保留下来的」)。
const GOLD_MASK_ID := "p2eq_135"
static func eq_gm(it) -> int:
	if not (it is Dictionary) or str((it as Dictionary).get("id", "")) != GOLD_MASK_ID:
		return 0
	return maxi(0, int((it as Dictionary).get("gm_stk", 0)))"""),
## 备战席合成(局前棋盘)
("""				var chg_sum: int = 0
				for ri0 in rm:
					chg_sum += eq_chg(bench_inventory[int(ri0)])""",
"""				var chg_sum: int = 0
				var gm_sum: int = 0
				for ri0 in rm:
					chg_sum += eq_chg(bench_inventory[int(ri0)])
					gm_sum += eq_gm(bench_inventory[int(ri0)])"""),
("""				bench_inventory.append(mk_eq(item_id, star + 1, chg_sum))""",
"""				bench_inventory.append(mk_eq(item_id, star + 1, chg_sum, gm_sum))"""),
("""				flat.append({"id": str(b.get("id", "")), "star": int(b.get("star", 1)), "pet": "", "chg": eq_chg(b)})""",
"""				flat.append({"id": str(b.get("id", "")), "star": int(b.get("star", 1)), "pet": "", "chg": eq_chg(b), "gm": eq_gm(b)})"""),
("""					flat.append({"id": str(it.get("id", "")), "star": int(it.get("star", 1)), "pet": str(pet), "chg": eq_chg(it)})""",
"""					flat.append({"id": str(it.get("id", "")), "star": int(it.get("star", 1)), "pet": str(pet), "chg": eq_chg(it), "gm": eq_gm(it)})"""),
("""				nb.append(mk_eq(str(it["id"]), int(it["star"]), int(it.get("chg", 0))))""",
"""				nb.append(mk_eq(str(it["id"]), int(it["star"]), int(it.get("chg", 0)), int(it.get("gm", 0))))"""),
("""				(ne[it["pet"]] as Array).append(mk_eq(str(it["id"]), int(it["star"]), int(it.get("chg", 0))))""",
"""				(ne[it["pet"]] as Array).append(mk_eq(str(it["id"]), int(it["star"]), int(it.get("chg", 0)), int(it.get("gm", 0))))"""),
("""		var m_chg: int = 0
		for mi2 in pick:
			m_chg += int((flat[mi2] as Dictionary).get("chg", 0))
		var merged: Dictionary = mk_eq(m_id, m_star + 1, m_chg)""",
"""		var m_chg: int = 0
		var m_gm: int = 0
		for mi2 in pick:
			m_chg += int((flat[mi2] as Dictionary).get("chg", 0))
			m_gm += int((flat[mi2] as Dictionary).get("gm", 0))
		var merged: Dictionary = mk_eq(m_id, m_star + 1, m_chg, m_gm)"""),
## 背包三合一(真打用的这条)
("""			var chg_sum: int = 0
			var host_pet := \"\"""",
"""			var chg_sum: int = 0
			var gm_sum: int = 0                           # 135 黄金面具: 三件的层数相加(11-27)
			var host_pet := \"\""""),
("""					chg_sum += eq_chg(persistent_bench[bi])   # ★093: 删之前先取充能""",
"""					gm_sum += eq_gm(persistent_bench[bi])
					chg_sum += eq_chg(persistent_bench[bi])   # ★093: 删之前先取充能"""),
("""							chg_sum += eq_chg(eqs[ei])   # ★093: 删之前先取充能""",
"""							gm_sum += eq_gm(eqs[ei])
							chg_sum += eq_chg(eqs[ei])   # ★093: 删之前先取充能"""),
("""								chg_sum += eq_chg(meqs[mei])   # ★093: 删之前先取充能""",
"""								gm_sum += eq_gm(meqs[mei])
								chg_sum += eq_chg(meqs[mei])   # ★093: 删之前先取充能"""),
("""				persistent_equipped[host_pet].append(mk_eq(iid, star + 1, chg_sum))""",
"""				persistent_equipped[host_pet].append(mk_eq(iid, star + 1, chg_sum, gm_sum))"""),
("""				heq.append(mk_eq(iid, star + 1, chg_sum))""",
"""				heq.append(mk_eq(iid, star + 1, chg_sum, gm_sum))"""),
("""				persistent_bench.append(mk_eq(iid, star + 1, chg_sum))""",
"""				persistent_bench.append(mk_eq(iid, star + 1, chg_sum, gm_sum))"""),
])

patch("scripts/gamedata/econ_ledger.gd", [
("""			var d: Dictionary = (it as Dictionary).duplicate(true)
			d.erase("chg")""",
"""			var d: Dictionary = (it as Dictionary).duplicate(true)
			d.erase("chg")
			d.erase("gm_stk")   # 135 黄金面具层数: 战斗里挣的进度(同 chg), 服务器结果单 gold_new 那条链管, 不是买卖(11-27)"""),
])

patch("scripts/systems/equip/eq_mask_batch.gd", [
("""## 本场层数账的键: 一方 + 龟 + 份号(换路后同一只龟、同一件拿到同一个键)""",
"""## 这一局一方的黄金面具每件新涨的层数 ⇒ 裁判结果单 gold_new / gold_new_b({"<龟 id>|<份号>": 层数}; 11-27 · 迁移 20261127b)。
##   小将身上的不写回(小将的装备按路 / 槽位存, 同 id 两只会撞键; 局内照样涨)。
func gold_new_of(side: String) -> Dictionary:
	var out := {}
	var keys: Array = gold_gain.keys()
	keys.sort()
	for k in keys:
		var parts: PackedStringArray = str(k).split("|")
		if parts.size() != 3 or parts[0] != side or parts[1] == "__minion__" or int(gold_gain[k]) <= 0:
			continue
		out["%s|%s" % [parts[1], parts[2]]] = int(gold_gain[k])
	return out


## 本场层数账的键: 一方 + 龟 + 份号(换路后同一只龟、同一件拿到同一个键)"""),
])

patch("scripts/referee/referee_runner.gd", [
("""		res["ritual_new_b"] = int(battle._equip_sys._dagger_sys.ritual_new["right"])
""",
"""		res["ritual_new_b"] = int(battle._equip_sys._dagger_sys.ritual_new["right"])
		## 135 黄金面具(2026-11-27 · 迁移 20261127b): 这一局两侧每件新涨的层数, 客户端写回那一件(跨对局保留)
		res["gold_new"] = battle._equip_sys._mask_sys.gold_new_of("left")
		res["gold_new_b"] = battle._equip_sys._mask_sys.gold_new_of("right")
"""),
])

patch("scripts/referee/referee_job.gd", [
("""	if key.get("b_ritual") is float or key.get("b_ritual") is int:
		b["ritual_marks"] = ritual_cap(BE.ghost_ritual_marks(b), key["b_ritual"])
""",
"""	if key.get("b_ritual") is float or key.get("b_ritual") is int:
		b["ritual_marks"] = ritual_cap(BE.ghost_ritual_marks(b), key["b_ritual"])
	## 135 黄金面具层数(2026-11-27 · 迁移 20261127b): 快照里各件 gm_stk 合计压到服务器结果单合计(key.b_gold)以内
	if key.get("b_gold") is float or key.get("b_gold") is int:
		gold_cap(b, key["b_gold"])
"""),
("""	if key.get("a_ritual") is float or key.get("a_ritual") is int:
		st["ritual_marks"] = ritual_cap(int(st["ritual_marks"]), key["a_ritual"])
""",
"""	if key.get("a_ritual") is float or key.get("a_ritual") is int:
		st["ritual_marks"] = ritual_cap(int(st["ritual_marks"]), key["a_ritual"])
	if key.get("a_gold") is float or key.get("a_gold") is int:   # 135 黄金面具层数: 左方同一条封顶(已穿 + 小将)
		gold_cap(st, key["a_gold"])
"""),
("""## 命运之轮层数封顶: 每种花色取「自报」与「服务器结果单合计」的较小值(迁移 20261109d)。""",
"""## 135 黄金面具层数封顶(2026-11-27 · 迁移 20261127b): 按固定顺序走一遍(字典键排序), 把各件 gm_stk 依次扣到合计 ≤ 服务器合计。
##   原地改; 返回封顶后的合计。层数只会被压低, 不会凭空变多。
static func gold_cap(root, server) -> int:
	var left: int = maxi(0, int(maxf(0.0, float(server))))
	var items: Array = []
	_gold_items(root, items)
	var total := 0
	for it in items:
		var v: int = maxi(0, int((it as Dictionary).get("gm_stk", 0)))
		var keep: int = mini(v, left)
		left -= keep
		total += keep
		if keep > 0:
			(it as Dictionary)["gm_stk"] = keep
		else:
			(it as Dictionary).erase("gm_stk")
	return total


static func _gold_items(v, out: Array) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		if str(d.get("id", "")) == "p2eq_135" and d.has("gm_stk"):
			out.append(d)
			return
		var ks: Array = d.keys()
		ks.sort()
		for k in ks:
			_gold_items(d[k], out)
	elif v is Array:
		for x in v:
			_gold_items(x, out)


## 命运之轮层数封顶: 每种花色取「自报」与「服务器结果单合计」的较小值(迁移 20261109d)。"""),
])

patch("scripts/net/referee_net.gd", [
("""		"ritual_new": parse_ritual(d.get("ritual_new", null)),
		"error": """,
"""		"ritual_new": parse_ritual(d.get("ritual_new", null)),
		"gold_new": parse_gold(d.get("gold_new", null)),
		"error": """),
("""## 纯函数: 回包里的 `ritual_new`(20261125 起: 这一局我方 114 仪式匕首新刻的血契道数)→ 整数。缺 / 形状不对 ⇒ 0(什么都不发)。""",
"""## 纯函数: 回包里的 `gold_new`(20261127b 起: 这一局我方 135 黄金面具每件新涨的层数 {"<龟 id>|<份号>": 层数})→ 字典。
##   缺 / 形状不对 / 值不是正数 ⇒ 丢掉那一项; 单件单局按 50 夹(同服务器封顶求和)。
static func parse_gold(v) -> Dictionary:
	var out := {}
	if not (v is Dictionary):
		return out
	for k in v:
		var n = (v as Dictionary)[k]
		if not (n is int or n is float) or is_nan(float(n)) or is_inf(float(n)) or float(n) < 1.0:
			continue
		if str(k).split("|").size() != 2:
			continue
		out[str(k)] = clampi(int(n), 1, 50)
	return out


## 纯函数: 回包里的 `ritual_new`(20261125 起: 这一局我方 114 仪式匕首新刻的血契道数)→ 整数。缺 / 形状不对 ⇒ 0(什么都不发)。"""),
("""		"bamboo_new": parse_bamboo(d.get("bamboo_new", null)), "ritual_new": parse_ritual(d.get("ritual_new", null))}""",
"""		"bamboo_new": parse_bamboo(d.get("bamboo_new", null)), "ritual_new": parse_ritual(d.get("ritual_new", null)),
		"gold_new": parse_gold(d.get("gold_new", null))}"""),
])

patch("scripts/systems/replay/referee_watch.gd", [
("""	apply_ritual(gs, st)                       # 服务器那一局里 114 仪式匕首新刻的血契(2026-11-25)
""",
"""	apply_ritual(gs, st)                       # 服务器那一局里 114 仪式匕首新刻的血契(2026-11-25)
	apply_gold(gs, st)                         # 服务器那一局里 135 黄金面具每件新涨的层数(2026-11-27)
"""),
("""			var rt_c: bool = apply_ritual(GameState, res)   # 仪式匕首血契(2026-11-25), 同上
			if ch_c or in_c or bm_c or rt_c:""",
"""			var rt_c: bool = apply_ritual(GameState, res)   # 仪式匕首血契(2026-11-25), 同上
			var gm_c: bool = apply_gold(GameState, res)     # 黄金面具层数(2026-11-27), 同上
			if ch_c or in_c or bm_c or rt_c or gm_c:"""),
("""	apply_ritual(gs, st)
	gs.battles_total += 1""",
"""	apply_ritual(gs, st)
	apply_gold(gs, st)
	gs.battles_total += 1"""),
("""static func apply_wheel(gs, st: Dictionary) -> bool:""",
"""## 服务器那一局我方 135 黄金面具每件新涨的层数 ⇒ 写回背包里那一件的 gm_stk(2026-11-27 · 方案书 20261125c §5; 跨对局保留、只记在这一件上)。
##   键 = "<龟 id>|<份号>": 份号 = 那只龟身上第几件黄金面具(EquipCk, 与局内同一口径)。找不到那一件(已卖 / 已换下)⇒ 那一项丢掉。
##   ★服务端没传这个键(迁移没上 / 老裁判)⇒ 什么都不发。
static func apply_gold(gs, st: Dictionary) -> bool:
	var g = st.get("gold_new", {})
	if not (g is Dictionary) or (g as Dictionary).is_empty() or not (gs.persistent_equipped is Dictionary):
		return false
	var hit := false
	for k in g:
		var parts: PackedStringArray = str(k).split("|")
		if parts.size() != 2 or not (gs.persistent_equipped as Dictionary).has(parts[0]):
			continue
		var seen := {}
		for it in (gs.persistent_equipped[parts[0]] as Array):
			if not (it is Dictionary) or str((it as Dictionary).get("id", "")) != "p2eq_135":
				continue
			if EquipCk.ck_next(seen, "p2eq_135") == parts[1]:
				(it as Dictionary)["gm_stk"] = maxi(0, int((it as Dictionary).get("gm_stk", 0))) + int(g[k])
				hit = true
				break
	return hit


static func apply_wheel(gs, st: Dictionary) -> bool:"""),
])

patch("scripts/systems/equip/eq_bomb_batch.gd", [
("""	var d := {"id": str(it["id"]), "star": int(it.get("star", 1)), "chg": chg}
	if it.get("mines") is Array:""",
"""	var d := {"id": str(it["id"]), "star": int(it.get("star", 1)), "chg": chg}
	if int(it.get("gm_stk", 0)) > 0:
		d["gm_stk"] = int(it["gm_stk"])   # 135 黄金面具层数跟着这一件进战斗(11-27; 原来这里重建字典会把它丢掉)
	if it.get("mines") is Array:"""),
])
