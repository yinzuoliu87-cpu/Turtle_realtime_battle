shader_type spatial;
// 陆地地砖(淤泥/石/沙)。只覆写 ALBEDO —— 光照照常吃。
// ★不要照抄水那条的 unshaded: 水是自发光的水体, 陆地要吃方向光才有体积。
#include "res://scripts/scenes/battle/shaders/ground_common.gdshaderinc"

uniform vec4 base_col : source_color = vec4(0.10, 0.14, 0.25, 1.0);   // 锁死调色板(TILE_COLS)
uniform sampler2D detail_tex : filter_nearest;
uniform float tex_scale = 0.32;
// 湿沙 = 【更暗】+ 偏水色。★第一版写的是 (0.55,0.80,0.92)×1.35, 亮度加权算下来
// 0.299*0.74 + 0.587*1.08 + 0.114*1.24 ≈ 1.00 —— 只换了色相没换明度, 等于没做。
// 探针实测: 离水 1 格 43 vs 2~3 格 47/45, 最靠水的反而没更暗。
// 现在 (0.50,0.70,1.05) 亮度加权 ≈ 0.68 → 明确压暗三成, 蓝味也上来了。
uniform vec4 wet_tint : source_color = vec4(0.42, 0.60, 0.98, 1.0);
// 湿带宽度(格)。★1.25 太窄: 距离场是按【格心】烘的, 贴水的那一圈陆地格心 d = -1.0,
// 在 1.25 的衰减下只剩 0.10 —— 湿带基本只覆盖到格子边缘、进不到格心, 探针量出来是平的
// (离水 1/2/3 格亮度 46/44/44, 无梯度)。2.2 让第一圈格心还有约 0.57。
uniform float wet_width = 2.2;
// 岛缘压暗的下限(越小 = 边缘越黑 = 聚光越强)。默认 0.18 是 2026-09 标定的原值。
uniform float edge_dark = 0.18;
uniform float caustic_far = 0.35;
uniform float caustic_scale = 0.5;
uniform float detail_amt = 1.0;
uniform float sed_amt = 0.08;
// 0 = 旧的 sin 光斑焦散(默认, 逐值不变); 1 = 网状细线焦散(深礁主题)
uniform float caustic_web = 0.0;
// 岛缘压暗的过渡宽度(默认 0.60 = 原值); 越大 = 暗得越往里 = 聚光越集中在中心
uniform float edge_soft = 0.60;
// 中心聚光: 离地图中心越远越暗(默认 0 = 不加, 逐值不变)。参考 mixed_033/034 中心一个亮池、四周沉黑。
uniform float spot_amt = 0.0;
uniform vec2 spot_c = vec2(0.0);      // 战场中心(世界 xz·米)
uniform vec2 spot_half = vec2(1.0);   // 战场半宽/半深(米): 归一化后边沿 = 1
// 岸线切角用的水色(与 ground_water 的 shallow_col 对齐)
uniform vec4 shore_water_col : source_color = vec4(0.30, 0.93, 0.90, 1.0);

void fragment() {
	vec2 wp = world_xz(INV_VIEW_MATRIX, VERTEX);
	float det = texture(detail_tex, wp * tex_scale).r;
	// ★★2026-09-18: 原来是 `c = base_col.rgb * det` —— 纹理【单向压暗】而不是在基色上下调制。
	//   实测 det 均值: silt 0.541 / stone 0.643 / sand 0.949, 于是占地面 37% 的主地面 grass
	//   被从明度 36 压到 19(近黑), stone 65→42。四种地块里只有 water(105) 落在中间调区间 60~130,
	//   而它只占 21% —— 精确对上了实测"中间调占比 11%"(参考组最低 24%, 见 tools/battle_scene_audit.py)。
	//   改成【绕基色调制】: det=0.5 时约 ×1.06 不再砍半, det 的明暗对比反而更强(0.80~1.30)。
	//   ★不动 base_col —— 调色板是用户 2026-07-13 拍板的硬锁(场景地图方案.md §4)。
	// ★★2026-10-02 振幅 ±25% → ±12%。**不是推翻上面那条, 是它的理由已经用不上这么大了**:
	//   当初放大到 0.80~1.30 是为了把中间调占比从 11% 救上门槛 24%; 实测现在是 **42.5%**,
	//   余量 18 个点。而这 ±25% 的代价是**地面高频噪声** —— 实测空地噪声里它占 29%。
	//   背景: 用户 2026-09-30「UI 全方面差距」, 量出我们战场噪声是参考的 4 倍、
	//   纯空地是 **16.4 倍**(10.77% vs 0.66%, 见 docs/plans/ref/20260930-Botworld逐帧参考.md §8)。
	//   ⇒ 改后**五条尺子全部不退反进**: 空地噪声 10.77→7.69 / 中间调 41.3→42.5 /
	//     色数 117→121 / 亮坡比 2.49→2.74 / 战场中带 12.5→10.7。
	// ★detail_amt(默认 1.0 = 原值 0.90~1.14): 主题把砖纹压到几乎看不见 —— 真实游玩截帧里
	//   咩咩地面是平滑的涂抹感, 没有方格砖纹; 我们实拍最显眼的就是这层砖纹。
	vec3 c = base_col.rgb * (1.0 + detail_amt * (mix(0.90, 1.14, det) - 1.0));

	// ── 大尺度沉积起伏: 让大片平地有"地形"而不是一块底色 ────────────
	// 同样过抖动分级(6 级) —— 平滑的明暗起伏在像素风里会显得像 3D 渲染的脏。
	if (rich_fx) {
		float sed = dither_steps(sediment(wp) * 0.5 + 0.5, 6.0, FRAGCOORD.xy);
		// ★sed_amt(默认 0.08 = 原值): 主题加大这层**大块柔和**斑驳, 替代被压掉的砖纹。
		c *= mix(1.0 - sed_amt, 1.0 + sed_amt, sed);
	}

	// ── 湿沙带: 靠水的这一圈地压暗并偏向水色 ────────────────────────
	// ★这是"岸线"的陆地那一半。改前水陆是硬切, 陆地一侧没有任何"被水浸过"的痕迹,
	//   于是青色像是被贴在地上而不是漫上来的。
	// d<0 在陆上, |d| 越小越靠水。
	float d = shore_sdf(wp);
	float wet = 1.0 - smoothstep(0.0, wet_width, -d);
	wet *= step(d, 0.0);                                  // 只作用在陆地一侧
	wet = dither_steps(wet, 3.0, FRAGCOORD.xy);           // 分级抖动 → 像素画的湿痕, 不是羽化模糊
	c = mix(c, c * wet_tint.rgb, wet);

	// ── 焦散: 海面折射的光纹爬过海底 ──────────────────────────────
	// ★靠水的地方更强(那儿水浅、光透得下来), 深入内陆逐渐消失。
	// 同样过抖动分级 —— 平滑的光纹在像素风里会显得"太 3D"。
	if (rich_fx) {
		// ★caustic_scale(默认 0.5 = 原值): 深礁主题实拍是一大团一大团光斑, 参考是细密网状亮纹 ⇒ 调细。
		float ca_raw = caustic_web > 0.5 ? caustics_web(wp * caustic_scale, TIME * caustic_speed) : caustics(wp * caustic_scale, TIME * caustic_speed);
		float ca = dither_steps(ca_raw, 3.0, FRAGCOORD.xy);
		float near_water = 1.0 - smoothstep(0.0, 5.0, -d);
		// ★caustic_far: 离水远处的焦散强度(默认 0.35 = 原值)。深礁主题要整片地面都有光纹(对标 Anchordeep),
		//   暗林主题要 0(林地上不该有水波光) —— 由主题经 caustic_amt / caustic_far 控制。
		c += caustic_col.rgb * ca * caustic_amt * (caustic_far + (1.0 - caustic_far) * near_water);
	}

	// ── ★★岸线【切角】: 边界跟着插值后的距离场走, 不跟着砖块的直角走 ─────
	// 砖是方的, 所以水陆交界原本是一级 26 屏幕像素的台阶; 而距离场是双线性插值的,
	// 它的零等值线会把凸角【斜切】掉。这一段就是把"其实已经在水侧"的那部分像素画成水色。
	// 过渡带只有 ±0.35 格并且过抖动 —— 要的是切角, 不是把岸线糊成渐变。
	float wmask = dither_steps(smoothstep(-0.14, 0.06, d), 2.0, FRAGCOORD.xy);
	c = mix(c, shore_water_col.rgb * 0.92, wmask);

	// ── 岛缘压暗: 越靠板子外沿越暗(照不到光) ────────────────────
	// 同样过抖动分级, 免得出现一圈羽化的模糊晕。
	float ef = dither_steps(smoothstep(0.02, edge_soft, edge_fade(wp)), 4.0, FRAGCOORD.xy);
	// ★系数 0.18 而不是 0.34: 场景开着雾, 而【雾是叠加的】——
	// 乘性压暗会被雾底冲淡, 探针实测 0.34 只做到 13% 的实际压暗(30→26)。
	// ★★★2026-10-03 下限做成 uniform, 默认 0.18 = 原值 ⇒ 不设就逐值不变。
	// 由来: 量咩咩的地面起伏(σ/均值)发现, 小块/中块我们已经**不输**(19.5/16.4% vs raw_18 的 18.0/11.9%),
	// 真正差的只有**大块那一档**: raw_01(地牢) 30.5% vs 我们 9.2% —— 那是它的**强聚光**,
	// 中心一个亮池、四周沉进黑, 是咩咩地牢最标志性的一笔。
	// ⇒ 调这个下限就是调"中心到边缘沉多少"。
	c *= mix(edge_dark, 1.0, ef);
	if (spot_amt > 0.0) {
		float sr = length((wp - spot_c) / spot_half);
		c *= 1.0 - spot_amt * dither_steps(smoothstep(0.30, 1.0, sr), 4.0, FRAGCOORD.xy);
	}

	ALBEDO = c;
}
