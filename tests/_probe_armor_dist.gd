extends Node
## 探针: 一场【真实对局】里, 被打的目标身上的护甲/魔抗到底有多高。
##
## ★为什么必须量运行时而不是读 pets.json:
##   建表值只有 9~21, 但局内会被【装备 / 等级 / 岩层 / 铁壁 / 水晶护盾 / 钻石壁垒 /
##   嘲讽 / 各种 buff】抬高, 也会被【削甲 / 穿甲】压低。补偿系数要建立在
##   "挨打那一刻目标实际有多少护甲"上, 不是建表值。
##   (我 2026-08-29 拿探针里自己编的 def=500 说"护甲挡掉 93%", 那是编的不是量的。)
##
## 记账点放在**产品自己结算伤害那一刻**: 每次 `_apply_damage_from` 落地时记下
## 目标此刻的 def/mr。不采样, 无条件记(memory fb-measure-events-not-samples)。
##
## 跑法: <godot> --headless --audio-driver Dummy --path . res://tests/_probe_armor_dist.tscn --quit-after 120000
##   ARMOR_SECS=60  跑多少秒(默认 60)

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _s = null


func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var i: int = clampi(int(round(q * float(a.size() - 1))), 0, a.size() - 1)
	return float(a[i])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.test_mode = true
	_s = RB.new()
	add_child(_s)
	for _i in range(40):
		await get_tree().process_frame

	var secs: float = 60.0
	if OS.has_environment("ARMOR_SECS"):
		secs = maxf(5.0, float(OS.get_environment("ARMOR_SECS")))

	## ★挂在产品的伤害管线上: `battle_damage` 每次落地都会调 `_take_dtype`,
	##   这里改成每帧扫全场单位取 def/mr —— 但那是**采样**, 会看不见短暂的护甲 buff。
	##   ⇒ 改成: 每帧把【本帧受过伤的单位】的 def/mr 记一笔。用 dmg_dealt 变化反查太绕,
	##     直接用单位的 `hp` 是否下降来判定"这一帧挨打了"。
	var defs: Array = []
	var mrs: Array = []
	var last_hp: Dictionary = {}       # sprite instance_id → 上一帧血量
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		for u in _s._units:
			if not (u is Dictionary) or not u.get("alive", false):
				continue
			var sp = u.get("sprite", null)
			if sp == null or not is_instance_valid(sp):
				continue
			var key: int = sp.get_instance_id()
			var hp: float = float(u.get("hp", 0.0))
			if last_hp.has(key) and hp < float(last_hp[key]) - 0.001:
				defs.append(float(u.get("def", 0.0)))
				mrs.append(float(u.get("mr", 0.0)))
			last_hp[key] = hp
		await get_tree().process_frame

	defs.sort()
	mrs.sort()
	print("ARMOR_N %d" % defs.size())
	if defs.is_empty():
		print("ARMOR_FAIL 一次挨打都没记到 —— 分母为 0, 这不是'护甲很低'而是没测到")
		_s.queue_free()
		get_tree().quit(1)
		return
	for nm in [["护甲def", defs], ["魔抗mr", mrs]]:
		var a: Array = nm[1]
		print("ARMOR %s  p10=%.0f  p25=%.0f  中位=%.0f  p75=%.0f  p90=%.0f  最大=%.0f"
			% [str(nm[0]), _pct(a, 0.10), _pct(a, 0.25), _pct(a, 0.50),
				_pct(a, 0.75), _pct(a, 0.90), float(a[a.size() - 1])])
	## ★真正要的那个数: 「一发物理伤害平均会被砍掉多少」
	##   = 对每一次挨打各算一次倍率再平均, **不是**拿中位护甲算一次倍率
	##   (两者不等 —— 倍率对护甲是凸函数, 拿中位数代入会低估平均倍率)。
	var sum_p := 0.0
	var sum_m := 0.0
	for v in defs:
		sum_p += 1.0 - float(v) / (float(v) + 40.0)
	for v in mrs:
		sum_m += 1.0 - float(v) / (float(v) + 40.0)
	var avg_p: float = sum_p / float(defs.size())
	var avg_m: float = sum_m / float(mrs.size())
	print("ARMOR_MULT 物理平均倍率 %.4f (要打回原值需 ×%.3f)" % [avg_p, 1.0 / maxf(0.001, avg_p)])
	print("ARMOR_MULT 魔法平均倍率 %.4f (要打回原值需 ×%.3f)" % [avg_m, 1.0 / maxf(0.001, avg_m)])
	print("ARMOR_DONE")
	_s.queue_free()
	get_tree().quit(0)
