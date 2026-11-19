extends "res://scripts/scenes/battle/shell_vfx.gd"
## 龟壳复制演出的计数替身(verify_shell_copy_two + 探针 _probe_shell_copy_count): 数 copy_icon 调用 = 头顶出了几个图标 = 放了几发, 其余照父类。
var icons: Array = []

func copy_icon(u: Dictionary, stype: String, hold: float) -> void:
	icons.append(stype)
	super.copy_icon(u, stype, hold)
