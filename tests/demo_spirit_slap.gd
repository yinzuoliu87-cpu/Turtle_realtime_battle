extends Node
## demo_spirit_slap.gd — 【验收场景 A1/A2/A3】灵物羁绊·触手拍击
##
## 用户 2026-08-21:「验收也是我一个个验收，需要你提前配置好所有需要的演出场景，假人，友军等等」
## ⇒ 这个场景【开箱即用】: 环境、假人、友军、血量、相机全部配好, 启动就能看。
##
## 怎么跑:
##   <godot> --path . res://tests/demo_spirit_slap.tscn
##   环境变量(都有默认值, 不填也能跑):
##     SPIRIT_TIER=1|2|3|4    看哪一档(默认 1 = 2 件)。档位决定触手根数与伤害倍率
##     SPIRIT_DUMMY_HP=3000   假人锁血(默认 3000, 便于心算 5%)
##     SPIRIT_SECS=24         跑多少秒(默认 24, 够看好几轮拍击)
##
## 配置表(逐条写死, 不靠碰运气):
##   · 我方 1 只带 N 件灵物装备的龟 —— 站桩不动不攻击, 血锁不死
##     ⇒ 场上**唯一的伤害来源就是触手拍击**, 数字不会被普攻污染
##   · 敌方 3 个假人, 全部锁血 SPIRIT_DUMMY_HP、不还手、不移动:
##       ① 零护甲(看未减免的基准值)
##       ② 高护甲 100(看"真的吃护甲了"—— 这是本次改动的核心)
##       ③ 站在射程外(看"射程内没敌人时只攒层不消费")
##   · 相机拉近到触手根部
##
## ★为什么假人要不还手: memory [[fb-clean-vfx-stage-not-squint]] ——
##   fixed 假人不还手是已知配套坑; 会还手就会有别的伤害数字混进来, 看不清哪个是拍击。

const SPIRIT_IDS := ["p2eq_032", "p2eq_025", "p2eq_046", "p2eq_033", "p2eq_034",
	"p2eq_060", "p2eq_061", "p2eq_062", "p2eq_063", "p2eq_064"]
## 各档需要的【不同】灵物件数(与 phase2_types.TYPES["灵物"].tiers 一致)
const TIER_PIECES := [2, 5, 8, 10]

var _scn = null
var _t0 := 0.0
var _last_hp := {}
var _shot_left := 0
var _shot_i := 0


func _env_i(k: String, d: int) -> int:
	return int(OS.get_environment(k)) if OS.has_environment(k) else d


func _ready() -> void:
	await get_tree().process_frame
	get_tree().root.size = Vector2i(1280, 720)
	_scn = load("res://scenes/RealtimeBattle3D.tscn").instantiate()
	add_child(_scn)
	await get_tree().process_frame
	await get_tree().process_frame

	var tier: int = clampi(_env_i("SPIRIT_TIER", 1), 1, 4)
	var dhp: float = float(_env_i("SPIRIT_DUMMY_HP", 3000))
	var secs: float = float(_env_i("SPIRIT_SECS", 24))
	var n_eq: int = TIER_PIECES[tier - 1]

	# 场上清干净: 只留我们自己配的单位
	for u in _scn._units.duplicate():
		var sp = u.get("sprite", null)
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
	_scn._units.clear()

	var cx: float = _scn.ARENA.position.x + _scn.ARENA.size.x * 0.5
	var cy: float = _scn.ARENA.position.y + _scn.ARENA.size.y * 0.5

	# ── 我方: 携带者(站桩·不攻击·血锁不死) ──
	var carrier: Dictionary = _scn._spawn._make_unit("basic", "left", Vector2(cx - 320.0, cy))
	carrier["no_move"] = true
	carrier["no_basic"] = true
	carrier["move_spd"] = 0.0
	carrier["active_skills"] = []
	carrier["deathfloor_until"] = 999999.0
	var eqs: Array = []
	for i in range(n_eq):
		eqs.append({"id": SPIRIT_IDS[i], "star": 1})
	carrier["equips"] = eqs
	_scn._units.append(carrier)

	# ── 敌方三个假人 ──
	## ★★两个必须按【真实对象】来的坑(我第一版全踩了):
	##   ① 护甲字段是 `base_def` 不是 `def` —— 直接写 `def` 会被 `_recalc_stats` 覆盖掉,
	##      表现是"我配了零护甲但实测掉血只有期望的 1/5"。
	##   ② 触手根部**不在携带者身上**, 而在场地宽度 18% 处(`default_root`)。
	##      按携带者摆假人会全摆错 —— 我第一版"射程外"那个反而挨打了。
	##   ⇒ 假人一律相对【触手根部】摆, 并且 ①② 摆在同一条直线上,
	##     这样一次拍击的带状范围能同时覆盖两个 ⇒ 有甲/无甲**同一下**对比, 最干净。
	var root: Vector2 = _scn._tentacle_vfx.default_root("left", 0)
	var rng: float = float(_scn._tentacle_vfx.attack_range_2d)
	var specs := [
		{"dx": 200.0, "dy": 0.0, "def": 0.0, "tag": "①零护甲"},
		{"dx": 340.0, "dy": 0.0, "def": 100.0, "tag": "②护甲100"},
		{"dx": rng + 400.0, "dy": 0.0, "def": 0.0, "tag": "③射程外"},
	]
	for sp2 in specs:
		var d: Dictionary = _scn._spawn._make_unit("basic", "right",
			Vector2(root.x + float(sp2["dx"]), root.y + float(sp2["dy"])))
		d["no_move"] = true
		d["no_basic"] = true
		d["move_spd"] = 0.0
		d["active_skills"] = []
		d["base_def"] = float(sp2["def"])
		d["base_mr"] = 0.0
		_scn._recalc_stats(d)
		d["maxHp"] = dhp
		d["hp"] = dhp
		d["_demo_tag"] = str(sp2["tag"])
		_scn._units.append(d)
		_last_hp[str(sp2["tag"])] = dhp

	## ★★羁绊档位必须【重算】: 我是在 `_make_unit` 之后才把装备塞进 `equips` 的,
	##   而档位是按全阵容的装备 id 去重算出来的、算过一次就存着 ⇒ 不重算的话档位是 0,
	##   触手压根不登场, 更别说拍击。第一版就栽在这: 跑 16 秒一次拍击都没有、层数恒为 0。
	##   (这就是 memory [[fb-gate-subject-never-constructed]] 那一族: 判据没错, 被测对象不在场。)
	## ★★必须先 `clear()` 再 `apply_all()` —— `apply_all` 里有一道 `is_empty()` 守卫,
	##   缓存非空就**不重算**。战斗启动时已按默认队算过一次 ⇒ 我换掉的阵容会被忽略。
	##   实测症状: 敌方档位 = 0、右边那条触手压根不出现(A6 场景第一版就栽在这)。
	##   左边"碰巧"能用只是因为默认左队没羁绊、缓存正好是空的 —— 那是运气不是正确。
	##   正规顺序见 `dual_lane_flow.gd:540`(换路时就是 clear + apply_all)。
	_scn._synergy.clear()
	_scn._synergy.apply_all()
	var _tt: int = _scn._spirit_syn._side_tier("left")
	print("  ★分母自证: 重算后我方灵物档位 = %d (0 就是没配上, 下面什么都不会发生)" % _tt)

	## ══ 相机 ══════════════════════════════════════════════════════
	## ★2026-08-21: 这里原本【只改 fov、没挪相机】= 等于没拉近, 实拍出来触手只有几个像素。
	##   我一度想在这里加"近景模式", **那是死代码** —— `battle_render.gd:425` 每帧无条件
	##   `_cam.position = _cam_zoom_base`, 只写一次 `_cam.position` 下一帧就被冲掉。
	##   (`battle_vfx_lab.gd:69` 早把这个坑写下来了, 我又踩了一遍 = 没先搜仓库。)
	## ⇒ **要看触手形状请用 VFXLAB**, 它是为这件事造的、且已处理相机每帧覆盖:
	##   VFXLAB=1 VFXLAB_CASE=syn_spirit VFXLAB_ZOOM=1.8 VFXLAB_GLOW=1 VFXLAB_HOLD=1
	##   本 demo 只负责**数值**(掉血/层数/护甲), 不负责看画面。
	if _scn._cam != null and is_instance_valid(_scn._cam):
		_scn._cam.fov = 30.0

	print("=== 【验收场景】灵物羁绊·触手拍击 ===")
	print("  档位 %d 档(%d 件灵物) · 触手 %d 根 · 伤害倍率 ×%.2f"
		% [tier, n_eq, _scn._spirit_syn.TENTACLES[tier - 1], _scn._spirit_syn.HIT_MULT[tier - 1]])
	print("  假人锁血 %.0f ⇒ 期望基准 = %.0f%%×%.0f + %.0f = %.0f(未减免)"
		% [dhp, _scn._spirit_syn.HIT_HP_PCT * 100.0, dhp, _scn._spirit_syn.HIT_FLAT,
			dhp * _scn._spirit_syn.HIT_HP_PCT + _scn._spirit_syn.HIT_FLAT])
	print("  ①零护甲 = 基准 × %.2f · ②护甲100 应【明显更低】(这是本次改动的核心) · ③射程外不该掉血"
		% _scn._spirit_syn.HIT_MULT[tier - 1])
	## ★★自证: 直接用产品自己的公式算出"这一下该打多少", 打印出来当对照。
	##   第一版没有这一条, 结果场上 48 的掉血我一度当成拍击 —— 实际那是**灵物装备自己的效果**
	##   (凑档位必须带 N 件真装备, 它们各有各的伤害)。没有对照值就分不清哪个数字是谁打的。
	for u2 in _scn._units:
		if not (u2 is Dictionary) or not u2.has("_demo_tag"):
			continue
		var b2: float = dhp * _scn._spirit_syn.HIT_HP_PCT + _scn._spirit_syn.HIT_FLAT
		## ★暴击必须钉成 0 再算 —— `_resolve_dmg` 会掷 `_battle_rng.randf() < crit`,
		##   不钉的话这行对照值时高时低(实测同一场景一会儿 250 一会儿 375),
		##   验收时和下面那句"实测约 300"直接打架, 看的人只会犯迷糊。
		var _cs: float = float(carrier.get("crit", 0.0))
		carrier["crit"] = 0.0
		var exp2: int = maxi(1, int(_scn._resolve_dmg(carrier, b2, u2, false)
			* _scn._spirit_syn.HIT_MULT[tier - 1]))
		carrier["crit"] = _cs
		print("  %-10s 护甲 %5.1f ⇒ 【拍击应掉 %d】" % [str(u2["_demo_tag"]), float(u2.get("def", 0.0)), exp2])
	print("  ⚠ 其它数字来自灵物装备自身效果(凑档位必须带真装备), 认准上面这个数才是拍击。")
	print('  ⚠ 实测会比上面这个数【再高 20%】—— 携带者是小龟, 被动【不屈】按目标稀有度增伤(C 档 +20%)。')
	print('     所以零护甲实测约 300、护甲100 实测约 85。这两个数差多少, 就是「吃护甲」这件事的效果。')
	print("  跑 %.0f 秒。下面每次掉血都会打印。" % secs)
	print("")
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	set_process(true)


func _process(_d: float) -> void:
	if _scn == null or not is_instance_valid(_scn):
		return
	for u in _scn._units:
		if not (u is Dictionary) or not u.has("_demo_tag"):
			continue
		var tag: String = str(u["_demo_tag"])
		var hp: float = float(u.get("hp", 0.0))
		var prev: float = float(_last_hp.get(tag, hp))
		if hp < prev - 0.5:
			print("  %-10s 掉血 %6.0f   (层数 L0=%d L1=%d)"
				% [tag, prev - hp,
					_scn._spirit_syn.stack_of("left", 0), _scn._spirit_syn.stack_of("left", 1)])
			_last_hp[tag] = hp
			## SPIRIT_SHOT=1: 掉血那一刻起连拍几帧 —— 命中特效只有 0.3 秒左右,
			## 事后随便截一张多半拍到空气(memory: 实拍要等落位, 且要拍对时刻)。
			## ★只在【大额掉血】时连拍 —— 场上还有灵物装备自己的伤害(约 48),
			##   按最亮帧取会拍到装备的金色电柱, 不是拍击(我第一版就抓错了时刻)。
			if OS.has_environment("SPIRIT_SHOT") and _shot_left <= 0 and (prev - hp) > 150.0:
				_shot_left = 32
				_shot_i = 0
	if _shot_left > 0:
		_shot_left -= 1
		var img := get_viewport().get_texture().get_image()
		img.save_png("user://spirit_hit_%02d.png" % _shot_i)
		_shot_i += 1
	var el: float = float(Time.get_ticks_msec()) / 1000.0 - _t0
	if el >= float(_env_i("SPIRIT_SECS", 24)):
		print("")
		print("DEMO DONE")
		get_tree().quit(0)
