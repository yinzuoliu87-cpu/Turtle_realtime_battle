// 圣光护盾·球形能量罩 shader
// 用户 2026-08-09:「这是3D啊，是要罩子啊，设计个罩子啊」「位置，等距都考虑了吗，大小呢」
//
// ★为什么用真 3D 球 + shader 而不是一张公告板贴图:
//   罩子是**包住单位**的立体物。用 3D 球体, 透视/等距/前后遮挡**引擎自己就算对了** ——
//   不需要我去凑"看起来像个罩子"的二维形状(那正是之前那块平板盾读不出"罩"的原因)。
//   能量罩用菲涅尔(掠射角变亮)是行业标准做法, 不是程序化几何凑数。
//
// 三个可观测项(装备的三件事各占一个):
//   ① 罩子存在  —— 边缘菲涅尔亮环 + 六边形能量格, 常驻
//   ② 刚补上盾  —— `pop` 推一记整体过亮 + 格子扫过一遍
//   ③ 挨打反击  —— `hit_dir` 方向上一圈**涟漪**从命中点扩开(打哪儿亮哪儿)
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3  tint : source_color = vec3(1.0, 0.90, 0.55);
uniform float alpha = 0.55;          // 整体强度(由剩余护盾驱动)
uniform float pop = 0.0;             // 补盾那一下的过亮(0~1, 由代码衰减)
uniform float hit_t = 1.0;           // 涟漪进度(0=刚被打, 1=结束)
uniform vec3  hit_dir = vec3(0.0, 0.0, 1.0);   // 命中方向(单位向量, 模型空间)
uniform float t = 0.0;               // 时间(缓慢流动)

// ⚠ 只传**模型空间**的方向(给能量格和涟漪用)。菲涅尔**不能**用它 ——
//   `vertex()` 里的 NORMAL 是模型空间, 而 `fragment()` 里的 VIEW 是视图空间,
//   两个坐标系的向量点乘出来不是"边缘"而是**球的赤道带**; 赤道带在 52° 俯视下
//   投影成一个扁椭圆 ⇒ 罩子读成"地上一个圈"(2026-08-09 实拍确认, 用户:「位置、等距、大小完全错误」)。
//   ★球体的轮廓在任何角度都是正圆 —— 看到椭圆就说明算错了空间。
varying vec3 v_local;

void vertex() {
	v_local = normalize(VERTEX);
}

void fragment() {
	// ① 菲涅尔: 掠射角(边缘)亮, 正对镜头的部分几乎透明 ⇒ 读成一个"壳"而不是实心球
	// ★直接用 fragment 里的 NORMAL 与 VIEW —— 两者都在视图空间, 点乘才是真的菲涅尔
	float fres = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(clamp(fres, 0.0, 1.0), 2.2);

	// ② ✖已删: 这里原本有一层常驻的六边形能量格(hexgrid, scale 9)。
	//   实拍 + 染色法确认(2026-08-09): 屏幕上那个**足球**就是它 ——
	//   不是合拢的板子(板子染成品红后只占几百像素, 而那层网格是满的)。
	//   它是**常驻**的 ⇒ 罩子天天挂着一层足球纹, 还把补盾那一下的装配过程盖死。
	//   ⇒ 罩子只留"壳"(菲涅尔边缘) + 挨打的涟漪; **六边形是合拢那一下的语言**,
	//   只在装配时出现, 装完就收走 —— 两层各管各的, 不抢戏。

	// ③ 涟漪: 从命中方向那一点扩开的一圈亮带(打哪儿亮哪儿)
	float ang = acos(clamp(dot(normalize(v_local), normalize(hit_dir)), -1.0, 1.0));
	float wave = 0.0;
	if (hit_t < 1.0) {
		float r = hit_t * 2.6;                        // 涟漪半径(弧度)
		wave = smoothstep(0.42, 0.0, abs(ang - r)) * (1.0 - hit_t);
	}

	// ★★正对镜头的那一片必须**接近全透** —— 否则格子铺满整个球面, 把里面的单位糊暗。
	//   真实的能量罩就是"中间看得见里面、边缘一圈亮"。⇒ 格子也乘 rim, 只在边缘显现。
	float shell = rim * rim;                      // 更陡的菲涅尔 ⇒ 中间收得更干净
	float a = alpha * shell * 1.25 + wave * rim * 1.1 + pop * shell * 1.6;
	ALBEDO = tint * (0.85 + 0.85 * rim + wave);
	ALPHA = clamp(a, 0.0, 1.0);
}
