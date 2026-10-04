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
		"fg_band_layer_gain": [1.0, 1.8, 1.7],   # 前景远/中层提亮(同深礁): 主题色近黑时远层贴着黑底读不出
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"detritus_tint": Color(0.66, 0.64, 0.56, 1.0),   # 2026-10-04 再压: 小贝壳在灯光下发白, 和龟身高光抢眼
		"ring_mod": {"dusk2_trunk": Color(0.74, 0.70, 0.68), "dusk4_trunk_b": Color(0.74, 0.70, 0.68), "dusk4_trunk_c": Color(0.74, 0.70, 0.68)},   # 树干在暗处(0.60 实拍几乎看不见)
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
		"field_piles": ["dusk3_anchor_a", "dusk3_shell_a", "dusk3_wreck_a", "dusk2_stones_a", "dusk2_stones_b", "dusk4_mush_a", "dusk4_mush_b"],   # 2026-10-04 +藤壶菌丛两款(新类别: 蘑菇)   # 2026-10-04 换: 海草缠锚 / 龟壳化石 / 沉船木板 + 叠石(原骷髅堆/红木十字是照搬参考题材)
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
		"ring_props": ["dusk2_trunk", "dusk4_trunk_b", "dusk4_trunk_c"],   # 2026-10-04 +断顶树干/挂藤树干: 一圈 20 来棵同一张图, 看得出是复制的   # 2026-10-03 重画: 粗描线红褐巨树干(mixed_034 两侧框边)
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
		"rim_light_tex_alt": ["dusk4_float_a", "dusk4_float_b"],   # 2026-10-04 一圈 18 盏同一张船灯 ⇒ 轮流换浮木桩挂玻璃浮球灯(两款)
		"rim_light_h_of": {"dusk4_float_a": 1.45, "dusk4_float_b": 1.6},
		"rim_light_tex": "dusk3_lantern_b",   # 2026-10-04 再换: 粗木桩+缠绳+大船灯(lantern_a 是细杆小灯, 实拍读着比旧红烛细); 风格锚 = dusk3_lantern_a   # 红烛→船灯
		"rim_light_real": 6,
		"rim_light_h": 1.65,          # 2026-10-04 1.4→1.65 + 换粗桩 lantern_b: 原细杆船灯 1.4 实拍比旧红烛(1.25·石墩粗)读着更细   # 第一版 0.55 实拍看不见(火盆是 1.28)
		"rim_light_energy": 1.6,
		"rim_light_range": 3.0,
		"light_col": Color(1.0, 0.262, 0.180),
		"light_energy": 1.0,
		"light_fixture": "dusk3_lantern_b",   # 2026-10-04 改成真在用的灯具名(原 dusk_candle 是一版没接线的旧名)
		## ⑤挡路障碍(2026-10-04): 中央大礁 → 缠锚链的老树桩, 两侧矮墙 → 长藤壶的倒木(两款)。footprint 不动, 只换外观。
		"obstacles": ["dusk4_stump", "dusk4_log_a", "dusk4_log_b"],
		"obstacle_tex": {"reef_big": "dusk4_stump", "reef_wall": ["dusk4_log_a", "dusk4_log_b"]},
		"obstacle_mod": Color(0.86, 0.84, 0.80),
		## ⑥中景(2026-10-04): 平台上沿一圈暗色灌木团, 站在巨树干身后(mixed_033/034 平台外两角)。
		"mid_props": ["dusk4_bush_a", "dusk4_bush_b", "dusk4_bush_c"],
		"mid_n": 9,
		"mid_h": [2.0, 2.8],
		"mid_r": [1.02, 1.10],
		"mid_mod": Color(0.62, 0.66, 0.60),
		## ⑧灯光(2026-10-04): 钉在巨树干上的吊灯(宿主 = 下面这几种树干; 不许悬空)
		"hang_lamp_tex": ["dusk4_hang_lamp_a", "dusk4_hang_lamp_b"],
		"hang_lamps": 5,
		"hang_on": ["dusk2_trunk", "dusk4_trunk_b", "dusk4_trunk_c"],
		"hang_at": [0.30, 0.40],
		"hang_lamp_h": 1.3,   # 0.9 实拍只有 20px 一个暗点(树干在 6.5~9 米, 灯小了就读不出)
		"hang_light_energy": 1.2,
		"hang_light_range": 2.6,
		## ⑨氛围(2026-10-04): 只留灯旁火星(删掉满场上飘气泡/冰蓝辉光)
		"ambient_lamp_embers": true,
		"bg_kind": "into_black",
		"bg_top": Color(0.010, 0.016, 0.012),
		"bg_horizon": Color(0.040, 0.056, 0.040),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "lamp_embers",
		"ambient_col": Color(1.0, 0.55, 0.22, 0.85),     # 2026-10-04 灯旁火星(原「林间萤光」是满场撒的气泡层改色, 已删)
	},
	V2_REEF: {
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"fg_band_layer_gain": [1.0, 1.8, 1.7],   # 2026-10-04 [近,中,远]: 主题色近黑, 远层实拍中位亮度只有 22/255、中层 0 ⇒ 三层读成一坨; 单独提中/远两层
		"ground_tileset_hsv": Vector3(0.467, 0.56, 0.37),   # V 0.44→0.37: 实拍中位 V0.69 而参考 0.57   # 地面目标色 = anchordeep_011 地面中位实测(H168 S0.50)
		"ground_tileset_tint": Color(0.62, 0.78, 0.76),   # 图块原色(生成器的鲜绿/粉红崖边)压进主题色调
		"ground_tileset": "tiles_reef",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"prop_cycle": true,   # 2026-10-04 同类素材轮流摆(随机挑会把一张图挑成大多数, verify_arena_variety)
		"layout_clear_obstacles": true,   # 2026-10-04 布局表有一格物件堆正压在下墙上, 叠成一坨像怪(暗林留下的差距) ⇒ 清掉
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
		"ring_props": ["reef2_kelp_a", "reef2_kelp_b", "reef2_kelp_a", "reef2_rocks_a", "reef2_rocks_b", "reef3_coral_a", "reef2_clam_a", "reef2_clam_b", "reef4_spire_a", "reef4_spire_b"],   # anchordeep_011: 高海草墙夹着石堆/珊瑚塔, 上沿是发光的大珍珠贝   # 2026-10-04 +礁石柱两款(吊灯的宿主)
		"ring_h_of": {"reef2_rocks_a": [1.4, 2.0], "reef2_rocks_b": [1.5, 2.2], "reef3_coral_a": [2.0, 2.8], "reef2_clam_a": [1.6, 2.2], "reef2_clam_b": [1.5, 2.0], "reef4_spire_a": [3.6, 5.0], "reef4_spire_b": [3.6, 5.0]},
		"ring_mod": {"reef4_spire_a": Color(0.80, 0.86, 0.90), "reef4_spire_b": Color(0.80, 0.86, 0.90)},
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
		"rim_light_tex_alt": ["reef4_cairn_a", "reef4_cairn_b"],   # 2026-10-04 16 盏同一张图 ⇒ 轮流换藤壶石堆托扇贝光球(两款)
		"rim_light_h_of": {"reef4_cairn_a": 1.15, "reef4_cairn_b": 1.15},
		"rim_light_real": 6,
		"rim_light_h": 1.3,
		"rim_light_energy": 3.2,
		"rim_light_range": 4.4,
		"light_col": Color(0.42, 1.0, 0.62),
		"light_energy": 1.0,
		"light_fixture": "reef2_lamp_b",   # 2026-10-04 改成真在用的灯具名(原 reef_glow_orb 是一版没接线的旧名)
		## ★2026-10-04 把暗林那一轮的四层复制过来(素材全新画, 风格锚 = 自家 reef3_coral_a):
		## ⑤挡路障碍: 中央大礁 → 缠旧锚链、长藤壶的扁礁石; 两侧矮墙 → 长苔的长条礁脊(两款)。footprint 不动, 只换外观。
		##   ★暗林教训「障碍别像一只怪」: 选的是扁平、横向、没有凸起头部的那几张。
		"obstacles": ["reef4_reefrock", "reef4_ridge_a", "reef4_ridge_b"],
		"obstacle_tex": {"reef_big": "reef4_reefrock", "reef_wall": ["reef4_ridge_a", "reef4_ridge_b"]},
		"obstacle_mod": Color(0.80, 0.84, 0.86),
		## ⑥中景: 平台上沿一圈暗色海扇/柳珊瑚丛(只在上半圈)。
		"mid_props": ["reef4_fan_a", "reef4_fan_b", "reef4_fan_c"],
		"mid_n": 9,
		"mid_h": [1.8, 2.6],
		"mid_r": [1.02, 1.10],
		"mid_mod": Color(0.62, 0.70, 0.70),
		## ⑧灯光: 钉在礁石柱上的绿藻玻璃灯(宿主 = 礁石柱 reef4_spire_*; 不许悬空)。深礁的光是冷绿, 不是火。
		"hang_lamp_tex": ["reef4_hang_lamp_a", "reef4_hang_lamp_b"],
		"hang_lamps": 5,
		"hang_on": ["reef4_spire_a", "reef4_spire_b"],
		"hang_at": [0.34, 0.44],
		"hang_lamp_h": 1.0,   # 礁石柱 3.6~5 米(暗林树干 6.5~9 米配 1.3 米灯)
		"hang_light_energy": 1.6,
		"hang_light_range": 2.6,
		## 「光源像素」色域: 亮青绿(藻灯/珍珠)。暖色判据在这版一个像素都认不出来。
		"flame_rgb": {"r": [-1.0, 0.85], "g": [0.85, 2.0], "b": [0.55, 2.0]},
		## ⑨氛围: 只留灯旁浮游光点(删掉满场上飘气泡)。
		"ambient_lamp_embers": true,
		"bg_kind": "deep_glow",                        # 深水: 暗青底 + 远处光点(对标 Anchordeep)
		"bg_top": Color(0.008, 0.022, 0.030),
		"bg_horizon": Color(0.030, 0.080, 0.090),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "lamp_embers",
		"ambient_col": Color(0.55, 1.0, 0.75, 0.80),   # 2026-10-04 灯旁浮游光点(原满场撒的那层已删)
	},
	V3_SHOAL: {
		"fg_band_layer_gain": [1.0, 1.8, 1.7],   # 前景远/中层提亮(同深礁): 主题色近黑时远层贴着黑底读不出
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"ring_per": 2,
		"ring_h_of": {"shoal2_rubble_b": [1.4, 2.0], "shoal4_column_a": [4.6, 6.4], "shoal4_column_b": [4.6, 6.4]},
		"ground_tileset_hsv": Vector3(0.750, 0.80, 0.55),   # S 0.62→0.80 H→270: 实拍 S0.56 而参考 S0.78 H282   # 地面目标色 = mixed_012 地面中位实测(H264 S0.62)
		"ground_tileset_tint": Color(0.80, 0.70, 0.95),   # 图块原色(生成器的鲜绿/粉红崖边)压进主题色调
		"ground_tileset": "tiles_shoal",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"prop_cycle": true,   # 2026-10-04 同类素材轮流摆(随机挑会把一张图挑成大多数, verify_arena_variety)
		"layout_clear_obstacles": true,   # 2026-10-04 布局表有一格物件堆正压在下墙上, 叠成一坨像怪(暗林留下的差距) ⇒ 清掉
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
		"ring_props": ["shoal2_trunk", "shoal4_column_a", "shoal4_column_b", "shoal2_rubble_b", "shoal4_column_a", "shoal4_column_b"],   # mixed_012/016: 外围暗紫巨树 + 碎石堆   # 2026-10-04 +龟纹断柱两款(废墟的身份 + 吊灯宿主); 巨树降成 1/6, 一圈同一张树看得出是复制的
		"ring_mod": {"shoal2_trunk": Color(0.80, 0.76, 0.86), "shoal4_column_a": Color(0.72, 0.68, 0.78), "shoal4_column_b": Color(0.72, 0.68, 0.78)},
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
		"rim_light_tex_alt": ["shoal4_brazier_a", "shoal4_brazier_b"],   # 2026-10-04 16 盏同一张铁杆火盆 ⇒ 轮流换龟纹石墩火盆(两款)
		"rim_light_h_of": {"shoal4_brazier_a": 1.35, "shoal4_brazier_b": 1.5},
		"rim_light_real": 6,
		"rim_light_h": 2.0,   # 参考火盆比角色高一倍
		"rim_light_energy": 1.7,
		"rim_light_range": 3.0,
		"light_col": Color(1.0, 0.20, 0.26),
		"light_energy": 1.0,
		"light_fixture": "shoal2_brazier_a",   # 2026-10-04 改成真在用的灯具名(原 dusk_candle 是暗林一版没接线的旧名)
		## ★2026-10-04 把暗林那一轮的四层复制过来(素材全新画, 风格锚 = 自家 shoal3_coral_altar), 题材是「沉没的龟纹神殿废墟」:
		## ⑤挡路障碍: 中央大礁 → 龟甲纹石台上倒着的断柱段; 两侧矮墙 → 半塌的石墙(两款)。footprint 不动, 只换外观。
		"obstacles": ["shoal4_drums", "shoal4_wall_a", "shoal4_wall_b"],
		"obstacle_tex": {"reef_big": "shoal4_drums", "reef_wall": ["shoal4_wall_a", "shoal4_wall_b"]},
		"obstacle_mod": Color(0.82, 0.80, 0.84),
		## ⑥中景: 平台上沿一圈被暗紫灌丛吞掉一半的残拱/断墙角(只在上半圈)。
		"mid_props": ["shoal4_ruin_a", "shoal4_ruin_b", "shoal4_ruin_c"],
		"mid_n": 9,
		"mid_h": [2.0, 2.8],
		"mid_r": [1.02, 1.10],
		"mid_mod": Color(0.66, 0.62, 0.70),
		## ⑧灯光: 钉在断柱/巨树上的铜壁灯(宿主 = 断柱 shoal4_column_* 与紫巨树 shoal2_trunk; 不许悬空)。
		"hang_lamp_tex": ["shoal4_hang_lamp_a", "shoal4_hang_lamp_b"],
		"hang_lamps": 5,
		"hang_on": ["shoal4_column_a", "shoal4_column_b", "shoal2_trunk"],
		"hang_at": [0.32, 0.42],
		"hang_lamp_h": 1.15,
		"hang_light_energy": 1.4,
		"hang_light_range": 2.6,
		## ⑨氛围: 只留灯旁火星(删掉满场上飘气泡)。
		"ambient_lamp_embers": true,
		"fog_col": Color(0.090, 0.020, 0.120),
		"bg_kind": "violet_haze",
		"bg_top": Color(0.012, 0.004, 0.024),
		"bg_horizon": Color(0.060, 0.016, 0.090),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "lamp_embers",
		"ambient_col": Color(1.0, 0.45, 0.40, 0.85),   # 2026-10-04 灯旁火星(原满场撒的那层已删)
	},
	V4_STORM: {
		"fg_band_layer_gain": [1.0, 1.8, 1.7],   # 前景远/中层提亮(同深礁): 主题色近黑时远层贴着黑底读不出
		"fg_band_y": -0.46,   # 2026-10-04 单张分层剪影 fg_sea_band: 标定图实测每格 2px、顶行在屏幕 y≈333(-0.368 时 294) ⇒ 下沿 30 格在画面外; 远层要压住场地下沿一点才读得出(全落在黑底上=看不见)   # 旧: 新剪影带草尖高, -0.54 会盖住下沿交战的龟(实拍 s7)
		"fg_band_px": 0.00475,   # 单张整幅(800 格 ≈ 3.8 单位宽), 每格 ≈ 2 屏幕像素
		"fg_band_gain": 3.4,   # 贴图是灰度(近层 ~0.27 / 远层 ~0.9), 抬回剪影色量级: 近层 ≈ fg_band_col, 远层 ≈ 3 倍亮
		"ring_per": 2,
		"ring_mod": {"storm2_trunk": Color(0.80, 0.74, 0.74), "storm4_trunk_b": Color(0.80, 0.74, 0.74), "storm4_trunk_c": Color(0.80, 0.74, 0.74)},
		"ground_tileset_hsv": Vector3(0.158, 0.30, 0.34),   # 2026-10-04「看清每只龟」: S0.41→0.30 V0.42→0.34(同一把尺: 最坏一只 0.15→0.12)   # 地面目标色 = mixed_035 地面中位实测(H57 S0.41)
		"ground_tileset": "tiles_storm",   # 画出来的地面+崖边(PixelLab Wang 图块)
		"prop_cycle": true,   # 2026-10-04 同类素材轮流摆(随机挑会把一张图挑成大多数, verify_arena_variety)
		"layout_clear_obstacles": true,   # 2026-10-04 布局表有一格物件堆正压在下墙上, 叠成一坨像怪(暗林留下的差距) ⇒ 清掉
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
		"field_piles": ["storm2_logs_a", "storm3_net_a", "storm4_flotsam_a", "storm2_logs_b", "storm3_traps_a", "storm4_flotsam_b"],   # 2026-10-04 +风暴冲上岸的漂流物两款(海藻/断桨/绳圈; 新类别)   # 2026-10-04: 木桩 X 架/十字桩换成挂浮子的渔网 / 捕虾笼, 留捆柴堆
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
		"ring_props": ["storm2_trunk", "storm4_trunk_b", "storm4_trunk_c"],   # 2026-10-03 重画: 长刺刻符的暗红巨树干(mixed_035 两侧)   # 2026-10-04 +雷劈焦裂/扭身断顶两款: 一圈同一张树看得出是复制的
		"ring_h_of": {"storm4_trunk_b": [5.4, 7.2], "storm4_trunk_c": [5.4, 7.2]},
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
		"rim_light_tex_alt": ["storm4_beacon_a", "storm4_beacon_b"],   # 2026-10-04 14 盏同一张系泊桩灯 ⇒ 轮流换木杆铁篮信号火(两款)
		"rim_light_h_of": {"storm4_beacon_a": 2.0, "storm4_beacon_b": 2.0},
		"rim_light_real": 8,
		"rim_light_h": 2.0,   # 2026-10-04 1.7→2.0: 系泊桩比旧墓碑烛(1.9)窄一圈, 同高读着细
		"rim_light_energy": 2.6,
		"rim_light_range": 4.0,
		"light_col": Color(1.0, 0.16, 0.12),
		"light_energy": 1.4,
		"light_fixture": "storm3_buoy_lamp",   # 2026-10-04 改成真在用的灯具名(原 dusk_candle 是暗林一版没接线的旧名)
		## ★2026-10-04 把暗林那一轮的四层复制过来(素材全新画, 风格锚 = 自家 storm3_traps_a), 题材是「风暴打过的海边红林」:
		## ⑤挡路障碍: 中央大礁 → 被风暴打烂的石笼码头墩; 两侧矮墙 → 绳子捆的断木桩栅(两款)。footprint 不动, 只换外观。
		"obstacles": ["storm4_crib", "storm4_stakes_a", "storm4_stakes_b"],
		"obstacle_tex": {"reef_big": "storm4_crib", "reef_wall": ["storm4_stakes_a", "storm4_stakes_b"]},
		"obstacle_mod": Color(0.84, 0.80, 0.78),
		## ⑥中景: 平台上沿一圈被风吹向一边的暗红灌木团(只在上半圈)。
		"mid_props": ["storm4_bush_a", "storm4_bush_b", "storm4_bush_c"],
		"mid_n": 9,
		"mid_h": [1.9, 2.7],
		"mid_r": [1.02, 1.10],
		"mid_mod": Color(0.56, 0.50, 0.50),   # 灌木原色是饱和红, 不压会比龟还抢眼(暗林教训)
		## ⑧灯光: 绳绑木架挂的红风灯, 钉在巨树干上(宿主 = 三种树干; 不许悬空)。
		"hang_lamp_tex": ["storm4_hang_lamp_a", "storm4_hang_lamp_b"],
		"hang_lamps": 5,
		"hang_on": ["storm2_trunk", "storm4_trunk_b", "storm4_trunk_c"],
		"hang_at": [0.30, 0.40],
		"hang_lamp_h": 1.3,
		"hang_light_energy": 1.4,
		"hang_light_range": 2.8,
		## ⑨氛围: 只留灯旁火星(删掉满场上飘气泡)。
		"ambient_lamp_embers": true,
		"fog_col": Color(0.300, 0.025, 0.040),
		"bg_kind": "crimson_fog",
		"bg_top": Color(0.090, 0.008, 0.016),
		"bg_horizon": Color(0.300, 0.030, 0.045),
		"sun_col": Color(1.0, 0.96, 0.86), "sun_energy": 1.0,
		"ambient_kind": "lamp_embers",
		"ambient_col": Color(1.0, 0.50, 0.24, 0.85),   # 2026-10-04 灯旁火星(原满场撒的那层已删)
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


## ★★已经【真的画出来】的版(不只是配置齐) —— 判据 `verify_arena_layers_drawn` /
##   `verify_arena_variety` / `verify_island_ambient` 只对这里列出的版逐层验。
## ★用户 2026-10-03 拍板「先把暗林一版做到位再复制」; 2026-10-04 看完暗林对比图「地图感觉差不多了」
##   ⇒ 同一天把同一套做法复制到深礁/紫墟/赤林(素材每版全新画, 不拿暗林的图换色), 四版全进。
##   别为了让清单变长把没做的版塞进来: 塞进来门禁当场红, 那正是它的用处。
const DRAWN: Array = [V1_DUSK, V2_REEF, V3_SHOAL, V4_STORM]

## 物件【类别】表(素材名 → 类)。判据 `verify_arena_variety` 按它数「一屏几类」与「同一张图重复多少」。
## ★参考(咩咩地牢, 人工归类 23 张): 一屏 7~8 类 —— 石板碎石 / 蘑菇 / 蜡烛 / 草簇 / 墓标 / 骨头 / 宝箱门 / 背景墙
##   (`docs/plans/ref/20261002-咩咩启示录地图参考.md` §7.5)。我们的类换成自己的世界观(海/龟/船), 不照搬题材。
## ★场上出现了**不在这张表里**的主题素材 ⇒ 判据红(「没分到类」单独一个桶, 不许静默落进别的类)。
## ★类名用英文键(不是给玩家看的字): grass 草丛 / stones 叠石 / relic 沉船遗物 / lamp 灯具 /
##   trunk 巨树干 / mushroom 藤壶菌丛 / bush 灌木团 / deadwood 倒木树桩。中文字面量会进玩家文案快照(text_golden)。
const PROP_CLASS: Dictionary = {
	"dusk2_grass_a": "grass", "dusk2_grass_b": "grass", "dusk2_grass_c": "grass",
	"dusk2_stones_a": "stones", "dusk2_stones_b": "stones",
	"dusk3_anchor_a": "relic", "dusk3_shell_a": "relic", "dusk3_wreck_a": "relic",
	"dusk3_lantern_b": "lamp", "dusk4_float_a": "lamp", "dusk4_float_b": "lamp",
	"dusk4_hang_lamp_a": "lamp", "dusk4_hang_lamp_b": "lamp",
	"dusk2_trunk": "trunk", "dusk4_trunk_b": "trunk", "dusk4_trunk_c": "trunk",
	"dusk4_mush_a": "mushroom", "dusk4_mush_b": "mushroom",
	"dusk4_bush_a": "bush", "dusk4_bush_b": "bush", "dusk4_bush_c": "bush",
	"dusk4_stump": "deadwood", "dusk4_log_a": "deadwood", "dusk4_log_b": "deadwood",
	## ── 深礁(2026-10-04) ── 类名同上规矩(英文键): coral 珊瑚(珊瑚塔 + 中景海扇/柳珊瑚, 都是珊瑚) /
	##   clam 珍珠贝 / spire 礁石柱(吊灯宿主) / reefrock 挡路礁石 / relic 沉物
	"reef2_kelp_a": "grass", "reef2_kelp_b": "grass",
	"reef2_rocks_a": "stones", "reef2_rocks_b": "stones",
	"reef2_lamp_a": "lamp", "reef2_lamp_b": "lamp", "reef4_cairn_a": "lamp", "reef4_cairn_b": "lamp",
	"reef4_hang_lamp_a": "lamp", "reef4_hang_lamp_b": "lamp",
	"reef3_coral_a": "coral", "reef4_fan_a": "coral", "reef4_fan_b": "coral", "reef4_fan_c": "coral",
	"reef3_shell_coins": "relic",
	"reef2_clam_a": "clam", "reef2_clam_b": "clam",
	"reef4_spire_a": "spire", "reef4_spire_b": "spire",
	"reef4_reefrock": "reefrock", "reef4_ridge_a": "reefrock", "reef4_ridge_b": "reefrock",
	## ── 紫墟(2026-10-04) ── rubble 碎石堆(含倒下的断柱段) / relic 砗磲深海币 / coral 龟纹珊瑚石台 /
	##   pillar 立着的龟纹断柱 / ruinwall 残拱断墙(中景 + 两侧矮墙)
	"shoal2_grass_a": "grass", "shoal2_grass_b": "grass",
	"shoal2_brazier_a": "lamp", "shoal2_brazier_b": "lamp", "shoal4_brazier_a": "lamp", "shoal4_brazier_b": "lamp",
	"shoal4_hang_lamp_a": "lamp", "shoal4_hang_lamp_b": "lamp",
	"shoal2_rubble_a": "rubble", "shoal2_rubble_b": "rubble", "shoal4_drums": "rubble",
	"shoal3_coins": "relic",
	"shoal3_coral_altar": "coral",
	"shoal2_trunk": "trunk",
	"shoal4_column_a": "pillar", "shoal4_column_b": "pillar",
	"shoal4_ruin_a": "ruinwall", "shoal4_ruin_b": "ruinwall", "shoal4_ruin_c": "ruinwall",
	"shoal4_wall_a": "ruinwall", "shoal4_wall_b": "ruinwall",
	## ── 赤林(2026-10-04) ── timber 捆柴 / gear 渔网虾笼 / flotsam 风暴冲上岸的漂流物 /
	##   wreck 风暴残骸(石笼码头墩 + 断木桩栅) / bush 暗红灌木团
	"storm2_grass_a": "grass", "storm2_grass_b": "grass", "storm2_grass_c": "grass",
	"storm3_buoy_lamp": "lamp", "storm4_beacon_a": "lamp", "storm4_beacon_b": "lamp",
	"storm4_hang_lamp_a": "lamp", "storm4_hang_lamp_b": "lamp",
	"storm2_trunk": "trunk", "storm4_trunk_b": "trunk", "storm4_trunk_c": "trunk",
	"storm2_logs_a": "timber", "storm2_logs_b": "timber",
	"storm3_net_a": "gear", "storm3_traps_a": "gear",
	"storm4_flotsam_a": "flotsam", "storm4_flotsam_b": "flotsam",
	"storm4_bush_a": "bush", "storm4_bush_b": "bush", "storm4_bush_c": "bush",
	"storm4_crib": "wreck", "storm4_stakes_a": "wreck", "storm4_stakes_b": "wreck",
}


## ★★场内物件的**设计布局**(四版共用一张构图, 各版换各自素材)。
## 依据: 咩咩每间房的物件是有构图的(四角成簇 / 边上框住 / 中间留战斗区), 不是随机撒点。
##   用户 2026-10-03:「人家是用代码解决的吗」—— 之前 field_tufts/field_piles 按半径随机撒, 一看就是程序生成。
## ★下半部(v>0.3)一律 ≤1.1 米(2026-10-04): 离镜头近的物件会挡住它身后(屏幕上方向)的龟 ——
##   实测右下角 2.2 米的草把角上的龟整个挡住。高的框景物件只放上半部(只挡得到场外)。
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
	[-0.55, 0.64, "p", 1.1],
	[-0.66, 0.57, "p", 1.1],
	[-0.71, 0.45, "t", 1.1],
	[-0.46, 0.75, "t", 1.1],
	[0.59, 0.62, "p", 1.1],
	[0.71, 0.48, "t", 1.1],
	[0.48, 0.73, "t", 1.1],
	[0.66, 0.71, "t", 1.1],
	[-0.12, -0.88, "t", 1.8],
	[0.10, -0.86, "t", 2.0],
	[0.00, -0.83, "p", 1.4],
	[-0.18, 0.87, "t", 1.1],
	[0.16, 0.88, "t", 1.1],
	[-0.78, -0.08, "t", 2.2],
	[-0.76, 0.12, "t", 1.9],
	[0.78, 0.06, "t", 2.1],
	[0.76, -0.12, "t", 1.8],
	[-0.30, 0.38, "p", 0.9],
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

