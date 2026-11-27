// laser_fan.gdshader —— 010 激光长刃【扇形斩】(11-27 重做; 参考研究 docs/studies/20261127-参考-永恩斩击特效配方.md)
// 网格 = Cent3dVfx.gen_fan(UV.x 沿弧 0→1 = 扫的方向, UV.y 从圆心 0 → 外缘 1), 放在刃的高度、不做深度测试(刃扫过敌人身上)。
// 一层里叠四样(永恩 W: 最亮的刃只亮 0.1 秒 → 拖尾 0.2~0.4 秒):
//   领先刃: 一条从圆心到外缘的激光(扫到哪亮到哪, 越靠外越亮)
//   月牙拖尾: 外圈那一圈的余光, 落在刃后面按距离衰减
//   速度纹: 三道同心细弧, 衰减比拖尾慢 ⇒ 刃过去后还能看见扫过的轨迹
//   外缘亮线: 扇形最外一圈细亮边
// prog = 领先刃位置(0 → 1 扫完; 继续往上加 = 所有东西按「落后距离」自然衰减掉); fade = 收尾整体淡出。
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

uniform float prog = 0.0;
uniform float fade = 1.0;
uniform vec3 c_deep = vec3(0.50, 0.02, 0.07);
uniform vec3 c_red = vec3(1.0, 0.14, 0.20);
uniform vec3 c_pink = vec3(1.0, 0.58, 0.62);
uniform vec3 c_hot = vec3(1.0, 0.97, 0.93);

void fragment() {
	float u = UV.x;
	float k = UV.y;
	float behind = prog - u;
	float swept = step(0.0, behind);
	float b = max(behind, 0.0);
	float tip = 1.0 - smoothstep(0.975, 1.0, k);
	float blade = exp(-b * 60.0) * swept * (0.25 + 0.75 * smoothstep(0.05, 0.85, k)) * tip;
	float cres = smoothstep(0.40, 0.95, k) * tip;
	float trail = exp(-b * 6.0) * swept * cres;
	float streak = exp(-pow((k - 0.60) * 75.0, 2.0)) * 0.5
		+ exp(-pow((k - 0.77) * 95.0, 2.0)) * 0.8
		+ exp(-pow((k - 0.90) * 120.0, 2.0)) * 1.0;
	streak *= exp(-b * 2.6) * swept;
	float rim = exp(-pow((k - 0.975) * 130.0, 2.0)) * exp(-b * 2.0) * swept;
	float side = smoothstep(0.0, 0.03, u);          // 起刃那条直边别是一道硬线
	float I = (blade * 2.4 + trail * 0.85 + streak * 0.85 + rim * 1.3) * side;
	vec3 col = mix(c_deep, c_red, clamp(I * 1.5, 0.0, 1.0));
	col = mix(col, c_pink, clamp((I - 0.7) * 1.6, 0.0, 1.0));
	col = mix(col, c_hot, clamp((I - 1.35) * 1.3, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(I, 0.0, 1.0) * fade;
}
