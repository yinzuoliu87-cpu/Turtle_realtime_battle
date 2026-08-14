extends Node
## verify_talisman_089.gd — 089 蚀月符纸的【专属判据】(2026-08-14)
##
## ★由来: `verify_staff_active_isolated` 里 089 是唯一没解掉的一件, 被显式登记为
##   "本判据量不到"。查根因(读代码, 不是猜): 它的主动是【贴符纸】,
##   之后每 1 秒对目标掉血 **+ 削魔抗 1 点/跳**, 持续 15 秒, 目标死亡转移剩余时长。
##   ⇒ 那条门禁的状态向量里【根本没有魔抗这一维】, 所以量不到 —— 不是 089 坏了。
##   这正是"判据选错层"的又一例, 与 v0.19.141 凤凰那次同族。
##
## ★本条判据全部落在【产品自己的账】上:
##   · `EqArcaneBatch._talismans` —— 符纸登记表(产品自己维护的)
##   · 目标的 `mr` —— 每跳削掉 TALISMAN_MR_PER_TICK, 期望值从常量推导
##   · 目标的血 —— 每跳掉血
## ★不数我插的标记, 不用哈希, 不用节点计数。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Arcane := preload("res://scripts/systems/equip/eq_arcane_batch.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fail += 1


func _ready() -> void:
	await get_tree().process_frame
	print("=== 089 蚀月符纸: 专属判据 ===")
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var c: Vector2 = s.ARENA.position + s.ARENA.size * 0.5
	var arc = s._equip_sys._arcane_sys

	var u: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-100, 0))
	u["atk"] = 150.0
	u["no_basic"] = true
	u["no_move"] = true
	u["equips"] = [{"id": "p2eq_089", "star": 3}]
	u["eq_state"] = {"p2eq_089": {}}
	var e: Dictionary = s._spawn._make_unit("basic", "right", c + Vector2(100, 0))
	e["maxHp"] = 1.0e7
	e["hp"] = 1.0e7
	e["mr"] = 100.0
	e["base_mr"] = 100.0
	e["no_basic"] = true
	e["no_move"] = true
	s._units.clear()
	s._units.append_array([u, e])
	s._edit_mode = false
	s._over = false
	s._equip_sys._stats._eq_apply_all_stats()

	# ── ① 分母: 开场没有任何符纸 ────────────────────────────────────────────
	arc._talismans.clear()
	_ok("★分母: 开场符纸登记表是空的", arc._talismans.is_empty(),
		"符纸 %d 张" % arc._talismans.size())
	var mr0: float = float(e["mr"])
	var hp0: float = float(e["hp"])
	_ok("★分母: 目标起始魔抗 %.0f" % mr0, mr0 > 0.0, "mr=%.1f" % mr0)

	# ── ② 走【真入口】灌满法力 ⇒ 符纸真的贴上去了 ──────────────────────────
	##   ★不直接调 `on_mana_full` —— 那会绕过"法力条满才触发"这条链, 而那正是要验的。
	s._staff_syn.add_mana(u, s._staff_syn.mana_full_for(u, "p2eq_089", 3) + 1.0)
	_ok("★★法力满 ⇒ 符纸【真的贴上去了】(登记表 0 → %d)" % arc._talismans.size(),
		arc._talismans.size() >= 1, "符纸 %d 张" % arc._talismans.size())
	if arc._talismans.size() >= 1:
		var t0: Dictionary = arc._talismans[0]
		_ok("★★贴的是【那个敌人】(不是随便贴一张)",
			t0.has("tgt") and is_same(t0["tgt"], e),
			"tgt 是那只敌人=%s" % str(t0.has("tgt") and is_same(t0["tgt"], e)))

	# ── ③ 每跳削魔抗 = TALISMAN_MR_PER_TICK(期望值从常量推导) ────────────────
	##   ★推进 1 个结算节拍。用 sim 时钟 + 真实帧(符纸 tick 挂在 arcane 的 tick 上)。
	var beats := 3
	for _f in range(int(Arcane.TALISMAN_TICK * float(beats) * 60.0) + 6):
		s._sim_step(1.0 / 60.0, false, false)
		await get_tree().process_frame
	var shred: float = mr0 - float(e["mr"])
	var want: float = Arcane.TALISMAN_MR_PER_TICK * float(beats)
	_ok("★★%d 跳后魔抗被削 %.1f 点(应 %d × %.1f = %.1f)"
			% [beats, shred, beats, Arcane.TALISMAN_MR_PER_TICK, want],
		absf(shred - want) < Arcane.TALISMAN_MR_PER_TICK + 0.01,
		"mr %.1f → %.1f (削 %.1f, 应 ≈%.1f)" % [mr0, float(e["mr"]), shred, want])
	_ok("★★符纸期间目标【也在掉血】", float(e["hp"]) < hp0 - 0.5,
		"血 %.0f → %.0f (掉 %.0f)" % [hp0, float(e["hp"]), hp0 - float(e["hp"])])

	# ── ④ 反面: 法力【没满】就不该贴符纸 ────────────────────────────────────
	arc._talismans.clear()
	var u2: Dictionary = s._spawn._make_unit("basic", "left", c + Vector2(-200, 0))
	u2["atk"] = 150.0
	u2["no_basic"] = true
	u2["no_move"] = true
	u2["equips"] = [{"id": "p2eq_089", "star": 3}]
	u2["eq_state"] = {"p2eq_089": {}}
	s._units.append(u2)
	s._equip_sys._stats._eq_apply_all_stats()
	s._staff_syn.add_mana(u2, s._staff_syn.mana_full_for(u2, "p2eq_089", 3) * 0.5)
	_ok("★反面: 法力只到一半 ⇒ 一张符纸都不该贴", arc._talismans.is_empty(),
		"符纸 %d 张" % arc._talismans.size())

	# ── ⑤ 时长上限: 15 秒后符纸应当到期离场 ────────────────────────────────
	arc._talismans.clear()
	s._staff_syn.add_mana(u2, s._staff_syn.mana_full_for(u2, "p2eq_089", 3) + 1.0)
	var n_after_fire: int = arc._talismans.size()
	_ok("★分母: 灌满后确实贴上了 %d 张" % n_after_fire, n_after_fire >= 1)
	## ★★符纸的 `el` 跟的是【真实帧的 delta】, 不是我推的 sim 步 ——
	##   探针实测: 推 1020 个 sim 步(=17 秒游戏时间)但只 await 510 帧时, `el` 才 2.48。
	##   ⇒ 想让它到期就必须**逐帧 await 够 15 秒的真实帧**, 光推 sim 时钟没用。
	##   (这与 CLAUDE.md §3.5 那条同源: 尺子必须匹配被测对象用的时钟。)
	var guard := 0
	while arc._talismans.size() >= n_after_fire and guard < 4000:
		s._sim_step(1.0 / 60.0, false, false)
		await get_tree().process_frame
		guard += 1
	if arc._talismans.size() > 0:
		var tl0: Dictionary = arc._talismans[0]
		print("    [探针] el=%.2f ticks=%d (到期需 el>=%.0f 且 ticks>=%d)"
			% [float(tl0.get("el", 0.0)), int(tl0.get("ticks", 0)),
			   Arcane.TALISMAN_SEC, int(Arcane.TALISMAN_SEC / Arcane.TALISMAN_TICK)])
	_ok("★★超过 %.0f 秒后符纸【到期离场】(不是永久贴着)" % Arcane.TALISMAN_SEC,
		arc._talismans.size() < n_after_fire,
		"符纸 %d → %d" % [n_after_fire, arc._talismans.size()])

	s._units.clear()
	s.set_process(false)
	await get_tree().process_frame
	s.queue_free()
	print("")
	print("  (共 %d 条断言)" % _n)
	if _fail == 0:
		print("ALL PASS — 089 蚀月符纸")
	else:
		print("FAIL x%d" % _fail)
	get_tree().quit()
