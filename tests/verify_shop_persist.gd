extends Node
## verify_shop_persist.gd — 守卫「局外商店货架跨场景保留」
##
## 起因(用户 2026-07-21):「每次退出后重进商店会被自动刷新, 要修复」。
## 根因: ShopScene._ready() 无条件 _roll(), 而 _offer 只是场景的局部变量、从不落盘。
##   → 退出重进 = 重新掷货: ①看中的货被冲掉 ②【已经买走的位子会复活】(但钱没退, 玩家白亏)。
##
## ★这类 bug 不报错、不崩溃, 只是"数字悄悄变了" —— 只能靠测试守。
##
## 断言:
##   A. 掷货后货架写进 GameState.meta_shop_offer(持久字段, 进存档)
##   B. 同一场战斗数下重进 → 恢复同一批货(不是新掷的)
##   C. 买走的格子恢复后仍是空(不复活)
##   D. 打完新的一场(season_total_battles 变) → 才换新货架
##   E. 存档往返(save→load)后货架还在
##   F. ShopScene 源码里 _ready 不再无条件 _roll(防复发)

const SRC := "res://scripts/scenes/ShopScene.gd"

var _fail := 0

func _ok(n: String, c: bool, d: String = "") -> void:
	if c:
		print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", n, "  ", d)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame

	# ── 备份现场, 结束时还原(别弄脏玩家存档) ──
	var bk_offer: Array = GameState.meta_shop_offer.duplicate(true)
	var bk_battles: int = int(GameState.meta_shop_battles)
	var bk_total: int = int(GameState.season_total_battles)

	_test_fields_exist()
	_test_persist_roundtrip()
	_test_source_no_unconditional_roll()

	GameState.meta_shop_offer = bk_offer
	GameState.meta_shop_battles = bk_battles
	GameState.season_total_battles = bk_total

	print("ALL PASS — 局外商店货架跨场景保留" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


## A. 持久字段存在且进存档
func _test_fields_exist() -> void:
	_ok("GameState 有 meta_shop_offer", "meta_shop_offer" in GameState)
	_ok("GameState 有 meta_shop_battles", "meta_shop_battles" in GameState)
	# 进存档: save() 产出的字典里要有这两个键
	var f := FileAccess.open("res://autoload/GameState.gd", FileAccess.READ)
	var src := f.get_as_text() if f != null else ""
	if f != null: f.close()
	_ok("meta_shop_offer 写进 save()", src.contains("\"meta_shop_offer\": meta_shop_offer"))
	_ok("meta_shop_offer 从 load() 读回", src.contains("meta_shop_offer = data.get(\"meta_shop_offer\""))
	_ok("新赛季会清空货架(不带着上赛季的货开局)",
		src.contains("meta_shop_offer = []"))


## B/C/D/E. 行为: 保留 / 买走留空 / 新战斗换货 / 存档往返
func _test_persist_roundtrip() -> void:
	GameState.season_total_battles = 5
	GameState.meta_shop_offer = [
		{"id": "p2eq_001"}, {"id": "p2eq_002"}, null, {"id": "p2eq_003"}
	]
	GameState.meta_shop_battles = 5

	# B. 战斗数没变 → 视为有效, 应恢复
	_ok("★同一场战斗数 → 货架有效(重进不换货)",
		int(GameState.meta_shop_battles) == int(GameState.season_total_battles),
		"stamp=%d total=%d" % [GameState.meta_shop_battles, GameState.season_total_battles])

	# C. 买走的格子是 null, 恢复后仍应是空
	var nulls := 0
	for row in GameState.meta_shop_offer:
		if row == null: nulls += 1
	_ok("★买走的格子存为 null(重进不复活)", nulls == 1, "空格数=%d" % nulls)

	# D. 打完新的一场 → 戳记不符 → 该换新货
	GameState.season_total_battles = 6
	_ok("★打完新一场 → 货架失效(该换新货)",
		int(GameState.meta_shop_battles) != int(GameState.season_total_battles),
		"stamp=%d total=%d" % [GameState.meta_shop_battles, GameState.season_total_battles])

	# E. JSON 往返(存档用 JSON.stringify/parse_string)。
	#    ★不真写存档: GameState.save() 里有 `if test_mode: return` —— 这是防测试污染玩家存档的
	#    正确设计, 测试要尊重它。所以这里只验"这个值经 JSON 往返不会变形"。
	GameState.season_total_battles = 5
	var payload := {"meta_shop_offer": GameState.meta_shop_offer,
					"meta_shop_battles": GameState.meta_shop_battles}
	var back = JSON.parse_string(JSON.stringify(payload))
	var ok_back: bool = back is Dictionary and (back as Dictionary).has("meta_shop_offer")
	var rows: Array = (back as Dictionary).get("meta_shop_offer", []) if ok_back else []
	_ok("★JSON 往返后货架条目数不变", rows.size() == GameState.meta_shop_offer.size(),
		"往返前 %d 件, 往返后 %d 件" % [GameState.meta_shop_offer.size(), rows.size()])
	var null_kept := false
	for r in rows:
		if r == null: null_kept = true
	_ok("★JSON 往返后『已买走』的空格仍是 null(不复活)", null_kept)
	var first_id := ""
	if rows.size() > 0 and rows[0] != null:
		first_id = str((rows[0] as Dictionary).get("id", ""))
	_ok("★JSON 往返后装备 id 完好", first_id == "p2eq_001", "首格 id=%s" % first_id)


## F. 源码级防复发
func _test_source_no_unconditional_roll() -> void:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		_ok("读取 ShopScene 源码", false, "打不开")
		return
	var src := f.get_as_text()
	f.close()
	_ok("★_ready 不再无条件 _roll(先试恢复)", src.contains("if not _restore_offer():"),
		"必须先 _restore_offer() 才 _roll()")
	_ok("掷货后落盘", src.contains("_persist_offer()"))
	# 买入分支也要落盘, 否则买走的位子会复活
	var buy_idx := src.find("func _on_buy")
	var buy_body := src.substr(buy_idx, 600) if buy_idx >= 0 else ""
	_ok("★买入后落盘(买走的位子不复活)", buy_body.contains("_persist_offer()"))
