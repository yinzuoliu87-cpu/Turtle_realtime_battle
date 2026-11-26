// cent_shock.gdshader —— 百夫长的「冲击罩」(11-27 用户「武器头部有一层冲击罩一样的冲击波…冲出去」)
// 网格 = Cent3dVfx.gen_shock 的旋转抛物面(尖端在本地原点、朝 +X; UV.y = 0 尖端 → 1 开口), 像高速物体前端的激波罩。
// 画面: 轮廓边最亮(越侧着看越亮, 读得出是一层罩子) + 一圈圈往后退的波纹 + 尖端白芯; 开口那头渐隐。
// 普攻 = 白金薄罩裹着矛头往前冲; 骑兵 = 压低压宽、土金色的船头浪(同一个着色器, 颜色 / 波纹数 / 形状由调用方给)。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float prog = 0.0;     // 波纹相位(调用方每帧推)
uniform float fade = 1.0;
uniform vec3 col_a = vec3(1.0, 0.97, 0.86);
uniform vec3 col_b = vec3(1.0, 0.72, 0.26);
uniform float rings = 4.0;
uniform float rim_pow = 1.5;
uniform float tail = 0.35;    // 从开口往回多长开始渐隐(占全长比例)

void fragment() {
	float k = UV.y;
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	rim = pow(clamp(rim, 0.0, 1.0), rim_pow);
	float r = 0.5 + 0.5 * sin((k * rings - prog) * 6.2831853);
	r = smoothstep(0.6, 1.0, r);
	float tl = 1.0 - smoothstep(1.0 - tail, 1.0, k);
	float apex = exp(-k * 10.0);
	// 罩身金橙、轮廓边更亮, 尖端和波纹峰发白(沙地上要压得住)
	vec3 c = col_b * (0.75 + rim * 0.5);
	c = mix(c, col_a, clamp(apex * 1.2 + r * 0.55 * rim, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = clamp(rim * 1.1 + r * 0.5 * (0.4 + rim) + apex * 0.9, 0.0, 0.95) * tl * fade;
}
