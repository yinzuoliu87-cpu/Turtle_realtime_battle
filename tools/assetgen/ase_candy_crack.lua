-- tools/assetgen/ase_candy_crack.lua —— 糖果锤砸地留下的地面裂痕(2026-11-15)。
-- 跑法(无窗口):
--   Aseprite.exe -b --script-param out=<仓库>/assets/sprites/vfx/candy-crack.png \
--     --script-param src=<仓库>/assets/sprites/vfx/src/candy_crack.aseprite --script tools/assetgen/ase_candy_crack.lua
-- 做法(如实): 在 Aseprite 里用它自己的工具画 —— 实心椭圆 / 椭圆描边画坑口, 铅笔画裂缝与碎屑; 每一笔的点坐标是我定的(写在下面),
--   由脚本驱动 Aseprite 的画笔落笔(app.useTool), 不是鼠标手画。俯视画(贴地放), 画布 +X = 砸出去的方向, 锤头落点在 (40, 48)。
-- 参考: docs/studies/20261115-糖果锤参考-波比咖啡甜心Q逐帧.md 第 26~32 帧(砸完地面留下的焦糖渍 + 边上的焦糖纹)。

local W, H = 128, 96
local spr = Sprite(W, H, ColorMode.RGB)
local cel = spr.cels[1]

local DARK = Color{ r = 58, g = 30, b = 46, a = 235 }     -- 裂缝(深紫褐)
local DENT = Color{ r = 74, g = 44, b = 58, a = 120 }     -- 坑底(半透明, 压暗草地)
local RIM = Color{ r = 226, g = 182, b = 174, a = 210 }   -- 坑沿翻起的土(亮; 11-15 新地图暗色地面上原来那档看不见)
local EDGE = Color{ r = 246, g = 214, b = 200, a = 230 }  -- 裂缝受光的翻边(左上一格): 暗地面上靠它读出缝, 亮地面上靠深缝
local SYRUP = Color{ r = 255, g = 140, b = 186, a = 255 } -- 缝里的粉色糖浆光(11-15 提亮)
local CHIP = Color{ r = 96, g = 60, b = 74, a = 220 }     -- 碎屑

local function P(t) local out = {} for i = 1, #t, 2 do out[#out + 1] = Point(t[i], t[i + 1]) end return out end
local function stroke(col, size, pts) app.useTool{ tool = "pencil", color = col, brush = Brush(size), points = P(pts), cel = cel } end
local function ell(tool, col, x0, y0, x1, y1, size)
	app.useTool{ tool = tool, color = col, brush = Brush(size or 1), points = { Point(x0, y0), Point(x1, y1) }, cel = cel }
end

-- ① 坑: 压暗的坑底 + 一圈翻起的坑沿(前方被砸得更开, 所以椭圆往 +X 拉长)
ell("filled_ellipse", DENT, 22, 34, 62, 62)
ell("ellipse", RIM, 20, 32, 64, 64, 2)
ell("filled_ellipse", Color{ r = 46, g = 24, b = 38, a = 110 }, 30, 40, 52, 56)

-- ② 主裂缝: 从坑口往前(+X)三条长的、往两侧两条中的、往后一条短的; 锯齿折线, 根部粗(3)尖部细(1)
local cracks = {
	{ 3, { 58, 46, 66, 44, 72, 47, 80, 43 },              1, { 80, 43, 88, 45, 95, 40, 103, 42, 111, 38, 118, 40 } },
	{ 3, { 60, 52, 68, 55, 75, 53, 83, 58 },              1, { 83, 58, 91, 56, 98, 61, 106, 59, 113, 64, 121, 62 } },
	{ 2, { 56, 40, 62, 33, 69, 31, 74, 25 },              1, { 74, 25, 80, 22, 86, 16, 93, 14 } },
	{ 2, { 44, 34, 46, 26, 42, 19, 45, 12 },              1, { 45, 12, 43, 6 } },
	{ 2, { 42, 62, 45, 70, 41, 77, 44, 85 },              1, { 44, 85, 42, 91 } },
	{ 2, { 24, 47, 17, 45, 11, 49, 5, 47 },               1, {} },
	{ 2, { 57, 58, 63, 66, 61, 73, 67, 80 },              1, { 67, 80, 72, 87 } },
}
local function shifted(pts) local o = {} for i = 1, #pts, 2 do o[#o + 1] = pts[i] - 1; o[#o + 1] = pts[i + 1] - 1 end return o end
for _, c in ipairs(cracks) do
	stroke(EDGE, 1, shifted(c[2]))                 -- 先画受光翻边(往左上挪一格), 再压深缝 ⇒ 缝的左上沿留一道亮边
	if #c[4] > 0 then stroke(EDGE, 1, shifted(c[4])) end
	stroke(DARK, c[1], c[2])
	if #c[4] > 0 then stroke(DARK, c[3], c[4]) end
end
-- 分叉
for _, b in ipairs({ { 72, 47, 76, 52, 80, 54 }, { 95, 40, 98, 34, 102, 31 }, { 98, 61, 101, 67 }, { 69, 31, 66, 24 }, { 106, 59, 109, 53 } }) do
	stroke(DARK, 1, b)
end
-- ③ 缝里的糖浆光: 贴着主裂缝根部那一段, 偏下一像素(光从缝里透出来)
for _, s in ipairs({ { 60, 47, 66, 45, 72, 48, 80, 44 }, { 62, 53, 68, 56, 74, 54, 83, 58 }, { 57, 41, 62, 35, 68, 32 }, { 45, 33, 47, 27 }, { 43, 63, 45, 69 } }) do
	stroke(SYRUP, 1, s)
end
-- ④ 坑沿外的碎屑
for _, d in ipairs({ { 18, 30 }, { 66, 30 }, { 70, 64 }, { 15, 62 }, { 34, 70 }, { 52, 27 }, { 86, 50 }, { 27, 26 } }) do
	stroke(CHIP, 2, { d[1], d[2], d[1] + 1, d[2] })
end

if app.params["src"] then spr:saveCopyAs(app.params["src"]) end
spr:saveCopyAs(app.params["out"])
print("ok candy-crack")
