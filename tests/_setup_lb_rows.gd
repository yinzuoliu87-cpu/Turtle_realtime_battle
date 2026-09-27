extends Node
## 门禁用的一次性种子: 给【排行榜】灌满真人行, 给【撮合】一个真人对手。
##
## ═══ 为什么必须有它 ═══
## 2026-09-27 把排行榜/撮合加进 `verify_ui_consistency` 棘轮时, 两屏 web/round/frame/tap
## 实测**全 0** —— 看着干净。而排行榜自带的那句分母打出来是 `[LB] rows=1`:
## **榜上只有我自己一行**, 量的是占位屏。
##
## 根因不是 bug, 是**产品行为**: v0.19.446 修掉了「种子池 396 条占名次」
## (用户实测看到「#57 你」而全周只有 10 个人) ⇒ 全新档的榜本来就只有自己。
##
## ★★而**灌不进去**的原因是 `Backend.save_pool()` 在 `test_mode` 下直接 return
##   (保护真存档), 场景读的是文件 ⇒ 内存里灌多少都没用。
##   ⇒ 走 `Backend.pool_override`(v0.19.454 开的注入缝, 默认空 ⇒ 玩家路径不变)。
##
## ★`Backend` **不是全局标识符** —— 本仓刻意不给它 class_name(`backend.gd:5`
##   「用 preload 引」), 这里必须自己 preload。漏了会整份 Parse Error, 而门禁那句
##   `has_method("run")` 会**一声不响地跳过** ⇒ 量占位屏而报全绿(2026-09-27 踩过)。
const Backend = preload("res://scripts/net/backend.gd")

const N_ROWS := 14        ## 面板画得下 11 行 ⇒ 灌 14 条, 让「画满 + 还有更多」都成立


## 快照形状照 `verify_leaderboard_sort._g()` 的真实用法, 不是我编的:
##   `origin = ORIGIN_REMOTE`      本机产的会被 `_is_self_ghost` 滤掉
##   `ghost_id` **不带 `seed_` 前缀**  产品就是按这个前缀认陪练的
##   `is_bot = false`              种子池 396 条实测也全是 false —— 拿 is_bot 当判据会假绿
static func run() -> void:
	GameState.test_mode = true
	var pool: Dictionary = {Backend.POOL_KEY: {}}
	var names := ["阿龟", "小壳", "铁甲", "疾风", "深海", "岩心", "赤焰",
		"苔痕", "浪吟", "霜背", "雷纹", "沙隐", "潮生", "碧鳞"]
	var bt := int(GameState.season_total_battles)
	for i in range(N_ROWS):
		Backend.pool_add(pool, {
			"schema_ver": Backend.SCHEMA_VER,
			"ghost_id": "uicons_r%d" % i,
			"is_bot": false,
			"origin": Backend.ORIGIN_REMOTE,
			"profile": {"name": str(names[i % names.size()])},
			"season_wins": 18 - i,
			"hearts": 3 + (i % 3),
			"season_sweeps": int((N_ROWS - i) / 3),
			"season_total_battles": bt,
		})
	Backend.pool_override = pool
	print("[LBSEED] 注入 %d 条真人快照(场次 %d)" % [N_ROWS, bt])


## ★用完必须清 —— `pool_override` 是 static, 活过场景切换。
static func clear() -> void:
	Backend.pool_override = {}
