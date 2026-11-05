// 岩浆浪潮 shader (用户2026-07-15拍板·照娜美R逐帧观察岩浆化):
// 关键=半透明熔岩玻璃感(透出地面)+内部岩浆亮纹流动(焦散)+低矮鼓包(几何负责)
// UV: u=横向(浪宽) / v=剖面弧位置0(前脚)→~0.33(浪尖)→0.5(顶)→1(背脚)
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;   // 整体强度(消散时降到0=摊平渐隐)

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p){
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p){
	float v = 0.0; float a = 0.5;
	for (int k = 0; k < 4; k++){ v += a * vnoise(p); p *= 2.02; a *= 0.5; }
	return v;
}

// ★2026-11-05 重调(用户看审核片:「熔岩龟特效几乎看不见…它是什么特效？」—— 火山爆发实拍是一团模糊的橙色椭圆):
//   原来整块都是中等 alpha 的橙色(底 0.72,0.2,0.05 → 0.5 alpha), 没有暗部、没有轮廓, 再叠一层软橙雾 ⇒ 读不出边界, 也读不出是岩浆。
//   参考娜美 R 逐帧: 浪是一块【边界清楚】的扁长体, 内部看得见纹理, 一圈亮边勾出轮廓。
//   ⇒ 形状 / 速度 / 半透明(07-15 用户定的)不动, 只拉开明暗: 暗红冷却岩壳做底 + 亮黄熔岩纹 + 浪头那一面最烫 + 轮廓压暗。
void fragment(){
	float x = UV.x;              // 0..1 横向
	float p = UV.y;              // 剖面弧位置 0前→1后
	float tt = TIME;
	// 内部岩浆纹(焦散·细长亮脉往后流=浪向前滚的相对运动)·收窄成硬一点的亮脉
	float vein_n = fbm(vec2(x * 7.0 + tt * 0.3, p * 3.0 + tt * 2.2));
	float veins = smoothstep(0.45, 0.55, vein_n) * (1.0 - smoothstep(0.55, 0.68, vein_n));
	float body_n = fbm(vec2(x * 4.0 - tt * 0.5, p * 2.2 + tt * 1.4));
	float lead = smoothstep(0.30, 0.12, p);                       // 浪头迎面那一侧
	vec3 crust = vec3(0.30, 0.06, 0.03);                          // 冷却岩壳(暗红)
	vec3 molten = vec3(0.98, 0.38, 0.07);                         // 熔岩(橙)
	vec3 col = mix(crust, molten, clamp(body_n * 1.1 - 0.25 + lead * 0.75, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.86, 0.42), veins);                 // 岩浆亮脉(亮黄)
	col = mix(col, vec3(1.0, 0.95, 0.72), lead * smoothstep(0.5, 0.75, body_n) * 0.8);   // 浪头白热斑
	float facing = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.0);
	col = mix(col, vec3(0.10, 0.02, 0.02), rim * 0.6);            // 轮廓压暗 ⇒ 浪的外形清楚
	col *= 0.80 + 0.28 * clamp(NORMAL.y, 0.0, 1.0);               // 轻度面向明暗(立体)
	// 仍半透(透出地面, 07-15 用户定的质感), 但底从 0.52 提到 0.68: 原来太透, 和地面混成一片
	float feet = smoothstep(0.10, 0.02, p) + smoothstep(0.90, 0.99, p);
	float a = (0.68 + veins * 0.22 + lead * 0.12 + rim * 0.18) * (1.0 - feet * 0.35) * intensity;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
