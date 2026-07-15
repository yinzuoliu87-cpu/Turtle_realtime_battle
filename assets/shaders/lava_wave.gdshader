// 熔岩浪壳 shader (用户2026-07-15"就一个图片在动?四面八方?"): 贴在世界空间3D浪壳mesh上(非billboard平面图)
// mesh剖面=前脚→上升→浪尖前卷(破浪弧)·横轴垂直行进方向→任何推进方向朝向自动正确
// UV: u=横向(浪宽0..1) / v: 1=底 0=浪尖(fragment里翻转); 着色: 底暗红基座→中亮橙滚动→浪尖白黄熔沫
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p){
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++){ v += a * vnoise(p); p *= 2.02; a *= 0.5; }
	return v;
}

void fragment(){
	float x = UV.x;              // 0..1 横向(浪宽)
	float p = UV.y;              // 剖面弧位置: 0=前脚 → ~0.33浪尖 → 0.5顶 → 1=背脚
	float tt = TIME;
	// 滚动噪声: 浪面向前卷(沿剖面滚) + 细碎熔泡
	float roll = fbm(vec2(x * 5.5 + tt * 0.4, p * 2.6 - tt * 2.6));
	float bub  = fbm(vec2(x * 13.0 - tt * 1.1, p * 5.0 - tt * 3.6));
	float nn = roll * 0.6 + bub * 0.4;
	// 实心体着色: 白沫只在浪尖前缘一圈(p≈0.22..0.55) · 前后脚暗红基座 · 其余亮橙滚动
	float foam = smoothstep(0.24, 0.31, p) * (1.0 - smoothstep(0.38, 0.46, p));   // 窄带=只浪尖一圈(顶面p0.5要保持橙)
	float feet = smoothstep(0.14, 0.02, p) + smoothstep(0.86, 0.99, p);
	vec3 col = mix(vec3(1.0, 0.52, 0.13), vec3(0.42, 0.06, 0.02), clamp(feet, 0.0, 1.0) * 0.85);
	col *= 0.55 + nn * 0.9;                                       // 滚动明暗
	col = mix(col, vec3(1.0, 0.95, 0.75), foam * clamp(0.55 + 0.8 * (nn - 0.3), 0.0, 1.0));
	col *= 0.72 + 0.4 * clamp(NORMAL.y, 0.0, 1.0);                // 轻度面向明暗(顶亮侧暗·立体)
	float a = (0.9 + nn * 0.1) * intensity;                       // 近不透明实心
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
