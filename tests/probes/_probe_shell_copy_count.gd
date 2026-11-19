extends Node
## _probe_shell_copy_count.gd —— 龟壳【复制】实际放几发(2026-11-19 用户「龟壳偷进来不是偷两个吗？为什么我只看到一个？」)
## 合成单位(同 verify_gambler_bet_attack_fx 的搭法): 左龟壳带复制, 右 3 只真龟各带默认主动技;
## 把 ShellVfx 换成子类数 copy_icon(= 头顶出了几个图标 = 放了几发)。不是门禁, 只打数。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
const FXC := preload("res://tests/_shell_fx_counter.gd")

var _s = null


func _mk(id: String, px: float, side: String) -> Dictionary:
	var u: Dictionary = _s._spawn._make_unit(id, side, Vector2(px, 400.0))
	u["hp"] = 100000.0; u["maxHp"] = 100000.0; u["alive"] = true
	u["no_move"] = true; u["atk_interval"] = 9999.0; u["atk_cd"] = 9999.0
	return u


func _case(name: String, enemy_ids: Array, alive_n: int) -> void:
	_s._units.clear()
	_s._pending_shots.clear()
	var sh: Dictionary = _mk("shell", 400.0, "left")
	_s._units.append(sh)
	var es: Array = []
	for i in range(enemy_ids.size()):
		var e: Dictionary = _mk(str(enemy_ids[i]), 700.0 + 40.0 * i, "right")
		if i >= alive_n:
			e["alive"] = false
		es.append(e)
		_s._units.append(e)
	var fx = FXC.new(_s)
	_s._shell_sys._fx = fx
	var sk: Array = []
	for e in es:
		sk.append("%s:%s%s" % [e["id"], str(e.get("active_skills", [])), "" if e["alive"] else "(死)"])
	_s._shell_sys._sk_shell_copy(sh, es[0] if es[0]["alive"] else null)
	for _k in range(40):
		_s._ballistics._step_pending_shots(0.05)
	print("  %-26s 敌 %s ⇒ 头顶图标 %d 个: %s" % [name, " ".join(sk), fx.icons.size(), str(fx.icons)])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	get_node("/root/GameState").test_mode = true
	RB.DEBUG_EDIT = true
	_s = RB.new()
	add_child(_s)
	for _i in range(10):
		await get_tree().process_frame
	_s.process_mode = Node.PROCESS_MODE_DISABLED
	_s._edit_mode = false
	print("=== 龟壳·复制 实际放几发 ===")
	_case("3 只活", ["stone", "ice", "ninja"], 3)
	_case("2 只活", ["stone", "ice", "ninja"], 2)
	_case("1 只活", ["stone", "ice", "ninja"], 1)
	_case("3 只活·其中两只不可抄", ["angel", "hunter", "ice"], 3)
	_s._units.clear()
	get_tree().quit(0)
