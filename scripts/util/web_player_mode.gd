class_name WebPlayerMode
extends RefCounted
## 网页录像播放器的进程判据(2026-11-08 · 方案书 docs/plans/20261105c-主站对接偷袭.md §4.7、docs/specs/主站对接约定.md §4.4)。
##
## 「这个进程是网页播放器」= 导出预设 `WebPlayer` 的特性标签 `web_player`(project.godot 里 `run/main_scene.web_player`
##   把主场景换成 `scenes/WebPlayer.tscn`), 或桌面调试时设了环境变量 `WEBPLAYER=1`。
## 判为真时开机(GameState._ready)整层不连网、不写存档:
##   · 后端停用(`TURTLE_SUPABASE` / `TURTLE_BACKEND` 设成空白串, 与裁判入口 referee_main.gd 同一个开关) ⇒ 不登录、不推云存档;
##   · 存档保护开着(test_mode) ⇒ 任何 save() 空转;
##   · 不装报错上报、不装版本墙、不起联网心跳、不修快照池缓存(这几样都会写 user:// 或连服务器)。
## ★只会让进程「更安静」: 判据误判为真的唯一后果是这个进程不存档、不连网, 不会放开任何闸。

const FEATURE := "web_player"
const ENV := "WEBPLAYER"
## 播放器场景(导出预设的主场景, 看完录像回这一页)。
const SCENE := "res://scenes/WebPlayer.tscn"


static func active() -> bool:
	return OS.has_feature(FEATURE) or OS.get_environment(ENV) == "1"


## 开机时停掉后端(GameState._ready 第一件事调; 网页播放器场景自己进来时再调一次, 两次都是同一个值)。
static func silence_backend() -> void:
	OS.set_environment("TURTLE_SUPABASE", " ")
	OS.set_environment("TURTLE_BACKEND", " ")
