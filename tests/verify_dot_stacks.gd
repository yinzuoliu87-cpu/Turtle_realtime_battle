extends Node
## verify_dot_stacks.gd — 自证: 层数式 DoT (灼烧/中毒/流血) 1:1 回合制 dot.gd 衰减模型.
## 跑法: godot --headless --path . res://tests/verify_dot_stacks.tscn --quit-after 120
## 实例化真实 RealtimeBattleScene → 抓一个真实单位 → 直接驱动 _tick_dot_stacks, 打印每秒层数+出伤.

const RTScene := preload("res://scripts/scenes/RealtimeBattleScene.gd")

func _ready() -> void:
	await get_tree().process_frame   # 让被实例化场景的 _ready 跑完 (spawn 整队)
	var scene = RTScene.new()
	add_child(scene)                 # 触发 _ready → 建场+spawn 单位
	await get_tree().process_frame

	var units: Array = scene.get("_units")
	if units == null or units.is_empty():
		push_error("verify: 没拿到单位"); _quit(); return

	# 取第一个非召唤单位当试验体, 满血固定 maxHp 便于核对 burn 的 maxHp 项
	var u = null
	for x in units:
		if not x.get("is_summon", false):
			u = x; break
	if u == null:
		push_error("verify: 没找到本体单位"); _quit(); return

	print("\n════ DoT 层数衰减自证 (单位 maxHp=%.0f) ════" % float(u["maxHp"]))

	# ---- BURN: 施加 100 层, 每秒 _tick_dot_stacks 一次, 打印 ----
	u["hp"] = u["maxHp"]
	u["dot_stacks"] = {}
	u["true_fire_until"] = 0.0
	scene.call("_apply_dot_stacks", u, "burn", 100, null)
	print("[burn] 施加100层. maxHp项每层贡献 round(maxHp*1*0.001)=%d" % roundi(float(u["maxHp"]) * 0.001))
	var burn_seq: Array = []
	for i in range(8):
		var stacks_before: int = int(u["dot_stacks"].get("burn", 0))
		var hp_before: float = u["hp"]
		scene.call("_tick_dot_stacks", u)
		var stacks_after: int = int(u["dot_stacks"].get("burn", 0))
		var dealt: float = hp_before - u["hp"]
		var expected_dmg: int = stacks_before + roundi(float(u["maxHp"]) * stacks_before * 0.001)
		print("  tick%d: 层 %3d → %3d  | 出伤=%d (期望burn公式=%d)" % [i + 1, stacks_before, stacks_after, int(dealt), expected_dmg])
		burn_seq.append(stacks_before)
		if stacks_after <= 0:
			burn_seq.append(0)
			break
	print("[burn] 层数序列: %s" % str(burn_seq))

	# ---- POISON: 100 层, 衰减 floor(×3/4) ----
	u["hp"] = u["maxHp"]; u["dot_stacks"] = {}
	scene.call("_apply_dot_stacks", u, "poison", 100, null)
	var poison_seq: Array = []
	for i in range(8):
		var sb: int = int(u["dot_stacks"].get("poison", 0))
		scene.call("_tick_dot_stacks", u)
		poison_seq.append(sb)
		if int(u["dot_stacks"].get("poison", 0)) <= 0:
			poison_seq.append(0); break
	print("[poison] 层数序列 (衰减1/4): %s" % str(poison_seq))

	# ---- BLEED: 100 层, 衰减 floor(×3/4) (与 poison 同衰减率) ----
	u["hp"] = u["maxHp"]; u["dot_stacks"] = {}
	scene.call("_apply_dot_stacks", u, "bleed", 100, null)
	var bleed_seq: Array = []
	for i in range(8):
		var sb2: int = int(u["dot_stacks"].get("bleed", 0))
		scene.call("_tick_dot_stacks", u)
		bleed_seq.append(sb2)
		if int(u["dot_stacks"].get("bleed", 0)) <= 0:
			bleed_seq.append(0); break
	print("[bleed] 层数序列 (衰减1/4): %s" % str(bleed_seq))

	# ---- TRUE FIRE: burn 在真火态下走 _raw_lose (真伤路径, 不弹字/不触发 on-hit 钩子). ----
	# 注: 1:1 回合制 dot.gd, true 型伤害仍被护盾吸收 (damage.gd:136 "真伤(true)也走护盾,同JS");
	# 真火的语义=灼烧改 _raw_lose 真伤路径 (跳过物/法减伤), 不是无视护盾.
	# 无护盾对比: 真火 burn 与普通 burn 对裸血出伤一致.
	u["hp"] = u["maxHp"]; u["shield"] = 0.0; u["dot_stacks"] = {}
	u["true_fire_until"] = 999999.0   # 真火生效
	scene.call("_apply_dot_stacks", u, "burn", 50, null)
	var hp0: float = u["hp"]
	scene.call("_tick_dot_stacks", u)
	var hp_lost: float = hp0 - u["hp"]
	var expect_tf: int = 50 + roundi(float(u["maxHp"]) * 50 * 0.001)
	print("[truefire] 50层burn(无盾): HP掉=%d (期望=%d) → %s" % [int(hp_lost), expect_tf, ("真火走真伤路径✓" if int(hp_lost) == expect_tf else "✗")])

	# ---- 多层叠加: 同类再施加 → 累加 ----
	u["dot_stacks"] = {"burn": 0}
	scene.call("_apply_dot_stacks", u, "burn", 30, null)
	scene.call("_apply_dot_stacks", u, "burn", 20, null)
	print("[stack] 施加30层再施加20层 → %d (期望50)" % int(u["dot_stacks"].get("burn", 0)))

	# ---- _has_dot 走 dot_stacks ----
	print("[has_dot] burn有层时 _has_dot=%s (期望true)" % str(scene.call("_has_dot", u, "burn")))
	u["dot_stacks"] = {}
	print("[has_dot] burn无层时 _has_dot=%s (期望false)" % str(scene.call("_has_dot", u, "burn")))

	print("════ 自证完成 ════\n")
	_quit()

func _quit() -> void:
	get_tree().quit()
