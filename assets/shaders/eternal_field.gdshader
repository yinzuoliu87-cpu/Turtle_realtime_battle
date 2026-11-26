// eternal_field.gdshader —— 145 永恒之枪灼烧力场(用户 11-26 深夜「相当于携带者周围一个力场一样的东西」)
// layer 0 = 力场罩(Cent3dVfx.gen_dome 低穹顶, UV.x 绕一圈 0→1, UV.y 地面 0 → 顶 1, 带法线)
// layer 1 = 地面(Cent3dVfx.gen_fan 整圆, UV.y 中心 0 → 边 1): 脚下最亮往外渐暗, 边上一道暗焦痕压对比
// 罩面: 大部分透明, 只画菲涅尔轮廓 + 地面一圈火线 + 往上流的热浪丝; 每秒跳伤害 pulse 由内往外鼓一下亮一下
// 颜色只在这里按三段渐变调(贴图只有灰度)。参数 t / grow / pulse / fade 进直播流。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex_energy : repeat_enable, filter_linear;
uniform float layer = 0.0;
uniform float t = 0.0;
uniform float grow = 1.0;     // 出现 0→1 / 收掉 1→0
uniform float pulse = 0.0;    // 跳伤害那一下 1 → 0
uniform float fade = 1.0;
uniform float stack = 1.0;    // 叠了几层(更浓)
uniform vec3 col_dark = vec3(0.16, 0.04, 0.01);
uniform vec3 col_deep = vec3(0.72, 0.18, 0.03);
uniform vec3 col_mid = vec3(1.0, 0.55, 0.12);
uniform vec3 col_hot = vec3(1.0, 0.92, 0.65);

vec3 ramp(float k) {
	return k < 0.5 ? mix(col_deep, col_mid, k * 2.0) : mix(col_mid, col_hot, (k - 0.5) * 2.0);
}

void vertex() {
	if (layer < 0.5) {
		VERTEX *= vec3(grow, grow, grow);
		VERTEX += NORMAL * (0.18 * pulse + 0.03 * sin(t * 5.0 + UV.x * 25.0 + UV.y * 6.0));
	} else {
		VERTEX.xz *= grow;
	}
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float st = clamp(stack, 1.0, 3.0);
	if (layer < 0.5) {
		float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.2);
		// 往上流的热浪丝: 绕圈方向很密(u × 36)、往上方向拉长 ⇒ 一根根竖丝; 只留最亮的那截(11-26 录像: 颗粒大成一片斑, 把人盖住)
		float e1 = texture(tex_energy, vec2(u * 36.0 + t * 0.05, v * 0.6 - t * 0.6)).r;
		float e2 = texture(tex_energy, vec2(u * 23.0 - t * 0.04, v * 0.9 - t * 0.85) + 0.37).r;
		float heat = smoothstep(0.62, 0.8, e1 * e2 * 1.6) * (1.0 - v * 0.8);
		float base = 1.0 - smoothstep(0.0, 0.09, v);                          // 贴地一圈火线
		float top = smoothstep(0.55, 1.0, v);
		float a = rim * 0.6 + heat * 0.28 + base * 0.85 + pulse * (0.15 + rim * 0.55);
		a *= (1.0 - top * 0.6) * (0.75 + 0.25 * st);
		float k = clamp(base * 0.9 + heat * 0.6 + rim * 0.35 + pulse * 0.5, 0.0, 1.0);
		vec3 c = mix(col_dark, ramp(k), clamp(k * 1.6, 0.0, 1.0));             // 亮的底下垫暗(沙地上压得住)
		ALBEDO = c;
		ALPHA = clamp(a, 0.0, 0.85) * fade;
	} else {
		float r = v;
		float core = 1.0 - smoothstep(0.0, 0.35, r);                          // 脚下最亮
		float n = texture(tex_energy, vec2(u * 5.0 + t * 0.03, r * 2.0 - t * 0.35)).r;
		float edge = smoothstep(0.86, 0.97, r) * (1.0 - smoothstep(0.97, 1.0, r)); // 边上一道焦痕
		float rays = smoothstep(0.75, 0.95, n) * (1.0 - r) * 0.5;               // 从中心往外辐射的热纹(细)
		float k = clamp(core * 0.8 + rays + pulse * (1.0 - r) * 0.6, 0.0, 1.0);
		vec3 c = mix(col_dark, ramp(k), clamp(k * 1.4, 0.0, 1.0));
		float a = core * 0.45 + rays * 0.35 + edge * 0.5 + pulse * 0.2 * (1.0 - r);
		a *= (0.8 + 0.2 * st);
		ALBEDO = edge > 0.5 ? mix(c, col_dark, 0.6) : c;
		ALPHA = clamp(a, 0.0, 0.8) * fade;
	}
}
