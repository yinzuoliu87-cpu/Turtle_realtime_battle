extends RefCounted
## 连哪台服务器：正式服 / 内测服（2026-10-21 · 方案书 docs/plans/20261020-内测服.md §4）。
##
## ★只在【构建期】决定（D2）：导出预设 WinBeta 带特性标签 `beta_server` ⇒ 内测服包；玩家包里没有任何开关。
##   开发 / 无头进程（编辑器跑、模拟号、门禁外的冒烟）用环境变量 `TURTLE_SERVER=beta|prod`，
##   **只在 debug 构建里认**（release 导出模板下 `OS.is_debug_build()` 为 false ⇒ 正式包设了也没用）。
## ★地址与 key 一起换（方案书调查 B：原来 `TURTLE_SUPABASE` 只能换地址、key 换不了 ⇒ 打内测服 401）。
##   取值一律走 `setting()`：是内测服 ⇒ 读 `<名>.beta_server`（project.godot 里那一组），否则读 `<名>` 本身。
##   ⚠ 不靠 Godot 自己的「设置名.特性名」覆盖（方案书 R8）：GDScript 的 `get_setting` 不保证套用特性覆盖，
##     而那一组 key 是否被套用正是「连没连错服」—— 所以这里显式读，开发进程（没有特性标签）也走同一条路。
## ★门禁口径不变：`TURTLE_SUPABASE=" "` 仍然整层停用（net_route.gd 先看它）。
## 守卫: tests/verify_beta_server_build.gd

const FEATURE := "beta_server"
const ENV := "TURTLE_SERVER"
const SUFFIX := ".beta_server"
## 屏上角标的字（主菜单版本号旁）。
const BADGE_TEXT := "内测服"

## 仅门禁用: -1 = 不盖; 0 = 当成正式服; 1 = 当成内测服（无头进程没有导出特性标签）。
static var beta_override := -1


static func is_beta() -> bool:
	if beta_override >= 0:
		return beta_override == 1
	if OS.has_feature(FEATURE):
		return true
	if OS.is_debug_build() and OS.has_environment(ENV):
		return OS.get_environment(ENV).strip_edges().to_lower() == "beta"
	return false


## 读一项 `turtle/*` 设置: 内测服 ⇒ 只读 `<名>.beta_server`, 正式服 ⇒ 只读 `<名>`。
## ★内测服【绝不回落】到正式服那一项: 少配一项 = 拿到默认值(地址空 = 整层停用), 而不是悄悄连回正式服 ——
##   内测服包放行时间穿越下的写请求(supabase.gd `travel_blocks`), 连错到正式服就是往生产写假时间数据。
static func setting(key: String, default_value: Variant = "") -> Variant:
	if is_beta():
		return ProjectSettings.get_setting(key + SUFFIX, default_value)
	return ProjectSettings.get_setting(key, default_value)
