// cent_aegis_flare.gdshader —— 龟甲阵弧盾两端的翼焰(11-27 附录 D)。网格 = Cent3dVfx.gen_aegis_flare 竖条
//   (UV.x = 0 贴着盾边 → 1 往外翻出去, UV.y = 地面 0 → 顶 1)。火舌灰度图往上卷、能量图扰动; 外形 = 贴盾边最高、往外渐矮的翼。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex_flame : repeat_enable, filter_linear;
uniform sampler2D tex_energy : repeat_enable, filter_linear;
uniform float t = 0.0;
uniform float open = 0.0;
uniform float close = 0.0;
uniform float fade = 1.0;
uniform vec3 col_mid = vec3(1.0, 0.62, 0.14);
uniform vec3 col_hot = vec3(1.0, 0.95, 0.78);

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float wob = texture(tex_energy, vec2(x * 0.7 + t * 0.2, y * 0.8 - t * 0.6)).r - 0.5;
	float fl = texture(tex_flame, vec2(x * 0.9 + wob * 0.25, y * 0.85 - t * 1.4)).r;
	float fl2 = texture(tex_flame, vec2(x * 1.3 - wob * 0.2 + 0.4, y * 1.2 - t * 2.1)).r;
	float shape = (1.0 - smoothstep(0.75 - x * 0.45, 1.0 - x * 0.35, y)) * (1.0 - smoothstep(0.55, 1.0, x)) * smoothstep(0.0, 0.08, y);
	float f = clamp((fl * 0.7 + fl2 * 0.6) * shape * 1.6, 0.0, 1.0);
	float g = min(open, 1.0) * (1.0 - close);
	vec3 c = mix(col_mid, col_hot, smoothstep(0.45, 0.95, f));
	ALBEDO = c;
	ALPHA = clamp(f * 1.1, 0.0, 0.9) * g * fade;
}
