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
// 岸线切角用的水色(与 ground_water 的 shallow_col 对齐)
uniform vec4 shore_water_col : source_color = vec4(0.30, 0.93, 0.90, 1.0);

void fragment() {
	vec2 wp = world_xz(INV_VIEW_MATRIX, VERTEX);
	float det = texture(detail_tex, wp * tex_scale).r;
	vec3 c = base_col.rgb * det;

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
	float ca = caustics(wp * 0.5, TIME * caustic_speed);
	ca = dither_steps(ca, 3.0, FRAGCOORD.xy);
	float near_water = 1.0 - smoothstep(0.0, 5.0, -d);
	c += caustic_col.rgb * ca * caustic_amt * (0.35 + 0.65 * near_water);

	// ── ★★岸线【切角】: 边界跟着插值后的距离场走, 不跟着砖块的直角走 ─────
	// 砖是方的, 所以水陆交界原本是一级 26 屏幕像素的台阶; 而距离场是双线性插值的,
	// 它的零等值线会把凸角【斜切】掉。这一段就是把"其实已经在水侧"的那部分像素画成水色。
	// 过渡带只有 ±0.35 格并且过抖动 —— 要的是切角, 不是把岸线糊成渐变。
	float wmask = dither_steps(smoothstep(-0.14, 0.06, d), 2.0, FRAGCOORD.xy);
	c = mix(c, shore_water_col.rgb * 0.92, wmask);

	// ── 岛缘压暗: 越靠板子外沿越暗(照不到光) ────────────────────
	// 同样过抖动分级, 免得出现一圈羽化的模糊晕。
	float ef = dither_steps(smoothstep(0.02, 0.60, edge_fade(wp)), 4.0, FRAGCOORD.xy);
	// ★系数 0.18 而不是 0.34: 场景开着雾, 而【雾是叠加的】——
	// 乘性压暗会被雾底冲淡, 探针实测 0.34 只做到 13% 的实际压暗(30→26)。
	c *= mix(0.18, 1.0, ef);

	ALBEDO = c;
}
