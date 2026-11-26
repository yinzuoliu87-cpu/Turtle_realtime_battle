-- eternal_flame_tongue.lua —— 145 永恒之枪灼烧圈「圈边火舌」(招牌部分, CLAUDE.md §10 第 7 条②: 像人一样操作 Aseprite 一笔笔画)
-- 后台跑: Aseprite.exe -b --script tools/assetgen/ase/eternal_flame_tongue.lua
-- 画法(如实): 每一笔都是 Aseprite 自己的工具 —— contour(轮廓填充) 画剪影 / 平涂 / 亮部 / 高光, pencil(铅笔) 点火星细节,
--   最后 Edit > FX > Outline 描深色外边; 每帧的形状由下面的 sway(左右摆) / bob(上下窜) / lick(火舌舔边) 参数决定, 8 帧一个循环。
-- 产物: tools/assetgen/ase/eternal_flame_tongue.aseprite(源文件, 每步一个图层) + .out/ase/flame_step_*.png(第 0 帧每一步的过程图)
local OUT = app.params["out"] or "tools/assetgen/ase/"
local PROC = app.params["proc"] or ".out/ase/"
local W, H, N = 32, 48, 8
local spr = Sprite(W, H, ColorMode.RGB)
spr.filename = OUT .. "eternal_flame_tongue.aseprite"
for i = 2, N do spr:newEmptyFrame() end
for i = 1, N do spr.frames[i].duration = 1 / 12 end

local C = {
  out = Color{r=0x2a, g=0x08, b=0x02},
  red = Color{r=0x8a, g=0x22, b=0x08},
  org = Color{r=0xd8, g=0x5a, b=0x10},
  amb = Color{r=0xf0, g=0xa8, b=0x30},
  core = Color{r=0xff, g=0xe8, b=0x90},
  hot = Color{r=0xff, g=0xff, b=0xf0},
}

-- 火舌外形: 底宽、往上收尖, 上半截左右摆 + 舔边; s = 往底边中点收缩的比例(内层用)
local function tongue(f, s)
  local p = (f - 1) / N * 2 * math.pi
  local sway = 4.5 * math.sin(p)
  local bob = 3 * math.sin(p * 2 + 0.7)
  local Ht = (39 + bob) * s
  local bx, by = 16, 46
  local L, R = {}, {}
  local steps = 10
  for k = 0, steps do
    local t = k / steps
    local w = 10.5 * s * (1 - t) ^ 0.75 * (1 + 0.18 * math.sin(p * 2 + t * 7))
    local c = bx + sway * t ^ 1.6 + 1.6 * math.sin(p * 3 + t * 6) * t
    local y = by - t * Ht
    L[#L + 1] = Point(math.floor(c - w + 0.5), math.floor(y + 0.5))
    R[#R + 1] = Point(math.floor(c + w + 0.5), math.floor(y + 0.5))
  end
  local pts = {}
  for i = 1, #L do pts[#pts + 1] = L[i] end
  for i = #R - 1, 1, -1 do pts[#pts + 1] = R[i] end
  return pts
end

local function layer(name)
  local l = spr:newLayer()
  l.name = name
  return l
end

local steps = {
  {"1 剪影", C.red, 1.0},
  {"2 平涂", C.org, 0.78},
  {"3 亮部", C.amb, 0.55},
  {"4 高光", C.core, 0.32},
}
spr.layers[1].name = "0 底"
local n = 0
for _, st in ipairs(steps) do
  local lay = layer(st[1])
  for f = 1, N do
    app.useTool{ tool = "contour", color = st[2], points = tongue(f, st[3]), layer = lay, frame = spr.frames[f] }
  end
  n = n + 1
  spr:saveCopyAs(PROC .. string.format("flame_step_%d.png", n))
end

-- 5 细节: 火舌尖甩出去的火星(铅笔一点一点点, 每帧位置不同)
local det = layer("5 细节")
for f = 1, N do
  local p = (f - 1) / N * 2 * math.pi
  local x = math.floor(16 + 6 * math.sin(p + 1.2) + 0.5)
  local y = math.floor(6 - 3 * math.cos(p) + 0.5)
  app.useTool{ tool = "pencil", color = C.amb, points = { Point(x, y) }, layer = det, frame = spr.frames[f] }
  app.useTool{ tool = "pencil", color = C.hot, points = { Point(x, y - 1) }, layer = det, frame = spr.frames[f] }
  -- 底部最热的一小块白芯
  app.useTool{ tool = "pencil", color = C.hot, points = { Point(15, 44), Point(16, 44), Point(17, 44), Point(16, 43) }, layer = det, frame = spr.frames[f] }
end
n = n + 1
spr:saveCopyAs(PROC .. string.format("flame_step_%d.png", n))

-- 6 描边: 合并图层后用 Outline 描一圈深色外边
app.activeSprite = spr
app.command.FlattenLayers{ visibleOnly = false }
for f = 1, N do
  app.activeFrame = spr.frames[f]
  app.command.Outline{ ui = false, color = C.out, place = "outside", matrix = "circle", bgColor = Color{r=0, g=0, b=0, a=0} }
end
n = n + 1
spr:saveCopyAs(PROC .. string.format("flame_step_%d.png", n))
spr:saveAs(OUT .. "eternal_flame_tongue.aseprite")
print("ok " .. n .. " steps")
