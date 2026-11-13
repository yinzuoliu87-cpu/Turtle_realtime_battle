class_name EqSummons
extends RefCounted
## 登场召唤类装备: 058 远古炮台 / 032 唤灵骨符(2026-11-13 从 equip_system.gd 搬出 —— 那个文件到了 3000 行架构预算)。
## 外部仍走 EquipSystem 的同名转发(`_eq_summon_turret` / `_tick_eq_turret` / `_eq_summon_skeleton`), 门禁与主场景不用改。
## ★11-13 用户「两件肯定召唤两个炮台啊，三件召唤三个炮台」: 每件各召一个、各自星级(份号 ck, 方案书 20261113)。

var battle


func _init(b) -> void:
	battle = b


## ck = 份号(同名第 2 件起「p2eq_058#2」): 每件各召一座, 炮台打的伤害记到召它的那一件(11-13)。
func turret(u: Dictionary, si: int, ck: String = "p2eq_058") -> void:   # 穿甲遗弹058(重做): 登场召唤不可移动的炮台
	if not u.get("alive", false): return
	battle._audio_sys.sfx_equip("p2eq_058")   # 装备触发声(11-05 音效 v2; 只管声音)
	var _tp: Array = battle._equip_sys.tally.push(u, ck)
	var tr = battle._spawn._spawn_summon(u, "turret", [650.0, 1400.0, 2500.0][si] + EquipSystem.TURRET_HP_PER_ATK * float(u.get("atk", 0.0)), [70.0, 120.0, 180.0][si] + float(u.get("atk", 0.0)),
		{"label": "炮台", "spr_id": "turret", "col_size": 44.0, "hp_w": 32.0,
		 "atk_interval": 1.0 / EquipSystem.TURRET_ASPD, "atk_range": EquipSystem.TURRET_RANGE, "move_spd": 0.0, "melee": false})
	battle._equip_sys.tally.pop(_tp)
	if tr == null: return
	tr["eq_state"] = {}; tr["equips"] = []
	tr["_eq_turret"] = true; tr["_turret_si"] = si
	tr["move_spd"] = 0.0; tr["no_move"] = true      # 移速为0
	tr["crit"] = 0.0; tr["armor_pen"] = 0.0
	if not (u.get("_turret_ref", null) is Dictionary):
		u["_turret_ref"] = tr                        # 第一座(老门禁读它); 只用 is_same 比较, 绝不当Dict键/深比较
	var _refs: Array = u.get("_turret_refs", [])
	_refs.append(tr)                                 # 每件一座: 双抗 / 近身攻速 / 锁定线逐座推进(11-13)
	u["_turret_refs"] = _refs
	# 登场演出: 蓝白部署环 + 起降形变
	battle._splash_ring_bold(tr["pos"], Color(0.42, 0.82, 1.0), 110.0)
	battle._skill_ring(tr["pos"], Color(0.5, 0.88, 1.0, 0.7), 62.0)
	if is_instance_valid(tr["sprite"]):
		var bs: Vector3 = tr["sprite"].scale
		tr["sprite"].scale = Vector3(bs.x * 1.3, 0.05, bs.z)
		var dtw = battle._reg_tween()
		dtw.tween_property(tr["sprite"], "scale", bs, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func tick_turret(u: Dictionary) -> void:   # 058: 炮台双抗随携带者存活 / 携带者在400码内得攻速 / 锁定红线
	var refs: Array = u.get("_turret_refs", [])
	if refs.is_empty():
		var tr0 = u.get("_turret_ref", null)   # 老门禁手动塞的 _turret_ref(没走 _eq_summon_turret)
		if not (tr0 is Dictionary):
			return
		refs = [tr0]
	## ★每件一座(11-13 用户「两件肯定召唤两个炮台…各自生效」): 每座各自的双抗(按召它那件的星级)、
	##   各自给 100% 攻速 ⇒ 携带者同时站在两座附近 = +200%(两件各给一份)。单件时与原来逐字相同。
	var mult: float = 1.0
	for tr in refs:
		if not (tr is Dictionary):
			continue
		if not tr.get("alive", false):
			battle._update_turret_line(tr)
			continue
		var si: int = int(tr.get("_turret_si", u.get("_turret_si", 0)))
		var res: float = ([70.0, 85.0, 100.0][si] if u.get("alive", false) else 0.0)   # 携带者阵亡→双抗归零
		if absf(float(tr.get("base_def", -1.0)) - res) > 0.01:
			tr["base_def"] = res; tr["base_mr"] = res
			battle._recalc_stats(tr)
		var near: bool = u.get("alive", false) and DetMath.vlen((u["pos"] - tr["pos"])) <= EquipSystem.TURRET_BUFF_R
		## ★用户 2026-09-14 拍板加强: 20/30/40% → **三档统一 100%**(「携带者在自己附近时, 攻速加 100%」)。
		if near:
			mult += EquipSystem.TURRET_BUFF_ASPD
		battle._update_turret_line(tr)
	u["_turret_aspd_mult"] = mult   # 直接赋值(不累加·不会泄漏)

func skeleton(u: Dictionary, si: int, ck: String = "p2eq_032") -> void:   # ck = 份号: 每件各召一只, 骷髅的账记到召它那件(11-13)
	if not u.get("alive", false): return
	battle._audio_sys.sfx_equip("p2eq_032")   # 装备触发声(11-05 音效 v2; 只管声音)
	var _tp: Array = battle._equip_sys.tally.push(u, ck)
	# 亡灵骷髅移速=近战斗士档110(用户2026-07-28移速定位化: 原 130 比全表任何龟都快)
	# ★2026-08-01 用户重定义: 血 16/31/55 · 攻 3/5/8 · 双抗 0 · 受任何伤害(含真伤)恒为 1 · 存活 13/17/23 秒。
	#   ★血【不乘 HP_MULT】: 用户给的是"拥有 16/31/55 最大生命值", 那是游戏里能看见的最终值。
	#     旧写法 [19,21,25]×3 = 57/63/75, 属于 CLAUDE.md §3.1 那类"多乘一次"的旧账 —— 顺手清掉。
	#   ★双抗 20000 → 0: 免伤改由 _dmg_cap_one 走减伤收口实现。用双抗堆到 20000 的老办法【拦不住真伤】,
	#     而用户点名"包括真实伤害"。两者并存还会让"受 1 点"变成"受 0 点"(被抗性吃光后再钳)。
	var sk = battle._spawn._spawn_summon(u, "skeleton", [16.0, 31.0, 55.0][si], [3.0, 5.0, 8.0][si], {"label": "亡灵骷髅", "spr_id": "skeleton", "col_size": 32.0, "hp_w": 22.0, "atk_interval": 1.0 / 1.2, "atk_range": 70.0, "melee": true, "move_spd": 110.0})
	battle._equip_sys.tally.pop(_tp)
	if sk == null: return
	sk["base_def"] = 0.0; sk["base_mr"] = 0.0; sk["def"] = 0.0; sk["mr"] = 0.0
	sk["_dmg_cap_one"] = true             # 收到的任何攻击(含真伤)降为 1 —— 闸在 _mitigate_incoming 末尾, 两条伤害路径共用
	sk["summon_life"] = [13.0, 17.0, 23.0][si]
	sk["boom_pct_true"] = [0.08, 0.13, 0.20][si]
	sk["boom_radius"] = 200.0
	battle._skill_ring(sk["pos"], Color(0.4, 1.0, 0.55, 0.6), 40.0)
	for k in range(5):
		battle._bone_speck(sk["pos"] + Vector2(randf_range(-24, 24), randf_range(-24, 24)))
	if is_instance_valid(sk["sprite"]):
		var base_sc: Vector3 = sk["sprite"].scale
		sk["sprite"].scale = Vector3(base_sc.x, 0.05, base_sc.z)
		var tw = battle._reg_tween()
		tw.tween_property(sk["sprite"], "scale", base_sc, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
