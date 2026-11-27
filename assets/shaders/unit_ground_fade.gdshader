// unit_ground_fade.gdshader —— 单位立绘材质: 朝镜头立起 + 接地软渐隐 + 屏幕平面侧转(145 插倒)。
// 11-26 从 RealtimeBattle3DScene._get_ground_fade_shader 的字符串搬出来(主文件 arch_budget; 内容逐字不变, 只加了 tilt)。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform float fade_frac = 0.16;   // 从底起算渐隐区占图高比例
uniform float fade_floor = 0.04;  // 接地处残留 alpha 下限
uniform float vframes = 1.0;      // ★sprite-sheet 的行数 (网格图必须传, 否则底淡算错)
uniform float tilt = 0.0;         // 屏幕平面内绕脚底侧转(弧度, 正 = 头往画面右倒; 145 插倒 11-26)
uniform vec2 grid = vec2(0.0);    // (横帧数, 竖帧数): 采样夹在当前帧格子里不串到邻帧; 0 = 没传(只做面积采样, 不夹)
// ★11-27 用户「身体处见几条横线分开…动画的话会看得更加明显」: 原来 texture(tex, UV) 最近点采样,
//   而龟贴图一行在屏幕上只有 0.43(1280×720)~0.70(手机)个像素 ⇒ 每帧扔掉一半左右的像素行, 一呼吸 / 一走动扔掉的行就换一批 ⇒ 身上闪横纹(全游戏单位都走这里)。
//   改成按屏幕像素覆盖范围采样(商业像素游戏通行做法):
//   缩小(一个屏幕像素盖住 >1 个贴图像素)= 覆盖范围里 4×4 取样按 alpha 加权平均(面积采样, 不丢行);
//   放大 = 锐利双线性(像素内部原色, 只在相邻贴图像素交界那 1 个屏幕像素里过渡, 不会整行画两遍)。
// 切帧由 Sprite3D 原生 hframes/vframes/frame 负责: 它把 mesh 的 UV 设成【该帧在整张图里的子矩形】,
// 所以这里 texture(tex, UV) 直接采到当前帧。UV 是【全图坐标】, 不是帧内 0..1 ——
// ★2026-07-10 订正: 旧注释写"UV 到此已是单帧内 0..1"是错的; 单行横条(vframes=1)时 UV.y 恰好等于帧内 y,
//   所以一直没暴露。改成网格(vframes>1)后必须用 fract(UV.y*vframes) 取行内局部 y, 否则只有最后一行会渐隐。

void vertex() {
	// upright billboard: 取相机右/上/前向量重建朝向, 保留 MODEL 缩放 (squash/stretch 仍生效).
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX[0] *= scl.x;
	MODELVIEW_MATRIX[1] *= scl.y;
	MODELVIEW_MATRIX[2] *= scl.z;
	vec4 rr = MODELVIEW_MATRIX[0]; vec4 uu = MODELVIEW_MATRIX[1];
	MODELVIEW_MATRIX[0] = rr * cos(tilt) - uu * sin(tilt) * scl.x / max(scl.y, 0.0001);
	MODELVIEW_MATRIX[1] = uu * cos(tilt) + rr * sin(tilt) * scl.y / max(scl.x, 0.0001);
}

vec4 tap(vec2 p, vec2 ts, vec2 lo, vec2 hi) {          // p = 贴图像素坐标; 取那一格像素(夹在本帧格子里)
	return texture(tex, (clamp(floor(p), lo, hi) + 0.5) / ts);
}

void fragment() {
	vec2 ts = vec2(textureSize(tex, 0));
	vec2 pix = UV * ts;               // UV = 该帧在整张图里的子矩形坐标 (Sprite3D 原生裁帧)
	vec2 lo = vec2(0.0);
	vec2 hi = ts - 1.0;
	if (grid.x >= 1.0 && grid.y >= 1.0) {
		vec2 cell = ts / grid;
		lo = floor(pix / cell) * cell;
		hi = lo + cell - 1.0;
	}
	vec2 fw = max(fwidth(pix), vec2(0.0001));
	vec4 c;
	if (max(fw.x, fw.y) > 1.0) {
		vec3 rgb = vec3(0.0);
		float a = 0.0;
		for (int i = 0; i < 4; i++) {
			for (int j = 0; j < 4; j++) {
				vec4 s = tap(pix + ((vec2(float(i), float(j)) + 0.5) / 4.0 - 0.5) * fw, ts, lo, hi);
				rgb += s.rgb * s.a;
				a += s.a;
			}
		}
		c = vec4(a > 0.0 ? rgb / a : vec3(0.0), a / 16.0);
	} else {
		vec2 tx = pix - 0.5 * fw;
		vec2 q = floor(tx) + smoothstep(1.0 - fw, vec2(1.0), fract(tx));   // 贴图像素坐标(格心在整数处)
		vec2 b = floor(q);
		vec2 f = q - b;
		vec4 s00 = tap(b + 0.5, ts, lo, hi);
		vec4 s10 = tap(b + vec2(1.5, 0.5), ts, lo, hi);
		vec4 s01 = tap(b + vec2(0.5, 1.5), ts, lo, hi);
		vec4 s11 = tap(b + 1.5, ts, lo, hi);
		vec4 p0 = mix(vec4(s00.rgb * s00.a, s00.a), vec4(s10.rgb * s10.a, s10.a), f.x);
		vec4 p1 = mix(vec4(s01.rgb * s01.a, s01.a), vec4(s11.rgb * s11.a, s11.a), f.x);
		vec4 pm = mix(p0, p1, f.y);
		c = vec4(pm.a > 0.0 ? pm.rgb / pm.a : vec3(0.0), pm.a);
	}
	// 帧内局部 y: 0=帧顶, 1=帧底。网格图(vframes>1)要把全图 UV.y 折算回行内。
	float vf = grid.y >= 1.0 ? grid.y : vframes;   // grid 换表时跟着更新, vframes 只在造材质时设过一次
	float ly = (vf <= 1.0) ? UV.y : fract(UV.y * vf);
	float fade = 1.0;
	if (ly > 1.0 - fade_frac) {
		float k = (1.0 - ly) / max(fade_frac, 0.0001);  // 渐隐线处=1, 最底=0
		fade = mix(fade_floor, 1.0, clamp(k, 0.0, 1.0));
	}
	ALBEDO = c.rgb * COLOR.rgb;     // COLOR = Sprite3D.modulate (受击闪白 >1 提亮)
	ALPHA = c.a * fade * COLOR.a;
}
