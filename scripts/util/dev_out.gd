class_name DevOut
extends RefCounted
## 开发产物(截图 / 特效实验台逐帧 / 对比图)的统一落点: res://.out/。
## 点目录: Godot 不扫、不导入; .gitignore 一条 /.out/ 管住; tools/clean.py 一条命令清。
## ★2026-11-02 之前各处默认写 res://_xxx.png 到仓库根目录, 攒了 700 多个文件,
##   Godot 导入缓存里三分之二是它们和文档截图(方案书 docs/plans/20261102-文件管理与发版流程重整.md F1)。
## 手动截图也照这个落点: SHOT_OUT=res://.out/shots/<名>.png。

const ROOT := "res://.out"


## 默认落点 res://.out/<sub>/<file>, 并建好目录。
static func path(file: String, sub: String = "shots") -> String:
	return prep("%s/%s/%s" % [ROOT, sub, file])


## 给任意输出路径建好上级目录 —— 手动传的 SHOT_OUT / VFXLAB_OUT 指到不存在的目录时 save_png 直接失败、不报在明处。
static func prep(p: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p).get_base_dir())
	return p
