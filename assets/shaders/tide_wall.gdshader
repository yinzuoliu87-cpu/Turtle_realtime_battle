// 043 海浪护符【浪墙】—— 第三版(2026-11-14 晚, 照娜美大招配方分层; 方案书 docs/plans/20261114-海浪护符浪墙重做.md)。
// 娜美实拆: 浪体网格 `R_Water.scb` 是**矮水丘**(英雄约半身高), 上面叠几层**滚动贴图**(R_WaterAdd 混合层 + AberraticCaustic 叠加层),
//   前沿一条带水刺的边(R_Water02), 其余靠粒子(泡沫 / 水雾 / 小卷浪 / 水珠, 在 GDScript 里撒)。
// 本着色器只管浪体那张网格:
//   区 0 浪身  UV = (沿墙 0..1, 横截面 0 背面最尾 .. 1 迎面最前); UV2.x = 形状高度(归一)
//      ① 底色: 深 → 中青按高度; ② 水纹层 `streak_tex`(灰度)沿推进方向往后流; ③ 焦散层 `caustic_tex`(灰度)提亮(叠加感);
//      ④ 前沿 `edge_tex`: 亮带 + 往前甩的水刺, 盖在最前那 18%。
//   区 1(旧水沫帘)不再画 —— 第三版改成粒子。区 2 身后贴地水雾保留(薄)。
// 贴图都是手画灰度图(tools/assetgen/paint_tide_fx.py), 颜色全在这里上(同娜美配方: 灰度图 + 引擎里调色)。
// 全部时间读 t_wave(sim 钟累加, 不读 TIME) ⇒ 回放 / 直播逐帧一致。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, blend_mix, shadows_disabled;

uniform float t_wave = 0.0;      // 这道浪自己的钟(秒)
uniform float fade = 1.0;        // 整体可见度(蓄浪 / 退场)
uniform sampler2D streak_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D caustic_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D edge_tex : source_color, filter_linear, repeat_enable;
uniform float tiles_u = 8.0;     // 沿浪墙铺几遍(GDScript 按墙长算好传进来)
uniform vec4 c_deep : source_color = vec4(0.04, 0.30, 0.38, 1.0);
uniform vec4 c_mid : source_color = vec4(0.10, 0.58, 0.60, 1.0);
uniform vec4 c_hi : source_color = vec4(0.62, 0.96, 0.92, 1.0);
uniform vec4 c_foam : source_color = vec4(0.93, 1.0, 1.0, 1.0);
const float T_EDGE = 0.60;       // 横截面上前沿那一带从哪开始(0.82 → 0.60: 太窄时俯视下只剩一条折线, 读成闪电)

varying float v_h;
varying float v_reg;

void vertex() {
	v_h = UV2.x;
	v_reg = UV2.y;
}

void fragment() {
	float u = UV.x;
	float t = UV.y;
	vec3 col = vec3(1.0);
	float a = 0.0;
	if (v_reg < 0.5) {
		// ── 0 浪身 ──
		float s = texture(streak_tex, vec2(u * tiles_u, t * 1.5 + t_wave * 0.9)).r;            // 水纹往后流
		vec4 ca = texture(caustic_tex, vec2(u * tiles_u * 0.7 + t_wave * 0.04, t * 1.1 + t_wave * 0.45));
		vec3 base = mix(c_deep.rgb, c_mid.rgb, smoothstep(0.05, 0.95, v_h));
		col = base * (0.55 + 0.9 * s) + c_hi.rgb * ca.a * 0.28;                                 // 焦散只轻轻提亮(0.6 时读成裂冰)
		a = (0.50 + 0.30 * s + 0.10 * ca.a) * smoothstep(0.0, 0.30, t);                          // 越往后越透
		if (t > T_EDGE) {
			float ev = (1.0 - t) / (1.0 - T_EDGE);                                                 // 最前 = 水刺尖, 往后 = 亮带
			vec4 e = texture(edge_tex, vec2(u * tiles_u * 1.2 + t_wave * 0.12, ev));                 // 水刺放大(×2 → ×1.2)
			col = mix(col, mix(c_hi.rgb, c_foam.rgb, smoothstep(0.85, 1.0, e.r)), e.a);            // 亮带浅青, 水刺尖才白
			a = mix(a * (1.0 - smoothstep(0.92, 1.0, t)), 0.92, e.a);
		}
	} else if (v_reg < 1.5) {
		// ── 1 旧水沫帘: 第三版不画(改成粒子) ──
		a = 0.0;
	} else {
		// ── 2 身后水雾: 贴地薄薄一层, 用水纹图打散, 贴着浪尾最浓 ──
		float s2 = texture(streak_tex, vec2(u * tiles_u * 0.5 + t_wave * 0.05, t * 0.8 + t_wave * 0.3)).r;
		col = mix(c_mid.rgb, c_foam.rgb, 0.55);
		a = smoothstep(0.55, 0.9, s2) * t * t * 0.30;
	}
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * fade;
}
