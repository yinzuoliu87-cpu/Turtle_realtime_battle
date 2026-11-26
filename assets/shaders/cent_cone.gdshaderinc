// cent_cone.gdshaderinc —— 百夫长普攻冲击罩各层的公共片段(11-27, 研究稿 docs/studies/20261127-普攻冲击罩参考-潘森Q强化飞矛配方.md)
// 网格 = Cent3dVfx.gen_shock 抛物面(尖端在本地原点朝 +X, UV.y = 0 尖端 → 1 开口, UV.x 绕一圈)。
// 同一个网格叠四层(暗层 / 主亮层 / 叠加中层 / 流动填充)+ 一层只画高速流光条纹; 各层由调用方给颜色 / 参数:
//   col      颜色 + 整体透明度
//   rim_mix  0 = 整面均匀, 1 = 只有轮廓边(越侧着看越亮)
//   tail     从开口往回多长开始渐隐
//   rings    > 0 时画往后退的波纹(流动填充层)
//   streaks  > 0 时只画一条条往后飞的流光(速度层)
uniform vec4 col = vec4(1.0, 0.7, 0.2, 0.5);
uniform float rim_mix = 0.5;
uniform float rim_pow = 1.6;
uniform float tail = 0.5;
uniform float apex = 0.6;
uniform float rings = 0.0;
uniform float streaks = 0.0;
uniform float prog = 0.0;
uniform float fade = 1.0;

float h11(float x) {
	return fract(sin(x * 78.233) * 43758.5453);
}

void fragment() {
	float k = UV.y;
	float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), rim_pow);
	float body = mix(1.0, rim, rim_mix);
	float tl = 1.0 - smoothstep(1.0 - tail, 1.0, k);
	float ap = 1.0 + apex * exp(-k * 9.0);
	float pat = 1.0;
	if (rings > 0.0) {
		pat = 0.45 + 0.55 * smoothstep(0.55, 1.0, 0.5 + 0.5 * sin((k * rings - prog) * 6.2831853));
	}
	if (streaks > 0.0) {
		float bi = floor(UV.x * streaks);
		float r1 = h11(bi + 3.1);
		float seg = fract(k * 1.3 - prog * (1.2 + r1) + r1);
		pat = step(0.45, h11(bi + 9.7)) * smoothstep(0.6, 0.95, seg) * (1.0 - smoothstep(0.95, 1.0, seg))
			* smoothstep(0.2, 0.8, 1.0 - abs(fract(UV.x * streaks) - 0.5) * 2.0);
	}
	ALBEDO = col.rgb * min(ap, 1.6);
	ALPHA = clamp(col.a * body * tl * ap * pat, 0.0, 1.0) * fade;
}
