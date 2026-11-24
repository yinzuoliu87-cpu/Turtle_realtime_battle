extends Node
## 开机定语言(2026-11-18 · scripts/util/lang.gd)。排在 autoload 第二个(第一个是 PersistentBg: 无头贴图占位加载器
##   要最先装, 它只铺一块底色、不建文字控件)、在 _init 里做:
## 其它 autoload 与主场景建控件之前语言就定好了, 第一帧就是对的语言。

## ★preload 而不是全局类名: autoload 比全局类表先就位, 新加的 class_name 在没重新导入过的工程里还查不到。
const _LANG := preload("res://scripts/util/lang.gd")


func _init() -> void:
	_LANG.boot()


## 英文折行(2026-11-23 实拍: 「restore your pro gress」「Dele ted Player」): 全仓为中文设的是 AUTOWRAP_ARBITRARY(任意处折),
##   英文会把单词拦腰切断。英文时: 每个进树的 Label / RichTextLabel, 等它自己设完(下一帧), 任意处折 ⇒ 按单词折。中文不动。
func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if _LANG.code != "en" or not (n is Label or n is RichTextLabel):
		return
	_fix_wrap.call_deferred(n)


static func _fix_wrap(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n.get("autowrap_mode") == TextServer.AUTOWRAP_ARBITRARY:
		n.set("autowrap_mode", TextServer.AUTOWRAP_WORD_SMART)
