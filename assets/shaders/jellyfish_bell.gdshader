// 060 磷光水母伞·钟体 shader (2026-08-11) —— 让伞"活着", 不是撑开的雕塑
//
// 三个生物学锚点(不是手调):
//   ① 泳动搏动: 水母喷射循环 =【快缩 30% + 缓张 70%】的非对称节律(~1.15s/拍),
//      收缩时钟体径向收、纵向拉(prolate), 舒张回落 —— 见 vertex 的 c(t)。
//   ② 生物荧光集中在【伞缘】(光器沿缘分布) ⇒ 菲涅尔边亮 + 缘带增亮。
//   ③ 荧光脉络: 8 条放射状生殖腺脉络, 亮斑沿脉络从伞顶向伞缘传播(荧光传播波)。
// 顶点数据约定(mesh 侧焊死): UV.x = 方位角/TAU; UV.y ≥ 0 伞面(0=伞缘, 1=伞顶),
//   UV.y < 0 触须(-w, w∈(0,1] 根→梢)。触须做行波摆动(振幅向梢端增长, 每条相位哈希错开)。
// 时间只走 u_t(CPU 喂), 不碰内建墙钟 —— 同 mana_beam 的纪律。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform float u_t = 0.0;
uniform float u_open = 0.0;        // 张开度(CPU 的阻尼阶跃, 可过冲到 >1)
uniform float u_alpha = 1.0;
uniform vec3 u_col = vec3(0.55, 0.95, 1.0);
uniform float u_pulse_sec = 1.15;  // 泳动周期
uniform float u_pulse_amp = 0.085; // 搏动幅度(径向)
uniform float u_vein_n = 8.0;      // 荧光脉络条数
uniform float u_tent_n = 12.0;     // 触须条数(与 mesh 的 TENTACLE_N 一致)

varying float v_w;                 // 触须: 根→梢 0..1; 伞面: 0

float h1(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}

// 喷射循环收缩度 c∈[0,1]: 快缩(前 30%)慢张(后 70%)
float contract(float t) {
	float p = fract(t / u_pulse_sec);
	if (p < 0.3) {
		return sin(p / 0.3 * 1.5707963);
	}
	return cos((p - 0.3) / 0.7 * 1.5707963);
}

void vertex() {
	float ko = clamp(u_open, 0.0, 1.0);
	float c = contract(u_t) * ko;
	// 搏动: 径向收、纵向拉(近似保体积的 prolate-oblate 循环)
	VERTEX.x *= 1.0 - u_pulse_amp * c;
	VERTEX.z *= 1.0 - u_pulse_amp * c;
	VERTEX.y *= 1.0 + 0.6 * u_pulse_amp * c;
	v_w = max(-UV.y, 0.0);
	if (v_w > 0.0) {
		// 触须行波: 相位沿须体滞后(逐段滞后), 振幅向梢端增长, 每条哈希错相
		float tid = floor(UV.x * u_tent_n + 0.5);
		float ph = u_t * 2.4 - v_w * 3.0 + h1(tid) * 6.2832;
		VERTEX.x += sin(ph) * 0.13 * v_w;
		VERTEX.z += cos(ph * 0.83 + h1(tid + 7.0) * 6.2832) * 0.10 * v_w;
	}
}

void fragment() {
	float ko = clamp(u_open, 0.0, 1.0);
	float a;
	if (v_w > 0.0) {
		// 触须: 半透明 + 微弱明暗呼吸
		a = COLOR.a * (0.55 + 0.25 * sin(u_t * 3.0 + v_w * 5.0));
	} else {
		// 伞面: 菲涅尔边亮(果冻质感 —— 边缘比中心亮)
		float fr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
		// 荧光脉络: 亮斑从伞顶(UV.y=1)沿脉络传向伞缘(0), 每条相位错开
		float ang = UV.x * u_vein_n;
		float vd = abs(fract(ang) - 0.5) * 2.0;
		float vein = smoothstep(0.22, 0.0, vd);
		float tp = 1.0 - fract(u_t * 0.45 + h1(floor(ang)) * 1.0);
		float glow = exp(-14.0 * (UV.y - tp) * (UV.y - tp));
		// 伞缘带(光器): UV.y→0 处增亮
		float rim = smoothstep(0.30, 0.0, UV.y);
		a = COLOR.a * (0.45 + 0.55 * fr) + vein * (0.16 + 0.5 * glow) + rim * 0.22;
	}
	ALBEDO = u_col;
	ALPHA = clamp(a * u_alpha * ko, 0.0, 1.0);
}
