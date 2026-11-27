// fortune_shield.gdshader —— 财神龟【梭哈】/【金盾】的金盾罩(11-27 重做, 方案书 20261126d「特效重做」第 3 行)
// 网格 = Cent3dVfx.gen_dome(低穹顶, UV.x 绕一圈 0→1, UV.y 地面 0 → 顶 1, 带法线), 中心在携带者脚下。
// 罩面: 中间几乎透明(不挡龟), 边缘菲涅尔金边 + 贴地一圈金线 + 一圈圈方孔铜钱纹(12 枚 × 4 圈, 每圈错开半枚, 慢慢转);
//   出现 grow 0→1 由小撑大; 挨打 hit 1→0 整个罩亮一下; fade 收掉。参数 t / grow / fade / hit 进直播流。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float t = 0.0;
uniform float grow = 1.0;
uniform float fade = 1.0;
uniform float hit = 0.0;
uniform vec3 col_dark = vec3(0.42, 0.22, 0.03);
uniform vec3 col_gold = vec3(1.0, 0.74, 0.16);
uniform vec3 col_hot = vec3(1.0, 0.96, 0.74);

void vertex() {
	VERTEX *= grow;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.2);
	float row = floor(v * 4.0);
	vec2 c = vec2(u * 12.0 + t * 0.12 + row * 0.5, v * 4.0);
	vec2 f = fract(c) - 0.5;
	float d = length(f);
	float coin = smoothstep(0.40, 0.37, d) * smoothstep(0.29, 0.32, d);              // 铜钱外圈细线
	float sq = max(abs(f.x), abs(f.y));
	float hole = smoothstep(0.13, 0.11, sq) * smoothstep(0.06, 0.08, sq);             // 方孔一圈细线
	float pat = max(coin, hole) * (1.0 - smoothstep(0.75, 1.0, v));                   // 顶上收掉(纹样在顶上挤成一团)
	float base = 1.0 - smoothstep(0.0, 0.07, v);                                      // 贴地金线
	float a = rim * 0.7 + pat * 0.32 + base * 0.8 + hit * (0.15 + rim * 0.5);
	float k = clamp(rim * 0.8 + base + hit * 0.6, 0.0, 1.0);
	vec3 col = mix(col_gold, col_hot, k);
	col = mix(col_dark, col, clamp(0.35 + rim + pat + base, 0.0, 1.0));              // 纹样暗处垫一点暗金(沙地上压得住)
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.85) * fade;
}
