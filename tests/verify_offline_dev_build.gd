extends Node
## verify_offline_dev_build.gd — 测试包不许碰正式服(2026-10-14 用户「不要干扰到内测里面的玩家」)
##
## 带调试场的 Windows 测试包走预设 WinDevOffline(特性标签 offline_dev):
##   网络两层(supabase.gd / remote_pool.gd)整层停用, 存档目录与窗口标题另分。
## 判据:
##   ① 标签在 ⇒ 两层都停用, 环境变量指向正式服也盖不过
##   ② 分母: 同一进程里标签不在时, 环境变量确实能把层打开(否则①是空检查)
##   ③ 导出预设: 有 WinDevOffline、带 offline_dev、导出路径不与 WinDist 撞
##   ④ project.godot: offline_dev 下另用存档目录, 且名字不同于正式包
## 无头进程没有导出特性标签 ⇒ ① 用 offline_override 模拟; 真包另由出包时实跑验证(见出包记录)。

const SB := preload("res://scripts/net/supabase.gd")
const RP := preload("res://scripts/net/remote_pool.gd")

var _n := 0
var _fail := 0


func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if cond:
		print("  [PASS] ", name)
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)


func _ready() -> void:
	print("=== 测试包不碰正式服 ===")
	var prod := str(ProjectSettings.get_setting(SB.SETTING_URL, ""))
	var env_sb0 := OS.get_environment(SB.ENV_URL)
	var env_rp0 := OS.get_environment(RP.ENV_KEY)
	OS.set_environment(SB.ENV_URL, prod)
	OS.set_environment(RP.ENV_KEY, "https://example.invalid")

	SB.offline_override = false
	_ok("② 分母: 没标签时环境变量能打开 Supabase 层", SB.enabled(), "url=%s" % SB.base_url())
	_ok("② 分母: 没标签时环境变量能打开旧对手池层", RP.enabled())

	SB.offline_override = true
	_ok("① ★测试包: Supabase 层停用(环境变量指向正式服也不行)", not SB.enabled() and SB.base_url() == "", "url=%s" % SB.base_url())
	_ok("① ★测试包: 旧对手池层停用", not RP.enabled(), "url=%s" % RP.base_url())
	_ok("① ★测试包: 服务状态报「没配后端」(不去问服务器)", SB.service_state() == SB.ST_OFF, SB.service_state())
	SB.offline_override = false
	OS.set_environment(SB.ENV_URL, env_sb0)
	OS.set_environment(RP.ENV_KEY, env_rp0)

	var cfg := ConfigFile.new()
	_ok("③ 读得到 export_presets.cfg", cfg.load("res://export_presets.cfg") == OK)
	var dev := ""
	var dist_path := ""
	for sec in cfg.get_sections():
		if str(cfg.get_value(sec, "name", "")) == "WinDevOffline":
			dev = sec
		if str(cfg.get_value(sec, "name", "")) == "WinDist":
			dist_path = str(cfg.get_value(sec, "export_path", ""))
	_ok("③ 有 WinDevOffline 预设且带 offline_dev", dev != "" and str(cfg.get_value(dev, "custom_features", "")).contains(SB.OFFLINE_FEATURE),
		"sec=%s" % dev)
	_ok("③ 导出路径不与 WinDist 撞", dev != "" and str(cfg.get_value(dev, "export_path", "")) != dist_path)

	var pg := ConfigFile.new()
	pg.load("res://project.godot")
	var dir_name := str(pg.get_value("application", "config/custom_user_dir_name." + SB.OFFLINE_FEATURE, ""))
	_ok("④ 测试包另用存档目录", bool(pg.get_value("application", "config/use_custom_user_dir." + SB.OFFLINE_FEATURE, false)) \
		and dir_name != "" and dir_name != str(pg.get_value("application", "config/name", "")), "dir=%s" % dir_name)

	print("分母: %d 条断言" % _n)
	if _fail == 0:
		print("ALL PASS — 测试包不碰正式服 (%d/%d)" % [_n, _n])
	get_tree().quit(1 if _fail > 0 else 0)
