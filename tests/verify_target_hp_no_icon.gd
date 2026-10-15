extends Node
## verify_target_hp_no_icon.gd — 别人的「最大生命值」不配♥图标, 自己的才配(2026-10-15)
##   用户「你看看lol里面怎么写是目标最大生命值还是有自己最大生命值加成」。
##   LoL 实截: 科加斯 E「2.5% of the target's max Health」写字不配图标; 塞恩 W「+8%♥」自己的放图标。
##   海盗龟被动实拍「造成其 25% ♥最大生命值」—— 中间隔着数字, 只认紧挨着的规则漏了。

const SKT := preload("res://scripts/util/skill_text.gd")
const HP_ICON := "hp-icon.png"

var _fail := 0
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond: print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else: _fail += 1; print("  [FAIL] ", name, "  ", detail)

func _bb(t: String) -> String:
	return SKT.plain_to_bb(t, 14)

func _ready() -> void:
	var others := [
		"造成其 25% 最大生命值的真实伤害。",
		"造成其 <span class=\"val-true\">25% 最大生命值</span>的真实伤害。",
		"外加 8% 目标最大生命值的物理伤害。",
		"外加 13% 目标的最大生命值。",
		"造成该敌人 6% 最大生命值的伤害。",
	]
	for t in others:
		var b := _bb(t)
		_ok("别人的不配图标: " + t.substr(0, 16), not b.contains(HP_ICON) and b.contains("最大生命值"), b.substr(0, 80))
	var selfs := [
		"每秒回复（4%×最大生命值(100) = 4）生命值。",
		"获得相当于自身 10% 最大生命值的护盾。",
		"对敌人造成相当于自身 5% 最大生命值的伤害。",
	]
	for t in selfs:
		var b := _bb(t)
		_ok("自己的照样配图标: " + t.substr(0, 16), b.contains(HP_ICON), b.substr(0, 80))
	## 分母: 真实数据里海盗龟被动就是那条实拍出问题的
	var pirate_brief := str(((DataRegistry.pet_by_id.get("pirate", {}) as Dictionary).get("passive", {}) as Dictionary).get("brief", ""))
	_ok("分母: 读到海盗龟被动", pirate_brief.contains("最大生命值"), pirate_brief.substr(0, 40))
	var pb := _bb(SKT.render_consts(pirate_brief))
	_ok("海盗龟被动「其 X% 最大生命值」不再配♥", not pb.contains(HP_ICON), pb.substr(0, 120))
	print("ALL PASS — 别人的最大生命值不配图标" if _fail == 0 else "FAIL x%d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)
