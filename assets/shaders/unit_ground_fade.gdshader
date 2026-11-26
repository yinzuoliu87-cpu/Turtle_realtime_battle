// unit_ground_fade.gdshader —— 单位立绘材质: 朝镜头立起 + 接地软渐隐 + 屏幕平面侧转(145 插倒)。
// 11-26 从 RealtimeBattle3DScene._get_ground_fade_shader 的字符串搬出来(主文件 arch_budget; 内容逐字不变, 只加了 tilt)。
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, shadows_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform float fade_frac = 0.16;   // 从底起算渐隐区占图高比例
uniform float fade_floor = 0.04;  // 接地处残留 alpha 下限
uniform float vframes = 1.0;      // ★sprite-sheet 的行数 (网格图必须传, 否则底淡算错)
uniform float tilt = 0.0;         // 屏幕平面内绕脚底侧转(弧度, 正 = 头往画面右倒; 145 插倒 11-26)
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

void fragment() {
	vec4 c = texture(tex, UV);       // UV = 该帧在整张图里的子矩形坐标 (Sprite3D 原生裁帧)
	// 帧内局部 y: 0=帧顶, 1=帧底。网格图(vframes>1)要把全图 UV.y 折算回行内。
	float ly = (vframes <= 1.0) ? UV.y : fract(UV.y * vframes);
	float fade = 1.0;
	if (ly > 1.0 - fade_frac) {
		float k = (1.0 - ly) / max(fade_frac, 0.0001);  // 渐隐线处=1, 最底=0
		fade = mix(fade_floor, 1.0, clamp(k, 0.0, 1.0));
	}
	ALBEDO = c.rgb * COLOR.rgb;     // COLOR = Sprite3D.modulate (受击闪白 >1 提亮)
	ALPHA = c.a * fade * COLOR.a;
}
