-- equip_cost_frame.lua —— 装备格按费用分稀有度的框(1 灰 / 2 绿 / 3 蓝 / 4 紫 / 5 金), 32×32, 游戏里 2 倍显示
-- 用户 11-27「上面九件装备…体现不出它的那个稀有度…这个框得想办法做呀。而且原本这个框太丑了」
-- 参考研究 docs/studies/20261127-参考-装备稀有度框与二级页顶栏.md: 框色 + 形状 + 数字三重标记(云顶), 高稀有度加底光(背包乱斗)。
-- 分层(逐层落笔, 每层存过程图): ① 底板 → ② 底光(4、5 费) → ③ 边框平涂 → ④ 斜面明暗 → ⑤ 角饰(4 费缺角, 5 费金角钉) → ⑥ 费用牌 + 数字 → ⑦ 描边
-- CLAUDE.md §10 第 7 条②: 后台驱动 Aseprite 逐像素画, 存 .aseprite + 导出 png。做法(如实): 逐像素按公式判层上色, 不用随机数, 重跑逐字节相同。
-- 后台跑: Aseprite.exe -b --script-param out=<目录> --script tools/assetgen/ase/equip_cost_frame.lua
local OUT = app.params["out"]
local rgba = app.pixelColor.rgba
local S = 32
local OUTLINE = rgba(59, 37, 49, 255)
-- 每费: 暗 / 本色 / 亮 / 高光(本色 = 局内 _equip_cost_color)
local RAMP = {
  {rgba(70, 78, 90, 255), rgba(138, 150, 163, 255), rgba(184, 194, 206, 255), rgba(228, 234, 240, 255)},
  {rgba(22, 110, 60, 255), rgba(74, 222, 128, 255), rgba(150, 240, 180, 255), rgba(222, 255, 232, 255)},
  {rgba(30, 80, 160, 255), rgba(96, 165, 250, 255), rgba(156, 204, 255, 255), rgba(226, 240, 255, 255)},
  {rgba(96, 48, 150, 255), rgba(192, 132, 252, 255), rgba(222, 184, 255, 255), rgba(246, 230, 255, 255)},
  {rgba(160, 96, 14, 255), rgba(251, 191, 36, 255), rgba(255, 222, 120, 255), rgba(255, 248, 210, 255)},
}
local BG = rgba(22, 28, 40, 255)
local BG2 = rgba(30, 38, 54, 255)
-- 3×5 像素数字
local DIG = {
  ["1"] = {"010", "110", "010", "010", "111"},
  ["2"] = {"110", "001", "010", "100", "111"},
  ["3"] = {"110", "001", "010", "001", "110"},
  ["4"] = {"101", "101", "111", "001", "001"},
  ["5"] = {"111", "100", "110", "001", "110"},
}

local function lerp(a, b, t) return math.floor(a + (b - a) * t + 0.5) end
local function mix(c1, c2, t)
  local P = app.pixelColor
  return rgba(lerp(P.rgbaR(c1), P.rgbaR(c2), t), lerp(P.rgbaG(c1), P.rgbaG(c2), t), lerp(P.rgbaB(c1), P.rgbaB(c2), t), 255)
end

for cost = 1, 5 do
  local R = RAMP[cost]
  local spr = Sprite(S, S, ColorMode.RGB)
  local names = {"底板", "底光", "边框平涂", "斜面明暗", "角饰", "费用牌", "描边"}
  spr.layers[1].name = names[1]
  for k = 2, #names do spr:newLayer().name = names[k] end
  local function inside(x, y) return x >= 0 and y >= 0 and x < S and y < S end
  -- 判定: e = 离外沿的距离; 外沿 0 = 描边, 1..3 = 边框, 4.. = 内区
  local function edge(x, y) return math.min(x, y, S - 1 - x, S - 1 - y) end
  -- 4 费缺角 / 5 费也缺角(角上另放金钉): 外沿四角各切掉一个 2 格三角
  local function cut(x, y)
    if cost < 4 then return false end
    local cx = math.min(x, S - 1 - x); local cy = math.min(y, S - 1 - y)
    return cx + cy < 2
  end
  local layers = {}
  for k = 1, #names do layers[k] = Image(S, S, ColorMode.RGB) end
  for y = 0, S - 1 do
    for x = 0, S - 1 do
      local e = edge(x, y)
      if not cut(x, y) then
        -- ① 底板: 内区上浅下深
        if e >= 1 then layers[1]:drawPixel(x, y, mix(BG2, BG, y / S)) end
        -- ② 底光: 4、5 费内区中间一团同色柔光(按离中心距离分 3 圈, 硬边)
        if cost >= 4 and e >= 4 then
          local d = math.sqrt((x + 0.5 - 16) ^ 2 + (y + 0.5 - 16) ^ 2)
          local c = nil
          if d < 7 then c = mix(BG, R[1], 0.42) elseif d < 10.5 then c = mix(BG, R[1], 0.2) end
          if c ~= nil then layers[2]:drawPixel(x, y, c) end
        end
        -- ③ 边框平涂: 离外沿 1..3
        if e >= 1 and e <= 3 then layers[3]:drawPixel(x, y, R[2]) end
        -- ④ 斜面: 外圈(1)左上亮右下暗, 内圈(3)反过来(凹进去的内沿)
        if e == 1 then
          local tl = (x <= y and x <= S - 1 - y) or (y <= x and y <= S - 1 - x)   -- 靠左边或上边
          layers[4]:drawPixel(x, y, tl and R[3] or R[1])
        elseif e == 3 then
          local tl = (x <= y and x <= S - 1 - y) or (y <= x and y <= S - 1 - x)
          layers[4]:drawPixel(x, y, tl and R[1] or R[3])
        end
        -- ⑦ 描边: 外沿 0 + 内沿 4 一圈深色
        local in_badge = x >= S - 9 and x <= S - 3 and y >= S - 11 and y <= S - 3   -- 费用牌那块不压(内沿描边原来正好穿过数字)
        if (e == 0 or e == 4) and not in_badge then layers[7]:drawPixel(x, y, OUTLINE) end
      elseif cut(x, y) then
        -- 切角处补描边(斜边)
        local cx = math.min(x, S - 1 - x); local cy = math.min(y, S - 1 - y)
        if cx + cy == 1 then layers[7]:drawPixel(x, y, OUTLINE) end
      end
    end
  end
  -- 外圈高光点: 左上角两颗
  layers[4]:drawPixel(3, 1, R[4]); layers[4]:drawPixel(1, 3, R[4])
  -- ⑤ 角饰: 5 费四角各一颗 3×3 金钉(白芯); 4 费四角各一颗 1 格亮点
  for _, c in ipairs({{2, 2}, {S - 3, 2}, {2, S - 3}, {S - 3, S - 3}}) do
    if cost == 5 then
      for dy = -1, 1 do for dx = -1, 1 do
        local col = (dx == 0 and dy == 0) and R[4] or ((dx + dy < 0) and R[3] or R[1])
        if math.abs(dx) + math.abs(dy) <= 1 then layers[5]:drawPixel(c[1] + dx, c[2] + dy, col) end
      end end
    elseif cost == 4 then
      layers[5]:drawPixel(c[1], c[2], R[4])
    end
  end
  -- 5 费上沿正中一颗菱形宝石(压在上边框上, 带描边): 7 宽 5 高
  if cost == 5 then
    local GEM = {"...o...", "..ohh..", ".ohhbo.", "..obd..", "...o..."}
    for r = 1, #GEM do for c = 1, 7 do
      local ch = GEM[r]:sub(c, c)
      local col = nil
      if ch == "o" then col = OUTLINE elseif ch == "h" then col = rgba(255, 255, 240, 255) elseif ch == "b" then col = rgba(255, 120, 60, 255) elseif ch == "d" then col = rgba(180, 50, 30, 255) end
      if col ~= nil then layers[5]:drawPixel(12 + c, r - 1, col) end
    end end
  end
  -- ⑥ 费用牌: 右下角 7×9 小牌(深底 + 费用色边 + 白数字)
  local bx0, by0 = S - 9, S - 11
  for y = by0, by0 + 8 do
    for x = bx0, bx0 + 6 do
      local edgeb = (x == bx0 or x == bx0 + 6 or y == by0 or y == by0 + 8)
      layers[6]:drawPixel(x, y, edgeb and R[2] or rgba(26, 18, 32, 255))   -- 深底 + 费用色边: 白数字反差够
    end
  end
  local g = DIG[tostring(cost)]
  for r = 1, 5 do
    for c = 1, 3 do
      if g[r]:sub(c, c) == "1" then layers[6]:drawPixel(bx0 + 1 + c, by0 + 1 + r, rgba(255, 255, 255, 255)) end
    end
  end
  -- 落笔: 每层一个 cel, 每落一层存一张过程图
  for k = 1, #names do
    spr:newCel(spr.layers[k], spr.frames[1], layers[k], Point(0, 0))
    local flat = Image(spr.spec)
    flat:drawSprite(spr, 1)
    flat:saveAs(OUT .. "/equip-frame-c" .. cost .. "-step" .. k .. ".png")
  end
  spr:saveAs(OUT .. "/equip_frame_c" .. cost .. ".aseprite")
  local final = Image(spr.spec)
  final:drawSprite(spr, 1)
  final:saveAs(OUT .. "/equip-frame-c" .. cost .. ".png")
  spr:close()
end
print("ok")
