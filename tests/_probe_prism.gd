extends Node
## _probe_prism.gd — 彩虹棱镜【实时转化】探针 (用户 2026-07-28)
##
## 只回答四个问题, 打真数字, 不推理:
##   ① 转化值对不对: 攻击力 = 基础 + 10%最大生命 ? 攻速 = 基础/(1+0.3%×最终攻击力) ?
##   ② 【实时】: 中途把 maxHp 抬高, 攻击力与攻速会跟着变吗?
##   ③ 【不翻倍】: 每帧调用, 攻击力会不会一帧一帧涨上去? (delta 记账写错就会)
##   ④ 【不漂移】: 攻速从基准间隔整体重算, 长跑后与"一次性算"的值是否仍相等?
##
## 反向验证(证明这个探针会 FAIL): 把 rainbow_system 的 PRISM_ATK_FROM_HP 改成 0.0 → ①③④ 全红。
##
## 跑法(必须 headless, 本机开 3D 窗口会蓝屏):
##   SHIP=1 DL_AUTOFIGHT=1 TURTLE_SEED=20260728 \
##   <godot> --headless --audio-driver Dummy --path . res://tests/_probe_prism.tscn
##
## ★下划线前缀 = 不进门禁(run-tests.sh 只自动发现 verify_*.gd)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const Rainbow := preload("res://scripts/systems/skills/rainbow_system.gd")

var _fail := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	var dr = get_node_or_null("/root/DataRegistry")
	if gs == null or dr == null:
		print("  [FAIL] 缺 autoload"); get_tree().quit(1); return
	gs.test_mode = true

	print("=== 彩虹棱镜实时转化 探针 ===")
	print("  常数: 攻击力 = %.0f%% 最大生命 | 攻速 = (0.3×攻击力)%% → 每点攻击力 +%.1f%%" % [
		Rainbow.PRISM_ATK_FROM_HP * 100.0, Rainbow.PRISM_ASPD_PER_ATK * 100.0])

	_setup(gs)
	var s = RB.new()
	add_child(s)
	for _i in range(4):
		await get_tree().process_frame

	var u := _find_rainbow(s)
	if u.is_empty():
		print("  [FAIL] 上路没找到彩虹龟"); _done(s); return
	# ★先等转化真的生效再查 —— 双路要先走完总览/预览才真 spawn 战场,
	# 单位字典已存在但 _tick_periodic 还没开始跑。在那之前查会拿到未转化的值→假 FAIL。
	var wait := 0
	while wait < 3000 and float(u.get("_prism_atk_add", 0.0)) <= 0.0:
		await get_tree().process_frame
		wait += 1
	print("  (等了 %d 帧转化才生效 —— 双路预演占掉的)" % wait)
	if float(u.get("_prism_atk_add", 0.0)) <= 0.0:
		print("  [FAIL] 等满 3000 帧转化仍未生效"); _fail += 1; _done(s); return

	# ── ① 转化值 ──
	var hp: float = float(u["maxHp"])
	var add: float = float(u.get("_prism_atk_add", 0.0))
	var iv0: float = float(u.get("_prism_base_iv", 0.0))
	var atk: float = float(u["atk"])
	var iv: float = float(u["atk_interval"])
	print("")
	print("  ① 登场实测")
	print("     最大生命 %.1f  →  棱镜加攻 %.2f  (应 = %.2f)" % [hp, add, hp * Rainbow.PRISM_ATK_FROM_HP])
	print("     最终攻击力 %.2f  (= 基础 %.2f + 棱镜 %.2f)" % [atk, atk - add, add])
	print("     基准间隔 %.4f 秒 → 现间隔 %.4f 秒" % [iv0, iv])
	print("     攻速 %.3f 下/秒 → %.3f 下/秒   (+%.1f%%)" % [1.0 / iv0, 1.0 / iv, (iv0 / iv - 1.0) * 100.0])
	_chk("① 加攻 = 10%最大生命", absf(add - hp * Rainbow.PRISM_ATK_FROM_HP) < 0.01)
	_chk("① 攻速 = 基准/(1+0.3%×最终攻击力)", absf(iv - iv0 / (1.0 + Rainbow.PRISM_ASPD_PER_ATK * atk)) < 1e-6)

	# ── ③ 每帧调用不翻倍 ──
	var atk_a: float = float(u["atk"])
	for _i in range(120):
		await get_tree().process_frame
		if not u.get("alive", false):
			break
	var atk_b: float = float(u["atk"])
	print("")
	print("  ③ 跑 120 帧后: 攻击力 %.2f → %.2f (差 %.4f)" % [atk_a, atk_b, atk_b - atk_a])
	_chk("③ 每帧调用不累加(允许血量变化引起的合理波动 <0.01)", absf(atk_b - atk_a) < 0.01)

	# ── ④ 攻速不漂移: 现值应仍严格等于"从基准一次算出来" ──
	var iv_now: float = float(u["atk_interval"])
	var iv_want: float = float(u["_prism_base_iv"]) / (1.0 + Rainbow.PRISM_ASPD_PER_ATK * float(u["atk"]))
	print("  ④ 攻速现值 %.9f  vs  从基准重算 %.9f  (差 %.12f)" % [iv_now, iv_want, absf(iv_now - iv_want)])
	_chk("④ 长跑后攻速无累积漂移", absf(iv_now - iv_want) < 1e-9)

	# ── ② 实时: 手动抬最大生命, 下一帧应跟着涨 ──
	if u.get("alive", false):
		var hp_old: float = float(u["maxHp"])
		var atk_old: float = float(u["atk"])
		var iv_old: float = float(u["atk_interval"])
		u["maxHp"] = hp_old + 1000.0            # 模拟中途吃到 +1000 血的装备/buff
		await get_tree().process_frame
		await get_tree().process_frame
		print("")
		print("  ② 中途最大生命 %.0f → %.0f" % [hp_old, float(u["maxHp"])])
		print("     攻击力 %.2f → %.2f (应 +%.1f)" % [atk_old, float(u["atk"]), 1000.0 * Rainbow.PRISM_ATK_FROM_HP])
		print("     攻速   %.3f → %.3f 下/秒" % [1.0 / iv_old, 1.0 / float(u["atk_interval"])])
		_chk("② 加血后攻击力实时跟涨", absf(float(u["atk"]) - atk_old - 1000.0 * Rainbow.PRISM_ATK_FROM_HP) < 0.01)
		_chk("② 加血后攻速实时跟涨", float(u["atk_interval"]) < iv_old - 1e-6)
	else:
		print("")
		print("  ② 跳过(彩虹已阵亡) —— 帧数不够或它太脆, 不算 FAIL")

	_done(s)


func _find_rainbow(s) -> Dictionary:
	for u in s._units:
		if str(u.get("id", "")) == "rainbow" and str(u.get("side", "")) == "left":
			return u
	return {}


func _chk(what: String, ok: bool) -> void:
	if not ok:
		_fail += 1
	print("     %s %s" % ["[PASS]" if ok else "[FAIL]", what])


func _done(s) -> void:
	s.queue_free()
	await get_tree().process_frame
	print("")
	print("  ALL PASS" if _fail == 0 else "  ★ %d 项 FAIL" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 左队上路 = 彩虹(带全色风暴) + 2 近战小将; 右队 ghost 同构。与 _duel.gd 同一套结构。
func _setup(gs) -> void:
	gs.reset_dual_lane()
	gs.dual_active = true
	gs.season_level = 5
	gs.hearts = 8
	gs.season_total_battles = 10
	gs.persistent_bench = []
	gs.persistent_equipped = {}
	gs.season_leaders = ["rainbow", "candy", "stone"]
	gs.left_team.assign(gs.season_leaders)
	gs.loadouts = {"rainbow": 2}
	gs.dual_lineup = {
		"top": [
			{"kind": "leader", "id": "rainbow", "slot": 0},
			{"kind": "minion", "role": "front"},
			{"kind": "minion", "role": "front"},
		],
		"bottom": [
			{"kind": "leader", "id": "candy", "slot": 1},
			{"kind": "leader", "id": "stone", "slot": 2},
			{"kind": "minion", "role": "front"},
		],
	}
	gs.dual_ghost = {
		"schema_ver": 1, "ghost_id": "probe_prism", "is_bot": false, "bracket": 4,
		"profile": {"name": "探针", "avatar": "rainbow", "id": "PROBE"},
		"leaders": ["rainbow", "candy", "stone"],
		"lane_assign": {"top": ["rainbow"], "bottom": ["candy", "stone"]},
		"minions": {
			"top": [{"role": "front", "elite": false, "equips": []}, {"role": "front", "elite": false, "equips": []}],
			"bottom": [{"role": "front", "elite": false, "equips": []}],
		},
		"loadouts": {"rainbow": 2}, "equipped": {}, "pet_levels": {},
		"season_total_battles": 10, "season_eggs_killed": 0,
	}
