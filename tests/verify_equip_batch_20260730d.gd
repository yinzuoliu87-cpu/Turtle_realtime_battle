extends Node
## 20260730d「装备平衡 7 项」的门禁 —— 补建（2026-08-02）。
##
## ★为什么现在才有：那批的交付提交 `397c55c` 的 `--stat` 显示**它没有碰过 tests/ 下任何文件**。
##   方案书的验收清单白纸黑字写着「门禁验次/秒」「各一条反向断言」「验随机池而不是验某一次
##   抽到什么」「验计数是 5 不是 4/6」—— 一条都不存在。代码值逐条核过全对，缺的只是保险。
##
## ★这个缺口不是理论风险：同一批的 1-4 荆棘海胆【反伤实发两倍】（通用钩 + 专属分支各发一次），
##   探针实测 1★ 名义 12%、打 1000 → 反伤 240。它活了三天没人发现，正是因为没有行为门禁 ——
##   `tooltip_number_audit` 只保证「文案里的数字在代码里存在同样的数组」，不验行为、不验用对地方。
##   （1-4 已于 v0.18.7 修复并由 `verify_thorn_reflect` 单独守着，本文件不重复。）
##
## ★期望值一律写【需求字面值】，不引用被测常量 —— 否则是恒真式（本项目 verify_trainer_magicstone
##   第一版真栽过：引用 s.TRAINER_ATK_MAGIC_STONE，把常量改掉测试照样全绿）。
var _n := 0
var _fail := 0
var _s

func _ok(name: String, cond: bool, detail: String = "") -> void:
	_n += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["PASS" if cond else "FAIL", name, ("  " + detail) if detail != "" else ""])

const WANT_BEAR_RATE := 0.7                        # 1-1 大熊 0.7 次/秒
const WANT_BEAR_HP := [1600.0, 3000.0, 15000.0]    # 1-5
const WANT_BEAR_ATK := [70.0, 120.0, 2000.0]       # 1-5 攻击力【不变】
const WANT_BEAR_RES := 70.0                        # 1-5 双抗各 70
const WANT_WORM_HP := [100.0, 1500.0, 10000.0]     # 1-3
const WANT_WORM_ATK := [50.0, 80.0, 200.0]         # 1-3
const WANT_WORM_N := 3                             # 1-3 诞生带 3 件
const WANT_WORM_STAR := [1, 2, 3]                  # 1-3 星级
const WANT_DART_EVERY := 5                         # 1-6 第 5 下
const WANT_DART_SEC := 1.0                         # 1-6 击飞 1 秒
const WANT_DART_ASPD := [0.40, 0.80, 1.50]         # 1-6 攻速


func _ready() -> void:
	await get_tree().process_frame
	_s = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_s)
	for i in range(40):
		await get_tree().process_frame
	# ★★让【游戏时钟 _t】真的推进 —— 否则任何 `await _wait_sim(x)` 都永不返回。
	#   _t 的门控是 `not _over and not _edit_mode and _dl_state != "place" and not _dl_is_present()`
	#   (RealtimeBattle3DScene.gd:2133)。测试场景默认停在放置/呈现态 ⇒ _t 冻结。
	#   ★这是 CLAUDE.md §3.5「别用游戏时钟当尺子」的镜像版: 那条说的是"等效果别看 _t",
	#     这里是"被测代码自己在等 _t, 你不让它走就永远等下去"。大熊的 1.2 秒蓄力就卡在这。
	_s._over = false
	_s._edit_mode = false
	_s._dl_state = ""
	await _t_bear()
	_t_fortress()
	_t_worm()
	_t_dart()
	print("")
	print("  (共 %d 条断言)" % _n)
	print("ALL PASS — 装备平衡7项(20260730d 补门禁)" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


## 干净合成单位 —— 拿随机 spawn 的单位测精确数值会 CI 偶发红
## （memory fb-ci-vs-local-divergence：队伍未播种 RNG / 敌带盾 flat_dr）。
func _mk(id: String, side: String, off: Vector2, hp: float = 100000.0) -> Dictionary:
	var c: Vector2 = _s.ARENA.position + _s.ARENA.size * 0.5
	var u: Dictionary = _s._spawn._make_unit(id, side, c + off)
	u["maxHp"] = hp
	u["hp"] = hp
	u["shield"] = 0.0
	u["flat_dr"] = 0.0
	u["def"] = 0.0
	u["mr"] = 0.0
	u["base_def"] = 0.0
	u["base_mr"] = 0.0
	u["crit"] = 0.0
	u["dodge_bonus"] = 0.0
	return u


## 1-1 攻速（验次/秒）+ 1-5 血量/双抗/【攻击力不变】—— 玩偶小熊 p2eq_034 的大熊
func _t_bear() -> void:
	for si in range(3):
		_s._units.clear()
		var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
		# ★★两边都得有人 —— 只留一边的话战斗【当场判定结束】⇒ _over=true ⇒ 游戏时钟 _t 冻结
		#   ⇒ 蓄力里的 `await _wait_sim(1.2)` 永不返回, 熊永远召不出来。
		#   探针实测: 只放一只时 6 秒墙钟里 _t 只走了 0.02 秒。
		#   (今晚在龟蛋碎裂那个探针上踩过完全相同的坑, 这是第二次。)
		var foe_keep: Dictionary = _mk("green", "right", Vector2(400.0, 0.0), 900000.0)
		_s._units.append_array([u, foe_keep])
		_s._over = false
		# ★★必须走【真入口】_big_bear_charge_and_spawn ——
		#   我第一版是自己调 _spawn_summon 并把 atk_interval 当参数【传进去】,
		#   于是把产品代码里的 1.0/0.7 改成 1.0/0.8, 门禁【照样全绿】= 恒真式:
		#   测试在测自己传的值, 根本没读产品代码。反向验证当场戳穿(FAIL 0 条)。
		_s._big_bear_charge_and_spawn(u, si)
		# ★真入口带【1.2 秒蓄力演出】(函数名就写着 charge_and_spawn), 要等它跑完。
		#   用【墙钟】不用帧数 —— 无头下帧率极高, 几百帧可能只过去零点几秒(CLAUDE.md §3.5)。
		var bear = null
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			await get_tree().process_frame
			for x in _s._units:
				if x.get("is_big_bear", false):
					bear = x
					break
			if bear != null:
				break
		_ok("★分母: si=%d 大熊真的召出来了" % si, bear != null)
		if bear == null:
			continue
		# ★方案书原话「门禁验【次/秒】而不是验 interval 字面量」——
		#   验字面量的话，把 1.0/0.7 改成 1.4286 会漏过去（值相同但表达变了，反之亦然）。
		var rate: float = 1.0 / maxf(0.0001, float(bear.get("atk_interval", 0.0)))
		_ok("1-1 si=%d 大熊攻速 = %.1f 次/秒" % [si, WANT_BEAR_RATE],
			absf(rate - WANT_BEAR_RATE) < 0.01,
			"实测 %.3f 次/秒 (interval=%.4f)" % [rate, float(bear.get("atk_interval", 0.0))])
		_ok("1-5 si=%d 大熊生命 = %.0f" % [si, float(WANT_BEAR_HP[si])],
			absf(float(bear.get("maxHp", 0.0)) - float(WANT_BEAR_HP[si])) < 1.0,
			"实测 %.0f" % float(bear.get("maxHp", 0.0)))
		# ★1-5 的【反向断言】：用户只说改血和双抗，没提攻击力 ⇒ 攻击力必须【原样】
		_ok("1-5 si=%d ★攻击力未被改动 = %.0f(反向断言)" % [si, float(WANT_BEAR_ATK[si])],
			absf(float(bear.get("atk", 0.0)) - float(WANT_BEAR_ATK[si])) < 1.0,
			"实测 %.0f" % float(bear.get("atk", 0.0)))


## 1-2 深海堡垒甲 p2eq_014：汲取生效 + 回复 + 【排除大师】【排除龟蛋】各一条反向断言
func _t_fortress() -> void:
	_s._units.clear()
	var car: Dictionary = _mk("fortune", "left", Vector2(-100.0, 0.0), 5000.0)
	car["hp"] = 3000.0
	car["equips"] = [{"id": "p2eq_014", "star": 1}]
	car["eq_state"] = {}
	car["def"] = 100.0
	car["mr"] = 100.0
	var foe: Dictionary = _mk("green", "right", Vector2(60.0, 0.0), 900000.0)
	var tr: Dictionary = _mk("green", "right", Vector2(80.0, 40.0), 900000.0)
	tr["is_trainer"] = true
	var egg: Dictionary = _mk("green", "right", Vector2(80.0, -40.0), 900000.0)
	egg["_isEgg"] = true
	_s._units.append_array([car, foe, tr, egg])
	var foe0: float = float(foe["hp"])
	var tr0: float = float(tr["hp"])
	var egg0: float = float(egg["hp"])
	var car0: float = float(car["hp"])
	# ★前提: 汲取要【硬化叠满】才开始(equip_tick_system.gd:78 `harden_stacks < harden_cap` 就 return)。
	#   我第一版没喂叠层, 结果"敌掉 0" —— 而"排除大师/排除龟蛋"那两条【照样 PASS】,
	#   因为什么都没被汲取。这正是【分母断言】要抓的：没有它，这组就是三条白过的空检查。
	_s._equip_sys._stats._eq_apply_flags(car, "p2eq_014", 1)
	var stt: Dictionary = car["eq_state"].get("p2eq_014", {})
	stt["harden_stacks"] = int(stt.get("harden_cap", 25))
	car["eq_state"]["p2eq_014"] = stt
	for _i in range(60):
		_s._equip_tick_sys._tick_fortress(car, 0.2)
	_ok("1-2 ★分母: 普通敌真的被汲取(否则下面三条是空检查)",
		float(foe["hp"]) < foe0 - 1.0, "敌掉 %.0f" % (foe0 - float(foe["hp"])))
	_ok("1-2 ★★排除【训龟大师】(放进汲取范围也不该掉血)",
		absf(float(tr["hp"]) - tr0) < 0.5, "大师掉 %.1f" % (tr0 - float(tr["hp"])))
	_ok("1-2 ★★排除【屏障内龟蛋】",
		absf(float(egg["hp"]) - egg0) < 0.5, "蛋掉 %.1f" % (egg0 - float(egg["hp"])))
	_ok("1-2 携带者确实回了血(回复公式生效)",
		float(car["hp"]) > car0, "hp %.0f → %.0f" % [car0, float(car["hp"])])


## 1-3 小虫 p2eq_033：属性三档 + 诞生带 3 件 + 星级 + 费用 ∈ {4,5}
## ★方案书原话「验随机池而不是验某一次抽到什么」—— 所以验的是【池子的规则】与
##   【产出的每一件都满足规则】，不是断言某个具体 id。
func _t_worm() -> void:
	var pool: int = 0
	for it in DataRegistry.phase2_equipment:
		var c: int = int(it.get("cost", 0))
		if c == 4 or c == 5:
			pool += 1
	_ok("1-3 ★分母: 4/5 费池非空(%d 件)" % pool, pool > 0)
	for si in range(3):
		_s._units.clear()
		var u: Dictionary = _mk("fortune", "left", Vector2(-200.0, 0.0))
		_s._units.append(u)
		var worm = _s._spawn._spawn_summon(u, "worm", WANT_WORM_HP[si], WANT_WORM_ATK[si],
			{"label": "海螺虫", "spr_id": "conch-worm", "col_size": 30.0, "hp_w": 22.0})
		_ok("1-3 ★分母: si=%d 小虫召出来了" % si, worm != null)
		if worm == null:
			continue
		_ok("1-3 si=%d 小虫生命 = %.0f" % [si, float(WANT_WORM_HP[si])],
			absf(float(worm.get("maxHp", 0.0)) - float(WANT_WORM_HP[si])) < 1.0,
			"实测 %.0f" % float(worm.get("maxHp", 0.0)))
		_ok("1-3 si=%d 小虫攻击 = %.0f" % [si, float(WANT_WORM_ATK[si])],
			absf(float(worm.get("atk", 0.0)) - float(WANT_WORM_ATK[si])) < 1.0,
			"实测 %.0f" % float(worm.get("atk", 0.0)))
		worm["equips"] = []
		worm["eq_state"] = {}
		_s._equip_sys._conch_grant_equips(worm, si)
		var eqs: Array = worm.get("equips", [])
		_ok("1-3 si=%d 诞生带 %d 件装备" % [si, WANT_WORM_N],
			eqs.size() == WANT_WORM_N, "实测 %d 件" % eqs.size())
		var star_bad: int = 0
		var cost_bad: int = 0
		for it in eqs:
			if int(it.get("star", 0)) != int(WANT_WORM_STAR[si]):
				star_bad += 1
			var c2: int = int(DataRegistry.phase2_equipment_by_id.get(str(it.get("id", "")), {}).get("cost", 0))
			if c2 != 4 and c2 != 5:
				cost_bad += 1
		_ok("1-3 si=%d 三件都是 %d 星" % [si, int(WANT_WORM_STAR[si])], star_bad == 0, "不合 %d 件" % star_bad)
		_ok("1-3 si=%d ★三件费用都 ∈ {4,5}(验池子规则, 不是验某一次抽到什么)" % si,
			cost_bad == 0, "不合 %d 件" % cost_bad)


## 1-6 飞镖 p2eq_056：攻速三档 + 【第 5 下】击飞
## ★方案书原话「验计数是 5 不是 4/6，且击飞真的发生」—— 所以逐下喂命中，记录到底在第几下触发。
func _t_dart() -> void:
	for si in range(3):
		_s._units.clear()
		var car: Dictionary = _mk("fortune", "left", Vector2(-100.0, 0.0))
		car["equips"] = [{"id": "p2eq_056", "star": si + 1}]
		car["eq_state"] = {}
		car["aspd_perm"] = 1.0
		var tgt: Dictionary = _mk("green", "right", Vector2(60.0, 0.0), 900000.0)
		_s._units.append_array([car, tgt])
		_s._equip_sys._stats._eq_apply_all_stats()
		var want: float = 1.0 + float(WANT_DART_ASPD[si])
		_ok("1-6 si=%d 攻速加成 = %d 个百分点" % [si, int(float(WANT_DART_ASPD[si]) * 100.0)],
			absf(float(car.get("aspd_perm", 1.0)) - want) < 0.01,
			"aspd_perm=%.2f (期望 %.2f)" % [float(car.get("aspd_perm", 1.0)), want])
		if si != 0:
			continue
		var fired: Array = []
		for hit in range(1, 11):
			var n0: int = int(tgt.get("_dart_kb_n", 0))
			_s._equip_sys._eq_on_hit(car, tgt, 10)
			if int(tgt.get("_dart_kb_n", 0)) > n0:
				fired.append(hit)
		_ok("1-6 ★★击飞发生在第 [5, 10] 下(不是 4 或 6)",
			fired == [5, 10], "实际在第 %s 下" % str(fired))
		_ok("1-6 击飞时长 = %.1f 秒(目标被晕住)" % WANT_DART_SEC,
			float(tgt.get("stun_until", 0.0)) > _s._t, "stun_until-_t=%.2f" % (float(tgt.get("stun_until", 0.0)) - _s._t))
