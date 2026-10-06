class_name SimShot
extends Node
## sim_shot.gd — `SIM_SHOT_DIR=<目录>` 时, 每 `SIM_SHOT_SEC` 秒(默认 5)把**本窗口自己的画面**存成 `<目录>/latest.png`。
##
## ★为什么要它(用户 2026-10-03):「你就用这一块屏幕，我用另一块，不要干涉我用的那个屏」。
##   原来看模拟窗口靠 `op.sh shot` —— 每拍一张都把窗口**切到前台**, 抢用户的焦点;
##   从屏幕上抠又会被别的窗口盖住; PrintWindow 对 Godot 的 GPU 画面拍出来是全白/全黑(实测)。
##   ⇒ 让游戏**自己**存图: 不动窗口、不动焦点、不动鼠标。
## ★默认彻底关掉: 不带环境变量时 `attach()` 第一行就返回, 不建节点、不建计时器。

const ENV := "SIM_SHOT_DIR"

static func enabled() -> bool:
	return OS.get_environment(ENV).strip_edges() != ""


## 唯一入口: `GameState._ready()` 一行接入(autoload 常驻, 换场景不丢)。
static func attach(host: Node) -> Node:
	## 模拟玩家整条流程的驱动(`SIM_DRIVER=1` 才建; 见 sim_driver.gd 头注)。借这一处接入 ——
	##   它也要挂在 autoload 下、跨场景常驻, 与自拍同一个宿主; 不带开关时它自己第一行就返回。
	load("res://scripts/systems/sim/sim_driver.gd").attach(host)
	if not enabled():
		return null
	var n := SimShot.new()
	n.name = "SimShot"
	host.add_child.call_deferred(n)
	return n


var _dir := ""

func _ready() -> void:
	_dir = OS.get_environment(ENV).strip_edges()
	DirAccess.make_dir_recursive_absolute(_dir)
	var t := Timer.new()
	t.wait_time = maxf(1.0, float(OS.get_environment("SIM_SHOT_SEC")) if OS.get_environment("SIM_SHOT_SEC") != "" else 5.0)
	t.autostart = true
	t.timeout.connect(_shoot)
	add_child(t)


func _shoot() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	img.save_png(_dir.path_join("latest.png"))
