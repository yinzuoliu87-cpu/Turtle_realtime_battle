// laser_scorch.gdshader —— 010 激光长刃【地面熔痕】(11-27 重做; 永恩 W 地面斩痕留 1.8 秒是招牌层 ⇒ 我们是激光烧出来的熔痕)
// 贴地, 开深度测试, 画在龟下面。strip = 0: 扇形(Cent3dVfx.gen_fan, UV.x 沿弧 0→1, UV.y 圆心 0 → 外缘 1);
//   strip = 1: 直线光带(LaserBladeVfx.gen_strip, UV.x 沿长 0→1, UV.y 横向 0→1, 中线 0.5)。
// 两层合在一个着色器里: 焦痕(外缘一道窄弧 / 中线一道窄线, 暗红褐, 淡) + 熔裂纹(从焦痕往里伸一小段, 红热发亮, 0.35 秒内冷下去)。
// (11-27 第一版铺满扇形外半圈 + 满地熔岩脉络, 录像里像一块熔岩地图、比刃还抢眼 ⇒ 收成窄弧)
// prog = 刃 / 波前扫到哪(没扫到的地方还没烧); age = 出生后多少秒; life = 总寿命。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float prog = 0.0;
uniform float age = 0.0;
uniform float life = 1.2;
uniform float strip = 0.0;
uniform float seed = 0.0;
uniform float sweep_sec = 0.0;   // 刃 / 波前从 UV.x = 0 扫到 1 用的秒数: 每一处从「扫到这里」那一刻起各自计时(冷却 / 淡出)
uniform vec3 c_scorch = vec3(0.10, 0.03, 0.03);
uniform vec3 c_ember = vec3(1.0, 0.24, 0.10);
uniform vec3 c_hot = vec3(1.0, 0.78, 0.45);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), w.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), w.x), w.y);
}

void fragment() {
	float u = UV.x;
	float k = UV.y;
	float burned = step(u, prog);
	// 形状: 扇形 = 外圈一圈月牙(刃扫过最狠的地方); 光带 = 中线两侧
	float shape;
	vec2 np;
	float band;
	float reach;
	if (strip > 0.5) {
		float y = abs(k - 0.5) * 2.0;
		band = 1.0 - smoothstep(0.10, 0.30, y + (vnoise(vec2(u * 30.0, 3.0)) - 0.5) * 0.12);   // 中线一道窄焦痕
		reach = 1.0 - smoothstep(0.25, 0.6, y);                                                 // 裂纹最多往两侧伸到这
		np = vec2(u * 26.0, k * 4.0);
	} else {
		band = smoothstep(0.84, 0.90, k + (vnoise(vec2(u * 18.0, 1.0)) - 0.5) * 0.06) * (1.0 - smoothstep(0.965, 0.99, k));   // 刃尖扫过的外缘一道窄弧
		reach = smoothstep(0.66, 0.86, k) * (1.0 - smoothstep(0.97, 1.0, k));                   // 裂纹从窄弧往里伸一小段
		np = vec2(u * 22.0, k * 7.0);
	}
	shape = band;
	// 熔裂纹: 两层噪声的「山脊线」(1 - |2n-1|) 取细
	float n1 = vnoise(np);
	float n2 = vnoise(np * 2.3 + 7.0);
	float ridge = pow(1.0 - abs(n1 * 2.0 - 1.0), 7.0) * 0.8 + pow(1.0 - abs(n2 * 2.0 - 1.0), 9.0) * 0.5;
	float la = max(age - u * sweep_sec, 0.0);                  // 这一处被扫到之后过了多久
	float a = clamp(la / life, 0.0, 1.0);
	float hot = clamp(1.0 - la / 0.35, 0.0, 1.0);            // 0.35 秒内冷下去
	float scorch_a = shape * 0.32 * (1.0 - smoothstep(0.25, 1.0, a));
	float ember = ridge * max(shape, reach * 0.7) * hot;
	vec3 col = mix(c_scorch, mix(c_ember, c_hot, clamp(ember * hot * 1.4 - 0.3, 0.0, 1.0)), clamp(ember * 1.6, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(max(scorch_a, ember * 1.2), 0.0, 1.0) * burned;
}
