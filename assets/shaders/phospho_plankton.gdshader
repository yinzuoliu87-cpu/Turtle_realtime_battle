// 060 磷光浮游生物场 shader (2026-08-11) —— 把"程序生成的圆"换成有机磷光
//
// 生物学锚点: 磷光浮游生物【不动】, 动的是穿过它们的【发光波】(受激发光传播) ——
//   开伞瞬间一圈光波从伞心扫到 200 码, 沿途点亮散布的浮游光点;
//   庇护圈 = 圈带处光点在张开期【持续微亮 + 各自闪烁】, 不是一根几何线。
// 顶点数据约定(mesh 侧焊死): UV.x = 归一半径(0=中心, 1=200码); UV.y = 光点 id(0..1);
//   COLOR.a = 光点形状(菱形中心亮、尖端 0)。
// u_mode: 0 = 地面场点阵(波 + 圈带 + 微光) / 1 = 上浮微粒(伞下缓慢上浮循环)。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform float u_t = 0.0;
uniform float u_open = 0.0;       // 张开度 0..1(常亮成分只在开伞期存在)
uniform float u_wave_t = -1.0;    // 开伞后经过秒; <0 = 无波
uniform float u_alpha = 1.0;
uniform vec3 u_col = vec3(0.55, 0.95, 1.0);
uniform int u_mode = 0;
uniform float u_wave_v = 1.82;    // 波速(归一半径/秒): 0.55s 扫满 200 码

varying float v_rise;

float h1(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

void vertex() {
	v_rise = 0.0;
	if (u_mode == 1) {
		// 上浮循环: 每颗自己的相位, 升到顶重新从底来(浮游微粒)
		v_rise = fract(h1(UV.y * 97.0) + u_t * 0.12);
		VERTEX.y += v_rise * 1.5;
	}
}

void fragment() {
	// 各自闪烁(频率/相位按 id 哈希 —— 生物荧光不齐步)
	float tw = 0.5 + 0.5 * sin(u_t * (2.5 + 4.0 * h1(UV.y * 31.0)) + UV.y * 40.0);
	float a = 0.0;
	if (u_mode == 0) {
		float wf = 0.0;
		if (u_wave_t >= 0.0) {
			float d = UV.x - u_wave_t * u_wave_v;
			wf = exp(-90.0 * d * d);          // 发光波前扫过 ⇒ 沿途点亮
		}
		float band = smoothstep(0.86, 0.93, UV.x) * (0.42 + 0.50 * tw) * u_open;
		float amb = 0.14 * u_open * tw;
		a = COLOR.a * (wf * 0.9 + band + amb);
	} else {
		a = COLOR.a * u_open * (0.35 + 0.40 * tw) * (1.0 - v_rise);
	}
	ALBEDO = u_col;
	ALPHA = clamp(a * u_alpha, 0.0, 1.0);
}
