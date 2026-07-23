extends Node

## verify_dot_float.gd — 点1: DOT 累积变大数字(按伤害类型桶) + 诅咒静音 (用户 2026-07-23)
## 直接 .new() 战斗脚本测累积逻辑/分桶/结束检测(不起 3D 场景)。

const Battle := preload("res://scripts/scenes/RealtimeBattle3DScene.gd")

var _fail: int = 0
func _ok(n: String, c: bool, d: String = "") -> void:
	if c: print("  [PASS] ", n, ("  " + d) if d != "" else "")
	else: _fail += 1; print("  [FAIL] ", n, "  ", d)

func _ready() -> void:
	var b = Battle.new()

	# ① 分桶颜色: mag蓝/phy红/tru紫
	_ok("mag桶=蓝", b._dot_bucket_col("mag").is_equal_approx(Color("#4dabf7")))
	_ok("phy桶=红", b._dot_bucket_col("phy").is_equal_approx(Color("#ff6b6b")))
	_ok("tru桶=紫", b._dot_bucket_col("tru").is_equal_approx(Color("#b48cff")))

	# ② 累积: 灼烧(mag)+中毒(mag)进【同一个】mag桶累加; 流血(phy)单独
	var u := {}
	b._dot_accumulate(u, "mag", 5)   # 灼烧5
	b._dot_accumulate(u, "mag", 3)   # 中毒3 → 同mag桶
	b._dot_accumulate(u, "phy", 2)   # 流血2 → 另一桶
	var df: Dictionary = u["_dot_float"]
	_ok("★灼烧+中毒同 mag 桶累加(5+3=8)", int((df.get("mag", {}) as Dictionary).get("total", 0)) == 8, str(df.get("mag", {}).get("total")))
	_ok("★流血单独 phy 桶(=2)", int((df.get("phy", {}) as Dictionary).get("total", 0)) == 2)
	b._dot_accumulate(u, "mag", 10)
	_ok("★累积再变大(mag +10 → 18)", int(df["mag"]["total"]) == 18)
	# 左右错开: 两桶槽位不同
	_ok("★多桶左右错开(mag/phy 槽位不同)", int(df["mag"]["slot"]) != int(df["phy"]["slot"]), "mag=%d phy=%d" % [df["mag"]["slot"], df["phy"]["slot"]])

	# ③ 桶结束检测 _dot_bucket_active
	b._t = 0.0
	_ok("灼烧活着→mag桶活", b._dot_bucket_active({"dot_stacks": {"burn": 5}}, "mag"))
	_ok("中毒活着→mag桶活", b._dot_bucket_active({"dot_stacks": {"poison": 3}}, "mag"))
	_ok("流血活着→phy桶活", b._dot_bucket_active({"dot_stacks": {"bleed": 2}}, "phy"))
	_ok("诅咒(flat dot)活着→tru桶活", b._dot_bucket_active({"dots": [{"until": 999.0}]}, "tru"))
	_ok("★都没了→桶结束(触发跳走)", not b._dot_bucket_active({"dot_stacks": {}, "dots": []}, "mag"))
	_ok("真火灼烧→算 tru 桶(不算mag)", b._dot_bucket_active({"dot_stacks": {"burn": 5}, "true_fire_until": 999.0}, "tru") and not b._dot_bucket_active({"dot_stacks": {"burn": 5}, "true_fire_until": 999.0}, "mag"))

	# ④ 源码: 5个DOT tick调用走累积模式; 诅咒静音
	var src: String = (Battle as GDScript).source_code if Battle is GDScript else ""
	var n_accum: int = src.count(', "mag", false, true)') + src.count(', "phy", false, true)') + src.count(', "tru", false, true)')
	_ok("★DOT tick 调用走累积模式(dot_accum)>=4", n_accum >= 4, "实际 %d" % n_accum)
	_ok("★诅咒 tick 静音(mute_sfx)", src.count(', "tru", false, true, true)') >= 1)
	_ok("★_process 每帧调 _update_dot_floats", src.contains("_update_dot_floats()"))

	b.free()
	print("ALL PASS — DOT累积数字(按桶)+诅咒静音" if _fail == 0 else "FAILED: %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
