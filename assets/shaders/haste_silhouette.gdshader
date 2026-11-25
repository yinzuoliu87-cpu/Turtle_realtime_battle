// haste_silhouette.gdshader —— 单位身体残影的纯色发光剪影(2026-11-25, 113 弯匕攻速暴涨)
// 只取原帧的透明度当形状, 颜色整块换成 tint, 叠加发光(blend_add)。
// 用户 11-25「金色纹风可以，但是我觉得还不够明显」: 原来残影用 modulate 乘在绿龟身上 = 一团土黄, 读不出「金色」。
// 用在 Sprite3D.material_override 上: Sprite3D 自己生成的四边形 UV 已经是当前帧那一格, 这里直接采样即可。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D tex : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0, 0.78, 0.22, 1.0);
uniform float fade = 1.0;

void fragment() {
	float a = texture(tex, UV).a;
	ALBEDO = tint.rgb;
	ALPHA = step(0.5, a) * fade * tint.a;
}
