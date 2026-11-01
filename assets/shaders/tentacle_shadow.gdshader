// 灵物触手 · 贴地接触阴影(2026-10-31): 根部一圈 + 沿中心线投到地面的一条柔和暗斑, 离地越高越淡越散。
// 透明, 只画在地面上(不写深度), 挂在触手节点下、与本体共用同一份固定网格(TentacleMeshVfx.gen_tentacle_tube):
//   种类 2(地洞那几圈) → 根部暗斑; 种类 3(拍痕那条) → 沿中心线的暗斑; 本体 / 外壳收到地下不出片元。
// 每帧只吃本体那两份 uniform(ctrl_pts / ctrl_r), 同一套中心线, 不另算。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

const int NCP = 32;
const float TAU_ = 6.28318530718;

uniform vec3 ctrl_pts[32];
uniform float ctrl_r[32];
uniform float strength = 0.40;
uniform vec3 shadow_col : source_color = vec3(0.020, 0.012, 0.040);

varying flat float v_kind;
varying float v_a;
varying vec2 v_uv;


void spline(float f, out vec3 c, out vec3 tg) {
	float s = clamp(f, 0.0, 1.0) * float(NCP - 1);
	int i = clamp(int(floor(s)), 0, NCP - 2);
	float t = s - float(i);
	vec3 p1 = ctrl_pts[i];
	vec3 p2 = ctrl_pts[i + 1];
	vec3 p0 = ctrl_pts[max(i - 1, 0)];
	vec3 p3 = ctrl_pts[min(i + 2, NCP - 1)];
	if (i == 0) {
		p0 = 2.0 * p1 - p2;
	}
	if (i == NCP - 2) {
		p3 = 2.0 * p2 - p1;
	}
	vec3 a = 2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3;
	vec3 b = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
	c = 0.5 * (2.0 * p1 + (p2 - p0) * t + a * t * t + b * t * t * t);
	tg = 0.5 * ((p2 - p0) + 2.0 * a * t + 3.0 * b * t * t);
}


float rad_at(float f) {
	float s = clamp(f, 0.0, 1.0) * float(NCP - 1);
	int i = clamp(int(floor(s)), 0, NCP - 2);
	return mix(ctrl_r[i], ctrl_r[i + 1], s - float(i));
}


void vertex() {
	v_kind = UV2.x;
	v_uv = UV;
	v_a = 0.0;
	int kind = int(UV2.x + 0.5);
	vec3 p = vec3(0.0, -50.0, 0.0);
	if (kind == 3) {
		float a = UV.x;
		vec3 c;
		vec3 tg;
		spline(a, c, tg);
		vec3 th = vec3(tg.x, 0.0, tg.z);
		vec3 side = length(th) > 0.0001 ? normalize(vec3(-th.z, 0.0, th.x)) : vec3(0.0, 0.0, 1.0);
		float h = max(c.y, 0.0);
		float w = rad_at(a) * 1.45 + h * 0.20;
		v_a = strength * (1.0 - smoothstep(0.0, 2.4, h));
		p = vec3(c.x, 0.03, c.z) + side * (UV.y * w);
	} else if (kind == 2) {
		float rr = UV.x * (ctrl_r[2] * 2.4 + 0.30);
		float th = UV.y * TAU_;
		p = ctrl_pts[0] + vec3(cos(th), 0.0, sin(th)) * rr + vec3(0.0, 0.02, 0.0);
		v_a = strength * 1.1 * (1.0 - UV.x * UV.x);
	}
	VERTEX = p;
}


void fragment() {
	float a = v_a;
	if (int(v_kind + 0.5) == 3) {
		a *= 1.0 - v_uv.y * v_uv.y;
	}
	ALBEDO = shadow_col;
	ALPHA = clamp(a, 0.0, 1.0);
}
