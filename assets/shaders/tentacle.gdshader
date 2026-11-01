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
render_mode unshaded, cull_back, shadows_disabled, blend_mix, depth_draw_never;

const int NCP = 32;
const float TAU_ = 6.28318530718;
const float PI_ = 3.14159265359;

// ── 每步会变的(节点 meta `stream_shader_params` 列的就是这几个) ──
uniform vec3 ctrl_pts[32];          // 中心线 32 点(相对根部), ctrl_pts[0] = 根部(地面) —— 8 月那版链式模拟的节点重采样
uniform float ctrl_r[32];            // 每个控制点处的管子半径(米, 8 月那版的半径式子 × TUBE_K)
uniform float arc_len = 9.6;         // 这一帧中心线的弧长(米; 出土时短), 棱鳍 / 回纹间距按它算
uniform vec3 fwd = vec3(1.0, 0.0, 0.0);   // 朝向(水平单位向量 = 拍击方向)
uniform vec3 lat = vec3(0.0, 0.0, 1.0);   // 侧向(水平单位向量, 垂直于拍击平面)
uniform float flash = 0.0;           // 命中闪 0..1(只在贴地那 2 帧为 1): 轮廓亮边 + 整体提亮, 不是整根换成白剪影
uniform float hole_r = 0.0;          // 根部地洞半径(米)
uniform float trail = 0.0;           // 地面拍痕 1→0(命中后停 0.3 秒再 0.35 秒退掉), 0 = 不画
uniform vec3 trail_fwd = vec3(1.0, 0.0, 0.0);  // 拍痕方向 = 贴地那一帧的拍击方向

// ── 不变的(建材质时设一次) ──
uniform float len_full = 9.6;        // 整根长度(米) = 攻击长度(拍痕长度)
uniform float outline_px = 1.0;      // 描边宽(屏幕像素, 与远近无关; 只要一圈细边, 粗了压扁体积)
uniform float fin_n = 11.0;          // 整根棱鳍齿数(越往梢越密, 与锥度同步变小)
uniform float fin_h = 0.55;          // 棱鳍高度 = 该处半径 × 这个倍数
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

varying flat float v_kind;
varying vec3 v_n;
varying float v_fin;
varying float v_sig;
varying float v_m;
varying float v_phi;
varying float v_h;
varying vec2 v_uv;


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
		vec3 sd = lat - dot(lat, T) * T;
		sd = length(sd) > 0.0001 ? normalize(sd) : normalize(cross(T, fwd) + vec3(0.0, 0.0, 0.0001));
		vec3 vn = cross(T, sd);                 // 凹侧(卷曲的内侧); -vn = 凸侧(背), 棱鳍长在这一侧
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
		// 方齿棱鳍: 凸侧正中一排城垛形齿(齿宽约 45%, 边缘略软免得锯齿闪), 根部与梢端那一截不长
		float sg = sig_of(m);
		float tw = fract(sg);
		float tooth = smoothstep(0.06, 0.14, tw) * (1.0 - smoothstep(0.50, 0.58, tw));
		float ridge = smoothstep(0.55, 0.92, -sn);
		float fin = fin_h * tooth * ridge * smoothstep(0.05, 0.12, m) * (1.0 - smoothstep(0.78, 0.92, m));
		p = c + off * r * (1.0 + fin);
		n = nrm;
		v_fin = tooth * ridge;
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
		float rr = UV.x * hole_r;
		float th = UV.y * TAU_;
		// 世界轴(不用 fwd/lat): 触手转向时洞口的锯齿边不跟着转
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


void fragment() {
	int kind = int(v_kind + 0.5);
	vec3 col;
	float alpha = 1.0;
	if (kind == 1) {
		discard;
	} else if (kind == 2) {
		// 地洞: 中心最黑, 往外渐亮成一圈碎土边(边的锯齿按角度固定取, 不随时间变)
		float seg = floor(v_uv.y * 20.0);
		if (v_uv.x > 0.97 - 0.10 * hash1(seg + 11.0)) {
			discard;
		}
		col = mix(c_hole, c_dirt, smoothstep(0.45, 0.92, v_uv.x));
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
		// 棱纹(用户 11-01「撸啊撸是光滑的吗」; 参考 LoL 俄洛伊触手「半透明青绿, 带棱纹」): 与棱鳍齿同一节距的螺旋亮纹, 纹上更实;
		//   绕一圈正好错一节(系数 1.0) ⇒ 接缝处连续; 屏幕上太密就淡掉(防闪)
		float rq = v_sig + v_phi / TAU_;
		float rk = 1.0 - smoothstep(0.15, 0.30, fwidth(rq));
		float rib = smoothstep(0.41, 0.48, abs(fract(rq) - 0.5)) * rk;
		col = mix(col, c_inner * 1.2, 0.35 * rib);
		alpha = mix(alpha, 0.80, 0.40 * rib);
		alpha = max(alpha, 0.85 * v_fin);
		alpha = clamp(alpha + 0.35 * flash, 0.0, 1.0);
	}
	ALBEDO = col;
	ALPHA = alpha;
}
