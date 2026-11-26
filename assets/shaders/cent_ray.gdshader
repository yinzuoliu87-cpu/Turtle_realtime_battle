// cent_ray.gdshader —— 龟甲阵盾后出刺的穿盾矛光(11-27 附录 D)。网格 = Cent3dVfx.gen_ray_cross 十字交叉两片(UV.y 0 = 盾面 → 1 = 矛光前端)。
// 贴图 ray.png(灰度): 中线最亮、前端星芒; prog 0→1 期间先往前长出去再整体淡掉。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex_ray : repeat_disable, filter_linear;
uniform float prog = 0.0;
uniform vec3 col = vec3(1.0, 0.85, 0.5);

void fragment() {
	float grow = smoothstep(0.0, 0.35, prog);
	float vis = step(UV.y, grow);
	float r = texture(tex_ray, vec2(UV.x, 1.0 - UV.y / max(0.001, grow))).r;
	float f = 1.0 - smoothstep(0.45, 1.0, prog);
	ALBEDO = mix(col, vec3(1.0), r * 0.6) * r * 1.6;
	ALPHA = clamp(r, 0.0, 1.0) * vis * f;
}
