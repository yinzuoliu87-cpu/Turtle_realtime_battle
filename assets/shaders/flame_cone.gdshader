// 凤凰灼烧·贴地扇形火焰 shader (用户2026-07-15拍板: 照兰博Q官方参考做贴地锥)
// 画在世界空间扇形mesh上(UV: u=角向0..1, v=径向0=嘴..1=远端)
// 参考要点: 放射状条纹火舌(从嘴向外流) + 深棕黑烟团裹边(~40%面积·对比) + 火体不透明只边缘侵蚀 + 嘴部白热
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float intensity = 1.0;   // 整体强度(轻微跳动)

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

void fragment(){
	float ang = UV.x;                 // 角向 0..1 (0.5=锥中线)
	float rad = UV.y;                 // 径向 0=嘴 → 1=远端
	float tt = TIME;
	// 放射状条纹(角向高频·径向拉长·往外滚) = 参考的"笔触"火舌
	float streaks = fbm(vec2(ang * 22.0, rad * 2.6 - tt * 2.6));
	// 大形体噪声(轮廓翻滚)
	float body_n = fbm(vec2(ang * 6.0 + tt * 0.35, rad * 3.2 - tt * 1.5));
	// 轮廓: 角向两侧噪声侵蚀 + 远端噪声化尖灭 + 嘴部起
	float edge = smoothstep(0.02, 0.24 + (body_n - 0.5) * 0.34, ang)
	           * smoothstep(0.98, 0.76 - (body_n - 0.5) * 0.34, ang);
	float tip = 1.0 - smoothstep(0.62, 1.0, rad + (body_n - 0.5) * 0.5);
	float startF = smoothstep(0.0, 0.05, rad);
	float sil = edge * tip * startF;
	float fire = sil * (0.55 + streaks * 0.75);
	// 深色烟团: 越靠边/越远越浓(参考~40%面积是暗烟·给对比和形)
	float smoke_n = fbm(vec2(ang * 9.0 - tt * 0.6, rad * 4.2 - tt * 1.05));
	float smokiness = clamp((rad * 1.5 - 0.18) + abs(ang - 0.5) * 1.9, 0.0, 1.0) * smoothstep(0.24, 0.58, smoke_n);
	// 颜色: 嘴白黄热核(小) → 橙 → 远端暗红, 条纹强对比
	float heat = (1.0 - rad) * (0.42 + streaks * 1.1);
	vec3 col = mix(vec3(0.72, 0.13, 0.03), vec3(1.0, 0.55, 0.15), clamp(heat * 1.25, 0.0, 1.0));
	col = mix(col, vec3(1.0, 0.95, 0.74), clamp((heat - 0.62) * 2.6, 0.0, 1.0));
	float core = smoothstep(0.26, 0.0, rad) * smoothstep(0.16, 0.0, abs(ang - 0.5));   // 嘴部白热收小(参考: 只一小簇)
	col = mix(col, vec3(1.0, 0.98, 0.9), core * 0.85);
	col *= 0.78 + streaks * 0.45;                                                     // 条纹明暗强化(放射笔触感)
	col = mix(col, vec3(0.1, 0.055, 0.045), smokiness * 0.92);                        // 烟团压暗(不透明的暗·非透明)
	// 火体不透明: 轮廓内alpha≈1, 只边缘渐隐(参考: 地面透不出来)
	float a = smoothstep(0.1, 0.3, sil * (0.7 + streaks * 0.45)) * intensity;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
