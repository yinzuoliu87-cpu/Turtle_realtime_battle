class_name RingSheets
extends RefCounted
## 共享技能环 `_skill_ring` 的三档帧表(2026-11-05)。
## 由来: 11-05 审核片逐段审 —— 大范围技能(竹刺阵 / 糖衣炮弹 / 墨水炸弹 / 碎晶爆破 / 财宝风暴 / 万千触须 / 火炮齐射)
##   脚下的环边缘一格一格的台阶。环原来只有一张 64 像素帧表, 半径 300 码时 1 个贴图像素 ≈ 10 个屏幕像素,
##   比场上其它像素画(龟立绘约 2~3 屏幕像素一格)粗三四倍; 11-04 加的敌我描边用同一张图, 又把台阶描了一圈。
## 三档同一套几何(Blender 同一组渲帧, tools/assetgen/build_skill_ring_hi.py; 64 档由同一流水复刻、逐帧像素数一致),
##   只是格边长不同 ⇒ 末帧外径 / 格边长的比例三档相同, pixel_size 换算公式不变(分母乘同一个比例)。
## 仍是「pixel_size 恒定只切帧」: 一个环从生到灭只用一档, 不在档之间缩放。

const PATHS := {
	64: "res://assets/sprites/vfx/skill-ring-10f.png",
	128: "res://assets/sprites/vfx/skill-ring-10f-128.png",
	256: "res://assets/sprites/vfx/skill-ring-10f-256.png",
}
## 挑档: 1280 宽画面上 1 码 ≈ 1.2 屏幕像素(11-05 探针: 两个单位相距 99 码, 屏幕上差 121 像素)
##   ⇒ 环直径 ≈ 2.4×半径 像素; 想要一格 ≈ 2.5 屏幕像素(与龟立绘同一密度) ⇒ 格边长 ≈ 半径。
## 末帧外径(像素, 按格心 (cell-1)/2 量, 与 verify_skill_ring_curve 同一量法)。三档比例差 1% 以内(像素化取整),
##   但 300 码的环差 1% 就是 3 码 ⇒ 每档用自己的实测值换算, 不共用 64 档的 RING_LAST_R_PX。
const LAST_R_PX := {64: 31.09, 128: 61.78, 256: 123.28}
const R_FOR_128 := 96.0
const R_FOR_256 := 192.0

static var _cache: Dictionary = {}

static func cell_for(radius: float) -> int:
	if radius < R_FOR_128:
		return 64
	if radius < R_FOR_256:
		return 128
	return 256

## 这一档下, 画出 radius 码外径的环该用的 pixel_size(末帧外径 = radius)
static func pixel_size_for(radius: float, cell: int, ws: float) -> float:
	return (radius * ws) / float(LAST_R_PX[cell])

static func sheet(cell: int) -> Texture2D:
	if not _cache.has(cell):
		_cache[cell] = load(PATHS[cell])
	return _cache[cell]
