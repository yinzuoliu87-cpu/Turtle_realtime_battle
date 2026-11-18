extends Node
## 开机定语言(2026-11-18 · scripts/util/lang.gd)。排在 autoload 第一个、在 _init 里做:
## 其它 autoload 与主场景建控件之前语言就定好了, 第一帧就是对的语言。

## ★preload 而不是全局类名: autoload 比全局类表先就位, 新加的 class_name 在没重新导入过的工程里还查不到。
const _LANG := preload("res://scripts/util/lang.gd")


func _init() -> void:
	_LANG.boot()
