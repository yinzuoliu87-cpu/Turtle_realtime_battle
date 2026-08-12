shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled;

// shield_orb.gdshader — 074 鲸骨护盾【流动能量球】
//
// 用户 2026-08-12:「这个护盾思路我希望你去参考 lol 卡尔马的 e 技能, 护盾应该是个球, 是流动的」
// 参考帧取自卡尔马原画/演出(yt_dlp 抽帧, scratchpad/karma/f1/g_0319.jpg), 逐像素量出的三档色:
//   芯 #c0feec / 能量带 #6de2c1 / 外缘 #4d9d81   ← u_core / u_band / u_rim 的默认值即这三个
//
// 「流动」是三层叠出来的, 不是一张贴图在转:
//   ① 菲涅耳边沿  —— 球的边亮、正对镜头处透 ⇒ 看着是【气泡/球壳】而不是实心球
//   ② 双向螺旋带  —— 两组沿球面经向缠绕的能量带, 一组顺、一组逆, 速度不同 ⇒
//                    交叠处不断错位重组, 是"流"而不是"整体旋转"(整体旋转一眼就看出是刚体)
//   ③ 细纹流丝    —— 高频细纹按不同相速漂移, 给表面"水在动"的碎光
// ★时间走 u_t(由 CPU 每帧喂), 不用 TIME —— 与 mana_beam 同一条纪律: 无头/暂停下可复现。

uniform float u_t = 0.0;
uniform float u_gain = 1.0;        // 整体亮度(叠盾脉冲时短暂拉高)
uniform float u_spin = 1.0;        // 流速倍率
uniform vec3 u_core : source_color = vec3(0.753, 0.996, 0.925);
uniform vec3 u_band : source_color = vec3(0.427, 0.886, 0.757);
uniform vec3 u_rim  : source_color = vec3(0.302, 0.616, 0.506);

varying vec3 v_local;
varying vec3 v_nrm;

void vertex() {
	v_local = normalize(VERTEX);
	v_nrm = NORMAL;
}

// 球面经纬(避免极点扎堆: 纬度用 asin 而不是 acos 的线性映射)
vec2 sph_uv(vec3 p) {
	float lon = atan(p.z, p.x);              // −π..π
	float lat = asin(clamp(p.y, -1.0, 1.0)); // −π/2..π/2
	return vec2(lon, lat);
}

void fragment() {
	vec3 p = normalize(v_local);
	vec2 uv = sph_uv(p);
	float t = u_t * u_spin;

	// ① 菲涅耳: 视线与法线夹角越大(球的边)越亮
	vec3 n = normalize((MODEL_MATRIX * vec4(v_nrm, 0.0)).xyz);
	vec3 vdir = normalize(-(INV_VIEW_MATRIX[3].xyz - (MODEL_MATRIX * vec4(v_local, 1.0)).xyz));
	float fres = pow(1.0 - abs(dot(n, vdir)), 2.2);

	// ② 双向螺旋带: 经度 + 纬度×缠绕系数 ± 时间
	//    带宽用 smoothstep 收出边界 ⇒ 是"带"不是正弦渐变的一坨
	float s1 = sin(uv.x * 3.0 + uv.y * 5.5 + t * 1.30);
	float s2 = sin(uv.x * 4.0 - uv.y * 4.0 - t * 0.85);
	float band1 = smoothstep(0.62, 0.98, s1);
	float band2 = smoothstep(0.68, 0.99, s2);

	// ③ 细纹流丝: 高频、低幅、另一个相速
	float fine = 0.5 + 0.5 * sin(uv.x * 15.0 + uv.y * 9.0 + t * 2.4);
	fine = pow(fine, 6.0);

	// 极点收敛: 球顶/球底把带压弱, 免得所有带在极点挤成一个亮点
	float polar = 1.0 - pow(abs(p.y), 3.0);

	float energy = (band1 * 0.85 + band2 * 0.65) * polar + fine * 0.30 * polar;
	vec3 col = mix(u_rim, u_band, clamp(energy, 0.0, 1.0));
	col = mix(col, u_core, clamp(energy - 0.75, 0.0, 1.0) * 1.6);

	// 边沿始终有一圈壳(哪怕那里没有带经过) ⇒ 球的轮廓永远读得出来
	// ★透明度收一档(2026-08-12 实拍复核): 第一版 a≈0.55+0.60 把龟整只盖住 ——
	//   参考里卡尔马的盾是【看得见人】的薄壳, 能量带只是掠过表面的流光。
	float a = clamp(fres * 0.34 + energy * 0.40, 0.0, 1.0) * u_gain;
	ALBEDO = col * (0.35 + 0.60 * energy + 0.30 * fres);
	ALPHA = a;
}
