class_name ArenaTheme
extends RefCounted
## 战场【主题】—— 四版完整地图共存, 一个常量切换。
##
## ★用户 2026-10-03:「我现在给你一个晚上的时间自己做3到4版，质量要达到咩咩启示录的质量」
##   「记住是3到4版**完整的地图**包括各种东西背景等等」
##
## 【为什么是一个常量而不是四个分支】
##   分支没法并排对比(用户要挑), 而且四份各自演进必然漂; 共存则同一次实拍就能出对照表。
##
## 【每一版必须九层齐全】地面材质 / 海岸线 / 周边装饰环 / 前景框边 /
##   挡路障碍 / 中景地标 / 远景背景 / 灯光(带灯具) / 氛围粒子。
##   ★少一层就不算"完整的地图" —— 判据 `tests/verify_arena_themes.gd` 逐层点名。
##
## 【四版的方向】(方案书 `docs/plans/20261003-四版完整地图.md` §4.2)
##   V1 黄昏孤岛 · V2 夜礁(最贴咩咩地牢) · V3 白昼浅滩 · V4 风暴
##
## ⚠ 本文件只放**配置**, 不放构建逻辑 —— 构建在 `battle_world_builder.gd`,
##   它读这里的表。配置与实现混在一起就没法"换一个数看四版"。

## ★★★`V0_BASE` = **现在这套已验收的画面**(TILE_COLS 的暖石台调色板 + 青水),
##   它是**默认值**。为什么不拿四个新版当默认:
##   四版还没建完(周边装饰环/前景框边/带灯具的灯光/氛围粒子都没接),
##   实测它们各差一两条画面判据 —— 把没建完的东西设成默认 = 让门禁红着过夜。
##   ⇒ 默认走已验收的那套, 四版是**可切换的预览**, 用户选中哪版再把它扶正。
const V0_BASE := "base"        # 现状(已验收·默认)
const V1_DUSK := "dusk"        # 黄昏孤岛
const V2_REEF := "reef"        # 夜礁
const V3_SHOAL := "shoal"      # 白昼浅滩
const V4_STORM := "storm"      # 风暴

## ★`ALL` 只列【四个新版】—— 判据按它数"3到4版"。`V0_BASE` 是现状基线, 不参与评比。
const ALL: Array = [V1_DUSK, V2_REEF, V3_SHOAL, V4_STORM]

## ★当前生效的主题。改这一个值 = 换一整张地图。
## ⚠ 地形生成器 `tools/gen_arena_map.py` 也要跟着跑一次(它按主题换地面类型与岸线扰动)。
static var active: String = V0_BASE


## 每一版的完整配置。★键名就是那九层, 缺一层判据会红。
const THEMES: Dictionary = {
	## ★★`base` 的四个颜色**必须与 `battle_world_builder.TILE_COLS` 和
	##   `ground_water.gdshader` 的默认 `shallow_col` 逐值相同** —— 它的全部意义就是
	##   「什么都没换」。判据 `verify_arena_themes` 不检查它(它不在 ALL 里),
	##   所以这里写错了不会红 ⇒ 下面逐条标出它对应的源, 改任一侧都要回来看一眼。
	V0_BASE: {
		"label": "现状(已验收)",
		"ground_col": Color(0.169, 0.184, 0.118),    # = TILE_COLS[0]
		"stone_col": Color(0.361, 0.318, 0.259),     # = TILE_COLS[2]
		"water_col": Color(0.122, 0.722, 0.769),     # = TILE_COLS[1] / shallow_col 默认
		"shore_col": Color(0.290, 0.251, 0.188),     # = TILE_COLS[3]
		"ring_props": ["(现状)"], "ring_density": 1.0,
		"fg_band": "(现状·无)", "obstacles": ["(现状)"], "mid_props": ["(现状)"],
		## ★★base **刻意不给** `bg_top`/`bg_horizon` —— 给了就会走那条斜坡, 而五个远景色
		##   本来不在一条线上, 推出来和原字面值对不上 = 悄悄改掉已验收的画面。
		##   不给 ⇒ `_bg_ramp` 走各调用点的原字面值 ⇒ 逐值不变。
		"bg_kind": "undersea",
		"light_col": Color(1.0, 0.96, 0.86), "light_energy": 1.0,
		"light_fixture": "(现状·无灯具)",
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "bubbles", "ambient_col": Color(0.58, 0.84, 1.0, 0.85),
	},
	V1_DUSK: {
		"label": "黄昏孤岛",
		## 地面: 暖沙→干草, 低饱和。★只给一种主材质(参考的战斗区都是单材质)
		"ground_col": Color(0.231, 0.196, 0.137),
		"stone_col": Color(0.286, 0.251, 0.200),
		## 海: 深蓝紫、低饱和 —— 必须比陆暗(实测参考: 海/陆 亮度比 < 1)
		"water_col": Color(0.078, 0.090, 0.169),
		"shore_col": Color(0.318, 0.263, 0.188),      # 湿沙
		## 周边装饰环(ARENA 外的海面/岸上, 不占活动空间)
		"ring_props": ["dusk_grass_tuft", "dusk_driftwood", "dusk_lamp_post"],
		"ring_density": 1.0,
		## 前景框边: 压住画面下沿的剪影
		"fg_band": "dusk_grass_silhouette",
		## 挡路障碍
		"obstacles": ["dusk_boulder"],
		## 中景地标
		"mid_props": ["dusk_far_rock", "dusk_wreck_post"],
		## 远景
		"bg_kind": "horizon_glow",                     # 海面→地平线暖光带→渐暗天
		"bg_top": Color(0.102, 0.090, 0.161),
		"bg_horizon": Color(0.627, 0.388, 0.212),
		## 灯光(必须有灯具, 不许凭空暖斑)
		"light_col": Color(1.0, 0.698, 0.388),
		"light_energy": 1.1,
		"light_fixture": "dusk_lamp_post",
		"sun_col": Color(1.0, 0.804, 0.620),
		"sun_energy": 0.85,
		## 氛围粒子(横飘沙尘 —— **不是**向上的气泡)
		"ambient_kind": "drift_dust",
		"ambient_col": Color(0.902, 0.780, 0.584, 0.35),
	},
	V2_REEF: {
		"label": "夜礁",
		"ground_col": Color(0.157, 0.161, 0.149),
		"stone_col": Color(0.212, 0.216, 0.204),
		"water_col": Color(0.035, 0.047, 0.078),
		"shore_col": Color(0.196, 0.200, 0.192),
		"ring_props": ["reef_candle_stone", "reef_fungus", "reef_bone_rubble"],
		"fg_band": "reef_rock_silhouette",
		"ring_density": 1.3,
		"obstacles": ["reef_menhir"],
		"mid_props": ["reef_far_spire"],
		"bg_kind": "into_black",                       # 咩咩地牢的做法: 直接沉进黑
		"bg_top": Color(0.016, 0.020, 0.031),
		"bg_horizon": Color(0.027, 0.035, 0.051),
		"light_col": Color(1.0, 0.580, 0.278),
		"light_energy": 1.5,
		"light_fixture": "reef_candle_stone",
		"sun_col": Color(0.541, 0.620, 0.839),
		"sun_energy": 0.60,
		"ambient_kind": "embers",                      # 只在烛台附近, 有因
		"ambient_col": Color(1.0, 0.608, 0.271, 0.5),
	},
	V3_SHOAL: {
		"label": "白昼浅滩",
		## ★★2026-10-03 从 (0.800,0.722,0.553) 压到这里。第一版按"白昼=高明度"想当然,
		##   实拍中间调只有 11.3%(判据要 ≥24%)、亮坡比 0.44(要 ≥1.0), **当场红两条**。
		##   量了参考才知道判据是对的: 咩咩的日景(raw_04 营地)地面 luma 中位 **119**、
		##   中间调占比 **47.7%** —— 它的白天**不是高调**, 和地牢(106/43.4%)在同一档。
		##   ⇒ 按 dusk 的实测反推(反照率 luma 0.200 → 渲染中间调 49.9%), 这里取 ≈0.33。
		"ground_col": Color(0.380, 0.349, 0.271),
		"stone_col": Color(0.333, 0.325, 0.310),
		"water_col": Color(0.129, 0.239, 0.263),   # 仍须比陆暗(判据④)
		"shore_col": Color(0.439, 0.408, 0.322),
		"ring_props": ["shoal_palm", "shoal_reed", "shoal_shell_pile", "shoal_flagpole"],
		"ring_density": 1.1,
		"fg_band": "shoal_big_leaf",
		"obstacles": ["shoal_rock"],
		"mid_props": ["shoal_far_island"],
		"bg_kind": "sky_horizon",                      # 开阔海 + 海平线 + 天空云带
		"bg_top": Color(0.596, 0.780, 0.898),
		"bg_horizon": Color(0.839, 0.890, 0.902),
		"light_col": Color(1.0, 0.961, 0.863),
		"light_energy": 0.4,
		"light_fixture": "shoal_flagpole",
		"sun_col": Color(1.0, 0.980, 0.925),
		"sun_energy": 0.60,
		"ambient_kind": "sun_glints",
		"ambient_col": Color(1.0, 1.0, 0.941, 0.28),
	},
	V4_STORM: {
		"label": "风暴",
		"ground_col": Color(0.188, 0.176, 0.161),
		"stone_col": Color(0.247, 0.247, 0.251),
		"water_col": Color(0.129, 0.149, 0.169),
		"shore_col": Color(0.224, 0.216, 0.200),
		"ring_props": ["storm_bent_grass", "storm_broken_frame"],
		"ring_density": 0.9,
		"fg_band": "storm_rain_veil",
		"obstacles": ["storm_boulder"],
		"mid_props": ["storm_far_wreck"],
		"bg_kind": "overcast",                         # 低垂乌云 + 远处雨幕
		"bg_top": Color(0.149, 0.157, 0.176),
		"bg_horizon": Color(0.361, 0.376, 0.400),
		"light_col": Color(0.776, 0.843, 1.0),
		"light_energy": 0.5,
		"light_fixture": "storm_broken_frame",
		"sun_col": Color(0.729, 0.769, 0.831),
		"sun_energy": 0.70,
		"ambient_kind": "rain_streaks",
		"ambient_col": Color(0.800, 0.859, 0.941, 0.4),
	},
}

## 这九个键是「完整的地图」的定义。判据逐个点名, 缺一个就不算完整。
const REQUIRED_KEYS: Array = [
	"ground_col", "shore_col", "water_col",     # ①地面材质 ②海岸线
	"ring_props", "fg_band",                     # ③周边装饰环 ④前景框边
	"obstacles", "mid_props",                    # ⑤挡路障碍 ⑥中景地标
	"bg_kind",                                   # ⑦远景背景
	"light_fixture",                             # ⑧灯光(带灯具)
	"ambient_kind",                              # ⑨氛围粒子
]


## 当前主题的配置。★找不到就**报错而不是静默兜底** —— 兜底会让"主题没生效"看起来像"主题生效了"。
static func cfg() -> Dictionary:
	assert(THEMES.has(active), "ArenaTheme.active 不是已知主题: " + str(active))
	return THEMES.get(active, THEMES[V1_DUSK])


static func cfg_of(name: String) -> Dictionary:
	return THEMES.get(name, {})

