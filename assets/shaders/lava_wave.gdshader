// 熔岩浪丘 shader (用户2026-07-15"得设计一下"·照娜美R官方参考岩浆化):
// 一整块圆角浪丘(非矩形墙非粒子): 底暗红基座→中亮橙滚动浪面→顶缘白黄熔沫带(贴圆弧顶翻滚); 不透明主体
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

void vertex(){
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3])
		* mat4(vec4(sx, 0.0, 0.0, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment(){
	float x = UV.x;              // 0..1 横向(浪宽)
	float y = 1.0 - UV.y;        // 0=底(贴地) → 1=顶
	float tt = TIME;
	// 滚动噪声: 前脸向下卷(浪往前滚) + 细碎熔泡
	float roll = fbm(vec2(x * 5.5 + tt * 0.4, y * 2.4 + tt * 2.6));
	float bub  = fbm(vec2(x * 13.0 - tt * 1.1, y * 4.5 + tt * 3.6));
	float nn = roll * 0.6 + bub * 0.4;
	// ★圆角浪丘轮廓(照娜美R·非矩形): 顶高随x呈圆拱, 两端低中间高, 噪声翻滚
	float cx = x * 2.0 - 1.0;                                     // -1..1
	float dome = sqrt(max(0.0, 1.0 - cx * cx * 0.85));            // 圆拱高度曲线
	float top = dome * (0.72 + (nn - 0.5) * 0.3);
	float body = smoothstep(top + 0.05, top - 0.22, y);
	float base = smoothstep(0.0, 0.05, y);
	float m = body * base;
	// 层次: 底部暗红基座带 → 中亮橙滚动纹 → 顶缘白黄熔沫薄边
	float crest = smoothstep(top - 0.13, top - 0.02, y);          // 顶缘熔沫(薄边·非半个丘)
	float basezone = smoothstep(0.42, 0.06, y);                   // 底部基座带(加高)
	vec3 col = mix(vec3(1.0, 0.52, 0.13), vec3(0.4, 0.055, 0.02), basezone);          // 中橙→底暗红
	col *= 0.52 + nn * 0.95;                                      // 浪身滚动明暗(先上纹理)
	col = mix(col, vec3(1.0, 0.95, 0.75), crest * clamp(0.5 + 0.8 * (nn - 0.3), 0.0, 1.0));   // 白黄熔沫薄边(翻滚断续·后叠不被调暗)
	float a = smoothstep(0.1, 0.26, m * (0.8 + nn * 0.35)) * intensity;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
