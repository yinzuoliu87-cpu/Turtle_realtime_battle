// 圣光护盾·补盾那一下的【护盾合拢】—— 六边形能量板飞入落位
// 用户 2026-08-09:「改掉，不允许图片敷衍或简单圆特效」
//
// ★为什么是这个:
//   「获得护盾」的动作应该是**罩子在身上成型**。之前拿一张 9 帧光柱贴图从天上砸下来 ——
//   那是"天罚/审判"的语言, 方向是反的, 而且它把罩子本身糊住了(实拍为证)。
//   ⇒ 主角改成罩子的**合拢动作**: N 块能量板从罩外飞进来, 边旋转边缩到位, 逐块锁死。
//
// ★为什么不是"缩放 + 透明度":
//   判据是【内部形变必须真的发生】。这里每一块板子有**自己的位置、自己的旋转、自己的落位时刻**,
//   是 26 个独立运动的刚体, 不是一张图整体缩放 —— 这正是 093 光柱那一轮定下的商业级判据。
//
// ★几何: 板子是真的贴在球面上的六边形(顶点被投影回半径 radius 的球面),
//   所以落位后它们**严丝合缝地拼成罩子**, 透视/等距/前后遮挡全由引擎算 —— 不用我去凑。
//
// 数据通道(顶点色, 由 holy_shield_vfx.panel_mesh() 烘进去):
//   COLOR.r = 本块的延时(0~1, 大致从下往上装 + 一点错落)
//   COLOR.g = 0 表示板心, 1 表示板缘(六个角)
//   COLOR.b = 本块自转方向/幅度的种子
//   NORMAL  = 本块的**中心方向**(单位向量) —— 飞入轴、自转轴都是它
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3  tint : source_color = vec3(1.0, 0.85, 0.45);
uniform float build = 0.0;      // 装配总进度(0 → 1.3; 超过 1 是留给最后几块闪完)
uniform float fade = 1.0;       // 收尾(1 → 0), 装完之后板子退场, 把画面交还给罩子本体
uniform float radius = 1.55;    // 罩子半径(局部空间), 与 SphereMesh 一致
uniform float fly = 0.55;       // 出生时离罩面多远(× 半径)

// 单块板子从起飞到落位占总进度的多少。
// ★必须 < 1, 否则所有板子同时到位 —— 那就退化成"一张图整体缩放"了。
const float DUR = 0.42;
// 落位后的过亮持续(按总进度折算)
const float LOCK = 0.24;

varying float v_e;       // 本块的落位进度 0~1
varying float v_lock;    // 本块落位之后的秒表 0~1(0 = 刚锁上)
varying vec2  v_uv;

void vertex() {
	float delay = COLOR.r * (1.0 - DUR);
	float p = clamp((build - delay) / DUR, 0.0, 1.0);
	// 三次缓出: 冲进来快, 到位那一下"顿"住 —— 有重量感, 不是匀速滑进来
	float e = 1.0 - pow(1.0 - p, 3.0);
	v_e = e;
	v_lock = clamp((build - delay - DUR) / LOCK, 0.0, 1.0);
	v_uv = UV;

	vec3 cdir = normalize(NORMAL);
	vec3 c = cdir * radius;          // 本块在罩面上的落点
	vec3 off = VERTEX - c;           // 顶点相对板心的偏移(切平面内)

	// 绕自身法线自转: 飞进来时是歪的, 落位时正好摆正(罗德里格旋转)
	float ang = (1.0 - e) * 1.45 * (COLOR.b * 2.0 - 1.0);
	float ca = cos(ang);
	float sa = sin(ang);
	vec3 rot = off * ca + cross(cdir, off) * sa + cdir * dot(cdir, off) * (1.0 - ca);

	// 沿法线从罩外冲进来 + 板子本身由小长到满
	VERTEX = c * (1.0 + (1.0 - e) * fly) + rot * mix(0.30, 1.0, e);
}

// 正六边形的归一化距离场(0 = 板心, 1 = 六个角所在的那条边界)。
// ★用它而不是 length(uv) —— 后者画出来是**圆**, 那正是被点名不许再出现的东西。
float hexd(vec2 q) {
	return max(abs(q.x) * 0.8660254 + abs(q.y) * 0.5, abs(q.y)) / 0.8660254;
}

void fragment() {
	vec2 q = (v_uv - 0.5) * 2.0;
	float d = hexd(q);
	// ★★板子必须是**细线框**, 不是实心片。
	//   第一版写的是 `smoothstep(0.58, 0.99, d)` —— 从半径 58% 起就开始亮, 而六边形
	//   面积的七成都在 58% 之外 ⇒ 每块读成一个**实心白六边形**, 26 块拼起来是个
	//   不透明的足球, 把龟整只埋掉(2026-08-09 实拍)。⇒ 改成绕 d≈0.86 的一条窄带。
	float line = smoothstep(0.13, 0.0, abs(d - 0.87));
	// 内部只留极淡的一层"能量玻璃", 看得见里面的龟
	float fill = (1.0 - d) * 0.05;
	// 落位那一下过亮一记 —— "咔"地锁上。★只在**线框上**加亮, 不糊满整块。
	float flash = (1.0 - v_lock) * v_e;
	float a = (line * 0.80 + fill + flash * (line * 0.6 + 0.06)) * v_e * fade * 0.85;
	// ★★颜色乘数必须 ≤ 1.0。第二版写成 0.75+0.80*line ⇒ 峰值 1.55,
	//   金色 (1.00,0.85,0.45) ×1.55 被钳成 (1,1,0.70) —— **金子被钳成了白子**,
	//   实拍里整个罩子读成白色足球。亮度要靠 ALPHA 给, 不靠把颜色推爆。
	//   ☆flash 系数同理压到 0.40: 设 0.85 时峰值 1.85, 整批板子在收尾那几帧几乎同时锁死
	//   ⇒ 实拍里一整个壳白成一片, 金色身份没了。
	ALBEDO = tint * (0.55 + 0.45 * line + 0.40 * flash);
	ALPHA = clamp(a, 0.0, 1.0);
}
