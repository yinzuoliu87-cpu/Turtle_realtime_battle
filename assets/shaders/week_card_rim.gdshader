// week_card_rim.gdshader —— 本周羁绊揭晓: 停留时卡框一圈金光沿边流动(方案书 20261127b 分段表③; 参考研究「外沿一直在动」)
// 盖在卡上的透明矩形; UV 0..1 = 整张卡。只在离边 edge 以内画: 一个亮头沿周长顺时针跑, 后面拖一段渐淡的尾巴, 其余边上留一层很淡的金。
// phase = 每张卡错开; 用内置 TIME, 不用每帧喂参数。
shader_type canvas_item;
render_mode blend_add;

uniform float phase = 0.0;
uniform float speed = 0.32;      // 每秒跑周长的几分之几
uniform float edge = 0.035;      // 光带宽(占短边)
uniform vec2 aspect = vec2(0.75, 1.0);   // 卡宽 : 卡高
uniform float on = 1.0;

float perim(vec2 uv) {           // 周长参数 0..1, 从左上角顺时针
	vec2 a = aspect;
	float L = 2.0 * (a.x + a.y);
	vec2 p = uv * a;
	float dl = p.x, dr = a.x - p.x, dt = p.y, db = a.y - p.y;
	float m = min(min(dl, dr), min(dt, db));
	if (m == dt) return p.x / L;
	if (m == dr) return (a.x + p.y) / L;
	if (m == db) return (a.x + a.y + (a.x - p.x)) / L;
	return (2.0 * a.x + a.y + (a.y - p.y)) / L;
}

void fragment() {
	vec2 a = aspect;
	vec2 p = UV * a;
	float d = min(min(p.x, a.x - p.x), min(p.y, a.y - p.y));
	float band = 1.0 - smoothstep(edge * 0.4, edge, d);
	float s = fract(TIME * speed + phase);
	float k = fract(s - perim(UV));          // 0 = 正在亮头处, 往后(已跑过)变大
	float head = exp(-k * 18.0) + 0.25 * exp(-k * 4.0);
	float a_ = band * (0.12 + head) * on;
	COLOR = vec4(vec3(1.0, 0.80, 0.36) * (0.6 + head), clamp(a_, 0.0, 1.0));
}
