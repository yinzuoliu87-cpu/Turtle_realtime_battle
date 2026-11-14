// tentacle_smear.gdshader —— 灵物触手拍下的速度线 + 刀光(2026-11-13, 方案书 docs/plans/20261113b-灵物触手最后一版优化.md)
//
// 网格整局一份(TentacleSlamFx.shared_mesh, 单位空间: x 沿长 0..1, z 横向以半宽为单位), 位置 / 朝向 / 长宽由节点变换给,
// 每步只改 `age` 一个 uniform(逐帧直播只录它) —— 不每步重建网格(那是 10-31「回放掉帧」那一族)。
// age = 贴地后秒数(负 = 还没贴地)。UV2.x: 0 刀光 · 1 速度线 · 2 贴地裂纹(拍下沿路径裂开: 亮洋红 → 冷成暗紫 → 淡掉)。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_test_disabled, shadows_disabled;

uniform float age = -1.0;
uniform float hold = 0.06;          // 刀光满亮多久
uniform float fade = 0.20;          // 再多久褪掉
uniform float lead = 0.034;         // 速度线提前出现多久(贴地前)
uniform float lines_after = 0.05;   // 速度线贴地后多久褪掉
uniform float aspect = 10.0;        // 节点长 / 半宽(裂纹格子按它拉成等方; 开局按攻击长度定一次)
uniform float crack_life = 2.4;     // 裂纹多久淡没
// 换配色(2026-11-13 自己设计外形): recolor = 1 时把烤进顶点色的三档紫换成这三色(按顶点色的 g / r 认出是哪一档)
uniform float recolor = 0.0;
uniform vec3 rc_core : source_color = vec3(0.96, 0.84, 1.0);
uniform vec3 rc_mid : source_color = vec3(0.62, 0.20, 1.0);
uniform vec3 rc_edge : source_color = vec3(0.40, 0.08, 0.85);

varying float v_line;
varying vec2 v_loc;

float smear_env(float a) {
	return a < 0.0 ? 0.0 : 1.0 - smoothstep(hold, hold + fade, a);
}

float lines_env(float a) {
	if (a < -lead || a > lines_after) {
		return 0.0;
	}
	return a < 0.0 ? 1.0 : 1.0 - a / lines_after;
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}


// Voronoi 裂纹: 最近两个格点距离之差(越小越靠近裂缝)。格点固定 ⇒ 不闪。
float crack_d(vec2 q) {
	vec2 ip = floor(q);
	vec2 fp = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			float d = length(g + hash2(ip + g) - fp);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}


// 同上, 另回一个按「这条裂缝两侧的格子」取的随机数(用来随机去掉一半裂缝, 不然是一张均匀的网)
vec2 crack_e(vec2 q) {
	vec2 ip = floor(q);
	vec2 fp = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 c1 = vec2(0.0);
	vec2 c2 = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			float d = length(g + hash2(ip + g) - fp);
			if (d < d1) {
				d2 = d1;
				c2 = c1;
				d1 = d;
				c1 = ip + g;
			} else if (d < d2) {
				d2 = d;
				c2 = ip + g;
			}
		}
	}
	return vec2(d2 - d1, fract(sin(dot(c1 + c2, vec2(12.9898, 78.233))) * 43758.5453));
}


void vertex() {
	v_line = UV2.x;
	v_loc = VERTEX.xz;
	if (v_line < 0.5) {
		// 刀光褪的时候横向收窄一些(读成「收进本体」)
		VERTEX.z *= 1.0 - 0.45 * (1.0 - smear_env(age));
	}
}

void fragment() {
	if (v_line > 1.5) {
		// 贴地裂纹: 从中线往两侧 0.08 秒裂开; 刚裂开亮洋红, 0.6 秒内冷成暗紫, crack_life 内淡没
		vec2 q = vec2(v_loc.x * aspect, v_loc.y) * 1.05 + vec2(5.3, 1.9);
		vec2 ce = crack_e(q);
		float cd = ce.x;
		float keep = step(0.48, ce.y);
		float seam = (1.0 - smoothstep(0.016, 0.055, cd)) * keep;
		float core = (1.0 - smoothstep(0.0, 0.018, cd)) * keep;
		float spread = smoothstep(0.0, 0.08, age);
		float mask = (1.0 - smoothstep(0.20 + 1.10 * spread, 0.35 + 1.20 * spread, abs(v_loc.y)))
			* smoothstep(0.0, 0.04, v_loc.x) * (1.0 - smoothstep(0.90, 1.0, v_loc.x));
		mask *= pow(clamp(1.0 - abs(v_loc.y) / 1.5, 0.0, 1.0), 1.4);
		float heat = 1.0 - smoothstep(0.03, 0.25, age);
		float cfade = age < 0.0 ? 0.0 : 1.0 - smoothstep(crack_life * 0.6, crack_life, age);
		ALBEDO = recolor > 0.5 ? mix(rc_mid * 0.8, rc_core, heat) : mix(vec3(0.52, 0.14, 0.86), vec3(1.0, 0.58, 1.0), heat);
		ALPHA = clamp((seam * 0.80 + core * 0.60 * heat) * mask * cfade, 0.0, 1.0);
	} else {
		float a = v_line > 0.5 ? lines_env(age) : smear_env(age);
		ALBEDO = COLOR.rgb;
		if (recolor > 0.5) {
			ALBEDO = mix(mix(rc_edge, rc_mid, smoothstep(0.40, 0.62, COLOR.r)), rc_core, smoothstep(0.20, 0.84, COLOR.g));
		}
		ALPHA = clamp(COLOR.a * a, 0.0, 1.0);
	}
}
