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
		## ★★base **刻意不给** `ambient_col` —— 原值是 `Color(1,1,1,0.55)`(白·半透),
		##   我一度在这里填了 (0.58,0.84,1.0,0.85), 那会**悄悄改掉已验收的粒子颜色**,
		##   而五条画面判据量不到这么小的东西 ⇒ 照样全绿。
		##   ★这是今晚**第四次**同一个形状(远景斜坡 / 沙地映射 / 墙色 / 这里):
		##     「顺手给 base 也填一个相近的值」, 而**相近 ≠ 相等**。
		##   ⇒ 凡是 base 该保持原样的键, 一律**不给**, 让代码侧走原字面值兜底。
		"ambient_kind": "bubbles",
	},
	V1_DUSK: {
		"field_tufts": ["dusk_grass_tuft"],   # 场内成簇大草丛(mixed_033/034 · anchordeep_005/011)
		"field_tufts_clusters": 9,
		"field_tufts_h": [1.3, 2.1],
		"edge_soft": 1.0,      # 聚光往里收: 参考 mixed_033/034 中心亮池、四周沉黑
		"spot_amt": 0.55,
		"rim_light_mod": Color(1.0, 0.45, 0.40),
		"rim_halo_col": Color(0.85, 0.06, 0.05, 0.55),
		"rim_halo_size": 2.6,
		## ★★2026-10-03 改成「暗林」(对标咩咩 Darkwood)。原来那版「黄昏孤岛」是我凭空想的方向;
		##   这版每一项都对着**真实游玩**截帧(桌面 `咩咩参考_真实游玩20张.jpg` 的 mixed_033~035)。
		"label": "暗林",
		## 地面: Darkwood 真实地面渲染色实测 (0.60,0.57,0.35); 按本仓光照实测倍率 ×1.8 反推反照率
		"ground_col": Color(0.400, 0.410, 0.210),
		"stone_col": Color(0.372, 0.381, 0.195),   # 贴近地面色: 两块石台不再是显眼的方块
		"detail_amt": 0.22,   # 砖纹压到几乎看不见
		"sed_amt": 0.16,      # 大块柔和斑驳加强
		"shore_col": Color(0.262, 0.248, 0.140),
		## 边界: 真实房间是平台边缘断成**暗色竖崖**, 不是亮色砖墙
		"wall_col": Color(0.100, 0.110, 0.080),
		## 外围压到近黑(参考: 平台外是虚空)。用户定的是海, 所以保留海、只压到接近虚空的明度
		"water_col": Color(0.030, 0.036, 0.050),
		"edge_dark": 0.06,
		"caustic_amt": 0.0,   # 林地上不该有水下焦散光纹
		"edge_tufts": ["dusk_grass_tuft"],
		"edge_tufts_n": 70,
		"edge_tufts_h": [0.8, 1.4],
		## 框边: 比角色大好几倍的暗色树干剪影(参考 mixed_033~035 左右两侧)
		"ring_props": ["dusk_trunk_silhouette"],
		"ring_density": 0.8,
		"ring_h": [4.2, 6.4],
		"ring_avoid_bottom": true,
		"fg_band": "dusk_grass_silhouette",
		## 地面碎件: 真实房间散着大量低对比小碎件(骨头/碎石/草屑)
		"detritus": ["dusk_debris_bones", "dusk_debris_grass"],
		"detritus_n": 120,
		"detritus_size": 1.15,        # 原 0.38→0.62 仍是几像素的碎屑; 参考里骨堆/碎石是看得清的一块
		"detritus_edge_bias": 1.5,
		## 周边一圈红烛(参考 Darkwood 房间沿边一圈红光)
		"rim_lights": 18,
		"rim_light_tex": "dusk_candle",
		"rim_light_real": 6,
		"rim_light_h": 1.05,          # 第一版 0.55 实拍看不见(火盆是 1.28)
		"rim_light_energy": 2.8,
		"rim_light_range": 4.6,
		"light_col": Color(1.0, 0.262, 0.180),
		"light_energy": 1.0,
		"light_fixture": "dusk_candle",
		"obstacles": ["dusk_boulder"],
		"mid_props": ["dusk_trunk_silhouette"],
		"bg_kind": "into_black",
		"bg_top": Color(0.010, 0.016, 0.012),
		"bg_horizon": Color(0.040, 0.056, 0.040),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "embers",
		"ambient_col": Color(1.0, 0.86, 0.42, 0.45),     # 林间萤光(慢·微上飘)
	},
	V2_REEF: {
		"field_tufts": ["reef_kelp_tuft"],   # 场内成簇大草丛(mixed_033/034 · anchordeep_005/011)
		"field_tufts_clusters": 9,
		"field_tufts_h": [1.4, 2.3],
		"caustic_web": 1.0,    # 网状细线焦散(anchordeep_011/016/020)
		"edge_soft": 0.9,
		"spot_amt": 0.35,
		"rim_halo_col": Color(0.15, 0.75, 0.40, 0.40),
		"rim_halo_size": 2.2,
		## ★★2026-10-03 改成「深礁」(对标咩咩 Anchordeep), 对照真实游玩截帧
		##   anchordeep_003/011/020/025 等 14 张(桌面 `咩咩参考_真实游玩20张.jpg`)。
		"label": "深礁",
		## 地面: Anchordeep 真实地面渲染色实测 (0.15~0.27, 0.42~0.61, 0.41~0.56) 青绿, 反推反照率
		"ground_col": Color(0.140, 0.350, 0.330),
		"stone_col": Color(0.130, 0.325, 0.306),
		"detail_amt": 0.22,   # 砖纹压到几乎看不见
		"sed_amt": 0.16,      # 大块柔和斑驳加强
		"shore_col": Color(0.100, 0.230, 0.220),
		"wall_col": Color(0.040, 0.075, 0.085),       # 暗色竖崖
		"water_col": Color(0.012, 0.030, 0.040),      # 外围压到接近虚空
		"edge_dark": 0.05,
		"caustic_amt": 0.26,
		"caustic_far": 1.0,   # 整片地面都有水下光纹(Anchordeep 最认得出的特征)
		"caustic_col": Color(0.70, 1.0, 0.92, 1.0),
		"caustic_scale": 0.95,  # 网状焦散的胞元≈1 米(参考里比角色略大)
		"edge_tufts": ["reef_kelp_tuft"],
		"edge_tufts_n": 70,
		"edge_tufts_h": [0.7, 1.3],
		## 框边: 暗色高海草(参考里平台四周一圈海草剪影)
		"ring_props": ["reef_kelp_silhouette"],   # 第一版带方尖碑, 实拍像一排墓碑, 参考里没有
		"ring_density": 1.1,
		"ring_h": [3.0, 5.2],
		"ring_avoid_bottom": true,
		"fg_band": "dusk_grass_silhouette",   # 第一版用礁石剪影读成「远山」; 参考底部是暗色海草
		## 地面碎件: 贝壳/小骨/碎石
		"detritus": ["reef_debris_shells"],
		"detritus_n": 70,
		"detritus_edge_bias": 2.0,
		"detritus_tint": Color(0.55, 0.68, 0.76, 1.0),   # 偏暗蓝灰(参考碎件不是白的)
		"detritus_size": 1.1,
		## 周边一圈绿色光球(参考 Anchordeep 的绿/白光点)
		"rim_lights": 16,
		"rim_light_tex": "reef_glow_orb",
		"rim_light_real": 6,
		"rim_light_h": 1.3,
		"rim_light_energy": 3.2,
		"rim_light_range": 4.4,
		"light_col": Color(0.42, 1.0, 0.62),
		"light_energy": 1.0,
		"light_fixture": "reef_glow_orb",
		"obstacles": ["reef_menhir"],
		"mid_props": ["reef_kelp_silhouette"],
		"bg_kind": "deep_glow",                        # 深水: 暗青底 + 远处光点(对标 Anchordeep)
		"bg_top": Color(0.008, 0.022, 0.030),
		"bg_horizon": Color(0.030, 0.080, 0.090),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "embers",
		"ambient_col": Color(0.55, 1.0, 0.75, 0.45),   # 水中浮游光点
	},
	V3_SHOAL: {
		"edge_soft": 1.0,
		"spot_amt": 0.45,
		"rim_light_mod": Color(1.0, 0.45, 0.40),
		"rim_halo_col": Color(0.85, 0.05, 0.12, 0.55),
		"rim_halo_size": 2.6,
		## ★★2026-10-03 改成「紫墟」(对标咩咩教程那座紫色地牢), 对照真实游玩截帧 mixed_009/012/016。
		"label": "紫墟",
		## 地面: 真实渲染色实测 (0.24~0.35, 0.04~0.10, 0.36~0.44) 很饱和的深紫, 反推反照率
		"ground_col": Color(0.155, 0.040, 0.225),
		"stone_col": Color(0.140, 0.036, 0.205),
		"detail_amt": 0.22,   # 砖纹压到几乎看不见
		"sed_amt": 0.16,      # 大块柔和斑驳加强
		"shore_col": Color(0.130, 0.035, 0.190),
		"wall_col": Color(0.050, 0.020, 0.080),
		"water_col": Color(0.015, 0.008, 0.030),
		"edge_dark": 0.05,
		"caustic_amt": 0.0,
		"ring_props": ["shoal_ruin_column"],
		"ring_density": 0.9,
		"ring_h": [2.6, 4.2],
		"ring_avoid_bottom": true,
		"fg_band": "dusk_grass_silhouette",
		"detritus": ["shoal_debris_rubble"],
		"detritus_n": 90,
		"detritus_size": 1.1,
		"detritus_edge_bias": 1.6,
		"detritus_tint": Color(0.85, 0.75, 0.95, 1.0),
		## 周边一圈红光(参考紫色地牢沿边是红色光源)
		"rim_lights": 16,
		"rim_light_tex": "dusk_candle",
		"rim_light_real": 6,
		"rim_light_h": 1.1,
		"rim_light_energy": 3.0,
		"rim_light_range": 4.5,
		"light_col": Color(1.0, 0.20, 0.26),
		"light_energy": 1.0,
		"light_fixture": "dusk_candle",
		"obstacles": ["shoal_ruin_column"],
		"mid_props": ["shoal_ruin_column"],
		"fog_col": Color(0.090, 0.020, 0.120),
		"bg_kind": "violet_haze",
		"bg_top": Color(0.012, 0.004, 0.024),
		"bg_horizon": Color(0.060, 0.016, 0.090),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "embers",
		"ambient_col": Color(1.0, 0.45, 0.70, 0.45),
	},
	V4_STORM: {
		"field_tufts": ["dusk_grass_tuft"],   # 场内成簇大草丛(mixed_033/034 · anchordeep_005/011)
		"field_tufts_clusters": 8,
		"field_tufts_h": [1.3, 2.1],
		"edge_soft": 1.0,
		"spot_amt": 0.45,
		"rim_light_mod": Color(1.0, 0.40, 0.36),
		"rim_halo_col": Color(0.95, 0.05, 0.04, 0.60),
		"rim_halo_size": 2.8,
		## ★★2026-10-03 改成「赤林」(对标红调的 Darkwood, 真实游玩截帧 mixed_035)。
		##   结构与 V1 暗林相同, **用的是今天给 V1 新做的那批素材**(树干/红烛/碎件/草丛),
		##   只换色调。不是复用旧素材库(用户「不要复用」说的是库里已有的那些)。
		"label": "赤林",
		"ground_col": Color(0.300, 0.230, 0.140),
		"stone_col": Color(0.278, 0.212, 0.130),
		"detail_amt": 0.22,   # 砖纹压到几乎看不见
		"sed_amt": 0.16,      # 大块柔和斑驳加强
		"shore_col": Color(0.240, 0.180, 0.115),
		"wall_col": Color(0.090, 0.030, 0.030),
		"water_col": Color(0.030, 0.010, 0.012),
		"edge_dark": 0.05,
		"caustic_amt": 0.0,
		"ring_props": ["dusk_trunk_silhouette"],
		"ring_density": 0.9,
		"ring_h": [4.2, 6.4],
		"ring_avoid_bottom": true,
		"fg_band": "dusk_grass_silhouette",
		"detritus": ["dusk_debris_bones", "dusk_debris_grass"],
		"detritus_n": 120,
		"detritus_size": 1.15,
		"detritus_edge_bias": 1.5,
		"detritus_tint": Color(1.0, 0.85, 0.80, 1.0),
		"edge_tufts": ["dusk_grass_tuft"],
		"edge_tufts_n": 70,
		"edge_tufts_h": [0.8, 1.4],
		## 比 V1 更多更亮的红光(参考 mixed_035 整个房间被红光浸着)
		"rim_lights": 24,
		"rim_light_tex": "dusk_candle",
		"rim_light_real": 8,
		"rim_light_h": 1.1,
		"rim_light_energy": 3.6,
		"rim_light_range": 5.2,
		"light_col": Color(1.0, 0.16, 0.12),
		"light_energy": 1.4,
		"light_fixture": "dusk_candle",
		"obstacles": ["dusk_boulder"],
		"mid_props": ["dusk_trunk_silhouette"],
		"fog_col": Color(0.200, 0.020, 0.030),
		"bg_kind": "crimson_fog",
		"bg_top": Color(0.030, 0.004, 0.008),
		"bg_horizon": Color(0.160, 0.020, 0.030),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "embers",
		"ambient_col": Color(1.0, 0.40, 0.30, 0.5),
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

