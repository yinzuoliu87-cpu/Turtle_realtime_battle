extends Node
## verify_two_head_form_art —— 变脸龟(id two_head)切形态时立绘跟着换(2026-10-07 定稿)。
## 远程(开局)=术士 pets/two_head.png · 近战=战士 pets/two_head_melee.png。走真技能后切形态的入口 _two_head_after_cast。

const RB := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")
var _fails := 0


func _ok(name: String, cond: bool, detail: String = "") -> void:
	print(("  [PASS] " if cond else "  [FAIL] ") + name + ("  " + detail if detail != "" else ""))
	if not cond:
		_fails += 1


func _tex_path(u: Dictionary) -> String:
	var sd = u.get("idle_sd", {})
	var t = (sd as Dictionary).get("tex", null) if sd is Dictionary else null
	return str((t as Texture2D).resource_path) if t is Texture2D else ""


func _ready() -> void:
	await get_tree().process_frame
	RB.DEBUG_EDIT = true
	var s = RB.new()
	add_child(s)
	await get_tree().process_frame
	await get_tree().process_frame
	var u: Dictionary = s._spawn._make_unit("two_head", "left", Vector2(300, 400))
	s._units.append(u)
	_ok("分母: 开局不是近战(远程/未设 = 远程)", str(u.get("two_form", "ranged")) != "melee", str(u.get("two_form", "")))
	_ok("开局立绘 = 术士(pets/two_head.png)", _tex_path(u).ends_with("pets/two_head.png"), _tex_path(u))
	s._two_head_sys._two_head_after_cast(u, null)
	_ok("分母: 放完技能切到近战", str(u.get("two_form", "")) == "melee", str(u.get("two_form", "")))
	_ok("★切近战后立绘 = 战士(pets/two_head_melee.png)", _tex_path(u).ends_with("pets/two_head_melee.png"), _tex_path(u))
	s._two_head_sys._two_head_after_cast(u, null)
	_ok("★再切回远程, 立绘回到术士", _tex_path(u).ends_with("pets/two_head.png") and str(u.get("two_form", "")) == "ranged", _tex_path(u))
	_ok("头像: 新头像在(avatars/two_head.png)", ResourceLoader.exists("res://assets/sprites/avatars/two_head.png"))
	s.queue_free()
	await get_tree().process_frame
	RB.DEBUG_EDIT = false
	print("ALL PASS — 变脸龟形态立绘" if _fails == 0 else "FAIL x%d" % _fails)
	get_tree().quit()
