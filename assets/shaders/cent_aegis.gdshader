// cent_aegis.gdshader —— 百夫长【龟甲阵】3D 弧形能量盾(11-27 用户「这举盾任何方向上都有可能举盾…需要三 D 特效」)
// 网格 = Cent3dVfx.gen_aegis 的竖立弧面(UV.x 沿弧 0→1, UV.y 地面 0 → 顶 1), 节点按举盾方向绕 Y 转 ⇒ 地面上朝哪个方向都对。
// 画面分层: 龟甲六边形格(格线亮、格内淡金、每格亮度不同) + 往上流的光带 + 盾缘亮边 + 中心光团 + 盾后出刺时整片闪一下;
//   张开(open 0→1)从中间往两边、从地面往上长出来, 前沿一道白线; 放盾(brk 0→1)按格随机碎掉, 碎前那一格先亮一下。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float open = 0.0;
uniform float fade = 1.0;
uniform float t = 0.0;
uniform float flash = 0.0;
uniform float brk = 0.0;
uniform vec2 size_m = vec2(3.4, 3.0);   // 弧长 / 高(米): 六边形格按真实尺寸铺, 不被拉扁
uniform float cell_m = 0.34;
uniform vec3 gold = vec3(1.0, 0.70, 0.22);
uniform vec3 hot = vec3(1.0, 0.94, 0.72);

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// 六边形格: xy = 到格心的偏移, zw = 格 id
vec4 hex_cell(vec2 p) {
	vec2 s = vec2(1.0, 1.7320508);
	vec2 hs = s * 0.5;
	vec2 a = mod(p, s) - hs;
	vec2 b = mod(p - hs, s) - hs;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	return vec4(g, p - g);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float cu = abs(u - 0.5) * 2.0;
	// 张开: 中间先出、往两边长; 同时从地面往上长
	float om = (1.0 - smoothstep(open - 0.05, open + 0.01, cu)) * (1.0 - smoothstep(open * 1.1 - 0.04, open * 1.1 + 0.02, v));
	vec4 hc = hex_cell(vec2(u * size_m.x, v * size_m.y) / cell_m);
	vec2 q = abs(hc.xy);
	float hd = max(dot(q, vec2(0.5, 0.8660254)), q.x);   // 格心 0 → 格边 0.5
	float line = smoothstep(0.405, 0.47, hd);            // 格线(靠近 0.5 的一圈)
	float rnd = h21(hc.zw);
	float fill = 0.06 + 0.10 * rnd + 0.08 * (1.0 - hd * 2.0);
	// 往上流的光带(两道错开)
	float b1 = exp(-pow((fract(v * 0.8 - t * 0.55) - 0.5) * 6.0, 2.0));
	float b2 = exp(-pow((fract(v * 0.8 - t * 0.55 + 0.5) - 0.5) * 9.0, 2.0)) * 0.5;
	// 盾缘亮边: 左右两侧 + 顶 + 贴地一线
	float rim = smoothstep(0.86, 1.0, cu) + smoothstep(0.90, 1.0, v) + (1.0 - smoothstep(0.0, 0.05, v)) * 0.7;
	// 中心光团(盾心)
	vec2 d = vec2((u - 0.5) * size_m.x / size_m.y, v - 0.46);
	float core = exp(-dot(d, d) * 14.0);
	// 张开前沿白线
	float oedge = (1.0 - smoothstep(0.0, 0.07, abs(cu - open))) * (1.0 - step(0.999, open));
	// 放盾碎裂: 每格一个阈值, 到了就没; 快到阈值那一下先亮
	float alive = step(brk, rnd * 0.92 + 0.04);
	float pre = (brk > 0.0) ? (1.0 - smoothstep(0.0, 0.12, rnd * 0.92 + 0.04 - brk)) : 0.0;
	vec3 col = gold * (fill + line * 0.95 + (b1 + b2) * 0.40 + core * 0.55)
		+ hot * (rim * 0.85 + oedge * 1.4 + flash * (0.35 + line * 0.9) + pre * 1.2);
	float lum = clamp(fill + line * 0.9 + (b1 + b2) * 0.35 + core * 0.5 + rim * 0.8 + oedge + flash * 0.4 + pre, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = clamp(lum * 0.85, 0.0, 0.9) * om * fade * alive;
}
