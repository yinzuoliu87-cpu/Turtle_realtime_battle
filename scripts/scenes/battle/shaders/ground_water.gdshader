shader_type spatial;
render_mode unshaded, cull_disabled;
// 潟湖水面。原来是 sin(UV.x*6.0+TIME) —— UV 是每格 0..1, 波在每格里重新开始,
// 整片水成了同一个印章排成的方阵。现在全部按世界坐标算, 并用距离场做浅→深 + 岸线泡沫。
#include "res://scripts/scenes/battle/shaders/ground_common.gdshaderinc"

uniform vec4 shallow_col : source_color = vec4(0.30, 0.93, 0.90, 1.0);  // 靠岸的浅水(亮)
uniform vec4 deep_col : source_color = vec4(0.135, 0.63, 0.66, 1.0);     // 远岸的深水
// ★深色不能压太狠: 潟湖只有 2~3 格宽, 深色一狠整条带就暗下去,
//   "亮青潟湖框住暗岛"的构图会被反转成"暗水 + 发光轮廓"(第一版实拍就是这样)。
uniform vec4 foam_col : source_color = vec4(0.78, 1.0, 0.98, 1.0);      // 岸线泡沫
uniform sampler2D detail_tex : filter_nearest, source_color;
uniform float detail_amt = 0.45;
uniform float tex_scale = 0.32;
uniform float depth_steps = 4.0;    // placeholder
// 岸线切角用的陆色(取淤泥/石的中间调 —— 岸边多半是这两种)
uniform vec4 shore_land_col : source_color = vec4(0.135, 0.175, 0.29, 1.0);    // 水深量化成几级(级数少=像素画; 多=糊成渐变)

void fragment() {
	vec2 wp = world_xz(INV_VIEW_MATRIX, VERTEX);
	float d = shore_sdf(wp);                       // >0 在水里, 单位=格

	// ── 浅→深: 按离岸距离分级 + 抖动 ────────────────────────────────
	// ★分级而不是平滑: 平滑渐变在这套低色数配色下必出条带; 分 4 级再抖动才是像素画的做法。
	float depth = dither_steps(smoothstep(0.45, 2.9, d), depth_steps, FRAGCOORD.xy);
	vec3 c = mix(shallow_col.rgb, deep_col.rgb, depth);

	// ── 波纹(世界坐标·跨格连续) ────────────────────────────────────
	// 浅水波纹更明显、深水几乎平静 —— 真实水体就是这样, 也让"深浅"读得更清楚。
	float w = sin(wp.x * 2.2 + TIME * 1.2) * 0.5 + 0.5;
	w = mix(w, sin(wp.y * 1.8 - TIME * 0.9) * 0.5 + 0.5, 0.5);
	c = mix(c, shallow_col.rgb, w * 0.30 * (1.0 - depth * 0.75));

	// ── 岸线泡沫 ──────────────────────────────────────────────────
	// 一条沿岸线的亮带, 宽度被一个低频正弦揉过 → 不是死板的等距轮廓线。
	// ★改前水陆是【硬切】: 亮青(98)直接怼上暗淤泥(32), 中间零过渡 —— 全图最不"精美"的地方。
	float wob = sin(wp.x * 3.1 + wp.y * 2.3 + TIME * 0.8) * 0.10;
	float foam = 1.0 - smoothstep(0.0, 0.34 + wob, d);   // 越靠岸越强
	foam *= smoothstep(-0.10, 0.06, d);                  // 别糊到陆地上去
	foam = dither_steps(foam, 3.0, FRAGCOORD.xy);        // 泡沫也分级抖动, 免得成一条羽化的模糊带
	// ★强度 0.22 不是 0.55: 第一版 0.55 + 宽 0.62 让泡沫成了【霓虹描边】,
	//   整座岛像套了个发光环。泡沫是"水拍岸的白边", 该是提示不是主角。
	vec3 c_pre_foam = c;
	c = mix(c, foam_col.rgb, foam * 0.22);

	// ── 细节纹(世界坐标) ──────────────────────────────────────────
	float det = texture(detail_tex, wp * tex_scale).r;
	c *= mix(1.0, det, detail_amt * (1.0 - depth * 0.4));

	// ── 焦散: 浅水最亮, 深水几乎没有(光透不下去) ──────────────────
	if (rich_fx) {
		float ca = dither_steps(caustics(wp * 0.5, TIME * caustic_speed), 3.0, FRAGCOORD.xy);
		c += caustic_col.rgb * ca * caustic_amt * (1.0 - depth * 0.8);
	}

	// ── ★★岸线【切角】(与 ground_land 对称) ────────────────────────
	// 砖的直角边被距离场的零等值线斜切掉; 两个 shader 各画自己那一半, 拼起来就是一条平滑岸线。
	float lmask = dither_steps(1.0 - smoothstep(-0.06, 0.14, d), 2.0, FRAGCOORD.xy);
	c = mix(c, shore_land_col.rgb, lmask);

	// ── 岛缘压暗: 越靠板子外沿越暗(照不到光) ────────────────────
	// 同样过抖动分级, 免得出现一圈羽化的模糊晕。
	float ef = dither_steps(smoothstep(0.02, 0.60, edge_fade(wp)), 4.0, FRAGCOORD.xy);
	// ★系数 0.18 而不是 0.34: 场景开着雾, 而【雾是叠加的】——
	// 乘性压暗会被雾底冲淡, 探针实测 0.34 只做到 13% 的实际压暗(30→26)。
	c *= mix(0.18, 1.0, ef);

	ALBEDO = c;
	// ★自发光按【泡沫之前】的颜色算 —— 否则泡沫会被二次放大成光晕。
	EMISSION = c_pre_foam * 0.26;
}
