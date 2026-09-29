class_name VfxGeom
extends RefCounted

## VfxGeom — 程序化贴地环几何的单一事实源 (2026-09-29 建)
##
## ══════════════════════════════════════════════════════════════════
##  【为什么要有】同一段几何曾在 8 个 `*_vfx.gd` 里各手写一份
## ══════════════════════════════════════════════════════════════════
## 逐字节比过(python 读字节, 不用 grep —— 本仓行尾是混的, grep 会把 CRLF 谎报成 LF):
##
##   · 顶点色三角形  `_tri`  —— **7 份**, 加 synergy_vfx 里改名成 `_tri3` 的第 8 份,
##                              8 份 body 去掉函数名后 **md5 完全相同**
##   · 贴地环顶点    `_flat` —— **3 份**, 加 food/shockwave/venom_drone 里改名成
##                              `_flat_vert` 的 3 份, 共 **6 份**, 同样 md5 相同
##   · 经向分段      RING_LON —— **5 份**(见下, 其中 1 份其实是另一个东西)
##
## ★改名会把副本藏起来: 按**函数名**找只有 7 份 `_tri`, 按 **body** 找是 8 份。
##   所以 `tools/dup_primitive_audit.py` 是按 body 哈希找的, 不是按名字。
##
## ══════════════════════════════════════════════════════════════════
##  【RING_LON 的 5 份里有 1 份不是副本 —— 没有合并它】
## ══════════════════════════════════════════════════════════════════
## 4 份是 48(arcane / food / potion / shockwave), 都是**贴地平环**的经向分段 ⇒ 并进来了。
## 第 5 份 `spirit_eq_vfx.gd` 是 **40**, 而它根本不是同一个量:
##   · 它与 `RING_TUBE := 8` 成对, 喂的是 `_build_torus` / `_build_torus_thin`
##     —— **三维环面**的经向分段(经向 × 管周向的网格), 不是平环
##   · spirit 自己的平环/平盘用的是函数内的 `n := 64` / `n := 48`, **从不读 RING_LON**
## ⇒ 取值不同是**故意的**, 合并会改变画面。只把它改名成 `RING_TORUS_LON` 留在原处,
##   让人一眼看出「这不是同一个东西」。(同理 relic_eq_vfx 那个算面法线的 `_tri`
##   —— 签名和 body 都不同, 是**同名不同物**, 已改名 `_tri_normal`。)
##
## ══════════════════════════════════════════════════════════════════
##  【谁在读】
## ══════════════════════════════════════════════════════════════════
## `VfxGeom.tri()`      : arcane / bow / food / potion / shockwave / spirit /
##                        synergy / venom_drone 共 8 个 `*_vfx.gd`
## `VfxGeom.flat()`     : 上面 8 个里做贴地环的 6 个, 各自留一行**绑定自己 GROUND_Y**
##                        的适配器(`_flat` / `_flat_vert`), 见下面 `flat()` 的注释
## `VfxGeom.RING_LON`   : arcane / food / potion / shockwave
##
## 【加新几何的规矩】只往这里加。往 `*_vfx.gd` 里再手写一份会被
## `tools/dup_primitive_audit.py` 当场扫出来(它按 body 哈希找, 改名躲不掉)。

## 贴地环的经向分段数。
## ★为什么是 48 而不是更省的 24: 环会被 scale 到很大的半径, 段数不够就**看得见多边形折线**
##   (shockwave_vfx 原注释:「贴地环的经向分段(要更密, 否则大半径时看得见多边形折线)」——
##    同文件的半球壳 `SHELL_LON` 只要 24, 因为壳不会被放这么大)。
const RING_LON := 48


## 顶点色三角形。`a`/`b`/`c` 各是 `[Vector3 位置, Color 顶点色]`。
## 配 `vertex_color_use_as_albedo = true` 的材质用 —— 顶点色当亮度与 alpha,
## 于是一张 mesh 就能画出"内沿渐隐 / 外沿硬边"而不需要贴图。
static func tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v in [a, b, c]:
		st.set_color(v[1])
		st.add_vertex(v[0])


## 贴地环的一个顶点: 极坐标 `(r, th)` 铺在 XZ 平面, 抬到 `gy` 高, 顶点色 alpha = `a`。
##
## ★★`gy` 必须由调用方传**自己的 `GROUND_Y`**, 不许在这里写死。
##   实测各件特效的离地高度**本来就不一样** —— 全仓 13 个 `GROUND_Y` 有 4 个取值:
##   0.03(axe_ember) / 0.055(potion) / 0.06(多数) / 0.07(blade, venom_drone)。
##   那是各自的美术选择(压在地砖上 vs 浮一点点), 不是漂移。
##   ⇒ 抽取时若顺手把 GROUND_Y 也搬进来, potion 的毒云会从 0.055 跳到 0.06 ——
##     **body 一模一样的 6 份函数, 语义并不相同**, 差别全在这个它们各自解析的常量上。
##     这也是为什么 6 个消费方各留一行适配器, 而不是直接改 53 个调用点。
static func flat(r: float, th: float, a: float, gy: float) -> Array:
	return [Vector3(r * cos(th), gy, r * sin(th)), Color(1, 1, 1, a)]
