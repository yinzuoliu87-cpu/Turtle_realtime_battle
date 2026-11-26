// cent_sheath.gdshader —— 骑兵冲锋时罩住人马全身的能量罩(11-27 用户「像赛亚冲锋一样…要有个罩子…不要很明显的贴图的那种感觉…有罩住的那种感觉」)
// 网格 = Cent3dVfx.gen_sheath 的水滴形外壳(前端钝、尾巴拉长收尖; UV.x 绕一圈 0→1, UV.y 前端 0 → 尾 1), 节点朝冲锋方向。
// 画法: 只有轮廓边亮(越侧着看越亮), 正对镜头的那部分几乎全透明 ⇒ 人马在里面看得清, 外面一层「壳」;
//   壳面上一缕缕气流线往后流(每条速度不同、断断续续); 前端被空气压得最亮; 尾巴渐隐; 整体轻微闪动。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float t = 0.0;
uniform float fade = 1.0;
uniform vec3 col_edge = vec3(1.0, 0.86, 0.45);
uniform vec3 col_hot = vec3(1.0, 0.98, 0.9);
uniform float bands = 28.0;

float h11(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

void fragment() {
	float k = UV.y;
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	rim = pow(clamp(rim, 0.0, 1.0), 2.8);
	// 气流线: 绕壳分 bands 条, 每条一个速度 / 相位, 往尾巴方向流
	float bi = floor(UV.x * bands);
	float r1 = h11(bi + 1.0);
	float r2 = h11(bi + 7.3);
	float lane = 1.0 - abs(fract(UV.x * bands) - 0.5) * 2.0;           // 条中间亮
	float seg = fract(k * (1.5 + r1 * 1.5) - t * (2.2 + r2 * 2.0) + r1);
	float streak = smoothstep(0.55, 0.95, seg) * (1.0 - smoothstep(0.95, 1.0, seg)) * smoothstep(0.3, 0.9, lane) * step(0.35, r2);
	float nose = exp(-k * 7.0);
	float tl = 1.0 - smoothstep(0.45, 1.0, k);
	float flick = 0.9 + 0.1 * sin(t * 37.0 + UV.x * 12.0);
	vec3 c = mix(col_edge, col_hot, clamp(nose * 0.8 + streak * 0.6, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = clamp(rim * 0.8 * flick + streak * (0.45 + 0.5 * rim) + nose * rim * 0.6, 0.0, 0.9) * tl * fade;   // 正面不加底色: 人马在里面看得清
}
