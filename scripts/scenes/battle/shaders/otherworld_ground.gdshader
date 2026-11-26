shader_type spatial;
render_mode unshaded, cull_disabled;
// 136 千面【里世界】地面: 黑曜石地砖平铺 + 按岛形(椭圆)裁出, 边缘碎进虚空(按地砖自身的明暗做参差), 越近边缘越暗。
uniform sampler2D tile_tex : filter_nearest, repeat_enable;
uniform vec2 tiles = vec2(30.0, 14.0);
uniform vec4 edge_glow : source_color = vec4(0.45, 0.2, 0.75, 1.0);

void fragment() {
	vec2 d = (UV - 0.5) * 2.0;
	float r = d.x * d.x + d.y * d.y;
	vec4 c = texture(tile_tex, UV * tiles);
	float lum = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	float cut = 1.0 - 0.10 * lum - 0.04 * step(0.5, fract(UV.x * tiles.x * 0.5 + UV.y * tiles.y * 0.5));
	if (r > cut) {
		discard;
	}
	float dark = smoothstep(cut, cut - 0.35, r);
	vec3 col = c.rgb * mix(0.35, 1.0, dark);
	col += edge_glow.rgb * 0.45 * smoothstep(cut - 0.07, cut, r);   // 边缘一圈暗紫微光(碎口)
	ALBEDO = col;
}
