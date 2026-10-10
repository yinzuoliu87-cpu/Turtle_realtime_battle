extends Node
## verify_cjk_wrap_export —— 导出包必须带文字引擎的断行数据(2026-10-10 用户手机截图)。
##
## 不带的话, 中文只在**空格**处折行: 图鉴说明「每道气波随机朝向 1」后面空着大半行就断,
## 「（40%×攻击力 = 」与「21）」被拆到两行。编辑器自带这份数据 ⇒ 电脑上永远看不出来, 只有导出包(手机)才坏。
## 实测(tests/_probe_cjk_wrap 设成启动场景导 WinVerify): 关 ⇒ 6 行且首行断在「1」; 开 ⇒ 5 行, 与编辑器逐字一致; 包 +4.8MB。
## 判据只能量设置本身 —— 门禁跑在编辑器里, 排版结果永远是对的(量排版 = 恒真)。

var _fail := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  [PASS] ", name, ("  " + detail) if detail != "" else "")
	else:
		_fail += 1
		print("  [FAIL] ", name, "  ", detail)

func _ready() -> void:
	var v = ProjectSettings.get_setting("internationalization/locale/include_text_server_data", false)
	_ok("★导出包带断行数据(internationalization/locale/include_text_server_data = true)", v == true, str(v))
	if _fail == 0:
		print("ALL PASS — 导出包中文断行数据")
	get_tree().quit(1 if _fail > 0 else 0)
