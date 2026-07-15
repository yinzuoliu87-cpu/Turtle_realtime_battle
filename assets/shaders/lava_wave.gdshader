// 岩浆浪潮 shader (用户2026-07-15拍板·照娜美R逐帧观察岩浆化):
// 关键=半透明熔岩玻璃感(透出地面)+内部岩浆亮纹流动(焦散)+低矮鼓包(几何负责)
// UV: u=横向(浪宽) / v=剖面弧位置0(前脚)→~0.33(浪尖)→0.5(顶)→1(背脚)
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;   // 整体强度(消散时降到0=摊平渐隐)

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
	float x = UV.x;              // 0..1 横向
	float p = UV.y;              // 剖面弧位置 0前→1后
	float tt = TIME;
	// 内部岩浆纹(焦散·细长亮脉往后流=浪向前滚的相对运动)
	float vein_n = fbm(vec2(x * 7.0 + tt * 0.3, p * 3.0 + tt * 2.2));
	float veins = smoothstep(0.42, 0.62, vein_n) * (1.0 - smoothstep(0.62, 0.82, vein_n));   // 窄带亮脉
	float body_n = fbm(vec2(x * 4.0 - tt * 0.5, p * 2.2 + tt * 1.4));
	// 颜色: 深熔岩橙红半透底 + 亮黄岩浆脉 + 浪尖前缘微亮
	float lead = smoothstep(0.3, 0.16, p);                        // 前缘微热
	vec3 col = mix(vec3(0.72, 0.2, 0.05), vec3(1.0, 0.5, 0.12), body_n * 0.6 + lead * 0.35);
	col = mix(col, vec3(1.0, 0.9, 0.55), veins * 0.9);            // 岩浆亮脉
	col *= 0.72 + 0.35 * clamp(NORMAL.y, 0.0, 1.0);               // 轻度面向明暗(立体)
	// ★半透明熔岩玻璃(透出地面·参考核心质感): 底~0.5, 亮脉处更实, 前后脚更透
	float feet = smoothstep(0.12, 0.02, p) + smoothstep(0.88, 0.99, p);
	float a = (0.52 + veins * 0.3 + lead * 0.1) * (1.0 - feet * 0.45) * intensity;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
