// 训龟大师钩锁的锁链(用户 2026-11-20「现在这个锁链完全不行，你需要新设计一种方法」)。
// 参考逐帧: docs/studies/20261120d-训龟大师锁链参考-锤石诺提勒斯逐帧.md —— 学锤石 Q 的做法:
//   ① 甩出去时是一条从手到钩头的**拖影带**(深色芯 + 冰青光边), 靠钩头那头最粗最浓、靠手那头淡;
//   ② 钩中那一下拖影带收成**细直的链子**: 固定大小的链节重复铺(UV 从目标那头量起 ⇒ 拽回来变短时链节不滑);
//   ③ 钩中 / 每拽一下, 一道亮光从目标那头沿链子跑回大师。
// 一张四边形(TrainerChainVfx 每个 sim 步摆: 长边顺着链子、正面朝镜头), 参数每步改 ⇒ 直播镜像照样收(ShaderMaterial 参数全跟踪)。
// UV.x: 0 = 大师(手) → 1 = 钩头 / 被钩的目标。UV.y: 0..1 横跨带子宽。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform sampler2D link_tex : source_color, filter_nearest, repeat_enable;
uniform vec2 link_px = vec2(14.0, 9.0);      // 链节贴图一个循环的像素尺寸
uniform float len_m = 1.0;                   // 链子此刻多长(米)
uniform float link_m = 0.49;                 // 一个循环(正面环 + 侧面节)多长(米)
uniform float chain_frac = 1.0;              // 链节那一条占带子宽的比例(绷紧时 1 = 整条就是链子; 飞行时带子比链子宽)
uniform float ribbon = 0.0;                  // 1 = 飞行(拖影带), 0 = 绷紧
uniform float glint = -1.0;                  // 亮光此刻在哪(0 = 大师 .. 1 = 目标); < 0 没有
uniform vec4 rim_col : source_color = vec4(0.47, 0.86, 1.0, 1.0);
uniform vec4 core_col : source_color = vec4(0.08, 0.13, 0.17, 1.0);

void fragment() {
	float x = UV.x;
	float v = abs(UV.y - 0.5) * 2.0;                             // 0 = 带子中线, 1 = 边
	vec4 outc = vec4(0.0);
	// ── 拖影带(飞行): 越靠钩头越粗越浓, 分四档硬边(像素画规矩, 不做连续渐变)
	if (ribbon > 0.5) {
		float lvl = floor(clamp(x, 0.0, 0.999) * 4.0);           // 0 1 2 3
		float hw = 0.35 + 0.65 * (lvl / 3.0);                    // 半宽: 手那头 35% → 钩头 100%
		if (v <= hw) {
			float a = (0.25 + 0.2 * lvl) * ribbon;               // 浓度 0.25 → 0.85
			outc = (v > hw - 0.22) ? vec4(rim_col.rgb, a * 0.9) : vec4(core_col.rgb, a);
		}
	}
	// ── 链节: 中间 chain_frac 那一条, 从目标那头量起平铺
	float band = chain_frac;
	if (v <= band) {
		float along = (1.0 - x) * len_m;                         // 离目标多远(米)
		vec2 tuv = vec2(along / link_m, 0.5 + (UV.y - 0.5) / band);
		vec4 c = texture(link_tex, vec2(-tuv.x, tuv.y));         // 负号: 链节朝向从大师往目标读
		if (c.a > 0.5) {
			vec3 col = c.rgb;
			if (glint >= 0.0) {
				float d = abs(x - glint) * len_m / link_m;          // 离亮光几个链节
				if (d < 1.2) {
					col = mix(col, vec3(0.85, 1.0, 1.0), 0.85 * (1.0 - d / 1.2));
				}
			}
			float ca = ribbon > 0.5 ? 0.75 : 1.0;                 // 飞行时链节在拖影带里若隐若现
			outc = vec4(mix(outc.rgb, col, ca), max(outc.a, ca));
		}
	}
	if (outc.a < 0.02) {
		discard;
	}
	ALBEDO = outc.rgb;
	ALPHA = outc.a;
}
