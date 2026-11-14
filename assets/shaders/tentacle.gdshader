// 灵物触手 · 固定网格 + 顶点着色器沿样条弯曲 + 能量带着色(2026-10-31 重做, 方案书 docs/plans/20261031d-灵物触手重做.md §4 B)
//
// 用户 2026-10-31:「这东西在抽搐，而且一直闪光」「回放的时候还掉帧」「建议是直接大重做」→ 方向 B;
//   看了平涂成品「效果差，这是3d吗」, 看了圆管 + 环纹 + 吸盘「外形不行，太猎奇，根本不像lol」「你可以是紫色，但别搞猎奇」
//   ⇒ 外形照 LoL 俄洛伊触手实机(docs/plans/ref/20261031d-触手参考/LoL俄洛伊被动-出土与待机.jpg 第 3、4 格):
//   宽扁的能量带(截面在弯曲面内宽、侧向薄)、深色外缘 + 亮内侧、凸侧一排方齿棱鳍、根粗梢细梢端回卷、极淡的回纹母题;
//   颜色用灵物紫一族。识别靠剪影(棱鳍 + 锥度 + 回卷), 不靠肉质细节 —— 环纹 / 吸盘凸起 / 粉色腹面都去掉了。
// 不闪的纪律:
//   ① 网格开局建一次(TentacleMeshVfx.gen_tentacle_tube), 每帧只改 ctrl_pts / ctrl_r 等几个 uniform —— 旧做法每帧重建整根网格。
//   ② 不透明(没有自身叠层排序跳变) + 无贴图 + 不滚 UV —— 旧做法是双面半透明 + 最近邻流纹 + 每帧滚 UV。
//   ③ 棱鳍 / 回纹钉在沿长坐标上(物体空间, 不随时间动); 回纹在屏幕上密到几像素以下按 fwidth 自动淡出(否则移动时摩尔纹闪)。
//   ④ 外缘 / 亮内侧按视线与法线的夹角算(随形体走, 不随时间变); 只有命中那 2 帧提亮。
//
// 顶点数据约定(与 TentacleMeshVfx.gen_tentacle_tube 焊死):
//   UV2.x = 种类: 0 本体 / 1 描边外壳(反向绕序) / 2 根部地洞 / 3 地面拍痕
//   本体与外壳: UV.x = 沿长 u(0 根 … 1 梢), UV.y = 绕轴角 / TAU
//   地洞: UV = (半径 0..1, 角 / TAU)      拍痕: UV = (沿长 0..1, 横向 -1..1)
// 坐标: 节点放在根部(世界), ctrl_pts 是相对根部的局部坐标; 节点不旋转 ⇒ 局部方向 = 世界方向。
shader_type spatial;
// 2026-11-13 夜: depth_draw_never ⇒ 整根一个网格按身长顺序画, 后画的(往下那条腿 / 卷圈后半)总盖在先画的上面 ——
//   对折时在身后的那条腿反而看着在前面、或像塞在身子里(用户「第一二三四五针…是把头放到…要么放前面，要么放到里面去了」, 3D 里头其实在后面 0.6 米)。
//   改成写深度: 离镜头近的那段挡住后面的; 对背景仍是半透明灵体
render_mode unshaded, cull_back, shadows_disabled, blend_mix, depth_draw_always;

const int NCP = 32;
const float TAU_ = 6.28318530718;
const float PI_ = 3.14159265359;

// ── 每步会变的(节点 meta `stream_shader_params` 列的就是这几个) ──
uniform vec3 ctrl_pts[32];          // 中心线 32 点(相对根部), ctrl_pts[0] = 根部(地面) —— 8 月那版链式模拟的节点重采样
uniform vec3 ctrl_n[32];             // 每个控制点的背侧方向(背鳍那一侧; TentacleRig 沿身体平行传递, 2026-11-13 起 ⇒ 不再挂固定侧向 lat)
uniform float ctrl_r[32];            // 每个控制点处的管子半径(米, 8 月那版的半径式子 × TUBE_K)
uniform float arc_len = 9.6;         // 这一帧中心线的弧长(米; 出土时短), 棱鳍 / 回纹间距按它算
uniform vec3 fwd = vec3(1.0, 0.0, 0.0);   // 朝向(水平单位向量 = 拍击方向)
uniform vec3 lat = vec3(0.0, 0.0, 1.0);   // 侧向(水平单位向量, 垂直于拍击平面)
uniform float flash = 0.0;           // 命中闪 0..1(只在贴地那 2 帧为 1): 轮廓亮边 + 整体提亮, 不是整根换成白剪影
uniform float hole_r = 0.0;          // 根部那片地面的基准半径(米); 2026-11-13 起画成龟裂地(裂缝透紫光), 不再是黑洞
uniform float fin_open = 1.0;        // 棱鳍张开 0..1(出土时尖芽合拢, 到顶后才像花瓣一样张开; 2026-11-13 照 LoL 实机)
uniform float portal = 0.0;          // 出土漩涡 0..1(2026-11-13 照 LoL 实机: 落点先一个暗紫漩涡、边缘光丝绕圈, 再褪成黑影)
uniform float trail = 0.0;           // 地面拍痕 1→0(命中后停 0.3 秒再 0.35 秒退掉), 0 = 不画
uniform vec3 trail_fwd = vec3(1.0, 0.0, 0.0);  // 拍痕方向 = 贴地那一帧的拍击方向

// ── 不变的(建材质时设一次) ──
uniform float len_full = 9.6;        // 整根长度(米) = 攻击长度(拍痕长度)
uniform float outline_px = 1.0;      // 描边宽(屏幕像素, 与远近无关; 只要一圈细边, 粗了压扁体积)
uniform float fin_n = 9.0;           // 整根棱鳍齿数(越往梢越密; 2026-11-13: 只长在上半段 ⇒ 实际露出 5~6 片, 照 LoL 实机)
uniform float fin_h = 1.30;          // 棱鳍高度 = 该处半径 × 这个倍数(2026-11-13: 0.55 → 1.30, LoL 实机是向后的大锯齿)
uniform float band_w = 1.35;         // 截面: 弯曲面内(凸侧 / 凹侧方向)放宽的倍数 ⇒ 读成一条带子
uniform float band_t = 0.72;         // 截面: 侧向(垂直弯曲面)收薄的倍数
uniform float trail_w = 1.40;        // 拍痕半宽 = 根部那段管子半径 × 这个倍数 × 沿长渐细
// 灵物紫一族(synergy_vfx.gd 灵物配色 #b388ff): 外缘深紫 → 内侧亮淡紫 → 正对镜头那一片中紫; 根部偏深、梢部偏亮
uniform vec3 c_core : source_color = vec3(0.420, 0.270, 0.760);
uniform vec3 c_inner : source_color = vec3(0.800, 0.690, 1.0);
uniform vec3 c_edge : source_color = vec3(0.170, 0.080, 0.330);
uniform vec3 c_tip : source_color = vec3(0.700, 0.580, 1.0);
uniform vec3 c_glyph : source_color = vec3(0.880, 0.800, 1.0);
uniform vec3 c_spec : source_color = vec3(1.0, 0.960, 1.0);
uniform vec3 c_line : source_color = vec3(0.090, 0.035, 0.160);
uniform vec3 c_hole : source_color = vec3(0.040, 0.020, 0.070);
uniform vec3 c_dirt : source_color = vec3(0.230, 0.160, 0.290);
uniform vec3 c_flash : source_color = vec3(0.973, 0.949, 1.0);
uniform vec3 light_dir = vec3(-0.45, 0.80, 0.40);
// ── 2026-11-13 自己设计的外形(用户「自己设计一款外形呢…可以不用紫色」; 不照俄洛伊): style = 1 时启用 ──
//   背上一条连续的软薄膜(波浪起伏、波纹往梢端流) 取代锯齿棱鳍; 身体中间一条发光灵脉, 光点往梢端流; 梢端一颗发光灯珠;
//   根部是往外扩的发光水纹 取代龟裂地。配色由 TentacleMeshVfx.PALETTES 给(不再写死灵物紫)。
//   用户 10-31「太猎奇」⇒ 不做吸盘 / 环纹 / 肉质细节。
uniform float style = 0.0;
uniform float frill_h = 0.50;        // 薄膜高度 = 该处半径 × 这个倍数
uniform float frill_k = 5.0;         // 薄膜沿长的波数
uniform float frill_speed = 2.2;     // 波纹往梢端流的速度
uniform float lure = 1.0;            // 梢端灯珠大小(× 根部半径的一半)
uniform vec3 c_glow : source_color = vec3(0.70, 1.0, 0.95);   // 灵脉 / 光点 / 灯珠 / 水纹
uniform vec3 c_base : source_color = vec3(0.05, 0.12, 0.30);   // 根部底色(往梢端过渡到 c_core)
uniform vec3 c_outline : source_color = vec3(0.02, 0.05, 0.14); // 硬描边(游戏里像素美术都有深色描边)
uniform float dots = 0.0;            // 1 = 中线改成一串发光点(萤火鱿那种), 0 = 连续灵脉
uniform float rim_glow = 0.0;        // 受光边的霓虹亮边强度(深色身体那套用)

varying flat float v_kind;
varying vec3 v_n;
varying float v_fin;
varying float v_sig;
varying float v_m;
varying float v_phi;
varying float v_h;
varying vec2 v_uv;
varying vec2 v_disc;


// Catmull-Rom 中心线 + 切向。f = 沿长比例(0 根 … 1 梢)。
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


// 半径: 控制点半径沿长线性插值(8 月那版的半径分布, 由 CPU 每帧给)。
float rad_at(float f) {
	float s = clamp(f, 0.0, 1.0) * float(NCP - 1);
	int i = clamp(int(floor(s)), 0, NCP - 2);
	return mix(ctrl_r[i], ctrl_r[i + 1], s - float(i));
}


// 棱鳍 / 回纹的沿长坐标: 越往梢越密(与锥度同步变小)。
float sig_of(float m) {
	return fin_n * (1.0 - pow(max(1.0 - m, 0.0), 0.6));
}


void vertex() {
	v_kind = UV2.x;
	v_uv = UV;
	v_m = UV.x;
	v_sig = 0.0;
	v_fin = 0.0;
	v_phi = 0.0;
	v_h = 1.0;
	int kind = int(UV2.x + 0.5);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 p;
	vec3 n = up;
	if (kind <= 1) {
		float m = UV.x;
		vec3 c;
		vec3 tg;
		spline(m, c, tg);
		vec3 T = length(tg) > 0.0001 ? normalize(tg) : up;
		// 背侧 D(背鳍那一侧) = 控制点背侧插值后对切向正交化; 截面坐标系: -vn = D(棱鳍长在背侧), sd = vn × T
		float sn_i = clamp(m, 0.0, 1.0) * float(NCP - 1);
		int ni = clamp(int(floor(sn_i)), 0, NCP - 2);
		vec3 D = mix(ctrl_n[ni], ctrl_n[ni + 1], sn_i - float(ni));
		D = D - dot(D, T) * T;
		D = length(D) > 0.0001 ? normalize(D) : normalize(cross(T, lat) + vec3(0.0001, 0.0, 0.0));
		vec3 vn = -D;
		vec3 sd = cross(vn, T);
		float ph = UV.y * TAU_;
		float cs = cos(ph);
		float sn = sin(ph);
		float r = rad_at(m);
		// 扁椭圆截面: 竖着时弯曲面内宽(宽面朝镜头)、趴着时侧向宽(宽面朝上) ⇒ 从镜头看始终是一条带子, 不是圆筒;
		//   ★只按弯曲面定宽窄的第一版: 趴地后从上面只看得到窄边、整根是深色外缘, 读成另一根细管(2026-10-31 实拍)
		float kv = abs(T.y);
		float sx = mix(band_w, band_t, kv);
		float sy = mix(band_t, band_w, kv);
		vec3 off = cs * sd * sx + sn * vn * sy;
		vec3 nrm = normalize(cs * sd / sx + sn * vn / sy);
		// 棱鳍(2026-11-13 照 LoL 实机): 凸侧一排向后的三角大锯齿 —— 缓坡升起、陡边落下(陡边朝梢端), 只长在上半段
		//   (原来是全长一排城垛形方齿, 读成「一节节」)
		float sg = sig_of(m);
		float tw = fract(sg);
		float tooth = smoothstep(0.02, 0.70, tw) * (1.0 - smoothstep(0.74, 0.84, tw));
		float ridge = smoothstep(0.55, 0.92, -sn);
		float fin = fin_h * fin_open * tooth * ridge * smoothstep(0.32, 0.46, m) * (1.0 - smoothstep(0.93, 0.99, m));
		v_fin = tooth * ridge;
		if (style > 0.5) {
			// 连续软薄膜: 背侧一道脊, 高度沿长起伏、往梢端流; 同时左右轻轻摆(鳍在划水)
			float wave = sin((m * frill_k) * TAU_);   // 鳍高低起伏钉在身上, 不随时间流(11-13 去掉流动: 读成在抖)
			float ridge2 = smoothstep(0.30, 0.95, -sn);
			float env = smoothstep(0.16, 0.36, m) * (1.0 - smoothstep(0.84, 0.93, m));
			fin = frill_h * fin_open * ridge2 * env * (0.72 + 0.28 * wave);
			// (11-13 去掉: 鳍左右扇动 —— 用户「搁那疯狂抽动」; LoL 的鳍不扇)
			v_fin = ridge2 * env * fin_open;
			// 梢端灯珠: 在 0.90–0.99 处鼓起一颗球(半径取根部半径的一半 × lure), 最末收口
			// 尖芽合着时(fin_open 小)不鼓灯珠 —— 手标的尖芽梢端是尖的(11-13)
			float bump = smoothstep(0.885, 0.945, m) * (1.0 - smoothstep(0.972, 0.998, m)) * smoothstep(0.35, 0.85, fin_open);
			float rl = rad_at(0.12) * 0.5 * lure;
			r = mix(r, max(r, rl), bump);
			off = mix(off, cs * sd + sn * vn, bump);
		}
		p = c + off * r * (1.0 + fin);
		n = nrm;
		v_sig = sg;
		v_phi = ph;
		v_h = p.y;
		if (kind == 1) {
			vec4 vp = MODELVIEW_MATRIX * vec4(p, 1.0);
			// 一个屏幕像素在这个深度上是多少米。★取绝对值: 兼容渲染器(GLES3)渲染到帧缓冲时把投影 Y 翻转,
			//   PROJECTION_MATRIX[1][1] 是负的 ⇒ 不取绝对值描边会被往里推、整圈藏进身体(2026-10-31 染色实测)。
			float vh = VIEWPORT_SIZE.y > 1.0 ? VIEWPORT_SIZE.y : 720.0;
			float pxw = -vp.z * 2.0 / (abs(PROJECTION_MATRIX[1][1]) * vh);
			p += nrm * outline_px * pxw;
		}
	} else if (kind == 2) {
		// 根部那片地(2026-11-13): 龟裂地面放大到 hole_r × 3.2; 出土漩涡时用同一块
		float rr = UV.x * hole_r * 3.2;
		float th = UV.y * TAU_;
		// 世界轴(不用 fwd/lat): 触手转向时裂纹不跟着转
		v_disc = vec2(cos(th), sin(th)) * UV.x;
		p = ctrl_pts[0] + vec3(cos(th), 0.0, sin(th)) * rr + up * 0.025;
	} else {
		float a = UV.x;
		float w = max(ctrl_r[2] * trail_w * (1.0 - 0.75 * a), 0.12) * clamp(trail * 1.6, 0.0, 1.0);
		// 拍痕从远端往根部退(trail 1→0): 退掉的部分收到根部, 不出片元
		float reach = len_full * clamp(trail * 1.25, 0.0, 1.0);
		vec3 tl = vec3(-trail_fwd.z, 0.0, trail_fwd.x);
		p = trail_fwd * (a * reach) + tl * (UV.y * w) + up * 0.02;
		if (trail <= 0.0) {
			p = ctrl_pts[0] - up * 0.5;
		}
	}
	VERTEX = p;
	NORMAL = n;
	v_n = n;
}


float hash1(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}


vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}


// Voronoi 裂纹: 返回到最近两个格点距离之差(越小越靠近裂缝)。格点固定(不随时间动 = 不闪)。
float crack_d(vec2 q) {
	vec2 ip = floor(q);
	vec2 fp = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(ip + g);
			float d = length(g + o - fp);
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


void fragment() {
	int kind = int(v_kind + 0.5);
	vec3 col;
	float alpha = 1.0;
	if (kind == 1) {
		discard;
	} else if (kind == 2) {
		// 根部那片地(2026-11-13 照 LoL 实机): 龟裂地面, 裂缝里透暗紫光, 越往外越淡; 中心一团软黑影(触手从这里出来)。
		//   出土时(portal > 0): 同一块地上先是暗紫漩涡 —— 黑心 + 边缘洋红光丝绕圈转(TIME 驱动, 只在出土那 1 秒)。
		float rr = length(v_disc);
		float cd = crack_d(v_disc * 5.5 + vec2(3.1, 7.7));
		float seam = 1.0 - smoothstep(0.03, 0.09, cd);
		float glow = 1.0 - smoothstep(0.0, 0.035, cd);
		float fall = 1.0 - smoothstep(0.35, 1.0, rr);
		float shadow = (1.0 - smoothstep(0.0, 0.32, rr)) * 0.55;
		float ang = atan(v_disc.y, v_disc.x);
		float swirl = smoothstep(0.86, 1.0, sin(ang * 5.0 - rr * 11.0 + TIME * 5.0) * 0.5 + 0.5) * smoothstep(0.28, 0.50, rr) * (1.0 - smoothstep(0.62, 0.85, rr));
		col = mix(c_hole, c_edge, seam * 0.6);
		col = mix(col, c_inner, glow * 0.8);
		col = mix(col, vec3(0.95, 0.45, 1.0), swirl * portal);
		alpha = max(seam * fall * 0.75, shadow);
		alpha = max(alpha, portal * max((1.0 - smoothstep(0.0, 0.50, rr)) * 0.90, swirl * 0.75));
		if (style > 0.5) {
			// 底 = 倒沙漏(11-13 用户「它是由周围汇聚成这个身体」): 贴地一片从四周往根部汇聚的光 ——
			//   越靠根部越浓; 一道道细纹从外往里流(TIME 驱动, 慢); 出土时(portal)整片更大更亮。不再是一圈圈往外扩的水纹(我自己设计的)
			float ang2 = atan(v_disc.y, v_disc.x);
			float pool2 = pow(1.0 - smoothstep(0.0, 0.75, rr), 1.6);
			float streak = smoothstep(0.55, 1.0, sin(ang2 * 7.0 + rr * 3.0) * 0.5 + 0.5)
				* smoothstep(0.75, 1.0, sin((rr * 5.0 + TIME * 0.35) * TAU_) * 0.5 + 0.5)   // 11-13: 1.4 → 0.35(身子不动时画面还在闪, 用户「搁那抽动」)
				* smoothstep(0.12, 0.30, rr) * (1.0 - smoothstep(0.65, 0.95, rr));
			col = mix(c_core, c_inner, pool2 * 0.6);
			col = mix(col, c_glow, streak * 0.8);
			alpha = pool2 * (0.30 + 0.35 * portal) + streak * (0.12 + 0.25 * portal);
		}
		if (alpha < 0.01) {
			discard;
		}
	} else if (kind == 3) {
		// 拍痕: 中间一道紫色压痕 + 外圈深色(趴着时被身体盖住中间, 只露出深色边 = 贴地的痕)
		float b = abs(v_uv.y);
		// 2026-11-01 用户「打下去为什么是一片紫」: 原来是不透明深紫(两根交叉成一个 X) ⇒ 只留淡淡一道亮紫
		col = c_inner;
		alpha = 0.20 * (1.0 - smoothstep(0.35, 0.94, b));
		if (b > 0.94) {
			discard;
		}
	} else {
		vec3 N = normalize(v_n);
		vec3 Nv = normalize((VIEW_MATRIX * vec4(N, 0.0)).xyz);
		float nv = clamp(dot(Nv, VIEW), 0.0, 1.0);
		float f = 1.0 - nv;                      // 0 = 正对镜头, 1 = 轮廓边
		// ── 能量带: 正对镜头那一片中紫 → 往边上亮成淡紫(亮内侧) → 最外一圈压成深紫(深色外缘) ──
		vec3 col0 = mix(c_core, c_inner, smoothstep(0.30, 0.74, f));
		col0 = mix(col0, c_edge, smoothstep(0.84, 0.97, f));
		// 根部偏深、梢部偏亮
		col0 = mix(col0 * 0.80, mix(col0, c_tip, 0.25), smoothstep(0.0, 1.0, v_m));
		// 棱鳍: 比身体再亮一档(它是剪影的主角)
		col0 = mix(col0, c_inner, 0.35 * v_fin * (1.0 - smoothstep(0.84, 0.97, f)));
		// ── 回纹母题: 极淡的方形回字纹, 钉在沿长坐标 × 绕轴角上; 屏幕上一格不到 ~10 像素就淡掉 ──
		vec2 gc = vec2(v_sig * 2.0, v_phi / TAU_ * 6.0);
		vec2 gw = fwidth(gc);
		float gk = 1.0 - smoothstep(0.05, 0.10, max(gw.x, gw.y));
		vec2 cell = abs(fract(gc) - 0.5);
		float sq = max(cell.x, cell.y);
		float glyph = (smoothstep(0.30, 0.33, sq) - smoothstep(0.38, 0.41, sq)) + (1.0 - smoothstep(0.10, 0.13, sq));
		col0 = mix(col0, c_glyph, 0.10 * gk * glyph * (1.0 - smoothstep(0.80, 0.95, f)));
		// ── 体积: 柔和的半兰伯特明暗 + 根部贴地处暗一点 + 一层宽的湿亮光(随形体走) ──
		vec3 L = normalize(light_dir);
		float hl = dot(N, L) * 0.5 + 0.5;
		col = col0 * (0.72 + 0.38 * hl);
		col *= mix(0.62, 1.0, smoothstep(0.0, 1.2, v_h));
		vec3 Lv = normalize((VIEW_MATRIX * vec4(L, 0.0)).xyz);
		float sp = pow(max(dot(Nv, normalize(Lv + VIEW)), 0.0), 36.0);
		col += c_spec * smoothstep(0.10, 0.60, sp) * 0.28;
		// 命中: 轮廓一圈亮边 + 整体提亮(参考: 命中只闪 1~2 帧; 不是整根换成白剪影)
		col = col * (1.0 + 0.30 * flash) + c_flash * flash * (0.08 + 0.80 * f);
		// 灵体: 正对镜头那片透明、轮廓一圈亮且实(用户 11-01「透明那种灵体感觉」「紫色看起来太实体了」)
		col = mix(col, c_inner * 1.15, smoothstep(0.55, 0.95, f) * 0.85);
		alpha = mix(0.30, 0.95, smoothstep(0.15, 0.90, f));
		// 体内流动纹(2026-11-13 照 LoL 实机; 取代一节节的螺旋棱纹): 沿长缓慢往梢端流的淡亮纹, 幅度小、速度慢(不闪)
		float fq = v_m * 5.0 + v_phi / TAU_ * 0.6 - TIME * 0.22;
		float fk = 1.0 - smoothstep(0.15, 0.30, fwidth(fq));
		float flow = smoothstep(0.30, 0.50, abs(fract(fq) - 0.5)) * fk;
		col = mix(col, c_inner * 1.15, 0.18 * flow);
		// 下透上实(2026-11-13 照 LoL 实机: 下半身几乎只剩轮廓, 越往上越实, 卷钩最亮)
		alpha *= mix(0.30, 1.0, smoothstep(0.04, 0.55, v_m));
		alpha = max(alpha, 0.85 * v_fin);
		alpha = clamp(alpha + 0.35 * flash, 0.0, 1.0);
		if (style > 0.5) {
			// 身体(第三版): 沿长三段配色 根深靛 → 中段青 → 梢端亮; 明暗两档色块(对齐像素画); 外缘一道硬描边
			vec3 core_m = mix(c_base, c_core, smoothstep(0.05, 0.55, v_m));
			core_m = mix(core_m, c_inner, smoothstep(0.70, 0.98, v_m) * 0.55);
			float lit = smoothstep(0.50, 0.56, hl);
			vec3 b0 = core_m * mix(0.72, 1.08, lit);
			// 受光一侧往内光过渡(第二档亮色块)
			b0 = mix(b0, c_inner, smoothstep(0.42, 0.50, f) * 0.55 * (1.0 - smoothstep(0.80, 0.86, f)));
			b0 *= mix(0.80, 1.0, smoothstep(0.0, 1.2, v_h));
			// 灵脉: 正对镜头那条中线发光; 光点沿它往梢端流
			float far = smoothstep(0.004, 0.02, fwidth(v_m));
			float spine = smoothstep(mix(0.80, 0.50, far), mix(0.97, 0.88, far), nv) * (1.0 - smoothstep(0.90, 0.95, v_m));
			float pq = v_m * 6.0 - TIME * 0.3;   // 11-13: 1.6 → 0.3(光点一直往梢端跑 ⇒ 身子不动也像在抖)
			float pulse = pow(max(sin(pq * TAU_), 0.0), mix(10.0, 4.0, far)) * (1.0 - smoothstep(0.25, 0.45, fwidth(pq)));
			float dq = v_m * 16.0;
			float dot_ = (1.0 - smoothstep(0.18, 0.34, abs(fract(dq) - 0.5))) * (1.0 - smoothstep(0.35, 0.6, fwidth(dq)));
			float sp_line = mix(1.0, dot_ * 1.3, dots);
			b0 = mix(b0, c_glow, clamp(spine * sp_line * (0.55 + 0.45 * pulse), 0.0, 1.0));
			b0 += c_glow * spine * pulse * 0.35;
			// 霓虹亮边: 轮廓内侧一道亮青(深色身体靠它出形)
			b0 = mix(b0, c_inner * 1.1, rim_glow * smoothstep(0.62, 0.80, f) * (1.0 - smoothstep(0.84, 0.89, f)));
			// 薄膜: 比身体更透, 外沿一道亮边
			float memb = smoothstep(0.05, 0.6, v_fin);
			float rim = smoothstep(0.80, 0.98, v_fin);
			// 鳍条: 背膜上一道道从身体放射到外沿的细亮线(像鱼鳍), 屏幕上太密就淡掉
			float rq = v_m * frill_k * 5.0;
			float ray = (1.0 - smoothstep(0.06, 0.16, abs(fract(rq) - 0.5))) * (1.0 - smoothstep(0.3, 0.5, fwidth(rq)));
			b0 = mix(b0, mix(c_core, c_inner, 0.35), memb * 0.55);
			b0 = mix(b0, c_inner, memb * ray * 0.45);
			b0 = mix(b0, c_glow, rim * 0.85);
			// 灯珠: 梢端一颗亮球, 中心近白
			float lb = smoothstep(0.895, 0.93, v_m) * (1.0 - smoothstep(0.985, 1.0, v_m));
			b0 = mix(b0, mix(c_glow, vec3(1.0), 0.45 * smoothstep(0.3, 0.9, nv)), lb);
			// 高光: 一小块硬边亮斑(不是大片柔光)
			b0 = mix(b0, c_spec, smoothstep(0.30, 0.36, sp) * 0.55);
			// 硬描边: 轮廓最外一圈, 薄膜外沿除外(那里是亮边)
			// 出土合着的时候(fin_open 小)不要深色描边 + 顶上朝上那面提亮 —— 11-13 实拍: 顶上一道黑条像面罩, 读成一个头;
			//   LoL 出土时顶(折弯)是最亮的
			float ol = smoothstep(0.84, 0.90, f) * (1.0 - rim) * smoothstep(0.3, 0.9, fin_open);
			b0 = mix(b0, mix(c_inner, c_glow, 0.3), smoothstep(0.25, 0.85, N.y) * (1.0 - smoothstep(0.3, 0.9, fin_open)) * 0.75);
			b0 = mix(b0, c_outline, ol);
			b0 = b0 * (1.0 + 0.30 * flash) + c_flash * flash * (0.08 + 0.80 * f);
			col = b0;
			// 透明度: 根部透(灵体从地里升起) → 头部实; 描边比身体更实一些(透的那段也有轮廓)
			float head = smoothstep(0.35, 0.70, v_m);
			float a0 = mix(mix(0.30, 0.60, smoothstep(0.30, 0.80, f)), 0.92, head);
			a0 *= mix(0.45, 1.0, smoothstep(0.02, 0.30, v_m));
			a0 = max(a0, ol * mix(0.55, 0.95, smoothstep(0.02, 0.35, v_m)));
			a0 = max(a0, spine * 0.85 * mix(1.0, dot_, dots));
			a0 = max(a0, rim_glow * smoothstep(0.62, 0.80, f) * 0.9 * mix(0.5, 1.0, smoothstep(0.02, 0.3, v_m)));
			a0 = mix(a0, mix(0.35, 0.92, rim), memb * 0.85);
			a0 = max(a0, lb);
			alpha = clamp(a0 + 0.35 * flash, 0.0, 1.0);
		}
	}
	ALBEDO = col;
	ALPHA = alpha;
}
