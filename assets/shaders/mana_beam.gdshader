// 068 法力射线·束身 shader (2026-08-11) —— 每个数字都是逐帧量出来的, 不是手调
//
// ★实测三连(方案书 §九), 与直觉全反:
//   ① 束身【不流动】: 55/55 帧对沿束亮纹互相关最佳位移 = 0 ⇒ 亮纹定在原地【闪变】,
//      去相关时间 ≈270ms(lag 267ms 相关掉到 0.50) ⇒ 噪声原地演化, 不滚动
//   ② 束宽呼吸 ±6.0%, 主周期 67ms(自相关首峰 4 帧)
//   ③ 束沿是【光滑】的(粗糙度 ±1px = 2%) ⇒ 不做边缘舔焰
//
// 挂在五层同轴壳 + 细丝网格上(顶点色 = 已实拍闭环校准的剖面色, shader 不动色相)。
// ★时间只走 uniform u_t(由 set_progress 喂 t_acc), 不碰内建墙钟 —— 暂停一致 + 门禁确定性
//   (门禁 ⑪ 扫源码焊死这一条)。
// ★亮度调制走 ALPHA, 不动 ALBEDO 色相(「亮度靠 alpha 给, 不洗白」v0.19.90 结论)。
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform float u_t = 0.0;             // 秒(束内累计)
uniform float u_env = 0.0;           // 包络亮度(mana_beam_vfx.env)
uniform float u_mod_amp = 0.105;     // 沿束亮度调制幅度(实测 std/mean ±10.5%)
uniform float u_evolve_sec = 0.27;   // 闪变去相关时间(实测 ≈270ms)
uniform float u_freq = 60.0;         // 沿束斑纹空间频率(实测斑纹 ~33码 / 束长 2000码)
uniform float u_breath = 0.06;       // 束宽呼吸幅度(实测 ±6.0%)
uniform float u_breath_sec = 0.067;  // 呼吸主周期(实测 67ms)

varying float v_x;                   // 归一沿束位置(模型 x∈[0,1])

float h1(float n) {
	return fract(sin(n * 12.9898 + 78.233) * 43758.5453);
}
float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(h1(i), h1(i + 1.0), f);
}

void vertex() {
	v_x = VERTEX.x;
	// 呼吸: 整束半径随时间起伏(值噪声, 不是正弦 —— 实测残差是宽带的, 4/8/14 帧都有峰)
	float br = 1.0 + u_breath * (2.0 * noise1(u_t / u_breath_sec) - 1.0);
	VERTEX.y *= br;
	VERTEX.z *= br;
}

void fragment() {
	// 沿束亮纹: 定在原地, 图案随时间在两个哈希档之间平滑过渡(= 原地闪变, 不滚动)
	float ep = u_t / u_evolve_sec;
	float k = fract(ep);
	k = k * k * (3.0 - 2.0 * k);
	float e0 = noise1(v_x * u_freq + floor(ep) * 171.0);
	float e1 = noise1(v_x * u_freq + (floor(ep) + 1.0) * 171.0);
	float m = 1.0 + u_mod_amp * 2.0 * (mix(e0, e1, k) - 0.5);
	ALBEDO = COLOR.rgb;
	ALPHA = clamp(COLOR.a * u_env * m, 0.0, 1.0);
}
