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

	ALBEDO = c;
}
