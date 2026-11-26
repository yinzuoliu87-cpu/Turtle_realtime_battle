// cent_aegis.gdshader —— 百夫长【龟甲阵】盾面(外层 / 内层共用, layer 区分)。11-27 附录 D 按特效师流程分层重做:
//   「真正厉害的三 D 美术师肯定不会说只做一层这个盾吧」「一层一层去实现」
// 网格 = Cent3dVfx.gen_aegis 竖立弧面(UV.x 沿弧 0→1, UV.y 地面 0 → 顶 1, 带法线), 节点绕 Y 转到举盾方向。
// 本层画: 两张能量灰度图交叉滚动(活的能量丝) × 高度渐变(顶亮底淡) + 菲涅尔轮廓 + 两侧边 + 顶边跳动电弧
//   + 盾心徽记(外层) + 受击涟漪(最多 4 圈) + 侵蚀式张开(盾心往外烧出来) / 放盾(从上往下烧掉), 烧的前沿发白。
// 颜色全在这里按三段渐变调(贴图只有灰度)。
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D tex_energy : repeat_enable, filter_linear;
uniform sampler2D tex_erode : repeat_enable, filter_linear;
uniform sampler2D tex_sigil : repeat_disable, filter_linear;
uniform float layer = 0.0;          // 0 外层 / 1 内层
uniform float open = 0.0;           // 张开 0→1
uniform float close = 0.0;          // 放盾 0→1
uniform float t = 0.0;
uniform float flash = 0.0;          // 出刺那一下
uniform float fade = 1.0;
uniform vec2 size_m = vec2(3.2, 3.0);
uniform float sigil_m = 1.15;       // 徽记边长(米)
uniform vec4 rip0 = vec4(0.5, 0.5, 9.0, 0.0);   // 涟漪: x, y = 盾面 UV, z = 年龄(秒), w = 强度
uniform vec4 rip1 = vec4(0.5, 0.5, 9.0, 0.0);
uniform vec4 rip2 = vec4(0.5, 0.5, 9.0, 0.0);
uniform vec4 rip3 = vec4(0.5, 0.5, 9.0, 0.0);
uniform vec3 col_deep = vec3(0.78, 0.3, 0.03);
uniform vec3 col_mid = vec3(1.0, 0.66, 0.16);
uniform vec3 col_hot = vec3(1.0, 0.96, 0.82);

float ripple(vec4 r, vec2 pm) {
	if (r.w <= 0.0 || r.z > 0.45) {
		return 0.0;
	}
	float d = length(pm - r.xy * size_m);
	float rad = r.z * 3.2;
	return exp(-pow((d - rad) * 7.0, 2.0)) * (1.0 - r.z / 0.45) * r.w;
}

void vertex() {
	// 盾面轻微鼓动(能量在流, 不是一块死板)
	VERTEX += NORMAL * 0.025 * sin(t * 6.0 + UV.x * 9.0 + UV.y * 5.0) * (1.0 - layer * 0.5);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec2 pm = vec2(u, v) * size_m;
	float dir = layer > 0.5 ? -1.0 : 1.0;
	float e1 = texture(tex_energy, pm * 0.32 + vec2(t * 0.06 * dir, -t * 0.22)).r;
	float e2 = texture(tex_energy, pm * 0.55 + vec2(-t * 0.13 * dir, -t * 0.37) + 0.37).r;
	float en = smoothstep(0.28, 0.85, e1 * e2 * 2.2);                  // 只留能量丝: 中间大片透明(11-27 自查: 原来整面奶黄像一张帘子, 把人挡没了)
	float hg = mix(0.25, 1.0, smoothstep(0.0, 1.0, v));           // 顶亮底淡
	float cu = abs(u - 0.5) * 2.0;
	float rim = pow(clamp(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 2.0);
	float sides = smoothstep(0.88, 1.0, cu);
	// 顶边跳动电弧
	float jit = texture(tex_energy, vec2(u * 3.0 + t * 1.7, t * 0.9)).r;
	float arc = 1.0 - smoothstep(0.0, 0.012, abs(v - (0.965 + (jit - 0.5) * 0.05)));
	float ground = 1.0 - smoothstep(0.0, 0.04, v);
	// 盾心徽记(外层)
	vec2 su = vec2((u - 0.5) * size_m.x / sigil_m + 0.5, 1.0 - ((v - 0.48) * size_m.y / sigil_m + 0.5));
	float sg = 0.0;
	if (layer < 0.5 && su.x > 0.0 && su.x < 1.0 && su.y > 0.0 && su.y < 1.0) {
		sg = texture(tex_sigil, su).r * (0.55 + 0.25 * sin(t * 4.0) + flash * 0.8);
	}
	float rp = ripple(rip0, pm) + ripple(rip1, pm) + ripple(rip2, pm) + ripple(rip3, pm);
	// 侵蚀: 张开 = 盾心往外烧出来; 放盾 = 从上往下烧掉
	float er = texture(tex_erode, pm * 0.45).r;
	float m_open = er * 0.45 + cu * 0.45 + v * 0.1;
	float vis = 1.0 - smoothstep(open - 0.03, open, m_open);
	float burn = (1.0 - smoothstep(0.0, 0.07, abs(m_open - open))) * step(open, 0.999);
	float m_close = er * 0.5 + (1.0 - v) * 0.5;
	float vis2 = smoothstep(close - 0.02, close + 0.01, m_close);
	float burn2 = close > 0.0 ? (1.0 - smoothstep(0.0, 0.08, m_close - close)) * vis2 : 0.0;
	vis *= close > 0.0 ? vis2 : 1.0;
	float inner = layer > 0.5 ? 0.55 : 1.0;
	vec3 base = mix(col_deep, col_mid, en);
	float hot = rim * 0.6 + sides * 0.9 + arc * 1.2 + sg + rp * 1.3 + burn * 1.5 + burn2 * 1.5 + flash * 0.35 + ground * 0.6;
	vec3 col = mix(base, col_hot, clamp(hot * 0.75, 0.0, 1.0));
	float a = (0.05 + en * hg * 0.75) * inner + rim * 0.55 + sides * 0.7 + arc + sg * 0.95 + rp + burn + burn2 + flash * 0.2 + ground * 0.4;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.92) * vis * fade * (layer > 0.5 ? 0.6 : 1.0);
}
