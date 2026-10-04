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
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"detritus_tint": Color(0.66, 0.64, 0.56, 1.0),   # 2026-10-04 再压: 小贝壳在灯光下发白, 和龟身高光抢眼
		"ring_mod": {"dusk2_trunk": Color(0.74, 0.70, 0.68)},   # 树干在暗处(0.60 实拍几乎看不见)
		"ring_per": 2,   # 巨树干一簇最多 2 棵: 7 棵挤成一堵墙(实拍), 参考是一棵棵分开站
		"ground_tileset_hsv": Vector3(0.156, 0.30, 0.62),   # 2026-10-04「看清每只龟」: S0.43→0.30 V0.76→0.62(量: 龟立绘像素与地面 ΔE<15 的占比, 最坏一只 0.32→0.15; 深礁试过同样压暗反而变差 0.23→0.26, 已撤)   # V 0.66→0.76: 实拍中位 V0.49 而参考 0.58(2026-10-03 量)   # 地面目标色 = mixed_034 地面中位实测(H56 S0.43)
		"ground_tileset_tint": Color(0.70, 0.66, 0.42),   # 图块原色(生成器的鲜绿/粉红崖边)压进主题色调
		"ground_tileset": "tiles_dusk",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"use_layout": true,   # 场内物件按 LAYOUT 设计布局摆
		"fg_band_col": Color(0.035, 0.050, 0.030),   # 镜头前剪影带颜色(贴图是纯白剪影)
		"no_base_midground": true,   # 默认中景(沉船/紫海葵)不进主题
		"ring_r": [1.0, 1.06],      # 外围物件站在平台边沿上, 不悬在黑海面上
		"ring_spread": 55.0,
		"prop_shadow": 0.55,   # 物件接地影
		"smooth_shade": 1.0,   # 地面不抖动: 参考是柔和涂抹, 抖动网点读作纱窗
		"ring_lanterns": 0,   # 撤: 悬在黑里的红光没有挂点, 读作乱飞(用户 2026-10-03); 红光只留插地火把
		"ring_lantern_col": Color(1.0, 0.08, 0.10, 0.95),
		"wall_h": 0.35,   # 海岸竖面压成矮边(高墙沿格子成一排台阶方块)
		"lamp_tex": "dusk3_lantern_b",   # 2026-10-04 再换 a→b: 场内三盏原是细杆小灯 lantern_a(1.5 米), 实拍读不清; 与周边船灯同一粗桩款   # 2026-10-04 换: 浮木桩上挂的旧船灯(原「石墩红烛」是照搬参考的祭祀题材)
		"lamp_h": 1.75,   # 1.5→1.75: 粗桩款配周边那圈(1.65)略高一点, 场内是主光源
		"field_tufts": ["dusk2_grass_a", "dusk2_grass_b", "dusk2_grass_c"],   # 2026-10-03 重画: 粗黑描线+三层明暗的大草丛(mixed_034)
		"field_tufts_clusters": 9,
		"field_piles": ["dusk3_anchor_a", "dusk3_shell_a", "dusk3_wreck_a", "dusk2_stones_a", "dusk2_stones_b"],   # 2026-10-04 换: 海草缠锚 / 龟壳化石 / 沉船木板 + 叠石(原骷髅堆/红木十字是照搬参考题材)
		"field_piles_clusters": 10,
		"field_piles_h": [1.1, 1.6],
		"field_tufts_h": [1.6, 2.4],
		"edge_soft": 1.0,      # 聚光往里收: 参考 mixed_033/034 中心亮池、四周沉黑
		"spot_amt": 0.55,
		"rim_light_mod": Color(1, 1, 1),
		"rim_halo_col": Color(0.85, 0.06, 0.05, 0.35),   # 参考红光是小而亮的点, 地面不抹成一片橙
		"rim_halo_size": 1.7,
		## ★★2026-10-03 改成「暗林」(对标咩咩 Darkwood)。原来那版「黄昏孤岛」是我凭空想的方向;
		##   这版每一项都对着**真实游玩**截帧(桌面 `咩咩参考_真实游玩20张.jpg` 的 mixed_033~035)。
		"label": "暗林",
		## 地面: Darkwood 真实地面渲染色实测 (0.60,0.57,0.35); 按本仓光照实测倍率 ×1.8 反推反照率
		"ground_col": Color(0.360, 0.420, 0.250),   # mixed_034: 灰绿(鼠尾草绿), 不是橄榄黄
		"stone_col": Color(0.356, 0.415, 0.247),   # 贴近地面色: 两块石台不再是显眼的方块
		"detail_amt": 0.35,   # 细纹压低: 放大看是一层颗粒
		"detail_tex": "ground_strokes",
		"detail_scale": 0.14,
		"sed_amt": 0.20,      # 大块柔和明暗(参考地面是涂抹感)
		"shore_col": Color(0.262, 0.248, 0.140),
		## 边界: 真实房间是平台边缘断成**暗色竖崖**, 不是亮色砖墙
		"wall_col": Color(0.100, 0.110, 0.080),
		## 外围压到近黑(参考: 平台外是虚空)。用户定的是海, 所以保留海、只压到接近虚空的明度
		"water_col": Color(0.030, 0.036, 0.050),
		"edge_dark": 0.06,
		"caustic_amt": 0.0,   # 林地上不该有水下焦散光纹
		"edge_tufts": ["dusk2_grass_a", "dusk2_grass_b", "dusk2_grass_c"],   # 与场内同一套草
		"edge_tufts_n": 170,
		"edge_tufts_r": [0.93, 1.01],   # 贴着平台边沿一圈密草, 盖住格子台阶(参考边沿是草边)
		"edge_tufts_h": [0.8, 1.4],
		## 框边: 比角色大好几倍的暗色树干剪影(参考 mixed_033~035 左右两侧)
		"ring_props": ["dusk2_trunk"],   # 2026-10-03 重画: 粗描线红褐巨树干(mixed_034 两侧框边)
		"ring_density": 1.1,
		"ring_h": [6.5, 9.0],   # 巨树干要顶出画面上沿(参考两侧树干比角色大好几倍)
		"ring_avoid_bottom": true,
		"fg_band": "fg_sea_band",   # 2026-10-04 重画: 两角大海带框边 + 下沿礁石/锚链 + 远处一排矮海带, 远/中/近三层灰度(原 fg_grass_band 是一排程序锯齿草)
		## 地面碎件: 真实房间散着大量低对比小碎件(骨头/碎石/草屑)
		"detritus": ["dusk3_debris_a", "dusk3_debris_b", "dusk2_debris_c", "dusk2_debris_e", "ink_tuft_a", "ink_tuft_b"],   # 2026-10-04: 碎骨换成小贝壳/藤壶石(我们的海), 留小石子 + 墨线小草
		"detritus_n": 110,   # 180→110: 满地亮碎点和龟身高光抢眼(战斗中段实拍)
		"detritus_size": 0.8,
		"detritus_edge_bias": 1.5,
		## 周边一圈红烛(参考 Darkwood 房间沿边一圈红光)
		"rim_lights": 18,
		"rim_light_tex": "dusk3_lantern_b",   # 2026-10-04 再换: 粗木桩+缠绳+大船灯(lantern_a 是细杆小灯, 实拍读着比旧红烛细); 风格锚 = dusk3_lantern_a   # 红烛→船灯
		"rim_light_real": 6,
		"rim_light_h": 1.65,          # 2026-10-04 1.4→1.65 + 换粗桩 lantern_b: 原细杆船灯 1.4 实拍比旧红烛(1.25·石墩粗)读着更细   # 第一版 0.55 实拍看不见(火盆是 1.28)
		"rim_light_energy": 1.6,
		"rim_light_range": 3.0,
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
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"fg_band_layer_gain": [1.0, 1.8, 1.7],   # 2026-10-04 [近,中,远]: 主题色近黑, 远层实拍中位亮度只有 22/255、中层 0 ⇒ 三层读成一坨; 单独提中/远两层
		"ground_tileset_hsv": Vector3(0.467, 0.56, 0.37),   # V 0.44→0.37: 实拍中位 V0.69 而参考 0.57   # 地面目标色 = anchordeep_011 地面中位实测(H168 S0.50)
		"ground_tileset_tint": Color(0.62, 0.78, 0.76),   # 图块原色(生成器的鲜绿/粉红崖边)压进主题色调
		"ground_tileset": "tiles_reef",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"use_layout": true,   # 场内物件按 LAYOUT 设计布局摆
		"fg_band_col": Color(0.020, 0.060, 0.060),   # 镜头前剪影带颜色(贴图是纯白剪影)
		"no_base_midground": true,   # 默认中景(沉船/紫海葵)不进主题
		"ring_r": [1.0, 1.06],      # 外围物件站在平台边沿上, 不悬在黑海面上
		"ring_spread": 55.0,
		"prop_shadow": 0.55,   # 物件接地影
		"smooth_shade": 1.0,   # 地面不抖动: 参考是柔和涂抹, 抖动网点读作纱窗
		"wall_h": 0.35,   # 海岸竖面压成矮边(高墙沿格子成一排台阶方块)
		"lamp_tex": "reef2_lamp_a",   # 2026-10-03 重画: 螺壳托着发光珍珠(anchordeep 顶部那几团白光的来源物)
		"lamp_h": 1.3,
		"field_tufts": ["reef2_kelp_a", "reef2_kelp_b"],   # 2026-10-03 重画: 橄榄绿带斑点的海草丛(anchordeep_011)
		"field_piles": ["reef2_rocks_a", "reef2_rocks_b", "reef3_coral_a", "reef3_shell_coins"],   # 2026-10-04: 长眼睛珊瑚塔(照搬 Anchordeep 造型)换成管珊瑚塔 / 长满海葵、夹着深海币的龟壳化石
		"field_piles_clusters": 7,
		"field_piles_h": [0.75, 1.05],   # 礁石放到 1.1~1.6 会盖住正在打的龟(装饰物不挡路, 单位会走进去)
		"field_tufts_mod": Color(0.86, 0.90, 0.82),   # 新海草比参考略亮略黄, 轻压
		"field_tufts_clusters": 9,
		"field_tufts_h": [1.6, 2.4],
		"caustic_web": 1.0,    # 网状细线焦散(anchordeep_011/016/020)
		"edge_soft": 0.9,
		"spot_amt": 0.35,
		"rim_halo_col": Color(0.15, 0.75, 0.40, 0.40),
		"rim_halo_size": 2.2,
		## ★★2026-10-03 改成「深礁」(对标咩咩 Anchordeep), 对照真实游玩截帧
		##   anchordeep_003/011/020/025 等 14 张(桌面 `咩咩参考_真实游玩20张.jpg`)。
		"label": "深礁",
		## 地面: Anchordeep 真实地面渲染色实测 (0.15~0.27, 0.42~0.61, 0.41~0.56) 青绿, 反推反照率
		"ground_col": Color(0.160, 0.410, 0.390),
		"stone_col": Color(0.158, 0.406, 0.386),
		"detail_amt": 0.35,   # 细纹压低: 放大看是一层颗粒
		"detail_tex": "ground_strokes",
		"detail_scale": 0.14,
		"sed_amt": 0.20,      # 大块柔和明暗(参考地面是涂抹感)
		"shore_col": Color(0.100, 0.230, 0.220),
		"wall_col": Color(0.040, 0.075, 0.085),       # 暗色竖崖
		"water_col": Color(0.012, 0.030, 0.040),      # 外围压到接近虚空
		"edge_dark": 0.05,
		"caustic_amt": 0.26,
		"caustic_far": 1.0,   # 整片地面都有水下光纹(Anchordeep 最认得出的特征)
		"caustic_col": Color(0.70, 1.0, 0.92, 1.0),
		"caustic_scale": 0.95,  # 网状焦散的胞元≈1 米(参考里比角色略大)
		"edge_tufts": ["reef2_kelp_a", "reef2_kelp_b"],
		"edge_tufts_n": 150,
		"edge_tufts_r": [0.93, 1.01],
		"edge_tufts_h": [0.7, 1.3],
		## 框边: 暗色高海草(参考里平台四周一圈海草剪影)
		"ring_props": ["reef2_kelp_a", "reef2_kelp_b", "reef2_kelp_a", "reef2_rocks_b", "reef3_coral_a", "reef2_clam_a", "reef2_clam_b"],   # anchordeep_011: 高海草墙夹着石堆/珊瑚塔, 上沿是发光的大珍珠贝
		"ring_h_of": {"reef2_rocks_b": [1.5, 2.2], "reef3_coral_a": [2.0, 2.8], "reef2_clam_a": [1.6, 2.2], "reef2_clam_b": [1.5, 2.0]},
		"ring_glow_of": {"reef2_clam_a": Color(0.80, 0.92, 1.0, 0.30)},   # 珍珠是发光的(anchordeep_011 上沿那几团白光)
		"ring_density": 1.1,
		"ring_h": [3.0, 5.2],
		"ring_avoid_bottom": true,
		"fg_band": "fg_sea_band",   # 2026-10-04 重画: 两角大海带框边 + 下沿礁石/锚链 + 远处一排矮海带, 远/中/近三层灰度(原 fg_grass_band 是一排程序锯齿草)
		## 地面碎件: 贝壳/小骨/碎石
		"detritus": ["reef2_pebbles_a", "reef2_pebbles_b", "reef2_pebbles_c", "reef2_pebbles_d", "reef2_pebbles_e", "ink_tuft_a"],   # anchordeep_011: 地上一串串石板蓝小卵石(2026-10-03 新画)
		"detritus_n": 110,   # 2026-10-04 170→110: 交战区一地深蓝卵石, 和龟脚下的影子/描线混在一起
		"detritus_edge_bias": 2.0,
		"detritus_tint": Color(0.50, 0.56, 0.72, 1.0),   # 卵石吃光后发白; 参考是深藏青
		"detritus_size": 0.7,
		## 周边一圈绿色光球(参考 Anchordeep 的绿/白光点)
		"rim_lights": 16,
		"rim_light_tex": "reef2_lamp_b",
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
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"ring_per": 2,
		"ring_h_of": {"shoal2_rubble_b": [1.4, 2.0]},
		"ground_tileset_hsv": Vector3(0.750, 0.80, 0.55),   # S 0.62→0.80 H→270: 实拍 S0.56 而参考 S0.78 H282   # 地面目标色 = mixed_012 地面中位实测(H264 S0.62)
		"ground_tileset_tint": Color(0.80, 0.70, 0.95),   # 图块原色(生成器的鲜绿/粉红崖边)压进主题色调
		"ground_tileset": "tiles_shoal",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"use_layout": true,   # 场内物件按 LAYOUT 设计布局摆
		"fg_band_col": Color(0.050, 0.025, 0.070),   # 镜头前剪影带颜色(贴图是纯白剪影)
		"no_base_midground": true,   # 默认中景(沉船/紫海葵)不进主题
		"ring_r": [1.0, 1.06],      # 外围物件站在平台边沿上, 不悬在黑海面上
		"ring_spread": 55.0,
		"prop_shadow": 0.55,   # 物件接地影
		"smooth_shade": 1.0,   # 地面不抖动: 参考是柔和涂抹, 抖动网点读作纱窗
		"ring_lanterns": 0,   # 撤: 悬在黑里的红光没有挂点, 读作乱飞(用户 2026-10-03); 红光只留插地火把
		"ring_lantern_col": Color(1.0, 0.06, 0.16, 0.95),
		"edge_tufts": ["shoal2_grass_a", "shoal2_grass_b"],
		"edge_tufts_n": 150,
		"edge_tufts_r": [0.93, 1.01],
		"edge_tufts_h": [0.8, 1.3],
		"edge_tufts_mod": Color(1, 1, 1),
		"wall_h": 0.35,   # 海岸竖面压成矮边(高墙沿格子成一排台阶方块)
		"lamp_tex": "shoal2_brazier_b",   # 2026-10-03 重画: 黑铁杆上的红火盆(mixed_012 底部那三盏)
		"lamp_h": 2.3,
		"field_tufts": ["shoal2_grass_a", "shoal2_grass_b"],   # 2026-10-03 重画: 靛紫高草丛(mixed_012)
		"field_tufts_clusters": 9,
		"field_tufts_h": [1.6, 2.4],
		"field_tufts_mod": Color(1, 1, 1),   # 新素材本身就是参考色
		"field_piles": ["shoal3_coral_altar", "shoal3_coins", "shoal2_rubble_a", "shoal2_rubble_b"],   # 2026-10-04: 粉骷髅堆换成龟纹石台长珊瑚 / 砗磲里溢出的深海币 + 品红碎石堆
		"field_piles_clusters": 13,
		"field_piles_h": [1.1, 1.6],
		"field_piles_mod": Color(1, 1, 1),
		"edge_soft": 1.0,
		"spot_amt": 0.45,
		"rim_light_mod": Color(1, 1, 1),
		"rim_halo_col": Color(0.85, 0.05, 0.12, 0.35),   # 参考红光是小而亮的点, 地面不抹成一片橙
		"rim_halo_size": 1.7,
		## ★★2026-10-03 改成「紫墟」(对标咩咩教程那座紫色地牢), 对照真实游玩截帧 mixed_009/012/016。
		"label": "紫墟",
		## 地面: 真实渲染色实测 (0.24~0.35, 0.04~0.10, 0.36~0.44) 很饱和的深紫, 反推反照率
		"ground_col": Color(0.300, 0.215, 0.420),   # mixed_012: 薰衣草紫地面, 不是深酒红
		"stone_col": Color(0.297, 0.213, 0.416),
		"detail_amt": 0.35,   # 细纹压低: 放大看是一层颗粒
		"detail_tex": "ground_strokes",
		"detail_scale": 0.14,
		"sed_amt": 0.20,      # 大块柔和明暗(参考地面是涂抹感)
		"shore_col": Color(0.130, 0.035, 0.190),
		"wall_col": Color(0.050, 0.020, 0.080),
		"water_col": Color(0.015, 0.008, 0.030),
		"edge_dark": 0.05,
		"caustic_amt": 0.0,
		"ring_props": ["shoal2_trunk", "shoal2_trunk", "shoal2_rubble_b"],   # mixed_012/016: 外围暗紫巨树 + 碎石堆
		"ring_mod": {"shoal2_trunk": Color(0.80, 0.76, 0.86)},
		"ring_density": 0.9,
		"ring_h": [6.5, 9.0],   # 巨树干要顶出画面上沿(参考两侧树干比角色大好几倍)
		"ring_avoid_bottom": true,
		"fg_band": "fg_sea_band",   # 2026-10-04 重画: 两角大海带框边 + 下沿礁石/锚链 + 远处一排矮海带, 远/中/近三层灰度(原 fg_grass_band 是一排程序锯齿草)
		"detritus": ["shoal3_debris_a", "shoal3_debris_b", "shoal2_debris_b", "ink_tuft_a"],   # 2026-10-04: 粉碎骨换成碎珊瑚枝 / 小螺壳, 留小点
		"detritus_n": 110,
		"detritus_size": 0.75,
		"detritus_edge_bias": 1.6,
		"detritus_tint": Color(0.75, 0.70, 0.80, 1.0),   # 2026-10-04: 碎珊瑚/小螺压暗, 别跟龟抢
		## 周边一圈红光(参考紫色地牢沿边是红色光源)
		"rim_lights": 16,
		"rim_light_tex": "shoal2_brazier_a",
		"rim_light_real": 6,
		"rim_light_h": 2.0,   # 参考火盆比角色高一倍
		"rim_light_energy": 1.7,
		"rim_light_range": 3.0,
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
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"ring_per": 2,
		"ring_mod": {"storm2_trunk": Color(0.80, 0.74, 0.74)},
		"ground_tileset_hsv": Vector3(0.158, 0.30, 0.34),   # 2026-10-04「看清每只龟」: S0.41→0.30 V0.42→0.34(同一把尺: 最坏一只 0.15→0.12)   # 地面目标色 = mixed_035 地面中位实测(H57 S0.41)
		"ground_tileset": "tiles_storm",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"ground_tileset_tint": Color(0.82, 0.78, 0.55),
		"use_layout": true,   # 场内物件按 LAYOUT 设计布局摆
		"fg_band_col": Color(0.090, 0.015, 0.020),   # 镜头前剪影带颜色(贴图是纯白剪影)
		"no_base_midground": true,   # 默认中景(沉船/紫海葵)不进主题
		"ring_r": [1.0, 1.06],      # 外围物件站在平台边沿上, 不悬在黑海面上
		"ring_spread": 55.0,
		"prop_shadow": 0.55,   # 物件接地影
		"smooth_shade": 1.0,   # 地面不抖动: 参考是柔和涂抹, 抖动网点读作纱窗
		"ring_lanterns": 0,   # 撤: 悬在黑里的红光没有挂点, 读作乱飞(用户 2026-10-03); 红光只留插地火把
		"ring_lantern_col": Color(1.0, 0.05, 0.06, 0.95),
		"wall_h": 0.35,   # 海岸竖面压成矮边(高墙沿格子成一排台阶方块)
		"lamp_tex": "storm3_buoy_lamp",   # 2026-10-04: 墓碑烛(照搬参考)换成系泊桩挂红船灯 + 红白浮标
		"lamp_h": 1.7,
		"field_tufts": ["storm2_grass_a", "storm2_grass_b", "storm2_grass_c"],   # 2026-10-03 重画: 鲜绿高草丛(mixed_035 边沿)
		"field_tufts_clusters": 8,
		"field_tufts_mod": Color(1, 1, 1),
		"field_piles": ["storm2_logs_a", "storm2_logs_b", "storm3_net_a", "storm3_traps_a"],   # 2026-10-04: 木桩 X 架/十字桩换成挂浮子的渔网 / 捕虾笼, 留捆柴堆
		"field_piles_clusters": 8,
		"field_piles_h": [1.1, 1.6],
		"field_piles_mod": Color(1, 1, 1),
		"field_tufts_h": [1.6, 2.4],
		"edge_soft": 1.0,
		"spot_amt": 0.72,
		"rim_light_mod": Color(1, 1, 1),
		"rim_halo_col": Color(0.95, 0.05, 0.04, 0.45),   # 参考红光是小而亮的点, 地面不抹成一片橙
		"rim_halo_size": 2.6,
		## ★★2026-10-03 改成「赤林」(对标红调的 Darkwood, 真实游玩截帧 mixed_035)。
		##   结构与 V1 暗林相同, **用的是今天给 V1 新做的那批素材**(树干/红烛/碎件/草丛),
		##   只换色调。不是复用旧素材库(用户「不要复用」说的是库里已有的那些)。
		"label": "赤林",
		"ground_col": Color(0.460, 0.500, 0.300),   # mixed_035: 中心是淡黄绿的亮地, 红的是四周
		"stone_col": Color(0.455, 0.495, 0.297),
		"detail_amt": 0.35,   # 细纹压低: 放大看是一层颗粒
		"detail_tex": "ground_strokes",
		"detail_scale": 0.14,
		"sed_amt": 0.20,      # 大块柔和明暗(参考地面是涂抹感)
		"shore_col": Color(0.300, 0.110, 0.080),
		"wall_col": Color(0.200, 0.035, 0.040),   # mixed_035: 平台外一整圈是红雾, 暗林那版是黑
		"water_col": Color(0.110, 0.012, 0.020),
		"edge_dark": 0.05,
		"caustic_amt": 0.0,
		"ring_props": ["storm2_trunk"],   # 2026-10-03 重画: 长刺刻符的暗红巨树干(mixed_035 两侧)
		"ring_density": 1.1,
		"ring_h": [6.5, 9.0],   # 巨树干要顶出画面上沿(参考两侧树干比角色大好几倍)
		"ring_avoid_bottom": true,
		"fg_band": "fg_sea_band",   # 2026-10-04 重画: 两角大海带框边 + 下沿礁石/锚链 + 远处一排矮海带, 远/中/近三层灰度(原 fg_grass_band 是一排程序锯齿草)
		"detritus": ["storm2_debris_a", "storm2_debris_b", "storm2_debris_c", "storm2_debris_d", "storm2_debris_e", "ink_tuft_a"],   # mixed_035: 地上是短草芽/断枝/小石子(2026-10-03 新画)
		"detritus_n": 170,
		"detritus_size": 0.8,
		"detritus_edge_bias": 1.5,
		"detritus_tint": Color(0.92, 0.92, 0.86, 1.0),
		"edge_tufts": ["storm2_grass_a", "storm2_grass_b", "storm2_grass_c"],
		"edge_tufts_n": 170,
		"edge_tufts_r": [0.93, 1.01],   # 贴着平台边沿一圈密草, 盖住格子台阶(参考边沿是草边)
		"edge_tufts_h": [0.8, 1.4],
		## 比 V1 更多更亮的红光(参考 mixed_035 整个房间被红光浸着)
		"rim_lights": 14,   # 墓碑烛放大后 24 座排成一圈篱笆; mixed_035 一圈约 8~10 座
		"rim_light_tex": "storm3_buoy_lamp",   # 2026-10-04: 墓碑烛→系泊桩船灯
		"rim_light_real": 8,
		"rim_light_h": 2.0,   # 2026-10-04 1.7→2.0: 系泊桩比旧墓碑烛(1.9)窄一圈, 同高读着细
		"rim_light_energy": 2.6,
		"rim_light_range": 4.0,
		"light_col": Color(1.0, 0.16, 0.12),
		"light_energy": 1.4,
		"light_fixture": "dusk_candle",
		"obstacles": ["dusk_boulder"],
		"mid_props": ["dusk_trunk_silhouette"],
		"fog_col": Color(0.300, 0.025, 0.040),
		"bg_kind": "crimson_fog",
		"bg_top": Color(0.090, 0.008, 0.016),
		"bg_horizon": Color(0.300, 0.030, 0.045),
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


## ★★场内物件的**设计布局**(四版共用一张构图, 各版换各自素材)。
## 依据: 咩咩每间房的物件是有构图的(四角成簇 / 边上框住 / 中间留战斗区), 不是随机撒点。
##   用户 2026-10-03:「人家是用代码解决的吗」—— 之前 field_tufts/field_piles 按半径随机撒, 一看就是程序生成。
## ★左右两侧 |u|>0.5 的已乘 0.84: 实拍角上的簇一半压在两侧 HUD 面板底下。
## ★2026-10-04「看清每只龟」: 交战区里那 4 件(|u|,|v|<0.45)一律改成矮物件堆(≤0.95 米)。
##   原来有两丛 1.5~1.6 米高草长在场中, 比龟高出一截, 龟走进去就被盖住。
## 每行 [u, v, 种类, 高(米)]: u/v = 战场椭圆归一化坐标(右/下为正); 种类 t = 草丛(field_tufts), p = 物件堆(field_piles)。
const LAYOUT: Array = [
	[-0.62, -0.60, "p", 1.9],
	[-0.69, -0.47, "t", 2.2],
	[-0.53, -0.71, "t", 1.9],
	[-0.74, -0.63, "t", 2.0],
	[0.60, -0.62, "p", 1.8],
	[0.50, -0.73, "t", 2.0],
	[0.70, -0.51, "t", 2.2],
	[-0.55, 0.64, "p", 2.0],
	[-0.66, 0.57, "p", 1.5],
	[-0.71, 0.45, "t", 2.1],
	[-0.46, 0.75, "t", 1.8],
	[0.59, 0.62, "p", 1.9],
	[0.71, 0.48, "t", 2.2],
	[0.48, 0.73, "t", 1.9],
	[0.66, 0.71, "t", 1.7],
	[-0.12, -0.88, "t", 1.8],
	[0.10, -0.86, "t", 2.0],
	[0.00, -0.83, "p", 1.4],
	[-0.18, 0.87, "t", 1.9],
	[0.16, 0.88, "t", 2.1],
	[-0.78, -0.08, "t", 2.2],
	[-0.76, 0.12, "t", 1.9],
	[0.78, 0.06, "t", 2.1],
	[0.76, -0.12, "t", 1.8],
	[-0.30, 0.38, "p", 0.95],
	[0.34, -0.32, "p", 0.9],
	[0.28, 0.44, "p", 0.9],
	[-0.36, -0.36, "p", 0.9]
]


## 当前主题的配置。★找不到就**报错而不是静默兜底** —— 兜底会让"主题没生效"看起来像"主题生效了"。
## ★桌面预览用: 环境变量 ARENA_THEME=V1_DUSK 等只在**第一次取配置时**覆盖一次 active。
##   之后代码里对 active 的赋值照常生效(门禁里切主题的测试不受影响); 不设 ⇒ 什么都不变。
static var _env_checked: bool = false

static func cfg() -> Dictionary:
	if not _env_checked:
		_env_checked = true
		var _e: String = OS.get_environment("ARENA_THEME")
		_e = {"V1_DUSK": V1_DUSK, "V2_REEF": V2_REEF, "V3_SHOAL": V3_SHOAL, "V4_STORM": V4_STORM}.get(_e, _e)
		if THEMES.has(_e):
			active = _e
	assert(THEMES.has(active), "ArenaTheme.active 不是已知主题: " + str(active))
	return THEMES.get(active, THEMES[V1_DUSK])


static func cfg_of(name: String) -> Dictionary:
	return THEMES.get(name, {})

