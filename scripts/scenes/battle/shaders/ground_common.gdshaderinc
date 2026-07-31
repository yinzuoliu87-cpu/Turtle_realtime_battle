// 地面 shader 共用件: 世界坐标 / 地图距离场 / 4×4 Bayer 抖动。
// 2026-07-31 用户「想想怎么从外观上做成那种精美像素风吧」「你做一板大的吧」
//
// ★为什么要距离场: 岸线泡沫 / 水深渐变 / 湿沙带 —— 这些像素画里最出彩的东西,
//   本质上都需要同一个信息「这一点离水陆边界有多远」。烘一张 58×34 的场一次给全,
//   比为每样各打一个补丁干净得多。烘法见 scripts/scenes/battle/map_field.gd。
//
// ★为什么要抖动(dither): 像素画表现渐变【不靠平滑插值, 靠有序抖动】——
//   平滑渐变在低色数下会出条带(banding), 而抖动把误差散成规则点阵,
//   正是"精美像素风"里那种颗粒感的来源。这里所有梯度都过一遍 Bayer 再量化。

uniform sampler2D map_field : filter_linear, hint_default_black;  // R = 有符号距离(打包 0..1)
uniform vec2 map_org = vec2(0.0);      // 地图包围盒左上角(世界坐标·米)
uniform vec2 map_size = vec2(1.0);     // 地图包围盒尺寸(米)
uniform float field_r = 6.0;           // 距离场量程(格) —— 与 MapField.FIELD_R 对齐

// 世界坐标(米) —— 片元着色里 VERTEX 是视图空间, 反变换回世界。
// ★用世界坐标而不是 mesh 的 UV: UV 是【每格 0..1】, 会让每块砖各自成为一个独立印章
//   (2026-07-31 实拍确认: 整片水面就是同一个印章排成的方阵)。
// ★内置量(INV_VIEW_MATRIX / VERTEX / FRAGCOORD)只在 fragment() 里有效, include 的全局函数
//   拿不到 —— 必须由调用方传进来。(直接在这儿写 INV_VIEW_MATRIX 会编译错:
//   "Unknown identifier in expression"。)
vec2 world_xz(mat4 inv_view, vec3 v) {
	return (inv_view * vec4(v, 1.0)).xz;
}

// 到水陆边界的有符号距离(单位: 格)。>0 在水里(越大越深) · <0 在陆上 · ≈0 是岸线。
float shore_sdf(vec2 wp) {
	vec2 muv = (wp - map_org) / map_size;
	return (texture(map_field, muv).r - 0.5) * 2.0 * field_r;
}

// 4×4 有序抖动矩阵, 返回 0..1。按【屏幕像素】取值 —— 抖动点阵必须钉在屏幕上,
// 钉在世界上会随透视缩放糊掉, 就不是像素画的颗粒了。
float bayer4(vec2 frag) {
	int x = int(mod(frag.x, 4.0));
	int y = int(mod(frag.y, 4.0));
	int i = y * 4 + x;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
							3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

// 把 0..1 的梯度量化成 steps 级 + 抖动。这是"渐变读起来像像素画"的关键一步。
float dither_steps(float v, float steps, vec2 frag) {
	return floor(clamp(v, 0.0, 1.0) * steps + bayer4(frag)) / steps;
}
