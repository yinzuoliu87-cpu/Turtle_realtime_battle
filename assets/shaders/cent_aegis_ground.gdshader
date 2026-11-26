// cent_aegis_ground.gdshader —— 龟甲阵地面层(11-27 附录 D): 盾前一片贴地扇形光 + 盾脚下一条亮线 + 往前推的光纹 + 扇形外缘细边。
// 网格 = Cent3dVfx.gen_fan 贴地扇形(UV.x 沿弧 0→1, UV.y 从内径 0 → 外径 1)。shell_k = 盾面在扇形里的径向位置。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex_energy : repeat_enable, filter_linear;
uniform float t = 0.0;
uniform float open = 0.0;
uniform float close = 0.0;
uniform float fade = 1.0;
uniform float shell_k = 0.45;
uniform vec3 col_mid = vec3(1.0, 0.62, 0.14);
uniform vec3 col_hot = vec3(1.0, 0.95, 0.8);

void fragment() {
	float u = UV.x;
	float k = UV.y;
	float cu = abs(u - 0.5) * 2.0;
	float line = exp(-pow((k - shell_k) * 22.0, 2.0));                    // 盾脚下亮线
	float fill = smoothstep(0.0, shell_k, k) * (1.0 - smoothstep(shell_k, 1.0, k)) * 0.35;
	float wave = smoothstep(0.85, 1.0, fract(k * 4.0 - t * 1.6)) * step(shell_k, k) * (1.0 - k);   // 盾前往外推的光纹
	float en = texture(tex_energy, vec2(u * 2.0, k * 1.5 - t * 0.3)).r;
	float edge = (1.0 - smoothstep(0.0, 0.025, 1.0 - k)) * 0.6 + smoothstep(0.93, 1.0, cu) * step(shell_k * 0.9, k) * 0.5;
	float side = 1.0 - smoothstep(0.8, 1.0, cu) * 0.6;
	float g = smoothstep(cu * 0.9, cu * 0.9 + 0.1, open) * (1.0 - close);
	float a = (line * 0.9 + fill * (0.5 + en) + wave * 0.6 + edge) * side;
	ALBEDO = mix(col_mid, col_hot, clamp(line + wave, 0.0, 1.0));
	ALPHA = clamp(a, 0.0, 0.85) * g * fade;
}
