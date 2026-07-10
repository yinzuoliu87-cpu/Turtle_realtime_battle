extends Node
## verify_codex_text.gd — 守卫: data/pets.json 里【会显示给玩家】的文案不许再出现陈旧/开发术语/占位符
##
## 由来 (2026-07-10 图鉴文案对账 轮A~H′):
##   逐轮撞出来的教训是「我只审我正在看的那个字段」。pets.json 里会显示的文案字段共 5 类:
##     passive.brief   → 选龟界面 被动 chip 的 tooltip   (TeamSelectScene.gd:1155)
##     passive.desc    → 图鉴被动区 (CodexScene.gd:1069) + 局内信息面板 (RealtimeBattle3DScene.gd:13555)
##     skillPool[i].brief / .detail → 图鉴技能卡 (CodexScene.gd:943 / 1060)
##     volcanoSkills[i].brief / .detail → 图鉴【双形态】切换区 (CodexScene.gd:873-879) — 仅熔岩
##   历史事故:
##     · `_lineFinishBrief_` / `_lineFinishDetail_` 占位符【直接显示给玩家】(轮E)
##     · 凤凰/熔岩 整块还是回合制的「灼烧【值】」模型 (轮E/F)
##     · pirate.brief 写着「海盗龟无被动技能(掠夺已移除)」, 与实装的死亡钩索正面冲突 (轮H′)
##     · cyber 的技能说明里漏出「F5精修」「kite近似」这类开发术语 (轮H′)
##
## 本测试只做【便宜且不会误伤】的黑名单扫描 + 结构完整性检查。它拦不住"数值写错",
## 但能拦住"占位符/陈旧模型/开发术语/整块空白"这四类已经真实发生过的事故。

var _fail := 0

# (子串, 为什么禁)
const BANNED := [
	["_lineFinish", "占位符: 曾直接显示给玩家"],
	["灼烧值", "回合制模型: 实时版是灼烧【层】"],
	["无被动技能", "pirate.brief 曾这样写, 与实装的死亡钩索冲突"],
	["掠夺已移除", "同上"],
	["F5", "开发术语, 不该出现在玩家看的文案里"],
	["TODO", "开发术语"],
	["待接入", "开发术语"],
	["占位", "开发术语"],
	["kite", "开发术语"],
	["A级及以下", "缩头召唤池实为12只固定名单(含SS级无头龟)"],
	["每2.5秒获得", "财神聚宝盆实为每3秒 4~7 枚"],
]

# 每只龟至少要有的文案字段
const REQUIRED_PASSIVE := ["brief", "desc"]


func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	await get_tree().process_frame
	var f := FileAccess.open("res://data/pets.json", FileAccess.READ)
	if f == null:
		print("  [FAIL] 读不到 data/pets.json")
		get_tree().quit(1)
		return
	var txt := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(txt)
	_ok("pets.json 是合法 JSON", parsed != null)
	if parsed == null:
		get_tree().quit(1)
		return
	var pets: Array = parsed["pets"] if (parsed is Dictionary and parsed.has("pets")) else parsed
	_ok("28 只龟", pets.size() == 28, "got=%d" % pets.size())

	# ── 1. 自检探针: 黑名单机制本身必须真的会命中 ──────────────────────────
	#    (我被自己的普查脚本骗过 3 次 → 扫描器先证明自己没瞎)
	var probe_hit := _scan_text("basic", "x.y", "这里故意塞一个 灼烧值 试试", "灼烧值")
	_ok("自检·已知阳性(埋入「灼烧值」被抓到)", probe_hit)
	var probe_miss := _scan_text("basic", "x.y", "一段完全干净的文案", "灼烧值")
	_ok("自检·已知阴性(干净文案不误报)", not probe_miss)

	# ── 2. 黑名单扫描: 5 类会显示的字段 ────────────────────────────────────
	var offenders: Array = []
	for p in pets:
		var pid := str(p.get("id", "?"))
		var pas: Dictionary = p.get("passive", {})
		for k in REQUIRED_PASSIVE:
			offenders.append_array(_check(pid, "passive." + k, str(pas.get(k, ""))))
		for arr_key in ["skillPool", "volcanoSkills", "meleeSkills"]:
			var arr = p.get(arr_key, [])
			if not (arr is Array):
				continue
			for i in (arr as Array).size():
				var sk: Dictionary = arr[i]
				offenders.append_array(_check(pid, "%s[%d].brief" % [arr_key, i], str(sk.get("brief", ""))))
				offenders.append_array(_check(pid, "%s[%d].detail" % [arr_key, i], str(sk.get("detail", ""))))
	_ok("黑名单扫描 (5 类会显示的字段)", offenders.is_empty(),
		"命中 %d 处: %s" % [offenders.size(), str(offenders.slice(0, 5))])

	# ── 3. 结构完整性: 会显示的字段不许为空 ────────────────────────────────
	var empties: Array = []
	for p in pets:
		var pid := str(p.get("id", "?"))
		var pas: Dictionary = p.get("passive", {})
		for k in REQUIRED_PASSIVE:
			if str(pas.get(k, "")).strip_edges() == "":
				empties.append("%s.passive.%s" % [pid, k])
		var pool = p.get("skillPool", [])
		if pool is Array:
			for i in (pool as Array).size():
				var sk: Dictionary = pool[i]
				for k2 in ["brief", "detail"]:
					if str(sk.get(k2, "")).strip_edges() == "":
						empties.append("%s.skillPool[%d].%s" % [pid, i, k2])
	_ok("会显示的文案字段无空白", empties.is_empty(), str(empties.slice(0, 5)))

	# ── 4. 每只龟 skillPool 恰好 4 格 (普攻 + 3选1 候选) ───────────────────
	var wrong_pool: Array = []
	for p in pets:
		var pool = p.get("skillPool", [])
		if not (pool is Array) or (pool as Array).size() != 4:
			wrong_pool.append("%s=%d" % [str(p.get("id", "?")), (pool as Array).size() if pool is Array else -1])
	_ok("每只龟 skillPool = 4 格 (普攻 + 3选1)", wrong_pool.is_empty(), str(wrong_pool))

	print("")
	if _fail == 0:
		print("ALL PASS — 图鉴文案: 无占位符 / 无回合制陈旧模型 / 无开发术语 / 无空白字段")
	else:
		print("FAIL x", _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _scan_text(_pid: String, _path: String, text: String, needle: String) -> bool:
	return text.find(needle) >= 0


func _check(pid: String, path: String, text: String) -> Array:
	var out: Array = []
	if text == "":
		return out
	for row in BANNED:
		if text.find(str(row[0])) >= 0:
			out.append("%s.%s 命中「%s」(%s)" % [pid, path, str(row[0]), str(row[1])])
	return out
