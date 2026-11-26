def sub(p, pairs):
    raw = open(p, "rb").read(); nl = "\r\n" if b"\r\n" in raw else "\n"
    s = raw.decode("utf-8").replace("\r\n", "\n")
    for a, b in pairs:
        assert s.count(a) == 1, (p, a)
        s = s.replace(a, b)
    open(p, "wb").write(s.replace("\n", nl).encode("utf-8"))
sub("scripts/scenes/ShopScene.gd", [
 ('##   左沿接在左上页签之后(WEEK_X), 右沿离钱袋牌留 16; 图标原尺寸 32、最近邻。点一下 ⇒ 吐司报这 10 个的名字(手机上没有悬停)。\n',
  '##   左沿接在左上页签之后(WEEK_X), 右沿离钱袋牌留 16; 图标原尺寸 32、最近邻。\n'
  '##   纯展示、不可点: 木牌只有 64 高(上下没空间), 做成可点就违反手机可点区短边 ≥ 81(verify_shop_inv_phone ④); 名字在图鉴羁绊页(非本周压暗)。\n'),
 ('plq.name = "WeekSynPlaque"; plq.mouse_filter = Control.MOUSE_FILTER_STOP', 'plq.name = "WeekSynPlaque"'),
 ('\tvar names: String = "、".join(PackedStringArray(syns))\n\t_wire_tap(plq, func() -> void: _toast(Lang.t("本周商店只出这些羁绊的装备：%s") % names))\n', ''),
])
sub("locale/en.po", [('\nmsgid "本周商店只出这些羁绊的装备：%s"\nmsgstr "This week the shop only sells gear from: %s"\n', '')])
print("ok")
