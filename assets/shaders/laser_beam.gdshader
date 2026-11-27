// laser_beam.gdshader —— 010 激光长刃【直线追斩】光带(11-27 重做; 永恩 Q: 亮刃 0.1 秒 + 三倍长余光 0.3 秒)
// 网格 = LaserBladeVfx.gen_strip(从携带者沿 +X 铺到最远处; UV.x 沿长 0→1, UV.y 横向 0→1), 放在刃的高度、不做深度测试。
// head = 波前走到哪(0→1); 波前后面拖一道光束(芯白热 → 粉 → 红), 按「落后距离」衰减; 波前本身一团更宽更亮的光。
// tail = 收尾: 波到头以后整条光束从尾巴往前散掉(0 → 1)。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform float head = 0.0;
uniform float tail = 0.0;
uniform float len_m = 10.0;          // 光带全长(米): 衰减按米算, 长短不同的光带看着一样
uniform vec3 c_deep = vec3(0.50, 0.02, 0.07);
uniform vec3 c_red = vec3(1.0, 0.14, 0.20);
uniform vec3 c_pink = vec3(1.0, 0.58, 0.62);
uniform vec3 c_hot = vec3(1.0, 0.97, 0.93);

void fragment() {
	float x = UV.x;
	float y = abs(UV.y - 0.5) * 2.0;
	float behind_m = (head - x) * len_m;
	float lit = step(0.0, behind_m);
	float b = max(behind_m, 0.0);
	float edge = 1.0 - smoothstep(0.62, 0.95, y);          // 光晕在网格边缘之前收干净(11-27 第一版到边还有 0.29, 一刀切出方框)
	float core = exp(-pow(y / 0.10, 2.0));
	float body = exp(-pow(y / 0.30, 2.0));
	float glow = exp(-pow(y / 0.50, 2.0)) * edge;
	float beam = (core * 1.6 + body * 0.7 + glow * 0.25) * exp(-b * 0.22) * lit;
	float ahead = (x - head) * len_m;                        // 波前前方也柔和过渡, 不是一条硬竖线
	float front = exp(-pow(max(b, 0.0) / 0.35, 2.0) - pow(max(ahead, 0.0) / 0.18, 2.0)) * (core * 1.2 + body * 1.0 + glow * 0.5);
	float gone = smoothstep(tail - 0.15, tail, x);         // 收尾: 从尾巴往前散
	float I = (beam + front * 1.5) * mix(1.0, gone, step(0.001, tail));
	vec3 col = mix(c_deep, c_red, clamp(I * 1.5, 0.0, 1.0));
	col = mix(col, c_pink, clamp((I - 0.7) * 1.6, 0.0, 1.0));
	col = mix(col, c_hot, clamp((I - 1.35) * 1.3, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(I, 0.0, 1.0);
}
